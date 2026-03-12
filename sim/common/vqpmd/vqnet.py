import itertools
import logging
import os
import sys
import random
import math
import struct
from collections import deque
from functools import wraps

import cocotb_test.simulator
import pytest

from address_space import IORegion, AddressSpace

import cocotb
from cocotb.log import SimLog
from cocotb.clock import Clock
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event,Lock
from cocotb.regression import TestFactory
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
import time

class VirtqPkt:
    def __init__(self, pktbase=None, pktlen=None, region=None, tb=None, maxPktlen=65535):
        if pktbase is None:
            # Construct a packet with length pktlen
            self.pktlen = pktlen if pktlen != None else random.randint(14, min(maxPktlen, 65535))
            self.region = tb.mem.alloc_region(self.pktlen)
            self.pktbase = self.region.get_absolute_address(0)
        else:
            self.pktbase = pktbase
            self.pktlen = pktlen
            self.region = region

class VirtqAddr:
    CONFIG_BASE_ADDR = 0x1800000
    DFX_AVAIL_RING_BASE_ADDR = 0x1c00000
    DFX_USED_RING_BASE_ADDR = 0x1c00000+ 0x20000
    DFX_NETTX_BASE_ADDR = 0x1c00000+ 0x40000
    DFX_NETRX_BASE_ADDR = 0x1c00000+ 0x60000
    DFX_BLK_BASE_ADDR = 0x1c00000+ 0x80000
    DFX_ERR_BASE_ADDR = 0x1c00000+ 0xa0000
    DFX_START_STOP_BASE_ADDR = 0x1c00000+ 0xc0000

class VirtqType:
    NETTX = 0x0
    NETRX = 0x1
    BLK = 0x2

class VirtioNetHdrFlagBit:
    VIRTIO_NET_HDR_F_NEEDS_CSUM = 0x1
    VIRTIO_NET_HDR_F_DATA_VALID = 0x2
    VIRTIO_NET_HDR_F_RSC_INFO = 0x4

class VirtioNetHdrGsoTypeBit:
    VIRTIO_NET_HDR_GSO_NONE = 0
    VIRTIO_NET_HDR_GSO_TCPV4 = 1
    VIRTIO_NET_HDR_GSO_UDP = 3
    VIRTIO_NET_HDR_GSO_TCPV6 = 4
    VIRTIO_NET_HDR_GSO_ECN = 0x80

class VirtioNetHdr(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("num_buffers",      0,  16),
        BitField("csum_offset",      0,  16),
        BitField("csum_start",       0,  16),
        BitField("gso_size",         0,  16),
        BitField("hdr_len",          0,  16),
        BitField("gso_type",         0,  8),
        BitField("flags",            0,  8),
    ]

    width = 0
    for elemnt in fields_desc:
        width += elemnt.size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        return cls(data)

class VirtqDescFlagBit:
    NEXT_BIT = 0x1
    WRITE_BIT = 0x2
    INDIRECT_BIT = 0x4

class VirtqDesc(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("next",            0,  16),
        BitField("flags",           0,  16),
        BitField("pktlen",          0,  32),
        BitField("addr",            0,  64),
    ]

    region = None

    width = 0
    for elemnt in fields_desc:
        width += elemnt.size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        return cls(data)

class VirtqUsedElem(Packet):
    name = 'virtq_used_elem'
    fields_desc = [
        BitField("dataLen",       0,  32),
        BitField("descID",        0,  32),
    ]

    width = 0
    for elemnt in fields_desc:
        width += elemnt.size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        return cls(data)

class VirtqAvailElem(Packet):
    name = 'virtq_avail_elem'
    fields_desc = [
        BitField("descID",        0,  16),
    ]

    width = 0
    for elemnt in fields_desc:
        width += elemnt.size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        return cls(data)

class rxqPktGenerator:
    def __init__(self, virtq=None, pps=100000):
        self.tb = virtq.tb
        self.virtq = virtq
        self.qid = virtq.qid
        self.gen = virtq.gen
        self.pps = pps
        self.maxPktlen = virtq.mtu
        self.magicCode = 0x0014
        self.lastPrintTm = 0

        self.totPkts = 0

        self.exit = Event()

    # Create an array whose length is `magicCode` and 
    # whose content has every two bytes as `magicCode`(littleEndian).
    def generate_byte_array(self):
        data = bytearray()
        for _ in range(self.magicCode // 2):
            data.extend(struct.pack('<H', self.magicCode))
        if self.magicCode % 2 == 1:
            data.append(0xFF)

        self.magicCode = self.magicCode + 1
        self.magicCode = max(14, (self.magicCode % self.maxPktlen))
        return data

    # TODO: generator exit
    async def mainLoop(self,gen):
        self.exit.clear()
        self.gen = gen
        intval = (10 ** 9) / self.pps
        while not self.exit.is_set():
            data = self.generate_byte_array()
            await self.tb.netrx_feq_rcv(self.qid, len(data), self.gen, data)
            self.totPkts += 1
            currTm = int(time.time())
            if currTm - self.lastPrintTm > 2:
                self.lastPrintTm = currTm
                self.virtq.mylog(f"gen {self.totPkts} pkt")
            await Timer(intval, 'ns')

    async def exitLoop(self):
        self.exit.set()
        await Timer(100, 'ns')

    def update_gen(self,gen):
        self.gen = gen

    @classmethod
    def validData(cls, data):
        virtio_hdr = data[0:12]
        for i in range(10):
          assert data[i] == 0
        assert data[10] == 1
        assert data[11] == 0
        data = data [12:]
        lenOfData = len(data)
        if len(data) % 2 == 1:
            if data[-1] != 0xff:
                print(f"data last byte is not 0xff")
                return False
            data = data[:-1]

        if len(data) <= 2:
            return True
        else:
            prev_2byte = data[0:2]
            if lenOfData != (data[0] + (data[1] << 8)):
                print(f"data len {lenOfData} != magicCode {data[0] + (data[1] << 8)}")
                return False

        for i in range(2, len(data), 2):
            curr_2byte = data[i:i + 2]
            if prev_2byte != curr_2byte:
                print(f"data {data} is not valid")
                return False
            prev_2byte = curr_2byte

        return True


class txqPktChecker:
    def __init__(self, virtq=None):
        self.virtq = virtq
        self.tb = virtq.tb

    async def mainLoop(self):
        nrCheckPkts = 0
        totData = []
        totDataLen = 0
        while (self.virtq.nrTestPkts != nrCheckPkts):
            self.virtq.mylog(f"txqPktChecker wait for tx pkts")
            eop, sop, qid, dataLen, gen, data = await self.tb.get_nettx_rcv(self.virtq.qid)
            self.virtq.mylog(f"txqPktChecker get pkts")

            totData = totData + data
            totDataLen = totDataLen + dataLen

            if self.virtq.disableChecker:
                self.virtq.mylog(f"txqPktChecker disabled")
                break
            
            if eop != 0:
                nrCheckPkts += 1
                pkt = self.virtq.inFlightPkts.popleft()
                if pkt is None:
                    await self.virtq.printVirtq()
                    raise ValueError(f"pkt is None packets nrCheckPkts {nrCheckPkts}")
                pktData = list(await pkt.region.read(0, pkt.pktlen))
                if len(pktData) != totDataLen:
                    await self.virtq.printVirtq()
                    raise ValueError(f"pkt check failed, qid {qid} dataLen {dataLen} len of data {len(totData)} pktLen {len(pktData)}")

                if pktData != totData:
                    bIdx = 0
                    for b1, b2 in zip(pktData, totData):
                        bIdx += 1
                        if b1 != b2:
                            await self.virtq.printVirtq()
                            raise ValueError(f"pkt check failed, qid {qid} dataLen {dataLen} bIdx {bIdx} len of data {len(totData)} pktLen {len(pktData)}")
                    raise ValueError(f"WTF")

                totData = []
                totDataLen = 0
                region = self.virtq.inFlightPktsCtx.popleft()
                self.virtq.tb.mem.free_region(region)
            else:
                pass
            

            self.virtq.mylog(f"txqPktChecker check pkts success, qid {qid} dataLen {dataLen} gen {gen} nrTxPkts {self.virtq.nrTxPkts} nrCheckPkts {nrCheckPkts}")
            # TODO: check generation

class virtqErrChecker:
    def __init__(self, virtq=None):
        self.virtq = virtq
        self.tb = virtq.tb

    async def mainLoop(self):
        while True:
            err = await self.virtq.hwErr() 
            if (err != 0) and (self.virtq.expErr):
                if err != self.virtq.expErrCode:
                    await self.virtq.printVirtq()
                    raise ValueError(f"hw error on q{self.virtq.qid} expErrCode {self.virtq.expErrCode} != hwErr {err}")
                elif self.virtq.expStop:
                    await Timer(8000, 'ns')
                    self.virtq.mylog(f"hw error on q{self.virtq.qid} expErrCode {self.virtq.expErrCode} hwErr {err}")
                    stopped = await self.virtq.hwStopped()
                    if not stopped:
                        await self.virtq.printVirtq()
                        raise ValueError(f"virtq not stopped")

                break
            elif (err != 0) and (not self.virtq.expErr):
                await self.virtq.printVirtq()
                raise ValueError(f"hw error on q{self.virtq.qid} hwErr {err}")
            else:
                # Check for errors every 1000ns
                await Timer(1000, 'ns')

        if self.virtq.testcase_destructor is not None:
            self.virtq.testcase_destructor()
            self.virtq.testcase_destructor = None
            self.virtq.testcase_destructor_arg = None

class IdPool:
    def __init__(self, size=1024):
        self.size = size
        self.allocator = set(range(0,size))

    def allocID(self):
        if not self.allocator:
            return None

        idx = random.choice(list(self.allocator))
        self.allocator.remove(idx)
        return idx

    def releaseID(self, idx):
        if idx < 0 or idx >= self.size:
            raise ValueError(f"idx {idx} out of range")
        if idx in self.allocator:
            raise ValueError(f"idx {idx} already released")

        self.allocator.add(idx)

    def clear(self):
        self.allocator.clear()
        self.allocator.update(range(0, self.size))

    def alloc_n_ID(self, n):
        IDs = []
        if n >= len(self.allocator):
            return IDs

        for i in range(n):
            IDs.append(self.allocID())

        return IDs

    def empty(self):
        if len(self.allocator) == 0:
            return True
        return False

class Virtq:
    def __init__(self, tb, qid=0, qtype=VirtqType.NETTX, qlen=1024, mtu=1500, gen=0):
        self.tb = tb
        self.qid = qid
        self.qtype = qtype
        self.qlen = qlen
        self.mtu = mtu
        self.gen = gen

        # Encode qid information into msix_addr and msix_data
        if qtype == VirtqType.NETTX:
            self.msix_addr = 0xffffffffffe00000 + self.qid
        elif qtype == VirtqType.NETRX:
            self.msix_addr = 0xfffffffffff00000 + self.qid
        self.msix_data = self.qid

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.DescTable = self.tb.mem.alloc_region((int)((VirtqDesc.width / 8)* self.qlen))
        self.AvailRing = self.tb.mem.alloc_region((int)(2 + 2 +  (VirtqAvailElem.width / 8) * self.qlen + 2))
        self.UsedRing = self.tb.mem.alloc_region((int)(2 + 2 + (VirtqUsedElem.width / 8) * self.qlen + 2))
        self.idPool = IdPool(self.qlen)
        if self.qtype == VirtqType.NETRX:
            self.pktGenerator = rxqPktGenerator(self)
        if self.qtype == VirtqType.NETTX:
            self.pktChecker = txqPktChecker(self)
        self.errChecker = virtqErrChecker(self)

        self.nrTxPkts = 0
        self.nrRxPkts = 0
        self.nrFillDescs = 0
        self.nrRecycleDescs = 0
        self.nrTestPkts = -1

        self.enableLog = True

        self.started = False
        self.workDone = False
        self.nextUsedRingID = 0
        self.inFlightPkts = deque()
        self.inFlightPktsCtx = deque()
        self.inFlightDescIDs = deque()
        self.rxDescCtx = deque()
        self.lastPrintTm = int(time.time())

        self.currStage = "init"

        self.expErr = False
        self.expStop = False
        self.expErrCode = 0
        self.testcase_destructor = None
        self.testcase_destructor_arg = None
        self.disableInt = False
        self.disableChecker = False

    async def reset(self):
        await self.stop()
        await self.resetHwErr()

        self.idPool.clear()
        # if self.qtype == VirtqType.NETRX:
        #     await self.pktGenerator.exitLoop()

        self.nrTxPkts = 0
        self.nrRxPkts = 0
        self.nrFillDescs = 0
        self.nrRecycleDescs = 0
        self.nrTestPkts = -1

        self.started = False
        self.workDone = False
        self.nextUsedRingID = 0
        self.inFlightPkts.clear()
        self.inFlightPktsCtx.clear()
        self.inFlightDescIDs.clear()
        self.rxDescCtx.clear()
        self.lastPrintTm = int(time.time())

        self.expErr = False
        self.expStop = False
        self.expErrCode = 0
        self.testcase_destructor = None
        self.testcase_destructor_arg = None

        self.gen = (self.gen + 1) % 256
        if self.qtype == VirtqType.NETRX:
           self.pktGenerator.update_gen(self.gen)

    async def start(self):
        initId = 0
        self.currStage = "start: start"

        self.currStage = "start: before write avail ring"
        await self.AvailRing.write(2, initId.to_bytes(2, byteorder='little'))

        self.currStage = "start: before write used ring"
        await self.UsedRing.write(2, initId.to_bytes(2, byteorder='little'))

        qt = {
            VirtqType.NETTX: 0,
            VirtqType.NETRX: 1
        }.get(self.qtype, 2)
        self.currStage = "start: before config"
        await self.tb.config(qt, self.qid, 0, self.AvailRing.get_absolute_address(0), self.UsedRing.get_absolute_address(0), self.DescTable.get_absolute_address(0), int(math.log2(self.qlen)),
                        self.msix_addr, self.msix_data, 0, 0, self.gen,
                        65535, 0, False, msix_enable=1, msix_mask=0)

        self.currStage = "start: before qset_cmd"
        await self.tb.qset_cmd(qt, self.qid, 0, 1, 0, 0, 0)

        cocotb.start_soon(self.printVirtqPeriod())

        self.errCheckerCoro = cocotb.start_soon(self.errChecker.mainLoop())
        if self.qtype == VirtqType.NETRX:
            await self.rxFill()
            cocotb.start_soon(self.pktGenerator.mainLoop(self.gen))
        elif self.qtype == VirtqType.NETTX and (not self.disableChecker):
            self.txPktCheckerCoro = cocotb.start_soon(self.pktChecker.mainLoop())

        self.started = True
        qt = {
            VirtqType.NETTX: 0,
            VirtqType.NETRX: 1
        }.get(self.qtype, 2)
        self.currStage = "start: before notify"
        await self.tb.soc_notify(qt, self.qid)
        self.currStage = "start: end"

    async def stop(self):
        self.currStage = "stop: start"
        qt = {
            VirtqType.NETTX: 0,
            VirtqType.NETRX: 1
        }.get(self.qtype, 2)
        self.started = False
        await self.tb.qset_cmd(qt, self.qid, 0, 0, 1, 0, 0)
        self.currStage = "stop: end"

    async def notify(self):
        qt = {
            VirtqType.NETTX: 0,
            VirtqType.NETRX: 1
        }.get(self.qtype, 2)

        self.currStage = "notify: start"
        await self.tb.notify(self.qtype, self.qid)
        self.currStage = "notify: end"

    async def getNextUsedElem(self):
        ringIDRaw = await self.UsedRing.read(2, 2)
        ringID = (ringIDRaw[0] + (ringIDRaw[1] << 8))

        if ringID == (self.nextUsedRingID % 65536):
            return None

        usedElemRawData = await self.UsedRing.read(int(4 + (self.nextUsedRingID % self.qlen) * (VirtqUsedElem.width / 8)), int(VirtqUsedElem.width / 8))
        usedElem = VirtqUsedElem.unpack(usedElemRawData[::-1])
        return usedElem

    async def writeNextAvailElem(self, descID):
        ringIDRaw = await self.AvailRing.read(2, 2)
        ringID = (ringIDRaw[0] + (ringIDRaw[1] << 8))

        availElem = VirtqAvailElem(descID=descID)

        await self.AvailRing.write(int(4 + (ringID % self.qlen) * (VirtqAvailElem.width / 8)), bytearray(availElem.pack().to_bytes(2, 'little')))

        ringID += 1
        await self.AvailRing.write(2, ringID.to_bytes(2, byteorder='little'))

    async def retrieveUsedDesc(self):
        usedElem = await self.getNextUsedElem()
        if usedElem is None:
            return None, None
        else:
            self.nextUsedRingID += 1
            self.nextUsedRingID %= 65536

        descID = usedElem.descID
        descRawData = await self.DescTable.read(int((descID % self.qlen) * (VirtqDesc.width / 8)), int(VirtqDesc.width / 8))
        desc = VirtqDesc.unpack(descRawData[::-1])
        desc.pktlen = usedElem.dataLen
        self.nrRecycleDescs += 1

        return desc, descID

    async def fillAvailDescChain(self, descs=None, IDs=None):
        if descs is None or IDs is None or len(descs) != len(IDs):
            await self.printVirtq()
            raise ValueError(f"descs or IDs is None or length mismatch")

        hdrDescID = None
        self.nrFillDescs += len(descs)

        for desc, descID in zip(descs, IDs):
            if hdrDescID is None:
                hdrDescID = descID
            self.printDesc(desc, descID)
            await self.DescTable.write(int((descID % self.qlen) * (VirtqDesc.width / 8)), bytearray(desc.pack().to_bytes(16, 'little')))

        await self.writeNextAvailElem(hdrDescID)

    async def txpkts(self, pkts):
        # TODO: add virtio net hdr
        if self.qtype != VirtqType.NETTX:
            await self.printVirtq()
            raise ValueError(f"txpkts on qtype {self.qtype}")

        self.currStage = "txpkts: before txrecycle"
        await self.txRecycle()

        nb_tx = 0
        for pkt in pkts:
            descs = VirtqDescChain(pkt, self.mtu)
            IDs = self.idPool.alloc_n_ID(len(descs))
            if len(IDs) == 0:
                return nb_tx

            prevDesc = descs[0]
            for desc, descID in zip(descs[1:], IDs[1:]):
                prevDesc.next = descID
                prevDesc = desc

            self.inFlightDescIDs.append(IDs)
            self.inFlightPkts.append(pkt)
            self.inFlightPktsCtx.append(pkt.region)
            nb_tx += 1
            self.nrTxPkts += 1
            self.currStage = "txpkts: before fillAvailDescChain"
            await self.fillAvailDescChain(descs, IDs)
            self.currStage = "txpkts: before notify"
            await self.notify()
            await Timer(10, 'ns')

        self.currStage = "txpkts: after"
        return nb_tx

    async def txRecycle(self):
        if self.qtype != VirtqType.NETTX:
            await self.printVirtq()
            raise ValueError(f"txRecycle on qtype {self.qtype}")

        # Try to recycle as much as possible.
        while True and not self.disableInt and self.started:
            self.currStage = "txrecycle: retrieve used desc"
            desc, descID = await self.retrieveUsedDesc()
            if desc is None:
                return

            IDs = self.inFlightDescIDs.popleft()
            for ID in IDs:
                self.idPool.releaseID(ID)

    async def rxFill(self):
        if self.qtype != VirtqType.NETRX:
            await self.printVirtq()
            raise ValueError(f"rxFill on qtype {self.qtype}")

        if self.expErr:
            # Do not fill in valid desc because invalid desc needs to be filled for testing
            return

        while not self.idPool.empty():
            descID = self.idPool.allocID()
            region = self.tb.mem.alloc_region(self.mtu)
            desc = VirtqDesc(addr=region.get_absolute_address(0), pktlen=int(self.mtu + (VirtioNetHdr.width / 8)) , flags=VirtqDescFlagBit.WRITE_BIT)
            self.rxDescCtx.append(region)
            self.currStage = "rxfill: before fill avail desc chain"
            await self.fillAvailDescChain([desc], [descID])

        await self.notify()
        self.currStage = "rxfill: end"

    async def rxpkt(self):
        self.currStage = "rxpkt: start"
        if self.qtype != VirtqType.NETRX:
            await self.printVirtq()
            raise ValueError(f"rxpkt on qtype {self.qtype}")

        desc, descID = await self.retrieveUsedDesc()
        if desc is None:
            return

        self.idPool.releaseID(descID)
        
        self.nrRxPkts += 1
        region = self.rxDescCtx.popleft()

        self.currStage = "rxpkt: before region read"
        data = await region.read(0, desc.pktlen)
        self.tb.mem.free_region(region)

        if len(data) <= int(VirtioNetHdr.width / 8):
            await self.printVirtq()
            raise ValueError(f"rxq data len {len(data)} <= virtio net hdr len")

        self.currStage = "rxpkt: before rxFill"
        await self.rxFill()
        # strip virtio net hdr
        # TODO: check virtio net hdr
        self.currStage = "rxpkt: end"
        return data

    async def txHandler(self):
        self.mylog(f"txHandler on q{self.qid}")
        await self.txRecycle()

    async def rxHandler(self):
        self.mylog(f"rxHandler on q{self.qid}")
        while True and not self.disableInt:
            data = await self.rxpkt()
            if data is None: 
                return

            if not rxqPktGenerator.validData(data):
                await self.printVirtq()
                raise ValueError(f"data {data} is not valid")

    def mylog(self, *args, sep=" ", end="\n", force=False):
        if self.enableLog:
            message = f"[q{self.qid}] {sep.join(map(str, args))}"
            self.log.debug(message)

    async def printVirtq(self):
        err = await self.hwErr()
        st = await self.hwStatus()
        self.mylog(f"virtq {self.qid} stage {self.currStage} tx {self.nrTxPkts} rx {self.nrRxPkts} fill {self.nrFillDescs} recycle {self.nrRecycleDescs} nrTestPkts {self.nrTestPkts} hwErr {err} hwStatus {st}")

    async def printVirtqPeriod(self):
        while True:
            currTm = int(time.time())
            if currTm - self.lastPrintTm > 2:
                self.lastPrintTm = currTm
                await self.printVirtq()
            await Timer(2000, 'ns')

    def printDesc(self, desc, descID):
        self.mylog(f"desc on q{self.qid} id {descID}")
        self.mylog(f"\taddr: {hex(desc.addr)}")
        self.mylog(f"\tpktlen: {desc.pktlen}")
        self.mylog(f"\tflags: {desc.flags}")
        self.mylog(f"\tnext: {desc.next}")
        hexVal = hex(desc.pack())
        self.mylog(f"\thex value: {hexVal}")

    async def hwErr(self):
        DFX_ERR_BASE_ADDR = 0x1c00000 + 0xa0000
        if self.qtype == VirtqType.NETTX:
            return await self.tb.read_reg(DFX_ERR_BASE_ADDR + (self.qid << 3))
        elif self.qtype == VirtqType.NETRX:
            return await self.tb.read_reg(DFX_ERR_BASE_ADDR + ((256 + self.qid) << 3))
        else: # blk
            return await self.tb.read_reg(DFX_ERR_BASE_ADDR + ((256 + 256 + self.qid) << 3))

    async def resetHwErr(self):
        DFX_ERR_BASE_ADDR = 0x1c00000 + 0xa0000
        if self.qtype == VirtqType.NETTX:
            return await self.tb.write_reg(DFX_ERR_BASE_ADDR + (self.qid << 3), 0xff)
        elif self.qtype == VirtqType.NETRX:
            return await self.tb.write_reg(DFX_ERR_BASE_ADDR + ((256 + self.qid) << 3), 0xff)
        else: # blk
            return await self.tb.write_reg(DFX_ERR_BASE_ADDR + ((256 + 256 + self.qid) << 3), 0xff)

    async def hwStatus(self):
        qt = {
            VirtqType.NETTX: 0,
            VirtqType.NETRX: 1,
            VirtqType.BLK:   2
        }.get(self.qtype, 2)

        addr=(0x1800000) + (qt*0x200) + (self.qid*0x800) + 0x58

        val = await self.tb.read_reg(addr)

        self.mylog(f"hwStatus on q{self.qid} addr {addr} val {val}")

        return val

    async def hwStopped(self):
        status = await self.hwStatus()

        return (status & 0x2) != 0


def VirtqDescChain(virtqPkt=None, maxDescLen=1500, extraFlags=0, maxChainLen=127):
    if virtqPkt is None:
        raise ValueError(f"idPool or virtqPkt is None")

    descs = []
    chainLen = 0

    leftDataLen = virtqPkt.pktlen
    usedDataLen = 0

    while leftDataLen > 0:
        chainLen += 1
        if (leftDataLen <= maxDescLen) or (chainLen == maxChainLen):
            desc = VirtqDesc(addr=(virtqPkt.pktbase + usedDataLen),
                             pktlen=leftDataLen,
                             flags=extraFlags)
        else:
            desc = VirtqDesc(addr=(virtqPkt.pktbase + usedDataLen),
                             pktlen=maxDescLen,
                             flags=(VirtqDescFlagBit.NEXT_BIT | extraFlags))

        usedDataLen += desc.pktlen
        leftDataLen -= desc.pktlen
        descs.append(desc)

    return descs

def print_cocotb_coroutine_suspend_location(coro):
    """递归获取 Cocotb 协程或生成器的挂起位置"""
    while coro:
        frame = getattr(coro, "cr_frame", None) or getattr(coro, "gi_frame", None)
        if frame:
            print(frame.f_code.co_name, frame.f_lineno, frame.f_globals.get('__file__'))
            # 检查是否有挂起点
            next_coro = getattr(coro, "cr_await", None) or getattr(coro, "gi_yieldfrom", None)
            if next_coro:
                coro = next_coro
                continue
        break
def print_all_cocotb_coroutine_traces():
    scheduler = cocotb.scheduler
    trigger_to_coroutines = getattr(scheduler, "_trigger2coros", {})
    for trigger, tasks in trigger_to_coroutines.items():
        print(f"Trigger: {trigger}")
        for task in tasks:
            coro = task._coro
            stack = print_cocotb_coroutine_suspend_location(coro)
            if stack:
                print("".join(stack))
            else:
                print("No stack trace available for this coroutine.")

allRxVirtqs = {}
allTxVirtqs = {}

async def netrx_handler(address, data, **kwargs):
    # ref class Virtq.__init__, we encode qid info into msix_addr and msix_data
    print(f"RX HANDLER: address: {address} data: {list(data)} {int.from_bytes(data, byteorder='little')}")
    if address == int.from_bytes(data, byteorder='little'):
        qid = address
        virtq = allRxVirtqs[qid]
        await virtq.rxHandler()

async def nettx_handler(address, data, **kwargs):
    # ref class Virtq.__init__, we encode qid info into msix_addr and msix_data
    print(f"TX HANDLER: address: {address} data: {list(data)} {int.from_bytes(data, byteorder='little')}")
    if address == int.from_bytes(data, byteorder='little'):
        qid = address
        virtq = allTxVirtqs[qid]
        await virtq.txHandler()

def register_net_handelr(tb, qtype):
    if qtype == VirtqType.NETTX:
        ioregionNetTx = IORegion()
        ioregionNetTx.register_write_handler(nettx_handler)
        tb.mem.register_region(ioregionNetTx, 0xffffffffffe00000, 4096)
    elif qtype == VirtqType.NETRX:
        ioregionNetRx = IORegion()
        ioregionNetRx.register_write_handler(netrx_handler)
        tb.mem.register_region(ioregionNetRx, 0xfffffffffff00000, 4096)


def testcase_decorator(func):
    @wraps(func)
    async def wrapper(*args, **kwargs):
        virtq = args[0]

        virtq.mylog(f"start test {func.__name__}", force=True)
        await virtq.reset()
        await virtq.start()

        await func(virtq)
        virtq.workDone = True

        if virtq.expErr:
            await virtq.errCheckerCoro.join()
        elif virtq.qtype == VirtqType.NETTX:
            await virtq.txPktCheckerCoro.join()

        await virtq.printVirtq()
        virtq.mylog(f"end test {func.__name__}", force=True)
        await Timer(10, 'ns')

    return wrapper

async def testcase_send_n_pkts(virtq, n, extra_flags=0, randomPktlen=True, smallPkt=False, noChain=False, pps=1000000):
    if virtq.qtype != VirtqType.NETTX:
        raise ValueError(f"send pkts on qtype {virtq.qtype}")

    virtq.nrTestPkts = n

    virtq.mylog(f"wait to send {virtq.nrTestPkts} pkts", force=True)

    pkts = []
    if randomPktlen:
        for _ in range(n):
            pkts.append(VirtqPkt(tb=virtq.tb, maxPktlen=virtq.mtu*127))
    elif smallPkt:
        for _ in range(n):
            pkts.append(VirtqPkt(tb=virtq.tb, pktlen=random.randint(14,64)))
    elif noChain:
        for _ in range(n):
            pkts.append(VirtqPkt(tb=virtq.tb, pktlen=random.randint(14,virtq.mtu)))

    sended = 0
    burst = 8
    intval = (10 ** 9) / pps
    while sended < len(pkts):
        sended += await virtq.txpkts(pkts[sended:sended+burst])
        await Timer(intval * burst, 'ns')

async def testcase_recv_n_pkts(virtq, n, extra_flags=0):
    if virtq.qtype != VirtqType.NETRX:
        raise ValueError(f"recv pkts on qtype {virtq.qtype}")

    lastPrintTm = int(time.time())
    virtq.nrTestPkts = n

    while virtq.nrRxPkts != virtq.nrTestPkts:
        currTm = int(time.time())
        if currTm - lastPrintTm > 2:
            lastPrintTm = currTm
            virtq.mylog(f"wait to recv {virtq.nrTestPkts} pkts, have receved {virtq.nrRxPkts} pkts", force=True)
        await Timer(100, 'ns')

@testcase_decorator
async def testcase_send_1_pkts(virtq):
    await testcase_send_n_pkts(virtq, 1)

@testcase_decorator
async def testcase_send_4_pkts(virtq):
    await testcase_send_n_pkts(virtq, 4)

@testcase_decorator
async def testcase_send_a_little_pkts(virtq):
    await testcase_send_n_pkts(virtq, random.randint(virtq.qlen,2*virtq.qlen))

@testcase_decorator
async def testcase_recv_1_pkts(virtq):
    await testcase_recv_n_pkts(virtq, 1)

@testcase_decorator
async def testcase_recv_a_little_pkts(virtq):
    await testcase_recv_n_pkts(virtq, random.randint(virtq.qlen,2*virtq.qlen))

@testcase_decorator
async def testcase_desc_next_idx_err(virtq):
    virtq.expErr = True
    virtq.expErrCode = 0x1
    virtq.disableInt = True
    virtq.expStop = True

    writeBit = 0
    if virtq.qtype == VirtqType.NETRX:
        writeBit = VirtqDescFlagBit.WRITE_BIT

    desc = VirtqDesc(addr=0, pktlen=1, flags=VirtqDescFlagBit.NEXT_BIT | writeBit, next=virtq.qlen+1)
    await virtq.fillAvailDescChain([desc], [0])
    await virtq.notify()

@testcase_decorator
async def testcase_chain_err(virtq):
    # chain len > 128
    virtq.expErr = True
    virtq.expErrCode = 0x2
    virtq.disableInt = True
    virtq.expStop = True

    writeBit = 0
    if virtq.qtype == VirtqType.NETRX:
        writeBit = VirtqDescFlagBit.WRITE_BIT

    descs = []
    IDs = []
    for i in range(0,129):
        desc = VirtqDesc(addr=0, pktlen=1, flags=VirtqDescFlagBit.NEXT_BIT | writeBit, next=i+1)
        descs.append(desc)
        IDs.append(i)

    desc = VirtqDesc(addr=0, pktlen=1, flags=writeBit, next=0)
    descs.append(desc)
    IDs.append(129)
    await virtq.fillAvailDescChain(descs, IDs)
    await virtq.notify()

@testcase_decorator
async def testcase_desc_flag_write_bit_err(virtq):
    virtq.expErr = True
    virtq.expErrCode = 0x4
    virtq.disableInt = True
    virtq.expStop = True

    if virtq.qtype == VirtqType.NETTX:
        # write_only bit == 1
        desc = VirtqDesc(addr=0, pktlen=1, flags=VirtqDescFlagBit.WRITE_BIT)
    elif virtq.qtype == VirtqType.NETRX:
        # write_only bit == 0
        desc = VirtqDesc(addr=0, pktlen=1, flags=0)
    else: # BLK
        raise ValueError(f"testcase_desc_flag_write_bit_err on qtype {virtq.qtype} not applicable")

    await virtq.fillAvailDescChain([desc], [0])
    await virtq.notify()

@testcase_decorator
async def testcase_desc_flag_indirect_bit_err(virtq):
    virtq.expErr = True
    virtq.expErrCode = 0x4
    virtq.disableInt = True
    virtq.expStop = True
    desc = VirtqDesc(addr=0, pktlen=1, flags=VirtqDescFlagBit.INDIRECT_BIT)

    await virtq.fillAvailDescChain([desc], [0])
    await virtq.notify()

@testcase_decorator
async def testcase_desc_data_len_large_err(virtq):
    # data len > config len
    virtq.expErr = True
    virtq.expErrCode = 0x8
    virtq.disableInt = True

    if virtq.qtype == VirtqType.NETRX:
        raise ValueError(f"testcase_desc_data_len_large_err on qtype {virtq.qtype} not applicable")

    if virtq.qtype == VirtqType.BLK:
        virtq.expStop = True
        # TODO
        raise ValueError(f"testcase_desc_data_len_err on qtype {virtq.qtype} TODO")
    desc = VirtqDesc(addr=0, pktlen=65536, flags=0)
    await virtq.fillAvailDescChain([desc], [0])
    await virtq.notify()

@testcase_decorator
async def testcase_desc_data_len_0_err(virtq):
    virtq.expErr = True
    virtq.expErrCode = 0x8
    virtq.disableInt = True
    virtq.expStop = True

    if virtq.qtype == VirtqType.NETTX:
        raise ValueError(f"testcase_desc_data_len_0_err on qtype {virtq.qtype} not applicable")

    if virtq.qtype == VirtqType.BLK:
        # TODO
        raise ValueError(f"testcase_desc_data_len_err on qtype {virtq.qtype} TODO")

    desc = VirtqDesc(addr=0, pktlen=0, flags=0)
    await virtq.fillAvailDescChain([desc], [0])
    await virtq.notify()

@testcase_decorator
async def testcase_ring_id_err(virtq):
    # ring idx > qsize
    virtq.expErr = True
    virtq.expErrCode = 0x10
    virtq.disableInt = True
    virtq.expStop = True

    await virtq.writeNextAvailElem(virtq.qlen + 1)
    await virtq.notify()

@testcase_decorator
async def testcase_idx_err(virtq):
    # The difference between the two read pointers is greater than qsize
    virtq.expErr = True
    virtq.expErrCode = 0x20
    virtq.disableInt = True
    virtq.expStop = True

    writeBit = 0
    if virtq.qtype == VirtqType.NETRX:
        writeBit = VirtqDescFlagBit.WRITE_BIT

    region = self.tb.mem.alloc_region(1)
    desc = VirtqDesc(addr=region.get_absolute_address(0), pktlen=1, flags=writeBit)
    await virtq.fillAvailDescChain([desc], [0])
    await virtq.notify()

    def destructor():
        virtq.tb.mem.free_region(virtq.testcase_destructor_arg)
    virtq.testcase_destructor = destructor
    virtq.testcase_destructor_arg = region

    ringID = virtq.qlen + 2
    await self.AvailRing.write(2, ringID.to_bytes(2, byteorder='little'))


@testcase_decorator
async def testcase_netrx_be_len_err(virtq):
    virtq.expErr = True
    virtq.expErrCode = 0x80
    virtq.disableInt = True

    if virtq.qtype != VirtqType.NETRX:
        raise ValueError(f"testcase_netrx_be_len_err on qtype {virtq.qtype}")

    region = self.tb.mem.alloc_region(1)
    desc = VirtqDesc(addr=region.get_absolute_address(0), pktlen=1, flags=VirtqDescFlagBit.WRITE_BIT)
    await virtq.fillAvailDescChain([desc], [0])
    await virtq.notify()

    def destructor():
        virtq.tb.mem.free_region(virtq.testcase_destructor_arg)

    virtq.testcase_destructor = destructor
    virtq.testcase_destructor_arg = region


@testcase_decorator
async def testcase_random_start_stop(virtq):
    virtq.disableChecker = True
    random_list = [random.randint(10, 100) for _ in range(random.randint(10, 100))]
    for i in random_list:
        if virtq.qtype == VirtqType.NETTX:
            await testcase_send_n_pkts(virtq, i)
        elif virtq.qtype == VirtqType.NETRX:
            await testcase_recv_n_pkts(virtq, i)
        else: # BLK
            raise ValueError(f"testcase_random_start_stop on qtype {virtq.qtype} TODO")

        await virtq.reset()
        '''
        if virtq.qtype == VirtqType.NETTX:
            (rd_desc_num_nettx,rd_data_num_nettx,wr_used_num_nettx,wr_msix_num_nettx) = await virtq.tb.get_nettx_stop_info(virtq.qtype,virtq.qid)
            await Timer(200, 'ns')
            (dfx_rd_desc_num_nettx,dfx_rd_data_num_nettx,dfx_wr_used_num_nettx,dfx_wr_msix_num_nettx) = await virtq.tb.rd_dfx_nettx_stop_info(virtq.qtype,virtq.qid)
            print(121212,rd_desc_num_nettx,rd_data_num_nettx,wr_used_num_nettx,wr_msix_num_nettx,dfx_rd_desc_num_nettx,dfx_rd_data_num_nettx,dfx_wr_used_num_nettx,dfx_wr_msix_num_nettx)
            assert int(rd_desc_num_nettx) == int(dfx_rd_desc_num_nettx)
            assert int(rd_data_num_nettx) == int(dfx_rd_data_num_nettx)
            assert int(wr_used_num_nettx) == int(dfx_wr_used_num_nettx)
            assert int(wr_msix_num_nettx) == int(dfx_wr_msix_num_nettx)

        elif virtq.qtype == VirtqType.NETRX:
            (rd_desc_num_netrx,wr_data_num_netrx,wr_used_num_netrx,wr_msix_num_netrx) = await virtq.tb.get_netrx_stop_info(virtq.qtype,virtq.qid)
            await Timer(200, 'ns')
            (dfx_rd_desc_num_netrx,dfx_wr_data_num_netrx,dfx_wr_used_num_netrx,dfx_wr_msix_num_netrx) = await virtq.tb.rd_dfx_netrx_stop_info(virtq.qtype,virtq.qid)
            print(121312313,rd_desc_num_netrx,wr_data_num_netrx,wr_used_num_netrx,wr_msix_num_netrx,dfx_rd_desc_num_netrx,dfx_wr_data_num_netrx,dfx_wr_used_num_netrx,dfx_wr_msix_num_netrx)
            assert int(rd_desc_num_netrx) == int(dfx_rd_desc_num_netrx)
            assert int(wr_data_num_netrx) == int(dfx_wr_data_num_netrx)
            assert int(wr_used_num_netrx) == int(dfx_wr_used_num_netrx)
            assert int(wr_msix_num_netrx) == int(dfx_wr_msix_num_netrx)

        else :
           
            (rd_desc_num_blk,rd_data_num_blk,wr_data_num_blk,wr_used_num_blk,wr_msix_num_blk) = await virtq.tb.get_blk_stop_info(virtq.qtype,virtq.qid)
            await Timer(200, 'ns')
            (dfx_rd_desc_num_blk,dfx_rd_data_num_blk,dfx_wr_data_num_blk,dfx_wr_used_num_blk,dfx_wr_msix_num_blk) = await virtq.tb.rd_dfx_blk_stop_info(virtq.qtype,virtq.qid)
            assert int(rd_desc_num_blk) == int(dfx_rd_desc_num_blk)
            assert int(rd_data_num_blk) == int(dfx_rd_data_num_blk)
            assert int(wr_data_num_blk) == int(dfx_wr_data_num_blk)
            assert int(wr_used_num_blk) == int(dfx_wr_used_num_blk)
            assert int(wr_msix_num_blk) == int(dfx_wr_msix_num_blk)
        
        (cmd_ack,used_ptr) =  await virtq.tb.qset_cmd_ack(virtq.qtype,virtq.qid)
        while cmd_ack == 0 :
            await Timer(20, 'ns')
            (cmd_ack,used_ptr) =  await virtq.tb.qset_cmd_ack(virtq.qtype,virtq.qid)
        '''
        await virtq.start()


@testcase_decorator
async def testcase_crazy_start_stop(virtq):
    virtq.nrTestPkts = 0
    for i in range(0, 10000):
        await virtq.stop()
        await Timer(12, 'ns')
        await virtq.start()

class TestMode:
    ALL_CASE = 0x0
    CHOOSE_ONE = 0x1 

async def startAllTestOnVirtq(virtq, testNum, testCases=[testcase_send_1_pkts]):
    log = logging.getLogger("cocotb.tb")
    for i in range(testNum):
        for test in testCases:
            log.debug(f"{i}-th test on q{virtq.qid}")
            log.debug(f"\t[q{virtq.qid}]: testcase:     {test.__name__}")
            log.debug(f"\t[q{virtq.qid}]: qsize:        {virtq.qlen}")
            log.debug(f"\t[q{virtq.qid}]: mtu:          {virtq.mtu}")
            await test(virtq)

workers = []

async def startTest(tb, testNum=1, qnum=32, qtype=VirtqType.NETTX, txqTestCases=[testcase_send_a_little_pkts], rxqTestCases=[testcase_recv_a_little_pkts], mode=TestMode.CHOOSE_ONE, MultiQType=True):
    register_net_handelr(tb, VirtqType.NETTX)
    register_net_handelr(tb, VirtqType.NETRX)

    if MultiQType or qtype == VirtqType.NETRX:
        global allRxVirtqs
        allRxVirtqs.clear()
        qids = random.sample(range(0, 256), qnum)
        qlens = [random.choice([1 << i for i in range(8,11)]) for _ in range(qnum)]
        mtus = random.sample(range(0, 65536), qnum)
        for i in range(qnum):
            allRxVirtqs[qids[i]] = Virtq(tb, qids[i], VirtqType.NETRX, qlens[i], mtus[i], gen=0)

        rxqCaseIdx = 0
        for virtq in allRxVirtqs.values():
            testNum = random.randint(1, testNum)
            if mode == TestMode.ALL_CASE:
                workers.append(cocotb.start_soon(startAllTestOnVirtq(virtq, testNum, rxqTestCases)))
            elif mode == TestMode.CHOOSE_ONE:
                workers.append(cocotb.start_soon(startAllTestOnVirtq(virtq, testNum, rxqTestCases[rxqCaseIdx:rxqCaseIdx + 1])))
                rxqCaseIdx += 1
                rxqCaseIdx %= len(rxqTestCases)


    if MultiQType or qtype == VirtqType.NETTX:
        global allTxVirtqs
        allTxVirtqs.clear()
        qids = random.sample(range(0, 256), qnum)
        qlens = [random.choice([1 << i for i in range(8,11)]) for _ in range(qnum)]
        mtus = random.sample(range(0, 65536), qnum)
        for i in range(qnum):
            allTxVirtqs[qids[i]] = Virtq(tb, qids[i], VirtqType.NETTX, qlens[i], mtus[i], gen=0)

        txqCaseIdx = 0
        for virtq in allTxVirtqs.values():
            testNum = random.randint(1, testNum)
            if mode == TestMode.ALL_CASE:
                workers.append(cocotb.start_soon(startAllTestOnVirtq(virtq, testNum, txqTestCases)))
            elif mode == TestMode.CHOOSE_ONE:
                workers.append(cocotb.start_soon(startAllTestOnVirtq(virtq, testNum, txqTestCases[txqCaseIdx:txqCaseIdx + 1])))
                txqCaseIdx += 1
                txqCaseIdx %= len(txqTestCases)

    for worker in workers:
        await worker.join()

    print("startTest exit")
