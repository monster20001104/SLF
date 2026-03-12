#!/usr/bin/env python3
################################################################################
#  文件名称 : virtio_pmd.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/10/21
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  10/21     Joe Jiang   初始化版本
################################################################################
import math
import cocotb
import logging
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, with_timeout
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from address_space import Pool, AddressSpace, MemoryRegion, IORegion
import random
from virtio_defines import *
from virtio_ctrl import VirtioCtrl
class VirtQ:
    def __init__(self, cfg, log, mem, virt_ctrl, doorbell_queue, soc_notify_queue, vq, qszWidth, max_len, msix_en,indirct_support, qos_en, qos_unit, bdf = 0, dev_id=0):
        self.cfg: Cfg           = cfg
        self.log                = log
        self.mem: Pool          = mem
        self.vq                 = vq
        self.virt_ctrl: VirtioCtrl = virt_ctrl
        self.soc_notify_queue   = soc_notify_queue
        self.doorbell_queue     = doorbell_queue
        self.qid, self.typ      = vq2qid(vq)
        self.qszWidth           = qszWidth
        self.qsz                = 2 ** qszWidth
        self.max_len            = max_len
        
        self.msix_mem: IORegion = None
        self.msix_event: Event  = Event()
        self.msix_en            = msix_en
        self.msix_mask          = 0
        self.msix_addr          = 0
        self.msix_data          = 0
        self.msix_threading     = None

        self.qos_en             = qos_en
        self.qos_unit           = qos_unit
        self.indirct_support    = indirct_support
        self.gen                = 0
        self.bdf                = bdf
        self.dev_id             = dev_id
        self.avail_idx_sw       = 0
        self.backend_used_idx   = 0
        self.used_idx_ci        = 0
        self.mem_reg_pool       = {}
        self.id_pool            = {}
        self.indirct_reg_pool   = {}
        self.id_allocator       = set(range(0, self.qsz))
        self.first_db           = True
        self.forced_shutdown_flag = False

    async def start(self, avail_idx=0):
        self.forced_shutdown_flag = False
        self.first_db           = True
        self.avail_ring         = self.mem.alloc_region(4 + 2 * self.qsz + 2, bdf=self.bdf, dev_id=self.dev_id)
        self.desc_tbl           = self.mem.alloc_region(16 * self.qsz, bdf=self.bdf, dev_id=self.dev_id)
        self.used_ring          = self.mem.alloc_region(4 + 8 * self.qsz + 2, bdf=self.bdf, dev_id=self.dev_id)
        avail_ring_addr         = self.avail_ring.get_absolute_address(0)
        used_ring_addr          = self.used_ring.get_absolute_address(0)
        desc_tbl_addr           = self.desc_tbl.get_absolute_address(0)
        if self.msix_en:
            self.msix_mem           = self.mem.alloc_region(4,bdf=self.bdf,dev_id=self.dev_id,region_type=IORegion)
            self.msix_mem.register_write_handler(self.msix_func)
            self.msix_addr          = self.msix_mem.get_absolute_address(0)
        self.avail_idx_sw       = avail_idx
        self.used_idx_ci        = avail_idx
        self.backend_used_idx   = avail_idx
        self.log.debug(f"alloc_region vq:{vq2qid(self.vq)[0]:4d}  avail_ring_addr:{avail_ring_addr:8x}  used_ring_addr:{used_ring_addr:8x}  desc_tbl_addr:{desc_tbl_addr:8x}  qsz:{self.qsz:8x}")
        await self.virt_ctrl.start(self.vq, self.qszWidth, avail_idx, avail_ring_addr, used_ring_addr, desc_tbl_addr, self.indirct_support, self.bdf, self.dev_id, self.max_len, self.gen, self.msix_addr, self.msix_data, self.msix_en, self.qos_en, self.qos_unit)

    async def stop(self, forced_shutdown=False, clear_res_func=None):
        await self.virt_ctrl.stop(self.vq, forced_shutdown)
        if forced_shutdown:
            self.forced_shutdown_flag = True
        await self.virt_ctrl.wait_stop_finish(self.vq)
        pending_hdrs = []
        if clear_res_func != None:
            pending_hdrs = await clear_res_func(self)
        self.gen = self.gen + 1
        await Timer(4, "us")
        self.mem.free_region(self.avail_ring )
        self.mem.free_region(self.desc_tbl   )
        self.mem.free_region(self.used_ring  )

        for i in list(self.mem_reg_pool.keys()):
            for j in self.mem_reg_pool[i]:
                self.mem.free_region(j)
            del self.mem_reg_pool[i]
        
        for i in list(self.indirct_reg_pool.keys()):
            if self.indirct_reg_pool[i] is not None:
                self.mem.free_region(self.indirct_reg_pool[i])
            del self.indirct_reg_pool[i]

        if self.msix_mem is not None:
            self.mem.free_region(self.msix_mem)

        self.log.debug(f"free_region vq:{vq2qid(self.vq)[0]:4d}  avail_ring_addr:{self.avail_ring.get_absolute_address(0):8x}  used_ring_addr:{self.used_ring.get_absolute_address(0):8x}  desc_tbl_addr:{self.desc_tbl.get_absolute_address(0):8x}  qsz:{self.qsz:8x}")
        return pending_hdrs
    async def alloc_id(self):
        while not self.id_allocator:
            await Timer(100, 'ns')
        idx = random.choice(list(self.id_allocator))
        self.id_allocator.remove(idx)
        return idx

    def release_id(self, idx):
        if idx < 0 or idx >= self.qsz:
            raise ValueError(f"[q{self.qid}]: ID {idx} out of range (0-{self.qsz})")
        if idx in self.id_allocator:
            raise ValueError(f"[q{self.qid}]: ID {idx} is already available.")
        self.id_allocator.add(idx)

    async def write_avail_idx(self, idx):
        await self.avail_ring.write(2, idx.to_bytes(2, byteorder="little"))
        self.log.debug("write_avail_idx {} addr {} idx {}".format(vq_str(self.vq), self.avail_ring.get_absolute_address(0), idx))
        if self.first_db:
            self.first_db = False
            await self.soc_notify_queue.put(self.vq)
        await self.doorbell_queue.put(self.vq)

    async def read_avail(self, idx):
        idx = idx & (self.qsz - 1)
        return int.from_bytes(await self.avail_ring.read(4+idx*2, 2), byteorder="little")

    async def write_avail(self, idx, ring_id):
        idx = idx & (self.qsz - 1)
        await self.avail_ring.write(4+idx*2, ring_id.to_bytes(2, byteorder="little"))

    async def write_desc(self, id, desc, indirct_mem_reg=None):
        if indirct_mem_reg == None:
            await self.desc_tbl.write(id*16, desc.build()[::-1])
        else:
            await indirct_mem_reg.write(id*16, desc.build()[::-1])

    async def read_used_idx(self):
        return int.from_bytes(await self.used_ring.read(2, 2), byteorder="little")

    async def read_used_element(self, idx):
        idx = idx & (self.qsz - 1)
        element_data = await self.used_ring.read(4+idx*8, 8)
        return VirtqUsedElement().unpack(element_data[::-1])

    def gen_a_desc(self, desc_addr, desc_len=0, flags_indirect=0, next=0, flags_next=0, flags_write=False, defect=None):
        flags_write = flags_write and flags_indirect == 0
        return VirtqDesc(addr=desc_addr, len=desc_len, flags_indirect=flags_indirect, flags_next=flags_next, flags_write=flags_write, next=next)

    async def set_msix_en(self, msix_en):
        if self.msix_mem == None and msix_en == 1:
            self.msix_mem           = self.mem.alloc_region(4,bdf=self.bdf,dev_id=self.dev_id,region_type=IORegion)
            self.msix_addr          = self.msix_mem.get_absolute_address(0)
            self.msix_mem.register_write_handler(self.msix_func)
            await self.virt_ctrl.set_msix_addr(vq=self.vq, msix_addr=self.msix_addr)

        await self.virt_ctrl.set_msix_en(vq=self.vq, msix_en=msix_en)
        self.msix_en = msix_en

    async def set_msix_mask(self, msix_mask):
        await self.virt_ctrl.set_msix_mask(vq=self.vq, msix_mask=msix_mask)
        self.msix_mask = msix_mask


    async def msix_func(self, address, data,** kwargs):
        self.msix_event.set()
        

class Virt:
    def __init__(self, cfg, log, mem, virt_ctrl, soc_notify_queues, doorbell_if):
        self.cfg: Cfg           = cfg
        self.log                = log
        self.mem: Pool          = mem
        self.virt_ctrl: VirtioCtrl   = virt_ctrl
        self.virtq: dict[int, VirtQ] = {}
        self.soc_notify_queues  = soc_notify_queues
        self.doorbell_queues    = {}
        self.doorbell_if        = doorbell_if
        self.blk_rsp_queues     = {}
        self.qos_update_queues     = {}
        self._msix_irs_cr   = {}

    def create_queue(self, vq, qszWidth, max_len, msix_en, indirct_support, qos_en, bdf = 0, dev_id=0):
        self.doorbell_queues[vq] = Queue(maxsize=1)
        self.soc_notify_queues[vq] = Queue(maxsize=1)
        self.blk_rsp_queues[vq] = Queue()
        self.qos_update_queues[vq] = Queue()
        self.log.info("create_queue {} qszWidth {} max_len {} msix_en {} indirct_support {} qos_en {} bdf {} dev_id {}".format(vq_str(vq), qszWidth, max_len, msix_en, indirct_support, qos_en, bdf, dev_id))
        qid,typ = vq2qid(vq)
        qos_unit = qid
        self.virtq[vq] = VirtQ(self.cfg, self.log, self.mem, self.virt_ctrl, self.doorbell_queues[vq], self.soc_notify_queues[vq], vq, qszWidth, max_len, msix_en, indirct_support, qos_en, qos_unit, bdf = bdf, dev_id = dev_id)            

    async def _msix_irs(self, virtq):
        virtq.msix_event.clear()
        while True:
            await virtq.msix_event.wait()
            virtq.msix_event.clear()
            await self.get_used_desc(virtq)
            await Timer(1, "us")
        
    async def destroy_queue(self, vq):
        self.log.info("destroy_queue {}".format(vq_str(vq)))
        del self.doorbell_queues[vq]
        await self.virt_ctrl.soc_notify_queues_lock.acquire()
        try:
            del self.soc_notify_queues[vq]
        finally:
            self.virt_ctrl.soc_notify_queues_lock.release()
        del self.virtq[vq]

    async def start(self, vq, avail_idx=0):
        self.log.info("start {}".format(vq_str(vq)))
        qid,typ = vq2qid(vq)
        self._msix_irs_cr[vq] = cocotb.start_soon(self._msix_irs(self.virtq[vq]))
        await self.virtq[vq].start(avail_idx)


    async def stop(self, vq, forced_shutdown=False):
        self.log.info("stop {} forced_shutdown {}".format(vq_str(vq), forced_shutdown))
        self._msix_irs_cr[vq].kill()
        pending_hdrs = await self.virtq[vq].stop(forced_shutdown, self.cycle_desc)
        while not self.qos_update_queues[vq].empty():
            self.qos_update_queues[vq].get_nowait()
        while not self.soc_notify_queues[vq].empty():
            await Timer(1, "us")
        return pending_hdrs

    async def doorbell_service(self):
        while True:
            for vq in self.doorbell_queues.keys():
                doorbell_queue = self.doorbell_queues[vq]
                if not doorbell_queue.empty():
                    vq = doorbell_queue.get_nowait()
                    obj = self.doorbell_if._transaction_obj
                    qid, typ = vq2qid(vq)
                    obj.vq = VirtioVq(typ = typ, qid = qid).pack()
                    await self.doorbell_if.send(obj)
            await Timer(5, "ns")

    async def cycle_desc(self, blk):
        await self.get_used_desc(blk)
        pending_hdrs = []
        for id in list(blk.id_pool.keys()):
            if blk.mem_reg_pool[blk.id_pool[id][0]][0].size != 16:
                raise Exception("{} hdr size is mismatch(size:{})".format(vq_str(blk.vq), blk.mem_reg_pool[blk.id_pool[id][0]][0].size))
            raw_hdr = await blk.mem_reg_pool[blk.id_pool[id][0]][0].read(0, 16)
            hdr = VirtioBlkOuthdr().unpack(raw_hdr[::-1])
            pending_hdrs.append(hdr)
            for idx in blk.id_pool[id]:
                blk.release_id(idx)
            del blk.id_pool[id]
        return pending_hdrs

    async def get_used_desc(self, blk):
        used_idx_pi = await blk.read_used_idx()
        used_desc_num = used_idx_pi - blk.used_idx_ci if used_idx_pi >= blk.used_idx_ci else used_idx_pi + (2**16) - blk.used_idx_ci
        if used_desc_num:
            self.log.debug("{} get_used_desc used_desc_num {}".format(vq_str(blk.vq), used_desc_num))
        for i in range(used_desc_num):
            used_elem = await blk.read_used_element(blk.used_idx_ci)
            used_len = used_elem.len
            id = used_elem.id
            regs = blk.mem_reg_pool[id]
            hdr_raw = await regs[0].read(0, 16)
            hdr = VirtioBlkOuthdr().unpack(hdr_raw[::-1])
            sts = await regs[-1].read(0, 1)
            if len(regs) > 2:
                pld_data = b''
                for j in range(len(regs)-2):
                    data = await regs[j+1].read(0, regs[j+1].size)
                    self.log.info("read reg seq {} idx {} addr {} len {}".format(hdr.ioprio, j, regs[j+1].get_absolute_address(0), regs[j+1].size))
                    pld_data = pld_data + data
            else:
                pld_data = None
            await self.blk_rsp_queues[blk.vq].put((hdr, pld_data, used_len, sts))

            if blk.used_idx_ci in blk.indirct_reg_pool.keys():
                self.mem.free_region(blk.indirct_reg_pool[blk.used_idx_ci])
                del blk.indirct_reg_pool[blk.used_idx_ci]
            for reg in regs:
                self.mem.free_region(reg)
            del blk.mem_reg_pool[id]
            blk.used_idx_ci = (blk.used_idx_ci + 1) & 0xffff
            ids = blk.id_pool[id]
            for i in ids:
                blk.release_id(i)
            del blk.id_pool[id]

    async def burst_xmit(self, vq, mbufs):
        qid, typ = vq2qid(vq)
        if typ != TestType.BLK:
            raise ValueError("The vq{} is not blk".format(vq_str(vq)))
        blk = self.virtq[vq]
        
        if not blk.msix_en:
            await self.get_used_desc(blk)
        avail_num = blk.avail_idx_sw - blk.used_idx_ci if blk.avail_idx_sw >= blk.used_idx_ci else blk.avail_idx_sw + (2**16) - blk.used_idx_ci
        need_send_pkt = min(blk.qsz - avail_num, len(mbufs))
        pkt_cnt = 0
        for i in range(need_send_pkt):
            mbuf = mbufs[i]
            seg_num = len(mbuf.regs)
            indirct_ptr = random.randint(0, seg_num-1) if blk.indirct_support else seg_num
            indirct_desc_sz = random.randint((seg_num-indirct_ptr), self.cfg.max_indirct_desc_size)
            if blk.indirct_support and self.cfg.indirct_relaxed_ordering:
                indirct_id_list = [0] + random.sample(range(1, indirct_desc_sz), seg_num-indirct_ptr-1)
            else:
                indirct_id_list = range(seg_num-indirct_ptr)

            indirct_mem_reg = None
            first_id = None
            id_list = []
            dirct_desc_cnt = min(seg_num, indirct_ptr+1)
            if dirct_desc_cnt > len(list(blk.id_allocator)):
                break
            else:
                pkt_cnt = pkt_cnt + 1
            for i in range(dirct_desc_cnt):
                id = await blk.alloc_id()
                if i == 0:
                    first_id = id
                id_list.append(id)
            total_len = 0
            for i in range(seg_num + (indirct_ptr < seg_num)):
                flags_write = (i + 1 == seg_num + (indirct_ptr < seg_num)) or (mbuf.typ == VirtioBlkType.VIRTIO_BLK_T_IN and (i != 0 and (indirct_ptr==0 and i != 1)))
                if i == indirct_ptr:
                    indirct_mem_reg = self.mem.alloc_region(indirct_desc_sz*16, bdf=blk.bdf, dev_id=blk.dev_id)
                    blk.indirct_reg_pool[blk.avail_idx_sw] = indirct_mem_reg
                    id = id_list[i]
                    desc = blk.gen_a_desc(indirct_mem_reg.get_absolute_address(0), indirct_mem_reg.size, flags_indirect=1, next=0, flags_next=0, flags_write=0)
                    self.log.debug("indirct desc write{} vq{} id {} idx {} desc {}".format("", vq_str(vq), id, blk.avail_idx_sw, desc.show(dump=True)))
                    await blk.write_desc(id, desc)
                elif i < indirct_ptr:
                    id = id_list[i]
                    desc = blk.gen_a_desc(mbuf.regs[i].get_absolute_address(0), mbuf.regs[i].size, flags_indirect=0, next=id_list[i+1] if i != seg_num - 1 else 0, flags_next=i != seg_num - 1, flags_write=flags_write)
                    self.log.debug("desc write{} vq{} id {} idx {} desc {}".format("", vq_str(vq), id, blk.avail_idx_sw, desc.show(dump=True)))
                    total_len = total_len + mbuf.regs[i].size
                    await blk.write_desc(id, desc)
                else:
                    id = indirct_id_list[i-indirct_ptr - 1]
                    desc = blk.gen_a_desc(mbuf.regs[i-1].get_absolute_address(0), mbuf.regs[i-1].size, flags_indirect=0, next=indirct_id_list[i-indirct_ptr] if i != seg_num else 0, flags_next=i != seg_num, flags_write=flags_write)
                    total_len = total_len + mbuf.regs[i-1].size
                    self.log.debug("desc write{} vq{} id {} idx {} desc {}".format("", vq_str(vq), id, blk.avail_idx_sw, desc.show(dump=True)))
                    await blk.write_desc(id, desc, indirct_mem_reg)
            if blk.qos_en:
                await self.qos_update_queues[vq].put(total_len)
            blk.id_pool[first_id] = id_list
            blk.mem_reg_pool[first_id] = mbuf.regs
            await blk.write_avail(blk.avail_idx_sw, first_id)
            blk.avail_idx_sw = (blk.avail_idx_sw + 1) & 0xffff
        if pkt_cnt:
            await blk.write_avail_idx(blk.avail_idx_sw)
        return mbufs[pkt_cnt:]