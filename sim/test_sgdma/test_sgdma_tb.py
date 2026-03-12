#!/usr/bin/env python3
################################################################################
#  文件名称 : test_sgdma_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/09/24
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  09/24     Joe Jiang   初始化版本
################################################################################
# python的原生库
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator
# cocotb核心库
import cocotb
from cocotb.log import SimLog,  SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory


sys.path.append('../common')
from bus.tlp_adap_dma_bus import DmaWriteBus, DmaReadBus
from bus.beq_data_bus import BeqBus
from drivers.beq_data_bus import BeqTxqMaster
from monitors.tlp_adap_dma_bus import DmaRam
from monitors.beq_data_bus import BeqRxqSlave
from sparse_memory import SparseMemory                           # 稀疏内存
from enum import Enum, unique
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster

@unique # 确保枚举值唯一 防止冲突
class SgdmaType(Enum):
    ReadHostAddress     = 1
    WriteHostAddress    = 2

@unique
class SgdmaErrorBits(Enum):
    ErrorBit        = 0x80
    ErrorOnWrite    = 0x40 #分类错误标志，前面信号置位了会检查这一位，这一位为1代表错误在写主机过程中

#todo:SgdmaErrorType
@unique
class SgdmaErrorType(Enum):
    UR          = 0 # 未定义请求
    CA          = 1 # 中止
    CRS         = 2 # 配置请求
    Poison      = 3 # 数据错误
    Timeout     = 4 # 超时
    LinkDown    = 5 # 链路断开


class BeqUser0WithSgdma(Packet): # 将结构化的数据包对象转换整数类型的二进制数据
    name = 'beq_user0_with_sgdma'
    fields_desc = [
        BitField("rd_rsp_err", 0,   1 ), # 中间是字段的默认值
        BitField("write_flag", 0,   1 ),
        BitField("rsv0",       0,   6 ),
        BitField("cookie",     0,   16),
        BitField("bdf",        0,   16)
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8 # 判断最少需要补多少位才能让在这个user0为8的整数倍
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc #加在字段表的最前面
    width += padding_size

    def pack(self): # 将结构化的数据包对象转换为整数类型的二进制数据
        # build负责把数据包的字段值拼接成二进制字节串
        # from_bytes将二进制字节串，转换为一个十进制整数
        return int.from_bytes(self.build(), byteorder="big")

    def unpack(self, data):
        #assert type(data) == cocotb.binary.BinaryValue
        # to_bytes(长度，byteorder) 长度单位是字节
        return BeqUser0WithSgdma(data.to_bytes(BeqUser0WithSgdma.width//8, byteorder='big'))

class BeqUser1WithSgdma(Packet):
    name = 'beq_user1_with_sgdma'
    fields_desc = [
        BitField("addr",   0,  64)
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
        # cocotb.binary.BinaryValue表示核心二进制数据类型
        assert type(data) == cocotb.binary.BinaryValue
        # buff是上面类型内置的核心属性 自动按照硬件的位宽对齐 自动大端序
        return BeqUser1WithSgdma(data.buff)

class SgdmaHeader(Packet):
    name = 'sgdma_header'
    fields_desc = [
        BitField("rsv1",   0,  400),
        BitField("length",   0,  16),
        BitField("addr",   0,  64),
        BitField("bdf",   0,  16),
        BitField("rsv0",   0,  8),
        BitField("type",   0,  8)
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
        return SgdmaHeader(data.buff)

#理解为存根 
class SgdmaReqCmd(NamedTuple):
    hdr: SgdmaHeader
    qid: int
    cookie: int
    event: Event
    illegal_err: int # 预期错误标志 如果你故意发了一个错地址，这里记为1
# BEQ-SGDMA
class SgdmaReq(NamedTuple): # 没有的信号都是由driver自己生成的
    qid: int
    data: bytearray         # 包含Header+Payload
    user0: int
    cmd: SgdmaReqCmd

LEGAL_ADDRESS = 2**32
ILLEGAL_ADDRESS = 2**64
ILLEGAL_ADDRESS_RANGE = ILLEGAL_ADDRESS - LEGAL_ADDRESS

# 将每一个字节转换成两个16进制符 同时将结果转换为字符串
def bytes_to_hex(byte_data):
    import binascii
    return binascii.hexlify(byte_data).decode('ascii')
class Sgdma:
    def __init__(self, dut, mem):
        # 模拟主机内存
        self.dmaMem = DmaRam(DmaWriteBus.from_prefix(dut, "dma"), DmaReadBus.from_prefix(dut, "dma"), dut.clk, dut.rst, mem=mem)
        
        self.beq_txq = BeqTxqMaster(BeqBus.from_prefix(dut, "beq2sgdma"), dut.clk, dut.rst)
        self.beq_rxq = BeqRxqSlave( BeqBus.from_prefix(dut, "sgdma2beq"), dut.clk, dut.rst)
        self.regconfigmaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)
        self.cmd_queue = Queue(maxsize=64)
        self.resp_queue = Queue(maxsize=64)
        self._process_req_cr = cocotb.start_soon(self._process_req())
        self._process_resp_cr = cocotb.start_soon(self._process_resp())

    async def read(self, addr, length, bdf=0x1234, event=None):
        illegal_addr_err = 1 if addr < 0 or addr > (LEGAL_ADDRESS - 1) else 0
        hdr = SgdmaHeader(type=SgdmaType["ReadHostAddress"].value, addr=addr, length=length, bdf=bdf)
        qid = random.randint(0, 255)
        cookie = random.randint(0, 65536-1)
        user0 = BeqUser0WithSgdma(cookie=cookie).pack()
        cmd = SgdmaReqCmd(hdr, qid, cookie, event, illegal_addr_err)
        req = SgdmaReq(qid, hdr.build()[::-1], user0, cmd) 
        
        if event == None:
            event = Event()                    
            await self.cmd_queue.put(req)      
            await event.wait()                 
            return event.data                  
        else:
            await self.cmd_queue.put(req)

    async def write(self, addr, data, bdf=0x1234, event=None):
        if not isinstance(data, bytes):
            raise ValueError("Expected bytes or bytearray for data")
        length = len(data)
        hdr = SgdmaHeader(type=SgdmaType["WriteHostAddress"].value, addr=addr, length=length, bdf=bdf)
        
        wr_req = b'' + hdr.build()[::-1] + data
        qid = random.randint(0, 255)
        cookie = random.randint(0, 65536-1)
        user0 = BeqUser0WithSgdma(cookie=cookie).pack()
        cmd = SgdmaReqCmd(hdr, qid, cookie, event, 0)
        req = SgdmaReq(qid, wr_req, user0, cmd)
        if event == None:
            event = Event()            
            await self.cmd_queue.put(req)
            await event.wait()
            return event.data
        else:
            await self.cmd_queue.put(req)

    async def _process_req(self):
        while True:
            # 调用read/write 就会产生req并且塞入cmd_queue
            # 从里面取出req
            req = await self.cmd_queue.get() 
            await self.beq_txq.send(req.qid, req.data, req.user0)
            await self.resp_queue.put(req.cmd) # 将存根塞入resp_queue


    async def _process_resp(self):
        while True:
            rsp_cmd = await self.resp_queue.get()
            rsp = await self.beq_rxq.recv()
            if rsp.qid != rsp_cmd.qid:
                raise ValueError("mismatch: qid")
            beq_user0 = BeqUser0WithSgdma().unpack(rsp.user0)
            if beq_user0.cookie != rsp_cmd.cookie:
                raise ValueError("mismatch: cookie")
            if beq_user0.rd_rsp_err != rsp_cmd.illegal_err:
                raise ValueError("mismatch: illegal_err")
            rsp_hdr = SgdmaHeader(rsp.data[0:64][::-1])
            if rsp_hdr.length != rsp_cmd.hdr.length:
                raise ValueError("mismatch: hdr length")
            if rsp_hdr.addr != rsp_cmd.hdr.addr:
                raise ValueError("mismatch: hdr addr")
            if rsp_cmd.hdr.type == SgdmaType["WriteHostAddress"].value:
                if beq_user0.write_flag != 1:
                    raise ValueError("mismatch: write_flag")
            if rsp_cmd.hdr.type == SgdmaType["ReadHostAddress"].value:
                if len(rsp.data[64:]) != rsp_cmd.hdr.length:
                    raise ValueError("mismatch: length")
                rsp_cmd.event.set(rsp.data[64:])
            else:
                rsp_cmd.event.set(None)

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.test_done = Event() # 创建一个测试完成的event 全局标志

        self.log = SimLog("cocotb.tb")  # 初始化 cocotb 的内置日志对象
        self.log.setLevel(logging.INFO) # 设置日志级别为 INFO
        # 启动后台协程跑时钟 不启动这个硬件内部的状态机就不会随时间跳变
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        self.mem = SparseMemory(LEGAL_ADDRESS)          # 稀疏存储器
        self.sgdma = Sgdma(dut, self.mem)               # 硬件接口和软件模型连接起来
        self.dfx_reg_queue = Queue(maxsize=1)           # 长度为1的队列 用于DFX校验的同步 
        self.reg_rd_queue_rsp =  Queue(maxsize=1)       # 专门用于配置寄存器读取的返回
    
    # 寄存器写请求 向指定地址写数据 true标识需要等待响应 配置
    async def reg_wr_req(self, addr,data):
        await self.sgdma.regconfigmaster.write(addr,data,True)
    # 寄存器读请求  监控
    # 读请求的发起和读结果的使用往往在不同的协程或逻辑段落 
    # 通过 Queue，你可以确保读回来的数据不会跟其他异步任务混淆
    # DFX是整场测试最后异步 不需要同时发送很多请求
    async def reg_rd_req(self, addr):
        addr = addr
        rddata = await self.sgdma.regconfigmaster.read(addr)
        await self.reg_rd_queue_rsp.put(rddata)

    # 复位
    async def cycle_reset(self):
        self.dut.rst.setimmediatevalue(0)  # 仿真开始一瞬间设置rst为0
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
            self.sgdma.beq_txq.set_idle_generator(generator) # 在BEQ发送给SGDMA的指令通道上注入空闲
            self.sgdma.dmaMem.set_idle_generator(generator)  # 在内存模型返回数据的通道上注入空闲
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.sgdma.beq_rxq.set_backpressure_generator(generator) # 在SGDMA返回响应给BEQ的通道上注入反压
            self.sgdma.dmaMem.set_backpressure_generator(generator)  # 在SGDMA写数据到内存的通道上注入反压

async def run_test_sgdma(dut, idle_inserter, backpressure_inserter, fifo_pfull_mode):
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    
    await tb.cycle_reset() # 等待复位完成

    outstanding = 32        # 在途任务数 
    addr_slice = LEGAL_ADDRESS//outstanding # 内存拆分
    
    async def read_dfx_reg(max_seq, outstanding):
        

        addr0 = 0x500000                    # 全局错误状态寄存器
        await tb.reg_rd_req(addr = addr0)
        rdata0 = await tb.reg_rd_queue_rsp.get()
        rdata0 = int(rdata0)
        tb.log.info("dfx 0x500000 : {}".format(rdata0))
        if rdata0 > 0 :
            assert False, " There are some DFX errors in module."
            tb.log.info("There are some DFX errors in module err is {}, ".format(rdata0))
        addr2 = 0x500200                    # 读写请求响应数量
        await tb.reg_rd_req(addr = addr2)
        rdata2 = await tb.reg_rd_queue_rsp.get()
        addr3 = 0x500208                    # BEQ/SGDMA
        await tb.reg_rd_req(addr = addr3)
        rdata3 = await tb.reg_rd_queue_rsp.get()
        wrreq_cnt = rdata2 & 0xFF           
        wrrsp_cnt = (rdata2 >> 8) & 0xFF
        rdreq_cnt = (rdata2 >> 16) & 0xFF
        rdrsp_cnt = (rdata2 >> 24) & 0xFF

        beq_cnt   = rdata3 & 0xFF           # BEQ处理的包数
        sgdma_cnt = (rdata3 >> 8) & 0xFF    # SGDMA处理的包数
        tb.log.info("dfx 0x500200 : 0x{:x}".format(int(rdata2)))
        tb.log.info("dfx 0x500208 : 0x{:x}".format(int(rdata3)))
        if wrreq_cnt != wrrsp_cnt or rdreq_cnt !=  rdrsp_cnt or beq_cnt !=  sgdma_cnt:
            assert False, " There are some DFX cnt are not equal."
            tb.log.info("There are some DFX cnt are not equal wrreq_cnt cnt  is {}, wrrsp_cnt cnt is {} ,{}, {}, {},{}".format(wrreq_cnt, wrrsp_cnt, rdreq_cnt, rdrsp_cnt, beq_cnt, sgdma_cnt))
        # max_seq是总循环次数 out是每轮并发数 确保读写请求能够处理理论上硬件应该处理的总请求数
        # 每一轮跑三种：_process_write & _process_read _process_illegal_read _process_in_flight_write & _process_in_flight_read
        if wrreq_cnt == (max_seq*outstanding*3) % 256 or rdreq_cnt == (max_seq*outstanding*3) % 256:
            pass
        else:
            tb.log.info("DFX wrreq_cnt {} is not equal to rdreq_cnt {} {}".format(wrreq_cnt, rdreq_cnt, ((max_seq*outstanding*3) % 256)))
            assert False, " DFX event_cnt is not equal."
            
        await Timer(500, 'ns')
        await tb.dfx_reg_queue.put(1) # 1是占位符
    # 测试SGDMA在FIFO pfull条件下情况
    async def rd_rsp_fifo_pfull_process():
        tb.dut.u_sgdma.rd_rsp_ff_rdy.value = 1 # 这个信号表示BEQ是否准备好接收数据
        while True:
            if fifo_pfull_mode:
                tb.dut.u_sgdma.rd_rsp_ff_rdy.value = 0
                await Timer(50000, 'ns')
                tb.dut.u_sgdma.rd_rsp_ff_rdy.value = 1
                await Timer(50000, 'ns')
                if tb.test_done.is_set(): # 主测试函数run_test_sgdma最末尾拉起
                    break
            else:
                break
    # rd_rsp_fifo_pfull_process是一个后台进程 和主测试逻辑一起跑
    match_fifo_pfull_cr = cocotb.start_soon(rd_rsp_fifo_pfull_process())
    max_seq = 10 # 测试的循环次数

    for i in range(max_seq):
        print("sequence {}".format(i))
        # 随机化长度：生成 outstanding (32) 个 1~4096 字节之间的随机长度
        length = [random.randint(1, 4096) for _ in range(outstanding)]
        # 生成随机数据：根据上面的长度，产生对应的随机字节流
        test_data = [random.randbytes(length[idx]) for idx in range(outstanding)]
        # 计算合法基地址：利用之前算的 addr_slice，确保 32 个任务的地址空间互不重叠
        base_addr = [random.randint(idx*addr_slice, (idx+1)*addr_slice-1) for idx in range(outstanding)]
        # 计算非法地址：生成超出 LEGAL_ADDRESS 范围的地址，用来测试硬件的错误拦截
        illegal_addr = [random.randint(LEGAL_ADDRESS + idx * ((ILLEGAL_ADDRESS_RANGE)//outstanding), LEGAL_ADDRESS + (idx+1) * (ILLEGAL_ADDRESS_RANGE//outstanding) - 1) for idx in range(outstanding)]
        # 创建 64 个 Event（32个用于写完成，32个用于读完成）
        events = [Event() for _ in range(outstanding*2)]

        async def _process_write():
            for j in range(outstanding):
                # 写操作确认后 底层驱动会调用events[j].set()
                await tb.sgdma.write(addr=base_addr[j], data=test_data[j], event=events[j])

        async def _process_read():
            for j in range(outstanding): 
                # 等待第 j 个写任务完成后，再发起第 j 个读任务
                await events[j].wait()
                data = await tb.sgdma.read(addr=base_addr[j], length=len(test_data[j]), event=events[outstanding+j])

        cocotb.start_soon(_process_read())
        cocotb.start_soon(_process_write())
        

        for j in range(outstanding): 
            # 获取第j个读任务对应的event
            event = events[outstanding+j]
            # 阻塞等待硬件返回读结果
            await event.wait()
            assert event.data == test_data[j]

        illegal_events = [Event() for _ in range(outstanding)]
        async def _process_illegal_read():
            for j in range(outstanding):
                data1 = await tb.sgdma.read(addr=illegal_addr[j], length=length[j], event=illegal_events[j])

        cocotb.start_soon(_process_illegal_read())

        for k in range(outstanding): 
            illegal_event = illegal_events[k]
            await illegal_event.wait()
            # 地址非法，硬件不应返回真实内存数据，而应返回全0
            # length是字节数
            assert illegal_event.data == b'\x00'*length[k]

    for i in range(max_seq):
        print("second sequence {}".format(i))
        tb.log.info(f"Sequence {i}: Start in-flight test (32x4096 bytes write -> read)")
        
        valid_pairs = [
            (4096, 4096),  
            (4095, 1), (4095, 2),  # sum=4096/4097
            (4094, 2), (4094, 4),  # sum=4096/4098
            (4092, 2), (4092, 1),  # sum=4094/4093
            (4091, 5), (4090, 5),  # sum=4096/4095
            (4093, 9), (4093, 3),  
        ]
        # 两个两个抽可以保证任务1的起始地址可能刚好是任务0的结束地址
        in_flight_len = [] # 创建一个空列表
        pair_num = outstanding // 2 # 抽取valid_pairs的次数
        remainder = outstanding % 2 # 计算余数

        for _ in range(pair_num):
            chosen_pair = random.choice(valid_pairs)  # 随机抽元组
            in_flight_len.extend(chosen_pair)         # 将两个长度展开放在列表中，循环完了后有32个值

        if remainder:                                 
            in_flight_len.append(4096)                # 如果outstanding是奇数 列表加一个
        # 返回一个介于AB中间的随机整数
        in_flight_base_addr = [
            random.randint(idx*addr_slice, (idx+1)*addr_slice - in_flight_len[idx]) 
            for idx in range(outstanding)
        ]

        in_flight_test_data = [random.randbytes(l) for l in in_flight_len]
        in_flight_write_events = [Event() for _ in range(outstanding)]
        in_flight_read_events = [Event() for _ in range(outstanding)]

        #in_flight_len = 4096
        #in_flight_base_addr = [random.randint(idx*addr_slice, (idx+1)*addr_slice-1) for idx in range(outstanding)]
        #in_flight_test_data = [random.randbytes(in_flight_len) for _ in range(outstanding)]
        #in_flight_write_events = [Event() for _ in range(outstanding)]
        #in_flight_read_events = [Event() for _ in range(outstanding)]

        # 不等响应 连续发送
        async def _process_in_flight_write():
            for j in range(outstanding):
                await tb.sgdma.write(
                    addr=in_flight_base_addr[j],
                    data=in_flight_test_data[j],
                    event=in_flight_write_events[j]
                )
            tb.log.info(f"Sequence {i}: All 32 write requests  completed")

        async def _process_in_flight_read():
            for j in range(outstanding):
                await in_flight_write_events[j].wait()
            tb.log.info(f"Sequence {i}: Start reading 32x4096 bytes data")
            
            for j in range(outstanding):
                data = await tb.sgdma.read(
                    addr=in_flight_base_addr[j],
                    length=in_flight_len[j],
                    event=in_flight_read_events[j]
                )

        write_task = cocotb.start_soon(_process_in_flight_write())
        await write_task 
        await Timer(5000, 'ns')
        read_task = cocotb.start_soon(_process_in_flight_read())
        
        for j in range(outstanding):
            await in_flight_read_events[j].wait()
            assert in_flight_read_events[j].data == in_flight_test_data[j], \
                f"Sequence {i}, in-flight read {j} data mismatch! Expected {len(in_flight_test_data[j])} bytes, got {len(in_flight_read_events[j].data)} bytes"
        tb.log.info(f"Sequence {i}: In-flight test (split len pairs) passed")
    
    for i in range(max_seq):
        print("second sequence {}".format(i))
        tb.log.info(f"Sequence {i}: Start write-only small packet test (length < 32 bytes)")

        small_pkt_len = [random.randint(1, 31) for _ in range(outstanding)]
        small_pkt_test_data = [random.randbytes(small_pkt_len[idx]) for idx in range(outstanding)]
        small_pkt_base_addr = [random.randint(idx*addr_slice, (idx+1)*addr_slice-1) for idx in range(outstanding)]
        small_pkt_write_events = [Event() for _ in range(outstanding)]

        async def _process_write_only_small():
            for j in range(outstanding):
                await tb.sgdma.write(
                    addr=small_pkt_base_addr[j],
                    data=small_pkt_test_data[j],
                    event=small_pkt_write_events[j]
                )
            tb.log.info(f"Sequence {i}: All {outstanding} small packet write requests (length <32) completed")

        write_small_pkt_task = cocotb.start_soon(_process_write_only_small())

        for j in range(outstanding):
            event = small_pkt_write_events[j]
            await event.wait() # 处理完第j个任务且响应才会到下一行
            # debug级别允许你在需要精确定位波形图上的某一个地址时才开启
            tb.log.debug(f"Sequence {i}, small packet write {j} completed: len={small_pkt_len[j]} bytes, addr=0x{small_pkt_base_addr[j]:x}")

        tb.log.info(f"Sequence {i}: Write-only small packet test (length <32 bytes) passed")

    await Timer(500, 'ns')
    read_dfx_reg_cr = cocotb.start_soon( read_dfx_reg(max_seq, outstanding))
    # 确保在宣告测试结束之前，所有的硬件内部状态已经经过了最终检查
    dfx_reg_flag0   = await tb.dfx_reg_queue.get()
    tb.test_done.set()
    await Timer(50000, 'ns')

# 随机的有效信号发生器    
def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)] # 前300为1 后700为0
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)] # +100个1
    return itertools.cycle(seed)

if cocotb.SIM_NAME: # 确保这段代码只有在真正的仿真器启动时才运行

    for test in [run_test_sgdma]:

        factory = TestFactory(test)                                     # 初始化一个工厂对象。它的核心功能是参数扫描
        factory.add_option("idle_inserter", [None, cycle_pause])        # 
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.add_option("fifo_pfull_mode", [True, False])
        factory.generate_tests() # 根据上面的选项计算笛卡尔积 它会自动生成8个独立的测试用例

root_logger = logging.getLogger() # 获取全局的日志管理器
file_handler = RotatingFileHandler("rotating.log", mode="w") # 创建一个滚动日志处理器 w表示每次运行仿真时重新创建
file_handler.setFormatter(SimLogFormatter()) # 设置格式  每一行日志前面加上仿真时间戳
root_logger.addHandler(file_handler) # 将这个文件处理器挂载到系统上 代码里写的都会被同步记录到rotating.log