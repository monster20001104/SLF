#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_data_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/09/24
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  09/24     Joe Jiang   初始化版本
################################################################################
import sys
import cocotb
from typing import List, NamedTuple, Union
from scapy.all import Packet, BitField
from cocotb.triggers import Event

sys.path.append('..')
from backpressure_bus import define_backpressure
from stream_bus import define_stream
from enum import Enum

class BeqData(NamedTuple):
    qid: int
    data: bytes
    user0: int
    user1: int
    sty: int

class BeqTxqSbd(Packet):
    name = 'beq_txq_sbd'
    fields_desc = [
        BitField("user0",   0,  40),
        BitField("qid",     0,   8),
        BitField("length",  0,  18)
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")
    def unpack(self, data):
        assert type(data) == cocotb.binary.BinaryValue
        return BeqTxqSbd(data.buff)

class BeqRxqSbd(Packet):
    name = 'beq_rxq_sbd'
    fields_desc = [
        BitField("user1",   0,  64),
        BitField("user0",   0,  40),
        BitField("qid",     0,   8),
        BitField("length",  0,  18)
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")
        
    def unpack(self, data):
        assert type(data) == cocotb.binary.BinaryValue
        return BeqRxqSbd(data.buff)

BeqBus, BeqTransaction, BeqSource, BeqSink, BeqMonitor = define_backpressure("BeqBus",
    signals=["data", "sty", "mty", "sop", "eop", "sbd"], 
    optional_signals=None,
    vld_signal = "vld",
    sav_signal = "sav",
    signal_widths={"sop": 1, "eop": 1}
)