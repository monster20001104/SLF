#!/usr/bin/env python3
################################################################################
#  文件名称 : test_virtio_desc_engine_core_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/07/11
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/11     Joe Jiang   初始化版本
################################################################################
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import math
import random
import cocotb_test.simulator

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory
import numpy as np

sys.path.append('../../common')
from bus.tlp_adap_dma_bus import DmaReadBus
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace, MemoryRegion
from enum import Enum, unique
from defines import *

class vQueue():
    def __init__(self, log, mem, vq, typ, depth, cfg, indirct_en=0, bdf=0, dev_id=0, head_slot=0, head_slot_vld=0, tail_slot=0, avail_idx=0, max_size=65562):
        self._cfg = cfg
        self.log = log
        self._mem = mem
        self._vq = vq
        self._typ = typ
        self._depth = depth
        self._depth_log2 = int(math.log2(self._depth))
        self._indirct_en = indirct_en
        self._bdf = bdf
        self._dev_id = dev_id
        self._head_slot = head_slot
        self._head_slot_vld = head_slot_vld
        self._tail_slot = tail_slot
        self._desc_tbl = self._mem.alloc_region(self._depth*16, bdf=self._bdf)
        self._desc_idx_pool = [i for i in range(self._depth)]
        self._avail_idx = 0
        self._forced_shutdown = 0
        self._max_size = max_size
        self._avail_ring = Queue(maxsize=self._depth)
        self.ref_results = []

    def gen_a_desc(self, desc_addr=None, desc_len=0, flags_indirect=0, next=0, flags_next=0):
        flags_write = TestType.NETRX == self._typ and flags_indirect == 0
        if desc_addr == None:
            desc_addr = random.randint(0, 2**64-1)
        return VirtqDesc(addr=desc_addr, len=desc_len, flags_indirect=flags_indirect, flags_next=flags_next, flags_write=flags_write, next=next)

    async def gen_indirect_split(self, seq_num, chain_len, pkt_len):
        idxs = []
        descs = []
        ring_id = None
        indirct_ptr = random.randint(0, min(self._cfg.max_indirct_ptr, chain_len-1))
        while len(self._desc_idx_pool) < indirct_ptr+1:
            await Timer(1, "us")

        for i in range(indirct_ptr+1):
            id = random.randint(0, len(self._desc_idx_pool)-1)
            idxs.append(self._desc_idx_pool.pop(id))

        indirct_desc_buf_len = random.randint(chain_len-indirct_ptr, self._cfg.max_indirct_desc_size)*16
        indirct_desc_buf = self._mem.alloc_region(indirct_desc_buf_len, bdf=self._bdf)

        for i in range(indirct_ptr+1):
            idx = idxs[i]
            if ring_id == None:
                ring_id = idx
            if i == indirct_ptr:
                next = random.randint(0, 65535)
                flags_next = 0
                flags_indirect = 1
                desc_addr = indirct_desc_buf.get_absolute_address(0)
                desc_len = indirct_desc_buf_len
            else:
                next = idxs[i+1]
                flags_next = 1
                flags_indirect = 0
                desc_addr = None
                desc_len = pkt_len//chain_len
            desc = self.gen_a_desc(desc_addr=desc_addr, desc_len=desc_len, flags_indirect=flags_indirect, next=next, flags_next=flags_next)    
            self.log.debug("desc write vq{} seq_num {} id {} desc {}".format(vq_str(self._vq), seq_num, idx, desc.show(dump=True)))
            await self._desc_tbl.write(16*idx, desc.build()[::-1])
            if i != indirct_ptr:
                descs.append(desc)
        indirect_idxs = [0]
        if chain_len-indirct_ptr-1 > 0:
            if random.randint(0, 100) > 50:
                indirect_idxs = indirect_idxs + random.sample([i for i in range(1, chain_len-indirct_ptr)], chain_len-indirct_ptr-1)
            else:
                indirect_idxs = indirect_idxs + random.sample([i for i in range(1, random.randint(chain_len-indirct_ptr, indirct_desc_buf_len//16))], chain_len-indirct_ptr-1)
        #ups the odds of sequential desc
        if random.randint(0, 100) > 40:
            indirect_idxs.sort()

        indirect_desc_size = chain_len-indirct_ptr
        for i in range(indirect_desc_size):
            idx = indirect_idxs[i]
            if i == indirect_desc_size - 1:
                next = random.randint(0, 65535)
                flags_next = 0
                desc_len = pkt_len - pkt_len//chain_len*(chain_len-1)
            else:
                next = indirect_idxs[i+1]
                flags_next = 1
                desc_len = pkt_len//chain_len
            desc = self.gen_a_desc(desc_addr=None, desc_len=desc_len, flags_indirect=0, next=next, flags_next=flags_next)    
            self.log.debug("desc(indirct) write vq{} seq_num {} id {} desc {}".format(vq_str(self._vq), seq_num, idx, desc.show(dump=True)))
            await indirct_desc_buf.write(16*idx, desc.build()[::-1])
            descs.append(desc)
        return idxs, ring_id, descs, indirct_desc_buf

    async def gen_direct_split(self, seq_num, chain_len, pkt_len):
        idxs = []
        descs = []
        ring_id = None
        while len(self._desc_idx_pool) < chain_len:
                await Timer(1, "us")

        for i in range(chain_len):
            id = random.randint(0, len(self._desc_idx_pool)-1)
            idxs.append(self._desc_idx_pool.pop(id))

        for i in range(chain_len):
            idx = idxs[i]
            if ring_id == None:
                ring_id = idx
            if i == chain_len - 1:
                next = random.randint(0, 65535)
                flags_next = 0
                desc_len = pkt_len - pkt_len//chain_len*(chain_len-1)
            else:
                next = idxs[i+1]
                flags_next = 1
                desc_len = pkt_len//chain_len
            desc = self.gen_a_desc(desc_addr=None, desc_len=desc_len, flags_indirect=0, next=next, flags_next=flags_next)    
            self.log.debug("desc write vq{} seq_num {} id {} desc {}".format(vq_str(self._vq), seq_num, idx, desc.show(dump=True)))
            await self._desc_tbl.write(16*idx, desc.build()[::-1])
            descs.append(desc)

        return idxs, ring_id, descs, None

    async def gen_a_chain(self, seq_num):
        pkt_id = seq_num % 1024#random.randint(0, 1023)
        pkt_len = random.randint(self._cfg.min_chain_num, self._cfg.max_size)
        indirct_desc_buf = None
        err = ErrInfo(fatal=0, err_code=0)
        chain_len = random.randint(self._cfg.min_chain_num, min(pkt_len, self._cfg.max_chain_num))
        self.log.info("gen_a_chain vq{} seq_num {} pkt_id {} chain_len {} pkt_len {} err {}".format(vq_str(self._vq), seq_num, pkt_id, chain_len, pkt_len, err.show(dump=True)))
        ring_id = None
        descs = []
        idxs = []
        if not self._indirct_en:
            idxs, ring_id, descs, indirct_desc_buf = await self.gen_direct_split(seq_num, chain_len, pkt_len)
        else:
            idxs, ring_id, descs, indirct_desc_buf = await self.gen_indirect_split(seq_num, chain_len, pkt_len)
        await self._avail_ring.put((ring_id, self._avail_idx, pkt_id, err))
        self.ref_results.append(RefResult(pkt_id, ring_id, self._avail_idx, pkt_len, descs, err, seq_num, idxs, indirct_desc_buf))
        self._avail_idx = (self._avail_idx+1) & (self._depth-1)
        await Timer(100, "ns")

class VirtQ():
    def __init__(self, mem, log, dut):
        self.log = log
        self._mem = mem
        self._dut = dut
        self.dmaDescIf = DmaRam(None, DmaReadBus.from_prefix(dut, "dma_desc"), dut.clk, dut.rst, mem=mem)
        self.ctxInfoRdTbl = CtxInfoRdTbl(CtxInfoRdReqBus.from_prefix(dut, "ctx_info"), CtxInfoRdRspBus.from_prefix(dut, "ctx_info"), None, dut.clk, dut.rst)
        def _ctxInfoRdCallback(req_obj):
            vq = int(req_obj.rd_req_vq)
            if vq not in self._q.keys():
                raise ValueError("The queue(vq:{}) is not exists".format(vq))
            rsp = CtxInfoRdRspTransaction()
            rsp.rd_rsp_desc_tbl_addr = self._q[vq]._desc_tbl.get_absolute_address(0)
            rsp.rd_rsp_qdepth = self._q[vq]._depth_log2
            rsp.rd_rsp_forced_shutdown = self._q[vq]._forced_shutdown
            rsp.rd_rsp_indirct_support = self._q[vq]._indirct_en
            rsp.rd_rsp_bdf = self._q[vq]._bdf
            rsp.rd_rsp_max_len = self._q[vq]._max_size
            return rsp
        self.ctxInfoRdTbl.set_callback(_ctxInfoRdCallback)
        
        self.ctxSlotChainTbl = CtxSlotChainTbl(CtxSlotChainRdReqBus.from_prefix(dut, "ctx_slot_chain"), CtxSlotChainRdRspBus.from_prefix(dut, "ctx_slot_chain"), CtxSlotChainWrBus.from_prefix(dut, "ctx_slot_chain"), dut.clk, dut.rst)
        def _ctxSlotChainWrCallback(req_obj):
            vq              = int(req_obj.wr_vq)
            if vq not in self._q.keys():
                raise ValueError("The queue(vq:{}) is not exists".format(vq))
            self._q[vq]._head_slot     = int(req_obj.wr_head_slot)
            self._q[vq]._head_slot_vld = int(req_obj.wr_head_slot_vld)
            self._q[vq]._tail_slot     = int(req_obj.wr_tail_slot)
            return
        self.ctxSlotChainTbl.set_wr_callback(_ctxSlotChainWrCallback)
        def _ctxSlotChainRdCallback(req_obj):
            vq = int(req_obj.rd_req_vq)
            if vq not in self._q.keys():
                raise ValueError("The queue(vq:{}) is not exists".format(vq))
            rsp = CtxSlotChainRdRspTransaction()
            rsp.rd_rsp_head_slot     = self._q[vq]._head_slot
            rsp.rd_rsp_head_slot_vld = self._q[vq]._head_slot_vld
            rsp.rd_rsp_tail_slot     = self._q[vq]._tail_slot
            return rsp
        self.ctxSlotChainTbl.set_callback(_ctxSlotChainRdCallback)
        
        self.slotSubmitSource   = SlotSubmitSource(SlotSubmitBus.from_prefix(dut, "slot_submit"), dut.clk, dut.rst)
        self.slotCplSink        = SlotCplSink(SlotCplBus.from_prefix(dut, "slot_cpl"), dut.clk, dut.rst)
        self.rdDescReqSource    = RdDescReqSource(RdDescReqBus.from_prefix(dut, "rd_desc_req"), dut.clk, dut.rst)
        self.rdDescRspSink      = RdDescRspSink(RdDescRspBus.from_prefix(dut, "rd_desc_rsp"), dut.clk, dut.rst)
        self.slotCplQueue       = Queue(maxsize=32)
        self._q = {}   
        self._slot_queue = Queue(maxsize=32)
        self.slot_bitmap = {}
        for i in range(32):
            self._slot_queue.put_nowait(i)
            self.slot_bitmap[i] = False

        cocotb.start_soon(self._submitThd())
        cocotb.start_soon(self._cplThd())
        cocotb.start_soon(self._freeSlotThd())
        
    def set_queue(self, qid, cfg, typ=TestType.NETTX, depth=32768, indirct_en=0, bdf=None, dev_id=None, max_size=65562):
        if bdf == None:
            bdf = random.randint(0, 65535)
        if dev_id == None:
            dev_id =random.randint(0, 1023)
        vq = qid2vq(qid, typ)
        self._q[vq] = vQueue(self.log, self._mem, vq, typ, depth, cfg, indirct_en, bdf=bdf, dev_id=dev_id, max_size=max_size)
    
    async def gen_a_pkt(self, qid, typ=TestType.NETTX, seq_num=0):
        await self._q[qid2vq(qid, typ)].gen_a_chain(seq_num)

    async def _submitThd(self):
        while True:
            for id, queue in self._q.items():
                if not queue._avail_ring.empty():
                    qid, typ = vq2qid(id)
                    (ring_id, avail_idx, pkt_id, err) = await queue._avail_ring.get()
                    obj = self.slotSubmitSource._transaction_obj()
                    obj.vq          = VirtioVq(typ=queue._typ, qid=qid).pack()
                    obj.dev_id      = queue._dev_id
                    obj.slot_id     = await self._slot_queue.get()
                    obj.pkt_id      = pkt_id
                    obj.ring_id     = ring_id
                    obj.avail_idx   = avail_idx
                    obj.err         = err.pack()
                    await self.slotSubmitSource.send(obj)
                    self.slot_bitmap[int(obj.slot_id)] = True
            await Timer(1, "ns")

    async def _cplThd(self):
        
        while True:
            slotCpl = await self.slotCplSink.recv()
            if self.slot_bitmap[int(slotCpl.slot_id)]:
                await self.slotCplQueue.put(slotCpl)
                self.slot_bitmap[int(slotCpl.slot_id)] = False
            else:
                raise ValueError("slot_id{} is double cpl(vq{})".format(slotCpl.slot_id, vq_str(slotCpl.vq)))
    async def _freeSlotThd(self):
        while True:
            slotCpl = await self.slotCplQueue.get()
            vq = slotCpl.vq
            slot_id = slotCpl.slot_id
            obj = self.rdDescReqSource._transaction_obj()
            obj.slot_id = slot_id
            await self.rdDescReqSource.send(obj)
            eop = False
            sbd = None
            descs = []
            while not eop:
                descRsp = await self.rdDescRspSink.recv()
                eop = descRsp.eop
                sbd = DescRspSbd().unpack(descRsp.sbd)
                if sbd.vq != int(vq):
                    raise ValueError("vq mismatch slotCpl {} rdDescRsp {}".format(vq.pack(), sbd.vq))
                err_info = ErrInfo().unpack(int(sbd.err_info))
                desc = VirtqDesc().unpack(descRsp.dat)
                descs.append(desc)
            q =  self._q[sbd.vq]
            ref = q.ref_results.pop(0)
            if sbd.dev_id != q._dev_id:
                self.log.debug("vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)))
                raise ValueError("dev_id mismatch vq{} seq_num {} ctx {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, q._dev_id, sbd.dev_id))
            if sbd.pkt_id != ref.pkt_id:
                self.log.debug("vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)))
                raise ValueError("pkt_id mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, ref.pkt_id, sbd.pkt_id))
            if sbd.avail_idx != ref.avail_idx:
                self.log.debug("vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)))
                raise ValueError("avail_idx mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, ref.avail_idx, sbd.avail_idx))
            if sbd.ring_id != ref.ring_id:
                self.log.debug("vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)))
                raise ValueError("ring_id mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, ref.ring_id, sbd.ring_id))
            if sbd.total_buf_length != ref.pkt_len:
                self.log.debug("vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)))
                raise ValueError("pkt_len mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, ref.pkt_len, sbd.total_buf_length))
            if sbd.valid_desc_cnt != len(ref.descs):
                self.log.debug("vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)))
                raise ValueError("valid_desc_cnt mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, len(ref.descs), sbd.valid_desc_cnt))
            if  ref.descs != descs:
                for i in range(len(descs)):
                    if ref.descs[i] != descs[i]:
                        raise ValueError("desc mismatch vq{} seq_num {} NO.{} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, i, ref.descs[i].show(dump=True), descs[i].show(dump=True)))
            err_info = ErrInfo().unpack(int(sbd.err_info))
            if  ref.err != err_info:
                raise ValueError("err mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, ref.err.show(dump=True), err_info.show(dump=True)))
            self.log.info("vq{} seq_num {} pass".format(vq_str(sbd.vq), ref.seq_num))
            q._desc_idx_pool = q._desc_idx_pool + ref.idxs
            if ref.indirct_desc_buf != None:
                self._mem.free_region(ref.indirct_desc_buf)
            self._slot_queue.put_nowait(slot_id)

    
class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.dut.rst.setimmediatevalue(1)
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.mem = Pool(None, 0, size=2**64, min_alloc=64)
        self.virtQ = VirtQ(self.mem, self.log, dut)
        

    async def cycle_reset(self):
        
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
        self.virtQ.dmaDescIf.set_idle_generator(generator)
        self.virtQ.slotSubmitSource.set_idle_generator(generator)
        self.virtQ.slotCplSink.set_idle_generator(generator)     
        self.virtQ.rdDescReqSource.set_idle_generator(generator) 
        self.virtQ.rdDescRspSink.set_idle_generator(generator)   
    def set_backpressure_generator(self, generator=None):
        self.virtQ.dmaDescIf.set_backpressure_generator(generator)
        self.virtQ.slotSubmitSource.set_backpressure_generator(generator)
        self.virtQ.slotCplSink.set_backpressure_generator(generator)     
        self.virtQ.rdDescReqSource.set_backpressure_generator(generator) 
        self.virtQ.rdDescRspSink.set_backpressure_generator(generator) 
async def run_test(dut, max_q = None, max_seq = None, indirct_support=None, indirct_mix=None, cfg = None, idle_inserter = None, backpressure_inserter = None):
    random.seed(123)
    default_max_q = 8
    default_max_seq = 10000
    default_indirct_support = True
    default_indirct_mix = True
    default_cfg = Cfg(
            min_chain_num = 1,
            max_chain_num = 16,
            max_indirct_ptr = 8,
            max_indirct_desc_size = (64*1024/16),
            max_size = 65562 #64KB max TCP payload + 12B virtio-net header + 14B eth header
        ) 
    
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    if max_q == None:
        max_q           = default_max_q
    if max_seq == None:
        max_seq         = default_max_seq
    if indirct_support == None:
        indirct_support = default_indirct_support
    if indirct_mix == None:
        indirct_mix     = default_indirct_mix
    if cfg == None:
        cfg             = default_cfg

    await tb.cycle_reset()
    workerthds = []

    async def worker(qid, max_size):
        typ =TestType.NETRX #When the module is instantiated, compilation parameters are specified, so it can only operate in a fixed mode.
        if indirct_support and indirct_mix:
            indirct_en = random.choice([True, False])
        else:
            indirct_en = indirct_support
        tb.virtQ.set_queue(qid, cfg, typ=typ, indirct_en=indirct_en, max_size=max_size)

        for i in range(max_seq):
            await tb.virtQ.gen_a_pkt(qid, typ=typ, seq_num=i)
    
    for qid in random.sample([i for i in range(256)], max_q):
        workerthds.append(cocotb.start_soon(worker(qid, cfg.max_size)))

    for i in range(max_q):
        await workerthds[i].join()
    while True:
        await Timer(100, "ns")
        empty = True
        for vq in tb.virtQ._q.keys():
            q = tb.virtQ._q[vq]
            empty = empty and len(q.ref_results) == 0
        if empty == True:
            break
    await Timer(10, "us")

debug = 1
if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        if debug:
            factory.add_option("max_q", [None]) #1, 4
            factory.add_option("max_seq", [None]) #10000
            factory.add_option("indirct_support", [None]) #True, False
            factory.add_option("indirct_mix", [None]) #True
            factory.add_option("cfg", [None]) #short_chain_cfg, long_chain_cfg, short_mix_chain_cfg, mix_chain_cfg
            factory.add_option("idle_inserter", [cycle_pause])
            factory.add_option("backpressure_inserter", [cycle_pause])
        else:
            factory.add_option("max_q", [1, 4]) #1, 8
            factory.add_option("max_seq", [10000]) #10000
            factory.add_option("indirct_support", [True, False]) #True, False
            factory.add_option("indirct_mix", [True]) #True
            factory.add_option("cfg", [short_chain_cfg, long_chain_cfg, short_mix_chain_cfg, mix_chain_cfg])
            factory.add_option("idle_inserter", [cycle_pause])
            factory.add_option("backpressure_inserter", [cycle_pause])
        factory.generate_tests()

#sys.path.append('../common'); from debug import *

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)