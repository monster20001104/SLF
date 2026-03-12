#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : test_mlite2avmm_tb.py
#* 作者名称 : matao
#* 创建日期 : 2025/08/20
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   08/20       matao       初始化版本
#******************************************************************************/
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

sys.path.append('../../common/')
from bus.mlite_bus      import MliteBus
from monitors.mlite_bus import MliteBusRam
from drivers.mlite_bus import MliteBusMaster

class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        self.mliteMaster = MliteBusMaster(MliteBus.from_prefix(dut, "mlite_slave"), dut.clk)
        self.mliteSlave = MliteBusRam(MliteBus.from_prefix(dut, "mlite_master"), dut.clk, dut.rst, size=4096)

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
            self.mliteMaster.set_idle_generator(generator)
            self.mliteSlave.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.mliteMaster.set_backpressure_generator(generator)
            self.mliteSlave.set_backpressure_generator(generator)

async def test_mlite2avmm(dut, idle_inserter, backpressure_inserter):
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    
    await tb.cycle_reset()

    for _ in range(10000):
        test_data = random.randint(0, 2**64-1)
        addr = random.randint(0, 511) * 8
        await tb.mliteMaster.write(addr, test_data)
        data = await tb.mliteMaster.read(addr)
        assert data == test_data

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:

    for test in [test_mlite2avmm]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()