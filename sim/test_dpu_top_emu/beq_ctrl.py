#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_ctrl.py
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
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout, Lock
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from beq_defines import *


class beq_q_depth_t:
    q1k = 1
    q2k = 2
    q4k = 3
    q8k = 4
beq_q_depth_type_list = [beq_q_depth_t.q1k, beq_q_depth_t.q2k, beq_q_depth_t.q4k, beq_q_depth_t.q8k]
class beq_status_type_t:
    idle        = 1
    starting    = 2
    doing       = 4
    stopping    = 8
class beq_transfer_type_t:
    emu     = 1
    net     = 2
    blk     = 4
    sgdma   = 8
beq_transfer_type_type_list = [beq_transfer_type_t.emu, beq_transfer_type_t.net, beq_transfer_type_t.blk, beq_transfer_type_t.sgdma]
class beq_rx_segment_t:
    sz_512  = 1
    sz_1k   = 2
    sz_2k   = 4
    sz_4k   = 8
    sz_8k   = 16
beq_rx_segment_type_list = [beq_rx_segment_t.sz_512, beq_rx_segment_t.sz_1k, beq_rx_segment_t.sz_2k, beq_rx_segment_t.sz_4k, beq_rx_segment_t.sz_8k]

class beq_ctx(object):
    def __init__(self, pcie_bar, reg_offset, base_addr, ci_ptr_addr, beq_depth, transfer_type, segment_sz=4096, drop_mode=False):
        self.pcie_bar = pcie_bar  
        self.reg_offset = reg_offset
        self.base_addr = base_addr
        self.ci_ptr_addr = ci_ptr_addr
        self.beq_depth = beq_depth
        self.transfer_type = transfer_type
        self.segment_sz = segment_sz
        self.drop_mode = drop_mode
        self.q_status = beq_status_type_t.idle
        self.db_idx = 0

    async def write_reg(self, addr, value):
     
        data = value.to_bytes(8, byteorder="little")
        await self.pcie_bar.write(self.reg_offset+addr, data)

    async def read_reg(self, addr):
      
        data = await self.pcie_bar.read(self.reg_offset+addr, 8)
        return int.from_bytes(data, byteorder="little")

class beq_ctrl:
    def __init__(self, pcie_bar):
        self.log = SimLog("cocotb.tb")
        self.ctxs = {}
        self.pcie_bar = pcie_bar

   
    async def create_queue(self, qid, is_txq, base_addr, ci_ptr_addr, beq_depth, transfer_type, segment_sz, drop_mode):
        reg_offset = (qid * 2 + is_txq) * 0x400 + 0x800000   
        ctx = beq_ctx(self.pcie_bar, reg_offset, base_addr, ci_ptr_addr, beq_depth, transfer_type, segment_sz, drop_mode)
        await ctx.write_reg(0x8, base_addr)
        await ctx.write_reg(0x10, beq_depth)
        await ctx.write_reg(0x20, ci_ptr_addr)
        await ctx.write_reg(0x28, transfer_type)
        await ctx.write_reg(0x30, drop_mode)
        await ctx.write_reg(0x38, segment_sz)
        if qid*2+is_txq in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is already exists".format(qid))
        self.ctxs[qid*2+is_txq] = ctx   

   
    def destroy_queue(self, qid, is_txq):
        if qid*2+is_txq not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        if self.ctxs[qid*2+is_txq].q_status is not beq_status_type_t.idle:
            raise ValueError("The queue(qid:{}) is not idle".format(qid))
        del self.ctxs[qid*2+is_txq] 
    
 
    async def start_queue(self, qid, is_txq, clean_dfx_cnt = True):
        ctx = self.ctxs[qid*2+is_txq]
        q_status = await ctx.read_reg(0)
        if q_status & 0xf != beq_status_type_t.idle:
            raise ValueError("The queue(qid:{}) is not idle".format(qid))
        await ctx.write_reg(0, beq_status_type_t.starting)  
       
        while (q_status & 0xf) is not beq_status_type_t.doing:
            q_status = await ctx.read_reg(0)
            await Timer(1000, "ns")
      
        if clean_dfx_cnt:     
            await ctx.write_reg(0x100, 0) 
            if not is_txq:
                await ctx.write_reg(0x108, 0)  
        
   
    async def stop_queue(self, qid, is_txq):
        ctx = self.ctxs[qid*2+is_txq]
        q_status = await ctx.read_reg(0)
        if q_status & 0xf != beq_status_type_t.doing:
            raise ValueError("The queue(qid:{}) is not doing".format(qid))
        await ctx.write_reg(0, beq_status_type_t.stopping)
        while (q_status & 0xf) is not beq_status_type_t.idle:
            q_status = await ctx.read_reg(0)
            await Timer(1000, "ns")
        #await self.get_beq_status(qid, is_txq)

    async def get_beq_status(self, qid, is_txq):
        if qid*2+is_txq not in self.ctxs.keys():
            return
        ctx = self.ctxs[qid*2+is_txq]

        tmp = await ctx.read_reg(0x40) 
        pi = tmp & 0xffff
        ci = (tmp >> 16) & 0xffff
        db_idx = (tmp >> 32) & 0xffff
        #ci = await ctx.read_reg(0x48)
        err_code = await ctx.read_reg(0x50)
        pkt_cnt = await ctx.read_reg(0x100)
        if not is_txq:
            pkt_drop_cnt = await ctx.read_reg(0x108)
        else:
            pkt_drop_cnt = 0
        local_pi = await ctx.read_reg(0x180)
        local_ci = await ctx.read_reg(0x188)
        local_ui = await ctx.read_reg(0x190)
        if is_txq:
            avail_chain_pi = await ctx.read_reg(0x198)
            avail_chain_ci = await ctx.read_reg(0x1a0)
        else:
            avail_chain_pi = 0
            avail_chain_ci = 0

        self.log.info("{}({}) get_beq_status db_idx {} pi {} ci {} err_code {} pkt_cnt {} pkt_drop_cnt {} local_pi {} local_ci {} local_ui {} avail_chain_pi {} avail_chain_ci {}".format(
                        "txq" if is_txq else "rxq" ,qid, hex(db_idx), hex(pi), hex(ci), err_code, hex(pkt_cnt), hex(pkt_drop_cnt),
                        hex(local_pi), hex(local_ci), hex(local_ui),
                        hex(avail_chain_pi), hex(avail_chain_ci)))
        return pi, ci, err_code, pkt_cnt, pkt_drop_cnt, local_pi, local_ci, local_ui, avail_chain_pi, avail_chain_ci
    
   
    async def wait_idle_queue(self, qid, is_txq):
        ctx = self.ctxs[qid*2+is_txq]
        q_status = await ctx.read_reg(0)
        while (q_status & 0xf) is not beq_status_type_t.idle:
            q_status = await ctx.read_reg(0)
            await Timer(1000, "ns")

    async def doorbell(self, qid, is_txq, idx):
        ctx = self.ctxs[qid*2+is_txq]
        await ctx.write_reg(0x18, idx) 