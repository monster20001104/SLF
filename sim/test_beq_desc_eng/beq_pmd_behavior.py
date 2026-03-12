#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_pmd_behavior.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/04
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/04     Joe Jiang   初始化版本
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

class pmd_txq:
    def __init__(self, mem, qdepth):
        self.desc_sz = len(BeqAvailDesc())
        self.ring_depth = 2**(qdepth-1) * 1024
        self.ring_buf = mem.alloc_region(self.desc_sz * self.ring_depth)
        self.ci_ptr_sz = 64
        self.ci_ptr = mem.alloc_region(self.ci_ptr_sz)
        self.pi = 0

    async def init(self, qid):
        await self.ci_ptr.write(0, bytearray(1)*self.ci_ptr_sz)

    async def get_ci(self):
        ci = int.from_bytes(await self.ci_ptr.read(0, self.ci_ptr_sz), byteorder="little")
        return ci & 0xffff

    async def write_desc(self, pi, desc):
        await self.ring_buf.write(pi*self.desc_sz, desc)

    async def read_desc(self, idx):
        desc_dat = await self.ring_buf.read(idx*self.desc_sz, self.desc_sz)
        return BeqAvailDesc().unpack(desc_dat)

class pmd_rxq:
    def __init__(self, mem, qdepth, mbuf_sz):
        self.log = SimLog("cocotb.tb")
        self.mbuf_sz = mbuf_sz
        self.desc_sz = len(BeqAvailDesc())
        self.ring_depth = 2**(qdepth-1) * 1024
        self.ring_buf = mem.alloc_region(self.desc_sz * self.ring_depth)
        self.sw_ring = {}
        self.pi = 0
        self.ci = 0
        self.ci_ptr_sz = 64
        self.ci_ptr = mem.alloc_region(self.ci_ptr_sz)
        self.mem = mem
    async def init(self, qid):
        for _ in range(self.ring_depth):
            mbuf = self.mem.alloc_region(self.mbuf_sz)            
            await self.write_desc(qid, self.pi, mbuf)
            self.pi = (self.pi + 1) & 0xffff

    async def write_used_desc(self, ci, used_desc):
        idx = (ci%self.ring_depth)
        await self.ring_buf.write(idx*self.desc_sz, used_desc.build()[::-1])

    async def write_desc(self, qid, pi, mbuf):
        phase_tag = 1 if (pi & self.ring_depth) else 0
        idx = (pi%self.ring_depth)
        desc = BeqAvailDesc(soc_buf_addr=mbuf.get_absolute_address(0), soc_buf_len=mbuf.size, avail=1^phase_tag, used=0^phase_tag, next=0)
        self.log.info("rxq write_desc(qid:{}) pi {} ring {} next {} avail {} used {} user0 {} len {} addr {}".format(qid, pi, self.ring_depth, desc.next, desc.avail, desc.used, desc.user0, desc.soc_buf_len, desc.soc_buf_addr))
        await self.ring_buf.write(idx*self.desc_sz, desc.build()[::-1])
        self.sw_ring[idx] = mbuf

    async def read_desc(self, idx):
        idx = idx%self.ring_depth
        desc_dat = await self.ring_buf.read(idx*self.desc_sz, self.desc_sz)
        desc = BeqUsedDesc().from_bytes(desc_dat[::-1])
        self.sw_ring[idx].drop()
        return desc

class beq_pmd_behavior:
    def __init__(self, mem, beq_ctr):
        self.log = SimLog("cocotb.tb")
        self.mem = mem
        self.beqs = {}
        self.beq_ctr = beq_ctr

    def create_queue(self, qid, beq_depth, transfer_type, mbuf_sz=4096):
        q = pmd_txq(self.mem, beq_depth) if qid & 1 else pmd_rxq(self.mem, beq_depth, mbuf_sz)
        self.beq_ctr.create_queue(qid, q.ring_buf.get_absolute_address(0), q.ci_ptr.get_absolute_address(0), q.ci_ptr_sz, beq_depth, transfer_type, mbuf_sz)
        if qid in self.beqs.keys():
            raise ValueError("The rx queue(qid:{}) is already exists".format(qid))
        self.beqs[qid] = q

    def destroy_queue(self, qid):
        self.beq_ctr.destroy_queue(qid)
        if qid not in self.beqs.keys():
            raise ValueError("The rx queue(qid:{}) is not exists".format(qid))
        del self.beqs[qid]

    async def start_queue(self, qid):
        if qid not in self.beqs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        await self.beqs[qid].init(qid)
        await self.beq_ctr.start_queue(qid)
        if not (qid & 1):
            await self.beq_ctr.doorbell(qid, self.beqs[qid].pi)
        await Timer(1, "us")

    async def stop_queue(self, qid):
        await self.beq_ctr.stop_queue(qid)
        timeout = 100
        while not await self.beq_ctr.get_stop_ack(qid) and timeout > 0:
            await Timer(1, "us")
            timeout = timeout - 1
        if timeout == 0:
            raise ValueError("The queue(qid:{}) stop is timeout".format(qid))

    async def burst_tx(self, qid, chains):
        if not (qid & 1):
            raise ValueError("The queue(qid:{}) is rxq".format(qid))
        nchain = 0
        txq = self.beqs[qid]
        for chain in chains:
            ci = await txq.get_ci()
            avail_num = txq.pi - ci if txq.pi >= ci else txq.pi + 2**16  - ci
            if len(chain) > txq.ring_depth - avail_num:
                await Timer(10, "ns")
                break
            ndesc = 0
            for mbuf in chain:
                phase_tag = 1 if (txq.pi & txq.ring_depth) else 0
                availDesc = BeqAvailDesc(soc_buf_addr=mbuf.addr, soc_buf_len=mbuf.len, user0=mbuf.user0, avail=1^phase_tag, next=ndesc != len(chain)-1)
                self.log.debug("txq (qid:{}) put desc addr {} len {} user0 {} pi {}".format(qid, mbuf.addr, mbuf.len, mbuf.user0, txq.pi))
                await txq.write_desc(txq.pi & (txq.ring_depth-1), availDesc.build()[::-1])
                txq.pi = (txq.pi + 1) & 0xffff
                ndesc = ndesc + 1
            nchain = nchain + 1
        await self.beq_ctr.doorbell(qid, txq.pi)
        return chains[nchain:]

    async def burst_rx(self, qid):
        if (qid & 1):
            raise ValueError("The queue(qid:{}) is txq".format(qid))
        rxq = self.beqs[qid]
        used_descs_list = []
        has_used_desc = True
        while has_used_desc:
            avail_num = rxq.pi - rxq.ci if rxq.pi >= rxq.ci else rxq.pi + 2**16  - rxq.ci
            if avail_num == 0:
                break
            used_descs = []
            user = []
            for i in range(avail_num):
                idx = rxq.ci + i
                desc = await rxq.read_desc(idx)
                phase_tag = 1 if (idx & rxq.ring_depth) else 0
                if desc.used == (1^phase_tag) and desc.used == desc.avail:
                    used_descs.append(desc)
                    if not desc.next:
                        used_descs_list.append(used_descs)
                        rxq.ci = (idx + 1) & 0xffff
                        break
                    elif i == avail_num - 1:
                        has_used_desc = False                        
                else:
                    has_used_desc = False
                    break
        avail_num = rxq.pi - rxq.ci if rxq.pi >= rxq.ci else rxq.pi + 2**16  - rxq.ci

        for _ in range(rxq.ring_depth - avail_num):
            mbuf = self.mem.alloc_region(rxq.mbuf_sz)            
            await rxq.write_desc(qid, rxq.pi, mbuf)
            rxq.pi = (rxq.pi + 1) & 0xffff
        await self.beq_ctr.doorbell(qid, rxq.pi)
        return used_descs_list

    #50000 us #only txq
    async def wait_finish(self, qid, timeout = 50000):
        if not (qid & 1):
            raise ValueError("The queue(qid:{}) is rxq".format(qid))
        txq = self.beqs[qid]
        timeout = timeout * 1000/100
        while txq.pi != await txq.get_ci() and timeout > 0:
            await Timer(100, "ns")
            timeout = timeout - 1
            self.log.debug("wait_finish qid {} pi {} ci {}".format(qid, txq.pi, await txq.get_ci()))
        if timeout == 0:
            raise ValueError("The queue(qid:{}) wait_finish is timeout".format(qid))

    


