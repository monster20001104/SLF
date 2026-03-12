#!/usr/bin/env python3
################################################################################
#  文件名称 : test_virtio_avail_ring_tb.py
#  作者名称 : Yun Feilong
#  创建日期 : 2025/07/17
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/17     Yun Feilong   初始化版本
################################################################################
import math
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
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
from cocotb.handle import Force
import numpy as np

sys.path.append('../../common')
from bus.tlp_adap_dma_bus import DmaReadBus, Desc
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace
from enum import Enum, unique
from defines import *
#import ding_robot


class ERR_CODE  :
    VIRTIO_ERR_CODE_NONE                                        = 0x00
    VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR                            = 0x71
    VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX                         = 0x72
    VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE                           = 0x03
    VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR                          = 0x04
    VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE                 = 0x10
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE            = 0x11
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE       = 0x12
    VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT                  = 0x13
    VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO                  = 0x14
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC                = 0x15
    VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO              = 0x16
    VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE               = 0x17
    VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN                      = 0x18
    VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR                           = 0x19
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE              = 0x1a
    VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE              = 0x1b
    VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR                           = 0x20
    VIRTIO_ERR_CODE_NETTX_PCIE_ERR                              = 0x30
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE             = 0x40
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE        = 0x41
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE   = 0x42
    VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT              = 0x43
    VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO              = 0x44
    VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC            = 0x45
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO             = 0x46
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE             = 0x47
    VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR                       = 0x48
    VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR                           = 0x50


class SET_CTRL:
    SET_ID_ERR = 0x1
    SET_TLP_ERR = 0x2
    SET_QSTOP_FORCE_DOWN = 0x3
    SET_QSTOP_STOPPING = 0x4

class Q_STATUS  :
    VIRTIO_Q_STATUS_IDLE       = 0x1
    VIRTIO_Q_STATUS_STATING    = 0x2
    VIRTIO_Q_STATUS_DOING      = 0x4
    VIRTIO_Q_STATUS_STOPPING   = 0x8


class vQueue():
    def __init__(self, log, mem, vq, depth, bdf, avail_idx, avail_pi, avail_ui, avail_ci,set_ctrl,vq_busy):
        self.log = log
        self._mem = mem
        self._vq = vq
        self._depth = depth
        self._forced_shutdown = 0
        self.vq_busy = vq_busy
        self._bdf = bdf
        self._depth_log2 = int(math.log2(self._depth))
        self._q_status = q_status_type_t.idle
        self._avail_ring = self._mem.alloc_region(self._depth*2+4, bdf=self._bdf)
        self._desc_idx_pool = [i for i in range(self._depth)]
        self._avail_idx = avail_idx
        self._avail_pi = avail_pi
        self._avail_ui = avail_ui
        self._avail_ci = avail_ci
        self.ref_results = []
        self.set_ctrl = set_ctrl
        self.test_finish = 0

        cocotb.start_soon(self._test())

    async def _test(self):
        while self._avail_pi == 0:
            await Timer(4, 'ns')
        if(self.set_ctrl[self._vq] == SET_CTRL.SET_QSTOP_STOPPING):
            await self._test_stopping()
        self.test_finish = 1

    async def _test_stopping(self):
        await Timer(400, 'ns')
        await self.stop_stopping()
        self._avail_ui = self._avail_idx
        self._avail_pi = self._avail_idx
        self.ref_results.clear()
        self._q_status = q_status_type_t.idle

    async def gen_a_chain(self, seq_num):
        if(self.set_ctrl[self._vq] == 0 or self.set_ctrl[self._vq] == SET_CTRL.SET_QSTOP_STOPPING):
            id = random.randint(0, len(self._desc_idx_pool)-1)
            ring_id = self._desc_idx_pool.pop(id)
            await self._avail_ring.write(4+self._avail_idx*2, int(ring_id).to_bytes(2, "little"))
            self.log.info("gen_a_chain vq{} ".format(vq_str(self._vq))) 
            err = ErrInfo(fatal=0, err_code=0)  
            self.ref_results.append(RefResult(ring_id, self._avail_idx, err, seq_num))
            self._avail_idx = (self._avail_idx+1) & (self._depth-1)
        elif(self.set_ctrl[self._vq] == SET_CTRL.SET_ID_ERR) :
            ring_id = 65535
            err = ErrInfo(fatal=1, err_code=ERR_CODE.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE)
            await self._avail_ring.write(4+self._avail_idx*2, int(ring_id).to_bytes(2, "little")) 
            self.log.info("gen_a_chain vq{} ".format(vq_str(self._vq)))  
            self.ref_results.append(RefResult(ring_id, self._avail_idx, err, seq_num))
            self._avail_idx = (self._avail_idx+1) & (self._depth-1)
        elif(self.set_ctrl[self._vq] == SET_CTRL.SET_TLP_ERR):
            err = ErrInfo(fatal=1, err_code=ERR_CODE.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR)  
            ring_id = 0
            self.ref_results.append(RefResult(ring_id, self._avail_idx, err, seq_num))
            await self._avail_ring.write(4+self._avail_idx*2, int(ring_id).to_bytes(2, "little"),defect_injection = 1)
            self.log.info("gen_a_chain vq{} ".format(vq_str(self._vq))) 
            self._avail_idx = (self._avail_idx+1) & (self._depth-1)

    def start(self):
        self._q_status = q_status_type_t.doing
    
    async def stop_stopping(self):
        self._q_status = q_status_type_t.stopping
        await Timer(20, "ns")
        rd_num_stop = self._avail_ui
        cnt = 0
        while cnt < 10 :
            await Timer(20, 'ns')
            assert rd_num_stop == self._avail_ui
            cnt = cnt + 1
        while self.vq_busy == 1:
            await Timer(20, 'ns')

class VirtQ():
    def __init__(self, mem, log, dut,set_ctrl):
        self.log = log
        self._mem = mem
        self._dut = dut
        self.set_ctrl = set_ctrl
        self.vq_busy = 0
        self.dmaRingIdIf = DmaRam(None, DmaReadBus.from_prefix(dut, "dma_ring_id"), dut.clk, dut.rst, mem=mem)
        self.schReqSource = SchReqSource(SchReqBus.from_prefix(dut, "sch_req"), dut.clk, dut.rst)
        
        self.nettxNotifyReqSink = NettxNotifyReqSink(NettxNotifyReqBus.from_prefix(dut, "nettx_notify_req"), dut.clk, dut.rst)
        self.nettxNotifyReqSink.queue_occupancy_limit = 2
        self.blkNotifyReqSink = BlkNotifyReqSink(BlkNotifyReqBus.from_prefix(dut, "blk_notify_req"), dut.clk, dut.rst)
        self.blkNotifyReqSink.queue_occupancy_limit = 2

        self.netrxAvailIdReqSource  = NetrxAvailIdReqSource(NetrxAvailIdReqBus.from_prefix(dut, "netrx_avail_id_req"), dut.clk, dut.rst)
        self.netrxAvailIdRspSink    = NetrxAvailIdRspSink(NetrxAvailIdRspBus.from_prefix(dut, "netrx_avail_id_rsp"), dut.clk, dut.rst)
        self.nettxAvailIdReqSource  = NettxAvailIdReqSource(NettxAvailIdReqBus.from_prefix(dut, "nettx_avail_id_req"), dut.clk, dut.rst)
        self.nettxAvailIdRspSink    = NettxAvailIdRspSink(NettxAvailIdRspBus.from_prefix(dut, "nettx_avail_id_rsp"), dut.clk, dut.rst)
        self.blkAvailIdReqSource    = BlkAvailIdReqSource(BlkAvailIdReqBus.from_prefix(dut, "blk_avail_id_req"), dut.clk, dut.rst)
        self.blkAvailIdRspSink      = BlkAvailIdRspSink(BlkAvailIdRspBus.from_prefix(dut, "blk_avail_id_rsp"), dut.clk, dut.rst)
        self.vqPendingChkReqSource  = VqPendingChkReqSource(VqPendingChkReqBus.from_prefix(dut, "vq_pending_chk_req"), dut.clk, dut.rst)
        self.vqPendingChkRspSink    = VqPendingChkRspSink(VqPendingChkRspBus.from_prefix(dut, "vq_pending_chk_rsp"), dut.clk, dut.rst)

        self.availIdRdTbl = AvailIdRdTbl(AvailIdRdReqBus.from_prefix(dut, "avail_addr"), AvailIdRdRspBus.from_prefix(dut, "avail_addr"), None, dut.clk, dut.rst)
        def _availIdRdCallback(req_obj):
            vq = int(req_obj.rd_req_qid)
            if vq not in self._q.keys():
                raise ValueError("The queue(vq:{}) is not exists".format(vq_str(vq)))
            rsp = AvailIdRdRspTransaction()
            rsp.rd_rsp_data = self._q[vq]._avail_ring.get_absolute_address(0)
            return rsp
        self.availIdRdTbl.set_callback(_availIdRdCallback)

        self.availPiTbl = AvailPiTbl(None, None, AvailPiWrBus.from_prefix(dut, "avail_pi"), dut.clk, dut.rst)
        def _availPiWrCallback(req_obj):
            vq              = int(req_obj.wr_req_qid)
            if vq not in self._q.keys():
                raise ValueError("The queue(vq:{}) is not exists".format(vq_str(vq)))
            self._q[vq]._avail_pi     = int(req_obj.wr_req_data)
            return
        self.availPiTbl.set_wr_callback(_availPiWrCallback)


        self.availUiTbl = AvailUiTbl(None, None, AvailUiWrBus.from_prefix(dut, "avail_ui"), dut.clk, dut.rst)
        def _availUiWrCallback(req_obj):
            vq              = int(req_obj.wr_req_qid)
            if vq not in self._q.keys():
                raise ValueError("The queue(vq:{}) is not exists".format(vq_str(vq)))
            self._q[vq]._avail_ui     = int(req_obj.wr_req_data)
            return
        self.availUiTbl.set_wr_callback(_availUiWrCallback)

        self.dmaCtxInfoRdTbl = DmaCtxInfoRdTbl(DmaCtxInfoRdReqBus.from_prefix(dut, "dma_ctx_info"), DmaCtxInfoRdRspBus.from_prefix(dut, "dma_ctx_info"), None, dut.clk, dut.rst)
        def _dmaCtxInfoRdCallback(req_obj):
            vq = int(req_obj.rd_req_qid)
            if vq not in self._q.keys():
                raise ValueError("The queue(vq:{}) is not exists".format(vq_str(vq)))
            rsp = AvailIdRdRspTransaction()
            rsp.rd_rsp_force_shutdown = self._q[vq]._forced_shutdown
            rsp.rd_rsp_ctrl           = self._q[vq]._q_status
            rsp.rd_rsp_bdf            = self._q[vq]._bdf
            rsp.rd_rsp_qdepth         = self._q[vq]._depth_log2
            rsp.rd_rsp_avail_idx      = self._q[vq]._avail_idx
            rsp.rd_rsp_avail_ui       = self._q[vq]._avail_ui
            rsp.rd_rsp_avail_ci       = self._q[vq]._avail_ci
            return rsp
        self.dmaCtxInfoRdTbl.set_callback(_dmaCtxInfoRdCallback)

        self.availCiTbl = AvailCiTbl(None, None, AvailCiWrBus.from_prefix(dut, "avail_ci"), dut.clk, dut.rst)
        def _availCiWrCallback(req_obj):
            vq              = int(req_obj.wr_req_qid)
            if vq not in self._q.keys():
                raise ValueError("The queue(vq:{}) is not exists".format(vq_str(vq)))
            self._q[vq]._avail_ci     = int(req_obj.wr_req_data)
            return
        self.availCiTbl.set_wr_callback(_availCiWrCallback)

        self.descEngineCtxInfoRdTbl = DescEngineCtxInfoRdTbl(DescEngineCtxInfoRdReqBus.from_prefix(dut, "desc_engine_ctx_info"), DescEngineCtxInfoRdRspBus.from_prefix(dut, "desc_engine_ctx_info"), None, dut.clk, dut.rst)
        def _descEngineCtxInfoRdCallback(req_obj):
            vq = int(req_obj.rd_req_qid)
            if vq not in self._q.keys():
                raise ValueError("The queue(vq:{}) is not exists".format(vq_str(vq)))
            rsp = AvailIdRdRspTransaction()
            rsp.rd_rsp_force_shutdown = self._q[vq]._forced_shutdown
            rsp.rd_rsp_ctrl           = self._q[vq]._q_status
            rsp.rd_rsp_avail_pi       = self._q[vq]._avail_pi
            rsp.rd_rsp_avail_idx      = self._q[vq]._avail_idx
            rsp.rd_rsp_avail_ui       = self._q[vq]._avail_ui
            rsp.rd_rsp_avail_ci       = self._q[vq]._avail_ci
            return rsp
        self.descEngineCtxInfoRdTbl.set_callback(_descEngineCtxInfoRdCallback)

        self._q = {}
        self.ref_nettx_notify_queue = Queue()
        self.ref_blk_notify_queue = Queue()
        cocotb.start_soon(self.rd_id_req_thd(TestType.NETRX, self.netrxAvailIdReqSource))
        cocotb.start_soon(self.rd_id_rsp_thd(TestType.NETRX, self.netrxAvailIdRspSink))
        cocotb.start_soon(self.rd_id_req_thd(TestType.NETTX, self.nettxAvailIdReqSource))
        cocotb.start_soon(self.rd_id_rsp_thd(TestType.NETTX, self.nettxAvailIdRspSink))
        cocotb.start_soon(self.rd_id_req_thd(TestType.BLK  , self.blkAvailIdReqSource))
        cocotb.start_soon(self.rd_id_rsp_thd(TestType.BLK  , self.blkAvailIdRspSink))
        cocotb.start_soon(self.dma_req_monitor())
        cocotb.start_soon(self.check_nettx_notify())
        cocotb.start_soon(self.check_blk_notify())
        cocotb.start_soon(self.vqpending_driver())
        cocotb.start_soon(self.vqpending_monitor())
    
    async def vqpending_driver(self):
        while True:
            await Timer(1, 'ns')
            for vq in list(self._q.keys()):
                await Timer(20, 'ns')
                obj = self.vqPendingChkReqSource._transaction_obj()
                obj.vq = vq
                await self.vqPendingChkReqSource.send(obj)

    async def vqpending_monitor(self):
        while True:
            await Timer(20, 'ns')
            self.vq_busy = await self.vqPendingChkRspSink.recv()
            
    def set_queue(self, typ, qid, depth=32768, bdf=None):
        if bdf == None:
            bdf=random.randint(0, 65535)
        vq = qid2vq(qid, typ)
        self._q[vq] = vQueue(self.log, self._mem, vq, depth, bdf, avail_idx=0, avail_pi=0, avail_ui=0, avail_ci=0,set_ctrl = self.set_ctrl,vq_busy = self.vq_busy)
        self._q[vq].start()
    async def gen_a_pkt(self, typ, qid, seq_num=0):
        vq = qid2vq(qid, typ)
        if vq not in self._q.keys():
            raise ValueError("The queue(vq:{}) is not exists".format(vq_str(vq)))
        await self._q[qid2vq(qid, typ)].gen_a_chain(seq_num)
        obj = self.schReqSource._transaction_obj()
        obj.qid = VirtioVq(typ=typ, qid=qid).pack()
        await self.schReqSource.send(obj)

    async def dma_req_monitor(self):
        while True:
            if self._dut.dma_ring_id_rd_req_val.value:
                desc_data = self._dut.dma_ring_id_rd_req_desc.value
                desc = Desc().unpack(desc_data)
                addr = desc.pcie_addr
                qid = None
                typ = None
                for vq in self._q.keys():
                    start_addr = self._q[vq]._avail_ring.get_absolute_address(0)
                    end_addr = start_addr + self._q[vq]._avail_ring.size
                    if addr >= start_addr and addr < end_addr:
                        qid, typ = vq2qid(vq)
                if typ == TestType.NETTX:
                    self.ref_nettx_notify_queue.put_nowait(qid)
                elif typ == TestType.BLK:
                    self.ref_blk_notify_queue.put_nowait(qid)
            await RisingEdge(self._dut.clk)

    async def check_blk_notify(self):
        cnt = 0
        while True:
            cnt = cnt + 1
            ref_qid = await self.ref_blk_notify_queue.get()
            
            req = await self.blkNotifyReqSink.recv()
            if req.qid != ref_qid:
                raise ValueError("err blk notify qid{} ref {} rsp {}".format(ref_qid, ref_qid, req.qid))
    async def check_nettx_notify(self):
        while True:
            ref_qid = await self.ref_nettx_notify_queue.get()
            req = await self.nettxNotifyReqSink.recv()
            if req.qid != ref_qid:
                raise ValueError("err nettx notify qid{} ref {} rsp {}".format(ref_qid, ref_qid, req.qid))

    async def rd_id_req_thd(self, typ, req_if):
        while True:
            await Timer(1, "ns")
            for vq in list(self._q.keys()):
                _qid, _typ = vq2qid(vq)
                if typ != _typ:
                    continue
                if len(self._q[vq].ref_results) == 0:
                    continue
                req = req_if._transaction_obj()
                req.data = _qid
                if _typ == TestType.NETRX or _typ == TestType.BLK:
                    req.nid = 1
                else:
                    req.nid = min(4, len(self._q[vq].ref_results))
                await req_if.send(req)
                if(random.randint(0,100)<50):
                    await Timer(200, 'ns')

    async def rd_id_rsp_thd(self, typ, rsp_if):
        sop = True
        vq = None
        while True:
            rsp_data = await rsp_if.recv()
            rsp = AvailIdRspDat().unpack(rsp_data.data)
            if sop:
                vq = rsp.vq
            else:
                if vq != rsp.vq:
                    raise ValueError("vq mismatch ref vq{} cur vq {}".format(vq_str(vq), vq_str(rsp.vq)))
            if not rsp.local_ring_empty:
                if(self.set_ctrl[rsp.vq] == 0 ):
                    assert rsp.err_info == 0
                elif(self.set_ctrl[rsp.vq] == SET_CTRL.SET_ID_ERR) :
                    assert (rsp.err_info & 0x7f) == ERR_CODE.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE
                    assert (rsp.err_info & 0x80) == 0x80
                elif(self.set_ctrl[rsp.vq] == SET_CTRL.SET_TLP_ERR) :
                    assert (rsp.err_info & 0x7f)  == ERR_CODE.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR
                    assert (rsp.err_info & 0x80) == 0x80

            if rsp.q_stat_doing :
                if not rsp.local_ring_empty :
                        self.log.info("rcv_qid = {},ring_id = {},avail_idx= {}".format(vq_str(rsp.vq),rsp.id,rsp.avail_idx))
                        ref = self._q[rsp.vq].ref_results.pop(0)
                        if rsp.id != ref.ring_id:
                            raise ValueError("ring id mismatch vq{} seq_num {} ref {} rsp {}".format(vq_str(rsp.vq), ref.seq_num, ref.ring_id, rsp.id))
                        if rsp.avail_idx != ref.avail_idx:
                            raise ValueError("ring id mismatch vq{} seq_num {} ref {} rsp {}".format(vq_str(rsp.vq), ref.seq_num, ref.avail_idx, rsp.avail_idx))
                        err_info = ErrInfo().unpack(int(rsp.err_info))
                        if err_info != ref.err:

                            raise ValueError("err mismatch vq{} seq_num {} ref {} rsp {}".format(vq_str(rsp.vq), ref.seq_num, ref.err.show(dump=True), err_info.err.show(dump=True)))
                else:
                        pass
            else:
                self.log.info("vq:{} is not work!".format(vq_str(vq)))
                sop = rsp_data.eop

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.set_ctrl = {}
        for i in range (256*3) :
            self.set_ctrl[i] = 0

        self.mem = Pool(None, 0, size=2**64, min_alloc=64)
        self.virtQ = VirtQ(self.mem, self.log, dut,self.set_ctrl)
        


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
        self.virtQ.schReqSource.set_idle_generator(generator)
        self.virtQ.netrxAvailIdReqSource.set_idle_generator(generator)
        self.virtQ.netrxAvailIdRspSink.set_idle_generator(generator)
        self.virtQ.nettxAvailIdReqSource.set_idle_generator(generator)
        self.virtQ.nettxAvailIdRspSink.set_idle_generator(generator)
        self.virtQ.blkAvailIdReqSource.set_idle_generator(generator)
        self.virtQ.blkAvailIdRspSink.set_idle_generator(generator)
        self.virtQ.nettxNotifyReqSink.set_idle_generator(generator)
        self.virtQ.blkNotifyReqSink.set_idle_generator(generator)
        self.virtQ.dmaRingIdIf.set_idle_generator(generator)
        
    def set_backpressure_generator(self, generator=None):
        self.virtQ.schReqSource.set_backpressure_generator(generator)
        self.virtQ.netrxAvailIdReqSource.set_backpressure_generator(generator)
        self.virtQ.netrxAvailIdRspSink.set_backpressure_generator(generator)
        self.virtQ.nettxAvailIdReqSource.set_backpressure_generator(generator)
        self.virtQ.nettxAvailIdRspSink.set_backpressure_generator(generator)
        self.virtQ.blkAvailIdReqSource.set_backpressure_generator(generator)
        self.virtQ.blkAvailIdRspSink.set_backpressure_generator(generator)
        self.virtQ.nettxNotifyReqSink.set_backpressure_generator(generator)
        self.virtQ.blkNotifyReqSink.set_backpressure_generator(generator)
        self.virtQ.dmaRingIdIf.set_backpressure_generator(generator)


async def run_test(dut, idle_inserter = None, backpressure_inserter = None):
    random.seed(123)
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    max_q = 16
    max_seq = 10000
    type_list = [TestType.NETRX, TestType.NETTX, TestType.BLK]
    set_ctrl = [0,0,0,SET_CTRL.SET_TLP_ERR,SET_CTRL.SET_ID_ERR,SET_CTRL.SET_QSTOP_STOPPING]
    await tb.cycle_reset()
    await Timer(500, 'ns')
    tb.log.info("wait ram init")
    while tb.dut.u_virtio_avail_ring.u_virtio_ring_id_engine.u_ring_id_nettx_ram.wr_rst_1d == 1:
        await Timer(20, 'ns')
    tb.log.info("ram init done")
    workerthds = []
    async def worker(typ, qid):
        tb.virtQ.set_queue(typ, qid)
        for i in range(max_seq):
            await tb.virtQ.gen_a_pkt(typ, qid, seq_num=i)

    qid_arry = random.sample(range(256), max_q)
    task_list = []
    for qid in qid_arry:
        for typ in type_list:
            task_list.append((qid, typ))

    random.shuffle(task_list)

    for qid, typ in task_list:  
        await Timer(random.randint(1, 10), "ns")   
        workerthds.append(cocotb.start_soon(worker(typ, qid)))           
        vq = qid + typ*256
        tb.set_ctrl[vq] = random.choice(set_ctrl)

    for i in range(len(workerthds)):
        await workerthds[i].join()

    while True:
        await Timer(100, "ns")
        empty = True
        for vq in tb.virtQ._q.keys():
            q = tb.virtQ._q[vq]
            empty = empty and len(q.ref_results) == 0
        if empty == True:
            break

    for qid in qid_arry:
        for typ in type_list:
            vq = qid + typ*256
            while tb.virtQ._q[vq].test_finish == 0 :
                await Timer(4, 'ns')


    await Timer(5000, "ns")

    if not tb.virtQ.ref_blk_notify_queue.empty() or not tb.virtQ.ref_nettx_notify_queue.empty():
        if not tb.virtQ.ref_blk_notify_queue.empty():
            qid = tb.virtQ.ref_blk_notify_queue.get()
            raise ValueError("blk qid:{} blk_notify_queue is not empty".format(qid))
        if not tb.virtQ.ref_nettx_notify_queue.empty():
            qid = tb.virtQ.ref_nettx_notify_queue.get()
            raise ValueError("nettx qid:{} nettx_notify_queue is not empty".format(qid))
    await Timer(4, "us")

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None,cycle_pause])
        factory.add_option("backpressure_inserter", [None,cycle_pause])
        factory.generate_tests()


root_logger = logging.getLogger()

file_handler = RotatingFileHandler("rotating.log", maxBytes=(100 * 1024 * 1024), backupCount=1000)
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
