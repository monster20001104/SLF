#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_ctx_ctrl.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/03
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/03     Joe Jiang   初始化版本
################################################################################
import cocotb
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout, Lock
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from defines import *

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
    def __init__(self, base_addr, ci_ptr_addr, ci_ptr_sz, beq_depth, transfer_type, segment_sz=4096, db_idx=0, pi=0, ci=0):
        self.base_addr = base_addr
        self.ci_ptr_addr = ci_ptr_addr
        self.ci_ptr_sz = ci_ptr_sz
        self.beq_depth = beq_depth
        self.transfer_type = transfer_type
        self.segment_sz = segment_sz
        self.db_idx = db_idx
        self.pi = pi
        self.ci = ci
        self.q_status = beq_status_type_t.idle

class beq_ctx_ctrl_callback(object):
    def _ringInfoRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)
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

    def _rxqTransferTypeRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)*2
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = TransferTypeRdRspTransaction()
        rsp.rsp_dat = self.ctxs[qid].transfer_type
        return rsp
    
    def _txqTransferTypeRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)*2+1
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = TransferTypeRdRspTransaction()
        rsp.rsp_dat = self.ctxs[qid].transfer_type
        return rsp

    def _ringDbIdxRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)
        if qid not in self.ctxs.keys():
            rsp = RingDbIdxRdRspTransaction()
            rsp.rsp_dat = 0
            return rsp
        else:
            #raise ValueError("The queue(qid:{}) is not exists".format(qid))
            rsp = RingDbIdxRdRspTransaction()
            rsp.rsp_dat = self.ctxs[qid].db_idx
            return rsp

    def _ringCiRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)
        self.log.info("_ringCiRdCallback {}".format(qid))
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = RingCiRdRspTransaction()
        rsp.rsp_dat = self.ctxs[qid].ci
        return rsp

    def _ringPiRdCallback(self, req_obj):
        qid = int(req_obj.rd_req_qid)
        if qid not in self.ctxs.keys():
            rsp = RingPiRdRspTransaction()
            rsp.rd_rsp_dat = 0
            return rsp
        else:
            rsp = RingPiRdRspTransaction()
            rsp.rd_rsp_dat = self.ctxs[qid].pi
            return rsp

    def _ringPiWrCallback(self, rsq_obj):
        qid = int(rsq_obj.wr_qid)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].pi = rsq_obj.wr_dat

class beq_ctx_ctrl(beq_ctx_ctrl_callback):
    def __init__(self, mem, clk, notifyReqIf, notifyRspIf, 
                    ringInfoRdTblIf, rxqTransferTypeRdTblIf, txqTransferTypeRdTblIf, 
                    ringDbIdxRdTblIf, ringCiRdTblIf, ringPiTblIf,
                    qstatusWrIf, qStopReqIf, qStopRspIf):
        self.log = SimLog("cocotb.tb")
        self.clk = clk
        self.mem = mem
        self.notifyReqIf = notifyReqIf
        self.notifyRspIf = notifyRspIf
        
        self.ringInfoRdTblIf = ringInfoRdTblIf
        self.rxqTransferTypeRdTblIf = rxqTransferTypeRdTblIf
        self.txqTransferTypeRdTblIf = txqTransferTypeRdTblIf
        self.ringDbIdxRdTblIf = ringDbIdxRdTblIf
        self.ringCiRdTblIf = ringCiRdTblIf
        self.ringPiTblIf = ringPiTblIf

        self.qstatusWrIf = qstatusWrIf
        self.qStopReqIf = qStopReqIf
        self.qStopRspIf = qStopRspIf 

        self.ctrlQueue = Queue(maxsize=8)
        self.qStopCmdQueue = Queue(maxsize=8)
        self.doorbellQueue = Queue(maxsize=64)
        self.schColdQueue = Queue(2**NotifyRsp.qid.size)
        self.schHotQueue = Queue(2**NotifyRsp.qid.size)
        self.schBitmap = {}

        self.qStopCr = cocotb.start_soon(self._qStopThd())
        self.qCtrlCr = cocotb.start_soon(self._qCtrlThd())
        self.notifyReqCr = cocotb.start_soon(self._notifyReqThd())
        self.notifyRspCr = cocotb.start_soon(self._notifyRspThd())
        self.ringInfoRdTblIf.set_callback(self._ringInfoRdCallback)
        self.rxqTransferTypeRdTblIf.set_callback(self._rxqTransferTypeRdCallback)
        self.txqTransferTypeRdTblIf.set_callback(self._txqTransferTypeRdCallback)
        self.ringDbIdxRdTblIf.set_callback(self._ringDbIdxRdCallback)
        self.ringCiRdTblIf.set_callback(self._ringCiRdCallback)
        self.ringPiTblIf.set_callback(self._ringPiRdCallback)
        self.ringPiTblIf.set_wr_callback(self._ringPiWrCallback)
        

        self.ctxs = {}

    def create_queue(self, qid, base_addr, ci_ptr_addr, ci_ptr_sz, beq_depth, transfer_type, segment_sz=4096):
        ctx = beq_ctx(base_addr, ci_ptr_addr, ci_ptr_sz, beq_depth, transfer_type, segment_sz)
        if qid in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is already exists".format(qid))
        self.ctxs[qid] = ctx

    def destroy_queue(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        if self.ctxs[qid].q_status is not beq_status_type_t.idle:
            raise ValueError("The queue(qid:{}) is not idle".format(qid))
        del self.ctxs[qid]


    async def start_queue(self, qid):
        await self.ctrlQueue.put((qid, beq_status_type_t.starting))
        while self.ctxs[qid].q_status is not beq_status_type_t.doing:
            await Timer(1, "ns")

    async def stop_queue(self, qid):
        await self.ctrlQueue.put((qid, beq_status_type_t.stopping))

    def get_base_addr(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        return self.ctxs[qid].base_addr 
        
    async def _set_ci(self, qid, ci):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        ci_byte_array = ci.to_bytes(self.ctxs[qid].ci_ptr_sz, byteorder="little")
        await self.mem.write(self.ctxs[qid].ci_ptr_addr, ci_byte_array)

    def get_segment_sz(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        return self.ctxs[qid].segment_sz

    async def get_stop_ack(self, qid, timeout=100):
        event = Event()
        obj = self.qStopReqIf._transaction_obj()
        obj.qid = qid
        await self.qStopReqIf.send(obj)
        await self.qStopCmdQueue.put((qid, event))
        await with_timeout(event.wait(), timeout, "us")
        return event.data

        
    async def _qCtrlThd(self):
        while True:
            (qid, ctrl_type) = await self.ctrlQueue.get()
            if qid not in self.ctxs.keys():
                raise ValueError("The queue(qid:{}) is not exists".format(qid))
            obj = self.qstatusWrIf._transaction_obj()
            obj.qid = qid
            ctx = self.ctxs[qid]
            if ctx.q_status == beq_status_type_t.idle and ctrl_type == beq_status_type_t.starting:
                obj.dat = beq_status_type_t.doing
            elif ctx.q_status == beq_status_type_t.doing and ctrl_type == beq_status_type_t.stopping:
                obj.dat = beq_status_type_t.stopping
            ctx.q_status = obj.dat
            await self.qstatusWrIf.send(obj)
            # when idle
            while not self.qstatusWrIf.idle():
                await Timer(1, "ns")
            self.ctxs[qid] = ctx
        
    async def _qStopThd(self):
        while True:
            (qid, event) = await self.qStopCmdQueue.get()
            data =  await self.qStopRspIf.recv()
            if int(data.dat) == 1:
                self.ctxs[qid].q_status = beq_status_type_t.idle
            event.set(int(data.dat))


    async def doorbell(self, qid, idx):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        cxt = self.ctxs[qid]
        cxt.db_idx = idx
        ring_sz = 2**(cxt.beq_depth-1) * 1024
        avail_num = cxt.db_idx - cxt.ci if cxt.db_idx > cxt.ci else cxt.db_idx + 2**16 - cxt.ci
        if avail_num > ring_sz:
            raise ValueError("The queue(qid:{}) is overflow".format(qid))
        await self.doorbellQueue.put(qid)

    async def _notifyReqThd(self):
        sel = True
        while True:
            q = self.schHotQueue if sel else self.schColdQueue
            if not q.empty():
                qid = q.get_nowait()
                obj = self.notifyReqIf._transaction_obj()
                obj.dat = qid
                await RisingEdge(self.clk)
                await self.notifyReqIf.send(obj)
            sel = not sel
            await RisingEdge(self.clk)

    async def _notifyRspThd(self):
        sel = True
        while True:
            empty = self.notifyRspIf.empty() if sel else self.doorbellQueue.empty()
            if not empty:
                if sel:
                    data = self.notifyRspIf.recv_nowait()
                    notifyRsp = NotifyRsp().unpack(data.dat)
                    if notifyRsp.done:
                        if self.schBitmap[notifyRsp.qid] == 2:
                            self.schBitmap[notifyRsp.qid] = 1
                            self.schColdQueue.put_nowait(notifyRsp.qid)
                        else:
                            del self.schBitmap[notifyRsp.qid]
                    else:
                        if notifyRsp.cold:
                            self.schColdQueue.put_nowait(notifyRsp.qid)
                        else:
                            self.schHotQueue.put_nowait(notifyRsp.qid)

                        if self.schBitmap[notifyRsp.qid] == 1:
                            self.schBitmap[notifyRsp.qid] = 2
                else:
                    qid = self.doorbellQueue.get_nowait()
                    if qid not in self.schBitmap.keys():
                        self.schHotQueue.put_nowait(qid)
                        self.schBitmap[qid] = 1
                    elif self.schBitmap[qid] == 1:
                        self.schBitmap[qid] = 2
            sel = not sel
            await RisingEdge(self.clk)

    async def ci_inc(self, qid):
        if qid not in self.ctxs.keys():
                raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].ci = (self.ctxs[qid].ci + 1) & 0xffff
        await self._set_ci(qid, self.ctxs[qid].ci)

    def get_ring_size(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        return 2**(self.ctxs[qid].beq_depth-1)*1024
