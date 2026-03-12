#!/usr/bin/env python3
################################################################################
#  文件名称 : tlp_adap_bypass_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/12
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/12     Joe Jiang   初始化版本
################################################################################
import logging
from collections import Counter
from typing import List, NamedTuple, Union

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Event, First, Timer

import sys
sys.path.append('..')
from bus.tlp_adap_bypass_bus import TlpBypassReqSink, TlpBypassRspSource, Header, OpCode, ComplStatus, TlpBypassReq, TlpBypassRsp

from address_space import Region
from reset import Reset

class TlpBypassSlave(Reset):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=4096, max_pause_duration=8, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset
        self.log = logging.getLogger(f"cocotb.{bus.req._entity._name}.{bus.req._name}")
        self.log = logging.getLogger(f"cocotb.{bus.rsp._entity._name}.{bus.rsp._name}")
        self.req_channel = TlpBypassReqSink(bus.req, clock, reset, reset_active_level, max_pause_duration)
        self.req_channel.queue_occupancy_limit = 2

        self.rsp_channel = TlpBypassRspSource(bus.rsp, clock, reset, reset_active_level)
        self.rsp_channel.queue_occupancy_limit = 2

        self.rsp_queue = Queue(maxsize=8)
        self.rsp_queue.queue_occupancy_limit = 2
        self.cur_req_cmd = None

        self.req_queue = Queue(maxsize=8)
        self.req_queue.queue_occupancy_limit = 2

        self.in_flight_operations = 0
        self._idle = Event()
        self._idle.set()

        self.address_width = 64
        self.width = len(self.req_channel.bus.req_data)
        self.byte_size = 8
        self.byte_lanes = self.width // self.byte_size
        self.max_burst_size = max(min(max_burst_size, 8192), 1)

        self.log.info("tlp adap bypass slaver configuration:")
        self.log.info("  Address width: %d bits", self.address_width)
        self.log.info("  Byte size: %d bits", self.byte_size)
        self.log.info("  Data width: %d bits (%d bytes)", self.width, self.byte_lanes)
        self.log.info("  Max burst size: %d bytes", self.max_burst_size)

        assert self.byte_lanes * self.byte_size == self.width

        self._process_req_cr = None
        self._process_rsp_cr = None

        self._init_reset(reset, reset_active_level)

    def set_idle_generator(self, generator=None):
        if generator:
            self.rsp_channel.set_pause_generator(generator())
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.req_channel.set_pause_generator(generator())


    def idle(self):
        return not self.in_flight_operations

    async def wait(self):
        while not self.idle():
            await self._idle.wait()

    async def recv_req(self):
        #while self.req_queue.empty():
        #    await Timer(4, 'ns')
        #return self.req_queue.get_nowait() 
        return await self.req_queue.get()

    async def send_rsp(self, rsp, gen):
        if rsp.addr < 0 or rsp.addr >= 2**self.address_width:
            raise ValueError("Address out of range")
        if isinstance(rsp.data, int):
            raise ValueError("Expected bytes or bytearray for data")
        if len(rsp.data) > self.max_burst_size + 8:
            raise ValueError("Responed burst size exceeds maximum burst size")
        self.in_flight_operations += 1
        self._idle.clear()
        await self.rsp_queue.put((rsp, gen))

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
            def flush_cmd(cmd):
                self.log.warning("Flushed write operation during reset: %s", cmd)
                if cmd.event:
                    cmd.event.set(None)
            while not self.req_queue.empty():
                cmd = self.req_queue.get_nowait()
                flush_cmd(cmd)

            while not self.rsp_queue.empty():
                cmd, _ = self.rsp_queue.get_nowait()
                flush_cmd(cmd)

            if self.cur_req_cmd:
                cmd, _ = self.cur_req_cmd
                self.cur_req_cmd = None
                flush_cmd(cmd)

            self.in_flight_operations = 0
            self._idle.set()
        else:
            self.log.info("Reset de-asserted")
            if self._process_req_cr is None:
                self._process_req_cr = cocotb.start_soon(self._process_req())
            if self._process_rsp_cr is None:
                self._process_rsp_cr = cocotb.start_soon(self._process_rsp())

    async def _process_req(self):
        while True:
            done = False
            data = b''
            tlp = None
            hdr = None
            gen = 0
            linkdown = 0
            while not done:
                req = await self.req_channel.recv()
                if hasattr(req, 'req_linkdown'):
                    linkdown = req.req_linkdown
                if linkdown:
                    break
                gen = req.req_gen
                done = req.req_eop
                if req.req_sop and len(data) != 0:
                    raise ValueError("sop lost")
                if "x" not in str(req.req_data):
                    data = data + req.req_data.value.to_bytes(self.byte_lanes, 'little')
                else:
                    tmp = b'\X00'*self.byte_lanes
                    data = data + tmp
                if req.req_eop:
                    if "x" not in str(req.req_hdr):
                        hdr = Header().unpack(req.req_hdr)
                    else:
                        hdr = Header()
                    tlp = TlpBypassReq(OpCode(hdr.op_code), hdr.addr, hdr.byte_length, hdr.tag, hdr.req_id, hdr.first_be, hdr.last_be, hdr.dest_id, hdr.ext_reg_num, hdr.reg_num, data, None)
                if len(data) > self.max_burst_size + 8:
                    ValueError("Requested burst size exceeds maximum burst size")
            if linkdown:
                continue
            await self.req_queue.put((tlp, gen))

    async def _process_rsp(self):
        while True:
            cmd, gen = await self.rsp_queue.get()
            self.cur_req_cmd = cmd
            data = cmd.data
            
            if cmd.op_code == OpCode.Cpl:
                cycles = 1
            else:
                cycles = (len(data) + self.byte_lanes - 1)//self.byte_lanes
            hdr = Header(op_code=cmd.op_code.value, addr=cmd.addr, byte_length=cmd.byte_length, tag=cmd.tag, cpl_id=cmd.cpl_id, req_id=cmd.req_id, cpl_status=cmd.cpl_status.value, cpl_byte_count=cmd.cpl_byte_count, first_be=cmd.first_be, last_be=cmd.last_be)#, dest_id=cmd.dest_id, ext_reg_num=cmd.ext_reg_num, reg_num=cmd.reg_num)
            for i in range(cycles):
                rsp = self.rsp_channel._transaction_obj()
                rsp.cpl_gen = gen
                rsp.cpl_sop = i == 0
                rsp.cpl_eop = i == cycles-1
                rsp.cpl_hdr = hdr.pack()
                if(len(data) < self.byte_lanes):
                    rsp.cpl_data = int.from_bytes(data, byteorder="little")
                else:
                    rsp.cpl_data = int.from_bytes(data[0:self.byte_lanes], byteorder="little")
                    data = data[self.byte_lanes:]
                await self.rsp_channel.send(rsp)
            self.cur_req_cmd = None