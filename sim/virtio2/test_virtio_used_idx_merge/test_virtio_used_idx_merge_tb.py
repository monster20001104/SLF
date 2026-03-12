#!/usr/bin/env python3
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.queue import Queue, QueueFull, QueueEmpty
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.clock import Clock
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union, Dict, Tuple
from cocotb.regression import TestFactory
from cocotb.triggers import ClockCycles


sys.path.append('../../common')
from bus.beq_data_bus import BeqBus
from monitors.beq_data_bus import BeqTxqSlave
from bus.tlp_adap_dma_bus import DmaReadBus, DmaWriteBus
from monitors.tlp_adap_dma_bus import DmaRam
from address_space import Pool, AddressSpace, MemoryRegion
from backpressure_bus import define_backpressure
from enum import Enum, unique
from defines import *


Q_NUM = 256
Q_WIDTH = 8  # $clog2(256)
CLOCK_FREQ_MHZ = 200
TIMEOUT_THRESHOLD = CLOCK_FREQ_MHZ * 2 

class virtio_vq_t:
    def __init__(self, typ, qid):
        self.typ = typ  
        self.qid = qid 

class net_used_idx_irq_ff_entry_t:
    def __init__(self, qid, typ):
        self.qid = qid
        self.typ = typ

class used_idx_merge_bitmap_entry_t:
    def __init__(self, bitmap, used_idx_num):
        self.bitmap = bitmap
        self.used_idx_num = used_idx_num

class TB:
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        
        
        cocotb.start_soon(Clock(dut.clk, 5, units="ns").start())
        
        self.input_queue = Queue()
        self.output_queue = Queue()
        self.ref_out_queue = Queue()
        self.qid_time_queue = Queue()
        self.timeout_queue = Queue()
        self.used_idx_num_queue = Queue()
        self.used_idx_output_queue = Queue()
        self.order_queue = Queue()

        self.WR_USED_IDX_TIME = 2  
        self.WR_USED_IDX_NUM = 4
        self.processed_input_count = 0

        self.timeout_tracker: Dict[int, Tuple[int, bool]] = {}
        
        self.used_idx_merge_in = UsedIdxMergeInSource(UsedIdxMergeInBus.from_prefix(dut, "used_idx_merge_in"), dut.clk, dut.rst)
        self.used_idx_merge_to_net_tx = UsedIdxMergeNetTxSink(UsedIdxMergeNetTxBus.from_prefix(dut, "used_idx_merge_out_to_net_tx"), dut.clk, dut.rst)
        self.used_idx_merge_to_net_rx = UsedIdxMergeNetRxSink(UsedIdxMergeNetRxBus.from_prefix(dut, "used_idx_merge_out_to_net_rx"), dut.clk, dut.rst)
        self.used_idx_merge_out = UsedIdxMergeOutSink(UsedIdxMergeOutBus.from_prefix(dut, "used_idx_merge_out"), dut.clk, dut.rst)
        
        self.bitmap = [used_idx_merge_bitmap_entry_t(0, 0) for _ in range(Q_NUM*2)]
        self.global_timer = 0
        self.sent_events = []
        self.recv_events = []

        self.test_complete = False
        self.empty_cycles = 0  
        self.EMPTY_TIMEOUT_CYCLES = 1000
        
        cocotb.start_soon(self.update_global_timer())
        cocotb.start_soon(self.drive_inputs())
        cocotb.start_soon(self.timeout_checker())
        cocotb.start_soon(self.monitor_tran_cstat())
        cocotb.start_soon(self.monitor_outputs())
           

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
        self.used_idx_merge_in.set_idle_generator(generator)
    def set_backpressure_generator(self, generator=None):
        self.used_idx_merge_to_net_tx.set_backpressure_generator(generator)
        self.used_idx_merge_to_net_rx.set_backpressure_generator(generator)
        self.used_idx_merge_out.set_backpressure_generator(generator)

    async def drive_inputs(self):
        while not self.test_complete: 
            if self.input_queue.empty():
                await RisingEdge(self.dut.clk)  
                continue
            qid = await self.input_queue.get()
            #qid = self.input_queue.get_nowait()
            self.log.info(f"qid={qid.qid}")
            transaction = UsedIdxMergeInTransaction()
            transaction.qid = (qid.typ << Q_WIDTH) | qid.qid 
            
            await self.used_idx_merge_in.send(transaction)
            self.sent_events.append(qid)
            self.log.info(f"Driving input: type={qid.typ}, qid={qid.qid}")

            bitmap_qid = transaction.qid

            wren_detected = False
            while not wren_detected:
                await RisingEdge(self.dut.clk)

                req_cstat = self.dut.u_virtio_used_idx_merge.req_cstat.value
                if int(req_cstat) == 4:           
                    if self.bitmap[bitmap_qid].bitmap == 1:
                        self.log.info(f"Q{bitmap_qid} bitmap is 1, no need to wait wren")
                        wren_detected = True
                    else:    
                        used_idx_ff_empty = self.dut.u_virtio_used_idx_merge.used_idx_ff_empty.value 
            
                        if (not used_idx_ff_empty) and (self.dut.u_virtio_used_idx_merge.qid_time_ff_wren.value == 1):
                            timer_val = int(self.dut.u_virtio_used_idx_merge.global_timer.value)
                            self.log.info(f"timer_value={timer_val}")
                
                            self.timeout_tracker[bitmap_qid] = (timer_val, True)
                            self.log.info(f"Tracking timeout: qid={bitmap_qid}, timer={timer_val}")
                            wren_detected = True 
                        else:
                            self.log.debug(f"wren is 0, waiting (qid={bitmap_qid})")  

            if bitmap_qid < len(self.bitmap):
                self.log.info(f"bitmap start")
                entry = self.bitmap[bitmap_qid]
                #threshold = int(self.dut.dfx_used_idx_merge_used_idx_num_threshold.value)
                threshold = 8
                
                if not entry.bitmap or (entry.bitmap and (entry.used_idx_num >= 0 and entry.used_idx_num < threshold)):
                    entry.bitmap = 1
                    entry.used_idx_num += 1
                elif entry.bitmap and entry.used_idx_num == threshold:
                    entry.bitmap = 1
                    entry.used_idx_num = 0
                    self.used_idx_num_queue.put_nowait(bitmap_qid)
                else:
                    entry.bitmap = 0
                    entry.used_idx_num = 0

                self.bitmap[bitmap_qid] = entry

            self.processed_input_count += 1

                
    async def update_global_timer(self):
        while True:
            await RisingEdge(self.dut.clk)
            self.global_timer = (self.global_timer + 1) & 0xFFFF

    #async def timeout_checker(self):
    #    while True:
    #        await RisingEdge(self.dut.clk)
#
    #        self.log.info(f"Tracking {len(self.timeout_tracker)} queues for timeout")
    #        
    #        timeout_items = list(self.timeout_tracker.items())
#
    #        for qid, (timestamp, in_queue) in timeout_items:
    #            if not in_queue:
    #                continue
#
    #            elapsed_time = (self.global_timer - timestamp) & 0xFFFF
    #            empty = int(self.dut.u_virtio_used_idx_merge.qid_time_ff_empty.value)
    #            
    #            #self.log.info("empty = {}".format(empty))
    #            
    #            if elapsed_time >= TIMEOUT_THRESHOLD and not empty:
    #                self.timeout_tracker.pop(qid, None)
    #                
    #                if qid < len(self.bitmap):
    #                    self.bitmap[qid].bitmap = 0
    #                    self.bitmap[qid].used_idx_num = 0
    #                    self.log.info(f"Timeout cleared bitmap for qid={qid}")
#
    #                self.timeout_queue.put_nowait(qid)
    #                self.log.info(f"Timeout detected: qid={qid}, elapsed_time={elapsed_time}")

    async def timeout_checker(self):
        while not self.test_complete:
            await RisingEdge(self.dut.clk)  

            rden_signal = self.dut.u_virtio_used_idx_merge.qid_time_ff_rden
            dout_signal = self.dut.u_virtio_used_idx_merge.qid_time_ff_dout_sim

            self.log.info(f"qid_time_ff_rden: {rden_signal.value}, qid_time_ff_dout_sim: {dout_signal.value}")

            def is_valid_signal(signal):
                val_str = str(signal.value)
                return 'x' not in val_str and 'z' not in val_str
            
            rden_valid = is_valid_signal(rden_signal)
            dout_valid = is_valid_signal(dout_signal)
            rden_is_1 = (rden_signal.value == 1) if rden_valid else False

            self.log.debug(
                f"rden_valid: {rden_valid}, "
                f"dout_valid: {dout_valid}, "
                f"rden_is_1: {rden_is_1}"
            )
    
            if rden_valid and dout_valid and rden_is_1:
                qid_signal = int(dout_signal.value)
                qid_full = (qid_signal>>16) & 0x3FF
                qid_typ = (qid_full >> 8) & 0x3
                qid_num = qid_full & 0xFF
                timeout_qid = (qid_typ << Q_WIDTH) | qid_num
                
                self.log.info(f"DUT timeout process, qid={timeout_qid}")
    
                if timeout_qid in self.timeout_tracker:
                    self.timeout_tracker.pop(timeout_qid)
                    self.log.info(f"from timeout_tracker delete qid={timeout_qid}")
    
                    #clear bitmap
                    if timeout_qid < len(self.bitmap):
                        self.bitmap[timeout_qid].bitmap = 0
                        self.bitmap[timeout_qid].used_idx_num = 0
                        self.log.info(f"cleatr qid={timeout_qid} bitmap")
    
                    self.timeout_queue.put_nowait(timeout_qid)
                    self.log.info(f"timeout qid={timeout_qid} put in timeout_queue")           
   
    async def monitor_tran_cstat(self):
        while not self.test_complete:
            await RisingEdge(self.dut.clk)

            current_tran_cstat = int(self.dut.u_virtio_used_idx_merge.tran_cstat.value)
            rden = self.dut.u_virtio_used_idx_merge.qid_time_ff_rden

            def is_valid_signal(signal):
                val_str = str(signal.value)
                return 'x' not in val_str and 'z' not in val_str
            
            rden_valid = is_valid_signal(rden)
            rden_is_1 = (rden.value == 1) if rden_valid else False

            self.log.info(f"qid_time_ff_rden: {rden_is_1},tran_cstat: {current_tran_cstat}")

            if (current_tran_cstat == self.WR_USED_IDX_TIME) and rden_is_1:
                await self.order_queue.put(0)
                self.log.info(f"tran_cstat=WR_USED_IDX_TIME(2) order_queue write 0")

            elif current_tran_cstat == self.WR_USED_IDX_NUM:
                await self.order_queue.put(1)
                self.log.info(f"tran_cstat=WR_USED_IDX_NUM(4) order_queue write 1")

    async def monitor_outputs(self):
        while not self.test_complete:
            await RisingEdge(self.dut.clk)

            def is_valid_signal(signal):
                try:
                    int(signal.value)  
                    return True
                except ValueError:
                    return False
            
            # monitor used_idx_merge_out
            if (is_valid_signal(self.dut.used_idx_merge_out_vld) and is_valid_signal(self.dut.used_idx_merge_out_rdy) and is_valid_signal(self.dut.used_idx_merge_out_dat) and self.dut.used_idx_merge_out_vld.value == 1 and self.dut.used_idx_merge_out_rdy.value == 1):
                self.log.info(f"recv start")
                qid_val = int(self.dut.used_idx_merge_out_dat.value)
                typ = (qid_val >> Q_WIDTH) & 0x1
                qid = qid_val & ((1 << Q_WIDTH) - 1)
                event = virtio_vq_t(typ, qid)
                self.recv_events.append(event)
                self.log.info(f"Received used_idx_merge_out: type={typ}, qid={qid}")
                self.used_idx_output_queue.put_nowait(event)
            
            # monitor used_idx_merge_out_to_net_tx
            if (is_valid_signal(self.dut.used_idx_merge_out_to_net_tx_vld) and is_valid_signal(self.dut.used_idx_merge_out_to_net_tx_rdy) and is_valid_signal(self.dut.used_idx_merge_out_to_net_tx_qid) and self.dut.used_idx_merge_out_to_net_tx_vld.value == 1 and self.dut.used_idx_merge_out_to_net_tx_rdy.value == 1):
                qid_val = int(self.dut.used_idx_merge_out_to_net_tx_qid.value)
                typ = (qid_val >> Q_WIDTH) & 0x1
                qid = qid_val & ((1 << Q_WIDTH) - 1)
                event = virtio_vq_t(typ, qid)
                self.recv_events.append(event)
                self.log.info(f"Received net_tx output: type={typ}, qid={qid}")
                self.output_queue.put_nowait(event)

            # monitor used_idx_merge_out_to_net_rx
            if (is_valid_signal(self.dut.used_idx_merge_out_to_net_rx_vld) and is_valid_signal(self.dut.used_idx_merge_out_to_net_rx_rdy) and is_valid_signal(self.dut.used_idx_merge_out_to_net_rx_qid) and self.dut.used_idx_merge_out_to_net_rx_vld.value == 1 and self.dut.used_idx_merge_out_to_net_rx_rdy.value == 1):
                qid_val = int(self.dut.used_idx_merge_out_to_net_rx_qid.value)
                typ = (qid_val >> Q_WIDTH) & 0x1
                qid = qid_val & ((1 << Q_WIDTH) - 1)
                event = virtio_vq_t(typ, qid)
                self.recv_events.append(event)
                self.log.info(f"Received net_rx output: type={typ}, qid={qid}")
                self.output_queue.put_nowait(event)
            

    async def generate_events(self, num_events, min_interval=1, max_interval=20):
        generated = 0
        #for _ in range(num_events):
        #    typ = random.randint(0, 1)  # 0=TX, 1=RX
        #    qid = random.randint(0, Q_NUM-1)
        #    
        #    event = virtio_vq_t(typ, qid)
        #    self.input_queue.put_nowait(event)
        #    generated += 1

        for i in range(num_events):
            if i > 0 and random.random() < 0.5:
                event = last_event
                self.log.debug(f"typ={event.typ}, qid={event.qid}")
            else:
                typ = random.randint(0, 1)  # 0=TX, 1=RX
                qid = random.randint(0, Q_NUM-1)
                event = virtio_vq_t(typ, qid)
                last_event = event 
        
            self.input_queue.put_nowait(event)
            generated += 1
            
        self.log.info(f"Successfully generated {generated} events (target: {num_events})")


    async def check_outputs(self):
        event_count = 0
        EMPTY_TIMEOUT_CYCLES = 1000

        #while True:
        #while event_count < max_events:
        self.log.info("wait data")

        while (self.order_queue.empty() and 
           self.timeout_queue.empty() and 
           self.used_idx_num_queue.empty() and 
           self.used_idx_output_queue.empty() and 
           self.ref_out_queue.empty()):
            await RisingEdge(self.dut.clk)

        empty_cycles = 0
        while True:
            if (not self.order_queue.empty() or 
               not self.timeout_queue.empty() or 
               not self.used_idx_num_queue.empty() or 
               not self.used_idx_output_queue.empty() or 
               not self.ref_out_queue.empty()):
                
                empty_cycles = 0
            
                try:
                    order_dat = await self.order_queue.get()
                    self.log.info(f"get order_dat={order_dat}")
                    
                    if order_dat == 0:  # WR_USED_IDX_TIME
                        timeout_qid = await self.timeout_queue.get()
                        await self.ref_out_queue.put(timeout_qid)
                        self.log.info(f"Got from timeout_queue and put to ref_out_queue: qid={timeout_qid}")
                    elif order_dat == 1:  # WR_USED_IDX_NUM
                        threshold_qid = await self.used_idx_num_queue.get()
                        await self.ref_out_queue.put(threshold_qid)
                        self.log.info(f"Got from used_idx_num_queue and put to ref_out_queue: qid={threshold_qid}")
                       
                    output_event = await self.used_idx_output_queue.get()
                    self.log.info(f"Received output event: type={output_event.typ}, qid={output_event.qid}")
                    ref_qid = await self.ref_out_queue.get()
                    self.log.info(f"Received ref event: ref_qid = {ref_qid}")
                    #self.log.info(f"Received ref event: type={ref_qid.typ}, qid={ref_qid.qid}")
                
                    output_id = (output_event.typ << Q_WIDTH) | output_event.qid
                
                    #self.log.info(f"Received output event ID: 0x{output_id:x}, Expected: 0x{ref_qid:x}")
                    self.log.info(f"Received output event ID: {output_id}, Expected: {ref_qid}")
                    if output_id == ref_qid:
                        self.log.info(f"Output verified success: {output_id}")
                    else:
                        self.log.error(f"Mismatch! Output: {output_id}, Expected: {ref_qid}")
                        assert False, "Output verification failed"
            
                    event_count += 1
                    self.log.info(f"Processed {event_count} events")

                except QueueEmpty:
                    await RisingEdge(self.dut.clk)

            else:
                empty_cycles += 1
                await RisingEdge(self.dut.clk)
                
                if empty_cycles >= EMPTY_TIMEOUT_CYCLES:
                    self.log.info(f"No new data for {EMPTY_TIMEOUT_CYCLES} cycles. Processing complete.")
                    break

        self.log.info(f"Processed {event_count} events, verification complete")
        self.test_complete = True
        

async def run_test(dut, idle_inserter, backpressure_inserter):
    #random.seed(321)
    tb = TB(dut)
    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    num_events = 1000000 #1000000  
    
    gen_task = cocotb.start_soon(tb.generate_events(num_events=num_events))
    
    check_task = cocotb.start_soon(tb.check_outputs())
    
    await gen_task
    tb.log.info("Event generation complete")

    while tb.processed_input_count < num_events:
        await RisingEdge(dut.clk)
    tb.log.info(f"All {num_events} input events processed")

    await check_task
    tb.log.info("Output check complete")

    while not tb.test_complete:
        await RisingEdge(dut.clk)

    assert tb.order_queue.empty()
    assert tb.timeout_queue.empty()
    assert tb.used_idx_num_queue.empty()
    assert tb.ref_out_queue.empty()
    
    tb.log.info("Test completed successfully")

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    #seed=random.seed(123)
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
