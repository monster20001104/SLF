#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : vio_nettx_data_bus.py
#* 作者名称 : matao
#* 创建日期 : 2025/05/29
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   05/29       matao       初始化版本
#******************************************************************************/
import random
import logging
from collections import Counter
from typing import List, NamedTuple, Union
from scapy.all import Packet, BitField

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Event, First, Timer
from backpressure_bus import define_backpressure
from stream_bus import define_stream

import sys
sys.path.append('..')
from reset import Reset

#TCP calc
TCPCsumCalcReqBus, TCPCsumCalcReqTransaction, TCPCsumCalcReqSource, TCPCsumCalcReqSink, TCPCsumCalcReqMonitor = define_stream("TCPCsumCalc_master",
    signals=["data", "info", "eop", "err"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None,
    signal_widths={"eop": 1, "err": 1}
)   
TCPCsumCalcRspBus, TCPCsumCalcRspTransaction, TCPCsumCalcRspSource, TCPCsumCalcRspSink, TCPCsumCalcRspMonitor = define_stream("TCPCsumCalc_slave",
    signals=["data", "info", "err"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None,
    signal_widths={"err": 1}
)   


class VirtioHeader(Packet):
    name = 'virtio_header'
    fields_desc = [
        BitField("num_buffers" ,   0,  16),
        BitField("csum_offset" ,   0,  16),
        BitField("csum_start"  ,   0,  16),
        BitField("gso_size"    ,   0,  16),
        BitField("hdr_len"     ,   0,  16),
        BitField("gso_type_ecn",   0,  5 ),
        BitField("gso_type"    ,   0,  3 ),
        BitField("flags_rsv"   ,   0,  7 ),
        BitField("flags"       ,   0,  1 )
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    def unpack(self, data):
        assert type(data) == cocotb.binary.BinaryValue
        return SgdmaHeader(data.buff)


class VionettxData(NamedTuple):
    qid: int
    data: bytes
    sty: int
    err: int ##vionettx err 0: no err, 1: err
    err_off: int ## Number of shots where the error occurred
    gen: int
    tso_en: int
    csum_en: int

VionettxBus, VionettxTransaction, VionettxSource, VionettxSink, VionettxMonitor = define_backpressure("VionettxBus",
    signals=["data", "sty", "mty", "sop", "eop", "qid", "length", "err", "gen", "tso_en", "csum_en"], 
    optional_signals=None,
    vld_signal = "vld",
    sav_signal = "sav",
    signal_widths={"sop": 1, "eop": 1, "err":1, "tso_en": 1, "csum_en":1}
)

class VionettxMaster(Reset):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=66560+64, max_pause_duration=8, is_txq=True, **kwargs):
        self.bus = bus
        self.clock = clock
        self.reset = reset
        self.is_txq = is_txq
        self.log = logging.getLogger(f"cocotb.{bus._entity._name}.{bus._name}")
        
        self.chn = VionettxSource(bus, clock, reset, reset_active_level, max_pause_duration)
        self.chn.queue_occupancy_limit = 2
        self.chn_queue = Queue(maxsize=8)
        self.chn_queue.queue_occupancy_limit = 2

        self._idle = Event()
        self._idle.set()
        self.in_flight_operations = 0

        self.width = len(self.chn.bus.data)
        self.byte_size = 8
        self.byte_lanes = self.width // self.byte_size
        self.max_burst_size = max(min(max_burst_size, 66560+64), 1)

        self.log.info("vionettx master configuration:")
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

    async def send(self, qid, data, sty=0, err=0, err_off=0, gen=0, tso_en=1, csum_en=1):
        if not isinstance(data, bytes):
            raise ValueError("Expected bytes or bytearray for data")
        if len(data) > self.max_burst_size:
            print(f"AAAA{len(data)}, {self.max_burst_size}")
            raise ValueError("Requested burst size exceeds maximum burst size")
        self.in_flight_operations += 1
        self._idle.clear()
        pkt = VionettxData(qid, data, sty, err, err_off, gen, tso_en, csum_en)
        await self.chn_queue.put(pkt)

    async def _process(self):
        while True:
            pkt = await self.chn_queue.get()
            data = pkt.data
            length = len(data)
            gen = pkt.gen
            tso_en = pkt.tso_en
            csum_en = pkt.csum_en
            qid = pkt.qid
            sty = pkt.sty
            mty = (self.byte_lanes - (length + sty)) % self.byte_lanes
            cycles = (sty + length + self.byte_lanes - 1)//self.byte_lanes
            for i in range(cycles):
                elemnt = self.chn._transaction_obj()
                elemnt.sty = sty if(i == 0) else 0
                elemnt.mty = mty if(i == cycles-1) else 0
                elemnt.sop = i == 0
                elemnt.eop = i == cycles-1
                elemnt.err = pkt.err if(i == pkt.err_off) else 0
                elemnt.qid = qid
                elemnt.length = length
                elemnt.gen = gen
                elemnt.tso_en = tso_en
                elemnt.csum_en = csum_en
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



class VionettxTxqMaster(VionettxMaster):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=66560+64, max_pause_duration=8, **kwargs):
        super().__init__(bus, clock, reset, reset_active_level, max_burst_size, max_pause_duration, is_txq=True, **kwargs)

class VionettxRxqMaster(VionettxMaster):
    def __init__(self, bus, clock, reset=None, reset_active_level=True, max_burst_size=66560+64, max_pause_duration=8, **kwargs):
        super().__init__(bus, clock, reset, reset_active_level, max_burst_size, max_pause_duration, is_txq=False, **kwargs)