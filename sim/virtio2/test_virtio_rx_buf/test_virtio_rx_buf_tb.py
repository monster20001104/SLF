# -*- coding: utf-8 -*-
import sys

sys.path.append("../../common")
import ding_robot
import itertools
import logging
import os
import random
import cocotb_test.simulator

import logging
from logging.handlers import RotatingFileHandler

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
from cocotb.regression import TestFactory

from define_virtio_rx_buf import *

from bus.beq_data_bus import BeqBus
from drivers.beq_data_bus import BeqTxqMaster
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster

# conf.encoding = 'utf-8'
# random.seed(42)


class TB(object):
    def __init__(self, dut, cfg):
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        # cfg
        self.cfg = cfg
        self.cfg.data_width = dut.DATA_WIDTH.value
        self.cfg.gen_width = dut.GEN_WIDTH.value
        self.cfg.qid_width = dut.QID_WIDTH.value
        self.cfg.dev_width = dut.DEV_WIDTH.value
        self.cfg.uid_width = dut.UID_WIDTH.value
        self.cfg.BKT_FF_DEPTH = dut.BKT_FF_DEPTH.value
        # self.cfg.exp_gen = randbit(self.cfg.gen_width)
        self.cfg.send_num = 0
        self.cfg.drop_num = 0
        self.cfg.rsp_drop = 0
        self.cfg.rsp_num = 0
        self.cfg.req_num = 0
        self.cfg.info_out_num = 0
        self.dut = dut

        self.list_init()
        self.mem_init()

        # self.log = logging.getLogger("cocotb.tb")
        # self.log.setLevel(logging.DEBUG)
        self.beq2net = BeqTxqMaster(BeqBus.from_prefix(dut, "beq2net"), dut.clk, dut.rst)
        self.pkt_beq2net_queue = Queue(maxsize=32)

        self.DropInfoSlaver = DropInfoSlaver(
            rd_req_bus=DropInfoReqBus.from_prefix(dut, "drop_info_rd"),
            rd_rsp_bus=DropInfoRspBus.from_prefix(dut, "drop_info_rd"),
            wr_bus=None,
            clock=dut.clk,
            reset=dut.rst,
            ready_latency=1,
        )
        self.DropInfoSlaver.set_callback(self.drop_info_slaver_cb)
        self.drop_info_queue = Queue(maxsize=32)

        self.drop_queue = Queue(maxsize=64)
        self.drop_data_queue = Queue(maxsize=64)

        self.QosReqSlaver = QosReqSlaver(QosReqBus.from_prefix(dut, "qos_query_req"), dut.clk, dut.rst)
        self.qos_req_queue = Queue(maxsize=128)
        self.QosRspMaster = QosRspMaster(QosRspBus.from_prefix(dut, "qos_query_rsp"), dut.clk, dut.rst)
        self.qos_rsp_queue = Queue(maxsize=64)
        self.QosUpSlaver = QosUpSlaver(QosUpBus.from_prefix(dut, "qos_update"), dut.clk, dut.rst)
        self.qos_update_queue = Queue(maxsize=64)

        self.PerQueSlaver = PerQueSlaver(
            rd_req_bus=PerQueReqBus.from_prefix(dut, "req_idx_per_queue_rd"),
            rd_rsp_bus=PerQueRspBus.from_prefix(dut, "req_idx_per_queue_rd"),
            wr_bus=None,
            clock=dut.clk,
            reset=dut.rst,
            ready_latency=1,
        )
        self.PerQueSlaver.set_callback(self.per_que_slaver_cb)

        self.PerDevSlaver = PerDevSlaver(
            rd_req_bus=PerDevReqBus.from_prefix(dut, "req_idx_per_dev_rd"),
            rd_rsp_bus=PerDevRspBus.from_prefix(dut, "req_idx_per_dev_rd"),
            wr_bus=None,
            clock=dut.clk,
            reset=dut.rst,
            ready_latency=1,
        )
        self.PerDevSlaver.set_callback(self.per_dev_slaver_cb)

        self.InfoOutSlaver = InfoOutSlaver(InfoOutBus.from_prefix(dut, "info_out"), dut.clk, dut.rst)
        self.info_out_queue = Queue(maxsize=512)

        self.DataReqMaster = DataReqMaster(DataReqBus.from_prefix(dut, "rd_data_req"), dut.clk, dut.rst)
        self.DataRspSlaver = DataRspSlaver(DataRspBus.from_prefix(dut, "rd_data_rsp"), dut.clk, dut.rst)

        self.mlitemaster = MliteBusMaster(MliteBus.from_prefix(dut, "dfx_if"), dut.clk)
        # self.dfx = MliteBusMaster(MliteBus.from_prefix(dut, "dfx_if"), dut.clk)

        clk = Clock(dut.clk, 5, units="ns")
        cocotb.start_soon(clk.start(start_high=False))
        self.pkt_qos_queue = Queue(maxsize=8)
        self.info_data_queue = Queue(maxsize=8)

    async def cycle_reset(self):
        # self.dut.drop_time_sel.value = self.cfg.time_sel
        # self.dut.drop_random_sel.value = self.cfg.random_sel
        # self.dut.csum_flag.value = self.cfg.csum_ctrl
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    def set_idle_generator(self, generator=None):
        # pass
        if generator:
            self.beq2net.set_idle_generator(generator)
            self.QosRspMaster.set_idle_generator(generator)
            self.DataReqMaster.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        # pass
        if generator:
            self.QosReqSlaver.set_backpressure_generator(generator)
            self.QosUpSlaver.set_backpressure_generator(generator)
            self.InfoOutSlaver.set_backpressure_generator(generator)
            self.DataRspSlaver.set_backpressure_generator(generator)

    def mem_init(self):
        self.per_que_mem_dev_id = CtxRam(2**self.cfg.qid_width)
        self.per_que_mem_limit_que = CtxRam(2**self.cfg.qid_width)
        self.per_dev_mem_limit_dev = CtxRam(2**self.cfg.dev_width)
        for i in range(2**self.cfg.qid_width):
            # self.per_que_mem_dev_id.write(i, 8)
            # self.per_que_mem_dev_id.write(i, randbit(self.cfg.dev_width))
            self.per_que_mem_dev_id.write(i, i)
            self.per_que_mem_limit_que.write(i, random.randint(1, 10))
        for i in range(2**self.cfg.dev_width):
            self.per_dev_mem_limit_dev.write(i, random.randint(1, 10))

    def list_init(self):
        self.pkt_list = []
        self.pkt_send_list = []
        self.info_send_list = []
        self.info_list = []
        self.info_out_list = []
        self.exp_gen_list = []
        self.recv_num_ram = []
        self.qos_drop_ram = []
        self.pfull_drop_ram = []
        self.csum_drop_ram = []
        self.ram_rd_drop_ram = []
        self.not_ready_drop_pkt_ram = []

        self.recv_num_ram_total = 0
        self.qos_drop_ram_total = 0
        self.pfull_drop_ram_total = 0
        self.csum_drop_ram_total = 0
        self.gen_rd_drop_total = 0
        self.not_ready_drop_pkt_ram_total = 0

        for _ in range(2**self.cfg.qid_width):
            self.pkt_list.append([])
        for _ in range(2**self.cfg.qid_width):
            self.pkt_send_list.append([])
        for _ in range(2**self.cfg.qid_width):
            self.info_send_list.append([])
        for _ in range(2**self.cfg.qid_width):
            self.info_list.append([])
        for _ in range(2**self.cfg.qid_width):
            self.exp_gen_list.append(randbit(self.cfg.gen_width))
        for _ in range(2**self.cfg.qid_width):
            self.qos_drop_ram.append(0)
            self.pfull_drop_ram.append(0)
            self.not_ready_drop_pkt_ram.append(0)
            self.recv_num_ram.append(0)
            self.csum_drop_ram.append(0)
            self.ram_rd_drop_ram.append(0)

    async def _process_beq2net(self):
        for _ in range(self.cfg.max_seq):
            info, eth_pkt = generate_beq2net_pkt(self.cfg)
            info.qid = randbit(self.cfg.qid_width)
            # info.qid = 0
            if random.random() < self.cfg.random_gen_err:
                while True:
                    info.act_gen = randbit(self.cfg.gen_width)
                    if info.act_gen != self.exp_gen_list[info.qid]:
                        break
            else:
                info.act_gen = self.exp_gen_list[info.qid]
            info.pkt_len = len(eth_pkt)
            byte_data = bytes(eth_pkt)

            if random.random() < self.cfg.random_need_vld:
                info.need_vld = 1
            else:
                info.need_vld = 0

            await self.pkt_beq2net_queue.put(info)
            self.pkt_list[info.qid].append(byte_data)
            user0 = randbit(40)
            user0 = (user0 & ~0xFF) | info.qid
            user0 = (user0 & ~(0xFF << 32)) | info.act_gen << 32
            # user1 = randbit(64)
            user0 = (user0 & ~(0x1 << 16)) | info.need_vld << 16
            # logging.error(info)
            await self.beq2net.send(
                qid=random.randint(0, 255),
                data=byte_data,
                user0=user0,
            )
            self.recv_num_ram[info.qid] += 1
            self.recv_num_ram_total += 1
            # user1=user1,

    def drop_info_slaver_cb(self, req_trans):
        if self.pkt_beq2net_queue.empty():
            raise Exception("pkt_beq2net_queue is empty")
        info = self.pkt_beq2net_queue.get_nowait()
        if req_trans.req_qid != info.qid:
            print(int(req_trans.req_qid))
            # print_tree(info)
            raise Exception("drop_info_req_err")

        rsp_trans = DropInfoRspTrans()
        rsp_trans.rsp_generation = self.exp_gen_list[info.qid]
        info.unit = randbit(self.cfg.uid_width)
        rsp_trans.rsp_qos_unit = info.unit
        if random.random() <= self.cfg.random_qos_en:
            info.qos_enable = 1
        else:
            info.qos_enable = 0
        rsp_trans.rsp_qos_enable = info.qos_enable
        if self.drop_info_queue.full():
            raise Exception("drop_info_queue is full")
        self.drop_info_queue.put_nowait(info)
        return rsp_trans

    async def _process_drop(self):
        await RisingEdge(self.dut.clk)
        while True:
            if self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_info_rd_rsp_vld.value == 1:
                if self.drop_info_queue.empty():
                    raise Exception("drop_info_queue is empty")
                info = self.drop_info_queue.get_nowait()
                bkt_ff_usedw = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.bkt_ff_usedw.value)
                # bkt_ff_pempty = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.bkt_ff_pempty.value)
                drop_random = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_random.value)
                time_now = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.time_stamp.value)
                time_send = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_time_ram_rdata.value)
                cnt = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.idx_per_queue_rdata.value)
                send_cnt = cnt & 0xFF
                rsv_cnt = (cnt >> 8) & 0xFF
                info.gen_drop = 0
                info.csum_drop = 0
                info.time_drop = 0
                info.rand_drop = 0
                info.empty_drop = 0
                info.vld_change = 0
                # print(info)
                if info.act_gen != self.exp_gen_list[info.qid]:
                    info.gen_drop = 1

                if self.cfg.csum_ctrl == 1 and info.need_vld == 1:
                    if info.eth_info.net_type in ["ipv4", "ipv6"]:

                        if info.eth_info.trans_type in ["tcp", "udp"]:
                            info.vld_change = 1

                            if info.eth_info.trans_info.csum_err:
                                info.csum_drop = 1

                    if info.eth_info.net_type == "ipv4":
                        if info.eth_info.net_info.ihl != 5:
                            info.csum_drop = 0
                            info.vld_change = 0
                        else:
                            if (info.eth_info.net_info.flags & 0b1) == 0 and info.eth_info.net_info.frag == 0:
                                if info.eth_info.net_info.csum_err:
                                    info.csum_drop = 1
                            else:
                                info.csum_drop = 0
                                info.vld_change = 0

                if 0 < self.cfg.random_sel < 8 and bkt_ff_usedw < self.cfg.BKT_FF_DEPTH / 4:
                    if (drop_random & (2 ** (self.cfg.random_sel + 1) - 1)) == 0:
                        info.rand_drop = 1

                if 0 < self.cfg.time_sel < 8 and bkt_ff_usedw < self.cfg.BKT_FF_DEPTH / 2 and send_cnt != rsv_cnt:
                    if (time_now - time_send) < 0:
                        time_now = time_now + 65536
                    if (time_now - time_send) > (1 << self.cfg.time_sel):
                        info.time_drop = 1

                # if bkt_ff_pempty:
                #     info.empty_drop = 1

                # if not info.gen_drop and not info.csum_drop and not info.time_drop and not info.rand_drop and not info.empty_drop:
                #     undrop_flag = 1
                # else:
                #     undrop_flag = 0
                if self.drop_queue.full():
                    raise Exception("drop_queue err")
                self.drop_queue.put_nowait(info)

            await RisingEdge(self.dut.clk)

    async def _process_qos_req(self):
        for _ in range(4):
            self.qos_req_queue.put_nowait(None)
        while True:
            await RisingEdge(self.dut.clk)
            if not self.drop_queue.empty():
                info = self.drop_queue.get_nowait()

                if info.qos_enable:
                    req_trans = await self.QosReqSlaver.recv()
                    if req_trans.uid != info.unit:
                        print(int(req_trans.uid))
                        print(int(info.unit))
                        print(int(info.qid))
                        raise Exception("qos_req_uid is fall")
                if self.qos_req_queue.full():
                    raise Exception("qos_req_queue is full")
                self.qos_req_queue.put_nowait(info)

            else:
                if self.qos_req_queue.full():
                    raise Exception("qos_req_queue is full")
                self.qos_req_queue.put_nowait(None)

    async def _process_qos_rsp(self):
        while True:
            await RisingEdge(self.dut.clk)
            if not self.qos_req_queue.empty():
                info = self.qos_req_queue.get_nowait()
                if info is not None:
                    info.qos_drop = 0
                    if info.qos_enable == 1:
                        rsp_trans = QosRspTrans()
                        if random.random() <= self.cfg.random_qos:
                            info.qos_ok = 0
                        else:
                            info.qos_ok = 1
                        rsp_trans.ok = info.qos_ok
                        if info.qos_ok == 0:
                            info.qos_drop = 1
                        self.QosRspMaster.send_nowait(rsp_trans)

                    if self.qos_rsp_queue.full():
                        raise Exception("qos_rsp_queue is full")
                    self.qos_rsp_queue.put_nowait(info)

    async def _process_drop_data(self):
        await RisingEdge(self.dut.clk)
        while True:
            if self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_qos_vld.value == 1 and self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.drop_qos_rdy.value == 1:
                if self.qos_rsp_queue.empty():
                    raise Exception("qos_rsp_queue is empty")
                info = self.qos_rsp_queue.get_nowait()
                # self.log.error("1")
                bkt_ff_pempty = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_drop.bkt_ff_pempty.value)

                if bkt_ff_pempty:
                    info.empty_drop = 1

                if not info.gen_drop and not info.csum_drop and not info.time_drop and not info.rand_drop and not info.empty_drop and not info.qos_drop:
                    # self.log.error("2")
                    undrop_flag = 1
                else:
                    # self.log.error("3")
                    undrop_flag = 0

                if undrop_flag:
                    if self.drop_data_queue.full():
                        raise Exception("drop_data_queue is full")
                    self.info_list[info.qid].append(info)
                    self.pkt_send_list[info.qid].append(self.pkt_list[info.qid].pop(0))
                    self.cfg.send_num = self.cfg.send_num + 1
                    self.drop_data_queue.put_nowait(info)
                else:
                    self.cfg.drop_num = self.cfg.drop_num + 1
                    self.pkt_list[info.qid].pop(0)

                if info != None:
                    if info.gen_drop:
                        pass
                    elif info.csum_drop:
                        self.csum_drop_ram[info.qid] += 1
                    elif info.qos_drop:
                        self.qos_drop_ram[info.qid] += 1
                    elif info.time_drop or info.rand_drop or info.empty_drop:
                        self.pfull_drop_ram[info.qid] += 1

            await RisingEdge(self.dut.clk)

    async def _process_qos_update(self):
        while True:
            up_trans = await self.QosUpSlaver.recv()
            if self.drop_data_queue.empty():
                raise Exception("drop_data_queue is empty")
            info = self.drop_data_queue.get_nowait()

            while not info.qos_enable:
                if self.drop_data_queue.empty():
                    raise Exception("drop_data_queue is empty")
                info = self.drop_data_queue.get_nowait()

            if info.qos_enable:
                if info.unit != up_trans.uid.value:
                    print(info.unit, int(up_trans.uid.value))
                    print(info)
                    raise Exception("qos_update uid is err")
                if info.pkt_len != up_trans.len.value:
                    print(info.pkt_len, int(up_trans.len.value))
                    print(info)
                    raise Exception("qos_update len is err")
                if 1 != up_trans.pkt_num.value:
                    raise Exception("qos_update pkt_num is err")

    def per_que_slaver_cb(self, req_trans):
        qid = req_trans.req_qid
        rsp_trans = PerQueRspTrans()
        rsp_trans.rsp_dev_id = self.per_que_mem_dev_id.read(qid)
        rsp_trans.rsp_idx_limit_per_queue = self.per_que_mem_limit_que.read(qid)
        return rsp_trans

    def per_dev_slaver_cb(self, req_trans):
        dev = req_trans.req_dev_id
        rsp_trans = PerDevRspTrans()
        rsp_trans.rsp_idx_limit_per_dev = self.per_dev_mem_limit_dev.read(dev)
        return rsp_trans

    async def _process_info_out(self):
        for _ in range(400):
            self.info_out_queue.put_nowait(None)

        while True:
            await RisingEdge(self.dut.clk)
            if not self.InfoOutSlaver.empty():
                trans = self.InfoOutSlaver.recv_nowait()
                req_trans = DataReqTrans()
                qid = trans.data_vq_gid
                if len(self.info_list[qid]) == 0:
                    print(int(trans.data_vq_gid))
                    raise Exception("info_list empty err")
                info = self.info_list[qid].pop(0)
                req_trans.data_pkt_id = trans.data_pkt_id
                req_trans.data_vq_gid = trans.data_vq_gid
                req_trans.data_vq_typ = 2
                if random.random() < self.cfg.random_rsp_drop:
                    req_trans.data_drop = 1
                    self.cfg.rsp_drop = self.cfg.rsp_drop + 1
                    info.drop = 1
                else:
                    req_trans.data_drop = 0
                    info.drop = 0
                self.info_send_list[qid].append(info)
                self.info_out_list.append(req_trans)
                if self.info_out_queue.full():
                    raise Exception("info_out_queue err")
                self.cfg.info_out_num += 1
                self.info_out_queue.put_nowait(1)
            else:
                self.info_out_queue.put_nowait(None)

    async def _process_data_req(self):
        while True:
            await RisingEdge(self.dut.clk)

            if not self.info_out_queue.empty():
                result = self.info_out_queue.get_nowait()
                if result is None:
                    continue

            if self.cfg.random_data_req:
                random_index = random.randint(0, len(self.info_out_list) - 1)
            else:
                random_index = 0
            req_trans = self.info_out_list.pop(random_index)
            self.cfg.req_num = self.cfg.req_num + 1
            if req_trans.data_drop == 1:
                self.not_ready_drop_pkt_ram[req_trans.data_vq_gid] += 1
                self.not_ready_drop_pkt_ram_total += 1
            await self.DataReqMaster.send(req_trans)

    async def _process_data_rsp(self):
        seq_num = self.cfg.max_seq
        i = 0
        last_seq_num = -1
        while seq_num > self.cfg.drop_num + self.cfg.rsp_drop:
            # rsp_trans = await self.DataRspSlaver.recv()
            act_seq_num = seq_num - self.cfg.drop_num - self.cfg.rsp_drop
            if act_seq_num != last_seq_num:
                if act_seq_num % 1000 == 0:
                    print(act_seq_num)
                i = 0
            else:
                i += 1
                if i == 10000:
                    cfg_send_num = self.cfg.send_num
                    cfg_drop_num = self.cfg.drop_num
                    cfg_rsp_drop = self.cfg.rsp_drop
                    cfg_rsp_num = self.cfg.rsp_num
                    cfg_req_num = self.cfg.req_num
                    cfg_info_num = self.cfg.info_out_num
                    self.log.warning(
                        f"act_seq_num: {act_seq_num}  send_num:{cfg_send_num}   drop_num:{cfg_drop_num} cfg_info_num:{cfg_info_num} cfg_req_num: {cfg_req_num} rsp_drop:{cfg_rsp_drop} rsp_num:{cfg_rsp_num}"
                    )
                    self.log.warning(
                        f"""

                        recv_num_ram_total: {self.recv_num_ram_total}
                        qos_drop_ram_total: {self.qos_drop_ram_total}
                        pfull_drop_ram_total: {self.pfull_drop_ram_total}
                        csum_drop_ram_total: {self.csum_drop_ram_total}
                        gen_rd_drop_total: {self.gen_rd_drop_total}
                        not_ready_drop_pkt_ram_total: {self.not_ready_drop_pkt_ram_total}
                        
                        """
                    )
                    for index in range(len(self.info_list)):
                        self.log.warning(f"info_list {index}:{self.info_list[index]}")
                    for index in range(len(self.info_send_list)):
                        self.log.warning(f"info_send_list {index}:{self.info_send_list[index]}")
                    for index in range(len(self.info_out_list)):
                        self.log.warning(f"info_out_list {index}:{self.info_out_list[index]}")
                    raise Exception("seq_num err")
            last_seq_num = act_seq_num
            await RisingEdge(self.dut.clk)
            if not self.DataRspSlaver.empty():
                rsp_trans = self.DataRspSlaver.recv_nowait()
                self.cfg.rsp_num = self.cfg.rsp_num + 1
            else:
                continue
            act_sbd = DataRspSbd().unpack(rsp_trans.sbd)
            qid = act_sbd.vq_qid
            while True:
                if len(self.info_send_list[qid]) == 0:
                    print(qid)
                    raise Exception("_process_data_rsp err")
                info = self.info_send_list[qid].pop(0)
                pkt = self.pkt_send_list[qid].pop(0)
                if info.drop == 0:
                    break
            byte_line = self.cfg.data_width // 8
            exp_length = info.pkt_len + 12
            sbd = DataRspSbd()
            sbd.vq_typ = 1
            sbd.vq_qid = qid
            sbd.length = exp_length
            data = pkt
            sty = int((self.cfg.data_width / 8) - 12)
            mty = int((byte_line - (exp_length + sty)) % byte_line)
            cycles = int((sty + exp_length + byte_line - 1) // byte_line)
            for i in range(cycles):
                act_sbd = DataRspSbd().unpack(rsp_trans.sbd)
                act_sty = rsp_trans.sty
                act_mty = rsp_trans.mty
                act_sop = rsp_trans.sop
                act_eop = rsp_trans.eop
                data_len = len(rsp_trans.data)
                act_data = rsp_trans.data if not act_eop else rsp_trans.data[act_mty * 8 : data_len - 1]

                exp_sbd = sbd
                exp_sty = sty if (i == 0) else 0
                exp_mty = mty if (i == cycles - 1) else 0
                exp_sop = i == 0
                exp_eop = i == cycles - 1
                if i == 0:
                    exp_data = info.vld_change << 161
                else:
                    local_len = byte_line - exp_sty - exp_mty
                    tmp = b"\x00" * exp_sty + data[0:local_len]
                    data = data[local_len:]
                    exp_data = int.from_bytes(tmp, byteorder="little")
                if i != cycles - 1:
                    rsp_trans = await self.DataRspSlaver.recv()
                else:
                    seq_num -= 1

                if exp_sbd != act_sbd:
                    exp_sbd.dis()
                    act_sbd.dis()
                    raise Exception("data_rsp sbd err")
                if exp_sty != act_sty:
                    print(exp_sty, act_sty)
                    raise Exception("data_rsp sty err")
                if exp_mty != act_mty:
                    print(exp_mty, act_mty)
                    raise Exception("data_rsp mty err")
                if exp_sop != act_sop:
                    raise Exception("data_rsp sop err")
                if exp_eop != act_eop:
                    raise Exception("data_rsp eop err")
                if exp_data != act_data:
                    print(hex(exp_data), hex(act_data))
                    print(info)
                    act_sbd.dis()
                    raise Exception("data_rsp data err")

        print(self.cfg.info_out_num)

    async def _process_notify_rsp_stop(self):
        await RisingEdge(self.dut.clk)
        while True:
            vld = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_linklist.notify_rsp_vld.value)
            rdy = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_linklist.notify_rsp_rdy.value)
            stop = int(self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_linklist.notify_rsp_sim_stop.value)
            if vld == 1 and stop == 0:
                for _ in range(20):
                    await RisingEdge(self.dut.clk)
                self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_linklist.notify_rsp_sim_stop.value = 1
                await RisingEdge(self.dut.clk)
            elif rdy == 1:
                self.dut.u_virtio_rx_buf_top.u_virtio_rx_buf_linklist.notify_rsp_sim_stop.value = 0

                await RisingEdge(self.dut.clk)
            else:
                await RisingEdge(self.dut.clk)

    # async def ram_test(self):
    #     ram_test_num = 10000

    #     for _ in range(ram_test_num):
    #         addr = randbit(16)
    #         act_data = await self.mlitemaster.read(addr)


async def normal_test(dut, idle_inserter, backpressure_inserter):
    # random.seed(123)
    cfg = Config()
    cfg.eth_cfg = Eth_Pkg_Cfg()
    cfg.max_seq = 10000
    cfg.random_qos_en = 0.9
    cfg.random_need_vld = 0.5
    cfg.csum_ctrl = 1
    cfg.time_sel = 3
    cfg.random_sel = 1
    cfg.random_gen_err = 0.01
    cfg.qos_en = 1
    cfg.random_qos = 0.01
    cfg.random_data_req = True
    cfg.random_rsp_drop = 0.01

    tb = TB(dut, cfg)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    cocotb.start_soon(tb._process_qos_req())
    cocotb.start_soon(tb._process_qos_rsp())
    cocotb.start_soon(tb._process_qos_update())
    cocotb.start_soon(tb._process_drop())
    cocotb.start_soon(tb._process_drop_data())
    cocotb.start_soon(tb._process_info_out())
    cocotb.start_soon(tb._process_data_req())
    await tb.cycle_reset()

    await tb.mlitemaster.write(0x0000_0000, cfg.csum_ctrl)
    await tb.mlitemaster.write(0x0000_0008, 0x21)
    await tb.mlitemaster.write(0x0000_0010, cfg.time_sel)
    await tb.mlitemaster.write(0x0000_0018, cfg.random_sel)
    await Timer(125000, "ns")
    cocotb.start_soon(tb._process_beq2net())
    # cocotb.start_soon(tb.ram_test())
    await cocotb.start_soon(tb._process_data_rsp())
    await Timer(1000, "ns")
    for qid in range(256):
        recv_num = await tb.mlitemaster.read(0x08_000 + qid * 8)
        csum_drop = await tb.mlitemaster.read(0x1E_000 + qid * 8)
        qos_drop = await tb.mlitemaster.read(0x1E_800 + qid * 8)
        pfull_drop = await tb.mlitemaster.read(0x1F_000 + qid * 8)
        not_ready_drop_pkt = await tb.mlitemaster.read(0x1F_800 + qid * 8)
        if recv_num != tb.recv_num_ram[qid]:
            raise ValueError(f"qid: {qid} recv_num: {recv_num} recv_num_ram:{tb.recv_num_ram[qid]}")
        if csum_drop != tb.csum_drop_ram[qid]:
            raise ValueError(f"qid: {qid} csum_drop: {csum_drop} csum_drop_ram:{tb.csum_drop_ram[qid]}")
        if qos_drop != tb.qos_drop_ram[qid]:
            raise ValueError(f"qid: {qid} qos_drop: {qos_drop} qos_drop_ram:{tb.qos_drop_ram[qid]}")
        if pfull_drop != tb.pfull_drop_ram[qid]:
            raise ValueError(f"qid: {qid} pfull_drop: {pfull_drop} pfull_drop_ram:{tb.pfull_drop_ram[qid]}")
        if not_ready_drop_pkt != tb.not_ready_drop_pkt_ram[qid]:
            raise ValueError(f"qid: {qid} pfull_drop: {not_ready_drop_pkt} pfull_drop_ram:{tb.not_ready_drop_pkt_ram[qid]}")

    for qid in range(256):
        await tb.mlitemaster.write(0x1E_000 + qid * 8, randbit(16))
        await tb.mlitemaster.write(0x1E_800 + qid * 8, randbit(16))
        await tb.mlitemaster.write(0x1F_000 + qid * 8, randbit(16))
        await tb.mlitemaster.write(0x1F_800 + qid * 8, randbit(16))
        await tb.mlitemaster.write(0x08_000 + qid * 8, randbit(16))

    for qid in range(256):
        recv_num = await tb.mlitemaster.read(0x08_000 + qid * 8)
        csum_drop = await tb.mlitemaster.read(0x1E_000 + qid * 8)
        qos_drop = await tb.mlitemaster.read(0x1E_800 + qid * 8)
        pfull_drop = await tb.mlitemaster.read(0x1F_000 + qid * 8)
        not_ready_drop_pkt = await tb.mlitemaster.read(0x1F_800 + qid * 8)
        if recv_num != 0:
            raise ValueError(f"qid: {qid} recv_num: {recv_num} ")
        if csum_drop != 0:
            raise ValueError(f"qid: {qid} csum_drop: {csum_drop} ")
        if qos_drop != 0:
            raise ValueError(f"qid: {qid} qos_drop: {qos_drop} ")
        if pfull_drop != 0:
            raise ValueError(f"qid: {qid} pfull_drop: {pfull_drop} ")
        if not_ready_drop_pkt != 0:
            raise ValueError(f"qid: {qid} pfull_drop: {not_ready_drop_pkt}")
    await Timer(1000, "ns")


async def bps_test(dut, idle_inserter, backpressure_inserter):
    random.seed(123)
    cfg = Config()
    cfg.eth_cfg = Eth_Pkg_Cfg()
    cfg.eth_cfg.test_mode = "bps"
    cfg.eth_cfg.random_vlan = 0
    cfg.eth_cfg.random_net_csum_err = 0
    cfg.eth_cfg.random_trans_csum_err = 0
    cfg.max_seq = 5000
    cfg.random_need_vld = 0.5
    cfg.random_qos_en = 1
    cfg.csum_ctrl = 1
    cfg.time_sel = 1
    cfg.random_sel = 1
    cfg.random_gen_err = 0
    cfg.qos_en = 1
    cfg.random_qos = 0
    cfg.random_data_req = False
    cfg.random_rsp_drop = 0
    tb = TB(dut, cfg)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    cocotb.start_soon(tb._process_qos_req())
    cocotb.start_soon(tb._process_qos_rsp())
    cocotb.start_soon(tb._process_qos_update())
    cocotb.start_soon(tb._process_drop())
    cocotb.start_soon(tb._process_drop_data())
    cocotb.start_soon(tb._process_info_out())
    cocotb.start_soon(tb._process_data_req())
    await tb.cycle_reset()
    await tb.mlitemaster.write(0x0000_0000, cfg.csum_ctrl)
    await tb.mlitemaster.write(0x0000_0008, 0x21)
    await tb.mlitemaster.write(0x0000_0010, cfg.time_sel)
    await tb.mlitemaster.write(0x0000_0018, cfg.random_sel)
    await Timer(125000, "ns")
    cocotb.start_soon(tb._process_beq2net())
    await cocotb.start_soon(tb._process_data_rsp())
    await Timer(1000, "ns")
    tb.log.warning(f"bps:{int(tb.dut.bps.value)}G")


async def pps_test(dut, idle_inserter, backpressure_inserter):
    random.seed(123)
    cfg = Config()
    cfg.eth_cfg = Eth_Pkg_Cfg()
    cfg.eth_cfg.random_vlan = 0
    cfg.eth_cfg.random_net_csum_err = 0
    cfg.eth_cfg.random_trans_csum_err = 0
    cfg.eth_cfg.test_mode = "pps"
    cfg.max_seq = 50000
    cfg.random_qos_en = 1
    cfg.random_need_vld = 0.5
    cfg.csum_ctrl = 1
    cfg.time_sel = 0
    cfg.random_sel = 0
    cfg.random_gen_err = 0
    cfg.qos_en = 1
    cfg.random_qos = 0
    cfg.random_data_req = False
    cfg.random_rsp_drop = 0
    tb = TB(dut, cfg)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    cocotb.start_soon(tb._process_qos_req())
    cocotb.start_soon(tb._process_qos_rsp())
    cocotb.start_soon(tb._process_qos_update())
    cocotb.start_soon(tb._process_drop())
    cocotb.start_soon(tb._process_drop_data())
    cocotb.start_soon(tb._process_info_out())
    cocotb.start_soon(tb._process_data_req())
    await tb.cycle_reset()
    await tb.mlitemaster.write(0x0000_0000, cfg.csum_ctrl)
    await tb.mlitemaster.write(0x0000_0008, 0x21)
    await tb.mlitemaster.write(0x0000_0010, cfg.time_sel)
    await tb.mlitemaster.write(0x0000_0018, cfg.random_sel)
    await Timer(125000, "ns")
    cocotb.start_soon(tb._process_beq2net())
    await cocotb.start_soon(tb._process_data_rsp())
    await Timer(1000, "ns")
    tb.log.warning(f"pps:{int(tb.dut.pps.value)/100}M")


async def dfx_test(dut, idle_inserter, backpressure_inserter):
    random.seed(123)
    cfg = Config()
    cfg.eth_cfg = Eth_Pkg_Cfg()
    cfg.eth_cfg.random_vlan = 0
    cfg.eth_cfg.random_net_csum_err = 0
    cfg.eth_cfg.random_trans_csum_err = 0
    cfg.eth_cfg.test_mode = "pps"
    cfg.max_seq = 10000
    cfg.random_need_vld = 0.5
    cfg.csum_ctrl = 1
    cfg.time_sel = 0
    cfg.random_sel = 0
    cfg.random_gen_err = 0
    cfg.random_qos_en = 1
    cfg.qos_en = 1
    cfg.random_qos = 0
    cfg.random_data_req = False
    cfg.random_rsp_drop = 0
    tb = TB(dut, cfg)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    cocotb.start_soon(tb._process_qos_req())
    cocotb.start_soon(tb._process_qos_rsp())
    cocotb.start_soon(tb._process_qos_update())
    cocotb.start_soon(tb._process_drop())
    cocotb.start_soon(tb._process_drop_data())
    cocotb.start_soon(tb._process_info_out())
    cocotb.start_soon(tb._process_data_req())
    await tb.cycle_reset()
    cocotb.start_soon(tb._process_beq2net())
    cocotb.start_soon(tb._process_data_rsp())
    for i in range(16384):
        await tb.mlitemaster.write(i * 8, randbit(64))
    for i in range(16384):
        await tb.mlitemaster.read(i * 8)
    # await tb.mlitemaster.write(0x0000_0010, cfg.time_sel)
    # await tb.mlitemaster.write(0x0000_0018, cfg.random_sel)
    # await Timer(125000, "ns")
    # await cocotb.start_soon(tb._process_data_rsp())
    # await Timer(1000, "ns")
    # tb.log.warning(f"pps:{int(tb.dut.pps.value)/100}M")


async def notify_rsp_stop_test(dut, idle_inserter, backpressure_inserter):
    random.seed(123)
    cfg = Config()
    cfg.eth_cfg = Eth_Pkg_Cfg()
    cfg.max_seq = 10000
    cfg.random_qos_en = 0.9
    cfg.random_need_vld = 0.5
    cfg.csum_ctrl = 1
    cfg.time_sel = 3
    cfg.random_sel = 1
    cfg.random_gen_err = 0.01
    cfg.qos_en = 1
    cfg.random_qos = 0.01
    cfg.random_data_req = True
    cfg.random_rsp_drop = 0.01

    tb = TB(dut, cfg)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    cocotb.start_soon(tb._process_qos_req())
    cocotb.start_soon(tb._process_qos_rsp())
    cocotb.start_soon(tb._process_qos_update())
    cocotb.start_soon(tb._process_drop())
    cocotb.start_soon(tb._process_drop_data())
    cocotb.start_soon(tb._process_info_out())
    cocotb.start_soon(tb._process_data_req())
    await tb.cycle_reset()

    await tb.mlitemaster.write(0x0000_0000, cfg.csum_ctrl)
    await tb.mlitemaster.write(0x0000_0008, 0x21)
    await tb.mlitemaster.write(0x0000_0010, cfg.time_sel)
    await tb.mlitemaster.write(0x0000_0018, cfg.random_sel)
    await Timer(125000, "ns")
    cocotb.start_soon(tb._process_beq2net())
    # cocotb.start_soon(tb.ram_test())
    cocotb.start_soon(tb._process_notify_rsp_stop())
    await cocotb.start_soon(tb._process_data_rsp())

    await Timer(1000, "ns")


def cycle_pause():
    # seed = [i % 2 for i in range(1000)]
    seed = [1 if i < 400 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)


ding_robot.ding_robot()
if cocotb.SIM_NAME:
    # for test in [normal_test, bps_test, pps_test, dfx_test, notify_rsp_stop_test]:
    for test in [pps_test]:

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
