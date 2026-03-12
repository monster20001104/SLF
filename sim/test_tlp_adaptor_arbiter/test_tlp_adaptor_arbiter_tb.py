#!/usr/bin/env python3
################################################################################
#  文件名称 : test_tlp_adaptor_arbiter_tb.py
#  作者名称 : matao
#  创建日期 : 2025/01/02
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  01/02       matao       初始化版本
################################################################################
import itertools
import logging
import os
import sys
import random
import cocotb_test.simulator
from logging.handlers import RotatingFileHandler
from cocotb.log import SimLog, SimLogFormatter

import cocotb
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory
import time 

sys.path.append('../common')
from bus.tlp_adap_dma_bus import DmaWriteBus, DmaReadBus
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace
from drivers.tlp_adap_dma_bus import DmaMaster
from bus.tlp_adap_dma_bus import DmaBus
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster
import ding_robot



class TB(object):
    def __init__(self, dut, chn_num):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.mem = Pool(None, 0, size=2**64, min_alloc=1)

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
        self.reg_rd_queue_rsp    = Queue(maxsize=8)
        self.dfx_reg_queue       = Queue(maxsize=8)

        self.dmaMem = DmaRam(DmaWriteBus.from_prefix(dut, "master"), DmaReadBus.from_prefix(dut, "master"), dut.clk, dut.rst, mem=self.mem)
        self.dmamasters = [DmaMaster(DmaBus.from_prefix(dut, "slave{}".format(i)), dut.clk, dut.rst) for i in range(chn_num)]
        self.regconmaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)
    
    async def reg_wr_req(self, addr,data):
        await self.regconmaster.write(addr,data,True)

    async def reg_rd_req(self, addr):
        addr = addr
        rddata = await self.regconmaster.read(addr)
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
            self.dmaMem.set_idle_generator(generator)
            for dmamaster in self.dmamasters:
                dmamaster.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.dmaMem.set_backpressure_generator(generator)
            for dmamaster in self.dmamasters:
                dmamaster.set_backpressure_generator(generator)


async def run_test_arbiter(dut, idle_inserter, backpressure_inserter , rd_chn_shaping_en):
    time_seed = int(time.time())
    random.seed(time_seed)
    max_seq = 1000#100000
    chn_num = 8
    tb = TB(dut, chn_num)
    tb.log.info(f"set time_seed {time_seed}")
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    if rd_chn_shaping_en:
        tb.dut.rd_chn_shaping_en.value = 0xFF
    else:
        tb.dut.rd_chn_shaping_en.value = 0x0F
    await tb.cycle_reset()

    async def worker_thd(chn_id, max_seq):
        wr_req_queue = Queue(maxsize=64)
        rd_req_queue = Queue(maxsize=64)

        async def wr_req_thd(chn_id, max_seq):
            for i in range(max_seq):
                print("chn {} wr req sequence {}".format(chn_id, i))

                length = random.randint(1, 4096) 
                test_data = os.urandom(length) 
                region_mem = tb.mem.alloc_region(length)
                region_base = region_mem.get_absolute_address(0)
                
                await tb.dmamasters[chn_id].write_nb_req(region_base, test_data,sty=random.randint(0,31), rd2rsp_loop=0x87654321,bdf=random.randint(0,1000), has_rsp=True)
                await wr_req_queue.put((region_mem, test_data))
                
        async def wr_rsp_thd(chn_id, max_seq):
            for i in range(max_seq):
                print("chn {} wr rsp sequence {}".format(chn_id, i))
                (region_mem, test_data) = await wr_req_queue.get()
                rsp = await tb.dmamasters[chn_id].write_rsp_get()
                print(region_mem.get_absolute_address(0), region_mem.size)
                data = await region_mem.read(0, region_mem.size)
                if data != test_data:
                    tb.log.debug("data:{}".format(data.hex()))
                    tb.log.debug("test_data:{}".format(test_data.hex()))
                    raise ValueError("wr req (chn_id:{}) (seq_cnt:{}) data is mismatched".format(chn_id, i))
                assert int(rsp) == 0x87654321
                region_base = region_mem.get_absolute_address(0)
                length = region_mem.size
                await tb.dmamasters[chn_id].read_nb_req(region_base, length, sty=0, rd2rsp_loop=0x12345678,bdf=random.randint(0,1000))
                await rd_req_queue.put((region_mem, test_data))
                
        async def rd_req_thd(chn_id, max_seq):
            for i in range(max_seq):
                print("chn {} rd req sequence {}".format(chn_id, i))
                (region_mem, test_data) = await rd_req_queue.get()
                val = await tb.dmamasters[chn_id].read_rsp_get()
            
                if val.data != test_data:
                    tb.log.debug("val_data:{}".format(val.data.hex()))
                    tb.log.debug("test_data:{}".format(test_data.hex()))
                    raise ValueError("rd req (chn_id:{}) (seq_cnt:{}) data is mismatched".format(chn_id, i))
                #assert test_data == val.data
                assert val.rd2rsp_loop == 0x12345678
                region_free = tb.mem.free_region(region_mem)
        wr_req_cr = cocotb.start_soon(wr_req_thd(chn_id, max_seq))
        wr_rsp_cr = cocotb.start_soon(wr_rsp_thd(chn_id, max_seq))
        rd_req_cr = cocotb.start_soon(rd_req_thd(chn_id, max_seq))

        await wr_req_cr.join()
        await wr_rsp_cr.join()
        await rd_req_cr.join()
    
    async def read_dfx_reg(max_seq, chn_num):
        addr0 = 0x00080
        await tb.reg_rd_req(addr = addr0)
        rdata0 = await tb.reg_rd_queue_rsp.get()
        rdata0 = int(rdata0)
        if rdata0 > 0 :
            tb.log.info("There are some DFX errors in module err0 is {}, ".format(rdata0))
            assert False, " There are some DFX errors in module."
            
        addr00 = 0x00100
        await tb.reg_rd_req(addr = addr00)
        rdata00 = await tb.reg_rd_queue_rsp.get()
    
        addr2 = 0x00200
        await tb.reg_rd_req(addr = addr2)
        rdata2 = await tb.reg_rd_queue_rsp.get()
        wr_req_cnt  = rdata2 & 0xFF
        wr_rsp_cnt  = (rdata2 >> 8) & 0xFF
        rd_req_cnt  = (rdata2 >> 16) & 0xFF
        rd_rsp_cnt  = (rdata2 >> 24) & 0xFF
        result = (max_seq * chn_num) % 256
        if result != wr_req_cnt or  result != wr_rsp_cnt or result != rd_req_cnt or result != rd_rsp_cnt :
            tb.log.info("There are some DFX errors in module cnt wr_req_cnt, wr_rsp_cnt, rd_req_cnt, rd_rsp_cnt , result is {},{},{},{},{} ".format(wr_req_cnt, wr_rsp_cnt, rd_req_cnt, rd_rsp_cnt, result))
            assert False, " There are some DFX errors in cnt."
        
        await Timer(500, 'ns')
        await tb.dfx_reg_queue.put(1)
    await Timer(5000, 'ns')
    data0 = 0x0123456789abcdef
    data8 = 0xfedc32104567b98a
    await tb.reg_wr_req(addr = 0x0, data = data0)
    await tb.reg_wr_req(addr = 0x8, data = data8)
    await tb.reg_rd_req(addr = 0x0)
    rdata0 = await tb.reg_rd_queue_rsp.get()
    if rdata0 != data0:
        tb.log.info("dfx reg 0x0 don't match, real result is {}, resv is {} ".format(data0, rdata0))
        assert False, " There are errors in reg 0x0."
    await tb.reg_rd_req(addr = 0x8)
    rdata8 = await tb.reg_rd_queue_rsp.get()
    if rdata8 != data8:
        tb.log.info("dfx reg 0x8 don't match, real result is {}, resv is {} ".format(data8, rdata8))
        assert False, " There are errors in reg 0x8."

    worker_cr = [cocotb.start_soon(worker_thd(chn_id, max_seq)) for chn_id in range(chn_num)]

    for chn_id in range(chn_num):
        await worker_cr[chn_id].join()
    await Timer(5000, 'ns')
    read_dfx_reg_cr = cocotb.start_soon( read_dfx_reg(max_seq, chn_num))
    dfx_reg_flag0   = await tb.dfx_reg_queue.get()
    await Timer(5000, 'ns')
        
        
    
def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

ding_robot.ding_robot()
if cocotb.SIM_NAME:

    for test in [run_test_arbiter]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.add_option("rd_chn_shaping_en", [True,False])
        factory.generate_tests()

#make from debug import *
root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
