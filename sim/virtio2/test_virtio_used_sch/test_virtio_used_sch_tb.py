#!/usr/bin/env python3
################################################################################
#  文件名称 : test_used_sch_tb.py
#  作者名称 : cui naiwan
#  创建日期 : 2025/07/07
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0   07/07     cui naiwan   初始化版本
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
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, ClockCycles, Combine
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union, AsyncGenerator
from cocotb.regression import TestFactory


sys.path.append('../../common')
from backpressure_bus import define_backpressure
from stream_bus import define_stream
from enum import Enum, unique

BlkupstreamBus, _, BlkupstreamSource, BlkupstreamSink, BlkupstreamMonitor = define_stream("blk_upstream_wr_used_info",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NetTxBus, _, NetTxSource, NetTxSink, NetTxMonitor = define_stream("net_tx_wr_used_info",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NetRxBus, _, NetRxSource, NetRxSink, NetRxMonitor = define_stream("net_rx_wr_used_info",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

WrusedinfoBus, _, WrusedinfoSource, WrusedinfoSink, WrusedinfoMonitor = define_stream("wr_used_info",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

class VirtioUsedinfo(Packet):
    name = 'virtio_used_info'
    fields_desc = [
        BitField("vq",   0,  10),
        BitField("elem",   0,  64),
        BitField("used_idx",   0,   16),
        BitField("err_info",   0,   8),
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        #assert type(data) == cocotb.binary.BinaryValue
        assert type(data) == bytes
        #return cls(data.buff)
        return cls(data)


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.BlkupstreamDrv = BlkupstreamSource(BlkupstreamBus.from_prefix(dut, "blk_upstream_wr_used_info"), dut.clk, dut.rst)
        self.NetTxDrv = NetTxSource(NetTxBus.from_prefix(dut, "net_tx_wr_used_info"), dut.clk, dut.rst)
        self.NetRxDrv = NetRxSource(NetRxBus.from_prefix(dut, "net_rx_wr_used_info"), dut.clk, dut.rst)

        self.wrusedinfoMon = WrusedinfoSink(WrusedinfoBus.from_prefix(dut, "wr_used_info"), dut.clk, dut.rst)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

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
            self.BlkupstreamDrv.set_pause_generator(generator()) 
            self.NetTxDrv.set_pause_generator(generator()) 
            self.NetRxDrv.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.wrusedinfoMon.set_pause_generator(generator()) 

    async def _send_from_source(self, source: str, max_seq: int) -> AsyncGenerator[int, None]:
        self.log.debug("send_from_source start")
        for i in range(max_seq):
            if source == "blk":
                data = VirtioUsedinfo(vq=i, elem=i*100, used_idx=i, err_info=0).pack()
            elif source == "tx":
                data = VirtioUsedinfo(vq=i+10, elem=i*200, used_idx=i+10, err_info=1).pack()
            else:  # rx
                data = VirtioUsedinfo(vq=i+20, elem=i*300, used_idx=i+20, err_info=2).pack()
            
            yield data

            await ClockCycles(self.dut.clk, random.randint(0, 3))

    async def _send_from_blk(self, max_seq):
        
        async for data in self._send_from_source("blk", max_seq):
            self.log.debug("send_from_blk start")
            blkupstream = self.BlkupstreamDrv._transaction_obj()
            blkupstream.dat = data
            self.log.debug("dat = {}".format(blkupstream.dat))
            await self.BlkupstreamDrv.send(blkupstream)

    async def _send_from_nettx(self, max_seq):
        
        async for data in self._send_from_source("tx", max_seq):
            self.log.debug("send_from_nettx start")
            nettx = self.NetTxDrv._transaction_obj()
            nettx.dat = data
            self.log.debug("dat = {}".format(nettx.dat))
            await self.NetTxDrv.send(nettx)
        
    async def _send_from_netrx(self, max_seq):
        
        async for data in self._send_from_source("rx", max_seq):
            self.log.debug("send_from_netrx start")
            netrx = self.NetRxDrv._transaction_obj()
            netrx.dat = data
            self.log.debug("dat = {}".format(netrx.dat))
            await self.NetRxDrv.send(netrx)

async def run_test(dut, idle_inserter, backpressure_inserter):
    max_seq = 10000
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)  

    await tb.cycle_reset() 
    # waiting for init
    await Timer(1000, "ns")


    blk_cr = cocotb.start_soon(tb._send_from_blk(max_seq))
    nettx_cr = cocotb.start_soon(tb._send_from_nettx(max_seq))
    netrx_cr = cocotb.start_soon(tb._send_from_netrx(max_seq))

    #wrusedinfo_cr = cocotb.start_soon(tb._wrusedinfoThd())
    
    await Combine(blk_cr, nettx_cr, netrx_cr)
    #await blk_cr.join()
    #await nettx_cr.join()
    #await netrx_cr.join()
    await ClockCycles(dut.clk, 100)
    tb.log.debug("test finish")
 
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