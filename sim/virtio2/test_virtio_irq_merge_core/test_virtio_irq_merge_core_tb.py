#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : test_virtio_irq_merge_core_tb.py
#* 作者名称 : matao
#* 创建日期 : 2025/07/30
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   07/30       matao       初始化版本
#******************************************************************************/
import itertools
import logging
from logging.handlers import RotatingFileHandler
import sys
import random
import cocotb_test.simulator
from cocotb.binary import BinaryValue
import os
import time 

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time
from collections import defaultdict

sys.path.append('../../common')
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster
from defines import *
from virtio_irq_merge_core_ctx_ctrl import *


class TB(object):
    def __init__(self, dut, num=8, qid_depth=256):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        #parameter
        self.BASE_TIMEOUT_US = 2
        self.TIME_STAMP_UNIT_NS = 500
        self.CLK_FREQ_M = 200
        self.CLK_CYCLE = self.TIME_STAMP_UNIT_NS / (1000 / self.CLK_FREQ_M)
        self.IRQ_MERGE_UINT_NUM = num
        self.QID_NUM = qid_depth
        self.SCAN_QID_NUM = qid_depth // num
        self.SCAN_WIDTH = (self.SCAN_QID_NUM - 1).bit_length()
        #Initialize state variables
        self._reset_state_variables()
        cocotb.start_soon(Clock(dut.clk, 5, units="ns").start())
        self.irq_in    = IrqInSource(IrqInBus.from_prefix(dut, "irq_in"), dut.clk, dut.rst)
        self.irq_in.queue_occupancy_limit = 8
        self.irq_out   = IrqOutSink (IrqInBus.from_prefix(dut, "irq_out"), dut.clk, dut.rst)
        self.msixtime_if= MsixTimeRdTbl(MsixTimeRdReqBus.from_prefix(dut, "msix_aggregation_time"), MsixTimeRdRspBus.from_prefix(dut, "msix_aggregation_time"), None, dut.clk, dut.rst)
        self.msixthreshold_if= MsixThresholdRdTbl(MsixThresholdRdReqBus.from_prefix(dut, "msix_aggregation_threshold"), MsixThresholdRdRspBus.from_prefix(dut, "msix_aggregation_threshold"), None, dut.clk, dut.rst)
        self.msixinfo_if= MsixInfoTbl(MsixInfoRdReqBus.from_prefix(dut, "msix_aggregation_info"), MsixInfoRdRspBus.from_prefix(dut, "msix_aggregation_info"), MsixInfoWrBus.from_prefix(dut, "msix_aggregation_info"), dut.clk, dut.rst, read_first=False)

        self.irq_qid_in_queue = Queue()
        self.irq_qid_cnt_queue = Queue()
        self.ctx_ctrl = irq_merge_core_ctx_ctrl(self.msixtime_if, self.msixthreshold_if, self.msixinfo_if)

        self._eng_in_flag_process_cr    = cocotb.start_soon(self._eng_in_flag_process())
        self._scan_process_cr           = cocotb.start_soon(self._scan_process())
        self._time_process_cr           = cocotb.start_soon(self._time_process())
        self._irq_in_process_cr         = cocotb.start_soon(self._irq_in_process())

    def _reset_state_variables(self):
        self.eng_in_flag = 0
        self.eng_in_flag_reg2 = 0
        self.time_stamp_imp = 0
        self.time_stamp = 0
        self.time_stamp_reg2 = 0
        self.time_cycle_cnt = 0
        self.scan_out_qid_reg2 = 0
        self.scan_out_vld_reg2 = 0
        self.scan_out_rdy_reg2 = 0
        self.irq_in_qid_reg1 = 0
        self.irq_in_vld_reg1 = 0
        self.irq_in_rdy_reg1 = 0
        self.irq_in_qid_reg2 = 0
        self.irq_in_vld_reg2 = 0
        self.irq_in_rdy_reg2 = 0
        self.irq_merge_cnt_en = 0
        self.sim_local_ctx = {}
        self.qid_input_info = defaultdict(lambda: {
            "first_input_time": None,
            "input_count": 0,
            "wr_en":0,
            "wr_time": None})
        self.irq_in_cnt = 0
        self.end_flag = 0
        self.signal_qid = 0

    def reset_queues(self):
        self.queue_dict = {}  
        self.ctx_ctrl.clear_queue()

    def generate_queues(self, num_queues=256, threshold_mode="threshold_mixed"):
        """
        threshold_mode: Control the generation mode of msix_threshold
        - "threshold_0": Fixed at 0
        - "threshold_1": Fixed at 1
        - "threshold_2_127": Random between 2-127
        - "threshold_mixed": Random between 0-127 (default)
        """
        self.reset_queues()
        for idx in range(num_queues):
            msix_time = random.randint(0, 7)
            if threshold_mode == "threshold_0":
                msix_threshold = 0
            elif threshold_mode == "threshold_1":
                msix_threshold = 1
            elif threshold_mode == "threshold_2_127":
                msix_threshold = random.randint(2, 127)
            elif threshold_mode == "threshold_mixed":
                msix_threshold = random.randint(0, 127)
            else:
                raise ValueError(f"Invalid threshold_mode: {threshold_mode}")

            self.ctx_ctrl.create_queue(
                idx = idx,
                msix_time = msix_time, 
                msix_threshold = msix_threshold
            )

            self.queue_dict[idx] = {
                "msix_time": msix_time,
                "msix_threshold": msix_threshold
            }

            self.log.info(
                f"Generate queue context | IDX={idx} | "
                f"msix_time={msix_time} (0x{msix_time:01X}), "
                f"msix_threshold={msix_threshold} (0x{msix_threshold:01X}), "
            )

    def get_queue_context(self, idx):
        if idx not in self.queue_dict:
            self.log.error(f"Queue ID {idx} not found in queue dictionary")
            return None
        return self.queue_dict[idx]

    def get_local_context(self, idx_num):
        if idx_num not in self.ctx_ctrl.local_ctxs:
            self.log.error(f"Queue ID {idx} not found in local_ctxs")
            return None
        return self.ctx_ctrl.local_ctxs[idx_num]
        #for idx in range(idx_num):
        #    if idx in self.ctx_ctrl.local_ctxs:
        #        ctx_data = self.ctx_ctrl.local_ctxs[idx].msix_info
        #        ctx_data_hex = f"0x{ctx_data:03x}"  
        #        self.log.info(
        #            f"get_local_context | IDX={idx:02d} | "
        #            f"Existence of data={ctx_data_hex}  |")
        #    else:
        #        self.log.info(
        #            f"get_local_context | IDX={idx:02d} | "
        #            f"No existence of data=0x000  |")

    async def _eng_in_flag_process(self):
        flag_reg1 = 0
        while True:
            await RisingEdge(self.dut.clk)
            rst_val = self.dut.rst.value
            if rst_val == 1 :
                current_flag  = 0
            else:
                current_flag  = 1 - self.eng_in_flag
            self.eng_in_flag_reg2 = flag_reg1
            flag_reg1 = self.eng_in_flag
            self.eng_in_flag = current_flag
            self.dut.tb_eng_in_flag.value = self.eng_in_flag 
            self.dut.tb_eng_in_flag_d2.value = self.eng_in_flag_reg2 

    async def _time_process(self):
        while True:
            await RisingEdge(self.dut.clk)
            self.time_stamp_reg2 = self.time_stamp
            if self.dut.rst.value == 1 :
                self.time_cycle_cnt = 0
                self.time_stamp = 0
            else :
                if self.time_cycle_cnt == self.CLK_CYCLE - 1:
                    self.time_cycle_cnt = 0
                    self.time_stamp = (self.time_stamp + 1) % 65536  # 65536 = 2^16
                    self.time_stamp_imp = 1
                else :
                    self.time_cycle_cnt += 1
                    self.time_stamp_imp = 0
            self.dut.tb_time_cycle_cnt.value = self.time_cycle_cnt
            self.dut.tb_time_stamp.value = self.time_stamp
            self.dut.tb_time_stamp_d2.value = self.time_stamp_reg2
            self.dut.tb_time_stamp_imp.value = self.time_stamp_imp

    async def _scan_process(self):
        scan_out_cnt = 0
        scan_out_vld = 0
        scan_out_rdy = 0
        scan_out_qid = 0
        vld_reg1 = 0
        rdy_reg1 = 0
        qid_reg1 = 0
        while True: 
            await RisingEdge(self.dut.clk)
            if self.dut.rst.value == 1 or self.time_stamp_imp == 1:
                scan_out_cnt = 0
            elif scan_out_vld == 1 and scan_out_rdy == 1:
                scan_out_cnt += 1
                if scan_out_cnt >= self.SCAN_QID_NUM:
                    scan_out_cnt = self.SCAN_QID_NUM
            self.scan_out_vld_reg2 = vld_reg1
            self.scan_out_rdy_reg2 = rdy_reg1
            self.scan_out_qid_reg2 = qid_reg1
            vld_reg1 = scan_out_vld
            rdy_reg1 = scan_out_rdy
            qid_reg1 = scan_out_qid
            scan_out_vld = (scan_out_cnt != self.SCAN_QID_NUM)
            scan_out_qid = scan_out_cnt & ((1 << self.SCAN_WIDTH) - 1)
            scan_out_rdy = self.eng_in_flag == 0 
            self.dut.tb_scan_out_qid_d2.value = self.scan_out_qid_reg2
            self.dut.tb_scan_out_vld_d2.value = self.scan_out_vld_reg2
            self.dut.tb_scan_out_rdy_d2.value = self.scan_out_rdy_reg2

    async def _irq_in_process(self):
        while True:
            await RisingEdge(self.dut.clk)
            self.irq_in_qid_reg2 = self.irq_in_qid_reg1
            self.irq_in_vld_reg2 = self.irq_in_vld_reg1
            self.irq_in_rdy_reg2 = self.irq_in_rdy_reg1
            self.irq_in_qid_reg1 = self.dut.irq_in_qid.value
            self.irq_in_vld_reg1 = self.dut.irq_in_vld.value
            self.irq_in_rdy_reg1 = self.dut.irq_in_rdy.value
            self.dut.tb_irq_in_qid_d2.value = self.irq_in_qid_reg2
            self.dut.tb_irq_in_vld_d2.value = self.irq_in_vld_reg2
            self.dut.tb_irq_in_rdy_d2.value = self.irq_in_rdy_reg2

    async def first_input_time_process(self):
        while True:
            await RisingEdge(self.dut.clk)
            if self.irq_in_vld_reg1 == 1 and self.irq_in_rdy_reg1 == 1:
                qid_reg1_int = self.irq_in_qid_reg1.integer
                current_sim_time = get_sim_time("ns")
                await Timer(2, 'ns')
                if self.qid_input_info[qid_reg1_int]["first_input_time"] is None:
                    self.qid_input_info[qid_reg1_int]["first_input_time"] = current_sim_time


    async def irq_merge_core_eng_process(self):
        while not self.irq_qid_in_queue.empty():
            try:
                self.irq_qid_in_queue.get_nowait()
            except:
                break
        while not self.irq_qid_cnt_queue.empty():
            try:
                self.irq_qid_cnt_queue.get_nowait()
            except:
                break
        while True:
            await RisingEdge(self.dut.clk)
            if self.eng_in_flag_reg2 == 1 and self.irq_in_vld_reg2 == 1 and self.irq_in_rdy_reg2 == 1:
                irq_qid = self.irq_in_qid_reg2.integer
                irq_cnt = self.qid_input_info[irq_qid]["input_count"] + 1
                ctx_params = self.get_queue_context(irq_qid)
                if ctx_params:
                    msix_time = ctx_params["msix_time"]
                    msix_threshold = ctx_params["msix_threshold"]
                else :
                    raise ValueError("irq_in: The queue_dict(irq_qid:{}) is not exists".format(irq_qid))
                self.log.debug(f"irq_merge_core_eng_process eng_in_flag_reg2 irq_qid is :{irq_qid}")
                if irq_cnt == msix_threshold and msix_threshold != 0 :
                    self.irq_qid_in_queue.put_nowait(irq_qid)
                    self.log.debug(f"msix_threshold == input_cnt put irq_qid_in_queue irq_qid is :{irq_qid}, {irq_cnt}, {msix_threshold}")
                    self.irq_qid_cnt_queue.put_nowait((irq_qid, irq_cnt, self.qid_input_info[irq_qid]["first_input_time"], 1)) #1=cnt
                    self.log.debug(f"msix_threshold == input_cnt put irq_qid_cnt_queue irq_qid is :{irq_qid}, {irq_cnt}, {self.qid_input_info[irq_qid]['first_input_time']}")
                    self.qid_input_info[irq_qid]["first_input_time"] = None
                    self.qid_input_info[irq_qid]["input_count"] = 0
                    self.qid_input_info[irq_qid]["wr_en"] = 0
                else:
                    if self.qid_input_info[irq_qid]["wr_en"] == 1:
                        self.qid_input_info[irq_qid]["input_count"] = irq_cnt
                    else:
                        self.qid_input_info[irq_qid]["wr_en"] = 1
                        self.qid_input_info[irq_qid]["input_count"] = 1
                        self.qid_input_info[irq_qid]["wr_time"] = ((self.time_stamp_reg2 >> msix_time) - 1 ) & 0x3
                    
            elif self.eng_in_flag_reg2 == 0 and self.scan_out_vld_reg2 == 1 and self.scan_out_rdy_reg2 == 1:
                scan_base_qid = self.scan_out_qid_reg2
                for i in range(8):
                    scan_qid = (scan_base_qid << 3) + i
                    ctx_params = self.get_queue_context(scan_qid)
                    if not ctx_params:
                        self.log.warning(f"scan_out: queue_dict(scan_qid:{scan_qid}) not exists, skip")
                        continue
                    msix_time = ctx_params["msix_time"]
                    current_time = (self.time_stamp_reg2 >> msix_time) & 0x3  
                    en = self.qid_input_info[scan_qid]["wr_en"]
                    time = self.qid_input_info[scan_qid]["wr_time"]
                    input_cnt = self.qid_input_info[scan_qid]["input_count"]
                    input_first_time = self.qid_input_info[scan_qid]["first_input_time"]
                    self.log.debug(f"irq_merge_core_eng_process eng_in_flag_reg2==0 scan_qid is :{scan_qid},msix_time is {msix_time},en is {en}, time is {time}, current_time is {current_time}")

                    if en == 1 and current_time == time:
                        self.irq_qid_in_queue.put_nowait(scan_qid)
                        self.irq_qid_cnt_queue.put_nowait((scan_qid, input_cnt, input_first_time, 0)) #0=timeout
                        self.log.debug(f"current_time == time put irq_qid_cnt_queue qid is :{scan_qid},{input_cnt}, {input_first_time}")
                        self.qid_input_info[scan_qid]["first_input_time"] = None
                        self.qid_input_info[scan_qid]["wr_en"] = 0
                        self.qid_input_info[scan_qid]["input_count"] = 0


    async def irq_merge_info_process(self, max_seq):
        while True:
            await RisingEdge(self.dut.clk)
            current_sim_time = get_sim_time("ns")
            await Timer(2, 'ns')
            if self.dut.irq_in_vld.value == 1 and self.dut.irq_in_rdy.value == 1:
                self.irq_in_cnt = self.irq_in_cnt + 1
                if self.irq_in_cnt == max_seq:
                    self.end_flag = 1
            if self.dut.u_virtio_irq_merge_core_top.eng_out_vld.value != 0:
                eng_out_vld_val = self.dut.u_virtio_irq_merge_core_top.eng_out_vld.value.integer
                eng_out_qid_val = self.dut.u_virtio_irq_merge_core_top.eng_out_qid.value.integer
                qid_high5 = eng_out_qid_val & 0x1F
                set_indices = []
                for i in range(8):
                    is_set = (eng_out_vld_val >> i) & 1
                    if is_set:
                        set_indices.append(i)
                if not set_indices:
                    self.log.error(f"eng_out_vld={bin(eng_out_vld_val)} (no valid bit set)")
                for qid_low3 in set_indices:
                    full_qid = (qid_high5 << 3) | qid_low3
                    ctx_params = self.get_queue_context(full_qid)
                    msix_time = ctx_params["msix_time"] if ctx_params else 0
                    msix_threshold = ctx_params["msix_threshold"] if ctx_params else 0
                    unit_time = 0.5 * (2** msix_time)
                    expected_timeout_us = (unit_time * (2** self.BASE_TIMEOUT_US)) * (1 - (1 / (2 ** self.BASE_TIMEOUT_US)))
                    input_time_err = (unit_time * (2** self.BASE_TIMEOUT_US)) * (1 / (2 ** self.BASE_TIMEOUT_US))
                    scan_time_err = 0.34 # 256/8 * 2 * 5ns + 20ns=340ns

                    try:
                        sim_qid, input_cnt, input_first_time, cnt_merge_flag = self.irq_qid_cnt_queue.get_nowait()
                        if full_qid != sim_qid:
                            self.log.error(f"irq_qid_cnt_queue qid don't match! sim_qid: {sim_qid}, irq_rsp.qid: {full_qid}")
                            assert sim_qid == full_qid, f"irq_qid_cnt_queue qid don't match! : sim {sim_qid}, rsp {full_qid}"
                        if cnt_merge_flag == 1 and input_cnt != msix_threshold:
                            self.log.error(f"irq_qid_cnt_queue input_cnt don't match! input_cnt: {input_cnt}, msix_threshold: {msix_threshold}")
                            assert input_cnt != msix_threshold, f"irq_qid_cnt_queue input_cnt don't match! : input_cnt {input_cnt}, msix_threshold {msix_threshold}"
                        actual_time_diff_us = (current_sim_time - input_first_time) / 1000  # ns -> us
                        if cnt_merge_flag == 1:
                            self.log.info(
                                f"QID {full_qid} is Count Aggregation!"
                                f"input_cnt={input_cnt}/threshold={msix_threshold}, "
                                f"first_time={input_first_time}ns | "
                                f"current_sim_time={current_sim_time}ns, "
                                f"msix_time={msix_time} (level), expected_timeout={expected_timeout_us}us, "
                                f"actual_time_diff={actual_time_diff_us:.2f}us | "
                            )
                        else :
                            is_within_tolerance = (expected_timeout_us - input_time_err) <= actual_time_diff_us <= (expected_timeout_us + scan_time_err)
                            self.log.info(
                                f"QID {full_qid} is Timeout Aggregation!"
                                f"input_cnt={input_cnt}/threshold={msix_threshold}, "
                                f"first_time={input_first_time}ns | "
                                f"current_sim_time={current_sim_time}ns, "
                                f"msix_time={msix_time} (level), expected_timeout={expected_timeout_us}us, "
                                f"input_time_err={input_time_err},scan_time_err={scan_time_err},"
                                f"expected_timeout_us - input_time_err={expected_timeout_us - input_time_err},"
                                f"expected_timeout_us + scan_time_err={expected_timeout_us + scan_time_err},"
                                f"actual_time_diff={actual_time_diff_us:.2f}us | "
                                f"within tolerance: {is_within_tolerance}"
                            )
                            if not is_within_tolerance:
                                self.log.error(f"Timeout merge is failed")
                    except Exception as e:
                        self.log.error(f"Failed to get data from irq_qid_cnt_queue: {str(e)}")
                
    async def cycle_reset(self):
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
        if generator:
            self.irq_in.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.irq_out.set_backpressure_generator(generator)



async def run_test_virtio_irq_merge_core(dut, idle_inserter, backpressure_inserter, threshold_mode, qid_mode):
    #random.seed(2)
    time_seed = int(time.time())
    random.seed(time_seed)
    tb = TB(dut)
    tb.log.info(f"set time_seed {time_seed}")
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)

    async def irq_in_process(i, max_seq, qid_mode="8_channel"):
        '''
        qid_mode: Control the qid generation mode
        - "8_channel": 8-channel mode, randomly selecting all qid from 0-255
        - "single_channel": Single channel mode, using only the qid of the first channel (0,8,16,..., 248)
        - "4_channel": 4-channel mode, using qid from channels 5-8 (4+8k, 5+8k, 6+8k, 7+8k)
        - "single_qid":1 qid
        '''
        if qid_mode == "8_channel":
            req_qid = random.randint(0, 255)
        elif qid_mode == "single_channel":
            qid_candidates = [8 * k for k in range(32)]  # 0,8,...,248
            req_qid = random.choice(qid_candidates)
        elif qid_mode == "4_channel":
            # #4-channel mode: Use channels 5-8 (index 4-7)
            qid_candidates4 = [4 + 8 * k for k in range(32)]  # 4,12,...,252
            qid_candidates5 = [5 + 8 * k for k in range(32)]  # 5,13,...,253
            qid_candidates6 = [6 + 8 * k for k in range(32)]  # 6,14,...,254
            qid_candidates7 = [7 + 8 * k for k in range(32)]  # 7,15,...,255
            all_qid_candidates = qid_candidates4 + qid_candidates5 + qid_candidates6 + qid_candidates7
            req_qid = random.choice(all_qid_candidates)
        elif qid_mode == "single_qid":
            if i == 0:
                qid_candidates = [8 * k for k in range(32)]  # 0,8,...,248
                tb.signal_qid = random.choice(qid_candidates)
                req_qid = tb.signal_qid
            else:
                req_qid = tb.signal_qid
        else:
            raise ValueError(f"Invalid qid_mode: {qid_mode}")
        obj = tb.irq_in._transaction_obj()
        obj.qid = req_qid
        input_info = tb.qid_input_info[req_qid]
        await tb.irq_in.send(obj)
        tb.log.info(f"Test sequence is {i+1}/{max_seq}, qid is {req_qid}")

    async def irq_out_process():
        while True:
            irq_rsp = await tb.irq_out.recv()
            sim_qid = await tb.irq_qid_in_queue.get()
            qid_int = irq_rsp.qid.integer
            if sim_qid != qid_int:
                tb.log.error(f"QID don't match! sim_qid: {sim_qid}, irq_rsp.qid: {qid_int}")
                assert sim_qid == qid_int, f"QID don't match! : sim {sim_qid}, rsp {qid_int}"
    cocotb.start_soon(irq_out_process())
    max_seq = 50000
    await Timer(5000, 'ns')
    tb.generate_queues(256, threshold_mode=threshold_mode)
    await Timer(5000, 'ns')
    cocotb.start_soon(tb.first_input_time_process())
    cocotb.start_soon(tb.irq_merge_core_eng_process())
    cocotb.start_soon(tb.irq_merge_info_process(max_seq))
    
    for i in range(max_seq):
        await irq_in_process(i, max_seq, qid_mode=qid_mode)
        
    while True:
        if tb.end_flag == 1 :
            break
        await Timer(1, 'us')
    await Timer(100, 'us')
    check_timeout = 300
    check_interval = 1
    elapsed_check = 0

    while elapsed_check < check_timeout:
        if tb.irq_qid_in_queue.empty():
            tb.log.info("irq_qid_in_queue cleared, test ended normally")
            break
        await Timer(check_interval, 'us')
        elapsed_check += check_interval
    else:
        remaining = tb.irq_qid_in_queue.qsize()
        tb.log.warning(f"After 400us total, irq_qid_in_queue has {remaining} elements unprocessed, forcing termination")
    await Timer(500, 'ns')
    
def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    #seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test_virtio_irq_merge_core]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None,cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        default_threshold_modes  = ["threshold_0", "threshold_1", "threshold_2_127", "threshold_mixed"]
        selected_threshold_modes  = os.getenv("COCOTB_THRESHOLD_MODES", ",".join(default_threshold_modes)).split(",")
        factory.add_option("threshold_mode", selected_threshold_modes)
        default_qid_modes = ["8_channel", "single_channel", "4_channel", "single_qid"]
        selected_qid_modes = os.getenv("COCOTB_QID_MODES", ",".join(default_qid_modes)).split(",")
        factory.add_option("qid_mode", selected_qid_modes)
        factory.generate_tests()

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)

#from debug import *