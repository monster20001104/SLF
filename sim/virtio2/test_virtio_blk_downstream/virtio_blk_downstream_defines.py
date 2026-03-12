#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : virtio_blk_downstream_defines.py
#* 作者名称 : matao
#* 创建日期 : 2025/07/09
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   07/09       matao       初始化版本
#******************************************************************************/
import logging
from collections import Counter
from typing import List, NamedTuple, Union
from scapy.all import Packet, BitField, PacketField, FlagsField
from enum import Enum, unique

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Event, First, Timer
from backpressure_bus import define_backpressure
from stream_bus import define_stream
from ram_tbl import define_ram_tbl

import sys
sys.path.append('..')

NotifySchBus, NotifySchTransaction, NotifySchSource, NotifySchSink, NotifySchMonitor = define_stream("notify_sch_master",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)    
QueryReqBus, QueryReqTransaction, QueryReqSource, QueryReqSink, QueryReqMonitor = define_stream("Query_master",
    signals=["uid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)    
QueryRspBus, QueryRspTransaction, QueryRspSource, QueryRspSink, QueryRspMonitor = define_stream("Query_slave",
    signals=["ok"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)  
UpDateReqBus, UpDateReqTransaction, UpDateReqSource, UpDateReqSink, UpDateReqMonitor = define_stream("UpDateReq",
    signals=["uid", "len", "pkt_num"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)
AllocSlotReqBus, AllocSlotReqTransaction, AllocSlotReqSource, AllocSlotReqSink, AllocSlotReqMonitor = define_stream("AllocSlot_master",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)    
AllocSlotRspBus, AllocSlotRspTransaction, AllocSlotRspSource, AllocSlotRspSink, AllocSlotRspMonitor = define_stream("AllocSlot_slave",
    signals=["dat", ], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)   
BlkDescBus, BlkDescTransaction, BlkDescSource, BlkDescSink, BlkDescMonitor = define_stream("BlkDesc",
    signals=["dat", "sbd", "sop", "eop"],
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths={"sop": 1, "eop": 1}
)

QosInfoRdReqBus, QosInfoRdRspBus, _, _, QosInfoRdRspTransaction, _, _, QosInfoRdTbl = define_ram_tbl("Qos_info_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_qos_enable", "rsp_qos_unit"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

DmaInfoRdReqBus, DmaInfoRdRspBus, _, _, DmaInfoRdRspTransaction, _, _, DmaInfoRdTbl = define_ram_tbl("Dma_info_rd", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_bdf", "rsp_forcedown", "rsp_generation"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

PtrRdReqBus, PtrRdRspBus, PtrWrBus, _, PtrRdRspTransaction, _, _, PtrTbl = define_ram_tbl("Ptr", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    wr_signals=["wr_qid", "wr_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld"
)

FstSegReqBus, FstSegRspBus, FstSegWrBus, FstSegReqTrans, FstSegRspTrans, FstSegWrTrans, FstSegMaster, FstSegTbl = define_ram_tbl("blk_chain_fst_seg",
    rd_req_signals=["rd_req_qid"],
    rd_rsp_signals=["rd_rsp_dat"],
    wr_signals=["wr_qid", "wr_dat"],
    rd_req_vld_signal="rd_req_vld",
    rd_req_rdy_signal=None,
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld",
    wr_rdy_signal=None,
)

ErrInfoBus, ErrInfoTransaction, ErrInfoSource, ErrInfoSink, ErrInfoMonitor = define_stream("blk_ds_err_info",
    signals=["dat", "qid"],
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)

class VirtioVq(Packet):
    name = 'virtio_vq'
    fields_desc = [
        BitField("typ"  ,   0,  2 ),
        BitField("qid"  ,   0,  8 )
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
        return VirtioVq(data.buff)

class VirtioDescSlotRsp(Packet):
    name = 'virtio_desc_slot_rsp'
    fields_desc = [
        BitField("vq_typ"           ,   0,  2 ),
        BitField("vq_id"            ,   0,  8 ),
        BitField("pkt_id"           ,   0,  10),
        BitField("ok"               ,   0,  1 ),
        BitField("local_ring_empty" ,   0,  1 ),
        BitField("avail_ring_empty" ,   0,  1 ),
        BitField("q_stat_doing"     ,   0,  1 ),
        BitField("q_stat_stopping"  ,   0,  1 ),
        BitField("desc_engine_limit",   0,  1 ),
        BitField("err_info"         ,   0,  8 )
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
        return VirtioDescSlotRsp(data.to_bytes(VirtioDescSlotRsp.width//8, byteorder='big'))

class VirtioDescRspSbd(Packet):
    name = 'virtio_desc_rsp_sbd'
    fields_desc = [
        BitField("vq_typ"           ,   0,  2),
        BitField("vq_id"            ,   0,  8),
        BitField("dev_id"           ,   0,  10),
        BitField("pkt_id"           ,   0,  10),
        BitField("total_buf_length" ,   0,  18),
        BitField("valid_desc_cnt"   ,   0,  16),
        BitField("ring_id"          ,   0,  16),
        BitField("avail_idx"        ,   0,  16),
        BitField("forced_shutdown"  ,   0,  1 ),
        BitField("err_info"         ,   0,  8 )
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        raw_bytes = self.build()
        reversed_bytes = raw_bytes
        return int.from_bytes(reversed_bytes, byteorder="big")

    def unpack(self, data):
        return VirtioDescRspSbd(data.to_bytes(VirtioDescRspSbd.width//8, byteorder='big'))

class VirtioFlags(Packet):
    name = 'virtio_flags'
    fields_desc = [
        BitField("flags_rsv",        0, 13),
        BitField("flags_indirect",   0,  1),
        BitField("flags_write",      0,  1),
        BitField("flags_next",       0,  1)
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
        return VirtioFlags(data.to_bytes(VirtioFlags.width//8, byteorder='big'))


class VirtioDesc(Packet):
    name = 'virtio_desc'
    fields_desc = [
        BitField("next"             ,   0,  16),
        BitField("flags_rsv"        ,   0,  13),
        BitField("flags_indirect"   ,   0,  1 ),
        BitField("flags_write"      ,   0,  1 ),
        BitField("flags_next"       ,   0,  1 ),
        BitField("len"              ,   0,  32),
        BitField("addr"             ,   0,  64)
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
        return VirtioDesc(data.to_bytes(VirtioDesc.width//8, byteorder='big'))

class BufferHeader(Packet):
    name = 'buffer_header'
    fields_desc = [
        BitField("rsv1"             ,   0,  320),
        BitField("magic_num"        ,   0,  16 ),
        BitField("rsv0"             ,   0,  8  ),
        BitField("rsv2"             ,   0,  8  ),
        BitField("length"           ,   0,  32 ),
        BitField("addr"             ,   0,  64 ),
        BitField("virtio_flags"     ,   0,  16 ),
        BitField("desc_index"       ,   0,  16 ),
        BitField("rsv3"             ,   0,  8  ),
        BitField("vq_gen"           ,   0,  8  ),
        BitField("vq_gid"           ,   0,  16 )
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
        return BufferHeader(data.to_bytes(BufferHeader.width//8, byteorder='big'))

class VirtioQidType(Enum):
    VirtioNetRx = 0
    VirtioNetTx = 1
    VirtioBlk   = 2

DEFAULT_MAX_SEQ = 1000

class Cfg(NamedTuple):
    max_seq           : int
    desc_chain_limit  : int
    desc_num_base     : int
    desc_num_limit    : int
    dma_len_base      : int
    dma_len_limit     : int

max_desc_cnt_cfg = Cfg(
            max_seq            = DEFAULT_MAX_SEQ,
            desc_chain_limit   = 3,
            desc_num_base      = 16,
            desc_num_limit     = 45,
            dma_len_base       = 1,
            dma_len_limit      = 4096,

)

min_desc_cnt_cfg = Cfg(
            max_seq            = DEFAULT_MAX_SEQ,
            desc_chain_limit   = 4,
            desc_num_base      = 1,
            desc_num_limit     = 1,
            dma_len_base       = 1,
            dma_len_limit      = 4096
)

mix_desc_cnt_cfg = Cfg(
            max_seq            = DEFAULT_MAX_SEQ,
            desc_chain_limit   = 2,
            desc_num_base      = 1,
            desc_num_limit     = 32,
            dma_len_base       = 1,
            dma_len_limit      = 4096
)

max_dma_len_cfg = Cfg(
            max_seq            = DEFAULT_MAX_SEQ,
            desc_chain_limit   = 2,
            desc_num_base      = 1,
            desc_num_limit     = 3, # update total_len 位宽18bit，64K描述符不能超过3个
            dma_len_base       = 65536,
            dma_len_limit      = 65536
)

min_dma_len_cfg = Cfg(
            max_seq            = DEFAULT_MAX_SEQ,
            desc_chain_limit   = 3,
            desc_num_base      = 1,
            desc_num_limit     = 16,
            dma_len_base       = 1,
            dma_len_limit      = 1
)

mix_dma_len_cfg = Cfg(
            max_seq            = DEFAULT_MAX_SEQ,
            desc_chain_limit   = 1,
            desc_num_base      = 1,
            desc_num_limit     = 3,
            dma_len_base       = 1,
            dma_len_limit      = 65536
)
