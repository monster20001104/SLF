#!/usr/bin/env python3
################################################################################
#  文件名称 : test_mgmt_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/10/24
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  10/24     Joe Jiang   初始化版本
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
from cocotb.triggers import RisingEdge, Timer, Join, First, Event
from cocotb.regression import TestFactory

sys.path.append('../../common/')
from i2c.i2c_master import I2cMaster
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster

class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(self.dut.clk, 4, units="ns").start())
        cocotb.start_soon(Clock(self.dut.clk_11m, 100, units="ns").start())
        cocotb.start_soon(Clock(self.dut.clk_50m, 20, units="ns").start())

        self.i2c_master = I2cMaster(sda=dut.i2c_data_o, sda_o=dut.i2c_data_in,
            scl=dut.i2c_clk_o, scl_o=dut.i2c_clk_in, speed=800e3)

        self.bmc_i2c_master = I2cMaster(sda=dut.bmc_i2c_data_o, sda_o=dut.bmc_i2c_data_in,
            scl=dut.bmc_i2c_clk_o, scl_o=dut.bmc_i2c_clk_in, speed=800e3)
        
        self.dfxBusMaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk,dut.rst)

    async def i2c_read_4B(self, addr, timeout=1000):
        event = Event()
        event.clear()
        async def req(addr):
            addr_array = struct.pack('>H', addr)
            await self.i2c_master.write(0x20, addr_array)
            data = await self.i2c_master.read(0x20, 4)
            await self.i2c_master.send_stop()
            event.set(data=data)
        cocotb.start_soon(req(addr))
        t = Timer(timeout, "us")
        fired = await First(event.wait(), t)
        if fired is t:
            return None 
        return int.from_bytes(event.data, byteorder='little')

    
    async def cycle_reset(self):
        async def rest(rst_pin, clk):
            rst_pin.value = 0
            await Timer(200, "ns")
            await RisingEdge(clk)
            rst_pin.value = 1
            await Timer(250, "ns")
            await RisingEdge(clk)
            rst_pin.value = 0
            await RisingEdge(clk)
            await RisingEdge(clk)
            await RisingEdge(clk)

        rst_sys_cr = cocotb.start_soon(rest(self.dut.rst, self.dut.clk))
        rst_11m_cr = cocotb.start_soon(rest(self.dut.rst_11m, self.dut.clk_11m))
        rst_50m_cr = cocotb.start_soon(rest(self.dut.rst_50m, self.dut.clk_50m))

        await Join(rst_sys_cr)
        await Join(rst_11m_cr)
        await Join(rst_50m_cr)


async def run_test_mgmt(dut):
    tb = TB(dut)    
    await tb.cycle_reset()
    await Timer(1000, 'ns')

    async def read_chip_id():
        while True:
            data = await tb.dfxBusMaster.read(0x130)
            act_data = await tb.dfxBusMaster.read(0x100000)
            tb.log.info("data: %s", hex(data))
            tb.log.info("act_data: %s", hex(act_data))
            #assert data == 0x1234567887654321
            await RisingEdge(tb.dut.clk)
    cocotb.start_soon(read_chip_id())
    await Timer(1000, 'ns')
    '''
    for _ in range(1):
        data = await tb.i2c_read_4B(0x00, 1000)
        tb.log.info("fpga version: %s", hex(data))

        data = await tb.i2c_read_4B(0x08, 1000)
        tb.log.info("fpga githash: %s", hex(data))

        data = await tb.i2c_read_4B(0x40, 1000)
        tb.log.info("fpga githash: %s", hex(data))

        data = await tb.i2c_read_4B(0x80, 1000)
        tb.log.info("fpga temp_sensor: %s", hex(data))

        data = await tb.i2c_read_4B(0x90, 1000)
        tb.log.info("fpga voltage_sensor0: %s", hex(data))

        data = await tb.i2c_read_4B(0x94, 1000)
        tb.log.info("fpga voltage_sensor1: %s", hex(data))

        data = await tb.i2c_read_4B(0x100, 1000)
        assert data == 0x0
        tb.log.info("fpga seu_0: %s", hex(data))

        data = await tb.i2c_read_4B(0x104, 1000)
        tb.log.info("fpga seu_1: %s", hex(data))

        data = await tb.i2c_read_4B(0x108, 1000)
        tb.log.info("fpga seu_2: %s", hex(data))

        data = await tb.i2c_read_4B(0x120, 1000)
        assert data == 0x87654321
        tb.log.info("fpga chip_id_0: %s", hex(data))

        data = await tb.i2c_read_4B(0x124, 1000)
        assert data == 0x12345678
        tb.log.info("fpga chip_id_1: %s", hex(data))
    '''
    

if cocotb.SIM_NAME:
    for test in [run_test_mgmt]:
        factory = TestFactory(test)
        factory.generate_tests()