#!/usr/bin/env python3
################################################################################
#  文件名称 : defines.py
#  作者名称 : cui naiwan
#  创建日期 : 2025/07/08
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/08     cui naiwan   初始化版本
################################################################################\
import sys
sys.path.append('../../common')
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union


BlkupstreamCtxRdReqBus, BlkupstreamCtxRdRspBus, _, _, BlkupstreamCtxRdRspTransaction, _, _, BlkupstreamCtxRdTbl = define_ram_tbl("blk_upstream_ctx", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_forced_shutdown", "rsp_generation", "rsp_dev_id", "rsp_bdf"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

BlkupstreamPtrRdReqBus, BlkupstreamPtrRdRspBus, BlkupstreamPtrWrBus, _, BlkupstreamPtrRdRspTransaction, _, _, BlkupstreamPtrTblIf = define_ram_tbl("blk_upstream_ptr", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    wr_signals=["wr_req_qid", "wr_req_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_req_vld"
)

WrusedinfoBus, _, WrusedinfoSource, WrusedinfoSink, WrusedinfoMonitor = define_stream("wr_used_info",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

class BlkupstreamOrderinfo(Packet):
    name = 'blk_upstream_order_info'
    fields_desc = [
        BitField("qid",             0,  10),
        BitField("dummy",           0,  1),
        BitField("flag",            0,  1),
        BitField("desc_index",      0,  16),
        BitField("used_length",     0,  32),
        BitField("used_idx",        0,  16)
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