#!/usr/bin/env python3
################################################################################
#  文件名称 : defines.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/07/16
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/16     Joe Jiang   初始化版本
################################################################################
import sys
import random
import itertools

sys.path.append('../common')
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from address_space import MemoryRegion
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union

class VirtqDesc(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("next",            0,  16),
        BitField("flags_rsv",       0,  13),
        BitField("flags_indirect",  0,   1),
        BitField("flags_write",     0,   1),
        BitField("flags_next",      0,   1),
        BitField("len",             0,  32),
        BitField("addr",            0,  64)
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
        if type(data) == cocotb.binary.BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))

class VirtioVq(Packet):
    name = 'virtio_vq'
    fields_desc = [
        BitField("typ",             0,  2),
        BitField("qid",             0,  8)
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
        if type(data) == cocotb.binary.BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))

class ErrInfo(Packet):
    name = 'err_info'
    fields_desc = [
        BitField("fatal",             0,  1),
        BitField("err_code",          0,  7)
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
        if type(data) == cocotb.binary.BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))

class DescRspSbd(Packet):
    name = 'desc_rsp_sbd'
    fields_desc = [
        BitField("vq",                  0,  10),
        BitField("dev_id",              0,  10),
        BitField("pkt_id",              0,  10),
        BitField("total_buf_length",    0,  18),
        BitField("valid_desc_cnt",      0,  16),
        BitField("ring_id",             0,  16),
        BitField("avail_idx",           0,  16),
        BitField("forced_shutdown",     0,  1),
        BitField("err_info",            0,  8)
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
        if type(data) == cocotb.binary.BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))

class TestType:
    NETRX = 0x1
    NETTX = 0x0
    BLK = 0x2

def typ_map(typ):
    _typ_map = {TestType.NETTX:"nettx", TestType.NETRX:"netrx", TestType.BLK:"blk"}
    return _typ_map[typ]

class RefResult(NamedTuple):
    pkt_id      : int
    ring_id     : int
    avail_idx   : int
    pkt_len     : int
    descs       : List   
    err         : ErrInfo
    seq_num     : int
    idxs        : List
    indirct_desc_buf: MemoryRegion

class Cfg(NamedTuple):
    min_chain_num           : int
    max_chain_num           : int
    max_indirct_ptr         : int
    max_indirct_desc_size   : int
    max_size                : int
    
def qid2vq(qid, typ):
    return VirtioVq(qid=qid, typ=typ).pack()

def vq2qid(vq):
    vq = VirtioVq().unpack(vq)
    return vq.qid, vq.typ

def vq_str(vq):
    vq = VirtioVq().unpack(vq)
    return f"(qid:{vq.qid},typ:{typ_map(vq.typ)})"

short_chain_cfg = Cfg(
            min_chain_num = 1,
            max_chain_num = 1,
            max_indirct_ptr = 1,
            max_indirct_desc_size = (64*1024/16),
            max_size = 65562 #64KB max TCP payload + 12B virtio-net header + 14B eth header
        ) 

long_chain_cfg = Cfg(
            min_chain_num = 63,
            max_chain_num = 128,
            max_indirct_ptr = 1,
            max_indirct_desc_size = (64*1024/16),
            max_size = 65562 #64KB max TCP payload + 12B virtio-net header + 14B eth header
        ) 

short_mix_chain_cfg = Cfg(
            min_chain_num = 1,
            max_chain_num = 48,
            max_indirct_ptr = 32,
            max_indirct_desc_size = (64*1024/16),
            max_size = 65562 #64KB max TCP payload + 12B virtio-net header + 14B eth header
        ) 

mix_chain_cfg = Cfg(
            min_chain_num = 1,
            max_chain_num = 128,
            max_indirct_ptr = 128,
            max_indirct_desc_size = (64*1024/16),
            max_size = 65562 #64KB max TCP payload + 12B virtio-net header + 14B eth header
        ) 

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

SlotSubmitBus, _, SlotSubmitSource, _, _ = define_stream("slot_submit",
    signals=["vq", "slot_id", "dev_id", "pkt_id", "ring_id", "avail_idx", "err"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

SlotCplBus, _, _, SlotCplSink, _ = define_backpressure("slot_cpl",
    signals=["slot_id", "vq"], 
    optional_signals=None,
    vld_signal = "vld",
    sav_signal = "sav"
)

RdDescReqBus, _, RdDescReqSource, _, _ = define_stream("rd_desc_req",
    signals=["slot_id"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

RdDescRspBus, _, _, RdDescRspSink, _ = define_stream("rd_desc_rsp",
    signals=["sbd", "sop", "eop", "dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

CtxInfoRdReqBus, CtxInfoRdRspBus, _, _, CtxInfoRdRspTransaction, _, _, CtxInfoRdTbl = define_ram_tbl("ctx_info", 
    rd_req_signals=["rd_req_vq"], 
    rd_rsp_signals=["rd_rsp_desc_tbl_addr", "rd_rsp_qdepth", "rd_rsp_forced_shutdown", "rd_rsp_indirct_support", "rd_rsp_max_len", "rd_rsp_bdf"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld"
)

CtxSlotChainRdReqBus, CtxSlotChainRdRspBus, CtxSlotChainWrBus, _, CtxSlotChainRdRspTransaction, CtxSlotChainWrTransaction, _, CtxSlotChainTbl = define_ram_tbl("ctx_slot_chain", 
    rd_req_signals=["rd_req_vq"], 
    rd_rsp_signals=["rd_rsp_head_slot", "rd_rsp_head_slot_vld", "rd_rsp_tail_slot"], 
    wr_signals=["wr_vq", "wr_head_slot", "wr_head_slot_vld", "wr_tail_slot"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld"
)