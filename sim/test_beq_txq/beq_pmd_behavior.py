#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_pmd_behavior.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/12
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/12     Joe Jiang   初始化版本
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
from beq_desc_eng import *
import random
class pmd_txq:
    def __init__(self, mem, qid, ring_depth=1024):
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)  
        self.mem = mem
        self.qid = qid
        self.ring_depth = ring_depth
        self.desc_sz = len(BeqAvailDesc())
        self.ring_queue = Queue(maxsize=self.ring_depth)
        #self.ring_queue = Queue()
        self.ring_buf = self.mem.alloc_region(self.desc_sz * self.ring_depth)
        self.ci_ptr_sz = 64 
        self.ci_ptr = mem.alloc_region(self.ci_ptr_sz)  
        self.desc_cnt = 0
        self.sw_ring = {}  
        self.pi = 0  
        self.ci = 0 
    
    async def reset(self):
        self.sw_ring = {}  
        self.pi = 0
        self.ci = 0
        await self.ci_ptr.write(0, b'\00'*self.ci_ptr_sz)  #0:addr

    async def init(self):
        # init ci_ptr 0
        await self.ci_ptr.write(0, bytearray(1)*self.ci_ptr_sz)  #0:addr bytearry(1)*self.ci_ptr_sz = 64bytes

    #write desc
    #async def write_desc(self, desc):
    #    await self.ring.put((desc,self.desc_cnt))
    #    self.desc_cnt = self.desc_cnt + 1

    async def write_desc(self, pi, reg, size, user0 = 0, next=0, fit=False): 
        phase_tag = 1 if (pi & self.ring_depth) else 0 
       
        soc_buf_len = size
        '''
        if fit:
            soc_buf_addr = 0
        else:
            soc_buf_addr=reg.get_absolute_address(0)
        '''
    
        soc_buf_addr=reg.get_absolute_address(reg.headr_room)
  
        if fit:  
            #desc = BeqAvailDesc(soc_buf_addr=soc_buf_addr, soc_buf_len=soc_buf_len, avail=0^phase_tag, used=1^phase_tag, user0=user0, next=next)
            desc = BeqAvailDesc(soc_buf_addr=soc_buf_addr, soc_buf_len=0, avail=1^phase_tag, used=0^phase_tag, user0=user0, next=next)
        else:
            desc = BeqAvailDesc(soc_buf_addr=soc_buf_addr, soc_buf_len=soc_buf_len, avail=1^phase_tag, used=0^phase_tag, user0=user0, next=next)
        
           
        idx = pi & (self.ring_depth-1)

        if size is None or size <= 0:
            self.log.error(f"size={size}")
            raise ValueError(f"size is > 0, current {size}")
    

        if size is not None:  
            self.log.debug("txq write_desc  idx {} desc {}".format(idx, desc.show(dump=True)))
        
       
        await self.ring_buf.write(idx*self.desc_sz, desc.build()[::-1])
        self.log.debug("cuinw1")
        await self.ring_queue.put((desc,self.desc_cnt)) 
        self.log.debug("cuinw2")
        self.desc_cnt = self.desc_cnt + 1
        self.sw_ring[idx] = reg 
        #self.log.info(f"txq.sw_ring add:idx={idx},current sw_ring :{list(self.sw_ring.keys())}")


    #def __del__(self):
        #self.mem.free_region(self.ci_ptr)  #free ci_ptr mem

    async def read_avail_desc(self, idx):
        desc_dat = await self.ring_buf.read((idx & (self.ring_depth-1))*self.desc_sz, self.desc_sz)
        return BeqAvailDesc().unpack(desc_dat[::-1])

    #async def get_txq_used_ptr(self):
    #    self.log.debug("get used ptr")
    #    data = int.from_bytes(await self.ci_ptr.read(0, self.ci_ptr_sz), byteorder="little") & 0xffffffff
    #    return data&0x80000000 != 0, data&0xffff  #[31]:error_flag, [15:0]:used_ptr

    async def get_txq_used_ptr(self):
        self.log.debug("get used ptr")
        data = int.from_bytes(await self.ci_ptr.read(0, self.ci_ptr_sz), byteorder="little") & 0xffffffff
        err_flag = data & 0x80000000 != 0
        used_ptr = data & 0xffff   
        return err_flag, used_ptr
  
    async def get_used_num(self, used_ptr):
        ring_depth = self.ring_depth
        used_ptr = used_ptr & 0xffff
        current_ci = self.ci & 0xffff
    
        if used_ptr >= current_ci:   
            used_num = used_ptr - current_ci
        else:
            used_num = (used_ptr + (1 << 16)) - current_ci
    
        used_num = min(used_num, ring_depth)
        used_num = max(used_num, 0)
    
        self.log.debug(
            f"qid={self.qid} get_used_num: used_ptr={used_ptr}, ci={current_ci}, used_num={used_num}"
        )
        return used_num

        

class beq_pmd_behavior:
    def __init__(self, mem, ring_queues, beq_ctr, beq_desc_eng, is_fit=False):
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.mem = mem
        self.txqs = {}   
        self.ring_queues = ring_queues
        self.is_fit = is_fit
        self.cnts = {} #per ring desc cnt
        self.beq_ctr = beq_ctr
        self.beq_desc_eng = beq_desc_eng
        self.queue_locks = {}

    async def create_queue(self, qid, transfer_type):
        self.log.debug("create queue start")
        q = pmd_txq(self.mem, qid)  

        if qid in self.txqs.keys():
            raise ValueError("The queue(qid:{}) q is already exists".format(qid))
        if qid in self.ring_queues.keys():
            raise ValueError("The queue(qid:{}) ring is already exists".format(qid))
        
        await q.init() 
        self.ring_queues[qid] = q.ring_queue
        self.txqs[qid] = q  
 
        await self.beq_ctr.create_queue(qid, q.ci_ptr.get_absolute_address(0), q.ci_ptr_sz, transfer_type)  
        self.log.debug("create queue end")

    async def start_queue(self, qid):
        self.log.debug("start queue start")
        if qid not in self.txqs.keys():
            raise ValueError("The queue(qid:{}) q is not exists".format(qid))
       
        #clear local_desc_buf
        if qid in self.beq_desc_eng.local_desc_buf:
            while not self.beq_desc_eng.local_desc_buf[qid].empty():
                desc,desc_cnt = self.beq_desc_eng.local_desc_buf[qid].get_nowait()
            if self.beq_desc_eng.local_desc_buf[qid].empty():
                self.log.debug("clear local desc buf done")

        #clear local_chain
        if qid in self.beq_desc_eng.local_chain:
            while not self.beq_desc_eng.local_chain[qid].empty():
                self.beq_desc_eng.local_chain[qid].get_nowait()
            if self.beq_desc_eng.local_chain[qid].empty():
                self.log.debug("clear local chain done")

        await self.beq_ctr.start_queue(qid)
        self.log.debug("start queue end")


    def destroy_queue(self, qid):
        self.beq_ctr.destroy_queue(qid)  
        
        if qid not in self.txqs.keys():
            raise ValueError("The queue(qid:{}) q is not exists".format(qid))
        if qid not in self.ring_queues.keys():
            raise ValueError("The queue(qid:{}) ring is already exists".format(qid))

        #for idx in self.txqs[qid].sw_ring.keys():
            #self.log.debug("self.txqs[qid].sw_ring[idx]={}".format(self.txqs[qid].sw_ring[idx].get_absolute_address(0)))
            #self.mem.free_region(self.txqs[qid].sw_ring[idx])

        #for idx in list(self.txqs[qid].sw_ring.keys()):  
        #    reg = self.txqs[qid].sw_ring[idx]
        #    self.mem.free_region(reg)
        #    self.log.debug(f"destroy_queue qid:{qid} free reg addr:0x{reg.get_absolute_address(0):x}")
        #    del self.txqs[qid].sw_ring[idx]

        self.mem.free_region(self.txqs[qid].ring_buf)
        self.mem.free_region(self.txqs[qid].ci_ptr)
        
        del self.txqs[qid]
        del self.ring_queues[qid]


    async def wait_finish(self, qid, timeout = 50000):
        timeout = timeout * 1000/1000
        txq = self.txqs[qid]

        # break while,if ci==pi or timeout
        while timeout > 0:
            err, used_ptr = await txq.get_txq_used_ptr()
            #used_ptr = used_ptr % txq.ring_depth  
            pi = self.beq_ctr.get_pi(qid)
            #pi = pi % txq.ring_depth

            if used_ptr == pi:
                self.log.info(f"wait_finish qid {qid} done: used_ptr={used_ptr} == pi={pi}")
                return
        
            self.log.info(f"wait_finish qid {qid}: pi={pi}, used_ptr={used_ptr}, timeout_remaining={timeout}")
            
            await self.burst_tx(qid, [])
            await Timer(1, "us")
            timeout -= 1

        raise ValueError(f"The queue(qid:{qid}) wait_finish is timeout (used_ptr={used_ptr}, pi={pi})")
  
#    async def burst_tx(self, qid, chains):
#        nchain = 0  
#        txq = self.txqs[qid]  
           
#        if qid not in self.cnts.keys():
#            self.cnts[qid] = 0
        #process per chain
#        for chain in chains:
#            ndesc = 0  
            #process per mbuf in chain
#            for mbuf in chain:
#                phase_tag = 1 if (self.beq_ctr.get_pi(qid) & txq.ring_depth) else 0 #first cycle:0
                
                #create available desc
#                availDesc = BeqAvailDesc(soc_buf_addr=mbuf.addr, soc_buf_len=mbuf.reg.size, user0=mbuf.user0, avail=1^phase_tag, next=ndesc != len(chain)-1)
#                self.log.debug("put desc(cnt:{}) to ring(qid:{}) soc_buf_addr {} soc_buf_len {} next {} avail {}".format(self.cnts[qid], qid, hex(availDesc.soc_buf_addr), hex(availDesc.soc_buf_len), availDesc.next, availDesc.avail))
#                if mbuf.reg.size == 0:
#                    raise ValueError("desc soc_buf_len == 0 when queue(qid:{}) write_desc".format(qid))
                
                #write desc and increase pi
#                await txq.write_desc(availDesc)
#                self.cnts[qid] = self.cnts[qid] + 1
#                self.beq_ctr.pi_inc(qid)  
#                ndesc = ndesc + 1
#                self.log.debug("write_desc_num = {} qid:{}".format(self.cnts[qid],qid))
                 
    async def burst_tx(self, qid, chains):
        if qid not in self.queue_locks:
            self.queue_locks[qid] = Lock()
            
        async with self.queue_locks[qid]:
            txq = self.txqs[qid]  
            avail_num = txq.pi - txq.ci if txq.pi >= txq.ci else txq.pi + 2**16  - txq.ci  
            #self.log.debug("burst_tx {} chains len {}".format(qid, len(chains)))
            err, used_ptr = await txq.get_txq_used_ptr()  #read used ptr
            self.log.debug("qid = {} err = {} used_ptr = {}".format(qid, err, used_ptr))
            
            #err handle
            if err:   
                self.log.debug("burst_tx err {} used_ptr {} err".format(qid, used_ptr))
                # wait stop done
                self.log.debug("qid {} wait stop done".format(qid))
                await self.beq_ctr.wait_idle_queue(qid)  #wait queue idle,confirm rtl finish
                while not self.ring_queues[qid].empty():
                    _ = self.ring_queues[qid].get_nowait()
                
                # found chain
                self.log.debug("qid {} before found chain ci {} used_ptr {} used".format(qid, txq.ci, used_ptr))
                used_num = used_ptr - txq.ci if used_ptr >= txq.ci else used_ptr + 2**16  - txq.ci 
                old_next = False 
                for i in range(used_num):
                    idx = (used_ptr-i-1) & 0xffff  #从硬件完成指针（used_ptr）向前遍历，逆向扫描的原因是如果出错的描述符是chain中后面的描述符，则要根据上一个desc的old_next和当前used_ptr指向的desc的next精准定位链头，确保完整的chain被回收
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
                    #self.mem.free_region(txq.sw_ring[idx & (txq.ring_depth-1)]) 
                    del txq.sw_ring[idx & (txq.ring_depth-1)]   
                txq.ci = used_ptr  
                self.log.debug("qid {} store avail data".format(qid))
                # store avail data  
                avail_chains    = []
                avail_chain     = []
                self.log.debug("txq.pi = {} txq.ci = {}".format(txq.pi, txq.ci))
                avail_num = txq.pi - txq.ci if txq.pi >= txq.ci else txq.pi + 2**16  - txq.ci  
                for i in range(avail_num):
                    idx = txq.ci + i
                    desc = await txq.read_avail_desc(idx)
                    self.log.debug("store avail data idx = {}".format(idx))
                    reg = txq.sw_ring[idx & (txq.ring_depth-1)]
                    avail_chain.append(beq_mbuf(addr=reg.get_absolute_address(reg.headr_room), reg=reg,  user0=desc.user0))
                    #avail_chain.append(beq_mbuf(addr=txq.sw_ring[idx & (txq.ring_depth-1)].get_absolute_address(txq.sw_ring[idx & (txq.ring_depth-1)].headr_room), reg=txq.sw_ring[idx & (txq.ring_depth-1)],  user0=desc.user0))
                    del txq.sw_ring[idx & (txq.ring_depth-1)]
                    if not desc.next:  
                        avail_chains.append(avail_chain)
                        avail_chain     = []  
                self.log.debug("qid {} restart".format(qid))
                # restart 
                await txq.reset()  
                await self.start_queue(qid)   
                self.log.debug("qid {} load old data".format(qid))
                # load old data
                for idx, avail_chain in enumerate(avail_chains):   
                    for i, mbuf in enumerate(avail_chain):
                        await txq.write_desc(txq.pi, mbuf.reg, size=mbuf.reg.size-mbuf.reg.headr_room, user0=mbuf.user0, next=i != len(avail_chain)-1)
                        txq.pi = (txq.pi + 1) & 0xffff
                        self.beq_ctr.pi_inc(qid) 
                        self.log.debug("txq.pi = {} pi = {}".format(txq.pi, self.beq_ctr.get_pi))
                await self.beq_ctr.doorbell(qid, txq.pi, txq.ring_depth) 
                self.log.info("qid {} queue recovery done".format(qid))
                return chains  
                
                #raise ValueError("the queue(qid:{}) is err".format(qid))
            #used_num = used_ptr - txq.ci if used_ptr >= txq.ci else used_ptr + 2**16  - txq.ci
            used_num = await txq.get_used_num(used_ptr)
    
            
            if True:      #txq.ring_depth - avail_num < 256:
                #used_num = used_ptr - txq.ci if used_ptr >= txq.ci else used_ptr + 2**16  - txq.ci
                used_num = await txq.get_used_num(used_ptr)
                self.log.debug("used_num = {} used_ptr = {} txq.ci = {}".format(used_num, used_ptr, txq.ci))
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
                        self.log.info("del txq.sw_ring[idx & (txq.ring_depth-1)] = {}".format(idx & (txq.ring_depth-1)))
                        #self.mem.free_region(txq.sw_ring[idx & (txq.ring_depth-1)]) 
                        sw_key = idx & (txq.ring_depth - 1)  
                        if sw_key in txq.sw_ring:
                            del txq.sw_ring[sw_key]
                            self.log.debug(f"qid={qid} del sw_ring Key:{sw_key}(idx={idx})")  
                        else:
                            self.log.warning(f"qid={qid} skip sw_ring Key:{sw_key}(idx={idx},sw_ring keys:{list(txq.sw_ring.keys())[:5]}...)")
                        #del txq.sw_ring[idx & (txq.ring_depth-1)] 
            
            
            avail_num = txq.pi - txq.ci if txq.pi >= txq.ci else txq.pi + 2**16  - txq.ci
    
            idle_num = txq.ring_depth - avail_num
            self.log.debug("qid = {} idle_num = {} txq.ring_depth = {} avail_num = {} txq.pi = {} txq.ci = {}".format(qid, idle_num, txq.ring_depth, avail_num, txq.pi, txq.ci))
            
            for idx, chain in enumerate(chains):
                if len(chain) > idle_num:    
                    self.log.debug("burst_tx qid {} len(chain) {} return  chains {}".format(qid, len(chain), len(chains[idx:])))
                    return chains[idx:]  
                
                for i, mbuf in enumerate(chain):
                    #if qid == 1:
                    #self.log.info("i = {} txq size={} chain_len={}".format(i, mbuf.reg.size, len(chain)))
                    await txq.write_desc(txq.pi, mbuf.reg, size=mbuf.reg.size-mbuf.reg.headr_room, user0=mbuf.user0, next=i != len(chain)-1, fit=self.is_fit and random.randint(0, 100) < 1)
                    self.log.info("2i = {} txq size={} chain_len={}".format(i, mbuf.reg.size, len(chain)))
                    idle_num = idle_num - 1
                    txq.pi = (txq.pi + 1) & 0xffff
                    self.beq_ctr.pi_inc(qid) 
                self.log.debug("burst_tx {} doorbell  pi {}".format(qid, txq.pi))
                
                await self.beq_ctr.doorbell(qid, txq.pi, txq.ring_depth)
    
            #self.log.debug("burst_tx {} idle return  chains {}".format(qid, 0))
            return []  

    def get_code(self, qid):
        return self.beq_ctr.get_code(qid) 