#!/usr/bin/env python3
################################################################################
#  文件名称 : test_virtio_blk_upstream_tb.py
#  作者名称 : cui naiwan
#  创建日期 : 2025/07/09
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/09     cui naiwan   初始化版本
################################################################################
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator
import struct


import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union, Dict, Any
from cocotb.regression import TestFactory
from cocotb.handle import Force, Release

from defines import *

sys.path.append('../../common')
from bus.beq_data_bus import BeqBus
from drivers.beq_data_bus import BeqTxqMaster
from bus.tlp_adap_dma_bus import DmaReadBus, DmaWriteBus
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace, MemoryRegion
from backpressure_bus import define_backpressure
from enum import Enum, unique

from virtio_ctx_ctrl import *
from queue import Empty  
from bus.mlite_bus import MliteBus
from drivers.mlite_bus import MliteBusMaster

class data_element(NamedTuple):
    qid: int
    data: bytearray
    user0: int
    user1: int
    header: Dict[str, Any]
    region: MemoryRegion

#Generate multiple unique random IDs within a specified range
def gen_unique_ids(num, start, end):
    if num > (end - start):
        raise ValueError(f"Not enough unique IDs between {start} and {end}")
    return random.sample(range(start, end), num)

def gen_data(length):
    data = bytearray()
    cnt = 0
    while cnt < length:
        chunk_size = min(256, length - cnt)
        chunk = bytearray([random.randint(0, 255) for _ in range(chunk_size)])
        data += chunk
        cnt += chunk_size
    return bytes(data)

# Helper function to generate valid buffer header
def generate_buffer_header(qid, vq_gen, flags, desc_index, host_addr, used_length, used_idx, magic_num):
    header = bytearray()
    
    # VQ GID (16b)
    header.extend(qid.to_bytes(2, 'little'))
    
    # VQ Gen (8b)
    header.extend(vq_gen.to_bytes(1, 'little'))

    #8b 0x00
    header.extend(b'\x00')
    
    # Descriptor Index (16b)
    header.extend(desc_index.to_bytes(2, 'little'))

    # Flags (16b)
    header.extend(flags.to_bytes(2, 'little'))
       
    # Host Buffer Address (64b)
    header.extend(host_addr.to_bytes(8, 'little'))
    
    # VirtIO Used Length (32b)
    header.extend(used_length.to_bytes(4, 'little'))
    
    # used_idx (16b)
    header.extend(used_idx.to_bytes(2, 'little'))
    
    # magic_num (16b) = 0xc0de
    header.extend(magic_num.to_bytes(2, 'little'))
    
    # Pad to 64 bytes
    header.extend(b'\x00' * (64 - len(header)))
    
    return header

async def packet_gen(chn, ref_queues, max_seq, qid_array, tb, ctx_ctrl, max_pkt_len=4096):
    tb.log.info(f"packet_gen start")
    vq_gens = {}

    for _ in range(max_seq):
        qid = random.choice(qid_array)

        if qid not in vq_gens:
            vq_gen = random.randint(0, 255)
            vq_gens[qid] = vq_gen
            dev_id = random.randint(0, 0x3FF)  # dev_id
            bdf = random.randint(0, 0xFFFF)    # bdf

            forced_shutdown_is_0 = random.random() > 0  #0.2

            forced_shutdown = 0 if forced_shutdown_is_0 else 1

            await ctx_ctrl.create_queue(
                qid=qid,
                dev_id=dev_id,
                bdf=bdf,
                generation=vq_gen, 
                forced_shutdown=forced_shutdown
            )
            tb.log.debug(f"Created ctx for qid={qid}, generation={vq_gen}")

        use_correct_gen = random.random() > 0 #0.2

        if use_correct_gen:
            vq_gen = vq_gens[qid]
        else:
            vq_gen = (vq_gens[qid] + random.randint(1, 255)) % 256

        use_correct_magic = random.random() > 0  #0.1
        magic_num = 0xC0DE if use_correct_magic else random.randint(0, 0xFFFF)

        #user0 = random.randint(0, 2**40-1)
        user1 = random.randint(1, 2**64-1) #avoid 0
        
        payload_size = random.randint(1, max_pkt_len)

        region = tb.mem.alloc_region(payload_size)  #allocate mem
        host_addr = region.base
        user0 = host_addr

        # Generate header fields
        flags = random.randint(0, 1)  # Random Next Bit
        desc_index = random.randint(0, 0xFFFF)
        used_length = random.randint(1, 0xFFFF)  
        used_idx = random.randint(0, 0xFFFF)
        
        # Generate buffer header
        header = generate_buffer_header(qid, vq_gen, flags, desc_index, host_addr=host_addr, used_length=used_length, used_idx=used_idx, magic_num=magic_num)
        
        # Override magic number if needed
        if not use_correct_magic:
            header = header[:-2] + struct.pack('<H', magic_num)

        # Generate payload
        payload = gen_data(payload_size)
        
        # Combine header and payload
        data = bytes(header + payload)

        # Save header information for later verification
        header_info = {
            'qid': qid,
            'vq_gen': vq_gen,
            'flags': flags,
            'desc_index': desc_index,
            'host_addr': host_addr,
            'used_length': used_length,
            'used_idx': used_idx,
            'magic_num': magic_num,
            'valid':use_correct_gen and use_correct_magic and forced_shutdown_is_0,
            'payload_size':payload_size
        }

        tb.log.debug(f"packet_gen qid={qid}")
        await chn.send(qid, data, user0, user1)  
        elem = data_element(qid, data, user0, user1, header_info, region=region)
        await ref_queues[qid].put(elem)  
        tb.log.debug("packet_gen end qid={} pkt_len={}".format(qid, payload_size))

class TB(object):
    def __init__(self, dut):
        self.dut = dut
        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
        self.dma_req_queue = Queue()
        self.dma_wr_req_monitor = cocotb.start_soon(self._monitor_dma_wr_req())
        self.completed_host_addrs = set()
        self.dma_wr_rsp_handler = cocotb.start_soon(self._handle_dma_wr_rsp())
        self.dma_completed_event = Event()
        self.dma_events = {}
        self.dma_lock = Lock()

        self.mem = Pool(None, 0, size=2**64, min_alloc=64)

        self.csrBusMaster = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), dut.clk)
        self.beq2blk   = BeqTxqMaster(BeqBus.from_prefix(dut, "beq2blk")  , dut.clk, dut.rst)
        self.wrusedinfo = WrusedinfoSink(WrusedinfoBus.from_prefix(dut, "wr_used_info"), dut.clk, dut.rst)
        self.blkupstreamctxRdTbl = BlkupstreamCtxRdTbl(BlkupstreamCtxRdReqBus.from_prefix(dut, "blk_upstream_ctx"), BlkupstreamCtxRdRspBus.from_prefix(dut, "blk_upstream_ctx"), None, dut.clk, dut.rst)
        self.dmaWrDataIf = DmaRam(DmaWriteBus.from_prefix(dut, "dma_data"), None, dut.clk, dut.rst, mem=self.mem)
        self.blkupstreamptrIf = BlkupstreamPtrTblIf(BlkupstreamPtrRdReqBus.from_prefix(dut, "blk_upstream_ptr"), BlkupstreamPtrRdRspBus.from_prefix(dut, "blk_upstream_ptr"), BlkupstreamPtrWrBus.from_prefix(dut, "blk_upstream_ptr"), dut.clk, dut.rst)
        self.virtio_ctx = virtio_ctx_ctrl(dut.clk, self.blkupstreamctxRdTbl, self.blkupstreamptrIf)
        #self.ref_queues = {}
        self.ref_queues: Dict[int, Queue] = {}
        self.doing = True

    def stop(self):
        self.doing = False

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
        await Timer(2, "us")

    def set_idle_generator(self, generator=None):
        self.dmaWrDataIf.set_idle_generator(generator)
        self.beq2blk.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        self.wrusedinfo.set_backpressure_generator(generator)
        self.dmaWrDataIf.set_backpressure_generator(generator)

    def _final_report(self, qid, total_pkts, drop_pkts, recv_pkts):
        #gen final report
        self.log.info(
            f"=== Q{qid} ===\n"
            f"total pkts: {total_pkts}\n"
            f"hw_drop_cnt: {drop_pkts}\n"
            f"recv_pkts: {recv_pkts}\n"
            "=================="
        )

    async def _monitor_dma_wr_req(self):
        while self.doing:
            await RisingEdge(self.dut.clk)
            if self.dut.dma_data_wr_req_if.vld.value and self.dut.dma_data_wr_req_if.sop.value:
                addr_bin = self.dut.dma_data_wr_req_if.desc.pcie_addr.value 
                host_addr = addr_bin.integer
                await self.dma_req_queue.put(host_addr)
                self.log.debug(f"DMA req: host_addr=0x{host_addr:x} added to queue")

    async def _handle_dma_wr_rsp(self):
        while self.doing:
            await RisingEdge(self.dut.clk)
            if self.dut.dma_data_wr_rsp_if.vld.value:
                if not self.dma_req_queue.empty():
                    completed_addr = await self.dma_req_queue.get()
                    self.completed_host_addrs.add(completed_addr)
                    self.log.debug(f"DMA rsp: host_addr=0x{completed_addr:x} marked as completed")

                    async with self.dma_lock:
                        if completed_addr in self.dma_events:
                            event = self.dma_events[completed_addr]
                            event.set() 
                            del self.dma_events[completed_addr] 
                else:
                    self.log.warning("DMA rsp vld triggered but no pending req in queue")

    async def worker(self, qid, max_seq):
        #init cnt
        total_pkts = max_seq      
        recv_pkts = 0       
        drop_pkts = 0            
        try_cnt = 0

        while self.doing or not self.ref_queues[qid].empty():  
           
            if self.ref_queues[qid].empty():
                self.log.warning(f"No reference data available for Q{qid}")
                await Timer(1000, "ns")
                continue
            
            data_elem = await self.ref_queues[qid].get()
            header = data_elem.header
            expected_valid = header['valid']
            payload_size = header['payload_size']
            region = data_elem.region

            if not expected_valid: #drop_pkt
                drop_pkts += 1
                self.log.info(f"Predicted drop on Q{qid}, drop_pkts={drop_pkts}")
            else:  #normal recv pkt        
                await Timer(10, "us")
                data_in_mem = await self.mem.read(header['host_addr'], payload_size)
                expected_data = data_elem.data[64:64+payload_size]

                if data_in_mem != expected_data:
                    self.log.error(f"Expected: {expected_data[:16].hex()}...")
                    self.log.error(f"Received: {data_in_mem[:16].hex()}...")
                    #self.mem.free_region(region)
                    raise ValueError(f"Data mismatch on Q{qid}")
                else:                   
                    recv_pkts += 1
                    self.log.info(f"Successfully processed packet {recv_pkts}/{total_pkts} on Q{qid}")
    
                self.mem.free_region(region)

            if not self.doing:
                try_cnt = try_cnt + 1
                if try_cnt == 1000:#timeout
                    break

            await Timer(1, "us")

        #final test
        self.log.info(f"Q{qid} processing complete - recv_pkts={recv_pkts}, drop_pkts={drop_pkts}, total_pkts={total_pkts}")
        if total_pkts != drop_pkts + recv_pkts:
            raise ValueError(f"Drop count mismatch on Q{qid}! total_pkts={total_pkts}, drop_pkts={drop_pkts}, recv_pkts={recv_pkts}")
        self._final_report(qid, total_pkts, drop_pkts, recv_pkts)
        #await self.virtio_ctx.stop_queue(qid=qid)  
        self.virtio_ctx.destroy_queue(qid=qid)
        if not self.ref_queues[qid].empty():
            raise ValueError("queue(qid:{}) is not finish!".format(qid))

async def run_test(dut, idle_inserter, backpressure_inserter):
    #random.seed(321)
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
   
    q_num = 1
    max_seq = 100000  #100000

    packet_gen_cr = None  
    worker_cr = []
    await Timer(2, "us")

    #tb.dut.emu2beq_eop = Force(0)
    chn = tb.beq2blk
    #ID distributed
    bid_array = gen_unique_ids(num=q_num, start=0, end=q_num)

    for qid in bid_array:  
        tb.ref_queues[qid] = Queue(maxsize=512)  #init ref_queue

    for qid in bid_array:  
        worker_cr.append(cocotb.start_soon(tb.worker(qid, max_seq)))
        
    await Timer(1, "us")
    
    packet_gen_cr=cocotb.start_soon(packet_gen(chn=chn, ref_queues=tb.ref_queues, max_seq=max_seq, qid_array=bid_array, tb=tb, ctx_ctrl=tb.virtio_ctx))
 
    await packet_gen_cr  
    tb.log.info("packet_gen is done") 

    tb.stop() 

    for cr in worker_cr:
        await cr.join() 

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
        #factory.add_option("idle_inserter", [cycle_pause])
        #factory.add_option("backpressure_inserter", [cycle_pause])
        factory.generate_tests()

#sys.path.append('../common'); from debug import *

root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)

