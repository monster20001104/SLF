import sys
import time
import random

from types import SimpleNamespace
from typing import List, Dict, Tuple

import logging
from logging import Logger
from logging.handlers import RotatingFileHandler


import cocotb
from cocotb.queue import Queue
from cocotb.log import SimLog, SimLogFormatter
from cocotb.handle import HierarchyObject
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.regression import TestFactory


sys.path.append('../../common')
from address_space import Pool, MemoryRegion
from bus.tlp_adap_dma_bus import DmaWriteBus, DmaReadBus
from generate_eth_pkg import generate_eth_pkt

from test_cfg import *
from test_func import cycle_pause, ResourceAllocator, randbit
from test_define import *
from test_interfaces import *
from ram_tbl import RamTblTransaction

class TB(object):
    def __init__(self, cfg: Cfg, dut: HierarchyObject, qid_list: List[int]):
        self.dut: HierarchyObject = dut  
        self.cfg: Cfg = cfg
        self.qid_list: List[int] = qid_list
        cocotb.start_soon(Clock(dut.clk, CLOCK_FREQ, units="ns").start()) 
        self._init_mem()
        self._log_init()
        self._init_interfaces()
        cocotb.start_soon(self.__slot_req_process())
        cocotb.start_soon(self.__slot_rsp_process())
        cocotb.start_soon(self.__nettx_desc_rsp_process())
        cocotb.start_soon(self.__qos_query_process())
        cocotb.start_soon(self.__qos_update_process())
        cocotb.start_soon(self.__net2tso_process())


    def _log_init(self) -> None:
        self.log: Logger = logging.getLogger("cocotb.tb") 
        self.log.setLevel(LOG_LEVEL) 

    def _init_interfaces(self) -> None:
        dut = self.dut
        clk = self.dut.clk
        rst = self.dut.rst
        self.interfaces: Interfaces = Interfaces()  
        self.interfaces.sch_req_if = SchReqSource(SchReqBus.from_prefix(dut, "sch_req"), clk, rst)
        self.interfaces.nettx_alloc_slot_req_if = SlotReqSink(SlotReqBus.from_prefix(dut, "nettx_alloc_slot_req"), clk, rst)
        self.interfaces.nettx_alloc_slot_rsp_if = SlotRspSource(SlotRspBus.from_prefix(dut, "nettx_alloc_slot_rsp"), clk, rst)
        self.interfaces.slot_ctrl_ctx_if = SlotCtxTbl(
            SlotCtxReqBus.from_prefix(dut, "slot_ctrl_ctx_info_rd"),
            SlotCtxRspBus.from_prefix(dut, "slot_ctrl_ctx_info_rd"),
            None, clk, rst
        )
        self.interfaces.slot_ctrl_ctx_if.set_callback(self.__slot_ctx_cb)
        self.interfaces.qos_query_req_if = QosQueryReqSink(QosQueryReqBus.from_prefix(dut, "qos_query_req"), clk, rst)
        self.interfaces.qos_query_rsp_if = QosQueryRspSource(QosQueryRspBus.from_prefix(dut, "qos_query_rsp"), clk, rst)
        self.interfaces.qos_update_if = QosUpdateSink(QosUpdateBus.from_prefix(dut, "qos_update"), clk, rst)
        self.interfaces.nettx_desc_rsp_if = NettxDescSource(NettxDescBus.from_prefix(dut, "nettx_desc_rsp"), clk, rst)
        self.interfaces.rd_data_ctx_if = RdDataCtxTbl(
            RdDataCtxReqBus.from_prefix(dut, "rd_data_ctx_info_rd"),
            RdDataCtxRspBus.from_prefix(dut, "rd_data_ctx_info_rd"),
            None, clk, rst
        )
        self.interfaces.rd_data_ctx_if.set_callback(self.__rd_data_ctx_cb)
        self.interfaces.net2tso_if = Net2TsoSink(Net2TsoBus.from_prefix(dut, "net2tso"), clk, rst)
        self.interfaces.used_info_if = UsedInfoSink(UsedInfoBus.from_prefix(dut, "used_info"), clk, rst)
        self.interfaces.dma_if = DmaRam(None,DmaReadBus.from_prefix(dut, "dma"), clk, rst, mem=self.mem)


    def _init_mem(self) -> None:
        self.mem = Pool(None, 0, size=2**64, min_alloc=64)
        self.virtio_head_len: int = 12
        self.sent_num = 0
        self.pass_num = 0
        self.drop_num = 0 

        self.driver_pending_queue: Dict[int, Queue] = {} 
        self.slot_req_queue = Queue(maxsize=32)  
        self.desc_pending_queue: Dict[int, Queue] = {}   
        self.scoreboard_queue: Dict[int, Queue] = {}              
        self.ctx_read_queue: Dict[int, Queue] = {}  
        self.ctx_read_bytes: Dict[int, int] = {}    
        self.pending_used_queue: Dict[int, Queue] = {} 
        
        self.mem_idx: Dict[int, ResourceAllocator] = {}     
        self.dev_id_ram: Dict[int, int] = {}
        self.bdf_ram: Dict[int, int] = {}
        self.qos_unit_ram: Dict[int, int] = {}
        self.qos_enable_ram: Dict[int, int] = {}

        self.avail_idx_cnt: Dict[int, int] = {}
        self.virtq_forced_shutdown: Dict[int, int] = {}
        self.slot_used_num = 0
        
        for qid in self.qid_list:
            self.driver_pending_queue[qid] = Queue()
            self.desc_pending_queue[qid] = Queue()
            self.scoreboard_queue[qid] = Queue()
            self.ctx_read_queue[qid] = Queue()
            self.ctx_read_bytes[qid] = 0
            self.pending_used_queue[qid] = Queue()
            self.mem_idx[qid] = ResourceAllocator(0, 2**16 - 1)
            self.avail_idx_cnt[qid] = 0
            self.dev_id_ram[qid] = qid  
            self.bdf_ram[qid] = qid     
            self.qos_unit_ram[qid] = qid
            self.qos_enable_ram[qid] = 1 if random.random() < self.cfg.random_qos else 0
            self.virtq_forced_shutdown[qid] = 0
            
    async def cycle_reset(self) -> None:
        clk = self.dut.clk
        rst = self.dut.rst
        rst.setimmediatevalue(0)
        await RisingEdge(clk)
        await RisingEdge(clk)
        rst.value = 1
        await RisingEdge(clk)
        await Timer(1, "us")
        await RisingEdge(clk)
        rst.value = 0
        await RisingEdge(clk)
        await RisingEdge(clk)
        await Timer(2, "us")

    async def _gen_pkt_process(self):
        while self.sent_num < self.cfg.seq_num * self.cfg.q_num:
            qid = random.choice(self.qid_list)
            
            if random.random() <= self.cfg.tlp_err:
                err_type = 'tlp_err'
            else:
                err_type = 'no_err'

            virtio_hdr = bytes([0] * self.virtio_head_len) 
            pkt_len = random.randint(self.cfg.eth_pkt_len_min, self.cfg.eth_pkt_len_max)
            eth_payload = bytes([random.randint(0, 255) for _ in range(pkt_len)])
            full_data = virtio_hdr + eth_payload 
            total_len = len(full_data)
            
            desc_cnt = random.randint(self.cfg.min_desc_cnt, self.cfg.max_desc_cnt)
            desc_len_list = []
            remaining_len = total_len
            for i in range(desc_cnt - 1):
                max_len = remaining_len - (desc_cnt - 1 - i)
                curr_len = random.randint(1, max_len) if max_len >= 1 else 1
                desc_len_list.append(curr_len)
                remaining_len -= curr_len
            desc_len_list.append(remaining_len)
            
            mem_regions = []
            desc_chain = []
            current_offset = 0
            
            for i in range(desc_cnt):
                d_len = desc_len_list[i]
                mem = self.mem.alloc_region(d_len, bdf=self.bdf_ram[qid], dev_id=self.dev_id_ram[qid])
                if err_type == 'tlp_err':
                    await mem.write(0, full_data[current_offset : current_offset + d_len], defect_injection=1)
                else:
                    await mem.write(0, full_data[current_offset : current_offset + d_len])
                current_offset += d_len
                
                desc_info = SimpleNamespace()
                desc_info.addr = mem.get_absolute_address(0)
                desc_info.len = d_len
                desc_info.next = 0 
                desc_info.flags_next = 1 if i < desc_cnt - 1 else 0
                desc_info.flags_write = 0 
                desc_info.flags_indirect = 0
                
                mem_regions.append(mem)        
                desc_chain.append(desc_info)
            
            pkt_info = SimpleNamespace()
            pkt_info.qid = qid
            pkt_info.eth_payload = eth_payload 
            pkt_info.mem_regions = mem_regions 
            pkt_info.desc_chain = desc_chain  
            pkt_info.total_len = total_len
            pkt_info.desc_cnt = desc_cnt
        
            pkt_info.err_type = err_type
            
            self.driver_pending_queue[qid].put_nowait(pkt_info)
            self.sent_num += 1
            
            trans = SchReqTrans(qid=qid)
            await self.interfaces.sch_req_if.send(trans)
            
            await Timer(random.randint(100, 500), "ns")


    async def __slot_req_process(self):
        while True:
            req = await self.interfaces.nettx_alloc_slot_req_if.recv()
            await self.slot_req_queue.put(req)

    async def __slot_rsp_process(self):
        while True:
            req_trans = await self.slot_req_queue.get()
            #  self.log.error(f"req_trans{req_trans}")
            vq = VirtioVq.unpack(req_trans.data)
            qid = vq.qid
            
            if vq.typ != TestType.NETTX:
                raise Exception(f"qid {qid} __slot_rsp_process vq_typ is not nettx is {vq.typ}")
            if req_trans.dev_id != self.dev_id_ram[qid]:
                raise Exception(f"qid {qid} __slot_rsp_process dev_id err act {req_trans.dev_id} exp {self.dev_id_ram[qid]}")
            
            has_pkt = not self.driver_pending_queue[qid].empty()

            rsp_data = Nettx_Alloc_Slot_Rsp_Data()
            rsp_data.vq = vq.pack()
            rsp_data.pkt_id = 0
            
            # default
            rsp_data.ok = 0
            rsp_data.local_ring_empty = 0
            rsp_data.avail_ring_empty = 0
            rsp_data.q_stat_doing = 1
            rsp_data.q_stat_stopping = 0
            rsp_data.desc_engine_limit = 0
            rsp_data.err_info = 0
            
            alloc_success = False

            if random.random() <= self.cfg.alloc_slot_err:
                fail_type = random.randint(0, 4)
                if fail_type == 0: # Engine Limit 
                    rsp_data.desc_engine_limit = 1
                elif fail_type == 1: # Local Ring Empty 
                    rsp_data.local_ring_empty = 1
                    rsp_data.avail_ring_empty = 0
                elif fail_type == 2: # Queue Stopping
                    rsp_data.q_stat_stopping = 1
                    rsp_data.q_stat_doing = 0
                elif fail_type == 3: # local and avail empty
                    rsp_data.local_ring_empty = 1
                    rsp_data.avail_ring_empty = 1
                elif fail_type == 4: # Error
                    rsp_data.err_info = 0x80 | random.choice(idx_avail_errcode_list)
            
            # 正常逻辑
            elif has_pkt:
                # 申请成功
                rsp_data.ok = 1
                alloc_success = True 
            else:
                # 队列为空或未启动 (Done)
                # 随机覆盖两种触发 Done 的条件，以验证 RTL 逻辑
                if random.choice([True, False]):
                    # 情况1: 队列运行中，但没有数据了
                    rsp_data.local_ring_empty = 1
                    rsp_data.avail_ring_empty = 1
                else:
                    # 情况2: 队列处于 IDLE/Disabled 状态 (doing=0, stopping=0)
                    rsp_data.q_stat_doing = 0
                    rsp_data.q_stat_stopping = 0
            
            # 发送响应
            rsp_trans = SlotRspTrans()
            rsp_trans.data = rsp_data.pack()
            await self.interfaces.nettx_alloc_slot_rsp_if.send(rsp_trans)
            
            is_done = (rsp_data.local_ring_empty == 1 and rsp_data.avail_ring_empty == 1 and rsp_data.q_stat_doing == 1) or \
                    (rsp_data.q_stat_doing == 0 and rsp_data.q_stat_stopping == 0)
            

            if alloc_success: 
                pkt_info = self.driver_pending_queue[qid].get_nowait()
                self.desc_pending_queue[qid].put_nowait(pkt_info)
                self.slot_used_num += 1 
            elif rsp_data.err_info != 0:
                if has_pkt:
                    _ = self.driver_pending_queue[qid].get_nowait()
                    self.drop_num += 1
                    self.log.info(f"QID {qid} Slot Alloc Fatal Error {hex(rsp_data.err_info)}. Dropping packet.")
                elif has_pkt and is_done:
                    self.log.info(f"QID {qid} Injected False DONE while has_pkt. Re-ringing doorbell.")
                    sch_trans = SchReqTrans(qid=qid)
                    await self.interfaces.sch_req_if.send(sch_trans)

    async def __nettx_desc_rsp_process(self):
        while True:
            active_qids = [q for q in self.qid_list if not self.desc_pending_queue[q].empty()]
            if not active_qids:
                await Timer(10, "ns")
                continue

            qid = random.choice(active_qids)
            info = self.desc_pending_queue[qid].get_nowait()
            
            ring_id = self.mem_idx[qid].alloc_id()
            avail_idx = self.avail_idx_cnt[qid]
            self.avail_idx_cnt[qid] = (self.avail_idx_cnt[qid] + 1) % 65536
            
            info.expected_ring_id = ring_id
            info.expected_avail_idx = avail_idx
            
            # 如果生成阶段没有注入TLP错误，则在此处根据配置注入描述符返回阶段的错误
            if info.err_type == 'no_err':
                info.err_type = random.choices(
                    population=list(err_type_list.keys()),
                    weights=list(err_type_list.values()),
                    k=1,
                )[0]
            
            self.scoreboard_queue[qid].put_nowait(info)

            sbd = VirioRspSbd()
            sbd.vq = VirtioVq(typ=TestType.NETTX, qid=qid).pack()
            sbd.dev_id = self.dev_id_ram[qid]
            sbd.pkt_id = 0 
            sbd.total_buf_length = info.total_len
            sbd.valid_desc_cnt = info.desc_cnt
            sbd.ring_id = ring_id
            sbd.avail_idx = avail_idx
            sbd.forced_shutdown = self.virtq_forced_shutdown[qid]
            sbd.err_info = 0
            
            info.early_drop = False
            push_to_ctx_queue = True

            if info.err_type == 'forced_shutdown':

             if random.random() >0.5:  #增加概率
                err_type = random.choices(
                population=list(err_type_list.keys()),
                weights=list(err_type_list.values()),
                k=1,
            )[0]
                sbd.forced_shutdown = randbit(1)
                if sbd.forced_shutdown == 1:
                    self.log.info(f"QID {qid} Injecting Early Forced Shutdown (SBD=1) for RingID {ring_id}")
                    info.early_drop = True
                    push_to_ctx_queue = False # RTL 在入口丢弃，不发 Context Read
                else:
                    self.log.info(f"QID {qid} Injecting Late Forced Shutdown (SBD=0 -> CTX=1) for RingID {ring_id}")
                    push_to_ctx_queue = True  # RTL 会发 Context Read，我们需要在那里拦截
            elif info.err_type == 'desc_rsp_err':
                sbd.err_info = 0x80 | randbit(7, False) 
                self.log.info(f"QID {qid} Injecting Desc Engine Error for RingID {ring_id} Code {hex(sbd.err_info)}")
                info.early_drop = True
                push_to_ctx_queue = False
            if push_to_ctx_queue:
                self.ctx_read_queue[qid].put_nowait(info)

            for i, desc_data in enumerate(info.desc_chain):
                rtl_desc = VirioRspData()
                rtl_desc.addr = desc_data.addr
                rtl_desc.len = desc_data.len
                rtl_desc.next = desc_data.next
                rtl_desc.flag_next = desc_data.flags_next
                rtl_desc.flag_write = desc_data.flags_write
                rtl_desc.flag_indirect = desc_data.flags_indirect
                rtl_desc.flag_rsv = 0
                
                trans = NettxDescTrans()
                trans.sop = 1 if i == 0 else 0
                trans.eop = 1 if i == info.desc_cnt - 1 else 0
                trans.sbd = sbd.pack()
                trans.data = rtl_desc.pack()
                await self.interfaces.nettx_desc_rsp_if.send(trans)

    def __slot_ctx_cb(self, req_tran) -> RamTblTransaction:
        vq = VirtioVq.unpack(req_tran.req_qid)
        qid = vq.qid
        
        if vq.typ != TestType.NETTX:
            raise Exception(f"qid {qid} __slot_ctx_cb vq_typ is not nettx is {vq.typ}")
            
        rsp = SlotCtxRspTrans()
        rsp.rsp_dev_id = self.dev_id_ram[qid]
        rsp.rsp_qos_unit = self.qos_unit_ram[qid]
        rsp.rsp_qos_enable = self.qos_enable_ram[qid]
        return rsp

    def __rd_data_ctx_cb(self, req_tran) -> RamTblTransaction:
        vq = VirtioVq.unpack(req_tran.req_qid)
        qid = vq.qid
        
        if vq.typ != TestType.NETTX:
            raise Exception(f"qid {qid} __rd_data_ctx_cb vq_typ is not nettx is {vq.typ}")
        # 这里可以加一条校验qid的
            
        rsp = RdDataCtxRspTrans()
        rsp.rsp_bdf = self.bdf_ram[qid]
        is_forced_shutdown = self.virtq_forced_shutdown[qid] 
        
        if not self.ctx_read_queue[qid].empty():
            info = self.ctx_read_queue[qid]._queue[0] 
            if info.err_type == 'forced_shutdown':
                is_forced_shutdown = 1
                self.log.info(f"QID {qid} Context Read: Injecting Forced Shutdown for RingID {info.expected_ring_id}")
                _ = self.ctx_read_queue[qid].get_nowait()
                self.ctx_read_bytes[qid] = 0
            else:
                remaining = info.total_len - self.ctx_read_bytes[qid]
                consumed = 4096 if remaining > 4096 else remaining
                self.ctx_read_bytes[qid] += consumed
                
                if self.ctx_read_bytes[qid] >= info.total_len:
                    _ = self.ctx_read_queue[qid].get_nowait()
                    self.ctx_read_bytes[qid] = 0
                    
        rsp.rsp_forced_shutdown = is_forced_shutdown
        rsp.rsp_qos_enable = self.qos_enable_ram[qid]
        rsp.rsp_qos_unit = self.qos_unit_ram[qid]
        rsp.rsp_tso_en = 0
        rsp.rsp_csum_en = 0
        rsp.rsp_gen = 0
        return rsp

    async def __qos_query_process(self):
        while True:
            req = await self.interfaces.qos_query_req_if.recv()
            
            uid = int(req.uid)
            if uid not in self.qos_unit_ram.values():
                self.log.error(f"QoS Query Req UID {uid} invalid! Valid UIDs: {list(self.qos_unit_ram.values())}")
                raise Exception(f"QoS Query Req UID {uid} invalid")
            
            rsp = QosQueryRspTrans()
            if random.random() < self.cfg.random_qos:
                rsp.data = 1
            else:
                rsp.data = 0
            
            await self.interfaces.qos_query_rsp_if.send(rsp)

    async def __qos_update_process(self):
        while True:
            req = await self.interfaces.qos_update_if.recv()

    async def __net2tso_process(self):
        while True:
            actual_data = bytearray()
            actual_qid = -1
            actual_err = 0 
            
            while True:
                trans = await self.interfaces.net2tso_if.recv()
                
                sop =       int(trans.sop)
                eop =       int(trans.eop)
                sty =       int(trans.sty)
                mty =       int(trans.mty)
                data_int =  int(trans.data)
                qid =       int(trans.qid)
                err =       int(trans.err) 
                
                if sop:
                    actual_qid = qid
                    actual_data = bytearray()
                    actual_err = 0
                    
                if err:
                    actual_err = 1

                data_bytes = data_int.to_bytes(32, 'little')
                
                start_idx = sty if sop else 0
                end_idx = 32 - mty if eop else 32
                
                if start_idx < 32 and end_idx > 0 and start_idx < end_idx:
                     actual_data.extend(data_bytes[start_idx:end_idx])
                    
                if eop:
                    break
            
            if actual_qid == -1:
                self.log.error("Received data transaction without SOP signal asserted.")
                raise Exception("Protocol Error: Missing SOP on net2tso interface")
            
            if actual_qid not in self.scoreboard_queue:
                 raise Exception(f"Received QID {actual_qid} not in scoreboard queues")

            while True:
                if self.scoreboard_queue[actual_qid].empty():
                    raise Exception(f"Scoreboard empty for QID {actual_qid} but received data")
                
                info = self.scoreboard_queue[actual_qid]._queue[0] 
                
                if info.err_type == 'desc_rsp_err' or getattr(info, 'early_drop', False):
                    dropped_info = self.scoreboard_queue[actual_qid].get_nowait() 
                    dropped_info.actual_data_received = False
                    dropped_info.actual_err = 0
                    self.pending_used_queue[actual_qid].put_nowait(dropped_info)
                    self.log.info(f"QID {actual_qid} Skipped Clean Drop packet (RingID {dropped_info.expected_ring_id}, Type {dropped_info.err_type})")
                    continue 
                
                if info.err_type == 'forced_shutdown':
                    if not getattr(info, 'early_drop', False):
                        if actual_err == 1:
                            self.log.info(f"QID {actual_qid} Matched data with TLP Error to Late forced_shutdown packet (RingID {info.expected_ring_id})")
                            info = self.scoreboard_queue[actual_qid].get_nowait()
                            break
                        else:
                            dropped_info = self.scoreboard_queue[actual_qid].get_nowait()
                            dropped_info.actual_data_received = False
                            dropped_info.actual_err = 0
                            self.pending_used_queue[actual_qid].put_nowait(dropped_info)
                            self.log.info(f"QID {actual_qid} Skipped forced_shutdown packet (Assumed Clean Drop, RingID {dropped_info.expected_ring_id})")
                            continue

                # 正常包
                info = self.scoreboard_queue[actual_qid].get_nowait()
                break

            virtio_hdr = bytes([0] * self.virtio_head_len)
            expected_data = virtio_hdr + info.eth_payload

            if info.err_type == 'tlp_err':
                if actual_err != 1:
                    self.log.error(f"QID {actual_qid} RingID {info.expected_ring_id} Expected TLP Error but got None")
                    raise Exception("TLP Error Mismatch") 
                else:
                    self.log.info(f"QID {actual_qid} RingID {info.expected_ring_id} Successfully detected TLP Error")
            elif actual_err == 1:
                if info.err_type == 'forced_shutdown':
                    self.log.info(f"QID {actual_qid} RingID {info.expected_ring_id} TLP Error on forced_shutdown packet (Allowed)")
                else:
                    # 详细打印调试信息
                    self.log.error(f"QID {actual_qid} RingID {info.expected_ring_id} Unexpected TLP Error!")
                    self.log.error(f"Packet Info: Type={info.err_type}, EarlyDrop={getattr(info, 'early_drop', False)}")
                    self.log.error(f"Data Received Len: {len(actual_data)}")
                    self.log.error(f"Data Expected Len: {len(expected_data)}")
                    self.log.error(f"info{info}")
                    raise Exception("Unexpected TLP Error")

            if actual_err == 0 and info.err_type != 'forced_shutdown':
                if actual_data != expected_data:
                    # self.log.error(f"expected_data:{info}")
                    self.log.error(f"Data Mismatch on QID {actual_qid} RingID {info.expected_ring_id}")
                    raise Exception(f"Data Mismatch: Exp len {len(expected_data)} vs Act len {len(actual_data)}")
            
            info.actual_data_received = True
            info.actual_err = actual_err 
            self.pending_used_queue[actual_qid].put_nowait(info)
            self.log.info(f"QID {actual_qid} Net2Tso Verified RingID {info.expected_ring_id} Len {len(actual_data)}")

    async def _used_info_process(self):
        while self.pass_num + self.drop_num < self.cfg.seq_num * self.cfg.q_num:
            trans = await self.interfaces.used_info_if.recv()
            
            used_data = UsedInfoData.unpack(trans.data)
            vq = VirtioVq.unpack(used_data.vq)
            qid = vq.qid
            used_elem_id    = used_data.id
            used_elem_len   = used_data.len
            used_idx        = used_data.used_idx
            err_info        = used_data.err_info
            
            info = None
            if not self.pending_used_queue[qid].empty():
                info = self.pending_used_queue[qid].get_nowait()
            elif not self.scoreboard_queue[qid].empty():
                candidate = self.scoreboard_queue[qid]._queue[0]
                
                is_explicit_drop = candidate.err_type in ['forced_shutdown', 'desc_rsp_err']
                looks_like_drop = (used_elem_len == 0)
                
                if is_explicit_drop:
                    await Timer(1, "ns")
                    
                    info = self.scoreboard_queue[qid].get_nowait()
                    info.actual_data_received = False
                    info.actual_err = 0
                    self.log.info(f"QID {qid} Recovered dropped packet (RingID {info.expected_ring_id}) from Scoreboard. Type: {candidate.err_type}, Len: {used_elem_len}")
                else:
                    self.log.info(f"QID {qid} Waiting for Net2Tso data for RingID {used_elem_id}...")
                    info = await self.pending_used_queue[qid].get()
            else:
                self.log.info(f"QID {qid} Waiting for Net2Tso data (Gap) for RingID {used_elem_id}...")
                info = await self.pending_used_queue[qid].get()
            
            if used_idx != info.expected_avail_idx:
                 self.log.error(f"QID {qid} Used Index Mismatch. Exp {info.expected_avail_idx} Act {used_idx}")
                 raise Exception("Used Info Index Mismatch")

            if used_elem_id != info.expected_ring_id:
                self.log.error(f"QID {qid} RingID Mismatch. Exp {info.expected_ring_id} Act {used_elem_id}")
                raise Exception("Used Info ID Mismatch")

            if info.err_type == 'no_err' and info.actual_err == 0:
                if used_elem_len != info.total_len:
                     self.log.error(f"QID {qid} Len Mismatch. Exp {info.total_len} Act {used_elem_len}")
                     raise Exception("Used Info Len Mismatch")
                self.pass_num += 1 
            else:
                if used_elem_len != 0 and err_info == 0:
                     self.log.warning(f"QID {qid} Error Packet (Type: {info.err_type}) returned non-zero len {used_elem_len} and no error code!")
                
                self.log.info(f"QID {qid} Error Packet Correctly Handled. Type: {info.err_type}")
                self.drop_num += 1 
            for region in info.mem_regions:
                self.mem.free_region(region)
            self.mem_idx[qid].release_id(info.expected_ring_id)
            
    def set_idle_generator(self, generator=None):
        if generator:
            self.interfaces.sch_req_if.set_idle_generator(generator)
            self.interfaces.nettx_alloc_slot_rsp_if.set_idle_generator(generator)
            self.interfaces.qos_query_rsp_if.set_idle_generator(generator)
            self.interfaces.nettx_desc_rsp_if.set_idle_generator(generator)
            self.interfaces.dma_if.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.interfaces.nettx_alloc_slot_req_if.set_backpressure_generator(generator)
            self.interfaces.qos_query_req_if.set_backpressure_generator(generator)
            self.interfaces.qos_update_if.set_backpressure_generator(generator)
            self.interfaces.used_info_if.set_backpressure_generator(generator)
            self.interfaces.net2tso_if.set_backpressure_generator(generator)


async def run_test(dut, cfg: Optional[Cfg] = None, idle_inserter=None, backpressure_inserter=None):
    seed = 1768551146
    random.seed(seed)

    cfg = cfg if cfg is not None else smoke_cfg
    qid_list = random.sample(range(0, 255), cfg.q_num)
    tb = TB(cfg, dut, qid_list)
    tb.log.error(f"Test QIDs:{qid_list}")
    tb.log.info(f"seed: {seed}")

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()

    await Timer(100, "us")
    cocotb.start_soon(tb._gen_pkt_process())
    await cocotb.start_soon(tb._used_info_process()).join()
    await Timer(10, "us")
   
    all_clean = True
    for qid in tb.qid_list:
        if not tb.driver_pending_queue[qid].empty():
            tb.log.error(f"[Fail] QID {qid} driver_pending_queue not empty! (Driver generated but not processed)")
            all_clean = False
        if not tb.desc_pending_queue[qid].empty():
            tb.log.error(f"[Fail] QID {qid} desc_pending_queue not empty! (Slot allocated but desc not sent)")
            all_clean = False
        if not tb.scoreboard_queue[qid].empty():
            tb.log.error(f"[Fail] QID {qid} scoreboard_queue not empty! (Desc sent but not received on Net2Tso)")
            all_clean = False
        if not tb.pending_used_queue[qid].empty():
            tb.log.error(f"[Fail] QID {qid} pending_used_queue not empty! (Received on Net2Tso but not on UsedRing)")
            all_clean = False
            
    if tb.sent_num != tb.pass_num + tb.drop_num:
        raise Exception(f"Packet Count Mismatch! Sent {tb.sent_num} != Pass {tb.pass_num} + Drop {tb.drop_num}")

    if not all_clean:
        raise Exception("Test Failed: Queues are not empty after test completion!")
    else:
        tb.log.info("All queues are clean. Consistency check passed.")
        
    await Timer(1, "us")


if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        # factory.add_option("idle_inserter", [None,cycle_pause])
        # factory.add_option("backpressure_inserter", [None,cycle_pause])
        factory.generate_tests()


root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
    
