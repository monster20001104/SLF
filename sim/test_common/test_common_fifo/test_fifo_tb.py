import itertools
import logging
import os
import sys
import random
import cocotb_test.simulator

import cocotb
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory


sys.path.append('../../common')
from backpressure_bus import define_backpressure


DataBus, DataTransaction, DataSource, DataSink, DataMonitor = define_backpressure("DataBus",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    sav_signal = "sav"
)


class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.data_width = len(dut.wr_dat)
        self.queue = Queue(maxsize=512)
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
        self.FifoWrBus = DataSource(DataBus.from_prefix(dut, "wr"), dut.clk, dut.rst)
        self.FifoRdBus = DataSink(DataBus.from_prefix(dut, "rd"), dut.clk, dut.rst)

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

    async def WrThd(self, max_seq):
        for i in range(max_seq):
            data = random.randint(0, 2**self.data_width-1)
            obj = DataTransaction()
            obj.dat = data
            await self.queue.put(data)
            await self.FifoWrBus.send(obj)

    async def RdThd(self, max_seq):
        for i in range(max_seq):
            ref_data = await self.queue.get()
            data = await self.FifoRdBus.recv()
            if ref_data != int(data.dat):
                raise ValueError("The result is mismatch(ref:{} dat:{})".format(ref_data, data))

    def set_idle_generator(self, generator=None):
        self.FifoWrBus.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        self.FifoRdBus.set_backpressure_generator(generator)


async def run_test_sch(dut, idle_inserter, backpressure_inserter):
    max_seq = 10000
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()


    wrCr = cocotb.start_soon(tb.WrThd(max_seq))
    rdCr = cocotb.start_soon(tb.RdThd(max_seq))

    await wrCr.join()
    await rdCr.join()

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test_sch]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None])
        factory.add_option("backpressure_inserter", [cycle_pause])
        factory.generate_tests()