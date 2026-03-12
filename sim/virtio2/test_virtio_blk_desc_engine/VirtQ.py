import sys
import math
import random
import cocotb
from cocotb.queue import Queue
from define_virtio_blk_desc_engine import *
from cocotb.triggers import RisingEdge, Timer, Event
from cocotb.utils import get_sim_time

sys.path.append('../../common')
from bus.tlp_adap_dma_bus import DmaReadBus, Desc
from monitors.tlp_adap_dma_bus import DmaRam

class vQueue:
    def __init__(self, log, mem, vq, typ, depth, cfg, indirct_en=0, bdf=0, dev_id=0, head_slot=0, head_slot_vld=0, tail_slot=0, avail_idx=0, limit=6):
        self._cfg = cfg
        self.log = log
        self._mem = mem
        self._vq = vq
        self._typ = typ
        self._depth = depth
        self._depth_log2 = int(math.log2(self._depth))
        self._indirct_en = indirct_en
        self._bdf = bdf
        self._dev_id = dev_id
        self._head_slot = head_slot
        self._head_slot_vld = head_slot_vld
        self._tail_slot = tail_slot
        self._desc_tbl = self._mem.alloc_region(self._depth * 16, bdf=self._bdf)
        self._desc_idx_pool = [i for i in range(self._depth)]
        self._avail_idx = 0
        self._forced_shutdown = 0
        self._limit = limit
        self._avail_ring = Queue(maxsize=self._depth)
        self._local_ring = Queue(maxsize=16)
        self.ref_results = []
        self.forced_shutdown_event = Event()
        self._forced_shutdown_tim = 0
        self._wait_finish = False
        self._wait_finish_event = Event()

    def gen_a_desc(self, desc_addr=None, desc_len=0, flags_indirect=0, next=0, flags_next=0, defect=None):
        if defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE:
            flags_write = 0
        elif defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO:
            flags_write = 1
        else:
            flags_write = TestType.NETRX == self._typ and flags_indirect == 0
        if self._typ ==TestType.BLK:
            flags_write = randbit(1)
        if desc_addr == None:
            desc_addr = random.randint(0, 2**64 - 1)
        return VirtqDesc(addr=desc_addr, len=desc_len, flags_indirect=flags_indirect, flags_next=flags_next, flags_write=flags_write, next=next)

    async def gen_indirect_split(self, seq_num, chain_len, pkt_len, defect):
        idxs = []
        descs = []
        ring_id = None
        indirct_ptr = random.randint(0, min(self._cfg.max_indirct_ptr, chain_len - 1))

        if (
            defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO
            or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO
        ):  # indirct 那一包
            defect_desc_idx = indirct_ptr
        elif (
            defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE
        ):  # direct
            if indirct_ptr == 0:  # 如果第0个就是indirct，他的next就没有意义了
                indirct_ptr = indirct_ptr + 1
            defect_desc_idx = random.randint(0, indirct_ptr - 1)
        elif (
            defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC
        ):  # indirect
            defect_desc_idx = random.randint(indirct_ptr + 1, chain_len)
        elif (
            defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE
            or defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO
            or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE
        ):  # 除了indirect 那一包
            defect_desc_idx = random.randint(0, chain_len)
            if defect_desc_idx == indirct_ptr:
                defect_desc_idx = defect_desc_idx + 1
        elif (
            defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE
            or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE
            or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE
        ):  # indirct 除了 indirct的最后一包
            if indirct_ptr == chain_len - 1:
                indirct_ptr = indirct_ptr - 1
            defect_desc_idx = random.randint(indirct_ptr + 1, chain_len - 1)
        else:
            defect_desc_idx = random.randint(0, chain_len)
        self.log.info("indirct_ptr {} {} {}".format(indirct_ptr, defect, defect_desc_idx))
        while len(self._desc_idx_pool) < indirct_ptr + 1:
            await Timer(1, "us")

        for i in range(indirct_ptr + 1):
            id = random.randint(0, len(self._desc_idx_pool) - 1)
            idxs.append(self._desc_idx_pool.pop(id))
        if (
            defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE
            or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE
        ):
            if chain_len - indirct_ptr > self._cfg.max_indirct_desc_size // 2:
                indirct_desc_buf_len = (chain_len - indirct_ptr) * 16
            else:
                indirct_desc_buf_len = random.randint(chain_len - indirct_ptr, self._cfg.max_indirct_desc_size // 2) * 16
        else:
            if chain_len - indirct_ptr > self._cfg.max_indirct_desc_size:
                indirct_desc_buf_len = (chain_len - indirct_ptr) * 16
            else:
                indirct_desc_buf_len = random.randint(chain_len - indirct_ptr, self._cfg.max_indirct_desc_size) * 16
        indirct_desc_buf = self._mem.alloc_region(indirct_desc_buf_len, bdf=self._bdf)

        for i in range(indirct_ptr + 1):
            idx = idxs[i]
            if ring_id == None:
                ring_id = idx
            if i == indirct_ptr:
                next = random.randint(0, 65535)
                if (
                    defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO
                    or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO
                ):
                    flags_next = 1
                else:
                    flags_next = 0
                flags_indirect = 1
                desc_addr = indirct_desc_buf.get_absolute_address(0)
                desc_len = indirct_desc_buf_len
            else:
                if (
                    defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE
                    or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE
                ):
                    next = random.randint(self._depth, 65535)
                else:
                    next = idxs[i + 1]
                flags_next = 1
                flags_indirect = 0
                desc_addr = None
                desc_len = pkt_len // chain_len

            if (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO
            ) and defect_desc_idx == i:
                desc_len = 0
            elif (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE
                or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE
            ) and defect_desc_idx == i:
                desc_len = random.randint(4097, 2**32 - 1)

            desc = self.gen_a_desc(
                desc_addr=desc_addr,
                desc_len=desc_len,
                flags_indirect=flags_indirect,
                next=next,
                flags_next=flags_next,
                defect=defect if defect_desc_idx == i else None,
            )
            self.log.debug(
                "desc write{} vq{} seq_num {} id {} desc {} idx {}".format(
                    "*" if defect_desc_idx == i and defect != None else "", vq_str(self._vq), seq_num, idx, desc.show(dump=True), i
                )
            )
            if defect_desc_idx == i and (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR
            ):
                await self._desc_tbl.write(16 * idx, desc.build()[::-1], defect_injection=1)
            else:
                await self._desc_tbl.write(16 * idx, desc.build()[::-1])
            if i != indirct_ptr:
                descs.append(desc)

        indirect_idxs = [0]
        if chain_len - indirct_ptr - 1 > 0:
            if random.randint(0, 100) > 50:
                indirect_idxs = indirect_idxs + random.sample([i for i in range(1, chain_len - indirct_ptr)], chain_len - indirct_ptr - 1)
            else:
                indirect_idxs = indirect_idxs + random.sample(
                    [i for i in range(1, random.randint(chain_len - indirct_ptr, indirct_desc_buf_len // 16))], chain_len - indirct_ptr - 1
                )
        # ups the odds of sequential desc
        if random.randint(0, 100) > 40:
            indirect_idxs.sort()

        indirect_desc_size = chain_len - indirct_ptr
        for i in range(indirect_desc_size):
            idx = indirect_idxs[i]
            if i == indirect_desc_size - 1:
                next = random.randint(0, 65535)
                flags_next = 0
                desc_len = pkt_len - pkt_len // chain_len * (chain_len - 1)
            else:
                if (
                    defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE
                    or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE
                ) and defect_desc_idx == i + indirct_ptr + 1:
                    next = random.randint(indirct_desc_buf_len // 16 + 1, 65535)
                elif defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE and defect_desc_idx == i + indirct_ptr + 1:
                    next = indirect_idxs[i]
                else:
                    next = indirect_idxs[i + 1]

                flags_next = 1
                desc_len = pkt_len // chain_len

            if (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO
            ) and defect_desc_idx == i + indirct_ptr + 1:
                desc_len = 0
            elif (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE
                or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE
            ) and defect_desc_idx == i + indirct_ptr + 1:
                desc_len = random.randint(4097, 2**32 - 1)

            if (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC
                or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC
            ):
                flags_indirect = 1
            else:
                flags_indirect = 0

            desc = self.gen_a_desc(
                desc_addr=None,
                desc_len=desc_len,
                flags_indirect=flags_indirect,
                next=next,
                flags_next=flags_next,
                defect=defect if defect_desc_idx == i + indirct_ptr + 1 else None,
            )
            self.log.debug(
                "desc(indirct) write{} vq{} seq_num {} id {} desc {} idx {}".format(
                    "*" if defect_desc_idx == i + indirct_ptr + 1 and defect != None else "",
                    vq_str(self._vq),
                    seq_num,
                    idx,
                    desc.show(dump=True),
                    i + indirct_ptr + 1,
                )
            )
            if defect_desc_idx == i + indirct_ptr + 1 and (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR
            ):
                await indirct_desc_buf.write(16 * idx, desc.build()[::-1], defect_injection=1)
            else:
                await indirct_desc_buf.write(16 * idx, desc.build()[::-1])
            descs.append(desc)
        return idxs, ring_id, descs, indirct_desc_buf

    async def gen_direct_split(self, seq_num, chain_len, pkt_len, defect):
        idxs = []
        descs = []
        ring_id = None
        while len(self._desc_idx_pool) < chain_len:
            await Timer(1, "us")

        defect_desc_idx = random.randint(0, chain_len - 1)

        if (
            defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE
            or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE
            or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE
        ) and defect_desc_idx == chain_len - 1:
            defect_desc_idx = defect_desc_idx - 1

        for i in range(chain_len):
            id = random.randint(0, len(self._desc_idx_pool) - 1)
            idxs.append(self._desc_idx_pool.pop(id))

        for i in range(chain_len):
            idx = idxs[i]
            if ring_id == None:
                ring_id = idx
            if i == chain_len - 1:
                next = random.randint(0, 65535)
                flags_next = 0
                desc_len = pkt_len - pkt_len // chain_len * (chain_len - 1)
            else:
                if (
                    defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE
                    or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE
                ) and defect_desc_idx == i:
                    next = random.randint(self._depth, 65535)
                elif defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE and defect_desc_idx == i:
                    next = idx
                else:
                    next = idxs[i + 1]
                flags_next = 1
                desc_len = pkt_len // chain_len
            if (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO
            ) and defect_desc_idx == i:
                desc_len = 0
            elif (defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE) and defect_desc_idx == i:
                desc_len = random.randint(4097, 2**32 - 1)
            if (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT
            ) and defect_desc_idx == i:
                flags_indirect = 1
            else:
                flags_indirect = 0
            desc = self.gen_a_desc(
                desc_addr=None,
                desc_len=desc_len,
                flags_indirect=flags_indirect,
                next=next,
                flags_next=flags_next,
                defect=defect if defect_desc_idx == i else None,
            )
            self.log.debug(
                "desc write {} vq{} seq_num {} id {} desc {} idx{}".format(
                    "*" if defect_desc_idx == i and defect != None else "", vq_str(self._vq), seq_num, idx, desc.show(dump=True), i
                )
            )
            if defect_desc_idx == i and (
                defect == DefectType.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR
            ):
                await self._desc_tbl.write(16 * idx, desc.build()[::-1], defect_injection=1)
            else:
                await self._desc_tbl.write(16 * idx, desc.build()[::-1])
            descs.append(desc)

        return idxs, ring_id, descs, None

    def make_defect_injection(self, cfg):
        defect_injection_list = [d[0] for d in cfg.defect_injection]
        defect_weight_list = [d[1] for d in cfg.defect_injection]

        def remove_defect(defect):
            indices_to_remove = [i for i, d in enumerate(defect_injection_list) if d == defect]
            for i in sorted(indices_to_remove, reverse=True):
                del defect_injection_list[i]
                del defect_weight_list[i]
            return defect_injection_list, defect_weight_list

        # if self._typ == TestType.NETRX:
        #     defect_injection_list = remove_defect(DefectType.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO)
        #     defect_injection_list = remove_defect(DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE)
        # elif self._typ == TestType.NETTX:
        #     defect_injection_list = remove_defect(DefectType.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE)

        if not self._indirct_en:
            defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC)
            defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE)
            defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO)
            defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE)
            defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO)
            defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC)

        else:
            # defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE)  # 暂时
            defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT)
            defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE)
            defect_injection_list, defect_weight_list = remove_defect(DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT)

        if len(defect_injection_list) > 0 and random.randint(0, 100) < 20:
            defect = random.choices(defect_injection_list, defect_weight_list)[0]
        else:
            defect = None
        return defect

    async def gen_a_chain(self, cfg, seq_num):
        pkt_id = seq_num % 1024  # random.randint(0, 1023)
        # if not self._indirct_en:
        # pkt_len = random.randint(1, self._cfg.max_size * self._cfg.max_chain_num)
        indirct_desc_buf = None
        defect = self.make_defect_injection(cfg)
        if defect is not None:
            err = ErrInfo(fatal=1, err_code=defect)
        else:
            err = ErrInfo(fatal=0, err_code=0)

        if defect in [DefectType.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE, DefectType.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR]:
            avail_err = ErrInfo(fatal=1, err_code=defect)
        else:
            avail_err = ErrInfo(fatal=0, err_code=0)

        if self._indirct_en:
            max_chain_num = self._cfg.max_chain_num
        else:
            max_chain_num = min(self._depth, self._cfg.max_chain_num)
        min_chain_num = max(2, self._cfg.min_chain_num)
        if min_chain_num > max_chain_num:
            min_chain_num = max_chain_num

        if defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE:
            # pkt_len = random.randint(1, self._cfg.max_size)
            chain_len = 1
        else:
            # min_chain_num = max((pkt_len + 4095) // 4096, self._cfg.min_chain_num)
            chain_len = random.randint(min_chain_num, max_chain_num)
            # pkt_len = max(chain_len, pkt_len)

        if defect != DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE:
            avg_len = random.randint(1, self._cfg.max_size)
            base_len = (chain_len - 1) * avg_len
            remainder = random.randint(avg_len, self._cfg.max_size)
            pkt_len = base_len + remainder
        else:
            pkt_len = random.randint(chain_len * self._cfg.max_size + 1, chain_len * (self._cfg.max_size + 1) - 1)
        # pkt_len = random.randint(self._cfg.max_size + 1, 8391936)
        # chain_len = max(math.ceil(pkt_len / self._cfg.max_size), chain_len)

        # if (
        #     defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE
        #     or defect == DefectType.VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE
        # ) and chain_len == 1:
        #     chain_len = chain_len + 1

        self.log.info(
            "gen_a_chain vq{} seq_num {} pkt_id {} chain_len {} pkt_len {} defect {} indirect {} err {}".format(
                vq_str(self._vq),
                seq_num,
                pkt_id,
                chain_len,
                pkt_len,
                defect,
                self._indirct_en,
                err.show(dump=True),
            )
        )
        ring_id = None
        descs = []
        idxs = []
        if not self._indirct_en:
            idxs, ring_id, descs, indirct_desc_buf = await self.gen_direct_split(seq_num, chain_len, pkt_len, defect)
        else:
            idxs, ring_id, descs, indirct_desc_buf = await self.gen_indirect_split(seq_num, chain_len, pkt_len, defect)
        await self._avail_ring.put((ring_id, self._avail_idx, pkt_id, avail_err))
        self.log.debug("_avail_ring put vq{} avail_idx {}".format(vq_str(self._vq), self._avail_idx))
        if avail_err.err_code == 0:
            self.ref_results.append(RefResult(pkt_id, ring_id, self._avail_idx, pkt_len, descs, err, seq_num, idxs, indirct_desc_buf))
        else:
            self._desc_idx_pool = self._desc_idx_pool + idxs
        self._avail_idx = (self._avail_idx + 1) & (self._depth - 1)
        if cfg.forced_shutdown and random.randint(0, 100) < 10:
            self._forced_shutdown = True
            self._forced_shutdown_tim = get_sim_time("ns")
            while self._forced_shutdown:
                await self.forced_shutdown_event.wait()
                self.forced_shutdown_event.clear() 
                await Timer(1, "ns")
                self._forced_shutdown = self.forced_shutdown_event.data != seq_num
        elif cfg.forced_shutdown and not self._forced_shutdown and random.randint(0, 100) < 10:
            self._wait_finish = True
            self.log.debug(f"wait_finish qid: {vq_str(self._vq)} seq_num: {seq_num}")
            while self._wait_finish:
                await self._wait_finish_event.wait()
                self._wait_finish_event.clear() 
                self.log.debug(f"wait_finish qid: {vq_str(self._vq)} seq_num: {seq_num} now:{self._wait_finish_event.data}")
                await Timer(1, "ns")
                self._wait_finish = self._wait_finish_event.data != seq_num
            self.log.debug(f"wait_finish_done qid: {vq_str(self._vq)} seq_num: {seq_num}")
        await Timer(100, "ns")


class VirtQ:

    def __init__(self, mod, mem, log, dut):
        self.log = log
        self._mem = mem
        self._mod = mod
        self._dut = dut
        self.dmaDescIf = DmaRam(None, DmaReadBus.from_prefix(dut, "desc_dma"), dut.clk, dut.rst, mem=mem)
        # self.ctxInfoRdTbl = CtxInfoRdTbl(
        #     CtxInfoRdReqBus.from_prefix(dut, mod + "_ctx_info"), CtxInfoRdRspBus.from_prefix(dut, mod + "_ctx_info"), None, dut.clk, dut.rst
        # )

        # def _ctxInfoRdCallback(req_obj):
        #     vq = int(req_obj.rd_req_vq)
        #     if vq not in self._q.keys():
        #         raise ValueError("The queue(vq:{}) is not exists".format(vq))
        #     rsp = CtxInfoRdRspTransaction()
        #     rsp.rd_rsp_desc_tbl_addr = self._q[vq]._desc_tbl.get_absolute_address(0)
        #     rsp.rd_rsp_qdepth = self._q[vq]._depth_log2
        #     rsp.rd_rsp_forced_shutdown = self._q[vq]._forced_shutdown
        #     rsp.rd_rsp_indirct_support = self._q[vq]._indirct_en
        #     rsp.rd_rsp_bdf = self._q[vq]._bdf
        #     return rsp

        # self.ctxInfoRdTbl.set_callback(_ctxInfoRdCallback)

        # self.ctxSlotChainTbl = CtxSlotChainTbl(
        #     CtxSlotChainRdReqBus.from_prefix(dut, mod + "_ctx_slot_chain"),
        #     CtxSlotChainRdRspBus.from_prefix(dut, mod + "_ctx_slot_chain"),
        #     CtxSlotChainWrBus.from_prefix(dut, mod + "_ctx_slot_chain"),
        #     dut.clk,
        #     dut.rst,
        # )

        # def _ctxSlotChainWrCallback(req_obj):
        #     vq = int(req_obj.wr_vq)
        #     if vq not in self._q.keys():
        #         raise ValueError("The queue(vq:{}) is not exists".format(vq))
        #     self._q[vq]._head_slot = int(req_obj.wr_head_slot)
        #     self._q[vq]._head_slot_vld = int(req_obj.wr_head_slot_vld)
        #     self._q[vq]._tail_slot = int(req_obj.wr_tail_slot)
        #     return

        # self.ctxSlotChainTbl.set_wr_callback(_ctxSlotChainWrCallback)

        # def _ctxSlotChainRdCallback(req_obj):
        #     vq = int(req_obj.rd_req_vq)
        #     if vq not in self._q.keys():
        #         raise ValueError("The queue(vq:{}) is not exists".format(vq))
        #     rsp = CtxSlotChainRdRspTransaction()
        #     rsp.rd_rsp_head_slot = self._q[vq]._head_slot
        #     rsp.rd_rsp_head_slot_vld = self._q[vq]._head_slot_vld
        #     rsp.rd_rsp_tail_slot = self._q[vq]._tail_slot
        #     return rsp

        # self.ctxSlotChainTbl.set_callback(_ctxSlotChainRdCallback)

        # self.allocSlotReqSource = AllocSlotReqSource(AllocSlotReqBus.from_prefix(dut, mod + "_alloc_slot_req"), dut.clk, dut.rst)
        # self.allocSlotRspSink = AllocSlotRspSink(AllocSlotRspBus.from_prefix(dut, mod + "_alloc_slot_rsp"), dut.clk, dut.rst)

        # self.availIdReqSink = AvailIdReqSink(AvailIdReqBus.from_prefix(dut, mod + "_avail_id_req"), dut.clk, dut.rst)
        # self.availIdRspSource = AvailIdRspSource(AvailIdRspBus.from_prefix(dut, mod + "_avail_id_rsp"), dut.clk, dut.rst)

        # self.descRspSink = DescRspSink(DescRspBus.from_prefix(dut, mod + "_desc_rsp"), dut.clk, dut.rst)

        # if mod == "net_tx":
        #     self.limitPerQueueRdTbl = LimitPerQueueRdTbl(
        #         LimitPerQueueRdReqBus.from_prefix(dut, mod + "_limit_per_queue"),
        #         LimitPerQueueRdRspBus.from_prefix(dut, mod + "_limit_per_queue"),
        #         None,
        #         dut.clk,
        #         dut.rst,
        #     )

        #     def _limitPerQueueCallback(req_obj):
        #         qid = int(req_obj.rd_req_qid)
        #         typ = TestType.NETTX
        #         vq = qid2vq(qid, typ)
        #         if vq not in self._q.keys():
        #             raise ValueError("The queue(vq:{}) is not exists".format(vq))
        #         rsp = CtxInfoRdRspTransaction()
        #         rsp.rd_rsp_dat = self._q[vq]._limit
        #         return rsp

        #     self.limitPerQueueRdTbl.set_callback(_limitPerQueueCallback)

        #     self.limitPerDevRdTbl = LimitPerDevRdTbl(
        #         LimitPerDevRdReqBus.from_prefix(dut, mod + "_limit_per_dev"),
        #         LimitPerDevRdRspBus.from_prefix(dut, mod + "_limit_per_dev"),
        #         None,
        #         dut.clk,
        #         dut.rst,
        #     )

        #     def _limitPerDevCallback(req_obj):
        #         dev_id = int(req_obj.rd_req_dev_id)
        #         if dev_id not in self._dev_ctx.keys():
        #             raise ValueError("The dev(dev_id:{}) is not exists".format(dev_id))
        #         rsp = CtxInfoRdRspTransaction()
        #         rsp.rd_rsp_dat = self._dev_ctx[dev_id]._limit
        #         return rsp

        #     self.limitPerDevRdTbl.set_callback(_limitPerDevCallback)

        self.slotCplQueue = Queue(maxsize=32)
        # self._dev_ctx = {}
        self._virtio_sch = {}
        # for i in range(1024):
        #     self._dev_ctx[i] = DevCtx(24)
        self._q = {}
        cocotb.start_soon(self._forcedShutdownDmaMonitorThd())
        # cocotb.start_soon(self._ringEngReqIdThd())
        # cocotb.start_soon(self._ringEngRspIdThd())
        # cocotb.start_soon(self._allocSlotThd())
        # cocotb.start_soon(self._descRspThd())

    def set_queue(self, qid, cfg, depth=32768, indirct_en=0, bdf=None, dev_id=None):
        if bdf == None:
            bdf = random.randint(0, 65535)
        if dev_id == None:
            dev_id = random.randint(0, 1023)
        typ = TestType.BLK
        vq = qid2vq(qid, typ)
        self._q[vq] = vQueue(self.log, self._mem, vq, typ, depth, cfg, indirct_en, bdf)
        # self._virtio_sch[qid] = []

    async def gen_a_pkt(self, qid, cfg, seq_num=0):
        typ = TestType.BLK
        await self._q[qid2vq(qid, typ)].gen_a_chain(cfg, seq_num)

    async def _forcedShutdownDmaMonitorThd(self):
        vq_bit_sz = len(VirtioVq()) * 8 - VirtioVq().padding_size
        vld = self.dmaDescIf.rd_req_channel.vld

        def get_dma_info():
            obj = self.dmaDescIf.rd_req_channel._transaction_obj()
            self.dmaDescIf.rd_req_channel.bus.sample(obj)
            desc = Desc().unpack(obj.rd_req_desc)
            vq_int = int(int(desc.rd2rsp_loop) >> 2 & (2**vq_bit_sz - 1))
            return VirtioVq().unpack(vq_int).pack(), desc

        while True:
            if vld.value:
                vq, desc = get_dma_info()
                q = self._q[vq]
                if q._forced_shutdown and get_sim_time("ns") - q._forced_shutdown_tim > 20:  # The FSM has 4 states.
                    raise ValueError("Illegal DMA mismatch vq{} is forced_shutdown\n Illegal DMA info:{}".format(vq_str(vq), desc.show(dump=True)))
            await RisingEdge(self._dut.clk)

    # async def _ringEngReqIdThd(self):
    #     while True:
    #         for id, queue in self._q.items():
    #             if not queue._avail_ring.empty() and not queue._local_ring.full():
    #                 qid, typ = vq2qid(id)
    #                 (ring_id, avail_idx, pkt_id, err) = await queue._avail_ring.get()
    #                 await queue._local_ring.put((ring_id, avail_idx, err))
    #                 self.log.debug("_local_ring put vq{} avail_idx {}".format(vq_str(id), avail_idx))
    #                 if typ == TestType.NETRX:
    #                     self._virtio_sch[qid].append((typ, pkt_id))
    #                 else:
    #                     if len(self._virtio_sch[qid]) == 0:
    #                         self._virtio_sch[qid].append((typ, pkt_id))
    #         await Timer(1, "ns")

    # async def _ringEngRspIdThd(self):
    #     while True:
    #         req = await self.availIdReqSink.recv()
    #         vq = VirtioVq().unpack(int(req.vq))

    #         class RingEngRspElem(NamedTuple):
    #             ring_id: int
    #             avail_idx: int
    #             err: ErrInfo

    #         rspElems = [RingEngRspElem(0, 0, ErrInfo(fatal=0, err_code=0))]
    #         q_stat_doing = True
    #         q_stat_stopping = False
    #         if random.randint(0, 100) < 20:  # stoping
    #             local_ring_empty = random.choice([False, True])
    #             avail_ring_empty = random.choice([False, True])
    #             rspElems = [RingEngRspElem(random.randint(0, 65536), random.randint(0, 65536), ErrInfo(fatal=0, err_code=0))]
    #             q_stat_doing = False
    #             q_stat_stopping = True
    #         elif random.randint(0, 100) < 10:  # local ring empty
    #             local_ring_empty = True
    #             avail_ring_empty = False  # random.randint(0, 100) < 40
    #         elif random.randint(0, 100) < 4:  # avail_ring_empty
    #             local_ring_empty = True
    #             avail_ring_empty = False
    #         elif not self._q[qid2vq(vq.qid, vq.typ)]._local_ring.empty():
    #             local_ring_empty = False
    #             avail_ring_empty = False
    #             nid = min(self._q[qid2vq(vq.qid, vq.typ)]._local_ring.qsize(), int(req.nid))
    #             rspElems = []
    #             for i in range(nid):
    #                 (ring_id, avail_idx, err) = await self._q[qid2vq(vq.qid, vq.typ)]._local_ring.get()
    #                 if (
    #                     err.err_code is not DefectType.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE
    #                     and err.err_code is not DefectType.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR
    #                 ):
    #                     err = ErrInfo(fatal=0, err_code=0)
    #                 self.log.debug("_local_ring get vq(qid:{},type:{}) avail_idx {}".format(vq.qid, vq.typ, avail_idx))
    #                 rspElems.append(RingEngRspElem(ring_id, avail_idx, err))
    #         else:
    #             avail_ring_empty = self._q[qid2vq(vq.qid, vq.typ)]._avail_ring.empty()
    #             local_ring_empty = True
    #         for i in range(len(rspElems)):
    #             elem = rspElems[i]
    #             obj = self.availIdRspSource._transaction_obj()
    #             rsp = AvailIdRspDat(
    #                 vq=req.vq,
    #                 id=elem.ring_id,
    #                 local_ring_empty=local_ring_empty,
    #                 avail_ring_empty=avail_ring_empty,
    #                 q_stat_doing=q_stat_doing,
    #                 q_stat_stopping=q_stat_stopping,
    #                 avail_idx=elem.avail_idx,
    #                 err_info=elem.err.pack(),
    #             )
    #             obj.dat = rsp.pack()
    #             obj.eop = i == len(rspElems) - 1
    #             self.log.debug("availIdRspSource send vq{} eop:{} rsp:{}".format(vq_str(int(req.vq)), obj.eop, rsp.show(dump=True)))
    #             await self.availIdRspSource.send(obj)

    # async def _allocSlotThd(self):
    #     hold_pkt = {}
    #     while True:
    #         for qid in self._virtio_sch.keys():
    #             if qid in hold_pkt.keys():
    #                 (qid, typ, pkt_id) = hold_pkt[qid]
    #                 if typ == TestType.NETRX:
    #                     del hold_pkt[qid]
    #             elif len(self._virtio_sch[qid]) > 0:
    #                 (typ, pkt_id) = self._virtio_sch[qid].pop(0)
    #             else:
    #                 pkt_id = None
    #             if pkt_id != None:
    #                 vq = qid2vq(qid, typ)
    #                 queue = self._q[vq]
    #                 obj = self.allocSlotReqSource._transaction_obj()
    #                 obj.vq = VirtioVq(typ=typ, qid=qid).pack()
    #                 obj.dev_id = queue._dev_id
    #                 obj.pkt_id = pkt_id

    #                 await self.allocSlotReqSource.send(obj)
    #                 self.log.debug("allocSlotReqSource send vq{} dev_id:{} pkt_id:{}".format(vq_str(int(obj.vq)), obj.dev_id, obj.pkt_id))
    #                 rsp = await self.allocSlotRspSink.recv()
    #                 allocSlotRsp = SlotRsp().unpack(rsp.dat)
    #                 self.log.debug("allocSlotRspSink recv vq{} rsp {}".format(vq_str(int(obj.vq)), allocSlotRsp.show(dump=True)))
    #                 err_info = ErrInfo().unpack(int(allocSlotRsp.err_info))
    #                 if not allocSlotRsp.ok and err_info.err_code == 0:
    #                     if (
    #                         not allocSlotRsp.desc_engine_limit
    #                         and allocSlotRsp.avail_ring_empty
    #                         and allocSlotRsp.q_stat_doing
    #                         and typ == TestType.NETTX
    #                     ):
    #                         if qid in hold_pkt.keys():
    #                             del hold_pkt[qid]
    #                     else:
    #                         hold_pkt[qid] = (qid, typ, pkt_id)
    #                 elif allocSlotRsp.ok and typ == TestType.NETTX:
    #                     hold_pkt[qid] = (qid, typ, pkt_id)
    #             else:
    #                 await Timer(1, "ns")
    #         await Timer(1, "ns")

    # async def _descRspThd(self):
    #     pkt_err_cnt = {}
    #     pkt_cnt = {}
    #     while True:
    #         eop = False
    #         sbd = None
    #         descs = []
    #         while not eop:
    #             descRsp = await self.descRspSink.recv()
    #             eop = descRsp.eop
    #             sbd = DescRspSbd().unpack(descRsp.sbd)
    #             # if sbd.vq != int(vq):
    #             #    raise ValueError("vq mismatch slotCpl {} rdDescRsp {}".format(vq.pack(), sbd.vq))
    #             err_info = ErrInfo().unpack(int(sbd.err_info))
    #             desc = VirtqDesc().unpack(descRsp.dat)
    #             descs.append(desc)
    #         q = self._q[sbd.vq]
    #         ref = q.ref_results.pop(0)
    #         if sbd.dev_id != q._dev_id:
    #             self.log.debug(
    #                 "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
    #                     vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)
    #                 )
    #             )
    #             raise ValueError("dev_id mismatch vq{} seq_num {} ctx {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, q._dev_id, sbd.dev_id))
    #         err_info = ErrInfo().unpack(int(sbd.err_info))
    #         if ref.err != err_info:
    #             raise ValueError(
    #                 "err mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(
    #                     vq_str(sbd.vq), ref.seq_num, ref.err.show(dump=True), err_info.show(dump=True)
    #                 )
    #             )
    #         if sbd.pkt_id != ref.pkt_id and q._typ == TestType.NETRX:
    #             self.log.debug(
    #                 "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
    #                     vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)
    #                 )
    #             )
    #             raise ValueError("pkt_id mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, ref.pkt_id, sbd.pkt_id))
    #         if sbd.avail_idx != ref.avail_idx:
    #             self.log.debug(
    #                 "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
    #                     vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)
    #                 )
    #             )
    #             raise ValueError(
    #                 "avail_idx mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, ref.avail_idx, sbd.avail_idx)
    #             )
    #         if sbd.ring_id != ref.ring_id:
    #             self.log.debug(
    #                 "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
    #                     vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)
    #                 )
    #             )
    #             raise ValueError("ring_id mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, ref.ring_id, sbd.ring_id))
    #         if err_info.err_code == DefectType.VIRTIO_ERR_CODE_NONE:
    #             if sbd.total_buf_length != ref.pkt_len:
    #                 self.log.debug(
    #                     "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
    #                         vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)
    #                     )
    #                 )
    #                 raise ValueError(
    #                     "pkt_len mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(vq_str(sbd.vq), ref.seq_num, ref.pkt_len, sbd.total_buf_length)
    #                 )
    #             if sbd.valid_desc_cnt != len(ref.descs):
    #                 self.log.debug(
    #                     "vq{} RefResult(pkt_id {} avail_idx {} ring_id {} total_buf_length {} valid_desc_cnt {})".format(
    #                         vq_str(sbd.vq), ref.pkt_id, ref.avail_idx, ref.ring_id, ref.pkt_len, len(ref.descs)
    #                     )
    #                 )
    #                 raise ValueError(
    #                     "valid_desc_cnt mismatch vq{} seq_num {} ref {} rdDescRsp {}".format(
    #                         vq_str(sbd.vq), ref.seq_num, len(ref.descs), sbd.valid_desc_cnt
    #                     )
    #                 )
    #             if ref.descs != descs:
    #                 for i in range(len(descs)):
    #                     if ref.descs[i] != descs[i]:
    #                         raise ValueError(
    #                             "desc mismatch vq{} seq_num {} NO.{} ref {} rdDescRsp {}".format(
    #                                 vq_str(sbd.vq), ref.seq_num, i, ref.descs[i].show(dump=True), descs[i].show(dump=True)
    #                             )
    #                         )
    #         if err_info.err_code != DefectType.VIRTIO_ERR_CODE_NONE:
    #             if sbd.vq not in pkt_err_cnt.keys():
    #                 pkt_cnt[sbd.vq] = 0
    #                 pkt_err_cnt[sbd.vq] = 1
    #             else:
    #                 pkt_err_cnt[sbd.vq] = pkt_err_cnt[sbd.vq] + 1
    #         else:
    #             if sbd.vq not in pkt_cnt.keys():
    #                 pkt_cnt[sbd.vq] = 1
    #                 pkt_err_cnt[sbd.vq] = 0
    #             else:
    #                 pkt_cnt[sbd.vq] = pkt_cnt[sbd.vq] + 1
    #         q._desc_idx_pool = q._desc_idx_pool + ref.idxs
    #         self.log.info("vq{} seq_num {} pass pkt_err_cnt {} pkt_cnt {}".format(vq_str(sbd.vq), ref.seq_num, pkt_err_cnt[sbd.vq], pkt_cnt[sbd.vq]))
    #         if ref.indirct_desc_buf != None:
    #             self._mem.free_region(ref.indirct_desc_buf)
    #         await Timer(1, "ns")


class DefectType:
    VIRTIO_ERR_CODE_NONE = 0x00
    VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE = 0x03
    VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR = 0x04
    VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE = 0x10
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE = 0x11
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE = 0x12
    VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT = 0x13
    VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO = 0x14
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC = 0x15
    VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO = 0x16
    VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE = 0x17
    VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN = 0x18
    VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR = 0x19
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE = 0x1A
    VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE = 0x1B

    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE = 0x40  # 64
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE = 0x41  # 65
    # VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE = 0x42
    VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT = 0x43
    VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO = 0x44  # 68
    VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC = 0x45
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO = 0x46  # 70
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE = 0x47  # 71
    VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR = 0x48  # 72
    VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE = 0x49  # 73
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE = 0x4A  # 74
