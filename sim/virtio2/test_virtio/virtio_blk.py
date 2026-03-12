#!/usr/bin/env python3
################################################################################
#  文件名称 : virtio_blk.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/10/21
#  功能描述 :
#
#  修改记录 :
#
#  版本号  日期       修改人       修改内容
#  v1.0  10/21     Joe Jiang   初始化版本
################################################################################
import random
import os
import cocotb
import copy
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from cocotb.utils import get_sim_time

from generate_eth_pkg import *
from test_virtio_net_tb import TB
from virtio_net_defines import (
    Cfg,
    VirtioStatus,
    VirtioVq,
    TestType,
    IO_Req_Type,
    VirtBlkInfo,
    Mbufs,
    VirtioBlkType,
    VirtioBlkOuthdr,
    VirtqBlkReqHeader,
    VirtqBlkRspHeader,
    VirtioErrCode,
)
from virtio_net_func import *


def gen_hdr(id, op_type=None):
    sector = randbit(64)
    # 默认是写
    header = VirtioBlkOuthdr(type=op_type, ioprio=id, sector=sector).build()[::-1]
    return header


async def gen_pkt(mem, bdf, dev_id, id, op_type, pld_data, pld_data_len, len_list, log=None):
    regs = []
    hdr_data = gen_hdr(id, op_type)
    hdr_reg = mem.alloc_region(16, bdf=bdf, dev_id=dev_id)
    # log.info(f"mem: {hdr_reg.get_absolute_address(0):x}")
    regs.append(hdr_reg)
    await hdr_reg.write(0, hdr_data)
    if op_type == VirtioBlkType.VIRTIO_BLK_T_OUT:
        for length in len_list:
            pld_reg = mem.alloc_region(length, bdf=bdf, dev_id=dev_id)
            await pld_reg.write(0, pld_data[:length])
            pld_data = pld_data[length:]
            regs.append(pld_reg)
    elif op_type == VirtioBlkType.VIRTIO_BLK_T_IN:
        for length in len_list:
            pld_reg = mem.alloc_region(length, bdf=bdf, dev_id=dev_id)
            regs.append(pld_reg)
    else:
        pld_data_len = 0
    sts_reg = mem.alloc_region(1, bdf=bdf, dev_id=dev_id)
    # log.info(f"mem: {sts_reg.get_absolute_address(0):x}")
    regs.append(sts_reg)
    return Mbufs(regs, 17 + pld_data_len, op_type)


class VirtioBLK:
    def __init__(self, tb: TB):
        self.tb: TB = tb
        self.cfg: Cfg = tb.cfg
        self.log = tb.log
        self.mem = tb.mem
        self.dut = tb.dut
        self.interfaces = tb.interfaces
        self.pmd = tb.virtio_pmd

        self.id: Dict[int, int] = {}
        self.id_alllocator: Dict[int, ResourceAllocator] = {}
        self.blk_tx_act_queues = {}
        self.blk_exp_queues: Dict[int, Dict[int, VirtBlkInfo]] = {}
        self.blk_act_queues = Queue()
        self.blk_tx_act_queues_hdr = {}
        self.blk_tx_act_queues_data = {}
        self.blk_tx_act_queues_chain = {}

        self.ref_pkt_num = Queue()
        self.forced_shutdown_queues = {}
        self.qos_req_queue = Queue()
        self.qos_update_queues = {}
        self._gen_pkt_cr = {}
        self.qos_req_queue = Queue()
        self.pkt_time_start = None
        self.pkt_time_last = None
        # self.pps_cnt = 0
        # self.bps_cnt = 0
        self.status = VirtioStatus.IDLE
        # self.tx_check_result = {}
        self.send_num = {}
        self.doing = False

    def start(self, qid_list):
        self.doing = True
        for qid in qid_list:
            # self._qos_total_len[qid] = 0
            # self._req_queues[qid] = Queue(maxsize=16)
            # self.done[qid] = False
            self.blk_exp_queues[qid] = {}
            self.blk_tx_act_queues_hdr[qid] = None
            self.blk_tx_act_queues_data[qid] = None
            self.blk_tx_act_queues_chain[qid] = []
            # self._finish_seq_num[qid] = 0
            # self._gen_req_cr[qid] = cocotb.start_soon(self._gen_req(qid))
            # self._checker_cr[qid] = cocotb.start_soon(self._blk_checker(qid))
            self.id[qid] = 0
            self.id_alllocator[qid] = ResourceAllocator(0, 65535)
            self.send_num[qid] = 0
        self.blk_tx_act_queues = Queue()
        self._blk_backend_req_cr = cocotb.start_soon(self._blk_backend_req())
        self._blk_backend_rsp_cr = cocotb.start_soon(self._blk_backend_rsp())
        self._process_qos_req_cr = cocotb.start_soon(self._process_qos_req())
        self._process_qos_rsp_cr = cocotb.start_soon(self._process_qos_rsp())
        # self._process_qos_update_cr = cocotb.start_soon(self._process_qos_update())

    async def join(self, qid_list):
        self.doing = False
        for qid in qid_list:
            await self._checker_cr[qid].join()
            self._blk_backend_rsp_cr[qid].kill()
            self._gen_req_cr[qid].join()
        self._process_qos_req_cr.kill()
        self._process_qos_rsp_cr.kill()
        self._process_qos_update_cr.kill()
        self._blk_backend_req_cr.kill()
        await Timer(8, "us")
        for qid in qid_list:
            while not self._req_queues[qid].empty():
                mbuf = self._req_queues[qid].get_nowait()
                for reg in mbuf.regs:
                    self.mem.free_region(reg)

    async def _gen_pkt(self, qid) -> Mbufs:
        vq = VirtioVq.qid2vq(qid, TestType.BLK)
        virtq = self.pmd.virtq[vq]
        typ = random.choice(
            [
                VirtioBlkType.VIRTIO_BLK_T_IN,
                VirtioBlkType.VIRTIO_BLK_T_OUT,
                VirtioBlkType.VIRTIO_BLK_T_FLUSH,
                VirtioBlkType.VIRTIO_BLK_T_DISCARD,
                VirtioBlkType.VIRTIO_BLK_T_WRITE_ZEROES,
            ]
        )
        idx = self.id_alllocator[qid].alloc_id()
        max_chain_num = min(self.cfg.max_chain_num, self.pmd.virtq[vq].qsz)
        mu = self.cfg.min_chain_num + min((max_chain_num - self.cfg.min_chain_num) // 3, 16)
        desc_cnt = rand_norm_int(self.cfg.min_chain_num, max_chain_num, mu)
        len_list = []
        if random.randint(0, 100) > 98:
            for i in range(desc_cnt):
                len_list.append(random.randint(1, 15))
        else:
            for i in range(desc_cnt):
                mu = 1 + min(self.cfg.max_len // 3, 512)
                length = rand_norm_int(1, self.cfg.max_len, mu)
                len_list.append(length)
        if typ == VirtioBlkType.VIRTIO_BLK_T_OUT:  # write
            length = sum(len_list)
            pld_data = bytearray(fake_urandom(length))
        elif typ == VirtioBlkType.VIRTIO_BLK_T_IN:  # read
            length = sum(len_list)
            pld_data = None
        else:
            length = None
            len_list = []
            pld_data = None
        # self.log.info("_gen_req qid:{} id {} typ {} length {} len_list {} {}".format(qid, id, blk_type_map(typ), length, len_list, desc_cnt))
        bdf = virtq.bdf
        dev_id = virtq.dev_id
        mbuf = await gen_pkt(
            mem=self.mem, id=(idx << 16) + (self.id[qid] % 65536), op_type=typ, pld_data=pld_data, pld_data_len=length, len_list=len_list, bdf=bdf, dev_id=dev_id, log=self.log
        )
        self.blk_exp_queues[qid][idx] = VirtBlkInfo(id=int(self.id[qid]), fe_typ=typ, fe_data=pld_data, fe_len=length)
        # self.log.debug(f"blk gen_pkt  seq_num {self.blk_exp_queues[qid][idx].id} idx {idx}")
        self.id[qid] = self.id[qid] + 1
        return mbuf

    async def _blk_backend_req(self):
        while self.doing:
            blk_req = await self.interfaces.blk2beq_if.recv()
            data = blk_req.data[blk_req.sty :]
            qid = blk_req.user0 & 0xFFFF
            host_gen = (blk_req.user0 & 0xFF0000) >> 16
            start_of_pkt = blk_req.user0 & (1 << 24) != 0
            end_of_pkt = blk_req.user0 & (1 << 25) != 0
            forced_shutdown = blk_req.user0 & (1 << 26)
            err_info = (blk_req.user0 >> 32) & 0xFF
            await self.blk_tx_act_queues.put((qid, IO_Req_Type(data, host_gen, start_of_pkt, end_of_pkt, forced_shutdown, err_info)))

    async def _blk_backend_rsp(self):
        # gen = None
        # is_hdr = True
        # req_hdr = None
        # req_data = None
        # self.blk_tx_act_queues_chain[qid] = []
        # force_shutdown = False
        while True:
            qid, io_req = await self.blk_tx_act_queues.get()
            vq = VirtioVq.qid2vq(qid, TestType.BLK)
            virtq = self.pmd.virtq[vq]

            host_gen = io_req.host_gen
            data = io_req.data
            start_of_pkt = io_req.start_of_pkt
            end_of_pkt = io_req.end_of_pkt
            forced_shutdown = io_req.forced_shutdown
            err_info = io_req.err_info & 0x7F
            
            if virtq.blk_status==False:
                self.log.error(f"vq {VirtioVq.vq2str(vq)} blk_status pass")
                continue

            if start_of_pkt:
                self.blk_tx_act_queues_hdr[qid] = VirtqBlkReqHeader().unpack(data[::-1])
                self.blk_tx_act_queues_data[qid] = b''
                # self.log.debug("qid {} is hdr {} hdr {} ".format(qid, start_of_pkt, self.blk_tx_act_queues_hdr[qid].show(dump=True)))
            else:
                self.blk_tx_act_queues_data[qid] = self.blk_tx_act_queues_data[qid] + data

            only_hdr = (start_of_pkt and end_of_pkt and (self.blk_tx_act_queues_hdr[qid].flags & 0x2)) != 0
            last_hdr = not (self.blk_tx_act_queues_hdr[qid].flags & 0x1)

            if end_of_pkt:
                self.blk_tx_act_queues_chain[qid].append((self.blk_tx_act_queues_hdr[qid], self.blk_tx_act_queues_data[qid]))

            if forced_shutdown:
                self.blk_tx_act_queues_hdr[qid] = None
                self.blk_tx_act_queues_data[qid] = b''
                self.blk_tx_act_queues_chain[qid] = []
                continue

            if err_info != VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                vq_str = VirtioVq.vq2str(vq)
                if err_info not in virtq.err_info_option and err_info != virtq.err_info:
                    # self.log.error(f"vq: {vq_str}")
                    self.log.error(f"vq: {vq_str} act err_info {str(VirtioErrCode(err_info))} ")
                    self.log.error(f"vq: {vq_str} exp virtq.err_info {str(virtq.err_info)} ")
                    self.log.error(f"vq: {vq_str} virtq.err_info_option {virtq.err_info_option} ")
                    raise Exception("unexcept err_info")
                self.blk_tx_act_queues_hdr[qid] = None
                self.blk_tx_act_queues_data[qid] = b''
                self.blk_tx_act_queues_chain[qid] = []
                virtq.blk_status = False
                # self.blk_tx_act_queues_status[qid] = False
                self.log.debug(f"vq {vq_str} blk_be_rsp with err {str(VirtioErrCode(err_info))}")
                continue

            if last_hdr:  # status flags.next = 0 flags.write = 1
                if not only_hdr:
                    await Timer(100, "ns")
                    self.log.error(f"qid: {qid} ")
                    self.log.error(f"{self.blk_tx_act_queues_hdr[qid].show(dump=True)} ")
                    raise Exception(f"last_hdr should be only_hdr")

                # self.log.debug("qid {} only_hdr {} last_hdr {}".format(qid, only_hdr, last_hdr))
                req_hdr, req_data = self.blk_tx_act_queues_chain[qid].pop(0)
                desc_idx = req_hdr.desc_idx

                blk_hdr = VirtioBlkOuthdr().unpack(req_data[::-1])
                id = blk_hdr.ioprio >> 16
                info = self.blk_exp_queues[qid][id]

                if blk_hdr.type != info.fe_typ:
                    raise Exception(f"blk_backend_req type error")

                info.be_vq_gid = qid
                info.be_host_gen = host_gen
                sts = int(randbit(8)).to_bytes(1, "little")
                info.be_sts = sts
                vq = VirtioVq.qid2vq(qid, TestType.BLK)

                if blk_hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:  # read
                    used_len = info.fe_len + 1
                else:
                    used_len = 1

                if blk_hdr.type == VirtioBlkType.VIRTIO_BLK_T_OUT:  # write
                    info.be_data = b''
                    for _ in range(len(self.blk_tx_act_queues_chain[qid]) - 1):
                        req_hdr, req_data = self.blk_tx_act_queues_chain[qid].pop(0)
                        info.be_data = info.be_data + req_data

                elif blk_hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:  # read
                    info.be_data = b''
                    for _ in range(len(self.blk_tx_act_queues_chain[qid]) - 1):
                        req_hdr, req_data = self.blk_tx_act_queues_chain[qid].pop(0)
                        pld_data = bytearray(fake_urandom(req_hdr.host_buf_len))
                        info.be_data = info.be_data + pld_data
                        rsp_hdr = VirtqBlkRspHeader(
                            vq_gid=qid,
                            vq_gen=host_gen,
                            desc_idx=desc_idx,
                            flags=req_hdr.flags,
                            host_buf_addr=req_hdr.host_buf_addr,
                            used_len=used_len,
                            used_idx=virtq.backend_used_idx,
                            magic_num=0xC0DE,
                        )
                        # self.log.debug("write data qid {} rsp_hdr {}".format(qid, rsp_hdr.show(dump=True)))
                        await self.interfaces.beq2blk_if.send(qid, rsp_hdr.build()[::-1] + pld_data, randbit(40))
                else:
                    info.be_data = b''
                req_hdr, req_data = self.blk_tx_act_queues_chain[qid].pop(0)
                rsp_hdr = VirtqBlkRspHeader(
                    vq_gid=qid,
                    vq_gen=host_gen,
                    desc_idx=desc_idx,
                    flags=req_hdr.flags,
                    host_buf_addr=req_hdr.host_buf_addr,
                    used_len=used_len,
                    used_idx=virtq.backend_used_idx,
                    magic_num=0xC0DE,
                )
                # self.log.debug(f"write sts seq_num {blk_hdr.ioprio%65536} qid {qid} rsp_hdr {rsp_hdr.show(dump=True)}")
                await self.interfaces.beq2blk_if.send(qid, rsp_hdr.build()[::-1] + sts, randbit(40))
                virtq.backend_used_idx = virtq.backend_used_idx + 1

    async def _process_qos_req(self):
        while True:
            req_trans = await self.interfaces.blk_qos.query_req_if.recv()
            if self.qos_req_queue.full():
                raise Exception("qos_req_queue is full")
            self.qos_req_queue.put_nowait(req_trans)

    async def _process_qos_rsp(self):
        while True:
            req_trans = await self.qos_req_queue.get()
            rsp_trans = self.interfaces.blk_qos.query_rsp_if._transaction_obj()
            if random.random() < self.cfg.random_qos:
                rsp_trans.ok = 1
            else:
                rsp_trans.ok = 0
            await self.interfaces.blk_qos.query_rsp_if.send(rsp_trans)

    async def _process_qos_update(self):
        while True:
            update_trans = await self.interfaces.blk_qos.update_if.recv()
            qid = int(update_trans.uid)
            vq = VirtioVq.qid2vq(qid, TestType.BLK)
            self._qos_total_len[qid] = self._qos_total_len[qid] + int(update_trans.len)
            if update_trans.pkt_num:
                ref_len = await self.pmd.qos_update_queues[vq].get()
                if self._qos_total_len[qid] != ref_len:
                    self.log.warning("{}  ref length: {} cur length {}".format(VirtioVq.vq2str(vq), ref_len, self._qos_total_len[qid]))
                    raise Exception("blk qos length is mismatch")
                self._qos_total_len[qid] = 0

    # async def _blk_checker(self, qid):
    #     vq = VirtioVq.qid2vq(qid, TestType.BLK)
    #     for i in range(self.cfg.max_seq):
    #         hdr, pld_data, used_len, sts = await self.pmd.blk_rsp_queues[vq].get()
    #         self.log.info("_blk_checker seq {} hdr {}".format(hdr.ioprio, hdr.show(dump=True)))
    #         id = hdr.ioprio >> 16
    #         info = self.blk_exp_queues[qid][id]
    #         info.fe_sts = sts
    #         if hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:  # read
    #             info.fe_data = pld_data
    #             info.fe_len = used_len - 1
    #         # checker
    #         if info.fe_typ != hdr.type:
    #             self.log.warning("{} id {} seq_num {} ref {} cur {}".format(VirtioVq.vq2str(vq), id, self._finish_seq_num[qid], info.fe_typ, hdr.type))
    #             raise Exception("blk checker status is mismatch")
    #         if hdr.type == VirtioBlkType.VIRTIO_BLK_T_OUT or hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:
    #             if info.fe_len != len(info.be_data):
    #                 self.log.warning("{} id {} seq_num {}".format(VirtioVq.vq2str(vq), id, self._finish_seq_num[qid]))
    #                 self.log.warning("be: {}".format(len(info.be_data)))
    #                 self.log.warning("fe: {}".format(info.fe_len))
    #                 raise Exception("blk checker len is mismatch")
    #             if info.fe_data != info.be_data:
    #                 self.log.warning("{} id {}  seq_num {}".format(VirtioVq.vq2str(vq), id, self._finish_seq_num[qid]))
    #                 self.log.warning("be: {}".format(info.be_data.hex()))
    #                 self.log.warning("fe: {}".format(info.fe_data.hex()))
    #                 raise Exception("blk checker data is mismatch")
    #         if info.fe_sts != info.be_sts:
    #             self.log.warning("{} id {} seq_num {} be {} fe {}".format(VirtioVq.vq2str(vq), id, self._finish_seq_num[qid], info.be_sts, info.fe_sts))
    #             raise Exception("blk checker status is mismatch")
    #         self.log.info("qid {} id {} seq_num {} pass!".format(qid, id, self._finish_seq_num[qid]))
    #         self._finish_seq_num[qid] = self._finish_seq_num[qid] + 1
    #         del self.blk_exp_queues[qid][id]
    #     self.done[qid] = True
