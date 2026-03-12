#!/usr/bin/env python3
################################################################################
#  文件名称 : test_virtio_blk_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/10/21
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  10/21     Joe Jiang   初始化版本
################################################################################
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import math
import random
import numpy as np
import cocotb_test.simulator
import time

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time

import numpy as np

sys.path.append('../../common')
from address_space import Pool, AddressSpace, MemoryRegion
from bus.tlp_adap_dma_bus import DmaWriteBus, DmaReadBus
from monitors.tlp_adap_dma_bus import DmaRam
from bus.beq_data_bus import BeqBus
from drivers.beq_data_bus import BeqTxqMaster
from monitors.beq_data_bus import BeqRxqSlave
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster
from virtio_defines import *
from virtio_ctrl import *
from virtio_pmd import *
from virtio_blk import *

class QosIf:
    query_req_if: QosReqSlaver
    query_rsp_if: QosRspMaster
    update_if   : QosUpdateSlaver

class Interfaces:
    dma_if      : DmaRam
    doorbell_if : DoorbellReqSource
    blk2beq_if  : BeqRxqSlave
    beq2blk_if  : BeqTxqMaster
    blk_qos     : QosIf
    csr_if      : MliteBusMaster

class TB(object):
    def __init__(self, cfg, dut):
        self.dut = dut
        self.cfg: Cfg = cfg
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.worker_cr = {}
        cocotb.start_soon(Clock(dut.clk, 5, units="ns").start())
        self.mem                                = Pool(None, 0, size=2**64, min_alloc=64)
        self.interfaces                         = Interfaces()
        self.interfaces.blk_qos                 = QosIf()
        self.interfaces.dma_if                  = DmaRam(DmaWriteBus.from_prefix(dut, "dma"), DmaReadBus.from_prefix(dut, "dma"), dut.clk, dut.rst, mem=self.mem, latency=cfg.dma_latency)
        self.interfaces.doorbell_if             = DoorbellReqSource(DoorbellReqBus.from_prefix(dut, "doorbell_req"), dut.clk, dut.rst)
        self.interfaces.blk2beq_if              = BeqRxqSlave(BeqBus.from_prefix(dut, "blk2beq"), dut.clk, dut.rst)
        self.interfaces.beq2blk_if              = BeqTxqMaster(BeqBus.from_prefix(dut, "beq2blk"), dut.clk, dut.rst)
        self.interfaces.blk_qos.query_req_if    = QosReqSlaver(QosReqBus.from_prefix(dut, "blk_qos_query_req"), dut.clk, dut.rst)
        self.interfaces.blk_qos.query_rsp_if    = QosRspMaster(QosRspBus.from_prefix(dut, "blk_qos_query_rsp"), dut.clk, dut.rst)
        self.interfaces.blk_qos.update_if       = QosUpdateSlaver(QosUpdateBus.from_prefix(dut, "blk_qos_update"), dut.clk, dut.rst)
        self.interfaces.csr_if                  = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)
        self.soc_notify_queues                  = {}
        self.virtio_ctrl                    = VirtioCtrl(self.cfg, self.log, self.soc_notify_queues, self.interfaces.csr_if)
        self.virtio_pmd                     = Virt(self.cfg, self.log, self.mem, self.virtio_ctrl, self.soc_notify_queues, self.interfaces.doorbell_if)
        self.virtio_blk                     = VirtBlk(self.cfg, self.log, self.mem, self.virtio_pmd, self.interfaces)
        self.bdf2vq                         = {}
        cocotb.start_soon(self.virtio_pmd.doorbell_service())

    def set_idle_generator(self, generator=None):
        if generator:
            self.interfaces.dma_if.set_idle_generator(generator)
            self.interfaces.doorbell_if.set_idle_generator(generator)
            self.interfaces.beq2blk_if.set_idle_generator(generator)
            self.interfaces.blk_qos.query_rsp_if.set_idle_generator(generator)
            self.interfaces.csr_if.set_idle_generator(generator)


    def set_backpressure_generator(self, generator=None):
        if generator:
            self.interfaces.dma_if.set_backpressure_generator(generator)
            self.interfaces.blk2beq_if.set_backpressure_generator(generator)
            self.interfaces.blk_qos.query_req_if.set_backpressure_generator(generator)
            self.interfaces.blk_qos.update_if.set_backpressure_generator(generator)
            self.interfaces.csr_if.set_backpressure_generator(generator)

    async def cycle_reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await Timer(1, "us")
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await Timer(8, "us")
        if self.cfg.force_shutdown_en:
            cocotb.start_soon(self._dma_mon())
    
    async def _dma_mon(self):
        wr_dma_vld = self.dut.wr_dma_vld
        wr_dma_sop = self.dut.wr_dma_sop
        wr_dma_bdf = self.dut.wr_dma_bdf
        rd_dma_vld = self.dut.rd_dma_vld
        rd_dma_bdf = self.dut.rd_dma_bdf
        num_wr_chn = len(wr_dma_vld)
        num_rd_chn = len(rd_dma_vld)
        while True:
            await RisingEdge(self.dut.clk) 
            wr_vld = wr_dma_vld.value & wr_dma_sop.value
            if wr_vld:
                for i in range(num_wr_chn):
                    if wr_vld & (1<<i):
                        bdf = (wr_dma_bdf.value >> 16*i) & 0xffff
                        vq = self.bdf2vq[bdf]
                        if self.virtio_pmd.virtq[vq].forced_shutdown_flag:
                            self.log.error("Illegal write DMA({} bdf{}) request, the queue has already been closed.".format(vq_str(vq), bdf))
                            raise Exception("Illegal request, the queue has already been closed.")
            rd_vld = rd_dma_vld.value
            if rd_vld:
                for i in range(num_rd_chn):
                    if rd_vld & (1<<i):
                        bdf = (rd_dma_bdf.value >> 16*i) & 0xffff
                        vq = self.bdf2vq[bdf]
                        if self.virtio_pmd.virtq[vq].forced_shutdown_flag:
                            self.log.error("Illegal read DMA({} bdf{}) request, the queue has already been closed.".format(vq_str(vq), bdf))
                            raise Exception("Illegal request, the queue has already been closed.")
                         

    async def worker(self, vq):
        qid, typ = vq2qid(vq)
        await self.virtio_pmd.start(vq, 0)
        mbufs = []
        seq_num = 0
        target_finish_seq_num = None
        while qid not in self.virtio_blk._req_queues.keys():
            await Timer(1, "us")
        while not self.virtio_blk.done[qid]:
            if not self.virtio_blk._req_queues[qid].empty():
                mbufs.append(await self.virtio_blk._req_queues[qid].get())
                if random.randint(0, 100) > 80 or seq_num == self.cfg.max_seq - 1 or len(mbufs) > 32:
                    self.log.debug("{} get burst_xmit len(mbufs) {}".format(vq_str(vq), len(mbufs)))
                    seq_num = seq_num + len(mbufs)
                    mbufs = await self.virtio_pmd.burst_xmit(vq, mbufs)
                    seq_num = seq_num - len(mbufs)
            else:
                if not self.virtio_pmd.virtq[vq].msix_en:
                    await self.virtio_pmd.burst_xmit(vq, [])
                await Timer(4, "us")
            if self.cfg.life_cycle_en:
                if target_finish_seq_num == None:
                    target_finish_seq_num = self.virtio_blk._finish_seq_num[qid] + random.randint(8, 32)
                elif target_finish_seq_num < self.virtio_blk._finish_seq_num[qid]:
                    pending_hdrs = await self.virtio_pmd.stop(vq, forced_shutdown=random.randint(0, 100) > 50 if self.cfg.force_shutdown_en else False)
                    for hdr in pending_hdrs:
                        del self.virtio_blk._info_dicts[qid][hdr.ioprio]
                        seq_num = seq_num - 1
                    await self.virtio_pmd.start(vq)
                    target_finish_seq_num = None
        pending_hdrs = await self.virtio_pmd.stop(vq)
        for hdr in pending_hdrs:
            del self.virtio_blk._info_dicts[qid][hdr.ioprio]
        for mbuf in mbufs:
            for reg in mbuf.regs:
                self.mem.free_region(reg)

async def run_test(dut, indirct_support=None, indirct_mix=None, cfg = None, idle_inserter = None, backpressure_inserter = None):
    time_seed = 123#int(time.time())
    random.seed(time_seed)
    if cfg == None:
        cfg = smoke_cfg
    tb = TB(cfg, dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    qid_list = gen_q_list(cfg.q_num)
    worker_cr = {}
    typ = TestType.BLK
    #create_queue
    for qid in qid_list:
        vq = qid2vq(qid, typ)
        qszWidth = random.choice(cfg.qsz_width_list)
        bdf = random.randint(0, 65536)
        while bdf in tb.bdf2vq.keys():
            bdf = random.randint(0, 65536)
        tb.bdf2vq[bdf] = vq
        tb.virtio_pmd.create_queue(vq, qszWidth, 
                                        cfg.max_len,
                                        msix_en=random.randint(0,1) if cfg.msix_en else 0,
                                        indirct_support=random.randint(0,1) if cfg.indirct_support else 0, 
                                        qos_en=random.randint(0,1) if cfg.qos_en else 0, 
                                        bdf = bdf, dev_id=random.randint(0, 1024))
        worker_cr[qid] = cocotb.start_soon(tb.worker(vq))
    tb.virtio_blk.start(qid_list)
    for qid in qid_list:
        await worker_cr[qid].join()
    await tb.virtio_blk.join(qid_list)
    #destroy_queue
    for qid in qid_list:
        vq = qid2vq(qid, typ)
        await tb.virtio_pmd.destroy_queue(vq)

    for (base, size, translate, region) in tb.mem.regions: # 查看是否所有空间都释放了
        tb.log.error(f"base:{base:x} size:{size} translate:{translate} region:{region} bdf:{region._bdf} dev_id:{region._dev_id}")

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

import ding_robot
ding_robot.ding_robot()
#sys.path.append('../common'); from debug import *
debug = 0
if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        if debug:
            factory.add_option("cfg", [smoke_cfg])
        else:
            factory.add_option("cfg", [test_1Q_short_chian_cfg, test_nQ_short_chian_cfg, test_1Q_long_chian_cfg, test_nQ_long_chian_cfg, test_1Q_life_cycle_cfg, test_nQ_life_cycle_cfg, test_1Q_force_shutdown_cfg, test_nQ_force_shutdown_cfg])
        factory.add_option("idle_inserter", [cycle_pause])
        factory.add_option("backpressure_inserter", [cycle_pause])
        factory.generate_tests()

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
