# -*- coding: utf-8 -*-
################################################################################
#  文件名称 : define_virtio_rx_buf.py
#  作者名称 : lch
#  创建日期 : 2025/07/09
#  功能描述 :
#
#  修改记录 :
#
#  版本号  日期       修改人       修改内容
#  v1.0  07/09       LCH         初始化版本
################################################################################\

import random

# from backpressure_bus import define_backpressure

# from ctx import define_ctx
# from scapy.all import Packet, BitField
# import cocotb
from ram_tbl import define_ram_tbl
from stream_bus import define_stream

# import inspect
# print(inspect.getfile(SCTP))

from scapy.packet import Raw
from scapy.volatile import RandMAC, RandIP, RandIP6, RandShort, RandString
from scapy.layers.inet import TCP, UDP, IP, ICMP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import Dot1Q, Ether, ARP, STP
from scapy.layers.sctp import SCTP

from cocotb.binary import BinaryValue
from scapy.all import Packet, BitField
from generate_eth_pkg import *

(
    DropInfoReqBus,
    DropInfoRspBus,
    DropInfoWrBus,
    DropInfoReqTrans,
    DropInfoRspTrans,
    DropInfoWrTrans,
    DropInfoMaster,
    DropInfoSlaver,
) = define_ram_tbl(
    "drop_info",
    rd_req_signals=["req_qid"],
    rd_rsp_signals=[
        "rsp_generation",
        "rsp_qos_unit",
        "rsp_qos_enable",
    ],
    wr_signals=None,
    rd_req_vld_signal="req_vld",
    rd_req_rdy_signal="req_rdy",
    rd_rsp_vld_signal="rsp_vld",
    wr_vld_signal=None,
    wr_rdy_signal=None,
)

QosReqBus, QosReqTrans, QosReqMaster, QosReqSlaver, QosReqMoniter = define_stream(
    "qos_query_req",
    signals=["uid"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

QosRspBus, QosRspTrans, QosRspMaster, QosRspSlaver, QosRspMoniter = define_stream(
    "qos_query_rsp",
    signals=["ok"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)
QosUpBus, QosUpTrans, QosUpMaster, QosUpSlaver, QosUpMoniter = define_stream(
    "qos_update",
    signals=["uid", "len", "pkt_num"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)
(
    PerQueReqBus,
    PerQueRspBus,
    PerQueWrBus,
    PerQueReqTrans,
    PerQueRspTrans,
    PerQueWrTrans,
    PerQueMaster,
    PerQueSlaver,
) = define_ram_tbl(
    "req_idx_per_queue_rd",
    rd_req_signals=["req_qid"],
    rd_rsp_signals=[
        "rsp_dev_id",
        "rsp_idx_limit_per_queue",
    ],
    wr_signals=None,
    rd_req_vld_signal="req_vld",
    rd_req_rdy_signal=None,
    rd_rsp_vld_signal="rsp_vld",
    wr_vld_signal=None,
    wr_rdy_signal=None,
)

(
    PerDevReqBus,
    PerDevRspBus,
    PerDevWrBus,
    PerDevReqTrans,
    PerDevRspTrans,
    PerDevWrTrans,
    PerDevMaster,
    PerDevSlaver,
) = define_ram_tbl(
    "req_idx_per_dev_rd",
    rd_req_signals=["req_dev_id"],
    rd_rsp_signals=[
        "rsp_idx_limit_per_dev",
    ],
    wr_signals=None,
    rd_req_vld_signal="req_vld",
    rd_req_rdy_signal=None,
    rd_rsp_vld_signal="rsp_vld",
    wr_vld_signal=None,
    wr_rdy_signal=None,
)

InfoOutBus, InfoOutTrans, InfoOutMaster, InfoOutSlaver, InfoOutMoniter = define_stream(
    "info_out",
    signals=[
        "data_pkt_id",
        "data_vq_gid",
    ],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

DataReqBus, DataReqTrans, DataReqMaster, DataReqSlaver, DataReqMoniter = define_stream(
    "rd_data_req",
    signals=[
        "data_pkt_id",
        "data_vq_gid",
        "data_vq_typ",
        "data_drop",
    ],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

DataRspBus, DataRspTrans, DataRspMaster, DataRspSlaver, DataRspMoniter = define_stream(
    "rd_data_rsp",
    signals=[
        "data",
        "sty",
        "mty",
        "sop",
        "eop",
        "sbd",
    ],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)


class BaseBitField(Packet):
    name = "base_bit_field"
    fields_desc = []

    def pack(self, byteorder="big"):
        return int.from_bytes(self.build(), byteorder=byteorder)

    def unpack(self, data, byteorder="big"):
        if isinstance(data, BinaryValue):
            return self.__class__(data.buff)
        elif isinstance(data, int):
            total_bits = sum(f.size for f in self.fields_desc)
            total_bytes = (total_bits + 7) // 8
            return self.__class__(data.to_bytes(total_bytes, byteorder))

    def compare(self, other):
        if not isinstance(other, self.__class__):
            return False

        for field in self.fields_desc:
            if getattr(self, field.name) != getattr(other, field.name):
                print(getattr(self, field.name), getattr(other, field.name))
                return False
        return True

    def dis(self):
        print(f"Packet {self.name} fields:")
        for field in self.fields_desc:
            value = getattr(self, field.name)
            print(f"  {field.name:10}: {value} (bits: {field.size})")


class DataRspSbd(BaseBitField):
    name = "data_rsp_sbd"
    fields_desc = [
        BitField("vq_typ", 0, 2),
        BitField("vq_qid", 0, 8),
        BitField("length", 0, 18),
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size


def generate_beq2net_pkt(cfg):
    info = Config()
    _, eth_info, eth_pkt = generate_eth_pkt(cfg.eth_cfg)
    info.eth_info = eth_info
    return info, eth_pkt


class CtxRam:
    def __init__(self, size=1024):
        self.memory = [0] * size
        self.size = size

    def read(self, addr):
        if isinstance(addr, BinaryValue):
            addr = addr.value
        if 0 <= addr < self.size:
            return self.memory[addr]
        else:
            raise IndexError("内存地址越界")

    def write(self, addr, value):
        if isinstance(addr, BinaryValue):
            addr = addr.value
        if isinstance(value, BinaryValue):
            value = value.value
        if 0 <= addr < self.size:
            self.memory[addr] = value
        else:
            raise IndexError("内存地址越界")

    def dump(self, start=0, end=None):
        end = end if end else self.size
        return self.memory[start:end]


def randbit(y):
    assert y >= 0
    return random.randint(0, 2**y - 1)


def print_tree(dictionary, level=0):
    for key, value in dictionary.items():
        key_str = f"{key}:".ljust(15)  # 固定8位宽度左对齐
        if isinstance(value, dict):
            print(" " * level * 4 + key_str)
            print_tree(value, level + 1)
        else:
            print(" " * level * 4 + f"{key_str} {value}")
    print()
