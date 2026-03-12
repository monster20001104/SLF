#!/usr/bin/env python3
################################################################################
#  文件名称 : tlp_adap_dma_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/09/25
#  功能描述 :
#
#  修改记录 :
#
#  版本号  日期       修改人       修改内容
#  v1.0  09/25     Joe Jiang   初始化版本
################################################################################
import math
import logging
from collections import Counter
from typing import List, NamedTuple, Union
import random
import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Event, First, Timer

import sys
sys.path.append('..')
from bus.tlp_adap_dma_bus import DmaWrReqSink, DmaWrRspSource, DmaRdReqSink, DmaRdRspSource, DmaWrRspSourceSav, DmaRdRspSourceSav ,Desc
from address_space import Region, Pool
from reset import Reset
from enum import Enum, unique

from cocotb.utils import get_sim_time

@unique
class DmaType(Enum):
    read = 0
    write = 1

class DmaReadReq(NamedTuple):
    sty: int
    desc: Desc


class DmaRam(Region, Reset):
    def __init__(self, wr_bus, rd_bus, clock, reset=None, reset_active_level=True, max_burst_size=4096, max_pause_duration=8, mem=None, order_queue=None, latency=1000, **kwargs):
        self.wr_bus = wr_bus
        self.rd_bus = rd_bus
        self.clock = clock
        self.reset = reset
        self._latency = latency
        if self.wr_bus != None:
            self.log = logging.getLogger(f"cocotb.{wr_bus.wr_req._entity._name}.{wr_bus.wr_req._name}")
            self.wr_req_channel = DmaWrReqSink(wr_bus.wr_req, clock, reset, reset_active_level, max_pause_duration)
            self.wr_req_channel.queue_occupancy_limit = 32

            if wr_bus.has_sav == None:
                self.wr_rsp_channel = DmaWrRspSource(wr_bus.wr_rsp, clock, reset, reset_active_level, max_pause_duration)
            else :
                self.wr_rsp_channel = DmaWrRspSourceSav(wr_bus.wr_rsp, clock, reset, reset_active_level, max_pause_duration)
            self.wr_rsp_channel.queue_occupancy_limit = 256

        if self.rd_bus != None:
            self.log = logging.getLogger(f"cocotb.{rd_bus.rd_req._entity._name}.{rd_bus.rd_req._name}")

            self.rd_req_channel = DmaRdReqSink(rd_bus.rd_req, clock, reset, reset_active_level, max_pause_duration)
            self.rd_req_channel.queue_occupancy_limit = 1

            if rd_bus.has_sav == None:
                self.rd_rsp_channel = DmaRdRspSource(rd_bus.rd_rsp, clock, reset, reset_active_level, max_pause_duration)
            else :
                self.rd_rsp_channel = DmaRdRspSourceSav(rd_bus.rd_rsp, clock, reset, reset_active_level, max_pause_duration)
            self.rd_rsp_channel.queue_occupancy_limit = 256

        self.rsp_queue_rd = Queue(maxsize=64)
        self.rsp_queue_rd.queue_occupancy_limit = 64

        self.rsp_queue_wr = Queue(maxsize=8)
        self.rsp_queue_wr.queue_occupancy_limit = 1

        self.in_flight_operations = 0
        self._idle = Event()
        self._idle.set()

        self._mem = mem
        self.dirty_log_cnt = 0
        self.address_width = 64

        self.width = len(self.wr_req_channel.bus.wr_req_data) if self.wr_bus != None else len(self.rd_rsp_channel.bus.rd_rsp_data)
        self.byte_size = 8
        self.byte_lanes = self.width // self.byte_size
        self.max_burst_size = max(min(max_burst_size, 8192), 1)
        super().__init__(2**self.address_width, **kwargs)

        self.log.info("tlp adap DMA slaver configuration:")
        self.log.info("  Address width: %d bits", self.address_width)
        self.log.info("  Byte size: %d bits", self.byte_size)
        self.log.info("  Data width: %d bits (%d bytes)", self.width, self.byte_lanes)
        self.log.info("  Max burst size: %d bytes", self.max_burst_size)

        assert self.byte_lanes * self.byte_size == self.width

        self._process_write_cr = None
        self._process_read_cr = None
        self._process_wr_resp_cr = None
        self._process_rd_resp_cr = None

        self._init_reset(reset, reset_active_level)
    def set_idle_generator(self, generator=None):
        if generator:
            if self.wr_bus != None:
                self.wr_rsp_channel.set_pause_generator(generator())
            if self.rd_bus != None:
                self.rd_rsp_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            if self.wr_bus != None:
                self.wr_req_channel.set_pause_generator(generator())
            if self.rd_bus != None:
                self.rd_req_channel.set_pause_generator(generator())

    def idle(self):
        return not self.in_flight_operations

    async def wait(self):
        while not self.idle():
            await self._idle.wait()

    def _handle_reset(self, state):
        if state:
            self.log.info("Reset asserted")
            if  self._process_write_cr is not None:
                self._process_write_cr.kill()
                self._process_write_cr = None
            if  self._process_read_cr is not None:
                self._process_read_cr.kill()
                self._process_read_cr = None
            if  self._process_wr_resp_cr is not None:
                self._process_wr_resp_cr.kill()
                self._process_wr_resp_cr = None
            if  self._process_rd_resp_cr is not None:
                self._process_rd_resp_cr.kill()
                self._process_rd_resp_cr = None

            if self.wr_bus is not None:
                self.wr_req_channel.clear()
                self.wr_rsp_channel.clear()
            if self.rd_bus is not  None:
                self.rd_req_channel.clear()
                self.rd_rsp_channel.clear()

            while not self.rsp_queue_rd.empty():
                cmd = self.rsp_queue_rd.get_nowait()

            while not self.rsp_queue_wr.empty():
                cmd = self.rsp_queue_wr.get_nowait()

            self.in_flight_operations = 0
            self._idle.set()
        else:
            self.log.info("Reset de-asserted")
            if self.wr_bus is not None:
                if self._process_write_cr is None:
                    self._process_write_cr = cocotb.start_soon(self._process_write())

            if self.rd_bus is not  None:
                if self._process_read_cr is None:
                    self._process_read_cr = cocotb.start_soon(self._process_read())

            if self._process_wr_resp_cr is None:
                self._process_wr_resp_cr = cocotb.start_soon(self._process_wr_resp())

            if self._process_rd_resp_cr is None:
                self._process_rd_resp_cr = cocotb.start_soon(self._process_rd_resp())

    async def _process_write(self):
        while True:
            eop = False
            data = b''
            sty = 0
            mty = 0
            desc = None
            while not eop:
                elemnt = await self.wr_req_channel.recv()
                desc = Desc().unpack(elemnt.wr_req_desc)

                sop = elemnt.wr_req_sop.value
                eop = elemnt.wr_req_eop.value
                if desc.pcie_length == 0 :
                    raise ValueError("dma wr req is illegal(len=0)")
                if sop and len(data) > 0:
                    raise ValueError("lost eop")
                if eop and not sop and len(data) == 0:
                    raise ValueError("lost sop")

                sty = elemnt.wr_req_sty.value if(sop) else sty
                mty = elemnt.wr_req_mty.value
                cur_sty = sty if sop else 0
                cur_mty = mty if eop else 0
                if "x" not in str(elemnt.wr_req_data):
                    data = data + elemnt.wr_req_data.value.to_bytes(self.byte_lanes, 'little')[cur_sty:self.byte_lanes-cur_mty]
                else:
                    tmp = b'\X00'*self.byte_lanes
                    data = data + tmp[sty:self.byte_lanes-mty]
                    raise ValueError("x in data")
            if len(data) != desc.pcie_length:
                raise ValueError("Malformed Packet")

            self.in_flight_operations += 1
            self._idle.clear()
            if type(self._mem) == Pool:
                if len(data) <= 512:
                    self.log.debug("write mem addr {} len {} data {}".format(hex(desc.pcie_addr), hex(len(data)), data.hex()))
                else:
                    self.log.debug("write mem addr {} len {} (data too large to print)".format(hex(desc.pcie_addr), hex(len(data))))
                await self._mem.write(desc.pcie_addr, data)
            else:
                self._mem.write(desc.pcie_addr, data, bdf=desc.bdf)
            #todo:check bdf

            await self.rsp_queue_wr.put((DmaType["write"], desc.rd2rsp_loop, desc.vf_active))
            # self.log.error(f"{self.write_cnt1} self.rsp_queue_wr.put time:{get_sim_time()} ")
            # self.write_cnt1+=1

    async def _process_read(self):
        while True:
            elemnt = await self.rd_req_channel.recv()
            desc = Desc().unpack(elemnt.rd_req_desc)
            if desc.pcie_length == 0 :
                raise ValueError("dma rd req is illegal(len=0)")
            sty = elemnt.rd_req_sty.value
            req = DmaReadReq(sty, desc)
            tim = get_sim_time("ns")
            await self.rsp_queue_rd.put(((DmaType["read"], req),tim))

    async def _process_wr_resp(self):
        while True:
            rsp_info = await self.rsp_queue_wr.get()
            if rsp_info[0] == DmaType["write"]:
                # self.log.error(f"{self.write_cnt2} self.rsp_queue_wr.get time:{get_sim_time()} ")
                # self.write_cnt2+=1
                rsp = self.wr_rsp_channel._transaction_obj()
                rsp.wr_rsp_rd2rsp_loop = rsp_info[1]
                if hasattr(rsp, 'wr_rsp_dirty_log'):
                    rsp.wr_rsp_dirty_log = rsp_info[2]
                    if rsp.wr_rsp_dirty_log == 1:
                        self.dirty_log_cnt = self.dirty_log_cnt + 1
                #if rsp.rd2rsp_loop == rd2rsp_loop:
                #    raise ValueError("mismatch rd2rsp_loop")
                await self.wr_rsp_channel.send(rsp)
                # self.log.error(f"{self.write_cnt3} self.wr_rsp_channel.send(rsp) time:{get_sim_time()} ")
                # self.write_cnt3+=1
                self.in_flight_operations -= 1



    # async def _process_resp(self):
    #     while True:
    #         rsp_info = await self.rsp_queue_wr.get()
    #         if rsp_info[0] == DmaType["write"]:
    #             self.log.error(f"{self.write_cnt2} self.rsp_queue_wr.get time:{get_sim_time()} ")
    #             self.write_cnt2+=1
    #             rsp = self.wr_rsp_channel._transaction_obj()
    #             rsp.wr_rsp_rd2rsp_loop = rsp_info[1]
    #             if hasattr(rsp, 'wr_rsp_dirty_log'):
    #                 rsp.wr_rsp_dirty_log = rsp_info[2]
    #                 if rsp.wr_rsp_dirty_log == 1:
    #                     self.dirty_log_cnt = self.dirty_log_cnt + 1
    #             #if rsp.rd2rsp_loop == rd2rsp_loop:
    #             #    raise ValueError("mismatch rd2rsp_loop")
    #             await self.wr_rsp_channel.send(rsp)
    #             self.log.error(f"{self.write_cnt3} self.wr_rsp_channel.send(rsp) time:{get_sim_time()} ")
    #             self.write_cnt3+=1
    #             self.in_flight_operations -= 1
    #         else:
    #             tim = get_sim_time("ns")
    #             # self.log.error(f"rsp_queue_rd.put tim : {tim}")
    #             await self.rsp_queue_rd.put((rsp_info,tim))


    async def _process_rd_resp(self):
        while True:
            (rsp_info, tim) = await self.rsp_queue_rd.get()
            latency = math.ceil(get_sim_time("ns") - tim)
            if latency < self._latency:
                await RisingEdge(self.clock)
                # await Timer(self._latency - latency + random.randint(1, self._latency//10), "ns")
                await Timer(self._latency - latency, "ns")
                #await RisingEdge(self.clock)

            if rsp_info[0] != DmaType["write"]:
                sty = rsp_info[1].sty
                desc = rsp_info[1].desc
                addr = desc.pcie_addr
                length = desc.pcie_length
                #todo:check bdf
                mty = (self.byte_lanes - (length + sty)) % self.byte_lanes
                cycles = (sty + length + self.byte_lanes - 1)//self.byte_lanes

                try:
                    data = await self._mem.read(addr, length, bdf=desc.bdf) if type(self._mem) == Pool else self._mem.read(addr, length, bdf=desc.bdf)
                except:
                    self.log.info("discover an injected fault(addr:{} len:{})".format(addr, length))
                    data = b'\x00'*length
                    rd_err = 1
                else:
                    rd_err = 0
                finally:
                    for i in range(cycles):
                        elemnt = self.rd_rsp_channel._transaction_obj()
                        elemnt.rd_rsp_desc = desc.pack()
                        elemnt.rd_rsp_sty = sty if(i == 0) else 0
                        elemnt.rd_rsp_mty = mty if(i == cycles-1) else 0
                        elemnt.rd_rsp_sop = i == 0
                        elemnt.rd_rsp_eop = i == cycles-1
                        elemnt.rd_rsp_err = rd_err
                        local_len = self.byte_lanes - elemnt.rd_rsp_sty - elemnt.rd_rsp_mty
                        tmp = bytes(random.getrandbits(8) for _ in range(elemnt.rd_rsp_sty))
                        tmp = tmp + data[0:local_len]
                        padding_size = self.byte_lanes - len(tmp)
                        if padding_size > 0:
                            tmp = tmp + bytes(random.getrandbits(8) for _ in range(padding_size))
                        data = data[local_len:]
                        elemnt.rd_rsp_data = int.from_bytes(tmp, byteorder="little")
                        await self.rd_rsp_channel.send(elemnt)
