#!/usr/bin/env python3
################################################################################
#  文件名称 : test_beq_desc_eng_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/11/29
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  11/29     Joe Jiang   初始化版本
################################################################################
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
import numpy as np


sys.path.append('../common')
from bus.tlp_adap_dma_bus import DmaReadBus
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace
from enum import Enum, unique
from defines import *
from beq_ctx_ctrl import *
from beq_pmd_behavior import *
from beq_txq_behavior import *
from beq_rxq_behavior import *


def tx_pkt_gen(seq):
    chain = []
    for i in range(random.randint(1, max_chain_num)):
        length = random.randint(1, 2**16-1)
        addr = random.randint(0, 2**64-length)
        user0 = random.randint(0, 2**40-1)
        chain.append(beq_mbuf(addr, length, user0))
    return chain

def rx_pkt_gen(seq, max_sz):
    length = random.randint(1, max_sz)
    user0 = random.randint(0, 2**40-1)
    user1 = random.randint(0, 2**64-1)
    return length, user0, user1

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.mem = Pool(None, 0, size=2**64, min_alloc=64)
        
        self.dmaDescIf = DmaRam(None, DmaReadBus.from_prefix(dut, "dma_desc"), dut.clk, dut.rst, mem=self.mem)

        self.notifyReq = NotifyReqSource(NotifyReqBus.from_prefix(dut, "db_notify_req"), dut.clk, dut.rst)
        self.notifyRsp = NotifyRspSink(NotifyRspBus.from_prefix(dut, "db_notify_rsp"), dut.clk, dut.rst)
        #self.notifyRsp.queue_occupancy_limit = 0
        self.rxqRdNdescReq = RxqRdNdescReqSource(RxqRdNdescReqBus.from_prefix(dut, "rxq_rd_ndesc_req"), dut.clk, dut.rst)
        self.rxqRdNdescRsp = RxqRdNdescRspSink(RxqRdNdescRspBus.from_prefix(dut, "rxq_rd_ndesc_rsp"), dut.clk, dut.rst)
        #self.rxqRdNdescRsp.queue_occupancy_limit = 0
        self.txqRdNdescReq = TxqRdNdescReqSource(TxqRdNdescReqBus.from_prefix(dut, "txq_rd_ndesc_req"), dut.clk, dut.rst)
        self.txqRdNdescRsp = TxqRdNdescRspSink(TxqRdNdescRspBus.from_prefix(dut, "txq_rd_ndesc_rsp"), dut.clk, dut.rst)
        #self.txqRdNdescRsp.queue_occupancy_limit = 32
        self.newChainNotify = NewChainNotifySink(NewChainNotifyBus.from_prefix(dut, "new_chain_notify"), dut.clk, dut.rst)
        #self.newChainNotify.queue_occupancy_limit = 0

        self.ringInfoRdTbl = RingInfoRdTbl(RingInfoRdReqBus.from_prefix(dut, "ring_info_rd"), RingInfoRdRspBus.from_prefix(dut, "ring_info_rd"), None, dut.clk, dut.rst)
        self.rxqTransferTypeRdTbl = TransferTypeRdTbl(TransferTypeRdReqBus.from_prefix(dut, "rxq_transfer_type_rd"), TransferTypeRdRspBus.from_prefix(dut, "rxq_transfer_type_rd"), None, dut.clk, dut.rst)
        self.txqTransferTypeRdTbl = TransferTypeRdTbl(TransferTypeRdReqBus.from_prefix(dut, "txq_transfer_type_rd"), TransferTypeRdRspBus.from_prefix(dut, "txq_transfer_type_rd"), None, dut.clk, dut.rst)

        self.ringDbIdxRdTbl = RingDbIdxRdTbl(RingDbIdxRdReqBus.from_prefix(dut, "ring_db_idx_rd"), RingDbIdxRdRspBus.from_prefix(dut, "ring_db_idx_rd"), None, dut.clk, dut.rst)
        self.ringCiRdTbl = RingCiRdTbl(RingCiRdReqBus.from_prefix(dut, "ring_ci_rd"), RingCiRdRspBus.from_prefix(dut, "ring_ci_rd"), None, dut.clk, dut.rst)
        self.ringPiTbl = RingPiTbl(RingPiRdReqBus.from_prefix(dut, "ring_pi"), RingPiRdRspBus.from_prefix(dut, "ring_pi"), RingPiWrBus.from_prefix(dut, "ring_pi"), dut.clk, dut.rst)
        #self.ringPiWr.queue_occupancy_limit = 0
        self.qstatusWr = QstatusWrSource(QstatusWrBus.from_prefix(dut, "qstatus_wr"), dut.clk, dut.rst)
        self.qStopReq = QStopReqSource(QStopReqBus.from_prefix(dut, "q_stop_req"), dut.clk, dut.rst)
        self.qStopRsp = QStopRspSink(QStopRspBus.from_prefix(dut, "q_stop_rsp"), dut.clk, dut.rst)
        #self.qStopRsp.queue_occupancy_limit = 0

        self.ctx_ctrl = beq_ctx_ctrl(self.mem, self.dut.clk, self.notifyReq, self.notifyRsp,
                                    self.ringInfoRdTbl, self.rxqTransferTypeRdTbl, self.txqTransferTypeRdTbl,
                                    self.ringDbIdxRdTbl, self.ringCiRdTbl, self.ringPiTbl,
                                    self.qstatusWr, 
                                    self.qStopReq, self.qStopRsp)
        self.beq_txq_ref = {}
        self.beq_rxq_ref = {}

        self.beq_txq = beq_txq_behavior(self.ctx_ctrl, self.newChainNotify, self.txqRdNdescReq, self.txqRdNdescRsp, self.beq_txq_ref, self.dut.clk)
        self.pmd_behavior = beq_pmd_behavior(mem=self.mem, beq_ctr=self.ctx_ctrl)
        self.beq_rxq = beq_rxq_behavior(self.ctx_ctrl, self.pmd_behavior, self.rxqRdNdescReq, self.rxqRdNdescRsp, self.dut.clk)

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
        self.dmaDescIf.set_idle_generator(generator)
        self.notifyReq.set_idle_generator(generator)
        self.rxqRdNdescReq.set_idle_generator(generator)
        self.txqRdNdescReq.set_idle_generator(generator)
        self.newChainNotify.set_idle_generator(generator)
        self.qstatusWr.set_idle_generator(generator)
        self.qStopReq.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        self.dmaDescIf.set_backpressure_generator(generator)
        self.notifyRsp.set_backpressure_generator(generator)
        self.rxqRdNdescRsp.set_backpressure_generator(generator)
        self.txqRdNdescRsp.set_backpressure_generator(generator)

async def txq_worker(tb, qid, max_seq):
    typ = beq_transfer_type_type_list[random.randint(0, len(beq_transfer_type_type_list)-1)]
    depth = beq_q_depth_type_list[random.randint(0, len(beq_q_depth_type_list)-1)]
    tb.pmd_behavior.create_queue(qid=qid, beq_depth=beq_q_depth_t.q1k, transfer_type=typ)
    await tb.pmd_behavior.start_queue(qid=qid)
    tb.beq_txq_ref[qid] = []
    desc_num = 0
    for i in range(max_seq):
        tb.log.info("qid {} seq: {}".format(qid, i))
        chains = []
        num_chain = random.randint(1, 16)
        for j in range(num_chain):
            chain = tx_pkt_gen(i)
            chains.append(chain)
            for desc in chain:
                tb.beq_txq_ref[qid].append((desc, typ))
            desc_num = desc_num + len(chain)
        while len(chains) > 0:
            chains = await tb.pmd_behavior.burst_tx(qid=qid, chains=chains)
            await Timer(100, "ns")
    await Timer(10, "us")
    tb.log.info("qid:{} total num of desc:{}".format(qid, desc_num))
    await tb.pmd_behavior.wait_finish(qid=qid)
    tb.log.info("wait_finish qid:{}".format(qid))

    if len(tb.beq_txq_ref[qid]) != 0:
        raise ValueError("beq_txq_ref(qid:{}) is not empty".format(qid))

    await tb.pmd_behavior.stop_queue(qid=qid)
    tb.log.info("stop_queue qid:{}".format(qid))
    await Timer(100, "ns")
    tb.pmd_behavior.destroy_queue(qid=qid)
    tb.log.info("destroy_queue qid:{}".format(qid))

async def rxq_worker(tb, qid, max_seq):
    typ = random.choice(beq_transfer_type_type_list) 
    depth = random.choice(beq_q_depth_type_list)
    seg_sz = random.choice(beq_rx_segment_type_list)*512
    max_size = seg_sz*24
    tb.pmd_behavior.create_queue(qid=qid, beq_depth=beq_q_depth_t.q1k, transfer_type=typ, mbuf_sz=seg_sz)
    await tb.pmd_behavior.start_queue(qid=qid)
    tb.beq_rxq_ref[qid] = Queue(maxsize=1024)
    desc_num = 0
    async def pkt_gen(qid, max_seq, max_size, typ):
        for i in range(max_seq):
            length, user0, user1 = rx_pkt_gen(i, max_size)
            tb.log.info("recv_a_pkt qid {} seq {} length {} user0 {} user1{}".format(qid, i, length, user0, user1))
            await tb.beq_rxq.recv_a_pkt(qid, length, user0, user1, typ)
            await tb.beq_rxq_ref[qid].put((qid, length, user0, user1, typ))
    
    cocotb.start_soon(pkt_gen(qid, max_seq, max_size, typ))
    n = 0
    while n < max_seq:
        descs_list = await tb.pmd_behavior.burst_rx(qid)
        if len(descs_list) > 0:
            for descs in descs_list:
                (ref_qid, ref_length, ref_user0, ref_user1, ref_typ) = await tb.beq_rxq_ref[qid].get()
                length = np.sum([desc.soc_buf_len for desc in descs])
                if descs[0].user0 == ref_user0 and descs[0].user1 == ref_user1:
                    if ref_length != length:
                        raise ValueError("len(qid:{}) is not matched(ref len {} cur len {})".format(qid, ref_length, length))
                else:
                    (drop_qid, drop_length, drop_user0, drop_user1, drop_typ) = await tb.beq_rxq.beq_drop_queue[qid].get()
                    if drop_qid != ref_qid or ref_length != drop_length or ref_user0 != drop_user0 or ref_user1 != drop_user1 or ref_typ != drop_typ:
                        raise ValueError("drop (qid:{}) is not matched(ref {} {} {} {} {} drop {} {} {} {} {}".format(ref_qid, ref_length, ref_user0, ref_user1, ref_typ, drop_qid, drop_length, drop_user0, drop_user1, drop_typ))
                tb.log.info("burst_rx(qid {}) len {} user0 {} user1 {}".format(qid, length, descs[0].user0, descs[0].user1))
        n = n + len(descs_list)

    if tb.beq_rxq_ref[qid].qsize() != 0:
        raise ValueError("beq_txq_ref(qid:{}) is not empty".format(qid))

    await tb.pmd_behavior.stop_queue(qid=qid)
    tb.log.info("stop_queue qid:{}".format(qid))
    await Timer(100, "ns")
    tb.pmd_behavior.destroy_queue(qid=qid)
    tb.log.info("destroy_queue qid:{}".format(qid))

async def run_test(dut, idle_inserter, backpressure_inserter):
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    q_num = 8
    max_seq = 500
    txq_worker_cr = {}
    rxq_worker_cr = {}
    for i in range(q_num):
        txq_worker_cr[i] = cocotb.start_soon(txq_worker(tb, i*2+1, max_seq))

    for i in range(q_num):
        rxq_worker_cr[i] = cocotb.start_soon(rxq_worker(tb, i*2, max_seq))
    for i in range(q_num):
        await txq_worker_cr[i].join()
    for i in range(q_num):
        await rxq_worker_cr[i].join()

    if len(tb.ctx_ctrl.schBitmap) != 0:
        raise ValueError("schBitmap is not empty")
    if tb.ctx_ctrl.schColdQueue.qsize() != 0:
        raise ValueError("schColdQueue is not empty")
    if tb.ctx_ctrl.schHotQueue.qsize() != 0:
        raise ValueError("schHotQueue is not empty")

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
        factory.generate_tests()

#sys.path.append('../common'); from debug import *

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
