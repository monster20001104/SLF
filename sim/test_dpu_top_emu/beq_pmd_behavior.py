#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_pmd_behavior.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/02/13
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  02/13     Joe Jiang   初始化版本
################################################################################
import cocotb
import logging
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from beq_defines import *
from beq_ctrl import *
from address_space import Pool, AddressSpace, MemoryRegion
import random

class Mbuf(NamedTuple):
    reg     : MemoryRegion  
#    length  : int   
#    user0   : int     
#    user1   : int     

class pmd_queue:
    def __init__(self, ctrl, mem, qdepth, mbuf_sz, typ):
        self.log = SimLog("cocotb.tb")   
        self.log.setLevel(logging.DEBUG)
        self.mem = mem                  
        self.mbuf_sz = mbuf_sz          
        self.desc_sz = len(BeqAvailDesc())  
        self.ring_depth = 2**(qdepth-1) * 1024  
        self.typ = typ                         
       
        self.ring_buf = self.mem.alloc_region(self.desc_sz * self.ring_depth)
        self.ci_ptr_sz = 64    
       
        self.ci_reg = mem.alloc_region(self.ci_ptr_sz) 
        self.sw_ring = {}  
        self.pi = 0  
        self.ci = 0 
    
    async def reset(self):
        self.sw_ring = {}  
        self.pi = 0
        self.ci = 0
        await self.ci_reg.write(0, b'\00'*self.ci_ptr_sz)  #0:addr

    #init desc
    async def init(self, is_fit=False):
        for _ in range(self.ring_depth): 
            reg = self.mem.alloc_region(self.mbuf_sz)           
            await self.write_desc(self.pi, reg, fit=is_fit and random.randint(0, 100) < 0)  
            self.pi = (self.pi + 1) & 0xffff

    async def write_desc(self, pi, reg, size=None, user0 = 0, next=0, fit=False): 
        phase_tag = 1 if (pi & self.ring_depth) else 0 
       
        if size is None:  #RX
            soc_buf_len = reg.size
        else:  #TX
            soc_buf_len = size
        '''
        if fit:
            soc_buf_addr = 0
        else:
            soc_buf_addr=reg.get_absolute_address(0)
        '''
        
        soc_buf_addr=reg.get_absolute_address(0)
  
        if fit:  
            desc = BeqAvailDesc(soc_buf_addr=soc_buf_addr, soc_buf_len=soc_buf_len, avail=0^phase_tag, used=1^phase_tag, user0=user0, next=next)
            #desc = BeqAvailDesc(soc_buf_addr=0, soc_buf_len=soc_buf_len, avail=1^phase_tag, used=0^phase_tag, user0=user0, next=next)
        else:
            desc = BeqAvailDesc(soc_buf_addr=soc_buf_addr, soc_buf_len=soc_buf_len, avail=1^phase_tag, used=0^phase_tag, user0=user0, next=next)
        
           
        idx = pi & (self.ring_depth-1)

        if size is not None:  
            self.log.debug("txq write_desc  idx {} desc {}".format(idx, desc.show(dump=True)))
        
       
        await self.ring_buf.write(idx*self.desc_sz, desc.build()[::-1])
        self.sw_ring[idx] = reg 


    async def read_desc(self, idx):
        desc_dat = await self.ring_buf.read((idx & (self.ring_depth-1))*self.desc_sz, self.desc_sz)
        return BeqUsedDesc().unpack(desc_dat[::-1])
    
    async def read_avail_desc(self, idx):
        desc_dat = await self.ring_buf.read((idx & (self.ring_depth-1))*self.desc_sz, self.desc_sz)
        return BeqAvailDesc().unpack(desc_dat[::-1])

    async def get_txq_used_ptr(self):
        data = int.from_bytes(await self.ci_reg.read(0, self.ci_ptr_sz), byteorder="little") & 0xffffffff
        return data&0x80000000 != 0, data&0xffff  #[31]:error_flag, [15:0]:used_ptr

class beq_pmd_behavior:
    def __init__(self, mem, beq_ctr, is_fit=False):
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.mem = mem        
        self.beqs = {}         
        self.is_fit = is_fit   
        self.beq_ctr = beq_ctr  

    async def create_queue(self, qid, is_txq, beq_depth, segment_sz, typ=beq_transfer_type_t.emu, drop_mode=False):
        seg_tbl = {beq_rx_segment_t.sz_512:512, beq_rx_segment_t.sz_1k:1024, beq_rx_segment_t.sz_2k:2048, beq_rx_segment_t.sz_4k:4096, beq_rx_segment_t.sz_8k:8192}
       
        q = pmd_queue(self.beq_ctr, self.mem, beq_depth, seg_tbl[segment_sz], typ)
       
        await self.beq_ctr.create_queue(qid, is_txq, q.ring_buf.get_absolute_address(0), q.ci_reg.get_absolute_address(0), beq_depth, typ, segment_sz, drop_mode)
       
        if qid*2+is_txq in self.beqs.keys():
            raise ValueError("The {}(qid:{}) is already exists".format("txq" if is_txq else "rxq", qid))
        self.beqs[qid*2+is_txq] = q  

    def destroy_queue(self, qid, is_txq):
       
        self.beq_ctr.destroy_queue(qid, is_txq)
        if qid*2+is_txq not in self.beqs.keys():
            raise ValueError("The {}(qid:{}) is not exists".format("txq" if is_txq else "rxq", qid))
       
        for idx in self.beqs[qid*2+is_txq].sw_ring.keys():
            self.mem.free_region(self.beqs[qid*2+is_txq].sw_ring[idx])
        
        self.mem.free_region(self.beqs[qid*2+is_txq].ring_buf)
        self.mem.free_region(self.beqs[qid*2+is_txq].ci_reg)
       
        del self.beqs[qid*2+is_txq]

    async def start_queue(self, qid, is_txq):
        if qid*2+is_txq not in self.beqs.keys():
            raise ValueError("The {}(qid:{}) is not exists".format("txq" if is_txq else "rxq", qid))
           
        await self.beq_ctr.start_queue(qid, is_txq)

        if not is_txq:
            await self.beqs[qid*2+is_txq].init(self.is_fit)
            await self.beq_ctr.doorbell(qid, is_txq, self.beqs[qid*2+is_txq].pi)
        

    async def stop_queue(self, qid, is_txq):
        self.log.info("{}(qid:{}) stop_queue stopping".format("txq" if is_txq else "rxq", qid))
        await self.beq_ctr.stop_queue(qid, is_txq)
        self.log.info("{}(qid:{}) stop_queue done".format("txq" if is_txq else "rxq", qid))

    def get_rxq_segment(self, qid):
        return self.beq_ctr.ctxs[qid*2].segment_sz

    async def burst_rx(self, qid):
        rxq = self.beqs[qid*2] 
        mbufs = []             
        has_used_desc = True    
        while has_used_desc:
            
            avail_num = rxq.pi - rxq.ci if rxq.pi >= rxq.ci else rxq.pi + 2**16  - rxq.ci
         
            if avail_num == 0: 
                break
            mbuf = []  
            for i in range(avail_num):
                idx = rxq.ci + i  
                desc = await rxq.read_desc(idx)
                phase_tag = 1 if (idx & rxq.ring_depth) else 0  
              
                if desc.used == (1^phase_tag) and desc.used == desc.avail:
                    self.log.debug("burst_rx qid {} idx {} {}".format(qid, idx, desc.show(dump=True)))
                    rxq.sw_ring[idx & (rxq.ring_depth-1)].occupancy_bytes = desc.soc_buf_len
                    rxq.sw_ring[idx & (rxq.ring_depth-1)].user0 = desc.user0
                    rxq.sw_ring[idx & (rxq.ring_depth-1)].user1 = desc.user1
                    #mbuf.append(Mbuf(rxq.sw_ring[idx & (rxq.ring_depth-1)], desc.soc_buf_len, desc.user0, desc.user1))
                    mbuf.append(Mbuf(rxq.sw_ring[idx & (rxq.ring_depth-1)]))
                    if not desc.next: 
                        
                        for j in range(i):
                            del rxq.sw_ring[(rxq.ci + j) & (rxq.ring_depth-1)]
                        if not desc.err:  
                            mbufs.append(mbuf)
                        else: 
                            err_desc = BeqAvailDesc().unpack(desc.build())
                            self.log.info("burst_rx err qid {} idx {} {}".format(qid, idx, err_desc.show(dump=True)))
                            self.mem.free_region(rxq.sw_ring[idx & (rxq.ring_depth-1)])
                            del rxq.sw_ring[idx & (rxq.ring_depth-1)]   
                        rxq.ci = (idx + 1) & 0xffff       
                        break
                else:
                    has_used_desc = False
                    break
        avail_num = rxq.pi - rxq.ci if rxq.pi >= rxq.ci else rxq.pi + 2**16  - rxq.ci

        for _ in range(rxq.ring_depth - avail_num):
            reg = self.mem.alloc_region(rxq.mbuf_sz)            
            await rxq.write_desc(rxq.pi, reg, fit=self.is_fit and random.randint(0, 100) < 0)
            rxq.pi = (rxq.pi + 1) & 0xffff

        if rxq.ring_depth - avail_num > 0:
            await self.beq_ctr.doorbell(qid, False, rxq.pi)

        return mbufs  

    async def burst_tx(self, qid, chains):
        txq = self.beqs[qid*2+1] 
        avail_num = txq.pi - txq.ci if txq.pi >= txq.ci else txq.pi + 2**16  - txq.ci 
        #self.log.debug("burst_tx {} chains len {}".format(qid, len(chains)))
        err, used_ptr = await txq.get_txq_used_ptr()  
        
        
        if err: 
            self.log.debug("burst_tx err {} used_ptr {} err".format(qid, used_ptr))
            # wait stop done
            self.log.debug("qid {} wait stop done".format(qid))
            await self.beq_ctr.wait_idle_queue(qid, True) 
            
            # found chain
            self.log.debug("qid {} before found chain ci {} used_ptr {} used".format(qid, txq.ci, used_ptr))
            used_num = used_ptr - txq.ci if used_ptr >= txq.ci else used_ptr + 2**16  - txq.ci  
            old_next = False  
            for i in range(used_num):
                idx = (used_ptr-i-1) & 0xffff  #The hardware completion pointer (used_ptr) is traversed forward with a reverse scan because if the faulty descriptor is located later in the chain, it is necessary to accurately identify the chain head based on the previous descriptor's old_next and the next pointer of the current used_ptr descriptor, ensuring the complete chain is properly reclaimed
                desc = await txq.read_avail_desc(idx)
                next = desc.next   
                self.log.debug(" qid {} found chian idx {}  {} {} desc {} ".format(qid, idx, next, old_next, desc.show(dump=True)))
                if i != 0:
                    # err_used_ptr = 425 
                    #  num    421 422 423 424   clean   idx  new_used_ptr        
                    # err_desc             x    
                    # case0    0   0  [0   0]  421-423   423   424(idx+1)
                    # case1   [0   1]   1  0    421      421   422(idx+1)
                    # case2    x  [0   1]  1  421-422    422   423(idx+1)
                    # case3    1   1   1   1    null     424   424(idx)
                    # case4                0    null     424   424(idx)
                    if (not next and not old_next) :#case0  
                        desc = await txq.read_avail_desc(idx-1)
                        self.log.info(" qid {} found chian idx {} case0 {} {} desc {} ".format(qid, idx-1, next, old_next, desc.show(dump=True)))
                        used_ptr = (idx + 1) & 0xffff
                        break
                    elif (not next and old_next):#case1/2  
                        desc = await txq.read_avail_desc(idx-1)
                        self.log.info(" qid {} found chian idx {} case1/2 {} {} desc {} ".format(qid, idx-1, next, old_next, desc.show(dump=True)))
                        used_ptr = (idx + 1) & 0xffff
                        break
                    elif (i == used_num - 1):#case3 
                        desc = await txq.read_avail_desc(idx-1)
                        self.log.info(" qid {} found chian idx {} case3 {} {} desc {} ".format(qid, idx-1, next, old_next, desc.show(dump=True)))
                        used_ptr = idx & 0xffff
                        break
                elif used_num == 1:  
                    self.log.info(" qid {} found chian idx {} case4 {} ".format(qid, idx, desc.show(dump=True)))
                    used_ptr = idx & 0xffff
                old_next = next 
            # clean used 
            self.log.debug("qid {} clean used_ptr(chian) {} used".format(qid, used_ptr))
            used_num = used_ptr - txq.ci if used_ptr >= txq.ci else used_ptr + 2**16  - txq.ci
            for i in range(used_num):
                idx = txq.ci + i
                self.mem.free_region(txq.sw_ring[idx & (txq.ring_depth-1)])  
                del txq.sw_ring[idx & (txq.ring_depth-1)]   
            txq.ci = used_ptr  
            self.log.debug("qid {} store avail data".format(qid))
            # store avail data  
            avail_chains    = []
            avail_chain     = []
            avail_num = txq.pi - txq.ci if txq.pi >= txq.ci else txq.pi + 2**16  - txq.ci   
            for i in range(avail_num):
                idx = txq.ci + i
                desc = await txq.read_avail_desc(idx)
                #self.log.debug("desc.soc_buf_len = {}".format(desc.soc_buf_len))
                #avail_chain.append(Mbuf(reg=txq.sw_ring[idx & (txq.ring_depth-1)], length=desc.soc_buf_len, user0=desc.user0, user1=0))
                self.log.debug("txq.sw_ring[idx & (txq.ring_depth-1)].occupancy_bytes = {}".format(txq.sw_ring[idx & (txq.ring_depth-1)].occupancy_bytes))
                avail_chain.append(Mbuf(reg=txq.sw_ring[idx & (txq.ring_depth-1)]))
                del txq.sw_ring[idx & (txq.ring_depth-1)]
                if not desc.next:  
                    avail_chains.append(avail_chain)
                    avail_chain     = []  #reset avail_chain
            self.log.debug("qid {} restart".format(qid))
            # restart 
            await txq.reset()  #reset pi ci
            await self.beq_ctr.start_queue(qid, True, clean_dfx_cnt=False)   #restart queue
            self.log.debug("qid {} load old data".format(qid))
            # load old data
            for idx, avail_chain in enumerate(avail_chains):   
                for i, mbuf in enumerate(avail_chain):
                    self.log.debug("False mbuf.occupancy_bytes = {}".format(mbuf.reg.occupancy_bytes))
                    await txq.write_desc(txq.pi, mbuf.reg, size=mbuf.reg.occupancy_bytes, user0=mbuf.reg.user0, next=i != len(avail_chain)-1)
                    txq.pi = (txq.pi + 1) & 0xffff
            await self.beq_ctr.doorbell(qid, True, txq.pi)  
            self.log.info("qid {} queue recovery done".format(qid))
            return chains  
            
            #raise ValueError("the queue(qid:{}) is err".format(qid))
        used_num = used_ptr - txq.ci if used_ptr >= txq.ci else used_ptr + 2**16  - txq.ci

        
        if True:      #txq.ring_depth - avail_num < 256:
            used_num = used_ptr - txq.ci if used_ptr >= txq.ci else used_ptr + 2**16  - txq.ci
            chian_idxs = []  
            idxs = []   
            last_free_idx = 0  
            for i in range(used_num):
                idx = (txq.ci + i) & 0xffff
                desc = await txq.read_avail_desc(idx)
                idxs.append(idx)  
                if not desc.next:
                    chian_idxs.append(idxs) 
                    idxs = []   
                    last_free_idx = idx  
            if len(chian_idxs) > 0:  
                txq.ci = (last_free_idx + 1) & 0xffff  
                self.log.debug("test {} {}".format(chian_idxs, txq.sw_ring.keys()))
            for idxs in chian_idxs:   
                for idx in idxs:   
                    self.mem.free_region(txq.sw_ring[idx & (txq.ring_depth-1)])   
                    del txq.sw_ring[idx & (txq.ring_depth-1)] 
        
        
        avail_num = txq.pi - txq.ci if txq.pi >= txq.ci else txq.pi + 2**16  - txq.ci

        idle_num = txq.ring_depth - avail_num
     
        for idx, chain in enumerate(chains):
            if len(chain) > idle_num:
                #self.log.debug("burst_tx {} return  chains {}".format(qid, len(chains[idx:])))
                return chains[idx:]  #Insufficient space; return the unprocessed chain as a sublist starting from index idx to the end, then exit the burst_tx function
          
            for i, mbuf in enumerate(chain):
                #if qid == 1:
                #    self.log.info("txq write_desc  idx {} reg {} {}".format(txq.pi, hex(mbuf.reg.get_absolute_address(0)), mbuf.length))
                self.log.debug("True mbuf.occupancy_bytes = {}".format(mbuf.reg.occupancy_bytes))
                await txq.write_desc(txq.pi, mbuf.reg, size=mbuf.reg.occupancy_bytes, user0=mbuf.reg.user0, next=i != len(chain)-1, fit=self.is_fit and random.randint(0, 100) < 1)
                idle_num = idle_num - 1
                txq.pi = (txq.pi + 1) & 0xffff
            self.log.debug("burst_tx {} doorbell  pi {}".format(qid, txq.pi))
            
            await self.beq_ctr.doorbell(qid, True, txq.pi)

        #self.log.debug("burst_tx {} idle return  chains {}".format(qid, 0))
        return []  
        
