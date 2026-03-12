#!/usr/bin/env python3
################################################################################
#  文件名称 : test_virtio_used_tb.py
#  作者名称 : cui naiwan
#  创建日期 : 2025/07/25
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/25     cui naiwan   初始化版本
################################################################################
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import math
import random
import cocotb_test.simulator
import struct


import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull, QueueEmpty
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union, Dict, Any
from cocotb.regression import TestFactory
from cocotb.handle import Force, Release

from defines import *

sys.path.append('../../common')
from bus.beq_data_bus import BeqBus
from drivers.beq_data_bus import BeqTxqMaster
from bus.tlp_adap_dma_bus import DmaReadBus, DmaWriteBus
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace, MemoryRegion, IORegion
from backpressure_bus import define_backpressure
from enum import Enum, unique

from virtio_ctx_ctrl import * 
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster

class VirtqType:
    NET_RX = 0
    NET_TX = 1
    BLK    = 2

class virtio_vq_t:
    def __init__(self, typ, qid):
        self.typ = typ  
        self.qid = qid

class data_element(NamedTuple):
    qid: int
    data: bytearray
    user0: int
    user1: int
    header: Dict[str, Any]
    region: MemoryRegion

class Virtq:
    def __init__(self, qid, mem, qdepth):
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        self.qid = qid  #global qid
        self.base_qid = qid & 0xFF
        self.qtype = (qid >> 8) & 0x3
        self.mem = mem
        self.qdepth = qdepth
        self.used_ring = self.mem.alloc_region((int)(2 + 2 + (64 / 8) * self.qdepth + 2))  #flags:16bit + used_idx:16bit + used_elem:64bit + avail_event:16bit
        self.last_used_idx = 0

        if self.qtype == VirtqType.NET_RX:
            self.msix_addr = 0xffffffffffd00000 + self.base_qid
        elif self.qtype == VirtqType.NET_TX:
            self.msix_addr = 0xffffffffffe00000 + self.base_qid
        elif self.qtype == VirtqType.BLK:
            self.msix_addr = 0xfffffffffff00000 + self.base_qid
        
        self.msix_data = self.qid

class virtq_behavior:
    def __init__(self, mem, virtio_ctrl):
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        self.mem = mem
        self.virtios = {}
        self.virtio_ctrl = virtio_ctrl

    async def create_queue(self, qid, qdepth, dev_id, bdf, forced_shutdown, msix_enable, msix_time, msix_threshold):
        if qid in self.virtios.keys():
            raise ValueError(f"queue is exist: qid={qid}")
        q = Virtq(qid, self.mem, qdepth)
        used_ring_base = q.used_ring.get_absolute_address(0)
        await q.used_ring.write(2, b'\x00\x00')  #init used_idx 0
        await self.virtio_ctrl.create_queue(qid, dev_id, bdf, forced_shutdown, used_ring_base, qdepth, q.msix_addr, q.msix_data, msix_enable, msix_time, msix_threshold)
        if qid in self.virtios.keys():
            raise ValueError("The rx queue(qid:{}) is already exists".format(qid))
        self.virtios[qid] = q  
        self.log.info(f"create queue: qid={qid}, used_ring_base=0x{used_ring_base:x}")
        return q

    async def start_queue(self, qid):
        if qid not in self.virtios.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        await self.virtio_ctrl.start_queue(qid)

    def stop_queue(self, qid):
        self.virtio_ctrl.stop_queue(qid)

    def destroy_queue(self, qid):
        if qid not in self.virtios.keys():
            raise ValueError("The rx queue(qid:{}) is not exists".format(qid))
        virtq = self.virtios[qid]
        self.mem.free_region(virtq.used_ring)
        self.virtio_ctrl.destroy_queue(qid)
        del self.virtios[qid]  

class TB(object):
    def __init__(self, dut, qid_array, max_seq):
        self.dut = dut
        self.qid_array = qid_array
        self.max_seq = max_seq
        self.used_idx = {}
        self.mask_msix = {}
        self.processed_counts = {}
        self.used_elem_ref_queues = {}
        self.qid_err_record = {}
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 5, units="ns").start())
        
        self.mem = Pool(None, 0, size=2**64, min_alloc=64)
    
        self.csrBusMaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)
        self.wrusedinfo = WrusedinfoSource(WrusedinfoBus.from_prefix(dut, "wr_used_info"), dut.clk, dut.rst)
        self.setmask = SetmaskSource(SetmaskBus.from_prefix(dut, "set_mask_req"), dut.clk, dut.rst)
        self.errhandle = ErrhandleSink(ErrhandleBus.from_prefix(dut, "err_handle"), dut.clk, dut.rst)
        self.blkdserrinfo = WrblkdserrinfoSource(WrblkdserrinfoBus.from_prefix(dut, "blk_ds_err_info_wr"), dut.clk, dut.rst)
        self.dmaWrDataIf = DmaRam(DmaWriteBus.from_prefix(dut, "dma_data"), None, dut.clk, dut.rst, mem=self.mem)
        self.usedctxRdTblIf = UsedCtxRdTblIf(UsedCtxRdReqBus.from_prefix(dut, "used_ring_irq"), UsedCtxRdRspBus.from_prefix(dut, "used_ring_irq"), None, dut.clk, dut.rst)
        self.usedelemptrTblIf = UsedElemPtrTblIf(UsedElemPtrRdReqBus.from_prefix(dut, "used_elem_ptr"), UsedElemPtrRdRspBus.from_prefix(dut, "used_elem_ptr"), UsedElemPtrWrBus.from_prefix(dut, "used_elem_ptr"), dut.clk, dut.rst)
        self.usedidxWrTblIf = UsedIdxTblIf(None, None, UsedIdxWrBus.from_prefix(dut, "used_idx"), dut.clk, dut.rst)
        self.msixtblWrTblIf = MsixTblIf(None, None, MsixWrBus.from_prefix(dut, "msix_tbl"), dut.clk, dut.rst)
        self.TxTimeRdTblIf =  TxMsixTimeRdTbl(TxMsixTimeRdReqBus.from_prefix(dut, "msix_aggregation_time"), TxMsixTimeRdRspBus.from_prefix(dut, "msix_aggregation_time"), None, dut.clk, dut.rst)
        self.TxThresholdRdTblIf = TxMsixThresholdRdTbl(TxMsixThresholdRdReqBus.from_prefix(dut, "msix_aggregation_threshold"), TxMsixThresholdRdRspBus.from_prefix(dut, "msix_aggregation_threshold"), None, dut.clk, dut.rst)
        self.RxTimeRdTblIf = RxMsixTimeRdTbl(RxMsixTimeRdReqBus.from_prefix(dut, "msix_aggregation_time"), RxMsixTimeRdRspBus.from_prefix(dut, "msix_aggregation_time"), None, dut.clk, dut.rst)
        self.RxThresholdRdTblIf = RxMsixThresholdRdTbl(RxMsixThresholdRdReqBus.from_prefix(dut, "msix_aggregation_threshold"), RxMsixThresholdRdRspBus.from_prefix(dut, "msix_aggregation_threshold"), None, dut.clk, dut.rst)
        self.TxmsixInfoTbl = TxMsixInfoTbl(TxMsixInfoRdReqBus.from_prefix(dut, "msix_aggregation_info"), TxMsixInfoRdRspBus.from_prefix(dut, "msix_aggregation_info"), TxMsixInfoWrBus.from_prefix(dut, "msix_aggregation_info"), dut.clk, dut.rst, read_first=False)
        self.RxmsixInfoTbl = RxMsixInfoTbl(RxMsixInfoRdReqBus.from_prefix(dut, "msix_aggregation_info"), RxMsixInfoRdRspBus.from_prefix(dut, "msix_aggregation_info"), RxMsixInfoWrBus.from_prefix(dut, "msix_aggregation_info"), dut.clk, dut.rst, read_first=False)
        self.ErrfatalWrTblIf = ErrfatalWrTblIf(None, None, ErrfatalWrBus.from_prefix(dut, "err_fatal"), dut.clk, dut.rst)
        self.DmawrusedidxirqflagWrTblIf = DmawrusedidxirqflagWrTblIf(None, None, DmawrusedidxirqflagWrBus.from_prefix(dut, "dma_write_used_idx_irq_flag"), dut.clk, dut.rst)
        self.virtio_ctx = virtio_ctx_ctrl(dut.clk, self.usedctxRdTblIf, self.usedelemptrTblIf, self.usedidxWrTblIf, self.msixtblWrTblIf, self.TxTimeRdTblIf, self.TxThresholdRdTblIf, self.RxTimeRdTblIf, self.RxThresholdRdTblIf, self.TxmsixInfoTbl, self.RxmsixInfoTbl, self.ErrfatalWrTblIf, self.DmawrusedidxirqflagWrTblIf)
        self.virtq_behavior = virtq_behavior(self.mem, self.virtio_ctx)
        
        self.all_completed = Event()
        self.queue_completed = set()
        self.all_used_info_sent = {}
        
        self.error_queues = set()  #record err queue
        self.dut_received_used_info_cnt = {}
       
    async def cycle_reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await Timer(2, "us")

    def set_idle_generator(self, generator=None):
        self.dmaWrDataIf.set_idle_generator(generator)
        self.wrusedinfo.set_idle_generator(generator)
        self.setmask.set_idle_generator(generator)
        self.blkdserrinfo.set_idle_generator(generator)
        
    def set_backpressure_generator(self, generator=None):
        self.dmaWrDataIf.set_backpressure_generator(generator)
        self.errhandle.set_backpressure_generator(generator)

    def _final_report(self, qid, total_pkts, drop_pkts, recv_pkts):
        #gen final report
        self.log.info(
            f"=== Q{qid} ===\n"
            f"total pkts: {total_pkts}\n"
            f"hw_drop_cnt: {drop_pkts}\n"
            f"recv_pkts: {recv_pkts}\n"
            "=================="
        )  

    async def _monitor_dut_used_info_reception(self):
        self.log.info("Starting DUT used_info reception monitor.")
    
        while True:
            await RisingEdge(self.dut.clk)
            
            if self.dut.wr_used_info_vld.value == 1 and self.dut.wr_used_info_rdy.value == 1:
                bin_str = self.dut.wr_used_info_dat.value.binstr
                
                dat_val = int(bin_str, 2)
                
                total_bits = 2 + 8 + 64 + 16 + 1 + 1 + 7 # 99 bits
                qid_type = (dat_val >> (total_bits - 2)) & 0x3
                qid_base = (dat_val >> (total_bits - 2 - 8)) & 0xFF
                global_qid = (qid_type << 8) | qid_base
    
                if global_qid in self.qid_array:
                    self.dut_received_used_info_cnt[global_qid] = self.dut_received_used_info_cnt.get(global_qid, 0) + 1
                    cnt = self.dut_received_used_info_cnt[global_qid]
                    
                    if cnt == self.max_seq:
                        self.all_used_info_sent[global_qid] = True
                        self.log.info(f"MONITOR: qid={global_qid} has received all {self.max_seq} used_info. Ready for destruction.")

    async def _irq_handler(self, address, data, qtype):
        qid = int.from_bytes(data, byteorder='little')
        self.log.info(f"recv irq: qtype={qtype}, address=0x{address:x}, qid={qid}, data={data.hex()}")

        if qid not in self.qid_array:
            self.log.warning(f"ignore unknow irq: qid={qid}")
            return
        
        if qid in self.qid_err_record and self.qid_err_record[qid]["has_err"]:
            self.log.info(f"Processing IRQ for error queue: qid={qid}")
        elif qid in self.error_queues:
            self.log.info(f"Ignoring IRQ for already completed error queue: qid={qid}")
            return
        
        if qid not in self.virtq_behavior.virtios:
            self.log.error(f"queue not exist: qid={qid}")
            return
        
        virtq = self.virtq_behavior.virtios[qid]

        used_idx_bytes = await virtq.used_ring.read(2, 2)
        current_used_idx = int.from_bytes(used_idx_bytes, byteorder='little')
        self.log.info(f"qid={qid}: current_used_idx={current_used_idx}, last_used_idx={virtq.last_used_idx}")

        qdepth = virtq.qdepth
        start = virtq.last_used_idx % qdepth
        #self.log.info(f"start = {start}")
        end = current_used_idx % qdepth
        #self.log.info(f"end = {end}")

        if start <= end:
            for i in range(start, end):
                await self._check_used_elem(virtq, i, qid)
        else:
            for i in range(start, qdepth):
                await self._check_used_elem(virtq, i, qid)
            for i in range(0, end):
                await self._check_used_elem(virtq, i, qid)

       
        self.processed_counts[qid] += (current_used_idx - virtq.last_used_idx) % qdepth
        self.log.info(f"qid={qid}: already processed {self.processed_counts[qid]}/{self.max_seq} irq")

        if qid in self.qid_err_record and self.qid_err_record[qid]["has_err"]:
            err_stop_idx = self.qid_err_record[qid]["dut_stop_used_idx"]
            self.log.info(f"err_stop_idx={err_stop_idx}")
            #if (self.processed_counts[qid] >= err_stop_idx and self.all_used_info_sent.get(qid, False)): 
            if self.processed_counts[qid] >= err_stop_idx:
                self.error_queues.add(qid)
                self.queue_completed.add(qid)
                self.log.info(f"qid={qid} has error, completed checking all elements before error (total: {err_stop_idx + 1})")

        if qid not in self.error_queues and self.processed_counts[qid] == self.max_seq:
            self.queue_completed.add(qid)
            self.log.info(f"qid={qid} has finished normal processing")

        if len(self.queue_completed) == len(self.qid_array):
            self.all_completed.set()

        virtq.last_used_idx = current_used_idx

    async def _check_used_elem(self, virtq, idx, qid):
        elem_offset = 4 + idx * 8
        used_elem_bytes = await virtq.used_ring.read(elem_offset, 8)
        used_elem = int.from_bytes(used_elem_bytes, byteorder='little')

        try:
            (exp_ptr, exp_elem) = await self.used_elem_ref_queues[qid].get()
        except QueueEmpty:
            raise ValueError(f"qid={qid}: ref data is empty, idx={idx}")
        
        if used_elem != exp_elem:
            raise ValueError(f"qid={qid} compare unsuccess: idx={idx}, used_elem={used_elem}, exp_elem={exp_elem}")
        self.log.info(f"qid={qid}: idx={idx} compare successfully ({used_elem})")

    def register_int_handler(self):
        # NET_RX irq region：0xffffffffffd00000
        ioregionNetRx = IORegion()
        ioregionNetRx.register_write_handler(lambda a, d, **k: self._irq_handler(a, d, VirtqType.NET_RX))
        self.mem.register_region(ioregionNetRx, 0xffffffffffd00000, 4096)

        # NET_TX irq region：0xffffffffffe00000
        ioregionNetTx = IORegion()
        ioregionNetTx.register_write_handler(lambda a, d, **k: self._irq_handler(a, d, VirtqType.NET_TX))
        self.mem.register_region(ioregionNetTx, 0xffffffffffe00000, 4096)

        # BLK irq region：0xfffffffffff00000
        ioregionBlk = IORegion()
        ioregionBlk.register_write_handler(lambda a, d, **k: self._irq_handler(a, d, VirtqType.BLK))
        self.mem.register_region(ioregionBlk, 0xfffffffffff00000, 4096)
        self.log.info("register all irq handler")

    async def pkt_gen(self, qid_array, pkt_num, tb):
        for global_qid in qid_array:
            self.used_idx[global_qid] = 0
            self.processed_counts[global_qid] = 0
            self.used_elem_ref_queues[global_qid] = Queue(maxsize=1024)

            self.qid_err_record[global_qid] = {
                "has_err": False,
                "first_err_pkt_idx": -1,
                "dut_stop_used_idx": -1
            }
            self.all_used_info_sent[global_qid] = False
    
        for global_qid in qid_array:
            qdepth = self.virtq_behavior.virtios[global_qid].qdepth
            self.log.info(f"qid={global_qid}: start generate {pkt_num} ref_data (qdepth={qdepth})")
            for pkt_idx in range(pkt_num):
                is_queue_err = self.qid_err_record[global_qid]["has_err"]
                #self.log.info(f"for qid={global_qid} generate {pkt_num} ref_data (qdepth={qdepth})")
    
                used_idx_val = self.used_idx[global_qid]
                #used_elem = random.randint(0, 0xFFFFFFFFFFFFFFFF)
                ptr = int(used_idx_val % qdepth)

                forced_shutdown = 1 if random.random() < 0 else 0
                
                if not is_queue_err:
                    error_probability  = 0  #0.3
                    fatal1_probability = 0.5
                    #has_error = (not is_queue_err) and (random.random() < error_probability) 
                    has_error = (not is_queue_err) and (random.random() < error_probability) 
                    fatal_is_1 = random.random() < fatal1_probability if has_error else False
                    fatal = 1 if fatal_is_1 else 0

                    if has_error and not fatal_is_1:
                        elem_len = 0
                        elem_id = random.randint(0, 0xFFFFFFFF)
                        self.log.debug(f"qid={global_qid} | pkt_idx={pkt_idx} | unfatal err: elem.len=0, elem.id=0x{elem_id:08x}")
                    else:
                        elem_len = random.randint(0, 0xFFFFFFFF)
                        elem_id = random.randint(0, 0xFFFFFFFF)

                    used_elem = (elem_len << 32) | elem_id
                    await self.used_elem_ref_queues[global_qid].put((ptr, used_elem))
                else:
                    self.log.debug(
                    f"qid={global_qid} (err) | pkt_idx={pkt_idx} | "
                    f"skip put to ref queue (no comparison needed)"
                )                
              
                #if has_error:
                if has_error and fatal_is_1 and not is_queue_err:
                    self.qid_err_record[global_qid] = {
                        "has_err": True,
                        "first_err_pkt_idx": pkt_idx,
                        "dut_stop_used_idx": ptr  #when err,used_idx value
                    }
                    self.log.error(
                        f"qid={global_qid} | first_err at pkt_idx={pkt_idx} | "
                        f"DUT stops DMA writes from used_idx={ptr}, but test will generate all {pkt_num} used_info"
                    )

                if has_error:  
                    err_info = random.randint(1, 127)
                else:
                    err_info = 0 
        
                #qid_type = int(global_qid / 256)
                #qid = int(global_qid % 256)
                qid_type = (global_qid >> 8) & 0x3
                qid = global_qid & 0xFF
                used_info = wr_used_info(qid_type = qid_type,
                                            qid = qid,
                                            used_elem = used_elem,
                                            used_idx = ptr,
                                            forced_shutdown = forced_shutdown,
                                            fatal = fatal,
                                            err_info = err_info).pack()
                
                wr_used_info_txn = tb.wrusedinfo._transaction_obj()
                wr_used_info_txn.dat = used_info
                await tb.wrusedinfo.send(wr_used_info_txn) 
        
                self.used_idx[global_qid] = (used_idx_val + 1) % 65536
        
                if random.random() < 0:  #0.1
                    
                    mask_dat = random.randint(0, 1)
                    
                    set_mask_txn = tb.setmask._transaction_obj()
                    set_mask_txn.qid = global_qid
                    set_mask_txn.dat = mask_dat
                    await tb.setmask.send(set_mask_txn)
                    
                    self.mask_msix[global_qid] = mask_dat
                    
                    tb.log.info(f"Packet {pkt_idx}: Set mask for QID {global_qid} to {mask_dat}")
        
    
    async def worker(self, qid, max_seq):
        qtype = (qid >> 8) & 0x3
        dev_id = qid
        bdf = qid
        forced_shutdown = 0
        msix_enable = 1 #random.randint(0, 1)
        qdepth_t = random.randint(8, 12)  #(0, 15)
        qdepth = 2**qdepth_t
        msix_time = 7
        msix_threshold = 1
        self.processed_counts[qid] = 0

        await self.virtq_behavior.create_queue(qid, qdepth, dev_id, bdf, forced_shutdown, msix_enable, msix_time, msix_threshold)
        await self.virtq_behavior.start_queue(qid=qid) 
        self.log.info(f"start queue: qid={qid}, qdepth={qdepth}")

        while qid not in self.queue_completed:  
            await Timer(1000, "ns")

        while not self.all_used_info_sent.get(qid, False):
            await Timer(100, "ns")
            self.log.info(f"qid={qid}: all used_info sent, ready to destroy")

        await Timer(100, "us")
        self.virtq_behavior.stop_queue(qid=qid)
        self.virtio_ctx.destroy_queue(qid=qid)
        self.log.info(f"qid={qid} has destory")
        

async def run_test(dut, idle_inserter, backpressure_inserter):
    random.seed(321)
    q_num = 4   #10
    qtype_num = 3   #3
    max_seq = 100000  #100000
   
    packet_gen_cr = None  
    worker_cr = []
    await Timer(2, "us")

    if qtype_num == 1:
        qtypes = [VirtqType.NET_RX]  # NET_RX
    elif qtype_num == 2:
        qtypes = [VirtqType.NET_RX, VirtqType.NET_TX]  # NET_RX+NET_TX
    elif qtype_num == 3:
        qtypes = [VirtqType.NET_RX, VirtqType.NET_TX, VirtqType.BLK]  # all type
    else:
        raise ValueError(f"not support qtype_num: {qtype_num}")

    tb = TB(dut, [], max_seq)

    qid_array = []
    for qtype in qtypes:
        base_qids = random.sample(range(256), q_num)

        for base_qid in base_qids:
            global_qid = (qtype << 8) | base_qid
            tb.log.info(f"global_qid = {global_qid}, qtype = {qtype}, base_qid = {base_qid}")
            qid_array.append(global_qid)

    tb.qid_array = qid_array

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()

    cocotb.start_soon(tb._monitor_dut_used_info_reception())

    tb.register_int_handler()

    for global_qid in qid_array:  
        worker_cr.append(cocotb.start_soon(tb.worker(global_qid, max_seq)))
        
    await Timer(2, "us")
    
    packet_gen_cr=cocotb.start_soon(tb.pkt_gen(qid_array=qid_array, pkt_num=max_seq, tb=tb))
 
    await packet_gen_cr  
    tb.log.info("packet_gen is done") 

    await tb.all_completed.wait()
    await Timer(100, "us")
    tb.log.info("all queue is finish")

    for cr in worker_cr:
        await cr.join() 

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        #factory.add_option("idle_inserter", [cycle_pause])
        #factory.add_option("backpressure_inserter", [cycle_pause])
        factory.generate_tests()

#sys.path.append('../common'); from debug import *

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)


