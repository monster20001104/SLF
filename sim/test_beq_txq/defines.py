#!/usr/bin/env python3
################################################################################
#  文件名称 : defines.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/12
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/12     Joe Jiang   初始化版本
################################################################################
import sys
sys.path.append('../common')
from stream_bus import define_stream
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union
from address_space import Pool, AddressSpace, MemoryRegion


max_chain_num = 24


class beq_mbuf(NamedTuple):
    addr: int
    reg: MemoryRegion
    user0: int

NotifyReqBus, _, NotifyReqSource, _, _ = define_stream("notify_req",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NotifyRspBus, _, _, NotifyRspSink, _ = define_stream("notify_rsp",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
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

RingCiAddrRdReqBus, RingCiAddrRdRspBus, _, _, RingCiAddrRdRspTransaction, _, _, RingCiAddrRdTbl = define_ram_tbl("ring_ci_addr_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_dat"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

ErrInfoRdReqBus, ErrInfoRdRspBus, ErrInfoWrBus, _, ErrInfoRdRspTransaction, _, _, ErrInfoTbl = define_ram_tbl("err_info", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    wr_signals=["wr_qid", "wr_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld"
)

RingCiRdReqBus, RingCiRdRspBus, RingCiWrBus, _, RingCiRdRspTransaction, _, _, RingCiTbl = define_ram_tbl("ring_ci", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    wr_signals=["wr_qid", "wr_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld"
)

'''
RingCiWrBus, _, _, RingCiWrSink, _ = define_stream("ring_ci_wr",
    signals=["qid", "dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None
)
'''

class Notify(Packet):
    name = 'notify_rsp'
    fields_desc = [
        BitField("qid",   0,  6),
        BitField("done",   0,  1),
        BitField("typ",   0,   4)
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

class BeqErrorInfo(Packet):
    name = 'beq_err_info'
    fields_desc = [
        BitField("vld"    ,   0,  1 ),
        BitField("code"   ,   0,  4)
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
        #assert type(data) == cocotb.binary.BinaryValue
        assert type(data) == bytes
        #return cls(data.buff)
        return cls(data)
