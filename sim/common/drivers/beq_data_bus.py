#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_data_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/09/24
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  09/24     Joe Jiang   初始化版本
################################################################################
import random
import logging
from collections import Counter
from typing import List, NamedTuple, Union

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Event, First, Timer

import sys
sys.path.append('..')
from bus.beq_data_bus import BeqSource, BeqTxqSbd, BeqRxqSbd, BeqData
from reset import Reset

class BeqMaster(Reset):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=16384+64, max_pause_duration=8, is_txq=True, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset
        self.is_txq = is_txq
        self.log = logging.getLogger(f"cocotb.{bus._entity._name}.{bus._name}")
        
        self.chn = BeqSource(bus, clock, reset, reset_active_level, max_pause_duration)
        self.chn.queue_occupancy_limit = 2
        self.chn_queue = Queue(maxsize=8)
        self.chn_queue.queue_occupancy_limit = 2

        self._idle = Event()
        self._idle.set()
        self.in_flight_operations = 0

        self.width = len(self.chn.bus.data)
        self.byte_size = 8
        self.byte_lanes = self.width // self.byte_size
        self.max_burst_size = max(min(max_burst_size, 16384+64), 1)

        self.log.info("beq master configuration:")
        self.log.info("  Byte size: %d bits", self.byte_size)
        self.log.info("  Data width: %d bits (%d bytes)", self.width, self.byte_lanes)
        self.log.info("  Max burst size: %d bytes", self.max_burst_size)

        assert self.byte_lanes * self.byte_size == self.width
        self._process_cr = None
        self._init_reset(reset, reset_active_level)

    def set_idle_generator(self, generator=None):
        if generator:
            self.chn.set_pause_generator(generator())
    
    def set_backpressure_generator(self, generator=None):
        pass

    def idle(self):
        return not self.in_flight_operations

    async def wait(self):
        while not self.idle():
            await self._idle.wait()

    def _handle_reset(self, state):
        if state:
            self.log.info("Reset asserted")
            if self._process_cr is not None:
                self._process_cr.kill()
                self._process_cr = None

            self.chn.clear()

            while not self.chn_queue.empty():
                _d = self.chn_queue.get_nowait()

            self.in_flight_operations = 0
            self._idle.set()
        else:
            self.log.info("Reset de-asserted")
            if self._process_cr is None:
                self._process_cr = cocotb.start_soon(self._process())

    async def send(self, qid, data, user0, user1=None, sty=0):
        if not isinstance(data, bytes):
            raise ValueError("Expected bytes or bytearray for data")
        if len(data) > self.max_burst_size:
            raise ValueError("Requested burst size exceeds maximum burst size")
        self.in_flight_operations += 1
        self._idle.clear()
        pkt = BeqData(qid, data, user0, user1, sty)
        await self.chn_queue.put(pkt)

    async def _process(self):
        while True:
            pkt = await self.chn_queue.get()
            data = pkt.data
            length = len(data)
            qid = pkt.qid
            user0 = pkt.user0
            user1 = pkt.user1
            sbd = BeqTxqSbd(user0=user0, qid=qid, length=length) if self.is_txq else BeqRxqSbd(user1=user1, user0=user0, qid=qid, length=length)
            sty = pkt.sty
            mty = (self.byte_lanes - (length + sty)) % self.byte_lanes
            cycles = (sty + length + self.byte_lanes - 1)//self.byte_lanes
            for i in range(cycles):
                elemnt = self.chn._transaction_obj()
                elemnt.sbd = sbd.pack()
                elemnt.sty = sty if(i == 0) else 0
                elemnt.mty = mty if(i == cycles-1) else 0
                elemnt.sop = i == 0
                elemnt.eop = i == cycles-1
                local_len = self.byte_lanes - elemnt.sty - elemnt.mty
                tmp = bytes(random.getrandbits(8) for _ in range(elemnt.sty))
                tmp = tmp + data[0:local_len]
                padding_size = self.byte_lanes - len(tmp)
                if padding_size > 0:
                    tmp = tmp + bytes(random.getrandbits(8) for _ in range(padding_size))
                data = data[local_len:]
                elemnt.data = int.from_bytes(tmp, byteorder="little")
                await self.chn.send(elemnt)
            self.in_flight_operations -= 1



class BeqTxqMaster(BeqMaster):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=16384+64, max_pause_duration=8, **kwargs):
        super().__init__(bus, clock, reset, reset_active_level, max_burst_size, max_pause_duration, is_txq=True, **kwargs)

class BeqRxqMaster(BeqMaster):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=16384+64, max_pause_duration=8, **kwargs):
        super().__init__(bus, clock, reset, reset_active_level, max_burst_size, max_pause_duration, is_txq=False, **kwargs)