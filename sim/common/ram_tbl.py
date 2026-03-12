#!/usr/bin/env python3
################################################################################
#  文件名称 : ram_tbl.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/04
#  功能描述 :
#
#  修改记录 :
#
#  版本号  日期       修改人       修改内容
#  v1.0  12/04     Joe Jiang   初始化版本
#  v1.1  26/01/21    Liuch      添加了函数返回的类型定义.便于对应的函数方法索引,并消除pylance检测报错
################################################################################
import logging
from typing import Tuple, Type, Optional, List

import cocotb
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, Event, First, Timer
from cocotb_bus.bus import Bus

from reset import Reset


class RamTblBus(Bus):

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


class RamTblTransaction:

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


class RamTblPause:
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

    def set_idle_generator(self, generator=None):
        if generator:
            self.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.set_pause_generator(generator())

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


class RamTblMaster(Reset):
    _signals = ["data", "vld"]
    _optional_signals = []

    _rd_req_vld_signal = "rd_req_vld"
    _rd_req_vld_init = 0

    _rd_req_rdy_signal = "rd_req_rdy"
    _rd_req_rdy_init = None

    _rd_rsp_vld_signal = "rd_rsp_vld"
    _rd_rsp_vld_init = None

    _wr_vld_signal = "wr_vld"
    _wr_vld_init = 0

    _wr_rdy_signal = "wr_rdy"
    _wr_rdy_init = None

    _rd_req_transaction_obj = RamTblTransaction
    _rd_req_bus_obj = RamTblBus
    _rd_rsp_transaction_obj = RamTblTransaction
    _rd_rsp_bus_obj = RamTblBus
    _wr_transaction_obj = RamTblTransaction
    _wr_bus_obj = RamTblBus

    def __init__(self, rd_req_bus, rd_rsp_bus, wr_bus, clock, reset=None, reset_active_level=True, *args, **kwargs):
        self.rd_req_bus = rd_req_bus
        self.rd_rsp_bus = rd_rsp_bus
        self.wr_bus = wr_bus
        self.clock = clock
        self.reset = reset
        # self.read_first = read_first
        self.log = logging.getLogger(f"cocotb.{rd_req_bus._entity._name}.{rd_req_bus._name}")
        self.log = logging.getLogger(f"cocotb.{rd_rsp_bus._entity._name}.{rd_rsp_bus._name}")

        super().__init__(*args, **kwargs)
        self.active = False

        self.rd_req_vld = None
        self.rd_req_rdy = None
        self.rd_rsp_vld = None

        self.wr_vld = None
        self.wr_rdy = None

        if self._rd_req_rdy_signal is not None and hasattr(self.rd_req_bus, self._rd_req_rdy_signal):
            self.rd_req_rdy = getattr(self.rd_req_bus, self._rd_req_rdy_signal)
            if self._rd_req_rdy_init is not None:
                self.rd_req_rdy.setimmediatevalue(self._rd_req_rdy_init)

        if self._rd_req_vld_signal is not None and hasattr(self.rd_req_bus, self._rd_req_vld_signal):
            self.rd_req_vld = getattr(self.rd_req_bus, self._rd_req_vld_signal)
            if self._rd_req_vld_init is not None:
                self.rd_req_vld.setimmediatevalue(self._rd_req_vld_init)

        if self._rd_rsp_vld_signal is not None and hasattr(self.rd_rsp_bus, self._rd_rsp_vld_signal):
            self.rd_rsp_vld = getattr(self.rd_rsp_bus, self._rd_rsp_vld_signal)
            if self._rd_rsp_vld_init is not None:
                self.rd_rsp_vld.setimmediatevalue(self._rd_rsp_vld_init)

        if self.wr_bus != None:
            if self._wr_vld_signal is not None and hasattr(self.wr_bus, self._wr_vld_signal):
                self.wr_vld = getattr(self.wr_bus, self._wr_vld_signal)
                if self._wr_vld_init is not None:
                    self.wr_vld.setimmediatevalue(self._wr_vld_init)

        if self.wr_bus != None:
            if self._wr_rdy_signal is not None and hasattr(self.wr_bus, self._wr_rdy_signal):
                self.wr_rdy = getattr(self.wr_bus, self._wr_rdy_signal)
                if self._wr_rdy_init is not None:
                    self.wr_rdy.setimmediatevalue(self._wr_rdy_init)

        self._init_reset(reset, reset_active_level)

    async def read(self, rd_req_obj):
        clock_edge_event = RisingEdge(self.clock)
        has_rd_req_vld = self.rd_req_vld is not None
        has_rd_req_rdy = self.rd_req_rdy is not None
        has_rd_rsp_vld = self.rd_rsp_vld is not None
        self.rd_req_bus.drive(rd_req_obj)
        if has_rd_req_vld:
            self.rd_req_vld.value = True
        await clock_edge_event
        while not (not has_rd_req_rdy or (self.rd_req_vld.value and self.rd_req_rdy.value)):
            await clock_edge_event
        self.rd_req_vld.value = False
        while not (not has_rd_rsp_vld or self.rd_rsp_vld.value):
            await clock_edge_event
        rd_rsp_obj = self._rd_rsp_transaction_obj()
        self.rd_rsp_bus.sample(rd_rsp_obj)
        return rd_rsp_obj

    async def write(self, wr_obj):
        has_wr_vld = self.wr_vld is not None
        has_wr_rdy = self.wr_rdy is not None
        clock_edge_event = RisingEdge(self.clock)
        self.wr_bus.drive(wr_obj)
        if has_wr_vld:
            self.wr_vld.value = True
        await clock_edge_event
        while not (not has_wr_rdy or (self.wr_vld.value and self.wr_rdy.value)):
            await clock_edge_event
        if has_wr_vld:
            self.wr_vld.value = False
        return


class RamTblSlaver(RamTblPause, Reset):
    _signals = ["data", "vld"]
    _optional_signals = []

    _rd_req_vld_signal = "rd_req_vld"
    _rd_req_vld_init = None

    _rd_req_rdy_signal = "rd_req_rdy"
    _rd_req_rdy_init = None

    _rd_rsp_vld_signal = "rd_rsp_vld"
    _rd_rsp_vld_init = 0

    _wr_vld_signal = "wr_vld"
    _wr_vld_init = None

    _wr_rdy_signal = "wr_rdy"
    _wr_rdy_init = 1

    _rd_req_transaction_obj = RamTblTransaction
    _rd_req_bus_obj = RamTblBus
    _rd_rsp_transaction_obj = RamTblTransaction
    _rd_rsp_bus_obj = RamTblBus
    _wr_transaction_obj = RamTblTransaction
    _wr_bus_obj = RamTblBus

    def __init__(self, rd_req_bus, rd_rsp_bus, wr_bus, clock, reset=None, reset_active_level=True, ready_latency=1, read_first=True, callback=None, *args, **kwargs):
        self.rd_req_bus = rd_req_bus
        self.rd_rsp_bus = rd_rsp_bus
        self.wr_bus = wr_bus
        self.clock = clock
        self.reset = reset
        self.read_first = read_first
        if rd_req_bus != None:
            self.log = logging.getLogger(f"cocotb.{rd_req_bus._entity._name}.{rd_req_bus._name}")
            self.log = logging.getLogger(f"cocotb.{rd_rsp_bus._entity._name}.{rd_rsp_bus._name}")
        if wr_bus != None:
            self.log = logging.getLogger(f"cocotb.{wr_bus._entity._name}.{wr_bus._name}")

        self.ready_latency = ready_latency

        super().__init__(*args, **kwargs)
        self.active = False

        self.callback = callback

        self.rd_req_vld = None
        self.rd_req_rdy = None
        self.rd_rsp_vld = None

        self.wr_vld = None
        self.wr_rdy = None

        if self._rd_req_rdy_signal is not None and hasattr(self.rd_req_bus, self._rd_req_rdy_signal):
            self.rd_req_rdy = getattr(self.rd_req_bus, self._rd_req_rdy_signal)
            if self._rd_req_rdy_init is not None:
                self.rd_req_rdy.setimmediatevalue(self._rd_req_rdy_init)

        if self._rd_req_vld_signal is not None and hasattr(self.rd_req_bus, self._rd_req_vld_signal):
            self.rd_req_vld = getattr(self.rd_req_bus, self._rd_req_vld_signal)
            if self._rd_req_vld_init is not None:
                self.rd_req_vld.setimmediatevalue(self._rd_req_vld_init)

        if self._rd_rsp_vld_signal is not None and hasattr(self.rd_rsp_bus, self._rd_rsp_vld_signal):
            self.rd_rsp_vld = getattr(self.rd_rsp_bus, self._rd_rsp_vld_signal)
            if self._rd_rsp_vld_init is not None:
                self.rd_rsp_vld.setimmediatevalue(self._rd_rsp_vld_init)

        if self.wr_bus != None:
            if self._wr_vld_signal is not None and hasattr(self.wr_bus, self._wr_vld_signal):
                self.wr_vld = getattr(self.wr_bus, self._wr_vld_signal)
                if self._wr_vld_init is not None:
                    self.wr_vld.setimmediatevalue(self._wr_vld_init)

        if self.wr_bus != None:
            if self._wr_rdy_signal is not None and hasattr(self.wr_bus, self._wr_rdy_signal):
                self.wr_rdy = getattr(self.wr_bus, self._wr_rdy_signal)
                if self._wr_rdy_init is not None:
                    self.wr_rdy.setimmediatevalue(self._wr_rdy_init)

        self._run_cr = None
        self._init_reset(reset, reset_active_level)

    def set_callback(self, callback):
        self.callback = callback

    def set_wr_callback(self, wr_callback):
        self.wr_callback = wr_callback

    def _handle_reset(self, state):
        if state:
            self.log.info("Reset asserted")
            if self._run_cr is not None:
                self._run_cr.kill()
                self._run_cr = None

            self.active = False
        else:
            self.log.info("Reset de-asserted")
            if self._run_cr is None:
                self._run_cr = cocotb.start_soon(self._run())

    async def _run(self):
        has_rd_req_vld = self.rd_req_vld is not None
        has_rd_req_rdy = self.rd_req_rdy is not None
        has_rd_rsp_vld = self.rd_rsp_vld is not None
        has_wr_vld = self.wr_vld is not None
        has_wr_rdy = self.wr_rdy is not None

        clock_edge_event = RisingEdge(self.clock)
        ready_delay = [None] * (self.ready_latency - 1)
        while True:
            pause_sample = bool(self.pause)
            await clock_edge_event
            rd_vld_sample = (not has_rd_req_vld or self.rd_req_vld.value) and (self.rd_req_bus is not None)
            rd_rdy_sample = not has_rd_req_rdy or self.rd_req_rdy.value

            wr_vld_sample = not has_wr_vld or self.wr_vld.value
            wr_rdy_sample = not has_wr_rdy or self.wr_rdy.value
            if self.wr_bus is not None:
                if not self.read_first:
                    if wr_vld_sample and wr_rdy_sample:
                        wr_obj = self._wr_transaction_obj()
                        self.wr_bus.sample(wr_obj)
                        if self.wr_callback is None:
                            raise ValueError("callback is None")
                        self.wr_callback(wr_obj)

            if rd_vld_sample and rd_rdy_sample:
                rd_req_obj = self._rd_req_transaction_obj()
                self.rd_req_bus.sample(rd_req_obj)
                if self.callback is None:
                    raise ValueError("callback is None")
                rd_rsp_obj = self.callback(rd_req_obj)

                ready_delay.append(rd_rsp_obj)
            else:
                ready_delay.append(None)

            if has_rd_req_rdy:
                paused = pause_sample
                self.rd_req_rdy.value = not paused

            if self.wr_bus is not None:
                if self.read_first:
                    if wr_vld_sample and wr_rdy_sample:
                        wr_obj = self._wr_transaction_obj()
                        self.wr_bus.sample(wr_obj)
                        if self.wr_callback is None:
                            raise ValueError("callback is None")
                        self.wr_callback(wr_obj)

            rd_rsp_obj = ready_delay.pop(0)
            if rd_rsp_obj is not None:
                self.rd_rsp_bus.drive(rd_rsp_obj)
                if has_rd_rsp_vld:
                    self.rd_rsp_vld.value = 1
                self.active = True
            else:
                if has_rd_rsp_vld:
                    self.rd_rsp_vld.value = 0
                self.active = False

    def idle(self):
        return not self.active


def define_ram_tbl(
    name, rd_req_signals=None, rd_rsp_signals=None, wr_signals=None, rd_req_vld_signal=None, rd_req_rdy_signal=None, rd_rsp_vld_signal=None, wr_vld_signal=None, wr_rdy_signal=None
) -> Tuple[
    Optional[Type[RamTblBus]],
    Optional[Type[RamTblBus]],
    Optional[Type[RamTblBus]],
    Optional[Type[RamTblTransaction]],
    Optional[Type[RamTblTransaction]],
    Optional[Type[RamTblTransaction]],
    Type[RamTblMaster],
    Type[RamTblSlaver],
]:
    if rd_req_signals is not None and rd_rsp_signals is not None:
        all_rd_req_signals = rd_req_signals.copy()
        if rd_req_vld_signal is None:
            for s in all_rd_req_signals:
                if s.lower().endswith('rd_req_vld'):
                    rd_req_vld_signal = s
        else:
            if rd_req_vld_signal not in all_rd_req_signals:
                rd_req_signals.append(rd_req_vld_signal)

        all_rd_req_signals = rd_req_signals.copy()
        if rd_req_rdy_signal is None:
            for s in all_rd_req_signals:
                if s.lower().endswith('rd_req_rdy'):
                    rd_req_rdy_signal = s
        else:
            if rd_req_rdy_signal not in all_rd_req_signals:
                rd_req_signals.append(rd_req_rdy_signal)

        all_rd_rsp_signals = rd_rsp_signals.copy()
        if rd_rsp_vld_signal is None:
            for s in all_rd_rsp_signals:
                if s.lower().endswith('rd_rsp_vld'):
                    rd_rsp_vld_signal = s
        else:
            if rd_rsp_vld_signal not in all_rd_rsp_signals:
                rd_rsp_signals.append(rd_rsp_vld_signal)

    if wr_signals is not None:
        all_wr_signals = wr_signals.copy()
        if wr_vld_signal is None:
            for s in all_wr_signals:
                if s.lower().endswith('wr_vld'):
                    wr_vld_signal = s
        else:
            if wr_vld_signal not in all_wr_signals:
                wr_signals.append(wr_vld_signal)

        all_wr_signals = wr_signals.copy()
        if wr_rdy_signal is None:
            for s in all_wr_signals:
                if s.lower().endswith('wr_rdy'):
                    wr_rdy_signal = s
        else:
            if wr_rdy_signal not in all_wr_signals:
                wr_signals.append(wr_rdy_signal)

    rd_req_attrib = {}
    rd_req_attrib['_signals'] = rd_req_signals
    rd_req_attrib['_optional_signals'] = []
    rd_req_bus = type(name + "RdReqBus", (RamTblBus,), rd_req_attrib) if rd_req_signals is not None else None

    rd_rsp_attrib = {}
    rd_rsp_attrib['_signals'] = rd_rsp_signals
    rd_rsp_attrib['_optional_signals'] = []
    rd_rsp_bus = type(name + "RdRspBus", (RamTblBus,), rd_rsp_attrib) if rd_rsp_signals is not None else None

    wr_attrib = {}
    wr_attrib['_signals'] = wr_signals
    wr_attrib['_optional_signals'] = []
    wr_bus = type(name + "WrBus", (RamTblBus,), wr_attrib) if wr_signals is not None else None

    rd_req_transaction = type(name + "RdReqTransaction", (RamTblTransaction,), rd_req_attrib) if rd_req_signals is not None else None
    rd_rsp_transaction = type(name + "RdRspTransaction", (RamTblTransaction,), rd_rsp_attrib) if rd_rsp_signals is not None else None
    wr_transaction = type(name + "WrTransaction", (RamTblTransaction,), wr_attrib) if wr_signals is not None else None
    attrib = {}
    attrib['_signals'] = (
        (rd_req_signals if rd_req_signals is not None else []) + (rd_rsp_signals if rd_rsp_signals is not None else []) + (wr_signals if wr_signals is not None else [])
    )
    attrib['_rd_req_vld_signal'] = rd_req_vld_signal
    attrib['_rd_req_rdy_signal'] = rd_req_rdy_signal
    attrib['_rd_rsp_vld_signal'] = rd_rsp_vld_signal
    attrib['_wr_vld_signal'] = wr_vld_signal
    attrib['_wr_rdy_signal'] = wr_rdy_signal
    attrib['_rd_req_transaction_obj'] = rd_req_transaction
    attrib['_rd_rsp_transaction_obj'] = rd_rsp_transaction
    attrib['_wr_transaction_obj'] = wr_transaction
    attrib['_rd_req_bus_obj'] = rd_req_bus
    attrib['_rd_rsp_bus_obj'] = rd_rsp_bus
    attrib['_wr_bus_obj'] = wr_bus

    ram_tbl_master = type(name + "RamTblMaster", (RamTblMaster,), attrib)
    ram_tbl_salver = type(name + "RamTblSlaver", (RamTblSlaver,), attrib)

    return rd_req_bus, rd_rsp_bus, wr_bus, rd_req_transaction, rd_rsp_transaction, wr_transaction, ram_tbl_master, ram_tbl_salver
