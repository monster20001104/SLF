#!/usr/bin/env python3
################################################################################
#  文件名称 : beq_defines.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/02/13
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  02/13     Joe Jiang   初始化版本
################################################################################
import sys
sys.path.append('../common')
from stream_bus import define_stream
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union
from address_space import Pool, AddressSpace, MemoryRegion

class BeqAvailDesc(Packet):
    name = 'beq_avail_desc'
    fields_desc = [
        BitField("err",             0,  1),
        BitField("rsv",             0,  4),
        BitField("used",            0,  1),
        BitField("next",            0,  1),
        BitField("avail",           0,  1),
        BitField("user0",           0,  40),
        BitField("soc_buf_len",     0,  16),
        BitField("soc_buf_addr",    0,  64)
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
    @classmethod
    def unpack(cls, data):
        assert type(data) == bytes
        return cls(data)


class BeqUsedDesc(Packet):
    name = 'beq_used_desc'
    fields_desc = [
        BitField("err",             0,  1),
        BitField("rsv",             0,  4),
        BitField("used",            0,  1),
        BitField("next",            0,  1),
        BitField("avail",           0,  1),
        BitField("user0",           0,  40),
        BitField("soc_buf_len",     0,  16),
        BitField("user1",           0,  64)
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
    @classmethod
    def unpack(cls, data):
        assert type(data) == bytes
        return cls(data)