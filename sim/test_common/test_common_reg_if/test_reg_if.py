#!/usr/bin/env python3
################################################################################
#  文件名称 : test_reg_if.py
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

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory

sys.path.append('../../common')
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster

class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.dfxBusMaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

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

async def run_test_read(dut, data_in=None):

    tb = TB(dut)
    await tb.cycle_reset()


    data = await tb.dfxBusMaster.read(0)
    await tb.dfxBusMaster.write(4, 0xdeadbeef)
    await RisingEdge(tb.dut.clk)
    data = await tb.dfxBusMaster.read(0)
    data = tb.dut.test1_test1_q.value
    assert data == 0xdeadbeef

    await tb.dfxBusMaster.write(8, 0xbeefdead)
    await RisingEdge(tb.dut.clk)
    data = await tb.dfxBusMaster.read(0)
    data = tb.dut.test2_test2_q.value
    assert data == 0xbeefdead

    await tb.dfxBusMaster.write(0xc, 0xabcd1234)
    await RisingEdge(tb.dut.clk)
    data = await tb.dfxBusMaster.read(0)
    data = tb.dut.test3_test2_q.value
    assert data == 0xabcd1234
    tb.dut.test3_test2_hwclr.value = 1
    await RisingEdge(tb.dut.clk)
    tb.dut.test3_test2_hwclr.value = 0
    await RisingEdge(tb.dut.clk)
    data = await tb.dfxBusMaster.read(0)
    data = await tb.dfxBusMaster.read(0xc)
    assert data == 0

    tb.dut.test4_test3_wdata.value = 0x12345678
    await RisingEdge(tb.dut.clk)
    data = await tb.dfxBusMaster.read(0x10)
    assert data == 0x12345678

    tb.dut.test5_test3_wdata.value = 0x87654321
    tb.dut.test5_test3_we.value = 1
    await RisingEdge(tb.dut.clk)
    tb.dut.test5_test3_wdata.value = 0
    tb.dut.test5_test3_we.value = 0
    await RisingEdge(tb.dut.clk)
    data = await tb.dfxBusMaster.read(0x14)
    assert data == 0x87654321


    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


if cocotb.SIM_NAME:

    for test in [run_test_read]:

        factory = TestFactory(test)
        #factory.add_option("idle_inserter", [None, cycle_pause])
        #factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()

# cocotb-test

tests_dir = os.path.abspath(os.path.dirname(__file__))
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', '..'))


def test_reg_if(request):
    dut = "reg_if"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
    ]

    parameters = {}

    parameters['ADDR_OFFSET'] = 0
    parameters['ADDR_WIDTH'] = 32
    parameters['DATA_WIDTH'] = 32

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    sim_build = os.path.join(tests_dir, "sim_build",
        request.node.name.replace('[', '-').replace(']', ''))

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
    )