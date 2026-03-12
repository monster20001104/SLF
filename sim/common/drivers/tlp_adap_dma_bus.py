#!/usr/bin/env python3
################################################################################
#  文件名称 : tlp_adap_dma_bus.py
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
from collections import Counter
from typing import List, NamedTuple, Union

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Event, First, Timer

import sys
sys.path.append('..')
from bus.tlp_adap_dma_bus import DmaWrReqSource, DmaWrRspSink, DmaRdReqSource, DmaRdRspSink, DmaWrRspSinkSav, DmaRdRspSinkSav, Desc
from address_space import Region
from reset import Reset

class DmaWriteReq(NamedTuple):
    address: int
    sty: int
    data: bytes
    bdf: int
    dev_id: int
    vf_active: bool
    rd2rsp_loop: int
    has_rsp: bool

class DmaReadReq(NamedTuple):
    address: int
    length: int
    sty: int
    bdf: int
    vf_active: bool
    rd2rsp_loop: int
    event: Event

class DmaReadRSP(NamedTuple):
    data: bytes
    bdf: int
    sty: int
    rd2rsp_loop: int
    err: bool
    event: Event


class DmaMasterWrite(Region, Reset):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=4096, max_pause_duration=8, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset
        self.log = logging.getLogger(f"cocotb.{bus.wr_req._entity._name}.{bus.wr_req._name}")
        self.wr_req_channel = DmaWrReqSource(bus.wr_req, clock, reset, reset_active_level, max_pause_duration)
        self.wr_req_channel.queue_occupancy_limit = 2
        if bus.has_sav == None:
            self.wr_rsp_channel = DmaWrRspSink(bus.wr_rsp, clock, reset, reset_active_level, max_pause_duration)
        else :
            self.wr_rsp_channel = DmaWrRspSinkSav(bus.wr_rsp, clock, reset, reset_active_level, max_pause_duration)
        self.wr_rsp_channel.queue_occupancy_limit = 2

        self.write_command_queue = Queue(maxsize=8)
        self.write_command_queue.queue_occupancy_limit = 2
        self.current_write_command = None

        self.write_rsp_command_queue = Queue(maxsize=8)

        self.write_rsp_result_queue = Queue(maxsize=8)

        self.write_rsp_result_queue_sync = Event()

        self.in_flight_operations = 0
        self._idle = Event()
        self._idle.set()

        self.address_width = 64
        self.width = len(self.wr_req_channel.bus.wr_req_data)
        self.byte_size = 8
        self.byte_lanes = self.width // self.byte_size
        self.max_burst_size = max(min(max_burst_size, 8192), 1)
        super().__init__(2**self.address_width, **kwargs)

        self.log.info("tlp adap DMA master configuration:")
        self.log.info("  Address width: %d bits", self.address_width)
        self.log.info("  Byte size: %d bits", self.byte_size)
        self.log.info("  Data width: %d bits (%d bytes)", self.width, self.byte_lanes)
        self.log.info("  Max burst size: %d bytes", self.max_burst_size)

        assert self.byte_lanes * self.byte_size == self.width

        self._process_write_cr = None
        self._process_write_resp_cr = None

        self._init_reset(reset, reset_active_level)

    def set_idle_generator(self, generator=None):
        if generator:
            self.wr_req_channel.set_pause_generator(generator())
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.wr_rsp_channel.set_pause_generator(generator())

    def idle(self):
        return not self.in_flight_operations

    async def wait(self):
        while not self.idle():
            await self._idle.wait()

    async def write_nb_req(self, address, data, sty, rd2rsp_loop, bdf=0, dev_id=0, vf_active=0, has_rsp=None):
        if address < 0 or address >= 2**self.address_width:
            raise ValueError("Address out of range")
        if isinstance(data, int):
            raise ValueError("Expected bytes or bytearray for data")
        if len(data) > self.max_burst_size:
            raise ValueError("Requested burst size exceeds maximum burst size")
        if len(data) == 0:
            raise ValueError("Requested len size cannot be zero")

        self.in_flight_operations += 1
        self._idle.clear()
        cmd = DmaWriteReq(address, sty, data, bdf, dev_id, vf_active, rd2rsp_loop, has_rsp)
        await self.write_command_queue.put(cmd)

    def _handle_reset(self, state):
        if state:
            self.log.info("Reset asserted")
            if self._process_write_cr is not None:
                self._process_write_cr.kill()
                self._process_write_cr = None
            if self._process_write_resp_cr is not None:
                self._process_write_resp_cr.kill()
                self._process_write_resp_cr = None

            self.wr_req_channel.clear()
            def flush_cmd(cmd):
                self.log.warning("Flushed write operation during reset: %s", cmd)
                if cmd.event:
                    cmd.event.set(None)
            while not self.write_command_queue.empty():
                cmd = self.write_command_queue.get_nowait()
                flush_cmd(cmd)
            while not self.write_rsp_command_queue.empty():
                cmd = self.write_rsp_command_queue.get_nowait()
                flush_cmd(cmd)

            while not self.write_rsp_result_queue.empty():
                cmd = self.write_rsp_result_queue.get_nowait()

            if self.current_write_command:
                cmd = self.current_write_command
                self.current_write_command = None
                flush_cmd(cmd)

            self.in_flight_operations = 0
            self._idle.set()
        else:
            self.log.info("Reset de-asserted")
            if self._process_write_cr is None:
                self._process_write_cr = cocotb.start_soon(self._process_write())
            if self._process_write_resp_cr is None:
                self._process_write_resp_cr = cocotb.start_soon(self._process_write_resp())
    async def _process_write(self):
        while True:
            cmd = await self.write_command_queue.get()
            self.current_write_command = cmd
            data = cmd.data
            length = len(data)
            sty = cmd.sty
            cycles = (sty + length + self.byte_lanes - 1)//self.byte_lanes
            mty = (self.byte_lanes - (length + sty)) % self.byte_lanes
            desc = Desc(pcie_addr=cmd.address, pcie_length=length, rd2rsp_loop=cmd.rd2rsp_loop, vf_active=cmd.vf_active, bdf=cmd.bdf, dev_id=cmd.dev_id)
            for i in range(cycles):
                req = self.wr_req_channel._transaction_obj()
                req.wr_req_desc = desc.pack()
                req.wr_req_sty = sty if(i == 0) else 0
                req.wr_req_mty = mty if(i == cycles-1) else 0
                req.wr_req_sop = i == 0
                req.wr_req_eop = i == cycles-1
                local_len = self.byte_lanes - req.wr_req_sty - req.wr_req_mty
                tmp = b'\x00'*req.wr_req_sty + data[0:local_len]
                data = data[local_len:]
                req.wr_req_data = int.from_bytes(tmp, byteorder="little")
                await self.wr_req_channel.send(req)

            #cmd.event.set(None)
            await self.write_rsp_command_queue.put(cmd)
            self.current_write_command = None
            
    async def _process_write_resp(self):
        while True:
            cmd = await self.write_rsp_command_queue.get()
            r = await self.wr_rsp_channel.recv()
            self.log.info("r.wr_rsp_rd2rsp_loop: %r", int(r.wr_rsp_rd2rsp_loop))
            self.log.info("cmd.rd2rsp_loop: %r", cmd.rd2rsp_loop)
            assert int(r.wr_rsp_rd2rsp_loop) == cmd.rd2rsp_loop
            if cmd.has_rsp == True :
                await self.write_rsp_result_queue.put(r.wr_rsp_rd2rsp_loop)
                self.write_rsp_result_queue_sync.set()
            
    async def write_rsp_get(self, timeout=0):
        #while self.write_rsp_result_queue.empty():
        #    await Timer(4, 'ns')
        if timeout:
            self.write_rsp_result_queue_sync.clear()
            await First(self.write_rsp_result_queue_sync.wait(), Timer(timeout, "ns"))        
        return await self.write_rsp_result_queue.get()

class DmaMasterRead(Region, Reset):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=8192, max_pause_duration=8, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset

        self.log = logging.getLogger(f"cocotb.{bus.rd_req._entity._name}.{bus.rd_req._name}")

        self.rd_req_channel = DmaRdReqSource(bus.rd_req, clock, reset, reset_active_level, max_pause_duration)
        self.rd_req_channel.queue_occupancy_limit = 2
        if bus.has_sav == None:
            self.rd_rsp_channel = DmaRdRspSink(bus.rd_rsp, clock, reset, reset_active_level, max_pause_duration)
        else :
            self.rd_rsp_channel = DmaRdRspSinkSav(bus.rd_rsp, clock, reset, reset_active_level, max_pause_duration)
        self.rd_rsp_channel.queue_occupancy_limit = 2

        self.read_command_queue = Queue(maxsize=8)
        self.read_command_queue.queue_occupancy_limit = 2
        self.current_read_command = None

        self.read_rsp_command_queue = Queue(maxsize=8)
        self.read_rsp_command_queue.queue_occupancy_limit = 2

        self.read_rsp_result_queue_sync = Event()

        self.read_rsp_result_queue = Queue(maxsize=8)


        self.in_flight_operations = 0
        self._idle = Event()
        self._idle.set()

        self.address_width = 64
        self.width = len(self.rd_rsp_channel.bus.rd_rsp_data)
        self.byte_size = 8
        self.byte_lanes = self.width // self.byte_size
        self.max_burst_size = max(min(max_burst_size, 8192), 1)
        super().__init__(2**self.address_width, **kwargs)

        self.log.info("tlp adap DMA mem configuration:")
        self.log.info("  Address width: %d bits", self.address_width)
        self.log.info("  Byte size: %d bits", self.byte_size)
        self.log.info("  Data width: %d bits (%d bytes)", self.width, self.byte_lanes)
        self.log.info("  Max burst size: %d bytes", self.max_burst_size)

        assert self.byte_lanes * self.byte_size == self.width
        self._process_read_cr = None
        self._process_read_resp_cr = None

        self._init_reset(reset, reset_active_level)

    def set_idle_generator(self, generator=None):
        if generator:
            self.rd_req_channel.set_pause_generator(generator())
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.rd_rsp_channel.set_pause_generator(generator())


    def idle(self):
        return not self.in_flight_operations

    async def wait(self):
        while not self.idle():
            await self._idle.wait()

    async def read(self, address, length, sty, rd2rsp_loop, bdf=0, vf_active=0):
        if address < 0 or address >= 2**self.address_width:
            raise ValueError("Address out of range")
        if length < 0:
            raise ValueError("Read length must be positive")
            
        event = Event()

        self.in_flight_operations += 1
        self._idle.clear()

        cmd = DmaReadReq(address, length, sty, bdf, vf_active, rd2rsp_loop, event)
        await self.read_command_queue.put(cmd)
        await event.wait()
        return event.data

    async def read_nb_req(self, address, length, sty=0, rd2rsp_loop=0, bdf=0, vf_active=0):
        if address < 0 or address >= 2**self.address_width:
            raise ValueError("Address out of range")
        if length < 0:
            raise ValueError("Read length must be positive")
        self.in_flight_operations += 1

        self._idle.clear()
        cmd = DmaReadReq(address, length, sty, bdf, vf_active, rd2rsp_loop, None)
        await self.read_command_queue.put(cmd)


    async def read_rsp_get(self, timeout=0):
        #while self.read_rsp_result_queue.empty():
        #    await Timer(4, 'ns')
        if timeout:
            self.read_rsp_result_queue_sync.clear()
            await First(self.read_rsp_result_queue_sync.wait(), Timer(timeout, "ns")) 
        return await self.read_rsp_result_queue.get()
        

    def _handle_reset(self, state):
        if state:
            self.log.info("Reset asserted")
            if self._process_read_cr is not None:
                self._process_read_cr.kill()
                self._process_read_cr = None
            if self._process_read_resp_cr is not None:
                self._process_read_resp_cr.kill()
                self._process_read_resp_cr = None

            self.rd_req_channel.clear()
            self.rd_rsp_channel.clear()

            def flush_cmd(cmd):
                self.log.warning("Flushed read operation during reset: %s", cmd)
                if cmd.event:
                    cmd.event.set(None)

            while not self.read_command_queue.empty():
                cmd = self.read_command_queue.get_nowait()
                flush_cmd(cmd)

            if self.current_read_command:
                cmd = self.current_read_command
                self.current_read_command = None
                flush_cmd(cmd)

            while not self.read_rsp_command_queue.empty():
                cmd = self.read_rsp_command_queue.get_nowait()
                flush_cmd(cmd)

            self.in_flight_operations = 0
            self._idle.set()
        else:
            self.log.info("Reset de-asserted")
            if self._process_read_cr is None:
                self._process_read_cr = cocotb.start_soon(self._process_read())
            if self._process_read_resp_cr is None:
                self._process_read_resp_cr = cocotb.start_soon(self._process_read_resp())

    async def _process_read(self):
        while True:
            cmd = await self.read_command_queue.get()
            self.current_read_command = cmd
            req = self.rd_req_channel._transaction_obj()
            req.rd_req_sty = cmd.sty
            req.rd_req_desc = Desc(pcie_addr=cmd.address, pcie_length=cmd.length, rd2rsp_loop=cmd.rd2rsp_loop, vf_active=cmd.vf_active, bdf=cmd.bdf).pack()
            await self.rd_req_channel.send(req)
            await self.read_rsp_command_queue.put(cmd)
            self.current_read_command = None
            

    async def _process_read_resp(self):
        while True:
            cmd = await self.read_rsp_command_queue.get() 
            length = cmd.length
            self.log.info("length {}".format(length))
            sty = cmd.sty
            self.log.info("sty {}".format(sty))
            self.log.info("self.byte_lanes {}".format(self.byte_lanes))
            cycles = (sty + length + self.byte_lanes - 1)//self.byte_lanes
            self.log.info("cycles {}".format(cycles))
            mty = (self.byte_lanes - (length + sty)) % self.byte_lanes
            err = 0
            data = b''
            for i in range(cycles):      
                r = await self.rd_rsp_channel.recv()
                desc = Desc().unpack(r.rd_rsp_desc)
                if(i == 0):
                    assert sty == r.rd_rsp_sty
                    assert r.rd_rsp_sop == 1
                if(i == cycles-1):
                    assert r.rd_rsp_eop == 1
                    assert mty == r.rd_rsp_mty
                if (cmd.rd2rsp_loop != desc.rd2rsp_loop):
                    self.log.info("cmd.rd2rsp_loop {}".format(cmd.rd2rsp_loop))
                    self.log.info("desc.rd2rsp_loop {}".format(desc.rd2rsp_loop))
                assert cmd.rd2rsp_loop == desc.rd2rsp_loop
                err = r.rd_rsp_err
                
                if "x" not in str(r.rd_rsp_data):
                    cur_sty = sty if i == 0 else 0
                    cur_mty = mty if i == cycles-1 else 0
                    data = data + r.rd_rsp_data.value.to_bytes(self.byte_lanes, 'little')[cur_sty:self.byte_lanes-cur_mty]
                else:
                    cur_sty = sty if i == 0 else 0
                    cur_mty = mty if i == cycles-1 else 0
                    tmp = b'\X00'*self.byte_lanes
                    data = data + tmp[sty:self.byte_lanes-mty]
                
            result =  DmaReadRSP(data, cmd.bdf, sty, cmd.rd2rsp_loop, err, None)
            await self.read_rsp_result_queue.put(result)
            self.read_rsp_result_queue_sync.set()
            self.in_flight_operations -= 1

class DmaMaster(Region):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_len=4096, max_pause_duration=8, **kwargs):
        self.write_if = None
        self.read_if = None

        self.write_if = DmaMasterWrite(bus.write, clock, reset, reset_active_level, max_burst_len, max_pause_duration, **kwargs)
        self.read_if = DmaMasterRead(bus.read, clock, reset, reset_active_level, max_burst_len, max_pause_duration, **kwargs)

        super().__init__(max(self.write_if.size, self.read_if.size), **kwargs)

    def set_idle_generator(self, generator=None):
        if generator:
            self.write_if.set_idle_generator(generator)
            self.read_if.set_idle_generator(generator)
    
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.write_if.set_backpressure_generator(generator)
            self.read_if.set_backpressure_generator(generator)

    async def read_nb_req(self, address, length, sty=0, rd2rsp_loop=0, bdf=0, vf_active=0):
        return await self.read_if.read_nb_req(address, length, sty, rd2rsp_loop, bdf, vf_active)

    async def read_rsp_get(self, timeout=0):
        return await self.read_if.read_rsp_get()

    async def write_nb_req(self, address, data, sty=0, rd2rsp_loop=0, bdf=0, dev_id=0,vf_active=0, has_rsp=None):
        return await self.write_if.write_nb_req(address, data, sty, rd2rsp_loop, bdf, dev_id,vf_active, has_rsp)

    async def write_rsp_get(self, timeout=0):
        return await self.write_if.write_rsp_get(timeout)