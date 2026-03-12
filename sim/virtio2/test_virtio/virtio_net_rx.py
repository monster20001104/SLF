import random
from scapy.packet import Raw
from scapy.volatile import RandMAC, RandIP, RandIP6, RandShort, RandString
from scapy.layers.inet import TCP, UDP, IP, ICMP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import Dot1Q, Ether, ARP, STP
from scapy.layers.sctp import SCTP

import cocotb
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


def generate_beq2net_pkt(cfg, qid, gen=0):
    info = Config()
    info.qid = qid
    info.act_gen = gen
    _, eth_info, eth_pkt = generate_eth_pkt(cfg.eth_cfg, "rx")
    info.eth_info = eth_info
    return info, eth_pkt


class VirtioNetRx:
    def __init__(self, tb: TB):
        self.tb: TB = tb
        self.cfg: Cfg = tb.cfg
        self.log = tb.log
        self.mem = tb.mem
        self.dut = tb.dut
        self.interfaces = tb.interfaces
        self.pmd = tb.virtio_pmd
        self.gen_pkt_queues = {}
        self.pkt_beq2net_queue = Queue(maxsize=128)
        self.rx_pkt_list = {}
        self.rx_buf_info = {}
        self.rx_buf_data = {}
        self.net_rx_data = {}
        self.net_rx_info = {}
        self.drop_queue = Queue()
        self.qos_req_queue = Queue()
        self.qos_rsp_queue = Queue()
        self.rx_buf_pkt_cnt = 0
        self.rx_buf_drop_cnt = 0
        self.net_rx_pkt_cnt = 0
        self.net_rx_drop_cnt = 0
        self.net_rx_cnt = 0
        self._gen_pkt_cr = {}
        # self._process_beq2net_cr = None

        self.pps_token_producer_ptr = 0.0
        self.pps_token_consumer_ptr = 0.0
        self.bps_token_producer_ptr = 0.0
        self.bps_token_consumer_ptr = 0.0

        self.rx_check_queue = Queue(maxsize=32)
        self.rx_check_result = {}

        self.pkt_time_start = None
        self.pkt_time_last = None
        self.pps_cnt = 0
        self.bps_cnt = 0

    def start(self, qid_list):
        self.doing = True
        self.rx_check_result = {}
        for qid in qid_list:
            self.gen_pkt_queues[qid] = Queue(maxsize=16)
            self.rx_pkt_list[qid] = []
            self.rx_buf_info[qid] = []
            self.rx_buf_data[qid] = []
            self.net_rx_data[qid] = []
            self.net_rx_info[qid] = []
            self._gen_pkt_cr[qid] = cocotb.start_soon(self._gen_pkt(qid))

        self._process_beq2net_cr = cocotb.start_soon(self._process_beq2net())
        self._process_beq2net_qos_cr = cocotb.start_soon(self._process_beq2net_qos())

        self._process_drop_cr = cocotb.start_soon(self._process_drop())
        self._process_qos_req_cr = cocotb.start_soon(self._process_qos_req())
        self._process_qos_rsp_cr = cocotb.start_soon(self._process_qos_rsp())
        self._process_qos_update_cr = cocotb.start_soon(self._process_qos_update())
        self._process_not_avail_id_drop_cr = cocotb.start_soon(self._process_not_avail_id_drop())

        self._process_rx_check_cr = cocotb.start_soon(self._process_rx_check())

    async def join(self, qid_list):
        self.doing = False
        for qid in qid_list:
            await self._gen_pkt_cr[qid].join()
        await self._process_beq2net_cr.join()
        await self._process_beq2net_qos_cr.join()
        await self._process_drop_cr.join()
        await self._process_qos_req_cr.join()
        await self._process_qos_rsp_cr.join()
        await self._process_qos_update_cr.join()
        await self._process_not_avail_id_drop_cr.join()
        await self._process_rx_check_cr.join()

    async def _gen_pkt(self, qid):
        vq = VirtioVq.qid2vq(qid, TestType.NETRX)
        virtq = self.pmd.virtq[vq]
        # for i in range(self.cfg.max_seq):
        i = 0
        while True:
            info = Config()
            info, eth_pkt = generate_beq2net_pkt(self.cfg, qid)
            info.seq_num = i
            info.pkt_len = len(eth_pkt)
            byte_data = bytes(eth_pkt)
            info.act_gen = virtq.gen
            info.qos_en = virtq.qos_en
            info.unit = virtq.qos_unit
            info.csum_en = self.cfg.global_rx_csum_en
            if random.random() < self.cfg.rx_random_need_vld:
                info.need_vld = 1
            else:
                info.need_vld = 0
            # self.log.info("net_rx_gen_pkt qid:{} seq_num {} info {}".format(qid, i, info))
            await self.gen_pkt_queues[qid].put((info, byte_data))
            i += 1

    async def _process_beq2net(self):
        pkt_id = 0
        while self.doing:
            for qid in self.gen_pkt_queues.keys():
                vq = VirtioVq.qid2vq(qid, TestType.NETRX)
                await Timer(5, "ns")
                if self.gen_pkt_queues[qid].empty():
                    continue
                # if self.pmd.virtq[vq].first_db:
                #     continue
                (info, byte_data) = self.gen_pkt_queues[qid].get_nowait()
                await self.pkt_beq2net_queue.put(info)
                self.rx_pkt_list[qid].append(byte_data)
                user0 = randbit(40)
                user0 = (user0 & ~0xFF) | info.qid
                user0 = (user0 & ~(0x1 << 16)) | info.need_vld << 16
                user0 = (user0 & ~(0xFF << 32)) | info.act_gen << 32
                info.pkt_id = pkt_id
                # logging.error(info)

                pps_tokens = (
                    self.pps_token_producer_ptr - self.pps_token_consumer_ptr
                    if self.pps_token_producer_ptr >= self.pps_token_consumer_ptr
                    else self.pps_token_producer_ptr + 1024 - self.pps_token_consumer_ptr
                )
                bps_tokens = (
                    self.bps_token_producer_ptr - self.bps_token_consumer_ptr
                    if self.bps_token_producer_ptr >= self.bps_token_consumer_ptr
                    else self.bps_token_producer_ptr + 65536 - self.bps_token_consumer_ptr
                )

                while (pps_tokens < 1 and self.cfg.global_rx_beq_pps != 0) or (bps_tokens < info.pkt_len and self.cfg.global_rx_beq_bps != 0):
                    await Timer(5, "ns")
                    pps_tokens = (
                        self.pps_token_producer_ptr - self.pps_token_consumer_ptr
                        if self.pps_token_producer_ptr >= self.pps_token_consumer_ptr
                        else self.pps_token_producer_ptr + 1024 - self.pps_token_consumer_ptr
                    )
                    bps_tokens = (
                        self.bps_token_producer_ptr - self.bps_token_consumer_ptr
                        if self.bps_token_producer_ptr >= self.bps_token_consumer_ptr
                        else self.bps_token_producer_ptr + 65536 - self.bps_token_consumer_ptr
                    )

                # await self.interfaces.beq2net_if.send(random.randint(0, 255), byte_data, user0, None)
                await self.interfaces.beq2net_if.send(pkt_id, byte_data, user0, None)
                pkt_id += 1
                self.pps_token_consumer_ptr = (self.pps_token_consumer_ptr + 1) % 1024
                self.bps_token_consumer_ptr = (self.bps_token_consumer_ptr + info.pkt_len) % 65536

    async def _process_beq2net_qos(self):
        pps_token_add = self.cfg.global_rx_beq_pps / 1000
        bps_token_add = self.cfg.global_rx_beq_bps / 1000 / 8
        while True:
            await Timer(5, "ns")
            pps_tokens = (
                self.pps_token_producer_ptr - self.pps_token_consumer_ptr
                if self.pps_token_producer_ptr >= self.pps_token_consumer_ptr
                else self.pps_token_producer_ptr + 1024 - self.pps_token_consumer_ptr
            )
            bps_tokens = (
                self.bps_token_producer_ptr - self.bps_token_consumer_ptr
                if self.bps_token_producer_ptr >= self.bps_token_consumer_ptr
                else self.bps_token_producer_ptr + 65536 - self.bps_token_consumer_ptr
            )
            if pps_tokens < 100:
                self.pps_token_producer_ptr = (self.pps_token_producer_ptr + pps_token_add * 5) % 1024

            if bps_tokens < 4096:
                self.bps_token_producer_ptr = (self.bps_token_producer_ptr + bps_token_add * 5) % 65536

    async def _process_drop(self):
        await RisingEdge(self.dut.clk)
        while True:
            if self.dut.u_virtio_top.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_info_rd_rsp_vld.value == 1:
                exp_gen = int(self.dut.u_virtio_top.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_info_rd_rsp_generation.value)
                if self.pkt_beq2net_queue.empty():
                    raise Exception("pkt_beq2net_queue is empty")
                info = self.pkt_beq2net_queue.get_nowait()
                bkt_ff_usedw = int(self.dut.u_virtio_top.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.bkt_ff_usedw.value)
                bkt_ff_pempty = int(self.dut.u_virtio_top.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.bkt_ff_pempty.value)
                drop_random = int(self.dut.u_virtio_top.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_random.value)
                time_now = int(self.dut.u_virtio_top.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.time_stamp.value)
                time_send = int(self.dut.u_virtio_top.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_time_ram_rdata.value)
                cnt = int(self.dut.u_virtio_top.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.idx_per_queue_rdata.value)
                send_cnt = cnt & 0xFF
                rsv_cnt = (cnt >> 8) & 0xFF
                info.gen_drop = 0
                info.csum_drop = 0
                info.time_drop = 0
                info.rand_drop = 0
                info.empty_drop = 0
                info.data_vld = 0
                info.qos_en  = int(self.dut.u_virtio_top.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_info_rd_rsp_qos_enable.value)
                if info.act_gen != exp_gen:
                    info.gen_drop = 1

                if info.csum_en == 1 and info.need_vld == 1:
                    if info.eth_info.net_type in ["ipv4", "ipv6"]:

                        if info.eth_info.trans_type in ["tcp", "udp"]:
                            info.data_vld = 1

                            if info.eth_info.trans_info.csum_err:
                                info.csum_drop = 1

                    if info.eth_info.net_type == "ipv4":
                        if info.eth_info.net_info.ihl != 5:
                            info.csum_drop = 0
                            info.data_vld = 0
                        else:
                            if (info.eth_info.net_info.flags & 0b1) == 0 and info.eth_info.net_info.frag == 0:
                                if info.eth_info.net_info.csum_err:
                                    info.csum_drop = 1
                            else:
                                info.csum_drop = 0
                                info.data_vld = 0

                if 0 < self.cfg.global_rx_random_sel < 8 and bkt_ff_usedw < 256:
                    if (drop_random & (2 ** (self.cfg.global_rx_random_sel + 1) - 1)) == 0:
                        info.rand_drop = 1

                if 0 < self.cfg.global_rx_time_sel < 8 and bkt_ff_usedw < 512 and send_cnt != rsv_cnt:
                    if (time_now - time_send) < 0:
                        time_now = time_now + 65536
                    if (time_now - time_send) > (1 << self.cfg.global_rx_time_sel):
                        info.time_drop = 1

                if bkt_ff_pempty:
                    info.empty_drop = 1

                if not info.gen_drop and not info.csum_drop and not info.time_drop and not info.rand_drop and not info.empty_drop:
                    undrop_flag = 1
                else:
                    undrop_flag = 0
                if self.drop_queue.full():
                    raise Exception("drop_queue err")
                self.drop_queue.put_nowait((undrop_flag, info))

            await RisingEdge(self.dut.clk)

    async def _process_qos_req(self):
        while True:
            if self.drop_queue.empty():
                await Timer(5, "ns")
                continue
            undrop_flag, info = self.drop_queue.get_nowait()
            # self.log.error(f"qos en {info.qos_en}")
            if info.qos_en == 1:
                req_trans = await self.interfaces.rx_qos.query_req_if.recv()
                if req_trans.uid != info.unit:
                    self.log.error(f" exp: {info.unit} act: {req_trans.uid}")
                    raise Exception("qos_req_uid is fall")

            if self.qos_req_queue.full():
                raise Exception("qos_req_queue is full")
            self.qos_req_queue.put_nowait((undrop_flag, info))

    async def _process_qos_rsp(self):
        while True:
            if self.qos_req_queue.empty():
                await Timer(5, "ns")
                continue
            undrop_flag, info = self.qos_req_queue.get_nowait()
            rsp_trans = self.interfaces.rx_qos.query_rsp_if._transaction_obj()
            if random.random() < self.cfg.random_qos or not info.qos_en:
                info.qos_ok = 1
            else:
                info.qos_ok = 0
            rsp_trans.ok = info.qos_ok
            if undrop_flag and info.qos_ok:
                if info.qos_en:
                    self.qos_rsp_queue.put_nowait(info)
                info.drop = 0
                self.rx_buf_info[info.qid].append(info)
                self.rx_buf_data[info.qid].append(self.rx_pkt_list[info.qid].pop(0))
                self.rx_buf_pkt_cnt = self.rx_buf_pkt_cnt + 1
            else:
                self.rx_buf_drop_cnt = self.rx_buf_drop_cnt + 1
                info.drop = 1
                self.rx_buf_info[info.qid].append(info)
                self.rx_pkt_list[info.qid].pop(0)

            if info.qos_en:
                await self.interfaces.rx_qos.query_rsp_if.send(rsp_trans)

    async def _process_qos_update(self):
        while True:
            if self.interfaces.rx_qos.update_if.empty():
                await Timer(5, "ns")
                continue
            up_trans = self.interfaces.rx_qos.update_if.recv_nowait()
            if self.qos_rsp_queue.empty():
                raise Exception("drop_info_queue is empty")
            info = self.qos_rsp_queue.get_nowait()

            if info.pkt_len != up_trans.len.value:
                self.log.error(int(up_trans.len.value))
                self.log.error(info.pkt_len)
                self.log.error(info)
                raise Exception("qos_up len is err")
            if info.unit != up_trans.uid.value:
                self.log.error(info.unit, int(up_trans.uid.value))
                raise Exception("qos_up uid is err")
            if 1 != up_trans.pkt_num.value:
                raise Exception("qos_up pkt_num is err")

    async def _process_not_avail_id_drop(self):
        await RisingEdge(self.dut.clk)
        while True:
            for qid in self.rx_buf_info.keys():
                while True:
                    if len(self.rx_buf_info[qid]) > 0 and self.rx_buf_info[qid][0].drop:
                        info = self.rx_buf_info[qid].pop(0)
                        # self.log.error(f"rx_buf_info 1:{info}")
                        self.net_rx_info[qid].append(info)
                    else:
                        break
            if self.dut.u_virtio_top.u_virtio_desc_engine_top.net_rx_alloc_slot_rsp_rdy.value and self.dut.u_virtio_top.u_virtio_desc_engine_top.net_rx_alloc_slot_rsp_vld.value:
                qid = int(self.dut.u_virtio_top.u_virtio_desc_engine_top.net_rx_alloc_slot_rsp_dat.vq.qid.value)
                local_ring_empty = self.dut.u_virtio_top.u_virtio_desc_engine_top.net_rx_alloc_slot_rsp_dat.local_ring_empty.value
                q_stat_doing = self.dut.u_virtio_top.u_virtio_desc_engine_top.net_rx_alloc_slot_rsp_dat.q_stat_doing.value
                not_drop = not local_ring_empty and q_stat_doing
                pkt = self.rx_buf_data[qid].pop(0)
                info = self.rx_buf_info[qid].pop(0)
                if not_drop:
                    self.net_rx_info[info.qid].append(info)
                    self.net_rx_data[info.qid].append(pkt)
                    self.net_rx_pkt_cnt = self.net_rx_pkt_cnt + 1
                    self.net_rx_cnt = self.net_rx_cnt + 1
                else:
                    info.drop = 1
                    self.net_rx_info[info.qid].append(info)
                    self.net_rx_drop_cnt = self.net_rx_drop_cnt + 1
                    self.net_rx_cnt = self.net_rx_cnt + 1
            await RisingEdge(self.dut.clk)

    def drop_pkt(self, vq):
        qid, typ = VirtioVq.vq2qid(vq)
        vq_str = VirtioVq.vq2str(vq)
        seq_num = None
        while qid in self.net_rx_info.keys() and len(self.net_rx_info[qid]) > 0:
            info = self.net_rx_info[qid][0]
            if info.drop:
                self.net_rx_info[qid].pop(0)
                seq_num = info.seq_num
                self.log.info("{} seq_num {} drop".format(vq_str, seq_num))
            else:
                # seq_num = info.seq_num
                # ref_info = info
                # ref_pkt  = self.net_rx_data[qid][0]
                # ref_data = ((2).to_bytes(1, byteorder="little") if ref_info.data_vld else b'\x00') + b'\x00'*11 + ref_pkt
                # self.log.error(f"{ref_data.hex()}")
                # self.log.error(f"seq_num = info.seq_num{seq_num}")
                break
        return seq_num

    async def _process_rx_check(self):
        while True:
            if self.rx_check_queue.empty():
                await Timer(5, "ns")
                continue

            vq, mbufs, mbufs_idx, forced_shutdown_num = self.rx_check_queue.get_nowait()

            qid, typ = VirtioVq.vq2qid(vq)
            vq_str = VirtioVq.vq2str(vq)
            seq_num = self.drop_pkt(vq)
            if len(mbufs) > 0:
                for i in range(len(mbufs)):
                    mbuf = mbufs[i]
                    mbuf_idx = mbufs_idx[i]
                    seq_num = self.drop_pkt(vq)
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
                    ref_info = self.net_rx_info[qid].pop(0)
                    ref_pkt = self.net_rx_data[qid].pop(0)
                    ref_data = ((2).to_bytes(1, byteorder="little") if ref_info.data_vld else b'\x00') + b'\x00' * 11 + ref_pkt
                    if ref_data != pkt:
                        self.log.error("{} total_len {} info: {}".format(vq_str, len(pkt), ref_info))
                        self.log.error(f"ref_pkt_len: {len(ref_data) - 12}\n ref: {ref_data.hex()}")
                        self.log.error(f"cur_pkt_len: {len(pkt) - 12}\n cur: {pkt.hex()}")
                        self.log.error(f"idx is:{mbuf_idx}")
                        self.log.error(f"doing {self.doing}")

                        for j in range(len(self.net_rx_data[qid])):
                            ref_info = self.net_rx_info[qid][j]
                            ref_pkt = self.net_rx_data[qid][j]
                            ref_data = ((2).to_bytes(1, byteorder="little") if ref_info.data_vld else b'\x00') + b'\x00' * 11 + ref_pkt
                            self.log.error(f"j{j} ref_pkt_len: {len(ref_data) - 12}\n ref: {ref_data.hex()}")

                        raise Exception("rx pkt is mismatch")
                    self.log.info(f"{vq_str} seq_num {ref_info.seq_num} pass ")
                    seq_num = ref_info.seq_num

                    self.pkt_time_last = get_sim_time("ns")
                    self.pps_cnt += 1
                    self.bps_cnt += len(ref_data) - 12  # B
                if self.pkt_time_start is None:
                    self.pkt_time_start = get_sim_time("ns")
                    self.pps_cnt = 0
                    self.bps_cnt = 0

            if forced_shutdown_num > 0:
                for i in range(forced_shutdown_num):
                    seq_num = self.drop_pkt(vq)
                    ref_info = self.net_rx_info[qid].pop(0)
                    ref_pkt = self.net_rx_data[qid].pop(0)
                    seq_num = ref_info.seq_num
                    self.log.info(f"{vq_str} seq_num {ref_info.seq_num} forced_shutdown drop ")

            seq_num_drop = self.drop_pkt(vq)
            if seq_num_drop is not None:
                seq_num = seq_num_drop
            if seq_num == (self.cfg.max_seq) - 1:
                self.rx_check_result[qid] = True
            else:
                # self.log.error(f"self.net_rx_cnt{self.net_rx_cnt}")
                # self.log.error(f"rx_check {seq_num}")
                # self.log.error(f"net_rx_cnt {self.net_rx_cnt}")
                # self.log.error(f"net_rx_pkt_cnt {self.net_rx_pkt_cnt}")
                # self.log.error(f"net_rx_drop_cnt {self.net_rx_drop_cnt}")
                # read_used_idx = await self.pmd.virtq[vq].read_used_idx()
                # self.log.error(f"used_idx_ci {self.pmd.virtq[vq].used_idx_ci}")
                # self.log.error(f"read_used_idx {read_used_idx}")
                # self.log.error(f"used_ci {self.pmd.virtq[vq].used_idx_ci}")
                pass

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
