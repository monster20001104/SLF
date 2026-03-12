#!/usr/bin/env python3
################################################################################
#  文件名称 : define_virtio_nettx.py
#  作者名称 : Feilong Yun
#  创建日期 : 2024/12/03
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/03     Feilong Yun   初始化版本
################################################################################\
import sys
sys.path.append('../common')
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union


SchReqBus, _, SchReqSource, SchReqSink, SchReqMonitor = define_stream("sch_req",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NotifyRspBus, _, NotifyRspSource, NotifyRspSink, NotifyRspMonitor = define_stream("notify_rsp",
    signals=["qid","cold","done"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

SlotReqBus, _, SlotReqSource, SlotReqSink, SlotReqMonitor = define_stream("nettx_alloc_slot_req",
    signals=["data","dev_id"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

SlotRspBus, _, SlotRspSource, SlotRspSink, SlotRspMonitor = define_stream("nettx_alloc_slot_rsp",
    signals=["data"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

QosQueryReqBus, _, QosQueryReqSource, QosQueryReqSink, QosQueryReqMonitor = define_stream("qos_query_req",
    signals=["uid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

QosQueryRspBus, _, QosQueryRspSource, QosQueryRspSink, QosQueryRspMonitor = define_stream("qos_query_rsp",
    signals=["data"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NettxDescBus, _, NettxDescSource, NettxDescSink, NettxDescMonitor = define_stream("nettx_desc_rsp",
    signals=["sop","eop","sbd","data"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)


QosUpdataBus, _, QosUpdataSource, QosUpdataSink, QosUpdataMonitor = define_stream("qos_update",
    signals=["uid","len","pkt_num"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)



UsedInfoBus, _, UsedInfoSource, UsedInfoSink, UsedInfoMonitor = define_stream("used_info",
    signals=["data"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)


Net2TsoBus, _, Net2TsoSource, Net2TsoSink, Net2TsoMonitor = define_backpressure("net2tso", 
    signals=["data","sop","eop","sty","mty","qid","err","len","gen","tso_en","csum_en"], 
    optional_signals=None,
    vld_signal = "vld",
    sav_signal = "sav"
)

SlotCtxReqBus, SlotCtxRspBus, _,_, SlotCtxRspTransaction,_,_, SlotCtxRspRdTbl = define_ram_tbl("slot_ctrl_ctx_info_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_dev_id","rsp_qos_unit","rsp_qos_enable"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)


RdDataCtxReqBus, RdDataCtxRspBus, _,_, RdDataCtxRspTransaction,_,_, RdDataCtxRspRdTbl = define_ram_tbl("rd_data_ctx_info_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_bdf","rsp_qos_unit","rsp_qos_enable","rsp_forced_shutdown","rsp_tso_en","rsp_csum_en","rsp_gen"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)


class virtio_desc_eng_slot_rsp(Packet):
    name = 'slot_rsp'
    fields_desc = [
        BitField("qid",               0,  10),
        BitField("pkt_id",            0,  10),
        BitField("ok",                0,  1),
        BitField("local_ring_empty",  0,  1),
        BitField("avail_ring_empty",  0,  1),
        BitField("q_stat_doing",      0,  1),
        BitField("q_stat_stopping",   0,  1),
        BitField("desc_engine_limit", 0,  1),
        BitField("err_info",          0,  8),
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

class virtio_desc(Packet):
    name = 'desc'
    fields_desc = [
        BitField("next_index",    0,  16),
        BitField("flag_rsv",      0,  13),
        BitField("flag_indirect", 0,  1),
        BitField("flag_write",    0,  1),
        BitField("flag_next",     0,  1),
        BitField("len",           0,  32),
        BitField("addr",          0,  64),
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


class virtio_desc_eng_desc_rsp_sbd(Packet):
    name = 'rsp_sbd'
    fields_desc = [
        BitField("qid",               0,  10),
        BitField("dev_id",           0,  10),
        BitField("pkt_id",           0,  10),
        BitField("total_buf_length", 0,  18),
        BitField("valid_desc_cnt",   0,  16),
        BitField("ring_id",          0,  16),
        BitField("avail_idx",        0,  16),
        BitField("forced_shutdown",  0,  1),
        BitField("err_info",         0,  8),
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

class used_info_pack(Packet):
    name = 'used'
    fields_desc = [
        BitField("qid",              0,  10),
        BitField("len",              0,  32),
        BitField("id",               0,  32),
        BitField("used_idx",         0,  16),
        BitField("force_down",       0,  1),
        BitField("err_info",         0,  8),

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
