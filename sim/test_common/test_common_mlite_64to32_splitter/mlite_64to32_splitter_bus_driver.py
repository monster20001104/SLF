#!/usr/bin/env python3
################################################################################
#  文件名称 : mlite_64to32_splitter_bus_driver.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/01
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/01     Joe Jiang   初始化版本
################################################################################
import logging
import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, ReadOnly
from cocotb.binary import BinaryValue
import random

from cocotb_bus.drivers import BusDriver
from cocotb_bus.monitors import BusMonitor
from typing import List, NamedTuple, Union
from cocotb.triggers import Event, with_timeout

import sys
sys.path.append('../../common/')
from bus.mlite_bus import MliteReqSource, MliteRspSink
from reset import Reset

class DmaReadReq(NamedTuple):
    addr :  int
    data :  int
    read :  bool
    en_f0:  int
    event:  Event

class MliteBusException(Exception):
    pass

class MliteBusMaster(Reset):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, timeout=1024, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset

        self._timeout = timeout

        self.log = logging.getLogger(f"cocotb.{bus.req._entity._name}.{bus.req._name}")
        self.log = logging.getLogger(f"cocotb.{bus.rsp._entity._name}.{bus.rsp._name}")

        self.req_channel = MliteReqSource(bus.req, clock, reset, reset_active_level)
        self.req_channel.queue_occupancy_limit = 2

        self.rsp_channel = MliteRspSink(bus.rsp, clock, reset, reset_active_level)
        self.rsp_channel.queue_occupancy_limit = 2

        self.req_queue = Queue(maxsize=4)
        self.req_queue.queue_occupancy_limit = 2

        self.rsp_queue = Queue(maxsize=4)
        self.rsp_queue.queue_occupancy_limit = 2

        self.addr_width = len(self.req_channel.bus.addr)
        self.data_width = len(self.req_channel.bus.wdata)
        self.mask_width = len(self.req_channel.bus.wmask)

        self._process_req_cr = None
        self._process_rsp_cr = None

        self._init_reset(reset, reset_active_level)
        self.log.debug("MliteBusMaster created")

    def set_idle_generator(self, generator=None):
        if generator:
            self.req_channel.set_pause_generator(generator())
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.rsp_channel.set_pause_generator(generator())


    def _handle_reset(self, state):
        if state:
            self.log.info("Reset asserted")
            if self._process_req_cr is not None:
                self._process_req_cr.kill()
                self._process_req_cr = None
            if self._process_rsp_cr is not None:
                self._process_rsp_cr.kill()
                self._process_rsp_cr = None

            self.req_channel.clear()
            self.rsp_channel.clear()

            while not self.req_queue.empty():
                req = self.req_queue.get_nowait()
                req.event.set()

            while not self.rsp_queue.empty():
                rsp = self.rsp_queue.get_nowait()
                rsp.event.set()
        else:
            self.log.info("Reset de-asserted")
            if self._process_req_cr is None:
                self._process_req_cr = cocotb.start_soon(self._process_req())
            if self._process_rsp_cr is None:
                self._process_rsp_cr = cocotb.start_soon(self._process_rsp())

    async def _process_req(self):
        while True:
            req = await self.req_queue.get()
            req_data = self.req_channel._transaction_obj()
            if req.en_f0 == 0:
                if req.read:
                    req_data.read = True
                    req_data.addr = req.addr & 0xfffffffffffffff8
                    low_addr = req.addr & 0x7
                    req_data.wdata = random.randint(0, 2**self.data_width-1)
                    req_data_wmask = 0xff << low_addr
                    req_data.wmask = req_data_wmask & 0xff
                    #print(req.addr, len(self.req_channel.bus.wdata)//8)
                    await self.req_channel.send(req_data)
                    await self.rsp_queue.put(req)
                else:
                    req_data.read = False
                    req_data.addr = req.addr & 0xfffffffffffffff8
                    low_addr = req.addr & 0x7
                    req_data_wdata = req.data << (low_addr*8)
                    req_data.wdata = req_data_wdata & 0xffffffffffffffff
                    req_data_wmask = 0xff << low_addr
                    req_data.wmask = req_data_wmask & 0xff
                    await self.req_channel.send(req_data)
                    req.event.set() 
            else :
                if req.read:
                    req_data.read = True
                    req_data.addr = req.addr & 0xfffffffffffffff8
                    low_addr = req.addr & 0x7
                    low_addr_d = 7 - low_addr
                    req_data.wdata = random.randint(0, 2**self.data_width-1)
                    req_data_wmask = 0xff >> low_addr_d
                    req_data.wmask = req_data_wmask & 0xff
                    #print(req.addr, len(self.req_channel.bus.wdata)//8)
                    await self.req_channel.send(req_data)
                    await self.rsp_queue.put(req)
                else:
                    req_data.read = False
                    req_data.addr = req.addr & 0xfffffffffffffff8
                    low_addr = req.addr & 0x7
                    low_addr_d = 7 - low_addr
                    req_data_wdata = req.data 
                    req_data.wdata = req_data_wdata & 0xffffffffffffffff
                    req_data_wmask = 0xff >> low_addr_d
                    req_data.wmask = req_data_wmask & 0xff
                    await self.req_channel.send(req_data)
                    req.event.set() 
    
    async def _process_rsp(self):
        while True:
            rsp = await self.rsp_queue.get()
            rsp_data = await self.rsp_channel.recv()
            rsp.event.set(rsp_data.rdata)
            
    async def read(self, address: int, en_f0: int, sync: bool = True) -> BinaryValue:
        if address < 0 or address >= 2**self.addr_width:
            raise ValueError("Address out of range")
        event = Event()
        req = DmaReadReq(address, 0, True, en_f0, event)
        await self.req_queue.put(req)
        await with_timeout(event.wait(), self._timeout, "us")
        low_addr = address & 0x7
        if en_f0 == 0:
            return event.data >> (low_addr*8)
        else:
            return event.data >> 0
        

    async def write(self, address: int, value: int, en_f0: int, sync: bool = True, ) -> None:
        if address < 0 or address >= 2**self.addr_width:
            raise ValueError("Address out of range")
        if not isinstance(value, int):
            raise ValueError("Expected int for value")
        if value < 0 or value >= 2**self.data_width:
            raise ValueError("Value out of range")
        event = Event()
        req = DmaReadReq(address, value, False, en_f0, event)
        await self.req_queue.put(req)
        await event.wait()
        return event.data



    