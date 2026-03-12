import cocotb
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout, Lock
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.triggers import Lock
from cocotb.triggers import Timer, with_timeout, Combine
from dataclasses import dataclass

import logging

from test_virtio_net_tb import TB
from virtio_net_defines import *


@dataclass
class VirtioCtrl_StartCfg:
    vq: int
    qszWidth: int
    avail_idx: int
    avail_ring_addr: int
    used_ring_addr: int
    desc_tbl_addr: int
    indirct_support: int
    bdf: int
    dev_id: int
    tso_en: int
    csum_en: int
    max_len: int
    gen: int
    msix_addr: int
    msix_data: int
    msix_en: int
    qos_en: int
    qos_unit: int
    msix_time:Optional[int]
    msix_threshold:Optional[int]


class VirtioCtrl:
    def __init__(self, tb: TB):
        self.tb: TB = tb
        self.cfg: Cfg = tb.cfg
        self.log: logging.Logger = tb.log
        # self.soc_notify_queues = tb.soc_notify_queues
        self.tx_qos = tb.interfaces.tx_qos
        self.rx_qos = tb.interfaces.rx_qos
        self.csr_if = tb.interfaces.csr_if
        # self.soc_notify_queues_lock = Lock()
        # cocotb.start_soon(self._soc_notify_serivce())

    async def global_reg_write(self):
        await self.csr_if.write(GlobalRegOffset.RX_BUF_G_CSUM_EN_OFFSET, self.cfg.global_rx_csum_en)
        await self.csr_if.write(GlobalRegOffset.RX_BUF_G_TIME_SEL_OFFSET, self.cfg.global_rx_time_sel)
        await self.csr_if.write(GlobalRegOffset.RX_BUF_G_RANDOM_SEL_OFFSET, self.cfg.global_rx_random_sel)

    async def reg_write(self, vq, offset, data):
        qid, typ = VirtioVq.vq2qid(vq)
        addr = typ * 0x1000 + qid * 0x4000 + offset
        await self.csr_if.write(addr, data)

    async def reg_read(self, vq, offset):
        qid, typ = VirtioVq.vq2qid(vq)
        addr = typ * 0x1000 + qid * 0x4000 + offset
        data = await self.csr_if.read(addr)
        return data

    # async def set_msix_aggregation(self, vq, time, threshold):
    #     await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_AGGREGATION_TIME, time)
    #     await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_AGGREGATION_THRESHOLD, threshold)

    async def set_msix_en(self, vq, msix_en):
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_ENABLE, msix_en)

    async def set_msix_mask(self, vq, msix_mask):
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_MASK, msix_mask)

    async def set_msix_addr(self, vq, msix_addr):
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_ADDR, msix_addr)

    # async def set_qos(self, vq, qos_en, qos_unit):
    #     self.qos_en = qos_en
    #     await self.reg_write(vq, QOS_ENABLE, self.qos_en)
    #     self.qos_unit = qos_unit
    #     await self.reg_write(vq, QOS_L1_UNIT, self.qos_unit)

    async def start(self, cfg: VirtioCtrl_StartCfg):
        vq = cfg.vq
        qid, typ = VirtioVq.vq2qid(vq)
        virtq = self.tb.virtio_pmd.virtq[vq]
        status = (await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) & 0xF
        if status != VirtioStatus.IDLE:
            raise ValueError("vq{} status is not idle(cur status: {})".format(VirtioVq.vq2str(cfg.vq), VirtioStatus(status)))
        await self.reg_write(vq, VirtioCtrlRegOffset.BDF, cfg.bdf)
        await self.reg_write(vq, VirtioCtrlRegOffset.DEV_ID, cfg.dev_id)
        await self.reg_write(vq, VirtioCtrlRegOffset.AVAIL_RING_ADDR, cfg.avail_ring_addr)
        await self.reg_write(vq, VirtioCtrlRegOffset.USED_RING_ADDR, cfg.used_ring_addr)
        await self.reg_write(vq, VirtioCtrlRegOffset.DESC_ADDR, cfg.desc_tbl_addr)
        await self.reg_write(vq, VirtioCtrlRegOffset.QSIZE, cfg.qszWidth)
        await self.reg_write(vq, VirtioCtrlRegOffset.INDIRECT_SUPPORT, (cfg.csum_en << 2) + (cfg.tso_en << 1) + cfg.indirct_support)
        await self.reg_write(vq, VirtioCtrlRegOffset.MAX_LEN, cfg.max_len)
        await self.reg_write(vq, VirtioCtrlRegOffset.GENERATION, cfg.gen)
        await self.reg_write(vq, VirtioCtrlRegOffset.AVAIL_IDX, cfg.avail_idx)
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_ADDR, cfg.msix_addr)
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_DATA, cfg.msix_data)
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_ENABLE, cfg.msix_en)
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_AGGREGATION_TIME, cfg.msix_time)
        await self.reg_write(vq, VirtioCtrlRegOffset.MSIX_AGGREGATION_THRESHOLD, cfg.msix_threshold)
        await self.reg_read(vq, VirtioCtrlRegOffset.MSIX_AGGREGATION_TIME)
        await self.reg_write(vq, VirtioCtrlRegOffset.QOS_ENABLE, cfg.qos_en)
        await self.reg_write(vq, VirtioCtrlRegOffset.QOS_L1_UNIT, cfg.qos_unit)
        await self.reg_write(vq, VirtioCtrlRegOffset.CTRL, VirtioStatus.STARTING)
        virtq.status = VirtioStatus.STARTING
        status = VirtioStatus((await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) & 0xF)
        if status != VirtioStatus.STARTING:
            raise ValueError(f"vq{VirtioVq.vq2str(vq)} status is not starting(cur status: {status})")

        # if typ == TestType.NETTX:
        #     self.virt_net.tx.forced_shutdown[qid] = False
        #     self.virt_net.tx.forced_shutdown_drop[qid] = False

    async def stop(self, vq, forced_shutdown):
        qid, typ = VirtioVq.vq2qid(vq)
        virtq = self.tb.virtio_pmd.virtq[vq]
        cur_status = await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)
        shutdown_status = cur_status & 0x10
        status = VirtioStatus(cur_status & 0xF)
        if status != VirtioStatus.STARTING and status != VirtioStatus.DOING:
            while status == VirtioStatus.STOPPING and shutdown_status == VirtioStatus.FORCED_SHUTDOWN:
                await Timer(1, "us")
                cur_status = await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)
                shutdown_status = cur_status & 0x10
                status = VirtioStatus(cur_status & 0xF)
            if status == VirtioStatus.IDLE:
                return
            raise ValueError(f"vq{VirtioVq.vq2str(vq)} status is not STARTING(cur status: {cur_status})")
        if forced_shutdown:
            ctrl = VirtioStatus.STOPPING + VirtioStatus.FORCED_SHUTDOWN
        else:
            ctrl = VirtioStatus.STOPPING
        await self.reg_write(vq, VirtioCtrlRegOffset.CTRL, ctrl)
        virtq.status = VirtioStatus.STOPPING
        while status != VirtioStatus.IDLE:
            rsp_data = await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)
            status = rsp_data & 0xF
            read_forced_shutdown = (rsp_data & 0x10) >> 4
            if status != VirtioStatus.STOPPING and status != VirtioStatus.IDLE:
                raise ValueError("vq{} status is not stopping or idle(cur status: {})".format(VirtioVq.vq2str(vq), VirtioStatus(status)))
            # if status == VirtioStatus.IDLE:
            #     if forced_shutdown:
            #         if typ == TestType.NETTX:
            #             self.virt_net.tx.forced_shutdown[qid] = True
            #     break
            # if read_forced_shutdown == 1:
            #     if typ == TestType.NETTX:
            #         self.virt_net.tx.forced_shutdown[qid] = True
            await Timer(100, "ns")
            # status = (await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) & 0xF
        err_info = await self.tb.virtio_ctrl.read_err_info(vq)
        if err_info is not VirtioErrCode.VIRTIO_ERR_CODE_NONE:
            self.log.info(err_info)
            if err_info is not virtq.err_info and err_info not in virtq.err_info_option:
                self.log.error(vq)
                self.log.error(virtq.err_info)
                self.log.error(virtq.err_info_option)
                raise ValueError(f"err_info err: {err_info}")

    async def wait_idle(self, vq):
        status = VirtioStatus.STOPPING
        while status != VirtioStatus.IDLE:
            await Timer(1, "us")
            status = (await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) & 0xF
            if status != VirtioStatus.STOPPING and status != VirtioStatus.IDLE:
                raise ValueError("vq{} status is not stopping or idle(cur status: {})".format(VirtioVq.vq2str(vq), VirtioStatus(status)))

    async def write_soc_notify(self, vq: int) -> None:
        await self.reg_write(vq, VirtioCtrlRegOffset.SOC_NOTIFY, 0)
        pass

    async def read_status(self, vq: int) -> VirtioStatus:
        return VirtioStatus((await self.reg_read(vq, VirtioCtrlRegOffset.CTRL)) & 0xF)

    async def read_err_info(self, vq: int) -> VirtioErrCode:
        return VirtioErrCode((await self.reg_read(vq, VirtioCtrlRegOffset.ERR_INFO) & 0x7F))
