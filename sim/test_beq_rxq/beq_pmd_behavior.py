#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_pmd_behavior.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/01/10
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  01/10     Joe Jiang   初始化版本
################################################################################
import cocotb
import logging
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from defines import *
from beq_ctx_ctrl import *
from unittest.mock import MagicMock
import random
from beq_error_ctrl import *

class pmd_rxq:
    def __init__(self, mem, qdepth, mbuf_sz):
        self.log = SimLog("cocotb.tb")
        self.mem = mem
        self.mbuf_sz = mbuf_sz
        self.desc_sz = len(BeqAvailDesc())
        self.ring_depth = 2**(qdepth-1) * 1024
        self.ring_queue = Queue()
        self.ring_buf = self.mem.alloc_region(self.desc_sz * self.ring_depth)  
        self.sw_ring = {}  
        self.pi = 0
        self.ci = 0
        self.desc_cnt = 0
        self.error_ctrl = beq_error_ctrl()

    async def init(self):
        for i in range(self.ring_depth):  
            mbuf = self.mem.alloc_region(self.mbuf_sz)      
            await self.write_desc(self.pi, mbuf)
            self.pi = (self.pi + 1) & 0xffff  
            #if ((i == (self.ring_depth//2)) and self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'drop_err' and self.error_ctrl.select_drop_subtype() == DropErrorType.DROP_MODE):
                #await Timer(16, "us")

    async def write_desc(self, pi, mbuf):
        phase_tag = 1 if (pi & self.ring_depth) else 0  

        if (self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'desc_err'):
            err_type = self.error_ctrl.select_desc_subtype()

            if err_type == DescErrorType.INVALID_ADDR:
                desc = BeqAvailDesc(soc_buf_addr=0, soc_buf_len=mbuf.size, avail=1^phase_tag, used=0^phase_tag, next=0)
            elif err_type == DescErrorType.INVALID_LEN:
                desc = BeqAvailDesc(soc_buf_addr=mbuf.get_absolute_address(0), soc_buf_len=0, avail=1^phase_tag, used=0^phase_tag, next=0)
            else:
                desc = BeqAvailDesc(soc_buf_addr=mbuf.get_absolute_address(0), soc_buf_len=mbuf.size, avail=0^phase_tag, used=1^phase_tag, next=0)
        
        else:  #no desc_err
            desc = BeqAvailDesc(soc_buf_addr=mbuf.get_absolute_address(0), soc_buf_len=mbuf.size, avail=1^phase_tag, used=0^phase_tag, next=0)

        await self.ring_buf.write((pi & (self.ring_depth-1))*self.desc_sz, desc.build()[::-1])  
        await self.ring_queue.put((desc,self.desc_cnt))  
        self.desc_cnt = self.desc_cnt + 1
        self.sw_ring[pi & (self.ring_depth-1)] = mbuf  


    async def read_desc(self, idx):
        desc_dat = await self.ring_buf.read((idx & (self.ring_depth-1))*self.desc_sz, self.desc_sz)
        return BeqUsedDesc().unpack(desc_dat[::-1])

class beq_pmd_behavior:
    def __init__(self, mem, beq_ctr):
        self.log = SimLog("cocotb.tb")
        self.mem = mem
        self.beqs = {}
        self.ring_queues = {}
        self.beq_ctr = beq_ctr
        self.error_ctrl = beq_error_ctrl()

    async def create_queue(self, qid, beq_depth, segment_sz, drop_mode):
        seg_tbl = {beq_rx_segment_t.sz_512:512, beq_rx_segment_t.sz_1k:1024, beq_rx_segment_t.sz_2k:2048, beq_rx_segment_t.sz_4k:4096, beq_rx_segment_t.sz_8k:8192}
        q = pmd_rxq(self.mem, beq_depth, seg_tbl[segment_sz])
        await self.beq_ctr.create_queue(qid, q.ring_buf.get_absolute_address(0), beq_depth, segment_sz, drop_mode)
        if qid in self.beqs.keys():
            raise ValueError("The rx queue(qid:{}) is already exists".format(qid))
        self.beqs[qid] = q  
        self.ring_queues[qid] = q.ring_queue  

    def destroy_queue(self, qid):
        self.beq_ctr.destroy_queue(qid)
        if qid not in self.beqs.keys():
            raise ValueError("The rx queue(qid:{}) is not exists".format(qid))
        del self.beqs[qid]  

    async def start_queue(self, qid):
        if qid not in self.beqs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        
        await self.beqs[qid].init() 

        #if(self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'drop_err' and self.error_ctrl.select_drop_subtype() == DropErrorType.QUEUE_DISABLED):
            #self.log.debug(f"Queue {qid} q_disable_err")
            #await Timer(32, "us")  #q_disable_err: wait sometime start queue
      
        self.log.debug("start_queue START!!!")
        await self.beq_ctr.start_queue(qid) 
        self.log.debug("start_queue END!!!")

    async def restart_queue(self, qid):
        if qid not in self.beqs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        
        self.log.debug("restart_queue START!!!")
        await self.beq_ctr.start_queue(qid) 
        self.log.debug("restart_queue END!!!")
        

    async def stop_queue(self, qid):
        await self.beq_ctr.stop_queue(qid)  

    
    async def burst_rx(self, qid):
        self.log.debug("burst_rx start")
        rxq = self.beqs[qid]
        mbufs = [] 
        users = []
        has_used_desc = True
        while has_used_desc:
            avail_num = rxq.pi - rxq.ci if rxq.pi >= rxq.ci else rxq.pi + 2**16  - rxq.ci  
            self.log.info("burst_rx qid {} avail_num {}".format(qid, avail_num))
            if avail_num == 0:
                break
            mbuf = []
            user = []
            for i in range(avail_num):
                idx = rxq.ci + i  
                desc = await rxq.read_desc(idx)
                phase_tag = 1 if (idx & rxq.ring_depth) else 0  #first circle 0

                if desc.used == (1^phase_tag) and desc.used == desc.avail: 
                    self.log.info("burst_rx qid {} idx {} {}".format(qid, idx, desc.show(dump=True)))
                    mbuf.append(rxq.sw_ring[idx & (rxq.ring_depth-1)])
                    user.append((desc.soc_buf_len, desc.user0, desc.user1))
                    if not desc.next:  
                        #delete current chain desc
                        for j in range(i):
                            del rxq.sw_ring[(rxq.ci + j) & (rxq.ring_depth-1)]
                        if not desc.err:     
                            self.log.info("no desc err")
                            mbufs.append(mbuf)
                            users.append(user)
                        else: 
                            self.log.debug("burst_rx err qid {} idx {}".format(qid, idx))
                            #err_desc = BeqAvailDesc().unpack(desc.build())
                            #self.log.debug("burst_rx err qid {} idx {} {}".format(qid, idx, err_desc.show(dump=True)))
                            self.mem.free_region(rxq.sw_ring[idx & (rxq.ring_depth-1)])
                            del rxq.sw_ring[idx & (rxq.ring_depth-1)]   
                        rxq.ci = (idx + 1) & 0xffff
                        break
                else:
                    has_used_desc = False
                    break
        #supplement new desc
        avail_num = rxq.pi - rxq.ci if rxq.pi >= rxq.ci else rxq.pi + 2**16  - rxq.ci

        self.log.info("burst_rx qid {} avail_num {} rxq.ring_depth {} rxq.pi {} rxq.ci {}".format(qid, avail_num, rxq.ring_depth, rxq.pi, rxq.ci))
        for _ in range(rxq.ring_depth - avail_num):           
            mbuf = self.mem.alloc_region(rxq.mbuf_sz)            
            await rxq.write_desc(rxq.pi, mbuf)
            rxq.pi = (rxq.pi + 1) & 0xffff
        #doorbell
        await self.beq_ctr.doorbell(qid, rxq.pi)
        return mbufs, users  
