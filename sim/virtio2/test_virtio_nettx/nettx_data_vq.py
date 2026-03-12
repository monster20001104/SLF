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


class ERR_CODE  :
    VIRTIO_ERR_CODE_NONE                                        = 0x00
    VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR                            = 0x01
    VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX                         = 0x02
    VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE                           = 0x03
    VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR                          = 0x04
    VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE                 = 0x10
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE            = 0x11
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE       = 0x12
    VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT                  = 0x13
    VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO                  = 0x14
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC                = 0x15
    VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO              = 0x16
    VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE               = 0x17
    VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN                      = 0x18
    VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR                           = 0x19
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE              = 0x1a
    VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE              = 0x1b
    VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR                           = 0x20
    VIRTIO_ERR_CODE_NETTX_PCIE_ERR                              = 0x30
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE             = 0x40
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE        = 0x41
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE   = 0x42
    VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT              = 0x43
    VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO              = 0x44
    VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC            = 0x45
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO             = 0x46
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE             = 0x47
    VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR                       = 0x48
    VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR                           = 0x50

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
    def __init__(self,tb,pktlen=None,set_chain = None,set_tlp_err = None,q_err_code = None ,qid = None):

        if set_chain == 1 :
            if pktlen is None:
                self.pktlen = random.randint(1, 65535)
            else:
                self.pktlen = pktlen
        else :
            if pktlen is None:
                self.pktlen = random.randint(1, 1500)
            else:
                self.pktlen = pktlen
        print("len is %d" %(self.pktlen))
            
        self.region = tb.mem.alloc_region( self.pktlen ,bdf = tb.bdf_arrary[qid])
        self.pktbase = self.region.get_absolute_address(0)
        self.pktlen = self.pktlen
        self.tb = tb
        self.q_err_code = q_err_code
        self.set_tlp_err = set_tlp_err
    
    async def _write_data(self):
        if(self.set_tlp_err == 1) :
            if(random.randint(0,100) < 50):
                await self.q_err_code.put(ERR_CODE.VIRTIO_ERR_CODE_NETTX_PCIE_ERR)     
                byte_arr = bytearray((i % 256) for i in range(self.pktlen))
                await self.region.write(0, byte_arr,defect_injection = 1)
            else :
                await self.q_err_code.put(0)     
                byte_arr = bytearray((i % 256) for i in range(self.pktlen))
                await self.region.write(0, byte_arr)
        else :   
                byte_arr = bytearray((i % 256) for i in range(self.pktlen))
                await self.region.write(0, byte_arr)
            
            

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
        self.random_mtu = False
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
                    if random.randint(1, 100) < 30:
                        self.mtu = random.randint(1, 32)
                    elif(random.randint(1, 100) < 60):
                        self.mtu = random.randint(1000, 5000)
                    else :
                        self.mtu = random.randint(65400, 65535)


                if (left_data_len <= self.mtu) or ((not allowLongChain) and (chainLen == 127)):
                    desc = VirtqDesc(addr=(virtqPkt.pktbase + used_data_len),
                                     pktlen=left_data_len, flags=extra_flags)
                else:
                    desc = VirtqDesc(addr=(virtqPkt.pktbase + used_data_len),
                                     pktlen=random.randint(1, self.mtu),
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
    def __init__(self, tb, qid, qszWidth, mtu, random_mtu,set_chain,set_tlp_err,testType=TestType.NETTX):
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.tb = tb
        self.qid = qid
        self.qszWidth = qszWidth
        self.qsz = 2 ** qszWidth

        self.mtu = mtu
        self.random_mtu = random_mtu
        self.is_start = False
        self.q_err_code = Queue(maxsize = 65536)

        self.gen = 0
        self.occupy = 0
        self.drop_pkt_checkout = 0
        self.region_q=  deque()
        self.set_chain = set_chain
        self.set_tlp_err = set_tlp_err

        # desc_base.write(address, data)
        # desc_base.get_absolute_address(0)
        self.desc_base = self.tb.mem.alloc_region(16 * self.qsz)  # 默认对齐么 ???
        self.id_allocator = set(range(0, self.qsz))
        self.saved_desc = deque()
        self.saved_ring_id = deque()
        self.record_desc = deque(maxlen=(2 * self.qsz))
        self.chain_len = deque()
        self.exit = Event()
        self.nrTestPkts = 0
        self.nrRetrievePkts = 0
        self.nrSendPkts = 0
        self.nrSendDesc = 0
        self.nrRetrieveDesc = 0
        self.workDone = False
        self.exitDirect = False
        self.expectError = False
        self.disableLog = False
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

        #if (not self.disableLog) or force:
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
            #self.mylog(f"no available id")
            await Timer(1000, 'ns')
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


    async def write_desc(self, desc, idx):
        self.mylog(f"desc id: {idx}")
        self.print_desc(desc)        
        self.nrSendDesc += 1   
        await self.tb._wr_desc(self.qid,desc.addr,desc.pktlen,(desc.flags & VirtqFlagBit.NEXT_BIT),(desc.flags & VirtqFlagBit.WRITE_BIT),(desc.flags & VirtqFlagBit.WRITE_BIT),desc.next)
        #await self.desc_base.write(int(idx * (VirtqDesc.width / 8)), data)

    async def start(self,need_config):
        if self.is_start:
            self.mylog(f"start q {self.qid} already start")
            return

        maxSegLen = 65536 * 2
        if self.invalidMaxSegLen:
            maxSegLen = 2
        if(need_config == 1):
            await self.tb.config(self.qid, self.desc_base.get_absolute_address(0),self.qid,
                             self.qszWidth, self.qid, self.qid, self.gen, maxSegLen)
        
        #await self.tb._config_start_stop(qid = self.qid,ptr = random.randint(0, 65535),start = 1,stop = 0)
        self.is_start = True
        await Timer(120, 'ns')
        await self.notify()
        #await self.tb._notify(self.qid)
        self.mylog(f"start q")

    async def stop(self):
        if not self.is_start:
            self.mylog(f"stop q {self.qid} already stop")
            return
        #await self.tb._config_start_stop(qid = self.qid,ptr = random.randint(0, 65535),start = 0,stop = 1)

        self.mylog(f"stop q")
        self.mylog(f"\tnumber of remaining in saved_desc is {len(self.saved_desc)}")
        self.mylog(f"\tnumber of remaining in saved_ring_id is {len(self.saved_ring_id)}")

        #self.saved_desc.clear()
        #self.record_desc.clear()
        #self.saved_ring_id.clear()
        #self.chain_len.clear()

       # self.id_allocator.clear()
       # self.id_allocator.update(range(0, self.qsz))
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
        await self.start(need_config = 0)


    async def notify(self):
        self.nrTotalNotify += 1

        #await Timer(1000, 'ns')

    async def tx_desc_chain(self, descs,region):
        first_idx = await self.alloc_id()
        prev_idx = first_idx
        self.chain_len.append(len(descs.descs))
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
            
        await self.tb._wr_ring_id(self.qid, first_idx)
        #await self.region_q.append(region)

    async def tx_packet(self, pkt, extra_flags=0):
        needHdr = False
        if self.testType == TestType.NETRX:
            extra_flags = extra_flags | VirtqFlagBit.WRITE_BIT
        elif self.testType == TestType.BLK:
            needHdr = True
        descs = VirtqDescChain(pkt, self.mtu, self.random_mtu, extra_flags, needHdr=needHdr)
        self.nrSendPkts += 1
        await self.tx_desc_chain(descs,pkt.region)
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
        
    '''    
    async def test_start_stop(self,test_time):
        for i in range (test_time):
            if(random.randint(0,100) <10):
                await Timer(5000, 'ns')
            await self.stop()
            await Timer(12, 'ns')
            
            stop_ok = 0
            while (self.occupy == 1):
                await Timer(4, 'ns')
            while(stop_ok == 0):
                (stop_ok) = await self.tb._rd_stop_info(self.qid)
                
                if(stop_ok == 1  ):
                    await Timer(500, 'ns')
                    (stop_ok) = await self.tb._rd_stop_info(self.qid)
                    assert stop_ok == 1
                else :
                    await Timer(12, 'ns')
                    

            await self.tb.config_gen(self.qid,self.gen)     
            await self.start(need_config = 0)
            await Timer(20, 'ns')

        '''

async def testcase_send_n_pkts(virtq, n, extra_flags=0):
    virtq.nrTestPkts = n
    cnt = 0;
    virtq.mylog(f"wait to send {virtq.nrTestPkts} pkts", force=True)
    
    pkts = []
    for _ in range(n):
        #pkts.append(VqPkt)
        VqPkt = VirtqPkt(tb = virtq.tb,set_chain = virtq.set_chain,set_tlp_err = virtq.set_tlp_err,q_err_code = virtq.q_err_code,qid = virtq.qid)
        await VqPkt._write_data()
        await virtq.tx_packet_burst([VqPkt], extra_flags)
        await virtq.notify()
        await virtq.tb._rcv_notify(virtq.qid)
        

    #await virtq.tx_packet_burst(pkts, extra_flags)
    virtq.nrEmptyNotify += 1
    #await virtq.notify()

def testcase_decorator(func):
    @wraps(func)
    async def wrapper(*args, **kwargs):
        virtq = args[0]

        virtq.mylog(f"start test {func.__name__}", force=True)
        await virtq.reset()
        if virtq.testType == TestType.NETRX:
            cocotb.start_soon(virtq.pkt_generator())
            
        #cocotb.start_soon(virtq.test_start_stop(100))

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
async def testcase_send_a_little_pkts(virtq):
   await testcase_send_n_pkts(virtq, random.randint(virtq.qsz,2*virtq.qsz))
   #await testcase_send_n_pkts(virtq, random.randint(100,200))



@testcase_decorator
async def testcase_crazy_start_stop(virtq):
    virtq.exitDirect = True
    for i in range(0, 10000):
        await virtq.test_start_stop()



async def startAllTestOnVirtq(virtq, testNum, testCases=[testcase_send_a_little_pkts]):
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
    data_checkout = 0
    
    while True: 
        chain_num = 0;          
        (force_down,err_info,global_qid,len,ring_id,used_idx) = await tb._checkout_used_info()   
        assert ring_id == used_idx
        typ = int(global_qid/256 )
        assert typ == 0
        qid = int(global_qid%256)
        used_len = len
        virtq = virtqs[qid]
        virtq.occupy = 1
        print(1111,qid)
        if(virtq.set_tlp_err == 1):
            err_code = await virtq.q_err_code.get()
            if( err_code != int(err_info & 0x7f) ):
                print(err_code,int(err_info))
            assert err_code == int(err_info & 0x7f)
            if(err_info > 0):
                assert 0x80 == int(err_info & 0x80)
        
        elif tb.set_desc_err[qid] == 1 :
            if(int(err_info) > 0):
                assert int(err_info & 0x7f) == 0x18
                assert 0x80 == int(err_info & 0x80)
        elif tb.set_force_down[qid] == 1:
                if(int(force_down) == 1):
                    assert int(force_down) == 1

        else :
            assert int(err_info) == 0
            assert int(force_down) == 0

                  
        chain_len = virtq.chain_len.popleft()
        if(chain_num == 0):
            saved_ring_id = virtq.get_saved_ring_id()
            virtq.nrRetrievePkts += 1
            if(saved_ring_id != ring_id):
                print(qid,saved_ring_id,ring_id)
            assert  saved_ring_id == ring_id
            chain_num = chain_num + 1           
        while(chain_num != chain_len):
            saved_ring_id = virtq.get_saved_ring_id()
            chain_num = chain_num + 1
   
   
        
        chain_datalen = 0 
        get_pack_len = 0
        savedDesc = virtq.get_saved_desc()
        virtq.nrRetrieveDesc += 1
        while (savedDesc.flags & VirtqFlagBit.NEXT_BIT == 1):
                chain_datalen = chain_datalen + savedDesc.pktlen
                savedDesc = virtq.get_saved_desc()
                virtq.nrRetrieveDesc += 1

        chain_datalen = chain_datalen + savedDesc.pktlen   
        if(force_down == 1 and used_len == 0):
            pass

        elif(force_down == 1 and used_len > 0):
                (len,qid_ctrl,gen,tso_en,csum_en,err) = await tb._get_ctrl()
                assert err > 0
                eop =0
                while eop == 0:
                    (data,sop,eop,sty,mty) = await tb._get_data() 

        elif  int(err_info & 0x7f) == ERR_CODE.VIRTIO_ERR_CODE_NETTX_PCIE_ERR  or int(err_info) == 0:
            (len,qid_ctrl,gen,tso_en,csum_en,err) = await tb._get_ctrl() 
            get_pack_len = int(len)
            if int(err_info & 0x7f) == ERR_CODE.VIRTIO_ERR_CODE_NETTX_PCIE_ERR :
                assert int(err) > 0

                 
            if(chain_datalen != get_pack_len ):
                print(qid,chain_datalen,get_pack_len)
            assert chain_datalen == get_pack_len
            assert qid == qid_ctrl  
        
            data_len = 0;
            cnt_32byte = int(get_pack_len /32)
            for i in range (cnt_32byte) :
                (data,sop,eop,sty,mty) = await tb._get_data()
                if (sop == 1 and eop == 0)  :
                    data_len = data_len + 32 - sty
                elif( sop == 1 and eop == 1):
                    data_len = data_len + 32 - sty - mty
                elif(sop == 0 and eop == 1):
                    data_len = data_len + 32  - mty 
                else :
                    data_len = data_len + 32
                if(err_info == 0) :
                    for j in range (32):
                        if(data[j] != data_checkout):
                           print(qid,i,j,data[j], data_checkout)
                        assert int(data[j]) == data_checkout              
                        data_checkout = int((data_checkout + 1)%256)


            rest_len = int(get_pack_len%32)
            if(rest_len>0):
                (data,sop,eop,sty,mty) = await tb._get_data()
                if (sop == 1 and eop == 0)  :
                    data_len = data_len + 32 - sty
                elif( sop == 1 and eop == 1):
                    data_len = data_len + 32 - sty - mty
                elif(sop == 0 and eop == 1):
                    data_len = data_len + 32  - mty 
                else :
                    data_len = data_len + 32
                
                if(err_info == 0):
                    for i in range (rest_len):
                        if(data[i] != data_checkout):
                            print(qid,i,data[i], data_checkout)
                        assert int(data[i]) == data_checkout
                        data_checkout = int((data_checkout + 1)%256)
            if(data_len != get_pack_len) :
                print(qid,data_len,get_pack_len)   
            assert data_len == get_pack_len

        #region = virtq.region_q.popleft()
        #tb.mem.free_region(region) 
         
        virtq.occupy = 0
        data_checkout = 0
        #print(virtq.workDone ,virtq.nrTestPkts ,virtq.nrRetrievePkts,virtq.exit.is_set(),virtq.exitDirect) 
        print(888888,virtq.workDone,virtq.nrTestPkts,virtq.nrRetrievePkts,virtq.nrSendDesc,virtq.nrRetrieveDesc,virtq.exit.is_set(),virtq.exitDirect)
        if (virtq.workDone or virtq.nrTestPkts == virtq.nrRetrievePkts)  and virtq.nrSendDesc == virtq.nrRetrieveDesc:
            if (not virtq.exit.is_set()) and (not virtq.exitDirect):
                virtq.mylog("set exit")
                virtq.exit.set()
                await Timer(10, 'ns')





async def startTest(tb, qnum,qids, testNum=1, testType=TestType.NETTX, have_chain = 0,set_tlp_err = None,testCases=[testcase_send_a_little_pkts], mode=TestMode.CHOOSE_ONE):
    virtqs = {}
    #if(testType==TestType.NETTX):
    #  qids = random.sample(range(0, 256), qnum)
    qszs = [random.choice([i for i in range(8,9)]) for _ in range(qnum)]
    mtus = random.sample(range(0, 1500), qnum)
    random_mtus = [random.choice([True, False]) for _ in range(qnum)]

    if have_chain == 0 :
        set_chain = [0 for i in range(len(qids))]
    elif have_chain == 1:
        set_chain = [1 for i in range(len(qids))]
    else :
        set_chain = [0 for i in range(len(qids))]
        for i in range(len(qids)):
            set_chain[i] = random.randint(0,1)
        
        
    for i in range(qnum):
        virtqs[qids[i]] = Virtq(tb, qids[i], qszs[i], mtus[i], random_mtus[i],set_chain[i],set_tlp_err[i], testType)


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
