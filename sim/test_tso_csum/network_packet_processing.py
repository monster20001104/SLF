#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : network_packet_processing.py
#* 作者名称 : matao
#* 创建日期 : 2025/06/12
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   06/12       matao       初始化版本
#******************************************************************************/
from collections import Counter
import sys
sys.path.append('..')
sys.path.append('../common')
import itertools
import logging
from logging.handlers import RotatingFileHandler
import os
import sys
import random
import cocotb_test.simulator
import scapy
import struct

import cocotb
from cocotb.log import SimLog,  SimLogFormatter
from cocotb.queue import Queue, QueueFull
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, First
from cocotb.clock import Clock
from scapy.all import conf,RandString, RandIP, RandIP6
from scapy.all import Ether, IP, TCP, sendp, sr1, hexdump, IPv6, UDP, ICMP,  IPOption, LLC, SNAP, IPOption_Router_Alert, IPOption_Timestamp, IPOption_Security, RandMAC
from scapy.layers.l2 import Dot1Q 
from scapy.all import Packet, BitField
from typing import List, NamedTuple, Union
from cocotb.regression import TestFactory
from vio_nettx_data_bus import VirtioHeader

def generate_random_mac(eth_flag=0):
    oui = [0x00, 0x16, 0x3e]
    
    if eth_flag == 2:  
        byte4 = random.randint(0x80, 0xff)
        byte5 = random.randint(0x00, 0xff)
        byte6 = random.randint(0x00, 0xff)
    else:
        byte4 = random.randint(0x00, 0x7f)
        byte5 = random.randint(0x00, 0xff)
        byte6 = random.randint(0x00, 0xff)
    
    mac = oui + [byte4, byte5, byte6]
    
    return ':'.join(map(lambda x: f"{x:02x}", mac))

def generate_random_ip(ip_version=4):
    if ip_version == 4:
        private_networks = [
            (10,), (172, random.randint(16, 31)), (192, 168)
        ]
        network = random.choice(private_networks)
        host = tuple(random.randint(0, 255) for _ in range(4 - len(network)))
        return '.'.join(map(str, network + host))
    else:
        prefix = random.randint(0xfc00, 0xfdff)
        segments = [prefix] + [random.randint(0, 0xffff) for _ in range(7)]
        return ':'.join(f"{seg:x}" for seg in segments)
def random_ipv4_option():
    """
    Generate valid IPv4 extension options of random length
    """
    length = random.randint(1, 40)  
    if length == 1:
        return b'\x01'  
    option_type = 0x44    
    option_len = length   
    option_value = bytes(random.randint(0, 255) for _ in range(option_len - 2))
    return struct.pack("!BB", option_type, option_len) + option_value

def generate_tcp_options():
    """
    Generate specific TCP extension options
    """
    option_types = ['MSS', 'WScale', 'SAckOK', 'Timestamp']
    num_options = random.randint(1, 4)
    selected_options = random.choices(option_types, k = num_options)
    options = []
    for opt_type in selected_options:
        if opt_type == 'MSS':
            mss_value = random.randint(536, 1460)
            options.append(('MSS', mss_value))
        elif opt_type == 'WScale':
            scale = random.randint(0, 14)
            options.append(('WScale', scale))
        elif opt_type == 'SAckOK':
            options.append(('SAckOK', b''))
        elif opt_type == 'Timestamp':
            ts_val = random.randint(0, 0xffffffff)
            ts_ecr = random.randint(0, 0xffffffff)
            options.append(('Timestamp', (ts_val, ts_ecr)))
    return options

def build_network_packet(eth_flag = 0, ip_version = 4, transport_protocol = "tcp", virtio_gso_size = 0, ip_option = 0, trans_option = 0,
                        packet_length = None, ip_len_err = 0, err = 0):
    """
    Constructing data packets for network protocol stack
    parameter:
        eth_flag: eth type(0=IP, 1=VLAN, 2=LLC)
        ip_version: IP version(4=ipv4,6=ipv6)
        transport_protocol: "tcp""udp""icmp"
        ip_option: 0: ip no option, 1:ip have option
        trans_option: 0: tcp no option, 1:tcp have option
        packet_length: packet len byte
        ip_len_err: 0:ip len no err, 1:ip len have err
        err: Data bus sideband error signal, an error occurred in a certain beat
        region_type: The type of err signal in the data segmentation area, 0 = no err, 1,2,3 = network data contains errors
        segment_index: Location of data error
        payload_relative_start:The starting position of this segment relative to the payload (non head), region_type = 3 is valid
    """
    # Build Ethernet layer and subsequent protocols based on eth_flag
    eth_hdr_len = 0
    dsta = generate_random_mac(eth_flag)
    srca = generate_random_mac(eth_flag)
    dstip4 = generate_random_ip(ip_version)
    srcip4 = generate_random_ip(ip_version)
    dstip6 = generate_random_ip(ip_version)
    srcip6 = generate_random_ip(ip_version)

    is_crossing_segment = False

    if eth_flag == 0:  # IP
        eth_layer = Ether(
            dst  = dsta,
            src  = srca,
            type = 0x0800 if ip_version == 4 else 0x86DD
        )
        eth_hdr = eth_layer
    elif eth_flag == 1:  # VLAN
        eth_layer = Ether(
            dst  = dsta,
            src  = srca,
            type = 0x8100  
        )
        random_vlan = random.randint(1, 4094)
        random_prio = random.randint(0,7)
        random_dei  = random.randint(0, 1)
        vlan_layer  = Dot1Q(
            type = 0x0800 if ip_version == 4 else 0x86DD,
            vlan = random_vlan,
            prio = random_prio,
            dei  = random_dei
        )
        eth_hdr = eth_layer / vlan_layer
    elif eth_flag == 2:  # LLC
        eth_layer = Ether(
            dst  = dsta,
            src  = srca,
            type = 0x0000  # 802.3 
        )
        snap_oui = 0
        snap_code = 0x0800 if ip_version == 4 else 0x86DD
        eth_hdr = eth_layer / LLC(dsap = 0xAA, ssap = 0xAA, ctrl = 3) / SNAP(OUI = snap_oui, code = snap_code)#14 + 1+1+1 +3+2
    else:
        raise ValueError("eth_flag must be 0(IP), 1(VLAN) or 2(LLC)")
    eth_hdr_len = len(eth_hdr)

    # IP build option
    ip_hdr_len = 0
    if ip_version == 4:
        ip_opts = []
        if ip_option == 1:
            ip_opts = random_ipv4_option()
        ip_layer = IP(
            version = 4, 
            tos     = random.randint(0, 255),
            id      = random.randint(0, 65535),
            flags   = 0,
            frag    = 0, 
            ttl     = random.randint(1, 255),
            proto   = 6 if transport_protocol.lower() == "tcp" else (17 if transport_protocol.lower() == "udp" else 1),
            src     = srcip4,
            dst     = dstip4,
            options = ip_opts
        )
    else:  # IPv6
        if ip_option == 1:
            nh_value = 0
        else:
            nh_value = 6 if transport_protocol.lower() == "tcp" else (17 if transport_protocol.lower() == "udp" else 1)
        ip_layer = IPv6(
            version = 6, 
            tc      = random.randint(0, 255),
            fl      = random.randint(0, 0xFFFFF),
            plen    = None,
            nh      = nh_value,
            hlim    = random.randint(1, 255),
            src     = srcip6,
            dst     = dstip6
        )
    ip_hdr_len = len(ip_layer)

    #tcp/udp/icmp
    src_port = random.randint(1, 65535)
    dst_port = random.randint(1, 65535)
    trans_hdr_len = 0
    if transport_protocol.lower() == "tcp":
        tcp_opts   = []
        flags_list = ['S', 'A', 'F', 'R', 'P', 'U', 'E', 'C']
        num_flags  = random.randint(1, 4)
        flags      = ''.join(random.sample(flags_list, num_flags))
        urg_ptr    = random.randint(0, 65535) if 'U' in flags else 0
        if trans_option == 1:
            tcp_opts = generate_tcp_options()
        transport_layer = TCP(
            sport    = src_port, 
            dport    = dst_port,
            seq      = random.randint(0, 0xFFFFFFFF),
            ack      = random.randint(0, 0xFFFFFFFF),
            reserved = 0, 
            flags    = flags,
            window   = random.randint(1, 65535), 
            urgptr   = urg_ptr,
            options  = tcp_opts
        )
    elif transport_protocol.lower() == "udp":
        transport_layer = UDP(sport = src_port, dport = dst_port)
    elif transport_protocol.lower() == "icmp":
        transport_layer = ICMP()
    else:
        raise ValueError("trans must be tcp/udp/icmp")
    trans_hdr_len = len(transport_layer)

    total_overhead = eth_hdr_len + ip_hdr_len + trans_hdr_len
    virtio_overhead = 12  
    effective_length = max(0, packet_length - virtio_overhead - total_overhead)
    random_payload = bytes([random.randint(0, 255) for _ in range(effective_length)])

    network_packet = eth_hdr / ip_layer / transport_layer / random_payload
    network_data = network_packet.build()

    #Incorrect injection length mismatch
    if ip_len_err:
        ip_start = eth_hdr_len
        if ip_version == 4:
            ip_len_offset = ip_start + 2
            current_ip_len = struct.unpack("!H", network_data[ip_len_offset:ip_len_offset+2])[0]
            while True:
                invalid_ip_len = random.randint(21, 65534)  
                if invalid_ip_len != current_ip_len:
                    break
            network_data = (
                network_data[:ip_len_offset] + 
                struct.pack("!H", invalid_ip_len) + 
                network_data[ip_len_offset+2:]
            )
        else :
            payload_len_offset = ip_start + 4
            current_payload_len = struct.unpack("!H", network_data[payload_len_offset:payload_len_offset+2])[0]
            max_payload_len = 65535 - 40
            while True:
                invalid_payload_len = random.randint(1, max_payload_len)
                if invalid_payload_len != current_payload_len:
                    break
            network_data = (
                network_data[:payload_len_offset] + 
                struct.pack("!H", invalid_payload_len) + 
                network_data[payload_len_offset+2:]
            )
    #Data sideband signal manufacturing error
    #0 = No error, 1 = Error in packet header, 2 = Error at head and payload mixing, 3 = Error at payload
    if err :
        hdr_length = total_overhead + 12
        total_segments = (packet_length + 31) // 32
        payload_length = effective_length
        pure_hdr_segments = hdr_length // 32
        has_mixed = hdr_length % 32 != 0
        mixed_segments = 1 if has_mixed else 0
        pure_payload_segments = total_segments - pure_hdr_segments - mixed_segments
        valid_regions = []
        if pure_hdr_segments > 0:
            valid_regions.append((1, pure_hdr_segments))
        if mixed_segments > 0:
            valid_regions.append((2, mixed_segments))
        if pure_payload_segments > 0:
            valid_regions.append((3, pure_payload_segments))
        region_type = random.choice([r[0] for r in valid_regions])
        region_segments = next(r[1] for r in valid_regions if r[0] == region_type)
        segment_offset = sum(r[1] for r in valid_regions if r[0] < region_type)
        segment_index = segment_offset + random.randint(0, region_segments - 1)
        payload_relative_start = (segment_index * 32) - hdr_length

        if region_type == 3:  
            segment_start = payload_relative_start
            remaining_payload = payload_length - segment_start
            segment_length = min(32, remaining_payload) 
            segment_end = segment_start + segment_length

            gso_segment_start = segment_start // virtio_gso_size
            gso_segment_end = (segment_end - 1) // virtio_gso_size  
            is_crossing_segment = gso_segment_start != gso_segment_end
    else :
        segment_index = 0 
        region_type = 0
        payload_relative_start= 0

    return network_data, network_packet, region_type, segment_index, payload_relative_start, is_crossing_segment

def process_network_packet(data, eth_flag, ip_version, transport_protocol, ip_option, trans_option, packet_length, ip_len_err, virtio_en, 
        virtio_flags, virtio_gso_type, virtio_gso_size, err, region_type, segment_index, payload_relative_start, is_crossing_segment, tso_en, csum_en):
    """
    Process network packets based on conditions:
        1.tso + checksum
        2.checksum
        3.bypass
    
    parameter:
        data: Original data packet byte stream
        eth_flag: Ethernet Type (0=IP, 1=VLAN, 2=LLC)
        ip_version: IPversion (4=IPv4, 6=IPv6)
        transport_protocol: Transport Protocol ("tcp", "udp", "icmp")
        ip_option: IP option flag (0=no options, 1=options available)
        trans_option: Transport layer option flag (0=no options, 1=options available)
        ip_len_err: 0:ip len no err, 1:ip len have err
        virtio_en: Virtio enable flag (0=random data, 1=Virtio header)
        virtio_flags: Virtio checksum enable (0= no enable, 1=enable)
        virtio_gso_type: Virtio GSOtype (0=none, 1=tcpv4, 3=udp, 4=tcpv6)
        virtio_gso_size: Virtio tso MSS
        err: Data bus sideband error signal, an error occurred in a certain beat
        region_type: The type of err signal in the data segmentation area, 0 = no err, 1,2,3 = network data contains errors
        segment_index: Location of data error
        payload_relative_start:The starting position of this segment relative to the payload (non head), region_type = 3 is valid
        
    retrun:
        list: Processed packet list
    """
    # 1.TSO processing
    if (ip_len_err == 0 and
        virtio_en == 1 and 
        tso_en == 1 and
        virtio_gso_type in [1, 4] and 
        eth_flag in [0, 1] and 
        ((region_type == 3 and err == 1) or err == 0) and
        ((virtio_gso_type == 1 and ip_version == 4) or (virtio_gso_type == 4 and ip_version == 6)) and
        transport_protocol == "tcp" and 
        packet_length >= 160 and
        virtio_gso_size >= 128 and 
        ip_option == 0):
        
        # Extract Virtio header (12 bytes) and network data
        reversed_bytes = data[:12]
        original_bytes = reversed_bytes[::-1]
        original_virtio_hdr = VirtioHeader(original_bytes)
        network_data = data[12:]
        
        pkt = Ether(network_data)
        
        # Extract protocols from each layer
        if eth_flag == 1:  # VLAN
            eth_layer = pkt.getlayer(Ether)
            vlan_layer = pkt.getlayer(Dot1Q)
            ip_layer = pkt.getlayer(IP) if ip_version == 4 else pkt.getlayer(IPv6)
            tcp_layer = ip_layer.getlayer(TCP)
            payload = tcp_layer.payload.load
        else:  # IP
            eth_layer = pkt.getlayer(Ether)
            ip_layer = pkt.getlayer(IP) if ip_version == 4 else pkt.getlayer(IPv6)
            tcp_layer = ip_layer.getlayer(TCP)
            payload = tcp_layer.payload.load

        # Calculate TCP header length (including options)
        tcp_header_len = len(tcp_layer)
        
        # Split Payload
        segments = []
        start = 0
        print(f"payload len is {len(payload)}")
        print(f"virtio_gso_size is {virtio_gso_size}")
        while start < len(payload):
            segment_size = min(virtio_gso_size, len(payload) - start)
            segments.append(payload[start:start + segment_size])
            start += segment_size
        
        # Generate a list of segmented data packets
        result_packets = []
        info_tso = []
        current_seq = tcp_layer.seq
        total_segments = len(segments)
        
        for i, segment in enumerate(segments):
            # copy IP layer
            if ip_version == 4:
                new_ip = IP(
                    version = ip_layer.version,
                    ihl = ip_layer.ihl,
                    tos = ip_layer.tos,
                    len = None,
                    #id = ip_layer.id + i,
                    id = (ip_layer.id + i) % 65536,
                    flags = ip_layer.flags,  
                    frag = ip_layer.frag,
                    ttl = ip_layer.ttl,
                    proto = ip_layer.proto,
                    src = ip_layer.src,
                    dst = ip_layer.dst,
                    chksum = None
                )
            else:  # IPv6
                new_ip = IPv6(
                    version = ip_layer.version,
                    tc = ip_layer.tc,
                    fl = ip_layer.fl,
                    plen = None,
                    nh = ip_layer.nh,
                    hlim = ip_layer.hlim,
                    src = ip_layer.src,
                    dst = ip_layer.dst
                )

            # copy TCP layer
            #tcp flag
            flags = tcp_layer.flags
            if i < total_segments - 1:
                flags = flags.replace("F", "").replace("P", "") if isinstance(flags, str) else flags
                flag_str = str(flags).replace("F", "").replace("P", "")
                flags = flag_str
            new_tcp = TCP(
                sport = tcp_layer.sport,
                dport = tcp_layer.dport,
                seq = current_seq,
                ack = tcp_layer.ack,
                dataofs = tcp_layer.dataofs,
                reserved = tcp_layer.reserved,
                flags = flags,
                window = tcp_layer.window,
                urgptr = tcp_layer.urgptr,
                options = tcp_layer.options,
                chksum = None
            )
            
            # updata tcp seq
            current_seq += len(segment)
            
            # Build a complete data package
            if eth_flag == 0:  # eth/ip
                new_pkt = Ether(src=pkt.src, dst=pkt.dst, type=pkt.type) / new_ip / new_tcp / segment
            else:  # VLAN
                new_vlan = Dot1Q(
                vlan=vlan_layer.vlan,
                prio=vlan_layer.prio,
                dei=vlan_layer.dei,
                type=vlan_layer.type
            )
                new_pkt = Ether(src=pkt.src, dst=pkt.dst, type=pkt.type) / new_vlan / new_ip / new_tcp / segment

            # Modify Virtio header and add it to the result list
            virtio_hdr = VirtioHeader(
                num_buffers  = original_virtio_hdr.num_buffers,
                csum_offset  = original_virtio_hdr.csum_offset,
                csum_start   = original_virtio_hdr.csum_start,
                gso_size     = original_virtio_hdr.gso_size,
                hdr_len      = original_virtio_hdr.hdr_len,
                gso_type_ecn = original_virtio_hdr.gso_type_ecn,
                gso_type     = 0,
                flags_rsv    = original_virtio_hdr.flags_rsv,
                flags        = 0
            )
            virtio_hdr_data = virtio_hdr.build()[::-1]
            bytes_0_1 = virtio_hdr_data[:2]
            bytes_4_5 = virtio_hdr_data[4:6]
            combined_bytes = bytes_0_1 + bytes_4_5
            result_packet =  new_pkt.build()
            ref_virtio_flags = int.from_bytes(combined_bytes, byteorder='little')
            result_packets.append((result_packet, ref_virtio_flags, 3)) #sop eop sametime = 3

        new_segment_index = payload_relative_start // virtio_gso_size
        
        if region_type == 3 and err == 1:
            if is_crossing_segment:
                result_packets.pop(new_segment_index)
                result_packets.pop(new_segment_index)
            else : 
                result_packets.pop(new_segment_index)
        return result_packets
    
    # 2.checksum processing
    elif (ip_len_err == 0 and
          err == 0 and
          csum_en == 1 and
          virtio_en == 1 and 
          virtio_flags == 1 and 
          eth_flag in [0, 1] and 
          ip_version in [4, 6] and 
          transport_protocol in ["tcp", "udp"] and 
          ip_option == 0):
        
        # Extract Virtio header (12 bytes) and network data
        reversed_bytes = data[:12]
        original_bytes = reversed_bytes[::-1]
        original_virtio_hdr = VirtioHeader(original_bytes)
        network_data = data[12:]

        pkt = Ether(network_data)
        
        if ip_version == 4 and IP in pkt:
            pkt[IP].chksum = None  
        
        if transport_protocol == "tcp" and TCP in pkt:
            pkt[TCP].chksum = None  
        elif transport_protocol == "udp" and UDP in pkt:
            pkt[UDP].chksum = None  
        
        #Modify Virtio header and add it to the result list
        virtio_hdr = VirtioHeader(
            num_buffers  = original_virtio_hdr.num_buffers,
            csum_offset  = original_virtio_hdr.csum_offset,
            csum_start   = original_virtio_hdr.csum_start,
            gso_size     = original_virtio_hdr.gso_size,
            hdr_len      = original_virtio_hdr.hdr_len,
            gso_type_ecn = original_virtio_hdr.gso_type_ecn,
            gso_type     = original_virtio_hdr.gso_type,
            flags_rsv    = original_virtio_hdr.flags_rsv,
            flags        = 0
        )
        result_packet = virtio_hdr.build()[::-1] + pkt.build()
        result_new_packet = pkt.build()
        bytes_0_1 = result_packet[:2]
        bytes_4_5 = result_packet[4:6]
        combined_bytes = bytes_0_1 + bytes_4_5
        ref_virtio_flags = int.from_bytes(combined_bytes, byteorder='little')
        if len(result_packet) > 32768:
            return split_packet(result_packet, ref_virtio_flags) #sop=2,eop=1,no sop eop = 0
        else:
            return [(result_new_packet, ref_virtio_flags, 3)] #sop eop sametime = 3

    # 3.err 
    elif ((ip_len_err == 1 and
         virtio_en == 1 and 
         eth_flag in [0, 1] and 
         ip_version in [4,6] )or 
         (region_type in [1,2,4] and
         err == 1 ) or
         ((not (ip_len_err == 0 and
         virtio_en == 1 and 
         tso_en == 1 and
         virtio_gso_type in [1, 4] and 
         eth_flag in [0, 1] and 
         ((virtio_gso_type == 1 and ip_version == 4) or (virtio_gso_type == 4 and ip_version == 6)) and
         transport_protocol == "tcp" and 
         ip_option == 0)) and region_type == 3) or
         packet_length < 13
         ):

        return []
    # 4.bypass
    else:
        #return [data]
        bytes_0_1 = data[:2]
        bytes_4_5 = data[4:6]
        combined_bytes = bytes_0_1 + bytes_4_5
        ref_virtio_flags = int.from_bytes(combined_bytes, byteorder='little')
        result_packet = data[12:] 
        if len(data) > 32768:
            return split_packet(data,ref_virtio_flags)#sop=2,eop=1,no sop eop = 0
        else:
            return [(result_packet, ref_virtio_flags, 3)]#sop eop sametime = 3

def compare_network_packet(len32K_flag, dut_data, ref_data, eth_flag, ip_version, transport_protocol, ip_option, trans_option, packet_length,
                 virtio_en, virtio_flags, virtio_gso_type, virtio_gso_size, rsp_pkt_cnt,err,region_type,segment_index,payload_relative_start, tso_en, csum_en):
    """
    Process network packets based on conditions:
        1.tso + checksum
        2.checksum
        3.bypass
    
    parameter:
        dut_data: dut output data packet byte stream
        ref_data: reference_model output data packet byte stream
        eth_flag: Ethernet Type (0=IP, 1=VLAN, 2=LLC)
        ip_version: IPversion (4=IPv4, 6=IPv6)
        transport_protocol: Transport Protocol ("tcp", "udp", "icmp")
        ip_option: IP option flag (0=no options, 1=options available)
        trans_option: Transport layer option flag (0=no options, 1=options available)
        virtio_en: Virtio enable flag (0=random data, 1=Virtio header)
        virtio_flags: Virtio checksum enable (0= no enable, 1=enable)
        virtio_gso_type: Virtio GSOtype (0=none, 1=tcpv4, 3=udp, 4=tcpv6)
        virtio_gso_size: Virtio tso MSS
        
    retrun:
        list: Processed packet list
    """
    param_info = (
        f"Parameters: eth_flag={eth_flag}, ip_version={ip_version}, "
        f"transport_protocol={transport_protocol}, ip_option={ip_option}, "
        f"trans_option={trans_option}, packet_length={packet_length}, "
        f"virtio_en={virtio_en}, virtio_flags={virtio_flags}, "
        f"virtio_gso_type={virtio_gso_type}, virtio_gso_size={virtio_gso_size}, "
        f"rsp_pkt_cnt={rsp_pkt_cnt},"
        f"len32K_flag={len32K_flag},"
        f"err={err},"
        f"region_type={region_type},"
        f"segment_index={segment_index},"
        f"payload_relative_start={payload_relative_start}"
    )
    errors = []
    chunk_idx, result = compare_data_in_256bit_chunks(dut_data, ref_data)
    #print(chunk_idx)
    error_details = []
    if chunk_idx > 0:
        error_details.append(f"REF chunk data: {result['ref_chunk_hex']}")
        
        error_details.append(f"Input Data Mismatch found in chunk {chunk_idx} (256-bit)")
        error_details.append(f"First difference at byte position {result['byte_position']}")
        error_details.append(f"DUT value: {result['dut_value']}, REF value: {result['ref_value']}")
        error_details.append(f"DUT chunk data: {result['dut_chunk_hex']}")
        error_details.append(f"REF chunk data: {result['ref_chunk_hex']}")
    elif chunk_idx == -1:
        error_details.append(f"compare input Data comparison failed: {result}")
    if error_details:
        errors.append(f"{param_info}\ndata difference: \n" + "\n".join(error_details))
    # 1.TSO or checksum   virtio_flags == 1 
    if (virtio_en == 1 and 
        (tso_en == 1 or csum_en == 1) and
        eth_flag in [0, 1] and
        ip_option == 0 and
        len32K_flag in [2, 3] and
        (
        (
            virtio_gso_type in [1, 4] and
            (
                (virtio_gso_type == 1 and ip_version == 4) or
                (virtio_gso_type == 4 and ip_version == 6)
            ) and
            transport_protocol == "tcp"
        ) or
        (
            virtio_flags == 1 and
            transport_protocol in ["tcp", "udp"] and
            ip_version in [4, 6] and
            (
                (ip_version == 4 and virtio_gso_type != 1) or
                (ip_version == 6 and virtio_gso_type != 4)
            )
        )
        )
        ):
        # Extract Virtio header (12 bytes) and network data
        #dut_reversed_bytes = dut_data[:12]
        #ref_reversed_bytes = ref_data[:12]
        #dut_original_bytes = dut_reversed_bytes[::-1]
        #ref_original_bytes = ref_reversed_bytes[::-1]
        #dut_original_virtio_hdr = VirtioHeader(dut_original_bytes)
        #ref_original_virtio_hdr = VirtioHeader(ref_original_bytes)

        dut_network_data = dut_data
        ref_network_data = ref_data
        
        dut_pkt = Ether(dut_network_data)
        ref_pkt = Ether(ref_network_data)

        #comparing the virtio hdr
        #virtio_header_diff = compare_virtio_headers(dut_original_virtio_hdr, ref_original_virtio_hdr)
        #if virtio_header_diff:
        #    errors.append(f"{param_info}\nVirtio header difference: {virtio_header_diff}")

        #comparing the eth hdr
        eth_header_diff = compare_ether_layers(dut_pkt, ref_pkt, eth_flag)
        if eth_header_diff:
            errors.append(f"{param_info}\neth header difference: {eth_header_diff}")

        #comparing the ip hdr
        ip_header_diff = compare_ip_layers(dut_pkt, ref_pkt, ip_version)
        if ip_header_diff:
            errors.append(f"{param_info}\nip header difference: {ip_header_diff}")
        
        #comparing the trans hdr
        trans_header_diff = compare_transport_layers(dut_pkt, ref_pkt, transport_protocol)
        if trans_header_diff:
            errors.append(f"{param_info}\ntrans header difference: {trans_header_diff}")
        
        #comparing the payload hdr
        payload_diff = compare_payloads(dut_pkt, ref_pkt, ip_version)
        if payload_diff:
            errors.append(f"{param_info}\ntrans header difference: {payload_diff}")

        return (False, errors) if errors else (True, [])
    else : #bypass
        chunk_idx, result = compare_data_in_256bit_chunks(dut_data, ref_data)
        error_details = []
        if chunk_idx > 0:
            error_details.append(f"Bypass Mismatch found in chunk {chunk_idx} (256-bit)")
            error_details.append(f"First difference at byte position {result['byte_position']}")
            error_details.append(f"DUT value: {result['dut_value']}, REF value: {result['ref_value']}")
            error_details.append(f"DUT chunk data: {result['dut_chunk_hex']}")
            error_details.append(f"REF chunk data: {result['ref_chunk_hex']}")
        elif chunk_idx == -1:
            error_details.append(f"Bypass Data comparison failed: {result}")
        if error_details:
            errors.append(f"{param_info}\nbypass difference: \n" + "\n".join(error_details))
        else:
            pass
        return (False, errors) if errors else (True, [])

# Auxiliary comparison function
def compare_virtio_headers(dut_hdr, ref_hdr):
    fields = [
        "num_buffers", "csum_offset", "csum_start",
        "gso_size", "hdr_len", "gso_type_ecn",
        "gso_type", "flags_rsv", "flags"
    ]
    
    differences = [
        f"{field} virtio hdr mismatched! dut_hdr is : {getattr(dut_hdr, field)}, ref_hdr is : {getattr(ref_hdr, field)}"
        for field in fields
        if getattr(dut_hdr, field) != getattr(ref_hdr, field)
    ]
    
    # Return differential information or None
    return "\n".join(differences) if differences else None

def compare_ether_layers(dut_pkt, ref_pkt, eth_flag):
    differences = []
    

    dut_eth = dut_pkt.getlayer(Ether)
    ref_eth = ref_pkt.getlayer(Ether)
    
    if dut_eth.src != ref_eth.src:
        differences.append(f"eth src mac mismatched! dut_src is : {dut_eth.src}, ref_src is : {ref_eth.src}")
    
    if dut_eth.dst != ref_eth.dst:
        differences.append(f"eth dst mac mismatched! dut_dst is : {dut_eth.dst}, ref_dst is : {ref_eth.dst}")
    
    if dut_eth.type != ref_eth.type:
        differences.append(f"eth ether type mismatched! dut_type is : 0x{dut_eth.type:x}, ref_type is : 0x{ref_eth.type:x}")
    
    if eth_flag == 1:
        if Dot1Q not in dut_pkt or Dot1Q not in ref_pkt:
            differences.append("VLAN layer exists mismatch!")
        else:
            dut_vlan = dut_pkt.getlayer(Dot1Q)
            ref_vlan = ref_pkt.getlayer(Dot1Q)

            if dut_vlan.vlan != ref_vlan.vlan:
                differences.append(f"vlan id mismatched! dut_vlan is : {dut_vlan.vlan}, ref_vlan is : {ref_vlan.vlan}")

            if dut_vlan.dei != ref_vlan.dei:
                differences.append(f"cfi dei mismatched! dut_vlan is : {dut_vlan.dei}, ref_vlan is : {ref_vlan.dei}")

            if dut_vlan.prio != ref_vlan.prio:
                differences.append(f"vlan priority mismatched! dut_prio is : {dut_vlan.prio}, ref_prio is : {ref_vlan.prio}")

            if dut_vlan.type != ref_vlan.type:
                differences.append(f"vlan type mismatched! dut_vlan_type is : 0x{dut_vlan.type:x}, ref_vlan_type is : 0x{ref_vlan.type:x}")
    
    # Return differential information or None
    return "\n".join(differences) if differences else None

def compare_ip_layers(dut_pkt, ref_pkt, ip_version):
    differences = []
    
    if ip_version == 4:
        dut_ip = dut_pkt.getlayer(IP)
        ref_ip = ref_pkt.getlayer(IP)
    else:  # IPv6
        dut_ip = dut_pkt.getlayer(IPv6)
        ref_ip = ref_pkt.getlayer(IPv6)
    if dut_ip.version != ref_ip.version:
        differences.append(f"ip version mismatched! dut_version is : {dut_ip.version}, ref_version is : {ref_ip.version}")
    
    if dut_ip.src != ref_ip.src:
        differences.append(f"ip src addr mismatched! dut_src is : {dut_ip.src}, ref_src is : {ref_ip.src}")
    
    if dut_ip.dst != ref_ip.dst:
        differences.append(f"ip dst addr mismatched! dut_dst is : {dut_ip.dst}, ref_dst is : {ref_ip.dst}")
    
    # IPv4
    if ip_version == 4:
        if dut_ip.ihl != ref_ip.ihl:
            differences.append(f"ip header length mismatched! dut_ihl is : {dut_ip.ihl}, ref_ihl is : {ref_ip.ihl}")
        
        if dut_ip.tos != ref_ip.tos:
            differences.append(f"ip tos mismatched! dut_tos is : {dut_ip.tos}, ref_tos is : {ref_ip.tos}")
        
        if dut_ip.len != ref_ip.len:
            differences.append(f"ip length mismatched! dut_len is : {dut_ip.len}, ref_len is : {ref_ip.len}")
    
        if dut_ip.id != ref_ip.id:
            differences.append(f"ip id mismatched! dut_id is : {dut_ip.id}, ref_id is : {ref_ip.id}")
        
        if dut_ip.flags != ref_ip.flags:
            differences.append(f"ip flags mismatched! dut_flags is : {dut_ip.flags}, ref_flags is : {ref_ip.flags}")
        
        if dut_ip.frag != ref_ip.frag:
            differences.append(f"ip frag offset mismatched! dut_frag is : {dut_ip.frag}, ref_frag is : {ref_ip.frag}")
        
        if dut_ip.ttl != ref_ip.ttl:
            differences.append(f"ip ttl mismatched! dut_ttl is : {dut_ip.ttl}, ref_ttl is : {ref_ip.ttl}")
        
        if dut_ip.proto != ref_ip.proto:
            differences.append(f"ip protocol mismatched! dut_proto is : {dut_ip.proto}, ref_proto is : {ref_ip.proto}")
        
        if dut_ip.chksum != ref_ip.chksum:
            differences.append(f"ip checksum mismatched! dut_chksum is : {dut_ip.chksum:04x}, ref_chksum is : {ref_ip.chksum:04x}")
    
    # IPv6
    else:
        if dut_ip.tc != ref_ip.tc:
            differences.append(f"ipv6 traffic class mismatched! dut_tc is : {dut_ip.tc}, ref_tc is : {ref_ip.tc}")
        
        if dut_ip.fl != ref_ip.fl:
            differences.append(f"ipv6 flow label mismatched! dut_fl is : {dut_ip.fl}, ref_fl is : {ref_ip.fl}")
        
        if dut_ip.plen != ref_ip.plen:
            differences.append(f"ipv6 payload length mismatched! dut_plen is : {dut_ip.plen}, ref_plen is : {ref_ip.plen}")

        if dut_ip.nh != ref_ip.nh:
            differences.append(f"ipv6 next header mismatched! dut_nh is : {dut_ip.nh}, ref_nh is : {ref_ip.nh}")
        
        if dut_ip.hlim != ref_ip.hlim:
            differences.append(f"ipv6 hop limit mismatched! dut_hlim is : {dut_ip.hlim}, ref_hlim is : {ref_ip.hlim}")
    
    # Return differential information or None
    return "\n".join(differences) if differences else None

def compare_transport_layers(dut_pkt, ref_pkt, transport_protocol):
    differences = []
    
    if transport_protocol.lower() == "tcp":
        dut_trans = dut_pkt.getlayer(TCP)
        ref_trans = ref_pkt.getlayer(TCP)
    elif transport_protocol.lower() == "udp":
        dut_trans = dut_pkt.getlayer(UDP)
        ref_trans = ref_pkt.getlayer(UDP)
    else:
        differences.append(f"unsupported transport protocol: {transport_protocol}")
        return "\n".join(differences) if differences else None
    
    # TCP
    if transport_protocol.lower() == "tcp":
        if dut_trans.sport != ref_trans.sport:
            differences.append(f"tcp src port mismatched! dut_sport is : {dut_trans.sport}, ref_sport is : {ref_trans.sport}")
        
        if dut_trans.dport != ref_trans.dport:
            differences.append(f"tcp dst port mismatched! dut_dport is : {dut_trans.dport}, ref_dport is : {ref_trans.dport}")
        
        if dut_trans.seq != ref_trans.seq:
            differences.append(f"tcp sequence num mismatched! dut_seq is : {dut_trans.seq}, ref_seq is : {ref_trans.seq}")
        
        if dut_trans.ack != ref_trans.ack:
            differences.append(f"tcp ack num mismatched! dut_ack is : {dut_trans.ack}, ref_ack is : {ref_trans.ack}")
        
        if dut_trans.dataofs != ref_trans.dataofs:
            differences.append(f"tcp data offset mismatched! dut_dataofs is : {dut_trans.dataofs}, ref_dataofs is : {ref_trans.dataofs}")
        
        if dut_trans.reserved != ref_trans.reserved:
            differences.append(f"tcp reserved bits mismatched! dut_reserved is : {dut_trans.reserved}, ref_reserved is : {ref_trans.reserved}")
        
        if dut_trans.flags != ref_trans.flags:
            differences.append(f"tcp flags mismatched! dut_flags is : {dut_trans.flags}, ref_flags is : {ref_trans.flags}")
        
        if dut_trans.window != ref_trans.window:
            differences.append(f"tcp window size mismatched! dut_window is : {dut_trans.window}, ref_window is : {ref_trans.window}")

        if dut_trans.chksum != ref_trans.chksum:
            differences.append(f"tcp checksum mismatched! dut_chksum: {dut_trans.chksum:04x}, ref_chksum: {ref_trans.chksum:04x}")
            
        
        if dut_trans.urgptr != ref_trans.urgptr:
            differences.append(f"tcp urgent ptr mismatched! dut_urgptr is : {dut_trans.urgptr}, ref_urgptr is : {ref_trans.urgptr}")
        
        if dut_trans.options != ref_trans.options:
            differences.append("tcp options mismatched!")
    
    # UDP
    elif transport_protocol.lower() == "udp":
        if dut_trans.sport != ref_trans.sport:
            differences.append(f"udp src port mismatched! dut_sport is : {dut_trans.sport}, ref_sport is : {ref_trans.sport}")
        
        if dut_trans.dport != ref_trans.dport:
            differences.append(f"udp dst port mismatched! dut_dport is : {dut_trans.dport}, ref_dport is : {ref_trans.dport}")
        
        if dut_trans.len != ref_trans.len:
            differences.append(f"udp length mismatched! dut_len is : {dut_trans.len}, ref_len is : {ref_trans.len}")
        
        if dut_trans.chksum != ref_trans.chksum:
            differences.append(f"udp checksum mismatched! dut_chksum is : {dut_trans.chksum:04x}, ref_chksum is : {ref_trans.chksum:04x}")
    
    # Return differential information or None
    return "\n".join(differences) if differences else None

def compare_payloads(dut_pkt, ref_pkt, ip_version):
    differences = []
    
    try:
        if ip_version == 4:
            ip_layer = dut_pkt.getlayer(IP)
            ref_ip_layer = ref_pkt.getlayer(IP)
            
            proto = ip_layer.proto
            ref_proto = ref_ip_layer.proto
        else:  # IPv6
            ip_layer = dut_pkt.getlayer(IPv6)
            ref_ip_layer = ref_pkt.getlayer(IPv6)
            
            proto = ip_layer.nh
            ref_proto = ref_ip_layer.nh
        if proto == 6:  # TCP
            dut_trans = ip_layer.getlayer(TCP)
            ref_trans = ref_ip_layer.getlayer(TCP)
        elif proto == 17:  # UDP
            dut_trans = ip_layer.getlayer(UDP)
            ref_trans = ref_ip_layer.getlayer(UDP)

        dut_payload = bytes(dut_trans.payload)
        ref_payload = bytes(ref_trans.payload)
        chunk_idx, result= compare_data_in_256bit_chunks(dut_payload, ref_payload)
        if chunk_idx > 0:
            differences.append(f"Payload Mismatch found in chunk {chunk_idx} (256-bit)")
            differences.append(f"First difference at byte position {result['byte_position']}")
            differences.append(f"DUT value: {result['dut_value']}, REF value: {result['ref_value']}")
            differences.append(f"DUT chunk data: {result['dut_chunk_hex']}")
            differences.append(f"REF chunk data: {result['ref_chunk_hex']}")
        elif chunk_idx == -1:
            differences.append(f"Payload Data comparison failed: {result}")
        #dut_hex = " ".join([f"{b:02x}" for b in dut_payload])
        #ref_hex = " ".join([f"{b:02x}" for b in ref_payload])
        #
        #if dut_payload != ref_payload:
        #    differences.append("The payload content does not match!")
        #    differences.append(f"DUT hexadecimal system: {dut_hex}")
        #    differences.append(f"REF hexadecimal system: {ref_hex}")

    except Exception as e:
        differences.append(f"Payload comparison failed: {str(e)}")
    
    # Return differential information or None
    return "\n".join(differences) if differences else None

def compare_data_in_256bit_chunks(dut_data, ref_data):
    if len(dut_data) != len(ref_data):
        return -1, f"Length mismatch: DUT={len(dut_data)}byte, REF={len(ref_data)}byte"
    
    total_bytes = len(dut_data)
    full_chunks = total_bytes // 32  
    remainder = total_bytes % 32  

    for chunk_idx in range(full_chunks + (1 if remainder > 0 else 0)):
        start_idx = chunk_idx * 32
        end_idx = min(start_idx + 32, total_bytes)
        
        dut_chunk = dut_data[start_idx:end_idx]
        ref_chunk = ref_data[start_idx:end_idx]
        
        if dut_chunk != ref_chunk:
            first_diff_byte = next((i for i, (d, r) in enumerate(zip(dut_chunk, ref_chunk)) if d != r), None)
            
            diff_info = {
                "chunk_index": chunk_idx,
                "byte_position": start_idx + first_diff_byte,
                "dut_value": f"0x{dut_chunk[first_diff_byte]:02x}",
                "ref_value": f"0x{ref_chunk[first_diff_byte]:02x}",
                "dut_chunk_hex": " ".join([f"{b:02x}" for b in dut_chunk]),
                "ref_chunk_hex": " ".join([f"{b:02x}" for b in ref_chunk])
            }
            
            return chunk_idx, diff_info
    
    return 0, "All data matches"


def split_packet(packet, ref_virtio_flags,max_size=32768):
    segments = []
    start = 0
    length = len(packet)
    
    while start < length:
        end = min(start + max_size, length) 
        is_last = (end >= length)
        flag = 2 if start == 0 else 1 if is_last else 0 #sop = 2,eop=1,no sop.eop = 0
        if start == 0:
            segments.append((packet[12:end], ref_virtio_flags, flag))
        else :
            segments.append((packet[start:end], ref_virtio_flags, flag))
        start = end
    return segments