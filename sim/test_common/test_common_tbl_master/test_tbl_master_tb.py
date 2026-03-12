#!/usr/bin/env python3
################################################################################
#  文件名称 : test_tbl_master_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/20
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/20     Joe Jiang   初始化版本
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


sys.path.append('../../common')
from ram_tbl import define_ram_tbl

TbRdReqBus, TbRdRspBus, TbWrBus, TbRdReqTransaction, TbRdRspTransaction, TbWrTransaction, TbTblMaster, _ = define_ram_tbl("tb", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    wr_signals=["wr_qid", "wr_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld"
)

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.tbTblMaster = TbTblMaster(TbRdReqBus.from_prefix(dut, "tb"), TbRdRspBus.from_prefix(dut, "tb"), TbWrBus.from_prefix(dut, "tb"), dut.clk, dut.rst)

    async def cycle_reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await Timer(2, "us")
        await RisingEdge(self.dut.clk)
        wrTransaction = TbWrTransaction()
        wrTransaction.wr_qid = 123
        wrTransaction.wr_dat = 3242
        await self.tbTblMaster.write(wrTransaction)
        
        rdReqTransaction = TbRdReqTransaction()
        rdReqTransaction.rd_req_qid = 123
        rdRspTransaction = await self.tbTblMaster.read(rdReqTransaction)
        print(rdRspTransaction)

async def run_test(dut):
    tb = TB(dut)
    await tb.cycle_reset()
    await Timer(1, "us")

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.generate_tests()


root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)