#!/usr/bin/env python3
################################################################################
#  文件名称 : test_virtio_idx_engine_tb.py
#  作者名称 : Yun Feilong
#  创建日期 : 2025/07/17
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/17     Yun Feilong   初始化版本
################################################################################

import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys

import random
import cocotb_test.simulator
from cocotb.utils import get_sim_time

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
from bus.tlp_adap_dma_bus import DmaWriteBus, DmaReadBus, Desc
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace, MemoryRegion
from enum import Enum, unique
#import ding_robot

from defines_idx_engine import * 

class VirtioCtx(object):
    def __init__(self, mem, cfg, dev_id, bdf, qdepth=9, avail_idx=0):
        self._cfg               = cfg
        self._dev_id            = dev_id
        self._bdf               = bdf
        self._qsz               = 2**qdepth
        self._qdepth            = qdepth
        self._avail_ring        = mem.alloc_region(self._qsz*2+6, bdf=self._bdf, dev_id=self._dev_id)
        self._avail_addr        = self._avail_ring.get_absolute_address(0)
        self._used_ring         = mem.alloc_region(self._qsz*8+6, bdf=self._bdf, dev_id=self._dev_id)
        self._used_addr         = self._used_ring.get_absolute_address(0)
        self._ctrl              = q_status_type_t.idle
        self._force_shutdown    = False
        self._sw_avail_idx      = avail_idx
        self._avail_idx         = avail_idx
        self._avail_ui          = avail_idx
        self._no_notify         = False
        self._no_change         = False
        self._dma_req_num       = 0
        self._dma_rsp_num       = 0
        self._err_code          = ERR_CODE.VIRTIO_ERR_CODE_NONE
        self._fault_injection   = ERR_CODE.VIRTIO_ERR_CODE_NONE
        self._injection         = False

class ram_callback(object): 
    def _rd_ctx(self, req_obj):
        vq                              = raw2vq(req_obj.rd_req_vq)
        if vq not in self.ctxs.keys():
            raise ValueError("The ctxs(vq:{}) is not exists".format(vq_str(vq)))
        rsp_obj                         = CtxInfoRdRspTransaction()
        rsp_obj.rd_rsp_dev_id           = self.ctxs[vq]._dev_id
        rsp_obj.rd_rsp_bdf              = self.ctxs[vq]._bdf
        rsp_obj.rd_rsp_avail_addr       = self.ctxs[vq]._avail_addr
        rsp_obj.rd_rsp_used_addr        = self.ctxs[vq]._used_addr
        rsp_obj.rd_rsp_qdepth           = self.ctxs[vq]._qdepth
        rsp_obj.rd_rsp_ctrl             = self.ctxs[vq]._ctrl
        rsp_obj.rd_rsp_force_shutdown   = self.ctxs[vq]._force_shutdown
        rsp_obj.rd_rsp_avail_idx        = self.ctxs[vq]._avail_idx
        rsp_obj.rd_rsp_avail_ui         = self.ctxs[vq]._avail_ui
        rsp_obj.rd_rsp_no_notify        = self.ctxs[vq]._no_notify
        rsp_obj.rd_rsp_no_change        = self.ctxs[vq]._no_change
        rsp_obj.rd_rsp_dma_req_num      = self.ctxs[vq]._dma_req_num
        rsp_obj.rd_rsp_dma_rsp_num      = self.ctxs[vq]._dma_rsp_num
        return rsp_obj  

    def _wr_ctx(self, req_obj):
        vq = raw2vq(req_obj.wr_vq)
        if vq not in self.ctxs.keys():
            raise ValueError("The ctxs(vq:{}) is not exists".format(vq_str(vq)))
        self.ctxs[vq]._avail_idx    = int(req_obj.wr_avail_idx)
        self.ctxs[vq]._no_notify    = bool(req_obj.wr_no_notify)
        self.ctxs[vq]._no_change    = bool(req_obj.wr_no_change)
        self.ctxs[vq]._dma_req_num  = int(req_obj.wr_dma_req_num)
        self.ctxs[vq]._dma_rsp_num  = int(req_obj.wr_dma_rsp_num)
        return

class TB(ram_callback):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.mem = Pool(None, 0, size=2**64, min_alloc=64)

        self.HostRdDma = DmaRam(DmaWriteBus.from_prefix(dut, "idx_eng_dma"), DmaReadBus.from_prefix(dut, "idx_eng_dma"), dut.clk, dut.rst, mem=self.mem)
        self.schReq = SchReqSource(SchReqBus.from_prefix(dut, "sch_req"), dut.clk, dut.rst)
        self.schReq.queue_occupancy_limit = 8
        self.IdxNotify = IdxNotifySink(IdxNotifyBus.from_prefix(dut, "idx_notify"), dut.clk, dut.rst)
        self.IdxNotify.queue_occupancy_limit = 2
        
        self.ctxInfo = CtxInfoRdTbl(CtxInfoRdReqBus.from_prefix(dut, "idx_engine_ctx"), CtxInfoRdRspBus.from_prefix(dut, "idx_engine_ctx"), CtxInfoWrBus(dut, "idx_engine_ctx"), dut.clk, dut.rst)
        self.ctxInfo.set_callback(self._rd_ctx)
        self.ctxInfo.set_wr_callback(self._wr_ctx)

        self.ErrCode = ErrCodeSink(ErrCodeBus.from_prefix(dut, "err_code_wr_req"), dut.clk, dut.rst)
        self.ErrCode.queue_occupancy_limit = 1
        self.ctxs = {}

        self._availRingSchQueue = Queue()
        self._availRingSchBitmap = {}
        self._availRingNotifyQueue = Queue(maxsize=4)

        self._sendDoorbellQueue = Queue(maxsize=4)

        self._errHandleCr       = cocotb.start_soon(self._errHandleThd())
        self._idxNotifyCr       = cocotb.start_soon(self._idxNotifyThd())
        self._availRingSchCr    = cocotb.start_soon(self._availRingSchThd())
        self._DoorbellCr    = cocotb.start_soon(self._DoorbellThd())
    
    async def _DoorbellThd(self):
        while True:
            vq = await self._sendDoorbellQueue.get()
            obj = self.schReq._transaction_obj()
            qid, typ = vq2qid(vq)
            obj.vq = VirtioVq(typ=typ, qid=qid).pack()
            await self.schReq.send(obj)

    async def _errHandleThd(self):
        while True:
            err_info_obj = await self.ErrCode.recv()
            vq = raw2vq(err_info_obj.vq)
            if vq not in self.ctxs.keys():
                raise ValueError("The ctxs(vq:{}) is not exists".format(vq_str(vq)))
            err_info = ErrInfo().unpack(err_info_obj.data)
            if self.ctxs[vq]._ctrl == q_status_type_t.doing:
                self.ctxs[vq]._err_code = err_info.err_code
                self.log.info("vq:{} found err_code({})".format(vq_str(vq), err_code_str(err_info.err_code)))
                await self.stop_vq(vq)
            elif self.ctxs[vq]._ctrl == q_status_type_t.stopping:
                self.ctxs[vq]._err_code = err_info.err_code
    
    async def _idxNotifyThd(self):
        while True:
            req_obj = await self.IdxNotify.recv()
            vq = raw2vq(req_obj.vq)
            await self._availRingNotifyQueue.put(vq)

    async def _availRingSchThd(self):
        while True:
            await RisingEdge(self.dut.clk)
            await RisingEdge(self.dut.clk)
            await RisingEdge(self.dut.clk)
            if not self._availRingNotifyQueue.empty():
                vq = await self._availRingNotifyQueue.get()
                self.log.debug("got idx Notify(vq:{})".format(vq_str(vq)))
                if vq not in self._availRingSchBitmap.keys():
                    tim = get_sim_time("ns")
                    self.log.debug("enqueue Notify(vq:{}) to availRingSch(@{})".format(vq_str(vq), tim))
                    await self._availRingSchQueue.put(vq)
                    self._availRingSchBitmap[vq] = (1, tim)
            elif not self._availRingSchQueue.empty():
                vq = await self._availRingSchQueue.get()
                cnt, tim = self._availRingSchBitmap[vq]
                cur_tim = get_sim_time("ns")
                #(vq:{} delta time {} idx {} ui {}) from availRingSch(@{})".format(vq_str(vq), cur_tim-tim, self.ctxs[vq]._avail_idx, self.ctxs[vq]._avail_ui, cur_tim))
                if cur_tim - tim > 1000:
                    idx_diff = (self.ctxs[vq]._avail_idx - self.ctxs[vq]._avail_ui) & 0xffff
                    self.ctxs[vq]._avail_ui = (self.ctxs[vq]._avail_ui + min(8, idx_diff)) & 0xffff
                    tim = cur_tim
                if (self.ctxs[vq]._avail_idx == self.ctxs[vq]._avail_ui or (self.ctxs[vq]._ctrl == q_status_type_t.stopping and self.ctxs[vq]._force_shutdown) or self.ctxs[vq]._ctrl == q_status_type_t.idle) and cnt == 1:
                    del self._availRingSchBitmap[vq]
                elif (self.ctxs[vq]._avail_idx == self.ctxs[vq]._avail_ui or self.ctxs[vq]._ctrl != q_status_type_t.doing) and cnt == 2:
                    self._availRingSchBitmap[vq] = (1, tim)
                    await self._availRingSchQueue.put(vq)
                else:
                    self._availRingSchBitmap[vq] = (2, tim)
                    await self._availRingSchQueue.put(vq)
            else:
                await RisingEdge(self.dut.clk)

    def create_vq(self, vq, cfg, dev_id, bdf, qdepth):
        self.log.info("create_queue {} dev_id {} bdf {} qdepth {}".format(vq_str(vq), dev_id, hex(bdf), qdepth))
        if vq in self.ctxs.keys():
            raise ValueError("The ctxs(vq:{}) is exists".format(vq_str(vq)))
        self.ctxs[vq] = VirtioCtx(mem=self.mem, cfg=cfg, dev_id=dev_id, bdf=bdf, qdepth=qdepth)
    
    def destroy_vq(self, vq):
        self.log.info("destroy_queue {}".format(vq_str(vq)))
        if vq not in self.ctxs.keys():
            raise ValueError("The ctxs(vq:{}) is not exists".format(vq_str(vq)))
        if self.ctxs[vq]._ctrl != q_status_type_t.idle:
            raise ValueError("The (vq:{}) status is not idle".format(vq_str(vq)))
        del self.ctxs[vq]

    async def start_vq(self, vq):
        self.log.info("start_vq {}".format(vq_str(vq)))
        if vq not in self.ctxs.keys():
            raise ValueError("The ctxs(vq:{}) is not exists".format(vq_str(vq)))
        if self.ctxs[vq]._ctrl != q_status_type_t.idle:
            raise ValueError("The (vq:{}) status is not idle".format(vq_str(vq)))
        self.ctxs[vq]._sw_avail_idx     = 0
        self.ctxs[vq]._avail_idx        = 0
        self.ctxs[vq]._avail_ui         = 0
        self.ctxs[vq]._no_notify        = 0
        self.ctxs[vq]._dma_req_num      = 0
        self.ctxs[vq]._dma_rsp_num      = 0
        self.ctxs[vq]._no_notify        = False
        self.ctxs[vq]._no_change        = False
        self.ctxs[vq]._err_code         = ERR_CODE.VIRTIO_ERR_CODE_NONE
        self.ctxs[vq]._fault_injection  = ERR_CODE.VIRTIO_ERR_CODE_NONE
        self.ctxs[vq]._injection        = False
        await self.ctxs[vq]._avail_ring.write(2, (int(self.ctxs[vq]._sw_avail_idx).to_bytes(2, byteorder="little")))
        await self.ctxs[vq]._used_ring.write(0, (int(0).to_bytes(2, byteorder="little")))
        self.ctxs[vq]._ctrl             = q_status_type_t.doing
        await RisingEdge(self.dut.clk)
        await self._sendDoorbellQueue.put(vq)
        await Timer(4, "us")
        
    
    async def resume_vq(self, vq):
        self.log.info("resume_vq {}".format(vq_str(vq)))
        if vq not in self.ctxs.keys():
            raise ValueError("The ctxs(vq:{}) is not exists".format(vq_str(vq)))
        if self.ctxs[vq]._ctrl != q_status_type_t.stopping or  self.ctxs[vq]._force_shutdown:
            raise ValueError("The (vq:{}) status({} force_shutdown:{}) is ready".format(vq_str(vq), q_stat_str(self.ctxs[vq]._ctrl), self.ctxs[vq]._force_shutdown))
        self.ctxs[vq]._ctrl = q_status_type_t.doing
        await RisingEdge(self.dut.clk)
        

    async def stop_vq(self, vq, force_shutdown=True):
        self.log.info("stop_vq {}".format(vq_str(vq)))
        if vq not in self.ctxs.keys():
            raise ValueError("The ctxs(vq:{}) is not exists".format(vq_str(vq)))
        if self.ctxs[vq]._ctrl != q_status_type_t.doing:
            if not self.ctxs[vq]._force_shutdown:
                raise ValueError("The (vq:{}) status is not doing".format(vq_str(vq)))
            self.log.info("stop_vq {} maybe err handle(status:{})".format(vq_str(vq), q_stat_str(self.ctxs[vq]._ctrl)))
            return #maybe err handle
            
        self.ctxs[vq]._ctrl             = q_status_type_t.stopping
        self.ctxs[vq]._force_shutdown   = force_shutdown
        
        await Timer(1, "us")
        self.log.debug("wait for stop {} _dma_req_num {} _dma_rsp_num {} bitmap {}".format(vq_str(vq), self.ctxs[vq]._dma_req_num, self.ctxs[vq]._dma_rsp_num, vq in self._availRingSchBitmap.keys()))
        while (self.ctxs[vq]._dma_req_num != self.ctxs[vq]._dma_rsp_num) or (vq in self._availRingSchBitmap.keys()):
            self.log.debug("wait for stop {} _dma_req_num {} _dma_rsp_num {} bitmap {}".format(vq_str(vq), self.ctxs[vq]._dma_req_num, self.ctxs[vq]._dma_rsp_num, vq in self._availRingSchBitmap.keys()))
            await Timer(1, "us")

        self.ctxs[vq]._ctrl             = q_status_type_t.idle
        self.ctxs[vq]._force_shutdown   = 0
        self.log.info("stop_vq {} done".format(vq_str(vq)))

    async def start_xmit(self, vq, num_pkt):
        if vq not in self.ctxs.keys():
            raise ValueError("The ctxs(vq:{}) is not exists".format(vq_str(vq)))
        ctx = self.ctxs[vq]
        avail_num = ctx._qsz - ((ctx._sw_avail_idx - ctx._avail_ui) & 0xffff)
        if ctx._injection and ctx._fault_injection == ERR_CODE.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX:
            return 0

        if ctx._fault_injection != ERR_CODE.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX:
            num_pkt = min(avail_num, num_pkt)
        elif ctx._fault_injection == ERR_CODE.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX and  not ctx._injection:
            num_pkt = 2*ctx._qsz
            ctx._injection = True
        if num_pkt > 0:
            ctx._sw_avail_idx = (ctx._sw_avail_idx + num_pkt) & 0xffff
            await ctx._avail_ring.write(2, (int(ctx._sw_avail_idx).to_bytes(2, byteorder="little")))
            flags = int.from_bytes(await ctx._used_ring.read(0, 2, force=1), byteorder="little")
            if flags == VIRTQ_USED_F_NO_NOTIFY:
                pass
            elif flags == 0:
                await self._sendDoorbellQueue.put(vq)
            else:
                raise ValueError("The used flags(vq:{}) is invalid({})".format(vq_str(vq), flags))
        if ctx._injection:
            return 0
        else:
            return num_pkt

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
        await Timer(8, "us")


    def set_idle_generator(self, generator=None):   
        if generator:
            self.schReq.set_idle_generator(generator)
            self.HostRdDma.set_idle_generator(generator)
            self.IdxNotify.set_idle_generator(generator)
            self.ErrCode.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.IdxNotify.set_backpressure_generator(generator)
            self.HostRdDma.set_backpressure_generator(generator)
            self.schReq.set_backpressure_generator(generator)
            self.ErrCode.set_backpressure_generator(generator)
    async def wait_for_empty(self, vq):
        if vq not in self.ctxs.keys():
            raise ValueError("The ctxs(vq:{}) is not exists".format(vq_str(vq)))
        while self.ctxs[vq]._sw_avail_idx != self.ctxs[vq]._avail_ui or self.ctxs[vq]._dma_req_num != self.ctxs[vq]._dma_rsp_num or self.ctxs[vq]._no_notify:
            await Timer(1, "us")
        await Timer(8, "us")
        flags = int.from_bytes(await self.ctxs[vq]._used_ring.read(0, 2, force=1), byteorder="little")
        if flags == VIRTQ_USED_F_NO_NOTIFY:
            raise ValueError("The ctxs(vq:{}) no_notify is on(sw_avail_idx {} avail_ui {} _no_notify {} flags {})".format(vq_str(vq), self.ctxs[vq]._sw_avail_idx, self.ctxs[vq]._avail_ui, self.ctxs[vq]._no_notify, flags))
    async def worker(self, vq):
        max_seq = self.ctxs[vq]._cfg.max_seq
        seq_num = 0
        while seq_num != max_seq or self.ctxs[vq]._ctrl != q_status_type_t.doing:
            if self.ctxs[vq]._ctrl == q_status_type_t.idle:
                if self.ctxs[vq]._injection:
                    if self.ctxs[vq]._fault_injection != self.ctxs[vq]._err_code:
                        raise ValueError("vq:{} err_code is mismatch(cur:{} exp:{}".format(vq_str(vq), err_code_str(self.ctxs[vq]._err_code), err_code_str(self.ctxs[vq]._fault_injection)))
                    else:
                        self.log.info("fault_injection(vq:{} err_code:{}) is success".format(vq_str(vq), err_code_str(self.ctxs[vq]._err_code)))
                await self.start_vq(vq)
            pkt_num = min(max_seq - seq_num, random.randint(8, 32))
            pkt_num = await self.start_xmit(vq, pkt_num)
            if pkt_num > 0:
                self.log.info("start_xmit {} seq_num {} pkt_num {}".format(vq_str(vq), seq_num, pkt_num))
            seq_num += pkt_num
            if pkt_num > 0 and random.randint(0, 100) > 95 and not self.ctxs[vq]._injection:
                self.log.info("vq {} wait_for_empty".format(vq_str(vq)))
                await self.wait_for_empty(vq)
                self.log.info("vq {} is_empty".format(vq_str(vq)))
            elif pkt_num > 0 and random.randint(0, 100) > 95 and self.ctxs[vq]._cfg.life_cycle_en and not self.ctxs[vq]._injection:
                self.log.info("vq {} life_cycle".format(vq_str(vq)))
                await self.stop_vq(vq, force_shutdown=self.ctxs[vq]._cfg.force_shutdown_en)
            elif pkt_num > 0 and random.randint(0, 100) > 95 and self.ctxs[vq]._cfg.fault_injection_en and not self.ctxs[vq]._injection:
                self.ctxs[vq]._fault_injection = random.choice(self.ctxs[vq]._cfg.fault_list)
                self.log.info("The fault({}) is about to be injected(vq {})".format(err_code_str(self.ctxs[vq]._fault_injection), vq_str(vq)))
                if self.ctxs[vq]._fault_injection == ERR_CODE.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR:
                    if random.randint(0, 100) > 50:
                        self.ctxs[vq]._avail_ring.defect_injection(2, 2)
                    else:
                        await self.wait_for_empty(vq)#Ensure the read operation targets the injected error address.
                        self.ctxs[vq]._used_ring.defect_injection(0, 2)
                    self.ctxs[vq]._injection = True
            await Timer(1, "us")
        self.log.info("vq {} done seq_num {} max_seq {}".format(vq_str(vq), seq_num, max_seq)) 
        await self.stop_vq(vq, force_shutdown=self.ctxs[vq]._cfg.force_shutdown_en)
        await Timer(8, "us")

async def run_test(dut, cfg = None, idle_inserter=None, backpressure_inserter=None):
    time_seed = 123#int(time.time())
    random.seed(time_seed)
    if cfg == None:
        cfg = smoke_cfg
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    worker_cr = {}
    await tb.cycle_reset()
    qid_list = gen_q_list(cfg.q_num)
    for typ in cfg.type_list:
        for qid in qid_list:
            vq = qid2vq(qid, typ)
            qszWidth = random.choice(cfg.qsz_width_list)
            tb.create_vq(vq, cfg, random.randint(0, 1023), random.randint(0, 65535), qszWidth)
            worker_cr[vq] = cocotb.start_soon(tb.worker(vq))
    
    await Timer(10, "us")

    for typ in cfg.type_list:
        for qid in qid_list:
            vq = qid2vq(qid, typ)
            await worker_cr[vq].join()
            tb.destroy_vq(vq)
 

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

#ding_robot.ding_robot()

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [cycle_pause])
        factory.add_option("backpressure_inserter", [cycle_pause])
        factory.add_option("cfg", [fault_injection_cfg])
        factory.generate_tests()
        

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
