import sys
import time
import random

from types import SimpleNamespace
from typing import List, Dict, Tuple

import logging
from logging import Logger
from logging.handlers import RotatingFileHandler


import cocotb
from cocotb.queue import Queue
from cocotb.log import SimLog, SimLogFormatter
from cocotb.handle import HierarchyObject
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.regression import TestFactory


sys.path.append('../../common')
from address_space import Pool, MemoryRegion
from bus.tlp_adap_dma_bus import DmaWriteBus, DmaReadBus
from generate_eth_pkg import generate_eth_pkt

from test_cfg import *
from test_func import cycle_pause, ResourceAllocator, randbit
from test_define import *
from test_interfaces import *
from ram_tbl import RamTblTransaction


class TB(object): # 括号内表示继承了python的基类object
    def __init__(self, cfg: Cfg, dut: HierarchyObject, qid_list: List[int]):
        self.dut: HierarchyObject = dut # self.dut表示实例变量 可以理解为TB对象内部开辟了一块空间来永久存储参数dut
        self.cfg: Cfg = cfg
        self.qid_list: List[int] = qid_list
        # 这段代码执行后 程序会立即往下执行，不会卡在这里等时钟结束
        cocotb.start_soon(Clock(dut.clk, CLOCK_FREQ, units="ns").start()) # start是Clock的一个方法，生成协程
        # 下划线表示这是一个受保护的方法 
        self._init_mem()
        self._log_init()
        self._init_interfaces()
        # 双下划线表示私有方法 在外部很难直接访问到
        cocotb.start_soon(self.__netrx_info_process())
        cocotb.start_soon(self.__slot_req_process())
        cocotb.start_soon(self.__slot_rsp_process())
        cocotb.start_soon(self.__netrx_desc_rsp_process())
        cocotb.start_soon(self.__rd_data_req_process())
        cocotb.start_soon(self.__rd_data_rsp_process())
        # 调用一个用async def定义的函数时，self.__netrx_info_process()，函数体内的代码不会立即执行。相反，Python会自动创建一个协程对象并返回给你。

    def _log_init(self) -> None: # 表示这个函数没有返回值
        self.log: Logger = logging.getLogger("cocotb.tb") # 将获取到的 Logger 对象赋值给实例变量
        self.log.setLevel(LOG_LEVEL) # 设置日志的级别
    # 实例化并连接所有的总线接口驱动（Drivers）、监视器（Monitors）和模型（Models）
    def _init_interfaces(self) -> None:
        dut = self.dut                                      # 把实例对象赋值给局部变量
        clk = self.dut.clk                                  # 把实例对象的clk属性赋值给局部变量
        rst = self.dut.rst                                  # 把实例对象的rst属性赋值给局部变量
        self.interfaces: Interfaces = Interfaces()          # 创建一个容器对象来存放所有的接口
        # 驱动线只知道要发数据但是不知道发给谁 也不知道具体信号线的名字 
        self.interfaces.netrx_info_if = NetrxInfoSource(NetrxInfoBus.from_prefix(dut, "netrx_info"), clk, rst)
        self.interfaces.netrx_alloc_slot_req_if = SlotReqSink(SlotReqBus.from_prefix(dut, "netrx_alloc_slot_req"), clk, rst)
        self.interfaces.netrx_alloc_slot_rsp_if = SlotRspSource(SlotRspBus.from_prefix(dut, "netrx_alloc_slot_rsp"), clk, rst)
        self.interfaces.slot_ctrl_dev_id_if = SlotCtrlDevIdTbl(
            SlotCtrlDevIdReqBus.from_prefix(dut, "slot_ctrl_dev_id_rd"), SlotCtrlDevIdRspBus.from_prefix(dut, "slot_ctrl_dev_id_rd"), None, clk, rst
        ) # 这里的None表示没有写请求总线 因为DUT是发起者
        self.interfaces.slot_ctrl_dev_id_if.set_callback(self.__slot_ctrl_dev_id_cb) # 注册一个回调函数当DUT发起读请求时，这个Python函数会被自动调用，其返回值会被作为读响应数据发回给DUT

        self.interfaces.netrx_desc_rsp_if = NetrxDescSource(NetrxDescBus.from_prefix(dut, "netrx_desc_rsp"), clk, rst)
        self.interfaces.rd_data_req_if = RdDataReqSink(RdDataReqBus.from_prefix(dut, "rd_data_req"), clk, rst)
        self.interfaces.rd_data_rsp_if = RdDataRspSource(RdDataRspBus.from_prefix(dut, "rd_data_rsp"), dut.clk, dut.rst)
        self.interfaces.wr_data_ctx_if = WrDataCtxTbl(WrDataCtxReqBus.from_prefix(dut, "wr_data_ctx_rd"), WrDataCtxRspBus.from_prefix(dut, "wr_data_ctx_rd"), None, clk, rst)
        self.interfaces.wr_data_ctx_if.set_callback(self.__wr_data_ctx_cb)

        self.interfaces.used_info_if = UsedInfoSink(UsedInfoBus.from_prefix(dut, "used_info"), clk, rst)
        # mem将dma接口绑定到了TB内存维护的大内存池上
        self.interfaces.dma_if = DmaRam(DmaWriteBus.from_prefix(dut, "dma"), None, clk, rst, mem=self.mem)
    # 初始化仿真环境所需的各种数据结构、内存模型和状态追踪器
    def _init_mem(self) -> None:
        self.virtio_head_len: int = 12
        self.pass_num = 0               # 成功接收的包数量
        self.drop_num = 0               # 丢弃的包数量
        # None表示这是顶层内存池，没有父内存池
        # 第二个0表示没有初始偏移地址地址从0开始分配
        # size表示这个内存池的总大小  min_alloc表示最小分配单元也就是64字节
        self.mem: Pool = Pool(None, 0, size=2**64, min_alloc=64)    # 模拟主机的物理内存

        self.rx_buf_ram_depth: int = self.cfg.pkt_id_num * 4 * 32
        self.pkt_id_ram = ResourceAllocator(0, self.cfg.pkt_id_num - 1) # 生成pkt_id的分配器
        self.dev_id_ram: Dict[int, int] = {} # self.dev_id_ram[0] = 0 里面是qid外面是dev_id
        self.bdf_ram: Dict[int, int] = {}    # int和int表示key和value都是int
        
        # Queue是cocotb提供的一个异步队列 用于在协程之间传递数据             
        # 一个协程可以往里面写数据 另一个协程可以往里面取数据 队列空了取数据的协程会被挂起等待数据到来    
        # List是python内置的列表类型 支持随机访问 读取不删除元素 
        # 包括pkt和元数据       
        self.rx_buf_ram: Dict[int, Queue] = {}          # 生成了pkt之后会将其放在这里 通知进程会取出数据包通知DUT             
        # 包含数据、元数据、接收标志和丢弃标志
        self.info_out_ram: Dict[int, List] = {}         # 读请求的时候需要给ram一个pktid，TB需要在这个列表查找对应的包并且进行标记 包响应过程就是判断列表里头部的包是否被标记从而发送给DUT并且从列表里面移除           
        # 包括pkt和元数据  
        self.info_out_queue: Dict[int, Queue] = {}      # 当DUT申请槽位时TB会从这个队列里面取出最早的一个消息将其pkt_id给slot响应   
        # 包括pkt和元数据  
        self.desc_rsp_queues: Dict[int, Queue] = {}     # 存放已经完成slot分配并且TB已经把desc发送给DUT的包  当DUT准备写数据前查询上下文时，TB从这里取出包信息    
        # 包括pkt和元数据  
        self.wr_data_ctx_queues: Dict[int, Queue] = {}

        self.slot_req_queue: Queue = Queue(32)          # 缓冲DUT发来的slot申请请求 防止TB处理不过来时无限堆积 实现接收请求和处理请求的解耦  32表示队列深度 队列超过32个则阻塞DUT
        # Dict用字典进行隔离 表示不同队列的处理进度互不影响
        self.slot_rsp_queue: Dict[int, Queue] = {}      # solt分配成功后会把包的原始数据还有元信息放入这个队列 desc_rsp会从这个里面取出包 取申请内存地址生成描述符
        # 用全局的QUEUE充当总线仲裁器 谁先请求谁的QID先放入队列谁的数据就先发送给DUT 
        # qid
        self.rd_data_req_queue: Queue = Queue()         # 把需要发送数据的qid放入这个队列 读数据响应协程会监听，发现里面有谁就把对应数据发送给DUT
        self.slot_used_num: int = 0                     # 录当前TB已经分配出去、但还没回收的Slot数量
        self.mem_idx: Dict[int, ResourceAllocator] = {} # 可用环的索引 不同qid的可用环索引互不影响
        self.mem_addr: Dict[int, Dict[int, List]] = {}  # 第一层是qid 第二层是avail_id 表示把哪个地址分配给了哪个索引
        self.virtq_forced_shutdown: Dict[int, int] = {} 
        for qid in self.qid_list:
            self.dev_id_ram[qid] = qid
            self.bdf_ram[qid] = qid

            self.rx_buf_ram[qid] = Queue()
            self.info_out_ram[qid] = []
            self.info_out_queue[qid] = Queue(4)          
            self.slot_rsp_queue[qid] = Queue()
            self.desc_rsp_queues[qid] = Queue()
            self.wr_data_ctx_queues[qid] = Queue()

            self.mem_idx[qid] = ResourceAllocator(0, 2**16 - 1)
            self.mem_addr[qid] = {}
            self.virtq_forced_shutdown[qid] = 0

    async def cycle_reset(self) -> None:
        clk = self.dut.clk
        rst = self.dut.rst
        rst.setimmediatevalue(0)
        await RisingEdge(clk)
        await RisingEdge(clk)
        rst.value = 1
        await RisingEdge(clk)
        await Timer(1, "us")
        await RisingEdge(clk)
        rst.value = 0
        await RisingEdge(clk)
        await RisingEdge(clk)
        await Timer(2, "us")
    # 设置TB向DUT发送数据时的空闲 在发送数据的过程中插入随机的停顿 valid拉低
    # 四个事件的空闲时刻是各自随机的
    def set_idle_generator(self, generator=None) -> None:
        if generator:
            self.interfaces.netrx_info_if.set_idle_generator(generator)
            self.interfaces.netrx_alloc_slot_rsp_if.set_idle_generator(generator)
            self.interfaces.netrx_desc_rsp_if.set_idle_generator(generator)
            self.interfaces.rd_data_rsp_if.set_idle_generator(generator)

    # ready拉低
    def set_backpressure_generator(self, generator=None) -> None:
        if generator:
            self.interfaces.netrx_alloc_slot_req_if.set_backpressure_generator(generator)
            self.interfaces.rd_data_req_if.set_backpressure_generator(generator)
            self.interfaces.used_info_if.set_backpressure_generator(generator)

    # need pps or bps control
    async def _rx_buf_process(self, qid_list: List[int]) -> None:
        eth_pkt_len_min = 64    # 最小64字节
        eth_pkt_len_max = 1518  # 最大1518字节

        send_num = 0            # 用于记录已经成功生成并放入缓存队列的数据包数量  

        act_eth_pkt_len_min = max(self.cfg.eth_pkt_len_min, eth_pkt_len_min)
        act_eth_pkt_len_max = min(self.cfg.eth_pkt_len_max, eth_pkt_len_max)
        while send_num < self.cfg.seq_num:
            pkt_len = random.randint(act_eth_pkt_len_min, act_eth_pkt_len_max)
            eth_pkt = bytes([random.randint(0, 255) for _ in range(pkt_len + self.virtio_head_len)]) # bytes把随机数列表转换为字节串
            qid = random.choice(qid_list)   # 随机选一个qid
            info = SimpleNamespace()        # 创建一个简单的命名空间对象来存放元数据    
            if self.rx_buf_ram_depth >= pkt_len and self.pkt_id_ram.has_available_resources():
                pkt_id = self.pkt_id_ram.alloc_id()
                info.qid = qid
                info.pkt_id = pkt_id
                info.pkt_len = pkt_len
                self.rx_buf_ram[qid].put_nowait((eth_pkt, info))
                send_num += 1 # 成功放入队列后，已发送计数加 1

            sleep_time = (pkt_len + BUS_BYTE_WIDTH - 1) // BUS_BYTE_WIDTH # 模拟数据包在总线上传输需要的时间  向上取整
            await Timer(sleep_time * CLOCK_FREQ, "ns") # await Timer表示协程在这里暂停，等待指定的时间后再继续执行

    async def __netrx_info_process(self) -> None:
        qid_list: List[int] = self.qid_list

        qid_seq = 0                                         # 用于记录上一次处理的队列索引，用于控制轮询节奏
        while True:
            for i in range(len(qid_list)):
                if qid_seq == i:
                    await Timer(2 * CLOCK_FREQ, "ns")
                qid = qid_list[i]
                # 检查发包的缓存里面有没有数据 info_out_ram表示已经通知DUT但是DUT还没读走的数据 
                # 如果积压了4个包，TB就停止向该队列发送新通知
                while self.rx_buf_ram[qid].qsize() > 0 and len(self.info_out_ram[qid]) < 4:
                    eth_pkt, info = self.rx_buf_ram[qid].get_nowait()                       # 不消耗仿真时间 前面已经判断过queue里面有数据
                    trans = NetrxInfoTrans()                                                # 实例化一个接口事务对象
                    vq = VirtioVq(qid=qid, typ=TestType.NETRX).pack()
                    data = Netrx_Info_Data(
                        vq=vq,
                        pkt_id=info.pkt_id,
                    ).pack()
                    trans.data = data                                                       # 将打包好的数据填入事务
                    await self.interfaces.netrx_info_if.send(trans)                         # DUT的ready如果为低会阻塞等待
                    alloc_flag = 0                                                          # 未使用的标志位
                    recv_flag = 0                                                           # 标记DUT是否发起了读数据请求
                    drop_flag = 0                                                           # 标记DUT是否丢弃了该包
                    self.info_out_ram[qid].append([eth_pkt, info, recv_flag, drop_flag])    # rd_data_req_process会遍历这个列表根据pkt_id找到对应的包数据
                    self.info_out_queue[qid].put_nowait((eth_pkt, info))                    # 后续的slot_rsp_process会从这里按顺序取出包信息
                    qid_seq = i

    def __slot_ctrl_dev_id_cb(self, req_tran) -> RamTblTransaction:
        vq = VirtioVq.unpack(req_tran.req_qid) # req_qid是DUT发起读请求时传过来的数据
        if vq.typ != TestType.NETRX:
            raise Exception(f" slot_ctrl_dev_id_cb vq_typ is not netrx is {vq.typ}")
        rsp_trans = SlotCtrlDevIdRspTrans()
        rsp_trans.rsp_data = self.dev_id_ram[vq.qid]
        return rsp_trans # rsp_trans.rsp_data：这才是真正的dev_id数据

    async def __slot_req_process(self) -> None:
        # 这意味着它可以被挂起（await），让出 CPU 给其他协程运行，模拟硬件的并发行为
        while True:
            req_trans = await self.interfaces.netrx_alloc_slot_req_if.recv() # recv表示阻塞等待直到总线上出现一次有效的握手 成功才会返回
            await self.slot_req_queue.put(req_trans)                         # req_trans是请求端的数据

    async def __slot_rsp_process(self) -> None:
        while True:
            req_trans = await self.slot_req_queue.get()
            vq = VirtioVq.unpack(req_trans.data)
            qid = vq.qid
            # qid做了校验
            if vq.typ != TestType.NETRX:
                raise Exception(f"qid {qid} _slot_req_process vq_typ is not netrx")
            # CTX的dev_id和请求的dev_id做了校验
            if req_trans.dev_id != self.dev_id_ram[qid]:
                raise Exception(f"qid {qid} _slot_req_process dev_id err")

            eth_pkt, info = self.info_out_queue[qid].get_nowait()
            # 检验pkt_id
            if info.pkt_id != req_trans.pkt_id:
                raise Exception(f"qid {qid} _slot_req_process pkt_id err act {req_trans.pkt_id} exp {info.pkt_id}")
            rsp_trans = SlotRspTrans()
            data = Netrx_Alloc_Slot_Rsp_Data()
            data.qid = vq.pack()
            data.pkt_id = req_trans.pkt_id
            # 初始化默认响应状态
            data.ok = 1
            data.local_ring_empty = 0
            data.avail_ring_empty = randbit(1)
            data.q_stat_doing = 1
            data.q_stat_stopping = randbit(1)
            data.desc_engine_limit = randbit(1)
            data.err_info = randbit(8)
            # 根据配置随机生成错误响应
            # random.random()生成一个0到1之间的浮点数
            if random.random() <= self.cfg.alloc_slot_err:
                if random.randint(0, 1) == 0:
                    data.local_ring_empty = 1
                    data.q_stat_doing = randbit(1)
                else:
                    data.local_ring_empty = randbit(1)
                    data.q_stat_doing = 0

            rsp_trans.data = data.pack()
            info.slot_rsp_data = data       # 保存slot响应数据以备后续使用
            await self.interfaces.netrx_alloc_slot_rsp_if.send(rsp_trans)
            # Slot分配成功的唯一条件
            if data.local_ring_empty == 0 and data.q_stat_doing == 1:
                await self.slot_rsp_queue[qid].put((eth_pkt, info))

            # eth_pkt, info = self.info_out_queue[qid].get_nowait()
            # if info.pkt_id !=

            # self.slot_used_num -= 1

        pass

    async def __netrx_desc_rsp_process(self):
        while True:
            non_empty_deques = [dq for dq in self.slot_rsp_queue.values() if not dq.empty()]  # 只包含那些当前时刻有数据等待处理的队列对象
            if not non_empty_deques:
                await Timer(2 * CLOCK_FREQ, "ns")
                continue
            dq = random.choice(non_empty_deques)            # 从所有有数据的队列中随机选择一个
            eth_pkt, info = dq.get_nowait()
            vq = VirtioVq(qid=info.qid, typ=TestType.NETRX)
            qid = info.qid

            dev_id = self.dev_id_ram[qid]
            bdf = self.bdf_ram[qid]
            # avail_idx =
            # 模拟Driver将描述符放入Available Ring的行为
            info.avail_idx = self.mem_idx[qid].alloc_id()
            # 初始化错误信息
            info.err = ""
            info.fatal = 0
            info.err_code = VirtioErrCode.VIRTIO_ERR_CODE_NONE
            # 
            self.mem_addr[qid][info.avail_idx] = []

            desc_cnt = random.randint(self.cfg.min_desc_cnt, self.cfg.max_desc_cnt) # 这个包由几个描述符构成
            pkt_len = random.randint(info.pkt_len + self.virtio_head_len, 2 * (info.pkt_len + self.virtio_head_len)) # 定义Buffer长度=头+包长

            err_type = random.choices(
                population=list(err_type_list.keys()),
                weights=list(err_type_list.values()),  # type: ignore
                k=1,
            )[0] # 0表示字符串值
            info.forced_shutdown = 0
            info.err_code = VirtioErrCode.VIRTIO_ERR_CODE_NONE
            if err_type == "desc_len_err": # 接收缓冲区长度不足
                pkt_len = random.randint(desc_cnt, info.pkt_len + self.virtio_head_len - 1)
                info.err = "desc_len_err"
                info.fatal = 0 # 不是致命错误
                info.err_code = VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR
            elif err_type == "forced_shutdown":
                info.err = "forced_shutdown"
                info.forced_shutdown = randbit(1)
                if info.forced_shutdown:
                    desc_cnt = 1 # 模拟关闭时不再提供复杂的描述符链
            elif err_type == "desc_rsp_err": # 描述符响应错误
                info.err = "desc_rsp_err"
                info.fatal = 1
                info.err_code = randbit(7, False) # 生成一个非零的随机错误码

            info.ring_id = randbit(16) # 生成一个16位的随机整数
            desc_rsp_sbd = VirioRspSbd(
                vq=vq.pack(),                       # 将对象打包成整数从而传输
                dev_id=dev_id,
                pkt_id=info.pkt_id,
                total_buf_length=pkt_len,
                valid_desc_cnt=desc_cnt,
                ring_id=info.ring_id,
                avail_idx=info.avail_idx,
                forced_shutdown=info.forced_shutdown,
                err_info=info.err_code,
            )
            # 一个数据包里面有多个描述符
            for i in range(desc_cnt):
                if i != desc_cnt - 1:
                    desc_len = random.randint(1, pkt_len - (desc_cnt - 1 - i))  # each >= 1
                else:
                    desc_len = pkt_len

                mem = self.mem.alloc_region(desc_len, bdf, dev_id)

                flag_write = randbit(1)
                flag_indirect = randbit(1)
                flag_next = i != desc_cnt - 1
                next = randbit(16)
                len = desc_len
                addr = mem.get_absolute_address(0)
                # 实际在记账
                self.mem_addr[qid][info.avail_idx].append((mem, len)) # avail_idx可以理解为可用环的索引 在某一行存储了描述符索引需要存储的值
                sop = i == 0
                eop = i == desc_cnt - 1

                desc_rsp_data = VirioRspData(
                    next=next,
                    flag_indirect=flag_indirect,
                    flag_write=flag_write,
                    flag_next=flag_next,
                    len=len,
                    addr=addr,
                )

                rsp_trans = NetrxDescTrans(
                    sop=sop,
                    eop=eop,
                    data=desc_rsp_data.pack(),
                    sbd=desc_rsp_sbd.pack(),
                )
                await self.interfaces.netrx_desc_rsp_if.send(rsp_trans)
            # 一个描述包处理完之后 把包和元信息放入描述符响应队列 给CTX查询使用
            self.desc_rsp_queues[qid].put_nowait((eth_pkt, info))  

    async def __rd_data_req_process(self) -> None:
        while True:
            req_trans = await self.interfaces.rd_data_req_if.recv()
            rd_data_req = RdDataReq.unpack(req_trans.data)
            vq = VirtioVq.unpack(rd_data_req.vq)
            qid = vq.qid
            recv_flag = False
            for i in range(len(self.info_out_ram[qid])):
                if self.info_out_ram[qid][i][1].pkt_id == rd_data_req.pkt_id:
                    recv_flag = True
                    if self.info_out_ram[qid][i][2] == 1: # 说明之前已经请求过这个包了
                        raise Exception(f"__rd_data_req_process pkt_id is recved {rd_data_req.pkt_id}")
                    self.info_out_ram[qid][i][2] = 1
                    self.info_out_ram[qid][i][3] = rd_data_req.drop
    # 只有当队列中最老的一个包（队头）准备好被读取时，才触发数据发送流程。 
    # 这确保了无论 DUT 以什么顺序发起请求，TB 返回数据的顺序永远是严格的 FIFO
                    if i == 0:
                        self.rd_data_req_queue.put_nowait(qid)  # 通知读响应进程把数据给DUT 这个队列存储的实际上是qid
                        # rsp进程会监测这个队列 一旦发现里面有qid就会把对应的数据发送给DUT
            if not recv_flag:
                self.log.error(f"qid {qid}")
                self.log.error(f"act pkt_id {rd_data_req.pkt_id}")
                for i in range(len(self.info_out_ram[qid])):
                    self.log.error(f"exp pkt_id {self.info_out_ram[qid][i][1].pkt_id}")
                raise Exception(f"pkt_id did exist")

    async def __rd_data_rsp_process(self) -> None:
        while True:
            qid = await self.rd_data_req_queue.get()
            vq = VirtioVq(qid=qid, typ=TestType.NETRX) # 边带信号
            while True:
                if not self.info_out_ram[qid]:
                    break
                if self.info_out_ram[qid][0][2] == 1:
                    eth_pkt, info, _, drop_flag = self.info_out_ram[qid].pop(0) # pop(0) 取出并且移除排在最前面的数据包记录
                    if drop_flag == 1:
                        self.drop_num += 1
                        self.pkt_id_ram.release_id(info.pkt_id)
                        self.log.info(f"drop_num {self.drop_num} pass_num {self.pass_num} total_num {self.drop_num+self.pass_num}")
                        continue
                    # else:
                    # self.desc_rsp_queues[qid].put_nowait((eth_pkt, info))

                    sbd = RdDataRspSbd(
                        vq=vq.pack(),
                        pkt_len=info.pkt_len + 12,
                    )
                    send_cnt = (info.pkt_len + BUS_BYTE_WIDTH - 1) // BUS_BYTE_WIDTH + 1 # 计算传输的拍数 这里的pkt_len不包括head
                    for i in range(send_cnt):
                        trans = RdDataRspTrans()
                        trans.sbd = sbd.pack()
                        trans.sop = i == 0
                        trans.eop = i == send_cnt - 1
                        trans.sty = BUS_BYTE_WIDTH - 12 if i == 0 else 0
                        trans.mty = (BUS_BYTE_WIDTH - info.pkt_len) % BUS_BYTE_WIDTH if i == send_cnt - 1 else 0
                        local_len = BUS_BYTE_WIDTH - trans.sty - trans.mty # 表示当前beat中实际有效的数据长度
                        data = bytes(random.getrandbits(8) for _ in range(trans.sty))
                        data = data + eth_pkt[0:local_len]  # 拼接第一拍数据 无效数据*20，报头0-报头11
                        eth_pkt = eth_pkt[local_len:]       # 截掉已经发送的数据
                        trans.data = int.from_bytes(data, byteorder="little")
                        await self.interfaces.rd_data_rsp_if.send(trans)
                    self.pkt_id_ram.release_id(info.pkt_id)# 释放pkt_id
                else:   # 说明队头的包还没准备好 停止处理这个qid
                    break

    def __wr_data_ctx_cb(self, req_tran) -> RamTblTransaction:# 发起读请求时候 RamTbSlaver会捕获请求并且自动调用这个函数
        vq = VirtioVq.unpack(req_tran.req_qid) # req_tran是DUT发送的请求
        qid = vq.qid
        if vq.typ != TestType.NETRX:
            raise Exception(f" slot_ctrl_dev_id_cb vq_typ is not netrx is {vq.typ}")
        rsp_trans = SlotCtrlDevIdRspTrans() # WrDataCtxRspTrans
        rsp_trans.rsp_bdf = self.bdf_ram[qid]

        eth_pkt, info = self.desc_rsp_queues[qid].get_nowait()
        if info.forced_shutdown:
            rsp_trans.rsp_forced_shutdown = 1
        else:
            if info.err == "forced_shutdown":
                rsp_trans.rsp_forced_shutdown = 1
            else:
                rsp_trans.rsp_forced_shutdown = 0

        self.wr_data_ctx_queues[qid].put_nowait((eth_pkt, info)) # 这个队列存放的是正在进行或即将进行DMA写操作的包
        return rsp_trans

    async def _used_info_process(self) -> None:
        while self.drop_num + self.pass_num < self.cfg.seq_num:
            if self.interfaces.used_info_if.empty():
                await Timer(5 * CLOCK_FREQ, "ns")
                continue
            req_trans = await self.interfaces.used_info_if.recv()

            used_info_data = UsedInfoData.unpack(req_trans.data)
            vq = VirtioVq.unpack(used_info_data.vq)
            qid = vq.qid
            if vq.typ != TestType.NETRX:
                raise Exception(f"qid {qid} _slot_req_process vq_typ is not netrx")
            if self.wr_data_ctx_queues[qid].empty():
                raise Exception(f"desc_rsp_queues {qid} empty")
            eth_pkt, info = self.wr_data_ctx_queues[qid].get_nowait()

            if used_info_data.used_idx != info.avail_idx:
                raise Exception(f"used_info idx err exp: {info.avail_idx} act: {used_info_data.used_idx}")
            if used_info_data.id != info.ring_id:
                raise Exception(f"used_info ring_id err exp: {info.ring_id} act: {used_info_data.id}")

            if info.err == "":

                if used_info_data.len != info.pkt_len + self.virtio_head_len:
                    raise Exception(f"used_info len err exp: {info.pkt_len +self.virtio_head_len} act: {used_info_data.len}")

                act_data = b''                  # 初始化空的字节串
                pkt_len = used_info_data.len    # 获取实际写入的长度
                # list是因为一个包可能对应多个描述符 里面的元素是一个元组 包含内存和长度
                mem_items: list[Tuple[MemoryRegion, int]] = self.mem_addr[qid][info.avail_idx]
                for mem, len in mem_items:
                    if pkt_len <= 0:
                        self.mem.free_region(mem)
                        continue
                    else:
                        data_len = min(pkt_len, len)
                        act_data = act_data + await mem.read(0, data_len)  # pyright: ignore[reportOperatorIssue]
                        pkt_len -= data_len
                        self.mem.free_region(mem)

                if eth_pkt != act_data:
                    self.log.error(f"exp_data {eth_pkt} act_data {act_data}")
                self.pass_num += 1 # 指的是DUT成功把包传给了驱动
                self.log.info(f"drop_num {self.drop_num} pass_num {self.pass_num} total_num {self.drop_num+self.pass_num}")
            elif info.err == "desc_len_err":
                mem_items: list[Tuple[MemoryRegion, int]] = self.mem_addr[qid][info.avail_idx]
                for mem, len in mem_items:
                    self.mem.free_region(mem)
                if used_info_data.force_down == 1:
                    raise Exception("force_down err")
                if used_info_data.fatal != 0 and used_info_data.err_info != VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR:
                    raise Exception(f"err_code exp {VirtioErrCode.VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR} act: {used_info_data.err_info}")
                self.drop_num += 1
                self.log.info(f"drop_num {self.drop_num} pass_num {self.pass_num} total_num {self.drop_num+self.pass_num} desc_len_err")
            elif info.err == "forced_shutdown":
                mem_items: list[Tuple[MemoryRegion, int]] = self.mem_addr[qid][info.avail_idx]
                for mem, len in mem_items:
                    self.mem.free_region(mem)
                if used_info_data.force_down == 0:
                    raise Exception("force_down err")
                if used_info_data.fatal != 0 and used_info_data.err_info != VirtioErrCode.VIRTIO_ERR_CODE_NONE:
                    raise Exception(f"err_code exp {VirtioErrCode.VIRTIO_ERR_CODE_NONE} act: {used_info_data.err_info}")
                self.drop_num += 1
                self.log.info(f"drop_num {self.drop_num} pass_num {self.pass_num} total_num {self.drop_num+self.pass_num} forced_shutdown")
            elif info.err == "desc_rsp_err":
                mem_items: list[Tuple[MemoryRegion, int]] = self.mem_addr[qid][info.avail_idx]
                for mem, len in mem_items:
                    self.mem.free_region(mem)
                if used_info_data.force_down != 0:
                    raise Exception("force_down err")
                if used_info_data.fatal != 1 and used_info_data.err_info != info.err_code:
                    raise Exception(f"err_code exp {info.err_code} act: {used_info_data.err_info}")
                self.drop_num += 1
                self.log.info(f"drop_num {self.drop_num} pass_num {self.pass_num} total_num {self.drop_num+self.pass_num} err_code")
        # pass


async def run_test(dut, cfg: Optional[Cfg] = None, idle_inserter=None, backpressure_inserter=None):
    seed = 1768551146
    # seed = int(time.time())
    random.seed(seed)

    cfg = cfg if cfg is not None else smoke_cfg
    qid_list = random.sample(range(0, 255), cfg.q_num)
    tb = TB(cfg, dut, qid_list)
    tb.log.info(f"seed: {seed}")

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()

    await Timer(40, "us")
    cocotb.start_soon(tb._rx_buf_process(qid_list))
    await cocotb.start_soon(tb._used_info_process()).join()
    await Timer(10, "us")


if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None,cycle_pause])
        factory.add_option("backpressure_inserter", [None,cycle_pause])
        factory.generate_tests()


root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
