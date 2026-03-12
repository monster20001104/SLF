###########################################
# 文件名称 : test_dirty_log_tb
# 作者名称 : 崔飞翔
# 创建日期 : 2025/08/07
# 功能描述 : 
# 
# 修改记录 : 
# 
# 修改日期 : 2025/08/07
# 版本号    修改人    修改内容
# v1.0     崔飞翔     初始化版本
###########################################
import math
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from cocotb.regression import TestFactory
from cocotb.queue import Queue, QueueFull

from cocotbext.pcie.core import RootComplex
from cocotbext.pcie.core.utils import PcieId

from cocotb_bus.drivers.avalon import AvalonMemory
from cocotb.utils import get_sim_time

sys.path.append('../common')
#from debug import *
from bus.mlite_bus      import MliteBus
from drivers.mlite_bus  import MliteBusMaster
from drivers.tlp_adap_dma_bus import DmaMasterWrite
from monitors.tlp_adap_dma_bus import DmaRam
from bus.tlp_adap_dma_bus import DmaWriteBus

from address_space import Pool, AddressSpace, MemoryRegion


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = SimLog("cocotb")
        self.log.setLevel(logging.DEBUG)
        self.mem_address_space = Pool(None, 0, size=2**64, min_alloc=64)
        self.milte_master = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk, dut.rst)
        self.dmaMaster = DmaMasterWrite(DmaWriteBus.from_prefix(dut, "cdc", has_sav=True), dut.clk, dut.rst)
        self.dmaSlave = DmaRam(wr_bus=DmaWriteBus.from_prefix(dut, "pcie", has_sav=True),rd_bus= None, clock=dut.clk, reset=dut.rst, mem = self.mem_address_space)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.dirty_log_en_list = []
        self.chn_idx_list = []
        self.dirty_log_len_list = []
        self.first_tbl_base_addr_list = []
        self.second_tbl_base_addr_list = []
        self.cnt_q = Queue(maxsize=2048)
        self.cnttemp_q = Queue(maxsize=4096)
        self.addr_q = Queue(maxsize=4096)
        self.length_q = Queue(maxsize=4096)
        self.dev_id_q = Queue(maxsize=4096)
        self.chn_idx_q = Queue(maxsize=4096)
        self.dirty_log_len_q = Queue(maxsize=4096)
        self.first_tbl_base_addr_q = Queue(maxsize=4096)
        self.second_tbl_base_addr_q = Queue(maxsize=4096)

        self.cnt_wr_req = 0
        self.cnt_wr_rsp = 0
        self.dirty_log_cmp_cnt = 0
        self.dirty_log_cnt = 0



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

    async def csr_init(self):
        for i in range(1024):
            dirty_log_en = random.randint(0, 1)
            self.dirty_log_en_list.append(dirty_log_en)
            chn_idx = random.randint(0, 31)
            self.chn_idx_list.append(chn_idx)
            dirty_log_tbl_idx_enable_tbl_val = (chn_idx << 1) | dirty_log_en
            await self.milte_master.write(0x0000_0000 + i*0x8, dirty_log_tbl_idx_enable_tbl_val)
        for i in range(32):
            dirty_log_len = random.getrandbits(24)
            self.dirty_log_len_list.append(dirty_log_len)
            await self.milte_master.write(0x0000_2000 + i*0x8, dirty_log_len)
        min_addr = 1024 * 1024 * 16
        max_addr = (1 << 36) - (1 << 24) - 1
        def gen_unique_addrs(count):
            seen = set()
            while len(seen) < count:
                addr = random.randint(min_addr + 1, max_addr)
                seen.add(addr)
            return list(seen)
        self.first_tbl_base_addr_list = gen_unique_addrs(32)
        self.second_tbl_base_addr_list = gen_unique_addrs(32)
        for i in range(32):
            await self.milte_master.write(0x0000_4000 + i*0x8, self.first_tbl_base_addr_list[i])
            await self.milte_master.write(0x0000_6000 + i*0x8, self.second_tbl_base_addr_list[i])

    async def cnt_init(self):
        numbers = list(range(2048))
        for num in numbers:
            await self.cnt_q.put(num)

    async def wr_req(self,max_seq, mem_base,addr_slice,bdf):
        num = 0
        while num < max_seq :
            i = await self.cnt_q.get()
            lengths = random.randint(1,4096)
            addr = mem_base+random.randint(addr_slice*i, addr_slice*(i+1)-lengths)
            data = os.urandom(lengths)
            #data = bytes([i % 256 for i in range(lengths)])
            dev_id = random.randint(0,1023)
            await self.dev_id_q.put(dev_id)
            await self.addr_q.put(addr)
            self.log.info("wr_addr {}".format(hex(addr)))
            await self.length_q.put(lengths)
            await self.dmaMaster.write_nb_req(addr, data, sty=random.randint(0,31), rd2rsp_loop=0x87654321+i, bdf=bdf, dev_id = dev_id, has_rsp=True)
            self.cnt_wr_req = self.cnt_wr_req + 1
            self.log.info("cnt_wr_req: {}".format(self.cnt_wr_req))
            
            await self.cnt_q.put(i)
            await self.cnttemp_q.put(i)
            num = num + 1

    async def wr_rsp(self):
        while True :
            i = await self.cnttemp_q.get()
            rsp = await self.dmaMaster.write_rsp_get()
            assert int(rsp) == 0x87654321+i
            self.cnt_wr_rsp = self.cnt_wr_rsp + 1
            self.log.info("cnt_wr_rsp {}".format(self.cnt_wr_rsp))

    async def data_cmp(self):
        while True :
            await RisingEdge(self.dut.clk)
            addr = await self.addr_q.get()
            second_tbl_addr = addr >> 12
            first_tbl_addr = addr >> 24
            lengths = await self.length_q.get()
            addr_offset_12 = addr & 0xFFF
            addr_offset_add_length = lengths + addr_offset_12
            dirty_log_all_size = 2*((addr_offset_add_length>>12) + int(bool(addr_offset_add_length & 0xFFF)))
            dev_id = await self.dev_id_q.get()
            dirty_log_en = self.dirty_log_en_list[dev_id]
            chn_idx = self.chn_idx_list[dev_id]
            dirty_log_len = self.dirty_log_len_list[chn_idx]
            while second_tbl_addr + dirty_log_all_size -1 > dirty_log_len and second_tbl_addr < dirty_log_len:
                dirty_log_all_size = dirty_log_all_size - 1
            second_tbl_base_addr = self.second_tbl_base_addr_list[chn_idx]
            first_tbl_base_addr = self.first_tbl_base_addr_list[chn_idx]
            self.log.info("self.dirty_log_cmp_cnt {}".format(self.dirty_log_cmp_cnt))
            self.log.info("self.dmaSlave.dirty_log_cnt {}".format(self.dmaSlave.dirty_log_cnt))
            self.log.info("addr {}".format(hex(addr)))
            self.log.info("lengths {}".format(lengths))
            self.log.info("dev_id {}".format(dev_id))
            self.log.info("chn_idx {}".format(chn_idx))
            self.log.info("dirty_log_en {}".format(dirty_log_en))
            self.log.info("dirty_log_len {}".format(dirty_log_len))
            self.log.info("second_tbl_addr {}".format(second_tbl_addr))
            self.log.info("self.dirty_log_cnt {}".format(self.dirty_log_cnt))  
            self.log.info("dirty_log_all_size {}".format(dirty_log_all_size))
            self.log.info("self.dmaSlave.dirty_log_cnt - self.dirty_log_cmp_cnt {}".format(self.dmaSlave.dirty_log_cnt - self.dirty_log_cmp_cnt))
            while (self.dmaSlave.dirty_log_cnt - self.dirty_log_cmp_cnt) < dirty_log_all_size and dirty_log_en == 1 and second_tbl_addr < dirty_log_len:
                await RisingEdge(self.dut.clk)
            if dirty_log_en == 1 and second_tbl_addr < dirty_log_len:
                self.dirty_log_cnt = 0
                while (self.dirty_log_cnt < dirty_log_all_size) and (second_tbl_addr < dirty_log_len):
                    await RisingEdge(self.dut.clk)
                    self.log.info("self.dirty_log_cnt {}".format( self.dirty_log_cnt))
                    self.log.info("read_addr_sec {}".format(hex(second_tbl_base_addr + second_tbl_addr)))
                    self.log.info("read_addr_fir {}".format(hex(first_tbl_base_addr + first_tbl_addr)))
                    sec_data = await self.mem_address_space.read(second_tbl_base_addr + second_tbl_addr, 1)
                    fir_data = await self.mem_address_space.read(first_tbl_base_addr + first_tbl_addr, 1)
                    self.log.info("sec_data {}".format(sec_data))
                    if sec_data != b'\xff':
                        self.log.info("sec_data {}".format(sec_data))
                        assert sec_data == b'\xff'
                    if fir_data != b'\xff':
                        self.log.info("fir_data {}".format(fir_data))
                        assert fir_data == b'\xff'                        
                    second_tbl_addr = second_tbl_addr + 1
                    first_tbl_addr = second_tbl_addr >> 12
                    self.dirty_log_cnt = self.dirty_log_cnt + 2
                    self.dirty_log_cmp_cnt = self.dirty_log_cmp_cnt + 2



    def set_idle_generator(self, generator=None):
        if generator:
            self.dmaMaster.set_idle_generator(generator)
            self.dmaSlave.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.dmaMaster.set_backpressure_generator(generator)
            self.dmaSlave.set_backpressure_generator(generator)

async def run_test(dut, idle_inserter, backpressure_inserter, seed):
    random.seed(seed)
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()
    await tb.csr_init()
    await tb.cnt_init()
    await Timer(500, 'ns')
    max_seq = 100000
    mem = tb.mem_address_space.alloc_region(2**36)  
    mem_base = mem.get_absolute_address(0)
    cocotb.start_soon(tb.wr_rsp())
    cocotb.start_soon(tb.data_cmp())
    await tb.wr_req(max_seq = max_seq, mem_base = mem_base, addr_slice = 8192, bdf = 1)
    while tb.cnt_wr_rsp != max_seq:
        await Timer(500, 'ns')

    while tb.dirty_log_cmp_cnt != tb.dmaSlave.dirty_log_cnt:
        await Timer(500, 'ns')
        tb.log.info("dirty_log_cmp_cnt: {}".format(tb.dirty_log_cmp_cnt))
        tb.log.info("send_dirty_log_cnt: {}".format(tb.dmaSlave.dirty_log_cnt))
        
    await Timer(500, 'ns')


def seed_gen(i):
    return random.Random(i).randint(0, 2**32-1)

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:

    for test in [run_test]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None ,cycle_pause])
        factory.add_option("backpressure_inserter", [None ,cycle_pause])
        factory.add_option("seed", [seed_gen(i) for i in range(10)])
        factory.generate_tests()

root_logger = logging.getLogger()

file_handler = RotatingFileHandler("rotating.log", maxBytes=(100 * 1024 * 1024), backupCount=1000)
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)