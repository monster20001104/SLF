import itertools
import logging
import os
import sys
import random
import math
from collections import deque
from functools import wraps

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.log import SimLog
from cocotb.clock import Clock
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event,Lock
from cocotb.regression import TestFactory
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
import time

class VirtqFlagBit:
    NEXT_BIT = 0x1
    WRITE_BIT = 0x2
    INDIRECT_BIT = 0x4

class InfoStatusBit:
    QSTOP_BIT = 0x10

class TestType:
    NETTX = 0x0
    NETRX = 0x1
    BLK = 0x2

class TestMode:
    ALL_CASE = 0x0
    CHOOSE_ONE = 0x1 

class VirtqPkt:
    def __init__(self, pktbase=None, pktlen=None):
        if pktbase is None:
            self.pktbase = random.randint(1, 2**63)
        else:
            self.pktbase = pktbase

        if pktlen is None:
            self.pktlen = random.randint(1, 65535)
        else:
            self.pktlen = pktlen


class VirtqDesc(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("next",            0,  16),
        BitField("flags",           0,  16),
        BitField("pktlen",          0,  32),
        BitField("addr",            0,  64),
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
        return cls(data)



class VirtqDescChain:
    def __init__(self, virtqPkt, mtu=1500, random_mtu=False, extra_flags=0, allowLongChain=False, oneDesc=False, needHdr=False):
        self.mtu = mtu
        self.random_mtu = random_mtu
        self.descs = deque()

        chainLen = 0
        left_data_len = virtqPkt.pktlen
        used_data_len = 0

        if needHdr:
            hdrDesc = VirtqDesc(addr=0, pktlen=1, flags=(VirtqFlagBit.NEXT_BIT | extra_flags))
            chainLen += 1
            self.descs.append(hdrDesc)

        if oneDesc:
            desc = VirtqDesc(addr=(virtqPkt.pktbase + 0), pktlen=virtqPkt.pktlen, flags=extra_flags)
            self.descs.append(desc)
        else:
            while left_data_len > 0:
                if self.random_mtu:
                    self.mtu = random.randint(1, 65535)

                if (left_data_len <= self.mtu) or ((not allowLongChain) and (chainLen == 127)):
                    desc = VirtqDesc(addr=(virtqPkt.pktbase + used_data_len),
                                     pktlen=left_data_len, flags=extra_flags)
                else:
                    desc = VirtqDesc(addr=(virtqPkt.pktbase + used_data_len),
                                     pktlen=self.mtu,
                                     flags=(VirtqFlagBit.NEXT_BIT | extra_flags))

                chainLen += 1
                used_data_len += desc.pktlen
                left_data_len -= desc.pktlen
                self.descs.append(desc)

    def popDesc(self):
        if not self.descs:
            return None
        return self.descs.popleft()


class Virtq:
    def __init__(self, tb, qid, qszWidth, mtu, random_mtu, testType=TestType.NETTX):
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.tb = tb
        self.qid = qid
        self.qszWidth = qszWidth
        self.qsz = 2 ** qszWidth

        self.mtu = mtu
        self.random_mtu = random_mtu
        self.is_start = False

        self.gen = 0

        # desc_base.write(address, data)
        # desc_base.get_absolute_address(0)
        self.desc_base = self.tb.mem.alloc_region(16 * self.qsz)  # 默认对齐么 ???
        self.id_allocator = set(range(0, self.qsz))
        self.saved_desc = deque()
        self.saved_ring_id = deque()
        self.record_desc = deque(maxlen=(2 * self.qsz))
        self.exit = Event()
        self.nrTestPkts = 0
        self.nrRetrievePkts = 0
        self.nrSendPkts = 0
        self.nrSendDesc = 0
        self.nrRetrieveDesc = 0
        self.workDone = False
        self.exitDirect = False
        self.expectError = False
        self.disableLog = True
        self.enableRecord = True
        self.lastPrintTM = int(time.time())
        self.nextIsChainHdr = True
        self.testType = testType 
        self.nrEmptyNotify = 0
        self.nrTotalNotify = 0
        self.invalidMaxSegLen = False
        self.expectStop = False
        self.pktGenExit = False
        self.paused = False
        self.randomPauseExit = False

        if self.random_mtu:
            self.mtu = random.randint(1, 65535)

    def mylog(self, *args, sep=" ", end="\n", force=False):
        currTM = int(time.time())
        if currTM - self.lastPrintTM > 2:
            self.lastPrintTM = currTM
            self.log.debug(f"[q{self.qid}] send {self.nrSendDesc} desc {self.nrSendPkts} pkts, retrieve {self.nrRetrieveDesc} desc already, {self.nrEmptyNotify} empty notify, {self.nrTotalNotify} total notify")

        if (not self.disableLog) or force:
            message = f"[q{self.qid}] {sep.join(map(str, args))}"
            self.log.debug(message)

    def print_desc(self, desc, force=False):
        self.mylog(f"desc on q{self.qid}", force=force)
        self.mylog(f"\taddr: {hex(desc.addr)}", force=force)
        self.mylog(f"\tpktlen: {desc.pktlen}", force=force)
        self.mylog(f"\tflags: {desc.flags}", force=force)
        self.mylog(f"\tnext: {desc.next}", force=force)
        hexVal = hex(desc.pack())
        self.mylog(f"\thex value: {hexVal}", force=force)

    def printRecordDesc(self):
        idx = 0
        self.mylog("print record desc", force=True)
        for desc in self.record_desc:
            self.mylog(f"{idx}-th desc in record:", force=True)
            self.print_desc(desc, force=True)
            idx += 1

    def printInfo(self, testName):
        self.mylog(f"{testName} on q{self.qid} exit\
                qsz: {self.qsz}, mtu: {self.mtu}, random_mtu: {self.random_mtu}, nrSendPkts: {self.nrSendPkts}", force=True)
        self.printRecordDesc()


    def get_saved_desc(self):
        if not self.saved_desc:
            return None
        return self.saved_desc.popleft()

    def get_saved_ring_id(self):
        if not self.saved_ring_id:
            return None
        idx = self.saved_ring_id.popleft()
        self.release_id(idx)
        return idx

    async def alloc_id(self):
        while not self.id_allocator:
            self.mylog(f"no available id")
            await Timer(100, 'ns')
        idx = random.choice(list(self.id_allocator))
        self.id_allocator.remove(idx)
        self.saved_ring_id.append(idx)
        return idx


    def release_id(self, idx):
        if idx < 0 or idx >= self.qsz:
            raise ValueError(f"[q{self.qid}]: ID {idx} out of range (0-{self.qsz})")
        if idx in self.id_allocator:
            raise ValueError(f"[q{self.qid}]: ID {idx} is already available.")
        self.id_allocator.add(idx)


    async def qpause(self):
        if not self.paused:
            self.mylog("queue pause", force=True)
            await self.tb._qpause(self.qid)
            self.paused = True
            await Timer(4, 'ns')

    async def qcontinue(self):
        if self.paused:
            self.mylog("queue continue", force=True)
            await self.tb._q_cacel_pause(self.qid)
            self.paused = False
            await Timer(4, 'ns')

    async def write_desc(self, desc, idx):
        self.mylog(f"desc id: {idx}")
        self.print_desc(desc)
        data = bytearray(desc.pack().to_bytes(16, 'little'))

        self.nrSendDesc += 1
        await self.desc_base.write(int(idx * (VirtqDesc.width / 8)), data)

    async def start(self):
        if self.is_start:
            self.mylog(f"start q {self.qid} already start")
            return

        maxSegLen = 65536 * 2
        if self.invalidMaxSegLen:
            maxSegLen = 2

        await self.tb.config(self.qid, self.desc_base.get_absolute_address(0),self.qid,
                             self.qszWidth, self.qid, self.qid, self.gen, maxSegLen)
        await self.tb._qstart(self.qid, random.randint(0, 65535))
        self.is_start = True
        await Timer(120, 'ns')
        self.mylog(f"start q")

    async def stop(self):
        if not self.is_start:
            self.mylog(f"stop q {self.qid} already stop")
            return

        await self.tb._qstop(self.qid)

        self.mylog(f"stop q")
        self.mylog(f"\tnumber of remaining in saved_desc is {len(self.saved_desc)}")
        self.mylog(f"\tnumber of remaining in saved_ring_id is {len(self.saved_ring_id)}")

        self.saved_desc.clear()
        self.record_desc.clear()
        self.saved_ring_id.clear()

        self.id_allocator.clear()
        self.id_allocator.update(range(0, self.qsz))
        self.gen += 1
        self.gen = int(self.gen%256)
        self.is_start = False


    async def reset(self):
        self.mylog(f"reset")

        self.exit.clear()
        self.exitDirect = False
        self.nrTestPkts = 0
        self.nrRetrievePkts = 0
        self.nrSendPkts = 0
        self.nrSendDesc = 0
        self.nrRetrieveDesc = 0
        self.workDone = False
        self.expectError = False
        self.disableLog = True
        self.enableRecord = True
        self.lastPrintTM = int(time.time())
        self.nextIsChainHdr = True
        self.nrEmptyNotify = 0
        self.nrTotalNotify = 0
        self.invalidMaxSegLen = False
        self.expectStop = False
        self.pktGenExit = False
        self.paused = False
        self.randomPauseExit = False

        await self.stop()
        await Timer(12, 'ns')
        await self.start()


    async def notify(self):
        self.nrTotalNotify += 1
        await self.tb.filter._host_notify(self.qid)
        await Timer(1000, 'ns')

    async def tx_desc_chain(self, descs):
        first_idx = await self.alloc_id()

        prev_idx = first_idx
        prev_desc = descs.popDesc()
        desc = descs.popDesc()
        while desc is not None:
            idx = await self.alloc_id()
            prev_desc.next = idx
            await self.write_desc(prev_desc, prev_idx)
            self.saved_desc.append(prev_desc)
            if self.enableRecord:
                self.record_desc.append(prev_desc)

            prev_desc = desc
            prev_idx = idx

            desc = descs.popDesc()

        await self.write_desc(prev_desc, prev_idx)
        self.saved_desc.append(prev_desc)
        if self.enableRecord:
            self.record_desc.append(prev_desc)

        await self.tb.wr_ring_id(self.qid, first_idx)

    async def tx_packet(self, pkt, extra_flags=0):
        needHdr = False

        if self.testType == TestType.NETRX:
            extra_flags = extra_flags | VirtqFlagBit.WRITE_BIT
        elif self.testType == TestType.BLK:
            needHdr = True

        descs = VirtqDescChain(pkt, self.mtu, self.random_mtu, extra_flags, needHdr=needHdr)
        self.nrSendPkts += 1
        await self.tx_desc_chain(descs)
        await self.notify()


    async def tx_packet_burst(self, pkts, extra_flags=0):
        for pkt in pkts:
            while True:
                try:
                    await self.tx_packet(pkt, extra_flags)
                    break
                except Exception as e:
                    self.mylog(f"exception: {e}, wait on sec")
                    await Timer(1000, 'ms')

    async def pkt_generator(self):
        self.mylog(f"start pkt generator", force=True)
        while not self.pktGenExit:
            await self.notify()
            await Timer(4, 'ns')
        self.mylog(f"end pkt generator", force=True)

    async def doRandomPause(self):
        self.mylog(f"start queue pause coroutine", force=True)
        while not self.randomPauseExit:
            if random.randint(1,5) == 1:
                await self.qpause()

            await Timer(random.randint(12, 400), 'ns')

            if self.paused:
                await self.qcontinue()

        if self.paused:
            await self.qcontinue()
        self.mylog(f"end queue pause coroutine", force=True)



async def testcase_send_n_pkts(virtq, n, extra_flags=0):
    virtq.nrTestPkts = n

    virtq.mylog(f"wait to send {virtq.nrTestPkts} pkts", force=True)

    pkts = []
    for _ in range(n):
        pkts.append(VirtqPkt())

    await virtq.tx_packet_burst(pkts, extra_flags)
    virtq.nrEmptyNotify += 1
    await virtq.notify()

def testcase_decorator(func):
    @wraps(func)
    async def wrapper(*args, **kwargs):
        virtq = args[0]

        virtq.mylog(f"start test {func.__name__}", force=True)
        await virtq.reset()

        if virtq.testType == TestType.NETRX:
            cocotb.start_soon(virtq.pkt_generator())

        await func(virtq)

        virtq.workDone = True

        if not virtq.exitDirect:
            await virtq.exit.wait()

        if virtq.testType == TestType.NETRX:
            virtq.pktGenExit = True

        virtq.printInfo(func.__name__)
        virtq.mylog(f"end test {func.__name__}", force=True)
        await Timer(10, 'ns')

    return wrapper


@testcase_decorator
async def testcase_send_1_pkts(virtq):
    await testcase_send_n_pkts(virtq, 1)


@testcase_decorator
async def testcase_send_a_little_pkts(virtq):
    await testcase_send_n_pkts(virtq, random.randint(virtq.qsz,2*virtq.qsz))


@testcase_decorator
async def testcase_send_some_pkts(virtq):
    await testcase_send_n_pkts(virtq,
                               random.randint(virtq.qsz + 1, min(virtq.qsz * 9, 5000)))


@testcase_decorator
async def testcase_send_a_lot_pkts(virtq):
    await testcase_send_n_pkts(virtq,
                               random.randint(1024 * virtq.qsz,
                                              1024 * 1024 * virtq.qsz))


@testcase_decorator
async def testcase_crazy_start_stop(virtq):
    virtq.exitDirect = True
    for i in range(0, 10000):
        await virtq.stop()
        await Timer(12, 'ns')
        await virtq.start()


@testcase_decorator
async def testcase_desc_invalid_addr(virtq):
    virtq.nrTestPkts = 1

    virtq.mylog(f"wait to send {virtq.nrTestPkts} pkts", force=True)

    pkts = []
    pkts.append(VirtqPkt(pktbase=0))

    await virtq.tx_packet_burst(pkts)
    virtq.nrEmptyNotify += 1
    await virtq.notify()


@testcase_decorator
async def testcase_desc_invalid_len(virtq):
    virtq.expectError = True
    virtq.nrTestPkts = 1
    virtq.mylog(f"wait to send {virtq.nrTestPkts} pkts", force=True)

    pkt = VirtqPkt(pktlen=0)

    needHdr = False
    if virtq.testType == TestType.BLK:
        needHdr = True

    descs = VirtqDescChain(pkt, 1, False, oneDesc=True, needHdr=needHdr)
    await virtq.tx_desc_chain(descs)
    await virtq.notify()


@testcase_decorator
async def testcase_desc_invalid_flags(virtq):
    virtq.expectError = True
    pkts = []
    pkts.append(VirtqPkt())
    await testcase_send_n_pkts(virtq, 1, extra_flags = VirtqFlagBit.INDIRECT_BIT)


@testcase_decorator
async def testcase_desc_invalid_chain(virtq):
    virtq.nrTestPkts = 1
    virtq.expectError = True

    virtq.mylog(f"wait to send {virtq.nrTestPkts} pkts", force=True)

    if virtq.qsz < 129:
        raise Exception(f"virtq size too \
                        small({virtq.qsz}) for invalid_chain testcase")

    if virtq.testType == TestType.BLK:
        needHdr = True
        pkt = VirtqPkt(pktlen=(virtq.qsz - 1))  # total len of chain is qsz
    else:
        needHdr = False
        pkt = VirtqPkt(pktlen=129)

    descs = VirtqDescChain(pkt, 1, False, extra_flags=VirtqFlagBit.NEXT_BIT, allowLongChain=True, needHdr=needHdr)
    await virtq.tx_desc_chain(descs)
    await virtq.notify()

@testcase_decorator
async def testcase_desc_invalid_blk_chain(virtq):
    if not virtq.testType == TestType.BLK:
        virtq.mylog(f"this test testcase_desc_invalid_blk_chain NA for {virtq.testType} virtq", force=True)
        return

    virtq.expectError = True
    virtq.nrTestPkts = 1
    virtq.mylog(f"wait to send {virtq.nrTestPkts} pkts", force=True)

    pkt = VirtqPkt(pktlen=1)

    descs = VirtqDescChain(pkt, 1, False, oneDesc=True)
    await virtq.tx_desc_chain(descs)
    await virtq.notify()

@testcase_decorator
async def testcase_desc_invalid_max_seg_len(virtq):
    virtq.expectError = True
    virtq.nrTestPkts = 1
    virtq.invalidMaxSegLen = True
    virtq.mylog(f"wait to send {virtq.nrTestPkts} pkts", force=True)

    pkt = VirtqPkt(pktlen=1024)

    descs = VirtqDescChain(pkt, 1500, False, oneDesc=True)
    await virtq.tx_desc_chain(descs)
    await virtq.notify()

@testcase_decorator
async def testcase_desc_pause_blk(virtq):
    cocotb.start_soon(virtq.doRandomPause())
    await testcase_send_n_pkts(virtq, random.randint(virtq.qsz,2*virtq.qsz))
    await virtq.notify()

    virtq.randomPauseExit = True
    await Timer(400, "ns")



@testcase_decorator
async def testcase_desc_stop_in_middle(virtq):
    pass

@testcase_decorator
async def testcase_invalid_id(virtq):
    virtq.expectError = True
    pass


@testcase_decorator
async def testcase_boundary_test(virtq):
    pass


@testcase_decorator
async def testcase_invalid_config(virtq):
    virtq.expectError = True
    pass

async def startAllTestOnVirtq(virtq, testNum, testCases=[testcase_send_1_pkts]):
    # allTestcases = [testcase_send_1_pkts,
    #                 testcase_send_a_little_pkts,
    #                 testcase_send_some_pkts,
    #                 testcase_send_a_lot_pkts,
    #                 testcase_crazy_start_stop,
    #                 testcase_desc_invalid_addr,
    #                 testcase_desc_invalid_len,
    #                 testcase_desc_invalid_flags,
    #                 testcase_desc_invalid_chain]

    log = logging.getLogger("cocotb.tb")
    for i in range(testNum):
     # test = random.choice(testCases)
        for test in testCases:
            log.debug(f"{i}-th test on q{virtq.qid}")
            log.debug(f"\t[q{virtq.qid}]: testcase:     {test.__name__}")
            log.debug(f"\t[q{virtq.qid}]: qsize:        {virtq.qsz}")
            log.debug(f"\t[q{virtq.qid}]: mtu:          {virtq.mtu}")
            log.debug(f"\t[q{virtq.qid}]: random_mtu:   {virtq.random_mtu}")
            await test(virtq)


async def checkResult(virtqs, tb):
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)
    try:
        while True:   
            log.debug(f"[CHECK]: get finish qid")
            info = await tb._get_finish_qid()
            virtq = virtqs[info.qid]
            """
            info
            fields_desc = [
                BitField("qid",               0,  8),
                BitField("chn",               0,  5),
                BitField("err",               0,  8),
                BitField("status",            0,  8),
                BitField("rd_rdptr_data",     0,  5),
                BitField("resch",             0,  1),
                BitField("index",             0,  16),
                BitField("ring_id",           0,  16),
                BitField("ring_id_avail_num", 0,  5),
                BitField("desc_num",          0,  16),
                BitField("generation",        0,  8),
            ]
            """

            #if (info.status & InfoStatusBit.QSTOP_BIT) and (virtq.is_start):
            #    raise Exception(f"status means q stop {info.status} while q is start")
            #elif info.status & InfoStatusBit.QSTOP_BIT:
            #    continue

            if info.generation != virtq.gen:
                """
                may be in-flight desc before q_stop
                """
                virtq.mylog(f"[CHECK]: gen info.gen({info.generation}) not equal virtq gen({virtq.gen}) on q{info.qid}")
                await tb._put_checkout_qid(info.qid)
                continue

            if (not virtq.expectError) and (info.err != 0):
                raise Exception(f"error on q{info.qid}: err: {info.err}")
            elif virtq.expectError and info.err != 0:
                virtq.mylog(f"\t[CHECK]: expect error and get error {info.err}")
                if not virtq.exit.is_set():
                    virtq.mylog("set exit")
                    virtq.exit.set()
                    await Timer(10, 'ns')
            else:
                virtq.mylog(f"[CHECK]: check {info.desc_num} descs for q {info.qid}")
                for i in range(info.desc_num):
                    virtq.mylog(f"\t[CHECK]: {i}-th desc")
                    retDesc, ret_ring_id = await tb._get_desc(info.qid)
                    virtq.nrRetrieveDesc += 1
                    savedDesc = virtq.get_saved_desc()
                    savedNum = savedDesc.pack()
                    virtq.mylog(f"\t\t[CHECK]: get desc: {hex(retDesc)}, saved desc: {hex(savedNum)}")
                    if savedNum != retDesc:
                        print(f"expect desc {hex(savedNum)}  acture receive desc {hex(retDesc)}")
                        raise Exception(f"desc not equal on q{info.qid}: \
                                savedDesc is {hex(savedNum)}, retDesc is {hex(retDesc)}")

                    if virtq.nextIsChainHdr:
                        virtq.mylog(f"\t\t[CHECK]: check ring id for q{info.qid}")
                        virtq.nrRetrievePkts += 1
                        saved_ring_id = virtq.get_saved_ring_id()
                        virtq.mylog(f"\t\t\t[CHECK]: return ring id: {ret_ring_id}, saved ring id: {saved_ring_id}")
                        if saved_ring_id != ret_ring_id:
                            raise Exception(f"ring id equal on q{info.qid}: saved ring id is {saved_ring_id}, ret ring id is {ret_ring_id}")
                        virtq.nextIsChainHdr = False
                    else:
                        idx = virtq.get_saved_ring_id()
                        if idx is None:
                            raise Exception("desc_num large than num of saved ring id")
                        virtq.mylog(f"\t\t[CHECK]: pop non-head ring id {idx}")

                    if not (savedDesc.flags & VirtqFlagBit.NEXT_BIT):
                        virtq.nextIsChainHdr = True
                        # we have got tail while nothing err happends
                        if virtq.expectError and info.err == 0:
                            raise Exception(f"[q{info.qid}]: expect error while no error in info")

            virtq.mylog(f"[CHECK]: checkout")
            await tb._put_checkout_qid(info.qid)

            if (virtq.workDone or virtq.nrTestPkts == virtq.nrRetrievePkts)  and virtq.nrSendDesc == virtq.nrRetrieveDesc:
                if (not virtq.exit.is_set()) and (not virtq.exitDirect):
                    virtq.mylog("set exit")
                    virtq.exit.set()
                    await Timer(10, 'ns')
    except Exception as e:
        virtq.printRecordDesc()
        raise e




async def startTest(tb, qnum, testNum=1, testType=TestType.NETTX, testCases=[testcase_send_1_pkts], mode=TestMode.CHOOSE_ONE):
    virtqs = {}
    qids = random.sample(range(0, 256), qnum)
    qszs = [random.choice([i for i in range(8,11)]) for _ in range(qnum)]
    mtus = random.sample(range(0, 65536), qnum)
    random_mtus = [random.choice([True, False]) for _ in range(qnum)]
    for i in range(qnum):
        virtqs[qids[i]] = Virtq(tb, qids[i], qszs[i], mtus[i], random_mtus[i], testType)


    workers = []
    caseIdx = 0
    for virtq in virtqs.values():
        testNum = random.randint(1, testNum)
        if mode == TestMode.ALL_CASE:
            workers.append(cocotb.start_soon(startAllTestOnVirtq(virtq, testNum, testCases)))
        elif mode == TestMode.CHOOSE_ONE:
            workers.append(cocotb.start_soon(startAllTestOnVirtq(virtq, testNum, testCases[caseIdx:caseIdx + 1])))
            caseIdx += 1
            caseIdx %= len(testCases)

    cocotb.start_soon(checkResult(virtqs, tb))

    for worker in workers:
        await worker.join()
