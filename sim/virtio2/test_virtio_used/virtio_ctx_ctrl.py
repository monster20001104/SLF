#!/usr/bin/env python3
################################################################################
#  文件名称 : virtio_ctx_ctrl.py
#  作者名称 : cui naiwan
#  创建日期 : 2025/07/25
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/25     cui naiwan   初始化版本
################################################################################
import cocotb
import logging
import math
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout, Lock
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from defines import *
import random

class virtio_qstat_t:
    VIRTIO_Q_STATUS_IDLE       = 1
    VIRTIO_Q_STATUS_STATING    = 2
    VIRTIO_Q_STATUS_DOING      = 4
    VIRTIO_Q_STATUS_STOPPING   = 8

class virtio_q_type_t:
    VIRTIO_NET_RX_TYPE = 0b01
    VIRTIO_NET_TX_TYPE = 0b00
    VIRTIO_BLK_TYPE    = 0b10

class virtio_qdepth_t:
    q1 = 0
    q2 = 1
    q4 = 2
    q8 = 3
    q16 = 4
    q32 = 5
    q64 = 6
    q128 = 7
    q256 = 8
    q512 = 9
    q1024 = 10
    q2048 = 11
    q4096 = 12
    q8192 = 13
    q16384 = 14
    q32768 = 15

class irq_merge_core_local_ctx(object):
    def __init__(self, msix_info):
        self.msix_info = msix_info

class virtio_ctx(object):
    def __init__(self, dev_id, bdf, forced_shutdown, used_ring_addr, qdepth, msix_addr, msix_data, msix_enable, msix_time, msix_threshold):
        self.used_ring_addr = used_ring_addr
        self.qdepth = qdepth
        self.msix_addr = msix_addr
        self.msix_data = msix_data
        self.msix_enable = msix_enable
        #self.msix_mask = msix_mask
        self.msix_mask = 0
        self.msix_pending = 0
        self.dev_id = dev_id 
        self.bdf = bdf
        self.forced_shutdown = forced_shutdown
        self.msix_time = msix_time
        self.msix_threshold = msix_threshold
        self.q_status = virtio_qstat_t.VIRTIO_Q_STATUS_IDLE
        self.err_fatal = 0
        self.used_elem_ptr = 0
        self.dma_write_used_idx_irq_flag = 0

class virtio_ctx_ctrl_callback(object):
    def _UsedctxRdCallback(self, req_obj):
        qid = int(req_obj.req_qid)
        if qid not in self.ctxs.keys():
            #raise ValueError("The queue(qid:{}) is not exists".format(qid))
            self.log.warning(f"qid={qid} is not in create queue")
            rsp = UsedCtxRdRspTransaction()
            rsp.rsp_forced_shutdown = 0
            rsp.rsp_dev_id = 0
            rsp.rsp_bdf = 0
            rsp.rsp_msix_addr = 0
            rsp.rsp_msix_data = 0
            rsp.rsp_msix_mask = 0
            rsp.rsp_msix_pending = 0
            rsp.rsp_msix_enable = 0
            rsp.rsp_used_ring_addr = 0
            rsp.rsp_qdepth = 0
            rsp.rsp_q_status = 0
            rsp.rsp_err_fatal = 0
            return rsp
        else:
            rsp = UsedCtxRdRspTransaction()
            rsp.rsp_forced_shutdown = self.ctxs[qid].forced_shutdown
            rsp.rsp_dev_id = self.ctxs[qid].dev_id
            rsp.rsp_bdf = self.ctxs[qid].bdf
            rsp.rsp_msix_addr = self.ctxs[qid].msix_addr
            rsp.rsp_msix_data = self.ctxs[qid].msix_data
            rsp.rsp_msix_mask = self.ctxs[qid].msix_mask
            rsp.rsp_msix_pending = self.ctxs[qid].msix_pending
            rsp.rsp_msix_enable = self.ctxs[qid].msix_enable
            rsp.rsp_used_ring_addr = self.ctxs[qid].used_ring_addr
            rsp.rsp_qdepth = self.ctxs[qid].qdepth
            rsp.rsp_q_status = self.ctxs[qid].q_status
            rsp.rsp_err_fatal = self.ctxs[qid].err_fatal
            return rsp
        
    def _usedelemptrRdCallback(self, req_obj):
        qid = int(req_obj.rd_req_qid)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        rsp = UsedElemPtrRdRspTransaction()
        rsp.rd_rsp_dat = self.ctxs[qid].used_elem_ptr
        return rsp
    
    def _usedelemptrWrCallback(self, wr_obj):
        qid = int(wr_obj.wr_qid)
        dat = int(wr_obj.wr_dat)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].used_elem_ptr = dat  
    
    def _ErrfatalWrCallback(self, wr_obj):
        qid = int(wr_obj.wr_qid)
        dat = int(wr_obj.wr_dat)
        if qid not in self.ctxs.keys():
        #    raise ValueError("The queue(qid:{}) is not exists".format(qid))
            self.log.warning(f"ErrFatalWr: Queue qid={qid} does not exist (already destroyed), skip setting err_fatal")
            return
        self.ctxs[qid].err_fatal = dat

    def _DmawrusedidxirqflagWrCallback(self, wr_obj):
        qid = int(wr_obj.wr_qid)
        dat = int(wr_obj.wr_dat)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].dma_write_used_idx_irq_flag = dat

    def _usedidxWrCallback(self, wr_obj):
        qid = int(wr_obj.wr_qid)
        dat = int(wr_obj.wr_dat)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].used_idx = dat  

    def _msixtblWrCallback(self, wr_obj):
        qid = int(wr_obj.wr_qid)
        mask = int(wr_obj.wr_mask)
        pending = int(wr_obj.wr_pending)
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        self.ctxs[qid].msix_mask = mask
        self.ctxs[qid].msix_pending = pending

    def _TxTimeRdCallback(self, req_obj):
        base_group_qid = int(req_obj.rd_req_qid_net_tx)
        base_global_qid = (0b01 << 5) | base_group_qid
        combined_dat = 0
        rsp = TxMsixTimeRdRspTransaction()
        for i in range(8):
            target_idx  = (base_global_qid << 3) + i 
            if target_idx  not in self.ctxs.keys():
                #raise ValueError("The queue(idx:{}) is not exists".format(idx))
                combined_dat |= (0 << (3 * i))
            else:
                msix_time = self.ctxs[target_idx].msix_time & 0x7 
                combined_dat |= (msix_time << (3 * i)) 
        rsp.rd_rsp_dat_net_tx = combined_dat
        return rsp

    def _TxThresholdRdCallback(self, req_obj):
        base_qid = int(req_obj.rd_req_qid_net_tx)
        global_qid = (0b01 << 8) | base_qid

        if global_qid not in self.ctxs.keys():
            #raise ValueError("The queue(idx:{}) is not exists".format(idx))
            rsp = TxMsixThresholdRdRspTransaction()
            rsp.rd_rsp_dat_net_tx = 0
            return rsp
        else:
            rsp = TxMsixThresholdRdRspTransaction()
            rsp.rd_rsp_dat_net_tx = self.ctxs[global_qid].msix_threshold
            return rsp
        
    def _RxTimeRdCallback(self, req_obj):
        #qid = int(req_obj.rd_req_qid_net_rx)
        base_group_qid = int(req_obj.rd_req_qid_net_rx)
        base_global_qid = (0b00 << 5) | base_group_qid
        combined_dat = 0
        rsp = RxMsixTimeRdRspTransaction()
        for i in range(8):
            target_idx  = (base_global_qid << 3) + i 
            if target_idx  not in self.ctxs.keys():
                #raise ValueError("The queue(idx:{}) is not exists".format(idx))
                combined_dat |= (0 << (3 * i))
            else:
                msix_time = self.ctxs[target_idx].msix_time & 0x7 
                combined_dat |= (msix_time << (3 * i)) 
        rsp.rd_rsp_dat_net_rx = combined_dat
        return rsp

    def _RxThresholdRdCallback(self, req_obj):
        #qid = int(req_obj.rd_req_qid_net_rx)
        base_qid = int(req_obj.rd_req_qid_net_rx)
        global_qid = (0b00 << 8) | base_qid
        #self.log.info(f"Rx Threshold req qid={qid}")
        if global_qid not in self.ctxs.keys():
            #raise ValueError("The queue(idx:{}) is not exists".format(idx))
            rsp = RxMsixThresholdRdRspTransaction()
            rsp.rd_rsp_dat_net_rx = 0
            return rsp
        else:
            rsp = RxMsixThresholdRdRspTransaction()
            rsp.rd_rsp_dat_net_rx = self.ctxs[global_qid].msix_threshold
            #self.log.info(f"qid={qid}, self.ctxs[qid].msix_threshold={self.ctxs[qid].msix_threshold}")
            return rsp
        
    def _TxInfoWrCallback(self, req_obj):
        #idx = int(req_obj.wr_qid_net_tx)
        base_group_qid = int(req_obj.wr_qid_net_tx)
        base_global_qid = (0b01 << 5) | base_group_qid
        data = int(req_obj.wr_dat_net_tx)
        # data width：TIME_MAP_WIDTH + 8 = 2 + 8 
        group_bit_width = 10
        group_mask = (1 << group_bit_width) - 1 
        for i in range(8):
            target_idx = (base_global_qid << 3) + i
            group_data = (data >> (i * group_bit_width)) & group_mask
            if target_idx not in self.tx_local_ctxs.keys():
                #raise ValueError("The queue(idx:{}) is not exists".format(idx))
                local_ctx = irq_merge_core_local_ctx(0)
                self.tx_local_ctxs[target_idx] = local_ctx
            else:
                local_ctx = irq_merge_core_local_ctx(group_data)
                self.tx_local_ctxs[target_idx] = local_ctx

    def _TxInfoRdCallback(self, req_obj):
        #idx = int(req_obj.rd_req_qid_net_tx)
        base_group_qid = int(req_obj.rd_req_qid_net_tx)
        base_global_qid = (0b01 << 5) | base_group_qid
        combined_dat = 0
        group_bit_width = 10
        rsp = TxMsixInfoRdRspTransaction()
        for i in range(8):
            target_idx  = (base_global_qid << 3) + i
            if target_idx not in self.tx_local_ctxs.keys():
                group_data = 0
            else:
                group_data = self.tx_local_ctxs[target_idx].msix_info & ((1 << group_bit_width) - 1)
            combined_dat |= (group_data << (i * group_bit_width))
        rsp.rd_rsp_dat_net_tx = combined_dat
        return rsp

    def _RxInfoWrCallback(self, req_obj):
        #idx = int(req_obj.wr_qid_net_rx)
        base_group_qid = int(req_obj.wr_qid_net_rx)
        base_global_qid = (0b00 << 5) | base_group_qid
        data = int(req_obj.wr_dat_net_rx)
        # data width：TIME_MAP_WIDTH + 8 = 2 + 8 
        group_bit_width = 10
        group_mask = (1 << group_bit_width) - 1 
        for i in range(8):
            target_idx = (base_global_qid << 3) + i
            group_data = (data >> (i * group_bit_width)) & group_mask
            if target_idx not in self.rx_local_ctxs.keys():
                #raise ValueError("The queue(idx:{}) is not exists".format(idx))
                local_ctx = irq_merge_core_local_ctx(0)
                self.rx_local_ctxs[target_idx] = local_ctx
            else:
                local_ctx = irq_merge_core_local_ctx(group_data)
                self.rx_local_ctxs[target_idx] = local_ctx

    def _RxInfoRdCallback(self, req_obj):
        #idx = int(req_obj.rd_req_qid_net_rx)
        base_group_qid = int(req_obj.rd_req_qid_net_rx)
        base_global_qid = (0b00 << 5) | base_group_qid
        combined_dat = 0
        group_bit_width = 10
        rsp = RxMsixInfoRdRspTransaction()
        for i in range(8):
            target_idx  = (base_global_qid << 3) + i
            if target_idx not in self.rx_local_ctxs.keys():
                group_data = 0
            else:
                group_data = self.rx_local_ctxs[target_idx].msix_info & ((1 << group_bit_width) - 1)
            combined_dat |= (group_data << (i * group_bit_width))
        rsp.rd_rsp_dat_net_rx = combined_dat
        return rsp

        
class virtio_ctx_ctrl(virtio_ctx_ctrl_callback):
    def __init__(self, clk, usedctxRdTblIf, usedelemptrTblIf, usedidxWrTblIf, msixtblWrTblIf, TxTimeRdTblIf, TxThresholdRdTblIf, RxTimeRdTblIf, RxThresholdRdTblIf, TxInfoTbl, RxInfoTbl, ErrfatalWrTblIf, DmawrusedidxirqflagWrTblIf):
        self.log = SimLog("cocotb.virtio_ctx_ctrl")
        self.log.setLevel(logging.INFO)
        self.clk = clk
        self.ctxs = {}   
        self.tx_local_ctxs = {}
        self.rx_local_ctxs = {}
        self.mask = {}
        self.pending = {}
        self.usedctxRdTblIf = usedctxRdTblIf
        self.usedelemptrTblIf = usedelemptrTblIf
        self.usedidxWrTblIf = usedidxWrTblIf
        self.msixtblWrTblIf = msixtblWrTblIf
        self.TxTimeRdTblIf = TxTimeRdTblIf
        self.TxThresholdRdTblIf = TxThresholdRdTblIf
        self.RxTimeRdTblIf = RxTimeRdTblIf
        self.RxThresholdRdTblIf = RxThresholdRdTblIf
        self.TxInfoTbl = TxInfoTbl
        self.RxInfoTbl = RxInfoTbl
        self.ErrfatalWrTblIf = ErrfatalWrTblIf
        self.DmawrusedidxirqflagWrTblIf = DmawrusedidxirqflagWrTblIf
        

        self.usedidxWrTblIf.set_wr_callback(self._usedidxWrCallback)
        self.usedelemptrTblIf.set_callback(self._usedelemptrRdCallback)
        self.usedelemptrTblIf.set_wr_callback(self._usedelemptrWrCallback)
        self.msixtblWrTblIf.set_wr_callback(self._msixtblWrCallback)
        self.usedctxRdTblIf.set_callback(self._UsedctxRdCallback)
        self.TxTimeRdTblIf.set_callback(self._TxTimeRdCallback)
        self.TxThresholdRdTblIf.set_callback(self._TxThresholdRdCallback)
        self.RxTimeRdTblIf.set_callback(self._RxTimeRdCallback)
        self.RxThresholdRdTblIf.set_callback(self._RxThresholdRdCallback)
        self.TxInfoTbl.set_callback(self._TxInfoRdCallback)
        self.TxInfoTbl.set_wr_callback(self._TxInfoWrCallback)
        self.RxInfoTbl.set_callback(self._RxInfoRdCallback)
        self.RxInfoTbl.set_wr_callback(self._RxInfoWrCallback)
        self.ErrfatalWrTblIf.set_wr_callback(self._ErrfatalWrCallback)
        self.DmawrusedidxirqflagWrTblIf.set_wr_callback(self._DmawrusedidxirqflagWrCallback)

    async def create_queue(self, qid, dev_id, bdf, forced_shutdown, used_ring_addr, qdepth, msix_addr, msix_data, msix_enable, msix_time, msix_threshold):
        ctx = virtio_ctx(dev_id, bdf, forced_shutdown, used_ring_addr, int(math.log2(qdepth)), msix_addr, msix_data, msix_enable, msix_time, msix_threshold)
        if qid in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is already exists".format(qid))
        self.ctxs[qid] = ctx

    async def start_queue(self, qid):
        
        self.log.info("start_queueqqqqqqqq")   
        self.ctxs[qid].q_status = virtio_qstat_t.VIRTIO_Q_STATUS_DOING

    def stop_queue(self, qid):
        self.log.info("stop_queueqqqqqqqq") 
        self.ctxs[qid].q_status = virtio_qstat_t.VIRTIO_Q_STATUS_IDLE

    def destroy_queue(self, qid):
        if qid not in self.ctxs.keys():
            raise ValueError("The queue(qid:{}) is not exists".format(qid))
        del self.ctxs[qid]
        tx_key = qid >> 3
        if tx_key in self.tx_local_ctxs:
            del self.tx_local_ctxs[tx_key]
        rx_key = qid >> 3
        if rx_key in self.rx_local_ctxs:
            del self.rx_local_ctxs[rx_key]


