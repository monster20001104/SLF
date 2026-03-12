#!/usr/bin/env python3
################################################################################
#  文件名称 : test_beq_rxq_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/01/08
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  01/08     Joe Jiang   初始化版本
################################################################################
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator


import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout, TriggerException
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory
from cocotb.handle import Force, Release

from defines import *

sys.path.append('../common')
from bus.beq_data_bus import BeqBus
from drivers.beq_data_bus import BeqRxqMaster
from bus.tlp_adap_dma_bus import DmaReadBus, DmaWriteBus
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace, MemoryRegion
from enum import Enum, unique

from beq_ctx_ctrl import *
from beq_desc_eng import *
from beq_pmd_behavior import *
from beq_error_ctrl import *
from queue import Empty  
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster


class data_element(NamedTuple):
    qid: int
    data: bytearray
    user0: int
    user1: int

#Generate 4 unique random IDs within a specified range
def gen_id(num, start, end):
    id_array = []  
    rng = [i for i in range(start, end)] #start include，end not include
    for i in range(4):  
        idx = random.randint(0, len(rng)-1) 
        id_array.append(rng[idx]) 
        del rng[idx]  #delete,avoid repeated
    return id_array

#def gen_data(len):
    #return os.urandom(len)
#    data = b""  #empty string
#    cnt = 0
#    while cnt < len:
#        end = min(256, len-cnt)
#        data = data + bytearray([i for i in range(0, end)])  
#        cnt = cnt + end  
#    return data

def gen_data(length):
    data = bytearray()
    cnt = 0
    while cnt < length:
        chunk_size = min(256, length - cnt)
        chunk = bytearray([random.randint(0, 255) for _ in range(chunk_size)])
        data += chunk
        cnt += chunk_size
    return bytes(data)


async def packet_gen(chn, ref_queues, qid_pkt_counts, tb, error_ctrl=None, max_pkt_len=12288):
    tb.log.info(f"packet_gen start")
    
    if error_ctrl is None:
        error_ctrl = beq_error_ctrl()

    #for i in range(max_seq):
    for qid, count in qid_pkt_counts.items():
        tb.log.info(f"start qid={qid}gen {count} pkts")
        for i in range(count):
        #qid = random.choice(qid_array)
            user0 = i
            #user1 = random.randint(1, 2**64-1) #avoid 0
            segment_size = tb.get_segment_size(qid)  #get segment size
            tb.log.info("pkt_gen: segment_size = {}".format(segment_size))
            
            #drop_err and rd_ndesc>24
            if ((i>=400) and (i<600) and error_ctrl.should_enter_fit_mode() and error_ctrl.select_error_type() == 'drop_err' and error_ctrl.select_drop_subtype() == DropErrorType.RD_NDESC_OVERFLOW):
                #only segment 512
                pkt_len = 25 * segment_size 
                tb.log.debug("abnormal packet gen pkt_len = {} segment_size = {}".format(pkt_len, segment_size))
            # if drop_err and drop_mode == 1,gen 64bytes pkt
            elif (error_ctrl.should_enter_fit_mode() and error_ctrl.select_error_type() == 'drop_err' and error_ctrl.select_drop_subtype() == DropErrorType.DROP_MODE):
                pkt_len = 64    
            else: 
                pkt_len = random.randint(1, max_pkt_len)
            
            data = gen_data(pkt_len)

            sty = random.randint(0,31)
            #if random.random() < 0.5:
            #    sty = 12
            #else:
            #    sty = 0
    
            tb.log.info(f"packet_gen qid={qid}")
            user1 =  pkt_len #avoid 0
            await chn.send(qid, data, user0, user1, sty)  
            elem = data_element(qid, data, user0, user1)
            await ref_queues[qid].put(elem)  
            tb.log.info("packet_gen end qid={} pkt_len={} pkt_num={}".format(qid, pkt_len, i))
        

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.mem = Pool(None, 0, size=2**64, min_alloc=64)
        self.csrBusMaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)
        self.emu2beq   = BeqRxqMaster(BeqBus.from_prefix(dut, "emu2beq")  , dut.clk, dut.rst)
        self.net2beq   = BeqRxqMaster(BeqBus.from_prefix(dut, "net2beq")  , dut.clk, dut.rst)
        self.blk2beq   = BeqRxqMaster(BeqBus.from_prefix(dut, "blk2beq")  , dut.clk, dut.rst)
        self.sgdma2beq = BeqRxqMaster(BeqBus.from_prefix(dut, "sgdma2beq"), dut.clk, dut.rst)
        self.net_qid2bidTbl = Qid2BidRdTbl(Qid2BidRdReqBus.from_prefix(dut, "net_qid2bid"), Qid2BidRdRspBus.from_prefix(dut, "net_qid2bid"), None, dut.clk, dut.rst)
        self.blk_qid2bidTbl = Qid2BidRdTbl(Qid2BidRdReqBus.from_prefix(dut, "blk_qid2bid"), Qid2BidRdRspBus.from_prefix(dut, "blk_qid2bid"), None, dut.clk, dut.rst)
        self.dropModeTbl = DropModeRdTbl(DropModeRdReqBus.from_prefix(dut, "drop_mode"), DropModeRdRspBus.from_prefix(dut, "drop_mode"), None, dut.clk, dut.rst)
        self.segmentSizeRdTbl = SegmentSizeRdTbl(SegmentSizeRdReqBus.from_prefix(dut, "segment_size"), SegmentSizeRdRspBus.from_prefix(dut, "segment_size"), None, dut.clk, dut.rst)
        self.rdNdescReq = RdNdescReqSink(RdNdescReqBus.from_prefix(dut, "rd_ndesc_req"), dut.clk, dut.rst)
        self.rdNdescRsp = RdNdescRspSource(RdNdescRspBus.from_prefix(dut, "rd_ndesc_rsp"), dut.clk, dut.rst)
        self.dmaWrDataIf = DmaRam(DmaWriteBus.from_prefix(dut, "dma_data"), None, dut.clk, dut.rst, mem=self.mem)
        self.ringInfoRdTbl = RingInfoRdTbl(RingInfoRdReqBus.from_prefix(dut, "ring_info_rd"), RingInfoRdRspBus.from_prefix(dut, "ring_info_rd"), None, dut.clk, dut.rst)
        self.ringCiTbl = RingCiTbl(RingCiRdReqBus.from_prefix(dut, "ring_ci"), RingCiRdRspBus.from_prefix(dut, "ring_ci"), RingCiWrBus.from_prefix(dut, "ring_ci"), dut.clk, dut.rst)
        self.doing = True
        self.beq_ctx_ctrl = beq_ctx_ctrl(self.mem, dut.clk, self.net_qid2bidTbl, self.blk_qid2bidTbl, self.dropModeTbl, self.segmentSizeRdTbl, self.ringInfoRdTbl, self.ringCiTbl, self.csrBusMaster)
        self.beq_pmd = beq_pmd_behavior(self.mem, self.beq_ctx_ctrl)
        self.beq_desc_eng = beq_desc_eng(dut.clk, self.beq_pmd.ring_queues, self.beq_ctx_ctrl, self.rdNdescReq, self.rdNdescRsp)
        self.ref_queues = {}
        self.error_ctrl = beq_error_ctrl()
        self.stop_workers = False
    
    def stop_worker(self):
        self.stop_workers = True

    def stop(self):
        self.doing = False

    async def cycle_reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await Timer(2, "us")

    def set_idle_generator(self, generator=None):
        self.emu2beq.set_idle_generator(generator)
        self.net2beq.set_idle_generator(generator)
        self.blk2beq.set_idle_generator(generator)
        self.sgdma2beq.set_idle_generator(generator)
        self.rdNdescRsp.set_idle_generator(generator)
        self.dmaWrDataIf.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        self.rdNdescReq.set_backpressure_generator(generator)
        self.dmaWrDataIf.set_backpressure_generator(generator)

    def get_segment_size(self, qid):
        if qid not in self.beq_pmd.beqs:
            raise ValueError(f"Queue {qid} not found")
      
        segment_sz = self.beq_pmd.beqs[qid].mbuf_sz
        self.log.debug(f"get_segment_size Q {qid} {segment_sz}")
        return segment_sz

    def _final_report(self, qid, total, hw_drops, processed):
        #gen final report
        self.log.info(
            f"=== Q{qid} ===\n"
            f"total pkts: {total}\n"
            f"hw_drop_cnt: {hw_drops}\n"
            f"recv_pkts: {processed}\n"
            "=================="
        )

    async def worker(self, qid, max_seq):
        #init cnt
        total_pkts = max_seq      
        recv_pkts = 0       
        hw_drop_cnt = 0 
        hw_drop_cnt_1 = 0       
        processed_pkts = 0     
        drop_mode = 0

        beq_depth = random.choice(beq_q_depth_type_list)
        self.log.debug(f"worker beq_depth {beq_depth}")
        
        # if drop_err and drop_mode == 1,wait 64us
        if ((self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'drop_err' and self.error_ctrl.select_drop_subtype() == DropErrorType.RD_NDESC_OVERFLOW) or self.error_ctrl.mixed_mode):
            segment_sz = beq_rx_segment_t.sz_512
        else:
            segment_sz = random.choice(beq_rx_segment_type_list) if qid != 63 else beq_rx_segment_t.sz_8k  

        self.log.debug(f"START")
        if (self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'drop_err' and self.error_ctrl.select_drop_subtype() == DropErrorType.DROP_MODE):
            drop_mode = 1
        self.log.debug(f"DROP end")
        
        
        await self.beq_pmd.create_queue(qid, beq_depth, segment_sz, drop_mode)
        self.log.debug(f"create queue end")
        if(self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'drop_err' and self.error_ctrl.select_drop_subtype() == DropErrorType.QUEUE_DISABLED):
            self.log.debug(f"Queue {qid} q_disable_err")
            await Timer(32, "us")  #q_disable_err: wait sometime start queue
        await self.beq_pmd.start_queue(qid=qid)
        self.log.debug(f"start queue end")
        idx = 0
        try_cnt = 0

        #while self.doing or not self.ref_queues[qid].empty():  
        while (not self.stop_workers) or (not self.ref_queues[qid].empty()) or (processed_pkts < total_pkts):
            self.log.debug(f"Drop detected on Q{qid} start")
            # if drop_err and drop_mode == 1,wait 64us for drop pkt
            #if (self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'drop_err' and self.error_ctrl.select_drop_subtype() == DropErrorType.DROP_MODE):
                #await Timer(64, "us")
            (mbufs, users) = await self.beq_pmd.burst_rx(qid=qid) 
            self.log.info(f"Q{qid} burst_rx finish")
            #recv_pkts += len(mbufs)
            self.log.info(f"mbufs on Q{qid} length {len(mbufs)}")

            # mbufs->some pkts,per mbuf->pkt
            for idx in range(len(mbufs)):  
                mbuf = mbufs[idx]
                user = users[idx]
                data_elem = await self.ref_queues[qid].get()
                ref_data = data_elem.data
                pkt_id   = data_elem.user0
                pkt_matched = True

                #per pkt(mbuf)->some buf or one buf
                for i, buf in enumerate(mbuf):  
                    length = user[i][0] 
                    self.log.debug("worker length={}".format(length))
                    data = await buf.read(0, length)
                    self.log.debug("should_enter_fit_mode = {} self.error_ctrl.select_error_type() = {}".format(self.error_ctrl.should_enter_fit_mode(), self.error_ctrl.select_error_type()))  
                    #if ((not self.error_ctrl.should_enter_fit_mode()) or (self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'desc_err')):  #normal case or not drop_err fit case
                    if ((not self.error_ctrl.should_enter_fit_mode()) or (self.error_ctrl.select_error_type() == 'desc_err')):
                        self.log.debug("In normal mode")
                        if data != ref_data[0:length]:
                            pkt_matched = False
                            self.log.warning("cur dat:{}".format(data.hex()))
                            self.log.warning("ref dat:{}".format(ref_data[0:length].hex()))  
                            raise ValueError(f"qid:{qid} len:{length} pkt_id:{pkt_id} is not match!")
                    else:  #drop_err
                        self.log.debug("In data compare mode")
                        pkt_matched = False
                        while not pkt_matched:
                            self.log.debug("while not")
                            if data == ref_data[0:length]:
                                self.log.debug("worker data={}".format(data.hex()))
                                self.log.debug("worker ref_data={}".format(ref_data[0:length].hex()))
                                pkt_matched = True
                                self.log.debug("exception break")
                                break
                            self.log.debug("data not matched,try next data")
                            if self.ref_queues[qid].empty():
                                raise ValueError("queue(qid:{}) is empty!".format(qid)) 
                            
                            #while len(ref_data) >= length:
                            ref_data = ref_data[length:]

                            data_elem = await self.ref_queues[qid].get()
                            ref_data = data_elem.data  
                            
                    ref_data = ref_data[length:]  
                    self.mem.free_region(buf)  #free mem
                
                if pkt_matched:  #sucess recv pkts
                    recv_pkts = recv_pkts + 1
                    self.log.info("qid:{} total recv pkts: {}".format(qid, recv_pkts))

                self.log.debug("should_enter_fit_mode = {} self.error_ctrl.select_error_type() = {} self.error_ctrl.mixed_mode = {} self.error_ctrl.select_drop_subtype() = {}".format(self.error_ctrl.should_enter_fit_mode(), self.error_ctrl.select_error_type(), self.error_ctrl.mixed_mode, self.error_ctrl.select_drop_subtype()))
                if (self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'drop_err' and self.error_ctrl.mixed_mode and self.error_ctrl.select_drop_subtype() == DropErrorType.QUEUE_DISABLED):  
                    await Timer(200, "us")
                    self.log.debug("phase1 finish and start phase2")
                    await self.beq_pmd.stop_queue(qid=qid)  
                    await self.beq_pmd.restart_queue(qid=qid)
                    self.error_ctrl.mixed_phase = 2
                    hw_drop_cnt_1 = await self.beq_ctx_ctrl.read_drop_cnt(qid)
                    self.log.debug("hw_drop_cnt_1 = {}".format(hw_drop_cnt_1))
                    await self.beq_ctx_ctrl.clear_cnt(qid)

            #if not self.doing:
            #    self.log.info("self.doing is 0")
            #    try_cnt = try_cnt + 1
            #    if try_cnt == 5000:#timeout
            #        break
#
            #await Timer(1, "us")

            hw_drop_cnt = await self.beq_ctx_ctrl.read_drop_cnt(qid)
            self.log.info(f"Q{qid} hw_drop_cnt={hw_drop_cnt}")  
            processed_pkts = hw_drop_cnt + hw_drop_cnt_1 + recv_pkts
            await Timer(1, "us")

        #final test
        self.log.info("qid:{} is finished".format(qid))
        hw_drop_cnt = await self.beq_ctx_ctrl.read_drop_cnt(qid)
        await self.beq_ctx_ctrl.clear_cnt(qid)   #wait for clear drop_cnt and pkt_cnt
        self.log.info(f"Drop detected on Q{qid} hw_drop_cnt={hw_drop_cnt}")
        if total_pkts != hw_drop_cnt + hw_drop_cnt_1 + recv_pkts:
            raise ValueError("Drop count mismatch! total_pkts={} hw_drop_cnt={} hw_drop_cnt_1={} recv_pkts={}".format(total_pkts, hw_drop_cnt, hw_drop_cnt_1, recv_pkts))
        self._final_report(qid, total_pkts, hw_drop_cnt, recv_pkts)
        await self.beq_pmd.stop_queue(qid=qid)  
        self.beq_pmd.destroy_queue(qid=qid)
        if not self.ref_queues[qid].empty():
            raise ValueError("queue(qid:{}) is not finish!".format(qid))

async def run_test(dut, idle_inserter, backpressure_inserter):
    #random.seed(321)
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    max_chn_num = 4    #4个chn
    max_seq = 100000  #100000

    packet_gen_cr = []  
    worker_cr = []
    await Timer(2, "us")

    #tb.dut.emu2beq_eop = Force(0)
    chns = [tb.emu2beq, tb.net2beq, tb.blk2beq, tb.sgdma2beq]
    #ID distributed
    bid_array = [[0], [id for id in gen_id(num=4, start=1, end=16)], [id for id in gen_id(num=4, start=16, end=63)], [63]]
    #bid_array = [
    #    [0],
    #    [id for id in gen_id(num=4,start=1,end=16)],
    #    [id for id in gen_id(num=4,start=16,end=63)], 
    #    [63]     
    #]

    qid_pkt_counts_per_chn = []  # per channel {qid: pkt_num}
    for chn_qids in bid_array[:max_chn_num]:
        qid_counts = {qid: max_seq for qid in chn_qids}
        qid_pkt_counts_per_chn.append(qid_counts)

        for qid in sum(bid_array, []):  
            tb.ref_queues[qid] = Queue()  #init ref_queue

    #bid_array = [
    #    [0],
    #    [3,7,11,14],
    #    [20,35,42,58],
    #    [63]
    #]

    #sum(bid_array,[]) = [] + [0] + [3,7,11,14] + [20,35,42,58] + [63] = [0,3,7,11,14,20,35,42,58,63]

    for qid in sum(bid_array[0:max_chn_num], []):  #for activate channel (max_chn_num)start worker，bid_array[0:1] = [[0]],sum([ [0] ], [])->[] + [0] → [0]
        worker_cr.append(cocotb.start_soon(tb.worker(qid, max_seq)))
        
    await Timer(1, "us")
    
    for i in range(max_chn_num):
        chn = chns[i]
        max_pkt_len= 8192*24 if i == max_chn_num -1 else 512*24
        #packet_gen_cr.append(cocotb.start_soon(packet_gen(chn=chn, ref_queues=tb.ref_queues, max_seq=max_seq, qid_array=bid_array[i], tb=tb, error_ctrl=tb.error_ctrl)))  #每个生成器绑定特定通道和队列ID组
        packet_gen_cr.append(cocotb.start_soon(packet_gen(chn=chn, ref_queues=tb.ref_queues, qid_pkt_counts=qid_pkt_counts_per_chn[i], tb=tb, error_ctrl=tb.error_ctrl)))  #每个生成器绑定特定通道和队列ID组
 

    for i in range(max_chn_num):
        cr = packet_gen_cr[i]
        await cr.join()  
        tb.log.info("packet_gen[{}] is done".format(i)) 

    for qid in tb.ref_queues:
        while not tb.ref_queues[qid].empty():
            await Timer(10, "us")

    await Timer(100, "us")

    tb.stop_worker()

    for cr in worker_cr:
        await cr.join()

    #tb.dut.emu2beq_eop = Release()

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    #seed=random.seed(123)
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        #factory.add_option("idle_inserter", [cycle_pause])
        #factory.add_option("backpressure_inserter", [cycle_pause])
        factory.generate_tests()

#sys.path.append('../common'); from debug import *

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
