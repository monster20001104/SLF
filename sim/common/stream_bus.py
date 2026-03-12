#!/usr/bin/env python3
################################################################################
#  文件名称 : stream_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/01
#  功能描述 :
#
#  修改记录 :
#
#  版本号  日期       修改人       修改内容
#  v1.0  08/01     Joe Jiang   初始化版本
#  v1.1  26/01/21    Liuch      添加了函数返回的类型定义.便于对应的函数方法索引,并消除pylance检测报错
################################################################################
import logging
from typing import Tuple, Type, Optional, List, Dict, Any

import cocotb
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, Event, First, Timer
from cocotb_bus.bus import Bus

from reset import Reset


class StreamBus(Bus):

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


class StreamTransaction:

    _signals = ["data"]

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


class StreamBase(Reset):

    _signals = ["data", "vld", "rdy"]
    _optional_signals = []

    _signal_widths = {"vld": 1, "rdy": 1}

    _init_x = False

    _vld_signal = "vld"
    _vld_init = None
    _rdy_signal = "rdy"
    _rdy_init = None

    _transaction_obj = StreamTransaction
    _bus_obj = StreamBus

    def __init__(self, bus, clock, reset=None, reset_active_level=True, *args, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset
        self.log = logging.getLogger(f"cocotb.{bus._entity._name}.{bus._name}")

        super().__init__(*args, **kwargs)

        self.active = False

        self.queue = Queue()
        self.dequeue_event = Event()
        self.idle_event = Event()
        self.idle_event.set()
        self.active_event = Event()
        self.wake_event = Event()

        self.rdy = None
        self.vld = None

        if self._rdy_signal is not None and hasattr(self.bus, self._rdy_signal):
            self.rdy = getattr(self.bus, self._rdy_signal)
            if self._rdy_init is not None:
                self.rdy.setimmediatevalue(self._rdy_init)

        if self._vld_signal is not None and hasattr(self.bus, self._vld_signal):
            self.vld = getattr(self.bus, self._vld_signal)
            if self._vld_init is not None:
                self.vld.setimmediatevalue(self._vld_init)

        for sig in self._signals + self._optional_signals:
            if hasattr(self.bus, sig):
                if sig in self._signal_widths:
                    assert len(getattr(self.bus, sig)) == self._signal_widths[sig]
                if self._init_x and sig not in (self._vld_signal, self._rdy_signal):
                    v = getattr(self.bus, sig).value
                    v.binstr = 'x' * len(v)
                    getattr(self.bus, sig).setimmediatevalue(v)

        self._run_cr = None

        self._init_reset(reset, reset_active_level)

    def count(self):
        return self.queue.qsize()

    def empty(self):
        return self.queue.empty()

    def clear(self):
        while not self.queue.empty():
            self.queue.get_nowait()
        self.dequeue_event.set()
        self.idle_event.set()
        self.active_event.clear()

    def _handle_reset(self, state):
        if state:
            self.log.info("Reset asserted")
            if self._run_cr is not None:
                self._run_cr.kill()
                self._run_cr = None

            self.active = False

            if self.queue.empty():
                self.idle_event.set()
        else:
            self.log.info("Reset de-asserted")
            if self._run_cr is None:
                self._run_cr = cocotb.start_soon(self._run())

    async def _run(self):
        raise NotImplementedError()


class StreamPause:
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        self._pause = False
        self._pause_generator = None
        self._pause_cr = None

    def _pause_update(self, val):
        pass

    @property
    def pause(self):
        return self._pause

    @pause.setter
    def pause(self, val):
        if self._pause != val:
            self._pause_update(val)
        self._pause = val

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
        if self._pause_generator is None:
            raise ValueError("self._pause_generator is None")
        for val in self._pause_generator:
            self.pause = val
            await clock_edge_event


class StreamDriver(StreamBase, StreamPause):

    _init_x = True

    _vld_init = 0
    _rdy_init = None

    def __init__(self, bus, clock, reset=None, reset_active_level=True, *args, **kwargs):
        super().__init__(bus, clock, reset, reset_active_level, *args, **kwargs)

        self.queue_occupancy_limit = -1

    def set_idle_generator(self, generator=None):
        if generator:
            self.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        pass

    async def send(self, obj):
        while self.full():
            self.dequeue_event.clear()
            await self.dequeue_event.wait()
        await self.queue.put(obj)
        self.idle_event.clear()
        self.active_event.set()

    def send_nowait(self, obj):
        if self.full():
            raise QueueFull()
        self.queue.put_nowait(obj)
        self.idle_event.clear()
        self.active_event.set()

    def full(self):
        if self.queue_occupancy_limit > 0 and self.count() >= self.queue_occupancy_limit:
            return True
        else:
            return False

    def idle(self):
        return self.empty() and not self.active

    async def wait(self):
        await self.idle_event.wait()

    def _handle_reset(self, state):
        super()._handle_reset(state)

        if state:
            if self.vld is not None:
                self.vld.value = 0

    async def _run(self):
        has_vld = self.vld is not None
        has_rdy = self.rdy is not None

        clock_edge_event = RisingEdge(self.clock)

        while True:
            await clock_edge_event

            # read handshake signals
            rdy_sample = not has_rdy or self.rdy.value
            vld_sample = not has_vld or self.vld.value

            if (rdy_sample and vld_sample) or (not vld_sample):
                if not self.queue.empty() and not self.pause:
                    self.bus.drive(self.queue.get_nowait())
                    self.dequeue_event.set()
                    if has_vld:
                        self.vld.value = 1
                    self.active = True
                else:
                    if has_vld:
                        self.vld.value = 0
                    self.active = not self.queue.empty()
                    if self.queue.empty():
                        self.idle_event.set()
                        self.active_event.clear()

                        await self.active_event.wait()


class StreamMonitor(StreamBase):

    _init_x = False

    _vld_init = None
    _rdy_init = None

    def __init__(self, bus, clock, reset=None, reset_active_level=True, *args, **kwargs):
        super().__init__(bus, clock, reset, reset_active_level, *args, **kwargs)

        if self.vld is not None:
            cocotb.start_soon(self._run_vld_monitor())
        if self.rdy is not None:
            cocotb.start_soon(self._run_rdy_monitor())

    def _dequeue(self, item):
        pass

    def _recv(self, item):
        if self.queue.empty():
            self.active_event.clear()
        self._dequeue(item)
        return item

    async def recv(self):
        item = await self.queue.get()
        return self._recv(item)

    def recv_nowait(self):
        item = self.queue.get_nowait()
        return self._recv(item)

    async def wait(self, timeout=0, timeout_unit=None):
        if not self.empty():
            return
        if timeout:
            if timeout_unit is None:
                await First(self.active_event.wait(), Timer(timeout))
            else:
                await First(self.active_event.wait(), Timer(timeout, timeout_unit))
        else:
            await self.active_event.wait()

    async def _run_vld_monitor(self):
        event = RisingEdge(self.vld)

        while True:
            await event
            self.wake_event.set()

    async def _run_rdy_monitor(self):
        event = RisingEdge(self.rdy)

        while True:
            await event
            self.wake_event.set()

    async def _run(self):
        has_vld = self.vld is not None
        has_rdy = self.rdy is not None

        clock_edge_event = RisingEdge(self.clock)

        wake_event = self.wake_event.wait()

        while True:
            await clock_edge_event

            # read handshake signals
            rdy_sample = not has_rdy or self.rdy.value
            vld_sample = not has_vld or self.vld.value

            if rdy_sample and vld_sample:
                obj = self._transaction_obj()
                self.bus.sample(obj)
                self.queue.put_nowait(obj)
                self.active_event.set()
            else:
                self.wake_event.clear()
                await wake_event


class StreamSink(StreamBase, StreamPause):

    _init_x = False

    _vld_init = None
    _rdy_init = 0

    def __init__(self, bus, clock, reset=None, reset_active_level=True, *args, **kwargs):
        super().__init__(bus, clock, reset, reset_active_level, *args, **kwargs)

        if self.vld is not None:
            cocotb.start_soon(self._run_vld_monitor())
        if self.rdy is not None:
            cocotb.start_soon(self._run_rdy_monitor())

        self.queue_occupancy_limit = -1

    def set_idle_generator(self, generator=None):
        pass

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.set_pause_generator(generator())

    def _recv(self, item):
        if self.queue.empty():
            self.active_event.clear()
        self._dequeue(item)
        return item

    async def recv(self):
        item = await self.queue.get()
        return self._recv(item)

    def recv_nowait(self):
        item = self.queue.get_nowait()
        return self._recv(item)

    async def wait(self, timeout=0, timeout_unit=None):
        if not self.empty():
            return
        if timeout:
            if timeout_unit is None:
                await First(self.active_event.wait(), Timer(timeout))
            else:
                await First(self.active_event.wait(), Timer(timeout, timeout_unit))
        else:
            await self.active_event.wait()

    async def _run_vld_monitor(self):
        event = RisingEdge(self.vld)

        while True:
            await event
            self.wake_event.set()

    async def _run_rdy_monitor(self):
        event = RisingEdge(self.rdy)

        while True:
            await event
            self.wake_event.set()

    def full(self):
        if self.queue_occupancy_limit > 0 and self.count() >= self.queue_occupancy_limit:
            return True
        else:
            return False

    def _handle_reset(self, state):
        super()._handle_reset(state)

        if state:
            if self.rdy is not None:
                self.rdy.value = 0

    def _pause_update(self, val):
        self.wake_event.set()

    def _dequeue(self, item):
        self.wake_event.set()

    async def _run(self):
        has_vld = self.vld is not None
        has_rdy = self.rdy is not None

        clock_edge_event = RisingEdge(self.clock)

        wake_event = self.wake_event.wait()

        while True:
            pause_sample = bool(self.pause)

            await clock_edge_event

            # read handshake signals
            rdy_sample = not has_rdy or self.rdy.value
            vld_sample = not has_vld or self.vld.value

            if rdy_sample and vld_sample:
                obj = self._transaction_obj()
                self.bus.sample(obj)
                try:
                    self.queue.put_nowait(obj)
                except:
                    print("{} {}".format(self.queue.maxsize, self.queue.qsize()))
                    print(self.bus._entity._name)
                    assert 0
                self.active_event.set()

            if has_rdy:
                paused = self.full() or pause_sample

                self.rdy.value = not paused

                if (not vld_sample or paused) and (pause_sample == bool(self.pause)):
                    self.wake_event.clear()
                    await wake_event
            else:
                if not vld_sample:
                    self.wake_event.clear()
                    await wake_event


def define_stream(
    name, signals, optional_signals=None, vld_signal=None, rdy_signal=None, signal_widths=None
) -> Tuple[Type[StreamBus], Type[StreamTransaction], Type[StreamDriver], Type[StreamSink], Type[StreamMonitor]]:
    all_signals = signals.copy()

    if optional_signals is None:
        optional_signals = []
    else:
        all_signals += optional_signals

    if vld_signal is None:
        for s in all_signals:
            if s.lower().endswith('vld'):
                vld_signal = s
    if vld_signal not in all_signals:
        signals.append(vld_signal)

    if rdy_signal is None:
        for s in all_signals:
            if s.lower().endswith('rdy'):
                rdy_signal = s
    else:
        if rdy_signal not in all_signals:
            signals.append(rdy_signal)

    if signal_widths is None:
        signal_widths = {}

    if vld_signal not in signal_widths:
        signal_widths[vld_signal] = 1

    if rdy_signal not in signal_widths:
        signal_widths[rdy_signal] = 1

    filtered_signals = []

    for s in all_signals:
        if s not in (rdy_signal, vld_signal):
            filtered_signals.append(s)

    attrib = {}
    attrib['_signals'] = signals
    attrib['_optional_signals'] = optional_signals
    bus = type(name + "Bus", (StreamBus,), attrib)

    attrib: Dict[str, Any] = {s: 0 for s in filtered_signals}
    attrib['_signals'] = filtered_signals

    transaction = type(name + "Transaction", (StreamTransaction,), attrib)

    attrib = {}
    attrib['_signals'] = signals
    attrib['_optional_signals'] = optional_signals
    attrib['_signal_widths'] = signal_widths
    attrib['_rdy_signal'] = rdy_signal
    attrib['_vld_signal'] = vld_signal
    attrib['_transaction_obj'] = transaction
    attrib['_bus_obj'] = bus

    Driver = type(name + "Driver", (StreamDriver,), attrib)
    sink = type(name + "Sink", (StreamSink,), attrib)
    monitor = type(name + "Monitor", (StreamMonitor,), attrib)

    return bus, transaction, Driver, sink, monitor
