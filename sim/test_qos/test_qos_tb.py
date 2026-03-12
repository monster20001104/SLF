#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : test_qos_tb.py
#* 作者名称 : matao
#* 创建日期 : 2025/04/03
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   04/03       matao       初始化版本
#* v1.1   07/25       matao       query由5通道改成3通道，取消rr调度使用3个ram
#******************************************************************************/
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import copy
import cocotb_test.simulator
import math
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

sys.path.append('../common')
from bus.beq_data_bus import BeqBus
from drivers.beq_data_bus import BeqTxqMaster
from monitors.beq_data_bus import BeqRxqSlave
from bus.tlp_adap_bypass_bus import TlpBypassBus, OpCode, ComplStatus, TlpBypassReq, TlpBypassRsp, TlpBypassReq2CfgTlp, Tlp2TlpBypassCpl,Header
from drivers.tlp_adap_bypass_bus import TlpBypassMaster
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster

QueryReqBus, QueryReqTransaction, QueryReqSource, QueryReqSink, QueryReqMonitor = define_stream("Query_master",
    signals=["uid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)    
QueryRspBus, QueryRspTransaction, QueryRspSource, QueryRspSink, QueryRspMonitor = define_stream("Query_slave",
    signals=["ok"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)    
UpDateReqBus, UpDateReqTransaction, UpDateReqSource, UpDateReqSink, UpDateReqMonitor = define_stream("UpDateReq",
    signals=["uid", "len", "pkt_num"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)
CalcReqBus, CalcReqTransaction, CalcReqSource, CalcReqSink, CalcReqMonitor = define_stream("Calc_master",
    signals=["uid", "curr_time", "bw_last_time", "qps_last_time","bw_cir", "qps_cir", "bw_cbs", "qps_cbs", "bw_token", "qps_token", "bw_len", "qps_pkt_num"], 
    optional_signals=None,
    vld_signal = "control",
    rdy_signal = None,
    signal_widths=None
)    
CalcRspBus, CalcRspTransaction, CalcRspSource, CalcRspSink, CalcRspMonitor = define_stream("Calc_slave",
    signals=["bw_token_result", "qps_token_result", "token_result_uid"], 
    optional_signals=None,
    vld_signal = "token_result_vld",
    rdy_signal = None,
    signal_widths=None
)   
class TB(object):
    def __init__(self, dut, clk_freq="220M"):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        self.result_detect_end_flag = 1

        if clk_freq == "200M":
            clk_period_ps = 5000  # 5ns = 5000ps
            clk_units = "ps"
        elif clk_freq == "220M":
            clk_period_ps = 4546  # 1000000ps/ns ÷ 220 = 4545.454... → 4546ps
            clk_units = "ps"
        
        self.log.info(f"Clock frequency set to {clk_freq}, period = {clk_period_ps} {clk_units} (≈{clk_period_ps/1000:.6f} ns)")
        cocotb.start_soon(Clock(dut.clk, clk_period_ps, units=clk_units).start())
        self.query_req     = [QueryReqSource(QueryReqBus.from_prefix(dut, "query{}_req".format(i)), dut.clk, dut.rst)for i in range(5)]
        self.query_rsp     = [QueryRspSink(QueryRspBus.from_prefix(dut, "query{}_rsp".format(i)), dut.clk, dut.rst)for i in range(5)]
        self.update_req    = [UpDateReqSource(UpDateReqBus.from_prefix(dut, "update{}".format(i)), dut.clk, dut.rst)for i in range(3)]
        self.regconmaster  = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)

        self.calc_req = CalcReqSource(CalcReqBus.from_prefix(dut, "calc"), dut.clk, dut.rst)
        self.calc_rsp = CalcRspSink(CalcRspBus.from_prefix(dut, "calc"), dut.clk, dut.rst)
        
        self.calc_req_queue = Queue(maxsize=100)
        self.calc_req1_queue = Queue(maxsize=100)
        self.calc_rsp_queue = Queue(maxsize=100)

        self.reg_rd_queue_rsp    = Queue(maxsize=64)
        self.only_prequery_queue = [Queue(maxsize=32) for _ in range(5)]
        self.only_query_queue    = [Queue(maxsize=32) for _ in range(5)]
        self.pre_query_queue     = [Queue(maxsize=32) for _ in range(5)]
        self.query_queue         = [Queue(maxsize=2) for _ in range(5)]
        self.end_queue           = Queue(maxsize=1)
        self.dfx_reg_queue       = Queue(maxsize=1)

    async def reg_wr_req(self, addr,data):
        await self.regconmaster.write(addr,data,True)

    async def reg_rd_req(self, addr):
        rddata = await self.regconmaster.read(addr)
        await self.reg_rd_queue_rsp.put(rddata)

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
            for query_req in self.query_req:
                query_req.set_idle_generator(generator)
            for query_rsp in self.query_rsp:
                query_rsp.set_idle_generator(generator)
            for update_req in self.update_req:
                update_req.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        if generator:
            for query_req in self.query_req:
                query_req.set_backpressure_generator(generator)
            for query_rsp in self.query_rsp:
                query_rsp.set_backpressure_generator(generator)
            for update_req in self.update_req:
                update_req.set_backpressure_generator(generator)

def binary_to_signed_decimal(binary_str, bit_length):
    num = int(binary_str, 2)
    if num & (1 << (bit_length - 1)):
        num -= (1 << bit_length)
    return num

def gen_uid_cir_cbs_en(uids_list, bw_cir, qps_cir):
    uid_cir_cbs = []
    if uids_list:
        for uid in uids_list:
            bw_cir = bw_cir
            bw_cbs = bw_cir * 100 
            addr_bw_cir = uid * 0x200 + 0x10
            data_bw_cir = bw_cir
            addr_bw_cbs = uid * 0x200 + 0x18
            data_bw_cbs = bw_cbs
            uid_cir_cbs.append((addr_bw_cir, data_bw_cir))
            uid_cir_cbs.append((addr_bw_cbs, data_bw_cbs))
            
            qps_cir = qps_cir
            qps_cbs = qps_cir * 100
            addr_qps_cir = uid * 0x200 + 0x20
            data_qps_cir = qps_cir
            addr_qps_cbs = uid * 0x200 + 0x28
            data_qps_cbs = qps_cbs
            uid_cir_cbs.append((addr_qps_cir, data_qps_cir))
            uid_cir_cbs.append((addr_qps_cbs, data_qps_cbs))

            addr_en = uid * 0x200
            data_en = 0x1
            uid_cir_cbs.append((addr_en, data_en))
    return uid_cir_cbs 

pre_query_req_cnt = {}
pre_query_rsp_cnt = {}
query_req_cnt = {}
query_rsp_cnt = {}
query_rsp_ok_cnt  ={}
bw_update_req_cnt ={}
bwg_cir = 400000 #50g
qpsg_cir = 400000

async def run_test_qos(dut, idle_inserter, backpressure_inserter,len_pkt_modes, uid_cnt_modes):
    clk_freq = os.getenv("COCOTB_CLK_FREQ", "220M")
    time_seed = int(time.time())
    random.seed(time_seed)
    tb = TB(dut, clk_freq)
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

    async def read_dfx_reg(sec_en0, sec_en1, sec_en2):
        addr0 = 0x300000
        await tb.reg_rd_req(addr = addr0)
        rdata0 = await tb.reg_rd_queue_rsp.get()
        rdata0 = int(rdata0)
        if rdata0 > 0 :
            tb.log.info("There are some DFX errors in module err0 is {}, ".format(rdata0))
            assert False, " There are some DFX errors in module."
            
        addr00 = 0x300100
        await tb.reg_rd_req(addr = addr00)
        rdata00 = await tb.reg_rd_queue_rsp.get()
        addr10 = 0x300108
        await tb.reg_rd_req(addr = addr10)
        rdata10 = await tb.reg_rd_queue_rsp.get()
    
        addr2 = 0x300200
        await tb.reg_rd_req(addr = addr2)
        rdata2 = await tb.reg_rd_queue_rsp.get()
        addr3 = 0x300208
        await tb.reg_rd_req(addr = addr3)
        rdata3 = await tb.reg_rd_queue_rsp.get()
        addr4 = 0x300210
        await tb.reg_rd_req(addr = addr4)
        rdata4 = await tb.reg_rd_queue_rsp.get()
 

        tb.log.info("DFX cnt rd 0x300100 is {}, 0x300108 is {}".format(rdata00, rdata10))
        tb.log.info("DFX cnt rd 0x300200 is {}, 0x300208 is {}".format(rdata2, rdata3))
        tb.log.info("DFX cnt rd 0x300210 is {}".format(rdata4))
        update0_cnt     = rdata2 & 0xFF
        update1_cnt     = (rdata2 >> 8) & 0xFF
        update2_cnt     = (rdata2 >> 16) & 0xFF
        query_req0_cnt  = (rdata3 ) & 0xFF
        query_req1_cnt  = (rdata3 >> 8) & 0xFF
        query_req2_cnt  = (rdata3 >> 16) & 0xFF
        query_rsp0_cnt  = (rdata4 ) & 0xFF
        query_rsp1_cnt  = (rdata4 >> 8) & 0xFF
        query_rsp2_cnt  = (rdata4 >> 16) & 0xFF

        #总一次查询请求请求
        sum_pre_query_req_0_255 = 0
        sum_pre_query_req_256_511 = 0
        sum_pre_query_req_512_767 = 0
        for uid, value in pre_query_req_cnt.items():
            if 0 <= uid <= 255:
                sum_pre_query_req_0_255 += value
            elif 256 <= uid <= 511:
                sum_pre_query_req_256_511 += value
            elif 512 <= uid <= 767:
                sum_pre_query_req_512_767 += value
        sum_pre_query_rsp_0_255 = 0
        sum_pre_query_rsp_256_511 = 0
        sum_pre_query_rsp_512_767 = 0
        for uid, value in pre_query_rsp_cnt.items():
            if 0 <= uid <= 255:
                sum_pre_query_rsp_0_255 += value
            elif 256 <= uid <= 511:
                sum_pre_query_rsp_256_511 += value
            elif 512 <= uid <= 767:
                sum_pre_query_rsp_512_767 += value
        sum_query_req_0_255 = 0
        sum_query_req_256_511 = 0
        sum_query_req_512_767 = 0
        for uid, value in query_req_cnt.items():
            if 0 <= uid <= 255:
                sum_query_req_0_255 += value
            elif 256 <= uid <= 511:
                sum_query_req_256_511 += value
            elif 512 <= uid <= 767:
                sum_query_req_512_767 += value
        sum_query_rsp_0_255 = 0
        sum_query_rsp_256_511 = 0
        sum_query_rsp_512_767 = 0
        for uid, value in query_rsp_cnt.items():
            if 0 <= uid <= 255:
                sum_query_rsp_0_255 += value
            elif 256 <= uid <= 511:
                sum_query_rsp_256_511 += value
            elif 512 <= uid <= 767:
                sum_query_rsp_512_767 += value
        sum_update_0_255 = 0
        sum_update_256_511 = 0
        sum_update_512_767 = 0
        for uid, value in bw_update_req_cnt.items():
            if 0 <= uid <= 255:
                sum_update_0_255 += value
            elif 256 <= uid <= 511:
                sum_update_256_511 += value
            elif 512 <= uid <= 767:
                sum_update_512_767 += value

        if sec_en0:# 0通道二次查询，第一次请求数等于0请求响应计数，第二次请求响应等于3请求计数
            if (query_req0_cnt != sum_pre_query_req_0_255 % 256) or (query_rsp0_cnt != sum_pre_query_rsp_0_255 % 256)\
                or (query_req3_cnt != sum_query_req_0_255 % 256) or (query_rsp3_cnt != sum_query_rsp_0_255 % 256):
                tb.log.info("DFX cnt are not equal twice query_req0_cnt is {}, sim_query_req0_cnt is {}".format(query_req0_cnt, sum_pre_query_req_0_255 % 256))
                tb.log.info("DFX cnt are not equal twice query_rsp0_cnt is {}, sim_query_rsp0_cnt is {}".format(query_rsp0_cnt, sum_pre_query_rsp_0_255 % 256))
                tb.log.info("DFX cnt are not equal twice query_req3_cnt is {}, sim_query_req3_cnt is {}".format(query_req3_cnt, sum_query_req_0_255 % 256))
                tb.log.info("DFX cnt are not equal twice query_rsp3_cnt is {}, sim_query_rsp3_cnt is {}".format(query_rsp3_cnt, sum_query_rsp_0_255 % 256))
                #assert False, " There are some DFX cnt are not equal in chn0 twice query."
            else :
                tb.log.info("DFX cnt are equal twice query_req0_cnt is {}, sim_query_req0_cnt is {}".format(query_req0_cnt, sum_pre_query_req_0_255 % 256))
                tb.log.info("DFX cnt are equal twice query_rsp0_cnt is {}, sim_query_rsp0_cnt is {}".format(query_rsp0_cnt, sum_pre_query_rsp_0_255 % 256))
                tb.log.info("DFX cnt are equal twice query_req3_cnt is {}, sim_query_req3_cnt is {}".format(query_req3_cnt, sum_query_req_0_255 % 256))
                tb.log.info("DFX cnt are equal twice query_rsp3_cnt is {}, sim_query_rsp3_cnt is {}".format(query_rsp3_cnt, sum_query_rsp_0_255 % 256))
        else: # 0通道一次查询，第一次请求响应计数等于0请求响应次数
            if (query_req0_cnt != sum_pre_query_req_0_255 % 256) or (query_rsp0_cnt != sum_pre_query_rsp_0_255 % 256):
                tb.log.info("DFX cnt are not equal single query_req0_cnt is {}, sim_query_req0_cnt is {}".format(query_req0_cnt, sum_pre_query_req_0_255 % 256))
                tb.log.info("DFX cnt are not equal single query_rsp0_cnt is {}, sim_query_rsp0_cnt is {}".format(query_rsp0_cnt, sum_pre_query_rsp_0_255 % 256))
                #assert False, " There are some DFX cnt are not equal in chn0 single query."
            else :
                tb.log.info("DFX cnt are equal single query_req0_cnt is {}, sim_query_req0_cnt is {}".format(query_req0_cnt, sum_pre_query_req_0_255 % 256))
                tb.log.info("DFX cnt are equal single query_rsp0_cnt is {}, sim_query_rsp0_cnt is {}".format(query_rsp0_cnt, sum_pre_query_rsp_0_255 % 256))

        if sec_en1:# 1通道二次查询，第一次响应计数等于第二次请求计数，第二次响应计数等于更新次数
            if (query_req1_cnt != sum_pre_query_req_256_511 % 256) or (query_rsp1_cnt != sum_pre_query_rsp_256_511 % 256)\
                or (query_req4_cnt != sum_query_req_256_511 % 256) or (query_rsp4_cnt != sum_query_rsp_256_511 % 256):
                tb.log.info("DFX cnt are not equal twice query_req1_cnt is {}, sim_query_req1_cnt is {}".format(query_req1_cnt, sum_pre_query_req_256_511 % 256))
                tb.log.info("DFX cnt are not equal twice query_rsp1_cnt is {}, sim_query_rsp1_cnt is {}".format(query_rsp1_cnt, sum_pre_query_rsp_256_511 % 256))
                tb.log.info("DFX cnt are not equal twice query_req4_cnt is {}, sim_query_req4_cnt is {}".format(query_req4_cnt, sum_query_req_256_511 % 256))
                tb.log.info("DFX cnt are not equal twice query_rsp4_cnt is {}, sim_query_rsp4_cnt is {}".format(query_rsp4_cnt, sum_query_rsp_256_511 % 256))
                #assert False, " There are some DFX cnt are not equal in chn1 twice query."
            else:
                tb.log.info("DFX cnt are equal twice query_req1_cnt is {}, sim_query_req1_cnt is {}".format(query_req1_cnt, sum_pre_query_req_256_511 % 256))
                tb.log.info("DFX cnt are equal twice query_rsp1_cnt is {}, sim_query_rsp1_cnt is {}".format(query_rsp1_cnt, sum_pre_query_rsp_256_511 % 256))
                tb.log.info("DFX cnt are equal twice query_req4_cnt is {}, sim_query_req4_cnt is {}".format(query_req4_cnt, sum_query_req_256_511 % 256))
                tb.log.info("DFX cnt are equal twice query_rsp4_cnt is {}, sim_query_rsp4_cnt is {}".format(query_rsp4_cnt, sum_query_rsp_256_511 % 256))
        else: # 1通道一次查询，第一次请求响应计数等于1请求响应次数
            if (query_req1_cnt != sum_pre_query_req_256_511 % 256) or (query_rsp1_cnt != sum_pre_query_rsp_256_511 % 256):
                tb.log.info("DFX cnt are not equal single query_req1_cnt is {}, sim_query_req1_cnt is {}".format(query_req1_cnt, sum_pre_query_req_256_511 % 256))
                tb.log.info("DFX cnt are not equal single query_rsp1_cnt is {}, sim_query_rsp1_cnt is {}".format(query_rsp1_cnt, sum_pre_query_rsp_256_511 % 256))
                #assert False, " There are some DFX cnt are not equal in chn1 single query."
            else:
                tb.log.info("DFX cnt are  equal single query_req1_cnt is {}, sim_query_req1_cnt is {}".format(query_req1_cnt, sum_pre_query_req_256_511 % 256))
                tb.log.info("DFX cnt are  equal single query_rsp1_cnt is {}, sim_query_rsp1_cnt is {}".format(query_rsp1_cnt, sum_pre_query_rsp_256_511 % 256))
        if sec_en2:# 2通道只有一次查询
            pass
        else: # 2通道一次查询，第一次响应计数等于更新次数
            if (query_req2_cnt != sum_pre_query_req_512_767 % 256) or (query_rsp2_cnt != sum_pre_query_rsp_512_767 % 256):
                tb.log.info("DFX cnt are not equal single query_req2_cnt is {}, sim_query_req2_cnt is {}".format(query_req2_cnt, sum_pre_query_req_512_767 % 256))
                tb.log.info("DFX cnt are not equal single query_rsp2_cnt is {}, sim_query_rsp2_cnt is {}".format(query_rsp2_cnt, sum_pre_query_rsp_512_767 % 256))
                #assert False, " There are some DFX cnt are not equal in chn2 single query."
            else :
                tb.log.info("DFX cnt are  equal single query_req2_cnt is {}, sim_query_req2_cnt is {}".format(query_req2_cnt, sum_pre_query_req_512_767 % 256))
                tb.log.info("DFX cnt are  equal single query_rsp2_cnt is {}, sim_query_rsp2_cnt is {}".format(query_rsp2_cnt, sum_pre_query_rsp_512_767 % 256))
        #########测试写清零
        await Timer(500, 'ns')
        data_clr = 0xFFFFFFFF
        await tb.reg_wr_req(addr = addr2, data = data_clr)
        await tb.reg_wr_req(addr = addr3, data = data_clr)
        await tb.reg_wr_req(addr = addr4, data = data_clr)

        await Timer(500, 'ns')
        await tb.reg_rd_req(addr = addr2)
        rdata2_clr = await tb.reg_rd_queue_rsp.get()
        await tb.reg_rd_req(addr = addr3)
        rdata3_clr = await tb.reg_rd_queue_rsp.get()
        await tb.reg_rd_req(addr = addr4)
        rdata4_clr = await tb.reg_rd_queue_rsp.get()
        rdata2_clr = int((rdata2_clr & 0xFFFF))
        rdata3_clr = int((rdata3_clr & 0xFFFF))
        rdata4_clr = int((rdata4_clr & 0xFFFF))

        if rdata2_clr != 0 or rdata3_clr != 0 or rdata4_clr != 0  :
            tb.log.info("rdata2_clr is {}, rdata3_clr is {}, rdata4_clr is {}".format(rdata2_clr, rdata3_clr, rdata4_clr))
            assert False, " soft write 1 to clear cnt is failed!!"
        await Timer(500, 'ns')
        await tb.dfx_reg_queue.put(1)

    async def pre_query(uids, start_time, sec_en, index, end_time):#index = 0,1,2
        global pre_query_req_cnt, pre_query_rsp_cnt
        if not uids:
            return
        tb.result_detect_end_flag = 0
        while True:
            time = math.ceil(get_sim_time("ns") - start_time)
            if time > end_time:
                tb.log.info(f"query -- time is end :{time}")
                current_time = get_sim_time("ns")
                tb.log.info(f"current time is end :{current_time}")
                tb.result_detect_end_flag = 1
                break
            time = get_sim_time("ns")
            print(time)
            uid = random.choice(uids)
            if sec_en: #开启二次查询
                obj = tb.query_req[index]._transaction_obj()#query_req index = 0,1
                obj.uid = uid
                await tb.query_req[index].send(obj)
                if uid in pre_query_req_cnt:
                    pre_query_req_cnt[uid] += 1
                else:
                    pre_query_req_cnt[uid] = 1
                pre_rsp = await tb.query_rsp[index].recv()#query_rsp index = 0,1
                if uid in pre_query_rsp_cnt:
                    pre_query_rsp_cnt[uid] += 1
                else:
                    pre_query_rsp_cnt[uid] = 1
                if pre_rsp.ok:
                    await tb.pre_query_queue[index].put((uid, get_sim_time("ns")))#index = 0,1, pre_query_queue index = 0,1  
            else: #一次查询
                await tb.only_query_queue[index].put((uid, get_sim_time("ns")))
                 
        await Timer(1000, 'ns')
        await tb.end_queue.put(1) #结束其他线程

    async def query(index, sec_en):#index = 0,1,
        global query_req_cnt, query_rsp_cnt, query_rsp_ok_cnt, pre_query_req_cnt,pre_query_rsp_cnt
        while True:
            if sec_en == 0:
                uid, last_time = await tb.only_query_queue[index].get()#only_query_queue index = 0,1,2
                obj = tb.query_req[index]._transaction_obj()#query_req index = 0,1,2
                obj.uid = uid
                await tb.query_req[index].send(obj)
                if uid in pre_query_req_cnt:
                    pre_query_req_cnt[uid] += 1
                else:
                    pre_query_req_cnt[uid] = 1
                pre_rsp = await tb.query_rsp[index].recv()#query_rsp index = 0,1,2
                if uid in pre_query_rsp_cnt:
                    pre_query_rsp_cnt[uid] += 1
                else:
                    pre_query_rsp_cnt[uid] = 1
                if pre_rsp.ok:
                    await tb.only_prequery_queue[index].put((uid, get_sim_time("ns")))#index = 0,1,2 only_prequery_queue index = 0,1,2 
            else: #两次查询
                uid, last_time = await tb.pre_query_queue[index].get()#pre_query_queue index = 0,1
                latency = math.ceil(get_sim_time("ns") - last_time)
                if latency < 1000:
                    await RisingEdge(tb.dut.clk)
                    await Timer(1000 - latency + random.randint(1, 128), "ns")
                obj = tb.query_req[index+3]._transaction_obj()#query_req index = 3,4
                obj.uid = uid
                await tb.query_req[index+3].send(obj)
                if uid in query_req_cnt:
                    query_req_cnt[uid] += 1
                else:
                    query_req_cnt[uid] = 1
                qry_rsp = await tb.query_rsp[index+3].recv()#query_rsp index = 3,4
                if uid in query_rsp_cnt:
                    query_rsp_cnt[uid] += 1
                else:
                    query_rsp_cnt[uid] = 1
                if qry_rsp.ok:
                    if uid in query_rsp_ok_cnt:
                        query_rsp_ok_cnt[uid] += 1
                    else:
                        query_rsp_ok_cnt[uid] = 1
                    await tb.query_queue[index].put((uid, get_sim_time("ns"))) #query_queue index = 0,1

    async def update(start_time, sec_en, index, update_len_num, pkt_num):
        global bw_update_req_cnt
        while True:
            time = math.ceil(get_sim_time("ns") - start_time)
            if sec_en == 1:
                uid, last_time = await tb.query_queue[index].get()#query_queue index = 0,1
                latency = math.ceil(get_sim_time("ns") - last_time)
                if latency < 20:
                    await RisingEdge(tb.dut.clk)
                    await Timer(20 - latency + random.randint(1, 6), "ns")
                obj = tb.update_req[index]._transaction_obj()#update_req index = 0,1
                obj.uid = uid
                update_len = update_len_num  
                obj.len = update_len
                update_pkt_num = pkt_num
                obj.pkt_num = update_pkt_num
                await tb.update_req[index].send(obj)
                if uid in bw_update_req_cnt:
                    bw_update_req_cnt[uid] += 1
                else:
                    bw_update_req_cnt[uid] = 1
            else :
                uid, last_time = await tb.only_prequery_queue[index].get()#only_prequery_queue index = 0,1,2
                latency = math.ceil(get_sim_time("ns") - last_time)
                if latency < 20:
                    await RisingEdge(tb.dut.clk)
                    await Timer(20 - latency + random.randint(1, 6), "ns")
                obj = tb.update_req[index]._transaction_obj()#update_req index = 0,1,2
                obj.uid = uid
                update_len = update_len_num
                obj.len = update_len
                update_pkt_num = pkt_num
                obj.pkt_num = update_pkt_num
                await tb.update_req[index].send(obj)
                if uid in bw_update_req_cnt:
                    bw_update_req_cnt[uid] += 1
                else:
                    bw_update_req_cnt[uid] = 1

    async def query_update_def(uids,  sec_en, end_time, index, update_len_num, pkt_num):
        await Timer(5000, "ns")
        start_time = get_sim_time("ns")
        pre_query_cr = cocotb.start_soon(pre_query(uids, start_time, sec_en, index, end_time))
        query_cr     = cocotb.start_soon(query(index, sec_en))
        update_cr    = cocotb.start_soon(update(start_time, sec_en, index, update_len_num, pkt_num))
        
    async def cir_test(selected_uid0, selected_uid1, selected_uid2, 
                        sec_en0, sec_en1, sec_en2, end_time, 
                        index0, index1, index2,
                        update_len_num, pkt_num,
                        selected_count0, selected_count1, selected_count2, NS_PER_SECOND):
        global pre_query_req_cnt ,pre_query_rsp_cnt,query_req_cnt ,query_rsp_cnt ,query_rsp_ok_cnt ,bw_update_req_cnt 
        pre_query_req_cnt = {}
        pre_query_rsp_cnt = {}
        query_req_cnt = {}
        query_rsp_cnt = {}
        query_rsp_ok_cnt  ={}
        bw_update_req_cnt ={}
        tb.log.info("cir_test the uid0 is :{}".format(selected_uid0))
        tb.log.info("cir_test the uid1 is :{}".format(selected_uid1))
        tb.log.info("cir_test the uid2 is :{}".format(selected_uid2))
        
        query_update_def0_cr = cocotb.start_soon(query_update_def(selected_uid0, sec_en0, end_time, index0, update_len_num, pkt_num))
        query_update_def1_cr = cocotb.start_soon(query_update_def(selected_uid1, sec_en1, end_time, index1, update_len_num, pkt_num))
        query_update_def2_cr = cocotb.start_soon(query_update_def(selected_uid2, sec_en2, end_time, index2, update_len_num, pkt_num))
        cir_update_cr        = cocotb.start_soon(cir_update(end_time, selected_uid0, selected_uid1, selected_uid2, selected_count0, selected_count1, selected_count2, NS_PER_SECOND))

    async def cir_update(end_time, selected_uid0, selected_uid1, selected_uid2, selected_count0, selected_count1, selected_count2, NS_PER_SECOND):
        global bwg_cir, qpsg_cir
        selected_uid = selected_uid0 + selected_uid1 + selected_uid2
        latency = NS_PER_SECOND * 5
        start_time = get_sim_time("ns")
        while True:
            time = math.ceil(get_sim_time("ns") - start_time)
            if time > (end_time + 6000):
                tb.log.info(f"cirupdate time is end :{time}")
                current_time = get_sim_time("ns")
                tb.log.info(f"current time is end :{current_time}")
                break
            await RisingEdge(tb.dut.clk)
            await Timer(500, "ns")
            bwg_cir = 400000//(selected_count0 + selected_count1 + selected_count2)
            qpsg_cir = 409836//(selected_count0 + selected_count1 + selected_count2)
            uid_cir_cbs = gen_uid_cir_cbs_en(selected_uid, bwg_cir, qpsg_cir)
            for addr, data in uid_cir_cbs:
                await tb.reg_wr_req(addr = addr, data = data)
            await tb.reg_rd_req(addr = 0x0)
            rdata0 = await tb.reg_rd_queue_rsp.get()

            await Timer(latency, "ns")
            bwg_cir = 320000//(selected_count0 + selected_count1 + selected_count2)
            qpsg_cir = 327869//(selected_count0 + selected_count1 + selected_count2)
            uid_cir_cbs = gen_uid_cir_cbs_en(selected_uid, bwg_cir, qpsg_cir)
            for addr, data in uid_cir_cbs:
                await tb.reg_wr_req(addr = addr, data = data)
            await tb.reg_rd_req(addr = 0x0)
            rdata0 = await tb.reg_rd_queue_rsp.get()

            await Timer(latency, "ns")
            bwg_cir = 160000//(selected_count0 + selected_count1 + selected_count2)
            qpsg_cir = 163934//(selected_count0 + selected_count1 + selected_count2)
            uid_cir_cbs = gen_uid_cir_cbs_en(selected_uid, bwg_cir, qpsg_cir)
            for addr, data in uid_cir_cbs:
                await tb.reg_wr_req(addr = addr, data = data)
            await tb.reg_rd_req(addr = 0x0)
            rdata0 = await tb.reg_rd_queue_rsp.get()

            await Timer(latency, "ns")
            bwg_cir = 8000//(selected_count0 + selected_count1 + selected_count2)
            qpsg_cir = 8197//(selected_count0 + selected_count1 + selected_count2)
            uid_cir_cbs = gen_uid_cir_cbs_en(selected_uid, bwg_cir, qpsg_cir)
            for addr, data in uid_cir_cbs:
                await tb.reg_wr_req(addr = addr, data = data)
            await tb.reg_rd_req(addr = 0x0)
            rdata0 = await tb.reg_rd_queue_rsp.get()
            await Timer(latency, "ns")


    async def result_detect2( len_num, pkt_num, selected_uid, NS_PER_SECOND):
        bw_update_req_last_cnt = {}
        last_time = 0
        while True:
            latency = math.ceil(get_sim_time("ns") - last_time)
            if latency < NS_PER_SECOND:
                await RisingEdge(tb.dut.clk)
                await Timer(NS_PER_SECOND - latency, "ns")
            last_time = get_sim_time("ns")
            bw_cir = bwg_cir
            qps_cir = qpsg_cir
            if NS_PER_SECOND == 10_000_000:
                cir_div = 100
            elif NS_PER_SECOND == 1_000_000:
                cir_div = 1000
            else :
                cir_div = 1
            for uid in selected_uid:
                pre_query_req_r = pre_query_req_cnt.get(uid, 0)
                pre_query_rsp_r = pre_query_rsp_cnt.get(uid, 0)
                query_req_r     = query_req_cnt.get(uid, 0)
                query_rsp_r     = query_rsp_cnt.get(uid, 0)
                query_rsp_ok_r  = query_rsp_ok_cnt.get(uid, 0)
                bw_update_req_r = bw_update_req_cnt.get(uid, 0)
                bw_update_req_last_cnt_r = bw_update_req_last_cnt.get(uid,0)
                update_cnt_diff = bw_update_req_r - bw_update_req_last_cnt_r
                bw_update_req_last_cnt[uid] = bw_update_req_r
                bw_cir1  = (bw_cir * 125)//cir_div
                bw_cir2  = ((len_num * update_cnt_diff)*8)//1000
                error_bw_cir = ((bw_cir2-bw_cir1)/bw_cir1)*100
                qps_cir1  = (qps_cir * 122)//cir_div
                qps_cir2  = pkt_num * update_cnt_diff
                error_qps_cir = ((qps_cir2-qps_cir1)/qps_cir1)*100
                if tb.result_detect_end_flag == 0:
                    tb.log.info("current_time is :{}, uid is :{}, update_cnt_diff is :{}, count_bw_cir is :{}, test_bw_cir is :{}, error_bw_cir is :{:.2f}% ".format(last_time, uid, update_cnt_diff, bw_cir1, bw_cir2, error_bw_cir))
                    tb.log.info("current_time is :{}, uid is :{}, update_cnt_diff is :{}, count_qps_cir is :{}, test_qps_cir is :{}, error_qps_cir is :{:.2f}% ".format(last_time, uid, update_cnt_diff, qps_cir1, qps_cir2, error_qps_cir))
                    tb.log.info("pre_query_req_r is :{},pre_query_rsp_r is :{} ".format(pre_query_req_r, pre_query_rsp_r ))
                    tb.log.info("query_req_r is :{},query_rsp_r is :{} ".format(query_req_r, query_rsp_r ))
                    tb.log.info("query_rsp_ok_r is :{},bw_update_req_r is :{} ".format(query_rsp_ok_r, bw_update_req_r ))

    ###############################################################################################
    ########calc模块单独仿真########################
    async def calc_test():
        while True:
            i, uid, curr_time, bw_last_time, qps_last_time, bw_cir, qps_cir, bw_cbs, qps_cbs, bw_token, qps_token, bw_len, qps_pkt_num = await tb.calc_req_queue.get()
            obj = tb.calc_req._transaction_obj()
            obj.uid             = uid
            obj.curr_time       = curr_time    
            obj.bw_last_time    = bw_last_time 
            obj.qps_last_time   = qps_last_time
            obj.bw_cir          = bw_cir       
            obj.qps_cir         = qps_cir      
            obj.bw_cbs          = bw_cbs       
            obj.qps_cbs         = qps_cbs      
            obj.bw_token        = bw_token     
            obj.qps_token       = qps_token    
            obj.bw_len          = bw_len       
            obj.qps_pkt_num     = qps_pkt_num  
            await tb.calc_req.send(obj)
            await tb.calc_req1_queue.put((i, uid, curr_time, bw_last_time, qps_last_time, bw_cir, qps_cir, bw_cbs, qps_cbs, bw_token, qps_token, bw_len, qps_pkt_num))

    async def result_test():
        while True:
            calc_result = await tb.calc_rsp.recv()
            await tb.calc_rsp_queue.put((calc_result.bw_token_result, calc_result.qps_token_result, calc_result.token_result_uid))

    async def result_check():
        MAX_24BIT = 2**24
        while True:
            i, uid, curr_time, bw_last_time, qps_last_time, bw_cir, qps_cir, bw_cbs, qps_cbs, bw_token, qps_token, bw_len, qps_pkt_num = await tb.calc_req1_queue.get()
            if curr_time >= bw_last_time:
                bw_diff = curr_time - bw_last_time
            else:
                bw_diff = curr_time + (MAX_24BIT - bw_last_time)
            if curr_time >= qps_last_time:
                qps_diff = curr_time - qps_last_time
            else:
                qps_diff = curr_time + (MAX_24BIT - qps_last_time)
            
            bw_cir_result0  = bw_diff * bw_cir + bw_token - 256 * bw_len
            qps_cir_result0 = qps_diff * qps_cir + qps_token - 32768 * qps_pkt_num
            
            if bw_cir_result0 < 0:
                if bw_cbs + bw_cir_result0 >=0:
                    bw_cir_result1 = bw_cir_result0
                else :
                    bw_cir_result1 = bw_cir_result0
            else :
                if bw_cbs - bw_cir_result0 >=0:
                    bw_cir_result1 = bw_cir_result0
                else :
                    bw_cir_result1 = bw_cbs
            if qps_cir_result0 < 0:
                if qps_cbs + qps_cir_result0 >=0:
                    qps_cir_result1 = qps_cir_result0
                else :
                    qps_cir_result1 = qps_cir_result0
            else :
                if qps_cbs - qps_cir_result0 >=0:
                    qps_cir_result1 = qps_cir_result0
                else :
                    qps_cir_result1 = qps_cbs
            bw_token_result, qps_token_result, token_result_uid = await tb.calc_rsp_queue.get()
            
            token_result_uid = str(token_result_uid)
            bw_token_result = str(bw_token_result)
            qps_token_result = str(qps_token_result)
            token_result_uid_decimal = int(token_result_uid, 2)
            tb.log.info("token_result_uid_decimal 2 is {}".format(token_result_uid_decimal))
            bw_token_result_decimal = binary_to_signed_decimal(bw_token_result, 44)
            qps_token_result_decimal = binary_to_signed_decimal(qps_token_result, 44)
            if uid == token_result_uid_decimal and bw_cir_result1 == bw_token_result_decimal and qps_cir_result1 == qps_token_result_decimal:
                tb.log.info("///////////pass//////////////")
                tb.log.info("check max_seq:{}".format(i)) 
                tb.log.info("bw_diff:{}, qps_diff :{}".format(bw_diff, qps_diff))
                tb.log.info("bw_cir:{}, qps_cir :{}".format(bw_cir, qps_cir))
                tb.log.info("bw_cbs:{}, qps_cbs :{}".format(bw_cbs, qps_cbs))
                tb.log.info("req uid:{}, rsp uid :{}".format(uid, token_result_uid_decimal))
                tb.log.info("req uid:{}, rsp uid :{}, curr_time:{}, bw_last_time:{}".format( uid, token_result_uid_decimal, curr_time, bw_last_time))
                tb.log.info("req bw_cir_result1:{}, rsp bw_token_result :{}".format(bw_cir_result1, bw_token_result_decimal))
                tb.log.info("req qps_cir_result1:{}, rsp qps_token_result :{}".format(qps_cir_result1, qps_token_result_decimal))
            else:
                tb.log.info("///////////error//////////////")
                tb.log.info("check max_seq:{}".format(i))
                tb.log.info("req uid:{}, rsp uid :{}".format(uid, token_result_uid_decimal))
                tb.log.info("req bw_cir_result1:{}, rsp bw_token_result :{}".format(bw_cir_result1, bw_token_result_decimal))
                tb.log.info("req qps_cir_result1:{}, rsp qps_token_result :{}".format(qps_cir_result1, qps_token_result_decimal))
                tb.log.info("req uid:{}, rsp uid :{}, curr_time:{}, bw_last_time:{}".format( uid, token_result_uid_decimal, curr_time, bw_last_time))
                tb.log.info("qps_last_time:{}, bw_cir:{}, qps_cir:{}, bw_cbs:{}".format(qps_last_time, bw_cir, qps_cir, bw_cbs))
                tb.log.info("qps_cbs:{}, bw_token:{}, qps_token:{}, bw_len:{}".format(qps_cbs, bw_token, qps_token, bw_len))
                tb.log.info("qps_pkt_num:{}".format(qps_pkt_num))
                tb.log.info("bw_diff:{}, qps_diff :{}".format(bw_diff, qps_diff))
                tb.log.info("bw_cir_result0:{}, qps_cir_result0 :{}".format(bw_cir_result0, qps_cir_result0))
                assert False, "calc req and rsp are not equal."
                    
    async def run_test_calc(max_seq):
        prev_curr_time = 8388600
        MAX_24BIT = 2**23
        for i in range(max_seq):
            tb.log.info("max_seq:{}".format(i))
            #uid
            uid = random.randint(0, 767)    
            #time
            time_diff = random.randint(20000, 30000)    
            bw_last_time = (prev_curr_time + time_diff) % MAX_24BIT
            qps_last_time = bw_last_time 
            curr_time = (bw_last_time + time_diff) % MAX_24BIT       
            prev_curr_time = curr_time
            #cir cbs
            bw_cir = random.randint(1000, 2**19-2)         
            qps_cir = random.randint(1000, 2**19-2)  
            bw_cbs = random.randint(1000, 2**42-2)     
            qps_cbs = random.randint(1000, 2**42-2)  
            
            #bw qps token
            bw_token = random.randint(-bw_cbs, bw_cbs)      
            qps_token = random.randint(-qps_cbs, qps_cbs)
            #len pkt_num 
            bw_len = random.randint(0, 1048575)          
            qps_pkt_num = random.randint(0, 255)    
            #tb.log.info("/////////start////////////")
            #tb.log.info("bw_cbs:{}, qps_cbs :{}, cbs_multiple :{}".format(bw_cbs, qps_cbs, cbs_multiple))
            #tb.log.info("uid :{}, bw_cir:{}, qps_cir :{}".format(uid, bw_cir, qps_cir))
            await tb.calc_req_queue.put((i, uid, curr_time, bw_last_time, qps_last_time, bw_cir, qps_cir, bw_cbs, qps_cbs, bw_token, qps_token, bw_len, qps_pkt_num))
            calc_test_cr = cocotb.start_soon(calc_test())
            result_test_cr = cocotb.start_soon(result_test())
            result_check_cr = cocotb.start_soon(result_check())
        await Timer(50000, 'ns')
    ##################################
    if len_pkt_modes == "len_mode":
        update_len_num = 1000
        pkt_num = 0
    elif len_pkt_modes == "pkt_mode":
        update_len_num = 0
        pkt_num = 8
    else:
        update_len_num = 1000
        pkt_num = 8
    
    index0 = 0                      # 0：使用查询接口[4:0]的[0]作为第一次查询，[3]作为第二次查询，使用更新接口[2:0]的[0]去更新
    index1 = 1                      # 1：使用查询接口[4:0]的[1]作为第一次查询，[4]作为第二次查询，使用更新接口[2:0]的[1]去更新
    index2 = 2                      # 2：使用查询接口[4:0]的[2]作为第一次查询，使用更新接口[2:0]的[2]去更新

    #if sec_en_modes == "sec_en_11":
    #    sec_en0 = 1                 # 0：关闭第二次查询，只查询一次；0725版本不支持第二次查询
    #    sec_en1 = 1                 # 0：关闭第二次查询，只查询一次；0725版本不支持第二次查询
    #else:
    #    sec_en0 = 0
    #    sec_en1 = 1
    sec_en0 = 0
    sec_en1 = 0
    sec_en2 = 0                     # 0：关闭第二次查询，只查询一次，不支持第二次查询功能
    end_time = 200*(10**6) + 10**3   # 结束时间：到结束事件后跳出循环结束仿真
    NS_PER_SECOND = 10_000_000      # CIR计算的时间粒度，10_000_000表示每10ms计算一次，1_000_000表示每1ms计算一次

    await Timer(50000, 'ns')
    max_seq = 10
    ##functional verification
    uids0 = list(range(0,256))
    uids1 = list(range(256,512))
    uids2 = list(range(512,768))
    if uid_cnt_modes == "uid_cnt_100":
        selected_count0 = min(1, len(uids0))
        selected_count1 = min(0, len(uids1))
        selected_count2 = min(0, len(uids2))
    else:
        selected_count0 = min(1, len(uids0))
        selected_count1 = min(1, len(uids1))
        selected_count2 = min(1, len(uids2))
    selected_uid0 = random.sample(uids0, selected_count0)
    selected_uid1 = random.sample(uids1, selected_count1)
    selected_uid2 = random.sample(uids2, selected_count2)
    selected_uid  = selected_uid0 + selected_uid1 + selected_uid2
    cir_test_cr   = cocotb.start_soon(cir_test(selected_uid0, selected_uid1, selected_uid2, 
                    sec_en0, sec_en1, sec_en2, end_time, 
                    index0, index1, index2, 
                    update_len_num, pkt_num,
                    selected_count0, selected_count1, selected_count2, NS_PER_SECOND))
    result_detect2_cr    = cocotb.start_soon(result_detect2( update_len_num, pkt_num, selected_uid, NS_PER_SECOND))
    run_test_calc_cr     = cocotb.start_soon(run_test_calc( max_seq))
    end_flag = await tb.end_queue.get()
    await Timer(200000000, 'ns')#20000000
    ##dfx rd
    read_dfx_reg_cr = cocotb.start_soon( read_dfx_reg(sec_en0, sec_en1, sec_en2))
    dfx_reg_flag0   = await tb.dfx_reg_queue.get()
    await Timer(500, 'ns')
    ram_clr = 0
    ram_addr = selected_uid0[0]*0x200 + 0x30
    tb.log.info(f"ram_addr is {ram_addr}")
    await tb.reg_rd_req(addr = ram_addr)
    rdata_ram0 = await tb.reg_rd_queue_rsp.get()
    tb.log.info(f"rdata_ram0 is {int(rdata_ram0)}")
    await tb.reg_wr_req(addr = ram_addr, data = ram_clr)
    await tb.reg_rd_req(addr = ram_addr)
    rdata_ram = await tb.reg_rd_queue_rsp.get()
    rdata_ram = int(rdata_ram)
    assert rdata_ram == 0, f"ram witer 0 is err"
    await Timer(100000, 'ns')
    
def cycle_pause():
    seed = [1 if i < 500 else 0 for i in range(1000)]
    random.shuffle(seed)
    #seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test_qos]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [cycle_pause,None])
        factory.add_option("backpressure_inserter", [cycle_pause, None])
        default_len_pkt_modes  = ["len_mode", "pkt_mode", "len_pkt_mode"]
        selected_len_pkt_modes  = os.getenv("COCOTB_LEN_PKT_MODES", ",".join(default_len_pkt_modes)).split(",")
        factory.add_option("len_pkt_modes", selected_len_pkt_modes)
        #default_sec_en_modes = ["sec_en_11", "sec_en_01"]
        #selected_sec_en_modes = os.getenv("COCOTB_SEC_EN_MODES", ",".join(default_sec_en_modes)).split(",")
        #factory.add_option("sec_en_modes", selected_sec_en_modes)
        default_uid_cnt_modes = ["uid_cnt_100", "uid_cnt_111"]
        selected_uid_cnt_modes = os.getenv("COCOTB_UID_CNT_MODES", ",".join(default_uid_cnt_modes)).split(",")
        factory.add_option("uid_cnt_modes", selected_uid_cnt_modes)
        factory.generate_tests()

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)

#from debug import *

