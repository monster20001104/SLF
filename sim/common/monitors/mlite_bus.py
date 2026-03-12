#!/usr/bin/env python3
################################################################################
#  文件名称 : mlite_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/09/05
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  09/05     Joe Jiang   初始化版本
################################################################################

import logging
from collections import Counter
from typing import List, NamedTuple, Union

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Event, First, Timer

import sys
sys.path.append('..')
from bus.mlite_bus import MliteReqSink, MliteRspSource

from reset import Reset
from address_space import AddressSpace, MemoryRegion

class MliteBusRam(Reset):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, size=4096, **kwargs):
        self._mem = AddressSpace()
        self._region = MemoryRegion(size)
        self._mem.register_region(self._region, 0)
        self.bus = bus
        self.clock = clock
        self.reset = reset

        self.log = logging.getLogger(f"cocotb.{bus.req._entity._name}.{bus.req._name}")
        self.log = logging.getLogger(f"cocotb.{bus.rsp._entity._name}.{bus.rsp._name}")

        self.req_channel = MliteReqSink(bus.req, clock, reset, reset_active_level)
        self.req_channel.queue_occupancy_limit = 2

        self.rsp_channel = MliteRspSource(bus.rsp, clock, reset, reset_active_level)
        self.rsp_channel.queue_occupancy_limit = 2

        self.req_queue = Queue(maxsize=8)
        self.req_queue.queue_occupancy_limit = 2

        self._process_req_cr = None
        self._process_rsp_cr = None

        self._init_reset(reset, reset_active_level)
    
    def set_idle_generator(self, generator=None):
        if generator:
            self.rsp_channel.set_pause_generator(generator())
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.req_channel.set_pause_generator(generator())


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

            while not self.req_queue.empty():
                cmd = self.req_queue.get_nowait()
        else:
            self.log.info("Reset de-asserted")
            if self._process_req_cr is None:
                self._process_req_cr = cocotb.start_soon(self._process_req())
            if self._process_rsp_cr is None:
                self._process_rsp_cr = cocotb.start_soon(self._process_rsp())


    async def _process_req(self):
        while True:
            req = await self.req_channel.recv()
            if (not req.read and ( "x" in str(req.addr) or "x" in str(req.wdata) or "x" in str(req.wmask))) or (req.read and "x" in str(req.addr)):
                print(req)
                ValueError("x in data when Requeste")
            addr = int(req.addr)
            if req.read:
                #print(req.addr, len(self.req_channel.bus.wdata)//8)
                rdata = await self._mem.read(addr, len(self.req_channel.bus.wdata)//8)
                await self.req_queue.put(rdata)
            else:
                data = await self._mem.read(addr, len(self.req_channel.bus.wdata)//8)                
                mask = int(req.wmask)
                wdata =  req.wdata.buff[::-1]
                new_data = b''
                for i in range(len(self.req_channel.bus.wdata)//8):
                    if(mask & 0x1):
                        new_data = new_data + wdata[i:i+1]
                    else:
                        new_data = new_data + data[i:i+1]
                    mask = mask >> 1
                await self._mem.write(addr, new_data)
    
    async def _process_rsp(self):
        while True:
            data = await self.req_queue.get()
            rsp_data = self.rsp_channel._transaction_obj()
            rsp_data.rdata = int.from_bytes(data, byteorder="little")
            await self.rsp_channel.send(rsp_data)
