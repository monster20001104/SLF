#!/usr/bin/env python3
################################################################################
#  文件名称 : tlp_adap_bypass_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/01/22
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  01/22     Joe Jiang   初始化版本
################################################################################
import logging
from collections import Counter
from typing import List, NamedTuple, Union

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Event, First, Timer

import sys
sys.path.append('..')
from bus.tlp_adap_bypass_bus import TlpBypassReqSource, TlpBypassRspSink, Header, OpCode, ComplStatus, TlpBypassReq, TlpBypassRsp

from address_space import Region
from reset import Reset

class TlpBypassMaster(Reset):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=4096, max_pause_duration=8, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset
        self.log = logging.getLogger(f"cocotb.{bus.req._entity._name}.{bus.req._name}")
        self.log = logging.getLogger(f"cocotb.{bus.rsp._entity._name}.{bus.rsp._name}")
        self.req_channel = TlpBypassReqSource(bus.req, clock, reset, reset_active_level, max_pause_duration)
        self.req_channel.queue_occupancy_limit = 2

        self.rsp_channel = TlpBypassRspSink(bus.rsp, clock, reset, reset_active_level)
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
            self.req_channel.set_pause_generator(generator())
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.rsp_channel.set_pause_generator(generator())


    def idle(self):
        return not self.in_flight_operations

    async def wait(self):
        while not self.idle():
            await self._idle.wait()

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
                cmd, _ = self.req_queue.get_nowait()
                flush_cmd(cmd)

            while not self.rsp_queue.empty():
                cmd, _ = self.rsp_queue.get_nowait()
                flush_cmd(cmd)

            if self.cur_req_cmd:
                cmd = self.cur_req_cmd
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

    async def recv_rsp(self):
        return await self.rsp_queue.get()

    async def send_req(self, req, gen):
        if req.addr < 0 or req.addr >= 2**self.address_width:
            raise ValueError("Address out of range")
        if isinstance(req.data, int):
            raise ValueError("Expected bytes or bytearray for data")
        if len(req.data) > self.max_burst_size + 8:
            raise ValueError("Responed burst size exceeds maximum burst size")
        self.in_flight_operations += 1
        self._idle.clear()
        await self.req_queue.put((req, gen))

    async def _process_rsp(self):
        while True:
            done = False
            data = b''
            tlp = None
            hdr = None
            gen = 0
            sop_hold = 0
            eop_hold = 0
            while not done:
                rsp = await self.rsp_channel.recv()
                gen = rsp.cpl_gen
                done = rsp.cpl_eop
                if sop_hold and rsp.cpl_sop:
                    raise ValueError("eop lost")
                if eop_hold and not rsp.cpl_sop:
                    raise ValueError("sop lost")
                if "x" not in str(rsp.cpl_data):
                    data = data + rsp.cpl_data.value.to_bytes(self.byte_lanes, 'little')
                else:
                    tmp = b'\x00'*self.byte_lanes
                    data = data + tmp
                if rsp.cpl_eop:
                    if "x" not in str(rsp.cpl_hdr):
                        hdr = Header().unpack(rsp.cpl_hdr)
                    else:
                        hdr = Header()
                    tlp = TlpBypassRsp(OpCode(hdr.op_code), hdr.addr, hdr.cpl_byte_count, hdr.byte_length, hdr.tag, hdr.cpl_id, hdr.req_id, ComplStatus(hdr.cpl_status), hdr.first_be, hdr.last_be, data, None)
                if len(data) > self.max_burst_size + 8:
                    ValueError("Requested burst size exceeds maximum burst size")
                if rsp.cpl_eop:
                    sop_hold = 0
                elif rsp.cpl_sop:
                    sop_hold = 1
                if rsp.cpl_sop and not rsp.cpl_eop:
                    eop_hold = 0
                elif rsp.cpl_eop:
                    eop_hold = 1
            await self.rsp_queue.put((tlp, gen))

    async def _process_req(self):
        while True:
            (cmd, gen) = await self.req_queue.get()
            self.cur_req_cmd = cmd
            data = cmd.data
            
            if cmd.op_code == OpCode.Cpl or cmd.op_code == OpCode.CFGWr0 or cmd.op_code == OpCode.CFGWr1 or cmd.op_code == OpCode.MRd or cmd.op_code == OpCode.CFGRd0 or cmd.op_code == OpCode.CFGRd1:
                cycles = 1
            else:
                cycles = (len(data) + self.byte_lanes - 1)//self.byte_lanes
            hdr = Header(op_code=cmd.op_code.value, addr=cmd.addr, byte_length=cmd.byte_length, tag=cmd.tag,  req_id=cmd.req_id,  first_be=cmd.first_be, last_be=cmd.last_be, dest_id=cmd.dest_id, ext_reg_num=cmd.ext_reg_num, reg_num=cmd.reg_num)
            for i in range(cycles):
                req = self.req_channel._transaction_obj()
                req.req_sop = i == 0
                req.req_eop = i == cycles-1
                req.req_hdr = hdr.pack()
                req.req_gen = gen
                if(len(data) < self.byte_lanes):
                    req.req_data = int.from_bytes(data, byteorder="little")
                else:
                    req.req_data = int.from_bytes(data[0:self.byte_lanes], byteorder="little")
                    data = data[self.byte_lanes:]
                await self.req_channel.send(req)
            self.cur_req_cmd = None