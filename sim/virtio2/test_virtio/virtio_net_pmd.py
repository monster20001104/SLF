import cocotb
from cocotb.queue import Queue, QueueEmpty
from cocotb.triggers import Timer
from cocotb.utils import get_sim_time

import logging
import random
from dataclasses import dataclass
from address_space import Pool

from test_virtio_net_tb import TB

from virtio_net_defines import Cfg, VirtioVq, TestType, VirtioStatus, Mbufs, VirtioErrCode, VirtioCtrlRegOffset, VirtioBlkType, VirtioBlkOuthdr
from virtio_net_virtq import VirtQConfig, VirtQ
from virtio_net_func import ResourceAllocator, rand_norm_int
from virtio_net_ctrl import VirtioCtrl_StartCfg


class Virt:
    def __init__(self, tb: TB):
        self.tb: TB = tb
        self.cfg: Cfg = self.tb.cfg
        self.log: logging.Logger = tb.log
        self.mem: Pool = tb.mem
        self.bdfallocator = ResourceAllocator(0, 65535, self.log)
        self.virtq: dict[int, VirtQ] = {}
        self.doorbell_queues: dict[int, Queue] = {}
        self.soc_notify_queues: Queue = Queue()
        cocotb.start_soon(self.doorbell_service())
        cocotb.start_soon(self.soc_notify_service())
        cocotb.start_soon(self.err_check_service())

    def create_queue(self, vq) -> None:
        self.doorbell_queues[vq] = Queue(maxsize=1)
        # self.soc_notify_queues[vq] = Queue()
        self.log.info(f"create_queue {VirtioVq.vq2str(vq)}")

        qid, typ = VirtioVq.vq2qid(vq)

        if typ == TestType.NETRX:
            max_len = self.cfg.max_len_rx
        elif typ == TestType.NETTX:
            max_len = self.cfg.max_len
        else:
            max_len = self.cfg.max_len

        bdf = self.bdfallocator.alloc(vq)
        qos_unit = qid
        virtq_cfg = VirtQConfig(
            cfg=self.cfg,
            log=self.log,
            mem=self.mem,
            tb=self.tb,
            vq=vq,
            qszWidth=random.choice(self.cfg.qsz_width_list),
            mss=random.randint(14, 16 * 1024),
            max_len=max_len,
            msix_en=random.randint(0, 1) if self.cfg.msix_en else 0,
            indirct_support=random.randint(0, 1) if self.cfg.indirct_support else 0,
            tso_en=random.randint(0, 1) if self.cfg.global_tx_tso_en else 0,
            csum_en=random.randint(0, 1) if self.cfg.global_tx_csum_en else 0,
            # qos_en=1,
            qos_en=random.randint(0, 1) if self.cfg.qos_en else 0,
            qos_unit=qid,
            bdf=bdf,
            dev_id=random.randint(0, 1024),
        )
        self.virtq[vq] = VirtQ(virtq_cfg)

    async def start(self, vq, avail_idx=0) -> None:
        self.log.info(f"vq{VirtioVq.vq2str(vq)} start start")
        await self.virtq[vq].start(avail_idx=avail_idx)
        self.log.info(f"vq{VirtioVq.vq2str(vq)} start done")

    async def stop(self, vq, forced_shutdown=0) -> None:
        vq_str = VirtioVq.vq2str(vq)
        virtq = self.virtq[vq]
        self.log.debug(f"vq: {vq_str} stop start {forced_shutdown}")
        await self.tb.virtio_ctrl.stop(vq=vq, forced_shutdown=forced_shutdown)
        await self.worker_clean(vq)
        virtq.status = VirtioStatus.IDLE
        await virtq.producer_event.wait()
        await virtq.stop(forced_shutdown=forced_shutdown)

    async def burst_tx_consumer(self, vq) -> None:
        virtq = self.virtq[vq]
        if virtq.status not in [VirtioStatus.DOING, VirtioStatus.STOPPING]:
            return None
        # while not virtq.consumer_event.is_set():
        #     await Timer(20, "ns")
        # if not virtq.consumer_event.is_set():
        #     return None
        # virtq.consumer_event.clear()
        # self.log.debug(f"burst_tx_consumer start")
        qid, typ = VirtioVq.vq2qid(vq)
        used_idx_pi = await virtq.read_used_idx()
        used_desc_num = used_idx_pi - virtq.used_idx_ci if used_idx_pi >= virtq.used_idx_ci else used_idx_pi + (2**16) - virtq.used_idx_ci
        if used_desc_num != 0:
            # self.log.debug(f"{VirtioVq.vq2str(vq)} recycle_desc used_desc_num {used_desc_num} used_idx_pi {used_idx_pi} virtq.used_idx_ci {virtq.used_idx_ci} ")
            await self.tb.virtio_net.tx.ref_pkt_num.put((virtq.qid, used_desc_num))
        for i in range(used_desc_num):
            used_elem = await virtq.read_used_element(virtq.used_idx_ci)
            total_len = used_elem.len
            virtq.elem.append(total_len)
            # self.log.error(f"consumer total_len {total_len}")
            id = used_elem.id
            # self.log.debug(f"vq: {VirtioVq.vq2str(vq)} mem_reg_pool stop id: {id} virtq.used_idx_ci: {virtq.used_idx_ci}")
            regs = virtq.mem_reg_pool[id]
            if virtq.used_idx_ci in virtq.indirct_reg_pool.keys():
                self.mem.free_region(virtq.indirct_reg_pool[virtq.used_idx_ci])
                del virtq.indirct_reg_pool[virtq.used_idx_ci]
            for reg in regs:
                self.mem.free_region(reg)
            del virtq.mem_reg_pool[id]
            virtq.used_idx_ci = (virtq.used_idx_ci + 1) & 0xFFFF
            ids = virtq.id_pool[id]
            for idx in ids:
                virtq.id_allocator.release_id(idx)
            del virtq.id_pool[id]
        # virtq.consumer_event.set()

    async def burst_tx_producer(self, vq, mbufs: list[Mbufs]) -> Mbufs:
        virtq = self.virtq[vq]
        while virtq.status not in [VirtioStatus.DOING, VirtioStatus.STARTING]:
            # self.log.debug(f"burst_tx_producer await {virtq.status}")
            if virtq.finished:
                return mbufs
            await Timer(1, "us")
        virtq.producer_event.clear()
        qid, typ = VirtioVq.vq2qid(vq)
        avail_num = virtq.avail_idx_sw - virtq.used_idx_ci if virtq.avail_idx_sw >= virtq.used_idx_ci else virtq.avail_idx_sw + (2**16) - virtq.used_idx_ci
        need_send_pkt = min(virtq.qsz - avail_num, len(mbufs))
        # self.log.error(f"need_send_pkt {need_send_pkt}")
        pkt_cnt = 0
        for i in range(need_send_pkt):
            defect = virtq.err_info_choose()
            mbuf = mbufs[i]
            seg_num = len(mbuf.regs)
            indirct_ptr = random.randint(0, seg_num - 1) if virtq.indirct_support or (defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT) else seg_num
            indirct_desc_sz = random.randint((seg_num - indirct_ptr), self.cfg.max_indirct_desc_size)

            if virtq.indirct_support and self.cfg.indirct_relaxed_ordering:
                indirct_id_list = [0] + random.sample(range(1, indirct_desc_sz), seg_num - indirct_ptr - 1)
            else:
                indirct_id_list = range(seg_num - indirct_ptr)

            indirct_mem_reg = None
            first_id = None
            id_list = []
            dirct_desc_cnt = min(seg_num, indirct_ptr + 1)
            if dirct_desc_cnt > virtq.id_allocator.get_available_count():
                break
            else:
                pkt_cnt = pkt_cnt + 1

            if defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX or defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR:
                virtq.idx_defect = defect
            if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT and virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE and not virtq.indirct_support:
                virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT
            defect_idx = random.randint(0, seg_num)
            # a = indirct_ptr + 1 if indirct_ptr < seg_num else indirct_ptr
            # defect_idx = random.randint(indirct_ptr + 1 if indirct_ptr < seg_num else indirct_ptr, seg_num)
            if defect not in [None, VirtioErrCode.VIRTIO_ERR_CODE_NONE]:
                self.log.info(
                    f"vq: {VirtioVq.vq2str(vq)} seg_num: {seg_num} indirct_ptr: {indirct_ptr}  defect:{str(VirtioErrCode(defect))} idx: {virtq.avail_idx_sw} defect_idx {defect_idx}"
                )
            for j in range(dirct_desc_cnt):
                id = virtq.id_allocator.alloc_id()
                id_list.append(id)
                if j == 0:
                    first_id = id

            for j in range(seg_num + (indirct_ptr < seg_num)):
                if j == indirct_ptr:
                    indirct_mem_reg = self.mem.alloc_region(indirct_desc_sz * 16, bdf=virtq.bdf, dev_id=virtq.dev_id)
                    virtq.indirct_reg_pool[virtq.avail_idx_sw] = indirct_mem_reg
                    mem_len = indirct_mem_reg.size
                    flags_next = 0
                    pcie_err_flag = 0
                    flags_write = random.randint(0, 1)
                    # if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE and seg_num > 1:
                    #     mem_len = ((self.cfg.max_len + 1 + seg_num) // seg_num) * (seg_num - indirct_ptr)
                    #     if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE not in virtq.err_info_option:
                    #         virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO:
                        flags_next = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO

                    # if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_WRITE_MUST_BE_ZERO:
                    #     flags_write = 1
                    #     if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                    #         virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_WRITE_MUST_BE_ZERO

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR and j == defect_idx:
                        pcie_err_flag = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR

                    id = id_list[j]
                    desc = virtq.gen_a_desc(indirct_mem_reg.get_absolute_address(0), mem_len, flags_indirect=1, next=0, flags_next=flags_next, flags_write=flags_write)
                    # self.log.debug("indirct desc write{} vq{} id {} idx {} desc {}".format("", VirtioVq.vq2str(vq), id, virtq.avail_idx_sw, desc.show(dump=True)))

                    await virtq.write_desc(
                        id,
                        desc,
                        pcie_err_flag=pcie_err_flag,
                    )
                elif j < indirct_ptr:
                    id = id_list[j]
                    next = id_list[j + 1] if j != seg_num - 1 else 0
                    flags_next = j != seg_num - 1
                    mem_len = mbuf.regs[j].size
                    flags_write = None
                    pcie_err_flag = 0

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE and j == defect_idx and j != seg_num - 1:
                        next = virtq.qsz
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE and j == defect_idx:
                        next = id_list[j]
                        flags_next = 1
                        mem_len = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE and seg_num > 1:
                        mem_len = (self.cfg.max_len + 1 + seg_num) // seg_num
                        if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO and j == defect_idx:
                        flags_write = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN and j == defect_idx:
                        mem_len = 0
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR and j == defect_idx:
                        pcie_err_flag = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE and j == defect_idx:
                        mem_len = random.randint(65563, 2**32 - 1)
                        if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_NETTX_PCIE_ERR and j == defect_idx:
                        data = 0
                        await mbuf.regs[j].write(0, data.to_bytes(1, byteorder="little"), defect_injection=1)
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_NETTX_PCIE_ERR

                    desc = virtq.gen_a_desc(
                        mbuf.regs[j].get_absolute_address(0),
                        mem_len,
                        flags_indirect=0,
                        next=next,
                        flags_next=flags_next,
                        flags_write=flags_write,
                    )

                    # self.log.debug("desc write{} vq{} id {} idx {} desc {}".format("", VirtioVq.vq2str(vq), id, virtq.avail_idx_sw, desc.show(dump=True)))
                    await virtq.write_desc(
                        id,
                        desc,
                        pcie_err_flag=pcie_err_flag,
                    )
                else:
                    id = indirct_id_list[j - indirct_ptr - 1]
                    next = indirct_id_list[j - indirct_ptr] if j != seg_num else 0
                    flags_next = j != seg_num
                    mem_len = mbuf.regs[j - 1].size
                    flags_indirect = 0
                    flags_write = None
                    pcie_err_flag = 0

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE and j == defect_idx and j != seg_num:
                        next = indirct_desc_sz
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE and j == defect_idx:
                        next = indirct_id_list[j - indirct_ptr - 1]
                        flags_next = 1
                        mem_len = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC and j == defect_idx:
                        flags_indirect = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE and seg_num > 1:
                        mem_len = (self.cfg.max_len + 1 + seg_num) // seg_num
                        if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO and j == defect_idx:
                        flags_write = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN and j == defect_idx:
                        mem_len = 0
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR and j == defect_idx:
                        pcie_err_flag = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE and j == defect_idx:
                        mem_len = random.randint(65563, 2**32 - 1)
                        if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_NETTX_PCIE_ERR and j == defect_idx:
                        data = 0
                        await mbuf.regs[j - 1].write(0, data.to_bytes(1, byteorder="little"), defect_injection=1)
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_NETTX_PCIE_ERR

                    desc = virtq.gen_a_desc(
                        mbuf.regs[j - 1].get_absolute_address(0),
                        mem_len,
                        flags_indirect=flags_indirect,
                        next=next,
                        flags_next=flags_next,
                        flags_write=flags_write,
                    )
                    # self.log.debug("desc write{} vq{} id {} idx {} desc {}".format("", VirtioVq.vq2str(vq), id, virtq.avail_idx_sw, desc.show(dump=True)))
                    await virtq.write_desc(
                        id,
                        desc,
                        indirct_mem_reg,
                        pcie_err_flag=pcie_err_flag,
                    )
            # self.log.error("done")
            virtq.id_pool[first_id] = id_list
            virtq.mem_reg_pool[first_id] = mbuf.regs
            # self.log.debug(f"vq: {VirtioVq.vq2str(vq)} mem_reg_pool start id: {first_id}")

            await virtq.write_avail(virtq.avail_idx_sw, first_id, defect)
            virtq.avail_idx_sw = (virtq.avail_idx_sw + 1) & 0xFFFF
        if pkt_cnt > 0:
            await virtq.write_avail_idx(virtq.avail_idx_sw, virtq.idx_defect)
            if virtq.idx_defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR:
                virtq.idx_defect = None
        virtq.producer_event.set()
        return mbufs[pkt_cnt:]

    async def burst_rx_consumer(self, vq, forced_shutdown=False):
        virtq = self.virtq[vq]
        if virtq.status not in [VirtioStatus.DOING, VirtioStatus.STOPPING]:
            return None
        virtq.consumer_event.clear()
        qid, typ = VirtioVq.vq2qid(vq)
        net_rx = self.tb.virtio_net.rx

        mbufs = []
        mbufs_idx = []
        used_idx_pi = await virtq.read_used_idx()
        used_desc_num = used_idx_pi - virtq.used_idx_ci if used_idx_pi >= virtq.used_idx_ci else used_idx_pi + (2**16) - virtq.used_idx_ci
        if used_desc_num != 0:
            # self.log.debug(f"{VirtioVq.vq2str(vq)} recycle_desc used_desc_num {used_desc_num} used_idx_pi {used_idx_pi} virtq.used_idx_ci {virtq.used_idx_ci} ")
            pass
        if used_desc_num > 0:
            for i in range(used_desc_num):
                used_elem = await virtq.read_used_element(virtq.used_idx_ci)
                total_len = used_elem.len
                id = used_elem.id
                regs = virtq.mem_reg_pool[virtq.used_idx_ci]
                if virtq.used_idx_ci in virtq.indirct_reg_pool.keys():
                    self.mem.free_region(virtq.indirct_reg_pool[virtq.used_idx_ci])
                    del virtq.indirct_reg_pool[virtq.used_idx_ci]
                mbufs.append(Mbufs(regs, total_len))
                del virtq.mem_reg_pool[virtq.used_idx_ci]
                mbufs_idx.append(id)
                ids = virtq.id_pool[virtq.used_idx_ci]
                for id in ids:
                    virtq.id_allocator.release_id(id)
                del virtq.id_pool[virtq.used_idx_ci]
                virtq.used_idx_ci = (virtq.used_idx_ci + 1) & 0xFFFF

        forced_shutdown_num = 0
        if forced_shutdown:
            used_idx_ci = ((await self.tb.virtio_ctrl.reg_read(vq, VirtioCtrlRegOffset.AVAIL_CI_PTR)) >> 32) & 0xFFFF
            forced_shutdown_num = used_idx_ci - virtq.used_idx_ci if used_idx_ci >= virtq.used_idx_ci else used_idx_ci + (2**16) - virtq.used_idx_ci
            if forced_shutdown_num > 0:
                self.log.info(f"used_idx_ci: {used_idx_ci} virtq.used_idx_ci: {virtq.used_idx_ci}")
        await net_rx.rx_check_queue.put((vq, mbufs, mbufs_idx, forced_shutdown_num))
        virtq.consumer_event.set()
        # used_idx_pi = self.virt_ctrl.reg_read()

    async def burst_rx_producer(self, vq):
        virtq = self.virtq[vq]
        while virtq.status not in [VirtioStatus.DOING, VirtioStatus.STARTING]:
            # self.log.debug(f"burst_rx_producer await {virtq.status}")
            if virtq.finished:
                return
            await Timer(1, "us")
        virtq.producer_event.clear()
        qid, typ = VirtioVq.vq2qid(vq)

        avail_num = virtq.used_idx_ci - virtq.avail_idx_sw if virtq.used_idx_ci > virtq.avail_idx_sw else virtq.used_idx_ci + (2**16) - virtq.avail_idx_sw
        # avail_num = min(avail_num, len(list(virtq.id_allocator)))
        avail_idx_sw_update_num = 0
        avail_num = max(avail_num, 32)
        for i in range(avail_num):
            defect = virtq.err_info_choose()
            indirct_desc_mem = None
            indirct_desc_sz = 0
            first_id = None
            dirct_id_list = []
            mem_reg_list = []

            # desc_cnt = random.randint(self.cfg.min_chain_num,self.cfg.max_chain_num)
            mu = self.cfg.min_chain_num + min((self.cfg.max_chain_num - self.cfg.min_chain_num) // 3, 16)
            desc_cnt = rand_norm_int(self.cfg.min_chain_num, self.cfg.max_chain_num, mu, 15)
            if defect == VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR:
                desc_cnt = 1
            dirct_cnt = desc_cnt
            if virtq.indirct_support or defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT:
                # indirct_ptr = random.randint(0 , min(desc_cnt - 1,self.cfg.max_indirct_ptr))
                indirct_ptr = random.randint(0, self.cfg.max_indirct_ptr)
                if indirct_ptr > desc_cnt - 1:
                    indirct_cnt = 0
                else:
                    dirct_cnt = indirct_ptr + 1
                    desc_cnt = desc_cnt + 1
                    indirct_cnt = desc_cnt - dirct_cnt

                    indirct_desc_sz = random.randint(indirct_cnt, self.cfg.max_indirct_desc_size)
                    if self.cfg.indirct_relaxed_ordering:
                        indirct_id_list = [0] + random.sample(range(1, indirct_desc_sz), indirct_cnt - 1)
                    else:
                        indirct_id_list = range(indirct_cnt)
            else:
                indirct_cnt = 0

            if dirct_cnt > virtq.id_allocator.get_available_count():
                break

            assert virtq.max_len > (desc_cnt - 1)

            if defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX or defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR:
                virtq.idx_defect = defect
                self.log.info(f"true choose {defect}")

            if indirct_cnt != 0:
                base_desc_data_len = virtq.max_len // (desc_cnt - 1)
                remain_desc_data_len = virtq.max_len % (desc_cnt - 1)
                indirct_desc_mem = self.mem.alloc_region(indirct_desc_sz * 16, bdf=virtq.bdf, dev_id=virtq.dev_id)
                virtq.indirct_reg_pool[virtq.avail_idx_sw] = indirct_desc_mem
                if not virtq.indirct_support:
                    if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                        virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT
                    if defect != VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT:
                        raise Exception(f"unexcept VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT")
            else:
                base_desc_data_len = virtq.max_len // (desc_cnt)
                remain_desc_data_len = virtq.max_len % (desc_cnt)
            vld_desc_cnt = desc_cnt if indirct_cnt == 0 else desc_cnt - 1
            defect_idx = random.randint(0, desc_cnt - 1)

            if defect not in [None, VirtioErrCode.VIRTIO_ERR_CODE_NONE]:
                self.log.info(
                    f"vq: {VirtioVq.vq2str(vq)} seg_num: {desc_cnt} indirct_cnt: {indirct_cnt}  defect: {str(VirtioErrCode(defect))} idx: {virtq.avail_idx_sw} defect_idx {defect_idx}"
                )
            for j in range(dirct_cnt):
                id = virtq.id_allocator.alloc_id()
                dirct_id_list.append(id)
                if j == 0:
                    first_id = id

            for j in range(dirct_cnt):

                if j == desc_cnt - 1:
                    mem_reg = self.mem.alloc_region(base_desc_data_len + remain_desc_data_len, bdf=virtq.bdf, dev_id=virtq.dev_id)
                elif j == dirct_cnt - 1:
                    pass
                else:
                    mem_reg = self.mem.alloc_region(base_desc_data_len, bdf=virtq.bdf, dev_id=virtq.dev_id)
                flags_write = None
                pcie_err_flag = 0
                if j == desc_cnt - 1:
                    desc_addr = mem_reg.get_absolute_address(0)
                    desc_len = base_desc_data_len + remain_desc_data_len
                    flags_indirect = 0
                    next = 0
                    flags_next = 0

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE and vld_desc_cnt > 1:

                        desc_len = (self.cfg.max_len_rx + 1 + vld_desc_cnt) // vld_desc_cnt
                        if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE and j == defect_idx:
                        flags_write = 0
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE and j == defect_idx:
                        desc_len = random.randint(65563, 2**32 - 1)
                        if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR:
                        desc_len = 1
                        if VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR)

                elif j == dirct_cnt - 1:
                    desc_addr = indirct_desc_mem.get_absolute_address(0)
                    desc_len = indirct_desc_sz * 16
                    flags_indirect = 1
                    next = random.randint(0, 2**16 - 1)
                    flags_next = 0

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO:
                        flags_next = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO

                    # if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_WRITE_MUST_BE_ZERO:
                    #     flags_write = 1
                    #     if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                    #         virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_WRITE_MUST_BE_ZERO

                    # desc = virtq.gen_a_desc(indirct_desc_mem.get_absolute_address(0), indirct_desc_sz * 16, flags_indirect=1, next=random.randint(0, 2**16 - 1), flags_next=0)
                else:
                    desc_addr = mem_reg.get_absolute_address(0)
                    desc_len = base_desc_data_len
                    next = dirct_id_list[j + 1]
                    flags_indirect = 0
                    flags_next = 1

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE and j == defect_idx:
                        next = virtq.qsz
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE and vld_desc_cnt > 1:
                        desc_len = (self.cfg.max_len_rx + 1 + vld_desc_cnt) // vld_desc_cnt
                        if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE and j == defect_idx:
                        flags_write = 0
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE and j == defect_idx:
                        desc_len = random.randint(65563, 2**32 - 1)
                        if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR:
                        desc_len = 1
                        if VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR)

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE and j == defect_idx and (j == desc_cnt - 1 or j != dirct_cnt - 1):
                    next = dirct_id_list[j]
                    flags_next = 1
                    desc_len = 1
                    if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                        virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN and j == defect_idx:
                    desc_len = 0
                    if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                        virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR and j == defect_idx:
                    pcie_err_flag = 1
                    if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                        virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR

                desc = virtq.gen_a_desc(
                    desc_addr,
                    desc_len,
                    flags_indirect=flags_indirect,
                    next=next,
                    flags_next=flags_next,
                    flags_write=flags_write,
                )

                if (j != dirct_cnt - 1) or j == desc_cnt - 1:
                    mem_reg_list.append(mem_reg)

                await virtq.write_desc(
                    dirct_id_list[j],
                    desc,
                    pcie_err_flag=pcie_err_flag,
                )

            for j in range(indirct_cnt):
                if j == indirct_cnt - 1:
                    mem_reg = self.mem.alloc_region(base_desc_data_len + remain_desc_data_len, bdf=virtq.bdf, dev_id=virtq.dev_id)
                else:
                    mem_reg = self.mem.alloc_region(base_desc_data_len, bdf=virtq.bdf, dev_id=virtq.dev_id)

                desc_addr = mem_reg.get_absolute_address(0)
                flags_write = None
                pcie_err_flag = 0
                if j == indirct_cnt - 1:
                    desc_len = base_desc_data_len + remain_desc_data_len
                    flags_indirect = 0
                    flags_next = 0
                    next = 0
                else:
                    desc_len = base_desc_data_len
                    flags_indirect = 0
                    flags_next = 1
                    next = indirct_id_list[j + 1]
                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE and j + dirct_cnt == defect_idx:
                        next = indirct_desc_sz
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR:
                    desc_len = 1
                    if VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR not in virtq.err_info_option:
                        virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR)

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE and j + dirct_cnt == defect_idx:
                    next = indirct_id_list[j]
                    flags_next = 1
                    desc_len = 1
                    if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                        virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE and vld_desc_cnt > 1:
                    desc_len = (self.cfg.max_len_rx + 1 + vld_desc_cnt) // vld_desc_cnt
                    if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE not in virtq.err_info_option:
                        virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE)

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC and j + dirct_cnt == defect_idx and j != indirct_cnt - 1:
                    flags_indirect = 1
                    if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                        virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE and j + dirct_cnt == defect_idx:
                    flags_write = 0
                    if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                        virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN and j + dirct_cnt == defect_idx:
                    desc_len = 0
                    if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                        virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN

                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR and j + dirct_cnt == defect_idx:
                    pcie_err_flag = 1
                    if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                        virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR
                if defect == VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE and j + dirct_cnt == defect_idx:
                    desc_len = random.randint(self.cfg.max_len_rx, 2**32 - 1)
                    if VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE not in virtq.err_info_option:
                        virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE)
                desc = virtq.gen_a_desc(
                    desc_addr,
                    desc_len,
                    flags_indirect=flags_indirect,
                    next=next,
                    flags_next=flags_next,
                    flags_write=flags_write,
                )

                mem_reg_list.append(mem_reg)
                await virtq.write_desc(
                    indirct_id_list[j],
                    desc,
                    indirct_desc_mem,
                    pcie_err_flag=pcie_err_flag,
                )

            virtq.mem_reg_pool[virtq.avail_idx_sw] = mem_reg_list
            virtq.id_pool[virtq.avail_idx_sw] = dirct_id_list
            await virtq.write_avail(virtq.avail_idx_sw, first_id, defect)
            virtq.avail_idx_sw = (virtq.avail_idx_sw + 1) & 0xFFFF
            avail_idx_sw_update_num += 1
        if avail_idx_sw_update_num > 0:
            await virtq.write_avail_idx(virtq.avail_idx_sw, defect=virtq.idx_defect)
            if virtq.idx_defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR:
                virtq.idx_defect = None
        virtq.producer_event.set()

    async def burst_blk_consumer(self, vq) -> None:
        virtq = self.virtq[vq]
        if virtq.status not in [VirtioStatus.DOING, VirtioStatus.STOPPING]:
            return None
        virtq.consumer_event.clear()
        qid, typ = VirtioVq.vq2qid(vq)
        blk = self.tb.virtio_net.blk
        # while not virtq.consumer_event.is_set():
        #     await Timer(20, "ns")
        # if not virtq.consumer_event.is_set():
        #     return None
        # self.log.debug(f"burst_tx_consumer start")
        used_idx_pi = await virtq.read_used_idx()
        used_desc_num = used_idx_pi - virtq.used_idx_ci if used_idx_pi >= virtq.used_idx_ci else used_idx_pi + (2**16) - virtq.used_idx_ci
        if used_desc_num != 0:
            # self.log.debug(f"{VirtioVq.vq2str(vq)} recycle_desc used_desc_num {used_desc_num} used_idx_pi {used_idx_pi} virtq.used_idx_ci {virtq.used_idx_ci} ")
            await self.tb.virtio_net.blk.ref_pkt_num.put((virtq.qid, used_desc_num))
        for i in range(used_desc_num):
            used_elem = await virtq.read_used_element(virtq.used_idx_ci)
            total_len = used_elem.len
            virtq.elem.append(total_len)
            # self.log.error(f"consumer total_len {total_len}")
            id = used_elem.id
            # self.log.debug(f"vq: {VirtioVq.vq2str(vq)} mem_reg_pool stop id: {id} virtq.used_idx_ci: {virtq.used_idx_ci}")
            regs = virtq.mem_reg_pool[id]
            if virtq.used_idx_ci in virtq.indirct_reg_pool.keys():
                self.mem.free_region(virtq.indirct_reg_pool[virtq.used_idx_ci])
                del virtq.indirct_reg_pool[virtq.used_idx_ci]

            hdr_raw = await regs[0].read(0, 16)
            hdr = VirtioBlkOuthdr().unpack(hdr_raw[::-1])
            sts = await regs[-1].read(0, 1)
            if len(regs) > 2:
                pld_data = b''
                for j in range(len(regs) - 2):
                    data = await regs[j + 1].read(0, regs[j + 1].size)
                    # self.log.info("read reg seq {} idx {} addr {} len {}".format(hdr.ioprio, j, regs[j + 1].get_absolute_address(0), regs[j + 1].size))
                    pld_data = pld_data + data
            else:
                pld_data = b''

            await blk.blk_act_queues.put((qid, hdr, pld_data, total_len, sts))

            for reg in regs:
                self.mem.free_region(reg)
            del virtq.mem_reg_pool[id]
            virtq.used_idx_ci = (virtq.used_idx_ci + 1) & 0xFFFF
            ids = virtq.id_pool[id]
            for idx in ids:
                virtq.id_allocator.release_id(idx)
            del virtq.id_pool[id]
        virtq.consumer_event.set()

    async def burst_blk_producer(self, vq, mbufs: list[Mbufs]) -> Mbufs:
        virtq = self.virtq[vq]
        while virtq.status not in [VirtioStatus.DOING, VirtioStatus.STARTING]:
            # self.log.debug(f"burst_tx_producer await {virtq.status}")
            if virtq.finished:
                return mbufs
            await Timer(1, "us")
        virtq.producer_event.clear()
        qid, typ = VirtioVq.vq2qid(vq)
        avail_num = virtq.avail_idx_sw - virtq.used_idx_ci if virtq.avail_idx_sw >= virtq.used_idx_ci else virtq.avail_idx_sw + (2**16) - virtq.used_idx_ci
        need_send_pkt = min(virtq.qsz - avail_num, len(mbufs))
        pkt_cnt = 0
        for i in range(need_send_pkt):
            defect = virtq.err_info_choose()
            mbuf = mbufs[i]
            seg_num = len(mbuf.regs) if defect != VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE else 1

            indirct_ptr = random.randint(0, seg_num - 1) if virtq.indirct_support or (defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT) else seg_num
            indirct_desc_sz = random.randint((seg_num - indirct_ptr), self.cfg.max_indirct_desc_size)

            if virtq.indirct_support and self.cfg.indirct_relaxed_ordering:
                indirct_id_list = [0] + random.sample(range(1, indirct_desc_sz), seg_num - indirct_ptr - 1)
            else:
                indirct_id_list = range(seg_num - indirct_ptr)

            indirct_mem_reg = None
            first_id = None
            id_list = []
            dirct_desc_cnt = min(seg_num, indirct_ptr + 1)
            if dirct_desc_cnt > virtq.id_allocator.get_available_count():
                break
            else:
                pkt_cnt = pkt_cnt + 1

            if seg_num == 1 and virtq.err_info == VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE
            # self.log.info(f" reg {mbuf.regs[0].get_absolute_address(0):x} reg used")
            if defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX or defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR:
                virtq.idx_defect = defect
            if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT and virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE and not virtq.indirct_support:
                virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT
            defect_idx = random.randint(0, seg_num)
            # defect_idx = random.randint(indirct_ptr, seg_num)
            # a = indirct_ptr + 1 if indirct_ptr < seg_num else indirct_ptr
            # defect_idx = random.randint(indirct_ptr + 1 if indirct_ptr < seg_num else indirct_ptr, seg_num)
            if defect not in [None, VirtioErrCode.VIRTIO_ERR_CODE_NONE]:
                self.log.info(
                    f"vq: {VirtioVq.vq2str(vq)} seg_num: {seg_num} indirct_ptr: {indirct_ptr}  defect: {str(VirtioErrCode(defect))} idx: {virtq.avail_idx_sw} defect_idx {defect_idx}"
                )
            for j in range(dirct_desc_cnt):
                id = virtq.id_allocator.alloc_id()
                id_list.append(id)
                if j == 0:
                    first_id = id

            for j in range(seg_num + (indirct_ptr < seg_num)):
                flags_write = (j + 1 == seg_num + (indirct_ptr < seg_num)) or (mbuf.typ == VirtioBlkType.VIRTIO_BLK_T_IN and (j != 0 and (indirct_ptr == 0 and j != 1)))
                if j == indirct_ptr:
                    indirct_mem_reg = self.mem.alloc_region(indirct_desc_sz * 16, bdf=virtq.bdf, dev_id=virtq.dev_id)
                    virtq.indirct_reg_pool[virtq.avail_idx_sw] = indirct_mem_reg
                    mem_len = indirct_mem_reg.size
                    flags_next = 0
                    pcie_err_flag = 0
                    id = id_list[j]

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO:
                        flags_next = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR and j == defect_idx:
                        pcie_err_flag = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR

                    desc = virtq.gen_a_desc(indirct_mem_reg.get_absolute_address(0), mem_len, flags_indirect=1, next=0, flags_next=flags_next, flags_write=flags_write)
                    # self.log.debug("indirct desc write{} vq{} id {} idx {} desc {}".format("", VirtioVq.vq2str(vq), id, virtq.avail_idx_sw, desc.show(dump=True)))

                    await virtq.write_desc(
                        id,
                        desc,
                        pcie_err_flag=pcie_err_flag,
                    )
                elif j < indirct_ptr:
                    id = id_list[j]
                    next = id_list[j + 1] if j != seg_num - 1 else 0
                    flags_next = j != seg_num - 1
                    mem_len = mbuf.regs[j].size
                    # flags_write = None
                    pcie_err_flag = 0

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE and j == defect_idx:
                        mem_len = virtq.segment_size_blk + 1
                        if VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE and j == defect_idx and j != seg_num - 1:
                        next = virtq.qsz
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE and j == defect_idx:
                        next = id_list[j]
                        flags_next = 1
                        mem_len = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO and j == defect_idx:
                        mem_len = 0
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR and j == defect_idx:
                        pcie_err_flag = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR and j == defect_idx and flags_write == 0:
                        # await mbuf.regs[j].write(0, (0).to_bytes(mbuf.regs[j].size,byteorder="little"), defect_injection=1)
                        mbuf.regs[j].defect_injection(0, mbuf.regs[j].size)
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR

                    desc = virtq.gen_a_desc(
                        mbuf.regs[j].get_absolute_address(0),
                        mem_len,
                        flags_indirect=0,
                        next=next,
                        flags_next=flags_next,
                        flags_write=flags_write,
                    )

                    # self.log.debug("desc write{} vq{} id {} idx {} desc {}".format("", VirtioVq.vq2str(vq), id, virtq.avail_idx_sw, desc.show(dump=True)))
                    await virtq.write_desc(
                        id,
                        desc,
                        pcie_err_flag=pcie_err_flag,
                    )
                else:
                    id = indirct_id_list[j - indirct_ptr - 1]
                    next = indirct_id_list[j - indirct_ptr] if j != seg_num else 0
                    flags_next = j != seg_num
                    mem_len = mbuf.regs[j - 1].size
                    flags_indirect = 0
                    # flags_write = None
                    pcie_err_flag = 0

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE and j == defect_idx and j != seg_num:
                        next = indirct_desc_sz
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE and j == defect_idx:
                        next = indirct_id_list[j - indirct_ptr - 1]
                        flags_next = 1
                        mem_len = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC and j == defect_idx:
                        flags_indirect = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO and j == defect_idx:
                        mem_len = 0
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR and j == defect_idx:
                        pcie_err_flag = 1
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE and j == defect_idx:
                        mem_len = virtq.segment_size_blk + 1
                        if VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE not in virtq.err_info_option:
                            virtq.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE)

                    if defect == VirtioErrCode.VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR and j == defect_idx and flags_write == 0:
                        # await mbuf.regs[j - 1].write(0, (0).to_bytes(mbuf.regs[j - 1].size,byteorder="little"), defect_injection=1)
                        mbuf.regs[j - 1].defect_injection(0, mbuf.regs[j - 1].size)
                        if virtq.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                            virtq.err_info = VirtioErrCode.VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR

                    desc = virtq.gen_a_desc(
                        mbuf.regs[j - 1].get_absolute_address(0),
                        mem_len,
                        flags_indirect=flags_indirect,
                        next=next,
                        flags_next=flags_next,
                        flags_write=flags_write,
                    )
                    # self.log.debug("desc write{} vq{} id {} idx {} desc {}".format("", VirtioVq.vq2str(vq), id, virtq.avail_idx_sw, desc.show(dump=True)))
                    await virtq.write_desc(
                        id,
                        desc,
                        indirct_mem_reg,
                        pcie_err_flag=pcie_err_flag,
                    )
            # self.log.error("done")
            virtq.id_pool[first_id] = id_list
            virtq.mem_reg_pool[first_id] = mbuf.regs
            # self.log.debug(f"vq: {VirtioVq.vq2str(vq)} mem_reg_pool start id: {first_id}")

            await virtq.write_avail(virtq.avail_idx_sw, first_id, defect)
            virtq.avail_idx_sw = (virtq.avail_idx_sw + 1) & 0xFFFF

        if pkt_cnt > 0:
            await virtq.write_avail_idx(virtq.avail_idx_sw, virtq.idx_defect)
            if virtq.idx_defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR:
                virtq.idx_defect = None
        virtq.producer_event.set()
        return mbufs[pkt_cnt:]

    async def tx_worker(self, vq) -> None:
        self.log.debug("tx_worker")
        mbufs = []
        qid, typ = VirtioVq.vq2qid(vq)
        # while qid not in self.tb.virtio_net.tx.gen_pkt_queues.keys():
        #     await Timer(1, "us")
        virtq = self.virtq[vq]
        while not virtq.finished:
            try:
                need_get = 32 - len(mbufs)
                for _ in range(need_get):
                    if self.tb.virtio_net.tx.ref_pkt_queues[qid].full():
                        break
                    mbufs.append(await self.tb.virtio_net.tx._gen_pkt(qid))
                    if random.randint(0, 100) > 80:
                        break
            except QueueEmpty:
                pass
            mbufs = await self.burst_tx_producer(vq, mbufs)
            if virtq.msix_event is not None:
                if virtq.msix_event.is_set():
                    virtq.msix_event.clear()
                    await self.burst_tx_consumer(vq)
            else:
                await self.burst_tx_consumer(vq)
            await Timer(1.6, "us")
        for mbuf in mbufs:
            regs = mbuf.regs
            for reg in regs:
                self.mem.free_region(reg)
        self.log.info(f"vq: {VirtioVq.vq2str(vq)} finished")

    async def rx_worker(self, vq) -> None:
        self.log.debug("rx_worker")
        qid, typ = VirtioVq.vq2qid(vq)
        virtq = self.virtq[vq]
        while not virtq.finished:
            await self.burst_rx_producer(vq)
            if virtq.msix_event is not None:
                if virtq.msix_event.is_set():
                    virtq.msix_event.clear()
                    await self.burst_rx_consumer(vq)
            else:
                await self.burst_rx_consumer(vq)
            await Timer(1.6, "us")

    async def blk_worker(self, vq) -> None:
        self.log.debug("blk_worker")
        mbufs = []
        qid, typ = VirtioVq.vq2qid(vq)
        virtq = self.virtq[vq]
        blk = self.tb.virtio_net.blk
        while not virtq.finished:
            try:
                need_get = 32 - len(mbufs)
                for _ in range(need_get):
                    if len(blk.blk_exp_queues[qid]) > 128 or not blk.id_alllocator[qid].available_resources:
                        break
                    # self.log.info(f"vq {VirtioVq.vq2str(VirtioVq.qid2vq(qid,TestType.BLK))} gen_pkt")
                    mbufs.append(await blk._gen_pkt(qid))
                    if random.randint(0, 100) > 80:
                        break

            except QueueEmpty:
                pass
            # self.log.info(f"vq {VirtioVq.vq2str(VirtioVq.qid2vq(qid,TestType.BLK))} blk_producer")
            mbufs = await self.burst_blk_producer(vq, mbufs)
            if virtq.msix_event is not None:
                if virtq.msix_event.is_set():
                    virtq.msix_event.clear()
                    await self.burst_blk_consumer(vq)
            else:
                await self.burst_blk_consumer(vq)
            await Timer(1.6, "us")

        for mbuf in mbufs:
            regs = mbuf.regs
            for reg in regs:
                # self.log.info(f"reg : {reg.get_absolute_address(0):x} free")
                self.mem.free_region(reg)

        self.log.info(f"vq: {VirtioVq.vq2str(vq)} finished")

    async def tx_check_result(self) -> None:
        net_tx = self.tb.virtio_net.tx
        while True:
            qid, pkt_num = await net_tx.ref_pkt_num.get()
            vq = VirtioVq.qid2vq(qid, TestType.NETTX)
            virtq = self.virtq[vq]
            vq_str = VirtioVq.vq2str(vq)
            for i in range(pkt_num):
                # pkt = await self.net2tso_queue[qid].get()
                total_len = virtq.elem.pop(0)
                (ref_info, ref_data) = net_tx.ref_pkt_queues[qid].get_nowait()
                if total_len == 0:
                    continue
                T = 0
                while net_tx.net2tso_queue[qid].empty():
                    await Timer(100, "ns")
                    T = T + 1
                    if T == 10:
                        self.log.error(f" qid {qid} has no pkt out pkt_num {i}")
                        (ref_info, ref_data) = net_tx.ref_pkt_queues[qid]._queue[0]
                        self.log.error(f"info: {ref_info}")
                        self.log.error(f"data: {ref_data.hex()}")
                        self.log.error(f"doing: {net_tx.doing}")
                        raise Exception(f"net2tso_queue qid:{qid} has no pkt")

                pkt = net_tx.net2tso_queue[qid].get_nowait()
                vq = VirtioVq.qid2vq(pkt.qid, TestType.NETTX)
                if ref_info.qid != pkt.qid:
                    self.log.warning(f"{vq_str}  ref qid: {ref_info.qid}")
                    raise Exception("tx pkt qid is mismatch")
                if self.tb.virtio_pmd.virtq[vq].gen != pkt.gen:
                    self.log.warning(f"{VirtioVq.vq2str(vq)}  ref gen: {ref_info.gen} cur gen {pkt.gen}")
                    raise Exception("tx pkt gen is mismatch")
                if ref_info.pkt_len != pkt.length:
                    self.log.warning(f"{VirtioVq.vq2str(vq)}  ref length: {ref_info.pkt_len} cur length {pkt.length}")
                    self.log.warning(f"ref: {ref_data.hex()}")
                    self.log.warning(f"cur: {pkt.data.hex()}")
                    raise Exception("tx pkt length is mismatch")
                if ref_info.tso_en != pkt.tso_en:
                    self.log.warning(f"{VirtioVq.vq2str(vq)}  ref tso_en: {ref_info.tso_en} cur tso_en {pkt.tso_en}")
                    raise Exception("tx pkt tso_en is mismatch")

                if ref_info.csum_en != pkt.csum_en:
                    self.log.warning(f"{VirtioVq.vq2str(vq)}  ref csum_en: {ref_info.csum_en} cur csum_en {pkt.csum_en}")
                    raise Exception("tx pkt csum_en is mismatch")

                if ref_data != pkt.data:
                    self.log.warning(f"{VirtioVq.vq2str(vq)} total_len {len(pkt.data)} info: {ref_info}")
                    self.log.warning(f"ref: {ref_data.hex()}")
                    self.log.warning(f"cur: {pkt.data.hex()}")
                    raise Exception("tx pkt data is mismatch")

                virtq.check_result += 1
                self.log.info(f"{VirtioVq.vq2str(vq)} seq_num {ref_info.seq_num} pass pass_num: {virtq.check_result} ")
                # self.log.info(f"{VirtioVq.vq2str(vq)} seq_num {ref_info.seq_num} pass data:{ref_data.hex()}")
            if virtq.check_result >= self.cfg.max_seq:
                virtq.finished = True
                # self.log.info("{VirtioVq.vq2str(vq)} seq_num {ref_info.seq_num} pass")

    def drop_pkt(self, vq):
        qid, typ = VirtioVq.vq2qid(vq)
        vq_str = VirtioVq.vq2str(vq)
        net_rx = self.tb.virtio_net.rx
        seq_num = None
        while qid in net_rx.net_rx_info.keys() and len(net_rx.net_rx_info[qid]) > 0:
            info = net_rx.net_rx_info[qid][0]
            if info.drop:
                net_rx.net_rx_info[qid].pop(0)
                seq_num = info.seq_num
                self.log.info(f"{vq_str} seq_num {seq_num} drop")
            else:
                # seq_num = info.seq_num
                # ref_info = info
                # ref_pkt  = self.net_rx_data[qid][0]
                # ref_data = ((2).to_bytes(1, byteorder="little") if ref_info.data_vld else b'\x00') + b'\x00'*11 + ref_pkt
                # self.log.error(f"{ref_data.hex()}")
                # self.log.error(f"seq_num = info.seq_num{seq_num}")
                break
        return seq_num

    async def rx_check_result(self) -> None:
        net_rx = self.tb.virtio_net.rx
        while True:
            vq, mbufs, mbufs_idx, forced_shutdown_num = await net_rx.rx_check_queue.get()
            virtq = self.virtq[vq]
            qid, typ = VirtioVq.vq2qid(vq)
            vq_str = VirtioVq.vq2str(vq)
            if len(mbufs) > 0:
                for i in range(len(mbufs)):
                    mbuf = mbufs[i]
                    mbuf_idx = mbufs_idx[i]
                    self.drop_pkt(vq)
                    pkt = bytes()
                    for reg in mbuf.regs:
                        total_len = len(pkt)
                        bytes_read = mbuf.len - total_len
                        if bytes_read == 0:
                            pass
                        elif bytes_read > reg.size:
                            pkt += await reg.read(0, reg.size)
                        else:
                            pkt += await reg.read(0, bytes_read)
                        self.mem.free_region(reg)
                    if len(net_rx.net_rx_info[qid]) < 1 or len(net_rx.net_rx_data[qid]) < 1:
                        self.log.error(f"vq: {vq_str}  pkt: {pkt.hex()} ")
                        raise Exception("net_rx_exp_error")
                    ref_info = net_rx.net_rx_info[qid].pop(0)
                    ref_pkt = net_rx.net_rx_data[qid].pop(0)
                    ref_data = ((2).to_bytes(1, byteorder="little") if ref_info.data_vld else b'\x00') + b'\x00' * 11 + ref_pkt
                    if len(pkt) == 0:
                        continue
                    if ref_data != pkt:
                        self.log.error("{} total_len {} info: {}".format(vq_str, len(pkt), ref_info))
                        self.log.error(f"ref_pkt_len: {len(ref_data) - 12}\n ref: {ref_data.hex()}")
                        self.log.error(f"cur_pkt_len: {len(pkt) - 12}\n cur: {pkt.hex()}")
                        self.log.error(f"idx is:{mbuf_idx}")

                        for j in range(len(net_rx.net_rx_data[qid])):
                            ref_info = net_rx.net_rx_info[qid][j]
                            ref_pkt = net_rx.net_rx_data[qid][j]
                            ref_data = ((2).to_bytes(1, byteorder="little") if ref_info.data_vld else b'\x00') + b'\x00' * 11 + ref_pkt
                            self.log.error(f"j{j} ref_pkt_len: {len(ref_data) - 12}\n ref: {ref_data.hex()}")

                        raise Exception("rx pkt is mismatch")
                    virtq.check_result += 1
                    self.log.info(f"{VirtioVq.vq2str(vq)} seq_num {ref_info.seq_num} pass pass_num: {virtq.check_result} ")

                    net_rx.pkt_time_last = get_sim_time("ns")
                    net_rx.pps_cnt += 1
                    net_rx.bps_cnt += len(ref_data) - 12  # B
                if net_rx.pkt_time_start is None:
                    net_rx.pkt_time_start = get_sim_time("ns")
                    net_rx.pps_cnt = 0
                    net_rx.bps_cnt = 0

            if forced_shutdown_num > 0:
                for i in range(forced_shutdown_num):
                    self.drop_pkt(vq)
                    ref_info = net_rx.net_rx_info[qid].pop(0)
                    ref_pkt = net_rx.net_rx_data[qid].pop(0)
                    self.log.info(f"{vq_str} seq_num {ref_info.seq_num} forced_shutdown drop ")

            if virtq.check_result >= self.cfg.max_seq:
                virtq.finished = True

    async def blk_check_result(self) -> None:
        blk = self.tb.virtio_net.blk
        while True:
            qid, hdr, pld_data, used_len, sts = await blk.blk_act_queues.get()
            vq = VirtioVq.qid2vq(qid, TestType.BLK)
            virtq = self.virtq[vq]
            # pass
            id = hdr.ioprio >> 16
            # self.log.error(f"blk_checker ioprio{hdr.ioprio>>16}")
            info = blk.blk_exp_queues[qid][id]
            info.fe_sts = sts
            if hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:  # read
                info.fe_data = pld_data
                info.fe_len = used_len - 1
            # checker
            if info.fe_typ != hdr.type:
                self.log.warning("{} id {} seq_num {} ref {} cur {}".format(VirtioVq.vq2str(vq), id, self._finish_seq_num[qid], info.fe_typ, hdr.type))
                raise Exception("blk checker status is mismatch")
            if hdr.type == VirtioBlkType.VIRTIO_BLK_T_OUT or hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:
                if info.fe_len != len(info.be_data):
                    self.log.warning("{} id {} seq_num {}".format(VirtioVq.vq2str(vq), id, self._finish_seq_num[qid]))
                    self.log.warning("be: {}".format(len(info.be_data)))
                    self.log.warning("fe: {}".format(info.fe_len))
                    raise Exception("blk checker len is mismatch")
                if info.fe_data != info.be_data:
                    self.log.warning("{} id {}  seq_num {}".format(VirtioVq.vq2str(vq), id, self._finish_seq_num[qid]))
                    self.log.warning("be: {}".format(info.be_data.hex()))
                    self.log.warning("fe: {}".format(info.fe_data.hex()))
                    raise Exception("blk checker data is mismatch")
            if info.fe_sts != info.be_sts:
                self.log.warning("{} id {} seq_num {} be {} fe {}".format(VirtioVq.vq2str(vq), id, self._finish_seq_num[qid], info.be_sts, info.fe_sts))
                raise Exception("blk checker status is mismatch")
            # self.log.info("qid {} id {} seq_num {} pass!".format(qid, id, self._finish_seq_num[qid]))
            virtq.check_result += 1
            self.log.info(f"{VirtioVq.vq2str(vq)} seq_num {info.id} pass pass_num: {virtq.check_result} ")
            # raise Exception("test")
            if virtq.check_result >= self.cfg.max_seq:
                virtq.finished = True
            blk.id_alllocator[qid].release_id(id)
            del blk.blk_exp_queues[qid][id]
        # self.done[qid] = True

    async def worker_clean(self, vq: int) -> None:
        qid, typ = VirtioVq.vq2qid(vq)
        vq_str = VirtioVq.vq2str(vq)
        virtq = self.virtq[vq]
        net_tx = self.tb.virtio_net.tx
        net_rx = self.tb.virtio_net.rx

        if typ == TestType.NETTX:
            await self.burst_tx_consumer(vq)
            self.log.info(f"{vq_str} close status avail_idx_sw {virtq.avail_idx_sw}")
            self.log.info(f"{vq_str} close status used_idx_ci  {virtq.used_idx_ci}")
            avail_num = virtq.avail_idx_sw - virtq.used_idx_ci if virtq.avail_idx_sw >= virtq.used_idx_ci else virtq.avail_idx_sw + 2**16 - virtq.used_idx_ci
            await Timer(1, "ns")
            for i in range(avail_num):
                if net_tx.ref_pkt_queues[qid].empty():
                    raise Exception("func Error")
                info, data = net_tx.ref_pkt_queues[qid].get_nowait()
                if info.qos_en and net_tx.qos_update_queues[qid]._queue[0].seq_num == info.seq_num:
                    qos_info = net_tx.qos_update_queues[qid].get_nowait()

            while not net_tx.net2tso_queue[qid].empty():
                net_tx.net2tso_queue[qid].get_nowait()

        if typ == TestType.NETRX:
            await self.burst_rx_consumer(vq, forced_shutdown=True)
        if typ == TestType.BLK:
            await self.burst_blk_consumer(vq)

    async def doorbell_service(self):
        while True:
            for vq in self.doorbell_queues.keys():
                doorbell_queue = self.doorbell_queues[vq]
                if not doorbell_queue.empty():
                    vq = doorbell_queue.get_nowait()
                    obj = self.tb.interfaces.doorbell_if._transaction_obj()
                    qid, typ = VirtioVq.vq2qid(vq)
                    obj.vq = VirtioVq(typ=typ, qid=qid).pack()
                    await self.tb.interfaces.doorbell_if.send(obj)
            await Timer(5, "ns")

    async def soc_notify_service(self):
        while True:
            vq = await self.soc_notify_queues.get()
            await self.tb.virtio_ctrl.write_soc_notify(vq)
            await Timer(5, "ns")
            # for vq in self.soc_notify_queues.keys():
            #     soc_notify_queue = self.soc_notify_queues[vq]
            #     if not soc_notify_queue.empty():
            #         soc_notify_queue.get_nowait()
            #         await self.tb.virtio_ctrl.write_soc_notify(vq)
            # await Timer(5, "ns")

    async def err_check_service(self):
        virtio_ctrl = self.tb.virtio_ctrl
        while True:
            await Timer(10, "us")
            for vq, virtq in self.virtq.items():

                if virtq.status == VirtioStatus.DOING:
                    status = await virtio_ctrl.read_status(vq)
                    if virtq.status == VirtioStatus.DOING and status == VirtioStatus.IDLE:
                        virtq.check_err = True
                        err_info = await virtio_ctrl.read_err_info(vq)
                        virtq.stop_event.set(1)
                        # self.log.info(f"vq {VirtioVq.vq2str(vq)} stopped with err_info {err_info}")
                        if err_info not in virtq.err_info_option and err_info != virtq.err_info:
                            vq_str = VirtioVq.vq2str(vq)
                            # self.log.error(f"vq: {vq_str}")
                            self.log.error(f"vq: {vq_str} act err_info {str(VirtioErrCode(err_info))} ")
                            self.log.error(f"vq: {vq_str} exp virtq.err_info {str(virtq.err_info)} ")
                            self.log.error(f"vq: {vq_str} virtq.err_info_option {virtq.err_info_option} ")
                            raise Exception("unexcept err_info")
                            # self.log.error(f"")
                        virtq.check_err = False
