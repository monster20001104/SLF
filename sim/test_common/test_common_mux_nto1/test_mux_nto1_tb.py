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
from stream_bus import define_stream


MuxBus, MuxTransaction, MuxSource, MuxSink, MuxMonitor = define_stream(
    "mux_nto1", signals=["dat"], optional_signals=None, vld_signal="vld", rdy_signal="rdy"
)

# MuxOutBus, MuxOutTransaction, MuxOutSource, MuxOutSink, MuxOutMonitor = define_stream(
#     "mux_out", signals=["dat"], optional_signals=None, vld_signal="vld", rdy_signal="rdy"
# )


class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.N = int(dut.N)
        # self.depth = int(dut.DEPTH)
        # creat queue for check
        self.queue = Queue(maxsize=8 * self.N)
        cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())

        self.mux_in_bus = MuxSource(MuxBus.from_prefix(dut, "mux_in"), dut.clk, dut.rst)
        # self.mux_in_bus.queue_occupancy_limit = 1
        self.mux_out_bus = MuxSink(MuxBus.from_prefix(dut, "mux_out"), dut.clk, dut.rst)
        # self.mux_out_bus.queue_occupancy_limit = 1
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

    def set_idle_generator(self, generator=None):
        if generator:
            self.mux_in_bus.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.mux_out_bus.set_backpressure_generator(generator)

    async def WrThd(self, max_seq):

        # rseed_len = max_seq + int(max_seq / 4)
        # rseed = [1 if i < max_seq else 0 for i in range(rseed_len)]
        # random.shuffle(rseed)
        # rseed = random.choices([0, 1], weights=[0.2, 0.8], k=max_seq)

        for i in range(max_seq):
            obj = MuxTransaction()
            data = random.randint(0, 2**self.N - 1)
            obj.dat = data
            await self.queue.put(data)
            await self.mux_in_bus.send(obj)
        # for i in range(10):
        #     await RisingEdge(self.dut.clk)
        # if (self.dut.in_vld) == 1:
        #     sum = 0
        #     for i in self.dut.in_data:
        #         sum += int(i)
        #     await self.queue.put(sum)

        # for i in range(max_seq):
        # data = random.randint(0, 2**self.data_width - 1)
        # obj = DataTransaction()
        # obj.data = data
        # await self.queue.put(data)
        # await self.FifoWrBus.send(obj)

    async def RdThd(self, max_seq):

        for i in range(max_seq):
            # log.info("recv seq: {}".format(i))
            ref_data = await self.queue.get()

            print("ref_data", end="")
            print(bin(ref_data))
            for i in range(self.N):
                data = ref_data & (1 << i)
                if data == 0:
                    continue
                else:
                    obj = await self.mux_out_bus.recv()
                    assert data == int(obj.dat)

        # async def Rst(self)


async def run_test_sch(dut, idle_inserter, backpressure_inserter):
    max_seq = 1000
    tb = TB(dut)
    # tb.set_idle_generator(idle_inserter)
    # tb.set_backpressure_generator(backpressure_inserter)
    # await tb.cycle_reset()

    # tb.dut.mux_in_vld.value = 0
    # tb.dut.mux_in_dat.value = 0
    # tb.dut.mux_out_rdy.value = 0
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    # tb.dut.in_data.value = random.randint(0, 2**tb.width - 1)
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
        # factory.add_option("idle_inserter", [None])
        factory.add_option("idle_inserter", [None,cycle_pause])
        # factory.add_option("backpressure_inserter", [None])
        factory.add_option("backpressure_inserter", [None,cycle_pause])
        factory.generate_tests()
