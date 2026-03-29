import sys
import random
from types import SimpleNamespace
from typing import Dict, List, Optional

import logging
from logging import Logger
from logging.handlers import RotatingFileHandler

import cocotb
from cocotb.queue import Queue
from cocotb.log import SimLogFormatter
from cocotb.handle import HierarchyObject
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory


sys.path.append('../../common')
from address_space import Pool
from bus.tlp_adap_dma_bus import DmaReadBus

from test_cfg import *
from test_func import cycle_pause, ResourceAllocator, randbit
from test_define import *
from test_interfaces import *
from ram_tbl import RamTblTransaction


ERR_NO_ERR = 'no_err'
ERR_DESC_RSP = 'desc_rsp_err'
ERR_FORCED_SHUTDOWN = 'forced_shutdown'
ERR_TLP = 'tlp_err'

FS_EARLY_SBD = 'early_sbd'
FS_LATE_CTX_NODATA = 'late_ctx_nodata'
FS_LATE_CTX_CHAINSTOP = 'late_ctx_chainstop'


class TB(object):
    def __init__(self, cfg: Cfg, dut: HierarchyObject, qid_list: List[int]):
        self.dut: HierarchyObject = dut
        self.cfg: Cfg = cfg
        self.qid_list: List[int] = qid_list
        cocotb.start_soon(Clock(dut.clk, CLOCK_FREQ, units='ns').start())
        self._init_mem()
        self._log_init()
        self._init_interfaces()
        cocotb.start_soon(self.__slot_req_process())
        cocotb.start_soon(self.__slot_rsp_process())
        cocotb.start_soon(self.__nettx_desc_rsp_process())
        cocotb.start_soon(self.__qos_query_process())
        cocotb.start_soon(self.__qos_update_process())
        cocotb.start_soon(self.__net2tso_process())

    def _log_init(self) -> None:
        self.log: Logger = logging.getLogger('cocotb.tb')
        self.log.setLevel(LOG_LEVEL)

    def _init_interfaces(self) -> None:
        dut = self.dut
        clk = self.dut.clk
        rst = self.dut.rst
        self.interfaces: Interfaces = Interfaces()
        self.interfaces.sch_req_if = SchReqSource(SchReqBus.from_prefix(dut, 'sch_req'), clk, rst)
        self.interfaces.nettx_alloc_slot_req_if = SlotReqSink(SlotReqBus.from_prefix(dut, 'nettx_alloc_slot_req'), clk, rst)
        self.interfaces.nettx_alloc_slot_rsp_if = SlotRspSource(SlotRspBus.from_prefix(dut, 'nettx_alloc_slot_rsp'), clk, rst)
        self.interfaces.slot_ctrl_ctx_if = SlotCtxTbl(
            SlotCtxReqBus.from_prefix(dut, 'slot_ctrl_ctx_info_rd'),
            SlotCtxRspBus.from_prefix(dut, 'slot_ctrl_ctx_info_rd'),
            None,
            clk,
            rst,
        )
        self.interfaces.slot_ctrl_ctx_if.set_callback(self.__slot_ctx_cb)
        self.interfaces.qos_query_req_if = QosQueryReqSink(QosQueryReqBus.from_prefix(dut, 'qos_query_req'), clk, rst)
        self.interfaces.qos_query_rsp_if = QosQueryRspSource(QosQueryRspBus.from_prefix(dut, 'qos_query_rsp'), clk, rst)
        self.interfaces.qos_update_if = QosUpdateSink(QosUpdateBus.from_prefix(dut, 'qos_update'), clk, rst)
        self.interfaces.nettx_desc_rsp_if = NettxDescSource(NettxDescBus.from_prefix(dut, 'nettx_desc_rsp'), clk, rst)
        self.interfaces.rd_data_ctx_if = RdDataCtxTbl(
            RdDataCtxReqBus.from_prefix(dut, 'rd_data_ctx_info_rd'),
            RdDataCtxRspBus.from_prefix(dut, 'rd_data_ctx_info_rd'),
            None,
            clk,
            rst,
        )
        self.interfaces.rd_data_ctx_if.set_callback(self.__rd_data_ctx_cb)
        self.interfaces.net2tso_if = Net2TsoSink(Net2TsoBus.from_prefix(dut, 'net2tso'), clk, rst)
        self.interfaces.used_info_if = UsedInfoSink(UsedInfoBus.from_prefix(dut, 'used_info'), clk, rst)
        self.interfaces.dma_if = DmaRam(None, DmaReadBus.from_prefix(dut, 'dma'), clk, rst, mem=self.mem)

    def _init_mem(self) -> None:
        self.mem = Pool(None, 0, size=2**64, min_alloc=64)
        self.virtio_head_len: int = 12
        self.sent_num = 0
        self.pass_num = 0
        self.drop_num = 0
        self.pkt_seq = 0

        self.driver_pending_queue: Dict[int, Queue] = {}
        self.slot_req_queue = Queue(maxsize=32)
        self.desc_pending_queue: Dict[int, Queue] = {}
        self.scoreboard_queue: Dict[int, Queue] = {}
        self.ctx_read_queue: Dict[int, Queue] = {}
        self.pending_used_queue: Dict[int, Queue] = {}
        self.qos_update_expect_queue: Dict[int, Queue] = {}

        self.mem_idx: Dict[int, ResourceAllocator] = {}
        self.dev_id_ram: Dict[int, int] = {}
        self.bdf_ram: Dict[int, int] = {}
        self.qos_unit_ram: Dict[int, int] = {}
        self.qos_enable_ram: Dict[int, int] = {}

        self.avail_idx_cnt: Dict[int, int] = {}
        self.virtq_forced_shutdown: Dict[int, int] = {}

        for qid in self.qid_list:
            self.driver_pending_queue[qid] = Queue()
            self.desc_pending_queue[qid] = Queue()
            self.scoreboard_queue[qid] = Queue()
            self.ctx_read_queue[qid] = Queue()
            self.pending_used_queue[qid] = Queue()
            self.qos_update_expect_queue[qid] = Queue()
            self.mem_idx[qid] = ResourceAllocator(0, 2**16 - 1)
            self.avail_idx_cnt[qid] = 0
            self.dev_id_ram[qid] = qid
            self.bdf_ram[qid] = qid
            self.qos_unit_ram[qid] = qid
            self.qos_enable_ram[qid] = 1 if random.random() < self.cfg.random_qos else 0
            self.virtq_forced_shutdown[qid] = 0

    @staticmethod
    def _peek_queue(q: Queue):
        if q.empty():
            return None
        return q._queue[0]

    @staticmethod
    def _queue_pop_idx(q: Queue, idx: int):
        item = q._queue[idx]
        del q._queue[idx]
        return item

    @classmethod
    def _queue_pop_match(cls, q: Queue, predicate):
        for idx, item in enumerate(q._queue):
            if predicate(item):
                return cls._queue_pop_idx(q, idx)
        return None

    @staticmethod
    def _calc_ctx_req_count(desc_chain) -> int:
        req_cnt = 0
        for desc in desc_chain:
            req_cnt += max(1, (int(desc.len) + 4095) // 4096)
        return req_cnt

    def _qid_from_qos_uid(self, uid: int) -> int:
        for qid, qos_uid in self.qos_unit_ram.items():
            if qos_uid == uid:
                return qid
        raise Exception(f'unknown qos uid={uid}')

    def _free_pkt_resources(self, info) -> None:
        for region in getattr(info, 'mem_regions', []):
            self.mem.free_region(region)
        ring_id = getattr(info, 'expected_ring_id', None)
        qid = getattr(info, 'qid', None)
        if ring_id is not None and qid is not None and ring_id >= 0:
            if self.mem_idx[qid].is_resource_used(ring_id):
                self.mem_idx[qid].release_id(ring_id)

    async def _rerun_doorbell(self, qid: int) -> None:
        await self.interfaces.sch_req_if.send(SchReqTrans(qid=qid))

    @staticmethod
    def _mark_no_data_complete(info) -> None:
        info.actual_data_received = False
        info.actual_err = 0

    async def cycle_reset(self) -> None:
        clk = self.dut.clk
        rst = self.dut.rst
        rst.setimmediatevalue(0)
        await RisingEdge(clk)
        await RisingEdge(clk)
        rst.value = 1
        await RisingEdge(clk)
        await Timer(1, 'us')
        await RisingEdge(clk)
        rst.value = 0
        await RisingEdge(clk)
        await RisingEdge(clk)
        await Timer(2, 'us')

    async def _gen_pkt_process(self):
        while self.sent_num < self.cfg.seq_num * self.cfg.q_num:
            qid = random.choice(self.qid_list)
            pkt_seq = self.pkt_seq
            self.pkt_seq += 1

            err_type = ERR_TLP if random.random() <= self.cfg.tlp_err else ERR_NO_ERR

            virtio_hdr = bytes([0] * self.virtio_head_len)
            pkt_len = random.randint(self.cfg.eth_pkt_len_min, self.cfg.eth_pkt_len_max)
            eth_payload = bytes([random.randint(0, 255) for _ in range(pkt_len)])
            full_data = virtio_hdr + eth_payload
            total_len = len(full_data)

            desc_cnt = random.randint(self.cfg.min_desc_cnt, self.cfg.max_desc_cnt)
            desc_len_list = []
            remaining_len = total_len
            for i in range(desc_cnt - 1):
                max_len = remaining_len - (desc_cnt - 1 - i)
                curr_len = random.randint(1, max_len) if max_len >= 1 else 1
                desc_len_list.append(curr_len)
                remaining_len -= curr_len
            desc_len_list.append(remaining_len)

            mem_regions = []
            desc_chain = []
            current_offset = 0
            for i, d_len in enumerate(desc_len_list):
                mem = self.mem.alloc_region(d_len, bdf=self.bdf_ram[qid], dev_id=self.dev_id_ram[qid])
                if err_type == ERR_TLP:
                    await mem.write(0, full_data[current_offset: current_offset + d_len], defect_injection=1)
                else:
                    await mem.write(0, full_data[current_offset: current_offset + d_len])
                current_offset += d_len

                desc_info = SimpleNamespace()
                desc_info.addr = mem.get_absolute_address(0)
                desc_info.len = d_len
                desc_info.next = 0
                desc_info.flags_next = 1 if i < desc_cnt - 1 else 0
                desc_info.flags_write = 0
                desc_info.flags_indirect = 0
                mem_regions.append(mem)
                desc_chain.append(desc_info)

            pkt_info = SimpleNamespace()
            pkt_info.pkt_seq = pkt_seq
            pkt_info.qid = qid
            pkt_info.eth_payload = eth_payload
            pkt_info.mem_regions = mem_regions
            pkt_info.desc_chain = desc_chain
            pkt_info.total_len = total_len
            pkt_info.desc_cnt = desc_cnt
            pkt_info.err_type = err_type
            pkt_info.injected_desc_err_code = 0
            pkt_info.force_shutdown_mode = None
            pkt_info.force_shutdown_req_idx = None
            pkt_info.early_drop = False
            pkt_info.expected_ring_id = None
            pkt_info.expected_avail_idx = None
            pkt_info.actual_data_received = False
            pkt_info.actual_err = 0
            pkt_info.ctx_req_total = self._calc_ctx_req_count(desc_chain)
            pkt_info.ctx_req_seen = 0
            pkt_info.expect_net2tso = True
            pkt_info.expect_net2tso_err = 1 if err_type == ERR_TLP else 0
            pkt_info.expected_used_len = total_len
            pkt_info.expected_used_force_down = 0
            pkt_info.expected_used_fatal = 1 if err_type == ERR_TLP else 0
            pkt_info.expected_used_err_code = int(VirtioErrCode.VIRTIO_ERR_CODE_NETTX_PCIE_ERR) if err_type == ERR_TLP else int(VirtioErrCode.VIRTIO_ERR_CODE_NONE)
            pkt_info.expect_qos_update = False

            self.driver_pending_queue[qid].put_nowait(pkt_info)
            self.sent_num += 1

            await self.interfaces.sch_req_if.send(SchReqTrans(qid=qid))
            await Timer(random.randint(100, 500), 'ns')

    async def __slot_req_process(self):
        while True:
            req = await self.interfaces.nettx_alloc_slot_req_if.recv()
            await self.slot_req_queue.put(req)

    async def __slot_rsp_process(self):
        while True:
            req_trans = await self.slot_req_queue.get()
            vq = VirtioVq.unpack(req_trans.data)
            qid = vq.qid

            if vq.typ != TestType.NETTX:
                raise Exception(f'qid {qid} __slot_rsp_process vq_typ is not nettx is {vq.typ}')
            if int(req_trans.dev_id) != self.dev_id_ram[qid]:
                raise Exception(
                    f'qid {qid} __slot_rsp_process dev_id err act {int(req_trans.dev_id)} exp {self.dev_id_ram[qid]}'
                )

            has_pkt = not self.driver_pending_queue[qid].empty()

            rsp_data = Nettx_Alloc_Slot_Rsp_Data()
            rsp_data.vq = vq.pack()
            rsp_data.pkt_id = 0
            rsp_data.ok = 0
            rsp_data.local_ring_empty = 0
            rsp_data.avail_ring_empty = 0
            rsp_data.q_stat_doing = 1
            rsp_data.q_stat_stopping = 0
            rsp_data.desc_engine_limit = 0
            rsp_data.err_info = 0

            alloc_success = False
            false_done_with_data = False

            if has_pkt and random.random() <= self.cfg.alloc_slot_err:
                fail_type = random.randint(0, 4)
                if fail_type == 0:
                    rsp_data.desc_engine_limit = 1
                elif fail_type == 1:
                    rsp_data.local_ring_empty = 1
                    rsp_data.avail_ring_empty = 0
                elif fail_type == 2:
                    rsp_data.q_stat_stopping = 1
                    rsp_data.q_stat_doing = 0
                elif fail_type == 3:
                    if random.choice([True, False]):
                        rsp_data.local_ring_empty = 1
                        rsp_data.avail_ring_empty = 1
                    else:
                        rsp_data.q_stat_doing = 0
                        rsp_data.q_stat_stopping = 0
                    false_done_with_data = True
                elif fail_type == 4:
                    rsp_data.err_info = 0x80 | random.choice(idx_avail_errcode_list)
            elif has_pkt:
                rsp_data.ok = 1
                alloc_success = True
            else:
                if random.choice([True, False]):
                    rsp_data.local_ring_empty = 1
                    rsp_data.avail_ring_empty = 1
                else:
                    rsp_data.q_stat_doing = 0
                    rsp_data.q_stat_stopping = 0

            rsp_trans = SlotRspTrans()
            rsp_trans.data = rsp_data.pack()
            await self.interfaces.nettx_alloc_slot_rsp_if.send(rsp_trans)

            is_done = (
                (rsp_data.local_ring_empty == 1 and rsp_data.avail_ring_empty == 1 and rsp_data.q_stat_doing == 1)
                or (rsp_data.q_stat_doing == 0 and rsp_data.q_stat_stopping == 0)
            )

            if alloc_success:
                pkt_info = self.driver_pending_queue[qid].get_nowait()
                self.desc_pending_queue[qid].put_nowait(pkt_info)
            elif rsp_data.err_info != 0 and has_pkt:
                dropped_info = self.driver_pending_queue[qid].get_nowait()
                self._free_pkt_resources(dropped_info)
                self.drop_num += 1
                self.log.info(
                    f'QID {qid} slot alloc fatal error {hex(int(rsp_data.err_info))}. drop pkt_seq={dropped_info.pkt_seq}'
                )
            elif has_pkt and is_done:
                self.log.info(f'QID {qid} injected false DONE while data is pending. rerun doorbell.')
                await self._rerun_doorbell(qid)
            elif false_done_with_data:
                raise Exception(f'QID {qid} false_done_with_data should always set is_done=1')

    async def __nettx_desc_rsp_process(self):
        while True:
            active_qids = [q for q in self.qid_list if not self.desc_pending_queue[q].empty()]
            if not active_qids:
                await Timer(10, 'ns')
                continue

            qid = random.choice(active_qids)
            info = self.desc_pending_queue[qid].get_nowait()

            ring_id = self.mem_idx[qid].alloc_id()
            if ring_id < 0:
                raise Exception(f'QID {qid} failed to allocate ring_id for pkt_seq={info.pkt_seq}')

            avail_idx = self.avail_idx_cnt[qid]
            self.avail_idx_cnt[qid] = (self.avail_idx_cnt[qid] + 1) % 65536

            info.expected_ring_id = ring_id
            info.expected_avail_idx = avail_idx

            if info.err_type == ERR_NO_ERR:
                info.err_type = random.choices(
                    population=list(err_type_list.keys()),
                    weights=list(err_type_list.values()),
                    k=1,
                )[0]

            sbd = VirioRspSbd()
            sbd.vq = VirtioVq(typ=TestType.NETTX, qid=qid).pack()
            sbd.dev_id = self.dev_id_ram[qid]
            sbd.pkt_id = 0
            sbd.total_buf_length = info.total_len
            sbd.valid_desc_cnt = info.desc_cnt
            sbd.ring_id = ring_id
            sbd.avail_idx = avail_idx
            sbd.forced_shutdown = self.virtq_forced_shutdown[qid]
            sbd.err_info = 0

            info.early_drop = False
            push_to_ctx_queue = True

            info.expect_net2tso = info.err_type != ERR_DESC_RSP
            info.expect_net2tso_err = 1 if info.err_type == ERR_TLP else 0
            info.expected_used_len = info.total_len
            info.expected_used_force_down = 0
            info.expected_used_fatal = 1 if info.err_type == ERR_TLP else 0
            info.expected_used_err_code = int(VirtioErrCode.VIRTIO_ERR_CODE_NETTX_PCIE_ERR) if info.err_type == ERR_TLP else int(VirtioErrCode.VIRTIO_ERR_CODE_NONE)

            if info.err_type == ERR_DESC_RSP:
                sbd.err_info = 0x80 | randbit(7, False)
                info.injected_desc_err_code = int(sbd.err_info) & 0x7F
                info.early_drop = True
                push_to_ctx_queue = False
                info.expect_net2tso = False
                info.expect_net2tso_err = 0
                info.expected_used_len = info.total_len
                info.expected_used_force_down = 0
                info.expected_used_fatal = 1
                info.expected_used_err_code = info.injected_desc_err_code
                self.log.info(
                    f'QID {qid} inject desc_rsp_err code={hex(int(sbd.err_info))} ring_id={ring_id} pkt_seq={info.pkt_seq}'
                )
            elif info.err_type == ERR_FORCED_SHUTDOWN:
                force_modes = [FS_EARLY_SBD, FS_LATE_CTX_NODATA]
                if info.ctx_req_total > 1:
                    force_modes.append(FS_LATE_CTX_CHAINSTOP)
                info.force_shutdown_mode = random.choice(force_modes)
                info.expected_used_force_down = 1
                info.expected_used_fatal = 0
                info.expected_used_err_code = int(VirtioErrCode.VIRTIO_ERR_CODE_NONE)
                if info.force_shutdown_mode == FS_EARLY_SBD:
                    sbd.forced_shutdown = 1
                    info.early_drop = True
                    push_to_ctx_queue = False
                    info.expect_net2tso = False
                    info.expect_net2tso_err = 0
                    info.expected_used_len = 0
                    self.log.info(
                        f'QID {qid} inject early forced_shutdown(sbd) ring_id={ring_id} pkt_seq={info.pkt_seq}'
                    )
                elif info.force_shutdown_mode == FS_LATE_CTX_NODATA:
                    info.force_shutdown_req_idx = 0
                    push_to_ctx_queue = True
                    info.expect_net2tso = False
                    info.expect_net2tso_err = 0
                    info.expected_used_len = 0
                    self.log.info(
                        f'QID {qid} inject late forced_shutdown(ctx no-data) ring_id={ring_id} pkt_seq={info.pkt_seq}'
                    )
                else:
                    info.force_shutdown_req_idx = random.randint(1, info.ctx_req_total - 1)
                    push_to_ctx_queue = True
                    info.expect_net2tso = True
                    info.expect_net2tso_err = 1
                    info.expected_used_len = info.total_len
                    self.log.info(
                        f'QID {qid} inject late forced_shutdown(ctx chain-stop) ring_id={ring_id} '
                        f'pkt_seq={info.pkt_seq} force_req_idx={info.force_shutdown_req_idx}/{info.ctx_req_total - 1}'
                    )

            if push_to_ctx_queue and info.ctx_req_total > 0:
                self.ctx_read_queue[qid].put_nowait(info)

            info.expect_qos_update = (
                self.qos_enable_ram[qid] == 1
                and push_to_ctx_queue
                and info.ctx_req_total > 0
                and (info.err_type in (ERR_NO_ERR, ERR_TLP) or info.force_shutdown_req_idx == info.ctx_req_total - 1)
            )
            if info.expect_qos_update:
                self.qos_update_expect_queue[qid].put_nowait(info)

            self.scoreboard_queue[qid].put_nowait(info)

            for i, desc_data in enumerate(info.desc_chain):
                rtl_desc = VirioRspData()
                rtl_desc.addr = desc_data.addr
                rtl_desc.len = desc_data.len
                rtl_desc.next = desc_data.next
                rtl_desc.flag_next = desc_data.flags_next
                rtl_desc.flag_write = desc_data.flags_write
                rtl_desc.flag_indirect = desc_data.flags_indirect
                rtl_desc.flag_rsv = 0

                trans = NettxDescTrans()
                trans.sop = 1 if i == 0 else 0
                trans.eop = 1 if i == info.desc_cnt - 1 else 0
                trans.sbd = sbd.pack()
                trans.data = rtl_desc.pack()
                await self.interfaces.nettx_desc_rsp_if.send(trans)

    def __slot_ctx_cb(self, req_tran) -> RamTblTransaction:
        vq = VirtioVq.unpack(req_tran.req_qid)
        qid = vq.qid

        if vq.typ != TestType.NETTX:
            raise Exception(f'qid {qid} __slot_ctx_cb vq_typ is not nettx is {vq.typ}')

        rsp = SlotCtxRspTrans()
        rsp.rsp_dev_id = self.dev_id_ram[qid]
        rsp.rsp_qos_unit = self.qos_unit_ram[qid]
        rsp.rsp_qos_enable = self.qos_enable_ram[qid]
        return rsp

    def __rd_data_ctx_cb(self, req_tran) -> RamTblTransaction:
        vq = VirtioVq.unpack(req_tran.req_qid)
        qid = vq.qid

        if vq.typ != TestType.NETTX:
            raise Exception(f'qid {qid} __rd_data_ctx_cb vq_typ is not nettx is {vq.typ}')

        rsp = RdDataCtxRspTrans()
        rsp.rsp_bdf = self.bdf_ram[qid]
        rsp.rsp_forced_shutdown = self.virtq_forced_shutdown[qid]

        info = self._peek_queue(self.ctx_read_queue[qid])
        if info is not None:
            if info.err_type == ERR_FORCED_SHUTDOWN and info.force_shutdown_mode in (FS_LATE_CTX_NODATA, FS_LATE_CTX_CHAINSTOP):
                if info.ctx_req_seen == info.force_shutdown_req_idx:
                    rsp.rsp_forced_shutdown = 1
                    _ = self.ctx_read_queue[qid].get_nowait()
                    self.log.info(
                        f'QID {qid} context read inject forced_shutdown ring_id={info.expected_ring_id} '
                        f'pkt_seq={info.pkt_seq} req_idx={info.ctx_req_seen}'
                    )
                else:
                    info.ctx_req_seen += 1
                    if info.ctx_req_seen >= info.ctx_req_total:
                        raise Exception(
                            f'QID {qid} forced_shutdown packet exhausted ctx reads without injection. '
                            f'pkt_seq={info.pkt_seq} mode={info.force_shutdown_mode}'
                        )
            else:
                info.ctx_req_seen += 1
                if info.ctx_req_seen >= info.ctx_req_total:
                    _ = self.ctx_read_queue[qid].get_nowait()

        rsp.rsp_qos_enable = self.qos_enable_ram[qid]
        rsp.rsp_qos_unit = self.qos_unit_ram[qid]
        rsp.rsp_tso_en = 0
        rsp.rsp_csum_en = 0
        rsp.rsp_gen = 0
        return rsp

    async def __qos_query_process(self):
        while True:
            req = await self.interfaces.qos_query_req_if.recv()
            uid = int(req.uid)
            if uid not in self.qos_unit_ram.values():
                self.log.error(f'QoS Query Req UID {uid} invalid! valid_uids={list(self.qos_unit_ram.values())}')
                raise Exception(f'QoS Query Req UID {uid} invalid')

            rsp = QosQueryRspTrans()
            rsp.data = 1 if random.random() < self.cfg.random_qos else 0
            await self.interfaces.qos_query_rsp_if.send(rsp)

    async def __qos_update_process(self):
        while True:
            req = await self.interfaces.qos_update_if.recv()
            uid = int(req.uid)
            qid = self._qid_from_qos_uid(uid)

            if self.qos_update_expect_queue[qid].empty():
                raise Exception(f'unexpected qos_update for qid={qid}, uid={uid}')

            info = self.qos_update_expect_queue[qid].get_nowait()
            exp_len = info.total_len - self.virtio_head_len if info.total_len > self.virtio_head_len else info.total_len
            exp_pkt_num = 1

            if int(req.len) != exp_len:
                raise Exception(
                    f'QID {qid} qos_update len mismatch. exp={exp_len} act={int(req.len)} pkt_seq={info.pkt_seq}'
                )
            if int(req.pkt_num) != exp_pkt_num:
                raise Exception(
                    f'QID {qid} qos_update pkt_num mismatch. exp={exp_pkt_num} act={int(req.pkt_num)} pkt_seq={info.pkt_seq}'
                )

    async def __net2tso_process(self):
        while True:
            actual_data = bytearray()
            actual_qid = -1
            actual_err = 0
            actual_len = None
            actual_gen = None
            actual_tso_en = None
            actual_csum_en = None

            while True:
                trans = await self.interfaces.net2tso_if.recv()

                sop = int(trans.sop)
                eop = int(trans.eop)
                sty = int(trans.sty)
                mty = int(trans.mty)
                data_int = int(trans.data)
                qid = int(trans.qid)
                err = int(trans.err)
                beat_len = int(trans.len)
                beat_gen = int(trans.gen)
                beat_tso_en = int(trans.tso_en)
                beat_csum_en = int(trans.csum_en)

                if sop:
                    actual_qid = qid
                    actual_data = bytearray()
                    actual_err = 0
                    actual_len = beat_len
                    actual_gen = beat_gen
                    actual_tso_en = beat_tso_en
                    actual_csum_en = beat_csum_en
                else:
                    if qid != actual_qid:
                        raise Exception(f'net2tso qid changed inside packet. exp={actual_qid} act={qid}')
                    if beat_len != actual_len:
                        raise Exception(f'net2tso len changed inside packet. exp={actual_len} act={beat_len}')
                    if beat_gen != actual_gen:
                        raise Exception(f'net2tso gen changed inside packet. exp={actual_gen} act={beat_gen}')
                    if beat_tso_en != actual_tso_en:
                        raise Exception(f'net2tso tso_en changed inside packet. exp={actual_tso_en} act={beat_tso_en}')
                    if beat_csum_en != actual_csum_en:
                        raise Exception(f'net2tso csum_en changed inside packet. exp={actual_csum_en} act={beat_csum_en}')

                if err:
                    actual_err = 1

                data_bytes = data_int.to_bytes(BUS_BYTE_WIDTH, 'little')
                start_idx = sty if sop else 0
                end_idx = BUS_BYTE_WIDTH - mty if eop else BUS_BYTE_WIDTH
                if 0 <= start_idx < end_idx <= BUS_BYTE_WIDTH:
                    actual_data.extend(data_bytes[start_idx:end_idx])

                if eop:
                    break

            if actual_qid == -1:
                raise Exception('Protocol Error: missing SOP on net2tso interface')
            if actual_qid not in self.scoreboard_queue:
                raise Exception(f'Received QID {actual_qid} not in scoreboard queues')

            while True:
                if self.scoreboard_queue[actual_qid].empty():
                    raise Exception(f'Scoreboard empty for QID {actual_qid} but received net2tso data')

                head = self._peek_queue(self.scoreboard_queue[actual_qid])
                if not head.expect_net2tso:
                    dropped_info = self.scoreboard_queue[actual_qid].get_nowait()
                    self._mark_no_data_complete(dropped_info)
                    self.pending_used_queue[actual_qid].put_nowait(dropped_info)
                    self.log.info(
                        f'QID {actual_qid} skipped no-data packet ring_id={dropped_info.expected_ring_id} '
                        f'type={dropped_info.err_type} mode={dropped_info.force_shutdown_mode}'
                    )
                    continue
                info = self.scoreboard_queue[actual_qid].get_nowait()
                break

            virtio_hdr = bytes([0] * self.virtio_head_len)
            expected_data = virtio_hdr + info.eth_payload

            if actual_len != info.total_len:
                raise Exception(
                    f'QID {actual_qid} net2tso len mismatch. exp={info.total_len} act={actual_len} pkt_seq={info.pkt_seq}'
                )
            if actual_gen != 0:
                raise Exception(f'QID {actual_qid} net2tso gen mismatch. exp=0 act={actual_gen} pkt_seq={info.pkt_seq}')
            if actual_tso_en != 0:
                raise Exception(f'QID {actual_qid} net2tso tso_en mismatch. exp=0 act={actual_tso_en} pkt_seq={info.pkt_seq}')
            if actual_csum_en != 0:
                raise Exception(f'QID {actual_qid} net2tso csum_en mismatch. exp=0 act={actual_csum_en} pkt_seq={info.pkt_seq}')
            if actual_err != info.expect_net2tso_err:
                raise Exception(
                    f'QID {actual_qid} net2tso err mismatch. exp={info.expect_net2tso_err} act={actual_err} '
                    f'pkt_seq={info.pkt_seq} err_type={info.err_type} mode={info.force_shutdown_mode}'
                )

            if info.err_type == ERR_NO_ERR:
                if actual_data != expected_data:
                    raise Exception(
                        f'QID {actual_qid} data mismatch. exp_len={len(expected_data)} act_len={len(actual_data)} '
                        f'ring_id={info.expected_ring_id} pkt_seq={info.pkt_seq}'
                    )

            info.actual_data_received = True
            info.actual_err = actual_err
            self.pending_used_queue[actual_qid].put_nowait(info)
            self.log.info(
                f'QID {actual_qid} net2tso verified ring_id={info.expected_ring_id} pkt_seq={info.pkt_seq} '
                f'err={actual_err} mode={info.force_shutdown_mode}'
            )

    async def _used_info_process(self):
        total_expected = self.cfg.seq_num * self.cfg.q_num
        while self.pass_num + self.drop_num < total_expected:
            trans = await self.interfaces.used_info_if.recv()

            used_data = UsedInfoData.unpack(trans.data)
            vq = VirtioVq.unpack(used_data.vq)
            qid = vq.qid
            used_elem_id = int(used_data.id)
            used_elem_len = int(used_data.len)
            used_idx = int(used_data.used_idx)
            used_force_down = int(used_data.force_down)
            used_fatal = int(used_data.fatal)
            used_err_code = int(used_data.err_info)

            if vq.typ != TestType.NETTX:
                raise Exception(f'used_info vq type mismatch. exp={TestType.NETTX} act={vq.typ}')

            info = None
            wait_cycles = 0
            while info is None:
                info = self._queue_pop_match(
                    self.pending_used_queue[qid],
                    lambda item: item.expected_ring_id == used_elem_id,
                )
                if info is not None:
                    break

                info = self._queue_pop_match(
                    self.scoreboard_queue[qid],
                    lambda item: item.expected_ring_id == used_elem_id and not item.expect_net2tso,
                )
                if info is not None:
                    self._mark_no_data_complete(info)
                    break

                wait_cycles += 1
                if wait_cycles > 100000:
                    raise Exception(f'QID {qid} timeout waiting used_info match for ring_id={used_elem_id}')
                await Timer(1, 'ns')

            if used_idx != info.expected_avail_idx:
                raise Exception(
                    f'QID {qid} used_idx mismatch. exp={info.expected_avail_idx} act={used_idx} pkt_seq={info.pkt_seq}'
                )
            if used_elem_id != info.expected_ring_id:
                raise Exception(
                    f'QID {qid} ring_id mismatch. exp={info.expected_ring_id} act={used_elem_id} pkt_seq={info.pkt_seq}'
                )
            if used_elem_len != info.expected_used_len:
                raise Exception(
                    f'QID {qid} used len mismatch. exp={info.expected_used_len} act={used_elem_len} '
                    f'pkt_seq={info.pkt_seq} err_type={info.err_type} mode={info.force_shutdown_mode}'
                )
            if used_force_down != info.expected_used_force_down:
                raise Exception(
                    f'QID {qid} force_down mismatch. exp={info.expected_used_force_down} act={used_force_down} '
                    f'pkt_seq={info.pkt_seq} err_type={info.err_type} mode={info.force_shutdown_mode}'
                )
            if used_fatal != info.expected_used_fatal:
                raise Exception(
                    f'QID {qid} fatal mismatch. exp={info.expected_used_fatal} act={used_fatal} '
                    f'pkt_seq={info.pkt_seq} err_type={info.err_type} mode={info.force_shutdown_mode}'
                )
            if used_err_code != info.expected_used_err_code:
                raise Exception(
                    f'QID {qid} err_code mismatch. exp={hex(info.expected_used_err_code)} act={hex(used_err_code)} '
                    f'pkt_seq={info.pkt_seq} err_type={info.err_type} mode={info.force_shutdown_mode}'
                )

            if info.err_type == ERR_NO_ERR and info.actual_err == 0:
                self.pass_num += 1
            else:
                self.drop_num += 1

            self._free_pkt_resources(info)
            self.log.info(
                f'QID {qid} used_info verified ring_id={info.expected_ring_id} pkt_seq={info.pkt_seq} '
                f'err_type={info.err_type} mode={info.force_shutdown_mode}'
            )

    def set_idle_generator(self, generator=None):
        if generator:
            self.interfaces.sch_req_if.set_idle_generator(generator)
            self.interfaces.nettx_alloc_slot_rsp_if.set_idle_generator(generator)
            self.interfaces.qos_query_rsp_if.set_idle_generator(generator)
            self.interfaces.nettx_desc_rsp_if.set_idle_generator(generator)
            self.interfaces.dma_if.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.interfaces.nettx_alloc_slot_req_if.set_backpressure_generator(generator)
            self.interfaces.qos_query_req_if.set_backpressure_generator(generator)
            self.interfaces.qos_update_if.set_backpressure_generator(generator)
            self.interfaces.used_info_if.set_backpressure_generator(generator)
            self.interfaces.net2tso_if.set_backpressure_generator(generator)


async def run_test(dut, cfg: Optional[Cfg] = None, idle_inserter=None, backpressure_inserter=None):
    seed = 1768551146
    random.seed(seed)

    cfg = cfg if cfg is not None else smoke_cfg
    qid_list = random.sample(range(0, 256), cfg.q_num)
    tb = TB(cfg, dut, qid_list)
    tb.log.error(f'Test QIDs: {qid_list}')
    tb.log.info(f'seed: {seed}')

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()

    await Timer(100, 'us')
    cocotb.start_soon(tb._gen_pkt_process())
    await cocotb.start_soon(tb._used_info_process()).join()
    await Timer(10, 'us')

    all_clean = True
    for qid in tb.qid_list:
        if not tb.driver_pending_queue[qid].empty():
            tb.log.error(f'[Fail] QID {qid} driver_pending_queue not empty')
            all_clean = False
        if not tb.desc_pending_queue[qid].empty():
            tb.log.error(f'[Fail] QID {qid} desc_pending_queue not empty')
            all_clean = False
        if not tb.scoreboard_queue[qid].empty():
            tb.log.error(f'[Fail] QID {qid} scoreboard_queue not empty')
            all_clean = False
        if not tb.pending_used_queue[qid].empty():
            tb.log.error(f'[Fail] QID {qid} pending_used_queue not empty')
            all_clean = False
        if not tb.ctx_read_queue[qid].empty():
            tb.log.error(f'[Fail] QID {qid} ctx_read_queue not empty')
            all_clean = False
        if not tb.qos_update_expect_queue[qid].empty():
            tb.log.error(f'[Fail] QID {qid} qos_update_expect_queue not empty')
            all_clean = False
        if tb.mem_idx[qid].get_used_count() != 0:
            tb.log.error(f'[Fail] QID {qid} ring_id allocator not empty, used={tb.mem_idx[qid].get_used_count()}')
            all_clean = False

    if tb.sent_num != tb.pass_num + tb.drop_num:
        raise Exception(f'Packet Count Mismatch! Sent {tb.sent_num} != Pass {tb.pass_num} + Drop {tb.drop_num}')

    if not all_clean:
        raise Exception('Test Failed: queues are not empty after test completion!')

    tb.log.info('All queues are clean. Consistency check passed.')
    await Timer(1, 'us')


if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        # factory.add_option('idle_inserter', [None, cycle_pause])
        # factory.add_option('backpressure_inserter', [None, cycle_pause])
        factory.generate_tests()


root_logger = logging.getLogger()
file_handler = RotatingFileHandler('rotating.log', mode='w')
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
