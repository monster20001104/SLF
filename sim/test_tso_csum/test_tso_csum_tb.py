#******************************************************************************
#* 文件名称 : test_tso_csum_tb.py
#* 作者名称 : matao
#* 创建日期 : 2025/05/23
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   05/23       matao       初始化版本
#******************************************************************************/
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator
import scapy
import binascii
from io import StringIO
from contextlib import redirect_stdout
import time

import cocotb
from cocotb.log import SimLog,  SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Ether, IP, TCP, hexdump, IPv6, UDP, ICMP,  IPOption, LLC, SNAP, IPOption_Router_Alert, IPOption_Timestamp, IPOption_Security
from scapy.layers.l2 import Dot1Q 
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory


sys.path.append('../common')

from bus.beq_data_bus import BeqBus
from monitors.beq_data_bus import BeqRxqSlave
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster
from vio_nettx_data_bus import VionettxTxqMaster, VionettxBus, VirtioHeader
from vio_nettx_data_bus import TCPCsumCalcReqSource, TCPCsumCalcReqBus, TCPCsumCalcRspSink, TCPCsumCalcRspBus
from network_packet_processing import build_network_packet, process_network_packet, compare_network_packet


def build_vio_nettx_packet(network_data, virtio_en = 0, data_length = None,
                          virtio_flags = 0,virtio_gso_type = 0, virtio_gso_size = 15, err = 0):
    """
    Constructing Virtio network transmission packets based on the virtio_en parameter
    
    When ` virtio-en=1 `, generate a data packet containing VirtioHeader, suitable for Virtio protocol communication
    When ` virtio_de=0 `, generate a random data payload that can be used to test or simulate abnormal data

    parameter:
        network_data: network_packet.build()
        virtio_en: Control whether to add VirtioHeader (0=random data, 1=build VirtioHeader)
        data_length: Random data length (valid when virtio_en=0)
        virtio_flags/virtio_gso_type/virtio_gso_size: Virtio hdr parameter
        err: Data bus sideband error signal, an error occurred in a certain beat
        region_type: The type of err signal in the data segmentation area, 0 = no err, 4 = random data contains errors
        segment_index: Location of data error
    """
    region_type = 0
    segment_index = 0
    hdr_fields = None
    if virtio_en == 0:
        if data_length is None:
            data_length = len(network_data)  
        data = bytearray([random.randint(0, 255) for _ in range(data_length)])
        if data_length > 26: ##Prevent detection of IP protocol
            data[24] = 0x12 
            data[25] = 0x34 
        if data_length > 30:
            data[28] = 0x56 
            data[29] = 0x78 
        data = bytes(data)
        if err :
            total_segments = (data_length + 31) // 32
            region_type = 4 
            segment_index = random.randint(0, total_segments - 1)
        return data, region_type, segment_index
    elif virtio_en == 1:
        hdr_fields = {
            "num_buffers"   : random.randint(0, 2**16 - 1),
            "csum_offset"   : random.randint(0, 2**16 - 1),
            "csum_start"    : random.randint(0, 2**16 - 1),
            "gso_size"      : virtio_gso_size,
            "hdr_len"       : random.randint(0, 2**16 - 1),
            "gso_type_ecn"  : random.randint(0, 2**5 - 1),
            "gso_type"      : virtio_gso_type,
            "flags_rsv"     : random.randint(0, 2**7 - 1),
            "flags"         : virtio_flags
        }
        virtio_hdr = VirtioHeader(**hdr_fields)
        data = virtio_hdr.build()[::-1] + network_data
        return data, region_type, segment_index
    else:
        raise ValueError("virtio_en must be 0 or 1")

def tcp_checksum_calc(data_num: int = 8) -> tuple:
    word_bit_width = 16          
    word_max_value = (1 << word_bit_width) - 1  
    bits_per_block = 256        
    words_per_block = bits_per_block // word_bit_width  

    random_data = []
    for _ in range(data_num):
        block_words = [random.randint(0, word_max_value) for _ in range(words_per_block)]
        block_int = 0
        for word in reversed(block_words):  
            block_int = (block_int << word_bit_width) | word
        random_data.append(block_int)
    
    sum_result = 0
    for block in random_data:
        for i in range(words_per_block):
            word = (block >> (i * word_bit_width)) & word_max_value
            sum_result += word
    
    while sum_result > word_max_value:
        carry = sum_result >> word_bit_width
        low_bits = sum_result & word_max_value
        sum_result = carry + low_bits 

    checksum = (~sum_result) & word_max_value
    
    return checksum, random_data

class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
        #net2tso_csum tso_csum2net
        self.net_txq    = VionettxTxqMaster(VionettxBus.from_prefix(dut, "net2tso"), dut.clk, dut.rst)
        self.beq_rxq    = BeqRxqSlave( BeqBus.from_prefix(dut, "tso2beq"), dut.clk, dut.rst)

        #net2tso_parser Is the reference mode correct for comparison
        #self.net_par    = VionettxTxqMaster(VionettxBus.from_prefix(dut, "vio_net2tso"), dut.clk, dut.rst)

        #csr
        self.regconf    = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)

        #tcp calc csum
        self.tcpcalc_req = TCPCsumCalcReqSource(TCPCsumCalcReqBus.from_prefix(dut, "tcp_calc_i_csum"), dut.clk, dut.rst)
        self.tcpcalc_rsp = TCPCsumCalcRspSink(TCPCsumCalcRspBus.from_prefix(dut, "tcp_calc_o_csum"), dut.clk, dut.rst)

        self.ipcalc_req_queue  = Queue(maxsize=8)
        self.tcpcalc_req_queue = Queue(maxsize=8)
        self.tcpcalc_end_queue = Queue(maxsize=8)
        self.net_req_queue     = Queue(maxsize=32)
        self.net_req2rsp_queue = Queue(maxsize=32)
        self.net_pro2rsp_queue = Queue(maxsize=32)
        self.net_pro2par_queue = Queue(maxsize=32)
        self.reg_rd_queue_rsp  = Queue(maxsize=8)
        self.dfx_reg_queue     = Queue(maxsize=8)

    async def reg_wr_req(self, addr,data):
        await self.regconf.write(addr,data,True)

    async def reg_rd_req(self, addr):
        addr = addr
        rddata = await self.regconf.read(addr)
        await self.reg_rd_queue_rsp.put(rddata)
   
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
            self.net_txq.set_idle_generator(generator)
            self.tcpcalc_req.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        if generator:
            self.beq_rxq.set_backpressure_generator(generator)
            self.tcpcalc_rsp.set_backpressure_generator(generator)

err_pkt_cnt = 0
real_cnt = 0

async def run_test_tso(dut, idle_inserter, backpressure_inserter):
    global err_pkt_cnt
    time_seed = int(time.time())
    random.seed(time_seed)
    tb = TB(dut)
    tb.log.info(f"set time_seed {time_seed}")
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    ###################### calc module sim #####################
    async def tcp_csum_calc_req( min_data_num=1, max_data_num=10, max_seq=4):
        for i in range(max_seq):
            data_num = random.randint(min_data_num, max_data_num)
            tcp_checksum, random_data = tcp_checksum_calc(data_num)
            length = len(random_data)
            random_info = random.randint(0, 65535)
            random_err = random.randint(0, 1)
            for i, data in enumerate(random_data):
                eop = (i == length - 1)
                obj = tb.tcpcalc_req._transaction_obj()
                obj.data = data
                obj.eop = eop
                obj.info = random_info
                obj.err  = random_err
                await tb.tcpcalc_req.send(obj)
            await tb.tcpcalc_req_queue.put((tcp_checksum, random_info, random_err ))

    async def tcp_csum_calc_rsp():
        req_cnt = 0
        while True:
            if req_cnt == max_seq-1 :
                await tb.tcpcalc_end_queue.put(1)
                break
            tcp_checksum, random_info, random_err = await tb.tcpcalc_req_queue.get()
            calc_result = await tb.tcpcalc_rsp.recv()
            dut_result = int(calc_result.data)
            dut_info = int(calc_result.info)
            dut_err  = int(calc_result.err)
            if tcp_checksum == dut_result :
                tb.log.info("///////////tcp_calc_pass//////////////")
                tb.log.info("tcp_checksum:{:04X}".format(tcp_checksum)) 
            else:
                tb.log.info("///////////tcp_calc_failed//////////////")
                tb.log.info("sim_sum:{:04X}".format(tcp_checksum)) 
                tb.log.info("calc_sum:{:04X}".format(dut_result)) 
                assert False, "tcp calc req and rsp are not equal."
            if random_info == dut_info :
                tb.log.info("///////////tcp_info_pass//////////////")
                tb.log.info("random_info:{:04X}".format(random_info)) 
            else:
                tb.log.info("///////////tcp_info_failed//////////////")
                tb.log.info("sim_info:{:04X}".format(random_info)) 
                tb.log.info("calc_info:{:04X}".format(dut_info)) 
                assert False, "tcp info req and rsp are not equal."
            if random_err == dut_err :
                tb.log.info("///////////tcp_err_pass//////////////")
                tb.log.info("random_err:{:04X}".format(random_err)) 
            else:
                tb.log.info("///////////tcp_err_failed//////////////")
                tb.log.info("sim_err:{:04X}".format(random_err)) 
                tb.log.info("calc_err:{:04X}".format(dut_err)) 
                assert False, "tcp err req and rsp are not equal."
            req_cnt = req_cnt + 1

    ###################### Comparison reference mode ###############
    async def _process_net2par_req():
        while True:
            result_data = await tb.net_pro2par_queue.get()
            #await tb.net_par.send(88,result_data, 0, 0, 0)

    ###################### tso_csum module sim #####################
    async def vio_net_req(eth_flag, ip_version, transport_protocol, ip_option, trans_option, packet_length, ip_len_err,
                        virtio_en, virtio_flags, virtio_gso_type, virtio_gso_size, err, end_flag, tso_en, csum_en):
        network_data, network_packet, network_region_type, network_segment_index, payload_relative_start, is_crossing_segment = build_network_packet(eth_flag = eth_flag, ip_version = ip_version, 
                    transport_protocol = transport_protocol, virtio_gso_size = virtio_gso_size, ip_option = ip_option, trans_option = trans_option, packet_length = packet_length, 
                    ip_len_err = ip_len_err, err = err)
        
        req_data, random_region_type, random_segment_index = build_vio_nettx_packet(network_data, virtio_en = virtio_en, data_length = packet_length, 
                                                                virtio_flags = virtio_flags, virtio_gso_type = virtio_gso_type, virtio_gso_size = virtio_gso_size, err=err)
        
        req_qid = random.randint(0, 255)
        req_gen = random.randint(0, 255)
        if virtio_en==1:
            region_type   = network_region_type
            segment_index = network_segment_index
        else :
            region_type   = random_region_type
            segment_index = random_segment_index
        await tb.net_txq.send(req_qid,req_data, 0, err, segment_index, req_gen, tso_en, csum_en)
        await tb.net_req2rsp_queue.put((req_qid, req_gen, req_data, eth_flag, ip_version, transport_protocol, ip_option, trans_option, packet_length, ip_len_err,
                virtio_en, virtio_flags, virtio_gso_type, virtio_gso_size, err, region_type, segment_index, payload_relative_start, is_crossing_segment,end_flag, tso_en, csum_en))
    
    async def _process_net_req_process():
        global real_cnt
        real_cnt = 0
        while True:

            req_qid, req_gen, req_data, eth_flag, ip_version, transport_protocol, ip_option, trans_option, packet_length, ip_len_err,virtio_en, virtio_flags,\
            virtio_gso_type, virtio_gso_size, err, region_type, segment_index, payload_relative_start, is_crossing_segment, end_flag, tso_en, csum_en = await tb.net_req2rsp_queue.get()
            tb.log.info(
                        "Parameters: req_data={}, eth_flag={}, ip_version={}, transport_protocol={}, "
                        "ip_option={}, trans_option={}, ip_len_err={}, virtio_en={}, virtio_flags={}, "
                        "virtio_gso_type={}, virtio_gso_size={}, err={}, region_type={}, "
                        "segment_index={}, payload_relative_start={}, is_crossing_segment={}".format(
                            1111, eth_flag, ip_version, transport_protocol,
                            ip_option, trans_option, ip_len_err,
                            virtio_en, virtio_flags, virtio_gso_type,
                            virtio_gso_size, err, region_type,
                            segment_index, payload_relative_start, is_crossing_segment
                            )
                        )
            results_data = process_network_packet(req_data, eth_flag, ip_version, transport_protocol, ip_option, trans_option, packet_length, ip_len_err,
                 virtio_en, virtio_flags, virtio_gso_type, virtio_gso_size, err, region_type, segment_index, payload_relative_start, is_crossing_segment, tso_en, csum_en)
            #real_cnt = real_cnt + len(results_data)
            
            if results_data:
                for result_data, ref_virtio_flags, flag in results_data:
                    real_cnt = real_cnt + 1
                    tb.log.info(" The real_cnt  is {}".format(real_cnt))
                    tb.log.info(" The process qid is {}, flag is :{} ,packet_length is {}, data_num is {} ".format(req_qid, flag,packet_length, len(results_data)))
                    tb.log.info(" The region_type is {}, segment_index is :{} ,payload_relative_start is {}, is_crossing_segment is {} ".format(region_type, segment_index,payload_relative_start,is_crossing_segment))
                    await tb.net_pro2rsp_queue.put((ref_virtio_flags, flag, req_qid,req_gen,result_data, eth_flag, ip_version,transport_protocol,ip_option,trans_option,packet_length,
                    virtio_en, virtio_flags,virtio_gso_type,virtio_gso_size,err,region_type,segment_index,payload_relative_start, end_flag, tso_en, csum_en))
                    #await tb.net_pro2par_queue.put(result_data)

    async def _process_beq_rsp():
        rsp_pkt_cnt = 1
        while True:
            rsp = await tb.beq_rxq.recv()
            tb.log.info("  33333 rsp_pkt_cnt is {}, real_cnt is {}".format(rsp_pkt_cnt,real_cnt))
            tb.log.info("  44444 rsp_pkt_cnt is {}, real_cnt is {}".format(rsp_pkt_cnt,real_cnt))
            ref_virtio_flags, len32K_flag, req_qid, req_gen, result_data, eth_flag, ip_version,transport_protocol,ip_option,trans_option,packet_length,\
                virtio_en, virtio_flags,virtio_gso_type,virtio_gso_size,err,region_type,segment_index,payload_relative_start, end_flag, tso_en, csum_en = await tb.net_pro2rsp_queue.get()
            tb.log.info(" The rsp req_qid is :{}, rsp_qid is :{} ,packet_length is {} ".format(req_qid, rsp.qid, packet_length))
            com_result, error_list = compare_network_packet(len32K_flag, rsp.data, result_data, eth_flag, ip_version, transport_protocol, ip_option, trans_option, packet_length,\
                 virtio_en, virtio_flags, virtio_gso_type, virtio_gso_size,rsp_pkt_cnt,err,region_type,segment_index,payload_relative_start, tso_en, csum_en)

            rsp_qid = rsp.user1 & 0xFFFF
            rsp_gen = (rsp.user1 >> 16) & 0xFF
            if rsp.qid != req_qid and rsp_qid != req_qid:
                tb.log.info(" The returned qid does not match {},{},{} ".format(rsp.qid,req_qid,rsp_qid))
                assert False,"qid no match"
            if rsp_gen != req_gen:
                tb.log.info(" The returned gen does not match {},{} ".format(rsp_gen,req_gen))
                assert False,"gen no match"
            if rsp.data != result_data:
                tb.log.info(" The returned data does not match {},{} ".format(rsp_pkt_cnt,packet_length))
                #assert False,"no match"
                print(f"data no match")
            if not com_result:
                tb.log.info(" The {} result returned failed to compare!!! ".format(rsp_pkt_cnt))
                for error in error_list:
                    tb.log.info(" {} ".format(error))
                assert False, error_list
            pkt_sop = (rsp.user0 >> 0) & 1 # bit0: SOP
            pkt_eop = (rsp.user0 >> 1) & 1 # bit1: EOP
            virtio_flags = (rsp.user0 >> 8) & 0xFFFFFFFF  # bit39:8: virtio_flags
            if len32K_flag == 0:
                expected_sop = 0
                expected_eop = 0
            elif len32K_flag == 1:
                expected_sop = 0
                expected_eop = 1
            elif len32K_flag == 2:
                expected_sop = 1
                expected_eop = 0
            elif len32K_flag == 3:
                expected_sop = 1
                expected_eop = 1
            else:
                raise ValueError(f"Invalid len32K_flag value: {len32K_flag}")
            if pkt_sop != expected_sop:
                tb.log.info(" The returned net sop does not match {},{} ".format(expected_sop,pkt_sop))
                assert False,"net sop no match"
            if pkt_eop != expected_eop:
                tb.log.info(" The returned net eop does not match {},{} ".format(expected_eop,pkt_eop))
                assert False,"net eop no match"
            if virtio_flags != ref_virtio_flags:
                tb.log.info(" The returned virtio flags does not match {},{} ".format(virtio_flags,ref_virtio_flags))
                assert False,"net virtio flags no match"
            tb.log.info("  666 rsp_pkt_cnt is {}, real_cnt is {},endflag is {}".format(rsp_pkt_cnt,real_cnt,end_flag))
            if rsp_pkt_cnt == real_cnt and end_flag ==1:
                tb.log.info("  5555 rsp_pkt_cnt is {}, real_cnt is {}".format(rsp_pkt_cnt,real_cnt))
                break
            rsp_pkt_cnt = rsp_pkt_cnt + 1 
        await tb.reg_rd_req(0x0)
        

    async def read_dfx_reg(max_seq):
        tso_en_addr = 0x000000
        await tb.reg_rd_req(addr = tso_en_addr)
        tso_en_rddata = await tb.reg_rd_queue_rsp.get()

        csum_en_addr = 0x000008
        await tb.reg_rd_req(addr = csum_en_addr)
        csum_en_rddata = await tb.reg_rd_queue_rsp.get()

        addr0 = 0x01000
        await tb.reg_rd_req(addr = addr0)
        rdata0 = await tb.reg_rd_queue_rsp.get()
        rdata0 = int(rdata0) & 0xFFFF
        if rdata0 > 0 :
            tb.log.info("There are some DFX errors in module err0 is 0x{:x}, ".format(rdata0))
            assert False, " There are some DFX errors in module."
            
        addr10 = 0x001100
        await tb.reg_rd_req(addr = addr10)
        rdata10 = await tb.reg_rd_queue_rsp.get()

        addr11 = 0x001108
        await tb.reg_rd_req(addr = addr11)
        rdata11 = await tb.reg_rd_queue_rsp.get()

        addr2 = 0x001200
        await tb.reg_rd_req(addr = addr2)
        rdata2 = await tb.reg_rd_queue_rsp.get()
        net2tso_cnt  = rdata2 & 0xFFFF
        tso2beq_cnt  = (rdata2 >> 16) & 0xFFFF
        MAX_CNT = 2**16
        if (net2tso_cnt != max_seq % MAX_CNT) :
            tb.log.info("DFX cnt are not equal net2tso_cnt is {}, sim_net2tso_cnt is {}".format(net2tso_cnt, max_seq % MAX_CNT))
            assert False, " There are some DFX cnt are not equal in net2tso_cnt."
        else :
            tb.log.info("DFX cnt are equal net2tso_cnt is {}, sim_net2tso_cnt is {}".format(net2tso_cnt, max_seq % MAX_CNT))
        if (tso2beq_cnt != real_cnt % MAX_CNT) :
            tb.log.info("DFX cnt are not equal tso2beq_cnt is {}, sim_tso2beq_cnt is {}".format(tso2beq_cnt, real_cnt % MAX_CNT))
            assert False, " There are some DFX cnt are not equal in tso2beq_cnt."
        else :
            tb.log.info("DFX cnt are equal tso2beq_cnt is {}, sim_tso2beq_cnt is {}".format(tso2beq_cnt, real_cnt % MAX_CNT))
        #########Test write clear zero
        data_clr = 0xFFFF_FFFF_FFFF_FFFF
        await tb.reg_wr_req(addr = addr2, data = data_clr)
        await tb.reg_rd_req(addr = addr2)
        rdata2_clr = await tb.reg_rd_queue_rsp.get()
        rdata2_clr = int((rdata2_clr & 0xFFFF_FFFF_FFFF_FFFF))

        if rdata2_clr != 0 :
            tb.log.info("rdata2_clr is {} ".format(rdata2_clr))
            assert False, " soft write 1 to clear cnt is failed!!"
        await Timer(500, 'ns')
        await tb.dfx_reg_queue.put(1)
    
    await tb.cycle_reset()
    await Timer(50000, 'ns')
    cocotb.start_soon(_process_net_req_process())
    cocotb.start_soon(_process_beq_rsp())
    #cocotb.start_soon(_process_net2par_req())

    #debug
    DEBUG_ENABLED = False #False
    DEBUG_PARAMS = {
    "eth_flag": 0,
    "ip_version": 6,
    "transport_protocol": "tcp",
    "ip_option": 0,
    "trans_option": 1,
    "ip_len_err": 0,
    "virtio_en": 0,
    "virtio_flags": 0,
    "virtio_gso_type": 4,
    "err": 1,
    "end_flag": 0,
    "packet_length": 1,
    "virtio_gso_size": 2, 
    "tso_en": 1,
    "csum_en": 1
        }
    #short pkt test
    SHORT_PACKET_MIN = 13
    SHORT_PACKET_MAX = 32
    SHORT_PARAMS = {
    "eth_flag": 0,
    "ip_version": 6,
    "transport_protocol": "tcp",
    "ip_option": 0,
    "trans_option": 1,
    "ip_len_err": 0,
    "virtio_en": 0,
    "virtio_flags": 0,
    "virtio_gso_type": 4,
    "err": 0,
    "end_flag": 0,
    "packet_length": 1,
    "virtio_gso_size": 2, 
    "tso_en": 1,
    "csum_en": 1
        }
    #normal test 
    param_options = {
        "eth_flag": [0,1,2], #0=IP, 1=VLAN, 2=LLC
        "ip_version": [4,6],  #4=ipv4, 6= ipv6
        "transport_protocol": ["tcp", "udp", "icmp"],#"tcp", "udp", "icmp"
        "ip_option": [0,1], #0,1
        "trans_option": [0,1], #0,1
        "ip_len_err"   : [0,1],#0,1
        "virtio_en": [0,1], #0,1
        "virtio_flags": [0,1],#0,1
        "virtio_gso_type": [1,0,3,4], #0=none, 1=tcpv4, 3=udp, 4=tcpv6
        "err":[0,1],#0=sbd no err, 1= sbd err
        "end_flag":[0],#end flag must be 0
        "tso_en": [0, 1],
        "csum_en": [0, 1]
        }
    PACKET_LENGTH_VIOEN0_MIN = 1#1   # virtio_en=0时最小160
    PACKET_LENGTH_VIOEN1_MIN = 260#160 # virtio_en=1时最小160
    PACKET_LENGTH_MAX = 64*1024    # 最大64*1024
    VIRTIO_GSO_MIN = 128           # virtio_gso_size最小值,协议500byte,确定最小拍，最小值暂定160
    VIRTIO_GSO_MAX = 1500          # virtio_gso_size最大值,最大1500

    max_seq = 50000
    err_pkt_cnt = 0
    
    for i in range(max_seq):
        if i < max_seq - 1:
            if DEBUG_ENABLED:
                params = DEBUG_PARAMS.copy()
            else:
                if i < max_seq * 9 // 10: 
                    params = {k: random.choice(v) for k, v in param_options.items()}
                    min_len = PACKET_LENGTH_VIOEN1_MIN if params["virtio_en"] == 1 else PACKET_LENGTH_VIOEN0_MIN
                    params["packet_length"] = random.randint(min_len, PACKET_LENGTH_MAX)
                    params["virtio_gso_size"] = random.randint(VIRTIO_GSO_MIN, VIRTIO_GSO_MAX)
                else:
                    params = SHORT_PARAMS.copy()
                    params["packet_length"] = random.randint(SHORT_PACKET_MIN, SHORT_PACKET_MAX)
            await vio_net_req(**params)
            param_str = ", ".join([f"{k}={v}" for k, v in params.items()])
            tb.log.info(f"Test {i+1}/{max_seq}: {param_str}")
            if params["ip_len_err"] == 1 and params["virtio_en"] == 1 and \
                params["eth_flag"] in [0, 1] and params["ip_version"] in [4, 6]:
                err_pkt_cnt += 1
        else :
            await vio_net_req(eth_flag=0, ip_version=4,transport_protocol='tcp',ip_option=0,trans_option=0,packet_length=100,ip_len_err=0,\
                        virtio_en=0, virtio_flags=0,virtio_gso_type=0,virtio_gso_size=160,err=0,end_flag=1,tso_en=1,csum_en=1)
    
    tb.log.info(f"maxseq :{max_seq}, len_err_cnt :{err_pkt_cnt}")
    await Timer(100000, 'ns')
    rsp_end = await tb.reg_rd_queue_rsp.get()
    cocotb.start_soon(tcp_csum_calc_req(1, 100, max_seq))
    cocotb.start_soon(tcp_csum_calc_rsp())
    tcp_calc_en_flag = await tb.tcpcalc_end_queue.get()
    ##dfx rd
    read_dfx_reg_cr = cocotb.start_soon( read_dfx_reg(max_seq))
    dfx_reg_flag0   = await tb.dfx_reg_queue.get()
    await Timer(10000, 'ns')

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

if cocotb.SIM_NAME:
    for test in [run_test_tso]:
        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)


############调试用#########
#packet.show2()#显示数据包的结构化信息，包括各层字段的值，并自动计算校验和等动态字段
#packet.show()#显示原始数据包内容，不重新计算校验和等动态字段
#hexdump(packet)#以十六进制和 ASCII 形式显示数据包的原始字节内容
#捕获网络报文并打印到log文件中，如下
#f = StringIO()
#with redirect_stdout(f):
#    network_packet.show2()
#output = f.getvalue()
#tb.log.info("build11111 {} ".format(output))
