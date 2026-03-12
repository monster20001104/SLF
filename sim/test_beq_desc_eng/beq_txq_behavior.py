#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_txq_behavior.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/05
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/05     Joe Jiang   初始化版本
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

class beq_txq_behavior(object):
    def __init__(self, beq_ctx_ctrl, newChainNotifyIf, txqRdNdescReqIf, txqRdNdescRspIf, beq_txq_ref, clk):
        self.log = SimLog("cocotb.tb")
        self.beq_ctx_ctrl = beq_ctx_ctrl
        self.newChainNotifyIf = newChainNotifyIf
        self._chainNotifySchBitmap = {}
        self._chainNotifySchQueue = Queue(maxsize=2**ChainNotify.qid.size)
        self._chainNotifyCmdQueue = Queue(maxsize=64)
        self.clk = clk
        self._beq_txq_ref = beq_txq_ref

        self._cmdQueue = Queue(64)

        self.txqRdNdescReqIf = txqRdNdescReqIf
        self.txqRdNdescRspIf = txqRdNdescRspIf

        self._newChainNotifyCr = cocotb.start_soon(self._newChainNotifyThd())
        self._ndescRdReqCr = cocotb.start_soon(self._ndescRdReqThd())
        self._ndescRdRspCr = cocotb.start_soon(self._ndescRdRspThd())
        self._dataMoverCr = cocotb.start_soon(self._dataMoverThd())

    
    async def _newChainNotifyThd(self):
        sel = True
        while True:
            empty = self.newChainNotifyIf.empty() if sel else self._chainNotifyCmdQueue.empty()
            if not empty:
                if sel:
                    data = self.newChainNotifyIf.recv_nowait()
                    chainNotify = ChainNotify().unpack(data.dat)
                    if chainNotify.qid not in self._chainNotifySchBitmap.keys():
                        self.log.debug("new chain qid {} add bitmap".format(chainNotify.qid))
                        self._chainNotifySchQueue.put_nowait(chainNotify)
                        self._chainNotifySchBitmap[chainNotify.qid] = 1
                    else:
                        self.log.debug("new chain qid {} set bitmap 2(before value {})".format(chainNotify.qid, self._chainNotifySchBitmap[chainNotify.qid]))
                        self._chainNotifySchBitmap[chainNotify.qid] = 2
                else:
                    beqRdNdescRsp = self._chainNotifyCmdQueue.get_nowait()
                    if not beqRdNdescRsp.ok:
                        if self._chainNotifySchBitmap[beqRdNdescRsp.qid] != 2 and self._chainNotifySchBitmap[beqRdNdescRsp.qid] != 1:
                            raise ValueError("The bitmap(qid:{} value:{}) is illegal".format(beqRdNdescRsp.qid, self._chainNotifySchBitmap[chainNotify.qid]))
                        if self._chainNotifySchBitmap[beqRdNdescRsp.qid] == 2:
                            self.log.debug("qid {} set bitmap 1".format(beqRdNdescRsp.qid))
                            chainNotify = ChainNotify(qid=beqRdNdescRsp.qid, typ=beqRdNdescRsp.typ)
                            self._chainNotifySchQueue.put_nowait(chainNotify)
                            self._chainNotifySchBitmap[beqRdNdescRsp.qid] = 1
                        else:
                            self.log.debug("qid {} rm bitmap(before value:{})".format(beqRdNdescRsp.qid, self._chainNotifySchBitmap[beqRdNdescRsp.qid]))
                            del self._chainNotifySchBitmap[beqRdNdescRsp.qid]
                    else:
                        chainNotify = ChainNotify(qid=beqRdNdescRsp.qid, typ=beqRdNdescRsp.typ)
                        self._chainNotifySchQueue.put_nowait(chainNotify)
                        if self._chainNotifySchBitmap[chainNotify.qid] == 1:
                            self._chainNotifySchBitmap[chainNotify.qid] = 2
                            self.log.debug("qid {} set bitmap 2(before value:{})".format(beqRdNdescRsp.qid, self._chainNotifySchBitmap[chainNotify.qid]))
                        else:
                            self.log.debug("qid {} set bitmap hold{}".format(beqRdNdescRsp.qid, self._chainNotifySchBitmap[chainNotify.qid]))
            sel = not sel
            await RisingEdge(self.clk)
    async def _ndescRdReqThd(self):
        while True:
            data = await self._chainNotifySchQueue.get()
            self.log.debug("qid {} (bitmap value:{}) sch get".format(data.qid, self._chainNotifySchBitmap[data.qid]))
            obj = self.txqRdNdescReqIf._transaction_obj()
            obj.dat = BeqRdNdescReq(qid=data.qid, pkt_length=0, typ=data.typ).pack()
            await self.txqRdNdescReqIf.send(obj)

    async def _ndescRdRspThd(self):
        cnts = {}
        while True:
            data = await self.txqRdNdescRspIf.recv()
            beqRdNdescRsp = BeqRdNdescRsp().unpack(data.sbd)
            if data.eop:
                await self._chainNotifyCmdQueue.put(beqRdNdescRsp)
            desc = BeqAvailDesc().unpack(data.dat)
            if beqRdNdescRsp.ok :
                # eop next err
                #  1   1    1
                #  0   0    1
                (ref_mbuf, ref_typ) = self._beq_txq_ref[beqRdNdescRsp.qid*2+1].pop(0)
                if ref_mbuf.addr != desc.soc_buf_addr or ref_mbuf.len != desc.soc_buf_len or ref_mbuf.user0 != desc.user0 or ref_typ != beqRdNdescRsp.typ:
                    self.log.warning("qid {} ref: addr {} len {} user {} typ {} desc: addr {} len {} user0 {} typ {}".format(beqRdNdescRsp.qid*2+1, ref_mbuf.addr, ref_mbuf.len, ref_mbuf.user0, ref_typ, desc.soc_buf_addr, desc.soc_buf_len, desc.user0, beqRdNdescRsp.typ))
                    raise ValueError("The desc is illegal")

                if data.eop == desc.next :
                    self.log.warning("qid {} ref addr {} len {} user {} desc addr {} len {} user0 {}".format(beqRdNdescRsp.qid*2+1, ref_mbuf.addr, ref_mbuf.len, ref_mbuf.user0, desc.soc_buf_addr, desc.soc_buf_len, desc.user0))
                    raise ValueError("The chain is illegal")
                if beqRdNdescRsp.qid not in cnts.keys():
                    cnts[beqRdNdescRsp.qid] = 0
                self.log.debug("qid:{} cnt {} test is pass\n{}".format(beqRdNdescRsp.qid*2+1, cnts[beqRdNdescRsp.qid], desc.show(dump=True)))
                cnts[beqRdNdescRsp.qid] = cnts[beqRdNdescRsp.qid] + 1
                await self._cmdQueue.put((beqRdNdescRsp.qid, beqRdNdescRsp.typ, desc))

    async def _dataMoverThd(self):
        while True:
            (qid, typ, desc) = await self._cmdQueue.get()
            await Timer((desc.soc_buf_len+3999)//4000, "ns")
            await self.beq_ctx_ctrl.ci_inc(qid*2+1)

            