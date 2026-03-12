#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : virtio_blk_qs_manager.py
#* 作者名称 : matao
#* 创建日期 : 2025/09/30
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   09/30       matao       初始化版本
#******************************************************************************/
import sys
import math
import random
import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Timer, Event
from cocotb.utils import get_sim_time
from cocotb.log import SimLog, SimLogFormatter
from enum import Enum, unique
from scapy.all import Packet, BitField
import logging
from typing import Optional
from dataclasses import dataclass, field
from typing import List, Tuple
from collections import deque

sys.path.append('../../common')
from monitors.tlp_adap_dma_bus import DmaRam
from bus.tlp_adap_dma_bus import DmaWriteBus, DmaReadBus, Desc
from bus.beq_data_bus import BeqBus, BeqTxqSbd, BeqData
from monitors.beq_data_bus import BeqRxqSlave
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster
from virtio_blk_downstream_defines import *


@dataclass
class DmaBlock:
    data: bytes
    length: int
    dma_err: int
    dma_index: int

@dataclass
class BlkDesc:
    virt_desc: VirtioDesc  # 原始VirtioDesc对象
    packed: bytes  # 打包后的描述符数据
    sop: bool
    eop: bool
    desc_index: int
    block_count: int
    dma_blocks: List[DmaBlock] = field(default_factory=list)

@dataclass
class DescGroup:
    descs: List[BlkDesc] = field(default_factory=list)  # 包含的desc
    buffer_headers: List = field(default_factory=list)
    group_index: int = 0
    sbd_obj: Optional[VirtioDescRspSbd] = None  # 原始SBD实例
    sbd_packed: bytes = b""  # 打包后的SBD字节数据
    sbd_total_len: int = 0
    pkt_num: int = 0
    dma_data_list: List = field(default_factory=list)
    group_dma_err_cnt :int=0

@dataclass
class Chain:
    groups: List[DescGroup] = field(default_factory=list)  # 包含的desc组
    chain_index: int = 0
    total_desc_num: int = 0 # 该chain的总描述符数量
    slot_rsp_err_info: int = 0

class vQueue:
    # cold done table, 类属性：属于类本身（vQueue 这个类），所有实例共享同一份数据，内存中只有一个副本,因为这个规则表不会变，不需要每个队列单独一份
    _WILDCARD = 'x'
    _COLD_DONE_RULES= {
        (0, 'x', 'x', 'x', 'x'): (1, 0),
        (1, 0, 1, 'x', 'x'):     (1, 0),
        (1, 0, 0, 'x', 'x'):     (0, 1),
        (1, 1, 0, 1, 1):         (0, 1),
        (1, 1, 0, 0, 1):         (1, 0),
        (1, 1, 0, 0, 0):         (0, 0)
    }
    _PER_SLOT_DESC_NUM = 16
    _BLK_MAX_SIZE = 65536 # 64k
    # probability
    _PROB_70P = 0.7 
    _PROB_30P = 0.3
    _PROB_50P_NO_ERR = 0.5
    # qos query cnt
    QOS_QUERY_CNT_MAX = 3
    # slot done
    SLOT_RSP_CNT_MAX = 3
    _bdf_counter = 0
    def __init__(self, cfg, mem, qid, typ, ctx_shutdown_mode, err_shutdown_mode, dma_err_mode):
        self.log = SimLog("cocotb.tb.vQueue")
        self.log.setLevel(logging.INFO)
        self.cfg = cfg
        self.mem = mem
        self.qid = qid
        self.typ = typ
        self.vq_gid = qid
        self.bdf = vQueue._bdf_counter
        vQueue._bdf_counter = (vQueue._bdf_counter + 1) % 256
        self.alloc_size = self.cfg.desc_chain_limit * self.cfg.desc_num_limit * self.cfg.dma_len_limit
        if self.alloc_size <= 0:
            raise ValueError(f"Invalid alloc_size {self.alloc_size} (desc_chain_limit={self.cfg.desc_chain_limit}, desc_num_limit={self.cfg.desc_num_limit}, dma_len_limit={self.cfg.dma_len_limit})")
        self.desc_rd_dma_data = self.mem.alloc_region(self.alloc_size, bdf=self.bdf)
        # err shutdown
        self.err_shutdown_mode = err_shutdown_mode
        self.ctx_shutdown_mode = ctx_shutdown_mode
        self.dma_err_mode = dma_err_mode
        # blk desc
        self.desc_chain_limit = cfg.desc_chain_limit #队列最多几个chain
        self.desc_num_base = cfg.desc_num_base
        self.desc_num_limit = cfg.desc_num_limit
        # dma len
        self.dma_len_base = cfg.dma_len_base
        self.dma_len_limit = cfg.dma_len_limit
        # cold_done
        self.cold_done_table = self._COLD_DONE_RULES
        self.expected_cold = None
        self.expected_done = None
        # qos update done
        self.qos_update_done = False #表示队列qos更新完成标志
        self.qos_act_update_cnt = 0 #实际更新次数对应desc组的总和
        self.qos_exp_update_cnt = 0 #期望更新次数对应desc组的总和
        self.magic_num = 0xc0de
        self.blk_desc_done_cnt = 0 # 描述符组数
        self.slot_done_cnt = 0 # 记录slot_rsp的done次数，连续两次done则不会发起notify请求

        #self.pending_blk_desc = []    # 专属blk_desc_process：处理desc/sbd发送
        #self.pending_qos_update = []  # 专属qos_update_process：处理qos更新
        #self.pending_beq = []         # 专属blk2beq_process：处理buffer_header/BEQ校验
        #self.pending_dma_data = []    # 专属blk2beq_process：处理dma rd校验
        #self.pending_dma_err = []     # 专属err_info：处理dma err校验
        self.pending_blk_desc = deque()    # 专属blk_desc_process：处理desc/sbd发送
        self.pending_qos_update = deque()  # 专属qos_update_process：处理qos更新
        self.pending_beq = deque()         # 专属blk2beq_process：处理buffer_header/BEQ校验
        self.pending_dma_data = deque()    # 专属blk2beq_process：处理dma rd校验
        self.pending_dma_err = deque()
        # initialization
        self._init_vqueue()

    def _init_vqueue(self):
        # ctx
        self.gen = random.randint(0, 0xFF)
        self.unit = self.qid #为了简单，这设置成每个qid对应一个uid，与模块功能影响不大
        self.qos_en = 1 if random.random() < self._PROB_70P else 0
        self.blk_ptr_dat = random.randint(0, 0xFFFF)
        self.blk_ptr_dat_bak = self.blk_ptr_dat
        self.blk_chain_fst_seg_wr_dat = 1
        # slot rsp 先随机cold=1/0,done=0场景，最后更新成done=1
        self.slot_rsp_pkt_id      = random.randint(0, 1023)
        self.slot_rsp_ok          = random.randint(0, 1)
        self.slot_rsp_local_empty = 1 
        self.slot_rsp_avail_empty = 0 
        self.slot_rsp_stat_stopping = 1 if random.random() < self._PROB_30P else 0
        if self.slot_rsp_stat_stopping == 1:
            self.slot_rsp_stat_doing = 0
        else:
            self.slot_rsp_stat_doing = 1

        self.slot_rsp_engine_limit  = random.randint(0, 1)
        if self.err_shutdown_mode:
            if random.random() < self._PROB_50P_NO_ERR:
                self.slot_rsp_err_info = 0
            else:
                self.slot_rsp_err_info = random.randint(1, 255)
        else:
            self.slot_rsp_err_info = 0

        self.slot_stopping_cnt = 0
        self.slot_local_empty_cnt = 0

        # blk_desc
        self.dev_id = random.randint(0, 1023)
        self.pkt_id = random.randint(0, 1023)
        self.val_cnt = random.randint(0, 2**16-1)
        self.ring_id = random.randint(0, 2**16-1)
        self.avail_idx = random.randint(0, 2**16-1)
        if self.slot_rsp_err_info == 0 and self.err_shutdown_mode:
            self.desc_shutdown = 0 if random.random() < self._PROB_50P_NO_ERR else 1
            self.desc_err = 0 if random.random() < self._PROB_50P_NO_ERR else random.randint(1, 255)
        else:
            self.desc_shutdown = 0
            self.desc_err = 0

        # qos
        if self.qos_en == 1:
            self.qos_ok = 1 if random.random() < self._PROB_70P else 0
        else:
            self.qos_ok = 1
        self.qos_query_cnt = 0 # qos查询次数，qos_en == 1，而ok==0时，设置一个请求次数上限，达到后ok==1,模拟一段时间后限速允许发送
        self.qos_flag = True if self.qos_ok == 1 else False # 表示qos此次查询为ok==1，为后面slot参数改动开始标志
        if self.slot_rsp_err_info != 0 or self.desc_err != 0 or self.desc_shutdown == 1 or self.qos_en == 0:
            self.qos_update_done = True
        
    def _match_params(self, params, pattern):
        for param, pat in zip(params, pattern):
            if pat != self._WILDCARD and param != pat:
                return False
        return True

    def cold_done_process(self):
        params = (
            self.qos_ok,
            self.slot_rsp_stat_doing,
            self.slot_rsp_stat_stopping,
            self.slot_rsp_avail_empty,
            self.slot_rsp_local_empty
        )
        self.expected_cold, self.expected_done = None, None
        for pattern, (cold, done) in self.cold_done_table.items():
            if self._match_params(params, pattern):
                self.expected_cold, self.expected_done = cold, done
                break
        if self.expected_cold is None:
            self.log.warning(
                f"Queue {self.qid} (type: {self.typ}) no matching rule! "
                f"Params: {params}, Rules: {list(self.cold_done_table.keys())}"
            )

    async def gen_desc(self, desc_cnt, chain_last, chain_desc_index, current_offset):
        # 初始化当前组的desc列表和dma块列表
        descs = []
        buffer_headers = []
        sbd_tot_len = 0
        max_dma_block_len = 4096
        pkt_num = 0

        for i in range(desc_cnt):
            desc = VirtioDesc()
            desc.next = random.randint(0, 0xFFFF)
            desc.flags_rsv = random.randint(0, 0x1FFF)
            desc.flags_indirect = random.randint(0, 1)
            desc.flags_write = random.randint(0, 1)
            desc.flags_next = 0 if (i == desc_cnt - 1 and chain_last == 1) else 1
            pkt_num = 1 if (desc.flags_next == 0) else 0

            dma_blocks = []
            block_count = 0
            if (self.desc_err == 0 and self.desc_shutdown == 0) and desc.flags_write == 0:
                total_length = random.randint(self.dma_len_base, self.dma_len_limit)
                desc.len = total_length
                block_count = (total_length + max_dma_block_len - 1) // max_dma_block_len

                for block_idx in range(block_count):
                    if self.dma_err_mode:
                        dma_rd_err = 0 if random.random() < self._PROB_70P else 1
                    else:
                        dma_rd_err = 0
                    block_length = min(max_dma_block_len, total_length - block_idx * max_dma_block_len)
                    block_offset = current_offset
                    block_data, block_abs_addr = await self.gen_dma_rd_data(
                        dma_rd_err=dma_rd_err, offset=block_offset, length=block_length
                    )
                    if block_idx == 0:
                        desc_start_addr = block_abs_addr
                    # 存储当前DMA块
                    dma_blocks.append(DmaBlock(
                        data=block_data,
                        length=block_length,
                        dma_err=dma_rd_err,
                        dma_index=block_idx
                    ))
                    current_offset += block_length  # 更新总偏移

                desc.addr = desc_start_addr  # 描述符起始地址=第一块地址
            else:
                # 非读操作
                total_length = random.randint(self.dma_len_base, self.dma_len_limit)
                desc.len = total_length
                desc.addr = random.randint(0, 2**64 - 1)

            virtio_flags_obj = VirtioFlags(
                flags_rsv=desc.flags_rsv,
                flags_indirect=desc.flags_indirect,
                flags_write=desc.flags_write,
                flags_next=desc.flags_next
            )
            virtio_flags_dat = virtio_flags_obj.pack()
            buffer_header = BufferHeader(
                magic_num=self.magic_num,
                length=total_length,
                addr=desc.addr,
                virtio_flags=virtio_flags_dat,
                desc_index=self.ring_id,
                vq_gen=self.gen,
                vq_gid=self.vq_gid
            )

            descs.append(BlkDesc(
                virt_desc=desc,
                packed=desc.pack(),
                sop=(i == 0),
                eop=(i == desc_cnt - 1),
                desc_index=i,
                dma_blocks=dma_blocks,
                block_count=block_count
            ))

            buffer_headers.append(( buffer_header, i, desc.flags_write))
            sbd_tot_len += total_length

        dma_data_list = []
        group_dma_err_cnt = 0
        for desc in descs:
            for blk in desc.dma_blocks:
                if blk.dma_err:
                    error_data = b'\x00' * blk.length
                    group_dma_err_cnt += 1
                else:
                    error_data = blk.data
                dma_data_list.append((
                    error_data,       
                    blk.length,     
                    blk.dma_err,    
                    blk.dma_index,  
                    desc.desc_index 
                ))
        blk_desc_sbd_obj = VirtioDescRspSbd(
            vq_typ=self.typ, vq_id=self.qid, dev_id=self.dev_id, pkt_id=self.pkt_id,
            total_buf_length=sbd_tot_len, valid_desc_cnt=self.val_cnt,
            ring_id=self.ring_id, avail_idx=self.avail_idx,
            forced_shutdown=self.desc_shutdown, err_info=self.desc_err
        )
        blk_desc_sbd_packed = blk_desc_sbd_obj.pack()
        desc_group = DescGroup(
            descs=descs,
            buffer_headers=buffer_headers,
            group_index=chain_desc_index,
            sbd_obj=blk_desc_sbd_obj,  # 赋值原始SBD实例
            sbd_packed=blk_desc_sbd_packed,  # 赋值打包后的字节
            sbd_total_len=sbd_tot_len, # 赋值该组总长度
            pkt_num=pkt_num,
            dma_data_list=dma_data_list,
            group_dma_err_cnt = group_dma_err_cnt
        )
        return desc_group, current_offset  

    async def gen_dma_rd_data(self, dma_rd_err, offset, length):
        test_data = random.randbytes(length) 
        if dma_rd_err:
            await self.desc_rd_dma_data.write(offset, test_data, defect_injection=1)
        else :
            await self.desc_rd_dma_data.write(offset, test_data)
        data_absolute_addr = self.desc_rd_dma_data.get_absolute_address(offset)
        return test_data, data_absolute_addr

    async def gen_chain(self):
        self.chains = []  # 存储所有chain
        #self.pending_blk_desc = []
        #self.pending_qos_update = []
        #self.pending_beq = []
        #self.pending_dma_data = []
        #self.pending_dma_err = []
        self.pending_blk_desc = deque()  
        self.pending_qos_update = deque()
        self.pending_beq = deque()       
        self.pending_dma_data = deque()  
        self.pending_dma_err = deque()

        if self.slot_rsp_err_info == 0:
            current_offset = 0
            for chain_idx in range(self.desc_chain_limit):
                chain = Chain(chain_index=chain_idx, total_desc_num=0)
                self.chains.append(chain)

                if self.desc_err != 0 or self.desc_shutdown == 1:
                    desc_num = 1
                else:
                    desc_num = random.randint(self.desc_num_base, self.desc_num_limit)
                chain.total_desc_num = desc_num
                chain.slot_rsp_err_info = 0

                # 分desc组处理（每组≤16个）
                if desc_num > self._PER_SLOT_DESC_NUM:
                    max_per = self._PER_SLOT_DESC_NUM
                    desc_seq = (desc_num + max_per - 1) // max_per

                    for i in range(desc_seq):
                        desc_cnt = max_per if i < desc_seq - 1 else (desc_num - i * max_per)
                        chain_last = 0 if (i < desc_seq - 1) else 1  # 当前组是否为chain最后一组
                        # 调用gen_desc获取当前组
                        desc_group, current_offset = await self.gen_desc(
                            desc_cnt=desc_cnt,
                            chain_last=chain_last,
                            chain_desc_index=i,
                            current_offset=current_offset
                        )
                        self.pending_blk_desc.append(desc_group)
                        self.pending_qos_update.append(desc_group)
                        for bh in desc_group.buffer_headers:
                            buffer_header, desc_idx, desc_write_flag = bh
                            self.pending_beq.append( 
                                (buffer_header, chain.chain_index, desc_group.group_index, desc_idx, desc_write_flag) 
                            )
                        for dma_item in desc_group.dma_data_list:
                            error_data, blk_length, dma_rd_err, dma_index, desc_idx = dma_item
                            new_dma_item = (
                                chain.chain_index, desc_group.group_index, desc_idx,
                                error_data, blk_length, dma_rd_err, dma_index
                            )
                            self.pending_dma_data.append(new_dma_item)
                        self.pending_dma_err.extend([
                            item for item in desc_group.dma_data_list 
                            if item[2]  # item[2] 对应 blk.dma_err
                        ])
                        chain.groups.append(desc_group)  # 加入当前chain的组列表
                        self.blk_desc_done_cnt += 1
                        self.qos_exp_update_cnt += 1
                else:
                    # 描述符数量≤16，单组处理
                    desc_group, current_offset = await self.gen_desc(
                        desc_cnt=desc_num,
                        chain_last=1,  # 单组即chain最后一组
                        chain_desc_index=0,
                        current_offset=current_offset
                    )
                    self.pending_blk_desc.append(desc_group)
                    self.pending_qos_update.append(desc_group)
                    for bh in desc_group.buffer_headers:
                        buffer_header, desc_idx, desc_write_flag = bh
                        self.pending_beq.append( 
                            (buffer_header, chain.chain_index, desc_group.group_index, desc_idx, desc_write_flag) 
                        )
                    for dma_item in desc_group.dma_data_list:
                        error_data, blk_length, dma_rd_err, dma_index, desc_idx = dma_item
                        new_dma_item = (
                            chain.chain_index, desc_group.group_index, desc_idx,
                            error_data, blk_length, dma_rd_err, dma_index
                        )
                        self.pending_dma_data.append(new_dma_item)

                    self.pending_dma_err.extend([
                        item for item in desc_group.dma_data_list 
                        if item[2]  
                    ])
                    chain.groups.append(desc_group)
                    self.blk_desc_done_cnt += 1
                    self.qos_exp_update_cnt += 1
        else:
            chain = Chain(chain_index=0, total_desc_num=0)
            self.chains.append(chain)
            chain.slot_rsp_err_info = self.slot_rsp_err_info
            buffer_headers = [] 
            buffer_header = BufferHeader(
                magic_num=self.magic_num,
                vq_gen=self.gen,
                vq_gid=self.vq_gid
            )
            buffer_headers.append((buffer_header, 0))
            desc_group = DescGroup(
                buffer_headers=buffer_headers,
                group_index=0
            )
            for bh in desc_group.buffer_headers:
                buffer_header, desc_idx = bh
                self.pending_beq.append( (buffer_header, chain.chain_index, 0, desc_idx, 1) ) 


class VirtQs:
    _SLOT_DONE = 0.5 
    def __init__(self, mem, dut, max_seq):
        self.log = SimLog("cocotb.tb.VirtQs")
        self.log.setLevel(logging.INFO)
        self.mem = mem
        self.dut = dut
        self.max_seq = max_seq
        self.seq = 0
        self._q = {} # qid:vQueue
        self._local_qid_queue = Queue(maxsize=32) 
        self._slot_rsp_queue = Queue(maxsize=4) #slot = 4
        self._slot2blk_queue = Queue()
        self.beq_rxq_cnt = 0
        self.slot_rsp_err_cnt   = 0
        self.blk_desc_err_cnt   = 0
        self.dma_rd_rsp_err_cnt = 0
        self.blk_desc_cnt       = 0
        self.buffer_hdr2beq_cnt = 0
        self.dma_data2beq_cnt   = 0
        # qid
        all_qids = list(range(256))
        random.shuffle(all_qids)
        self.available_qids = Queue(maxsize=256)
        for qid in all_qids:
            self.available_qids.put_nowait(qid)
        self.qid_available_event = Event()
        self.all_queues_stopped = Event() 

        self.QosInfoRdTblIf = QosInfoRdTbl(QosInfoRdReqBus.from_prefix(dut, "qos_info_rd"), QosInfoRdRspBus.from_prefix(dut, "qos_info_rd"), None, dut.clk, dut.rst)
        def _qosInfoRdCallback(req_obj):
            qid = int(req_obj.req_qid)
            if qid not in self._q.keys():
                raise ValueError("The qos_info rd queue(qid:{}) is not exists".format(qid))
            rsp = QosInfoRdRspTransaction()
            rsp.rsp_qos_unit = self._q[qid].unit
            rsp.rsp_qos_enable = self._q[qid].qos_en
            return rsp
        self.QosInfoRdTblIf.set_callback(_qosInfoRdCallback)

        self.DmaInfoRdTblIf = DmaInfoRdTbl(DmaInfoRdReqBus.from_prefix(dut, "dma_info_rd"), DmaInfoRdRspBus.from_prefix(dut, "dma_info_rd"), None, dut.clk, dut.rst)
        def _dmaInfoRdCallback(req_obj):
            qid = int(req_obj.req_qid)
            if qid not in self._q.keys():
                raise ValueError("The dma_info rd queue(qid:{}) is not exists".format(qid))
            rsp = DmaInfoRdRspTransaction()
            rsp.rsp_bdf = self._q[qid].bdf
            if self._q[qid].ctx_shutdown_mode:
                rsp.rsp_forcedown = random.randint(0, 1)
            else:
                rsp.rsp_forcedown = 0
            rsp.rsp_generation = self._q[qid].gen
            return rsp
        self.DmaInfoRdTblIf.set_callback(_dmaInfoRdCallback)

        self.PtrTblIf = PtrTbl(PtrRdReqBus.from_prefix(dut, "blk_ds_ptr"), PtrRdRspBus.from_prefix(dut, "blk_ds_ptr"), PtrWrBus.from_prefix(dut, "blk_ds_ptr"), dut.clk, dut.rst, read_first=False)
        def _PtrWrCallback(req_obj):
            qid = int(req_obj.wr_qid)
            data = int(req_obj.wr_dat)
            if qid not in self._q.keys():
                raise ValueError("The ptr wr req queue(qid:{}) is not exists".format(qid))
            self._q[qid].blk_ptr_dat = data

        def _PtrRdCallback(req_obj):
            qid = int(req_obj.rd_req_qid)
            rsp = PtrRdRspTransaction()
            if qid not in self._q.keys():
                raise ValueError("The ptr rd req queue(qid:{}) is not exists".format(qid))
            rsp.rd_rsp_dat = self._q[qid].blk_ptr_dat
            return rsp
        self.PtrTblIf.set_callback(_PtrRdCallback)
        self.PtrTblIf.set_wr_callback(_PtrWrCallback)

        self.FstSegTblIf = FstSegTbl(FstSegReqBus.from_prefix(dut, "blk_chain_fst_seg"), FstSegRspBus.from_prefix(dut, "blk_chain_fst_seg"), FstSegWrBus.from_prefix(dut, "blk_chain_fst_seg"), dut.clk, dut.rst, read_first=False)
        def _FstSegWrCallback(req_obj):
            qid = int(req_obj.wr_qid)
            data = int(req_obj.wr_dat)
            if qid not in self._q.keys():
                raise ValueError("The FstSeg wr req queue(qid:{}) is not exists".format(qid))
            self._q[qid].blk_chain_fst_seg_wr_dat = data

        def _FstSegRdCallback(req_obj):
            qid = int(req_obj.rd_req_qid)
            rsp = FstSegRspTrans()
            if qid not in self._q.keys():
                raise ValueError("The FstSeg rd req queue(qid:{}) is not exists".format(qid))
            rsp.rd_rsp_dat = self._q[qid].blk_chain_fst_seg_wr_dat
            return rsp
        self.FstSegTblIf.set_callback(_FstSegRdCallback)
        self.FstSegTblIf.set_wr_callback(_FstSegWrCallback)
        
        self.sch_req      = NotifySchSource(NotifySchBus.from_prefix(dut, "sch_req"), dut.clk, dut.rst)
        self.query_req    = QueryReqSink   (QueryReqBus.from_prefix(dut, "qos_query_req"), dut.clk, dut.rst)
        self.query_rsp    = QueryRspSource (QueryRspBus.from_prefix(dut, "qos_query_rsp"), dut.clk, dut.rst)
        self.update_req   = UpDateReqSink  (UpDateReqBus.from_prefix(dut, "qos_update"), dut.clk, dut.rst)
        self.slot_req     = AllocSlotReqSink  (AllocSlotReqBus.from_prefix(dut, "alloc_slot_req"), dut.clk, dut.rst)
        self.slot_rsp     = AllocSlotRspSource(AllocSlotRspBus.from_prefix(dut, "alloc_slot_rsp"), dut.clk, dut.rst)
        self.blk_desc_rsp = BlkDescSource  (BlkDescBus.from_prefix(dut, "blk_desc"), dut.clk, dut.rst)
        self.dma_rd       = DmaRam(None, DmaReadBus.from_prefix(dut, "dma"), dut.clk, dut.rst, mem=mem)
        self.beq_rxq      = BeqRxqSlave( BeqBus.from_prefix(dut, "blk2beq"), dut.clk, dut.rst)
        self.err_info_if  = ErrInfoSink( ErrInfoBus.from_prefix(dut, "blk_ds_err_info_wr"), dut.clk, dut.rst)
        self.regconmaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)

    async def reg_rd_req(self, addr):
        rddata = await self.regconmaster.read(addr)
        return rddata

    async def reg_wr_req(self, addr, data):
        await self.regconmaster.write(addr,data)

    def log_struct(self,
        title: str, 
        struct_obj: Optional[Packet] = None,
        extra_fields: dict = None, 
        special_fields: dict = None, 
        is_assert: bool = False,  # False: common log , true: assert
        expected: any = None,
        actual: any = None, 
        err_msg: str = "" ,
        compare_fields: list = None):
        self.log.debug(title)
        
        if not is_assert:
            for field in struct_obj.fields_desc:
                field_name = field.name
                if field_name.startswith("_"):
                    continue
                
                field_value = getattr(struct_obj, field_name, None)
                if field_value is None:
                    continue
                
                hex_digits = (field.size + 3) // 4 
                hex_format = f"0{hex_digits}X"
                
                if special_fields and field_name in special_fields:
                    field_desc = special_fields[field_name](field_value)
                    self.log.debug(f"  {field_name}: {field_value} ({field_desc})")
                else:
                    self.log.debug(f"  {field_name}: {field_value} (0x{field_value:{hex_format}})")
        
        if extra_fields:
            for name, value in extra_fields.items():
                if isinstance(value, int):
                    self.log.debug(f"  {name}: {value} (0x{value:01X})")
                else:
                    self.log.debug(f"  {name}: {value}")
        self.log.debug(" ///////////////////////////////////////////////////////////")
        
        if is_assert:
            def get_struct_fields(struct_instance):
                if isinstance(struct_instance, Packet):
                    fields = struct_instance.fields_desc
                    if compare_fields:
                        fields = [f for f in fields if f.name in compare_fields]
                    else:
                        fields = [f for f in fields if not f.name.startswith("_")]
                    return {f.name: getattr(struct_instance, f.name, None) for f in fields}
                return struct_instance

            expected_converted = get_struct_fields(expected)
            actual_converted = get_struct_fields(actual)

            if expected_converted != actual_converted:
                diff_info = []
                if isinstance(expected, Packet) and isinstance(actual, Packet):
                    target_fields = compare_fields if compare_fields else [
                        f.name for f in expected.fields_desc if not f.name.startswith("_")
                    ]
                    common_fields = set(expected.fields_desc).intersection(set(actual.fields_desc))

                    for field_name in target_fields:
                        if hasattr(expected, field_name) and hasattr(actual, field_name):
                            exp_val = getattr(expected, field_name, None)
                            act_val = getattr(actual, field_name, None)
                            def format_value(val):
                                if isinstance(val, Packet):
                                    return str(get_struct_fields(val))
                                elif isinstance(val, int):
                                    return f"{val} (0x{val:0X})"
                                else:
                                    return str(val)
                            exp_str = format_value(exp_val)
                            act_str = format_value(act_val)
                            diff_info.append(f"    {field_name}: Expected={exp_str}, Actual={act_str}")
                    diff_info = "\n".join(diff_info) if diff_info else "    No fields to compare"
                else:
                    def format_non_struct(val):
                        if isinstance(val, int):
                            return f"{val} (0x{val:0X})"
                        return str(val)
                    exp_str = format_non_struct(expected_converted)
                    act_str = format_non_struct(actual_converted)
                    diff_info = f"    Expected={exp_str}, Actual={act_str}"

                extra_info = "\n".join([f"  {k}: {v}" for k, v in (extra_fields or {}).items()])
                full_err_msg = (
                    f"{err_msg}\n"
                    f"  Struct Comparison Diff:\n{diff_info}\n"
                    f"  Extra Info:\n{extra_info}" if extra_info else f"  Extra Info: None"
                )
                self.log.error(full_err_msg) 
            assert expected_converted == actual_converted, err_msg

    
    async def blk_ds_err_info_check_process(self):
        while True:
            err_info_wr_req = await self.err_info_if.recv()
            err_info_wr_req_dat = int(err_info_wr_req.dat)
            err_info_qid = err_info_wr_req.qid & 0xFF
            q = self._q[err_info_qid]
            self.log.debug(
                f"Received error request: qid={err_info_qid}, requested error code={err_info_wr_req_dat}, "
                f"current status: slot_rsp_err_info={q.slot_rsp_err_info}, "
                f"desc_err={q.desc_err}, "
                f"length of pending_dma_err={len(q.pending_dma_err)}, "
                f"dma_err of the first element in pending_dma_err={q.pending_dma_err[0][2] if q.pending_dma_err else 'None'}"
            )
            if q.slot_rsp_err_info != 0:
                if q.slot_rsp_err_info != err_info_wr_req_dat:
                    self.log.error(
                        f"blk_ds_err_info_check_process error, slot_rsp_err_info = {q.slot_rsp_err_info},err_info_wr_req_dat: {err_info_wr_req_dat}, qid is {err_info_qid}"
                    )
            elif q.desc_err != 0:
                if q.desc_err != err_info_wr_req_dat:
                    self.log.error(
                        f"blk_ds_err_info_check_process error, desc_err = {q.desc_err},err_info_wr_req_dat: {err_info_wr_req_dat}, qid is {err_info_qid}"
                    )
            elif q.pending_dma_err and q.pending_dma_err[0][2] != 0:
                dma_tuple = q.pending_dma_err.popleft()
                _, blk_length, err_info_dma_err, dma_index, desc_index = dma_tuple
                if err_info_dma_err != 0:
                    dma_err_code = 0xd0
                if dma_err_code != err_info_wr_req_dat:
                    self.log.error(
                        f"blk_ds_err_info_check_process error! "
                        f"QID: {err_info_qid}, "f"Expected DMA error code: {dma_err_code}, "
                        f"Actual written error code: {err_info_wr_req_dat}, "f"DMA block length: {blk_length} bytes, "
                        f"DMA block index: {dma_index}, "
                        f"Associated descriptor index: {desc_index}")
            else:
                self.log.error(
                    f"blk_ds_err_info_check_process error, qid has no err! qid is {err_info_qid}"
                )
    
    async def sch_req_process(self):#gen_blk_desc生成qid的desc后放到_local_qid_queue，这里_local_qid_queue非空则发起sch请求
        while True:
            qid = await self._local_qid_queue.get()
            obj = self.sch_req._transaction_obj()
            obj.qid = qid
            await self.sch_req.send(obj)

    async def qos_query_process(self):#qos_en==1,blk_chain_fst_seg_wr_dat==1
        while True:
            qos_query_req = await self.query_req.recv()
            uid = int(qos_query_req.uid)
            obj = self.query_rsp._transaction_obj()
            obj.ok = self._q[uid].qos_ok
            await self.query_rsp.send(obj)
            if self._q[uid].qos_ok == 1:
                self._q[uid].qos_flag = True
            else:
                self._q[uid].qos_query_cnt += 1
                if self._q[uid].qos_query_cnt == self._q[uid].QOS_QUERY_CNT_MAX:
                    self._q[uid].qos_ok = 1
            if self._q[uid].blk_chain_fst_seg_wr_dat == 0:
                self.log.error(
                    f"QoS query request error, blk_chain_fst_seg_wr_dat is 0 and cannot initiate the query! QID: {uid}"
                )
            if self._q[uid].qos_en == 0:
                self.log.error(
                    f"QoS query request error, qos_en is 0 and cannot initiate the query! QID: {uid}"
                )

    async def slot_req_process(self):
        while True:
            slot_req = await self.slot_req.recv()
            slot_req = VirtioVq().unpack(slot_req.dat)
            slot_vq_typ = slot_req.typ
            slot_vq_id  = slot_req.qid
            slot_rsp_obj = VirtioDescSlotRsp(vq_typ=slot_vq_typ, vq_id=slot_vq_id, pkt_id=self._q[slot_vq_id].slot_rsp_pkt_id, ok=self._q[slot_vq_id].slot_rsp_ok, 
                        local_ring_empty=self._q[slot_vq_id].slot_rsp_local_empty, avail_ring_empty=self._q[slot_vq_id].slot_rsp_avail_empty, 
                        q_stat_doing=self._q[slot_vq_id].slot_rsp_stat_doing, q_stat_stopping=self._q[slot_vq_id].slot_rsp_stat_stopping,
                        desc_engine_limit=self._q[slot_vq_id].slot_rsp_engine_limit, err_info=self._q[slot_vq_id].slot_rsp_err_info)
            slot_rsp_dat = slot_rsp_obj.pack()
            await self._slot_rsp_queue.put((slot_vq_id, slot_rsp_obj, slot_rsp_dat))
            if self._q[slot_vq_id].slot_rsp_err_info != 0:
                self.slot_rsp_err_cnt += 1
            if self._q[slot_vq_id].typ != slot_vq_typ:
                self.log.error(
                    f"slot_req error, slot_vq_typ is {slot_vq_typ} and typ is {self._q[slot_vq_id].typ} ! QID: {slot_vq_id}"
                )
            if self._q[slot_vq_id].qos_ok != 1:
                self.log.error(
                    f"slot_req error, slot_vq_typ is {slot_vq_typ} and qos_ok is {self._q[slot_vq_id].qos_ok} ! QID: {slot_vq_id}"
                )

    async def slot_rsp_process(self):
        while True:
            slot_vq_id, slot_rsp_obj, slot_rsp_dat = await self._slot_rsp_queue.get()
            self._q[slot_vq_id].cold_done_process()
            obj = self.slot_rsp._transaction_obj()
            obj.dat = slot_rsp_dat
            await self.slot_rsp.send(obj)
            if self._q[slot_vq_id].expected_done == 1:
                self._q[slot_vq_id].slot_done_cnt += 1 # sch两次done后停止req

            extra_fields = {
                "qos_en": self._q[slot_vq_id].qos_en,
                "qos_ok": self._q[slot_vq_id].qos_ok,
                "qos_flag": self._q[slot_vq_id].qos_flag,
                "expected_cold": self._q[slot_vq_id].expected_cold,
                "expected_done": self._q[slot_vq_id].expected_done,
                "slot_rsp_err_info":self._q[slot_vq_id].slot_rsp_err_info,
                "blk_desc_done_cnt":self._q[slot_vq_id].blk_desc_done_cnt,
                "slot_stopping_cnt":self._q[slot_vq_id].slot_stopping_cnt,
                "slot_local_empty_cnt":self._q[slot_vq_id].slot_local_empty_cnt
            }
            self.log_struct(
                title=" //1. Alloc_Slot_Rsp :",
                struct_obj=slot_rsp_obj,
                extra_fields=extra_fields
            )
            if self._q[slot_vq_id].expected_cold == 0 and \
                self._q[slot_vq_id].expected_done == 0 and \
                self._q[slot_vq_id].slot_rsp_err_info == 0 and \
                self._q[slot_vq_id].blk_desc_done_cnt != 0:

                self._slot2blk_queue.put_nowait(slot_vq_id) #发送一次desc
                self._q[slot_vq_id].blk_desc_done_cnt = self._q[slot_vq_id].blk_desc_done_cnt - 1

            if self._q[slot_vq_id].qos_flag :
                if self._q[slot_vq_id].slot_rsp_stat_stopping == 1:
                    self._q[slot_vq_id].slot_stopping_cnt += 1
                    if self._q[slot_vq_id].slot_stopping_cnt == self._q[slot_vq_id].SLOT_RSP_CNT_MAX:
                        self._q[slot_vq_id].slot_rsp_stat_stopping = 0
                        self._q[slot_vq_id].slot_rsp_stat_doing = 1
                elif self._q[slot_vq_id].slot_rsp_stat_stopping == 0 and \
                    self._q[slot_vq_id].slot_rsp_stat_doing == 1 and \
                    self._q[slot_vq_id].slot_rsp_local_empty == 1 :
                    self._q[slot_vq_id].slot_local_empty_cnt += 1
                    if self._q[slot_vq_id].slot_local_empty_cnt == self._q[slot_vq_id].SLOT_RSP_CNT_MAX:
                        self._q[slot_vq_id].slot_rsp_local_empty = 0
                elif self._q[slot_vq_id].slot_rsp_stat_stopping == 0 and \
                    self._q[slot_vq_id].slot_rsp_stat_doing == 1 and \
                    self._q[slot_vq_id].slot_rsp_local_empty == 0 and \
                    self._q[slot_vq_id].slot_rsp_avail_empty == 0 :
                        if self._q[slot_vq_id].slot_rsp_err_info != 0:
                            if random.random() < self._SLOT_DONE :
                                self._q[slot_vq_id].slot_rsp_stat_doing = 0
                            else :
                                self._q[slot_vq_id].slot_rsp_local_empty = 1
                                self._q[slot_vq_id].slot_rsp_avail_empty = 1
                        else:
                            if self._q[slot_vq_id].blk_desc_done_cnt == 0:
                                if random.random() < self._SLOT_DONE :
                                    self._q[slot_vq_id].slot_rsp_stat_doing = 0
                                else :
                                    self._q[slot_vq_id].slot_rsp_local_empty = 1
                                    self._q[slot_vq_id].slot_rsp_avail_empty = 1

    async def blk_desc_process(self):
        while True:
            blk_qid = await self._slot2blk_queue.get()
            queue = self._q[blk_qid]
            if not queue.pending_blk_desc:
                self.log.error(f"qid={blk_qid} don't have desc_group")
                continue

            current_group = queue.pending_blk_desc.popleft()
            pending_dma_err_len = len(queue.pending_dma_err)
            current_group_err_cnt = current_group.group_dma_err_cnt
            special_fields = {"vq_typ": lambda x: f"type: {VirtioQidType(x).name}"}
            self.log_struct(
                title=f"//2.1 Blk_Desc_Sbd (qid={blk_qid} "
                    f"group={current_group.group_index}),"
                    f"current_group_dma_err_cnt={current_group_err_cnt}, "
                    f" pending_dma_err_len={pending_dma_err_len}",
                struct_obj=current_group.sbd_obj,
                special_fields=special_fields,
            )
            if current_group.sbd_obj.err_info != 0:
                self.blk_desc_err_cnt += 1
            for desc in current_group.descs:
                obj = self.blk_desc_rsp._transaction_obj()
                obj.sbd = current_group.sbd_packed
                obj.dat = desc.packed
                obj.sop = desc.sop
                obj.eop = desc.eop
                await self.blk_desc_rsp.send(obj)
                self.blk_desc_cnt += 1

                dma_blocks = desc.dma_blocks  
                block_count = desc.block_count 
                dma_block_details = []
                for blk in dma_blocks:
                    dma_block_details.append(f"block[{blk.dma_index}]: err={blk.dma_err}")
                if not dma_block_details:
                    dma_block_details.append("no dma blocks (non-read operation)")

                extra_fields = {
                    "sop": desc.sop,
                    "eop": desc.eop,
                    "desc_index": desc.desc_index,
                    "group_index": current_group.group_index,
                    "dma_block_count": block_count,
                    "dma_block_errors": "; ".join(dma_block_details)
                }
                
                self.log_struct(
                    title=f"//2.2 Blk_Desc_Dat (qid={blk_qid} group{current_group.group_index} desc{desc.desc_index}) :",
                    struct_obj=desc.virt_desc,
                    extra_fields=extra_fields
                )

    async def qos_update_process(self):
        while True:
            qos_update_req = await self.update_req.recv()
            qos_up_qid = int(qos_update_req.uid)
            self._q[qos_up_qid].qos_act_update_cnt += 1
            if self._q[qos_up_qid].qos_exp_update_cnt == self._q[qos_up_qid].qos_act_update_cnt:
                self._q[qos_up_qid].qos_update_done = True

            queue = self._q[qos_up_qid]
            if not queue.pending_qos_update:
                self.log.error(f"qos_update_process: qid={qos_up_qid} don't have qos_group list")
                continue
            
            current_group = queue.pending_qos_update.popleft()
            sbd_tot_len = current_group.sbd_total_len
            pkt_num = current_group.pkt_num

            if sbd_tot_len != int(qos_update_req.len):
                self.log.error(
                    f"qos update req len doesn't match! Expected: {sbd_tot_len}, Actual: {int(qos_update_req.len)}, QID: {qos_up_qid}"
                )
                assert (sbd_tot_len) == int(qos_update_req.len), \
                    f"qos update req len doesn't match! Expected: {sbd_tot_len}, Actual: {int(qos_update_req.len)}, QID: {qos_up_qid}"
            if pkt_num != int(qos_update_req.pkt_num):
                self.log.error(
                    f"qos update req pkt_num doesn't match! Expected: {pkt_num}, Actual: {int(qos_update_req.pkt_num)}, QID: {qos_up_qid}"
                )
                assert pkt_num == int(qos_update_req.pkt_num), \
                    f"qos update req pkt_num doesn't match! Expected: {pkt_num}, Actual: {int(qos_update_req.pkt_num)}, QID: {qos_up_qid}"

    async def blk2beq_process(self):#shutdown模式只是没有dma读数据
        while True:
            beq_rsp = await self.beq_rxq.recv()
            user0 = beq_rsp.user0
            beq_user0_qid = user0 & 0xFFFF  #user0[15:0]:  qid
            beq_host_gen = (user0 >> 16) & 0xFF  # user0[23:16]:  host_gen
            beq_start_of_io = (user0 >> 24) & 1 != 0  # user0[24]: start of io
            beq_end_of_io = (user0 >> 25) & 1 != 0 # user0[25]: end of io
            beq_forced_shutdown = (user0 >> 26) & 1 # user0[26]:forced_shutdown
            beq_err_code = (user0 >> 32) & 0xFF  # user0[39:32]:err_code

            self.beq_rxq_cnt += 1
            if beq_start_of_io: # hdr
                self.buffer_hdr2beq_cnt += 1
                header_bytes = beq_rsp.data[:64][::-1]
                header_int = int.from_bytes(header_bytes, byteorder='big')
                buffer_hdr = BufferHeader().unpack(header_int)
                
                beq_qid = buffer_hdr.vq_gid & 0xFF
                #1. qid
                if beq_qid != beq_user0_qid:
                    self.log.error(
                        f"HDR QID mismatch! QID from buffer_hdr: {beq_qid}, QID from user0: {beq_user0_qid}"
                    )
                    assert beq_qid == beq_user0_qid, "HDR QID mismatch between buffer_hdr and user0"

                current_queue = self._q[beq_qid]
                if not current_queue.pending_beq:
                    self.log.error(f"blk2beq_process: qid={beq_qid} don't have beq group")
                    continue
                
                buffer_header_obj, chain_index, group_index, desc_index, desc_write_flag = current_queue.pending_beq.popleft()
                #2.gen
                if current_queue.slot_rsp_err_info == 0: 
                    if beq_host_gen != current_queue.gen:
                        self.log.error(
                            f"HDR Gen mismatch! QID: {beq_user0_qid}, chain: {chain_index}, desc: {desc_index}, "
                            f"Expected gen: {current_queue.gen}, Actual gen from user0: {beq_host_gen}"
                        )
                        assert beq_host_gen == current_queue.gen, "HDR Gen mismatch between queue and user0"
                else:  
                    self.log.debug(
                        f"HDR Gen check skipped! QID: {beq_user0_qid}, chain: {chain_index}, desc: {desc_index}, "
                        f"Reason: slot_rsp_err_info={current_queue.slot_rsp_err_info}≠0 (has slot error)"
                    )

                #3.shutdown
                expected_forced_shutdown = current_queue.desc_shutdown
                if (not current_queue.ctx_shutdown_mode) and (current_queue.slot_rsp_err_info == 0):
                    if beq_forced_shutdown != expected_forced_shutdown:
                        self.log.error(
                            f"HDR forced_shutdown mismatch! QID: {beq_qid}, chain: {chain_index}, desc: {desc_index}, "
                            f"ctx_shutdown_mode: {current_queue.ctx_shutdown_mode}, desc_shutdown: {current_queue.desc_shutdown}, "
                            f"Expected forced_shutdown: {expected_forced_shutdown}, Actual: {beq_forced_shutdown}"
                        )
                        assert beq_forced_shutdown == expected_forced_shutdown, "HDR forced_shutdown mismatch"
                #4.err info
                if current_queue.slot_rsp_err_info != 0:
                    expected_err_code = current_queue.slot_rsp_err_info
                elif current_queue.desc_err != 0:
                    expected_err_code = current_queue.desc_err
                else:
                    expected_err_code = 0
                if beq_err_code != expected_err_code:
                    self.log.error(
                        f"HDR err_code mismatch! QID: {beq_qid}, chain: {chain_index}, desc: {desc_index}, "
                        f"slot_rsp_err_info: {current_queue.slot_rsp_err_info}, desc_err: {current_queue.desc_err}, "
                        f"Expected err_code: {expected_err_code}, Actual: {beq_err_code}"
                    )
                    assert beq_err_code == expected_err_code, "HDR err_code mismatch"
                #5.ctx_shutdown del dam data
                if beq_forced_shutdown and (current_queue.desc_shutdown == 0) and (desc_write_flag == 0):
                    remaining_dma = deque()
                    deleted_count = 0 
                    while current_queue.pending_dma_data:
                        dma_item = current_queue.pending_dma_data.popleft()
                        item_chain_idx, item_group_idx, item_desc_idx = dma_item[0], dma_item[1], dma_item[2]
                        if item_chain_idx == chain_index and item_group_idx == group_index and item_desc_idx == desc_index:
                            deleted_count += 1
                            continue
                        remaining_dma.append(dma_item)
                    current_queue.pending_dma_data = remaining_dma
                    self.log.debug(
                        f"ctx_shutdown (HDR stage): "
                        f"qid={beq_qid}, chain={chain_index}, group={group_index}, desc={desc_index},"
                        f"deleted {deleted_count} DMA data items (matched chain+desc), "
                        f"remaining {len(remaining_dma)} items in pending_dma_data"
                    )

                fields_info = []
                for field in buffer_hdr.fields_desc:
                    field_name = field.name
                    if field_name.startswith("_"):
                        continue 
                    field_value = getattr(buffer_hdr, field_name, None) 
                    if isinstance(field_value, int):
                        fields_info.append(f"{field_name}: {field_value} (0x{field_value:0X})")
                    else:
                        fields_info.append(f"{field_name}: {field_value}")
                buffer_hdr_str = "BufferHeader(\n  " + ",\n  ".join(fields_info) + "\n)"
                self.log.debug(
                    f"blk2beq_process HDR: qid={beq_qid}, chain={chain_index}, desc={desc_index}, "
                    f"buffer_hdr={buffer_hdr_str}"
                )
                
                hdr_extra = {
                    "QID": beq_qid,
                    "ChainIndex": chain_index,
                    "GroupIndex": group_index,
                    "DescIndex": desc_index,
                    "vq_gid": buffer_hdr.vq_gid,
                    "QueueGen": current_queue.gen,
                    "User0Gen": beq_host_gen,
                    "ForcedShutdown(Expected)": expected_forced_shutdown,
                    "ForcedShutdown(Actual)": beq_forced_shutdown,
                    "ErrCode(Expected)": expected_err_code,
                    "ErrCode(Actual)": beq_err_code,
                    "slot_rsp_err_info": current_queue.slot_rsp_err_info,
                    "desc_err": current_queue.desc_err,
                    "desc_shutdown": current_queue.desc_shutdown,
                    "ctx_shutdown_mode": current_queue.ctx_shutdown_mode
                }
                expected_err = 0
                if current_queue.slot_rsp_err_info != 0:
                    expected_err = current_queue.slot_rsp_err_info
                elif current_queue.desc_err != 0:
                    expected_err = current_queue.desc_err
                
                expected_ctrl = 1 if current_queue.desc_shutdown != 0  else 0

                base_compare_fields = ["vq_gid", "magic_num"]
                extended_compare_fields = base_compare_fields + ["vq_gen"]
                if current_queue.slot_rsp_err_info != 0:
                    compare_fields = base_compare_fields
                    err_msg = "beq buffer hdr (slot error state) fields don't match (check vq_gid/magic_num)"
                    self.log.debug(f"slot_rsp_err_info != 0 (QID: {beq_qid}), compare base fields")
                elif current_queue.desc_err != 0 or current_queue.desc_shutdown != 0:
                    compare_fields = extended_compare_fields
                    err_msg = "beq buffer hdr (desc error/shutdown state) fields don't match (check vq_gid/magic_num)"
                    self.log.debug(f"desc_err != 0 (QID: {beq_qid}), compare base fields")
                else:
                    compare_fields = None
                    err_msg = "beq buffer hdr (normal state) fields don't match (check all key fields)"
                    self.log.debug(f"normal state (QID: {beq_qid}), compare all fields")

                self.log_struct(
                    title=f"// Beq HDR Check (chain={chain_index}, desc={desc_index}): All Fields",
                    extra_fields=hdr_extra,
                    is_assert=True,
                    expected=buffer_header_obj,
                    actual=buffer_hdr,
                    err_msg=err_msg,
                    compare_fields=compare_fields
                )
            else: # dma data
                beq_qid = beq_user0_qid
                current_queue = self._q[beq_qid]
                if not current_queue.pending_dma_data:
                    self.log.error(f"blk2beq_process: qid={beq_qid} don't have pending_dma_data")
                    continue
                
                if beq_host_gen != current_queue.gen:
                    self.log.error(
                        f"DATA Gen mismatch! QID: {beq_qid}, chain: {current_queue.chain_index}, "
                        f"Expected gen: {current_queue.gen}, Actual gen from user0: {beq_host_gen}"
                    )
                    assert beq_host_gen == current_queue.gen, "DATA Gen mismatch between queue and user0"
            
                if beq_forced_shutdown:
                    expected_data = b'\x00' * 64
                    actual_data = beq_rsp.data
                    actual_len = len(actual_data)

                    data_extra = {
                        "QID": beq_qid,
                        "CtxShutdown": True,
                        "Expected_Data_Len": 64,
                        "Actual_Data_Len": actual_len
                    }
                    self.log_struct(
                        title=" // Beq Data Check (ctx_shutdown): Length",
                        extra_fields=data_extra,
                        is_assert=True,
                        expected=64,
                        actual=actual_len,
                        err_msg="ctx_shutdown DMA data length doesn't match (expected 64 bytes)"
                    )

                    if actual_data != expected_data:
                        self.log.error(
                            f"ctx_shutdown DMA data content error! QID: {beq_qid}, "
                            f"Expected: all 0x00, Actual: {actual_data.hex()[:32]}..."
                        )

                    if current_queue.pending_dma_data:
                        first_item = current_queue.pending_dma_data[0]
                        target_chain_idx, target_group_idx, target_desc_idx = first_item[0], first_item[1], first_item[2]
                        remaining_dma = deque()
                        while current_queue.pending_dma_data:
                            dma_item = current_queue.pending_dma_data.popleft()
                            item_chain_idx, item_group_idx, item_desc_idx = dma_item[0], dma_item[1], dma_item[2]
                            if item_chain_idx == target_chain_idx and item_group_idx == target_group_idx and item_desc_idx == target_desc_idx:
                                continue
                            remaining_dma.append(dma_item)
                        current_queue.pending_dma_data = remaining_dma
                        self.log.debug(f"ctx_shutdown (Data stage): qid={beq_qid}, chain={target_chain_idx}, group={target_group_idx}, desc={target_desc_idx}, popped remaining DMA data")
                else:
                    self.dma_data2beq_cnt  += 1
                    dma_item = current_queue.pending_dma_data.popleft()
                    chain_index, group_index, desc_index, block_data, block_length, dma_rd_err, dma_index = dma_item
                    if dma_rd_err != 0:
                        self.dma_rd_rsp_err_cnt += 1
                    actual_data = beq_rsp.data
                    actual_len = len(actual_data)

                    data_extra = {
                        "QID": beq_qid,
                        "ChainIndex": chain_index,
                        "GroupIndex": group_index, 
                        "DescIndex": desc_index,
                        "DMAIndex": dma_index,
                        "Expected_Data_Len": block_length,
                        "Actual_Data_Len": actual_len
                    }

                    self.log_struct(
                        title=f" // Beq Data Check (chain={chain_index}, group={group_index}, desc={desc_index}, dma={dma_index}): Length",
                        extra_fields=data_extra,
                        is_assert=True,
                        expected=block_length,
                        actual=actual_len,
                        err_msg="normal DMA data length doesn't match"
                    )

                    if len(block_data) == actual_len and block_data is not None:
                        self.log_struct(
                            title=f" // Beq Data Check (chain={chain_index}, group={group_index}, desc={desc_index}, dma={dma_index}): Content",
                            extra_fields=data_extra,
                            is_assert=True,
                            expected=block_data.hex()[:32],
                            actual=actual_data.hex()[:32],
                            err_msg="normal DMA data content doesn't match"
                        )

    async def check_stop(self):
        while True:
            await Timer(5000, 'ns')
            current_qids = list(self._q.keys())
            if not current_qids:
                self.log.debug(f"No queues exist yet, wait 5000ns and retry")
                await Timer(5000, 'ns')
                continue 

            has_satisfied_queue = False

            for qid in current_qids:
                if qid not in self._q:
                    continue
                
                queue = self._q[qid]
                buf_hdr_list_len = len(queue.pending_beq)
                test_data_list_len = len(queue.pending_dma_data)
                expected_cold = queue.expected_cold
                expected_done = queue.expected_done
                qos_update_done = queue.qos_update_done
                slot_done_cnt = queue.slot_done_cnt

                is_satisfied = (
                    buf_hdr_list_len == 0 and
                    test_data_list_len == 0 and
                    expected_cold == 0 and
                    expected_done == 1 and
                    qos_update_done and 
                    slot_done_cnt >= 2
                )

                self.log.debug(
                    f"Queue {qid} current delete conditions: "
                    f"buf_hdr_list_len={buf_hdr_list_len}, "
                    f"test_data_list_len={test_data_list_len}, "
                    f"expected_cold={expected_cold}, "
                    f"expected_done={expected_done}, "
                    f"qos_update_done={qos_update_done} "
                    f"slot_done_cnt={slot_done_cnt} "
                    f"is_satisfied is {is_satisfied}"
                )

                if is_satisfied:
                    has_satisfied_queue = True
                    self.log.debug(f"The queue {qid} is ready to delete")
                    actual_chain_cnt = len(queue.chains)
                    if queue.slot_rsp_err_info != 0 or queue.desc_shutdown != 0 or queue.desc_err != 0 :
                        if (queue.blk_ptr_dat_bak + actual_chain_cnt) % 0x10000 != queue.blk_ptr_dat:
                            self.log.error(f"The queue {qid} ptr err check failed, blk_ptr_dat_bak is {queue.blk_ptr_dat_bak}, blk_ptr_dat is {queue.blk_ptr_dat}, actual_chain_cnt={actual_chain_cnt}")
                    else:
                        if queue.blk_ptr_dat_bak + actual_chain_cnt != queue.blk_ptr_dat:
                            self.log.error(f"The queue {qid} ptr no_err and next check failed, blk_ptr_dat_bak is {queue.blk_ptr_dat_bak}, blk_ptr_dat is {queue.blk_ptr_dat}, , actual_chain_cnt={actual_chain_cnt}")

                    await Timer(5000, 'ns')
                    del self._q[qid]
                    self.seq += 1
                    self.available_qids.put_nowait(qid)
                    self.qid_available_event.set()
                    self.log.info(f"Queue {qid} deleted, max_seq is {self.max_seq}, seq is {self.seq}")
                    
                    if not self._q:
                        self.log.debug("All queues processed, trigger stop event")
                        self.all_queues_stopped.set()
                        return
            
            if not has_satisfied_queue:
                self.log.debug(f"All existing queues don't meet delete condition, wait 5000ns and retry")
                await Timer(5000, 'ns')
                    
    async def set_queue(self, cfg, typ, ctx_shutdown_mode, err_shutdown_mode, dma_err_mode):
        while self.available_qids.empty():
            self.log.debug("The available qid has been exhausted, waiting for recycling...")
            await self.qid_available_event.wait()
            self.qid_available_event.clear()
        
        qid = await self.available_qids.get()
        self._q[qid] = vQueue(cfg, self.mem, qid, typ, ctx_shutdown_mode, err_shutdown_mode, dma_err_mode)
        await self._q[qid].gen_chain()
        await self._local_qid_queue.put(qid)

