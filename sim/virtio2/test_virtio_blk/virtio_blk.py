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

from cocotb.binary import BinaryValue
from scapy.all import Packet, BitField
from virtio_defines import *

class IO_Req_Type(NamedTuple):
    data            : bytearray  
    host_gen        : int
    start_of_pkt    : bool
    end_of_pkt      : bool
    forced_shutdown : bool
    err_info        : int

class VirtBlkInfo:
    def __init__(self, id, fe_typ, fe_data=None, fe_len=None):
        self.id = id
        self.fe_typ = fe_typ
        self.fe_data = fe_data
        self.fe_len = fe_len
        self.fe_sts = None
        self.be_data = None
        self.be_sts = None
        self.be_err = None
        self.be_vq_gid = None
        self.be_host_gen = None
        self.be_forced_shutdown = None

class VirtBlk:
    def __init__(self, cfg, log, mem, pmd, interfaces):
        self.log = log
        self.cfg = cfg
        self.pmd = pmd
        self.mem = mem
        self.interfaces = interfaces
        self._req_queues = {}
        self._info_dicts = {}
        self.qos_req_queue = Queue()
        self._backend_buf_queues = {}
        self._qos_total_len = {}
        self.done = {}
        self._gen_req_cr = {}
        self._checker_cr = {}
        self._blk_backend_rsp_cr = {}
        self._finish_seq_num = {}

    def start(self, qid_list):
        self.doing = True
        for qid in qid_list:
            self._qos_total_len[qid] = 0
            self._req_queues[qid] = Queue(maxsize=16)
            self.done[qid] = False
            self._info_dicts[qid] = {}
            self._finish_seq_num[qid] = 0
            self._backend_buf_queues[qid] = Queue(maxsize=16)
            self._gen_req_cr[qid] = cocotb.start_soon(self._gen_req(qid))
            self._checker_cr[qid] = cocotb.start_soon(self._blk_checker(qid))
            self._blk_backend_rsp_cr[qid] = cocotb.start_soon(self._blk_backend_rsp(qid))
        self._process_qos_req_cr = cocotb.start_soon(self._process_qos_req())
        self._process_qos_rsp_cr = cocotb.start_soon(self._process_qos_rsp())
        self._process_qos_update_cr = cocotb.start_soon(self._process_qos_update())
        self._blk_backend_req_cr = cocotb.start_soon(self._blk_backend_req())

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


    async def _gen_req(self, qid):
        id = 0
        vq = qid2vq(qid, TestType.BLK)
        while self.doing and vq in self.pmd.virtq.keys():
        #for _ in range(self.cfg.max_seq):
            if len(self._info_dicts[qid]) > 128 or self._req_queues[qid].qsize() > self._req_queues[qid].maxsize-2:
                await Timer(1, "us")
                continue
            typ = random.choice([VirtioBlkType.VIRTIO_BLK_T_IN, VirtioBlkType.VIRTIO_BLK_T_OUT, VirtioBlkType.VIRTIO_BLK_T_FLUSH, VirtioBlkType.VIRTIO_BLK_T_DISCARD, VirtioBlkType.VIRTIO_BLK_T_WRITE_ZEROES])
            max_chain_num = min(self.cfg.max_chain_num, self.pmd.virtq[vq].qsz)
            mu = self.cfg.min_chain_num + min((max_chain_num - self.cfg.min_chain_num)//3, 16)
            desc_cnt = rand_norm_int(self.cfg.min_chain_num, max_chain_num, mu)
            len_list = []
            if random.randint(0, 100) > 98:
                for i in range(desc_cnt):
                    len_list.append(random.randint(1, 15))
            else:
                for i in range(desc_cnt):
                    mu = 1 + min(self.cfg.max_len//3, 512)
                    length = rand_norm_int(1, self.cfg.max_len, mu)
                    len_list.append(length)
            if typ == VirtioBlkType.VIRTIO_BLK_T_OUT:#write
                length = sum(len_list)
                pld_data = bytearray(fake_urandom(length))
            elif typ == VirtioBlkType.VIRTIO_BLK_T_IN:#read
                length = sum(len_list)
                pld_data = None
            else:
                length = None
                len_list = []
                pld_data = None
            self.log.info("_gen_req qid:{} id {} typ {} length {} len_list {} {}".format(qid, id, blk_type_map(typ), length, len_list, desc_cnt))
            bdf = self.pmd.virtq[vq].bdf
            dev_id = self.pmd.virtq[vq].dev_id
            mbuf = await gen_pkt(mem=self.mem, id=id, op_type=typ, pld_data=pld_data, pld_data_len=length, len_list=len_list, bdf=bdf, dev_id=dev_id)
            self._info_dicts[qid][id] = VirtBlkInfo(id=id, fe_typ=typ, fe_data=pld_data, fe_len=length)
            await self._req_queues[qid].put(mbuf)
            id = id + 1

    async def _blk_backend_req(self):
        while self.doing:
            blk_req = await self.interfaces.blk2beq_if.recv()
            data = blk_req.data[blk_req.sty:]
            qid = blk_req.user0 & 0xffff
            host_gen = (blk_req.user0 & 0xff0000) >> 16
            start_of_pkt = blk_req.user0 & (1<<24) != 0
            end_of_pkt =  blk_req.user0 & (1<<25)  != 0
            forced_shutdown =  blk_req.user0 & (1<<26)
            err_info = (blk_req.user0 >> 32) & 0xff
            await self._backend_buf_queues[qid].put(IO_Req_Type(data, host_gen, start_of_pkt, end_of_pkt, forced_shutdown, err_info))


    async def _blk_backend_rsp(self, qid):
        gen = None
        is_hdr = True
        req_hdr = None
        req_data = None
        _backend_buf = []
        force_shutdown = False
        while self.doing:
            io_req = await self._backend_buf_queues[qid].get()
            host_gen = io_req.host_gen
            data = io_req.data
            start_of_pkt = io_req.start_of_pkt
            end_of_pkt = io_req.end_of_pkt
            #self.log.debug("_backend_buf_queues {} {} {} {}".format(start_of_pkt, end_of_pkt, io_req.err_info, data.hex()))
            if gen == None:
                gen = host_gen
                _backend_buf = []
            elif gen != host_gen:
                force_shutdown = False
                gen = host_gen
                _backend_buf = []
            is_hdr = start_of_pkt
            if is_hdr:
                req_hdr = VirtqBlkReqHeader().unpack(data[::-1])
                self.log.debug("qid {} is hdr {} hdr {} ".format(qid, is_hdr, req_hdr.show(dump=True)))
                req_data = b''
            else:
                req_data = req_data + data
            
            only_hdr = (is_hdr and (req_hdr.flags & 0x2)) != 0

            last_hdr = not (req_hdr.flags & 0x1)

            if io_req.forced_shutdown or force_shutdown:
                force_shutdown = True
                _backend_buf = []
            else:
                if end_of_pkt:
                    _backend_buf.append((req_hdr, req_data))
                if only_hdr and last_hdr: #status flags.next = 0 flags.write = 1
                    self.log.debug("qid {} only_hdr {} last_hdr {}".format(qid, only_hdr, last_hdr))
                    req_hdr, req_data = _backend_buf.pop(0)
                    desc_idx = req_hdr.desc_idx
                    blk_hdr = VirtioBlkOuthdr().unpack(req_data[::-1])
                    id = blk_hdr.ioprio
                    #if seq_num in self._info_dicts[qid].keys():
                    #self.log.debug("blk_hdr {} id {} {}".format(qid, id, blk_hdr.show(dump=True)))
                    info = self._info_dicts[qid][id]
                    #else:
                    #    await Timer(1, "us")
                    #    continue
                    info.be_vq_gid = qid
                    info.be_host_gen = host_gen
                    sts = int(randbit(8)).to_bytes(1, "little")
                    info.be_sts = sts
                    vq = qid2vq(qid, TestType.BLK)
                    if blk_hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:#read
                        used_len = info.fe_len + 1
                    else :
                        used_len = 1
                    if blk_hdr.type == VirtioBlkType.VIRTIO_BLK_T_OUT:#write
                        info.be_data = b''
                        for i in range(len(_backend_buf)-1):
                            req_hdr, req_data = _backend_buf.pop(0)
                            info.be_data = info.be_data + req_data
                    elif blk_hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:#read
                        info.be_data = b''
                        for i in range(len(_backend_buf)-1):
                            req_hdr, req_data = _backend_buf.pop(0)
                            pld_data = bytearray(fake_urandom(req_hdr.host_buf_len))
                            info.be_data = info.be_data + pld_data
                            rsp_hdr = VirtqBlkRspHeader(vq_gid=qid, vq_gen=host_gen, desc_idx=desc_idx, flags=req_hdr.flags, host_buf_addr=req_hdr.host_buf_addr, used_len=used_len, used_idx=self.pmd.virtq[vq].backend_used_idx, magic_num=0xc0de)
                            self.log.debug("write data qid {} rsp_hdr {}".format(qid, rsp_hdr.show(dump=True)))
                            await self.interfaces.beq2blk_if.send(qid, rsp_hdr.build()[::-1] + pld_data, randbit(40))
                    else:
                        info.be_data = b''
                    req_hdr, req_data = _backend_buf.pop(0)
                    rsp_hdr = VirtqBlkRspHeader(vq_gid=qid, vq_gen=host_gen, desc_idx=desc_idx, flags=req_hdr.flags, host_buf_addr=req_hdr.host_buf_addr, used_len=used_len, used_idx=self.pmd.virtq[vq].backend_used_idx, magic_num=0xc0de)
                    self.log.debug("write sts qid {} rsp_hdr {}".format(qid, rsp_hdr.show(dump=True)))
                    await self.interfaces.beq2blk_if.send(qid, rsp_hdr.build()[::-1] + sts, randbit(40))
                    self.pmd.virtq[vq].backend_used_idx = self.pmd.virtq[vq].backend_used_idx + 1

    async def _process_qos_req(self):
        while self.doing:
            req_trans = await self.interfaces.blk_qos.query_req_if.recv()
            if self.qos_req_queue.full():
                raise Exception("qos_req_queue is full")
            self.qos_req_queue.put_nowait(req_trans)

    async def _process_qos_rsp(self):
        while self.doing:
            req_trans = await self.qos_req_queue.get()
            rsp_trans = self.interfaces.blk_qos.query_rsp_if._transaction_obj()
            if random.random() < self.cfg.random_qos:
                rsp_trans.ok = 1
            else:
                rsp_trans.ok = 0
            await self.interfaces.blk_qos.query_rsp_if.send(rsp_trans)

    async def _process_qos_update(self):
        while self.doing:
            update_trans = await self.interfaces.blk_qos.update_if.recv()
            qid = int(update_trans.uid)
            vq = qid2vq(qid, TestType.BLK)
            self._qos_total_len[qid] = self._qos_total_len[qid] + int(update_trans.len)
            if update_trans.pkt_num:
                ref_len = await self.pmd.qos_update_queues[vq].get()
                if self._qos_total_len[qid] != ref_len:
                    self.log.warning("{}  ref length: {} cur length {}".format(vq_str(vq), ref_len, self._qos_total_len[qid]))
                    raise Exception("blk qos length is mismatch")
                self._qos_total_len[qid] = 0
    

    async def _blk_checker(self, qid):
        vq = qid2vq(qid, TestType.BLK)
        for i in range(self.cfg.max_seq):
            hdr, pld_data, used_len, sts = await self.pmd.blk_rsp_queues[vq].get()
            self.log.info("_blk_checker seq {} hdr {}".format(hdr.ioprio, hdr.show(dump=True)))
            id = hdr.ioprio
            info = self._info_dicts[qid][id]
            info.fe_sts = sts
            if hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:#read
                info.fe_data = pld_data
                info.fe_len = used_len-1
            #checker
            if info.fe_typ != hdr.type:
                self.log.warning("{} id {} seq_num {} ref {} cur {}".format(vq_str(vq), id, self._finish_seq_num[qid], info.fe_typ, hdr.type))
                raise Exception("blk checker status is mismatch")
            if hdr.type == VirtioBlkType.VIRTIO_BLK_T_OUT or hdr.type == VirtioBlkType.VIRTIO_BLK_T_IN:
                if info.fe_len != len(info.be_data):
                    self.log.warning("{} id {} seq_num {}".format(vq_str(vq), id, self._finish_seq_num[qid]))
                    self.log.warning("be: {}".format(len(info.be_data)))
                    self.log.warning("fe: {}".format(info.fe_len))
                    raise Exception("blk checker len is mismatch")
                if info.fe_data != info.be_data:
                    self.log.warning("{} id {}  seq_num {}".format(vq_str(vq), id, self._finish_seq_num[qid]))
                    self.log.warning("be: {}".format(info.be_data.hex()))
                    self.log.warning("fe: {}".format(info.fe_data.hex()))
                    raise Exception("blk checker data is mismatch")
            if info.fe_sts != info.be_sts:
                self.log.warning("{} id {} seq_num {} be {} fe {}".format(vq_str(vq), id, self._finish_seq_num[qid], info.be_sts, info.fe_sts))
                raise Exception("blk checker status is mismatch")
            self.log.info("qid {} id {} seq_num {} pass!".format(qid, id, self._finish_seq_num[qid]))
            self._finish_seq_num[qid] = self._finish_seq_num[qid] + 1
            del self._info_dicts[qid][id]
        self.done[qid] = True
        
