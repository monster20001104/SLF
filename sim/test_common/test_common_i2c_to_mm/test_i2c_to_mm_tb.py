#!/usr/bin/env python3
################################################################################
#  文件名称 : test_i2c_to_mm.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/10/22
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  10/22     Joe Jiang   初始化版本
################################################################################
import itertools
import logging
import os
import sys
import random
import math
import struct

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory

from cocotb_bus.drivers.avalon import AvalonMemory

sys.path.append('../../common/')
from i2c.i2c_master import I2cMaster

class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(self.dut.clk, 10, units="ns").start())

        self.i2c_master = I2cMaster(sda=dut.i2c_data_o, sda_o=dut.i2c_data_in,
            scl=dut.i2c_clk_o, scl_o=dut.i2c_clk_in, speed=400e3)

        self.avalonMm = AvalonMemory(dut, "avmm", dut.clk, readlatency_min=8, readlatency_max=16)

        

    async def cycle_reset(self):
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    

async def run_test_i2c(dut):
    tb = TB(dut)    
    await tb.cycle_reset()

    await Timer(100, 'us')

    dev_addr = 0x20
    max_seq = 1

    for i in range(max_seq):
        addr = i*4
        data_array = os.urandom(4)
        addr_array = struct.pack('>H', addr)

        await tb.i2c_master.write(dev_addr, addr_array + data_array)
        await tb.i2c_master.send_stop()
        await tb.i2c_master.write(dev_addr, addr_array)
        data = await tb.i2c_master.read(dev_addr, 4)
        await tb.i2c_master.send_stop()
        tb.log.info("test data: %s", data_array.hex())
        tb.log.info("Read data: %s", data.hex())
        assert data_array == data



if cocotb.SIM_NAME:
    for test in [run_test_i2c]:
        factory = TestFactory(test)
        factory.generate_tests()