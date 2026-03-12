#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : test_virtio_blk_downstream_tb.py
#* 作者名称 : matao
#* 创建日期 : 2025/07/09
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   07/09       matao       初始化版本
#******************************************************************************/
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import copy
import cocotb_test.simulator
import math
from enum import Enum, unique
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

sys.path.append('../../common')
from sparse_memory import SparseMemory
from address_space import Region, Pool
from virtio_blk_downstream_defines import *
from virtio_blk_qs_manager import *
import ding_robot


class TB(object):
    def __init__(self, dut, cfg):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        self.max_seq = cfg.max_seq
        cocotb.start_soon(Clock(dut.clk, 5, units="ns").start())
        self.mem = Pool(None, 0, size=2**32, min_alloc=64)
        self.virt_qs = VirtQs(self.mem, self.dut, self.max_seq)
        self.test_done = Event()
        cocotb.start_soon(self.virt_qs.sch_req_process())
        cocotb.start_soon(self.virt_qs.qos_query_process())
        cocotb.start_soon(self.virt_qs.slot_req_process())
        cocotb.start_soon(self.virt_qs.slot_rsp_process())
        cocotb.start_soon(self.virt_qs.blk_desc_process())
        cocotb.start_soon(self.virt_qs.qos_update_process())
        cocotb.start_soon(self.virt_qs.blk2beq_process())
        cocotb.start_soon(self.virt_qs.blk_ds_err_info_check_process())
        cocotb.start_soon(self.virt_qs.check_stop())

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
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    def set_idle_generator(self, generator=None):
        if generator:
            self.virt_qs.sch_req.set_idle_generator(generator)
            self.virt_qs.query_rsp.set_idle_generator(generator)
            self.virt_qs.slot_rsp.set_idle_generator(generator)
            self.virt_qs.blk_desc_rsp.set_idle_generator(generator)
            self.virt_qs.dma_rd.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.virt_qs.query_req.set_backpressure_generator(generator)
            self.virt_qs.update_req.set_backpressure_generator(generator)
            self.virt_qs.slot_req.set_backpressure_generator(generator)
            self.virt_qs.dma_rd.set_backpressure_generator(generator)
            self.virt_qs.beq_rxq.set_backpressure_generator(generator)
            self.virt_qs.err_info_if.set_backpressure_generator(generator)

async def run_test_virtio_blk_downstream(dut, idle_inserter, backpressure_inserter, cfg, ctx_shutdown_mode, err_shutdown_mode, dma_err_mode, fifo_pfull_mode):
    time_seed = int(time.time())
    random.seed(time_seed)
    tb = TB(dut, cfg)
    tb.log.info(f"set time_seed {time_seed}")
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()

    async def read_dfx_reg():
        addr0 = 0x6e0000
        rdata_err = await tb.virt_qs.reg_rd_req(addr = addr0)
        rdata_err = int(rdata_err)
        if rdata_err > 0 :
            tb.log.info("There are some DFX errors in module err0 is {}, ".format(rdata_err))
            assert False, " There are some DFX errors in module."
            
        addr00 = 0x6e0100
        rdata_sta = await tb.virt_qs.reg_rd_req(addr = addr00)

        MAX_ERR_CNT = 2 ** 16
        ERR_WIDTH = 16
        MAX_IF_CNT = 2 ** 8
        IF_WIDTH = 8
        addr2_0 = 0x6e0200
        rdata2_0 = await tb.virt_qs.reg_rd_req(addr = addr2_0)
        dfx_slot_rsp_err_cnt  = (rdata2_0 >> (0*ERR_WIDTH)) & (MAX_ERR_CNT-1)
        dfx_blk_desc_err_cnt  = (rdata2_0 >> (1*ERR_WIDTH)) & (MAX_ERR_CNT-1)
        dfx_dma_rd_rsp_err_cnt= (rdata2_0 >> (2*ERR_WIDTH)) & (MAX_ERR_CNT-1)

        if (dfx_slot_rsp_err_cnt != tb.virt_qs.slot_rsp_err_cnt % MAX_ERR_CNT):
            tb.log.info("DFX cnt are not equal: dfx_slot_rsp_err_cnt is {}, sim_slot_rsp_err_cnt is {}".format(dfx_slot_rsp_err_cnt, tb.virt_qs.slot_rsp_err_cnt % MAX_ERR_CNT))
            assert False, "There are some DFX cnt are not equal in dfx_slot_rsp_err_cnt."
        else:
            tb.log.info("DFX cnt are equal: dfx_slot_rsp_err_cnt is {}, sim_slot_rsp_err_cnt is {}".format(dfx_slot_rsp_err_cnt, tb.virt_qs.slot_rsp_err_cnt % MAX_ERR_CNT))

        if (dfx_blk_desc_err_cnt != tb.virt_qs.blk_desc_err_cnt % MAX_ERR_CNT):
            tb.log.info("DFX cnt are not equal: dfx_blk_desc_err_cnt is {}, sim_blk_desc_err_cnt is {}".format(dfx_blk_desc_err_cnt, tb.virt_qs.blk_desc_err_cnt % MAX_ERR_CNT))
            assert False, "There are some DFX cnt are not equal in dfx_blk_desc_err_cnt."
        else:
            tb.log.info("DFX cnt are equal: dfx_blk_desc_err_cnt is {}, sim_blk_desc_err_cnt is {}".format(dfx_blk_desc_err_cnt, tb.virt_qs.blk_desc_err_cnt % MAX_ERR_CNT))

        if (dfx_dma_rd_rsp_err_cnt != tb.virt_qs.dma_rd_rsp_err_cnt % MAX_ERR_CNT):
            tb.log.info("DFX cnt are not equal: dfx_dma_rd_rsp_err_cnt is {}, sim_dma_rd_rsp_err_cnt is {}".format(dfx_dma_rd_rsp_err_cnt, tb.virt_qs.dma_rd_rsp_err_cnt % MAX_ERR_CNT))
            assert False, "There are some DFX cnt are not equal in dfx_dma_rd_rsp_err_cnt."
        else:
            tb.log.info("DFX cnt are equal: dfx_dma_rd_rsp_err_cnt is {}, sim_dma_rd_rsp_err_cnt is {}".format(dfx_dma_rd_rsp_err_cnt, tb.virt_qs.dma_rd_rsp_err_cnt % MAX_ERR_CNT))

        addr2_1 = 0x6e0208
        rdata2_1 = await tb.virt_qs.reg_rd_req(addr = addr2_1)
        dfx_beq_cnt           = (rdata2_1 >> (0*IF_WIDTH)) & (MAX_IF_CNT-1)
        dfx_blk_desc_cnt      = (rdata2_1 >> (1*IF_WIDTH)) & (MAX_IF_CNT-1)
        dfx_buffer_hdr2beq_cnt= (rdata2_1 >> (2*IF_WIDTH)) & (MAX_IF_CNT-1)
        dfx_dma_data2beq_cnt  = (rdata2_1 >> (3*IF_WIDTH)) & (MAX_IF_CNT-1)

        if (dfx_beq_cnt != tb.virt_qs.beq_rxq_cnt % MAX_IF_CNT) :
            tb.log.info("DFX cnt are not equal: dfx_beq_cnt is {}, sim_beq_cntt is {}".format(dfx_beq_cnt, tb.virt_qs.beq_rxq_cnt % MAX_IF_CNT))
            assert False, " There are some DFX cnt are not equal in dfx_beq_cnt."
        else :
            tb.log.info("DFX cnt are equal dfx_beq_cnt is {}, sim_beq_cnt is {}".format(dfx_beq_cnt, tb.virt_qs.beq_rxq_cnt % MAX_IF_CNT))

        if (dfx_blk_desc_cnt != tb.virt_qs.blk_desc_cnt % MAX_IF_CNT):
            tb.log.info("DFX cnt are not equal: dfx_blk_desc_cnt is {}, sim_blk_desc_cnt is {}".format(dfx_blk_desc_cnt, tb.virt_qs.blk_desc_cnt % MAX_IF_CNT))
            assert False, "There are some DFX cnt are not equal in dfx_blk_desc_cnt."
        else:
            tb.log.info("DFX cnt are equal: dfx_blk_desc_cnt is {}, sim_blk_desc_cnt is {}".format(dfx_blk_desc_cnt, tb.virt_qs.blk_desc_cnt % MAX_IF_CNT))

        if (dfx_buffer_hdr2beq_cnt != tb.virt_qs.buffer_hdr2beq_cnt % MAX_IF_CNT):
            tb.log.info("DFX cnt are not equal: dfx_buffer_hdr2beq_cnt is {}, sim_buffer_hdr2beq_cnt is {}".format(dfx_buffer_hdr2beq_cnt, tb.virt_qs.buffer_hdr2beq_cnt % MAX_IF_CNT))
            assert False, "There are some DFX cnt are not equal in dfx_buffer_hdr2beq_cnt."
        else:
            tb.log.info("DFX cnt are equal: dfx_buffer_hdr2beq_cnt is {}, sim_buffer_hdr2beq_cnt is {}".format(dfx_buffer_hdr2beq_cnt, tb.virt_qs.buffer_hdr2beq_cnt % MAX_IF_CNT))

        if (dfx_dma_data2beq_cnt != tb.virt_qs.dma_data2beq_cnt % MAX_IF_CNT):
            tb.log.info("DFX cnt are not equal: dfx_dma_data2beq_cnt is {}, sim_dma_data2beq_cnt is {}".format(dfx_dma_data2beq_cnt, tb.virt_qs.dma_data2beq_cnt % MAX_IF_CNT))
            assert False, "There are some DFX cnt are not equal in dfx_dma_data2beq_cnt."
        else:
            tb.log.info("DFX cnt are equal: dfx_dma_data2beq_cnt is {}, sim_dma_data2beq_cnt is {}".format(dfx_dma_data2beq_cnt, tb.virt_qs.dma_data2beq_cnt % MAX_IF_CNT))

        #########Test write clear zero
        data_clr = 0xFFFF_FFFF_FFFF_FFFF
        await tb.virt_qs.reg_wr_req(addr = addr2_0, data = data_clr)
        rdata20_clr = await tb.virt_qs.reg_rd_req(addr = addr2_0)
        rdata20_clr = int((rdata20_clr & 0xFF))

        if rdata20_clr != 0 :
            tb.log.info("rdata20_clr is {} ".format(rdata20_clr))
            assert False, " soft write 1 to clear cnt is failed!!"
        await tb.virt_qs.reg_wr_req(addr = addr2_1, data = data_clr)
        rdata21_clr = await tb.virt_qs.reg_rd_req(addr = addr2_1)
        rdata21_clr = int((rdata21_clr & 0xFF))

        if rdata21_clr != 0 :
            tb.log.info("rdata21_clr is {} ".format(rdata21_clr))
            assert False, " soft write 1 to clear cnt is failed!!"

        await Timer(500, 'ns')
        tb.test_done.set()

    async def pkt_fifo_pfull_process():
        tb.dut.u_virtio_blk_downstream.dma_pkt_ff_rdy.value = 1
        while True:
            if fifo_pfull_mode:
                tb.dut.u_virtio_blk_downstream.dma_pkt_ff_rdy.value = 0
                await Timer(50000, 'ns')
                tb.dut.u_virtio_blk_downstream.dma_pkt_ff_rdy.value = 1
                await Timer(50000, 'ns')
                if tb.test_done.is_set():
                    break
            else:
                break

    await Timer(5000, 'ns')
    match_fifo_pfull_cr = cocotb.start_soon(pkt_fifo_pfull_process())
    for i in range(tb.max_seq):
        typ = VirtioQidType.VirtioBlk.value
        await tb.virt_qs.set_queue(cfg, typ, ctx_shutdown_mode, err_shutdown_mode, dma_err_mode)
    
    await tb.virt_qs.all_queues_stopped.wait()
    await Timer(50000, 'ns')
    read_dfx_reg_cr = cocotb.start_soon( read_dfx_reg())
    await Timer(50000, 'ns')

    
def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

ding_robot.ding_robot()

debug = 0
if cocotb.SIM_NAME:
    for test in [run_test_virtio_blk_downstream]:
        factory = TestFactory(test)
        if debug:
            factory.add_option("idle_inserter", [None])
            factory.add_option("backpressure_inserter", [cycle_pause])
            factory.add_option("cfg", [max_dma_len_cfg])
            factory.add_option("ctx_shutdown_mode", [False])
            factory.add_option("err_shutdown_mode", [False])
            factory.add_option("dma_err_mode", [False])
            factory.add_option("fifo_pfull_mode", [True])
        else:
            factory.add_option("idle_inserter", [None,cycle_pause])
            factory.add_option("backpressure_inserter", [None, cycle_pause])
            factory.add_option("cfg", [max_desc_cnt_cfg, min_desc_cnt_cfg, mix_desc_cnt_cfg, max_dma_len_cfg, min_dma_len_cfg, mix_dma_len_cfg])
            factory.add_option("ctx_shutdown_mode", [True,False])
            factory.add_option("err_shutdown_mode", [True,False])
            factory.add_option("dma_err_mode", [True, False])
            factory.add_option("fifo_pfull_mode", [True, False])
        factory.generate_tests()

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)

#from debug import *

