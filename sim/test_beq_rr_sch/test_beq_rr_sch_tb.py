#!/usr/bin/env python3
################################################################################
#  文件名称 : test_beq_rr_sch_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/11/18
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  11/18     Joe Jiang   初始化版本
################################################################################
import itertools
import logging
import os
import sys
import random
import cocotb_test.simulator

import cocotb
from cocotb.log import SimLog
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory


sys.path.append('../common')
from backpressure_bus import define_backpressure
from stream_bus import define_stream
from enum import Enum, unique

DoorbellBus, _, DoorbellSource, DoorbellSink, DoorbellMonitor = define_backpressure("doorbell",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    sav_signal = "sav"
)

NotifyReqBus, _, NotifyReqSource, NotifyReqSink, NotifyReqMonitor = define_stream("notify_req",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NotifyRspBus, _, NotifyRspSource, NotifyRspSink, NotifyRspMonitor = define_stream("notify_rsp",
    signals=["data"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

class NotifyRsp(Packet):
    name = 'notify_rsp'
    fields_desc = [
        BitField("qid",   0,  7),
        BitField("done",   0,  1),
        BitField("cold",   0,   1)
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    def unpack(self, data):
        assert type(data) == cocotb.binary.BinaryValue
        return NotifyRsp(data.buff)

#模拟单个队列（FIFO）的行为，包括数据存储、取出和传输延迟
class QueueBehavior():
    #初始化队列的容量和缓冲区
    def __init__(self, max_local_bus_sz = 32, ring_size = 4096, max_rd_desc_burst=8):
        self._max_rd_desc_burst = max_rd_desc_burst #读desc时的burst length为8
        self._max_local_bus_sz = max_local_bus_sz #总线位宽是256bit = 32 bytes
        self._ring_size = ring_size  #环形缓冲区大小
        self._desc_ring = Queue(maxsize=self._ring_size)  #desc ring 4096个desc
        self._local_desc_buf = Queue(maxsize=self._max_local_bus_sz) #本地缓存32个desc

    #预填充主队列（_desc_ring）为后续测试准备数据
    async def init_rxq(self):
        for _ in range(self._ring_size):
            await self._desc_ring.put(random.randint(1, 100))  #填充随机数
    
    #向队列中添加一组数据（descs）
    async def put_pkt(self, descs):
        for desc in descs:
            await self._desc_ring.put(desc)  #将desc放进desc ring

    #从主队列读取数据到本地缓冲，受背压控制（缓冲区满时停止）
    async def get_desc(self):
        if self._local_desc_buf.full():
            return self._desc_ring.empty(), True  #本地缓冲满时返回背压
        #计算本次可读取的数据量
        print("max_local_bus_sz = " ,(self._max_local_bus_sz),"local_desc_buf.qsize() = ",(self._local_desc_buf.qsize()),"desc_ring.qsize() = ",self._desc_ring.qsize(),"max_rd_desc_burst = ", self._max_rd_desc_burst)
        rd_ndesc = min(self._max_local_bus_sz - self._local_desc_buf.qsize(), self._desc_ring.qsize())
        rd_ndesc = min(rd_ndesc, self._max_rd_desc_burst)
        for i in range(rd_ndesc):
            desc = await self._desc_ring.get()  #从主队列读desc
            await self._local_desc_buf.put(desc)  #存入本地缓存
        return self._desc_ring.empty(), False  #返回不背压

    #生成随机数据包（用于测试填充队列）在 put_desc 和 recv 中调用，模拟真实数据输入
    def gen_pkt(self, ndesc=None):
        descs = []
        if ndesc == None:
            ndesc = random.randint(1, 4)  #默认生成1~4个随机数据
        for i in range(ndesc):
            descs.append(random.randint(1, 100))  #数据值为1~100的随机数
        return descs
    
    #模拟数据传输延迟（延迟时间由数据值决定）
    async def move_data(self):
        if not self._local_desc_buf.empty():
            desc = await self._local_desc_buf.get()  # 取一个数据
            await Timer(desc, "ns") # 模拟传输延迟（时间=数据值）

    #判断队列是否处理完成，被 txq_is_done 调用，用于发送队列的状态检查
    def is_done(self):
        return self._desc_ring.empty()  #检查主队列是否为空
    
class BeqBehavior():
    #初始化多个队列和后台任务
    def __init__(self, qsize = 1):
        self._db_ring = Queue(maxsize=32)  #db_ff：32x7
        self._txq = [QueueBehavior() for _ in range(qsize)]  # 发送队列列表
        self._rxq = [QueueBehavior() for _ in range(qsize)]  # 接收队列列表
        self._tx_datamove = cocotb.start_soon(self._tx_datamove())  # 启动后台数据传输

    #初始化所有接收队列并触发初始门铃，门铃的 qid 使用 qid * 2 标识接收队列（发送队列为 qid * 2 + 1）
    async def init_rxq(self):
        qid = 0
        for rxq in self._rxq:
            await rxq.init_rxq() # 初始化每个接收队列
            await self._db_ring.put(qid*2)  # 触发门铃（偶数qid表示rxq）
            qid = qid + 1

    #持续轮询所有发送队列，模拟硬件的数据搬运过程
    async def _tx_datamove(self):
        while True:
            for txq in self._txq:
                await txq.move_data()  # 遍历所有发送队列，模拟数据传输
            await Timer(4, "ns")  # 固定间隔检查

    #模拟接收端处理数据并反馈新数据
    async def recv(self, qid):
        _q = self._rxq[qid]  # 获取指定接收队列
        ndesc = random.randint(1, 16)  # 随机生成待处理数据量
        for _ in range(ndesc):
            await _q.move_data()  # 模拟数据处理延迟
        descs = _q.gen_pkt(ndesc) #生成新数据
        await _q.put_pkt(descs) # 填充到队列
        await self._db_ring.put(qid*2) # 触发门铃（偶数qid表示rxq）
        print("rxq_qid = ",(qid*2))

    #向指定队列（发送或接收）填充数据，并通知调度器
    async def put_desc(self, qid, is_txq):
        _q =  self._txq[qid] if is_txq else self._rxq[qid] # 选择队列
        descs = _q.gen_pkt() # 生成随机数据
        await _q.put_pkt(descs) # 填充队列
        await self._db_ring.put(qid*2+is_txq)# 触发门铃（+1表示txq）

    async def get_desc(self, qid, is_txq):
        _q =  self._txq[qid] if is_txq else self._rxq[qid]
        return await _q.get_desc()
    
    #判断发送队列是否已完成所有数据传输
    def txq_is_done(self, qid):
        _q = self._txq[qid]
        return _q.is_done()

class TB(object):
    def __init__(self, dut, qsize=1):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.qsize = qsize
        print("qsize = ",(qsize))
        self.beqbhv = BeqBehavior(self.qsize)

        self.doorbellDrv = DoorbellSource(DoorbellBus.from_prefix(dut, "doorbell"), dut.clk, dut.rst)

        self.notifyReqMon = NotifyReqSink(NotifyReqBus.from_prefix(dut, "notify_req"), dut.clk, dut.rst)
        self.notifyReqMon.queue_occupancy_limit = 2

        self.notifyRspDrv = NotifyRspSource(NotifyRspBus.from_prefix(dut, "notify_rsp"), dut.clk, dut.rst)
        cocotb.start_soon(self._doorbellThd())
        cocotb.start_soon(self._notifyReqThd())
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

    async def cycle_reset(self):
        self.dut.hot_weight.value = 5
        self.dut.cold_weight.value = 2
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    async def _doorbellThd(self):
        while True:
            qid = await self.beqbhv._db_ring.get() #从db_ff获取qid
            db = self.doorbellDrv._transaction_obj()
            db.qid = qid
            await self.doorbellDrv.send(db)  #发送door_bell给DUT

    async def _notifyReqThd(self):
        while True:
            notifyReq = await self.notifyReqMon.recv()  #接受DUT发出的req
            qid = int(notifyReq.qid)
            done, cold = await self.beqbhv.get_desc(qid//2, qid%2)
            # 构造响应
            notifyRsp = self.notifyRspDrv._transaction_obj()
            notifyRsp.data = NotifyRsp(qid=notifyReq.qid, done=done, cold=cold).pack()
            await self.notifyRspDrv.send(notifyRsp)

    async def txq_thd(self, qid, max_seq = 10):
        for i in range(max_seq):
            print("txq qid", qid, "sub seq", i)
            await self.beqbhv.put_desc(qid, True)  # 向发送队列填充数据
            if random.randint(1, 100) < 5: # 5%概率等待队列空
                while not self.beqbhv.txq_is_done(qid):
                    await Timer(10, "ns")

    async def rxq_thd(self, max_seq = 10):
        for i in range(max_seq*self.qsize):
            print("rxq seq", i)
            await self.beqbhv.recv(random.randint(0, self.qsize-1))  # 随机选择队列
            if random.randint(1, 100) < 15:
                await Timer(random.randint(1,10), "ns")
            elif random.randint(1, 100) < 3:
                await Timer(random.randint(10,100), "ns")

    def set_idle_generator(self, generator=None):   
        if generator:
            self.doorbellDrv.set_pause_generator(generator()) # 设置门铃驱动的空闲间隔
            self.notifyRspDrv.set_pause_generator(generator())  # 设置响应驱动的空闲间隔

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.notifyReqMon.set_pause_generator(generator())  # 设置请求监视器的背压间隔

async def run_test(dut, idle_inserter, backpressure_inserter):
    qsize = 64
    max_seq = 10000
    tb = TB(dut, qsize=qsize)
    tb.set_idle_generator(idle_inserter)# 配置空闲生成器
    tb.set_backpressure_generator(backpressure_inserter)  # 配置背压生成器

    await tb.cycle_reset() # 复位DUT
    # waiting for init
    await Timer(1000, "ns")
    await tb.beqbhv.init_rxq()# 初始化接收队列

    #启动发送和接收协程
    rxq_cr =  cocotb.start_soon(tb.rxq_thd(max_seq))
    txq_cr = [cocotb.start_soon(tb.txq_thd(qid, max_seq)) for qid in range(tb.qsize) ]

     # 等待所有协程完成
    await rxq_cr.join()
    for cr in txq_cr:
        await cr.join()

    await Timer(10000, "ns")
    tb.notifyReqMon.set_pause_generator(None)  
    tb.notifyReqMon.pause = True 
    await Timer(5000, "ns")
    print("usedw = ",int(dut.u_beq_rr_sch.u_cold_ff.usedw.value))
    assert dut.u_beq_rr_sch.u_cold_ff.usedw.value == qsize

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
