#!/usr/bin/env python3
################################################################################
#  文件名称 : test_beq_feq2bid_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/11/25
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  11/25     Joe Jiang   初始化版本
################################################################################
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import Lock, RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory


sys.path.append('../common')
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster
from stream_bus import define_stream

netQid2BidReqBus, _, netQid2BidReqSource, _, _ = define_stream("net_qid2bid_req",
    signals=["idx"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None
)

netQid2BidRspBus, _, _, netQid2BidRspSink, _ = define_stream("net_qid2bid_rsp",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None
)

blkQid2BidReqBus, _, blkQid2BidReqSource, _, _ = define_stream("blk_qid2bid_req",
    signals=["idx"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None
)

blkQid2BidRspBus, _, _, blkQid2BidRspSink, _ = define_stream("blk_qid2bid_rsp",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None
)

#维护两张表（sel=0 和 sel=1），存储 feid 到 bid 的映射
class TblBehavior:
    #初始化两张表，将所有feid的初始映射设为0
    def __init__(self, num_feq):
        self._tbl = ({}, {})
        for i in range(num_feq):
            self._tbl[0][i] = 0
            self._tbl[1][i] = 0
    #更新映射
    def set(self, sel, feid, bid):
        sel = int(sel) & 0x1  # 强制 sel 为 0 或 1
        print(f"Debug: sel={sel}, int(sel)={int(sel)}, feid={feid}, bid={bid}")  # 调试
        print(f"self._tbl length: {len(self._tbl)}")  # 检查元组长度
        self._tbl[sel][int(feid)] = int(bid)
    #查询映射
    def get(self, sel, feid):
        return self._tbl[int(sel)][int(feid)]

class Behavior:
    def __init__(self, num_feq, num_beq, csr_if):
        self.log = SimLog("cocotb.bhv")
        self._num_beq = num_beq  #beq数量
        self._num_feq = num_feq  #feq数量
        self._csr_if = csr_if

         # 定义 CSR 地址常量
        self.NET_SEL_ADDR = 0x100000
        self.BLK_SEL_ADDR = 0x101000
        
        self._gen = ([0 for _ in range(self._num_feq)], [0 for _ in range(self._num_feq)]) #版本号计数
        self._tbls = (TblBehavior(num_feq), TblBehavior(num_feq))
        self._lock = Lock()

    async def get_net_sel(self):
        #从CSR读取net_sel_sig的当前值
        #return (await self._csr_if.read(self.NET_SEL_ADDR)) & 0x1
        return await self._csr_if.read(self.NET_SEL_ADDR)

    async def get_blk_sel(self):
        #从CSR读取blk_sel_sig的当前值
        #return (await self._csr_if.read(self.BLK_SEL_ADDR)) & 0x1
        return await self._csr_if.read(self.BLK_SEL_ADDR)
    
    #切换活跃表
    async def change_tbl(self, is_net):
        async with self._lock:
            if is_net:
                for i in range(len(self._gen[0])):
                    self._gen[0][i] = self._gen[0][i] + 1 
                # 读取当前值并翻转
                current_val = await self.get_net_sel()
                new_val = 0 if current_val != 0 else 1
                await self._csr_if.write(self.NET_SEL_ADDR, new_val)  

#                self._net_sel_sig.setimmediatevalue(0 if int(self._net_sel_sig.value) != 0 else 1)
            else:
                for i in range(len(self._gen[1])):
                    self._gen[1][i] = self._gen[1][i] + 1
                # 读取当前值并翻转
                current_val = int(await self.get_blk_sel())
                new_val = 0 if current_val != 0 else 1
                await self._csr_if.write(self.BLK_SEL_ADDR, new_val)

#                self._blk_sel_sig.setimmediatevalue(0 if int(self._blk_sel_sig.value) != 0 else 1)

    async def cfg_set(self, is_net, feid, bid):
        async with self._lock:
            tbl_index = 0 if is_net else 1
            current_sel = await self.get_net_sel() if is_net else await self.get_blk_sel()

            #更新内部表
            self._tbls[tbl_index].set(current_sel,feid,bid)
            self._gen[tbl_index][feid] += 1

            #日志和调试信息
            self.log.debug(f"cfg_set {'net' if is_net else 'blk'} {self._gen[tbl_index][feid]} {feid} {bid} {current_sel}")
            print(f"cfg_set_feid = {feid}, current_sel = {current_sel}")

            #计算地址并写入
            addr = feid * 0x20 + current_sel * 0x8 + (0 if is_net else 0x40000)
            print(f"cfg_set: is_net={is_net}, feid={feid}, bid={bid}, current_sel={current_sel}")
            print(f"addr={hex(addr)}, write_value={bid}")
            await self._csr_if.write(addr, bid)

            #回读验证
            read_back = await self._csr_if.read(addr)
            print(f"read_back={int(read_back)} (expected {bid})")

            if read_back != bid:
                breakpoint()
                raise ValueError("CSR readback mismatch!!!")


            #assert read_back == bid, f"CSR readback mismatch: {read_back} != {bid}"

        #if is_net:
        #    async with self._lock:
        #        current_sel = int(await self.get_net_sel())  #获取sel值
        #        self._tbls[0].set(current_sel, feid, bid)  # 更新内部表
        #        self._gen[0][feid] = self._gen[0][feid] + 1 
        #        self.log.debug("cfg_set net {} {} {} {}".format(self._gen[0][feid], feid, bid, current_sel))
        #        print("cfg_set_feid = ",(feid),"current_sel = ",(current_sel))
        #        addr = feid * 0x20 + current_sel * 0x8
        #        print(f"cfg_set_addr = {hex(addr)},bid = {bid}")
        #        await self._csr_if.write(addr, bid)
        #        read_back = await self._csr_if.read(addr)
        #        assert read_back == bid, f"CSR readback mismatch: {read_back} != {bid}"
        #else:
        #    async with self._lock:
        #        current_sel = int(await self.get_blk_sel())
        #        self._tbls[1].set(current_sel, feid, bid)
        #        self._gen[1][feid] = self._gen[1][feid] + 1
        #       self.log.debug("cfg_set blk {} {} {} {}".format(self._gen[0][feid], feid, bid, current_sel))
        #         #print("blk_cfg_set_feid = ",(feid),"current_sel = ",(current_sel))
        #        addr = feid * 0x20 + current_sel * 0x8 + 0x40000
        #         #print(f"blk_cfg_set_addr = {hex(addr)},bid = {bid}")
        #        await self._csr_if.write(addr, bid)
        #        read_back = await self._csr_if.read(addr)
        #        assert read_back == bid, f"CSR readback mismatch: {read_back} != {bid}"
    
    async def cfg_get(self, is_net, feid):
        async with self._lock:
            #if is_net:
                    current_sel = await self.get_net_sel() if is_net else await self.get_blk_sel()
                    await Timer(10, "ns")  # 等待硬件稳定
                    bid = self._tbls[0 if is_net else 1].get(current_sel, feid)
                    return self._gen[0 if is_net else 1][feid], bid
                    #return self._gen[0][feid], self._tbls[0].get(current_sel, feid)
            #else:
                    #current_sel = int(await self.get_blk_sel())
                    #return self._gen[1][feid], self._tbls[1].get(current_sel, feid)
    
    #检查生成计数器是否匹配
    def check_gen(self, is_net, feid, gen):
        return (self._gen[0][feid] == gen) if is_net else (self._gen[1][feid] == gen)

    async def cfg_rd(self, is_net, feid):
        current_sel = await self.get_net_sel() if is_net else await self.get_blk_sel()
        if is_net:
            print("feid = ",(feid),"current_sel = ",(current_sel))
            addr = feid * 0x20 + current_sel * 0x8
            print("addr = ",hex(addr))
        else:
            addr = feid * 0x20 + current_sel * 0x8 + 0x40000
        return await self._csr_if.read(addr)


class TB(object):
    def __init__(self, dut, num_feq, num_beq):
        self.dut = dut

        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self._rand_cfg_wr_cr = None
        self._rand_cfg_rd_cr = None

        self.csrBusMaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)
        self.netQid2BidReqDrv = netQid2BidReqSource (netQid2BidReqBus.from_prefix(dut, "net_qid2bid_req"), dut.clk, dut.rst)
        self.netQid2BidRspMon = netQid2BidRspSink   (netQid2BidRspBus.from_prefix(dut, "net_qid2bid_rsp"), dut.clk, dut.rst)
        self.blkQid2BidReqDrv = blkQid2BidReqSource (blkQid2BidReqBus.from_prefix(dut, "blk_qid2bid_req"), dut.clk, dut.rst)
        self.blkQid2BidRspMon = blkQid2BidRspSink   (blkQid2BidRspBus.from_prefix(dut, "blk_qid2bid_rsp"), dut.clk, dut.rst)
        self.netQid2BidReqDrv.set_pause_generator(itertools.cycle([1, 0, 1, 1, 0, 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0]))
        self.blkQid2BidReqDrv.set_pause_generator(itertools.cycle([1, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0]))
        self._num_feq = num_feq
        self._num_beq = num_beq
        
        self.valid_num = 0
        self.ignore_num = 0
        
        #创建两个队列用于存储请求
        self._queue = (Queue(maxsize=512), Queue(maxsize=512))

        self.bhv = Behavior(self._num_feq, self._num_beq, self.csrBusMaster)


        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    async def _rand_cfg_wr(self):
         while True:
            is_net = random.randint(0, 100) > 50  #50%概率选择网络或块配置
            if random.randint(0, 100) < 10:   # 10%概率改变表
                await self.bhv.change_tbl(is_net)
            else: # # 90%概率进行配置写入
                feid = random.randint(0, self._num_feq - 1)
                bid = random.randint(0, self._num_beq - 1)
                await self.bhv.cfg_set(is_net, feid, bid)  #调用配置写入
            await Timer(random.randint(50, 400), "ns")

    async def _rand_cfg_rd(self):
        while True:
            is_net = random.randint(0, 100) > 50  # 50%概率选择网络或块配置
            feid = random.randint(0, self._num_feq - 1)
            await self.bhv.cfg_rd(is_net, feid)  #调用配置读取
            await Timer(random.randint(10,1000), "ns")

    async def test_req_thd(self, is_net, max_seq):
        for i in range(max_seq):
            print("req seq:", i)
            feid = random.randint(0, self._num_feq - 1)
            gen, bid = await self.bhv.cfg_get(is_net, feid) # 获取配置和生成号
            if is_net:
                self.log.debug("req net {} {} {}".format(gen, feid, bid))
                await self._queue[0].put((gen, feid, bid)) # 存入网络队列
                obj = self.netQid2BidReqDrv._transaction_obj() # 创建事务对象
                obj.idx = feid # 设置索引
                await self.netQid2BidReqDrv.send(obj)  # 发送请求
            else:
                self.log.debug("req blk {} {} {}".format(gen, feid, bid))
                await self._queue[1].put((gen, feid, bid))
                obj = self.blkQid2BidReqDrv._transaction_obj()
                obj.idx = feid
                await self.blkQid2BidReqDrv.send(obj)
            await RisingEdge(self.dut.clk)

    async def test_rsp_thd(self, is_net, max_seq):
        for i in range(max_seq):
            print("rsp seq:", i)
            (gen, feid, bid) = await self._queue[0].get() if is_net else await self._queue[1].get() #从相应队列获取请求信息
            rsp = await self.netQid2BidRspMon.recv() if is_net else await self.blkQid2BidRspMon.recv() #接收响应
            self.log.debug("test_rsp_thd {} {} {} {} {} {}".format("net" if is_net else blk, gen, feid, bid, rsp, self.bhv._gen[0][feid]))
            if self.bhv.check_gen(is_net, feid, gen):
                assert rsp.dat == bid
                self.valid_num = self.valid_num + 1
            else:
                self.ignore_num = self.ignore_num + 1
            

    async def cycle_reset(self):
        if self._rand_cfg_wr_cr:
            self._rand_cfg_wr_cr.kill()
            await Timer(5000, "ns")  # 等待kill结束
        if self._rand_cfg_rd_cr:
            self._rand_cfg_rd_cr.kill()
            await Timer(5000, "ns")  # 等待kill结束
        #self.dut.rst.setimmediatevalue(0)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        
        # 初始化 sel 信号为 0
        await self.bhv._csr_if.write(self.bhv.NET_SEL_ADDR, 0)
        await self.bhv._csr_if.write(self.bhv.BLK_SEL_ADDR, 0)
        await Timer(100, "ns")  # 等待写入生效

        for i in range(self._num_feq):
            await self.bhv.cfg_set(False, i, 3)
            await self.bhv.cfg_set(True, i, 3)
        await self.bhv.change_tbl(False)
        await self.bhv.change_tbl(True)
        await RisingEdge(self.dut.clk)
        for i in range(self._num_feq):
            await self.bhv.cfg_set(False, i, 3)
            await self.bhv.cfg_set(True, i, 3)
 
        
        self._rand_cfg_wr_cr = cocotb.start_soon(self._rand_cfg_wr())
        self._rand_cfg_wr_cr = cocotb.start_soon(self._rand_cfg_rd())

    def set_idle_generator(self, generator=None):
        self.csrBusMaster.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        self.csrBusMaster.set_backpressure_generator(generator)

async def run_test(dut, idle_inserter, backpressure_inserter):
    num_beq = 64
    num_feq = 256
    max_seq = 100000
    tb = TB(dut, num_feq, num_beq)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    await Timer(5000, "ns")
    rsp_cr = [cocotb.start_soon(tb.test_rsp_thd(i == 0, max_seq)) for i in range(1)]
    req_cr = [cocotb.start_soon(tb.test_req_thd(i == 0, max_seq)) for i in range(1)]
    for i in range(1):
        await req_cr[i].join()
        await rsp_cr[i].join()
    print("valid_num: {} ignore_num: {}".format(tb.valid_num, tb.ignore_num))
    await Timer(5000, "ns")

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", maxBytes=(5 * 1024 * 1024), backupCount=2)
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)


if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()