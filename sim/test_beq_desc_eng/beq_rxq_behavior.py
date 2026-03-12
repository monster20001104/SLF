#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_rxq_behavior.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/01/17
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  01/17     Joe Jiang   初始化版本
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
import numpy as np

class beq_rxq_behavior(object):
    def __init__(self, beq_ctx_ctrl, beq_pmd, rxqRdNdescReqIf, rxqRdNdescRspIf, clk):
        self.log = SimLog("cocotb.tb")
        self.beq_ctx_ctrl = beq_ctx_ctrl
        self.beq_pmd = beq_pmd
        self.clk = clk
        self.rxqRdNdescReqIf = rxqRdNdescReqIf
        self.rxqRdNdescRspIf = rxqRdNdescRspIf
        self.beq_rxq_queue = [Queue(maxsize=64) for _ in range(4)]
        self.beq_drop_queue = [Queue() for _ in range(4)]
        self.beq_desc_queue = Queue(maxsize=64)
        cocotb.start_soon(self._ndescRdReqThd())
        cocotb.start_soon(self._ndescRdRspThd())

    async def recv_a_pkt(self, qid, length, user0, user1, typ):
        await self.beq_rxq_queue[int(np.log2(typ))].put((qid, length, user0, user1, typ))

    async def _ndescRdReqThd(self):
        hold_flags = [False, False, False, False]
        hold_datas = [None, None, None, None]
        while True:
            for i in range(4):
                if not self.beq_rxq_queue[i].empty() or hold_flags[i]:
                    if hold_flags[i]:
                        (qid, length, user0, user1, typ) = hold_datas[i]
                    else:
                        (qid, length, user0, user1, typ) = await self.beq_rxq_queue[i].get()
                    seg = self.beq_ctx_ctrl.get_segment_sz(qid)//512
                    descs = []
                    obj = self.rxqRdNdescReqIf._transaction_obj()
                    obj.dat = BeqRdNdescReq(qid=qid//2, pkt_length=length, seg=seg, typ=typ).pack()
                    await self.rxqRdNdescReqIf.send(obj)
                    #self.log.info("rxqRdNdescReqIf qid {} length {} seg {} typ {}".format(qid, length, seg, typ))
                    while True:
                        data = await self.rxqRdNdescRspIf.recv()
                        beqRdNdescRsp = BeqRdNdescRsp().unpack(data.sbd)
                        if data.eop:
                            if beqRdNdescRsp.q_disable:
                                hold_flags[i] = False
                                await self.beq_drop_queue[i].put((qid, length, user0, user1, typ))
                            elif not beqRdNdescRsp.ok:
                                hold_flags[i] = True
                                hold_datas[i] = (qid, length, user0, user1, typ)
                                break
                            else:
                                hold_flags[i] = False
                        desc = BeqAvailDesc().unpack(data.dat)
                        descs.append(desc)
                        if data.eop and beqRdNdescRsp.ok:
                            self.log.info("rxqRdNdescRspIf qid {} desc_num {}".format(qid, len(descs)))
                            break
                    if len(descs) > 0:
                        await self.beq_desc_queue.put((qid, length, user0, user1, typ, seg*512, descs))
                await Timer(4, "ns")
    async def _ndescRdRspThd(self):
        while True:
            qid, length, user0, user1, typ, seg_sz, descs = await self.beq_desc_queue.get()
            n = 0
            for idx in range(len(descs)):
                chunk_sz = 0
                if length - n > seg_sz:
                    chunk_sz = seg_sz
                    n = n + chunk_sz
                else:
                    chunk_sz = length - n
                    n = n + chunk_sz
                used_desc = BeqUsedDesc(next=n < length, avail=descs[idx].avail, used=descs[idx].used != 1, user0=user0, soc_buf_len=chunk_sz, user1=user1)
                await self.beq_pmd.beqs[qid].write_used_desc(self.beq_ctx_ctrl.ctxs[qid].ci, used_desc)
                self.log.info("rxq write_used_desc(qid {} ci {}): idx {} next {} avail {} used {} user0 {} soc_buf_len {} user1 {}".format(qid, self.beq_ctx_ctrl.ctxs[qid].ci, idx, used_desc.next, used_desc.avail, used_desc.used, used_desc.user0, used_desc.soc_buf_len, used_desc.user1))
                self.beq_ctx_ctrl.ctxs[qid].ci = (self.beq_ctx_ctrl.ctxs[qid].ci + 1) & 0xffff