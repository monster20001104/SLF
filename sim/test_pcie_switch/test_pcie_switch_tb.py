###########################################
# 文件名称 : test_pcie_switch_tb
# 作者名称 : 崔飞翔
# 创建日期 : 2025/02/18
# 功能描述 : 
# 
# 修改记录 : 
# 
# 修改日期 : 2025/02/18
# 版本号    修改人    修改内容
# v1.0     崔飞翔     初始化版本
###########################################
import itertools
import math
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator
from enum import Enum, unique
import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time

sys.path.append('../common')
from bus.mlite_bus      import MliteBus
from drivers.mlite_bus import MliteBusMaster
from bus.tlp_adap_bypass_bus import TlpBypassBus, OpCode, ComplStatus, TlpBypassReq, TlpBypassRsp, TlpBypassReq2CfgTlp, Tlp2TlpBypassCpl
from drivers.tlp_adap_bypass_bus import TlpBypassMaster
from monitors.tlp_adap_bypass_bus import TlpBypassSlave

class Cmp_TlpBypassRsp(NamedTuple):
    op_code: OpCode
    addr: int
    cpl_byte_count: int
    byte_length: int
    tag: int
    cpl_id: int #req.req_id
    req_id: int #dev bdf
    cpl_status: ComplStatus
    first_be: int
    last_be: int
    data: bytes
    event: Event



class TB(object):
    def __init__(self,dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
        cocotb.start_soon(Clock(dut.hardip_clk, 5, units="ns").start())
        self.s2emu_tlpBypass = TlpBypassSlave(TlpBypassBus.from_prefix(dut, "switch2emu_tlp_bypass"), dut.clk, dut.rst, max_pause_duration=8)
        self.host2s_tlpBypass = TlpBypassMaster(TlpBypassBus.from_prefix(dut, "host2switch_tlp_bypass"), dut.clk, dut.rst, max_pause_duration=8)
        self.milte_master = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk, dut.rst)
        self.cpl_cmp_cnt = 0
        self.cpl_cnt = 0
        self.toemu_cnt = 0
        self.cfg_cmp_flag = 0
        self.reg_data = [bytes([0x36,0x1b,0xfe]), bytes([0x06,0x00,0x10]),bytes([0x00,0x00,0x04,0x06]),bytes([0x00,0x00,0x01]),
                         bytes([0x00]),bytes([0x00]),bytes([0xff,0xff,0xff]),bytes([0x00]),
                         bytes([0xf0,0xff,0xf0,0xff]),bytes([0xf1,0xff,0xf1,0xff]),bytes([0xff,0xff,0xff,0xff]),bytes([0xff,0xff,0xff,0xff]),
                         bytes([0x00]),bytes([0x70]),bytes([0x00]),bytes([0x00,0x00,0x40]),
                         bytes([0x00]),bytes([0x00]),bytes([0x00]),bytes([0x00]),
                         bytes([0x00]),bytes([0x00]),bytes([0x00]),bytes([0x00]),
                         bytes([0x00]),bytes([0x00]),bytes([0x00]),bytes([0x00]),
                         bytes([0x10,0x00,0x52]),bytes([0x20]),bytes([0xe0,0x71]),bytes([0x83,0x00,0x40]),
                         bytes([0x40,0x00,0xff,0x13]),bytes([0x00]),bytes([0x00]),bytes([0x00]),
                         bytes([0x00]),bytes([0x00]),bytes([0x00]),bytes([0x08])]
        self.opcode_numbers = [OpCode.MWr,OpCode.MRd,OpCode.CFGRd0,OpCode.CFGRd1,OpCode.CFGWr0,OpCode.CFGWr1]
        self.opcode_cpl_num = [OpCode.CplD,OpCode.Cpl]
        self.cmp_cpl= {tag: Queue(maxsize=32) for tag in range(256)} 
        self.mem_be_numbers = [1,2,3,4,6,7,8,12,14,15]
        self.cfg_be_number = [1,2,3,4,8,12,15]
        self.host_req_id = 0x9999
        self.dest_id = [0x120,0x222,0x322,0x422]
        self.gen = 0
        random.seed(42)

    async def time_out(self,time):
        time_error = 0
        while True:
            await RisingEdge(self.dut.clk)
            if self.dut.host2switch_tlp_bypass_cpl_rdy.value == 0:
                time_error = time_error + 1
            else:
                time_error = 0
            if time_error == time:
                raise ValueError("time out error!!!")
            
    async def cycle_reset(self):
        self.dut.rst.setimmediatevalue(0) 
        self.dut.linkdown.setimmediatevalue(0)    
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        self.dut.linkdown.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        self.dut.linkdown.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.current_ls.value = 0xf
        self.dut.negotiated_lw.value = 0x3f
        self.dut.event_rdy.value = 1


    async def linkdown(self):
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.linkdown.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.linkdown.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    async def hardip_cycle_reset(self):
        self.dut.hardip_rst.setimmediatevalue(0)     
        await RisingEdge(self.dut.hardip_clk)
        await RisingEdge(self.dut.hardip_clk)
        self.dut.hardip_rst.value = 1
        await RisingEdge(self.dut.hardip_clk)
        await RisingEdge(self.dut.hardip_clk)
        self.dut.hardip_rst.value = 0
        await RisingEdge(self.dut.hardip_clk)
        await RisingEdge(self.dut.hardip_clk)

    def find_lowest_one(self,num):
        if num == 0:
            return -1  # 如果没有1，返回-1
        position = 0
        while num != 0:
            if num & 1:  # 检查最低位是否为1
                return position
            num >>= 1    # 右移一位
            position += 1
        return -1

    async def tag_init(self):
        numbers = list(range(256))
        random.seed(42)
        random.shuffle(numbers)
        self.tag_q = Queue(maxsize=256)
        for num in numbers:
            await self.tag_q.put(num)

    async def tlp_driver_send(self,max_seq):
        for i in range(max_seq):
            tag = await self.tag_q.get()
            if i == 0:
                opcode = OpCode.CFGWr0
                addr = 0
                byte_length = 4
                first_be = 0xf
                last_be = 0
                req_id = self.host_req_id
                dest_id = 0x120
                ext_reg_num = 0
                reg_num = 6
                data = bytes([0x01,0x02,0x03])
            else:
                opcode = random.choice(self.opcode_numbers)
                if opcode == OpCode.MRd:
                    addr = random.randint(0,(2**32)-1)
                    byte_length = random.randint(1,1024) * 4  
                    data = bytes(0x0)             
                    if byte_length + addr > 2**32-1:
                        byte_length = (2**32-1-addr)//8
                    dest_id = 0
                    req_id = self.host_req_id
                    reg_num = 0
                    ext_reg_num = 0
                    first_be = random.choice(self.mem_be_numbers)
                    if byte_length > 4:
                        last_be = random.choice(self.mem_be_numbers)
                    else:
                        last_be = 0
                elif opcode == OpCode.MWr:
                    addr = random.randint(0,(2**32)-1)
                    byte_length = random.randint(1,1024) * 4
                    if byte_length + addr > 2**32-1:
                        byte_length = (2**32-1-addr)//8
                    data = bytes(random.getrandbits(8) for _ in range(byte_length))
                    dest_id = 0
                    req_id = self.host_req_id
                    reg_num = 0
                    ext_reg_num = 0
                    first_be = random.choice(self.mem_be_numbers)
                    if byte_length > 4:
                        last_be = random.choice(self.mem_be_numbers)
                    else:
                        last_be = 0

                elif opcode == OpCode.CFGRd0:
                    addr = 0
                    byte_length = 4
                    first_be = random.choice(self.cfg_be_number)
                    last_be = 0
                    req_id = self.host_req_id
                    dest_id = 0x120
                    reg_num_data = random.randint(0,39)
                    ext_reg_num = (reg_num_data >> 6) & 0xf
                    reg_num = reg_num_data & 0x3f
                    data = bytes(0x0) 

                elif opcode == OpCode.CFGWr0:
                    addr = 0
                    byte_length = 4
                    first_be = random.choice(self.cfg_be_number)
                    last_be = 0
                    req_id = self.host_req_id
                    dest_id = 0x120
                    reg_num_data = random.randint(0,39) 
                    ext_reg_num = (reg_num_data >> 6) & 0xf
                    reg_num = reg_num_data & 0x3f
                    data = bytes([0x01,0x02,0x03])

                elif opcode == OpCode.CFGRd1:
                    addr = 0
                    byte_length = 4
                    first_be = random.choice(self.cfg_be_number)
                    last_be = 0
                    req_id = self.host_req_id
                    dest_id = 0x422
                    reg_num_data = random.randint(0,39)
                    ext_reg_num = (reg_num_data >> 6) & 0xf
                    reg_num = reg_num_data & 0x3f
                    data = bytes(0x0) 

                elif opcode == OpCode.CFGWr1:
                    addr = 0
                    byte_length = 4
                    first_be = random.choice(self.cfg_be_number)
                    last_be = 0
                    req_id = self.host_req_id
                    dest_id = 0x422
                    reg_num_data = random.randint(0,39) 
                    ext_reg_num = (reg_num_data >> 6) & 0xf
                    reg_num = reg_num_data & 0x3f
                    data = bytes([0x01,0x02,0x03])

            if dest_id == 0x120:
                if opcode == OpCode.CFGRd0:
                    self.cpl_cnt = self.cpl_cnt + 1
                    cmp_cpl_data = Cmp_TlpBypassRsp(OpCode.CplD, 0, 4, 4,  tag, dest_id, req_id, ComplStatus.SC, 0, 0, bytes([0x0]), None)
                    await self.cmp_cpl[tag].put(cmp_cpl_data)
                elif opcode == OpCode.CFGWr0:
                    self.cpl_cnt = self.cpl_cnt + 1
                    cmp_cpl_data = Cmp_TlpBypassRsp(OpCode.Cpl, 0, 4, 0, tag, dest_id, req_id, ComplStatus.SC, 0, 0, bytes([0x0]), None)
                    await self.cmp_cpl[tag].put(cmp_cpl_data)
                print(f"cpl_cnt is {self.cpl_cnt}")
                print(f"dest_id is {dest_id},opcode is {opcode}")
                print(f"cmp_cpl_data is {cmp_cpl_data}")

            elif dest_id == 0x422:
                self.cpl_cnt = self.cpl_cnt + 1
                cmp_cpl_data = Cmp_TlpBypassRsp(OpCode.Cpl, 0, 4, 0, tag, 0x120, req_id, ComplStatus.UR, 0, 0, bytes([0x0]), None)        
                await self.cmp_cpl[tag].put(cmp_cpl_data)
                print(f"cpl_cnt is {self.cpl_cnt}")
                print(f"dest_id is {dest_id},opcode is {opcode}")
                print(f"cmp_cpl_data is {cmp_cpl_data}")

            req = TlpBypassReq(opcode,addr,byte_length,tag,req_id,first_be,last_be,dest_id,ext_reg_num,reg_num,data,None)   
            await self.host2s_tlpBypass.send_req(req,self.gen)

    async def tlp_driver_cfg_send(self):
        self.cfg_cmp_flag = 1
        for i in range(40):
            self.cpl_cnt = self.cpl_cnt + 1
            opcode = OpCode.CFGWr0
            tag = await self.tag_q.get()
            addr = 0
            byte_length = 4
            first_be = 0xf
            last_be = 0
            req_id = self.host_req_id
            dest_id = 0x120
            reg_num_data = i
            ext_reg_num = (reg_num_data >> 6) & 0xf
            reg_num = reg_num_data & 0x3f
            cmp_data = bytes(0x00)
            cmp_data = cmp_data.ljust(32, b'\x00')
            data = bytes([0xff,0xff,0xff,0xff])
            cmp_cpl_data = Cmp_TlpBypassRsp(OpCode.Cpl, 0, 4, 0, tag, dest_id, req_id, ComplStatus.SC, 0, 0,cmp_data, None)
            await self.cmp_cpl[tag].put(cmp_cpl_data)
            print(f"cpl_cnt is {self.cpl_cnt}")
            print(f"dest_id is {dest_id},opcode is {opcode}")
            print(f"cmp_cpl_data is {cmp_cpl_data}")
            req = TlpBypassReq(opcode,addr,byte_length,tag,req_id,first_be,last_be,dest_id,ext_reg_num,reg_num,data,None)   
            await self.host2s_tlpBypass.send_req(req,self.gen)

        for i in range(40):
            self.cpl_cnt = self.cpl_cnt + 1
            opcode = OpCode.CFGRd0
            tag = await self.tag_q.get()
            addr = 0
            byte_length = 4
            first_be = random.choice(self.cfg_be_number)
            last_be = 0
            req_id = self.host_req_id
            dest_id = 0x120
            reg_num_data = i
            ext_reg_num = (reg_num_data >> 6) & 0xf
            reg_num = reg_num_data & 0x3f
            cmp_data = self.reg_data[i]
            cmp_data = cmp_data.ljust(32, b'\x00')
            data = bytes([0x00])
            cmp_cpl_data = Cmp_TlpBypassRsp(OpCode.CplD, 0, 4, 4, tag, dest_id, req_id, ComplStatus.SC, 0, 0, cmp_data, None)
            await self.cmp_cpl[tag].put(cmp_cpl_data)
            print(f"cpl_cnt is {self.cpl_cnt}")
            print(f"dest_id is {dest_id},opcode is {opcode}")
            print(f"cmp_cpl_data is {cmp_cpl_data}")
            req = TlpBypassReq(opcode,addr,byte_length,tag,req_id,first_be,last_be,dest_id,ext_reg_num,reg_num,data,None)   
            await self.host2s_tlpBypass.send_req(req,self.gen)

    async def tlp_driver_bypass_send(self):
        await self.milte_master.write(0x0000_0318,0x01)
        await Timer(1000, 'ns')
        for i in range(100):
            opcode = OpCode.CFGRd0
            tag = random.randint(0,255)
            addr = 0
            byte_length = 4
            first_be = random.choice(self.cfg_be_number)
            last_be = 0
            req_id = self.host_req_id
            dest_id = 0x622
            reg_num_data = i
            ext_reg_num = (reg_num_data >> 6) & 0xf
            reg_num = reg_num_data & 0x3f
            data = bytes([0x00])
            print(f"dest_id is {dest_id},opcode is {opcode}")
            req = TlpBypassReq(opcode,addr,byte_length,tag,req_id,first_be,last_be,dest_id,ext_reg_num,reg_num,data,None)   
            print(f"req is {req}")
            await self.host2s_tlpBypass.send_req(req,self.gen)
        await Timer(1000, 'ns') 
        await self.milte_master.write(0x0000_0318,0x00)       

    async def tlp_driver_recv(self):
        while True:
            cpl,_ = await self.host2s_tlpBypass.recv_rsp()
            if cpl.cpl_id == 0x120:
                print(f"cpl_id is {cpl.cpl_id},tag is {cpl.tag}")
                self.cpl_cmp_cnt = self.cpl_cmp_cnt + 1
                print(f"cpl_cmp_cnt is {self.cpl_cmp_cnt}")
                cpl_cmp = await self.cmp_cpl[cpl.tag].get()
                src = (
                    cpl.op_code,
                    cpl.addr,
                    cpl.byte_length,
                    cpl.cpl_byte_count,
                    cpl.cpl_status,
                )
                cmp = (
                    cpl_cmp.op_code,
                    cpl_cmp.addr,
                    cpl_cmp.byte_length,
                    cpl_cmp.cpl_byte_count,
                    cpl_cmp.cpl_status,
                )
                if self.cfg_cmp_flag == 1:
                    src = (
                        cpl.op_code,
                        cpl.addr,
                        cpl.byte_length,
                        cpl.cpl_byte_count,
                        cpl.cpl_status,
                        cpl.data,
                    )
                    cmp = (
                        cpl_cmp.op_code,
                        cpl_cmp.addr,
                        cpl_cmp.byte_length,
                        cpl_cmp.cpl_byte_count,
                        cpl_cmp.cpl_status,
                        cpl_cmp.data,
                    )                    
                if src != cmp:
                    print(f"src is {src}")
                    print(f"cmp is {cmp}")
                    raise ValueError("cmp error!!!") 
                await self.tag_q.put(cpl.tag)

    async def tlp_monitor_recv(self):
        while True:
            req,_ = await self.s2emu_tlpBypass.recv_req()
            self.toemu_cnt = self.toemu_cnt +1
            if req.dest_id == 0x120 :
                if req.op_code not in [OpCode.CFGRd0, OpCode.CFGWr0]:
                    raise ValueError("transform error!!!")

    async def tlp_monitor_send(self):
        while True:
            await Timer(100, 'ns')
            opcode = random.choice(self.opcode_cpl_num)
            tag = random.randint(0,255)
            if opcode == OpCode.CplD:
                addr = random.randint(0,3)
                byte_length = random.randint(1,1024) * 4
                cpl_byte_count =  byte_length
                cpl_id = 0x222
                req_id = self.host_req_id
                cpl_status = ComplStatus.SC
                first_be = 0
                last_be = 0
                data = bytes(random.getrandbits(8) for _ in range(byte_length))
            elif opcode == OpCode.Cpl:
                addr = 0
                byte_length = 0
                cpl_byte_count =  byte_length
                cpl_id = 0x222
                req_id = self.host_req_id
                cpl_status = ComplStatus.SC
                first_be = 0
                last_be = 0
                data = bytes(0x0)
            rsp = TlpBypassRsp(opcode, addr, cpl_byte_count, byte_length, tag, cpl_id, req_id, cpl_status, first_be, last_be, data, None)
            await self.s2emu_tlpBypass.send_rsp(rsp,self.gen)

    async def hip_bypass_config_if_set_f(self,single):
        await RisingEdge(self.dut.hardip_clk)
        single.value = 0
        await RisingEdge(self.dut.hardip_clk)
        single.value = 0xf
        await RisingEdge(self.dut.hardip_clk)
        await Timer(400, 'ns')

    async def hip_bypass_config_if_set_1(self,single):
        await RisingEdge(self.dut.hardip_clk)
        single.value = 0
        await RisingEdge(self.dut.hardip_clk)
        single.value = 0x1
        await RisingEdge(self.dut.hardip_clk)
        single.value = 0
        await Timer(400, 'ns')

    async def hip_bypass_read_data_cmp(self):
        nums = [64, 66, 128, 129, 132]
        nums2 = [66, 129, 132]
        cdata = [bytes([0x19,0x00,0x01,0x20]),bytes([0x0f,0x00,0x00,0x00]),bytes([0x01,0x00,0x01,0x00]),bytes([0x31,0x20,0x46,0x00]),bytes([0xc1,0x51,0x00,0x00])]
        for i in range(5):
            self.cpl_cnt = self.cpl_cnt + 1
            opcode = OpCode.CFGRd0
            tag = await self.tag_q.get()
            addr = 0
            byte_length = 4
            first_be = random.choice(self.cfg_be_number)
            last_be = 0
            req_id = self.host_req_id
            dest_id = 0x120
            reg_num_data = nums[i]
            print(f"reg_num_data {reg_num_data}")
            ext_reg_num = (reg_num_data >> 6) & 0xf
            reg_num = reg_num_data & 0x3f
            cmp_data = cdata[i]
            cmp_data = cmp_data.ljust(32, b'\x00')
            data = bytes([0x00])
            cmp_cpl_data = Cmp_TlpBypassRsp(OpCode.CplD, 0, 4, 4, tag, dest_id, req_id, ComplStatus.SC, 0, 0, cmp_data, None)
            await self.cmp_cpl[tag].put(cmp_cpl_data)
            print(f"cpl_cnt is {self.cpl_cnt}")
            print(f"dest_id is {dest_id},opcode is {opcode}")
            print(f"cmp_cpl_data is {cmp_cpl_data}")
            req = TlpBypassReq(opcode,addr,byte_length,tag,req_id,first_be,last_be,dest_id,ext_reg_num,reg_num,data,None)   
            await self.host2s_tlpBypass.send_req(req,self.gen)    

        for i in range(3):
            self.cpl_cnt = self.cpl_cnt + 1
            opcode = OpCode.CFGWr0
            tag = await self.tag_q.get()
            addr = 0
            byte_length = 4
            first_be = 0xf
            last_be = 0
            req_id = self.host_req_id
            dest_id = 0x120
            reg_num_data = nums2[i]
            ext_reg_num = (reg_num_data >> 6) & 0xf
            reg_num = reg_num_data & 0x3f
            cmp_data = bytes(0x00)
            cmp_data = cmp_data.ljust(32, b'\x00')
            data = bytes([0xff,0xff,0xff,0xff])
            cmp_cpl_data = Cmp_TlpBypassRsp(OpCode.Cpl, 0, 4, 0, tag, dest_id, req_id, ComplStatus.SC, 0, 0,cmp_data, None)
            await self.cmp_cpl[tag].put(cmp_cpl_data)
            print(f"cpl_cnt is {self.cpl_cnt}")
            print(f"dest_id is {dest_id},opcode is {opcode}")
            print(f"cmp_cpl_data is {cmp_cpl_data}")
            req = TlpBypassReq(opcode,addr,byte_length,tag,req_id,first_be,last_be,dest_id,ext_reg_num,reg_num,data,None)   
            await self.host2s_tlpBypass.send_req(req,self.gen)    

        for i in range(3):
            self.cpl_cnt = self.cpl_cnt + 1
            opcode = OpCode.CFGRd0
            tag = await self.tag_q.get()
            addr = 0
            byte_length = 4
            first_be = random.choice(self.cfg_be_number)
            last_be = 0
            req_id = self.host_req_id
            dest_id = 0x120
            reg_num_data = nums2[i]
            ext_reg_num = (reg_num_data >> 6) & 0xf
            reg_num = reg_num_data & 0x3f
            cmp_data = bytes(0x00)
            cmp_data = cmp_data.ljust(32, b'\x00')
            data = bytes([0x00])
            cmp_cpl_data = Cmp_TlpBypassRsp(OpCode.CplD, 0, 4, 4, tag, dest_id, req_id, ComplStatus.SC, 0, 0, cmp_data, None)
            await self.cmp_cpl[tag].put(cmp_cpl_data)
            print(f"cpl_cnt is {self.cpl_cnt}")
            print(f"dest_id is {dest_id},opcode is {opcode}")
            print(f"cmp_cpl_data is {cmp_cpl_data}")
            req = TlpBypassReq(opcode,addr,byte_length,tag,req_id,first_be,last_be,dest_id,ext_reg_num,reg_num,data,None)   
            await self.host2s_tlpBypass.send_req(req,self.gen)  

    def set_idle_generator(self, generator=None): 
        if generator:
            self.s2emu_tlpBypass.set_idle_generator(generator)
            self.host2s_tlpBypass.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
       if generator:
            self.s2emu_tlpBypass.set_backpressure_generator(generator)
            self.host2s_tlpBypass.set_backpressure_generator(generator)

async def run_test(dut, idle_inserter, backpressure_inserter):
    tb = TB(dut)
    tb.dut.lane_err.value = 0
    tb.dut.err_uncorr_internal = 0
    tb.dut.rx_corr_internal    = 0
    tb.dut.err_tlrcvovf        = 0
    tb.dut.txfc_err            = 0
    tb.dut.err_tlmalf          = 0
    tb.dut.err_surpdwn_dll     = 0
    tb.dut.err_dllrev          = 0
    tb.dut.err_dll_repnum      = 0
    tb.dut.err_dllreptim       = 0
    tb.dut.err_dllp_baddllp    = 0
    tb.dut.err_dll_badtlp      = 0
    tb.dut.err_phy_tng         = 0
    tb.dut.err_phy_rcv         = 0
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    await tb.hardip_cycle_reset()
    cocotb.start_soon(tb.time_out(20000))
    cocotb.start_soon(tb.tlp_monitor_recv())
    cocotb.start_soon(tb.tlp_driver_recv())
    cocotb.start_soon(tb.tlp_monitor_send())
    

    await tb.tag_init()
    await tb.tlp_driver_send(max_seq=20)
    while tb.cpl_cnt != tb.cpl_cmp_cnt:
        await Timer(1000, 'ns')
        print(f"tags is {tb.tag_q}")
        print(f"cpl_cnt is {tb.cpl_cnt}")
        print(f"cpl_cmp_cnt is {tb.cpl_cmp_cnt}")
    print(f"All received, ready to send 80 register read and write messages")
    await Timer(4000, 'ns')
#    await tb.linkdown()
    await tb.tlp_driver_cfg_send()
    while tb.cpl_cnt != tb.cpl_cmp_cnt:
        await Timer(1000, 'ns')
        print(f"tags is {tb.tag_q}")
        print(f"cpl_cnt is {tb.cpl_cnt}")
        print(f"cpl_cmp_cnt is {tb.cpl_cmp_cnt}")

    print(f"cpl_cnt is {tb.cpl_cnt}")
    print(f"cpl_cmp_cnt is {tb.cpl_cmp_cnt}")
    print(f"toemu_cnt is {tb.toemu_cnt}")
    print(f"all cnt is {tb.toemu_cnt + tb.cpl_cmp_cnt}")
    print(f"All received, read and write data verified as correct")   
    await Timer(4000, 'ns')
    await tb.tlp_driver_bypass_send()
    await Timer(4000, 'ns')
    while tb.cpl_cnt != tb.cpl_cmp_cnt:
        await Timer(1000, 'ns')
        print(f"tags is {tb.tag_q}")
        print(f"cpl_cnt is {tb.cpl_cnt}")
        print(f"cpl_cmp_cnt is {tb.cpl_cmp_cnt}")

    print(f"cpl_cnt is {tb.cpl_cnt}")
    print(f"cpl_cmp_cnt is {tb.cpl_cmp_cnt}")
    print(f"toemu_cnt is {tb.toemu_cnt}")
    print(f"all cnt is {tb.toemu_cnt + tb.cpl_cmp_cnt}")
    print(f"All received, read and write data verified as correct")
    await Timer(4000, 'ns')
    await tb.hip_bypass_config_if_set_f(tb.dut.lane_err)
    await tb.hip_bypass_config_if_set_1(tb.dut.err_uncorr_internal  )
    await tb.hip_bypass_config_if_set_1(tb.dut.rx_corr_internal     )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_tlrcvovf         )
    await tb.hip_bypass_config_if_set_1(tb.dut.txfc_err             )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_tlmalf           )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_surpdwn_dll      )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_dllrev           )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_dll_repnum       )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_dllreptim        )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_dllp_baddllp     )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_dll_badtlp       )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_phy_tng          )
    await tb.hip_bypass_config_if_set_1(tb.dut.err_phy_rcv          )

    await tb.hip_bypass_read_data_cmp()
    while tb.cpl_cnt != tb.cpl_cmp_cnt:
        await Timer(1000, 'ns')
        print(f"tags is {tb.tag_q}")
        print(f"cpl_cnt is {tb.cpl_cnt}")
        print(f"cpl_cmp_cnt is {tb.cpl_cmp_cnt}")

    print("end")


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

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
