#!/usr/bin/env python3
################################################################################
#  文件名称 : defines.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/01/09
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  01/09     Joe Jiang   初始化版本
################################################################################
import sys
sys.path.append('../common')
from stream_bus import define_stream
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union
from address_space import Pool, AddressSpace, MemoryRegion

Qid2BidRdReqBus, Qid2BidRdRspBus, _, _, Qid2BidRdRspTransaction, _, _, Qid2BidRdTbl = define_ram_tbl("qid2bid", 
    rd_req_signals=["req_idx"], 
    rd_rsp_signals=["rsp_dat"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

DropModeRdReqBus, DropModeRdRspBus, _, _, DropModeRdRspTransaction, _, _, DropModeRdTbl = define_ram_tbl("drop_mode", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_dat"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

SegmentSizeRdReqBus, SegmentSizeRdRspBus, _, _, SegmentSizeRdRspTransaction, _, _, SegmentSizeRdTbl = define_ram_tbl("segment_size", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_dat"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

RingCiRdReqBus, RingCiRdRspBus, RingCiWrBus, _, RingCiRdRspTransaction, _, _, RingCiTbl = define_ram_tbl("ring_ci", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    wr_signals=["wr_qid", "wr_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld"
)

RingInfoRdReqBus, RingInfoRdRspBus, _, _, RingInfoRdRspTransaction, _, _, RingInfoRdTbl = define_ram_tbl("ring_info_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_base_addr", "rsp_qdepth"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

RdNdescReqBus, _, _, RdNdescReqSink, _ = define_stream("rd_ndesc_req",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

RdNdescRspBus, _, RdNdescRspSource, _, _ = define_stream("rd_ndesc_rsp",
    signals=["sbd", "sop", "eop", "dat", "tag"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

class BeqRdNdescReq(Packet):
    name = 'beq_rd_ndesc_req'
    fields_desc = [
        BitField("qid"          ,   0,   6),
        BitField("pkt_length"   ,   0,  18),
        BitField("typ"          ,   0,   4),
        BitField("seg"          ,   0,   5)
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
        assert type(data) == cocotb.binary.BinaryValue
        return cls(data.buff)

class BeqRdNdescRsp(Packet):
    name = 'beq_rd_ndesc_rsp'
    fields_desc = [
        BitField("q_disable"    ,   0,  1),
        BitField("qid"          ,   0,  6),
        BitField("ok"           ,   0,  1),
        BitField("fatal"        ,   0,  1),
        BitField("typ"          ,   0,  4),
        BitField("maybe_last"   ,   0,  1)
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
        assert type(data) == cocotb.binary.BinaryValue
        return cls(data.buff)


class BeqAvailDesc(Packet):
    name = 'beq_avail_desc'
    fields_desc = [
        BitField("err",             0,  1),
        BitField("err_code",        0,  4),
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
        assert type(data) == cocotb.binary.BinaryValue
        return cls(data.buff)


class BeqUsedDesc(Packet):
    name = 'beq_used_desc'
    fields_desc = [
        BitField("err",             0,  1),
        BitField("err_code",        0,  4),
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