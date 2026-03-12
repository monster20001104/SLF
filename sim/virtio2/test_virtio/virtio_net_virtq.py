import logging
import random
from dataclasses import dataclass
from typing import Any, Optional

from cocotb.queue import Queue
from cocotb.triggers import Timer, Event
from address_space import Pool, IORegion

from test_virtio_net_tb import TB
from virtio_net_defines import Cfg, VirtioStatus, VirtioVq, VirtqDesc, TestType, VirtqUsedElement, VirtioErrCode, VirtioBlkOuthdr
from virtio_net_func import ResourceAllocator
from virtio_net_ctrl import VirtioCtrl_StartCfg


@dataclass
class VirtQConfig:
    cfg: Cfg
    log: logging.Logger
    mem: Pool
    tb: Any
    vq: int
    qszWidth: int
    mss: int
    max_len: int
    msix_en: int
    indirct_support: int
    tso_en: int
    csum_en: int
    qos_en: int
    qos_unit: int
    bdf: int
    dev_id: int


class VirtQ:
    def __init__(self, config: VirtQConfig):
        self.cfg: Cfg = config.cfg
        self.log: logging.Logger = config.log
        self.mem: Pool = config.mem
        self.tb: TB = config.tb
        self.vq: int = config.vq
        self.qid, self.typ = VirtioVq.vq2qid(self.vq)
        self.qszWidth: int = config.qszWidth
        self.mss: int = config.mss
        self.max_len: int = config.max_len
        self.msix_en: int = config.msix_en
        self.msix_event: Optional[Event] = Event() if self.msix_en else None
        self.msix_mem: Optional[IORegion] = None
        self.msix_addr: int = 0
        self.msix_data: int = 0
        self.indirct_support: int = config.indirct_support
        self.tso_en: int = config.tso_en
        self.csum_en: int = config.csum_en
        self.qos_en: int = config.qos_en
        self.qos_unit: int = config.qos_unit
        self.bdf: int = config.bdf
        self.dev_id: int = config.dev_id
        self.gen: int = 0
        self.qsz = 2**self.qszWidth
        self.id_allocator = ResourceAllocator(0, self.qsz - 1, self.log)
        # self.id_allocator = set(range(0, self.qsz))
        self.soc_notify_queues = self.tb.virtio_pmd.soc_notify_queues
        self.doorbell_queue = self.tb.virtio_pmd.doorbell_queues[self.vq]

        self.mem_reg_pool = {}
        self.id_pool = {}
        self.indirct_reg_pool = {}
        self.first_db = True
        self.check_result = 0
        self.finished: bool = False
        self.stop_event: Event = Event()
        self.producer_event: Event = Event()
        self.producer_event.set()
        self.consumer_event: Event = Event()
        self.consumer_event.set()
        self.status: VirtioStatus = VirtioStatus.IDLE
        self.check_err: bool = False
        self.err_info: list[VirtioErrCode] = [VirtioErrCode.VIRTIO_ERR_CODE_NONE]
        self.err_info_option: list[VirtioErrCode] = [VirtioErrCode.VIRTIO_ERR_CODE_NONE]
        self.err_info_list: list[VirtioErrCode] = []
        self.elem: list[int] = []
        if self.typ == TestType.BLK:
            self.segment_size_blk = 65562
            self.blk_status = False
        pass

    async def start(self, avail_idx: int = 0) -> None:
        while self.status != VirtioStatus.IDLE or self.check_err:
            await Timer(1, "us")
            self.log.debug(f"vq {VirtioVq.vq2str(self.vq)} wait idle")
        self.log.debug(f"vq {VirtioVq.vq2str(self.vq)} start")
        self.avail_ring = self.mem.alloc_region(4 + 2 * self.qsz + 2, bdf=self.bdf, dev_id=self.dev_id)
        self.desc_tbl = self.mem.alloc_region(16 * self.qsz, bdf=self.bdf, dev_id=self.dev_id)
        self.used_ring = self.mem.alloc_region(4 + 8 * self.qsz + 2, bdf=self.bdf, dev_id=self.dev_id)
        avail_ring_addr = self.avail_ring.get_absolute_address(0)
        used_ring_addr = self.used_ring.get_absolute_address(0)
        desc_tbl_addr = self.desc_tbl.get_absolute_address(0)

        if self.msix_en:
            self.msix_mem = self.mem.alloc_region(4, bdf=self.bdf, dev_id=self.dev_id, region_type=IORegion)
            self.msix_mem.register_write_handler(self.msix_func)
            self.msix_addr = self.msix_mem.get_absolute_address(0)
        else:
            self.msix_addr = 0xFFFF_FFFF
        #     self.msix_mem = self.mem.alloc_region(4, bdf=self.bdf, dev_id=self.dev_id, region_type=IORegion)
        #     self.msix_mem.register_write_handler(self.msix_func)
        #     self.msix_addr = self.msix_mem.get_absolute_address(0)

        self.avail_idx_sw = avail_idx
        self.used_idx_ci = avail_idx
        self.backend_used_idx = avail_idx
        self.err_info = VirtioErrCode.VIRTIO_ERR_CODE_NONE
        self.err_info_option = [VirtioErrCode.VIRTIO_ERR_CODE_NONE]
        self.err_info_list = self.err_info_gen_list(min_err_num=1, max_err_num=1)
        self.idx_defect = None
        if self.typ == TestType.BLK:
            self.blk_status = True
        self.log.info(
            f"alloc_region vq:{VirtioVq.vq2str(self.vq)}  avail_ring_addr:{avail_ring_addr:8x}  used_ring_addr:{used_ring_addr:8x}  desc_tbl_addr:{desc_tbl_addr:8x}  qsz:{self.qsz:8x}"
        )
        start_cfg = VirtioCtrl_StartCfg(
            vq=self.vq,
            qszWidth=self.qszWidth,
            avail_idx=avail_idx,
            avail_ring_addr=avail_ring_addr,
            used_ring_addr=used_ring_addr,
            desc_tbl_addr=desc_tbl_addr,
            indirct_support=self.indirct_support,
            bdf=self.bdf,
            dev_id=self.dev_id,
            tso_en=self.tso_en,
            csum_en=self.csum_en,
            max_len=self.max_len,
            gen=self.gen,
            msix_addr=self.msix_addr,
            msix_data=self.msix_data,
            msix_en=self.msix_en,
            qos_en=self.qos_en,
            qos_unit=self.qos_unit,
        )
        await self.tb.virtio_ctrl.start(cfg=start_cfg)
        self.status = VirtioStatus.DOING

        pass

    async def stop(self, forced_shutdown: int = False) -> None:
        self.gen = (self.gen + 1) % 256
        self.mem.free_region(self.avail_ring)
        self.mem.free_region(self.desc_tbl)
        self.mem.free_region(self.used_ring)

        for i in list(self.mem_reg_pool.keys()):
            if self.mem_reg_pool[i] not in ([], None):
                if self.typ == TestType.BLK:
                    hdr_raw = await self.mem_reg_pool[i][0].read(0, 16, force=True)
                    hdr = VirtioBlkOuthdr().unpack(hdr_raw[::-1])
                    id = hdr.ioprio >> 16
                    self.tb.virtio_net.blk.id_alllocator[self.qid].release_id(id)
                    del self.tb.virtio_net.blk.blk_exp_queues[self.qid][id]
                for j in self.mem_reg_pool[i]:
                    self.mem.free_region(j)
                del self.mem_reg_pool[i]
        for i in list(self.indirct_reg_pool.keys()):
            if self.indirct_reg_pool[i] is not None:
                self.mem.free_region(self.indirct_reg_pool[i])
                del self.indirct_reg_pool[i]
        for i in list(self.id_pool.keys()):
            if self.id_pool[i] not in ([], None):
                for j in self.id_pool[i]:
                    self.id_allocator.release_id(j)
                del self.id_pool[i]
        # if self.typ == TestType.BLK:
        #     # .id_alllocator[qid].release_id(id)
        #     # del blk.blk_exp_queues[qid][id]

        if self.msix_mem is not None:
            self.mem.free_region(self.msix_mem)

        self.used_idx_ci = 0
        self.avail_idx_sw = 0
        self.first_db = True

        self.log.debug(
            f"free_region vq:{VirtioVq.vq2str(self.vq)}  avail_ring_addr:{self.avail_ring.get_absolute_address(0):8x}  used_ring_addr:{self.used_ring.get_absolute_address(0):8x}  desc_tbl_addr:{self.desc_tbl.get_absolute_address(0):8x}  qsz:{self.qsz:8x}"
        )

        pass

    async def read_used_idx(self) -> int:
        return int.from_bytes(await self.used_ring.read(2, 2), byteorder="little")

    async def read_used_element(self, idx) -> VirtqUsedElement:
        idx = idx & (self.qsz - 1)
        element_data = await self.used_ring.read(4 + idx * 8, 8)
        return VirtqUsedElement().unpack(element_data[::-1])

    async def write_avail(self, idx, ring_id, defect: VirtioErrCode = VirtioErrCode.VIRTIO_ERR_CODE_NONE) -> None:
        idx = idx & (self.qsz - 1)
        pcie_flag = False
        # if defect not in [VirtioErrCode.VIRTIO_ERR_CODE_NONE, None]:
        # self.log.debug(f"write_avail {VirtioVq.vq2str(self.vq)} idx {idx} ring_id {ring_id} defect: {defect}")

        if defect == VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE:
            ring_id = self.qsz
            if self.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                self.err_info = defect
        if defect == VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR:
            pcie_flag = True
            if self.err_info is VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                self.err_info = defect
            self.err_info_option.append(VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR)

        # self.log.debug("write_avail {} addr {} idx {}".format(VirtioVq.vq2str(self.vq), self.avail_ring.get_absolute_address(0), idx))
        if pcie_flag:
            await self.avail_ring.write(4 + idx * 2, ring_id.to_bytes(2, byteorder="little"), defect_injection=1)
        else:
            await self.avail_ring.write(4 + idx * 2, ring_id.to_bytes(2, byteorder="little"))

    async def write_avail_idx(self, idx, defect=None) -> None:
        # if self.status != VirtioStatus.DOING and self.status != VirtioStatus.STARTING:
        #     return
        pcie_flag = False

        if defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR:
            pcie_flag = True
            self.err_info_option.append(defect)
        if defect == VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX:
            idx = idx + self.qsz
            self.err_info_option.append(defect)

        self.log.debug("write_avail_idx {} addr {} idx {}".format(VirtioVq.vq2str(self.vq), self.avail_ring.get_absolute_address(0), idx))
        if pcie_flag:
            await self.avail_ring.write(2, idx.to_bytes(2, byteorder="little"), defect_injection=1)
        else:
            await self.avail_ring.write(2, idx.to_bytes(2, byteorder="little"))
        if self.first_db:
            self.first_db = False
            await self.soc_notify_queues.put(self.vq)
            self.log.debug(f"soc_notify_put")
        await self.doorbell_queue.put(self.vq)

    async def write_desc(self, id, desc, indirct_mem_reg=None, pcie_err_flag=0) -> None:
        if self.status != VirtioStatus.DOING and self.status != VirtioStatus.STARTING:
            return
        if indirct_mem_reg == None:
            if pcie_err_flag:
                await self.desc_tbl.write(id * 16, desc.build()[::-1], defect_injection=1)
            else:
                await self.desc_tbl.write(id * 16, desc.build()[::-1])
            # self.log.debug(f"id:{id} desc:{desc} mem_reg:{self.desc_tbl.get_absolute_address(0):x} addr:{desc.addr:x}")
        else:
            if pcie_err_flag:
                await indirct_mem_reg.write(id * 16, desc.build()[::-1], defect_injection=1)
            else:
                await indirct_mem_reg.write(id * 16, desc.build()[::-1])
            # self.log.debug(f"id:{id} desc:{desc} indirct_mem_reg:{indirct_mem_reg.get_absolute_address(0):x} addr:{desc.addr:x}")

    def gen_a_desc(self, desc_addr, desc_len=0, flags_indirect=0, next=0, flags_next=0, defect=None, flags_write=None):
        '''
        if defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE:
            flags_write = 0
        elif defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO:
            flags_write = 1
        elif defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_WRITE_MUST_BE_ZERO:
            flags_write = 1
        else:
            flags_write = TestType.NETRX == self.typ and flags_indirect == 0
        '''
        if flags_write is None:
            flags_write = TestType.NETRX == self.typ and flags_indirect == 0
        return VirtqDesc(addr=desc_addr, len=desc_len, flags_indirect=flags_indirect, flags_next=flags_next, flags_write=flags_write, next=next)

    def err_info_gen_list(self, min_err_num: int = 1, max_err_num: int = 3) -> list[VirtioErrCode]:

        ERR_WEIGHTS = {VirtioErrCode.VIRTIO_ERR_CODE_NONE: 90}
        if self.typ == TestType.NETTX:
            ERR_WEIGHTS = {
                VirtioErrCode.VIRTIO_ERR_CODE_NONE: 0.001,
                VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE: 1,
                # VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_NETTX_PCIE_ERR: 1,
            }
        if self.typ == TestType.NETRX:
            ERR_WEIGHTS = {
                VirtioErrCode.VIRTIO_ERR_CODE_NONE: 0.001,
                VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE: 1,
                # VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR: 1,
            }
        if self.typ == TestType.BLK:
            ERR_WEIGHTS = {
                VirtioErrCode.VIRTIO_ERR_CODE_NONE: 0.001,
                VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE: 1,
                # VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE: 1,
                VirtioErrCode.VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR: 1,
            }

        none_item = VirtioErrCode.VIRTIO_ERR_CODE_NONE
        if not self.cfg.fault_injection:
            return [none_item]
        other_items = [err for err in ERR_WEIGHTS if err != none_item]
        other_weights = [ERR_WEIGHTS[err] for err in other_items]
        total_other_weight = sum(other_weights)
        # none_weight =  ERR_WEIGHTS[none_item]
        none_weight = ERR_WEIGHTS[none_item] if none_item in ERR_WEIGHTS else total_other_weight

        error = random.choices([False, True], weights=[none_weight, total_other_weight], k=1)[0]
        if error:
            err_count = random.randint(min(min_err_num, len(other_items)), min(max_err_num, len(other_items)))
            # err_info_list = random.sample(population=other_items, k=err_count, counts=other_weights)
            err_info_list = random.choices(population=other_items, weights=other_weights, k=err_count)
        else:
            return [none_item]

        mutually_exclusive_errs = {VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR, VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX}
        selected_exclusive_errs = [err for err in err_info_list if err in mutually_exclusive_errs]

        while len(selected_exclusive_errs) >= 2:
            err_to_remove = random.choice(selected_exclusive_errs)
            err_info_list.remove(err_to_remove)
            selected_exclusive_errs = [err for err in err_info_list if err in mutually_exclusive_errs]

        # self.log.error(f"err_info_list: {err_info_list}")
        return err_info_list

    def err_info_choose(self) -> Optional[VirtioErrCode]:
        if not self.err_info_list:
            return None

        if random.random() <= 0.1:
            chosen_err = random.choice(self.err_info_list)
            self.err_info_list.remove(chosen_err)
            return chosen_err

        return None

    async def msix_func(self, address, data, **kwargs):
        if self.msix_en:
            self.msix_event.set()
