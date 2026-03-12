#!/usr/bin/env python3
################################################################################
#  文件名称 : a10_model.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/10/14
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  10/14     Joe Jiang   初始化版本
################################################################################

import cocotb
from cocotb.clock import Clock
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First

from cocotbext.pcie.core import Device, Endpoint, __version__
from cocotbext.pcie.core.caps import MsiCapability, MsixCapability
from cocotbext.pcie.core.caps import AerExtendedCapability, PcieExtendedCapability
from cocotbext.pcie.core.utils import PcieId
from cocotbext.pcie.core.tlp import Tlp, TlpType

from .interface import A10PcieFrame, A10PcieSource, A10PcieSink


valid_configs = [
    # speed, links, width, freq
    (1,  1, 256, 125.0e6),
    (1,  2, 256, 125.0e6),
    (1,  4, 256, 125.0e6),
    (1,  8, 256, 125.0e6),
    (1, 16, 256, 125.0e6),
    (2,  1, 256, 125.0e6),
    (2,  2, 256, 125.0e6),
    (2,  4, 256, 125.0e6),
    (2,  8, 256, 125.0e6),
    (2, 16, 256, 250.0e6),
    (3,  1, 256, 125.0e6),
    (3,  2, 256, 125.0e6),
    (3,  4, 256, 125.0e6),
    (3,  8, 256, 250.0e6),
    (3, 16, 512, 250.0e6),
]


class A10PcieFunction(Endpoint):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        # PCIe capabilities
        self.register_capability(self.pm_cap, offset=0x10)

        self.msi_cap = MsiCapability()
        self.msi_cap.msi_64bit_address_capable = 1
        self.msi_cap.msi_per_vector_mask_capable = 0
        self.register_capability(self.msi_cap, offset=0x14)

        self.register_capability(self.pcie_cap, offset=0x1c)

        self.msix_cap = MsixCapability()
        self.register_capability(self.msix_cap, offset=0x2c)

        # PCIe extended capabilities
        self.aer_ext_cap = AerExtendedCapability()
        self.register_capability(self.aer_ext_cap, offset=0x40)

        # VC 0x4e
        # ARI 0x5e

        self.pcie_ext_cap = PcieExtendedCapability()
        self.register_capability(self.pcie_ext_cap, offset=0x62)

        # SRIOV 0x6e
        # TPH 0x7e
        # ATS 0xa1
        # VSEC (Intel) 0x2e0


def init_signal(sig, width=None, initval=None):
    if sig is None:
        return None
    if width is not None:
        assert len(sig) == width
    if initval is not None:
        sig.setimmediatevalue(initval)
    return sig


class A10PcieDevice(Device):
    def __init__(self,
            tlp_bypass = False,
            # configuration options
            pcie_generation=None,
            pcie_link_width=None,
            pld_clk_frequency=None,
            l_tile=False,
            pf_count=1,
            max_payload_size=128,
            enable_extended_tag=False,

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
            npor=None,
            pin_perst=None,
            ninit_done=None,
            pld_clk_inuse=None,
            pld_core_ready=None,
            reset_status=None,
            clr_st=None,
            refclk=None,
            coreclkout_hip=None,

            # RX interface
            rx_bus=None,

            # TX interface
            tx_bus=None,

            # TX flow control
            tx_ph_cdts=None,
            tx_pd_cdts=None,
            tx_nph_cdts=None,
            tx_npd_cdts=None,
            tx_cplh_cdts=None,
            tx_cpld_cdts=None,
            tx_hdr_cdts_consumed=None,
            tx_data_cdts_consumed=None,
            tx_cdts_type=None,
            tx_cdts_data_value=None,

            # Hard IP status
            int_status=None,
            int_status_common=None,
            derr_cor_ext_rpl=None,
            derr_rpl=None,
            derr_cor_ext_rcv=None,
            derr_uncor_ext_rcv=None,
            rx_par_err=None,
            tx_par_err=None,
            ltssmstate=None,
            link_up=None,
            lane_act=None,
            currentspeed=None,

            # Power management
            pm_linkst_in_l1=None,
            pm_linkst_in_l0s=None,
            pm_state=None,
            pm_dstate=None,
            apps_pm_xmt_pme=None,
            apps_ready_entr_l23=None,
            apps_pm_xmt_turnoff=None,
            app_init_rst=None,
            app_xfer_pending=None,

            # Interrupt interface
            app_msi_req=None,
            app_msi_ack=None,
            app_msi_tc=None,
            app_msi_num=None,
            app_msi_func_num=None,
            app_int_sts=None,

            # Error interface
            app_err_valid=None,
            app_err_hdr=None,
            app_err_info=None,
            app_err_func_num=None,

            # Configuration output
            tl_cfg_add=None,
            tl_cfg_ctl=None,

            # Configuration extension bus
            ceb_req=None,
            ceb_ack=None,
            ceb_addr=None,
            ceb_din=None,
            ceb_dout=None,
            ceb_wr=None,
            ceb_cdm_convert_data=None,
            ceb_func_num=None,
            ceb_vf_num=None,
            ceb_vf_active=None,

            # Hard IP reconfiguration interface
            hip_reconfig_clk=None,
            hip_reconfig_rst_n=None,
            hip_reconfig_address=None,
            hip_reconfig_read=None,
            hip_reconfig_readdata=None,
            hip_reconfig_readdatavalid=None,
            hip_reconfig_write=None,
            hip_reconfig_writedata=None,
            hip_reconfig_waitrequest=None,

            *args, **kwargs):

        super().__init__(*args, **kwargs)

        self.log.info("Intel Stratix 10 H-Tile/L-Tile PCIe hard IP core model")
        self.log.info("cocotbext-pcie version %s", __version__)
        self.log.info("Copyright (c) 2021 Alex Forencich")
        self.log.info("https://github.com/alexforencich/cocotbext-pcie")

        self.default_function = A10PcieFunction
        self.tlp_bypass = tlp_bypass

        self.dw = None

        self.rx_queue = Queue(maxsize=8)

        # configuration options
        self.pcie_generation = pcie_generation
        self.pcie_link_width = pcie_link_width
        self.pld_clk_frequency = pld_clk_frequency
        self.l_tile = l_tile
        self.pf_count = pf_count
        self.max_payload_size = max_payload_size
        self.enable_extended_tag = enable_extended_tag

        self.pf0_msi_enable = pf0_msi_enable
        self.pf0_msi_count = pf0_msi_count
        self.pf1_msi_enable = pf1_msi_enable
        self.pf1_msi_count = pf1_msi_count
        self.pf2_msi_enable = pf2_msi_enable
        self.pf2_msi_count = pf2_msi_count
        self.pf3_msi_enable = pf3_msi_enable
        self.pf3_msi_count = pf3_msi_count
        self.pf0_msix_enable = pf0_msix_enable
        self.pf0_msix_table_size = pf0_msix_table_size
        self.pf0_msix_table_bir = pf0_msix_table_bir
        self.pf0_msix_table_offset = pf0_msix_table_offset
        self.pf0_msix_pba_bir = pf0_msix_pba_bir
        self.pf0_msix_pba_offset = pf0_msix_pba_offset
        self.pf1_msix_enable = pf1_msix_enable
        self.pf1_msix_table_size = pf1_msix_table_size
        self.pf1_msix_table_bir = pf1_msix_table_bir
        self.pf1_msix_table_offset = pf1_msix_table_offset
        self.pf1_msix_pba_bir = pf1_msix_pba_bir
        self.pf1_msix_pba_offset = pf1_msix_pba_offset
        self.pf2_msix_enable = pf2_msix_enable
        self.pf2_msix_table_size = pf2_msix_table_size
        self.pf2_msix_table_bir = pf2_msix_table_bir
        self.pf2_msix_table_offset = pf2_msix_table_offset
        self.pf2_msix_pba_bir = pf2_msix_pba_bir
        self.pf2_msix_pba_offset = pf2_msix_pba_offset
        self.pf3_msix_enable = pf3_msix_enable
        self.pf3_msix_table_size = pf3_msix_table_size
        self.pf3_msix_table_bir = pf3_msix_table_bir
        self.pf3_msix_table_offset = pf3_msix_table_offset
        self.pf3_msix_pba_bir = pf3_msix_pba_bir
        self.pf3_msix_pba_offset = pf3_msix_pba_offset

        # signals

        # Clock and reset
        self.npor = init_signal(reset_status, 1)
        self.pin_perst = init_signal(pin_perst, 1)
        self.ninit_done = init_signal(ninit_done, 1)
        self.pld_clk_inuse = init_signal(pld_clk_inuse, 1, 0)
        self.pld_core_ready = init_signal(pld_core_ready, 1)
        self.reset_status = init_signal(reset_status, 1, 0)
        self.clr_st = init_signal(clr_st, 1, 0)
        self.refclk = init_signal(refclk, 1)
        self.coreclkout_hip = init_signal(coreclkout_hip, 1, 0)

        # RX interface
        self.rx_source = None

        if rx_bus is not None:
            self.rx_source = A10PcieSource(rx_bus, self.coreclkout_hip)
            self.rx_source.queue_occupancy_limit_frames = 2
            self.rx_source.ready_latency = 3
            self.dw = self.rx_source.width

        # TX interface
        self.tx_sink = None

        if tx_bus is not None:
            self.tx_sink = A10PcieSink(tx_bus, self.coreclkout_hip)
            self.tx_sink.queue_occupancy_limit_frames = 2
            self.tx_sink.ready_latency = 3
            self.dw = self.tx_sink.width

        # TX flow control
        self.tx_ph_cdts = init_signal(tx_ph_cdts, 8, 0)
        self.tx_pd_cdts = init_signal(tx_pd_cdts, 12, 0)
        self.tx_nph_cdts = init_signal(tx_nph_cdts, 8, 0)
        self.tx_cplh_cdts = init_signal(tx_cplh_cdts, 8, 0)
        if self.l_tile:
            self.tx_npd_cdts = init_signal(tx_npd_cdts, 12, 0)
            self.tx_cpld_cdts = init_signal(tx_cpld_cdts, 12, 0)
        # self.tx_hdr_cdts_consumed
        # self.tx_data_cdts_consumed
        # self.tx_cdts_type
        # self.tx_cdts_data_value

        # Hard IP status
        self.int_status = init_signal(int_status, 11, 0)
        self.int_status_common = init_signal(int_status_common, 3, 0)
        self.derr_cor_ext_rpl = init_signal(derr_cor_ext_rpl, 1, 0)
        self.derr_rpl = init_signal(derr_rpl, 1, 0)
        self.derr_cor_ext_rcv = init_signal(derr_cor_ext_rcv, 1, 0)
        self.derr_uncor_ext_rcv = init_signal(derr_uncor_ext_rcv, 1, 0)
        self.rx_par_err = init_signal(rx_par_err, 1, 0)
        self.tx_par_err = init_signal(tx_par_err, 1, 0)
        self.ltssmstate = init_signal(ltssmstate, 6, 0)
        self.link_up = init_signal(link_up, 1, 0)
        self.lane_act = init_signal(lane_act, 5, 0)
        self.currentspeed = init_signal(currentspeed, 2, 0)

        # Power management
        self.pm_linkst_in_l1 = init_signal(pm_linkst_in_l1, 1, 0)
        self.pm_linkst_in_l0s = init_signal(pm_linkst_in_l0s, 1, 0)
        self.pm_state = init_signal(pm_state, 3, 0)
        self.pm_dstate = init_signal(pm_dstate, 3, 0)
        self.apps_pm_xmt_pme = init_signal(apps_pm_xmt_pme, 1)
        self.apps_ready_entr_l23 = init_signal(apps_ready_entr_l23, 1)
        self.apps_pm_xmt_turnoff = init_signal(apps_pm_xmt_turnoff, 1)
        self.app_init_rst = init_signal(app_init_rst, 1)
        self.app_xfer_pending = init_signal(app_xfer_pending, 1)

        # Interrupt interface
        self.app_msi_req = init_signal(app_msi_req, 1)
        self.app_msi_ack = init_signal(app_msi_ack, 1, 0)
        self.app_msi_tc = init_signal(app_msi_tc, 3)
        self.app_msi_num = init_signal(app_msi_num, 5)
        self.app_msi_func_num = init_signal(app_msi_func_num, 2)
        self.app_int_sts = init_signal(app_int_sts, 4)

        # Error interface
        self.app_err_valid = init_signal(app_err_valid, 1)
        self.app_err_hdr = init_signal(app_err_hdr, 32)
        self.app_err_info = init_signal(app_err_info, 11)
        self.app_err_func_num = init_signal(app_err_func_num, 2)

        # Configuration output
        self.tl_cfg_add = init_signal(tl_cfg_add, 4, 0)
        self.tl_cfg_ctl = init_signal(tl_cfg_ctl, 32, 0)

        # Configuration intercept interface
        self.ceb_req = init_signal(ceb_req, 1, 0)
        self.ceb_ack = init_signal(ceb_ack, 1)
        self.ceb_addr = init_signal(ceb_addr, 12, 0)
        self.ceb_din = init_signal(ceb_din, 32)
        self.ceb_dout = init_signal(ceb_dout, 32, 0)
        self.ceb_wr = init_signal(ceb_wr, 4, 0)
        self.ceb_cdm_convert_data = init_signal(ceb_cdm_convert_data, 32)
        self.ceb_func_num = init_signal(ceb_func_num, 2, 0)
        self.ceb_vf_num = init_signal(ceb_vf_num, 11, 0)
        self.ceb_vf_active = init_signal(ceb_vf_active, 1, 0)

        # Hard IP reconfiguration interface
        self.hip_reconfig_clk = init_signal(hip_reconfig_clk, 1)
        self.hip_reconfig_rst_n = init_signal(hip_reconfig_rst_n, 1)
        self.hip_reconfig_address = init_signal(hip_reconfig_address, 21)
        self.hip_reconfig_read = init_signal(hip_reconfig_read, 1)
        self.hip_reconfig_readdata = init_signal(hip_reconfig_readdata, 8, 0)
        self.hip_reconfig_readdatavalid = init_signal(hip_reconfig_readdatavalid, 1, 0)
        self.hip_reconfig_write = init_signal(hip_reconfig_write, 1)
        self.hip_reconfig_writedata = init_signal(hip_reconfig_writedata, 8)
        self.hip_reconfig_waitrequest = init_signal(hip_reconfig_waitrequest, 1, 0)

        # validate parameters
        assert self.dw in {256, 512}

        # rescale clock frequency
        if self.pld_clk_frequency is not None and self.pld_clk_frequency < 1e6:
            self.pld_clk_frequency *= 1e6

        if not self.pcie_generation or not self.pcie_link_width or not self.pld_clk_frequency:
            self.log.info("Incomplete configuration specified, attempting to select reasonable options")
            # guess some reasonable values for unspecified parameters
            for config in reversed(valid_configs):
                # find configuration matching specified parameters
                if self.pcie_generation is not None and self.pcie_generation != config[0]:
                    continue
                if self.pcie_link_width is not None and self.pcie_link_width != config[1]:
                    continue
                if self.dw != config[2]:
                    continue
                if self.pld_clk_frequency is not None and self.pld_clk_frequency != config[3]:
                    continue

                # set the unspecified parameters
                if self.pcie_generation is None:
                    self.log.info("Setting PCIe speed to gen %d", config[0])
                    self.pcie_generation = config[0]
                if self.pcie_link_width is None:
                    self.log.info("Setting PCIe link width to x%d", config[1])
                    self.pcie_link_width = config[1]
                if self.pld_clk_frequency is None:
                    self.log.info("Setting user clock frequency to %d MHz", config[3]/1e6)
                    self.pld_clk_frequency = config[3]
                break

        self.log.info("Intel Stratix 10 H-Tile/L-Tile PCIe hard IP core configuration:")
        self.log.info("  PCIe speed: gen %d", self.pcie_generation)
        self.log.info("  PCIe link width: x%d", self.pcie_link_width)
        self.log.info("  PLD clock frequency: %d MHz", self.pld_clk_frequency/1e6)
        self.log.info("  Tile: %s", "L-Tile" if self.l_tile else "H-Tile")
        self.log.info("  PF count: %d", self.pf_count)
        self.log.info("  Max payload size: %d", self.max_payload_size)
        self.log.info("  Enable extended tag: %s", self.enable_extended_tag)
        self.log.info("  Enable PF0 MSI: %s", self.pf0_msi_enable)
        self.log.info("  PF0 MSI vector count: %d", self.pf0_msi_count)
        self.log.info("  Enable PF1 MSI: %s", self.pf1_msi_enable)
        self.log.info("  PF1 MSI vector count: %d", self.pf1_msi_count)
        self.log.info("  Enable PF2 MSI: %s", self.pf2_msi_enable)
        self.log.info("  PF2 MSI vector count: %d", self.pf2_msi_count)
        self.log.info("  Enable PF3 MSI: %s", self.pf3_msi_enable)
        self.log.info("  PF3 MSI vector count: %d", self.pf3_msi_count)
        self.log.info("  Enable PF0 MSIX: %s", self.pf0_msix_enable)
        self.log.info("  PF0 MSIX table size: %d", self.pf0_msix_table_size)
        self.log.info("  PF0 MSIX table BIR: %d", self.pf0_msix_table_bir)
        self.log.info("  PF0 MSIX table offset: 0x%08x", self.pf0_msix_table_offset)
        self.log.info("  PF0 MSIX PBA BIR: %d", self.pf0_msix_pba_bir)
        self.log.info("  PF0 MSIX PBA offset: 0x%08x", self.pf0_msix_pba_offset)
        self.log.info("  Enable PF1 MSIX: %s", self.pf1_msix_enable)
        self.log.info("  PF1 MSIX table size: %d", self.pf1_msix_table_size)
        self.log.info("  PF1 MSIX table BIR: %d", self.pf1_msix_table_bir)
        self.log.info("  PF1 MSIX table offset: 0x%08x", self.pf1_msix_table_offset)
        self.log.info("  PF1 MSIX PBA BIR: %d", self.pf1_msix_pba_bir)
        self.log.info("  PF1 MSIX PBA offset: 0x%08x", self.pf1_msix_pba_offset)
        self.log.info("  Enable PF2 MSIX: %s", self.pf2_msix_enable)
        self.log.info("  PF2 MSIX table size: %d", self.pf2_msix_table_size)
        self.log.info("  PF2 MSIX table BIR: %d", self.pf2_msix_table_bir)
        self.log.info("  PF2 MSIX table offset: 0x%08x", self.pf2_msix_table_offset)
        self.log.info("  PF2 MSIX PBA BIR: %d", self.pf2_msix_pba_bir)
        self.log.info("  PF2 MSIX PBA offset: 0x%08x", self.pf2_msix_pba_offset)
        self.log.info("  Enable PF3 MSIX: %s", self.pf3_msix_enable)
        self.log.info("  PF3 MSIX table size: %d", self.pf3_msix_table_size)
        self.log.info("  PF3 MSIX table BIR: %d", self.pf3_msix_table_bir)
        self.log.info("  PF3 MSIX table offset: 0x%08x", self.pf3_msix_table_offset)
        self.log.info("  PF3 MSIX PBA BIR: %d", self.pf3_msix_pba_bir)
        self.log.info("  PF3 MSIX PBA offset: 0x%08x", self.pf3_msix_pba_offset)

        assert self.pcie_generation in {1, 2, 3}
        assert self.pcie_link_width in {1, 2, 4, 8, 16}
        assert self.pld_clk_frequency in {125e6, 250e6}

        # check for valid configuration
        config_valid = False
        for config in valid_configs:
            if self.pcie_generation != config[0]:
                continue
            if self.pcie_link_width != config[1]:
                continue
            if self.dw != config[2]:
                continue
            if self.pld_clk_frequency != config[3]:
                continue

            config_valid = True
            break

        assert config_valid, "link speed/link width/clock speed/interface width setting combination not valid"

        # configure port
        self.upstream_port.max_link_speed = self.pcie_generation
        self.upstream_port.max_link_width = self.pcie_link_width

        # configure functions
        if not self.tlp_bypass:
            self.make_function()

            if self.pf0_msi_enable:
                self.functions[0].msi_cap.msi_multiple_message_capable = (self.pf0_msi_count-1).bit_length()
            else:
                self.functions[0].deregister_capability(self.functions[0].msi_cap)

            if self.pf0_msix_enable:
                self.functions[0].msix_cap.msix_table_size = self.pf0_msix_table_size
                self.functions[0].msix_cap.msix_table_bar_indicator_register = self.pf0_msix_table_bir
                self.functions[0].msix_cap.msix_table_offset = self.pf0_msix_table_offset
                self.functions[0].msix_cap.msix_pba_bar_indicator_register = self.pf0_msix_pba_bir
                self.functions[0].msix_cap.msix_pba_offset = self.pf0_msix_pba_offset
            else:
                self.functions[0].deregister_capability(self.functions[0].msix_cap)

            if self.pf_count > 1:
                self.make_function()

                if self.pf1_msi_enable:
                    self.functions[1].msi_cap.msi_multiple_message_capable = (self.pf1_msi_count-1).bit_length()
                else:
                    self.functions[1].deregister_capability(self.functions[1].msi_cap)

                if self.pf1_msix_enable:
                    self.functions[1].msix_cap.msix_table_size = self.pf1_msix_table_size
                    self.functions[1].msix_cap.msix_table_bar_indicator_register = self.pf1_msix_table_bir
                    self.functions[1].msix_cap.msix_table_offset = self.pf1_msix_table_offset
                    self.functions[1].msix_cap.msix_pba_bar_indicator_register = self.pf1_msix_pba_bir
                    self.functions[1].msix_cap.msix_pba_offset = self.pf1_msix_pba_offset
                else:
                    self.functions[1].deregister_capability(self.functions[1].msix_cap)

            if self.pf_count > 2:
                self.make_function()

                if self.pf2_msi_enable:
                    self.functions[2].msi_cap.msi_multiple_message_capable = (self.pf2_msi_count-2).bit_length()
                else:
                    self.functions[2].deregister_capability(self.functions[2].msi_cap)

                if self.pf2_msix_enable:
                    self.functions[2].msix_cap.msix_table_size = self.pf2_msix_table_size
                    self.functions[2].msix_cap.msix_table_bar_indicator_register = self.pf2_msix_table_bir
                    self.functions[2].msix_cap.msix_table_offset = self.pf2_msix_table_offset
                    self.functions[2].msix_cap.msix_pba_bar_indicator_register = self.pf2_msix_pba_bir
                    self.functions[2].msix_cap.msix_pba_offset = self.pf2_msix_pba_offset
                else:
                    self.functions[2].deregister_capability(self.functions[2].msix_cap)

            if self.pf_count > 3:
                self.make_function()

                if self.pf3_msi_enable:
                    self.functions[3].msi_cap.msi_multiple_message_capable = (self.pf3_msi_count-3).bit_length()
                else:
                    self.functions[3].deregister_capability(self.functions[3].msi_cap)

                if self.pf3_msix_enable:
                    self.functions[3].msix_cap.msix_table_size = self.pf3_msix_table_size
                    self.functions[3].msix_cap.msix_table_bar_indicator_register = self.pf3_msix_table_bir
                    self.functions[3].msix_cap.msix_table_offset = self.pf3_msix_table_offset
                    self.functions[3].msix_cap.msix_pba_bar_indicator_register = self.pf3_msix_pba_bir
                    self.functions[3].msix_cap.msix_pba_offset = self.pf3_msix_pba_offset
                else:
                    self.functions[3].deregister_capability(self.functions[3].msix_cap)

        for f in self.functions:
            f.pcie_cap.max_payload_size_supported = (self.max_payload_size//128-1).bit_length()
            f.pcie_cap.extended_tag_supported = self.enable_extended_tag

        # fork coroutines

        if self.coreclkout_hip is not None:
            cocotb.start_soon(Clock(self.coreclkout_hip, int(1e9/self.pld_clk_frequency), units="ns").start())

        if self.rx_source:
            cocotb.start_soon(self._run_rx_logic())
        if self.tx_sink:
            cocotb.start_soon(self._run_tx_logic())
        if self.tx_pd_cdts:
            cocotb.start_soon(self._run_tx_fc_logic())
        if self.app_msi_req:
            cocotb.start_soon(self._run_int_logic())
        if self.tl_cfg_ctl:
            cocotb.start_soon(self._run_cfg_out_logic_a10())

        cocotb.start_soon(self._run_reset())

    async def upstream_recv(self, tlp):
        self.log.debug("Got downstream TLP: %r", tlp)

        if tlp.fmt_type in {TlpType.CFG_READ_0, TlpType.CFG_WRITE_0}:
            # config type 0
            # capture address information
            self.bus_num = tlp.dest_id.bus
            # pass TLP to function
            for f in self.functions:
                if f.pcie_id == tlp.dest_id: 
                    await f.upstream_recv(tlp)
                    return
            if self.tlp_bypass:
                frame = A10PcieFrame.from_tlp(tlp)
                frame.func_num = tlp.requester_id.function
                await self.rx_queue.put(frame)
                tlp.release_fc()
                return
            tlp.release_fc()
            self.log.warning("Function not found: failed to route config type 0 TLP: %r", tlp)
        elif tlp.fmt_type in {TlpType.CFG_READ_1, TlpType.CFG_WRITE_1}:
            # config type 1
            if self.tlp_bypass:
                frame = A10PcieFrame.from_tlp(tlp)
                frame.func_num = tlp.requester_id.function
                await self.rx_queue.put(frame)
                tlp.release_fc()
                return
            tlp.release_fc()
            self.log.warning("Malformed TLP: endpoint received config type 1 TLP: %r", tlp)
        elif tlp.fmt_type in {TlpType.CPL, TlpType.CPL_DATA, TlpType.CPL_LOCKED, TlpType.CPL_LOCKED_DATA}:
            # Completion
            for f in self.functions:
                if f.pcie_id == tlp.requester_id:
                    frame = A10PcieFrame.from_tlp(tlp)
                    frame.func_num = tlp.requester_id.function
                    await self.rx_queue.put(frame)
                    tlp.release_fc()
                    return
            if self.tlp_bypass:
                frame = A10PcieFrame.from_tlp(tlp)
                frame.func_num = tlp.requester_id.function
                await self.rx_queue.put(frame)
                tlp.release_fc()
                return
            tlp.release_fc()
            self.log.warning("Unexpected completion: failed to route completion to function: %r", tlp)
            return  # no UR response for completion
        elif tlp.fmt_type in {TlpType.IO_READ, TlpType.IO_WRITE}:
            # IO read/write
            for f in self.functions:
                bar = f.match_bar(tlp.address, True)
                if bar:
                    frame = A10PcieFrame.from_tlp(tlp)
                    frame.bar_range = 6
                    frame.func_num = tlp.requester_id.function
                    await self.rx_queue.put(frame)
                    tlp.release_fc()
                    return
            tlp.release_fc()
            self.log.warning("No BAR match: IO request did not match any BARs: %r", tlp)
        elif tlp.fmt_type in {TlpType.MEM_READ, TlpType.MEM_READ_64, TlpType.MEM_WRITE, TlpType.MEM_WRITE_64}:
            # Memory read/write
            for f in self.functions:
                bar = f.match_bar(tlp.address)
                if bar:
                    frame = A10PcieFrame.from_tlp(tlp)
                    frame.bar_range = bar[0]
                    frame.func_num = tlp.requester_id.function
                    await self.rx_queue.put(frame)
                    tlp.release_fc()
                    return
            if self.tlp_bypass:
                frame = A10PcieFrame.from_tlp(tlp)
                await self.rx_queue.put(frame)
                tlp.release_fc()
                return

            tlp.release_fc()

            if tlp.fmt_type in {TlpType.MEM_WRITE, TlpType.MEM_WRITE_64}:
                self.log.warning("No BAR match: memory write request did not match any BARs: %r", tlp)
                return  # no UR response for write request
            else:
                self.log.warning("No BAR match: memory read request did not match any BARs: %r", tlp)
        else:
            raise Exception("TODO")

        # Unsupported request
        cpl = Tlp.create_ur_completion_for_tlp(tlp, PcieId(self.bus_num, 0, 0))
        self.log.debug("UR Completion: %r", cpl)
        await self.upstream_send(cpl)

    def set_idle_generator(self, generator=None):
        if generator:
            if self.rx_source is not None:
                self.rx_source.set_pause_generator(generator())
    def set_backpressure_generator(self, generator=None):
        if generator:
            if self.tx_sink is not None:
                self.tx_sink.set_pause_generator(generator())

    async def _run_reset(self):
        clock_edge_event = RisingEdge(self.coreclkout_hip)

        while True:
            await clock_edge_event
            await clock_edge_event

            if self.pld_clk_inuse is not None:
                self.pld_clk_inuse.value = 1
            if self.reset_status is not None:
                self.reset_status.value = 1
            if self.clr_st is not None:
                self.clr_st.value = 1

            if self.pin_perst is not None:
                if not self.pin_perst.value:
                    await RisingEdge(self.pin_perst)
                await First(FallingEdge(self.pin_perst), Timer(100, 'ns'))
                await First(FallingEdge(self.pin_perst), RisingEdge(self.coreclkout_hip))
                if not self.pin_perst.value:
                    continue
            else:
                await Timer(100, 'ns')
                await clock_edge_event

            if self.pld_clk_inuse is not None:
                self.pld_clk_inuse.value = 0
            if self.reset_status is not None:
                self.reset_status.value = 0
            if self.clr_st is not None:
                self.clr_st.value = 0

            if self.pin_perst is not None:
                await FallingEdge(self.pin_perst)
            else:
                return

    async def _run_rx_logic(self):
        while True:
            frame = await self.rx_queue.get()
            await self.rx_source.send(frame)

    async def _run_tx_logic(self):
        while True:
            frame = await self.tx_sink.recv()
            tlp = frame.to_tlp()
            #self.log.debug("tlp_data_length %r", len(tlp.data))
            #self.log.debug("tlp_length %r", tlp.length)
            await self.send(tlp)

    async def _run_tx_fc_logic(self):
        clock_edge_event = RisingEdge(self.coreclkout_hip)

        while True:
            if self.tx_ph_cdts is not None:
                self.tx_ph_cdts.value = self.upstream_port.fc_state[0].ph.tx_credits_available & 0xff
            if self.tx_pd_cdts is not None:
                self.tx_pd_cdts.value = self.upstream_port.fc_state[0].pd.tx_credits_available & 0xfff
            if self.tx_nph_cdts is not None:
                self.tx_nph_cdts.value = self.upstream_port.fc_state[0].nph.tx_credits_available & 0xff
            if self.tx_cplh_cdts is not None:
                self.tx_cplh_cdts.value = self.upstream_port.fc_state[0].cplh.tx_credits_available & 0xff
            if self.l_tile:
                if self.tx_npd_cdts is not None:
                    self.tx_npd_cdts.value = self.upstream_port.fc_state[0].npd.tx_credits_available & 0xfff
                if self.tx_cpld_cdts is not None:
                    self.tx_cpld_cdts.value = self.upstream_port.fc_state[0].cpld.tx_credits_available & 0xfff
            # self.tx_hdr_cdts_consumed
            # self.tx_data_cdts_consumed
            # self.tx_cdts_type
            # self.tx_cdts_data_value
            await clock_edge_event

    async def _run_status_logic(self):
        pass

        # Hard IP status
        # int_status
        # int_status_common
        # derr_cor_ext_rpl
        # derr_rpl
        # derr_cor_ext_rcv
        # derr_uncor_ext_rcv
        # rx_par_err
        # tx_par_err
        # ltssmstate
        # link_up
        # lane_act
        # currentspeed

    async def _run_pm_logic(self):
        pass

        # Power management
        # pm_linkst_in_l1
        # pm_linkst_in_l0s
        # pm_state
        # pm_dstate
        # apps_pm_xmt_pme
        # apps_ready_entr_l23
        # apps_pm_xmt_turnoff
        # app_init_rst
        # app_xfer_pending

    async def _run_int_logic(self):
        clock_edge_event = RisingEdge(self.coreclkout_hip)

        while True:
            await clock_edge_event

            # Interrupt interface
            while not self.app_msi_req.value.integer:
                await RisingEdge(self.app_msi_req)
                await clock_edge_event

            # issue MSI interrupt
            app_msi_func_num = self.app_msi_func_num.value.integer
            app_msi_num = self.app_msi_num.value.integer
            app_msi_tc = self.app_msi_tc.value.integer
            if not self.tlp_bypass:
                await self.functions[app_msi_func_num].msi_cap.issue_msi_interrupt(app_msi_num, tc=app_msi_tc)

            self.app_msi_ack.value = 1
            await clock_edge_event
            self.app_msi_ack.value = 0

            while self.app_msi_req.value.integer:
                await clock_edge_event

    # Error interface
    # app_err_valid
    # app_err_hdr
    # app_err_info
    # app_err_func_num

    async def _run_cfg_out_logic_a10(self):
        import numpy
        clock_edge_event = RisingEdge(self.coreclkout_hip)
        while True:
            if not self.tlp_bypass:
                for func in self.functions:
                    cfg_dev_ctrl  = (int(numpy.log2(self.max_payload_size)-7) & 0x7) << 5
                    cfg_dev_ctrl |=  self.enable_extended_tag << 8
                    cfg_dev_ctrl |=  (int(numpy.log2(4096)-7) & 0x7) << 12


                    cfg_busdev  = (func.pcie_id.bus & 0xff) << 5
                    cfg_busdev |= (func.pcie_id.device & 0x1f)

                    self.tl_cfg_add.value = 0x00
                    val = cfg_dev_ctrl << 16
                    self.tl_cfg_ctl.value = val
                    await clock_edge_event

                    for i in range(1, 15):
                        self.tl_cfg_add.value = i
                        self.tl_cfg_ctl.value = 0
                        await clock_edge_event


                    self.tl_cfg_add.value = 0x0f
                    val = cfg_busdev & 0x1FFF
                    self.tl_cfg_ctl.value = val
                    await clock_edge_event
            else:
                cfg_dev_ctrl  = (int(numpy.log2(self.max_payload_size)-7) & 0x7) << 5
                cfg_dev_ctrl |=  self.enable_extended_tag << 8
                cfg_dev_ctrl |=  (int(numpy.log2(4096)-7) & 0x7) << 12
                cfg_busdev  = (0 & 0xff) << 5
                cfg_busdev |= (0 & 0x1f)
                self.tl_cfg_add.value = 0x00
                val = cfg_dev_ctrl << 16
                self.tl_cfg_ctl.value = val
                await clock_edge_event
                for i in range(1, 15):
                    self.tl_cfg_add.value = i
                    self.tl_cfg_ctl.value = 0
                    await clock_edge_event
                self.tl_cfg_add.value = 0x0f
                val = cfg_busdev & 0x1FFF
                self.tl_cfg_ctl.value = val
                await clock_edge_event

    # Configuration extension bus
    # ceb_req
    # ceb_ack
    # ceb_addr
    # ceb_din
    # ceb_dout
    # ceb_wr
    # ceb_cdm_convert_data
    # ceb_func_num
    # ceb_vf_num
    # ceb_vf_active

    # Hard IP reconfiguration interface
    # hip_reconfig_clk
    # hip_reconfig_rst_n
    # hip_reconfig_address
    # hip_reconfig_read
    # hip_reconfig_readdata
    # hip_reconfig_readdatavalid
    # hip_reconfig_write
    # hip_reconfig_writedata
    # hip_reconfig_waitrequest
