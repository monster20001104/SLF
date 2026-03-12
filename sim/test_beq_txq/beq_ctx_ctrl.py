#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_ctx_ctrl.py
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
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout, Lock
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from defines import *

class beq_transfer_type_t:
    emu     = 1
    net     = 2
    blk     = 4
    sgdma   = 8
beq_transfer_type_type_list = [beq_transfer_type_t.emu, beq_transfer_type_t.net, beq_transfer_type_t.blk, beq_transfer_type_t.sgdma]

class beq_status_type_t:
    idle        = 1
    starting    = 2
    doing       = 4
    stopping    = 8

class beq_ctx(object):
    def __init__(self, ci_ptr_addr, ci_ptr_sz, transfer_type, pi=0, ci=0, local_ci=0, local_out_cnt = 0):
        self.ci_ptr_addr = ci_ptr_addr  
        self.ci_ptr_sz = ci_ptr_sz
        self.transfer_type = transfer_type
        self.pi = pi
        self.ci = ci
        self.local_ci = local_ci
        self.local_out_cnt = local_out_cnt
        self.err_info = 0
        self.q_status = beq_status_type_t.idle

class beq_ctx_ctrl_callback(object):
    def _ringCiAddrRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)   
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = RingCiAddrRdRspTransaction()
        rsp.rsp_dat = self.ctxs[qid].ci_ptr_addr
        return rsp
    def _ringCiRdCallback(self, req_obj):
        qid = int(req_obj.rd_req_qid)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = RingCiRdRspTransaction()
        rsp.rd_rsp_dat = self.ctxs[qid].ci
        return rsp
    def _ringCiWrCallback(self, wr_obj):
        qid = int(wr_obj.wr_qid)
        dat = int(wr_obj.wr_dat)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].ci = dat  

    def _errInfoRdCallback(self, req_obj):
        qid = int(req_obj.rd_req_qid)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = RingCiRdRspTransaction()
        rsp.rd_rsp_dat = self.ctxs[qid].err_info
        return rsp

    def _errInfoWrCallback(self, wr_obj):
        qid = int(wr_obj.wr_qid)
        dat = int(wr_obj.wr_dat)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].err_info = dat

class beq_ctx_ctrl(beq_ctx_ctrl_callback):
    def __init__(self, mem, clk, ringCiAddrRdTblIf,  ringCiTblIf, errInfoTblIf):
        self.log = SimLog("cocotb.beq_ctx_ctrl")
        self.log.setLevel(logging.DEBUG)
        self.clk = clk
        self.mem = mem
        self.ctxs = {}   
        self.ringCiAddrRdTblIf = ringCiAddrRdTblIf
        self.ringCiTblIf = ringCiTblIf
        self.errInfoTblIf = errInfoTblIf

        
        self.ringCiAddrRdTblIf.set_callback(self._ringCiAddrRdCallback)
        self.ringCiTblIf.set_callback(self._ringCiRdCallback)
        self.ringCiTblIf.set_wr_callback(self._ringCiWrCallback)
        self.errInfoTblIf.set_callback(self._errInfoRdCallback)
        self.errInfoTblIf.set_wr_callback(self._errInfoWrCallback)

    def get_typ(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        return self.ctxs[qid].transfer_type

    async def get_txq_used_ptr(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        ci_ptr_addr = self.ctxs[qid].ci_ptr_addr
        ci_ptr_sz = self.ctxs[qid].ci_ptr_sz
        ci = int.from_bytes(await self.mem.read(ci_ptr_addr, ci_ptr_sz), byteorder="little")
        return ci & 0xffff

    def pi_inc(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].pi = (self.ctxs[qid].pi + 1) & 0xffff

    def get_pi(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        return self.ctxs[qid].pi
    
    def get_ci(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        return self.ctxs[qid].ci

    async def create_queue(self, qid, ci_ptr_addr, ci_ptr_sz, transfer_type):
        self.log.debug("create_queueqqqqqqqq")
        ctx = beq_ctx(ci_ptr_addr, ci_ptr_sz, transfer_type)
        if qid in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is already exists".format(qid))
        self.ctxs[qid] = ctx

    async def start_queue(self, qid):
        
        self.log.debug("start_queueqqqqqqqq")   
        self.ctxs[qid].err_info = 0
        self.ctxs[qid].local_out_cnt = 0
        self.ctxs[qid].pi = 0
        self.ctxs[qid].ci = 0
        self.ctxs[qid].q_status = beq_status_type_t.doing

    def stop_queue(self, qid):
        self.log.debug("stop_queueqqqqqqqq") 
        self.ctxs[qid].q_status = beq_status_type_t.stopping     

    
    async def wait_idle_queue(self, qid, timeout=50000):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))

        timeout = timeout * 1000/1000

        # break while,if ci==pi or timeout
        while self.get_ci(qid) != self.ctxs[qid].local_ci and timeout > 0:
            await Timer(1, "ns")
            timeout = timeout - 1
            self.log.info("wait_idle_queue qid {} ci {} local_ci {}".format(qid, self.get_ci(qid), self.ctxs[qid].local_ci))
        if self.get_ci(qid) == self.ctxs[qid].local_ci:
            self.log.debug("idle")
            self.ctxs[qid].q_status = beq_status_type_t.idle

        if timeout == 0:
            raise ValueError("The queue(qid:{}) wait_finish is timeout".format(qid))
        
        #while True:
            #current_ci = self.get_ci(qid) & 0x1f
            #self.log.debug("current_ci = {}".format(current_ci))
            #if current_ci == self.ctxs[qid].local_ci:
                #self.ctxs[qid].q_status = beq_status_type_t.idle 
                #break
            #else:
                #await Timer (5000, "us")
                #break

        #not_equal = (self.get_ci(qid) & 0x1f) != self.ctxs[qid].local_ci
        #while not_equal:
            #current_ci = self.get_ci(qid) & 0x1f
            #not_equal = current_ci != self.ctxs[qid].local_ci
            #self.log.info("wait_idle_queue qid {} ci {} local_ci {}".format(qid, self.get_ci(qid), self.ctxs[qid].local_ci))

        #if (self.get_ci(qid) & 0x1f) == self.ctxs[qid].local_ci:
            #self.ctxs[qid].q_status = beq_status_type_t.idle 

        
    def destroy_queue(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        if self.ctxs[qid].ci != self.ctxs[qid].pi:
            raise ValueError("The queue(qid:{}) is not idle".format(qid))
        del self.ctxs[qid]

    async def doorbell(self, qid, idx, beq_depth):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        cxt = self.ctxs[qid]
        cxt.db_idx = idx  
        #ring_sz = 2**(beq_depth-1) * 1024
        avail_num = cxt.db_idx - cxt.ci if cxt.db_idx > cxt.ci else cxt.db_idx + 2**16 - cxt.ci  
        assert avail_num <= beq_depth