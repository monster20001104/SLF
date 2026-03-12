###########################################
# 文件名称 : test_p_probe_tb
# 作者名称 : 崔飞翔
# 创建日期 : 2025/03/06
# 功能描述 : 
# 
# 修改记录 : 
# 
# 修改日期 : 2025/03/06
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
from enum import Enum, unique
import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time

sys.path.append('../../common')
from bus.mlite_bus      import MliteBus
from drivers.mlite_bus import MliteBusMaster
from bus.tlp_adap_bypass_bus import TlpBypassBus, OpCode, ComplStatus, TlpBypassReq, TlpBypassRsp, TlpBypassReq2CfgTlp, Tlp2TlpBypassCpl
from drivers.tlp_adap_bypass_bus import TlpBypassMaster
from monitors.tlp_adap_bypass_bus import TlpBypassSlave



class TB(object):
    def __init__(self,dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 5, units="ns").start())
        self.s2emu_tlpBypass = TlpBypassSlave(TlpBypassBus.from_prefix(dut, "switch2emu_tlp_bypass"), dut.clk, dut.rst)
        self.host2s_tlpBypass = TlpBypassMaster(TlpBypassBus.from_prefix(dut, "host2switch_tlp_bypass"), dut.clk, dut.rst)
            
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
        self.dut.timer.value = 1000


    async def tlp_driver_send(self,max_seq):
        for i in range(max_seq):
            print(f"cnt is {i}")
            tag = 0
            opcode = OpCode.CFGWr0
            addr = 0
            byte_length = 4
            first_be = 0
            last_be = 0
            req_id = 0
            dest_id = 0
            ext_reg_num = 0
            reg_num = 0
            data = bytes([0x01,0x02,0x03])
            req = TlpBypassReq(opcode,addr,byte_length,tag,req_id,first_be,last_be,dest_id,ext_reg_num,reg_num,data,None)   
            await self.host2s_tlpBypass.send_req(req,0)


    async def tlp_driver_recv(self):
        while True:
            await self.host2s_tlpBypass.recv_rsp()

    async def tlp_monitor_recv(self):
        while True:
            await self.s2emu_tlpBypass.recv_req()

    async def tlp_monitor_send(self):
        while True:
            opcode = OpCode.Cpl
            tag = 0
            addr = 0
            byte_length = 0
            cpl_byte_count =  byte_length
            cpl_id = 0
            req_id = 0
            cpl_status = ComplStatus.SC
            first_be = 0
            last_be = 0
            data = bytes(0x0)
            rsp = TlpBypassRsp(opcode, addr, cpl_byte_count, byte_length, tag, cpl_id, req_id, cpl_status, first_be, last_be, data, None)
            await self.s2emu_tlpBypass.send_rsp(rsp,0)

    def set_idle_generator(self, generator=None): 
        if generator:
            self.s2emu_tlpBypass.set_idle_generator(generator)
            self.host2s_tlpBypass.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
       if generator:
            self.s2emu_tlpBypass.set_backpressure_generator(generator)
            self.host2s_tlpBypass.set_backpressure_generator(generator)

async def run_test(dut, idle_inserter, backpressure_inserter):
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    cocotb.start_soon(tb.tlp_monitor_recv())
    cocotb.start_soon(tb.tlp_driver_recv())
    cocotb.start_soon(tb.tlp_monitor_send())
    
    await tb.tlp_driver_send(max_seq=20000)
    await Timer(4000, 'ns')
    print("end")


def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
