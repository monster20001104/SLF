#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : defines.py
#* 作者名称 : matao
#* 创建日期 : 2025/09/02
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   09/02       matao       初始化版本
#******************************************************************************/
import logging
from collections import Counter
from typing import List, NamedTuple, Union, Dict, Optional, Set, Tuple, Any
from scapy.all import Packet, BitField, PacketField, FlagsField
import random
from enum import Enum, auto
from dataclasses import dataclass
import copy

import cocotb
from cocotb.queue import Queue
from cocotb.log import SimLog
from cocotb.triggers import RisingEdge, Event, First, Timer
from backpressure_bus import define_backpressure
from stream_bus import define_stream

import sys
sys.path.append('../common')
from bus.tlp_adap_bypass_bus import TlpBypassBus, OpCode, ComplStatus, TlpBypassReq, TlpBypassRsp, TlpBypassReq2CfgTlp, Tlp2TlpBypassCpl,Header

EventReqBus, EventReqTransaction, EventReqSource, EventReqSink, EventReqMonitor = define_stream("event_master",
    signals=["data"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)    

DoorBellRspBus, DoorBellRspTransaction, DoorBellRspSource, DoorBellRspSink, DoorBellRspMonitor = define_stream("DoorBellRsp",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)

class TlpReq(NamedTuple):
    hdr: TlpBypassReq
    host_gen: bytearray

class OpType(Enum):
    ADD_PF = auto()
    ADD_VF = auto()
    DEL_PF = auto()
    DEL_VF = auto()
    EQUAL  = auto()

@dataclass
class Op:
    type: OpType
    pf_id: int = None
    vf_id: Optional[int] = None  # 仅VF操作需要
    stride: int = 0  # 仅ADD_PF需要
    vid_len: int = 1  # 仅ADD_VF需要

class VF:
    def __init__(self, vf_id: int, pf_id: int, vid_len: int, stride: int):
        self.log = SimLog("cocotb.tb.vf")
        if not (1 <= vid_len <= 512):
            raise ValueError(f"The vid_len must be between 1-256, which is actually{vid_len}")
        
        self.vf_id = vf_id
        self.pf_id = pf_id
        self.vid_len = vid_len
        self.stride = stride
        self.addr_offsets = {}

        for vid in range(vid_len):
            self.addr_offsets[vid] = self._calc_offset(vid)

    def _calc_offset(self, vid: int) -> int:
        return (self.vf_id << (10 + self.stride)) | (vid << 2)

    def __repr__(self) -> str:
        return f"VF(vf_id={self.vf_id}, pf_id={self.pf_id}, vid_len= {self.vid_len}, stride={self.stride})"


class PF:
    def __init__(self, pf_id: int, stride: int, start_addr: int, end_addr: int):
        self.log = SimLog("cocotb.tb.pf")
        if not (0 <= pf_id <= 15):
            raise ValueError(f"The PF number must be between 0-15, which is actually{pf_id}")
        
        self.pf_id = pf_id
        self.stride = stride
        self.start_addr = start_addr
        self.end_addr = end_addr
        self.vfs: Dict[int, VF] = {}
        self.vfnum = 0

    def add_vf(self, vf_id: int, vid_len: int) -> Optional[VF]:
        if len(self.vfs) > 32:
            self.log.warning(f"PF {self.pf_id}maximum VF quantity has been reached 32")
            return None
        
        if vf_id in self.vfs:
            self.log.warning(f"VF {vf_id} already exists in PF {self.pf_id}")
            return None
        
        try:
            vf = VF(vf_id, self.pf_id, vid_len, self.stride)
        except ValueError as e:
            self.log.error(f"PF {self.pf_id}, Creating VF {vf_id} failed:{e}")
            return None
        
        for vid, offset in vf.addr_offsets.items():
            if self.start_addr + offset > self.end_addr:
                self.log.error(f"The vid {vid} address of VF {vf_id} exceeds the range of PF {self. pf_id}")
                return None
        
        self.vfs[vf_id] = vf
        self.vfnum += 1
        self.log.debug(f"PF {self.pf_id} successfully added {vf}") 
        return vf

    def del_vf(self, vf_id: int) -> bool:
        if len(self.vfs) <= 1:
            self.log.error(f"PF {self.pf_id}At least 1 VF must be retained, VF cannot be deleted {vf_id}")
            return False
        
        if vf_id in self.vfs:
            del self.vfs[vf_id]
            self.vfnum -= 1
            return True
        return False

    def get_vf_addr(self, vf_id: int, vid: int) -> Optional[int]:
        vf = self.vfs.get(vf_id)
        if vf and vid in vf.addr_offsets:
            return self.start_addr + vf.addr_offsets[vid]
        return None
    
    def __repr__(self) -> str:
        return f"PF(pf_id={self.pf_id}, vf_count={len(self.vfs)}, stride={self.stride})"

class PFVFManager:
    _TABLES_TEMPLATE = {
        "index_table": {},   # 键: (pf_id, vf_id)，值: (entry) —— 一个VF对应一条index记录
        "gqid_table": [],    # list,(pf_id, vf_id, gqid, high_bit)
        "strides": {},       # 键: pf_id，值: (stride) —— 一个PF对应一条stride记录
        "vf_num": {},        # 键: pf_id，值: (vfnum) —— 一个PF对应一条vf_num记录
        "start_end_addr": {} # 键: pf_id，值: List[(start, end)] —— 一个PF对应两条start/end记录
    }
    def __init__(self):
        self.log = SimLog("cocotb.tb.pvm")
        self.pfs: Dict[int, PF] = {}
        self.current_group_flag = 0 # 当前组标志（0/1）
        self.select_group_flag = 1 - self.current_group_flag  #用于选择组标志（0/1）
        self.all_tables_list = {k: v.copy() for k, v in self._TABLES_TEMPLATE.items()}#目前dut寄存器所有有效信息
        self.all_tables_list_tmp = {k: v.copy() for k, v in self._TABLES_TEMPLATE.items()}#增删过程中dut寄存器所有临时有效信息
        self.vf_to_gqid_indices = {}
        self.vf_to_gqid_indices_tmp = {}
        self.wr_reg_busy = True

        self.all_possible_addresses: List[Tuple[int, int, int, int]] = []  # (pf_id, vf_id, vid, address)
        self.all_possible_addresses_tmp: List[Tuple[int, int, int, int]] = []  # (pf_id, vf_id, vid, address)
        self.illegal_addresses: List[int] = []
        self.all_addr_range = 0x3E00FFF#在16个PF的地址区间内，缩小范围
        self.add_flag = False
        self.del_pf_flag = False
        self.del_vf_flag = False
        self.gen_equal_flag = False
        self.pf_addr_ranges = {}
        # 寄存器基地址
        self.REG_GROUP_SEL = 0x000000
        self.REG_PF_BASE = 0x200000
        self.REG_TABLE_BASE_GROUP0 = (0x100000, 0x140000)
        self.REG_TABLE_BASE_GROUP1 = (0x120000, 0x160000)
        # 硬件限制
        self.MAX_PF = 16          # 最大PF数量（0-15）
        self.MAX_VF_PER_PF = 32   # 每个PF最大VF数量
        self.MAX_GQID_ENTRIES = 1024  # gqid_table最大条目数
    
        # 地址计算常量
        self.BASE_BLOCK = 0x10000  # 64KB基础块
        self.MAX_BLOCK_SHIFT = 6   # 最大块移位（64KB <<6 = 4MB）
        self.MAX_ADDR = (1 << 63) - 1

    def _gen_pf_addr_range(self, pf_id: int, stride: int) -> Tuple[int, int]:
        '''
        Calculate the address space required for a single VF: 512 VID x 4 bytes (determined by vid<<2)
        Each VF requires 512 × 4=1024 bytes=2KB
        32 VFs require 32 × 2KB=64KB, which is the minimum requirement
        Basic address block size: 64KB (0x10000), ensuring that it can accommodate 32 VFs and 512 VIDs
        
        block_size = self.BASE_BLOCK << stride  # 64KB × 2^stride
        max_block_size = self.BASE_BLOCK << self.MAX_BLOCK_SHIFT
    
        base = pf_id * max_block_size + 0x1000
        end = base + block_size - 1
        '''
        block_size = self.BASE_BLOCK << stride  # 64KB × 2^stride
        max_block_size = self.BASE_BLOCK << self.MAX_BLOCK_SHIFT

        start_total = 16
        end_total = (1 << 64) - 1
        total_length = end_total - start_total + 1
        big_chunk_size = total_length // self.MAX_PF

        big_start = start_total + pf_id * big_chunk_size
        if pf_id == self.MAX_PF - 1:
            big_end = end_total
        else:
            big_end = big_start + big_chunk_size - 1

        num_small_chunks = (big_end - big_start + 1) // max_block_size
        k = random.randint(0, num_small_chunks - 1)
        base = big_start + k * max_block_size
        end = base + block_size - 1
        if end > big_end:
            end = big_end
        return (base, end)

    def _gen_start_end_reg(self, pf_id: int, start_addr: int, end_addr: int) -> List[Tuple[int, int]]:
        return [
            (self.REG_PF_BASE + pf_id * 0x400 + 0x00, start_addr),  # start寄存器
            (self.REG_PF_BASE + pf_id * 0x400 + 0x08, end_addr)     # end寄存器
        ]

    def _gen_stride_reg(self, pf_id: int, stride: int) -> Tuple[int, int]:
        return (self.REG_PF_BASE + pf_id * 0x400 + 0x18, stride)

    def _gen_vfnum_reg(self, pf_id: int, vf_num: int) -> Tuple[int, int]:
        return (self.REG_PF_BASE + pf_id * 0x400 + 0x20, vf_num)

    def _get_table_base_addr(self) -> Tuple[int, int]:
        if self.select_group_flag == 0:
            return self.REG_TABLE_BASE_GROUP0  # index基地址, gqid基地址
        else:
            return self.REG_TABLE_BASE_GROUP1

    def _gen_index_reg(self, pf_id: int, vf_id: int, entry: int) -> Tuple[int, int]:
        table_idx_addr, _ = self._get_table_base_addr()
        addr = table_idx_addr + (pf_id * self.MAX_VF_PER_PF + vf_id) * 0x8
        return (addr, entry)

    def _gen_gqid_regs(self, gqid_table: List[Tuple[int, int, int, int]]) -> List[Tuple[int, int]]:
        _, table_gqid_addr = self._get_table_base_addr()
        regs = []
        for tbl_idx, (pf_id, vf_id, gqid, high_bit) in enumerate(gqid_table):
            addr = table_gqid_addr + tbl_idx * 0x8
            regs.append((addr, gqid))
        return regs

    def _update_illegal_addresses(self):
        original_addr_set = {addr for (pf_id, vf_id, vid, addr) in self.all_possible_addresses_tmp}
        self.illegal_addresses.clear()
        for addr_tuple in self.all_possible_addresses_tmp:
            _, _, _, original_addr = addr_tuple
            for i in range(1):
                new_addr = original_addr + ((i+1)*4)
                if new_addr not in original_addr_set:
                    self.illegal_addresses.append(new_addr)

    def add_pf(self, pf_id: int, stride: int = 0) -> Optional[PF]:
        if pf_id in self.pfs:
            self.log.warning(f"PVM add_pf : PF {pf_id} already exists")
            return None
        try:
            start_addr, end_addr = self._gen_pf_addr_range(pf_id, stride)
            pf = PF(pf_id, stride, start_addr, end_addr)
        except ValueError as e:
            self.log.error(f"PVM add_pf : failed to create PF: {e}")
            return None

        self.all_tables_list_tmp["start_end_addr"][pf_id] = (start_addr, end_addr)
        self.all_tables_list_tmp["strides"][pf_id] = (stride)
        self.pfs[pf_id] = pf
        self.log.debug(f"PVM add_pf : PF {pf_id} with stride {stride}, address range [0x{start_addr:x}, 0x{end_addr:x}]")
        return pf

    def add_vf_to_pf(self, pf_id: int, vf_id: int, vid_len: int) -> Optional[VF]:
        pf = self.pfs.get(pf_id)
        if not pf:
            self.log.warning(f"PVM add_vf_to_pf : PF {pf_id} does not exist")
            return None
        if vf_id in pf.vfs:
            self.log.warning(f"PVM addadd_vf_to_pf_pf : VF {vf_id} already exists in PF {pf_id}")
            return None
        
        current_total = len(self.all_tables_list_tmp["gqid_table"])
        if current_total + vid_len > self.MAX_GQID_ENTRIES:
            self.log.warning(f"PVM addadd_vf_to_pf_pf : Cannot add PF:{pf_id},VF {vf_id}: gqid_table full (max 512 entries), current_total is {current_total}, vid_len is {vid_len}")
            if len(pf.vfs) <= 0:
                del self.all_tables_list_tmp["strides"][pf_id]
                self.all_tables_list_tmp["start_end_addr"][pf_id] = (0, 0)
                del self.pfs[pf_id]
            return None
        existing_vf_ids = list(pf.vfs.keys())
        if existing_vf_ids:
            existing_vf_ids_sorted = sorted(existing_vf_ids)
            target_vf_id = existing_vf_ids_sorted[-1] + 1
        else:
            target_vf_id = 0
        if vf_id != target_vf_id:
            self.log.warning(
            f"PVM add_vf_to_pf: Incoming VF ID {vf_id} is not continuous. "
            f"Current max VF ID of PF {pf_id} is {existing_vf_ids_sorted[-1] if existing_vf_ids else 'none'}, "
            f"force use target VF ID {target_vf_id}"
        )
            vf_id = target_vf_id 

        vf = pf.add_vf(vf_id, vid_len)
        if vf:
            start_index = current_total
            for _ in range(vid_len):
                high_bit = random.randint(0, 1)
                low_bits = random.randint(1, 0xFFFF)
                gqid = (high_bit << 31) | (low_bits & 0xFFFF)
                self.all_tables_list_tmp["gqid_table"].append((pf_id, vf_id, gqid, high_bit))
            
            entry = (start_index << 10) | (vid_len & 0x3FF)
            key = (pf_id, vf_id)  # 以(pf_id, vf_id)为键
            self.all_tables_list_tmp["index_table"][key] = (entry)
            self.all_tables_list_tmp["vf_num"][pf_id] = (pf.vfnum)  # 以pf_id为键
            self.vf_to_gqid_indices_tmp[(pf_id, vf_id)] = list(range(start_index, start_index + vid_len))
            new_addresses = []
            for vid in range(vid_len):
                addr = pf.get_vf_addr(vf_id, vid)
                if addr is not None:
                    new_addresses.append((pf_id, vf_id, vid, addr))
            original_addresses = self.all_possible_addresses_tmp.copy()
            self.all_possible_addresses_tmp = original_addresses + new_addresses
            self.log.debug(f"PVM add_vf_to_pf_pf : added VF {vf_id} to PF {pf_id} with {vid_len} VIDs:")
            self.log.debug(f"PVM add_vf_to_pf_pf : start index in gqid_table: {start_index}")
            self.add_flag = True
            return vf
        return None

    def del_pf(self, pf_id: int) -> bool:
        if pf_id not in self.pfs:
            self.log.warning(f"PVM del_pf : PF {pf_id} does not exist")
            return True
        
        pf = self.pfs[pf_id]
        self.all_possible_addresses_tmp = [(p, v, vid, addr) for (p, v, vid, addr) in self.all_possible_addresses_tmp if p != pf_id]
        
        if pf_id in self.all_tables_list_tmp["strides"]:
            del self.all_tables_list_tmp["strides"][pf_id]
            self.log.debug(f"PVM del_pf :Delete strips entry for PF {pf_id}")
        
        if pf_id in self.all_tables_list_tmp["start_end_addr"]:
            self.all_tables_list_tmp["start_end_addr"][pf_id] = (0, 0) #keep addr,data=0,Write register to overwrite old values
            self.log.debug(f"PVM del_pf :The start_end_addr of PF {pf_id} has been set to zero")
        
        index_keys_to_del = [
            (p, v) for (p, v) in self.all_tables_list_tmp["index_table"].keys()
            if p == pf_id
        ]
        for key in index_keys_to_del:
            del self.all_tables_list_tmp["index_table"][key]
        self.log.debug(f"PVM del_pf :Delete {len (index_keys_to_del)} index table entries from PF {pf_id}")
        
        pf_vf_keys = [key for key in self.vf_to_gqid_indices_tmp.keys() if key[0] == pf_id]
        all_indices = []
        for key in pf_vf_keys:
            all_indices.extend(self.vf_to_gqid_indices_tmp[key])
        for idx in all_indices:
            self.all_tables_list_tmp["gqid_table"][idx] = (0, 0, 0, 0)
        for key in pf_vf_keys:
            del self.vf_to_gqid_indices_tmp[key]
        self.log.debug(f"PVM del_pf :The entry of PF {pf_id} in gqid_table has been set to zero")

        if pf_id in self.all_tables_list_tmp["vf_num"]:
            del self.all_tables_list_tmp["vf_num"][pf_id]
            self.log.debug(f"PVM del_pf :Delete vf_num entry for PF {pf_id}")
        
        del self.pfs[pf_id]
        self.del_pf_flag = True
        self.log.debug(f"PVM del_pf :Successfully deleted PF {pf_id}")
        return True

    def del_vf_from_pf(self, pf_id: int, vf_id: int) -> bool:
        pf = self.pfs.get(pf_id)
        if not pf:
            self.log.warning(f"PVM del_vf_from_pf :PF {pf_id} does not exist")
            return False
        
        vf = pf.vfs.get(vf_id)
        if not vf:
            self.log.warning(f"PVM del_vf_from_pf :VF {vf_id} in PF {pf_id} does not exist")
            return False
        
        success = pf.del_vf(vf_id)
        if not success:
            self.log.warning(f"PVM del_vf_from_pf :VF {vf_id} in PF {pf_id} pf.del_vf failed")
            return False

        self.all_possible_addresses_tmp = [
        (p, v, vid, addr) for (p, v, vid, addr) in self.all_possible_addresses_tmp
        if not (p == pf_id and v == vf_id)]
        
        index_key = (pf_id, vf_id)
        if index_key in self.all_tables_list_tmp["index_table"]:
            self.all_tables_list_tmp["index_table"][index_key] = (0)
            self.log.debug(f"PVM del_vf_from_pf :Delete the index table entry for VF {vf_id} in PF {pf_id}")
        else:
            self.log.warning(f"PVM del_vf_from_pf :No index table entry found for VF {vf_id} in PF {pf_id}")
            return False

        indices = self.vf_to_gqid_indices_tmp.get((pf_id, vf_id), [])
        for idx in indices:
            self.all_tables_list_tmp["gqid_table"][idx] = (0, 0, 0, 0)
        del self.vf_to_gqid_indices_tmp[(pf_id, vf_id)]
        self.log.debug(f"PVM del_vf_from_pf :VF {vf_id} in PF {pf_id} has been set to zero in the gqid_table entry")
        
        if pf_id in self.all_tables_list_tmp["vf_num"]:
            self.all_tables_list_tmp["vf_num"][pf_id] = (pf.vfnum)
            self.log.debug(f"PVM del_vf_from_pf :Update the vf_num of PF {pf_id} to {pf. vfnum}")

        self.del_vf_flag = True
        return True

    def gen_equal_tbl(self) -> Optional[bool]:
        gqid_list = self.all_tables_list_tmp.get("gqid_table", [])
        if not gqid_list:
            self.log.warning("PVM gen_equal_tbl :The input gqid list is empty")
            return True
        
        filtered_gqid = [
            entry for entry in gqid_list
            if not (entry[0] == 0 and entry[1] == 0 and entry[2] == 0 and entry[3] == 0)]
        removed_count = len(gqid_list) - len(filtered_gqid)
        groups: Dict[Tuple[int, int], List[Tuple[int, int, int, int]]] = {}
        for entry in filtered_gqid:
            key = (entry[0], entry[1])
            if key not in groups:
                groups[key] = []
            groups[key].append(entry)
        if removed_count > 0:
            self.log.debug(f"PVM gen_equal_tbl :Removed all 0 rows of {removed_count} and updated them directly using the filtered list")
            group_keys = list(groups.keys())
        else:#No all 0 rows (need to shuffle grouping)
            self.log.debug("PVM gen_equal_tbl :Without all 0 rows, group by (pf, vf) and shuffle the order")
            group_keys = list(groups.keys())
            random.shuffle(group_keys)
            self.log.debug(f"PVM gen_equal_tbl :There are {len (groups)} groups in total, and the grouping order has been disrupted")
        
        new_gqid_table = []
        for key in group_keys:
            new_gqid_table.extend(groups[key])

        self.vf_to_gqid_indices_tmp.clear()
        new_index_table = {}
        current_start_idx = 0
        for key in group_keys:
            pf_id, vf_id = key
            group = groups[key]
            vid_len = len(group)
            entry_data = (current_start_idx << 10) | (vid_len & 0x3FF)
            new_index_table[key] = (entry_data)
            gqid_indices = list(range(current_start_idx, current_start_idx + vid_len))
            self.vf_to_gqid_indices_tmp[(pf_id, vf_id)] = copy.deepcopy(gqid_indices)
            current_start_idx += vid_len
        self.all_tables_list_tmp["gqid_table"] = copy.deepcopy(new_gqid_table)
        self.all_tables_list_tmp["index_table"] = copy.deepcopy(new_index_table)
        self.log.debug(f'gen_equal_tbl all_tables_list[gqid_table]: {self.all_tables_list_tmp["gqid_table"]}')
        self.log.debug(f"PVM gen_equal_tbl :Update completed: gqid_table has {len (new_gqid_table)} records, and index_table has {len (new_index_table)} indexes")
        self.gen_equal_flag = True
        return True

    async def wr_dut_common_reg(self, tb) -> int:
        async def verify_register_write(self, tb, addr, data):
            if random.random() < 0.05:
                rdata = await tb.reg_rd_req(addr)
                self.log.debug(f" register read-write verification passed, Address:0x{addr:X}, Data:0x{data:X}")
                assert rdata == data, (
                f"register read-write verification failed! "
                f"Address: 0x{addr:X}, Expected: 0x{data:X}, Actual: 0x{rdata:X}")

        self.wr_reg_busy = False
        await Timer(10000, 'ns')
        if self.add_flag :
            for pf_id, stride in self.all_tables_list_tmp["strides"].items():
                addr, data = self._gen_stride_reg(pf_id, stride)
                await tb.reg_wr_req(addr, data)
                self.log.debug(f"wr_dut_common_reg-written to stride [PF:{pf_id}]: addr=0x{addr:x}, data=0x{data:x}")
                await verify_register_write(self, tb, addr, data)
                    
        if self.add_flag or self.del_vf_flag:
            for pf_id, vf_num in self.all_tables_list_tmp["vf_num"].items():
                addr, data = self._gen_vfnum_reg(pf_id, vf_num)
                await tb.reg_wr_req(addr, data)
                self.log.debug(f"wr_dut_common_reg-written to vf_num[PF:{pf_id}]: addr=0x{addr:x}, data=0x{data:x}")
                await verify_register_write(self, tb, addr, data)
            
        if self.add_flag or self.del_pf_flag:
            for pf_id, (start_addr, end_addr) in self.all_tables_list_tmp["start_end_addr"].items():
                regs = self._gen_start_end_reg(pf_id, start_addr, end_addr)
                for addr, data in regs:
                    await tb.reg_wr_req(addr, data)
                    self.log.debug(f"wr_dut_common_reg-written to start_end_addr[PF:{pf_id}]: addr=0x{addr:x}, data=0x{data:x}")
                    await verify_register_write(self, tb, addr, data)

        if self.add_flag or self.del_vf_flag or self.gen_equal_flag:
            for (pf_id, vf_id), entry in self.all_tables_list_tmp["index_table"].items():
                addr, data = self._gen_index_reg(pf_id, vf_id, entry)
                await tb.reg_wr_req(addr, data)
                self.log.debug(f"wr_dut_common_reg-written to index_table[PF:{pf_id}-VF:{vf_id}]: addr=0x{addr:x}, data=0x{data:x}")
                await verify_register_write(self, tb, addr, data)

        if self.add_flag or self.gen_equal_flag or self.del_vf_flag:
            gqid_regs = self._gen_gqid_regs(self.all_tables_list_tmp["gqid_table"])
            for idx, (addr, data) in enumerate(gqid_regs):
                await tb.reg_wr_req(addr, data)
                self.log.debug(f"wr_dut_common_reg-written to gqid_table[index:{idx}]: addr=0x{addr:x}, data=0x{data:x}")
                await verify_register_write(self, tb, addr, data)

        rdata0 = await tb.reg_rd_req(addr=0x0)
        return rdata0

    async def init_common_regs(self, tb) -> bool:
        self.log.debug("Start initializing start/end address registers for PF 0-15")
        qid_addr = self.REG_GROUP_SEL + 0x8
        qid_data = random.randint(0, 255)
        await tb.reg_wr_req(qid_addr, qid_data)
        await Timer(1000, 'ns')
        qid_rdata = await tb.reg_rd_req(qid_addr)
        assert qid_data == int(qid_rdata), (
                f"qid register read-write verification failed! "
                f"Address: 0x{qid_addr:X}, Expected: 0x{qid_data:X}, Actual: 0x{int(qid_rdata):X}")

        for pf_id in range(16):
            regs = self._gen_start_end_reg(pf_id, start_addr=0, end_addr=0)
            for addr, data in regs:
                await tb.reg_wr_req(addr, data)
                self.log.debug(
                    f"Initialized start/end reg [PF:{pf_id}]: addr=0x{addr:x}, data=0x{data:x}")
        self.log.debug("Completed initializing start/end address registers for all PF")
        rdata0 = await tb.reg_rd_req(addr=0x0)
        return True

    async def set_group_select(self, tb) -> int:
        target_group = 1 - self.current_group_flag
        if target_group not in (0, 1):
            raise ValueError(f"PVM set_group_select :Group_id must be 0 or 1, but the actual value is:{target_group}")
        select_group_addr = self.REG_GROUP_SEL
        await Timer(1000, 'ns')
        self.log.debug(f'pvm.all_tables_list[gqid_table]front: {self.all_tables_list_tmp["gqid_table"]}')
        if self.del_pf_flag or self.del_vf_flag:
            self.all_possible_addresses = self.all_possible_addresses_tmp.copy()
            self.vf_to_gqid_indices = self.vf_to_gqid_indices_tmp.copy()
            self.all_tables_list = self.all_tables_list_tmp.copy()
            self._update_illegal_addresses()
            tb.log.debug(f'pvm.all_tables_list[gqid_table]del: {self.all_tables_list["gqid_table"]}')
            tb.log.debug(f'pvm.all_tables_list_tmp[gqid_table]del: {self.all_tables_list_tmp["gqid_table"]}')
            tb.log.debug(f'pvm.all_possible_addresses_tmp:del :{self.all_possible_addresses_tmp}')
            tb.log.debug(f'pvm.illegal_addresses:del :{self.illegal_addresses}')

        await tb.reg_wr_req(addr=select_group_addr, data=target_group)
        rdata1 = await tb.reg_rd_req(addr=select_group_addr)
        self.log.debug(f"PVM set_group_select ")
        
        if self.add_flag or self.gen_equal_flag:
            self.all_possible_addresses = self.all_possible_addresses_tmp.copy()
            self.vf_to_gqid_indices = self.vf_to_gqid_indices_tmp.copy()
            self.all_tables_list = self.all_tables_list_tmp.copy()
            self._update_illegal_addresses()
            tb.log.debug(f'pvm.all_tables_list[gqid_table]add: {self.all_tables_list["gqid_table"]}')
            tb.log.debug(f'pvm.all_tables_list_tmp[gqid_table]add: {self.all_tables_list_tmp["gqid_table"]}')
            tb.log.debug(f'pvm.all_possible_addresses_tmp:add :{self.all_possible_addresses_tmp}')
            tb.log.debug(f'pvm.illegal_addresses:add :{self.illegal_addresses}')
        
        await Timer(2000, 'ns')
        self.wr_reg_busy = True
        self.log.debug(f"PVM set_group_select : all_possible_addresses is {self.all_possible_addresses}")
        self.log.debug(f"PVM set_group_select : current_group_flag is {target_group},self.add_flag is {self.add_flag},self.del_pf_flag is {self.del_pf_flag}")

        self.current_group_flag = target_group
        self.select_group_flag = 1 - self.current_group_flag
        self.add_flag = False
        self.del_pf_flag = False
        self.del_vf_flag = False
        self.gen_equal_flag = False
        return rdata1
    
    def get_pf_vf_vid_by_addr(self, addr: int) -> Optional[Tuple[int, int, int]]:
        for pf_id, vf_id, vid, entry_addr in self.all_possible_addresses:
            if entry_addr == addr:
                return (pf_id, vf_id, vid)
        return None

    def _generate_ops(self, 
                 add_pfs: List[Tuple[int, int, int, int]] = None, 
                 del_pfs: List[int] = None,
                 del_vfs: List[Tuple[int, int]] = None,
                 need_equal: bool = False) -> List[Op]:
        ops = []
        add_pfs = add_pfs or []
        del_pfs = del_pfs or []
        del_vfs = del_vfs or []

        for pf_id, stride, vf_count, total_vid in add_pfs:
            is_pf_exist = pf_id in self.pfs
            current_pf = self.pfs.get(pf_id)

            if not is_pf_exist:
                ops.append(Op(OpType.ADD_PF, pf_id=pf_id, stride=stride))
                start_vf_id = 0
                existing_vf_count = 0 
                self.log.debug(f"_generate_ops:PF {pf_id}")
            else:
                existing_vf_ids = list(current_pf.vfs.keys())
                existing_vf_count = len(existing_vf_ids)
                start_vf_id = max(existing_vf_ids) + 1 if existing_vf_ids else 0
                self.log.debug(f"PF {pf_id} already exists, start adding VF from {start_vf_id}")

            max_allowed = 32 - existing_vf_count
            if max_allowed <= 0:
                self.log.warning(f"PF {pf_id} already has 32 VFs (max allowed), cannot add more VFs")
                continue

            actual_vf_count = min(vf_count, max_allowed)
            if actual_vf_count < vf_count:
                self.log.warning(f"PF {pf_id} can only add {actual_vf_count} VFs (max 32 total), requested {vf_count}")

            if actual_vf_count <= 0:
                self.log.warning(f"VF count for PF {pf_id} is {actual_vf_count}, skip adding VF")
                continue 

            base_vid_len = total_vid // actual_vf_count
            remainder = total_vid % actual_vf_count

            for vf_idx in range(actual_vf_count):
                current_vf_id = start_vf_id + vf_idx
                if current_vf_id > 31:
                    self.log.warning(f"PF {pf_id} VF ID {current_vf_id} exceeds max 31, skip")
                    break
                current_vid_len = base_vid_len + 1 if vf_idx < remainder else base_vid_len
                ops.append(Op(
                    type=OpType.ADD_VF,
                    pf_id=pf_id,
                    vf_id=current_vf_id,
                    vid_len=current_vid_len
                ))
                self.log.debug(f"PF {pf_id} VF {current_vf_id}: vid_len={current_vid_len}")

        for pf_id, vf_id in del_vfs:
            ops.append(Op(OpType.DEL_VF, pf_id=pf_id, vf_id=vf_id))

        for pf_id in del_pfs:
            ops.append(Op(OpType.DEL_PF, pf_id=pf_id))

        if need_equal:
            ops.append(Op(OpType.EQUAL))

        return ops

    async def batch_process(self, tb,
                           add_pfs: List[Tuple[int, int, int, Tuple[int, int]]] = None,
                           del_pfs: List[int] = None,
                           del_vfs: List[Tuple[int, int]] = None,
                           need_equal: bool = False) -> bool:
        """
        - add_pfs: [(pf_id, stride, vf_count, total_len), ...]
        - del_pfs: [pf_id1, pf_id2, ...]
        - del_vfs: [(pf_id1, vf_id1), (pf_id2, vf_id2), ...]
        """
        ops = self._generate_ops(add_pfs, del_pfs, del_vfs, need_equal)
        if not ops:
            return True
        
        self.all_tables_list_tmp = copy.deepcopy(self.all_tables_list)
        self.all_possible_addresses_tmp = copy.deepcopy(self.all_possible_addresses)
        self.vf_to_gqid_indices_tmp = copy.deepcopy(self.vf_to_gqid_indices)
        for op in ops:
            if op.type == OpType.ADD_PF:
                self.add_pf(op.pf_id, op.stride)
            elif op.type == OpType.ADD_VF:
                self.add_vf_to_pf(op.pf_id, op.vf_id, op.vid_len)
            elif op.type == OpType.DEL_VF:
                self.del_vf_from_pf(op.pf_id, op.vf_id)
            elif op.type == OpType.DEL_PF:
                self.del_pf(op.pf_id)
            elif op.type == OpType.EQUAL:
                self.log.debug("Executing EQUAL operation: generating equal table")
                if not self.gen_equal_tbl():
                    self.log.error("Failed to generate equal table in EQUAL operation")
                    return False
 
        await self.wr_dut_common_reg(tb)
        await self.set_group_select(tb)

        return True

    def get_gqid_info(self, op_code, first_be, last_be, byte_length, addr, valid_addresses):
        table1gqid = 0
        table1hit = 0
        doorbell_match = 0
        self.log.debug(f"get_gqid_info addr: {addr}, valid_addresses is {valid_addresses}")

        matched_pf_id = None
        offset_addr = None
        pf_start_addr = None
        for pf_id, (start_addr, end_addr) in self.all_tables_list["start_end_addr"].items():
            if start_addr == 0 and end_addr == 0:
                continue
            if start_addr <= addr <= end_addr:
                matched_pf_id = pf_id
                offset_addr = addr - start_addr
                pf_start_addr = start_addr
                break

        if matched_pf_id is None:
            self.log.debug(f"Address 0x{addr:x} does not belong to any PF, skip address alignment")
            return table1gqid, table1hit, doorbell_match
            
        mask = 0xFFFFFFFFFFFFFFFC
        addr_align = offset_addr & mask
        addr_new = addr_align + pf_start_addr
        self.log.debug(
            f"get_gqid_info Address 0x{addr:x} (dec: {addr}) matched PF {matched_pf_id}, offset_addr is {offset_addr}, pf_start_addr is {pf_start_addr}, addr_new is {addr_new}! ")

        if (op_code == OpCode.MWr 
            and first_be == 3 
            and last_be == 0 
            and byte_length == 4 
            and addr_new in valid_addresses):

            doorbell_match = 1
            pf_vf_vid = self.get_pf_vf_vid_by_addr(addr_new)
            
            if pf_vf_vid is not None:
                found_pf, found_vf, found_vid = pf_vf_vid
                vf_key = (found_pf, found_vf)
                gqid_indices = self.vf_to_gqid_indices.get(vf_key)
                self.log.debug(f"gqid_indices: {gqid_indices}, pf_vf_11vid is {pf_vf_vid}, len(gqid_indices) is {len(gqid_indices)}")
                gqid_table = self.all_tables_list["gqid_table"]
                for i in range(0, len(gqid_table), 20):
                    chunk = gqid_table[i:i+20]
                    self.log.debug(f'pvm.all_tables_list[gqid_table] (group {i//20 + 1}): {chunk}')
                
                if gqid_indices is not None and len(self.all_tables_list["gqid_table"]) != 0:
                    if 0 <= found_vid < len(gqid_indices):
                        gqid_table_index = gqid_indices[found_vid]
                        if gqid_table_index < len(self.all_tables_list["gqid_table"]):
                            tbl_pf, tbl_vf, table1gqid, table1hit = self.all_tables_list["gqid_table"][gqid_table_index]
                            self.log.debug(f"pf_vf_vid: {pf_vf_vid}, tbl_pf={tbl_pf},, tbl_vf={tbl_vf},gqid_table_index {gqid_table_index}")
                            if (tbl_pf, tbl_vf) == vf_key:
                                self.log.debug(f"match gqid: {hex(table1gqid)}, hit={table1hit}")
                            else:
                                self.log.warning("Invalid gqid_table entry (PF/VF mismatch)")
                        else:
                            self.log.warning(f"Gqid_table index out of bounds (index: {gqid_table_index}, table length: {len (self.all_tables_list ['gqid_table'])})")
                    else:
                        self.log.warning(f"VID {found_vid} is out of range (maximum VID: {len (gqid_indices) -1})")
                else:
                    self.log.warning(f"No index mapping was found in vf_to-ugqid_indices for VF {found_vf} (PF {found_pf})")
        return table1gqid, table1hit, doorbell_match

    def get_available_pf_ids(self) -> List[int]:
        used_pf_ids = set(self.pfs.keys())
        all_pf_ids = set(range(16))
        return list(all_pf_ids - used_pf_ids)

    def get_pf_with_available_vf(self) -> List[PF]:
        return [pf for pf in self.pfs.values() if len(pf.vfs) < 32]

    def calc_used_vid_total(self) -> int:
        used_vid = 0
        for pf in self.pfs.values():
            for vf in pf.vfs.values():
                used_vid += vf.vid_len
        return used_vid

class Constants:
    DATA_ALIGNMENT = 32
    USER0_LOW_SHIFT = 8
    BDF_MASK = 0xFFFF
    BAR_RANGE_MASK = 0x3
    COOKIE_MAX = 1 << 19
    BE_VALID_RANGE = (0, 15)
    ADDR_MAX = 2 **64
    CPL_BYTE_COUNT_MAX = 2** 12


class BeqTxq(NamedTuple):
    rsp:TlpBypassRsp
    qid: int
    data: bytearray
    user0: int
    length:int