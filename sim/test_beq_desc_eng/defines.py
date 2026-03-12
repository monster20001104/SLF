#!/usr/bin/env python3
################################################################################
#  文件名称 : defines.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/12/03
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/03     Joe Jiang   初始化版本
################################################################################\
import sys
sys.path.append('../common')
from stream_bus import define_stream
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union

max_chain_num = 24


class beq_mbuf(NamedTuple):
    addr: int
    len: int
    user0: int

NotifyReqBus, _, NotifyReqSource, _, _ = define_stream("db_notify_req",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NotifyRspBus, _, _, NotifyRspSink, _ = define_stream("db_notify_rsp",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

RxqRdNdescReqBus, _, RxqRdNdescReqSource, _, _ = define_stream("rxq_rd_ndesc_req",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

TxqRdNdescReqBus, _, TxqRdNdescReqSource, _, _ = define_stream("txq_rd_ndesc_req",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

RxqRdNdescRspBus, _, _, RxqRdNdescRspSink, _ = define_stream("rxq_rd_ndesc_rsp",
    signals=["sbd", "sop", "eop", "dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

TxqRdNdescRspBus, _, _, TxqRdNdescRspSink, _ = define_stream("txq_rd_ndesc_rsp",
    signals=["sbd", "sop", "eop", "dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NewChainNotifyBus, _, _, NewChainNotifySink, _ = define_stream("new_chain_notify",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)


RingInfoRdReqBus, RingInfoRdRspBus, _, _, RingInfoRdRspTransaction, _, _, RingInfoRdTbl = define_ram_tbl("ring_info_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_base_addr", "rsp_qdepth"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)


TransferTypeRdReqBus, TransferTypeRdRspBus, _, _, TransferTypeRdRspTransaction, _, _, TransferTypeRdTbl = define_ram_tbl("transfer_type_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_dat"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)


RingDbIdxRdReqBus, RingDbIdxRdRspBus, _, _, RingDbIdxRdRspTransaction, _, _, RingDbIdxRdTbl = define_ram_tbl("ring_db_idx_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_dat"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

RingPiRdReqBus, RingPiRdRspBus, RingPiWrBus, _, RingPiRdRspTransaction, _, _, RingPiTbl = define_ram_tbl("ring_pi", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_signals=["wr_qid", "wr_dat"], 
    wr_vld_signal = "wr_vld"
)

RingCiRdReqBus, RingCiRdRspBus, _, _, RingCiRdRspTransaction, _, _, RingCiRdTbl = define_ram_tbl("ring_ci_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_dat"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

QstatusWrBus, _, QstatusWrSource, _, _ = define_stream("qstatus_wr",
    signals=["qid", "dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

QStopReqBus, _, QStopReqSource, _, _ = define_stream("q_stop_req",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

QStopRspBus, _, _, QStopRspSink, _ = define_stream("q_stop_rsp",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = None
)

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
        assert type(data) == cocotb.binary.BinaryValue
        return cls(data.buff)

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
        assert type(data) == cocotb.binary.BinaryValue
        return cls(data.buff)
    @classmethod
    def from_bytes(cls, data):
        assert type(data) == bytes
        return cls(data)


class NotifyRsp(Packet):
    name = 'notify_rsp'
    fields_desc = [
        BitField("qid",   0,  7),
        BitField("done",   0,  1),
        BitField("cold",   0,   1)
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

class ChainNotify(Packet):
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