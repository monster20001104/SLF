import itertools
import logging
import os
import sys
import random
import math
import struct
from collections import deque
from functools import wraps

import cocotb_test.simulator
import pytest

from address_space import IORegion, AddressSpace

import cocotb
from cocotb.log import SimLog
from cocotb.clock import Clock
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event,Lock
from cocotb.regression import TestFactory
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
import time

test_mode = None

class VirtqReq:
    def __init__(self, reqbase=None, reqlen=None, region=None, tb=None):
        if tb is None:
            raise ValueError(f"tb is None")
        if reqlen is None:
            raise ValueError(f"reqlen is None")

        # Construct a request with length reqlen：
        self.reqhdr_len = 16
        self.reqhdr_region = tb.mem.alloc_region(self.reqhdr_len)
        self.reqhdr_base = self.reqhdr_region.get_absolute_address(0)

        self.reqpld_len = reqlen
        self.reqpld_region = tb.mem.alloc_region(self.reqpld_len)
        self.reqpld_base = self.reqpld_region.get_absolute_address(0)

        self.reqsts_len = 1
        self.reqsts_region = tb.mem.alloc_region(self.reqsts_len)
        self.reqsts_base = self.reqsts_region.get_absolute_address(0)

        self.descs = []
        self.ids = []
        self.type = None

        log = logging.getLogger("cocotb.tb")
        log.debug(f"VirtqReq: reqhdr_base=0x{self.reqhdr_base:x}, reqhdr_len={self.reqhdr_len}")
        log.debug(f"VirtqReq: reqpld_base=0x{self.reqpld_base:x}, reqpld_len={self.reqpld_len}")
        log.debug(f"VirtqReq: reqsts_base=0x{self.reqsts_base:x}, reqsts_len={self.reqsts_len}")

class VirtqPkt:
    def __init__(self, pktbase=None, pktlen=None, region=None, tb=None, maxPktlen=65535):
        if pktbase is None:
            # Construct a packet with length pktlen
            self.pktlen = pktlen if pktlen != None else random.randint(14, min(maxPktlen, 65535))
            self.region = tb.mem.alloc_region(self.pktlen)
            self.pktbase = self.region.get_absolute_address(0)
        else:
            self.pktbase = pktbase
            self.pktlen = pktlen
            self.region = region

class VirtioBlkStatus:
    VIRTIO_BLK_S_OK       = 0
    VIRTIO_BLK_S_IOERR    = 1
    VIRTIO_BLK_S_UNSUPP   = 2

class VirtioBlkType:
    VIRTIO_BLK_T_IN            = 0
    VIRTIO_BLK_T_OUT           = 1
    VIRTIO_BLK_T_FLUSH         = 4
    VIRTIO_BLK_T_DISCARD       = 11
    VIRTIO_BLK_T_WRITE_ZEROES  = 13

class VirtioBlkMaxSegs:
    VIRTIO_BLK_MAX_DATA_SEGS    = 14
    VIRTIO_BLK_MAX_SEGS_W_HDR_STS = 16

class VirtioBlkMaxSegSize:
    VIRTIO_BLK_MAX_SIZE_PER_SEG    = 32 * 1024  # 32KB

class CheckerType:
    VIRTQ_CHECKER_NONE = 0
    VIRTQ_CHECKER_ERR = 1
    VIRTQ_CHECKER_BLK = 2

class VirtqType:
    NETTX = 0x0
    NETRX = 0x1
    BLK = 0x2

class VirtqDescFlagBit:
    NEXT_BIT = 0x1
    WRITE_BIT = 0x2
    INDIRECT_BIT = 0x4

class VirtqDesc(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("next",            0,  16),
        BitField("flags",           0,  16),
        BitField("pktlen",          0,  32),
        BitField("addr",            0,  64),
    ]

    region = None

    width = 0
    for elemnt in fields_desc:
        width += elemnt.size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        return cls(data)

class VirtqUsedElem(Packet):
    name = 'virtq_used_elem'
    fields_desc = [
        BitField("dataLen",       0,  32),
        BitField("descID",        0,  32),
    ]

    width = 0
    for elemnt in fields_desc:
        width += elemnt.size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        return cls(data)

class VirtqAvailElem(Packet):
    name = 'virtq_avail_elem'
    fields_desc = [
        BitField("descID",        0,  16),
    ]

    width = 0
    for elemnt in fields_desc:
        width += elemnt.size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        return cls(data)

class blkBeqChecker:
    def __init__(self, virtqblk=None):
        self.virtqblk = virtqblk
        self.tb = virtqblk.tb

    def mylog(self, message, force=False):
        """Custom log method that adds 'in beq' after the queue ID"""
        if self.virtqblk and hasattr(self.virtqblk, 'mylog'):
            # Use the virtqblk's mylog but modify the message
            # The virtqblk.mylog will add [q{qid}], so we insert "in beq" right after that
            modified_message = message.replace("[", "[q" + str(self.virtqblk.qid) + " in beq] ", 1)
            if "[q" not in modified_message:
                modified_message = f"[q{self.virtqblk.qid} in beq] {message}"
            self.virtqblk.log.debug(modified_message)

    async def receive_beq_data(self, qid=None):
        """
        Encapsulate h2s_beq_rx_data call with entry and exit logging

        Args:
            qid: Queue ID to receive data from, defaults to self.virtqblk.qid if None

        Returns:
            tuple: (qid, dataLen, gen, data) from h2s_beq_rx_data
        """
        # Use provided qid or default to virtqblk's qid
        use_qid = qid if qid is not None else self.virtqblk.qid

        # Entry log
        self.mylog(f"Entering receive_beq_data for qid={use_qid}")

        # Call the original function
        result = await self.tb.h2s_beq_rx_data(use_qid)
        qid, dataLen, gen, data = result

        # Exit log with received data info
        self.mylog(f"Exiting receive_beq_data: received qid={qid}, dataLen={dataLen}, gen={gen}, data_size={len(data)}")

        return result

    def check_buffer_header(self, data, virtqblk, desc_index=0, req=None):
        """
        Compare buffer header fields with the corresponding descriptor information

        Args:
            data: The buffer header data received
            virtqblk: VirtqBlk instance containing descriptor information
            desc_index: Index of the descriptor to compare with
        """
        # Extract fields from buffer header (little endian)
        vq_idx = int.from_bytes(data[0:2], byteorder='little')
        vq_gen = data[2]
        desc_idx = int.from_bytes(data[4:6], byteorder='little')
        desc_flag = int.from_bytes(data[6:8], byteorder='little')
        host_addr = int.from_bytes(data[8:16], byteorder='little')
        host_buffer_length = int.from_bytes(data[16:20], byteorder='little')

        # check if req is None
        if req is None:
            raise ValueError("req is None")

        if desc_index >= len(req.descs):
            self.mylog(f"Error: desc_index {desc_index} out of range, total descs {len(req.descs)}")
            raise ValueError(f"desc_index {desc_index} out of range, total descs {len(req.descs)}")

        virtqblk.printDesc(req.descs[desc_index], req.ids[desc_index])

        desc = req.descs[desc_index]

        # Compare fields
        errors = []
        # Check queue id
        if vq_idx != virtqblk.qid:
            errors.append(f"Queue ID mismatch: header={vq_idx}, expected={virtqblk.qid}")

        # Check generation
        if vq_gen != virtqblk.gen:
            errors.append(f"Generation mismatch: header={vq_gen}, expected={virtqblk.gen}")

        # Check descriptor index
        if desc_idx != req.ids[0]:
            errors.append(f"Descriptor index mismatch: header={desc_idx}, expected={req.ids[0]}")

        # Check descriptor flags
        if desc_flag != desc.flags:
            errors.append(f"Descriptor flags mismatch: header=0x{desc_flag:x}, desc=0x{desc.flags:x}")

        # Check host address
        if host_addr != desc.addr:
            errors.append(f"Host address mismatch: header=0x{host_addr:x}, desc=0x{desc.addr:x}")

        # Check buffer length
        if host_buffer_length != desc.pktlen:
            errors.append(f"Buffer length mismatch: header={host_buffer_length}, desc={desc.pktlen}")

        # Log comparison results
        if errors:
            self.mylog(f"Buffer header verification failed for desc_index {desc_index}:")
            for error in errors:
                self.mylog(f"  {error}")
            raise ValueError(f"Buffer header verification failed: {errors}")
        else:
            self.mylog(f"Buffer header verification passed for desc_index {desc_index}")

        return host_buffer_length

    def print_buffer_header(self, data):
        """
        Parse and print buffer header fields from received data

        Args:
            data: The buffer header data received
        """
        # Extract fields from buffer header (little endian)
        vq_idx = int.from_bytes(data[0:2], byteorder='little')
        vq_gen = data[2]
        resv0 = data[3]
        desc_idx = int.from_bytes(data[4:6], byteorder='little')
        desc_flag = int.from_bytes(data[6:8], byteorder='little')
        host_addr = int.from_bytes(data[8:16], byteorder='little')
        host_buffer_length = int.from_bytes(data[16:20], byteorder='little')

        # Print the extracted fields
        self.mylog(f"Buffer header contents:")
        self.mylog(f"  vq_idx: {vq_idx}")
        self.mylog(f"  vq_gen: {vq_gen}")
        self.mylog(f"  resv0: {resv0}")
        self.mylog(f"  desc_idx: {desc_idx}")
        self.mylog(f"  desc_flag: {desc_flag}")
        self.mylog(f"  host_addr: 0x{host_addr:x}")
        self.mylog(f"  buf_len: {host_buffer_length}")

        return host_buffer_length

    def process_buffer_header(self, data, desc_index):
        """Process buffer header data and perform verification"""
        self.mylog(f"Received buffer header, length={len(data)}")

        # Print and verify buffer header fields
        host_buffer_length = self.print_buffer_header(data)

        # Verify buffer header matches descriptor information
        if len(self.virtqblk.pendingReq) > 0:
            self.check_buffer_header(data, self.virtqblk, desc_index, req=self.virtqblk.pendingReq[0])
        else:
            # Throw an error if there's a buffer header but no pending requests
            self.mylog(f"Error: Received buffer header but no pending requests", force=True)
            raise ValueError("Received buffer header but no pending requests")

        # Validate buffer header size
        if len(data) != 64:
            raise ValueError(f"Invalid buffer header size: {len(data)}, expected 64 bytes")

        if host_buffer_length == 0:
            raise ValueError(f"Invalid buffer buffer length: {host_buffer_length}, expected non-zero value")

        return host_buffer_length

    def process_data_chunk(self, data, expected_length, total_data):
        """Process a data chunk and validate its length"""
        self.mylog(f"Received data chunk, length={len(data)}")

        if len(data) != expected_length:
            raise ValueError(f"Data length {len(data)} doesn't match expected length {expected_length} from buffer header")

        # Add data to accumulated buffer
        total_data.extend(data)
        return total_data

    async def verify_request_completion(self, total_data):
        """Verify if we have received a complete request and validate it"""
        if not self.virtqblk.pendingReq:
            self.mylog("Warning: Received data but no pending requests")
            raise ValueError("Received data but no pending requests")

        req = self.virtqblk.pendingReq[0]
        expected_len = req.reqhdr_len + req.reqpld_len

        # Check if we have enough data for a complete request
        if len(total_data) < expected_len:
            return None, total_data

        # Remove request from pending queue
        req = self.virtqblk.pendingReq.popleft()

        # Verify data length
        if len(total_data) != expected_len:
            self.mylog(f"Data length mismatch: received {len(total_data)} bytes, expected {expected_len} bytes")
            raise ValueError(f"Block write data length mismatch: received {len(total_data)} bytes, expected {expected_len} bytes")

        # Verify header
        await self.verify_request_header(req, total_data)

        # Verify payload
        await self.verify_request_payload(req, total_data)

        return req, bytearray()

    async def verify_request_header(self, req, total_data):
        """Verify the request header matches the received data"""
        req_hdr = await req.reqhdr_region.read(0, req.reqhdr_len)
        if req_hdr != total_data[:req.reqhdr_len]:
            self.mylog(f"Header verification failed: received {len(total_data)} bytes, expected {req.reqhdr_len} bytes")
            raise ValueError("Block write header verification failed for request")

    async def verify_request_payload(self, req, total_data):
        """Verify the request payload matches the received data"""
        req_data = await req.reqpld_region.read(0, req.reqpld_len)
        total_data_slice = total_data[req.reqhdr_len:req.reqhdr_len + req.reqpld_len]
        if req_data != total_data_slice:
            self.mylog(f"Data verification failed: received {len(total_data)} bytes, expected {req.reqpld_len} bytes")
            raise ValueError("Block write data verification failed for request")

    async def process_status_header(self, req, desc_index):
        """Process the status buffer header and return the data"""
        self.mylog(f"Try to get status buffer header")
        qid, dataLen, gen, data = await self.receive_beq_data()
        self.print_buffer_header(data)

        if dataLen != 64:
            raise ValueError(f"Invalid status size: {dataLen}, expected 64 byte")

        desc_flag = int.from_bytes(data[6:8], byteorder='little')
        if desc_flag & VirtqDescFlagBit.NEXT_BIT:
            self.mylog(f"Error: status buffer header has NEXT_BIT set")
            raise ValueError(f"Status buffer header has NEXT_BIT set")

        self.check_buffer_header(data, self.virtqblk, desc_index, req=req)

        # Return the data to the caller
        return data

    async def write_back_status(self, req, status_bh):
        """Update the status buffer and send it to the host"""
        self.mylog(f"Writing status to host")

        # Create a 65-byte array
        status_buffer = bytearray(65)

        # Copy the 64-byte buffer header from status_bh to the first 64 bytes
        status_buffer[:64] = status_bh

        # Write 0 to the flag field (bytes 6-7)
        # 0 means to update used ring
        status_buffer[6:8] = (0).to_bytes(2, byteorder='little')

        # Write VIRTIO_BLK_S_OK (0) to the last byte (at index 64)
        status_buffer[64] = VirtioBlkStatus.VIRTIO_BLK_S_OK

        # Print the status buffer content for debugging
        self.mylog(f"Status buffer contents (65 bytes):")

        # Use print_buffer_header to print the header fields
        self.print_buffer_header(status_buffer[:64])

        self.mylog(f"  Status byte (last byte): {status_buffer[64]} (VIRTIO_BLK_S_OK={VirtioBlkStatus.VIRTIO_BLK_S_OK})")

        # Send the status buffer to the host using the correct parameter format
        await self.tb.s2h_beq_tx_data(self.virtqblk.qid, 65, self.virtqblk.gen, status_buffer)

        self.mylog(f"write back status from beq to host")

    async def write_back_data(self, req):
        """
        Write back data for read requests based on descriptor chain information.
        Each buffer consists of a 64-byte header followed by data.
        """
        self.mylog(f"Writing data back to host for read request")

        data = self.virtqblk.blk_generated_data.popleft()
        data_offset = 0

        # Process each descriptor in the chain except the last one (status descriptor)
        for i in range(len(req.descs) - 1):
            # Skip the first descriptor (request header)
            if i == 0:
                continue

            desc = req.descs[i]
            desc_id = req.ids[i]
            # Print detailed descriptor information before processing
            self.mylog(f"Processing descriptor {i} (ID={desc_id}):")
            self.mylog(f"  Address: 0x{desc.addr:x}")
            self.mylog(f"  Length: {desc.pktlen} bytes")
            self.mylog(f"  Flags: 0x{desc.flags:x}")
            self.mylog(f"    NEXT: {'Yes' if desc.flags & VirtqDescFlagBit.NEXT_BIT else 'No'}")
            self.mylog(f"    WRITE: {'Yes' if desc.flags & VirtqDescFlagBit.WRITE_BIT else 'No'}")
            self.mylog(f"    INDIRECT: {'Yes' if desc.flags & VirtqDescFlagBit.INDIRECT_BIT else 'No'}")
            if hasattr(desc, 'next') and desc.next:
                self.mylog(f"  Next descriptor: {desc.next}")
            # Create a buffer with size: descriptor length + 64 bytes for the header
            response_buffer = bytearray(desc.pktlen + 64)

            # Construct buffer header based on descriptor information
            buffer_header = bytearray(64)

            # Fill header fields
            buffer_header[0:2] = self.virtqblk.qid.to_bytes(2, byteorder='little')  # vq_idx
            buffer_header[2] = self.virtqblk.gen  # vq_gen
            buffer_header[3] = 0  # reserved
            buffer_header[4:6] = desc_id.to_bytes(2, byteorder='little')  # desc_idx

            # Set NEXT_BIT in flags for all buffers
            buffer_header[6:8] = (1).to_bytes(2, byteorder='little')  # flags (set NEXT_BIT)

            buffer_header[8:16] = desc.addr.to_bytes(8, byteorder='little')  # host_addr
            buffer_header[16:20] = desc.pktlen.to_bytes(4, byteorder='little')  # host_buffer_length

            # Copy the header to the response buffer
            response_buffer[:64] = buffer_header

            # For read operations, fill with the generated data instead of random pattern
            data_offset_end = data_offset + desc.pktlen
            # Make sure we don't go beyond the data length
            if data_offset_end > len(data):
                raise ValueError(f"Data offset {data_offset_end} exceeds data length {len(data)}")

            # Copy portion of data to response buffer
            data_part = data[data_offset:data_offset_end]
            response_buffer[64:64+len(data_part)] = data_part

            # Update data offset for next descriptor
            data_offset += len(data_part)

            # Debug output
            self.mylog(f"Sending data buffer {i}: descriptor id={desc_id}, length={desc.pktlen}, data_offset={data_offset}, data_length={len(data_part)}, flags={buffer_header[6:8].hex()}")
            self.print_buffer_header(buffer_header)

            # Send buffer to host
            total_len = desc.pktlen + 64
            await self.tb.s2h_beq_tx_data(self.virtqblk.qid, total_len, self.virtqblk.gen, response_buffer)

        # After sending all data, process the status buffer
        status_desc = req.descs[-1]
        # Use the first descriptor ID for status
        status_desc_id = req.ids[0]

        # Create the status buffer (64-byte header + 1-byte status)
        status_buffer = bytearray(65)

        # Construct status buffer header
        status_header = bytearray(64)
        status_header[0:2] = self.virtqblk.qid.to_bytes(2, byteorder='little')  # vq_idx
        status_header[2] = self.virtqblk.gen  # vq_gen
        status_header[3] = 0  # reserved
        status_header[4:6] = status_desc_id.to_bytes(2, byteorder='little')  # desc_idx
        status_buffer[6:8] = (0).to_bytes(2, byteorder='little')
        status_header[8:16] = status_desc.addr.to_bytes(8, byteorder='little')  # host_addr
        status_header[16:20] = status_desc.pktlen.to_bytes(4, byteorder='little')  # host_buffer_length

        # Copy header to status buffer
        status_buffer[:64] = status_header

        # Set status to VIRTIO_BLK_S_OK (0)
        status_buffer[64] = VirtioBlkStatus.VIRTIO_BLK_S_OK

        # Debug output
        self.mylog(f"Sending status buffer: descriptor id={status_desc_id}")
        self.print_buffer_header(status_header)

        # Send status buffer to host
        await self.tb.s2h_beq_tx_data(self.virtqblk.qid, 65, self.virtqblk.gen, status_buffer)

        self.mylog(f"All data and status sent to host for read request")

    async def mainLoop(self):
        # Keep track of whether next read is buffer header or data
        expecting_buffer_header = True
        total_data = bytearray()
        current_buffer_length = 0
        desc_index = 0

        while True:
            self.mylog(f"blkBeqChecker wait for blk write data, qid={self.virtqblk.qid}")
            qid, dataLen, gen, data = await self.receive_beq_data()
            self.mylog(f"read blk data, qid={qid}, dataLen={dataLen}, gen={gen}")

            if expecting_buffer_header:
                # Processing buffer header
                current_buffer_length = self.process_buffer_header(data, desc_index)
                desc_index += 1
                expecting_buffer_header = False
            else:
                # Processing data
                total_data = self.process_data_chunk(data, current_buffer_length, total_data)
                expecting_buffer_header = True

                # Check if we've received a complete request
                req, total_data = await self.verify_request_completion(total_data)

                if req is not None:
                    # Process status buffer header
                    status_bh = await self.process_status_header(req, desc_index)

                    self.mylog(f"Successfully verified block write data: header {req.reqhdr_len}, data {req.reqpld_len}")

                    # write success status to reqsts_region and send it to the host
                    # fpga will update used ring and notify the host
                    await self.write_back_status(req, status_bh)
                    # Free resources
                    #await self.free_request_resources(req)

                    # Reset for next request
                    desc_index = 0

    async def mainLoop_read_write(self):
        # Keep track of whether next read is buffer header or data
        expecting_buffer_header = True
        total_data = bytearray()
        current_buffer_length = 0
        desc_index = 0
        req_type = None

        while not (self.virtqblk.workDone and len(self.virtqblk.pendingReq) == 0):
            self.mylog(f"blkBeqChecker wait for blk write data, qid={self.virtqblk.qid}")
            qid, dataLen, gen, data = await self.receive_beq_data()
            self.mylog(f"read blk data, qid={qid}, dataLen={dataLen}, gen={gen}")

            if expecting_buffer_header:
                # Processing buffer header
                current_buffer_length = self.process_buffer_header(data, desc_index)
                desc_flag = int.from_bytes(data[6:8], byteorder='little')
                expecting_buffer_header = False

                # if desc_index is 0 and current_buffer_length is 16, try to read blk request header data
                if desc_index == 0 and current_buffer_length == 16:
                    self.mylog(f"Try to get blk request header data")
                    qid, dataLen, gen, data = await self.receive_beq_data()

                    if len(data) != 16:
                        self.mylog(f"Error: blk request header size {len(data)} is not 16 bytes")
                        raise ValueError(f"blk request header size {len(data)} is not 16 bytes")

                    req_type = int.from_bytes(data[:4], byteorder='little')
                    if req_type == VirtioBlkType.VIRTIO_BLK_T_IN:
                        self.mylog(f"Processing read request (VIRTIO_BLK_T_IN)")
                    else:
                        total_data = self.process_data_chunk(data, current_buffer_length, total_data)

                    expecting_buffer_header = True

                if req_type == VirtioBlkType.VIRTIO_BLK_T_IN:
                        expecting_buffer_header = True
                        # Check if we've received a complete read request
                        if not desc_flag & VirtqDescFlagBit.NEXT_BIT:
                            self.mylog(f"Processing read request (VIRTIO_BLK_T_IN)")
                            # Remove request from pending queue
                            req = self.virtqblk.pendingReq.popleft()

                            if desc_index < 2 or (desc_index != len(req.descs) - 1):
                                self.mylog(f"Error: desc_index {desc_index} out of range, total descs {len(req.descs)}")
                                raise ValueError(f"desc_index {desc_index} out of range, total descs {len(req.descs)}")

                            await self.write_back_data(req)
                            req_type = None
                            desc_index = 0
                            continue

                desc_index += 1
            else:
                # Processing data
                total_data = self.process_data_chunk(data, current_buffer_length, total_data)
                expecting_buffer_header = True

                # Check if we've received a complete request
                req, total_data = await self.verify_request_completion(total_data)

                if req is not None:
                    # Process status buffer header
                    status_bh = await self.process_status_header(req, desc_index)

                    self.mylog(f"Successfully verified block write data: header {req.reqhdr_len}, data {req.reqpld_len}")

                    # write success status to reqsts_region and send it to the host
                    # fpga will update used ring and notify the host
                    await self.write_back_status(req, status_bh)
                    # Free resources
                    #await self.free_request_resources(req)

                    # Reset for next request
                    desc_index = 0
        self.mylog("blkBeqChecker mainLoop exiting - all work completed")

        # Print statistics about processed requests
        if hasattr(self.virtqblk, 'nrBlkWrites') and hasattr(self.virtqblk, 'nrBlkReads'):
            self.mylog(f"Total bytes processed: {self.virtqblk.nrBlkWrites + self.virtqblk.nrBlkReads} bytes")
            self.mylog(f"  - Write operations: {self.virtqblk.nrBlkWrites} bytes")
            self.mylog(f"  - Read operations: {self.virtqblk.nrBlkReads} bytes")

        # Print information about any pending requests that weren't processed
        if hasattr(self.virtqblk, 'pendingReq') and len(self.virtqblk.pendingReq) > 0:
            self.mylog(f"Warning: {len(self.virtqblk.pendingReq)} requests still pending at exit")

        # Additional cleanup if needed
        if hasattr(self.virtqblk, 'blk_generated_data') and len(self.virtqblk.blk_generated_data) > 0:
            self.mylog(f"Warning: {len(self.virtqblk.blk_generated_data)} generated data blocks not used")

        self.mylog("blkBeqChecker completed successfully")

# blk_err	[7:0]	r/w	：
#   bit [0]desc_next_idx_err : index大于等于qsize
#   bit [1]chain_err: chain长大于qsize，或者为1
#   bit [2]desc_flag_err: indirect bit 1，则err
#   bit [3]desc_data_len_err: 某个描述的数据长度大于最大值，或者等于0
#   bit [4]ring_id_err: ring_idx大于等于qsize
#   bit [5]idx_err: 2次读取的指针大于qsize
#   bit [6]tlp err:
#   bit [7]:rsv
class virtqErrChecker:
    def __init__(self, virtq=None):
        self.virtq = virtq
        self.tb = virtq.tb

    async def mainLoop(self):
        while True:
            err = await self.virtq.hwErr()
            if (err != 0) and (self.virtq.expErr):
                if err != self.virtq.expErrCode:
                    self.virtq.printVirtq()
                    raise ValueError(f"hw error on q{self.virtq.qid} expErrCode {hex(self.virtq.expErrCode)} != hwErr bits: {hex(err)}")
                elif self.virtq.expStop:
                    await Timer(8000, 'ns')
                    self.virtq.mylog(f"hw error on q{self.virtq.qid} expErrCode {hex(self.virtq.expErrCode)} hwErr bits: {hex(err)}")
                    stopped = await self.virtq.hwStopped()
                    if not stopped:
                        self.virtq.printVirtq()
                        raise ValueError(f"virtq not stopped")

                break
            elif (err != 0) and (not self.virtq.expErr):
                self.virtq.printVirtq()
                raise ValueError(f"hw error on q{self.virtq.qid} hwErr {err}")
            else:
                # Check for errors every 1000ns
                await Timer(1000, 'ns')

        if self.virtq.testcase_destructor is not None:
            self.virtq.testcase_destructor()
            self.virtq.testcase_destructor = None
            self.virtq.testcase_destructor_arg = None

class IdPool:
    def __init__(self, size=1024):
        self.size = size
        self.allocator = set(range(0,size))

    def allocID(self):
        if not self.allocator:
            return None

        idx = random.choice(list(self.allocator))
        self.allocator.remove(idx)
        return idx

    def releaseID(self, idx):
        if idx < 0 or idx >= self.size:
            raise ValueError(f"idx {idx} out of range")
        if idx in self.allocator:
            raise ValueError(f"idx {idx} already released")

        self.allocator.add(idx)

    def clear(self):
        self.allocator.clear()
        self.allocator.update(range(0, self.size))

    def alloc_n_ID(self, n):
        IDs = []
        if n >= len(self.allocator):
            return IDs

        for i in range(n):
            IDs.append(self.allocID())

        return IDs

    def empty(self):
        if len(self.allocator) == 0:
            return True
        return False

class Virtq:
    def __init__(self, tb, qid=0, qtype=VirtqType.NETTX, qlen=1024, mtu=1500, gen=0):
        self.tb = tb
        self.qid = qid
        self.qtype = qtype
        self.qlen = qlen
        self.mtu = mtu
        self.gen = gen

        # Encode qid information into msix_addr and msix_data
        self.msix_addr = 0xffffffffffe00000 + self.qid
        self.msix_data = self.qid

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.DescTable = self.tb.mem.alloc_region((int)((VirtqDesc.width / 8)* self.qlen))
        self.AvailRing = self.tb.mem.alloc_region((int)(2 + 2 +  (VirtqAvailElem.width / 8) * self.qlen + 2))
        self.UsedRing = self.tb.mem.alloc_region((int)(2 + 2 + (VirtqUsedElem.width / 8) * self.qlen + 2))

        # Print the allocated addresses
        self.log.info(f"DescTable allocated at: 0x{self.DescTable.get_absolute_address(0):x}, size: {(VirtqDesc.width // 8) * self.qlen} bytes")
        self.log.info(f"AvailRing allocated at: 0x{self.AvailRing.get_absolute_address(0):x}, size: {2 + 2 + (VirtqAvailElem.width // 8) * self.qlen + 2} bytes")
        self.log.info(f"UsedRing allocated at: 0x{self.UsedRing.get_absolute_address(0):x}, size: {2 + 2 + (VirtqUsedElem.width // 8) * self.qlen + 2} bytes")
        self.idPool = IdPool(self.qlen)
        self.errChecker = virtqErrChecker(self)

        self.nrTxPkts = 0
        self.nrRxPkts = 0
        self.nrFillDescs = 0
        self.nrRecycleDescs = 0
        self.nrTestPkts = -1

        self.enableLog = True

        self.started = False
        self.workDone = False
        self.nextUsedRingID = 0
        self.inFlightPkts = deque()
        self.inFlightPktsCtx = deque()
        self.rxDescCtx = deque()
        self.lastPrintTm = int(time.time())

        self.expErr = False
        self.expStop = False
        self.expErrCode = 0
        self.testcase_destructor = None
        self.testcase_destructor_arg = None
        self.disableInt = False

    async def reset(self):
        await self.stop()

        self.idPool.clear()

        self.nrTxPkts = 0
        self.nrRxPkts = 0
        self.nrFillDescs = 0
        self.nrRecycleDescs = 0
        self.nrTestPkts = -1

        self.started = False
        self.workDone = False
        self.nextUsedRingID = 0
        self.inFlightPkts.clear()
        self.inFlightPktsCtx.clear()
        self.rxDescCtx.clear()
        self.lastPrintTm = int(time.time())

        self.expErr = False
        self.expStop = False
        self.expErrCode = 0
        self.testcase_destructor = None
        self.testcase_destructor_arg = None
        self.disableInt = False

    async def stop(self):
        qt = {
            VirtqType.NETTX: 0,
            VirtqType.NETRX: 1
        }.get(self.qtype, 2)
        await self.tb.qset_cmd(qt, self.qid, 0, 0, 1, 0, 0)
        self.started = False

    async def notify(self):
        qt = {
            VirtqType.NETTX: 0,
            VirtqType.NETRX: 1
        }.get(self.qtype, 2)

        await self.tb.notify(self.qtype, self.qid)

    async def getNextUsedElem(self):
        ringIDRaw = await self.UsedRing.read(2, 2)
        ringID = (ringIDRaw[0] + (ringIDRaw[1] << 8))

        if ringID == (self.nextUsedRingID % 65536):
            return None

        usedElemRawData = await self.UsedRing.read(int(4 + (self.nextUsedRingID % self.qlen) * (VirtqUsedElem.width / 8)), int(VirtqUsedElem.width / 8))
        usedElem = VirtqUsedElem.unpack(usedElemRawData[::-1])
        return usedElem

    async def writeNextAvailElem(self, descID):
        ringIDRaw = await self.AvailRing.read(2, 2)
        ringID = (ringIDRaw[0] + (ringIDRaw[1] << 8))

        availElem = VirtqAvailElem(descID=descID)

        await self.AvailRing.write(int(4 + (ringID % self.qlen) * (VirtqAvailElem.width / 8)), bytearray(availElem.pack().to_bytes(2, 'little')))

        ringID += 1
        await self.AvailRing.write(2, ringID.to_bytes(2, byteorder='little'))

    async def updateAvailRing(self, descID):
        ringIDRaw = await self.AvailRing.read(2, 2)
        ringID = (ringIDRaw[0] + (ringIDRaw[1] << 8))

        availElem = VirtqAvailElem(descID=descID)

        offset = int(4 + (ringID % self.qlen) * (VirtqAvailElem.width / 8))
        data_bytes = bytearray(availElem.pack().to_bytes(2, 'little'))

        self.mylog(f"updateAvailRing: descID={descID}, ringID={ringID}, offset={offset}, data={list(data_bytes)}", force=True)

        await self.AvailRing.write(offset, data_bytes)

        ringID += 1
        await self.AvailRing.write(2, ringID.to_bytes(2, byteorder='little'))

        self.mylog(f"updateAvailRing: new ringID={ringID}", force=True)

    async def retrieveUsedDesc(self):
        usedElem = await self.getNextUsedElem()
        if usedElem is None:
            return None, None
        else:
            self.nextUsedRingID += 1
            self.nextUsedRingID %= 65536

        descID = usedElem.descID
        descRawData = await self.DescTable.read(int((descID % self.qlen) * (VirtqDesc.width / 8)), int(VirtqDesc.width / 8))
        desc = VirtqDesc.unpack(descRawData[::-1])
        desc.pktlen = usedElem.dataLen
        self.nrRecycleDescs += 1

        return desc, descID

    async def fillAvailDescChain(self, descs=None, IDs=None):
        if descs is None or IDs is None or len(descs) != len(IDs):
            raise ValueError(f"descs or IDs is None or length mismatch")

        hdrDescID = None
        self.nrFillDescs += len(descs)

        for desc, descID in zip(descs, IDs):
            if hdrDescID is None:
                hdrDescID = descID
            self.printDesc(desc, descID)
            await self.DescTable.write(int((descID % self.qlen) * (VirtqDesc.width / 8)), bytearray(desc.pack().to_bytes(16, 'little')))

        await self.updateAvailRing(hdrDescID)

    def mylog(self, *args, sep=" ", end="\n", force=False):
        currTm = int(time.time())
        if currTm - self.lastPrintTm > 2:
            self.lastPrintTm = currTm
            self.printVirtq()

        if self.enableLog:
            message = f"[q{self.qid}] {sep.join(map(str, args))}"
            self.log.debug(message)

    def printVirtq(self):
        self.log.debug(f"virtq {self.qid} fill {self.nrFillDescs} recycle {self.nrRecycleDescs} inFlight {self.nrFillDescs - self.nrRecycleDescs} left:{self.qlen - self.nrFillDescs + self.nrRecycleDescs}")

    def printDesc(self, desc, descID):
        self.mylog(f"desc on q{self.qid} id {descID}")
        self.mylog(f"\taddr: {hex(desc.addr)}")
        self.mylog(f"\tpktlen: {desc.pktlen}")
        self.mylog(f"\tflags: {desc.flags}")
        self.mylog(f"\tnext: {desc.next}")
        hexVal = hex(desc.pack())
        self.mylog(f"\thex value: {hexVal}")

    async def hwErr(self):
        DFX_ERR_BASE_ADDR = 0x1c00000 + 0xa0000
        return await self.tb.read_reg(DFX_ERR_BASE_ADDR + ((256 + 256 + self.qid) << 3))

    async def resetHwErr(self):
        DFX_ERR_BASE_ADDR = 0x1c00000 + 0xa0000
        return await self.tb.write_reg(DFX_ERR_BASE_ADDR + ((256 + 256 + self.qid) << 3), 0xff)

    async def hwStatus(self):
        addr=(0x1800000) + (2*0x200) + (self.qid*0x800) + 0x58

        val = await self.tb.read_reg(addr)

        self.mylog(f"hwStatus on qid_cmd on q{self.qid} addr {hex(addr)} val {hex(val)}: 1 start; 2 stop, 3 pause, 4 cancel_pause")

        return val

    async def hwStopped(self):
        status = await self.hwStatus()

        return (status & 0x2) != 0

def VirtqReq2Descs(virtqReq=None, max_size=VirtioBlkMaxSegSize.VIRTIO_BLK_MAX_SIZE_PER_SEG,
    extraFlags=0, max_chain_len=VirtioBlkMaxSegs.VIRTIO_BLK_MAX_SEGS_W_HDR_STS, virtqBlk=None, ignore_chain_len=False, ignore_size=False):
    if virtqReq is None:
        if virtqReq is None or virtqBlk is None:
            raise ValueError("virtqReq is None, or virtqBlk is None")

    if max_size > VirtioBlkMaxSegSize.VIRTIO_BLK_MAX_SIZE_PER_SEG and not ignore_size:
        raise ValueError(f"max_size {max_size} > VIRTIO_BLK_MAX_SIZE_PER_SEG {VirtioBlkMaxSegSize.VIRTIO_BLK_MAX_SIZE_PER_SEG}")

    descs = []
    chainLen = 0

    virtqBlk.mylog(f"VirtqReq2Descs: request header length={virtqReq.reqhdr_len}, payload length={virtqReq.reqpld_len}, status length={virtqReq.reqsts_len}")
    virtqBlk.mylog(f"VirtqReq2Descs: request header base={hex(virtqReq.reqhdr_base)}, payload base={hex(virtqReq.reqpld_base)}, status base={hex(virtqReq.reqsts_base)}")

    # The first descriptor is for the request header, which is 16 bytes long
    desc = VirtqDesc(addr=virtqReq.reqhdr_base,
                         pktlen=16, flags=(VirtqDescFlagBit.NEXT_BIT))
    chainLen += 1
    descs.append(desc)

    leftDataLen = virtqReq.reqpld_len
    usedDataLen = 0

    while leftDataLen > 0:
        chainLen += 1
        if (leftDataLen <= max_size) :
            curr_len = min(leftDataLen, max_size)
            desc = VirtqDesc(addr=(virtqReq.reqpld_base + usedDataLen),
                             pktlen=curr_len,
                             flags=(VirtqDescFlagBit.NEXT_BIT | extraFlags))
        else:
            curr_len = max_size
            desc = VirtqDesc(addr=(virtqReq.reqpld_base + usedDataLen),
                             pktlen=curr_len,
                             flags=(VirtqDescFlagBit.NEXT_BIT | extraFlags))

        usedDataLen += desc.pktlen
        leftDataLen -= desc.pktlen
        descs.append(desc)

        # 打印desc信息
        virtqBlk.mylog(
            f"VirtqReq2Descs: desc addr={hex(desc.addr)}, buflen={desc.pktlen}, flags={desc.flags}, next={getattr(desc, 'next', None)}, "
            f"usedDataLen={usedDataLen}, leftDataLen={leftDataLen}"
        )

    # The last descriptor is for the request status, which is 1 byte long
    desc = VirtqDesc(addr=virtqReq.reqsts_base,
                         pktlen=1, flags=(VirtqDescFlagBit.WRITE_BIT))
    chainLen += 1
    descs.append(desc)

    if (ignore_chain_len is False) and (chainLen > max_chain_len):
        virtqBlk.mylog(f"Error: chain length {chainLen} exceeds max chain length {max_chain_len}")
        raise ValueError(f"chain length {chainLen} exceeds max chain length {max_chain_len}")

    return descs

class VirtqBlk(Virtq):
    """
    VirtqBlk类继承自Virtq，用于处理块存储设备的虚拟队列
    """
    def __init__(self, tb, qid=0, qlen=1024, mtu=1500, gen=0,
                 size_max=VirtioBlkMaxSegSize.VIRTIO_BLK_MAX_SIZE_PER_SEG, chain_len=VirtioBlkMaxSegs.VIRTIO_BLK_MAX_SEGS_W_HDR_STS, feature_flag=0):
        """
        初始化VirtqBlk类

        参数:
            tb: 测试平台对象
            qid: 队列ID
            qlen: 队列长度
            mtu: 最大传输单元
            gen: 生成号
            sector_size_max: 最大扇区大小，默认32K
            chain_len: 链长度,默认16
            feature_flag: 特性标志，默认0
        """
        # 调用父类初始化方法，设置类型为BLK
        super().__init__(tb, qid, VirtqType.BLK, qlen, mtu, gen)

        # 设置特定于块设备的参数
        self.size_max = size_max
        self.chain_len = chain_len
        self.feature_flag = feature_flag

        # 添加data成员用于存储生成的数据
        self.data = None
        self.data_length = 512  # 默认数据长度

        # 块设备特定的计数器和队列
        self.nrBlkWrites = 0
        self.nrBlkReads = 0
        self.pendingReq = deque()

        # Create an array to store requests, with the same size as qlen
        self.blk_descTb_to_req = [None] * qlen

        self.blk_generated_data = deque()
        self.blk_generated_data_copy = deque()

        self.errCheckerCoro = None
        self.blkDataCheckerCoro = None
        self.enableChecker = CheckerType.VIRTQ_CHECKER_NONE

    def gen_data(self, data_length=None):
        """
        生成随机数据并存储在self.data成员中

        参数:
            data_length: 要生成的数据长度，如果为None则使用self.data_length

        返回:
            生成的数据
        """
        # 更新数据长度
        if data_length is not None:
            self.data_length = data_length

        # 使用os.urandom生成高效的随机数据
        self.data = bytearray(os.urandom(self.data_length))
        return self.data

    async def prepare_blk_req(self, req, data, op_type=None):
        """
        准备块设备请求，设置请求头、有效载荷和状态

        参数:
            req: VirtqReq实例，即请求对象
            data: 要写入的数据
            op_type: 操作类型，默认为None，将使用VIRTIO_BLK_T_OUT

        返回:
            成功返回True，失败返回False
        """
        try:
            # 确定操作类型，默认为写操作
            type_val = op_type if op_type is not None else VirtioBlkType.VIRTIO_BLK_T_OUT
            reserved = 0
            sector = random.randint(0, 0xFFFFFFFF)  # 随机扇区值

            # 使用小端格式格式化头部
            header = struct.pack('<IIQ', type_val, reserved, sector)
            await req.reqhdr_region.write(0, header)

            if op_type == VirtioBlkType.VIRTIO_BLK_T_OUT:
            # 将数据写入请求payload区域
                await req.reqpld_region.write(0, data)
            elif op_type == VirtioBlkType.VIRTIO_BLK_T_IN:
                # clear the payload region
                await req.reqpld_region.write(0, bytes([0] * req.reqpld_len))

            # 写入随机状态字节
            await req.reqsts_region.write(0, bytes([random.randint(0, 255)]))

            return True
        except Exception as e:
            self.mylog(f"Error preparing block request: {e}", force=True)
            return False

    async def allocate_descriptor_ids(self, num_descriptors):
        """
        Allocate the required number of descriptor IDs with retries.

        Args:
            num_descriptors: Number of descriptor IDs to allocate

        Returns:
            List of allocated IDs or empty list if allocation failed
        """
        # Try to allocate the required number of descriptor IDs
        all_IDs = self.idPool.alloc_n_ID(num_descriptors)

        # If we couldn't get enough IDs, wait and retry
        max_retries = 5
        retry_count = 0
        while len(all_IDs) == 0 :
            self.mylog(f"Not enough IDs. Need {num_descriptors} descriptors, but only {len(self.idPool.allocator)} available. Retrying... (attempt {retry_count+1}/{max_retries})", force=True)
            await Timer(400000, 'ns')  # Wait for 1s before retrying

            # Try allocation again
            all_IDs = self.idPool.alloc_n_ID(num_descriptors)
            retry_count += 1

        # If we still couldn't get enough IDs after retrying
        if len(all_IDs) == 0:
            raise ValueError("Failed to allocate descriptor IDs after multiple retries", force=True)

        # Print how many IDs are available in the idPool
        self.mylog(f"idPool : before {len(self.idPool.allocator) + num_descriptors} after{len(self.idPool.allocator)} allocate {num_descriptors} descs", force=True)
        return all_IDs

    async def blk_read_request(self, data=None, data_length=None):
        """
        发送块设备读请求

        参数:
            data: 要读取的数据，如果为None则生成随机数据
            data_length: 数据长度，如果data为None则使用此长度生成数据
        """
        self.mylog(f"start reading with data length {data_length}", force=True)

        # 检查参数有效性
        if data_length is None:
            self.mylog("error: data_length cannot be None", force=True)
            return False

        # 使用VirtqReq创建请求
        req = VirtqReq(reqbase=None, reqlen=data_length, region=None, tb=self.tb)

        # 准备块设备请求
        if not await self.prepare_blk_req(req, data, op_type = VirtioBlkType.VIRTIO_BLK_T_IN):
            self.mylog("Failed to prepare block request", force=True)
            return False

        # 使用VirtqReq2Descs将req转换为descs
        descs = VirtqReq2Descs(virtqReq=req, max_size=self.size_max, extraFlags=VirtqDescFlagBit.WRITE_BIT, max_chain_len=self.chain_len, virtqBlk=self)

        # Allocate descriptor IDs using the new function
        all_IDs = await self.allocate_descriptor_ids(len(descs))

        # fill next descID for desc chain
        prevDesc = descs[0]
        for desc, descID in zip(descs[1:], all_IDs[1:]):
            prevDesc.next = descID
            prevDesc = desc

        # 跟踪请求
        req.ids = all_IDs
        req.descs = descs
        req.type = VirtioBlkType.VIRTIO_BLK_T_IN

        self.pendingReq.append(req)

        self.blk_descTb_to_req[all_IDs[0]] = req
        self.blk_generated_data.append(data)
        self.blk_generated_data_copy.append(data)

        self.mylog(f"blk_descTb_to_req[{all_IDs[0]}] = {req}")

        # 提交描述符链
        await self.fillAvailDescChain(descs, all_IDs)

        await self.notify()
        self.nrBlkReads += 1
        self.mylog(f"successed to read #{req.reqpld_len} bytes")
        return True

    async def blk_write_request(self, data=None, data_length=None):
        """
        发送块设备写请求

        参数:
            data: 要写入的数据，如果为None则生成随机数据
            data_length: 数据长度，如果data为None则使用此长度生成数据
        """
        self.mylog(f"start writing with data length {data_length}", force=True)

        # 检查参数有效性
        if data is None or data_length is None:
            self.mylog("error: data and data_length cannot be None", force=True)
            return False

        # 使用VirtqReq创建请求
        req = VirtqReq(reqbase=None, reqlen=data_length, region=None, tb=self.tb)

        # 准备块设备请求
        if not await self.prepare_blk_req(req, data):
            self.mylog("Failed to prepare block request", force=True)
            return False

        # 使用VirtqReq2Descs将req转换为descs
        descs = VirtqReq2Descs(virtqReq=req, max_size=self.size_max, extraFlags=0, max_chain_len=self.chain_len, virtqBlk=self)

        # Allocate descriptor IDs using the new function
        all_IDs = await self.allocate_descriptor_ids(len(descs))

        # fill next descID for desc chain
        prevDesc = descs[0]
        for desc, descID in zip(descs[1:], all_IDs[1:]):
            prevDesc.next = descID
            prevDesc = desc

        # 跟踪请求
        req.ids = all_IDs
        req.descs = descs
        req.type = VirtioBlkType.VIRTIO_BLK_T_OUT
        self.pendingReq.append(req)

        self.blk_descTb_to_req[all_IDs[0]] = req

        self.mylog(f"blk_descTb_to_req[{all_IDs[0]}] = {req}")
        self.mylog(f"blk_descTb_to_req[{all_IDs[0]}] = {req}")

        # 提交描述符链
        await self.fillAvailDescChain(descs, all_IDs)

        await self.notify()
        self.nrBlkWrites += 1
        self.mylog(f"successed to write #{req.reqpld_len} bytes")
        return True

    async def check_request_status(self, req):
        """
        Check whether the returned status is VIRTIO_BLK_S_OK

        Args:
            req: The VirtqReq instance containing the status region

        Returns:
            True if status is OK, otherwise raises ValueError
        """
        status_buffer = await req.reqsts_region.read(0, 1)
        status = status_buffer[0]
        if status != VirtioBlkStatus.VIRTIO_BLK_S_OK:
            raise ValueError(f"Error: Block request failed with status {status}")
        return True

    async def blkHandler(self):
        """处理块设备完成的中断"""
        self.mylog(f"blkHandler in q{self.qid}")

        while True:
            desc, descID = await self.retrieveUsedDesc()
            if desc is None:
                return

            req = self.blk_descTb_to_req[descID]

            if req is None or descID != req.ids[0]:
                raise ValueError(f"Error: No request found for descID {descID}")

            # Check if this is a read request completed
            if req.type == VirtioBlkType.VIRTIO_BLK_T_IN:
                # Verify that we have generated data to compare with
                if len(self.blk_generated_data_copy) > 0:
                    # Read the data that was written back to the req.reqpld_region
                    read_data = await req.reqpld_region.read(0, req.reqpld_len)

                    # Get the data that we generated
                    generated_data = self.blk_generated_data_copy.popleft()

                    # Compare the data
                    if read_data != generated_data:
                        self.mylog(f"Error: Read data doesn't match generated data.", force=True)
                        self.mylog(f"Read data length: {len(read_data)}, Generated data length: {len(generated_data)}", force=True)

                        raise ValueError("Block read data verification failed: data mismatch")
                    else:
                        self.mylog(f"Block read data verification successful: {req.reqpld_len} bytes match", force=True)
                else:
                    self.mylog(f"Warning: No generated data available to verify read request", force=True)
                    raise ValueError("No generated data available to verify read request")

            await self.check_request_status(req)

            await self.free_descriptor_chain(req)

            await self.free_request_resources(req)

    async def free_descriptor_chain(self, req):
        """
        Free all descriptor IDs associated with a request and remove entries from the mapping table.

        Args:
            req: The request containing descriptor IDs to be freed
        """
        if req is None or not hasattr(req, 'ids') or not req.ids:
            self.mylog("Warning: Attempting to free empty or invalid descriptor chain", force=True)
            return

        descs_ids = req.ids.copy()  # Make a copy to avoid modifying the original
        for descID in descs_ids:
            self.blk_descTb_to_req[descID] = None
            self.idPool.releaseID(descID)

        # The first descriptor ID is the chain header which is already counted when call retrieveUsedDesc
        # So we need to subtract 1 from the count of recycled descriptors
        # to avoid double counting
        self.nrRecycleDescs += len(descs_ids) - 1
        self.mylog(f"Freed descriptor before: {len(self.idPool.allocator) - len(descs_ids)} after: {len(self.idPool.allocator)} freed:{len(descs_ids)}", force=True)

    async def free_request_resources(self, req):
        """Free resources associated with the request"""
        self.tb.mem.free_region(req.reqhdr_region)
        self.tb.mem.free_region(req.reqpld_region)
        self.tb.mem.free_region(req.reqsts_region)

    async def reset(self):
        """
        重置VirtqBlk的状态
        先调用父类的reset方法，再清理VirtqBlk特有的状态
        """
        # 调用父类的reset方法
        await super().reset()
        await self.resetHwErr()

        # 清理VirtqBlk特有的状态
        self.data = None
        self.data_length = 512  # 恢复默认值

        # 重置块设备特有的计数器和队列
        self.nrBlkWrites = 0
        self.nrBlkReads = 0

        # 释放所有pendingReq中的资源
        while len(self.pendingReq) > 0:
            req = self.pendingReq.popleft()
            if req.reqhdr_region is not None:
                self.tb.mem.free_region(req.reqhdr_region)
            if req.reqpld_region is not None:
                self.tb.mem.free_region(req.reqpld_region)
            if req.reqsts_region is not None:
                self.tb.mem.free_region(req.reqsts_region)

        self.pendingReq.clear()
        self.blk_generated_data.clear()
        self.blk_generated_data_copy.clear()
        self.blk_descTb_to_req = [None] * self.qlen
        self.errCheckerCoro = None
        self.blkDataCheckerCoro = None
        self.enableChecker = CheckerType.VIRTQ_CHECKER_NONE

        self.mylog("VirtqBlk reset done", force=True)

    async def start(self):
        """
        启动VirtqBlk，提供块设备专用的启动功能
        这个方法覆盖了父类的同名方法，不调用父类的start
        """
        self.mylog("VirtqBlk starting", force=True)

        # 初始化队列ID
        initId = 0
        await self.AvailRing.write(2, initId.to_bytes(2, byteorder='little'))
        await self.UsedRing.write(2, initId.to_bytes(2, byteorder='little'))

        # 配置块设备队列类型为2
        qt = 2  # 块设备的队列类型固定为2

        # 配置队列
        await self.tb.config(qt, self.qid, 0,
                          self.AvailRing.get_absolute_address(0),
                          self.UsedRing.get_absolute_address(0),
                          self.DescTable.get_absolute_address(0),
                          int(math.log2(self.qlen)),
                          self.msix_addr, self.msix_data, 0, 0, self.gen,
                          65535, 32768, False,
                          msix_enable=1, msix_mask=0)

        # 发送队列设置命令
        await self.tb.qset_cmd(qt, self.qid, 0, 1, 0, 0, 0)


        # Start the appropriate checker based on test_mode
        global test_mode
        self.mylog(f"Starting VirtqBlk handlers based on test mode: {test_mode}", force=True)
        # First validate that test_mode has one of the expected values
        if test_mode not in ["normal", "error", "mixed"]:
            error_msg = f"Invalid test_mode: {test_mode}. Must be 'normal', 'error', or 'mixed'"
            self.mylog(error_msg, force=True)
            raise ValueError(error_msg)

        if test_mode == "error" or test_mode == "mixed":
            self.mylog(f"Starting error checker for {self.qid}", force=True)
            self.errCheckerCoro = cocotb.start_soon(self.errChecker.mainLoop())

        if test_mode == "normal" or test_mode == "mixed":
            self.mylog(f"Starting block data checker for {self.qid}", force=True)
            self.blkDataCheckerCoro = cocotb.start_soon(blkBeqChecker(self).mainLoop_read_write())

        self.mylog(f"VirtqBlk handlers started successfully for test mode: {test_mode}", force=True)


        # 标记已启动
        self.started = True

        # 通知系统块设备队列已经启动
        await self.tb.soc_notify(qt, self.qid)

        self.mylog("VirtqBlk start done", force=True)

allVirtqs = {}

async def blk_handler(address, data, **kwargs):
    # 处理块设备完成中断
    print(f"BLK HANDLER: address: {address} data: {list(data)} {int.from_bytes(data, byteorder='little')}")
    if address == int.from_bytes(data, byteorder='little'):
        qid = address
        virtq = allVirtqs[qid]
        await virtq.blkHandler()

def register_intr_handelr(tb):
    ioregionBlk = IORegion()
    ioregionBlk.register_write_handler(blk_handler)
    tb.mem.register_region(ioregionBlk, 0xffffffffffe00000, 4096)


def testcase_decorator(func):
    @wraps(func)
    async def wrapper(*args, **kwargs):
        virtq = args[0]

        virtq.mylog(f"start test {func.__name__}", force=True)
        await virtq.reset()
        await virtq.start()

        await func(virtq)
        virtq.workDone = True

        if virtq.enableChecker & CheckerType.VIRTQ_CHECKER_ERR:
            virtq.mylog(f"Waiting for error checker to complete", force=True)
            if virtq.errCheckerCoro is not None and not virtq.errCheckerCoro.done():
                await virtq.errCheckerCoro.join()

        if virtq.enableChecker & CheckerType.VIRTQ_CHECKER_BLK:
            virtq.mylog(f"Waiting for block data checker to complete", force=True)
            if virtq.blkDataCheckerCoro is not None and not virtq.blkDataCheckerCoro.done():
                await virtq.blkDataCheckerCoro.join()

        # Add code to forcibly terminate coroutines
        if virtq.errCheckerCoro is not None and not virtq.errCheckerCoro.done():
            virtq.mylog(f"Forcing termination of error checker coroutine", force=True)
            virtq.errCheckerCoro.kill()
            virtq.errCheckerCoro = None

        if virtq.blkDataCheckerCoro is not None and not virtq.blkDataCheckerCoro.done():
            virtq.mylog(f"Forcing termination of data checker coroutine", force=True)
            virtq.blkDataCheckerCoro.kill()
            virtq.blkDataCheckerCoro = None

        virtq.printVirtq()
        virtq.mylog(f"end test {func.__name__}", force=True)
        await Timer(10, 'ns')

    return wrapper

async def testcase_blk_operation(virtqblk, op_type=None, datalength=None, loop=1, mixed_ratio=0.5):
    """
    Unified block operation test function supporting read, write, or mixed operations.

    Args:
        virtqblk: The VirtqBlk instance to use for operations
        op_type: Operation type - 'read', 'write', or 'mixed' (default None, which equals 'write')
        datalength: Data length to use (default None, will generate random length)
        loop: Number of operations to perform (default 1)
        mixed_ratio: For mixed operations, ratio of reads (0.0-1.0) (default 0.5)
    """
    if virtqblk.qtype != VirtqType.BLK:
        raise ValueError(f"Block operation on invalid qtype {virtqblk.qtype}")

    # Default to write if op_type not specified
    if op_type is None:
        op_type = 'write'

    virtqblk.enableChecker = CheckerType.VIRTQ_CHECKER_BLK

    # Validate op_type
    if op_type not in ['read', 'write', 'mixed']:
        raise ValueError(f"Invalid op_type: {op_type}. Must be 'read', 'write', or 'mixed'")

    # Validate mixed_ratio
    if op_type == 'mixed' and not (0.0 <= mixed_ratio <= 1.0):
        raise ValueError(f"Invalid mixed_ratio: {mixed_ratio}. Must be between 0.0 and 1.0")

    virtqblk.mylog(f"Performing {loop} block {op_type} operations", force=True)

    # Add counters for successful operations
    successful_reads = 0
    successful_writes = 0

    for i in range(loop):
        # Determine current operation type for mixed mode
        current_op = op_type
        if op_type == 'mixed':
            current_op = 'read' if random.random() < mixed_ratio else 'write'

        # Generate random data length if not specified
        if datalength is None:
            max_data_length = virtqblk.size_max * VirtioBlkMaxSegs.VIRTIO_BLK_MAX_DATA_SEGS
            current_datalength = random.randint(1, max_data_length)
        else:
            current_datalength = datalength

        virtqblk.mylog(f"Block {current_op} operation {i+1}/{loop} with data length {current_datalength}", force=True)

        # Generate data (needed for both read and write since read verification uses this data)
        data = virtqblk.gen_data(current_datalength)

        # Perform the operation based on type
        success = False
        if current_op == 'read':
            success = await virtqblk.blk_read_request(data=data, data_length=current_datalength)
            if success:
                successful_reads += 1
        else:  # write operation
            success = await virtqblk.blk_write_request(data=data, data_length=current_datalength)
            if success:
                successful_writes += 1

        if not success:
            virtqblk.mylog(f"Block {current_op} operation {i+1} failed, stopping loop", force=True)
            break

        # Add a small delay between operations
        if i < loop - 1:
            await Timer(2000, 'ns')

    # Log the final count of successful operations
    virtqblk.mylog(f"Block operations completed: {successful_reads} reads, {successful_writes} writes", force=True)

    # Return the counts for potential use by the test runner
    return successful_reads, successful_writes


@testcase_decorator
async def testcase_blk_read_data(virtqBlk):
    await testcase_blk_operation(virtqBlk, op_type='read', loop=2)

@testcase_decorator
async def testcase_blk_write_data(virtqBlk):
    await testcase_blk_operation(virtqBlk, op_type='write', loop=2)

@testcase_decorator
async def testcase_blk_mixed_data(virtqBlk):
    await testcase_blk_operation(virtqBlk, op_type='mixed', loop=4, mixed_ratio=0.5)

@testcase_decorator
async def testcase_desc_next_idx_err(virtq):
    # next desc index 大于等于 qlen; blk_err.bit[0]
    # 检测描述符的NEXT desc index标志位是否等于或者超过了队列长度，应该触发 blk_err.bit[0]
    virtq.expErr = True
    virtq.expErrCode = 0x1
    virtq.disableInt = True
    virtq.expStop = True

    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_ERR

    writeBit = 0

    desc = VirtqDesc(addr=0, pktlen=1, flags=VirtqDescFlagBit.NEXT_BIT | writeBit, next=virtq.qlen)
    await virtq.fillAvailDescChain([desc], [0])
    await virtq.notify()

@testcase_decorator
async def testcase_chain_1_err(virtq):
    # chain len == 1; blk_err.bit[0]
    # 检测描述符链长度为1，应该触发 blk_err.bit[1]
    virtq.expErr = True
    virtq.expErrCode = 0x2
    virtq.disableInt = True
    virtq.expStop = True

    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_ERR

    writeBit = 1

    desc = VirtqDesc(addr=0, pktlen=1, flags=writeBit, next=0)
    await virtq.fillAvailDescChain([desc], [0])
    await virtq.notify()

@testcase_decorator
async def testcase_chain_long_err(virtq):
    # chain len > qlen; block error bit[1]
    # 检测描述符链长度超过队列长度，应该触发 blk_err.bit[1]
    virtq.expErr = True
    virtq.expErrCode = 0x2
    virtq.disableInt = True
    virtq.expStop = True

    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_ERR

    writeBit = 0

    descs = []
    IDs = []

    for i in range(0, virtq.qlen + 1):
        # For the last descriptor, don't set NEXT_BIT
        if i == virtq.qlen:
            desc = VirtqDesc(addr=0, pktlen=1, flags=writeBit, next=0)
        else:
            desc = VirtqDesc(addr=0, pktlen=1, flags=VirtqDescFlagBit.NEXT_BIT | writeBit, next=i+1)
        descs.append(desc)
        IDs.append(i)

    await virtq.fillAvailDescChain(descs, IDs)
    await virtq.notify()

@testcase_decorator
async def testcase_chainlen_equal_qlen_noerr(virtq):
    # chain len = qlen; expect no error
    virtq.expErr = True
    virtq.expErrCode = 0x0
    virtq.disableInt = True
    virtq.expStop = False

    writeBit = 0

    descs = []
    IDs = []
    for i in range(0, virtq.qlen):
        # For the last descriptor, don't set NEXT_BIT
        if i == virtq.qlen - 1:
            desc = VirtqDesc(addr=0, pktlen=1, flags=writeBit, next=0)
        else:
            desc = VirtqDesc(addr=0, pktlen=1, flags=VirtqDescFlagBit.NEXT_BIT | writeBit, next=i+1)
        descs.append(desc)
        IDs.append(i)

    await virtq.fillAvailDescChain(descs, IDs)
    await virtq.notify()

@testcase_decorator
async def testcase_desc_flag_indirect_bit_err(virtq):
    # indirect bit should not be set blk_err.bit[2]
    # 检测描述符的INDIRECT_BIT标志位设置错误，应该为0
    virtq.expErr = True
    virtq.expErrCode = 0x4
    virtq.disableInt = True
    virtq.expStop = True

    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_ERR

    # Create a chain of 3 descriptors with INDIRECT_BIT set
    desc1 = VirtqDesc(addr=0, pktlen=16, flags=VirtqDescFlagBit.NEXT_BIT | VirtqDescFlagBit.INDIRECT_BIT)
    desc2 = VirtqDesc(addr=100, pktlen=32, flags=VirtqDescFlagBit.NEXT_BIT | VirtqDescFlagBit.INDIRECT_BIT)
    desc3 = VirtqDesc(addr=200, pktlen=64, flags=VirtqDescFlagBit.INDIRECT_BIT)

    # Set up descriptor chain links
    desc1.next = 1
    desc2.next = 2

    # Fill the descriptor chain with the three descriptors
    await virtq.fillAvailDescChain([desc1, desc2, desc3], [0, 1, 2])
    await virtq.notify()

@testcase_decorator
async def testcase_desc_data_len_large_read_err(virtq):
    # data len > config len for read operation
    # 检测读场景下单个desc的数据长度大于最大值（SIZE_MAX）会触发 blk_err.bit[3]
    virtq.expErr = True
    virtq.expErrCode = 0x8
    virtq.disableInt = True
    virtq.expStop = True

    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_ERR

    # Allocate memory regions for descriptors
    region1 = virtq.tb.mem.alloc_region(16)  # 16 bytes for request header
    region2 = virtq.tb.mem.alloc_region(32769)  # 32769 bytes (>32KB) for data buffer
    region3 = virtq.tb.mem.alloc_region(1)  # 1 byte for status

    # Get absolute addresses for the allocated regions
    addr1 = region1.get_absolute_address(0)
    addr2 = 0
    addr3 = region3.get_absolute_address(0)

    # Create a chain of 3 descriptors:
    # 1. Header descriptor (with READ type)
    # 2. Data descriptor with too large buffer (with WRITE bit set for read operation)
    # 3. Status descriptor (with WRITE bit set)
    desc1 = VirtqDesc(addr=addr1, pktlen=16, flags=VirtqDescFlagBit.NEXT_BIT)
    desc2 = VirtqDesc(addr=addr2, pktlen=32769, flags=VirtqDescFlagBit.NEXT_BIT | VirtqDescFlagBit.WRITE_BIT)
    desc3 = VirtqDesc(addr=addr3, pktlen=1, flags=VirtqDescFlagBit.WRITE_BIT)

    # Set the next field for proper chaining
    desc1.next = 1
    desc2.next = 2

    # Fill the descriptor chain with the three descriptors
    await virtq.fillAvailDescChain([desc1, desc2, desc3], [0, 1, 2])

    # Notify the device to process the queue
    await virtq.notify()

    # Free regions after test
    virtq.tb.mem.free_region(region1)
    virtq.tb.mem.free_region(region2)
    virtq.tb.mem.free_region(region3)

@testcase_decorator
async def testcase_desc_data_len_large_err(virtq):
    # data len > config len
    # 单个desc的数据长度大于最大值（SIZE_MAX） blk_err.bit[3]
    virtq.expErr = True
    virtq.expErrCode = 0x8
    virtq.disableInt = True
    virtq.expStop = True

    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_ERR

    # Allocate memory regions for descriptors
    region1 = virtq.tb.mem.alloc_region(1)  # 1 byte for desc1
    region2 = virtq.tb.mem.alloc_region(32769)  # 32579 bytes for desc2
    region3 = virtq.tb.mem.alloc_region(32)  # 32 bytes for desc3

    # Get absolute addresses for the allocated regions
    addr1 = region1.get_absolute_address(0)
    addr2 = region2.get_absolute_address(0)
    addr3 = region3.get_absolute_address(0)

    # Create a chain of 3 descriptors, with properly allocated memory addresses
    desc1 = VirtqDesc(addr=addr1, pktlen=1, flags=VirtqDescFlagBit.NEXT_BIT)
    desc2 = VirtqDesc(addr=addr2, pktlen=32769, flags=VirtqDescFlagBit.NEXT_BIT)
    desc3 = VirtqDesc(addr=addr3, pktlen=32, flags=0)

    # Set the next field for proper chaining
    desc1.next = 1
    desc2.next = 2

    # Fill the descriptor chain with the three descriptors
    await virtq.fillAvailDescChain([desc1, desc2, desc3], [0, 1, 2])

    await virtq.notify()

@testcase_decorator
async def testcase_desc_data_len_0_err(virtq):
    # 描述符数据长度为0 blk_err.bit[3]
    virtq.expErr = True
    virtq.expErrCode = 0x8
    virtq.disableInt = True
    virtq.expStop = True

    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_ERR

    # Create a chain of 3 descriptors, with the first one having length=0
    desc1 = VirtqDesc(addr=0, pktlen=0, flags=VirtqDescFlagBit.NEXT_BIT)
    desc2 = VirtqDesc(addr=100, pktlen=16, flags=VirtqDescFlagBit.NEXT_BIT)
    desc3 = VirtqDesc(addr=200, pktlen=32, flags=0)

    # Set the next field for proper chaining
    desc1.next = 1
    desc2.next = 2

    # Fill the descriptor chain with the three descriptors
    await virtq.fillAvailDescChain([desc1, desc2, desc3], [0, 1, 2])
    await virtq.notify()

@testcase_decorator
async def testcase_ring_id_err(virtq):
    # ring idx > qsize bit
    # 读取的avail_ring的idx值与上次的值相比，差值超过 queue 长度 blk_err.bit[4]
    virtq.expErr = True
    virtq.expErrCode = 0x10
    virtq.disableInt = True
    virtq.expStop = True

    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_ERR

    await virtq.writeNextAvailElem(virtq.qlen + 1)
    await virtq.notify()

@testcase_decorator
async def testcase_idx_err(virtq):
    # 读取的avail_ring的idx值与上次的值相比，差值超过 queue 长度 blk_err.bit[5]
    virtq.expErr = True
    virtq.expErrCode = 0x20 #bit 5
    virtq.disableInt = True
    virtq.expStop = True

    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_ERR

    await testcase_blk_operation(virtq, op_type='mixed', loop=1, mixed_ratio=0.5)

    ringID = virtq.qlen + 2
    await virtq.AvailRing.write(2, ringID.to_bytes(2, byteorder='little'))

@testcase_decorator
async def testcase_random_start_stop(virtq):
    virtq.enableChecker |= CheckerType.VIRTQ_CHECKER_BLK

    random_list = [random.randint(10, 100) for _ in range(random.randint(10, 100))]
    for i in random_list:
        await testcase_blk_operation(virtq, op_type='mixed', loop=2, mixed_ratio=0.5)

        await virtq.reset()
        await virtq.start()

@testcase_decorator
async def testcase_crazy_start_stop(virtq):
    virtq.nrTestPkts = 0
    for i in range(0, 10000):
        await virtq.stop()
        await Timer(12, 'ns')
        await virtq.start()

async def startAllTestOnBlk(virtq, testNum, testCases=[testcase_blk_write_data]):
    log = logging.getLogger("cocotb.tb")
    for i in range(testNum):
        for test in testCases:
            log.debug(f"{i}-th test on q{virtq.qid}")
            log.debug(f"\t[q{virtq.qid}]: testcase:     {test.__name__}")
            log.debug(f"\t[q{virtq.qid}]: queue length:        {virtq.qlen}")
            log.debug(f"\t[q{virtq.qid}]: max sector size:          {virtq.size_max}")
            log.debug(f"\t[q{virtq.qid}]: max chain len:          {virtq.chain_len}")
            log.debug(f"\t[q{virtq.qid}]: feature flag: {virtq.feature_flag}")
            await test(virtq)
    '''
    await virtq.tb.qset_cmd(qid_type = virtq.qtype,qid = virtq.qid,start_ptr = 0,start =0,stop =1,pause =0,cancel_pause = 0)
     
    (rd_desc_num_blk,rd_data_num_blk,wr_data_num_blk,wr_used_num_blk,wr_msix_num_blk) = await virtq.tb.get_blk_stop_info(virtq.qtype,virtq.qid)
    await Timer(200, 'ns')
    (dfx_rd_desc_num_blk,dfx_rd_data_num_blk,dfx_wr_data_num_blk,dfx_wr_used_num_blk,dfx_wr_msix_num_blk) = await virtq.tb.rd_dfx_blk_stop_info(virtq.qtype,virtq.qid)
    assert int(rd_desc_num_blk) == int(dfx_rd_desc_num_blk)
    assert int(rd_data_num_blk) == int(dfx_rd_data_num_blk)
    assert int(wr_data_num_blk) == int(dfx_wr_data_num_blk)
    assert int(wr_used_num_blk) == int(dfx_wr_used_num_blk)
    assert int(wr_msix_num_blk) == int(dfx_wr_msix_num_blk)
        
    (cmd_ack,used_ptr) =  await virtq.tb.qset_cmd_ack(virtq.qtype,virtq.qid)
    while cmd_ack == 0 :
        await Timer(20, 'ns')
        (cmd_ack,used_ptr) =  await virtq.tb.qset_cmd_ack(virtq.qtype,virtq.qid)
    '''

async def get_test_cases_from_env():
    """
    Get test cases to run based on the TEST_CASES environment variable.
    Format: comma-separated list of test case names, abbreviations, or indices
    Examples:
        - Full names: 'testcase_blk_write_data,testcase_blk_read_data'
        - Abbreviations: 'write,read,mixed'
        - Numbers: '0,1,2' (corresponding to the order in available_tests)
        - Mixed: 'write,1,testcase_idx_err'
    Returns an array of test case functions.
    """
    # Dictionary mapping test case names to actual test case functions
    available_tests = [
        ("testcase_blk_write_data", testcase_blk_write_data, "write", "normal"), # 0
        ("testcase_blk_read_data", testcase_blk_read_data, "read", "normal"), # 1
        ("testcase_blk_mixed_data", testcase_blk_mixed_data, "mixed", "normal"), # 2
        ("testcase_desc_next_idx_err", testcase_desc_next_idx_err, "next_idx", "error"), # 3
        ("testcase_chain_1_err", testcase_chain_1_err, "chain_1", "error"), # 4
        ("testcase_chain_long_err", testcase_chain_long_err, "chain_long", "error"),# 5
        ("testcase_desc_flag_indirect_bit_err", testcase_desc_flag_indirect_bit_err, "indirect", "error"),# 6
        ("testcase_desc_data_len_large_err", testcase_desc_data_len_large_err, "len_large", "error"), # 7
        ("testcase_desc_data_len_large_read_err", testcase_desc_data_len_large_read_err, "len_large_read", "error"), # 8
        ("testcase_desc_data_len_0_err", testcase_desc_data_len_0_err, "len_0", "error"), # 9
        ("testcase_ring_id_err", testcase_ring_id_err, "ring_id", "error"), # 10
        ("testcase_idx_err", testcase_idx_err, "idx", "error"), # 11
        ("testcase_chainlen_equal_qlen_noerr", testcase_chainlen_equal_qlen_noerr, "chainlen_equal_qlen", "normal") # 12
    ]

    # Get test cases from environment variable
    test_cases_str = os.environ.get('TEST_CASES', 'mixed')
    test_case_identifiers = [identifier.strip() for identifier in test_cases_str.split(',')]
    global test_mode

    # Get the corresponding test case functions
    selected_tests = []
    test_has_normal = False
    test_has_error = False

    for identifier in test_case_identifiers:
        test_found = False

        # Check if identifier is a number
        if identifier.isdigit():
            idx = int(identifier)
            if 0 <= idx < len(available_tests):
                selected_tests.append(available_tests[idx][1])
                test_found = True

                # Check if this test is normal or error
                if available_tests[idx][3] == "normal":
                    test_has_normal = True
                elif available_tests[idx][3] == "error":
                    test_has_error = True
            else:
                logging.warning(f"Test index '{idx}' out of range (0-{len(available_tests)-1}), skipping")

        # Check if identifier matches full name or abbreviation
        if not test_found:
            for i, (full_name, test_func, abbrev, test_type) in enumerate(available_tests):
                if identifier == full_name or identifier == abbrev:
                    selected_tests.append(test_func)
                    test_found = True

                    # Check if this test is normal or error
                    if test_type == "normal":
                        test_has_normal = True
                    elif test_type == "error":
                        test_has_error = True
                    break

            if not test_found:
                logging.warning(f"Test case '{identifier}' not recognized, skipping")

    # If no valid test cases were found, use the default
    if not selected_tests:
        logging.warning(f"No valid test cases specified, using default: testcase_blk_mixed_data")
        selected_tests = [testcase_blk_mixed_data]
        test_has_normal = True

    # Set the global test_mode variable
    if test_has_normal and test_has_error:
        test_mode = "mixed"
    elif test_has_normal:
        test_mode = "normal"
    elif test_has_error:
        test_mode = "error"
    else:
        test_mode = "unknown"

    # Print out test mode and selected tests for debugging
    logging.debug(f"Test mode set to: {test_mode}")
    logging.debug(f"Selected tests: {[test.__name__ for test in selected_tests]}")

    return selected_tests

async def startTest(tb, testNum=1, qnum=1, qtype=VirtqType.BLK, testCases=None, mode= None):
    register_intr_handelr(tb)

    global allVirtqs
    allVirtqs.clear()

    if testCases is None:
        testCases = await get_test_cases_from_env()

    # Print selected test cases with more details
    print("Selected test cases:")
    for i, test_case in enumerate(testCases):
        print(f"  {i+1}. {test_case.__name__}")

    # Also print the test mode being used
    print(f"Test mode: {test_mode}")
    qids = random.sample(range(0, 256), qnum)
    qlens = [random.choice([1 << i for i in range(8,11)]) for _ in range(qnum)]
    mtus = random.sample(range(0, 65536), qnum)
    for i in range(qnum):
        # 修正创建VirtqBlk实例的方式，确保参数正确传递
        allVirtqs[qids[i]] = VirtqBlk(tb, qids[i], qlens[i], mtus[i], gen=0, size_max=VirtioBlkMaxSegSize.VIRTIO_BLK_MAX_SIZE_PER_SEG,
                                      chain_len=VirtioBlkMaxSegs.VIRTIO_BLK_MAX_SEGS_W_HDR_STS, feature_flag=0)

    workers = []
    for virtq in allVirtqs.values():
        # Run all test cases for each virtq
        workers.append(cocotb.start_soon(startAllTestOnBlk(virtq, testNum, testCases)))

    for worker in workers:
        await worker.join()

    print("startTest exit")
