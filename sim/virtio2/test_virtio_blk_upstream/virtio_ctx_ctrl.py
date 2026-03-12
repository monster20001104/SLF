#!/usr/bin/env python3
################################################################################
#  文件名称 : virtio_ctx_ctrl.py
#  作者名称 : cui naiwan
#  创建日期 : 2025/07/08
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/08     cui naiwan   初始化版本
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

class virtio_ctx(object):
    def __init__(self, dev_id, bdf, generation, forced_shutdown):
        self.dev_id = dev_id 
        self.bdf = bdf
        self.generation = generation
        self.forced_shutdown = forced_shutdown
        self.blk_upstream_ptr = 0

class virtio_ctx_ctrl_callback(object):
    def _blkupstreamctxRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)
        if qid not in self.ctxs.keys():
            #raise ValueError("The queue(qid:{}) is not exists".format(qid))
            rsp = BlkupstreamCtxRdRspTransaction()
            rsp.rsp_forced_shutdown = 0
            rsp.rsp_generation = 0
            rsp.rsp_dev_id = 0
            rsp.rsp_bdf = 0
            return rsp
        else:
            rsp = BlkupstreamCtxRdRspTransaction()
            rsp.rsp_forced_shutdown = self.ctxs[qid].forced_shutdown
            rsp.rsp_generation = self.ctxs[qid].generation
            rsp.rsp_dev_id = self.ctxs[qid].dev_id
            rsp.rsp_bdf = self.ctxs[qid].bdf
            return rsp
        
    def _blkupstreamptrRdCallback(self, req_obj):
        qid = int(req_obj.rd_req_qid)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = BlkupstreamPtrRdRspTransaction()
        rsp.rd_rsp_dat = self.ctxs[qid].blk_upstream_ptr
        return rsp
    
    def _blkupstreamptrWrCallback(self, wr_obj):
        qid = int(wr_obj.wr_req_qid)
        dat = int(wr_obj.wr_req_dat)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].blk_upstream_ptr = dat  

class virtio_ctx_ctrl(virtio_ctx_ctrl_callback):
    def __init__(self, clk, blkupstreamctxRdTblIf, blkupstreamptrIf):
        self.log = SimLog("cocotb.virtio_ctx_ctrl")
        self.log.setLevel(logging.DEBUG)
        self.clk = clk
        self.ctxs = {}   
        self.blkupstreamctxRdTblIf = blkupstreamctxRdTblIf
        self.blkupstreamptrIf = blkupstreamptrIf
        
        self.blkupstreamctxRdTblIf.set_callback(self._blkupstreamctxRdCallback)
        self.blkupstreamptrIf.set_callback(self._blkupstreamptrRdCallback)
        self.blkupstreamptrIf.set_wr_callback(self._blkupstreamptrWrCallback)

    async def create_queue(self, qid, dev_id, bdf, generation, forced_shutdown):
        ctx = virtio_ctx(dev_id, bdf, generation, forced_shutdown)
        if qid in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is already exists".format(qid))
        self.ctxs[qid] = ctx

    def destroy_queue(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        del self.ctxs[qid]


