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
from stream_bus import define_stream

InVldBus, InVldTransaction, InVldSource, InVldSink, InVldMonitor = define_stream("invld_master",
    signals=["data"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None,
    signal_widths=None
)    
OutVldBus, OutVldTransaction, OutVldSource, OutVldSink, OutVldMonitor = define_stream("OutVld_master",
    signals=["sum"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None,
    signal_widths=None
)    
# DataBus, DataTransaction, DataSource, DataSink, DataMonitor = define_backpressure(
#     "DataBus", signals=["data"], optional_signals=None, vld_signal="vld", sav_signal="sav"
# )


class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.INFO)

        self.width = int(dut.WIDTH)
        self.depth = int(dut.DEPTH)
        # creat queue for check
        self.queue = Queue(maxsize=512)
        cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
        self.in_master = InVldSource(InVldBus.from_prefix(dut, "in"), dut.clk, dut.rst)
        self.out_slave = OutVldSink(OutVldBus.from_prefix(dut, "out"), dut.clk, dut.rst)

        # self.FifoWrBus = DataSource(DataBus.from_prefix(dut, "wr"), dut.clk, dut.rst)
        # self.FifoRdBus = DataSink(DataBus.from_prefix(dut, "rd"), dut.clk, dut.rst)

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
        #rseed_len = max_seq + int(max_seq / 4)
        #rseed = [1 if i < max_seq else 0 for i in range(rseed_len)]
        #random.shuffle(rseed)
        # rseed = random.choices([0, 1], weights=[0.2, 0.8], k=max_seq)

        for i in range(max_seq):
            #self.dut.in_vld.value = rseed[i]
            obj = self.in_master._transaction_obj()
            obj.data = random.randint(0, 2 ** (self.width * 2**self.depth) - 1)
            await self.in_master.send(obj)
            sub_data_count = 2 ** self.depth
            sub_data_mask = (1 << self.width) - 1
            sum_result = sum(
                (obj.data >> (k * self.width)) & sub_data_mask 
                for k in range(sub_data_count)
            )
            await self.queue.put(sum_result)
            #self.dut.in_data.value = random.randint(0, 2 ** (self.width * 2**self.depth) - 1)
            #if (self.dut.in_vld) == 1:
            #    sum = 0
            #    for i in self.dut.in_data:
            #        sum += int(i)
            #    await self.queue.put(sum)

            #await RisingEdge(self.dut.clk)
        #if (self.dut.in_vld) == 1:
        #    sum = 0
        #    for i in self.dut.in_data:
        #        sum += int(i)
        #    await self.queue.put(sum)

        # for i in range(max_seq):
        # data = random.randint(0, 2**self.data_width - 1)
        # obj = DataTransaction()
        # obj.data = data
        # await self.queue.put(data)
        # await self.FifoWrBus.send(obj)

    async def RdThd(self, max_seq):
        for i in range(max_seq):
            out_sum = await self.out_slave.recv()
            ref_data = await self.queue.get()
            if ref_data != out_sum.sum.integer:
                raise ValueError(
                    "The result is mismatch(ref:{} dat:{})".format(
                        ref_data, out_sum.sum.integer
                    )
                )
            #while 1:
            #    if int(self.dut.out_vld) == 1:
            #        if ref_data != int(self.dut.out_sum):
            #            raise ValueError(
            #                "The result is mismatch(ref:{} dat:{})".format(
            #                    ref_data, self.dut.out_sum
            #                )
            #            )
            #        else:
            #            await RisingEdge(self.dut.clk)
            #            break
            #    else:
            #        await RisingEdge(self.dut.clk)
            # data = await self.FifoRdBus.recv()

        print("true_down")

    def set_idle_generator(self, generator=None):
        self.in_master.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        self.out_slave.set_backpressure_generator(generator)


async def run_test_sch(dut, idle_inserter, backpressure_inserter):
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    # await tb.cycle_reset()

    tb.dut.in_data.value = 0
    tb.dut.in_vld.value = 0
    # tb.dut.in_data.value = random.randint(0, 2**tb.width - 1)
    await tb.cycle_reset()
    # for i in range(10):
    #     tb.dut.in_vld.value = rseed[i]
    #     tb.dut.in_data.value = random.randint(0, 2 ** (tb.width * 2**tb.depth) - 1)

    #     tb.WrThd()
    #     # for j in range(2**tb.depth):
    #     # value = 1
    #     # print(j)
    #     # print(value)
    #     # tb.dut.in_data[j].value = value
    #     # pass
    #     # tb.dut.in_data.value[1] = 1
    #     if tb.dut.in_vld == 1:
    #         sum = 0
    #         for i in tb.dut.in_data:
    #             print(int(i))
    #             sum += int(i)
    #         print(sum)
    #         # data = tb.dut.in_data

    #         # print(int(tb.dut.in_data[0]))
    #         # print(int(tb.dut.in_data[1]))
    #         # # data = sum(int(tb.dut.in_data))
    #         # print(int(data.value))
    #         print("\n")
    #     await RisingEdge(tb.dut.clk)
    #     # random
    max_seq = 1000
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
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()
