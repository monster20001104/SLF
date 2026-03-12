#!/usr/bin/env python3
################################################################################
#  文件名称 : test_beq_desc_eng_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/11/29
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  11/29     Joe Jiang   初始化版本
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
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory


sys.path.append('../common')
from bus.beq_data_bus import BeqBus
from monitors.beq_data_bus import BeqTxqSlave
from bus.tlp_adap_dma_bus import DmaReadBus, DmaWriteBus
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace, MemoryRegion
from backpressure_bus import define_backpressure
from enum import Enum, unique
from defines import *
from beq_ctx_ctrl import *
from beq_desc_eng import *
from beq_pmd_behavior import *

#Generate multiple unique random IDs within a specified range
def gen_unique_ids(num, start, end):
    if num > (end - start):
        raise ValueError(f"Not enough unique IDs between {start} and {end}")
    return random.sample(range(start, end), num)

ErrStopRspBus, ErrStopRspTransaction, ErrStopRspSource, ErrStopRspSink, ErrStopRspMonitor = define_backpressure("err_stop",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    sav_signal = "sav",
    signal_widths=None
)

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)  
        self.mem = Pool(None, 0, size=2**64, min_alloc=64) 
        self.pkt_pool = {}  

        self.beq_txq_ref = {}  

        cocotb.start_soon(Clock(dut.clk, 5, units="ns").start())
    
        self.errstopRsp = ErrStopRspSink(ErrStopRspBus.from_prefix(dut, "err_stop"), dut.clk, dut.rst)
        
        self.notifyReq = NotifyReqSource(NotifyReqBus.from_prefix(dut, "notify_req"), dut.clk, dut.rst)
        self.notifyRsp = NotifyRspSink(NotifyRspBus.from_prefix(dut, "notify_rsp"), dut.clk, dut.rst)

        self.rdNdescReq = RdNdescReqSink(RdNdescReqBus.from_prefix(dut, "rd_ndesc_req"), dut.clk, dut.rst)
        self.rdNdescRsp = RdNdescRspSource(RdNdescRspBus.from_prefix(dut, "rd_ndesc_rsp"), dut.clk, dut.rst)

        self.dmaWrCiIf = DmaRam(DmaWriteBus.from_prefix(dut, "dma_ci"), None, dut.clk, dut.rst, mem=self.mem)
        self.dmaRdDataIf = DmaRam(None, DmaReadBus.from_prefix(dut, "dma_data"), dut.clk, dut.rst, mem=self.mem)

        self.beq2emu   = BeqTxqSlave(BeqBus.from_prefix(dut, "beq2emu")  , dut.clk, dut.rst)
        self.beq2net   = BeqTxqSlave(BeqBus.from_prefix(dut, "beq2net")  , dut.clk, dut.rst)
        self.beq2blk   = BeqTxqSlave(BeqBus.from_prefix(dut, "beq2blk")  , dut.clk, dut.rst)
        self.beq2sgdma = BeqTxqSlave(BeqBus.from_prefix(dut, "beq2sgdma"), dut.clk, dut.rst)

        self.ringCiAddrRdTbl = RingCiAddrRdTbl(RingCiAddrRdReqBus.from_prefix(dut, "ring_ci_addr_rd"), RingCiAddrRdRspBus.from_prefix(dut, "ring_ci_addr_rd"), None, dut.clk, dut.rst)
        self.ringCiTbl = RingCiTbl(RingCiRdReqBus.from_prefix(dut, "ring_ci"), RingCiRdRspBus.from_prefix(dut, "ring_ci"), RingCiWrBus.from_prefix(dut, "ring_ci"), dut.clk, dut.rst)
        self.errInfoTbl = ErrInfoTbl(ErrInfoRdReqBus.from_prefix(dut, "err_info"), ErrInfoRdRspBus.from_prefix(dut, "err_info"), ErrInfoWrBus.from_prefix(dut, "err_info"), dut.clk, dut.rst)

        #self.ringCiWr = RingCiWrSink(RingCiWrBus.from_prefix(dut, "ring_ci_wr"), dut.clk, dut.rst)
        self.rings = {}
        self.beq_ctx_ctrl = beq_ctx_ctrl(self.mem, dut.clk, self.ringCiAddrRdTbl, self.ringCiTbl, self.errInfoTbl)
        self.beq_desc_eng = beq_desc_eng(dut.clk, self.rings, self.beq_ctx_ctrl, self.notifyReq, self.notifyRsp, self.rdNdescReq, self.rdNdescRsp)
        self.beq_pmd = beq_pmd_behavior(self.mem, self.rings, self.beq_ctx_ctrl, self.beq_desc_eng, is_fit=False)   
    
        #self.beq_desc_eng = beq_desc_eng(dut.clk, self.beq_pmd.ring_queues, self.beq_ctx_ctrl, self.notifyReq, self.notifyRsp, self.rdNdescReq, self.rdNdescRsp)
       
        cocotb.start_soon(self._txqRefCheckThd())
        cocotb.start_soon(self._errhandleThd())

    async def _errhandleThd(self):
        while True:
            qid_err = await self.errstopRsp.recv()
            self.beq_ctx_ctrl.stop_queue(qid_err.qid.integer)


    async def _txqRefCheckThd(self):
        txq_chns = [self.beq2emu, self.beq2net, self.beq2blk, self.beq2sgdma]
        q_cnts = {} 
        while True:
            for idx in range(len(txq_chns)):  
                txq_chn = txq_chns[idx]
                if not txq_chn.empty():  
                    beq_data = txq_chn.recv_nowait()  #receive rtl transmit data immediate
                    qid = beq_data.qid  
                    #if qid not exist,init q_cnts
                    if qid not in q_cnts.keys():
                        q_cnts[qid] = 0
                    
                    sty = beq_data.sty
                    data = beq_data.data
                    user0 = beq_data.user0

                    if sty != 0:
                        raise ValueError("txq (qid:{}) (cnt:{}) sty is mismatched".format(qid, q_cnts[qid]))
                    
                    
                    (ref_mbufs, ref_typ) = await self.beq_txq_ref[qid].get()
                    
                    ref_data = b''    # init empty string
   
                    for ref_mbuf in ref_mbufs:
                        self.log.debug("ref_mbuf.reg.size={}".format(ref_mbuf.reg.size))
                        #ref_data = ref_data + await ref_mbuf.reg.read(0, ref_mbuf.reg.size)
                        ref_data = ref_data + await ref_mbuf.reg.read(ref_mbuf.reg.headr_room, ref_mbuf.reg.size-ref_mbuf.reg.headr_room)  #0:start addr，ref_mbuf.reg.size:length

                        addr = ref_mbuf.addr 
                        if ref_typ in self.pkt_pool and addr in self.pkt_pool[ref_typ]:
                            del self.pkt_pool[ref_typ][addr] 

                        self.mem.free_region(ref_mbuf.reg)   
                    #compare pkt data
                    if ref_data != data:
                        self.log.info("ref:{}".format(ref_data.hex()))
                        self.log.info("dat:{}".format(data.hex()))
                        raise ValueError("txq (qid:{}) (cnt:{}) data is mismatched".format(qid, q_cnts[qid]))
                    if ref_typ != beq_transfer_type_type_list[idx]:
                        self.log.info(f"idx={idx}, ref_typ={ref_typ}, expected_type={beq_transfer_type_type_list[idx]}")
                        raise ValueError("txq (qid:{}) (cnt:{}) type is mismatched".format(qid, q_cnts[qid]))
                    self.log.info("txq (qid:{} cnt:{} len:{}) test is passed".format(qid, q_cnts[qid], len(data)))
                    q_cnts[qid] = q_cnts[qid] + 1  
            await RisingEdge(self.dut.clk)
            

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
        
        #self.dut.ring_ci_rd_rsp_dat.value = 0

   
    def set_idle_generator(self, generator=None):
        self.notifyReq.set_idle_generator(generator)
        self.rdNdescReq.set_idle_generator(generator)
        self.dmaWrCiIf.set_idle_generator(generator)
        self.dmaRdDataIf.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        self.errstopRsp.set_backpressure_generator(generator)
        self.notifyRsp.set_backpressure_generator(generator)
        self.rdNdescRsp.set_backpressure_generator(generator)
        self.dmaWrCiIf.set_backpressure_generator(generator)
        self.dmaRdDataIf.set_backpressure_generator(generator)
        self.beq2emu.set_backpressure_generator(generator)
        self.beq2net.set_backpressure_generator(generator)
        self.beq2blk.set_backpressure_generator(generator)
        self.beq2sgdma.set_backpressure_generator(generator)
    def gen_data(self, len):
        return os.urandom(len)  #Produce random byte data with a given length
        '''
        data = b""
        cnt = 0
        while cnt < len:
            end = min(256, len-cnt)
            data = data + bytearray([i for i in range(0, end)])
            cnt = cnt + end
        return data
        '''

    def random_pkt_len(self, chain_num):
        lens = []
        max_len = random.randint(chain_num,  8*1024)  #max 8KB
        
        if random.randint(0, 1000) < 500:
            if random.randint(0, 100) < 20:  
                max_len = (max_len+4095)//4096*4096  
            #cal lens
            lens = [4096 for _ in range(max_len//4096)] + ([max_len % 4096] if max_len % 4096 !=  0 else [])
            return (lens, len(lens))
        else:
            #random cut data
            cuts = [0] + sorted(random.sample(range(1, max_len), chain_num-1))+[max_len] 
            cuts.sort()
            for i in range(len(cuts)-1):
                lens.append(cuts[i+1]-cuts[i])  
            return (lens, chain_num)
        
    async def pkt_gen(self, typ, pkt_idx):
        chain = []
        chain_num = random.randint(1, max_chain_num)  #random chain num
        (lens, chain_num) = self.random_pkt_len(chain_num) 

        if typ not in self.pkt_pool.keys():
            self.pkt_pool[typ] = {} 

        for i in range(chain_num):
            len = lens[i]#random.randint(1, 8912)
            oft = random.randint(0, 63)
            while True: #unique addr
                reg = self.mem.alloc_region(len + oft)  
                reg.headr_room = oft
                addr = reg.get_absolute_address(reg.headr_room)
                
                if addr not in self.pkt_pool[typ]:
                    break
                
                self.log.warning(f"addr {addr} (typ={typ}) duplicate, retry...")
                self.mem.free_region(reg)
            #reg = self.mem.alloc_region(len + oft)  
            #reg.headr_room = oft
            await reg.write(oft, self.gen_data(len))     
            #addr = reg.get_absolute_address(reg.headr_room)

            #if addr in self.pkt_pool[typ].keys():
            #    raise ValueError(f"addr {addr} (typ={typ}) is already existed!")
            
            if typ not in beq_transfer_type_type_list:
                raise ValueError("typ is not existed!")
            #according type 
            
            self.pkt_pool[typ][addr] = reg  #record alloc_region
            
            user0 = addr
            #create desc chain
            chain.append(beq_mbuf(addr, reg, user0))
            self.log.info("pkt_idx {} desc i {} chain num {} chain end {} addr:{} len:{}".format(pkt_idx, i, chain_num, i==chain_num-1, addr, reg.size))
        return chain
    
class FlowControlDriver:
    def __init__(self, dut):
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)  
        self.dut = dut
        self.fc_probability = 0.2 #0.2
        self.delay_probability = 0.5 #0.5
        #self.test_done = Event()
        self.test_done = 0
    
    def set_fc_probability(self, prob):
        self.fc_probability = prob
    
    def set_delay_probability(self, prob):
        self.delay_probability = prob
    
    async def run(self):
        # init
        self.dut.emu_to_beq_cred_fc.value = 0
        self.dut.blk_to_beq_cred_fc.value = 0
        self.dut.sgdma_to_beq_cred_fc.value = 0
        
        #while not self.test_done.is_set():
        self.log.debug("self.test_done = {}".format(self.test_done))
        while not self.test_done:
            await RisingEdge(self.dut.clk)
            
            if random.random() < self.fc_probability:
                self.dut.emu_to_beq_cred_fc.value = random.randint(0, 1)
                self.dut.blk_to_beq_cred_fc.value = random.randint(0, 1)
                self.dut.sgdma_to_beq_cred_fc.value = random.randint(0, 1)
            else:
                self.dut.emu_to_beq_cred_fc.value = 0
                self.dut.blk_to_beq_cred_fc.value = 0
                self.dut.sgdma_to_beq_cred_fc.value = 0
            
            #if random.random() < self.delay_probability and not self.test_done.is_set():
            if random.random() < self.delay_probability and not self.test_done:
                delay_cycles = random.randint(1, 5)
                for _ in range(delay_cycles):
                    #if self.test_done.is_set():
                    if self.test_done:
                        break
                    await RisingEdge(self.dut.clk)
    
    def stop(self):
        #self.test_done.set()
        self.test_done = 1

async def worker(tb, qid, max_seq):
  
    typ = beq_transfer_type_type_list[random.randint(0, len(beq_transfer_type_type_list)-1)]
    #create queue
    await tb.beq_pmd.create_queue(qid=qid, transfer_type=typ)
    await tb.beq_pmd.start_queue(qid=qid)
    tb.log.debug("typ: {}".format(typ))
    idx = 0
    for i in range(max_seq):  
        tb.log.info("qid:{} seq: {}".format(qid, i))
        chains = []
        num_chain = random.randint(1, 8) #random chain num
        for j in range(num_chain):  #gen per chain
            chain = await tb.pkt_gen(typ, idx)
            idx = idx + 1
            chains.append(chain)
            #if not exist,init beq_txq_reg
            if qid not in tb.beq_txq_ref.keys():
                tb.beq_txq_ref[qid] = Queue(maxsize=512)
                #tb.beq_txq_ref[qid] = Queue()
          
            tb.log.debug("chain = {} typ = {}".format(chain, typ))
            await tb.beq_txq_ref[qid].put((chain, typ))
        #the descriptors (desc) are written into the ring buffer, triggering the hardware to read the data and initiate transmission
        while True:
            chains = await tb.beq_pmd.burst_tx(qid=qid, chains=chains)

            if len(chains) == 0:
                tb.log.debug("len chains 0")
                break
            else:
                await Timer(1, "us")

            
        '''
        if random.randint(100) < 10 :
            if random.randint(100) < 30 :
                error_code = 2
                err_chains = [beq_mbuf(0, MemoryRegion(1024), 0x111), beq_mbuf(0x12312, MemoryRegion(0), 0x222), beq_mbuf(0x12312, MemoryRegion(1024), 0x222)]
            elif random.randint(100) < 50 :
                error_code = 1
                err_chains = [beq_mbuf(0x12312, MemoryRegion(0), 0x222), beq_mbuf(0x12312, MemoryRegion(1024), 0x222)]
            else:
                error_code = 1
                err_chains = [beq_mbuf(0, MemoryRegion(0), 0x111), beq_mbuf(0x12312, MemoryRegion(1024), 0x222), beq_mbuf(0x12312, MemoryRegion(1024), 0x222)]
            await tb.beq_pmd.burst_tx(qid=qid, chains=err_chains)
            while tb.beq_pmd.get_code(qid=qid) == error_code:
                await Timer(1, "us")
        '''
    #wait finish 
    await tb.beq_pmd.wait_finish(qid=qid)
    tb.log.info("qid:{} is finished".format(qid))
    
    active = not tb.beq_txq_ref[qid].empty()
    while active:
        pkt_num = tb.beq_txq_ref[qid].qsize()
        await Timer(200, "us")   #1000us
        active = pkt_num != tb.beq_txq_ref[qid].qsize()
    
    tb.beq_pmd.destroy_queue(qid=qid)
    
    
    if not tb.beq_txq_ref[qid].empty():
        raise ValueError("queue(qid:{}) is not finish!".format(qid))
    

async def run_test(dut, idle_inserter, backpressure_inserter):
    #random.seed(321)
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    
    fc_driver = FlowControlDriver(dut)
    fc_driver_cr = cocotb.start_soon(fc_driver.run())

    q_num = 4   #16
    max_seq = 2000  #2000
    #worker_cr = {}
    worker_cr = []

    bid_array = gen_unique_ids(num=q_num, start=0, end=q_num) 
    tb.log.debug("bid_array = {}".format(bid_array))
  
    for qid in bid_array:
        tb.log.debug("worker qid = {}".format(qid))  
        worker_cr.append(cocotb.start_soon(worker(tb, qid, max_seq)))
        
    await Timer(1, "us")

    for cr in worker_cr:
        await cr.join()  

####################################
#这一段是qid从0->q_num-1逐渐递增的方式
    #启动所有工作线程
    #for i in range(q_num):
    #    worker_cr[i] = cocotb.start_soon(worker(tb, i, max_seq))
    #等待所有线程完成
    #for i in range(q_num):
    #    await worker_cr[i].join()
####################################

    fc_driver.stop()
    await fc_driver_cr 

    #check memory leak
    if len(tb.mem.regions) != 0:
        raise ValueError("Memory Leak")


def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        #factory.add_option("idle_inserter", [None])
        #factory.add_option("backpressure_inserter", [None])
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()

#sys.path.append('../common'); from debug import *

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
