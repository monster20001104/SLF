#!/usr/bin/env python3
################################################################################
#  文件名称 : interface.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/10/14
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  10/14     Joe Jiang   初始化版本
################################################################################

import logging
import struct

import cocotb
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, Timer, First, Event
from cocotb_bus.bus import Bus

from cocotbext.pcie.core.tlp import Tlp, TlpType
from cocotb.utils import get_sim_time

class BaseBus(Bus):

    _signals = ["data"]
    _optional_signals = []

    def __init__(self, entity=None, prefix=None, **kwargs):
        super().__init__(entity, prefix, self._signals, optional_signals=self._optional_signals, **kwargs)

    @classmethod
    def from_entity(cls, entity, **kwargs):
        return cls(entity, **kwargs)

    @classmethod
    def from_prefix(cls, entity, prefix, **kwargs):
        return cls(entity, prefix, **kwargs)


class A10TxBus(BaseBus):
    _signals = ["data", "sop", "eop", "valid", "ready", "err", "empty"]
    _optional_signals = ["parity", "vf_active"]


class A10RxBus(BaseBus):
    _signals = ["data", "empty", "sop", "eop", "valid", "ready", "bar_range"]
    _optional_signals = ["vf_active", "func_num", "vf_num", "parity"]


def qword_parity(d):
    lower_32 = d & 0xFFFFFFFF
    upper_32 = d >> 32
    lower_parity = dword_parity(lower_32)
    upper_parity = dword_parity(upper_32)
    return (upper_parity << 4) | lower_parity

def dword_parity(d):
    d ^= d >> 4
    d ^= d >> 2
    d ^= d >> 1
    p = d & 0x1
    if d & 0x100:
        p |= 0x2
    if d & 0x10000:
        p |= 0x4
    if d & 0x1000000:
        p |= 0x8
    return p

'''
def parity(d):
    d ^= d >> 4
    d ^= d >> 2
    d ^= d >> 1
    b = 0x1
    p = 0
    while d:
        if d & 0x1:
            p |= b
        d >>= 8
        b <<= 1
    return p
'''
def header_endian(hdr):
    ret = bytearray()
    for k in range(0, len(hdr), 4):
        ret.extend(hdr[k:k+4][::-1])
    return ret
class A10PcieFrame:
    def __init__(self, frame=None):
        self.data = []
        self.parity = []
        self.func_num = 0
        self.vf_num = None
        self.bar_range = 0
        self.err = 0

        if isinstance(frame, Tlp):
            '''
            hdr = frame.pack_header()
            for k in range(0, len(hdr), 4):
                self.data.extend(struct.unpack_from('>L', hdr, k))
            print(hdr)
            data = frame.get_data()
            for k in range(0, len(data), 4):
                self.data.extend(struct.unpack_from('<L', data, k))
            print(data)
            '''
            hdr = frame.pack_header()
            data = frame.get_data()
            if (frame.register_number % 2 != 0 and (frame.fmt_type in {TlpType.CFG_WRITE_0, TlpType.CFG_WRITE_1}) ) or (frame.address % 8 != 0 and (frame.fmt_type in {TlpType.MEM_WRITE, TlpType.MEM_WRITE_64})) or ((frame.lower_address&~3) % 8 != 0  and (frame.fmt_type in {TlpType.CPL_DATA, TlpType.CPL_LOCKED_DATA})):
                #addr not alinment and hdr alinment
                if len(hdr) % 8 == 0:
                    payload = header_endian(hdr)
                    payload.extend([0,0,0,0])
                    payload.extend(data)
                #addr not alinment and hdr not alinment
                else:
                    payload = header_endian(hdr)
                    payload.extend(data)
            else:
                #addr alinment and hdr alinment
                if len(hdr) % 8 == 0:
                    payload = header_endian(hdr)
                    payload.extend(data)
                #addr alinment and hdr not alinment
                else:
                    payload = header_endian(hdr)
                    payload.extend([0,0,0,0])
                    payload.extend(data)
            if len(payload) % 8 != 0:
                        payload.extend([0,0,0,0])
            

            for k in range(0, len(payload), 8):
                self.data.extend(struct.unpack_from('<Q', payload, k))

            
            self.update_parity()

        elif isinstance(frame, A10PcieFrame):
            self.data = list(frame.data)
            self.parity = list(frame.parity)
            self.func_num = frame.func_num
            self.vf_num = frame.vf_num
            self.bar_range = frame.bar_range
            self.err = frame.err

    @classmethod
    def from_tlp(cls, tlp):
        return cls(tlp)

    def to_tlp(self):
        hdr = bytearray()
        for dw in self.data[:5]:
            hdr.extend(struct.pack('>L', dw))
        tlp = Tlp.unpack_header(hdr)
        data_offset = 0
        if (tlp.address % 8 != 0 and (tlp.fmt_type in {TlpType.MEM_WRITE, TlpType.MEM_WRITE_64})) or ((tlp.lower_address&~3) % 8 != 0  and (tlp.fmt_type in {TlpType.CPL_DATA, TlpType.CPL_LOCKED_DATA})):
            if tlp.get_header_size_dw() == 4:
                data_offset = tlp.get_header_size_dw() + 1
            else:
                data_offset = tlp.get_header_size_dw()
        else:
            if tlp.get_header_size_dw() == 4:
                data_offset = tlp.get_header_size_dw()
            else:
                data_offset = tlp.get_header_size_dw() + 1
        
        for dw in self.data[data_offset:data_offset+tlp.length]:
            tlp.data.extend(struct.pack('<L', dw))        
        return tlp

    def update_parity(self):
        self.parity = [dword_parity(d) ^ 0xff for d in self.data]

    def check_parity(self):
        return (
            self.parity == [dword_parity(d) ^ 0xff for d in self.data]
        )

    def __eq__(self, other):
        if isinstance(other, A10PcieFrame):
            return (
                self.data == other.data and
                self.parity == other.parity and
                self.func_num == other.func_num and
                self.vf_num == other.vf_num and
                self.bar_range == other.bar_range and
                self.err == other.err
            )
        return False

    def __repr__(self):
        return (
            f"{type(self).__name__}(data=[{', '.join(f'{x:#010x}' for x in self.data)}], "
            f"parity=[{', '.join(hex(x) for x in self.parity)}], "
            f"func_num={self.func_num}, "
            f"vf_num={self.vf_num}, "
            f"bar_range={self.bar_range}, "
            f"err={self.err})"
        )

    def __len__(self):
        return len(self.data)


class A10PcieTransaction:

    _signals = ["data", "empty", "sop", "eop", "valid", "err",
        "vf_active", "func_num", "vf_num", "bar_range", "parity"]

    def __init__(self, *args, **kwargs):
        for sig in self._signals:
            if sig in kwargs:
                setattr(self, sig, kwargs[sig])
                del kwargs[sig]
            else:
                setattr(self, sig, 0)

        super().__init__(*args, **kwargs)

    def __repr__(self):
        return f"{type(self).__name__}({', '.join(f'{s}={int(getattr(self, s))}' for s in self._signals)})"


class A10PcieBase:

    _signal_widths = {"ready": 1}

    _valid_signal = "valid"
    _ready_signal = "ready"

    _transaction_obj = A10PcieTransaction
    _frame_obj = A10PcieFrame

    def __init__(self, bus, clock, reset=None, ready_latency=0, *args, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset
        self.ready_latency = ready_latency
        self.log = logging.getLogger(f"cocotb.{bus._entity._name}.{bus._name}")

        super().__init__(*args, **kwargs)

        self.active = False
        self.queue = Queue(maxsize=8)
        self.dequeue_event = Event()
        self.idle_event = Event()
        self.idle_event.set()
        self.active_event = Event()

        self.pause = False
        self._pause_generator = None
        self._pause_cr = None

        self.queue_occupancy_bytes = 0
        self.queue_occupancy_frames = 0

        self.width = len(self.bus.data)
        self.byte_size = 64
        self.byte_lanes = self.width // self.byte_size
        self.byte_mask = 2**self.byte_size-1

        self.seg_count = len(self.bus.valid)
        self.seg_width = self.width // self.seg_count
        self.seg_mask = 2**self.seg_width-1
        self.seg_par_width = self.seg_width // 8
        self.seg_par_mask = 2**self.seg_par_width-1
        self.seg_byte_lanes = self.byte_lanes // self.seg_count
        self.seg_empty_width = (self.seg_byte_lanes-1).bit_length()
        self.seg_empty_mask = 2**self.seg_empty_width-1

        assert self.width in {256, 512}

        assert len(self.bus.data) == self.seg_count*self.seg_width
        assert len(self.bus.sop) == self.seg_count
        assert len(self.bus.eop) == self.seg_count
        assert len(self.bus.valid) == self.seg_count

        if hasattr(self.bus, "empty"):
            #print(len(self.bus.empty), self.seg_empty_width)
            assert len(self.bus.empty) == self.seg_count*self.seg_empty_width

        '''
        if hasattr(self.bus, "err"):
            assert len(self.bus.err) == self.seg_count
        if hasattr(self.bus, "bar_range"):
            assert len(self.bus.bar_range) == self.seg_count*3

        if hasattr(self.bus, "vf_active"):
            assert len(self.bus.vf_active) == self.seg_count
        if hasattr(self.bus, "func_num"):
            assert len(self.bus.func_num) == self.seg_count*2
        if hasattr(self.bus, "vf_num"):
            assert len(self.bus.vf_num) == self.seg_count*11

        if hasattr(self.bus, "parity"):
            assert len(self.bus.parity) == self.seg_count*self.seg_width//8
        '''

    def count(self):
        return self.queue.qsize()

    def empty(self):
        return self.queue.empty()

    def clear(self):
        while not self.queue.empty():
            self.queue.get_nowait()
        self.idle_event.set()
        self.active_event.clear()

    def idle(self):
        raise NotImplementedError()

    async def wait(self):
        raise NotImplementedError()

    def set_pause_generator(self, generator=None):
        if self._pause_cr is not None:
            self._pause_cr.kill()
            self._pause_cr = None

        self._pause_generator = generator

        if self._pause_generator is not None:
            self._pause_cr = cocotb.start_soon(self._run_pause())

    def clear_pause_generator(self):
        self.set_pause_generator(None)

    async def _run_pause(self):
        clock_edge_event = RisingEdge(self.clock)

        for val in self._pause_generator:
            self.pause = val
            await clock_edge_event


class A10PcieSource(A10PcieBase):

    _signal_widths = {"valid": 2, "ready": 1}

    _valid_signal = "valid"
    _ready_signal = "ready"

    _transaction_obj = A10PcieTransaction
    _frame_obj = A10PcieFrame

    def __init__(self, bus, clock, reset=None, ready_latency=0, *args, **kwargs):
        super().__init__(bus, clock, reset, ready_latency, *args, **kwargs)

        self.drive_obj = None
        self.drive_sync = Event()

        self.delay_queue = Queue(maxsize=256)
        self.delay_queue.queue_occupancy_limit = 150

        self.queue_occupancy_limit_bytes = -1
        self.queue_occupancy_limit_frames = -1

        self.bus.data.setimmediatevalue(0)
        self.bus.sop.setimmediatevalue(0)
        self.bus.eop.setimmediatevalue(0)
        self.bus.valid.setimmediatevalue(0)

        if hasattr(self.bus, "empty"):
            self.bus.empty.setimmediatevalue(0)
        '''
        if hasattr(self.bus, "err"):
            self.bus.err.setimmediatevalue(0)
        if hasattr(self.bus, "bar_range"):
            self.bus.bar_range.setimmediatevalue(0)

        if hasattr(self.bus, "vf_active"):
            self.bus.vf_active.setimmediatevalue(0)
        if hasattr(self.bus, "func_num"):
            self.bus.func_num.setimmediatevalue(0)
        if hasattr(self.bus, "vf_num"):
            self.bus.vf_num.setimmediatevalue(0)

        if hasattr(self.bus, "parity"):
            self.bus.parity.setimmediatevalue(0)
        '''
        cocotb.start_soon(self.delay_thread())
        cocotb.start_soon(self._run_source())
        cocotb.start_soon(self._run())

    async def _drive(self, obj):
        if self.drive_obj is not None:
            self.drive_sync.clear()
            await self.drive_sync.wait()

        self.drive_obj = obj

    async def send(self, frame):
        while self.full():
            self.dequeue_event.clear()
            await self.dequeue_event.wait()
        frame = A10PcieFrame(frame)
        await self.delay_queue.put((frame, get_sim_time("ns")))
        #await self.queue.put(frame)
        #self.idle_event.clear()
        #self.queue_occupancy_bytes += len(frame)
        #self.queue_occupancy_frames += 1

    def send_nowait(self, frame):
        if self.full() or self.delay_queue.full():
            raise QueueFull()
        frame = A10PcieFrame(frame)
        self.delay_queue.put_nowait((frame, get_sim_time("ns")))
        #self.queue.put_nowait(frame)
        #self.idle_event.clear()
        #self.queue_occupancy_bytes += len(frame)
        #self.queue_occupancy_frames += 1

    async def delay_thread(self):
        while True:
            (frame, sim_time_start) = await self.delay_queue.get()
            sim_time_ns = get_sim_time("ns") - sim_time_start
            #e2e sim pcie delay
            if sim_time_ns < 598: 
                await Timer(int(600 - sim_time_ns), 'ns')
            await self.queue.put(frame)
            self.idle_event.clear()
            self.queue_occupancy_bytes += len(frame)
            self.queue_occupancy_frames += 1

    def full(self):
        if self.queue_occupancy_limit_bytes > 0 and self.queue_occupancy_bytes > self.queue_occupancy_limit_bytes:
            return True
        elif self.queue_occupancy_limit_frames > 0 and self.queue_occupancy_frames > self.queue_occupancy_limit_frames:
            return True
        else:
            return False

    def idle(self):
        return self.empty() and not self.active

    async def wait(self):
        await self.idle_event.wait()

    async def _run_source(self):
        self.active = False
        ready_delay = []

        clock_edge_event = RisingEdge(self.clock)

        while True:
            await clock_edge_event

            # read handshake signals
            ready_sample = self.bus.ready.value
            valid_sample = self.bus.valid.value

            if self.reset is not None and self.reset.value:
                self.active = False
                self.bus.valid.value = 0
                continue

            # ready delay
            if self.ready_latency > 1:
                if len(ready_delay) != (self.ready_latency-1):
                    ready_delay = [0]*(self.ready_latency-1)
                ready_delay.append(ready_sample)
                ready_sample = ready_delay.pop(0)
            if (ready_sample and valid_sample) or not valid_sample or self.ready_latency > 0:
                if self.drive_obj and not self.pause and (ready_sample or self.ready_latency == 0):
                    self.bus.drive(self.drive_obj)
                    self.drive_obj = None
                    self.drive_sync.set()
                    self.active = True
                else:
                    self.bus.valid.value = 0
                    self.active = bool(self.drive_obj)
                    if not self.drive_obj:
                        self.idle_event.set()

    async def _run(self):
        while True:
            frame = await self._get_frame()
            frame_offset = 0
            #self.log.debug("TX frame: %r", frame)
            first = True

            while frame is not None:
                transaction = self._transaction_obj()

                for seg in range(self.seg_count):
                    if frame is None:
                        if not self.empty():
                            frame = self._get_frame_nowait()
                            frame_offset = 0
                            #self.log.debug("TX frame: %r", frame)
                            first = True
                        else:
                            break

                    if first:
                        first = False

                        transaction.valid |= 1 << seg
                        transaction.sop |= 1 << seg

                    transaction.bar_range |= frame.bar_range << seg*3
                    transaction.func_num |= frame.func_num << seg*3
                    if frame.vf_num is not None:
                        transaction.vf_active |= 1 << seg
                        transaction.vf_num |= frame.vf_num << seg*11
                    transaction.err |= frame.err << seg

                    empty = 0
                    if frame.data:
                        transaction.valid |= 1 << seg

                        for k in range(min(self.seg_byte_lanes, len(frame.data)-frame_offset)):
                            transaction.data |= frame.data[frame_offset] << 64*(k+seg*self.seg_byte_lanes)
                            transaction.parity |= frame.parity[frame_offset] << 8*(k+seg*self.seg_byte_lanes)
                            empty = self.seg_byte_lanes-1-k
                            frame_offset += 1
                    if frame_offset >= len(frame.data):
                        transaction.eop |= 1 << seg
                        transaction.empty |= empty << seg*self.seg_empty_width

                        frame = None

                await self._drive(transaction)

    async def _get_frame(self):
        frame = await self.queue.get()
        self.dequeue_event.set()
        self.queue_occupancy_bytes -= len(frame)
        self.queue_occupancy_frames -= 1
        return frame

    def _get_frame_nowait(self):
        frame = self.queue.get_nowait()
        self.dequeue_event.set()
        self.queue_occupancy_bytes -= len(frame)
        self.queue_occupancy_frames -= 1
        return frame


class A10PcieSink(A10PcieBase):

    _signal_widths = {"valid": 2, "ready": 1}

    _valid_signal = "valid"
    _ready_signal = "ready"

    _transaction_obj = A10PcieTransaction
    _frame_obj = A10PcieFrame

    def __init__(self, bus, clock, reset=None, ready_latency=0, *args, **kwargs):
        super().__init__(bus, clock, reset, ready_latency, *args, **kwargs)

        self.sample_obj = None
        self.sample_sync = Event()

        self.queue_occupancy_limit_bytes = -1
        self.queue_occupancy_limit_frames = -1

        self.bus.ready.setimmediatevalue(0)

        cocotb.start_soon(self._run_sink())
        cocotb.start_soon(self._run())

    def _recv(self, frame):
        if self.queue.empty():
            self.active_event.clear()
        self.queue_occupancy_bytes -= len(frame)
        self.queue_occupancy_frames -= 1
        return frame

    async def recv(self):
        frame = await self.queue.get()
        return self._recv(frame)

    def recv_nowait(self):
        frame = self.queue.get_nowait()
        return self._recv(frame)

    def full(self):
        if self.queue_occupancy_limit_bytes > 0 and self.queue_occupancy_bytes > self.queue_occupancy_limit_bytes:
            return True
        elif self.queue_occupancy_limit_frames > 0 and self.queue_occupancy_frames > self.queue_occupancy_limit_frames:
            return True
        else:
            return False

    def idle(self):
        return not self.active

    async def wait(self, timeout=0, timeout_unit='ns'):
        if not self.empty():
            return
        if timeout:
            await First(self.active_event.wait(), Timer(timeout, timeout_unit))
        else:
            await self.active_event.wait()

    async def _run_sink(self):
        ready_delay = []

        clock_edge_event = RisingEdge(self.clock)

        while True:
            await clock_edge_event

            # read handshake signals
            ready_sample = self.bus.ready.value
            valid_sample = self.bus.valid.value

            if self.reset is not None and self.reset.value:
                self.bus.ready.value = 0
                continue

            # ready delay
            if self.ready_latency > 0:
                if len(ready_delay) != self.ready_latency:
                    ready_delay = [0]*self.ready_latency
                ready_delay.append(ready_sample)
                ready_sample = ready_delay.pop(0)

            #if valid_sample and ready_sample:
            if valid_sample :
                self.sample_obj = self._transaction_obj()
                self.bus.sample(self.sample_obj)
                self.sample_sync.set()
            elif self.ready_latency > 0:
                assert not valid_sample, "handshake error: valid asserted outside of ready cycle"

            self.bus.ready.value = (not self.full() and not self.pause)

    async def _run(self):
        self.active = False
        frame = None
        dword_count = 0

        while True:
            while not self.sample_obj:
                self.sample_sync.clear()
                await self.sample_sync.wait()

            self.active = True
            sample = self.sample_obj
            #self.log.debug("RX sample: %r", sample)
            self.sample_obj = None

            for seg in range(self.seg_count):
                #self.log.debug("seg: %r", seg)
                
                if not sample.valid & (1 << seg):
                    continue
                #self.log.debug("sample.sop: %r", sample.sop)
                if sample.sop & (1 << seg):
                    assert frame is None, "framing error: sop asserted in frame"
                    frame = A10PcieFrame()

                    hdr = (sample.data >> (seg*self.seg_width)) & self.seg_mask
                    #self.log.debug("hdr: %r", hdr)
                    fmt = (hdr >> 29) & 0b111

                    if fmt & 0b001:
                        dword_count = 4
                    else:
                        dword_count = 3

                    #if fmt & 0b010:
                    #    count = hdr & 0x3ff
                    #    if count == 0:
                    #        count = 1024
                    #    dword_count += count

                    #frame.bar_range = (sample.bar_range >> seg*3) & 0x7
                    #frame.func_num = (sample.func_num >> seg*3) & 0x7
                    #if sample.vf_active & (1 << seg):
                    #    frame.vf_num = (sample.vf_num >> seg*11) & 0x7ff
                    frame.err = (sample.err >> seg) & 0x1

                assert frame is not None, "framing error: data transferred outside of frame"

                #if dword_count > 0:
                data = (sample.data >> (seg*self.seg_width)) & self.seg_mask
                #self.log.debug("data: %r", data)
                parity = (sample.parity >> (seg*self.seg_par_width)) & self.seg_par_mask
                if sample.empty & (1 << seg):
                    data_range = 2
                else :
                    data_range = 4
                #self.log.debug("sample.empty & (1 << seg): %r", sample.empty & (1 << seg))
                #self.log.debug("data_range: %r", data_range)
                for k in range(data_range):
                    frame.data.append((data >> 32*k) & 0xffffffff)
                    frame.parity.append((parity >> 4*k) & 0xf)
                    #dword_count -= 1
                #self.log.debug("sample.eop: %r", sample.eop)
                #self.log.debug("1 << seg: %r",(1 << seg))
                #self.log.debug("sample.eop & (1 << seg): %r", sample.eop & (1 << seg))
                if sample.eop & (1 << seg):
                    #assert dword_count == 0, "framing error: incorrect length or early eop"
                    self.log.debug("RX frame: %r", frame)
                    self._sink_frame(frame)
                    self.active = False
                    frame = None

    def _sink_frame(self, frame):
        self.queue_occupancy_bytes += len(frame)
        self.queue_occupancy_frames += 1

        self.queue.put_nowait(frame)
        self.active_event.set()
