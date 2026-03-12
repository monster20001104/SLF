#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_desc_eng.py
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
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout, Lock
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from defines import *
from beq_ctx_ctrl import *
import random
import math
from beq_error_ctrl import *

class beq_desc_eng(object):
    def __init__(self, clock, rings, beq_ctx_ctrl, RdNdescReqIf, RdNdescRspIf):
        self.log = SimLog("cocotb.tb")
        self.clock = clock
        self.localDescBufSize = 32
        self.maxBrustRdNDesc = 8
        self.rings = rings
        self.beq_ctx_ctrl = beq_ctx_ctrl
        self.RdNdescReqIf = RdNdescReqIf
        self.RdNdescRspIf = RdNdescRspIf

        self.local_desc_buf = {}

        self.error_ctrl = beq_error_ctrl()
        #启动两个协程
        self._rdNdescCr = cocotb.start_soon(self._rdNdescThd())
        self._descEngCr = cocotb.start_soon(self._descEngThd())

    async def _descEngThd(self):
        cnts = {}  #per ring desc cnt
        while True:
            for qid in self.rings.keys():  
                ring = self.rings[qid]
                if not ring.empty(): 
                    if qid not in cnts.keys():  #init cnt
                        cnts[qid] = 0
                    if qid not in self.local_desc_buf.keys():  #init shadle ring
                        self.local_desc_buf[qid] = Queue(maxsize=self.localDescBufSize)
                    rd_desc_num = min(self.localDescBufSize-self.local_desc_buf[qid].qsize(), ring.qsize())
                    rd_desc_num = min(self.maxBrustRdNDesc, rd_desc_num)
                    for _ in range(rd_desc_num):
                        desc,desc_cnt = await ring.get()
                        self.log.debug("put desc(cnt:{}) to local_desc_buf(qid:{}) soc_buf_addr {} soc_buf_len {} next {} avail {}".format(cnts[qid], qid, hex(desc.soc_buf_addr), hex(desc.soc_buf_len), desc.next, desc.avail))
                        if desc.soc_buf_len == 0:
                            self.log.warning("desc soc_buf_len == 0 when put desc to local_desc_buf(qid:{})".format(qid))
                            #raise ValueError("desc soc_buf_len == 0 when put desc to local_desc_buf(qid:{})".format(qid))
                        if (self.error_ctrl.should_enter_fit_mode() and self.error_ctrl.select_error_type() == 'drop_err' and self.error_ctrl.select_drop_subtype() == DropErrorType.DROP_MODE):
                            await Timer(100, "ns")
                        await self.local_desc_buf[qid].put((desc,desc_cnt))
                        cnts[qid] = cnts[qid] + 1
            await RisingEdge(self.beq_ctx_ctrl.clk)

    async def _rdNdescThd(self):
        seg_tbl = {beq_rx_segment_t.sz_512:512, beq_rx_segment_t.sz_1k:1024, beq_rx_segment_t.sz_2k:2048, beq_rx_segment_t.sz_4k:4096, beq_rx_segment_t.sz_8k:8192}
        while True:
            #recv desc req
            data = await self.RdNdescReqIf.recv()
            ndescReq = BeqRdNdescReq().unpack(data.dat)
            qid = ndescReq.qid
            rsp = None
            #cal read desc num
            segment_size = seg_tbl[ndescReq.seg]
            rd_ndesc = math.ceil(ndescReq.pkt_length / segment_size)  
            #desc > 24
            if rd_ndesc > self.localDescBufSize - self.maxBrustRdNDesc:
                self.log.warning("rd_ndesc:{}".format(rd_ndesc))
                rsp = BeqRdNdescRsp(qid=qid, ok=False, fatal=True, typ=ndescReq.typ, maybe_last=random.randint(0,1), q_disable=False)
                obj = self.RdNdescRspIf._transaction_obj()
                obj.sop = True
                obj.eop = True
                obj.sbd = rsp.pack()
                obj.dat = 0
                await self.RdNdescRspIf.send(obj)
                #raise ValueError("rd_ndesc({}) > {} when BeqRdNdescReq(qid:{})".format(rd_ndesc, self.localDescBufSize - self.maxBrustRdNDesc, qid))
            #if qid not in self.local_desc_buf.keys():
            #            self.local_desc_buf[qid] = Queue(maxsize=self.localDescBufSize)
            
            elif self.beq_ctx_ctrl.get_status(qid) == beq_status_type_t.idle or self.beq_ctx_ctrl.get_status(qid) == beq_status_type_t.starting:
                #queue not ready rsp
                rsp = BeqRdNdescRsp(qid=qid, ok=False, fatal=False, typ=ndescReq.typ, maybe_last=random.randint(0,1), q_disable=True)
                obj = self.RdNdescRspIf._transaction_obj()
                obj.sop = True
                obj.eop = True
                obj.sbd = rsp.pack()
                obj.dat = 0
                await self.RdNdescRspIf.send(obj)
            #local_desc_buf desc num >= read desc num 
            elif self.local_desc_buf[qid].qsize() >= rd_ndesc:
                self.log.info("rd_ndesc = {}".format(rd_ndesc))
                for i in range(rd_ndesc):
                    self.log.info("for rd_ndesc = {}".format(rd_ndesc))
                    desc,desc_cnt = await self.local_desc_buf[qid].get()
                    rsp = BeqRdNdescRsp(qid=qid, ok=True, fatal=False, typ=ndescReq.typ, maybe_last=self.local_desc_buf[qid].empty(), q_disable=False)
                    obj = self.RdNdescRspIf._transaction_obj()
                    obj.sop = i == 0
                    obj.eop = i == rd_ndesc - 1
                    obj.sbd = rsp.pack()
                    obj.dat = desc.pack()
                    obj.tag = desc_cnt & 0xf
                    await self.RdNdescRspIf.send(obj)
            #shadle ring desc num is not enough
            else:
                self.log.info("not_enoutgh rd_ndesc = {}".format(rd_ndesc))
                rsp = BeqRdNdescRsp(qid=qid, ok=False, fatal=False, typ=ndescReq.typ, maybe_last=random.randint(0,1), q_disable=False)
                obj = self.RdNdescRspIf._transaction_obj()
                obj.sop = True
                obj.eop = True
                obj.sbd = rsp.pack()
                obj.dat = 0
                await self.RdNdescRspIf.send(obj)
