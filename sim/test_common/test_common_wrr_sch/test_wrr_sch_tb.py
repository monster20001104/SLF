'''
Author: Joe Jiang
Date: 2024-07-29 15:08:51
LastEditTime: 2024-07-29 19:57:49
LastEditors: Joe Jiang
Description: 
FilePath: /dpu10prj/sim/test_wrr_sch/test_wrr_sch.py
Copyright (c) 2024 Yucca
'''
#!/usr/bin/python3
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
from scapy.all import Packet, BitField

sys.path.append('../common/')

class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    async def cycle_reset(self):
        sch_num = len(self.dut.sch_grant)
        weight_width = int(len(self.dut.sch_weight)/sch_num)
        class SchWeightObj(Packet):
            name = 'sch weight'
            fields_desc = [
                BitField("port{}".format(i), i+1, weight_width) for i in range(sch_num)
            ]
        schWeight = SchWeightObj()
        self.dut.sch_weight.value = int.from_bytes(schWeight.build(), byteorder="little")

        self.dut.sch_en.value = 0
        self.dut.sch_req.value = 0
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

async def run_test_sch(dut):

    tb = TB(dut)
    await tb.cycle_reset()
    max_seq = 50 * len(dut.sch_grant)
    dut.sch_en.setimmediatevalue(1)
    dut.sch_req.setimmediatevalue(0xf)

    async def sch_req():
        for i in range(0, max_seq):
            await RisingEdge(dut.clk)

    async def sch_rsp():
        cnts = list()

        for i in range(len(dut.sch_grant)):
            cnts.append(0)
        for i in range(0, max_seq):
            await Timer(0.1, units="ns")
            if int(dut.sch_grant_vld.value):
                #tb.log.info("idx {} sch_grant {}".format(i, int(dut.sch_grant.value)))
                cnts[int(math.log2(int(dut.sch_grant.value)))] = cnts[int(math.log2(int(dut.sch_grant.value)))] + 1
            await RisingEdge(dut.clk)
        tb.log.info(cnts)
        for i in range(1, len(dut.sch_grant)):
            assert cnts[i-1] / (i) == cnts[i] / (i+1)
    cocotb.start_soon(sch_req())
    cocotb.start_soon(sch_rsp())

    for i in range(0, max_seq):
        await RisingEdge(dut.clk)


if cocotb.SIM_NAME:

    for test in [run_test_sch]:

        factory = TestFactory(test)
        #factory.add_option("idle_inserter", [None, cycle_pause])
        #factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()