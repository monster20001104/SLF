###########################################
# 文件名称 : test_host_tlp_tracing_tb
# 作者名称 : 崔飞翔
# 创建日期 : 2025/08/27
# 功能描述 : 
# 
# 修改记录 : 
# 
# 修改日期 : 2025/08/27
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
from cocotb.queue import Queue
from cocotb.triggers import Combine
 
sys.path.append('../common')

from bus.mlite_bus      import MliteBus
from drivers.mlite_bus  import MliteBusMaster
from bus.tlp_adap_bypass_bus import TlpBypassBus,OpCode
from drivers.tlp_adap_bypass_bus import TlpBypassMaster

from test_tlptype import *

class AVST256QW_2ch_Interface:
    def __init__(self, dut, data_signal_name: str = "tx_st_data", 
                 sop_signal_name: str = "tx_st_sop", 
                 eop_signal_name: str = "tx_st_eop", 
                 valid_signal_name: str = "tx_st_valid"):
        self.dut = dut
        self.data_signal = getattr(dut, data_signal_name)
        self.sop_signal = getattr(dut, sop_signal_name)
        self.eop_signal = getattr(dut, eop_signal_name)
        self.valid_signal = getattr(dut, valid_signal_name)

    async def send_transaction(self, transaction: AVST256QW_2ch_t):
        self.data_signal.value = transaction.data.data
        self.sop_signal.value = transaction.sop
        self.eop_signal.value = transaction.eop
        self.valid_signal.value = transaction.valid
        await RisingEdge(self.dut.clk)

    def idle_bus(self):
        self.data_signal.value = 0
        self.sop_signal.value = 0
        self.eop_signal.value = 0
        self.valid_signal.value = 0

def create_mem_read_32_tlp(addr: int, length_dw: int, req_id: int = 0, tag: int = 0) -> TlpHeader:
    tlp = TlpHeader()
    tlp.set_tlp_type(TlpType.MEM_READ)
    tlp.dw0.length_dw = length_dw
    
    tlp.dw1 = TlpHeader_DW1_Req_t(
        req_id=req_id,
        tag=tag,
        last_be=0xF,  # 所有字节使能
        first_be=0xF  # 所有字节使能
    )
    
    tlp.dw2 = TlpHeader_DW2_Req32b_t(
        addr_low_dw=addr >> 2,  # 地址需要右移2位（DW对齐）
        ph=0b00
    )
    
    return tlp

def create_mem_read_64_tlp(addr: int, length_dw: int, req_id: int = 0, tag: int = 0) -> TlpHeader:
    tlp = TlpHeader()
    tlp.set_tlp_type(TlpType.MEM_READ_64)
    tlp.dw0.length_dw = length_dw
    
    tlp.dw1 = TlpHeader_DW1_Req_t(
        req_id=req_id,
        tag=tag,
        last_be=0xF, 
        first_be=0xF  
    )
    tlp.dw2 = TlpHeader_DW2_Req64b_t(
        addr_high=addr >> 32  
    )
    tlp.dw3 = TlpHeader_DW3_Req64b_t(
        addr_low_dw=(addr & 0xFFFFFFFF) >> 2,  
        ph=0b00
    )
    
    return tlp

def create_mem_write_32_tlp(addr: int, length_dw: int, req_id: int = 0, tag: int = 0) -> TlpHeader:
    tlp = TlpHeader()
    tlp.set_tlp_type(TlpType.MEM_WRITE)
    tlp.dw0.length_dw = length_dw
    
    tlp.dw1 = TlpHeader_DW1_Req_t(
        req_id=req_id,
        tag=tag,
        last_be=0xF,  # 所有字节使能
        first_be=0xF  # 所有字节使能
    )
    
    tlp.dw2 = TlpHeader_DW2_Req32b_t(
        addr_low_dw=addr >> 2,  # 地址需要右移2位（DW对齐）
        ph=0b00
    )
    
    return tlp

def create_mem_write_64_tlp(addr: int, length_dw: int, req_id: int = 0, tag: int = 0) -> TlpHeader:
    tlp = TlpHeader()
    tlp.set_tlp_type(TlpType.MEM_WRITE_64)
    tlp.dw0.length_dw = length_dw
    
    tlp.dw1 = TlpHeader_DW1_Req_t(
        req_id=req_id,
        tag=tag,
        last_be=0xF,  # 所有字节使能
        first_be=0xF  # 所有字节使能
    )
    
    tlp.dw2 = TlpHeader_DW2_Req64b_t(
        addr_high=addr >> 32  # 高32位地址
    )
    
    tlp.dw3 = TlpHeader_DW3_Req64b_t(
        addr_low_dw=(addr & 0xFFFFFFFF) >> 2,  # 低32位地址，右移2位
        ph=0b00
    )
    
    return tlp

def create_cpl_tlp(req_id: int, tag: int, 
                  cpl_id: int = 0, cpl_status: int = 0) -> TlpHeader:
    tlp = TlpHeader()
    tlp.set_tlp_type(TlpType.CPL)
    tlp.dw0.length_dw = 0
    tlp.dw1 = TlpHeader_DW1_CplD_t(
        cpl_id=cpl_id,
        cpl_status=cpl_status,
        bcm=0,
        byte_count=0
    )
    
    tlp.dw2 = TlpHeader_DW2_CplD_t(
        req_id=req_id,
        tag=tag,
        reserved_b7=0,
        lower_addr=0  # 根据实际情况设置
    )
    
    return tlp

def create_cpl_data_tlp(req_id: int, tag: int, byte_count: int, lower_addr: int,
                       cpl_id: int = 0, cpl_status: int = 0) -> TlpHeader:
    tlp = TlpHeader()
    tlp.set_tlp_type(TlpType.CPL_DATA)
    tlp.dw0.length_dw = 0
    tlp.dw1 = TlpHeader_DW1_CplD_t(
        cpl_id=cpl_id,
        cpl_status=cpl_status,
        bcm=0,
        byte_count=byte_count
    )
    
    tlp.dw2 = TlpHeader_DW2_CplD_t(
        req_id=req_id,
        tag=tag,
        reserved_b7=0,
        lower_addr=lower_addr  # 根据实际情况设置
    )
    return tlp

def flush_queue(q):
    try:
        while True:
            q.get_nowait()
    except cocotb.queue.QueueEmpty:
        pass

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb")
        self.log.setLevel(logging.INFO)
        self.tlpBypass = TlpBypassMaster(TlpBypassBus.from_prefix(dut, "tlp_bypass"), dut.clk, dut.rst)
        self.tx_st_avst = AVST256QW_2ch_Interface(dut, "tx_st_data", "tx_st_sop", "tx_st_eop", "tx_st_valid")
        self.milte_master = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk, dut.rst)
        self.send_transaction = AVST256QW_2ch_t()
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.opcode_numbers = [OpCode.MWr,OpCode.MRd,OpCode.CFGRd0,OpCode.CFGRd1,OpCode.CFGWr0,OpCode.CFGWr1,OpCode.CplD,OpCode.Cpl]
        self.mem_be_numbers = [1,2,3,4,6,7,8,12,14,15]
        self.cfg_be_number = [1,2,3,4,8,12,15]
        self.rx_loop_send_list = [None] * 1024
        self.tx_loop_send_list = [None] * 1024
        self.rx_send_tlp_q = Queue(maxsize=8192)
        self.tx_send_tlp_q = Queue(maxsize=8192)
        self.tx_flag          = 1
        self.tx_mrd_flag      = 1
        self.tx_mwr_flag      = 1
        self.tx_cpl_cpld_flag = 1
        self.rx_flag          = 1
        self.rx_mrd_flag      = 1
        self.rx_mwr_flag      = 1
        self.rx_cpl_cpld_flag = 1
        self.rx_cfg_flag      = 1
        self.start_flag       = 0
        self.loop_start_flag  = 1
        self.stop_flag        = 0
        self.tx_stop_flag     = 0
        self.rx_stop_flag     = 0
        self.tx_cnt           = 0
        self.rx_cnt           = 0


    def setup_channel_tlp(self, channel, tlp, sop=True, eop=True, valid=True):
        if channel not in [0, 1]:
            raise ValueError("channel must 0 or 1")
        
        if valid == True:
            dwords = tlp.to_dwords()
            data = dwords[0] | (dwords[1] << 32) | (dwords[2] << 64) | (dwords[3] << 96)
        else:
            data = 0
        
        self.send_transaction.set_channel_data(channel, data)
        self.send_transaction.set_channel_sop(channel, sop)
        self.send_transaction.set_channel_eop(channel, eop)
        self.send_transaction.set_channel_valid(channel, valid)
    
    def setup_dual_channel_tlp(self, tlp_ch0, tlp_ch1, 
                              sop_ch0=True, eop_ch0=True, valid_ch0=True,
                              sop_ch1=True, eop_ch1=True, valid_ch1=True):
        self.setup_channel_tlp(0, tlp_ch0, sop_ch0, eop_ch0, valid_ch0)
        self.setup_channel_tlp(1, tlp_ch1, sop_ch1, eop_ch1, valid_ch1)

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
    
    async def csr_init(self,tx_flag,tx_mrd_flag,tx_mwr_flag,tx_cpl_cpld_flag,rx_flag,rx_mrd_flag,rx_mwr_flag,rx_cpl_cpld_flag,rx_cfg_flag,start_flag,loop_start_flag):
        self.tx_flag          = tx_flag         
        self.tx_mrd_flag      = tx_mrd_flag     
        self.tx_mwr_flag      = tx_mwr_flag     
        self.tx_cpl_cpld_flag = tx_cpl_cpld_flag
        self.rx_flag          = rx_flag         
        self.rx_mrd_flag      = rx_mrd_flag     
        self.rx_mwr_flag      = rx_mwr_flag     
        self.rx_cpl_cpld_flag = rx_cpl_cpld_flag
        self.rx_cfg_flag      = rx_cfg_flag     
        self.start_flag       = start_flag  
        self.loop_start_flag  = loop_start_flag    
        switch_list = [
            self.tx_flag         ,
            self.tx_mrd_flag     ,
            self.tx_mwr_flag     ,
            self.tx_cpl_cpld_flag,
            self.rx_flag         ,
            self.rx_mrd_flag     ,
            self.rx_mwr_flag     ,
            self.rx_cpl_cpld_flag,
            self.rx_cfg_flag     ,
            self.start_flag      ,
            self.loop_start_flag
            ]
        for i in range(len(switch_list)):
            if switch_list[i] == 1:
                await self.milte_master.read(0x0000_0000 + i*0x8)

    async def tracing_stop(self):
            await self.milte_master.read(0x0000_0000 + 0x58)    

    async def send_tx(self, max_seq):
        i = 0
        while i < max_seq:
            i = i + 1
            length_dw = random.getrandbits(10)
            addr_64 = random.getrandbits(64)
            addr_32 = random.getrandbits(32)
            tag  = random.getrandbits(8)
            req_id = random.getrandbits(16)
            cpl_id = random.getrandbits(16)
            byte_count = random.getrandbits(12)
            cpl_status = random.getrandbits(3)
            lower_addr = random.getrandbits(7)
            random_num1 = random.randint(0,1)
            random_num2 = random.randint(0,1)
            random_num3 = random.randint(0,1)
            random_num4 = random.randint(0,1)
            random_num5 = random.randint(0,5)
            if random_num1 == 0:
                tlp_mem_read = create_mem_read_32_tlp(addr=addr_32, length_dw=length_dw, req_id=req_id, tag=tag)
            else :
                tlp_mem_read = create_mem_read_64_tlp(addr=addr_64, length_dw=length_dw, req_id=req_id, tag=tag)

            if random_num2 == 0:
                tlp_mem_write = create_mem_write_32_tlp(addr=addr_32, length_dw=length_dw, req_id=req_id, tag=tag)
            else :
                tlp_mem_write = create_mem_write_64_tlp(addr=addr_64, length_dw=length_dw, req_id=req_id, tag=tag)
            if random_num3 == 0:
                tlp_cpl = create_cpl_tlp(req_id=req_id, tag=tag, cpl_id=cpl_id, cpl_status=cpl_status)
            else :
                tlp_cpl = create_cpl_data_tlp(req_id=req_id, tag=tag, byte_count=byte_count,lower_addr = lower_addr ,cpl_id=cpl_id, cpl_status=cpl_status)
            if random_num5 == 0:
                tlp_chn0 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn1 = tlp_mem_write
                else:
                    tlp_chn1 = tlp_cpl                        
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                            sop_ch0=True, eop_ch0=True, valid_ch0=True, 
                                            sop_ch1=True, eop_ch1=True, valid_ch1=True)
                if self.tx_mrd_flag ==1 and self.tx_mwr_flag ==1 and self.tx_cpl_cpld_flag == 1 : 
                    await self.tx_send_tlp_q.put(tlp_chn0)
                    await self.tx_send_tlp_q.put(tlp_chn1)
                    self.tx_cnt = self.tx_cnt + 2
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 : 
                    await self.tx_send_tlp_q.put(tlp_chn0)
                    self.tx_cnt = self.tx_cnt + 1
                    if random_num4 == 0:
                        await self.tx_send_tlp_q.put(tlp_chn1)
                        self.tx_cnt = self.tx_cnt + 1   
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :                 
                    await self.tx_send_tlp_q.put(tlp_chn0)
                    self.tx_cnt = self.tx_cnt + 1
                    if random_num4 == 1:
                        await self.tx_send_tlp_q.put(tlp_chn1)
                        self.tx_cnt = self.tx_cnt + 1
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 0 :
                    await self.tx_send_tlp_q.put(tlp_chn0)
                    self.tx_cnt = self.tx_cnt + 1
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 1 :
                    await self.tx_send_tlp_q.put(tlp_chn1)
                    self.tx_cnt = self.tx_cnt + 1
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 :
                    if random_num4 == 0:
                        await self.tx_send_tlp_q.put(tlp_chn1)
                        self.tx_cnt = self.tx_cnt + 1  
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :
                    if random_num4 == 1:
                        await self.tx_send_tlp_q.put(tlp_chn1)
                        self.tx_cnt = self.tx_cnt + 1  

            elif random_num5 == 1:
                tlp_chn1 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn0 = tlp_mem_write
                else:
                    tlp_chn0 = tlp_cpl    
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                                sop_ch0=True, eop_ch0=True, valid_ch0=True, 
                                                sop_ch1=True, eop_ch1=True, valid_ch1=True)
                if self.tx_mrd_flag ==1 and self.tx_mwr_flag ==1 and self.tx_cpl_cpld_flag == 1 : 
                    await self.tx_send_tlp_q.put(tlp_chn0)
                    await self.tx_send_tlp_q.put(tlp_chn1)
                    self.tx_cnt = self.tx_cnt + 2
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 : 
                    if random_num4 == 0:
                        await self.tx_send_tlp_q.put(tlp_chn0)
                        self.tx_cnt = self.tx_cnt + 1  
                    await self.tx_send_tlp_q.put(tlp_chn1)
                    self.tx_cnt = self.tx_cnt + 1 
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :                 
                    if random_num4 == 1:
                        await self.tx_send_tlp_q.put(tlp_chn0)
                        self.tx_cnt = self.tx_cnt + 1
                    await self.tx_send_tlp_q.put(tlp_chn1)
                    self.tx_cnt = self.tx_cnt + 1
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 0 :
                    await self.tx_send_tlp_q.put(tlp_chn1)
                    self.tx_cnt = self.tx_cnt + 1
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 1 :
                    await self.tx_send_tlp_q.put(tlp_chn0)
                    self.tx_cnt = self.tx_cnt + 1
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 :
                    if random_num4 == 0:
                        await self.tx_send_tlp_q.put(tlp_chn0) 
                        self.tx_cnt = self.tx_cnt + 1 
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :
                    if random_num4 == 1:
                        await self.tx_send_tlp_q.put(tlp_chn0)
                        self.tx_cnt = self.tx_cnt + 1  

            elif random_num5 == 2:
                tlp_chn0 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn1 = tlp_mem_write
                else:
                    tlp_chn1 = tlp_cpl                        
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                            sop_ch0=True, eop_ch0=True, valid_ch0=True, 
                                            sop_ch1=False, eop_ch1=False, valid_ch1=False)
                if self.tx_mrd_flag == 1 : 
                    await self.tx_send_tlp_q.put(tlp_chn0)
                    self.tx_cnt = self.tx_cnt + 1

            elif random_num5 == 3:
                tlp_chn1 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn0 = tlp_mem_write
                else:
                    tlp_chn0 = tlp_cpl    
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                                sop_ch0=True, eop_ch0=True, valid_ch0=True, 
                                                sop_ch1=False, eop_ch1=False, valid_ch1=False)
                if self.tx_mwr_flag ==1 and self.tx_cpl_cpld_flag == 1 : 
                    await self.tx_send_tlp_q.put(tlp_chn0)
                    self.tx_cnt = self.tx_cnt + 1
                elif self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 : 
                    if random_num4 == 0:
                        await self.tx_send_tlp_q.put(tlp_chn0)
                        self.tx_cnt = self.tx_cnt + 1   
                elif self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :                 
                    if random_num4 == 1:
                        await self.tx_send_tlp_q.put(tlp_chn0)
                        self.tx_cnt = self.tx_cnt + 1

            elif random_num5 == 4:
                tlp_chn0 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn1 = tlp_mem_write
                else:
                    tlp_chn1 = tlp_cpl                        
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                            sop_ch0=False, eop_ch0=False, valid_ch0=False, 
                                            sop_ch1=True, eop_ch1=True, valid_ch1=True)
                if self.tx_mwr_flag ==1 and self.tx_cpl_cpld_flag == 1 : 
                    await self.tx_send_tlp_q.put(tlp_chn1)
                    self.tx_cnt = self.tx_cnt + 1
                elif self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 : 
                    if random_num4 == 0:
                        await self.tx_send_tlp_q.put(tlp_chn1)   
                        self.tx_cnt = self.tx_cnt + 1
                elif self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :                 
                    if random_num4 == 1:
                        await self.tx_send_tlp_q.put(tlp_chn1)
                        self.tx_cnt = self.tx_cnt + 1

            elif random_num5 == 5:
                tlp_chn1 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn0 = tlp_mem_write
                else:
                    tlp_chn0 = tlp_cpl    
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                                sop_ch0=False, eop_ch0=False, valid_ch0=False, 
                                                sop_ch1=True, eop_ch1=True, valid_ch1=True)
                if self.tx_mrd_flag == 1 : 
                    await self.tx_send_tlp_q.put(tlp_chn1)
                    self.tx_cnt = self.tx_cnt + 1

            await self.tx_st_avst.send_transaction(self.send_transaction)
            self.log.info("self.tx_cnt  {}".format(self.tx_cnt ))
        self.tx_st_avst.idle_bus()

    async def loop_send_tx(self, max_seq,index_modulo=1024):
        i = 0
        list_index = 0
        while i < max_seq:
            length_dw = random.getrandbits(10)
            addr_64 = random.getrandbits(64)
            addr_32 = random.getrandbits(32)
            tag  = random.getrandbits(8)
            req_id = random.getrandbits(16)
            cpl_id = random.getrandbits(16)
            byte_count = random.getrandbits(12)
            cpl_status = random.getrandbits(3)
            lower_addr = random.getrandbits(7)
            random_num1 = random.randint(0,1)
            random_num2 = random.randint(0,1)
            random_num3 = random.randint(0,1)
            random_num4 = random.randint(0,1)
            random_num5 = random.randint(0,5)
            if random_num1 == 0:
                tlp_mem_read = create_mem_read_32_tlp(addr=addr_32, length_dw=length_dw, req_id=req_id, tag=tag)
            else :
                tlp_mem_read = create_mem_read_64_tlp(addr=addr_64, length_dw=length_dw, req_id=req_id, tag=tag)

            if random_num2 == 0:
                tlp_mem_write = create_mem_write_32_tlp(addr=addr_32, length_dw=length_dw, req_id=req_id, tag=tag)
            else :
                tlp_mem_write = create_mem_write_64_tlp(addr=addr_64, length_dw=length_dw, req_id=req_id, tag=tag)
            if random_num3 == 0:
                tlp_cpl = create_cpl_tlp(req_id=req_id, tag=tag, cpl_id=cpl_id, cpl_status=cpl_status)
            else :
                tlp_cpl = create_cpl_data_tlp(req_id=req_id, tag=tag, byte_count=byte_count,lower_addr = lower_addr ,cpl_id=cpl_id, cpl_status=cpl_status)
            if random_num5 == 0:
                tlp_chn0 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn1 = tlp_mem_write
                else:
                    tlp_chn1 = tlp_cpl                        
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                            sop_ch0=True, eop_ch0=True, valid_ch0=True, 
                                            sop_ch1=True, eop_ch1=True, valid_ch1=True)
                if self.tx_mrd_flag ==1 and self.tx_mwr_flag ==1 and self.tx_cpl_cpld_flag == 1 :
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                    list_index = list_index + 1
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                    list_index = list_index + 1
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 : 
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                    list_index = list_index + 1
                    if random_num4 == 0:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                        list_index = list_index + 1  
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :                 
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                    list_index = list_index + 1
                    if random_num4 == 1:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                        list_index = list_index + 1  
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 0 :
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                    list_index = list_index + 1
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 1 :
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                    list_index = list_index + 1  
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 :
                    if random_num4 == 0:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                        list_index = list_index + 1  
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :
                    if random_num4 == 1:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                        list_index = list_index + 1  

            elif random_num5 == 1:
                tlp_chn1 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn0 = tlp_mem_write
                else:
                    tlp_chn0 = tlp_cpl    
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                                sop_ch0=True, eop_ch0=True, valid_ch0=True, 
                                                sop_ch1=True, eop_ch1=True, valid_ch1=True)
                if self.tx_mrd_flag ==1 and self.tx_mwr_flag ==1 and self.tx_cpl_cpld_flag == 1 : 
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                    list_index = list_index + 1
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                    list_index = list_index + 1
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 : 
                    if random_num4 == 0:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                        list_index = list_index + 1
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                    list_index = list_index + 1
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :                 
                    if random_num4 == 1:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                        list_index = list_index + 1
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                    list_index = list_index + 1
                elif self.tx_mrd_flag == 1 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 0 :
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                    list_index = list_index + 1
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 1 :
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                    list_index = list_index + 1
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 :
                    if random_num4 == 0:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                        list_index = list_index + 1
                elif self.tx_mrd_flag == 0 and self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :
                    if random_num4 == 1:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                        list_index = list_index + 1
            elif random_num5 == 2:
                tlp_chn0 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn1 = tlp_mem_write
                else:
                    tlp_chn1 = tlp_cpl                        
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                            sop_ch0=True, eop_ch0=True, valid_ch0=True, 
                                            sop_ch1=False, eop_ch1=False, valid_ch1=False)
                if self.tx_mrd_flag == 1 : 
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                    list_index = list_index + 1

            elif random_num5 == 3:
                tlp_chn1 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn0 = tlp_mem_write
                else:
                    tlp_chn0 = tlp_cpl    
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                                sop_ch0=True, eop_ch0=True, valid_ch0=True, 
                                                sop_ch1=False, eop_ch1=False, valid_ch1=False)
                if self.tx_mwr_flag ==1 and self.tx_cpl_cpld_flag == 1 : 
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                    list_index = list_index + 1
                elif self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 : 
                    if random_num4 == 0:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                        list_index = list_index + 1
                elif self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :                 
                    if random_num4 == 1:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn0
                        list_index = list_index + 1

            elif random_num5 == 4:
                tlp_chn0 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn1 = tlp_mem_write
                else:
                    tlp_chn1 = tlp_cpl                        
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                            sop_ch0=False, eop_ch0=False, valid_ch0=False, 
                                            sop_ch1=True, eop_ch1=True, valid_ch1=True)
                if self.tx_mwr_flag ==1 and self.tx_cpl_cpld_flag == 1 : 
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                    list_index = list_index + 1
                elif self.tx_mwr_flag == 1 and self.tx_cpl_cpld_flag == 0 : 
                    if random_num4 == 0:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                        list_index = list_index + 1
                elif self.tx_mwr_flag == 0 and self.tx_cpl_cpld_flag == 1 :                 
                    if random_num4 == 1:
                        self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                        list_index = list_index + 1

            elif random_num5 == 5:
                tlp_chn1 = tlp_mem_read
                if random_num4 == 0:
                    tlp_chn0 = tlp_mem_write
                else:
                    tlp_chn0 = tlp_cpl    
                self.setup_dual_channel_tlp(tlp_chn0,tlp_chn1,
                                                sop_ch0=False, eop_ch0=False, valid_ch0=False, 
                                                sop_ch1=True, eop_ch1=True, valid_ch1=True)
                if self.tx_mrd_flag == 1 : 
                    self.tx_loop_send_list[list_index%index_modulo] = tlp_chn1
                    list_index = list_index + 1

            await self.tx_st_avst.send_transaction(self.send_transaction)
            self.log.info("list_index  {}".format(list_index%index_modulo))
            i = i + 1
        self.tx_st_avst.idle_bus()

    async def tx_tlp_cmp(self, max_seq):
        for i in range(2*max_seq):
            group      = i // 4
            grp_offset = group * 0x10  
            base = 0x0004_0000 if ((i // 2) & 1 == 0) else 0x0004_2000
            offset_in_pair = (i % 2) * 0x8
            addr = base + grp_offset + offset_in_pair
            data64 = await self.milte_master.read(addr)
            if i%2 == 0:
                lo64 = data64
            elif i%2 == 1:
                hi64 = data64
                data128 = (hi64 << 64) | lo64
                rev_tlp_type = (data128 >> 106) & 0xf
                rev_tlp_length_dw = (data128 >> 96) & 0x3ff
                rev_mem_tlp_tag = (data128 >> 72) & 0xff
                rev_cpl_tlp_tag = (data128 >> 40) & 0xff
                tlp = await self.tx_send_tlp_q.get()
                self.log.info("tlp {}".format(tlp))
                if tlp.tlp_type in [TlpType.CPL]:
                    assert rev_tlp_type == 0b0101
                    assert tlp.dw0.length_dw == rev_tlp_length_dw
                    assert tlp.dw2.tag == rev_cpl_tlp_tag  
                elif tlp.tlp_type in [TlpType.CPL_DATA]:
                    assert rev_tlp_type == 0b0100
                    assert tlp.dw0.length_dw == rev_tlp_length_dw
                    assert tlp.dw2.tag == rev_cpl_tlp_tag
                elif tlp.tlp_type in [TlpType.MEM_READ]:
                    assert rev_tlp_type == 0b0001
                    assert tlp.dw0.length_dw == rev_tlp_length_dw
                    assert tlp.dw1.tag == rev_mem_tlp_tag
                elif tlp.tlp_type in [TlpType.MEM_WRITE]:
                    assert rev_tlp_type == 0b0011
                    assert tlp.dw0.length_dw == rev_tlp_length_dw 
                    assert tlp.dw1.tag == rev_mem_tlp_tag             
                elif tlp.tlp_type in [TlpType.MEM_READ_64]:
                    assert rev_tlp_type == 0b0001
                    assert tlp.dw0.length_dw == rev_tlp_length_dw
                    assert tlp.dw1.tag == rev_mem_tlp_tag  
                elif tlp.tlp_type in [TlpType.MEM_WRITE_64]:
                    assert rev_tlp_type == 0b0011
                    assert tlp.dw0.length_dw == rev_tlp_length_dw 
                    assert tlp.dw1.tag == rev_mem_tlp_tag   

    async def loop_tx_tlp_cmp(self, max_seq):
        list_index = 0
        for i in range(max_seq):
            group      = i // 4
            grp_offset = group * 0x10  
            base = 0x0004_0000 if ((i // 2) & 1 == 0) else 0x0004_2000
            offset_in_pair = (i % 2) * 0x8
            addr = base + grp_offset + offset_in_pair
            data64 = await self.milte_master.read(addr)
            if i%2 == 0:
                lo64 = data64
            elif i%2 == 1:
                hi64 = data64
                data128 = (hi64 << 64) | lo64
                rev_tlp_type = (data128 >> 106) & 0xf
                rev_tlp_length_dw = (data128 >> 96) & 0x3ff
                rev_mem_tlp_tag = (data128 >> 72) & 0xff
                rev_cpl_tlp_tag = (data128 >> 40) & 0xff
                tlp = self.tx_loop_send_list[list_index]
                list_index = list_index + 1
                self.log.info("tlp {}".format(tlp))
                if tlp.tlp_type in [TlpType.CPL]:
                    assert rev_tlp_type == 0b0101
                    assert tlp.dw0.length_dw == rev_tlp_length_dw
                    assert tlp.dw2.tag == rev_cpl_tlp_tag  
                elif tlp.tlp_type in [TlpType.CPL_DATA]:
                    assert rev_tlp_type == 0b0100
                    assert tlp.dw0.length_dw == rev_tlp_length_dw
                    assert tlp.dw2.tag == rev_cpl_tlp_tag
                elif tlp.tlp_type in [TlpType.MEM_READ]:
                    assert rev_tlp_type == 0b0001
                    assert tlp.dw0.length_dw == rev_tlp_length_dw
                    assert tlp.dw1.tag == rev_mem_tlp_tag
                elif tlp.tlp_type in [TlpType.MEM_WRITE]:
                    assert rev_tlp_type == 0b0011
                    assert tlp.dw0.length_dw == rev_tlp_length_dw 
                    assert tlp.dw1.tag == rev_mem_tlp_tag             
                elif tlp.tlp_type in [TlpType.MEM_READ_64]:
                    assert rev_tlp_type == 0b0001
                    assert tlp.dw0.length_dw == rev_tlp_length_dw
                    assert tlp.dw1.tag == rev_mem_tlp_tag  
                elif tlp.tlp_type in [TlpType.MEM_WRITE_64]:
                    assert rev_tlp_type == 0b0011
                    assert tlp.dw0.length_dw == rev_tlp_length_dw 
                    assert tlp.dw1.tag == rev_mem_tlp_tag   

    async def send_rx(self,max_seq):
        i = 0
        while i < max_seq:
            i = i + 1
            opcode = random.choice(self.opcode_numbers)
            tag = random.randint(0,255)
            dest_id = 0
            ext_reg_num = 0
            reg_num = 0
            cpl_status = ComplStatus.SC
            cpl_id = 0x222
            if opcode == OpCode.MRd:
                addr = random.randint(0,(2**32)-1)
                cpl_byte_count = 0
                byte_length = random.randint(1,1024) * 4  
                data = bytes(0x0)             
                if byte_length + addr > 2**32-1:
                    byte_length = (2**32-1-addr)//8
                dest_id = 0
                req_id = 1
                reg_num = 0
                ext_reg_num = 0
                first_be = random.choice(self.mem_be_numbers)
                if byte_length > 4:
                    last_be = random.choice(self.mem_be_numbers)
                else:
                    last_be = 0
            elif opcode == OpCode.MWr:
                addr = random.randint(0,(2**32)-1)
                byte_length = random.randint(1,10) * 4
                cpl_byte_count = 0
                if byte_length + addr > 2**32-1:
                    byte_length = (2**32-1-addr)//8
                data = bytes(random.getrandbits(8) for _ in range(byte_length))
                dest_id = 0
                req_id = 1
                reg_num = 0
                ext_reg_num = 0
                first_be = random.choice(self.mem_be_numbers)
                if byte_length > 4:
                    last_be = random.choice(self.mem_be_numbers)
                else:
                    last_be = 0
            elif opcode in [OpCode.CFGRd0, OpCode.CFGRd1]:
                addr = 0
                byte_length = 4
                cpl_byte_count = 0
                first_be = random.choice(self.cfg_be_number)
                last_be = 0
                req_id = 1
                dest_id = 0
                ext_reg_num = 0
                reg_num = 0
                data = bytes(0x0) 
            elif opcode in [OpCode.CFGWr0, OpCode.CFGWr1]:
                addr = 0
                byte_length = 4
                cpl_byte_count = 0
                first_be = random.choice(self.cfg_be_number)
                last_be = 0
                req_id = 1
                data = bytes([0x01,0x02,0x03])
            elif opcode == OpCode.CplD:
                addr = random.randint(0,3)
                byte_length = random.randint(1,10) * 4
                cpl_byte_count = byte_length
                cpl_id = 0x222
                req_id = 1
                cpl_status = ComplStatus.SC
                first_be = 0
                last_be = 0
                data = bytes(random.getrandbits(8) for _ in range(byte_length))
            elif opcode == OpCode.Cpl:
                addr = 0
                byte_length = 0
                cpl_byte_count = byte_length
                cpl_id = 0x222
                req_id = 1
                cpl_status = ComplStatus.SC
                first_be = 0
                last_be = 0
                data = bytes(0x0)
            req = TlpBypassReq(opcode, addr, cpl_byte_count, byte_length, tag, cpl_id, req_id, cpl_status, first_be, last_be,dest_id,ext_reg_num,reg_num, data, None)
            await self.rx_send_tlp_q.put(req)
            await self.tlpBypass.send_req(req,0)
            self.rx_cnt  = self.rx_cnt  + 1
            self.log.info("self.rx_cnt  {}".format(self.rx_cnt ))

    async def loop_send_rx(self,max_seq,index_modulo=1024):
        i = 0
        while i < max_seq:
            opcode = random.choice(self.opcode_numbers)
            tag = random.randint(0,255)
            dest_id = 0
            ext_reg_num = 0
            reg_num = 0
            cpl_status = ComplStatus.SC
            cpl_id = 0x222
            if opcode == OpCode.MRd:
                addr = random.randint(0,(2**32)-1)
                cpl_byte_count = 0
                byte_length = random.randint(1,1024) * 4  
                data = bytes(0x0)             
                if byte_length + addr > 2**32-1:
                    byte_length = (2**32-1-addr)//8
                dest_id = 0
                req_id = 1
                reg_num = 0
                ext_reg_num = 0
                first_be = random.choice(self.mem_be_numbers)
                if byte_length > 4:
                    last_be = random.choice(self.mem_be_numbers)
                else:
                    last_be = 0
            elif opcode == OpCode.MWr:
                addr = random.randint(0,(2**32)-1)
                byte_length = random.randint(1,10) * 4
                cpl_byte_count = 0
                if byte_length + addr > 2**32-1:
                    byte_length = (2**32-1-addr)//8
                data = bytes(random.getrandbits(8) for _ in range(byte_length))
                dest_id = 0
                req_id = 1
                reg_num = 0
                ext_reg_num = 0
                first_be = random.choice(self.mem_be_numbers)
                if byte_length > 4:
                    last_be = random.choice(self.mem_be_numbers)
                else:
                    last_be = 0
            elif opcode in [OpCode.CFGRd0, OpCode.CFGRd1]:
                addr = 0
                byte_length = 4
                cpl_byte_count = 0
                first_be = random.choice(self.cfg_be_number)
                last_be = 0
                req_id = 1
                dest_id = 0
                ext_reg_num = 0
                reg_num = 0
                data = bytes(0x0) 
            elif opcode in [OpCode.CFGWr0, OpCode.CFGWr1]:
                addr = 0
                byte_length = 4
                cpl_byte_count = 0
                first_be = random.choice(self.cfg_be_number)
                last_be = 0
                req_id = 1
                data = bytes([0x01,0x02,0x03])
            elif opcode == OpCode.CplD:
                addr = random.randint(0,3)
                byte_length = random.randint(1,10) * 4
                cpl_byte_count = byte_length
                cpl_id = 0x222
                req_id = 1
                cpl_status = ComplStatus.SC
                first_be = 0
                last_be = 0
                data = bytes(random.getrandbits(8) for _ in range(byte_length))
            elif opcode == OpCode.Cpl:
                addr = 0
                byte_length = 0
                cpl_byte_count = byte_length
                cpl_id = 0x222
                req_id = 1
                cpl_status = ComplStatus.SC
                first_be = 0
                last_be = 0
                data = bytes(0x0)
            req = TlpBypassReq(opcode, addr, cpl_byte_count, byte_length, tag, cpl_id, req_id, cpl_status, first_be, last_be,dest_id,ext_reg_num,reg_num, data, None)
            index = i % index_modulo
            self.rx_loop_send_list[index] = req
            await self.tlpBypass.send_req(req,0)
            self.log.info("rx_i  {}".format(index ))
            i = i + 1

    async def rx_tlp_cmp(self, max_seq):
        for i in range(2*max_seq):
            addr = 0x0004_4000 + i*0x8 
            data64 = await self.milte_master.read(addr)
            if i%2 == 0:
                lo64 = data64
            elif i%2 == 1:
                hi64 = data64
                data128 = (hi64 << 64) | lo64
                rev_tlp_type = (data128 >> 106) & 0xf
                rev_tlp_length_dw = (data128 >> 96) & 0x3ff
                rev_mem_tlp_tag = (data128 >> 72) & 0xff
                rev_cpl_cfg_tlp_tag = (data128 >> 40) & 0xff
                req = await self.rx_send_tlp_q.get()
                self.log.info("tlp {}".format(req))
                if req.op_code in [OpCode.Cpl]:
                    assert rev_tlp_type == 0b0101
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_cpl_cfg_tlp_tag
                elif req.op_code in [OpCode.CplD]:
                    assert rev_tlp_type == 0b0100
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_cpl_cfg_tlp_tag
                elif req.op_code in [OpCode.MRd]:
                    assert rev_tlp_type == 0b0001
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_mem_tlp_tag
                elif req.op_code in [OpCode.MWr]:
                    assert rev_tlp_type == 0b0011
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw 
                    assert req.tag == rev_mem_tlp_tag     
                elif req.op_code in [OpCode.CFGRd0]:
                    assert rev_tlp_type == 0b1100
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_cpl_cfg_tlp_tag
                elif req.op_code in [OpCode.CFGRd1]:
                    assert rev_tlp_type == 0b1101
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_cpl_cfg_tlp_tag
                elif req.op_code in [OpCode.CFGWr0]:
                    assert rev_tlp_type == 0b1110
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw 
                    assert req.tag == rev_cpl_cfg_tlp_tag       
                elif req.op_code in [OpCode.CFGWr1]:
                    assert rev_tlp_type == 0b0000
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw 
                    assert req.tag == rev_cpl_cfg_tlp_tag      

    async def loop_rx_tlp_cmp(self, max_seq):
        list_index = 0
        for i in range(max_seq):
            addr = 0x44000 + i*0x8
            data64 = await self.milte_master.read(addr)
            if i%2 == 0:
                lo64 = data64
            elif i%2 == 1:
                hi64 = data64
                data128 = (hi64 << 64) | lo64
                rev_tlp_type = (data128 >> 106) & 0xf
                rev_tlp_length_dw = (data128 >> 96) & 0x3ff
                rev_mem_tlp_tag = (data128 >> 72) & 0xff
                rev_cpl_cfg_tlp_tag = (data128 >> 40) & 0xff
                req = self.rx_loop_send_list[list_index]
                list_index = list_index + 1
                self.log.info("tlp {}".format(req))
                if req.op_code in [OpCode.Cpl]:
                    assert rev_tlp_type == 0b0101
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_cpl_cfg_tlp_tag
                elif req.op_code in [OpCode.CplD]:
                    assert rev_tlp_type == 0b0100
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_cpl_cfg_tlp_tag
                elif req.op_code in [OpCode.MRd]:
                    assert rev_tlp_type == 0b0001
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_mem_tlp_tag
                elif req.op_code in [OpCode.MWr]:
                    assert rev_tlp_type == 0b0011
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw 
                    assert req.tag == rev_mem_tlp_tag     
                elif req.op_code in [OpCode.CFGRd0]:
                    assert rev_tlp_type == 0b1100
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_cpl_cfg_tlp_tag
                elif req.op_code in [OpCode.CFGRd1]:
                    assert rev_tlp_type == 0b1101
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw
                    assert req.tag == rev_cpl_cfg_tlp_tag
                elif req.op_code in [OpCode.CFGWr0]:
                    assert rev_tlp_type == 0b1110
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw 
                    assert req.tag == rev_cpl_cfg_tlp_tag       
                elif req.op_code in [OpCode.CFGWr1]:
                    assert rev_tlp_type == 0b0000
                    if int(rev_tlp_length_dw) == 0:
                        rev_tlp_length_dw = 1024
                    assert (req.byte_length>>2) == rev_tlp_length_dw 
                    assert req.tag == rev_cpl_cfg_tlp_tag      


async def run_test(dut,seed):
    random.seed(seed)
    tb = TB(dut)
    loop_cnt = 100
    await tb.cycle_reset()
    await tb.loop_send_rx(5000)
    await tb.loop_send_tx(5000)
    await Timer(500, 'ns')
    await tb.tracing_stop()
    tracing_stat = await tb.milte_master.read(0x100)
    rx_tracing_cnt = (tracing_stat >> 12) & 0x3ff
    rx_multiple_loop_flag_store = (tracing_stat >> 1) & 0x1
    tx_tracing_cnt = (tracing_stat >> 2) & 0x3ff
    tx_multiple_loop_flag_store = tracing_stat & 0x1    
    tb.log.info("tracing_stat {}".format(tracing_stat))
    tb.log.info("rx_tracing_cnt {}".format(rx_tracing_cnt))
    tb.log.info("rx_multiple_loop_flag {}".format(rx_multiple_loop_flag_store))
    tb.log.info("tx_tracing_cnt {}".format(tx_tracing_cnt))
    tb.log.info("tx_multiple_loop_flag {}".format(tx_multiple_loop_flag_store))
    if rx_multiple_loop_flag_store == 1:
        rx_loop_max_seq = 2048
    else :
        rx_loop_max_seq = int(rx_tracing_cnt)*2
    if tx_multiple_loop_flag_store == 1:
        tx_loop_max_seq = 2048
    else :
        tx_loop_max_seq = int(tx_tracing_cnt)*2
    await tb.loop_rx_tlp_cmp(rx_loop_max_seq)
    await tb.loop_tx_tlp_cmp(tx_loop_max_seq)
    await Timer(50, 'ns')

    for loop in range(loop_cnt):
        tb.log.info(f"===== loop {loop} =====")
        await tb.csr_init(tx_flag = 1,tx_mrd_flag = 1,tx_mwr_flag = 1,tx_cpl_cpld_flag = 1,
                          rx_flag = 1,rx_mrd_flag = 1,rx_mwr_flag = 1,rx_cpl_cpld_flag = 1,rx_cfg_flag = 1,start_flag = 0,loop_start_flag = 1)
        await tb.loop_send_rx(5000)
        await tb.loop_send_tx(5000)
        await Timer(500, 'ns')
        await tb.tracing_stop()
        await Timer(50, 'ns')
        tracing_stat = await tb.milte_master.read(0x100)
        rx_tracing_cnt = (tracing_stat >> 12) & 0x3ff
        rx_multiple_loop_flag_store = (tracing_stat >> 1) & 0x1
        tx_tracing_cnt = (tracing_stat >> 2) & 0x3ff
        tx_multiple_loop_flag_store = tracing_stat & 0x1    
        tb.log.info("tracing_stat {}".format(tracing_stat))
        tb.log.info("rx_tracing_cnt {}".format(rx_tracing_cnt))
        tb.log.info("rx_multiple_loop_flag {}".format(rx_multiple_loop_flag_store))
        tb.log.info("tx_tracing_cnt {}".format(tx_tracing_cnt))
        tb.log.info("tx_multiple_loop_flag {}".format(tx_multiple_loop_flag_store))
        if rx_multiple_loop_flag_store == 1:
            rx_loop_max_seq = 2048
        else :
            rx_loop_max_seq = int(rx_tracing_cnt)*2
        if tx_multiple_loop_flag_store == 1:
            tx_loop_max_seq = 2048
        else :
            tx_loop_max_seq = int(tx_tracing_cnt)*2
        await tb.loop_rx_tlp_cmp(rx_loop_max_seq)
        await tb.loop_tx_tlp_cmp(tx_loop_max_seq)
        await Timer(50, 'ns')

    for loop in range(loop_cnt):
        tb.log.info(f"===== loop {loop} =====")
        await tb.csr_init(tx_flag = 1,tx_mrd_flag = 1,tx_mwr_flag = 1,tx_cpl_cpld_flag = 1,
                          rx_flag = 0,rx_mrd_flag = 1,rx_mwr_flag = 1,rx_cpl_cpld_flag = 1,rx_cfg_flag = 1,start_flag = 0,loop_start_flag = 1)
        await tb.loop_send_tx(5000)
        await Timer(50, 'ns')
        await tb.tracing_stop()
        await Timer(50, 'ns')
        tracing_stat = await tb.milte_master.read(0x100)
        tx_tracing_cnt = (tracing_stat >> 2) & 0x3ff
        tx_multiple_loop_flag_store = tracing_stat & 0x1    
        tb.log.info("tracing_stat {}".format(tracing_stat))
        tb.log.info("tx_tracing_cnt {}".format(tx_tracing_cnt))
        tb.log.info("tx_multiple_loop_flag {}".format(tx_multiple_loop_flag_store))
        if tx_multiple_loop_flag_store == 1:
            tx_loop_max_seq = 2048
        else :
            tx_loop_max_seq = int(tx_tracing_cnt)*2
        await tb.loop_tx_tlp_cmp(tx_loop_max_seq)
        await Timer(50, 'ns')

    for loop in range(loop_cnt):
        tb.log.info(f"===== loop {loop} =====")
        await tb.csr_init(tx_flag = 0,tx_mrd_flag = 1,tx_mwr_flag = 1,tx_cpl_cpld_flag = 1,
                          rx_flag = 1,rx_mrd_flag = 1,rx_mwr_flag = 1,rx_cpl_cpld_flag = 1,rx_cfg_flag = 1,start_flag = 0,loop_start_flag = 1)
        await tb.loop_send_rx(5000)
        await Timer(500, 'ns')
        await tb.tracing_stop()
        await Timer(500, 'ns')
        tracing_stat = await tb.milte_master.read(0x100)
        rx_tracing_cnt = (tracing_stat >> 12) & 0x3ff
        rx_multiple_loop_flag_store = (tracing_stat >> 1) & 0x1
        tb.log.info("tracing_stat {}".format(tracing_stat))
        tb.log.info("rx_tracing_cnt {}".format(rx_tracing_cnt))
        tb.log.info("rx_multiple_loop_flag {}".format(rx_multiple_loop_flag_store))
        if rx_multiple_loop_flag_store == 1:
            rx_loop_max_seq = 2048
        else :
            rx_loop_max_seq = int(rx_tracing_cnt)*2
        await tb.loop_rx_tlp_cmp(rx_loop_max_seq)
        await Timer(50, 'ns')

    for loop in range(loop_cnt):
        tb.log.info(f"===== loop {loop} =====")
        await tb.csr_init(tx_flag = 1,tx_mrd_flag = 1,tx_mwr_flag = 1,tx_cpl_cpld_flag = 1,
                          rx_flag = 1,rx_mrd_flag = 1,rx_mwr_flag = 1,rx_cpl_cpld_flag = 1,rx_cfg_flag = 1,start_flag =1,loop_start_flag=0)
        max_seq = 2100
        rx_task = cocotb.start_soon(tb.send_rx(max_seq))
        tx_task = cocotb.start_soon(tb.send_tx(max_seq))
        await Combine(rx_task, tx_task)
        await Timer(500, 'ns')
        await tb.tracing_stop()
        await Timer(500, 'ns')
        tracing_stat = await tb.milte_master.read(0x100)
        rx_tracing_cnt = (tracing_stat >> 12) & 0x3ff
        tx_tracing_cnt = (tracing_stat >> 2) & 0x3ff
        tb.log.info("tx_tracing_cnt {}".format(int(tx_tracing_cnt)))
        tb.log.info("rx_tracing_cnt {}".format(int(rx_tracing_cnt)))
        await tb.tx_tlp_cmp(int(tx_tracing_cnt))
        await Timer(50, 'ns')
        await tb.rx_tlp_cmp(int(rx_tracing_cnt))
        await Timer(50, 'ns')
        flush_queue(tb.rx_send_tlp_q)
        flush_queue(tb.tx_send_tlp_q)
        await Timer(50, 'ns')

    for loop in range(loop_cnt):
        tb.log.info(f"===== loop {loop} =====")
        await tb.csr_init(tx_flag = 0,tx_mrd_flag = 1,tx_mwr_flag = 1,tx_cpl_cpld_flag = 1,
                          rx_flag = 1,rx_mrd_flag = 1,rx_mwr_flag = 1,rx_cpl_cpld_flag = 1,rx_cfg_flag = 1,start_flag =1,loop_start_flag=0)
        max_seq = 2100
        rx_task = cocotb.start_soon(tb.send_rx(max_seq))
        tx_task = cocotb.start_soon(tb.send_tx(max_seq))
        await Combine(rx_task, tx_task)
        await Timer(500, 'ns')
        await tb.tracing_stop()
        await Timer(500, 'ns')
        tracing_stat = await tb.milte_master.read(0x100)
        rx_tracing_cnt = (tracing_stat >> 12) & 0x3ff
        tb.log.info("tx_tracing_cnt {}".format(int(tx_tracing_cnt)))
        tb.log.info("rx_tracing_cnt {}".format(int(rx_tracing_cnt)))
        await tb.rx_tlp_cmp(int(rx_tracing_cnt))
        await Timer(50, 'ns')
        flush_queue(tb.rx_send_tlp_q)
        flush_queue(tb.tx_send_tlp_q)
        await Timer(50, 'ns')

    for loop in range(loop_cnt):
        tb.log.info(f"===== loop {loop} =====")
        await tb.csr_init(tx_flag = 1,tx_mrd_flag = 1,tx_mwr_flag = 1,tx_cpl_cpld_flag = 1,
                          rx_flag = 0,rx_mrd_flag = 1,rx_mwr_flag = 1,rx_cpl_cpld_flag = 1,rx_cfg_flag = 1,start_flag =1,loop_start_flag=0)
        max_seq = 2100
        rx_task = cocotb.start_soon(tb.send_rx(max_seq))
        tx_task = cocotb.start_soon(tb.send_tx(max_seq))
        await Combine(rx_task, tx_task)
        await Timer(50, 'ns')
        await tb.tracing_stop()
        await Timer(50, 'ns')
        tracing_stat = await tb.milte_master.read(0x100)
        tx_tracing_cnt = (tracing_stat >> 2) & 0x3ff
        tb.log.info("tx_tracing_cnt {}".format(int(tx_tracing_cnt)))
        await tb.tx_tlp_cmp(int(tx_tracing_cnt))
        await Timer(50, 'ns')
        flush_queue(tb.rx_send_tlp_q)
        flush_queue(tb.tx_send_tlp_q)
        await Timer(50, 'ns')

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
        factory.add_option("seed", [seed_gen(i) for i in range(10)])
        factory.generate_tests()

root_logger = logging.getLogger()

file_handler = RotatingFileHandler("rotating.log", maxBytes=(100 * 1024 * 1024), backupCount=1000)
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)