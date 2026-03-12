#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : test_mlite_64to32_splitter_tb.py
#* 作者名称 : matao
#* 创建日期 : 2025/08/19
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   08/19       matao       初始化版本
#******************************************************************************/
import itertools
import logging
import os
import sys
import random
import math
from logging.handlers import RotatingFileHandler
import cocotb_test.simulator
import pytest
from cocotb.log import SimLog,  SimLogFormatter

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory
from cocotb.queue import Queue, QueueFull

from cocotb_bus.drivers.avalon import AvalonMaster
from mlite_64to32_splitter_bus_driver import MliteBusMaster
sys.path.append('../../common')
from bus.mlite_bus      import MliteBus
from monitors.mlite_bus import MliteBusRam


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        self.mliteMaster = MliteBusMaster(MliteBus.from_prefix(dut, "mlite_slave"), dut.clk)
        self.mliteSlave = MliteBusRam(MliteBus.from_prefix(dut, "mlite_master"), dut.clk, dut.rst, size=4096)
        self.reg_rd_queue_rsp =  Queue(maxsize=8)

    async def reg_wr_req(self, addr, data, en_f0):
        await self.mliteMaster.write(addr,data,en_f0,True)

    async def reg_rd_req(self, addr, en_f0):
        rddata = await self.mliteMaster.read(addr,en_f0)
        await self.reg_rd_queue_rsp.put(rddata)


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

async def run_test_splitter(dut, idle_inserter, backpressure_inserter):
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    
    await tb.cycle_reset()
    await Timer(5000, 'ns')

    for i in range(5000):
        data_width_64_en = random.randint(0,1)#data_width_64_en=1时寄存器请求为64bit数据，此时需要分成2次32bit的数据请求，data_width_64_en=0时只有一次请求
        en_f0 = random.randint(0,1) #对于掩码0XFF可能出现0X0F，当en_f0=0时，掩码可能为0XFF,0XF0，当en_f0=1时，掩码可能为0XFF,0X0F
        if data_width_64_en == 1:
            test_data = random.randint(0,2**64-1)
            addr = random.randint(0, 15)*8
        else :
            test_data = random.randint(0,2**32-1)
            addr = random.randint(0,4095)
        low_addr = addr & 0x7
        low_addr_d = 7 - low_addr
        no_en_f0_wmask = 0xff << low_addr
        no_en_f0_wmask = no_en_f0_wmask & 0xff
        en_f0_wmask = 0xff >> low_addr_d
        en_f0_wmask = en_f0_wmask & 0xff
        if en_f0 == 0:
            wmask = no_en_f0_wmask
        else : 
            wmask = en_f0_wmask
        req_test_data = 0
        for j in range(8):
            if wmask & (1 << j):
                byte_data = (test_data >> (j * 8)) & 0xff
                req_test_data |= byte_data << (j * 8)

        await tb.reg_wr_req(addr, test_data, en_f0)
        await tb.reg_rd_req(addr, en_f0)
        rsp_data = await tb.reg_rd_queue_rsp.get()
        rsp_dut_data = 0
        for j in range(8):
            if wmask & (1 << j):
                byte_data = (rsp_data >> (j * 8)) & 0xff
                rsp_dut_data |= byte_data << (j * 8)

        tb.log.info(f"The sequence is {i}, data_width_64_en is {data_width_64_en}, en_f0 is {en_f0}, addr is 0x{addr}, test_data is 0x{test_data:X}, rsp_data is 0x{rsp_data:X}, req_test_data is : 0x{req_test_data:X}, rsp_dut_data is : 0x{rsp_dut_data:X}, no_en_f0_wmask is :0x{no_en_f0_wmask:X}, en_f0_wmask is {en_f0_wmask:X}")
        assert rsp_dut_data == req_test_data, f"no match ! rsp_dut_data : {rsp_dut_data:X}, req_test_data: {req_test_data:X} , data_width_64_en: {data_width_64_en} , addr : {addr}"

    await Timer(5000, 'ns')

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:

    for test in [run_test_splitter]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)