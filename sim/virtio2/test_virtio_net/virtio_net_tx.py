import random
from scapy.packet import Raw
from scapy.volatile import RandMAC, RandIP, RandIP6, RandShort, RandString
from scapy.layers.inet import TCP, UDP, IP, ICMP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import Dot1Q, Ether, ARP, STP
from scapy.layers.sctp import SCTP

import cocotb
import copy
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from cocotb.utils import get_sim_time

from cocotb.binary import BinaryValue
from scapy.all import Packet, BitField
from generate_eth_pkg import *
from test_virtio_net_tb import TB
from virtio_net_defines import Cfg, VirtioStatus, VirtioVq, TestType, VirtioNetHdrGsoTypeBit, VirtioNetHdr, Net2TsoPkt, Mbufs
from virtio_net_func import *


def generate_pkt(cfg, qid, gen=0):
    info = Config()
    info.qid = qid
    info.act_gen = gen
    _, eth_info, eth_pkt = generate_eth_pkt(cfg.eth_cfg, "tx")
    info.eth_info = eth_info
    return info, eth_pkt


class VirtioNetTx:
    def __init__(self, tb: TB):
        self.tb: TB = tb
        self.cfg: Cfg = tb.cfg
        self.log = tb.log
        self.mem = tb.mem
        self.dut = tb.dut
        self.interfaces = tb.interfaces
        self.pmd = tb.virtio_pmd
        self.gen_pkt_queues: Dict[int, Queue] = {}
        self.ref_pkt_queues = {}
        self.ref_pkt_num = Queue()
        self.forced_shutdown_queues = {}
        self.qos_req_queue = Queue()
        self.net2tso_queue = {}
        self.qos_update_queues = {}
        self._gen_pkt_cr = {}

        self.pkt_time_start = None
        self.pkt_time_last = None
        self.pps_cnt = 0
        self.bps_cnt = 0
        self.status = VirtioStatus.IDLE
        # self.tx_check_result = {}
        self.tx_num = {}
        self.doing = False

    def start(self, qid_list):
        self.doing = True
        for qid in qid_list:
            self.gen_pkt_queues[qid] = Queue(maxsize=64)
            self.ref_pkt_queues[qid] = Queue(maxsize=128)
            self.forced_shutdown_queues[qid] = Queue(maxsize=128)
            self.qos_update_queues[qid] = Queue()
            self.net2tso_queue[qid] = Queue()
            # self._gen_pkt_cr[qid] = cocotb.start_soon(self._gen_pkt(qid))
            # self.tx_check_result[qid] = 0
            self.tx_num[qid] = 0
        self._process_qos_req_cr = cocotb.start_soon(self._process_qos_req())
        self._process_qos_rsp_cr = cocotb.start_soon(self._process_qos_rsp())
        self._process_qos_update_cr = cocotb.start_soon(self._process_qos_update())
        self._process_net2tso_cr = cocotb.start_soon(self._process_net2tso())
        # self._tx_check_result_cr = cocotb.start_soon(self._tx_check_result())
        # self.status = VirtioStatus.DOING

    async def join(self, qid_list):
        self.doing = False
        for qid in qid_list:
            # await self._gen_pkt_cr[qid].join()
            while not self.ref_pkt_queues[qid].empty():
                await Timer(1, "us")
        self._process_qos_req_cr.kill()
        self._process_qos_rsp_cr.kill()
        self._process_qos_update_cr.kill()
        self._process_net2tso_cr.kill()
        # self._tx_check_result_cr.kill()

    async def _gen_pkt(self, qid) -> Mbufs:

        vq = VirtioVq.qid2vq(qid, TestType.NETTX)
        # while not self.tb.virtio_pmd.virtq[vq].finished:
        info = Config()
        info, eth_pkt = generate_pkt(self.cfg, qid)
        info.seq_num = self.tx_num[qid]
        virtq = self.pmd.virtq[VirtioVq.qid2vq(qid, TestType.NETTX)]
        info.tso_en = virtq.tso_en
        info.csum_en = virtq.csum_en
        info.qos_en = virtq.qos_en
        info.gen = virtq.gen
        info.flags = 0
        if info.eth_info.net_type in ["ipv4", "ipv6"]:
            if info.eth_info.net_type == "ipv4" and info.eth_info.net_info.csum_err:
                info.flags = 1
            if info.eth_info.trans_type in ["tcp", "udp"] and info.eth_info.trans_info.csum_err:
                info.flags = 1

        if random.random() < self.cfg.tx_random_need_tso and info.eth_info.net_type in ["ipv4", "ipv6"] and info.eth_info.trans_type in ["tcp", "udp"]:
            info.need_tso = 1
        else:
            info.need_tso = 0

        if not info.need_tso:
            info.gso_type = VirtioNetHdrGsoTypeBit.VIRTIO_NET_HDR_GSO_NONE
        else:
            if info.eth_info.net_type in ["ipv4", "ipv6"] and info.eth_info.trans_type == "udp":
                info.gso_type = VirtioNetHdrGsoTypeBit.VIRTIO_NET_HDR_GSO_UDP
            elif info.eth_info.net_type == "ipv4" and info.eth_info.trans_type == "tcp":
                info.gso_type = VirtioNetHdrGsoTypeBit.VIRTIO_NET_HDR_GSO_TCPV4
            elif info.eth_info.net_type == "ipv6" and info.eth_info.trans_type == "tcp":
                info.gso_type = VirtioNetHdrGsoTypeBit.VIRTIO_NET_HDR_GSO_TCPV6
            else:
                raise Exception("unsupported gso_type")

        net_hdr = VirtioNetHdr(
            num_buffers=randbit(16),
            csum_offset=randbit(16),
            csum_start=randbit(16),
            gso_size=virtq.mss,
            hdr_len=randbit(16),
            gso_type=info.gso_type,
            flags=info.flags,
        ).build()[::-1]

        byte_data = net_hdr + bytes(eth_pkt)
        info.pkt_len = len(byte_data)

        # self.log.info(f"net_rx_gen_pkt qid:{qid} seq_num:{i} info:{info} data:{byte_data.hex()}")

        if info.qos_en:
            await self.qos_update_queues[qid].put(info)
        # self.log.error(f"put gen{info.gen}")
        while self.ref_pkt_queues[qid].full():
            await Timer(5, "ns")
            info.gen = virtq.gen
        await self.ref_pkt_queues[qid].put((info, copy.deepcopy(byte_data)))
        regs = []
        reg_num = min(info.pkt_len, random.randint(self.cfg.min_chain_num, self.cfg.max_chain_num))
        reg_len_list = split_number(info.pkt_len, reg_num)
        for i in range(reg_num):
            length = reg_len_list[i]
            reg = self.mem.alloc_region(length)
            await reg.write(0, byte_data[:length])
            byte_data = byte_data[length:]
            regs.append(reg)
        self.tx_num[qid] += 1
        return Mbufs(regs=regs, len=info.pkt_len)
        # await self.gen_pkt_queues[qid].put(Mbufs(regs=regs, len=info.pkt_len))

    async def _process_qos_req(self):
        while self.doing:
            req_trans = await self.interfaces.tx_qos.query_req_if.recv()
            if self.qos_req_queue.full():
                raise Exception("qos_req_queue is full")
            self.qos_req_queue.put_nowait(req_trans)

    async def _process_qos_rsp(self):
        while self.doing:
            req_trans = await self.qos_req_queue.get()
            rsp_trans = self.interfaces.tx_qos.query_rsp_if._transaction_obj()
            if random.random() < self.cfg.random_qos:
                rsp_trans.ok = 1
            else:
                rsp_trans.ok = 0
            await self.interfaces.tx_qos.query_rsp_if.send(rsp_trans)

    async def _process_qos_update(self):
        while self.doing:
            update_trans = await self.interfaces.tx_qos.update_if.recv()
            qid = int(update_trans.uid)
            vq = VirtioVq.qid2vq(qid, TestType.NETTX)
            info = await self.qos_update_queues[qid].get()
            ref_pkt_len = info.pkt_len - 12 if info.pkt_len > 12 else info.pkt_len
            length = int(update_trans.len)
            if length != ref_pkt_len:
                self.log.warning("{}  ref length: {} cur length {}".format(VirtioVq.vq2str(vq), ref_pkt_len, length))
                raise Exception("tx qos length is mismatch")
            if update_trans.pkt_num != 1:
                raise Exception("tx qos pkt_num is mismatch")

    async def _process_net2tso(self):
        while self.doing:
            data = b''
            eop = False
            sty = 0
            qid = None
            length = None
            gen = None
            err = False
            tso_en = None
            csum_en = None
            while not eop:
                elemnt = await self.interfaces.net2tso_if.recv()
                qid = elemnt.qid.value
                length = elemnt.length.value
                gen = elemnt.gen.value
                err = err or elemnt.err.value
                tso_en = elemnt.tso_en.value
                csum_en = elemnt.csum_en.value
                sop = elemnt.sop.value
                eop = elemnt.eop.value
                if sop and len(data) > 0:
                    raise ValueError("lost eop")
                if eop and not sop and len(data) == 0:
                    raise ValueError("lost sop")

                sty = elemnt.sty.value if sop else sty
                mty = elemnt.mty.value
                cur_sty = sty if sop else 0
                cur_mty = mty if eop else 0

                if "x" not in str(elemnt.data):
                    data = data + elemnt.data.value.to_bytes(32, 'little')[cur_sty : 32 - cur_mty]
                else:
                    tmp = b'\X00' * 32
                    data = data + tmp[sty : 32 - mty]
            await self.net2tso_queue[qid].put(Net2TsoPkt(qid=qid, length=length, gen=gen, err=err, tso_en=tso_en, csum_en=csum_en, data=data))
            # self.log.info(f"qid: {qid} recv pkt gen{gen}")
            self.pkt_time_last = get_sim_time("ns")
            self.pps_cnt += 1
            self.bps_cnt += len(data)
            if self.pkt_time_start is None:
                self.pkt_time_start = get_sim_time("ns")
                self.pps_cnt = 0
                self.bps_cnt = 0

    # async def _tx_check_result(self):
    #     while self.doing:
    #         qid, pkt_num = await self.ref_pkt_num.get()
    #         for i in range(pkt_num):
    #             # pkt = await self.net2tso_queue[qid].get()
    #             T = 0
    #             while self.net2tso_queue[qid].empty():
    #                 await Timer(100, "ns")
    #                 self.log.error(f" qid {qid} has no pkt out pkt_num {pkt_num}")
    #                 (ref_info, ref_data) = self.ref_pkt_queues[qid]._queue[0]
    #                 self.log.error(f"info: {ref_info}")
    #                 self.log.error(f"data: {ref_data.hex()}")
    #                 T = T + 1
    #                 if T == 10:
    #                     raise Exception(f"net2tso_queue qid:{qid} has no pkt")
    #             pkt = self.net2tso_queue[qid].get_nowait()
    #             vq = VirtioVq.qid2vq(pkt.qid, TestType.NETTX)

    #             (ref_info, ref_data) = self.ref_pkt_queues[pkt.qid].get_nowait()
    #             if ref_info.qid != pkt.qid:
    #                 self.log.warning("{}  ref qid: {}".format(VirtioVq.vq2str(vq), ref_info.qid))
    #                 raise Exception("tx pkt qid is mismatch")
    #             if self.tb.virtio_pmd.virtq[vq].gen != pkt.gen:
    #                 self.log.warning("{}  ref gen: {} cur gen {}".format(VirtioVq.vq2str(vq), ref_info.gen, pkt.gen))
    #                 raise Exception("tx pkt gen is mismatch")
    #             if ref_info.pkt_len != pkt.length:
    #                 self.log.warning("{}  ref length: {} cur length {}".format(VirtioVq.vq2str(vq), ref_info.pkt_len, pkt.length))
    #                 self.log.warning("ref: {}".format(ref_data.hex()))
    #                 self.log.warning("cur: {}".format(pkt.data.hex()))
    #                 raise Exception("tx pkt length is mismatch")
    #             if ref_info.tso_en != pkt.tso_en:
    #                 self.log.warning("{}  ref tso_en: {} cur tso_en {}".format(VirtioVq.vq2str(vq), ref_info.tso_en, pkt.tso_en))
    #                 raise Exception("tx pkt tso_en is mismatch")

    #             if ref_info.csum_en != pkt.csum_en:
    #                 self.log.warning("{}  ref csum_en: {} cur csum_en {}".format(VirtioVq.vq2str(vq), ref_info.csum_en, pkt.csum_en))
    #                 raise Exception("tx pkt csum_en is mismatch")

    #             if ref_data != pkt.data:
    #                 self.log.warning("{} total_len {} info: {}".format(VirtioVq.vq2str(vq), len(pkt.data), ref_info))
    #                 self.log.warning("ref: {}".format(ref_data.hex()))
    #                 self.log.warning("cur: {}".format(pkt.data.hex()))
    #                 raise Exception("tx pkt data is mismatch")
    #             self.log.info(f"{VirtioVq.vq2str(vq)} seq_num {ref_info.seq_num} pass pass_num: {self.tx_check_result[qid]} ")
    #             # self.log.info(f"{VirtioVq.vq2str(vq)} seq_num {ref_info.seq_num} pass data:{ref_data.hex()}")
    #             self.tx_check_result[qid] += 1
    #             if self.tx_check_result[qid] == self.cfg.max_seq:
    #                 self.tb.virtio_pmd.virtq[vq].finished = True
    #             # self.log.info("{VirtioVq.vq2str(vq)} seq_num {ref_info.seq_num} pass")

    def get_pps(self):
        time = self.pkt_time_last - self.pkt_time_start  # ns
        pkt = self.pps_cnt

        pps = pkt * 1000 / time if time != 0 else 0  # M
        return pps

    def get_bps(self):
        time = self.pkt_time_last - self.pkt_time_start  # ns
        pkt = self.bps_cnt

        bps = pkt * 8 / time if time != 0 else 0  # G
        return bps
