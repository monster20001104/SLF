#!/usr/bin/env python3
################################################################################
#  文件名称 : defines.py
#  作者名称 : cui naiwan
#  创建日期 : 2025/07/29
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/29     cui naiwan   初始化版本
################################################################################
import sys
sys.path.append('../../common')
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union


UsedIdxMergeInBus, UsedIdxMergeInTransaction, UsedIdxMergeInSource, UsedIdxMergeInSink, UsedIdxMergeInMonitor = define_backpressure("used_idx_merge_in",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    sav_signal = "sav",
    signal_widths=None
)

UsedIdxMergeNetTxBus, _, UsedIdxMergeNetTxSource, UsedIdxMergeNetTxSink, UsedIdxMergeNetTxMonitor = define_stream("used_idx_merge_out_to_net_tx",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

UsedIdxMergeNetRxBus, _, UsedIdxMergeNetRxSource, UsedIdxMergeNetRxSink, UsedIdxMergeNetRxMonitor = define_stream("used_idx_merge_out_to_net_rx",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

UsedIdxMergeOutBus, _, UsedIdxMergeOutSource, UsedIdxMergeOutSink, UsedIdxMergeOutMonitor = define_stream(" used_idx_merge_out",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)


class wr_used_info(Packet):
    name = 'wr_used_info'
    fields_desc = [
        BitField("qid_type"            ,   0,  2),
        BitField("qid"                 ,   0,  8),
        BitField("elem"                ,   0,  64),
        BitField("used_idx"            ,   0,  16),
        BitField("forced_shutdown"     ,   0,  1),
        BitField("fatal"               ,   0,  1),
        BitField("err_info"            ,   0,  7)
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

