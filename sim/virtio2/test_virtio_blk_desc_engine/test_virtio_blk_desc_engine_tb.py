#!/usr/bin/env python3
################################################################################
#  文件名称 : test_virtio_blk_desc_engine_tb.py
#  作者名称 : lch
#  创建日期 : 2025/07/09
#  功能描述 :
#
#  修改记录 :
#
#  版本号  日期       修改人       修改内容
#  v1.0   07/09      Lch    初始化版本
#  v1.1   08/12      Lch    大概框架,使用VirtQ
################################################################################
import sys

sys.path.append("../../common")
import ding_robot
import logging
from logging.handlers import RotatingFileHandler
import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.log import SimLogFormatter
from cocotb.clock import Clock
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time

from address_space import Pool
from VirtQ import *
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster


class TB(object):
    def __init__(self, dut, cfg):
        self.cfg = cfg
        self.cfg.data_width = dut.DATA_WIDTH.value
        self.cfg.qid_width = dut.QID_WIDTH.value
        self.dut = dut
        self.dut.rst.setimmediatevalue(1)
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.INFO)
        # self.log.setLevel(logging.DEBUG)
        self.mem = Pool(None, 0, size=2**64, min_alloc=64)
        self.virtQ = VirtQ("BLK", self.mem, self.log, dut)
        self.done = 0
        self.dfx = MliteBusMaster(MliteBus.from_prefix(dut, "dfx_if"), dut.clk, dut.rst)

        self.SchReqMaster = SchReqMaster(
            SchReqBus.from_prefix(dut, "sch_req"), dut.clk, dut.rst
        )
        self.NotifyRspMaster = NotifyRspMaster(
            NotifyRspBus.from_prefix(dut, "notify_rsp"), dut.clk, dut.rst
        )
        self.NotifyRspQueue = Queue(32)
        self.AllocSlotRspSlaver = AllocSlotRspSlaver(
            AllocSlotRspBus.from_prefix(dut, "alloc_slot_rsp"), dut.clk, dut.rst
        )
        self.AllocSlotQueue = Queue(64)
        self.AvailIdReqSlaver = AvailIdReqSlaver(
            AvailIdReqBus.from_prefix(dut, "avail_id_req"), dut.clk, dut.rst
        )
        self.AvailIdRspMaster = AvailIdRspMaster(
            AvailIdRspBus.from_prefix(dut, "avail_id_rsp"), dut.clk, dut.rst
        )
        self.AvailIdQueue = Queue(4)
        self.ResummerSlaver = ResummerSlaver(
            rd_req_bus=ResummerReqBus.from_prefix(dut, "blk_desc_resummer_rd_req"),
            rd_rsp_bus=ResummerRspBus.from_prefix(dut, "blk_desc_resummer_rd_rsp"),
            wr_bus=ResummerWrBus.from_prefix(dut, "blk_desc_resumer_wr"),
            clock=dut.clk,
            reset=dut.rst,
            ready_latency=1,
        )
        self.ResummerSlaver.set_callback(self.resummer_slaver_cb)
        self.ResummerSlaver.set_wr_callback(self.resummer_slaver_wr_cb)
        self.GlbInfoSlaver = GlbInfoSlaver(
            rd_req_bus=GlbInfoReqBus.from_prefix(dut, "blk_desc_global_info_rd_req"),
            rd_rsp_bus=GlbInfoRspBus.from_prefix(dut, "blk_desc_global_info_rd_rsp"),
            wr_bus=None,
            clock=dut.clk,
            reset=dut.rst,
            ready_latency=1,
        )
        self.GlbInfoSlaver.set_callback(self.global_info_cb)
        self.LocInfoSlaver = LocInfoSlaver(
            rd_req_bus=LocInfoReqBus.from_prefix(dut, "blk_desc_local_info_rd_req"),
            rd_rsp_bus=LocInfoRspBus.from_prefix(dut, "blk_desc_local_info_rd_rsp"),
            wr_bus=LocInfoWrBus.from_prefix(dut, "blk_desc_local_info_wr"),
            clock=dut.clk,
            reset=dut.rst,
            ready_latency=1,
        )
        self.LocInfoSlaver.set_callback(self.loc_info_cb)
        self.LocInfoSlaver.set_wr_callback(self.loc_info_wr_cb)
        self.BLKDescSlaver = BLKDescSlaver(
            BLKDescBus.from_prefix(dut, "blk_desc"), dut.clk, dut.rst
        )

        self.ram_init()
        clk = Clock(dut.clk, 5, units="ns")
        cocotb.start_soon(clk.start(start_high=False))

    def set_idle_generator(self, generator=None):
        # pass
        if generator:
            self.NotifyRspMaster.set_idle_generator(generator)
            self.AvailIdRspMaster.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        # pass
        if generator:
            self.SchReqMaster.set_backpressure_generator(generator)
            self.AllocSlotRspSlaver.set_backpressure_generator(generator)
            self.AvailIdReqSlaver.set_backpressure_generator(generator)
            self.BLKDescSlaver.set_backpressure_generator(generator)
        #     self.QosUpSlaver.set_backpressure_generator(generator)
        #     self.InfoOutSlaver.set_backpressure_generator(generator)
        #     self.DataRspSlaver.set_backpressure_generator(generator)

    async def cycle_reset(self):

        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await Timer(2, "us")

    def ram_init(self):
        self.resummer_list = []
        self.loc_info_list = []
        self.q_descs = []
        self.q_info = []
        self.q_sbd = []
        self._local_ring = []
        for _ in range(2**self.cfg.qid_width):
            config = Config()
            config.pkt_len = 0
            self._local_ring.append(Queue(10))
            self.q_sbd.append(0)
            self.q_descs.append([])
            self.q_info.append(config)
            self.resummer_list.append(randbit(1))
            self.loc_info_list.append((0, 0, 0, 0, 0, 0, 0))

    async def _process_sch_req(self):
        while True:
            for vq, queue in self.virtQ._q.items():
                if not self.virtQ._q[vq]._avail_ring.empty():

                    while not self.virtQ._q[vq]._avail_ring.empty():
                        qid, typ = vq2qid(vq)
                        if self._local_ring[qid].full():
                            break
                        else:
                            ring = await self.virtQ._q[vq]._avail_ring.get()
                            await self._local_ring[qid].put(ring)
                    req_tran = SchReqTrans()
                    req_tran.vq = vq
                    await self.SchReqMaster.send(req_tran)

            await Timer(100, "ns")

    async def _process_avail_id_req(self):
        while True:
            req_tran = await self.AvailIdReqSlaver.recv()
            await self.AvailIdQueue.put(req_tran)

    async def _process_avail_id_rsp(self):
        while True:
            await Timer(1,"ns")
            req_tran = await self.AvailIdQueue.get()
            rsp_tran = AvailIdRspTrans()
            vq = req_tran.vq.value
            vq = qid2vq(vq, typ=2)
            qid, typ = vq2qid(vq)
            if vq in self.virtQ._q:
                if not self._local_ring[qid].empty():
                    if random.random() < 0.1:
                        rsp_tran.dat_id = random.randint(0, 1023)
                        rsp_tran.dat_idx = random.randint(0, 1023)
                        rsp_tran.dat_vq = vq
                        rsp_tran.dat_err_info = 0
                        rsp_tran.dat_local_ring_empty = 1
                        rsp_tran.dat_avail_ring_empty = 0
                        rsp_tran.dat_q_stat_doing = 1
                        rsp_tran.dat_q_stat_stopping = 0
                        await self.AvailIdRspMaster.send(rsp_tran)
                    elif random.random() < 0.1:
                        rsp_tran.dat_id = random.randint(0, 1023)
                        rsp_tran.dat_idx = random.randint(0, 1023)
                        rsp_tran.dat_vq = vq
                        rsp_tran.dat_err_info = 0
                        rsp_tran.dat_local_ring_empty = 0
                        rsp_tran.dat_avail_ring_empty = 0
                        rsp_tran.dat_q_stat_doing = 0
                        rsp_tran.dat_q_stat_stopping = 1
                        await self.AvailIdRspMaster.send(rsp_tran)
                    else:
                        (ring_id, avail_idx, pkt_id, err) = await self._local_ring[
                            qid
                        ].get()
                        rsp_tran.dat_id = ring_id
                        rsp_tran.dat_idx = avail_idx
                        rsp_tran.dat_vq = vq
                        rsp_tran.dat_err_info = err.pack()
                        rsp_tran.dat_local_ring_empty = 0
                        rsp_tran.dat_avail_ring_empty = 0
                        rsp_tran.dat_q_stat_doing = 1
                        rsp_tran.dat_q_stat_stopping = 0
                        await self.AvailIdRspMaster.send(rsp_tran)
                    continue
                else:
                    rsp_tran.dat_id = random.randint(0, 1023)
                    rsp_tran.dat_idx = random.randint(0, 1023)
                    rsp_tran.dat_vq = vq
                    rsp_tran.dat_err_info = 0
                    rsp_tran.dat_local_ring_empty = 1
                    rsp_tran.dat_avail_ring_empty = self.virtQ._q[vq]._avail_ring.empty()
                    rsp_tran.dat_q_stat_doing = 1
                    rsp_tran.dat_q_stat_stopping = 0
                    await self.AvailIdRspMaster.send(rsp_tran)
                    continue
            else:
                print(vq)
                raise Exception("Avail qid not exeit")

    def resummer_slaver_cb(self, req_tran):
        rsp_tran = ResummerRspTrans()
        qid = req_tran.qid.value
        rsp_tran.dat = self.resummer_list[qid]
        return rsp_tran

    def resummer_slaver_wr_cb(self, req_tran):
        qid = req_tran.qid
        dat = req_tran.dat
        self.resummer_list[qid] = dat

    async def _process_alloc_slot_rsp(self):
        while True:
            rsp_tran = await self.AllocSlotRspSlaver.recv()
            req_tran = NotifyRspTrans()
            req_tran.vq = rsp_tran.dat_vq.value

            err = rsp_tran.dat_err_info.value

            if rsp_tran.dat_q_stat_stopping.value == 1:
                req_tran.cold = 1
                req_tran.done = 0
                await self.AllocSlotQueue.put((req_tran,err))
                continue
            if (
                rsp_tran.dat_q_stat_stopping.value == 0
                and rsp_tran.dat_q_stat_doing.value == 0
            ):
                req_tran.cold = 0
                req_tran.done = 1
                await self.AllocSlotQueue.put((req_tran,err))
                continue
            if (
                rsp_tran.dat_q_stat_doing.value == 1
                and rsp_tran.dat_avail_ring_empty.value == 1
                and rsp_tran.dat_local_ring_empty.value == 1
            ):
                req_tran.cold = 0
                req_tran.done = 1
                await self.AllocSlotQueue.put((req_tran,err))
                continue
            if (
                rsp_tran.dat_q_stat_doing.value == 1
                and rsp_tran.dat_local_ring_empty.value == 1
            ):
                req_tran.cold = 1
                req_tran.done = 0
                await self.AllocSlotQueue.put((req_tran,err))
                continue



            req_tran.cold = 0
            req_tran.done = 0
            await self.AllocSlotQueue.put((req_tran,err))

    async def _process_notify_rsp(self):
        while True:
            rsp_tran = await self.NotifyRspQueue.get()
            await self.NotifyRspMaster.send(rsp_tran)

    def global_info_cb(self, req_tran):
        rsp_tran = GlbInfoRspTrans()
        qid = req_tran.qid.value
        vq = qid2vq(qid=qid, typ=TestType.BLK)

        if vq not in self.virtQ._q.keys():
            raise ValueError("The queue(vq:{}) is not exists".format(vq))
        # rsp = CtxInfoRdRspTransaction()
        rsp_tran.bdf = self.virtQ._q[vq]._bdf
        rsp_tran.forced_shutdown = self.virtQ._q[vq]._forced_shutdown
        rsp_tran.desc_tbl_addr = self.virtQ._q[vq]._desc_tbl.get_absolute_address(0)
        rsp_tran.qdepth = self.virtQ._q[vq]._depth_log2
        rsp_tran.indirct_support = self.virtQ._q[vq]._indirct_en
        rsp_tran.segment_size_blk = 65532
        # rsp_tran.segment_size_blk = self.virtQ._q[vq]._segment_size_blk
        return rsp_tran

    def loc_info_cb(self, req_tran):
        qid = req_tran.qid.value
        (
            desc_tbl_addr_blk,
            desc_tbl_size_blk,
            desc_tbl_next_blk,
            desc_tbl_id_blk,
            desc_cnt,
            data_len,
            is_indirct,
        ) = self.loc_info_list[qid]
        rsp_tran = LocInfoRspTrans()
        rsp_tran.desc_tbl_addr_blk = desc_tbl_addr_blk
        rsp_tran.desc_tbl_size_blk = desc_tbl_size_blk
        rsp_tran.desc_tbl_next_blk = desc_tbl_next_blk
        rsp_tran.desc_tbl_id_blk = desc_tbl_id_blk
        rsp_tran.desc_cnt = desc_cnt
        rsp_tran.data_len = data_len
        rsp_tran.is_indirct = is_indirct
        return rsp_tran

    def loc_info_wr_cb(self, req_tran):
        qid = req_tran.qid.value
        desc_tbl_addr_blk = req_tran.desc_tbl_addr_blk.value
        desc_tbl_size_blk = req_tran.desc_tbl_size_blk.value
        desc_tbl_next_blk = req_tran.desc_tbl_next_blk.value
        desc_tbl_id_blk = req_tran.desc_tbl_id_blk.value
        desc_cnt = req_tran.desc_cnt.value
        data_len = req_tran.data_len.value
        is_indirct = req_tran.is_indirct.value
        self.loc_info_list[qid] = (
            desc_tbl_addr_blk,
            desc_tbl_size_blk,
            desc_tbl_next_blk,
            desc_tbl_id_blk,
            desc_cnt,
            data_len,
            is_indirct,
        )

    async def _process_blk_desc_rsp(self):
        while True:
            if self.AllocSlotQueue.empty():
                if self.BLKDescSlaver.empty():
                    await RisingEdge(self.dut.clk)
                    continue
                else:
                    raise Exception("AllocSlotQueue empty")
            else:
                alloc_tran,err = self.AllocSlotQueue._queue[0]
                if alloc_tran.cold == 0 and alloc_tran.done == 0 and err == 0:
                    qid, typ = vq2qid(alloc_tran.vq)
                    descs = []
                    sbd = None
                    end = False
                    while True:
                        descRsp = await self.BLKDescSlaver.recv()
                        sbd = DescRspSbd().unpack(descRsp.sbd)
                        err_info = ErrInfo().unpack(int(sbd.err_info))
                        desc = VirtqDesc().unpack(descRsp.dat)
                        self.q_descs[qid].append(desc)
                        # self.q_sbd[qid] = sbd
                        if alloc_tran.vq != sbd.vq:
                            logging.error(f"alloc_tran:{alloc_tran}, sbd:{sbd}")
                            logging.error(f"alloc_tran:{alloc_tran.vq}, sbd:{sbd.vq}")
                            raise Exception("rsp_sbd.vq != alloc_rsp.vq")
                        if descRsp.eop.value == 1 or sbd.forced_shutdown:
                            self.q_info[qid].pkt_len = (
                                self.q_info[qid].pkt_len + sbd.total_buf_length
                            )
                            if (
                                (desc.flags_next == 0 and desc.flags_indirect == 0)
                                or err_info.err_code != 0
                                or sbd.forced_shutdown
                            ):
                                end = True

                            alloc_tran,err = self.AllocSlotQueue.get_nowait()
                            await self.NotifyRspQueue.put(alloc_tran)
                            break
                    if end:
                        q = self.virtQ._q[sbd.vq]
                        ref = q.ref_results.pop(0)
                        descs = self.q_descs[qid]
                        err_info = ErrInfo().unpack(int(sbd.err_info))

                        if sbd.dev_id != q._dev_id:
                            self.log.debug(
                                "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
                                    vq_str(sbd.vq),
                                    ref.pkt_id,
                                    ref.avail_idx,
                                    ref.ring_id,
                                    ref.pkt_len,
                                    len(ref.descs),
                                )
                            )
                            raise ValueError(
                                "dev_id mismatch vq{} seq_num {} ctx {} rdDescRsp {}".format(
                                    vq_str(sbd.vq), ref.seq_num, q._dev_id, sbd.dev_id
                                )
                            )
                        # if sbd.avail_idx != ref.avail_idx:
                        #     self.log.debug(
                        #         "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
                        #             vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)
                        #         )
                        #     )
                        #     raise ValueError(
                        #         "avail_idx mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(
                        #             vq_str(sbd.vq), ref.seq_num, ref.avail_idx, sbd.avail_idx
                        #         )
                        #     )
                        if sbd.ring_id != ref.ring_id:
                            self.log.error(
                                "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
                                    vq_str(sbd.vq),
                                    ref.pkt_id,
                                    ref.avail_idx,
                                    ref.ring_id,
                                    ref.pkt_len,
                                    len(ref.descs),
                                )
                            )
                            raise ValueError(
                                "ring_id mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(
                                    vq_str(sbd.vq),
                                    ref.seq_num,
                                    ref.ring_id,
                                    sbd.ring_id,
                                )
                            )

                        if ref.err != err_info and not sbd.forced_shutdown:
                            raise ValueError(
                                "err mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(
                                    vq_str(sbd.vq),
                                    ref.seq_num,
                                    ref.err.show(dump=True),
                                    err_info.show(dump=True),
                                )
                            )

                        if (
                            err_info == DefectType.VIRTIO_ERR_CODE_NONE
                            and not sbd.forced_shutdown
                        ):
                            if self.q_info[qid].pkt_len != ref.pkt_len:
                                self.log.debug(
                                    "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
                                        vq_str(sbd.vq),
                                        ref.pkt_id,
                                        ref.avail_idx,
                                        ref.ring_id,
                                        ref.pkt_len,
                                        self.q_info[qid].pkt_len,
                                    )
                                )
                                raise ValueError(
                                    "pkt_len mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(
                                        vq_str(sbd.vq),
                                        ref.seq_num,
                                        ref.pkt_len,
                                        sbd.total_buf_length,
                                    )
                                )
                            if len(descs) != len(ref.descs):
                                self.log.debug(
                                    "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
                                        vq_str(sbd.vq),
                                        ref.pkt_id,
                                        ref.avail_idx,
                                        ref.ring_id,
                                        len(descs),
                                        len(ref.descs),
                                    )
                                )
                                raise ValueError(
                                    "valid_desc_cnt mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(
                                        vq_str(sbd.vq),
                                        ref.seq_num,
                                        len(ref.descs),
                                        sbd.valid_desc_cnt,
                                    )
                                )
                            if ref.descs != descs:
                                for i in range(len(descs)):
                                    if ref.descs[i] != descs[i]:
                                        raise ValueError(
                                            "desc mismatch vq{} seq_num {} NO.{} ref {} rdDescRsp {}".format(
                                                vq_str(sbd.vq),
                                                ref.seq_num,
                                                i,
                                                ref.descs[i].show(dump=True),
                                                descs[i].show(dump=True),
                                            )
                                        )
                        if q._wait_finish:
                            self.log.debug(
                                f"wait_finish_push qid: {vq_str(sbd.vq)} seq_num = {ref.seq_num}"
                            )
                            q._wait_finish_event.set(ref.seq_num)

                        if sbd.forced_shutdown:
                            if not q._forced_shutdown:
                                raise ValueError(
                                    "forced_shutdown mismatch vq{} seq_num {}".format(
                                        vq_str(sbd.vq), ref.seq_num
                                    )
                                )
                            q.forced_shutdown_event.set(ref.seq_num)

                        self.log.warning(
                            "vq{} seq_num {} pass".format(vq_str(sbd.vq), ref.seq_num)
                        )
                        q._desc_idx_pool = q._desc_idx_pool + ref.idxs
                        if ref.indirct_desc_buf != None:
                            self.virtQ._mem.free_region(ref.indirct_desc_buf)
                        self.q_descs[qid] = []
                        self.q_info[qid].pkt_len = 0
                        self.done = self.done + 1
                        # self.log.error(f"self.done {self.done}")
                        pass
                else:
                    if err != 0:
                        self.done = self.done + 1
                        # self.log.error(f"self.done {self.done}")
                    alloc_tran,err = self.AllocSlotQueue.get_nowait()
                    await self.NotifyRspQueue.put(alloc_tran)


async def normal_test(dut, idle_inserter, backpressure_inserter):
    cfg = Config()
    cfg.max_q = 8
    # cfg.max_q = 1
    cfg.depth = 256
    # cfg.max_seq = 2
    cfg.max_seq = 10
    cfg.indirct_support = 1
    cfg.indirct_mix = True
    cfg.min_chain_num = 2
    # cfg.max_chain_num = 4
    cfg.max_chain_num = 300
    cfg.max_indirct_ptr = 1
    cfg.max_indirct_desc_size = 32768
    cfg.max_size = 4096
    cfg.forced_shutdown = False
    cfg.defect_injection = [
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE, 0.01],
    ]
    tb = TB(dut, cfg)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    cocotb.start_soon(tb._process_sch_req())
    cocotb.start_soon(tb._process_avail_id_req())
    cocotb.start_soon(tb._process_avail_id_rsp())
    cocotb.start_soon(tb._process_alloc_slot_rsp())
    cocotb.start_soon(tb._process_notify_rsp())
    cocotb.start_soon(tb._process_blk_desc_rsp())

    await tb.cycle_reset()
    await Timer(20, "us")
    workerthds = []

    async def worker(qid):
        typ = TestType.BLK
        if cfg.indirct_support and cfg.indirct_mix:
            indirct_en = random.choice([True, False])
        else:
            indirct_en = cfg.indirct_support
        tb.virtQ.set_queue(qid, cfg, indirct_en=indirct_en, depth=cfg.depth)

        for i in range(cfg.max_seq):
            await tb.virtQ.gen_a_pkt(qid, cfg, seq_num=i)

    for qid in random.sample([i for i in range(256)], cfg.max_q):
        workerthds.append(cocotb.start_soon(worker(qid)))

    await Timer(2, "us")

    while tb.done != (cfg.max_seq * cfg.max_q):
        await Timer(8, "us")

    await Timer(100, "us")


async def err_info_test(dut, idle_inserter, backpressure_inserter):
    random.seed(1)
    cfg = Config()
    cfg.max_q = 8
    # cfg.max_q = 1
    cfg.depth = 256
    # cfg.max_seq = 2
    cfg.max_seq = 10
    cfg.indirct_support = 1
    cfg.indirct_mix = True
    cfg.min_chain_num = 2
    # cfg.max_chain_num = 4
    cfg.max_chain_num = 300
    cfg.max_indirct_ptr = 1
    cfg.max_indirct_desc_size = 32768
    cfg.max_size = 4096
    cfg.forced_shutdown = False
    cfg.defect_injection = [
        [DefectType.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE, 1],
        [DefectType.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE, 0.001],
    ]
    tb = TB(dut, cfg)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    cocotb.start_soon(tb._process_sch_req())
    cocotb.start_soon(tb._process_avail_id_req())
    cocotb.start_soon(tb._process_avail_id_rsp())
    cocotb.start_soon(tb._process_alloc_slot_rsp())
    cocotb.start_soon(tb._process_notify_rsp())
    cocotb.start_soon(tb._process_blk_desc_rsp())

    await tb.cycle_reset()
    await Timer(20, "us")
    workerthds = []

    async def worker(qid):
        typ = TestType.BLK
        if cfg.indirct_support and cfg.indirct_mix:
            indirct_en = random.choice([True, False])
        else:
            indirct_en = cfg.indirct_support
        tb.virtQ.set_queue(qid, cfg, indirct_en=indirct_en, depth=cfg.depth)

        for i in range(cfg.max_seq):
            await tb.virtQ.gen_a_pkt(qid, cfg, seq_num=i)

    for qid in random.sample([i for i in range(256)], cfg.max_q):
        workerthds.append(cocotb.start_soon(worker(qid)))

    await Timer(2, "us")

    while tb.done != (cfg.max_seq * cfg.max_q):
        await Timer(8, "us")
    await Timer(100, "us")


async def force_shutdown_test(dut, idle_inserter, backpressure_inserter):
    random.seed(123)
    cfg = Config()
    cfg.max_q = 8
    # cfg.max_q = 1
    cfg.depth = 256
    # cfg.max_seq = 2
    cfg.max_seq = 10
    cfg.indirct_support = 1
    cfg.indirct_mix = True
    cfg.min_chain_num = 2
    # cfg.max_chain_num = 4
    cfg.max_chain_num = 300
    cfg.max_indirct_ptr = 1
    cfg.max_indirct_desc_size = 32768
    cfg.max_size = 4096
    cfg.forced_shutdown = True
    cfg.defect_injection = [
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE, 1],
        [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE, 1],
        # [DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE, 0.01],
    ]
    tb = TB(dut, cfg)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    cocotb.start_soon(tb._process_sch_req())
    cocotb.start_soon(tb._process_avail_id_req())
    cocotb.start_soon(tb._process_avail_id_rsp())
    cocotb.start_soon(tb._process_alloc_slot_rsp())
    cocotb.start_soon(tb._process_notify_rsp())
    cocotb.start_soon(tb._process_blk_desc_rsp())

    await tb.cycle_reset()
    await Timer(20, "us")
    workerthds = []

    async def worker(qid):
        typ = TestType.BLK
        if cfg.indirct_support and cfg.indirct_mix:
            indirct_en = random.choice([True, False])
        else:
            indirct_en = cfg.indirct_support
        tb.virtQ.set_queue(qid, cfg, indirct_en=indirct_en, depth=cfg.depth)

        for i in range(cfg.max_seq):
            await tb.virtQ.gen_a_pkt(qid, cfg, seq_num=i)

    for qid in random.sample([i for i in range(256)], cfg.max_q):
        workerthds.append(cocotb.start_soon(worker(qid)))

    await Timer(2, "us")

    while tb.done != (cfg.max_seq * cfg.max_q):
        await Timer(8, "us")
    await Timer(100, "us")


ding_robot.ding_robot()

if cocotb.SIM_NAME:
    # for test in [normal_test, err_info_test, force_shutdown_test]:
    for test in [err_info_test]:

        factory = TestFactory(test)
        # factory.add_option("idle_inserter", [None])
        factory.add_option("idle_inserter", [None, cycle_pause])
        # factory.add_option("idle_inserter", [cycle_pause])
        # factory.add_option("backpressure_inserter", [None])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        # factory.add_option("backpressure_inserter", [cycle_pause])
        factory.generate_tests()


root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
