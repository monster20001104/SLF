#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_data_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/09/25
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  09/25     Joe Jiang   初始化版本
################################################################################
import logging
from collections import Counter
from typing import List, NamedTuple, Union

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Event, First, Timer

import sys
sys.path.append('..')
from bus.beq_data_bus import BeqSink, BeqTxqSbd, BeqRxqSbd, BeqData
from reset import Reset

class BeqSlave(Reset):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=16384+64, max_pause_duration=8, is_txq=True, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset
        self.is_txq = is_txq
        self.log = logging.getLogger(f"cocotb.{bus._entity._name}.{bus._name}")
        
        self.chn = BeqSink(bus, clock, reset, reset_active_level, max_pause_duration)
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
        pass
    
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.chn.set_pause_generator(generator())

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

    def empty(self):
        return self.chn_queue.empty()

    def recv_nowait(self):
        pkt = self.chn_queue.get_nowait()
        self.in_flight_operations -= 1
        return pkt

    async def recv(self):
        pkt = await self.chn_queue.get()
        self.in_flight_operations -= 1
        return pkt

    async def _process(self):
        while True:
            data = b''
            eop = False
            sty = 0
            sbd = None
            while not eop:
                elemnt = await self.chn.recv()
                sbd = BeqTxqSbd().unpack(elemnt.sbd) if(self.is_txq) else BeqRxqSbd().unpack(elemnt.sbd)
                sop = elemnt.sop.value
                eop = elemnt.eop.value
                if sop and len(data) > 0:
                    raise ValueError("lost eop")
                if eop and not sop and len(data) == 0:
                    raise ValueError("lost sop")
                
                sty = elemnt.sty.value if sop else sty
                mty = elemnt.mty.value
                cur_sty = sty if sop else 0
                cur_mty = mty if eop else 0
                if "x" not in str(elemnt.data):
                    data = data + elemnt.data.value.to_bytes(self.byte_lanes, 'little')[cur_sty:self.byte_lanes-cur_mty]
                else:
                    tmp = b'\X00'*self.byte_lanes
                    data = data + tmp[sty:self.byte_lanes-mty]
            length = sbd.length
            qid = sbd.qid
            user0 = sbd.user0
            user1 = None if self.is_txq else sbd.user1
            if length != len(data):
                raise ValueError("len is missmatched(qid {} user0 {} user1 {})".format(qid, user0, user1))
            pkt = BeqData(qid, data, user0, user1, sty)
            self.in_flight_operations += 1
            await self.chn_queue.put(pkt)

class BeqTxqSlave(BeqSlave):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=16384+64, max_pause_duration=8, **kwargs):
        super().__init__(bus, clock, reset, reset_active_level, max_burst_size, max_pause_duration, is_txq=True, **kwargs)

class BeqRxqSlave(BeqSlave):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=16384+64, max_pause_duration=8, **kwargs):
        super().__init__(bus, clock, reset, reset_active_level, max_burst_size, max_pause_duration, is_txq=False, **kwargs)