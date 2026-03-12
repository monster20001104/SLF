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
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Join, Event
from cocotb.clock import Clock
from cocotb.regression import TestFactory


from cocotbext.pcie.core.utils import PcieId
 
sys.path.append('../common')
from pcie.a10 import RootComplex
from pcie.a10 import  A10PcieFunction, A10PcieDevice, A10RxBus, A10TxBus
from address_space import AddressSpace, MemoryRegion

class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        # PCIe
        self.host_rc = RootComplex()

        self.soc_rc = RootComplex()

        self.a10_host_ep = A10PcieDevice(
            tlp_bypass = True,
            # configuration options
            pcie_generation=3,
            l_tile=False,
            pf_count=1,
            max_payload_size=512,
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
            reset_status=dut.host_pcie_rst,
            # reset_status_n=dut.reset_status_n,
            coreclkout_hip=dut.host_pcie_clk,
            # refclk0=dut.refclk0,
            # refclk1=dut.refclk1,
            # pin_perst_n=dut.pin_perst_n,

            # RX interface
            rx_bus=A10RxBus.from_prefix(dut, "host_rx_st"),
            # rx_par_err=dut.rx_par_err,

            # TX interface
            tx_bus=A10TxBus.from_prefix(dut, "host_tx_st"),
            # tx_par_err=dut.tx_par_err,
            )

        self.a10_soc_ep = A10PcieDevice(
            # configuration options
            pcie_generation=3,
            l_tile=False,
            pf_count=1,
            max_payload_size=512,
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

        self.host_rc.make_port().connect(self.a10_host_ep)
        self.soc_rc.make_port().connect(self.a10_soc_ep)
        self.a10_soc_ep.functions[0].configure_bar(0, 1024*1024*64, ext=True, prefetch=True)



        #cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        cocotb.start_soon(Clock(dut.clk_200m, 5, units="ns").start())
        cocotb.start_soon(Clock(dut.clk_50m, 20, units="ns").start())
        cocotb.start_soon(Clock(dut.clk_11m, 100, units="ns").start())

    def get_pcie_switch_down_stream_port_enable(self):
        return self.dut.u_dpu_top.u_dpu_role.u_pcie_switch_top.u_pcie_switch_cfg_space.down_stream_port_enable == 1

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

        #rst_sys_cr = cocotb.start_soon(rest(self.dut.rst, self.dut.clk))
        rst_11m_cr = cocotb.start_soon(rest(self.dut.rst_11m, self.dut.clk_11m))
        rst_50m_cr = cocotb.start_soon(rest(self.dut.rst_50m, self.dut.clk_50m))
        rst_200m_cr = cocotb.start_soon(rest(self.dut.rst_200m, self.dut.clk_200m))
        rst_user_cr = cocotb.start_soon(rest(self.dut.fpga_user_reset, self.dut.clk_200m))
        #await Join(rst_sys_cr)
        await Join(rst_11m_cr)
        await Join(rst_50m_cr)
        await Join(rst_200m_cr)
        await Join(rst_user_cr)

    async def init(self):
        await self.cycle_reset()
        await Timer(1, 'us')
        await self.soc_rc.enumerate()
        soc_dev = self.soc_rc.find_device(self.a10_soc_ep.functions[0].pcie_id)
        await soc_dev.enable_device()
        await soc_dev.set_master()
        await Timer(100, 'ns')
        '''
        dev_pf0_bar0 = soc_dev.bar_window[0]

        test_data = b'\x11\x22\x33\x44\x11\x22\x33\x44'
        await dev_pf0_bar0.write(0x800008, test_data)
        data = await dev_pf0_bar0.read(0x800008, 8)
        print(data.hex())

        test_data = b'\x11\x22\x33\x44\x11\x22\x33\x44'
        await dev_pf0_bar0.write(0xFFF008, test_data)
        data = await dev_pf0_bar0.read(0xFFF008, 8)
        print(data.hex())

        test_data = b'\x02\x00\x00\x00\x00\x00\x00\x00'
        await dev_pf0_bar0.write(0x800000, test_data)
        data = await dev_pf0_bar0.read(0x800000, 8)
        print(data.hex())

        await Timer(2, 'us')

        test_data = b'\x08\x00\x00\x00\x00\x00\x00\x00'
        await dev_pf0_bar0.write(0x800000, test_data)
        data = await dev_pf0_bar0.read(0x800000, 8)
        print(data.hex())
        '''
        dev_pf0_bar0 = soc_dev.bar_window[0]
   #     print(dir(self.dut.u_dpu_top))
        await Timer(100, 'ns')
        test_data = b'\x11\x22\x33\x44\x11\x22\x33\x44'
        await dev_pf0_bar0.write(0x800008, test_data)
        await dev_pf0_bar0.write(0x800008, test_data)
        await dev_pf0_bar0.write(0x800008, test_data)
        await dev_pf0_bar0.write(0x800008, test_data)
        data = await dev_pf0_bar0.read(0x800008, 8)
        print(data.hex())

        data = await dev_pf0_bar0.read(0x200248, 8)
        print(data.hex())
        data = await dev_pf0_bar0.read(0x200010, 8)
        print(data.hex())
        data = await dev_pf0_bar0.read(0x300248, 8)
        print(data.hex())
        data = await dev_pf0_bar0.read(0x300010, 8)
        print(data.hex())
#        test_data = b'\x55\x22\x33\x44\x11\x22\x55\x55'
#        await host_bar.write(0x800008, test_data)
#        data = await host_bar.read(0x800008, 8)
#        print(data.hex())
#
#        data = await host_bar.read(0x348, 8)
#        print(data.hex())



    def set_idle_generator(self, generator=None):
        if generator:
            pass

    def set_backpressure_generator(self, generator=None):
        if generator:
            pass

async def run_test(dut, idle_inserter, backpressure_inserter):
    random.seed(123)
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.init()
    #print(tb.get_pcie_switch_down_stream_port_enable())

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None])
        factory.add_option("backpressure_inserter", [None])
        factory.generate_tests()

#sys.path.append('../common'); from debug import *
root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)