#!/usr/bin/env python3
################################################################################
#  文件名称 : test_tlp_adap_soc_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/01
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/01     Joe Jiang   初始化版本
################################################################################

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
from drivers.tlp_adap_dma_bus import DmaMaster
from bus.tlp_adap_dma_bus import DmaBus

from pcie.a10 import  A10PcieDevice, A10RxBus, A10TxBus
from address_space import Pool, AddressSpace, MemoryRegion
from cocotbext.pcie.core.tlp import Tlp, TlpType, CplStatus



class Shuffled_Tlp:
    def __init__(self, rc, num_of_tag=64):
        self.rc = rc
        self.num_of_tag = num_of_tag
        self.chns = [Queue() for _ in range(self.num_of_tag)]
        #cocotb.start_soon(self._process())

    async def put(self, tlp):
       await self.chns[tlp.tag].put((get_sim_time("ns"), tlp))

    async def _process(self):
        while True:
            for chn in self.chns:
                if not chn.empty():
                    (tim, _) = chn._queue[0]
                    latency = math.ceil(get_sim_time("ns") - tim)
                    if latency < 1000:
                        continue
                    (_, tlp) = await chn.get()
                    await self.rc.send(tlp)
            await Timer(5, "ns")
class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = SimLog("cocotb")
        self.log.setLevel(logging.DEBUG)
        self.mem_address_space = Pool(None, 0, size=2**64, min_alloc=64)
        self.mem_4G = self.mem_address_space.alloc_region(1536*4*1024*1024)
        # PCIe
        self.rc = RootComplex()

        self.shuffled_tlp = Shuffled_Tlp(self.rc, num_of_tag=64)
        
        self.rc.register_rx_tlp_handler(TlpType.MEM_READ, self.handle_mem_read_tlp)
        self.rc.register_rx_tlp_handler(TlpType.MEM_READ_64, self.handle_mem_read_tlp)
        self.rc.register_rx_tlp_handler(TlpType.MEM_WRITE, self.handle_mem_write_tlp)
        self.rc.register_rx_tlp_handler(TlpType.MEM_WRITE_64, self.handle_mem_write_tlp)
        
        self.dev = A10PcieDevice(
            # configuration options
            pcie_generation=3,
            l_tile=False,
            pf_count=1,
            max_payload_size=128,
            enable_extended_tag=True,

            pf0_msi_enable=False,
            pf0_msi_count=1,
            pf1_msi_enable=False,
            pf1_msi_count=1,
            pf2_msi_enable=False,
            pf2_msi_count=1,
            pf3_msi_enable=False,
            pf3_msi_count=1,
            pf0_msix_enable=False,
            pf0_msix_table_size=0,
            pf0_msix_table_bir=0,
            pf0_msix_table_offset=0x00000000,
            pf0_msix_pba_bir=0,
            pf0_msix_pba_offset=0x00000000,
            pf1_msix_enable=False,
            pf1_msix_table_size=0,
            pf1_msix_table_bir=0,
            pf1_msix_table_offset=0x00000000,
            pf1_msix_pba_bir=0,
            pf1_msix_pba_offset=0x00000000,
            pf2_msix_enable=False,
            pf2_msix_table_size=0,
            pf2_msix_table_bir=0,
            pf2_msix_table_offset=0x00000000,
            pf2_msix_pba_bir=0,
            pf2_msix_pba_offset=0x00000000,
            pf3_msix_enable=False,
            pf3_msix_table_size=0,
            pf3_msix_table_bir=0,
            pf3_msix_table_offset=0x00000000,
            pf3_msix_pba_bir=0,
            pf3_msix_pba_offset=0x00000000,

            # signals
            # Clock and reset
            reset_status=dut.rst,
            # reset_status_n=dut.reset_status_n,
            coreclkout_hip=dut.clk,
            # refclk0=dut.refclk0,
            # refclk1=dut.refclk1,
            # pin_perst_n=dut.pin_perst_n,

            # RX interface
            rx_bus=A10RxBus.from_prefix(dut, "rx_st"),
            # rx_par_err=dut.rx_par_err,

            # TX interface
            tx_bus=A10TxBus.from_prefix(dut, "tx_st"),
            # tx_par_err=dut.tx_par_err,

            # Configuration output
            tl_cfg_add=dut.tl_cfg_add,
            tl_cfg_ctl=dut.tl_cfg_ctl,
            )

        self.rc.make_port().connect(self.dev)

        self.dev.functions[0].configure_bar(0, 1024*1024*8, True, True)
        self.dev.functions[0].configure_bar(2, 1024*1024*8, True, True)
        self.dev.functions[0].configure_bar(4, 1024*1024*8, True, True)

        self.avalonMm = AvalonMemory(dut, "avmm", dut.clk, readlatency_min=8, readlatency_max=16)
        self.milte_master = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk, dut.rst)
        self.dmaMaster = DmaMaster(DmaBus.from_prefix(dut, "dma", has_sav=True), dut.clk, dut.rst)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.clock_edge_event = RisingEdge(dut.clk)

        self.cnt_q = Queue(maxsize=2048)
        self.cnttemp_q = Queue(maxsize=4096)
        self.data_q = Queue(maxsize=4096)
        self.addr_q = Queue(maxsize=4096)
        self.length_q = Queue(maxsize=4096)
        self.rd2rsp_loop_wrq = Queue(maxsize=4096)
        self.rd2rsp_loop_rdq = Queue(maxsize=4096)
        self.cnt_req = 0
        self.cnt_rsp = 0
        self.cnt_rc_cpl = 0

    async def handle_mem_read_tlp(self, tlp):
        self.rc.log.info("Memory read, address 0x%08x, length %d, BE 0x%x/0x%x, tag %d",
                tlp.address, tlp.length, tlp.first_be, tlp.last_be, tlp.tag)
        if not self.mem_address_space.find_regions(tlp.address, tlp.length*4):
            self.rc.log.warning("Memory request did not match any regions: %r", tlp)

            # Unsupported request
            cpl = Tlp.create_ur_completion_for_tlp(tlp, PcieId(0, 0, 0))
            self.rc.log.info("UR Completion: %r", cpl)
            await self.rc.send(cpl)
            return

        # perform operation
        addr = tlp.address

        # check for 4k boundary crossing
        if tlp.length*4 > 0x1000 - (addr & 0xfff):
            self.rc.log.warning("Request crossed 4k boundary, discarding request")
            return

        # perform read
        try:
            data = await self.mem_address_space.read(addr, tlp.length*4)
        except Exception:
            self.rc.log.warning("Memory read operation failed: %r", tlp)

            # Completer abort
            cpl = Tlp.create_ca_completion_for_tlp(tlp, PcieId(0, 0, 0))
            self.rc.log.info("CA Completion: %r", cpl)
            await self.rc.send(cpl)
            return
        # prepare completion TLP(s)
        m = 0
        n = 0
        addr = tlp.address+tlp.get_first_be_offset()
        dw_length = tlp.length
        byte_length = tlp.get_be_byte_count()           
        while m < dw_length:
            cpl = Tlp.create_completion_data_for_tlp(tlp, PcieId(0, 0, 0))

            cpl_dw_length = dw_length - m
            cpl_byte_length = byte_length - n
            cpl.byte_count = cpl_byte_length
            if cpl_dw_length > 32 << self.rc.max_payload_size:
                cpl_dw_length = 32 << self.rc.max_payload_size  # max payload size
                cpl_dw_length -= (addr & 0x7c) >> 2  # RCB align

            cpl.lower_address = addr & 0x7f

            cpl.set_data(data[m*4:(m+cpl_dw_length)*4])

            self.rc.log.info("Completion: %r", cpl)
            #await self.shuffled_tlp.put(cpl)
            await self.rc.send(cpl)

            m += cpl_dw_length
            n += cpl_dw_length*4 - (addr & 3)
            addr += cpl_dw_length*4 - (addr & 3)

    async def handle_mem_write_tlp(self, tlp):
        self.rc.log.debug("Memory write, address 0x%08x, length %d, BE 0x%x/0x%x",
                tlp.address, tlp.length, tlp.first_be, tlp.last_be)

        if not self.mem_address_space.find_regions(tlp.address, tlp.length*4):
            self.rc.log.warning("Memory request did not match any regions: %r", tlp)
            return

        # perform operation
        addr = tlp.address
        offset = 0
        start_offset = None
        mask = tlp.first_be

        # check for 4k boundary crossing
        if tlp.length*4 > 0x1000 - (addr & 0xfff):
            self.rc.log.warning("Request crossed 4k boundary, discarding request")
            return

        # generate operation list
        write_ops = []

        data = tlp.get_data()

        # first dword
        for k in range(4):
            if mask & (1 << k):
                if start_offset is None:
                    start_offset = offset
            else:
                if start_offset is not None and offset != start_offset:
                    write_ops.append((addr+start_offset, data[start_offset:offset]))
                start_offset = None

            offset += 1

        if tlp.length > 2:
            # middle dwords
            if start_offset is None:
                start_offset = offset
            offset += (tlp.length-2)*4

        if tlp.length > 1:
            # last dword
            mask = tlp.last_be

            for k in range(4):
                if mask & (1 << k):
                    if start_offset is None:
                        start_offset = offset
                else:
                    if start_offset is not None and offset != start_offset:
                        write_ops.append((addr+start_offset, data[start_offset:offset]))
                    start_offset = None

                offset += 1

        if start_offset is not None and offset != start_offset:
            write_ops.append((addr+start_offset, data[start_offset:offset]))

        # perform writes
        try:
            for addr, data in write_ops:
                await self.mem_address_space.write(addr, data)
        except Exception:
            self.rc.log.warning("Memory write operation failed: %r", tlp)
            return

    async def wait_clk(self):
        await self.clock_edge_event
    
    async def init(self):
        await FallingEdge(self.dut.rst)
        await Timer(100, 'ns')
        await self.rc.enumerate()
        dev = self.rc.find_device(self.dev.functions[0].pcie_id)
        await dev.enable_device()
        await dev.set_master()
        await Timer(1000, 'ns')

    async def cnt_init(self):
        numbers = list(range(2048))
        for num in numbers:
            await self.cnt_q.put(num)

    async def test_case(self,max_seq, mem_base,addr_slice,bdf):
        num = 0
        while num < max_seq :
            i = await self.cnt_q.get()
            self.log.info("seq: {}".format(num))
            lengths = random.randint(1,4096)
            addr =  mem_base+random.randint(addr_slice*i, addr_slice*(i+1)-lengths)
            #data = os.urandom(lengths)
            data = bytes([i % 256 for i in range(lengths)])
            await self.dmaMaster.write_nb_req(addr, data, sty=random.randint(0,31), rd2rsp_loop=0x87654321+i, bdf=bdf,has_rsp=True)
            await self.cnt_q.put(i)
            await self.cnttemp_q.put(i)
            await self.length_q.put(lengths)
            await self.addr_q.put(addr)
            await self.data_q.put(data)
            num = num + 1

    async def rd_req(self,bdf):
        while True :
            i = await self.cnttemp_q.get()
            rsp = await self.dmaMaster.write_rsp_get()
            assert int(rsp) == 0x87654321+i
            lengths = await self.length_q.get()
            addr = await self.addr_q.get()
            rd2rsp_loop = 0x12345678+i
            await self.dmaMaster.read_nb_req(addr, lengths, sty=random.randint(0,31), rd2rsp_loop=rd2rsp_loop, bdf=bdf)
            #await self.dmaMaster.read_nb_req(addr, lengths, sty=20, rd2rsp_loop=rd2rsp_loop, bdf=bdf)
            await self.rd2rsp_loop_rdq.put(rd2rsp_loop)
            self.cnt_req = self.cnt_req + 1
            self.rc.log.info("cnt_req {}".format(self.cnt_req))

    async def rd_rsp(self):
        while True :
            val = await self.dmaMaster.read_rsp_get()
            data = await self.data_q.get()
            rd2rsp_loop_back = await self.rd2rsp_loop_rdq.get()
            assert data == val.data  
            assert val.rd2rsp_loop == rd2rsp_loop_back
            self.cnt_rsp = self.cnt_rsp + 1
            self.rc.log.info("cnt_rsp {}".format(self.cnt_rsp))



    def set_idle_generator(self, generator=None):
        if generator:
            self.dmaMaster.set_idle_generator(generator)
            self.dev.set_idle_generator(generator)
            #self.dmaMaster.write_if.wr_rsp_channel.set_pause_generator(generator())
            #self.dmaMaster.read_if.rd_rsp_channel.set_pause_generator(generator())
            #self.dev.rx_source.set_pause_generator(generator())
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.dmaMaster.set_backpressure_generator(generator)
            self.dev.set_backpressure_generator(generator)
            #self.dmaMaster.write_if.wr_req_channel.set_pause_generator(generator())
            #self.dmaMaster.read_if.rd_req_channel.set_pause_generator(generator())
            #self.dev.tx_sink.set_pause_generator(generator())

async def run_test(dut, idle_inserter, backpressure_inserter):
    random.seed(321)
    dut.rst.setimmediatevalue(0)
    tb = TB(dut)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.init()
    await tb.cnt_init()
    mem = tb.rc.mem_pool.alloc_region(16*1024*1024)
    mem_base = mem.get_absolute_address(0)

    dev = tb.rc.find_device(tb.dev.functions[0].pcie_id)
    bdf = int(tb.dev.functions[0].pcie_id)

    dev_pf0_bar0 = dev.bar_window[0]
    dev_pf0_bar2 = dev.bar_window[2]

    '''
    tb.log.info("Test memory write to BAR 2")
    test_data = b'\x11\x22\x33\x44\x11\x22\x33\x44'
    await dev_pf0_bar2.write(0, test_data)
    await Timer(100, 'ns')
    
    tb.log.info("Test memory read from BAR 2")
    val = await dev_pf0_bar2.read(0, len(test_data), timeout=100000)
    tb.log.info("Read data: %s", val.hex())
    assert val == test_data

    #dma test
    test_data = test_data*4
    print(len(test_data))
    await tb.dmaMaster.write_nb_req(mem_base, test_data, rd2rsp_loop=0x87654321)
    await tb.dmaMaster.write_nb_req(mem_base, test_data, rd2rsp_loop=0x87654321)
    await Timer(1000, 'ns')
    '''
    max_seq = 100000
    outstanding = 1

    
    async def bar_test():
        for _ in range(max_seq * outstanding):
            #tb.log.info("Test memory write to BAR 2")
            test_data = b'\x11\x22\x33\x44\x11\x22\x33\x55'
            await dev_pf0_bar2.write(0, test_data)            
            #tb.log.info("Test memory read from BAR 2")
            val = await dev_pf0_bar2.read(0, len(test_data), timeout=100000)
            #tb.log.info("Read data: %s", val.hex())
            assert val == test_data
    _process_bar_test_cr = cocotb.start_soon(bar_test())
    await Timer(1000, 'ns')
    cocotb.start_soon(tb.rd_req(bdf = bdf))
    cocotb.start_soon(tb.rd_rsp()) 
    await tb.test_case(max_seq = max_seq, mem_base = mem_base, addr_slice = 8192, bdf = bdf)    
    while tb.cnt_rsp != max_seq:
       await Timer(1000, 'ns')
    await Timer(5000, 'ns')

    _process_bar_test_cr.kill()  
    await Timer(5000, 'ns')


def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:

    for test in [run_test]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None,cycle_pause])
        factory.add_option("backpressure_inserter", [None,cycle_pause])
        factory.generate_tests()

root_logger = logging.getLogger()

file_handler = RotatingFileHandler("rotating.log", maxBytes=(100 * 1024 * 1024), backupCount=1000)
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)