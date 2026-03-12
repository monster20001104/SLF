#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : test_emu_tb.py
#* 作者名称 : matao
#* 创建日期 : 2025/01/20
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   01/20       matao       初始化版本
#* v1.1   09/02       matao       重构版本
#******************************************************************************/
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import copy
import cocotb_test.simulator
import time

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union, Dict, Optional, Set, Tuple
from cocotb.regression import TestFactory


sys.path.append('../common')
from bus.beq_data_bus import BeqBus
from drivers.beq_data_bus import BeqTxqMaster
from monitors.beq_data_bus import BeqRxqSlave
from bus.tlp_adap_bypass_bus import TlpBypassBus, OpCode, ComplStatus, TlpBypassReq, TlpBypassRsp, TlpBypassReq2CfgTlp, Tlp2TlpBypassCpl,Header
from drivers.tlp_adap_bypass_bus import TlpBypassMaster
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster
from defines import *
import ding_robot

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        self.max_seq = 5000
        self.test_done = Event()
        cocotb.start_soon(Clock(dut.clk, 5, units="ns").start())

        self.beq_txq = BeqTxqMaster(BeqBus.from_prefix(dut, "beq2emu"), dut.clk, dut.rst)
        self.beq_rxq = BeqRxqSlave (BeqBus.from_prefix(dut, "emu2beq"), dut.clk, dut.rst)
        self.tlp_bypass_master = TlpBypassMaster(TlpBypassBus.from_prefix(dut, "tlp_bypass_master"), dut.clk, dut.rst)
        self.event_master = EventReqSource(EventReqBus.from_prefix(dut, "event_master"), dut.clk, dut.rst)
        self.doorbell_slave = DoorBellRspSink(DoorBellRspBus.from_prefix(dut, "fe_doorbell"), dut.clk, dut.rst)
        self.regconfigmaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)
        
        self._process_beq_rxq_cr        = cocotb.start_soon(self._process_beq_rxq())
        self._process_doorbell_rsp_cr   = cocotb.start_soon(self._process_doorbell_rsp())
        self._process_beq_txq_cr        = cocotb.start_soon(self._process_beq_txq())
        self._process_tlp_bypass_cpl_cr = cocotb.start_soon(self._process_tlp_bypass_rsp())
        self._process_event_req_cr   = cocotb.start_soon(self._process_event_req())
        self._process_event_rsp_cr   = cocotb.start_soon(self._process_event_rsp())
        ## tlp_bypass2emu
        self.tlp_req_queue = Queue(maxsize=8)
        self.beq_rxq_queue = Queue(maxsize=64)
        self.doorbell_req_queue = Queue(maxsize=64)
        self.tlp_req_end_queue = Queue(maxsize=8)
        ## test case
        self.test_case_end_queue = Queue(maxsize=8)
        ## beq2emu
        self.beq_txq_queue = Queue(maxsize=8)
        self.beq_req_end_queue = Queue(maxsize=8)
        self.tlp_cpl_queue = Queue(maxsize=8)
        ## event 
        self.event_req_queue = Queue(maxsize=8)
        self.event_rsp_queue = Queue(maxsize=8)
        self.event_end_queue = Queue(maxsize=8)
        self.beq_rxq_event_queue = Queue(maxsize=8)
        ## dfx
        self.dfx_reg_queue = Queue(maxsize=8)
        self.cookie_chk_en = 0

        self.non_posted_cnt = 0
        self.non_posted_req_cnt = 0
        self.beq2emu_mrd_cnt = 0
        self.beq2emu_mwr_cnt = 0
        self.beq2emu_cfg_cnt = 0
        self.tlp_bypass_req_mwr_cnt = 0
        self.tlp_bypass_req_mrd_cnt = 0
        self.event_req_cnt = 0
        self.event_rsp_cnt = 0
        self.tlp_bypass2beq_cnt = 0
        self.tlp_bypass2doorbell_cnt = 0
        self.beq2emu_req_cnt = 0
        self.beq2emu_rsp_cnt = 0
        self.beq_rsp_cookie_cnt = 0

    async def _process_beq_rxq(self):
        while True:
            rxq_rsp = await self.beq_rxq.recv()#pkt = BeqData(qid, data, user0, user1, sty)user1[15:8]=hostgen
            tlptype = rxq_rsp.user1 & 0xFF
            if tlptype == 1 :#host_tlp
                self.tlp_bypass2beq_cnt += 1
                beq_rxq_req_hdr,beq_rxq_req_host_gen, non_posted_cnt = await self.beq_rxq_queue.get()
                header_length = 32
                rxq_header = rxq_rsp.data[:header_length][::-1][-26:]
                binary_value = cocotb.binary.BinaryValue(value=rxq_header, n_bits=26*8)
                header_obj = Header.unpack(binary_value)

                if beq_rxq_req_hdr.op_code in [OpCode.CFGWr0 , OpCode.CFGWr1 ,OpCode.MWr]:
                    rxq_data = rxq_rsp.data[header_length:]
                    beq_rxq_req_hdr_data = beq_rxq_req_hdr.data.ljust(len(rxq_data), b'\x00')
                else :
                    rxq_data = b''
                    beq_rxq_req_hdr_data = beq_rxq_req_hdr.data

                user1_high = (rxq_rsp.user1 >> 8) & 0xFF
                fields = [
                    ("data", beq_rxq_req_hdr_data, rxq_data),
                    ("host_gen", beq_rxq_req_host_gen, user1_high),
                    ("op_code", beq_rxq_req_hdr.op_code.value, header_obj.op_code),
                    ("addr", beq_rxq_req_hdr.addr, header_obj.addr),
                    ("byte_length", beq_rxq_req_hdr.byte_length, header_obj.byte_length),
                    ("tag", beq_rxq_req_hdr.tag, header_obj.tag),
                    ("req_id", beq_rxq_req_hdr.req_id, header_obj.req_id),
                    ("first_be", beq_rxq_req_hdr.first_be, header_obj.first_be),
                    ("last_be", beq_rxq_req_hdr.last_be, header_obj.last_be),
                    ("dest_id", beq_rxq_req_hdr.dest_id, header_obj.dest_id),
                    ("ext_reg_num", beq_rxq_req_hdr.ext_reg_num, header_obj.ext_reg_num),
                    ("reg_num", beq_rxq_req_hdr.reg_num, header_obj.reg_num)
                ]
                non_matching = []
                for field_name, val1, val2 in fields:
                    if isinstance(val1, bytes) and isinstance(val2, bytes):
                        debug_msg = f"Comparing {field_name}: expected={val1.hex()}, actual={val2.hex()}"
                    elif isinstance(val1, int) and isinstance(val2, int):
                        debug_msg = f"Comparing {field_name}: expected=0x{val1:x} ({val1}), actual=0x{val2:x} ({val2})"
                    else:
                        debug_msg = f"Comparing {field_name}: expected={val1}, actual={val2}"
                    self.log.debug(debug_msg)
                    if val1 != val2:
                        non_matching.append(field_name)
                        msg = f"{field_name} mismatch: {val1} != {val2}"
                        self.log.debug(msg)
                if non_matching:
                    assert False, f"Not match: {', '.join(non_matching)}"

                bar_range = header_obj.bar_range
                bdf = header_obj.bdf            
                vf_active = header_obj.vf_active
                tmp = (bar_range << 17) | (bdf << 1) | vf_active
                cookie = tmp & 0x7FFFF
                cookie_en = (tmp >> 19) & 0x1
                if header_obj.op_code in [OpCode.MRd.value, OpCode.CFGRd0.value, OpCode.CFGRd1.value, OpCode.CFGWr0.value, OpCode.CFGWr1.value]:
                    if self.cookie_chk_en != cookie_en:
                        self.log.debug(f" self.cookie_chk_en is {self.cookie_chk_en}, rsp cookie_en is {cookie_en}")
                        assert False,f" self.cookie_chk_en is {self.cookie_chk_en}, rsp cookie_en is {cookie_en}"
                    if self.cookie_chk_en == 1:
                        self.log.debug(f"tlp_bypass_req_hdr cookie is {cookie}, non_posted_cnt is {non_posted_cnt}")
                        if cookie != non_posted_cnt:
                            err_msg = f"tlp_bypass_req_hdr cookie mismatch: cookie={cookie}, non_posted_cnt={non_posted_cnt}"
                            self.log.debug(err_msg)
                            assert False, err_msg 
            elif tlptype == 3 :#event reset
                await self.beq_rxq_event_queue.put(rxq_rsp) 
            else :
                raise ValueError(f"Invalid user1: {tlptype}. Expected tlp or reset event.")

    async def _process_doorbell_rsp(self):
        while True:
            qid_sink = await self.doorbell_slave.recv()
            self.tlp_bypass2doorbell_cnt += 1
            req_addr,host_gen, qid_src = await self.doorbell_req_queue.get()
            mask = 0xFFFF
            qid_src = qid_src & mask
            qid_sink_qid_int = qid_sink.qid.integer
            self.log.debug(f"Checking qid match: sink_qid=0x{qid_sink_qid_int:x}, src_qid=0x{qid_src:x}, host_gen={host_gen}, req_addr is {req_addr}, tlp_bypass2doorbell_cnt is {self.tlp_bypass2doorbell_cnt}")
            assert qid_sink_qid_int == qid_src, f"Checking qid match: sink_qid=0x{qid_sink_qid_int:x}, src_qid=0x{qid_src:x}"
            
    #beq2emu
    async def _process_beq_txq(self):
        while True:
            req = await self.beq_txq_queue.get()
            await self.beq_txq.send(req.qid, req.data, req.user0)
            self.beq2emu_req_cnt += 1
            await self.tlp_cpl_queue.put((req.rsp, req.user0))

    async def _process_tlp_bypass_rsp(self):
        def compare_tlp_bypass_rsp(req, rsp):
            req_attrs = {k: v for k, v in vars(req).items() if not k.startswith('__')}
            rsp_attrs = {k: v for k, v in vars(rsp).items() if not k.startswith('__')}
            
            diff_details = []
            attr_names = set(req_attrs.keys()).union(set(rsp_attrs.keys()))
            
            for attr in sorted(attr_names):
                if attr not in req_attrs:
                    diff_details.append(f"req don't have: {attr}")
                    continue
                if attr not in rsp_attrs:
                    diff_details.append(f"rsp don't have: {attr}")
                    continue
                
                req_val = req_attrs[attr]
                rsp_val = rsp_attrs[attr]
                
                if attr != "data":
                    if req_val != rsp_val:
                        diff_details.append(
                            f"Attribute [{attr}] does not match: req={req_val}, rsp={rsp_val}"
                        )
                else:
                    req_valid_len = req.byte_length
                    rsp_valid_len = rsp.byte_length
                    
                    req_data_valid = req_val[:req_valid_len]
                    rsp_data_valid = rsp_val[:rsp_valid_len]
                    
                    if req_data_valid != rsp_data_valid:
                        req_data_hex = req_data_valid.hex()
                        rsp_data_hex = rsp_data_valid.hex()
                        diff_details.append(
                            f"Attribute [data] does not match: "
                            f"valid lengths (req={req_valid_len}, rsp={rsp_valid_len}), "
                            f"req valid data (hex)={req_data_hex}, "
                            f"rsp valid data (hex)={rsp_data_hex}"
                        )
            return len(diff_details) == 0, diff_details
        while True:
            tlp_rsp, rsp_gen = await self.tlp_bypass_master.recv_rsp()
            self.beq2emu_rsp_cnt += 1
            txq_req, user0 = await self.tlp_cpl_queue.get()
            user0_bits_15_8 = (user0 >> 8) & 0xFF

            if txq_req.op_code in [OpCode.Cpl, OpCode.MRd, OpCode.CFGRd0, OpCode.CFGRd1]:
                txq_req = txq_req._replace(data=tlp_rsp.data)
                prefix = "cpl" 
            else:
                prefix = "cpld"

            is_equal, diffs = compare_tlp_bypass_rsp(txq_req, tlp_rsp)
            if not is_equal:
                self.log.info(f"{prefix} txq_req and tlp_rsp are not equal.")
                self.log.info(f"txq_req: {txq_req}")
                self.log.info(f"tlp_rsp: {tlp_rsp}")

                self.log.info(f"diff:")
                for idx, diff in enumerate(diffs, 1):
                    self.log.info(f"  {idx}. {diff}")

                assert False, f"{prefix} txq_req and tlp_rsp are not equal. Number of differences: {len(diffs)}. Details: {'; '.join(diffs)}"
            #if txq_req != tlp_rsp:
            #    self.log.info(f"{prefix} txq_req and tlp_rsp are not equal.")
            #    self.log.info(f"txq_req: {txq_req}")
            #    self.log.info(f"tlp_rsp: {tlp_rsp}")
            #    assert False, f"{prefix} txq_req and tlp_rsp are not equal."

            if rsp_gen != user0_bits_15_8:
                self.log.info(f"rsp_gen ({rsp_gen}) is not equal to user0[15:8] ({user0_bits_15_8})")
                assert False, "rsp_gen is not equal to user0[15:8]."

    #event
    async def _process_event_req(self):
        while True:
            event_vld, event_dat = await self.event_req_queue.get()
            obj = self.event_master._transaction_obj()
            obj.data = event_dat
            
            if event_vld == 1:
                await RisingEdge(self.dut.clk)
                await self.event_master.send(obj)
                self.event_req_cnt += 1
                await self.event_rsp_queue.put((event_dat))
            else:
                await RisingEdge(self.dut.clk)

    async def _process_event_rsp(self):
        while True:
            event_dat = await self.event_rsp_queue.get()
            beq_rxq_rsp = await self.beq_rxq_event_queue.get()
            self.event_rsp_cnt += 1
            beq_rxq_data = beq_rxq_rsp.data

            padded_linkdata = event_dat.to_bytes(1, byteorder='big').ljust(64, b'\x00')
            if padded_linkdata != beq_rxq_data:
                self.log.info(f"expected data: {padded_linkdata.hex()}")
                self.log.info(f"actual data: {beq_rxq_data.hex()}")
                assert False, "beq_rxq_data and padded_linkdata are not equal."
                    
    async def reg_wr_req(self, addr,data):
        await self.regconfigmaster.write(addr,data,True)

    async def reg_rd_req(self, addr):
        rddata = await self.regconfigmaster.read(addr)
        return rddata

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

    def set_idle_generator(self, generator=None):
        if generator:
            self.beq_txq.set_idle_generator(generator)
            self.tlp_bypass_master.set_idle_generator(generator) 
            self.event_master.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.beq_rxq.set_backpressure_generator(generator)
            self.tlp_bypass_master.set_backpressure_generator(generator)
            self.doorbell_slave.set_backpressure_generator(generator)


async def run_test_emu(dut, idle_inserter, backpressure_inserter,case_mode, stride_choice, cookie_limit_mod, fifo_pfull_en):
    time_seed = int(time.time())
    random.seed(time_seed)
    tb = TB(dut)
    tb.log.info(f"set time_seed {time_seed}")
    pvm = PFVFManager()
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    if cookie_limit_mod:
        max_value = (1 << 19) - 1  # 2^19 - 1 = 524287
        tb.non_posted_cnt_sim_init = random.randint(max_value - 100 + 1, max_value)
        tb.dut.u_emu.non_posted_cnt_sim_en.value = 1
        tb.dut.u_emu.non_posted_cnt_sim_init.value = tb.non_posted_cnt_sim_init
    else :
        tb.non_posted_cnt_sim_init = 0
        tb.dut.u_emu.non_posted_cnt_sim_en.value = 0
        tb.dut.u_emu.non_posted_cnt_sim_init.value = tb.non_posted_cnt_sim_init
    tb.non_posted_cnt = tb.non_posted_cnt_sim_init
    tb.beq_rsp_cookie_cnt = tb.non_posted_cnt_sim_init
    await tb.cycle_reset()
    for _ in range(6):
        await RisingEdge(tb.dut.clk)

    ## tlp_bypass2emu req
    async def process_tlp_bypass_req(tb):
        for i in range(tb.max_seq):
            print(f"\rmax_seq is : {tb.max_seq}, tlpbypass to beq sequence is :{i+1}", end='', flush=True) 
            tb.log.info(f"max_seq is : {tb.max_seq}, tlpbypass to beq sequence is :{i+1}", )
            host_gen    = random.randint(0, 255)
            tag         = random.randint(0, 255)
            req_id      = random.randint(0, 2**15)
            dest_id     = random.randint(0, 2**15)
            ext_reg_num = random.randint(0, 7)
            reg_num     = random.randint(0, 63)

            op_codes = [OpCode.MRd, OpCode.CFGRd0, OpCode.CFGRd1, OpCode.CFGWr0, OpCode.CFGWr1]
            if pvm.wr_reg_busy:
                op_code = OpCode.MWr if random.random() < 0.7 else random.choice(op_codes)
                tb.log.info(f"reg wr isn't busy")
            else:
                tb.log.info(f"reg wr is busy")
                op_code = random.choice(op_codes)
            
            if fifo_pfull_en :
                op_code = random.choice(op_codes)
            
            first_be, last_be = (3, 0) if random.random() < 0.8 else (random.randint(0, 15), random.randint(0, 15))

            if op_code in [OpCode.CFGRd0, OpCode.CFGRd1, OpCode.CFGWr0, OpCode.CFGWr1]:
                byte_length = 4 if random.random() < 0.8 else random.choice([n for n in range(1, 33) if n != 4])
            elif op_code in [OpCode.MRd, OpCode.MWr]:
                byte_length = 4 if random.random() < 0.7 else random.choice([n for n in range(1, 1025) if n != 4])
            else:
                byte_length = 32

            is_read_cmd = op_code in [OpCode.MRd, OpCode.CFGRd0, OpCode.CFGRd1]
            data = b'' if is_read_cmd else random.randbytes(byte_length)
            rand_prob = random.random()

            if pvm.all_possible_addresses:
                if rand_prob < 0.5:
                    addr = random.choice(pvm.all_possible_addresses)[3]
                elif rand_prob < 0.7:
                    if pvm.illegal_addresses:
                        addr = random.choice(pvm.illegal_addresses)
                    else:
                        addr = random.randint(0, pvm.all_addr_range)
                elif rand_prob < 0.9:
                    addr = random.randint(0, pvm.all_addr_range)
                else:
                    addr = random.randint(1, 2**63 - 1)
            else:
                addr = random.randint(1, 2**63 - 1)

            hdr = TlpBypassReq(op_code=op_code, addr=addr, byte_length=byte_length, data=data, tag=tag, req_id=req_id, first_be=first_be, last_be=last_be, 
                dest_id=dest_id, ext_reg_num=ext_reg_num, reg_num=reg_num, event=None)
            req = TlpReq(hdr,host_gen)

            await tb.tlp_bypass_master.send_req(req.hdr,req.host_gen)
            valid_addresses = {addr for (_, _, _, addr) in pvm.all_possible_addresses}
            table1gqid, table1hit, doorbell_match = pvm.get_gqid_info(op_code, first_be, last_be, byte_length, addr, valid_addresses)
            tb.log.debug("tlpbypass to beq-- op_code is:{}, byte_length is: {}, first_be is:{}, last_be is:{}, addr is 0x{:x}, host_gen is: {}".format(op_code, byte_length,first_be, last_be, addr, host_gen ))
            tb.log.debug("tlpbypass to beq-- data is:{}".format(data))
            tb.log.debug("tlpbypass to beq--pvm.all_possible_addresses is : {}".format(pvm.all_possible_addresses))
            tb.log.debug("tlpbypass to beq--table1hit is {}, doorbell_match is {}".format(table1hit, doorbell_match))

            #await tb.tlp_req_queue.put((req, table1gqid, table1hit, doorbell_match))
            if  table1hit == 1 and doorbell_match ==1 :
                await tb.doorbell_req_queue.put((req.hdr.addr, req.host_gen, table1gqid))
            else :
                await tb.beq_rxq_queue.put((req.hdr ,req.host_gen, tb.non_posted_cnt))
            if req.hdr.op_code != OpCode.MWr and tb.cookie_chk_en == 1:
                tb.non_posted_cnt = (tb.non_posted_cnt + 1) % (1 << 19)
            if req.hdr.op_code == OpCode.MWr:
                tb.tlp_bypass_req_mwr_cnt = (tb.tlp_bypass_req_mwr_cnt + 1) % (1 << 16)
            else :
                tb.non_posted_req_cnt = (tb.non_posted_req_cnt + 1) % (1 << 19)
            if req.hdr.op_code == OpCode.MRd:
                tb.tlp_bypass_req_mrd_cnt = (tb.tlp_bypass_req_mrd_cnt + 1) % (1 << 16)
        
        await tb.tlp_req_end_queue.put(1) 
        tb.log.debug("tlp_req_end_queue has put 1")
        tb.test_done.set()

    ## PFVFManager case
    def _select_stride(stride_choice: Optional[int]) -> int:
        if stride_choice is not None:
            return stride_choice
        return random.randint(0, 5)

    async def _run_add_basic_test(stride_choice: Optional[int] = None, tb=None) -> bool:
        available_pf_ids = pvm.get_available_pf_ids()
        pf_with_available_vf = pvm.get_pf_with_available_vf()
        used_vid_total = pvm.calc_used_vid_total()
        remaining_vid_total = pvm.MAX_GQID_ENTRIES - used_vid_total

        is_pf_available = len(available_pf_ids) > 0 or len(pf_with_available_vf) > 0
        is_vid_available = remaining_vid_total >= 1
        tb.log.debug(f"_run_add_basic_test: is_pf_available {is_pf_available}, is_vid_available {is_vid_available},available_pf_ids {available_pf_ids},pf_with_available_vf {pf_with_available_vf},remaining_vid_total {remaining_vid_total}")
        if not (is_pf_available and is_vid_available):
            return await pvm.batch_process(
                tb=tb,
                add_pfs=[]
            )

        add_pfs: List[Tuple[int, int, int, int]] = []
        stride = _select_stride(stride_choice)
        allocated_vid_total = 0

        max_pf_to_operate = min(3, len(available_pf_ids) + len(pf_with_available_vf))
        num_pf_to_operate = random.randint(1, max_pf_to_operate)
        selected_pfs: List[Tuple[int, PF]] = []

        for pf_id in random.sample(available_pf_ids, min(num_pf_to_operate, len(available_pf_ids))):
            selected_pfs.append((pf_id, None))
        remaining_pf_need = num_pf_to_operate - len(selected_pfs)
        if remaining_pf_need > 0:
            for pf in random.sample(pf_with_available_vf, remaining_pf_need):
                selected_pfs.append((pf.pf_id, pf))
        MAX_VID_PER_VF = 256
        for pf_id, pf_instance in selected_pfs:
            if pf_instance is None:
                max_vf_for_pf = 32
            else:
                max_vf_for_pf = 32 - len(pf_instance.vfs)

            max_vid_for_pf = remaining_vid_total - allocated_vid_total
            if max_vid_for_pf <= 0:
                continue
            
            max_vf_possible = min(5, max_vid_for_pf, max_vf_for_pf)
            if max_vf_possible <= 0:
                continue

            vf_count = random.randint(1, max_vf_possible)
            total_vid_min = vf_count  
            total_vid_max = min(max_vid_for_pf, vf_count * MAX_VID_PER_VF)
            total_vid_for_pf = total_vid_min if total_vid_min == total_vid_max else random.randint(total_vid_min, total_vid_max)
            
            add_pfs.append((pf_id, stride, vf_count, total_vid_for_pf))
            allocated_vid_total += total_vid_for_pf
            tb.log.debug(
                f"_run_add_basic_test: PF {pf_id} :stride={stride}, VFnum={vf_count}, "
                f"VID num={total_vid_for_pf}")

        return await pvm.batch_process(
            tb=tb,
            add_pfs=add_pfs)

    async def _run_add_boundary_test(case: str, stride_choice: Optional[int] = None, tb=None) -> bool:
        """
        Boundary test case (replacing the original case_id)
        Case parameter description:
        -single-min : single PF+single VF+minimum VID (1)
        -single_max : Single PF+Single VF+Maximum VID (256)
        -single_full: A single PF+4 VFs+total VID=1024
        -full_pf : Fill 16 PFs (1 VF+1 VID each)
        -max_vf_per_pf ": 16 PFs (32 VFs+64 VIDs each)
        """
        add_pfs: List[Tuple[int, int, int, int]] = []
        stride = _select_stride(stride_choice)

        def get_pf_id(available_pfs: List[int]) -> int:
            return (available_pfs[0] if available_pfs 
                else random.choice(list(pvm.pfs.keys())) if pvm.pfs 
                else random.randint(0, 15))
        
        case_handlers = {
            "single_min": lambda: [
                (get_pf_id(pvm.get_available_pf_ids()), stride, 1, 1)
            ],
            "single_max": lambda: [
                (get_pf_id(pvm.get_available_pf_ids()), stride, 1, 256)
            ],
            "single_max_pro": lambda: [
                (get_pf_id(pvm.get_available_pf_ids()), 2, 2, 1024)
            ],
            "single_full": lambda: [
                (get_pf_id(pvm.get_available_pf_ids()), stride, 4, 1024)
            ],
            "full_pf": lambda: [
                (get_pf_id(pvm.get_available_pf_ids()[i:i+1]), stride, 1, 1) 
                for i in range(16)
            ],
            "max_vf_per_pf": lambda: [
                (get_pf_id(pvm.get_available_pf_ids()[i:i+1]), stride, 32, 64) 
                for i in range(16)
            ]}
        if case not in case_handlers:
            raise ValueError(f"Invalid test case: {case}, optional values: {list(case_handlers.keys())}")
        add_pfs = case_handlers[case]()

        return await pvm.batch_process(
            tb=tb,
            add_pfs=add_pfs)

    async def _run_del_pfvf_test() -> bool:
        current_pfs = list(pvm.pfs.values())
        tb.log.debug(f"_RUN_del_pfvf_test: current_pfs {current_pfs}  ")
        if not current_pfs:
            return await pvm.batch_process(tb=tb, del_pfs=[], del_vfs=[])
        
        del_pfs: List[int] = []
        del_vfs: List[Tuple[int, int]] = []
        total_pf_count = len(current_pfs)
        operation_type = random.choice([0, 1])
        tb.log.debug(f"_RUN_del_pfvf_test: total_pf_count {total_pf_count}  ")

        if operation_type == 0:
            num_del_pf = random.randint(1, total_pf_count)
            pf_to_del = random.sample(current_pfs, num_del_pf)
            del_pfs = [pf.pf_id for pf in pf_to_del]
        
        else:
            pfs_with_vf = [pf for pf in current_pfs if len(pf.vfs) > 0]
            if not pfs_with_vf:
                return await pvm.batch_process(tb=tb, del_pfs=del_pfs, del_vfs=del_vfs)

            num_pf_for_vf = random.randint(1, len(pfs_with_vf))
            pf_to_process = random.sample(pfs_with_vf, num_pf_for_vf)
            
            for pf in pf_to_process:
                vf_count = len(pf.vfs)
                pf_id = pf.pf_id
                vf_list = list(pf.vfs.values()) 
                tb.log.debug(f"_run_del_pfvf_test: vf_count {vf_count}  pf is {pf},vf_list is {vf_list}")
                if vf_count == 1:
                    del_pfs.append(pf_id)
                else:
                    max_del_vf = vf_count - 1
                    num_del_vf = random.randint(1, max_del_vf)
                    tb.log.debug(f"_run_del_pfvf_test: num_del_vf {num_del_vf}  ")
                    sorted_vf_ids = sorted(pf.vfs.keys(), reverse=True)
                    vf_to_del = sorted_vf_ids[:num_del_vf]
                    
                    for vf_id in vf_to_del:
                        del_vfs.append((pf_id, vf_id))

        return await pvm.batch_process(
            tb=tb,
            del_pfs=del_pfs,
            del_vfs=del_vfs
        )

    async def run_pvm_test_case(case_mode, stride_choice, tb):
        async def _run_single_op_steps(pre_step_coroutine):
            await Timer(1000, 'ns')
            await pre_step_coroutine
            await Timer(20, 'us')
            await _run_equal_loop()

        async def _run_equal_loop():
            for _ in range(10):
                await Timer(1000, 'ns')
                await pvm.batch_process(tb=tb, need_equal=True)
                await Timer(20, 'us')

        async def _run_add_then_del(add_coroutine):
            await Timer(1000, 'ns')
            await add_coroutine
            await Timer(20, 'us')
            await _run_equal_loop()
            await Timer(20, 'us')
            await _run_del_pfvf_test()
            await Timer(20, 'us')
            await _run_equal_loop()
            await Timer(20, 'us')

        mode_handlers = {
            "add_base": lambda: _run_single_op_steps(_run_add_basic_test(stride_choice, tb)),
            "single_min": lambda: _run_single_op_steps(_run_add_boundary_test("single_min", stride_choice, tb)),
            "single_max": lambda: _run_single_op_steps(_run_add_boundary_test("single_max", stride_choice, tb)),
            "single_max_pro": lambda: _run_single_op_steps(_run_add_boundary_test("single_max_pro", stride_choice, tb)),
            "single_full": lambda: _run_single_op_steps(_run_add_boundary_test("single_full", stride_choice, tb)),
            "full_pf": lambda: _run_single_op_steps(_run_add_boundary_test("full_pf", stride_choice, tb)),
            "max_vf_per_pf": lambda: _run_single_op_steps(_run_add_boundary_test("max_vf_per_pf", stride_choice, tb)),
            "del_base": lambda: _run_add_then_del(_run_add_boundary_test("max_vf_per_pf", stride_choice, tb)),
            "add_del_mix": lambda: _run_add_then_del(_run_add_basic_test(stride_choice, tb))}

        done = await pvm.init_common_regs(tb=tb)
        tb.log.debug(f"Start PVM test: case_mode={case_mode}, stride_choice={stride_choice}")

        while True:
            if case_mode not in mode_handlers:
                raise ValueError(f"Invalid testing case_mode: {case_mode}, optional values: {list(mode_handlers.keys())}")
            await mode_handlers[case_mode]()
            tb.log.info(f"Checking end condition - Current counter values:")
            tb.log.info(f"  non_posted_req_cnt: {tb.non_posted_req_cnt}")
            tb.log.info(f"  tlp_bypass_req_mwr_cnt: {tb.tlp_bypass_req_mwr_cnt}")
            tb.log.info(f"  Sum (non_posted + mwr): {tb.non_posted_req_cnt + tb.tlp_bypass_req_mwr_cnt} (expected: {tb.max_seq})")
            tb.log.info(f"  event_req_cnt: {tb.event_req_cnt}")
            tb.log.info(f"  event_rsp_cnt: {tb.event_rsp_cnt}")
            tb.log.info(f"  tlp_bypass2beq_cnt: {tb.tlp_bypass2beq_cnt}")
            tb.log.info(f"  tlp_bypass2doorbell_cnt: {tb.tlp_bypass2doorbell_cnt}")
            tb.log.info(f"  Sum ( beq + doorbell): {tb.tlp_bypass2beq_cnt + tb.tlp_bypass2doorbell_cnt} (expected: {tb.max_seq})")
            tb.log.info(f"  beq2emu_rsp_cnt: {tb.beq2emu_rsp_cnt} (expected: {tb.max_seq})")
            if tb.non_posted_req_cnt + tb.tlp_bypass_req_mwr_cnt == tb.max_seq and \
            tb.event_req_cnt == tb.event_rsp_cnt and \
            tb.tlp_bypass2beq_cnt + tb.tlp_bypass2doorbell_cnt == tb.max_seq and\
            tb.beq2emu_rsp_cnt == tb.max_seq:
                break
        await tb.test_case_end_queue.put(1)
        tb.log.debug("test_case_end_queue has put 1")
    ## beq2emu txq
    def _pad_data(data: bytes) -> bytes:
        padding_len = (Constants.DATA_ALIGNMENT - (len(data) % Constants.DATA_ALIGNMENT)) % Constants.DATA_ALIGNMENT
        return data + b'\x00' * padding_len

    def _build_txq_data(op_code: OpCode, hdr_bytes: bytes, data: bytes) -> bytes:
        padded_hdr = b'\x00' * (Constants.DATA_ALIGNMENT - len(hdr_bytes)) + hdr_bytes
        reversed_hdr = padded_hdr[::-1]

        if op_code in [OpCode.Cpl, OpCode.MRd, OpCode.CFGRd0, OpCode.CFGRd1]:
            return reversed_hdr
        elif op_code in [OpCode.CplD, OpCode.MWr, OpCode.CFGWr0, OpCode.CFGWr1]:
            return reversed_hdr + data
        return b''

    async def process_beq_txq(tb: int):
        for i in range(tb.max_seq):
            print(f"\rmax_seq is : {tb.max_seq}, beq to tlpbypass sequence is :{i+1}", end='', flush=True)
            tb.log.info(f"max_seq is : {tb.max_seq}, beq to tlpbypass sequence is :{i+1}", )
            op_code = random.choice([
                OpCode.Cpl, OpCode.CplD, OpCode.MRd, OpCode.MWr,
                OpCode.CFGRd0, OpCode.CFGRd1, OpCode.CFGWr0, OpCode.CFGWr1
            ])
            cpl_status = random.choice([ComplStatus.SC, ComplStatus.UR, ComplStatus.CRS, ComplStatus.CA])
            host_gen = random.randint(0, 255)
            qid = random.randint(0, 255)
            cpl_byte_count = random.randint(0, Constants.CPL_BYTE_COUNT_MAX)
            tag = random.randint(0, 255)
            cpl_id = random.randint(0, 2**15)
            req_id = random.randint(0, 2**15)
            first_be = random.randint(*Constants.BE_VALID_RANGE)
            last_be = random.randint(*Constants.BE_VALID_RANGE)
            addr = random.randint(0, Constants.ADDR_MAX)

            if op_code in [OpCode.Cpl, OpCode.MRd, OpCode.CFGRd0, OpCode.CFGRd1]:
                byte_length = Constants.DATA_ALIGNMENT
                data = b''
            else:
                byte_length = random.randint(1, 65)
                data = random.randbytes(byte_length)

            if op_code in [OpCode.Cpl, OpCode.CplD]:
                vf_active = tb.beq_rsp_cookie_cnt & 0x1
                bdf = (tb.beq_rsp_cookie_cnt >> 1) & Constants.BDF_MASK
                bar_range_low2  = (tb.beq_rsp_cookie_cnt >> 17) & Constants.BAR_RANGE_MASK
                bar_range = (tb.cookie_chk_en << 2) | bar_range_low2
            else:
                vf_active = 0
                bdf = 0
                bar_range = 0

            beq_hdr = Header(
                op_code=op_code.value,
                addr=addr,
                cpl_byte_count=cpl_byte_count,
                byte_length=byte_length,
                tag=tag,
                cpl_id=cpl_id,
                req_id=req_id,
                cpl_status=cpl_status.value,
                first_be=first_be,
                last_be=last_be,
                vf_active=vf_active,
                bdf=bdf,
                bar_range=bar_range
            )
            hdr_bytes = beq_hdr.build()

            padding_data = _pad_data(data)
            txq_data = _build_txq_data(op_code, hdr_bytes, data)

            txq_req = TlpBypassRsp(
                op_code=op_code,
                addr=addr,
                cpl_byte_count=cpl_byte_count,
                byte_length=byte_length,
                tag=tag,
                cpl_id=cpl_id,
                req_id=req_id,
                cpl_status=cpl_status,
                first_be=first_be,
                last_be=last_be,
                data=data,
                event=None
            )

            user0_low = 1 if op_code in [OpCode.Cpl, OpCode.CplD] else 0
            user0 = (host_gen << Constants.USER0_LOW_SHIFT) | user0_low
            req = BeqTxq(txq_req, qid, txq_data, user0, byte_length)
            await tb.beq_txq_queue.put(req)

            if op_code == OpCode.MRd:
                    tb.beq2emu_mrd_cnt = tb.beq2emu_mrd_cnt + 1
            if op_code == OpCode.MWr:
                tb.beq2emu_mwr_cnt = tb.beq2emu_mwr_cnt + 1
            if op_code in [OpCode.CFGRd0,OpCode.CFGRd1,OpCode.CFGWr0,OpCode.CFGWr1]:
                    tb.beq2emu_cfg_cnt = tb.beq2emu_cfg_cnt + 1

            if op_code in [OpCode.Cpl, OpCode.CplD]:
                step = 1
                tb.beq_rsp_cookie_cnt = (tb.beq_rsp_cookie_cnt + step) % Constants.COOKIE_MAX

        await tb.beq_req_end_queue.put(1)
        tb.log.debug("beq_req_end_queue has put 1")

    ## event
    async def process_event_req(tb):
        for i in range(tb.max_seq):
            print(f"\rmax_seq is : {tb.max_seq}, event         sequence is :{i+1}", end='', flush=True) 
            tb.log.info(f"max_seq is : {tb.max_seq}, event         sequence is :{i+1}", )
            event_vld = 1 if random.random() < 0.2 else 0
            event_dat = 3
            await tb.event_req_queue.put((event_vld, event_dat))
        await tb.event_end_queue.put(1)
        tb.log.debug("event_end_queue has put 1")

    async def read_dfx_reg():
        def check_equality(actual, expected, log_msg, assert_msg):
            if actual != expected:
                tb.log.error(log_msg.format(actual, expected))
                assert False, assert_msg
        tb.log.info(f"tlp bypass req src: non_posted_req_cnt={tb.non_posted_req_cnt}, tlp_bypass_req_mwr_cnt={tb.tlp_bypass_req_mwr_cnt}, total={tb.non_posted_req_cnt+tb.tlp_bypass_req_mwr_cnt}")
        tb.log.info(f"tlp bypass req sink: tlp_bypass2beq_cnt={tb.tlp_bypass2beq_cnt}, tlp_bypass2doorbell_cnt={tb.tlp_bypass2doorbell_cnt}")
        tb.log.info(f"beq tx: beq2emu_req_cnt={tb.beq2emu_req_cnt}, beq2emu_rsp_cnt={tb.beq2emu_rsp_cnt}")
        tb.log.info(f"event: event_req_cnt={tb.event_req_cnt}, event_rsp_cnt={tb.event_rsp_cnt}")
        tb.log.info(f"beq2emu: mrd={tb.beq2emu_mrd_cnt}, mwr={tb.beq2emu_mwr_cnt}, cfg={tb.beq2emu_cfg_cnt}")

        rdata0 = await tb.reg_rd_req(addr=0x400000)
        rdata1 = await tb.reg_rd_req(addr=0x400008)
        if rdata0 > 0 or rdata1 > 0:
            tb.log.error(f"DFX errors: err0={rdata0}, err1={rdata1}")
            assert False, "DFX module has errors."

        rdata2 = await tb.reg_rd_req(addr=0x400200)
        rdata3 = await tb.reg_rd_req(addr=0x400208)
        check_equality(
            rdata2, tb.max_seq % 2**32,
            "DFX tlp_req cnt mismatch: actual={}, expected={}",
            "DFX tlp_req cnt not equal to max_seq"
        )
        check_equality(
            rdata3, tb.max_seq % 2**32,
            "DFX tlp_cpl cnt mismatch: actual={}, expected={}",
            "DFX tlp_cpl cnt not equal to max_seq"
        )

        rdata4 = await tb.reg_rd_req(0x400210)
        event_cnt = rdata4 & 0xFF
        beq2emu_cnt = (rdata4 >> 8) & 0xFF
        doorbell_cnt = (rdata4 >> 16) & 0xFF
        emu2beq_cnt = (rdata4 >> 24) & 0xFF

        check_equality(
            event_cnt, tb.event_rsp_cnt % 256,
            "DFX event_cnt mismatch: actual={}, expected={}",
            "DFX event_cnt not equal to tb.event_rsp_cnt"
        )
        check_equality(
            beq2emu_cnt, tb.beq2emu_rsp_cnt % 256,
            "DFX beq2emu_cnt mismatch: actual={}, expected={}",
            "DFX beq2emu_cnt not equal to tb.beq2emu_rsp_cnt"
        )
        check_equality(
            doorbell_cnt, tb.tlp_bypass2doorbell_cnt % 256,
            "DFX doorbell_cnt mismatch: actual={}, expected={}",
            "DFX doorbell_cnt not equal to tb.tlp_bypass2doorbell_cnt"
        )
        check_equality(
            emu2beq_cnt, (tb.tlp_bypass2beq_cnt + tb.event_rsp_cnt) % 256,
            "DFX emu2beq_cnt mismatch: actual={}, expected={}",
            "DFX emu2beq_cnt not equal to tb.tlp_bypass2beq_cnt"
        )

        rdata5 = await tb.reg_rd_req(0x400218)
        req_mwr_dut_cnt = rdata5 & 0xFFFF
        req_mrd_dut_cnt = (rdata5 >> 16) & 0xFFFF
        check_equality(
            req_mwr_dut_cnt, tb.tlp_bypass_req_mwr_cnt,
            "DFX bypass mwr cnt mismatch: actual={}, expected={}",
            "DFX tlp_bypass_req_mwr_cnt not equal"
        )
        check_equality(
            req_mrd_dut_cnt, tb.tlp_bypass_req_mrd_cnt,
            "DFX bypass mwr cnt mismatch: actual={}, expected={}",
            "DFX tlp_bypass_req_mrd_cnt not equal"
        )

        rdata6 = await tb.reg_rd_req(0x400220)
        mrd_cnt = rdata6 & 0xFF
        mwr_cnt = (rdata6 >> 8) & 0xFF
        cfg_cnt = (rdata6 >> 16) & 0xFF

        check_equality(
            mrd_cnt, tb.beq2emu_mrd_cnt % 256,
            "DFX mrd_cnt mismatch: actual={}, expected={}",
            "DFX mrd_cnt not equal to beq2emu_mrd_cnt"
        )
        check_equality(
            mwr_cnt, tb.beq2emu_mwr_cnt % 256,
            "DFX mwr_cnt mismatch: actual={}, expected={}",
            "DFX mwr_cnt not equal to beq2emu_mwr_cnt"
        )
        check_equality(
            cfg_cnt, tb.beq2emu_cfg_cnt % 256,
            "DFX cfg_cnt mismatch: actual={}, expected={}",
            "DFX cfg_cnt not equal to beq2emu_cfg_cnt"
        )

        await Timer(500, 'ns')
        await tb.dfx_reg_queue.put(1)

    async def cookie_chk_en_process():
        random_time_us = random.randint(1, 10)
        tb.log.info(f"Cookie check enable: waiting random time {random_time_us:.1f}us ")
        
        await Timer(random_time_us, 'us')
        await tb.reg_wr_req(addr=0x10, data=random.randint(0, 0xFFFFFFFF))
        tb.cookie_chk_en = 1
        rdata0 = await tb.reg_rd_req(addr=0x10)
        tb.log.info(f"Cookie_chk_en reg readback: 0x{rdata0:08x}")

    async def match_fifo_pfull_process():
        while True:
            if fifo_pfull_en:
                tb.dut.u_emu.u1_emu_tlp_bypass_req_match.sim_fifo_rdy.value = 0
                await Timer(50000, 'ns')
                tb.dut.u_emu.u1_emu_tlp_bypass_req_match.sim_fifo_rdy.value = 1
                await Timer(50000, 'ns')
                if tb.test_done.is_set():
                    break
            else:
                break

    await cookie_chk_en_process()
    tlp_req_cr = cocotb.start_soon(process_tlp_bypass_req(tb))
    case_test_cr = cocotb.start_soon(run_pvm_test_case(case_mode,stride_choice, tb))
    beq_txq_cr = cocotb.start_soon(process_beq_txq(tb))
    event_cr = cocotb.start_soon(process_event_req(tb))
    match_fifo_pfull_cr = cocotb.start_soon(match_fifo_pfull_process())
    tlp_req_end_flag   = await tb.tlp_req_end_queue.get()
    beq_req_end_flag   = await tb.beq_req_end_queue.get()
    event_end_flag  = await tb.event_end_queue.get()
    test_case_end_flag  = await tb.test_case_end_queue.get()
    await Timer(50000, 'ns')
    read_dfx_reg_cr = cocotb.start_soon( read_dfx_reg())
    dfx_reg_flag   = await tb.dfx_reg_queue.get()
    await Timer(50000, 'ns')

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = [0 for _ in range(1000)] + seed + [1 for _ in range(1000)]
    return itertools.cycle(seed)


ding_robot.ding_robot()

if cocotb.SIM_NAME:
    for test in [run_test_emu]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None,cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.add_option("case_mode", ["add_base","single_min", "single_max","single_max_pro", "single_full","full_pf","max_vf_per_pf","del_base", "add_del_mix"])#"add_base", "single_min", "single_max", "single_max_pro", "single_full", "full_pf", "max_vf_per_pf", "del_base", "add_del_mix"])
        factory.add_option("stride_choice", [0,1,2,3,4,5])
        factory.add_option("cookie_limit_mod", [True, False])
        factory.add_option("fifo_pfull_en", [True, False])
        factory.generate_tests()

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)

