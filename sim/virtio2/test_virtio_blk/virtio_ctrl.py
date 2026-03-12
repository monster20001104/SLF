#!/usr/bin/env python3
################################################################################
#  文件名称 : virtio_ctrl.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/10/21
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  10/21     Joe Jiang   初始化版本
################################################################################
import cocotb
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout, Lock
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from virtio_defines import *
from cocotb.triggers import Lock
from cocotb.triggers import Timer, with_timeout, Combine



class VirtioCtrl:
    def __init__(self, cfg, log, soc_notify_queues, csr_if):
        self.cfg: Cfg                   = cfg
        self.log                        = log
        self.soc_notify_queues          = soc_notify_queues
        self.csr_if                     = csr_if
        self.soc_notify_queues_lock     = Lock()

        cocotb.start_soon(self._soc_notify_serivce())

    async def global_reg_write(self):
        await self.csr_if.write(GlobalRegOffset.RX_BUF_G_CSUM_EN_OFFSET     , self.cfg.global_rx_csum_en   )
        await self.csr_if.write(GlobalRegOffset.RX_BUF_G_TIME_SEL_OFFSET    , self.cfg.global_rx_time_sel  )
        await self.csr_if.write(GlobalRegOffset.RX_BUF_G_RANDOM_SEL_OFFSET  , self.cfg.global_rx_random_sel)

    async def reg_write(self, vq, offset, data):
        qid, typ = vq2qid(vq)
        addr = typ*0x1000 + qid*0x4000 + offset
        await self.csr_if.write(addr, data)

    async def reg_read(self, vq, offset):
        qid, typ = vq2qid(vq)
        addr = typ*0x1000 + qid*0x4000 + offset
        data = await self.csr_if.read(addr)
        return data

    async def set_msix_aggregation(self, vq, time, threshold):
        await self.reg_write(vq, MSIX_AGGREGATION_TIME,         time)
        await self.reg_write(vq, MSIX_AGGREGATION_THRESHOLD,    threshold)

    async def set_msix_en(self, vq, msix_en):
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_ENABLE,       msix_en)

    async def set_msix_mask(self, vq, msix_mask):
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_MASK,       msix_mask)

    async def set_msix_addr(self, vq, msix_addr):
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_ADDR,         msix_addr)

    async def set_qos(self, vq, qos_en, qos_unit):
        self.qos_en     = qos_en
        await self.reg_write(vq, QOS_ENABLE,        self.qos_en)
        self.qos_unit   = qos_unit
        await self.reg_write(vq, QOS_L1_UNIT,       self.qos_unit)

    async def start(self, vq, qszWidth, avail_idx, avail_ring_addr, used_ring_addr, desc_tbl_addr, indirct_support, bdf, dev_id, max_len, gen, msix_addr, msix_data, msix_en, qos_en, qos_unit):
        status = (await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) &  0xf
        if status != VirtioStatus.IDLE:
            raise ValueError("vq{} status is not idle(cur status: {})".format(vq_str(vq), status_str(status)))
        await self.reg_write(vq, VirtioCtrlRegOffset.BDF,               bdf)
        await self.reg_write(vq, VirtioCtrlRegOffset.DEV_ID,            dev_id)
        await self.reg_write(vq, VirtioCtrlRegOffset.AVAIL_RING_ADDR,   avail_ring_addr)
        await self.reg_write(vq, VirtioCtrlRegOffset.USED_RING_ADDR,    used_ring_addr)
        await self.reg_write(vq, VirtioCtrlRegOffset.DESC_ADDR,         desc_tbl_addr)
        await self.reg_write(vq, VirtioCtrlRegOffset.QSIZE,             qszWidth)
        await self.reg_write(vq, VirtioCtrlRegOffset.INDIRECT_SUPPORT,  indirct_support)
        await self.reg_write(vq, VirtioCtrlRegOffset.MAX_LEN,           max_len)
        await self.reg_write(vq, VirtioCtrlRegOffset.GENERATION,        gen)
        await self.reg_write(vq, VirtioCtrlRegOffset.AVAIL_IDX,         avail_idx)
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_ADDR,         msix_addr)
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_DATA,         msix_data)
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_ENABLE,       msix_en)
        await self.reg_write(vq, VirtioCtrlRegOffset.QOS_ENABLE,        qos_en)
        await self.reg_write(vq, VirtioCtrlRegOffset.QOS_L1_UNIT,       qos_unit)
        await self.reg_write(vq, VirtioCtrlRegOffset.CTRL, VirtioStatus.STARTING)
        status = (await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) &  0xf
        if status != VirtioStatus.STARTING:
            raise ValueError("vq{} status is not starting(cur status: {})".format(vq_str(vq), status_str(status)))

    async def stop(self, vq, forced_shutdown):
        status = (await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) &  0xf
        if status != VirtioStatus.STARTING and status != VirtioStatus.DOING:
            raise ValueError("vq{} status is not STARTING(cur status: {})".format(vq_str(vq), status_str(status)))
        if forced_shutdown:
            ctrl = VirtioStatus.STOPPING + VirtioStatus.FORCED_SHUTDOWN
        else:
            ctrl = VirtioStatus.STOPPING
        await self.reg_write(vq, VirtioCtrlRegOffset.CTRL, ctrl)
        await Timer(1, "us")

    async def wait_stop_finish(self, vq):
        status = (await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) &  0xf
        while status != VirtioStatus.IDLE:
            await Timer(1, "us")
            status = (await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) &  0xf
            if status != VirtioStatus.STOPPING and status != VirtioStatus.IDLE:
                raise ValueError("vq{} status is not stopping or idle(cur status: {})".format(vq_str(vq), status_str(status)))


    async def _soc_notify_serivce(self):
        while True:
            await self.soc_notify_queues_lock.acquire()
            try:
                for vq in self.soc_notify_queues.keys():
                    soc_notify_queue = self.soc_notify_queues[vq]
                    if not soc_notify_queue.empty():
                        vq = soc_notify_queue.get_nowait()
                        await self.reg_write(vq, VirtioCtrlRegOffset.SOC_NOTIFY, 0)
            finally:
                self.soc_notify_queues_lock.release()
            await Timer(1, "us")

