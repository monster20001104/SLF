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
from enum import Enum, unique


MultiCdcBus, MultiCdcTransaction, MultiCdcSource, MultiCdcSink, MultiCdcMonitor = define_stream("multi_cdc",
    signals=["data"], 
    optional_signals=None,
    vld_signal = "valid",
    rdy_signal = "ready"
)


class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.data_width = len(dut.din_data)
        self.queue = Queue(maxsize=512)
        cocotb.start_soon(Clock(dut.din_clk, 3, units="ns").start())
        cocotb.start_soon(Clock(dut.dout_clk, 13, units="ns").start())
    

        self.MultiCdcDrv = MultiCdcSource(MultiCdcBus.from_prefix(dut, "din"), dut.din_clk, dut.din_rst)
        self.MultiCdcDrv.queue_occupancy_limit = 8

        self.MultiCdcMon = MultiCdcSink(MultiCdcBus.from_prefix(dut, "dout"), dut.dout_clk, dut.dout_rst)

    async def cycle_reset(self):
        async def rest(rst_pin,clk):
            rst_pin.value = 0
            await Timer(1,"us")
            await RisingEdge(clk)
            rst_pin.value = 1
            await Timer(1,"us")
            await RisingEdge(clk) 
            rst_pin.value = 0
            await RisingEdge(clk) 
            await RisingEdge(clk)
            await RisingEdge(clk)

        rst_din_clk_cr = cocotb.start_soon(rest(self.dut.din_rst, self.dut.din_clk)) 
        rst_dout_clk_cr = cocotb.start_soon(rest(self.dut.dout_rst, self.dut.dout_clk)) 

        await rst_din_clk_cr.join()
        await rst_dout_clk_cr.join()
        


    async def TransThd(self, max_seq):
        for i in range(max_seq):
            data = random.randint(1, 2**self.data_width-1)
            obj = MultiCdcTransaction()
            obj.data = data
            print("111111111")
            print("data = ",obj)
            await self.queue.put(data)
            print("222222222")
            await self.MultiCdcDrv.send(obj)

    async def RecvThd(self, max_seq):
        for i in range(max_seq):
            ref_data = await self.queue.get()
            print("33333333")
            data = await self.MultiCdcMon.recv()
            print("44444444")
            if ref_data != int(data.data):
                print("ref_data =" ,(ref_data),"data = ",int(data.data))
                raise ValueError("The result is mismatch(ref:{} dat:{})".format(ref_data, data))
            
            
    async def time_out(self):
        time = 0
        while True:
            await RisingEdge(self.dut.din_clk)
            time = time + 1
            if time == 80000:
                raise ValueError("time out error!!!")

    def set_idle_generator(self, generator=None):
        self.MultiCdcDrv.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        self.MultiCdcMon.set_backpressure_generator(generator)


async def run_test(dut, idle_inserter, backpressure_inserter):
    max_seq = 10
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    cocotb.start_soon(tb.time_out())


    wrCr = cocotb.start_soon(tb.TransThd(max_seq))
    rdCr = cocotb.start_soon(tb.RecvThd(max_seq))

    await wrCr.join()
    await rdCr.join()

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