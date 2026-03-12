#!/usr/bin/env python3
################################################################################
#  文件名称 : test_pkt_fifo_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/20
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/20     Joe Jiang   初始化版本
################################################################################
import itertools
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


sys.path.append('../../common')
from stream_bus import define_stream

PktFifoReqBus, PktFifoReqTransaction, PktFifoReqSource, PktFifoReqSink, _ = define_stream("pkt_fifo",
    signals=["dat", "eop", "drop"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths={"rdy": 1}
)

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.dist_pkt_ff_in = PktFifoReqSource(PktFifoReqBus.from_prefix(dut, "dist_in"), dut.clk, dut.rst)
        self.dist_pkt_ff_in.queue_occupancy_limit = 1
        self.dist_pkt_ff_out = PktFifoReqSink(PktFifoReqBus.from_prefix(dut, "dist_out"), dut.clk, dut.rst)
        self.dist_pkt_ff_out.queue_occupancy_limit = 1

        self.blk_pkt_ff_in = PktFifoReqSource(PktFifoReqBus.from_prefix(dut, "blk_in"), dut.clk, dut.rst)
        self.blk_pkt_ff_in.queue_occupancy_limit = 1
        self.blk_pkt_ff_out = PktFifoReqSink(PktFifoReqBus.from_prefix(dut, "blk_out"), dut.clk, dut.rst)
        self.blk_pkt_ff_out.queue_occupancy_limit = 1
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
            self.dist_pkt_ff_in.set_idle_generator(generator)
            self.blk_pkt_ff_in.set_idle_generator(generator)
              
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.dist_pkt_ff_out.set_backpressure_generator(generator)
            self.blk_pkt_ff_out.set_backpressure_generator(generator)

def pkt_gen(max_dat):
    if random.randint(0, 100) < 20:
        return [random.randint(0, max_dat)]
    else:
        return [random.randint(0, max_dat) for _ in range(random.randint(1, 128))]

async def sendThd(sender, ref_queue, max_dat, max_seq, log):
    for i in range(max_seq):
        log.info("send seq: {}".format(i))
        dat = pkt_gen(max_dat)
        drop = True
        while drop:
            drop = random.randint(0, 100) < 3
            if not drop:
                await ref_queue.put(dat)
            for i in range(len(dat)):
                eop = i == len(dat) - 1
                obj = PktFifoReqTransaction()
                obj.eop = eop
                obj.dat = dat[i]
                obj.drop = drop if eop else False
                await sender.send(obj)

async def recvThd(recver, ref_queue, max_seq, log):
    for i in range(max_seq):
        log.info("recv seq: {}".format(i))
        ref_dat = await ref_queue.get()
        for i in range(len(ref_dat)):
            obj = await recver.recv()
            log.info("idx:{}\n ref:{}\n dat:{}".format(i, hex(ref_dat[i]), hex(int(obj.dat))))
            if obj.dat != ref_dat[i]:
                #log.warning("idx:{}\n ref:{}\n dat:{}".format(i, ref_dat[i], int(obj.dat)))
                raise ValueError("dat is  mismatched!")
            if (i == len(ref_dat) - 1) != obj.eop:
                raise ValueError("eop is  mismatched!")


async def run_test(dut,idle_inserter, backpressure_inserter):
    dist_ref_queue = Queue(maxsize=8)
    blk_ref_queue = Queue(maxsize=8)
    tb = TB(dut) 
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
<<<<<<< HEAD:sim/test_common/test_common_pkt_fifo/test_pkt_fifo_tb.py
    max_seq = 100
    max_dat = 2**len(dut.in_dat)-1
=======
    max_seq = 10000
    max_dat = 2**len(dut.dist_in_dat)-1
>>>>>>> f1146924a12d2750b9cbae10a1d01cebd7735d9c:sim/test_common_pkt_fifo/test_pkt_fifo_tb.py
    await tb.cycle_reset() 

    dist_senderCr = cocotb.start_soon(sendThd(tb.dist_pkt_ff_in, dist_ref_queue, max_dat, max_seq, tb.log))
    dist_recverCr = cocotb.start_soon(recvThd(tb.dist_pkt_ff_out, dist_ref_queue, max_seq, tb.log))

    blk_senderCr = cocotb.start_soon(sendThd(tb.blk_pkt_ff_in, blk_ref_queue, max_dat, max_seq, tb.log))
    blk_recverCr = cocotb.start_soon(recvThd(tb.blk_pkt_ff_out, blk_ref_queue, max_seq, tb.log))

    await dist_senderCr.join()
    await dist_recverCr.join()
    await blk_senderCr.join()
    await blk_recverCr.join()

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