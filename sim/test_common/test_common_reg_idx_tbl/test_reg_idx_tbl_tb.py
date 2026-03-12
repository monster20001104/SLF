#!/usr/bin/env python3
################################################################################
#  文件名称 : test_reg_idx_tbl_tb.py
#  作者名称 : liuch
#  创建日期 : 2024/08/01
#  功能描述 :
#
#  修改记录 :
#
#  版本号  日期       修改人       修改内容
#  v1.0  08/01         liuch     初始化版本
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
from cocotb.queue import Queue
from cocotb.binary import BinaryValue
from cocotb.types import LogicArray
from cocotb.handle import Force
from cocotb.log import SimLog

sys.path.append('../../common')
from drivers.mlite_bus import MliteBusMaster
from monitors.mlite_bus import MliteBusRam
from bus.mlite_bus import MliteBus


class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
        self.mlitemaster = MliteBusMaster(MliteBus.from_prefix(dut, "mlite_slave"), dut.clk)

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
            self.mlitemaster.set_idle_generator(generator)  # hold off vld
            pass

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.mlitemaster.set_backpressure_generator(generator)  # hold off rready
            pass


async def run_test(dut, idle_inserter, backpressure_inserter):
    addr_bot = 0xFF0
    addr_top = 0x1008
    sim_file = "../../common/reg_idx_tbl/reg_idx_tbl_sim.txt"

    sim_data = []
    sim_len = 0
    if True:
        try:
            with open(sim_file, "r") as file:
                sim_data = [int(line.strip(), 16) for line in file]
                sim_len = len(sim_data)
        except FileNotFoundError:
            print("WARNING : FileNotFound, SIM error")

    tb = TB(dut)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()

    # rd_cr = cocotb.start_soon(tb.rd_thd())
    round_num = (addr_top - addr_bot) // 8 + 1
    for i in range(round_num):
        test_addr = i * 8 + addr_bot
        act_data = await tb.mlitemaster.read(test_addr)
        if test_addr / 8 < sim_len:
            assert int(act_data) == sim_data[i]
        if test_addr >= 0x1000:
            assert int(act_data) == 0xDEADBEEFDEADC0DE


def cycle_pause():
    seed = [1 if i < 800 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)


if cocotb.SIM_NAME:

    # for test in [run_test ,run_test_timeout]:
    for test in [run_test]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()
