#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_ctx_ctrl.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/01/09
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  01/09     Joe Jiang   初始化版本
################################################################################
import cocotb
import logging
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout, Lock
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from defines import *
import random

#2**(value-1)*1024
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
    def __init__(self, ring_ptr_addr, beq_depth, segment_sz, drop_mode, db_idx=0, pi=0, ci=0):
        self.base_addr = ring_ptr_addr
        self.beq_depth = beq_depth
        self.segment_sz = segment_sz
        self.drop_mode = drop_mode
        self.db_idx = db_idx
        self.pi = pi
        self.ci = ci
        self.q_status = beq_status_type_t.idle


class beq_ctx_ctrl_callback(object):
    def _ringInfoRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)//2
        if qid not in self.ctxs.keys():
            #raise ValueError("The queue(qid:{}) is not exists".format(qid))
            rsp = RingInfoRdRspTransaction()
            rsp.rsp_base_addr = 0
            rsp.rsp_qdepth = 0
            return rsp
        else:
            rsp = RingInfoRdRspTransaction()
            rsp.rsp_base_addr = self.ctxs[qid].base_addr
            rsp.rsp_qdepth = self.ctxs[qid].beq_depth
            return rsp

    def _ringCiRdCallback(self, req_obj):
        qid = int(req_obj.rd_req_qid)
        self.log.debug("_ringCiRdCallback {}".format(qid))
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = RingCiRdRspTransaction()
        rsp.rd_rsp_dat = self.ctxs[qid].ci
        return rsp

    def _ringCiWrCallback(self, rsq_obj):
        qid = int(rsq_obj.wr_qid)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].ci = int(rsq_obj.wr_dat)

    def _dropModeRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)
        self.log.debug("_ringCiRdCallback {}".format(qid))
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = DropModeRdRspTransaction
        rsp.rsp_dat = self.ctxs[qid].drop_mode
        return rsp

    def _segmentSizeRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)
        self.log.debug("_ringCiRdCallback {}".format(qid))
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = SegmentSizeRdRspTransaction()
        rsp.rsp_dat = self.ctxs[qid].segment_sz
        return rsp

    def _net_qid2bidRdCallback(self, req_obj):
        idx = int(req_obj.req_idx)
        self.log.debug("_ringCiRdCallback {}".format(idx))
        if idx not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(idx))
        rsp = Qid2BidRdRspTransaction()
        rsp.rsp_dat = idx #self.net_qid2bid[idx]
        return rsp

    def _blk_qid2bidRdCallback(self, req_obj):
        idx = int(req_obj.req_idx)
        self.log.debug("_ringCiRdCallback {}".format(idx))
        if idx not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(idx))
        rsp = Qid2BidRdRspTransaction()
        rsp.rsp_dat = idx #self.blk_qid2bid[idx]
        return rsp

class beq_ctx_ctrl(beq_ctx_ctrl_callback):
    def __init__(self, mem, clk, net_qid2bidTblIf, blk_qid2bidTblIf, 
                    dropModeTblIf, segmentSizeRdTblIf, 
                    ringInfoRdTblIf, ringCiTblIf, csr_if):

        self.log = SimLog("cocotb.tb")
        self.clk                = clk
        self.mem                = mem
        self.net_qid2bidTblIf = net_qid2bidTblIf
        self.blk_qid2bidTblIf = blk_qid2bidTblIf
        self.dropModeTblIf    = dropModeTblIf
        self.segmentSizeRdTblIf= segmentSizeRdTblIf
        self.ringInfoRdTblIf  = ringInfoRdTblIf
        self.ringCiTblIf      = ringCiTblIf

        self.net_qid2bidTblIf.set_callback(self._net_qid2bidRdCallback)
        self.blk_qid2bidTblIf.set_callback(self._blk_qid2bidRdCallback)
        self.dropModeTblIf.set_callback(self._dropModeRdCallback)
        self.segmentSizeRdTblIf.set_callback(self._segmentSizeRdCallback)
        self.ringInfoRdTblIf.set_callback(self._ringInfoRdCallback)
        self.ringCiTblIf.set_callback(self._ringCiRdCallback)
        self.ringCiTblIf.set_wr_callback(self._ringCiWrCallback)

        self.doorbellQueue = Queue(maxsize=64)

        self.ctxs = {}

        self.csr_if = csr_if


    async def create_queue(self, qid, ring_ptr_addr, beq_depth, segment_sz, drop_mode):
        ctx = beq_ctx(ring_ptr_addr, beq_depth, segment_sz, drop_mode)
        if qid in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is already exists".format(qid))
        self.ctxs[qid] = ctx

    def destroy_queue(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        if self.ctxs[qid].q_status is not beq_status_type_t.idle:
            raise ValueError("The queue(qid:{}) is not idle".format(qid))
        del self.ctxs[qid]

    def get_status(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        return self.ctxs[qid].q_status

    async def start_queue(self, qid):
        
        self.log.debug("start_queueqqqqqqqq")   
        self.ctxs[qid].q_status = beq_status_type_t.doing

    async def clear_cnt(self, qid):
        await self.csr_if.write((0x100 | (qid << 11)), 0)  #clear pkt_cnt 0   
        await self.csr_if.write((0x108 | (qid << 11)), 0)  #clear pkt_drop_cnt 0


    async def stop_queue(self, qid):
        self.ctxs[qid].q_status = beq_status_type_t.idle       

    async def read_drop_cnt(self, qid):
        #addr:0x108 + (qid << 11)
        addr = 0x108 | (qid << 11)
        self.log.debug("drop_cnt_addr = %0x",addr)
        rsp = await self.csr_if.read(addr)
        return rsp & 0xFFFF  

    async def doorbell(self, qid, idx):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        cxt = self.ctxs[qid]
        cxt.db_idx = idx  
        ring_sz = 2**(cxt.beq_depth-1) * 1024
        avail_num = cxt.db_idx - cxt.ci if cxt.db_idx > cxt.ci else cxt.db_idx + 2**16 - cxt.ci  
        assert avail_num <= ring_sz
