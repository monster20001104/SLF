import itertools
import logging
import os
import sys
import random
import cocotb_test.simulator

import cocotb
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory


sys.path.append('../common')
from stream_bus import define_stream
from enum import Enum, unique

NewChainNotifyBus, _, NewChainNotifySource, NewChainNotifySink, _ = define_stream("new_chain_notify",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NotifyReqBus, _, NotifyReqSource, NotifyReqSink, _ = define_stream("notify_req",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NotifyRspBus, _, NotifyRspSource, NotifyRspSink, _ = define_stream("notify_rsp",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

class Notify(Packet):
    name = 'notify_rsp'
    fields_desc = [
        BitField("qid",   0,  7),
        BitField("done",   0,  1),
        BitField("typ",   0,   4)
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
    @classmethod
    def unpack(cls, data):
        assert type(data) == cocotb.binary.BinaryValue
        return cls(data.buff)


class QueueBehavior():
    def __init__(self, max_local_bus_sz = 32, ring_size = 64):
        self._ring_size = ring_size
        self._ring = Queue(maxsize=self._ring_size)

    async def put_pkts(self, pkts):
        for pkt in pkts:
            await self._ring.put(pkt)

    def gen_pkts(self, npkt=None):
        pkts = []
        if npkt == None:
            npkt = random.randint(1, 4)
        for i in range(npkt):
            pkts.append((random.randint(1, 100), i == npkt-1))
        return pkts

    async def get_desc(self):
        descs = []
        if not self._ring.empty():
            eop = False
            while not eop:
                (pkt, eop) = await self._ring.get()
                descs.append(pkt)
        return descs
    
    def is_done(self):
        return self._ring.empty()

class BeqBehavior():
    def __init__(self, qsize = 1):
        self._new_chain_ff = Queue(maxsize=512)
        self._local_buf = Queue(maxsize=64)
        self._txq = [QueueBehavior() for _ in range(qsize)]
        self._typ = [ (1 << random.randint(0, 3)) for _ in range(qsize)]
        cocotb.start_soon(self._data_mover())

    def get_typ(self, qid):
        return self._typ[qid]

    async def put_pkts(self, qid, typ):
        _q =  self._txq[qid]
        pkts = _q.gen_pkts()
        await _q.put_pkts(pkts)
        await self._new_chain_ff.put((qid, typ))

    async def get_desc(self, qid):
        _q =  self._txq[qid]
        descs = await _q.get_desc()
        for desc in descs:
            await self._local_buf.put(desc)
        return _q.is_done()

    async def _data_mover(self):
        while True:
             pkt = await self._local_buf.get()
             await Timer(pkt, "ns")

    def is_done(self):
        done = True
        for _q in self._txq:
            done &= _q.is_done()
        return done


class TB(object):
    def __init__(self, dut, qsize=1):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.qsize = qsize
        self.beqbhv = BeqBehavior(self.qsize)

        self.newChainNotifyDrv = NewChainNotifySource(NewChainNotifyBus.from_prefix(dut, "new_chain_notify"), dut.clk, dut.rst)

        self.notifyReqMon = NotifyReqSink(NotifyReqBus.from_prefix(dut, "notify_req"), dut.clk, dut.rst)
        self.notifyReqMon.queue_occupancy_limit = 2

        self.notifyRspDrv = NotifyRspSource(NotifyRspBus.from_prefix(dut, "notify_rsp"), dut.clk, dut.rst)
        cocotb.start_soon(self._newChainThd())
        cocotb.start_soon(self._notifyReqThd())
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())


    async def cycle_reset(self):
        self.dut.emu_weight.value = 4
        self.dut.net_weight.value = 2
        self.dut.blk_weight.value = 2
        self.dut.sgdma_weight.value = 3
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    async def _newChainThd(self):
        while True:
            (qid, typ) = await self.beqbhv._new_chain_ff.get()
            notify = self.newChainNotifyDrv._transaction_obj()
            notify.dat = Notify(qid=qid, done=0, typ=typ).pack()
            await self.newChainNotifyDrv.send(notify)

    async def _notifyReqThd(self):
        while True:
            notifyReq = await self.notifyReqMon.recv()
            notify = Notify().unpack(notifyReq.dat)
            notify.done = await self.beqbhv.get_desc(notify.qid)
            assert self.beqbhv.get_typ(notify.qid) == notify.typ
            notifyRsp = self.notifyRspDrv._transaction_obj()
            notifyRsp.dat = notify.pack()
            await self.notifyRspDrv.send(notifyRsp)

    async def txq_thd(self, qsize, max_seq):
        for i in range(max_seq):
            print("seq:", i)
            qid = random.randint(0, self.qsize-1)
            await self.beqbhv.put_pkts(qid, self.beqbhv.get_typ(qid))
        while not self.beqbhv.is_done():
            await Timer(4, "ns")

    def set_idle_generator(self, generator=None):   
        if generator:
            self.newChainNotifyDrv.set_idle_generator(generator)
            self.notifyRspDrv.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.notifyReqMon.set_backpressure_generator(generator)

async def run_test(dut, idle_inserter, backpressure_inserter):
    qsize = 64
    max_seq = 10000
    tb = TB(dut, qsize=qsize)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()
    # waiting for init
    await Timer(1000, "ns")

    txq_cr = cocotb.start_soon(tb.txq_thd(qsize, max_seq))
    await txq_cr.join()

    await Timer(10000, "ns")
    tb.notifyReqMon.set_pause_generator(None)
    tb.notifyReqMon.pause = True
    await Timer(500, "ns")
    assert dut.u_beq_wrr_sch.qid_ff_usedw[0].value == 0
    assert dut.u_beq_wrr_sch.qid_ff_usedw[1].value == 0
    assert dut.u_beq_wrr_sch.qid_ff_usedw[2].value == 0
    assert dut.u_beq_wrr_sch.qid_ff_usedw[3].value == 0


def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()