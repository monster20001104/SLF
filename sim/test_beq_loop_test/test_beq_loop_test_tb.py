###########################################
# 文件名称 : test_loop_tb
# 作者名称 : 崔飞翔
# 创建日期 : 2025/01/13
# 功能描述 : 
# 
# 修改记录 : 
# 
# 修改日期 : 2025/01/13
# 版本号    修改人    修改内容
# v1.0     崔飞翔     初始化版本
###########################################
import itertools
import math
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


sys.path.append('../common')
from bus.tlp_adap_dma_bus import DmaWriteBus, DmaReadBus
from bus.beq_data_bus import BeqBus
from bus.mlite_bus      import MliteBus
from drivers.beq_data_bus import BeqTxqMaster
from drivers.mlite_bus import MliteBusMaster
from monitors.tlp_adap_dma_bus import DmaRam
from monitors.beq_data_bus import BeqRxqSlave
from sparse_memory import SparseMemory
from enum import Enum, unique
from cocotb.utils import get_sim_time

class Loop:
    def __init__(self, dut):

        self.beq_txq = BeqTxqMaster(BeqBus.from_prefix(dut, "beq2loop"), dut.clk_i, dut.rst_i)
        self.beq_rxq = BeqRxqSlave( BeqBus.from_prefix(dut, "loop2beq"), dut.clk_i, dut.rst_i)
        self.milte_master = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk_i, dut.rst_i)
        self.req_q = {qid: Queue(maxsize=32) for qid in range(8)}
        cocotb.start_soon(self._process_req())
        for qid in range(8):
            cocotb.start_soon(self._process_send(dut,qid))


    async def _process_req(self):
        rx_cnt = 0
        while True:
            rx_cnt = rx_cnt + 1
            req = await self.beq_rxq.recv()
            print("rx_cnt = {}".format(rx_cnt))
            await self.req_q[req.qid].put((req, get_sim_time("ns")))

    async def _process_send(self,dut,qid):
        tx_cnt = 0
        while True:
            tx_cnt = tx_cnt + 1
            (send_data, tim) = await self.req_q[qid].get()
            latency = math.ceil(get_sim_time("ns") - tim)
            if latency < 1000:
                await RisingEdge(dut.clk_i)
                await Timer(1000 - latency + random.randint(1, 128), "ns")
            print("tx_cnt = {}".format(tx_cnt))
            await self.beq_txq.send(send_data.qid,send_data.data,send_data.user0)
        
class TB(object):
    def __init__(self,dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
        self.loop = Loop(dut)



    async def cycle_reset(self):
        self.dut.rst_i.setimmediatevalue(0)       
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_i.value = 1
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)
        self.dut.rst_i.value = 0
        await RisingEdge(self.dut.clk_i)
        await RisingEdge(self.dut.clk_i)

    async def error(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            if (self.dut.u0_beq_loop_test_top.u_beq_loop_test_dfx.error_r_error_r_q.value == 1):
                raise ValueError("error!!!")

    def set_idle_generator(self, generator=None):
        if generator:
            self.loop.beq_txq.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.loop.beq_rxq.set_backpressure_generator(generator)


async def run_test_loop(dut, idle_inserter, backpressure_inserter):
    tcntl = 0
    tcnth = 0
    rcntl = 0
    rcnth = 0
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    cocotb.start_soon(tb.error())
    await tb.loop.milte_master.write(0x0000_0008,0xC876_FABD)
    await tb.loop.milte_master.write(0x0000_0010,0xE43B_7D5E)
    await tb.loop.milte_master.write(0x0000_0018,0x721D_BEAF)
    await tb.loop.milte_master.write(0x0000_0020,0xB90E_DF57)
    await tb.loop.milte_master.write(0x0000_0028,0xDC87_6FAB)
    await tb.loop.milte_master.write(0x0000_0030,0xEE43_B7D5)
    await tb.loop.milte_master.write(0x0000_0038,0xF721_DBEA)
    await tb.loop.milte_master.write(0x0000_0040,0x7B90_EDF5)
    await RisingEdge(tb.dut.clk_i)
    await RisingEdge(tb.dut.clk_i) 
    await tb.loop.milte_master.write(0x0000_0000,0x1f)
    await Timer(4000000, 'ns')
    await RisingEdge(tb.dut.clk_i)
    await RisingEdge(tb.dut.clk_i) 
    await tb.loop.milte_master.write(0x0000_0000,0xf)
    await Timer(40000, 'ns')
    await RisingEdge(tb.dut.clk_i)
    await RisingEdge(tb.dut.clk_i) 
    await tb.loop.milte_master.write(0x0000_0000,0x00)
    await Timer(5000, 'ns')
    await tb.loop.milte_master.write(0x0000_0068,0x01)
    await Timer(400000, 'ns')    
    await tb.loop.milte_master.write(0x0000_0008,0xC876_FABD)
    await tb.loop.milte_master.write(0x0000_0010,0xE43B_7D5E)
    await tb.loop.milte_master.write(0x0000_0018,0x721D_BEAF)
    await tb.loop.milte_master.write(0x0000_0020,0xB90E_DF57)
    await tb.loop.milte_master.write(0x0000_0028,0xDC87_6FAB)
    await tb.loop.milte_master.write(0x0000_0030,0xEE43_B7D5)
    await tb.loop.milte_master.write(0x0000_0038,0xF721_DBEA)
    await tb.loop.milte_master.write(0x0000_0040,0x7B90_EDF5)
    await tb.loop.milte_master.write(0x0000_0000,0xf)
    await Timer(4000000, 'ns')
    await RisingEdge(tb.dut.clk_i)
    await RisingEdge(tb.dut.clk_i)  
    await tb.loop.milte_master.write(0x0000_0000,0x02)   
    await Timer(40000, 'ns')
    tcntl = await tb.loop.milte_master.read(0x0000_0048)
    tcnth = await tb.loop.milte_master.read(0x0000_0050)
    rcntl = await tb.loop.milte_master.read(0x0000_0058)
    rcnth = await tb.loop.milte_master.read(0x0000_0060) 

    tb.log.info("tcntl = {:x},rcntl = {:x},tcnth = {:x},rcnth = {:x}".format(tcntl,rcntl,tcnth,rcnth))



def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:

    for test in [run_test_loop]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)