#!/usr/bin/env python3
################################################################################
#  文件名称 : test_dpu_top_tb.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/02/07
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  02/07     Joe Jiang   初始化版本
################################################################################
import math
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator
from functools import reduce
import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Join, Event
from cocotb.clock import Clock
from cocotb.regression import TestFactory

from cocotbext.pcie.core import RootComplex
from cocotbext.pcie.core.utils import PcieId
 
sys.path.append('../common')
from pcie.a10 import  A10PcieFunction, A10PcieDevice, A10RxBus, A10TxBus
from address_space import Pool, AddressSpace, MemoryRegion
from cocotbext.pcie.core.tlp import Tlp, TlpType, CplStatus

from beq_defines import *
from beq_pmd_behavior import *
from beq_ctrl import *

class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        # PCIe
        self.mem_address_space = Pool(None, 0, size=2**64, min_alloc=64)
        #self.mem_4G = self.mem_address_space.alloc_region(1536*4*1024*1024)
        self.soc_rc = RootComplex()
        self.soc_rc.register_rx_tlp_handler(TlpType.MEM_READ, self.handle_mem_read_tlp)
        self.soc_rc.register_rx_tlp_handler(TlpType.MEM_READ_64, self.handle_mem_read_tlp)
        self.soc_rc.register_rx_tlp_handler(TlpType.MEM_WRITE, self.handle_mem_write_tlp)
        self.soc_rc.register_rx_tlp_handler(TlpType.MEM_WRITE_64, self.handle_mem_write_tlp)

        self.a10_soc_ep = A10PcieDevice(
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
            reset_status=dut.soc_pcie_rst,
            # reset_status_n=dut.reset_status_n,
            coreclkout_hip=dut.soc_pcie_clk,
            # refclk0=dut.refclk0,
            # refclk1=dut.refclk1,
            # pin_perst_n=dut.pin_perst_n,

            # RX interface
            rx_bus=A10RxBus.from_prefix(dut, "soc_rx_st"),
            # rx_par_err=dut.rx_par_err,

            # TX interface
            tx_bus=A10TxBus.from_prefix(dut, "soc_tx_st"),
            # tx_par_err=dut.tx_par_err,

            # Configuration output
            tl_cfg_add=dut.soc_tl_cfg_add,
            tl_cfg_ctl=dut.soc_tl_cfg_ctl,
            )

        self.soc_rc.make_port().connect(self.a10_soc_ep)
        self.a10_soc_ep.functions[0].configure_bar(0, 1024*1024*64, ext=True, prefetch=True)

        cocotb.start_soon(Clock(dut.soc_pcie_clk, 4, units="ns").start())
        cocotb.start_soon(Clock(dut.clk_200m, 5, units="ns").start())
        cocotb.start_soon(Clock(dut.clk_50m, 20, units="ns").start())
        cocotb.start_soon(Clock(dut.clk_11m, 100, units="ns").start())

        self.doing = True
        self.sw_tx_doing = True
        self.sw_rx_doing = True
        self.worker_ready = {}
        self.sw_lo_queue = {}
        

    async def cycle_reset(self):
        async def rest(rst_pin, clk):
            rst_pin.value = 0
            await Timer(1, "us")
            await RisingEdge(clk)
            rst_pin.value = 1
            await Timer(1, "us")
            await RisingEdge(clk)
            rst_pin.value = 0
            await RisingEdge(clk)
            await RisingEdge(clk)
            await RisingEdge(clk)

        rst_sys_cr = cocotb.start_soon(rest(self.dut.soc_pcie_rst, self.dut.soc_pcie_clk))
        rst_11m_cr = cocotb.start_soon(rest(self.dut.rst_11m, self.dut.clk_11m))
        rst_50m_cr = cocotb.start_soon(rest(self.dut.rst_50m, self.dut.clk_50m))
        rst_200m_cr = cocotb.start_soon(rest(self.dut.rst_200m, self.dut.clk_200m))
        await Join(rst_sys_cr)
        await Join(rst_11m_cr)
        await Join(rst_50m_cr)
        await Join(rst_200m_cr)

    async def handle_mem_read_tlp(self, tlp):
        self.soc_rc.log.debug("Memory read, address 0x%08x, length %d, BE 0x%x/0x%x, tag %d",
                tlp.address, tlp.length, tlp.first_be, tlp.last_be, tlp.tag)
        if not self.mem_address_space.find_regions(tlp.address, tlp.length*4):
            self.soc_rc.log.warning("Memory request did not match any regions: %r", tlp)

            # Unsupported request
            cpl = Tlp.create_ur_completion_for_tlp(tlp, PcieId(0, 0, 0))
            self.soc_rc.log.info("UR Completion: %r", cpl)
            await self.soc_rc.send(cpl)
            return

        # perform operation
        addr = tlp.address

        # check for 4k boundary crossing
        if tlp.length*4 > 0x1000 - (addr & 0xfff):
            self.soc_rc.log.warning("Request crossed 4k boundary, discarding request")
            return

        # perform read
        try:
            data = await self.mem_address_space.read(addr, tlp.length*4)
        except Exception:
            self.soc_rc.log.warning("Memory read operation failed: %r", tlp)

            # Completer abort
            cpl = Tlp.create_ca_completion_for_tlp(tlp, PcieId(0, 0, 0))
            self.soc_rc.log.info("CA Completion: %r", cpl)
            await self.soc_rc.send(cpl)
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
            if cpl_dw_length > 32 << self.soc_rc.max_payload_size:
                cpl_dw_length = 32 << self.soc_rc.max_payload_size  # max payload size
                cpl_dw_length -= (addr & 0x7c) >> 2  # RCB align

            cpl.lower_address = addr & 0x7f

            cpl.set_data(data[m*4:(m+cpl_dw_length)*4])

            self.soc_rc.log.debug("Completion: %r", cpl)
            await self.soc_rc.send(cpl)

            m += cpl_dw_length
            n += cpl_dw_length*4 - (addr & 3)
            addr += cpl_dw_length*4 - (addr & 3)

    async def handle_mem_write_tlp(self, tlp):
        self.soc_rc.log.debug("Memory write, address 0x%08x, length %d, BE 0x%x/0x%x",
                tlp.address, tlp.length, tlp.first_be, tlp.last_be)

        if not self.mem_address_space.find_regions(tlp.address, tlp.length*4):
            self.soc_rc.log.warning("Memory request did not match any regions: %r", tlp)
            return

        # perform operation
        addr = tlp.address
        offset = 0
        start_offset = None
        mask = tlp.first_be

        # check for 4k boundary crossing
        if tlp.length*4 > 0x1000 - (addr & 0xfff):
            self.soc_rc.log.warning("Request crossed 4k boundary, discarding request")
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
            self.soc_rc.log.warning("Memory write operation failed: %r", tlp)
            return

    async def init(self):
        await self.cycle_reset()
        await Timer(1, 'us')
        await self.soc_rc.enumerate()
        soc_dev = self.soc_rc.find_device(self.a10_soc_ep.functions[0].pcie_id)
        await soc_dev.enable_device()
        await soc_dev.set_master()
        await Timer(100, 'ns')
        self.soc_bar0 = soc_dev.bar_window[0]
        self.beq_ctrl = beq_ctrl(self.soc_bar0)
        self.beq_pmd =  beq_pmd_behavior(self.mem_address_space, self.beq_ctrl, is_fit=False)

    async def write_reg(self, addr, value):
        data = value.to_bytes(8, byteorder="little")
        await self.soc_bar0.write(addr, data)

    async def read_reg(self, addr):
        data = await self.soc_bar0.read(addr, 8)
        val = int.from_bytes(data, byteorder="little")
        self.log.info("bar0 read reg addr {} value {}".format(hex(addr), hex(val)))
        return val


    def set_idle_generator(self, generator=None):
        if generator:
            self.a10_soc_ep.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.a10_soc_ep.set_backpressure_generator(generator)

  
    async def worker_tx(self, qid):
        segment = self.beq_pmd.get_rxq_segment(qid)
        segment_sz = segment*512
        pkt_cnt = 0
        while self.sw_tx_doing:
            if self.sw_lo_queue[qid].qsize() < 128:  
                mbuf_chains = [] 
                for i in range(random.randint(16, 64)):  
                    pkt_cnt = pkt_cnt + 1
                    if random.randint(0, 100) < 10:
                        length = random.randint(1, min(segment_sz*24, 65536))
                    else:
                        length = random.randint(1, min(segment_sz*4, 65536))
                    cycles = math.ceil(length/segment_sz)
                    mbuf = []
                    for i in range(cycles):  
                        reg = self.mem_address_space.alloc_region(segment_sz)   
                        addr = reg.get_absolute_address(0)
                        if i == cycles - 1 and length % segment_sz != 0:
                            buf_len = length % segment_sz 
                        else :
                            buf_len = segment_sz 
                        #self.log.info("desc qid {} {} {} {}".format(qid, hex(addr), buf_len, segment_sz))
                        mbuf.append(Mbuf(reg, buf_len, 0, 0))  

                        await self.sw_lo_queue[qid].put(buf_len)  
                    mbuf_chains.append(mbuf) 
                        
                while True:
                 
                    mbuf_chains = await self.beq_pmd.burst_tx(qid=qid, chains=mbuf_chains)
                   
                    if len(mbuf_chains) == 0:
                        break
                    else:
                        await Timer(1, "us")
            await Timer(100, "ns")
        self.log.info("worker_tx(qid:{}) pkt_cnt {}".format(qid, pkt_cnt))

    async def worker_rx(self, qid):
        pkt_cnt = 0
        while self.sw_rx_doing:
            mbuf_chains = await self.beq_pmd.burst_rx(qid=qid)
            if len(mbuf_chains) > 0:
                for chain in mbuf_chains:
                    pkt_cnt = pkt_cnt + 1
                    for mbuf in chain:
                        buf_len = await self.sw_lo_queue[qid].get()
                        self.mem_address_space.free_region(mbuf.reg) 
                        if mbuf.length != buf_len:  
                            raise ValueError("software loopback error!")
                self.log.info("worker_rx(qid:{}) pkt_cnt {}".format(qid, pkt_cnt))
            await Timer(100, "ns")
        self.log.info("worker_rx(qid:{}) pkt_cnt {}".format(qid, pkt_cnt))

   
    async def worker(self, qid):
        self.worker_ready[qid] = True  
        rx_pkt_cnt = 0  
        while self.doing:
            mbuf_chains = await self.beq_pmd.burst_rx(qid=qid)
            rx_pkt_cnt = rx_pkt_cnt + len(mbuf_chains) 
            if len(mbuf_chains) > 0:
                self.log.info("worker(qid:{}) rx_pkt_cnt: {}".format(qid, rx_pkt_cnt))
            while True:
                mbuf_chains = await self.beq_pmd.burst_tx(qid=qid, chains=mbuf_chains)  
                if len(mbuf_chains) == 0:
                    break
                else:
                    await Timer(1, "us")
            await Timer(100, "ns")

    async def get_loopback_status(self):
        tx_cnt = [0 for _ in range(8)]
        rx_cnt = [0 for _ in range(8)] 
        for i in range(2):
            data = await self.read_reg(0xFFF048 + i * 0x8)
            for j in range(4):
                tx_cnt[i*4+j] = data & 0xffff
                data = data >> 16
            data = await self.read_reg(0xFFF058 + i * 0x8)
            for j in range(4):
                rx_cnt[i*4+j] = data & 0xffff
                data = data >> 16        
        loopback_err = await self.read_reg(0xFFF070)
        return loopback_err, tx_cnt, rx_cnt
    
    
    def wait_worker_ready(self, worker_num):
        ready = True
        for i in range(worker_num):
            ready = ready and self.worker_ready[i]
        return ready

async def run_test(dut, idle_inserter, backpressure_inserter):
    random.seed(52346)
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.init()
    worker_num = 8

    async def err_checker(dut):
        while True:
            await RisingEdge(dut.clk_200m)
            if dut.u_dpu_top.u_dpu_role.u_beq_loop_test_top.u0_beq_loop_test_rx.error_o.value:
                raise ValueError("loopback error!")

    cocotb.start_soon(err_checker(dut))
    for seq in range(20):  #20
        print("seq num:{}".format(seq))
        tb.doing = True
        tb.sw_rx_doing = True
        tb.sw_tx_doing = True
        worker_cr = []
        worker_cr_tx = []
        worker_cr_rx = []
        
        for qid in range(worker_num):
            beq_depth = beq_q_depth_t.q1k#random.choice(beq_q_depth_type_list)
            segment_sz = random.choice(beq_rx_segment_type_list)
            await tb.beq_pmd.create_queue(qid, False, beq_depth, segment_sz, typ=beq_transfer_type_t.emu)
            await tb.beq_pmd.create_queue(qid, True, beq_depth, segment_sz, typ=beq_transfer_type_t.emu)

            await tb.beq_pmd.start_queue(qid=qid, is_txq=False)
            await tb.beq_pmd.start_queue(qid=qid, is_txq=True)
        '''
        tb.sw_lo_queue = {}
        for qid in range(worker_num):
            tb.sw_lo_queue[qid+worker_num] = Queue()
            beq_depth = random.choice(beq_q_depth_type_list)
            segment_sz = random.choice(beq_rx_segment_type_list)
            await tb.beq_pmd.create_queue(qid+worker_num, False, beq_depth, segment_sz, typ=beq_transfer_type_t.sgdma)
            await tb.beq_pmd.create_queue(qid+worker_num, True, beq_depth, segment_sz, typ=beq_transfer_type_t.sgdma)

            await tb.beq_pmd.start_queue(qid=qid+worker_num, is_txq=False)
            await tb.beq_pmd.start_queue(qid=qid+worker_num, is_txq=True)
        '''
        for qid in range(worker_num):
            worker_cr.append(cocotb.start_soon(tb.worker(qid))) 
        '''
        for qid in range(worker_num):
            worker_cr_tx.append(cocotb.start_soon(tb.worker_tx(qid+worker_num)))
            worker_cr_rx.append(cocotb.start_soon(tb.worker_rx(qid+worker_num)))
        '''
        for i in range(worker_num):
            await tb.write_reg(0xFFF008 + i*0x8, 0x1234 + i)
        ctrl = ((worker_num-1) << 2) + 0x3
        await tb.write_reg(0xFFF000, ctrl)
        for idx in range(random.randint(2,10)):
            if idx % 4 == 0:
                for i in range(worker_num):
                    await tb.beq_ctrl.get_beq_status(i, False)
                    await tb.beq_ctrl.get_beq_status(i, True)
                loopback_err, tx_cnt, rx_cnt = await tb.get_loopback_status()  
                tb.log.info("loopback check err:{} tx_cnt:{} rx_cnt:{}".format(loopback_err, tx_cnt, rx_cnt)) 
                if loopback_err:
                    raise ValueError("loopback error!")
            await Timer(1, "us")
        await tb.write_reg(0xFFF000, ctrl & 0xFFFE)  
        loopback_idle = False
        tb.sw_tx_doing = False
        while not loopback_idle:
            loopback_err, tx_cnt, rx_cnt = await tb.get_loopback_status()
            tb.log.info("loopback stop err:{} tx_cnt:{} rx_cnt:{}".format(loopback_err, tx_cnt, rx_cnt))
            if tx_cnt == rx_cnt:  
                loopback_idle = True
            if loopback_err:
                raise ValueError("loopback error!")
            await Timer(1, "us")
        tb.doing = False  
        '''
        for i in range(worker_num):
            await Join(worker_cr_tx[i])  #等待所有发送线程完成
        sw_loopback_idle = False
        while not sw_loopback_idle:
            if len(tb.sw_lo_queue.keys()) == 0:
                sw_loopback_idle = True
            emptys = [tb.sw_lo_queue[qid].empty() for qid in tb.sw_lo_queue.keys()]
            sw_loopback_idle = reduce(lambda x, y: x&y, emptys)
            await Timer(1, "us")
        tb.sw_rx_doing = False
        '''
        for i in range(worker_num):   
            await Join(worker_cr[i])
            #await Join(worker_cr_rx[i])
        '''
        for qid in range(worker_num):
            _, _, _, rxq_pkt_cnt, _, _, _, _, _, _ = await tb.beq_ctrl.get_beq_status(qid+worker_num, False)
            _, _, _, txq_pkt_cnt, _, _, _, _, _, _ = await tb.beq_ctrl.get_beq_status(qid+worker_num, True)
            if rxq_pkt_cnt != txq_pkt_cnt:
                raise ValueError("beq pkt cnt error!")
            await tb.beq_pmd.stop_queue(qid=qid+worker_num, is_txq=False)
            await tb.beq_pmd.stop_queue(qid=qid+worker_num, is_txq=True)
            tb.beq_pmd.destroy_queue(qid=qid+worker_num, is_txq=False)
            tb.beq_pmd.destroy_queue(qid=qid+worker_num, is_txq=True)
        '''
        for qid in range(worker_num):
            _, _, _, rxq_pkt_cnt, _, _, _, _, _, _ = await tb.beq_ctrl.get_beq_status(qid, False)
            _, _, _, txq_pkt_cnt, _, _, _, _, _, _ = await tb.beq_ctrl.get_beq_status(qid, True)
            if rxq_pkt_cnt != txq_pkt_cnt: 
                raise ValueError("beq pkt cnt error!")
            await tb.beq_pmd.stop_queue(qid=qid, is_txq=False)
            await tb.beq_pmd.stop_queue(qid=qid, is_txq=True)
            tb.beq_pmd.destroy_queue(qid=qid, is_txq=False)
            tb.beq_pmd.destroy_queue(qid=qid, is_txq=True)
        
        common_dfx_err = await tb.read_reg(0xc00000)
        if common_dfx_err != 0:
                raise ValueError("common_dfx error!")
        desc_eng_dfx_err = await tb.read_reg(0xc01000)
        if desc_eng_dfx_err!= 0:
                raise ValueError("desc_eng_dfx error!")
        rxq_dfx_err = await tb.read_reg(0xc02000)
        if rxq_dfx_err!= 0:
                raise ValueError("rxq_dfx error!")
        txq_dfx_err = await tb.read_reg(0xc03000)
        if txq_dfx_err!= 0:
                raise ValueError("txq_dfx error!")

        #if dut.u_dpu_top.u_dpu_role.u_beq_top.u_beq_txq.rd_dma_data_inflight.value != 0:
        #    raise ValueError("txq inflight error!")
        

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [cycle_pause])
        factory.add_option("backpressure_inserter", [cycle_pause])
        factory.generate_tests()

#sys.path.append('../common'); from debug import *


root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
