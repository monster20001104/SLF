#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_desc_eng.py
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
from beq_ctx_ctrl import *
import random


class beq_desc_eng(object):
    def __init__(self, clock, rings, beq_ctx_ctrl, notifyReqIf, notifyRspIf, RdNdescReqIf, RdNdescRspIf):
        self.log = SimLog("cocotb.tb")  
        self.log.setLevel(logging.DEBUG)
        self.clock = clock   
        self.localDescBufSize = 32  
        self.maxBrustRdNDesc = 8  
        self.rings = rings  
        self.beq_ctx_ctrl = beq_ctx_ctrl  
        self.notifyReqIf = notifyReqIf
        self.notifyRspIf = notifyRspIf
        self.RdNdescReqIf = RdNdescReqIf
        self.RdNdescRspIf = RdNdescRspIf


        self._lock = Lock()
        self._NotifySchBitmap = {}  #Decide whether to write qid into FIFO
        self._NotifySchQueue = Queue(maxsize=Notify.qid.size)
        self.newChainQueue = Queue(maxsize=64)
        self.putNewChainQueue = Queue(maxsize=64)
        self.local_buf_queue = Queue()


        self.local_desc_buf = {}
        self.local_chain = {}
        self.beq_ctx_ctrl.local_ci = {}
        self.beq_ctx_ctrl.local_out_cnt = {}

        for qid in self.rings.keys():
            self.local_desc_buf[qid] = Queue(maxsize=self.localDescBufSize)
            self.local_chain[qid] = Queue(maxsize=self.localDescBufSize)
            self.beq_ctx_ctrl.local_ci[qid] = 0  
            self.beq_ctx_ctrl.local_out_cnt[qid] = 0  

        self._rdNdescCr = cocotb.start_soon(self._rdNdescThd())
        self._notifyReqCr = cocotb.start_soon(self._notifyReqThd())
        self._notifyRspCr = cocotb.start_soon(self._notifyRspThd())
        self._descEngCr = cocotb.start_soon(self._descEngThd())
    
    #receive read Ndesc req and send rsp
    async def _rdNdescThd(self):
        while True:
            data = await self.RdNdescReqIf.recv()  #read desc req
            ndescReq = BeqRdNdescReq().unpack(data.dat)  
            rsp = None

            qid = ndescReq.qid
            if qid not in self.local_chain:
                self.local_chain[qid] = Queue(maxsize=self.localDescBufSize)
            if qid not in self.local_desc_buf:
                self.local_desc_buf[qid] = Queue(maxsize=self.localDescBufSize)
            if qid not in self.beq_ctx_ctrl.local_ci:
                self.beq_ctx_ctrl.local_ci[qid] = 0
            if qid not in self.beq_ctx_ctrl.local_out_cnt:
                self.beq_ctx_ctrl.local_out_cnt[qid] = 0
                
            if not self.local_chain[ndescReq.qid].empty() and self.beq_ctx_ctrl.ctxs[ndescReq.qid].q_status == beq_status_type_t.doing:  #if local chain not empty
                chain_next = True
                sop = True
                while chain_next: 
                    desc,desc_cnt = await self.local_desc_buf[ndescReq.qid].get()  #get desc from local desc buf
                    chain_next = desc.next  
            
                    rsp = BeqRdNdescRsp(qid=ndescReq.qid, ok=True, typ=ndescReq.typ, maybe_last=self.local_desc_buf[ndescReq.qid].empty())
                    obj = self.RdNdescRspIf._transaction_obj()
                    obj.sop = sop 
                    obj.eop = not chain_next  
                    obj.sbd = rsp.pack() 
                    obj.dat = desc.pack()  
                    obj.tag = self.beq_ctx_ctrl.ctxs[ndescReq.qid].local_out_cnt & 0xf
                    self.log.debug("cnt_value {} tag {} qid {}".format(self.beq_ctx_ctrl.ctxs[ndescReq.qid].local_out_cnt, obj.tag, ndescReq.qid))
                    await self.RdNdescRspIf.send(obj) 
                    self.beq_ctx_ctrl.ctxs[ndescReq.qid].local_out_cnt = self.beq_ctx_ctrl.ctxs[ndescReq.qid].local_out_cnt + 1 
                    self.beq_ctx_ctrl.ctxs[ndescReq.qid].local_ci = self.beq_ctx_ctrl.ctxs[ndescReq.qid].local_out_cnt
                    if not chain_next: #chain last desc
                        await self.local_chain[ndescReq.qid].get() 
                    sop = False  
            else:
                rsp = BeqRdNdescRsp(qid=ndescReq.qid, ok=False, typ=ndescReq.typ, maybe_last=random.randint(0,1))
                obj = self.RdNdescRspIf._transaction_obj()
                obj.sop = True
                obj.eop = True
                obj.sbd = rsp.pack()
                obj.dat = 0
                await self.RdNdescRspIf.send(obj)


    async def _descEngThd(self):
        cnts = {}  # record per qid desc num
        while True:
            for qid in self.rings.keys(): 
                #self.log.debug("get desc")
                ring = self.rings[qid]
                if not ring.empty(): 
                    #self.log.debug("ring not empty")
                    if qid not in cnts.keys():
                        cnts[qid] = 0 #if not exist,init cnt
                    if qid not in self.local_desc_buf.keys():
                        self.local_desc_buf[qid] = Queue(maxsize=self.localDescBufSize) #if not exist,init shadle ring
                    if qid not in self.local_chain.keys():
                        self.local_chain[qid] = Queue(maxsize=self.localDescBufSize) #if not exist,init local chain

                    #cal read desc
                    rd_desc_num = min(self.localDescBufSize-self.local_desc_buf[qid].qsize(), ring.qsize())
                    
                    rd_desc_num = min(self.localDescBufSize-self.local_chain[qid].qsize(), rd_desc_num)
                   
                    rd_desc_num = min(self.maxBrustRdNDesc, rd_desc_num)
                    #self.log.debug("rd_desc_num {}" .format(rd_desc_num))

                    #self.log.debug("qid = {} self.beq_ctx_ctrl.ctxs[qid].q_status={}".format(qid, self.beq_ctx_ctrl.ctxs[qid].q_status))
                    if self.beq_ctx_ctrl.ctxs[qid].q_status == beq_status_type_t.doing:
                        for _ in range(rd_desc_num):
                        #if self.beq_ctx_ctrl.ctxs[qid].q_status == beq_status_type_t.doing:
                            desc,desc_cnt = await ring.get()    
                            self.log.debug("put desc(cnt:{}) to local_desc_buf(qid:{}) soc_buf_addr {} soc_buf_len {} next {} avail {}".format(cnts[qid], qid, hex(desc.soc_buf_addr), hex(desc.soc_buf_len), desc.next, desc.avail))
                            if desc.soc_buf_len == 0:
                                self.log.warning("desc soc_buf_len == 0 when put desc to local_desc_buf(qid:{})".format(qid))
                            await self.local_desc_buf[qid].put((desc,desc_cnt)) 
                            cnts[qid] = cnts[qid] + 1  
                            if not desc.next: #if chain last desc
                                typ = self.beq_ctx_ctrl.get_typ(qid) 
                                self.log.debug("type {}" .format(typ))
                                if qid not in self.local_chain.keys():
                                    self.local_chain[qid] = Queue(maxsize=self.localDescBufSize)
                                await self.local_chain[qid].put(True)  #local chain has complete chain
                                await self._putNewChain(qid, typ) 
            await RisingEdge(self.beq_ctx_ctrl.clk)

    
    async def _putNewChain(self, qid, typ):    
        #Notify(qid=qid, done=False, typ=typ).show()
        self.log.debug("notify req qid = {}".format(qid))
        await self.putNewChainQueue.put(Notify(qid=qid, done=False, typ=typ))

    #generate notify req
    async def _notifyReqThd(self):
        while True:
            notify = await self._NotifySchQueue.get()  
            obj = self.notifyReqIf._transaction_obj()
            obj.dat = notify.pack()
            await self.notifyReqIf.send(obj)  #send notify_req to rtl

    # wrr_sch
    async def _notifyRspThd(self):
        sel = True  
        while True:    
            empty =  self.notifyRspIf.empty() if sel else self.putNewChainQueue.empty()
            if not empty:  
                if sel:  #notify rsp
                    data = self.notifyRspIf.recv_nowait() 
                    notifyRsp = Notify().unpack(data.dat) 
                    if notifyRsp.done:
                        if self._NotifySchBitmap[notifyRsp.qid] == 2:  #done:1 and bitmap:2
                            self._NotifySchBitmap[notifyRsp.qid] = 1  #bitmap->1
                            self._NotifySchQueue.put_nowait(notifyRsp)  
                        else:
                            del self._NotifySchBitmap[notifyRsp.qid] #done:1 and bitmap:1 
                    else: #done:0
                        self._NotifySchQueue.put_nowait(notifyRsp) 
                        #if self._NotifySchBitmap[notifyRsp.qid] == 1: 
                        self._NotifySchBitmap[notifyRsp.qid] = 2
                else: #new chain
                    notifyRsp = self.putNewChainQueue.get_nowait()
                    if notifyRsp.qid not in self._NotifySchBitmap.keys():  #if qid not exist
                        self._NotifySchBitmap[notifyRsp.qid] = 1  #bitmap -> 1
                        self._NotifySchQueue.put_nowait(notifyRsp) 
                    else:
                        self._NotifySchBitmap[notifyRsp.qid] = 2 
            sel = not sel
            await RisingEdge(self.clock)
               
                