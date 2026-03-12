#!/usr/bin/env python3
################################################################################
#  文件名称 : test_dwrr_sch_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/01
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/01     Joe Jiang   初始化版本
################################################################################
import itertools
import logging
import os
import sys
import random
import math

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory

from cocotb_bus.drivers.avalon import AvalonMaster

sys.path.append('../../common/')
from bus.mlite_bus      import MliteBus
from monitors.mlite_bus import MliteBusRam

class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        self.avalonMm = AvalonMaster(dut, "avmm", dut.clk)
        self.mliteSlave = MliteBusRam(MliteBus.from_prefix(dut, "csr_if"), dut.clk, dut.rst, size=4096)

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
        
    def set_idle_generator(self, generator=None):
        if generator:
            self.mliteSlave.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.mliteSlave.set_backpressure_generator(generator)

async def run_test_sch(dut, idle_inserter, backpressure_inserter):
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    
    await tb.cycle_reset()

    for _ in range(1000):
        test_data = random.randint(0, 2**64-1)
        await tb.avalonMm.write(0x10, test_data)
        data = await tb.avalonMm.read(0x10)
        assert data == test_data

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:

    for test in [run_test_sch]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()