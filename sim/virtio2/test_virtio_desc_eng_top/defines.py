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

class AvailIdRspDat(Packet):
    name = 'avail_id_rsp_dat'
    fields_desc = [
        BitField("vq",                  0,  10),
        BitField("id",                  0,  16),
        BitField("local_ring_empty",    0,  1 ),
        BitField("avail_ring_empty",    0,  1 ),
        BitField("q_stat_doing",        0,  1 ),
        BitField("q_stat_stopping",     0,  1 ),
        BitField("avail_idx",           0,  16),
        BitField("err_info",            0,  8 )
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

class SlotRsp(Packet):
    name = 'slot_rsp'
    fields_desc = [
        BitField("vq",                  0,  10),
        BitField("pkt_id",              0,  10),
        BitField("ok",                  0,  1 ),
        BitField("local_ring_empty",    0,  1 ),
        BitField("avail_ring_empty",    0,  1 ),
        BitField("q_stat_doing",        0,  1 ),
        BitField("q_stat_stopping",     0,  1 ),
        BitField("desc_engine_limit",   0,  1 ),
        BitField("err_info",            0,  8 )
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

class DefectType:
    VIRTIO_ERR_CODE_NONE                                        = 0x00
    VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE                           = 0x03
    VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR                          = 0x04
    VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE                 = 0x10
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE            = 0x11
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE       = 0x12
    VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT                  = 0x13
    VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO                  = 0x14
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC                = 0x15
    VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO              = 0x16
    VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE               = 0x17
    VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN                      = 0x18
    VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR                           = 0x19
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE              = 0x1a
    VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE              = 0x1b
class DevCtx:
    def __init__(self, limit=16):
        self._limit = limit
    def set_limit(self, limit):
        self._limit = limit

def typ_map(typ):
    _typ_map = {TestType.NETTX:"nettx", TestType.NETRX:"netrx", TestType.BLK:"blk"}
    return _typ_map[typ]

class RefResult(NamedTuple):
    pkt_id          : int
    ring_id         : int
    avail_idx       : int
    pkt_len         : int
    descs           : List   
    err             : ErrInfo
    seq_num         : int
    idxs            : List
    indirct_desc_buf: MemoryRegion
    
def qid2vq(qid, typ):
    return VirtioVq(qid=qid, typ=typ).pack()

def vq2qid(vq):
    vq = VirtioVq().unpack(vq)
    return vq.qid, vq.typ

def vq_str(vq):
    vq = VirtioVq().unpack(vq)
    return f"(qid:{vq.qid},typ:{typ_map(vq.typ)})"

class Cfg(NamedTuple):
    max_q                   : int
    max_seq                 : int
    min_chain_num           : int
    max_chain_num           : int
    max_indirct_ptr         : int
    max_indirct_desc_size   : int
    qdepth_list             : List
    max_size                : int
    defect_injection        : List
    dma_latency             : int
    forced_shutdown         : bool

short_chain_1q_cfg = Cfg(
            max_q                   = 1,
            max_seq                 = 20000,
            min_chain_num           = 1,
            max_chain_num           = 1,
            max_indirct_ptr         = 1,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [8,13,15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [],
            dma_latency             = 512,
            forced_shutdown         = False
        ) 

short_chain_mq_cfg = Cfg(
            max_q                   = 8,
            max_seq                 = 8000,
            min_chain_num           = 1,
            max_chain_num           = 1,
            max_indirct_ptr         = 1,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [7, 8, 13, 15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [],
            dma_latency             = 512,
            forced_shutdown         = False
        )

long_chain_1q_cfg = Cfg(
            max_q                   = 1,
            max_seq                 = 3000,
            min_chain_num           = 63,
            max_chain_num           = 128,
            max_indirct_ptr         = 1,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [8,13,15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header 
            defect_injection        = [],
            dma_latency             = 300,
            forced_shutdown         = False
        ) 

long_chain_mq_cfg = Cfg(
            max_q                   = 8,
            max_seq                 = 1000,
            min_chain_num           = 63,
            max_chain_num           = 128,
            max_indirct_ptr         = 1,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [8,13,15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [],
            dma_latency             = 256,
            forced_shutdown         = False
        ) 

short_mix_chain_1q_cfg = Cfg(
            max_q                   = 1,
            max_seq                 = 5000,
            min_chain_num           = 1,
            max_chain_num           = 48,
            max_indirct_ptr         = 32,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [8,13,15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [],
            dma_latency             = 384,
            forced_shutdown         = False
        ) 

short_mix_chain_mq_cfg = Cfg(
            max_q                   = 8,
            max_seq                 = 4000,
            min_chain_num           = 1,
            max_chain_num           = 48,
            max_indirct_ptr         = 32,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [8,13,15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [],
            dma_latency             = 384,
            forced_shutdown         = False
        )

mix_chain_1q_cfg = Cfg(
            max_q                   = 1,
            max_seq                 = 1000,
            min_chain_num           = 1,
            max_chain_num           = 128,
            max_indirct_ptr         = 128,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [8,13,15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [],
            dma_latency             = 512,
            forced_shutdown         = False
        ) 

mix_chain_mq_cfg = Cfg(
            max_q                   = 8,
            max_seq                 = 4000,
            min_chain_num           = 1,
            max_chain_num           = 128,
            max_indirct_ptr         = 128,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [8,13,15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [],
            dma_latency             = 256,
            forced_shutdown         = False
        ) 

defect_injection_1q_cfg = Cfg(
            max_q                   = 1,
            max_seq                 = 4000,
            min_chain_num           = 1,
            max_chain_num           = 4,
            max_indirct_ptr         = 2,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [8,13,15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE, DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE, DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT, DefectType.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE, 
                                DefectType.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR, DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO, DefectType.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE, DefectType.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN, DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE],
            dma_latency             = 384,
            forced_shutdown         = False
        )

defect_injection_mq_cfg = Cfg(
            max_q                   = 8,
            max_seq                 = 4000,
            min_chain_num           = 1,
            max_chain_num           = 4,
            max_indirct_ptr         = 2,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [7, 8, 13 ,15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE, DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE, DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT, DefectType.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE, 
                                DefectType.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR, DefectType.VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO, DefectType.VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE, DefectType.VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR, 
                                DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN, DefectType.VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE],
            dma_latency             = 256,
            forced_shutdown         = False
        )

forced_shutdown_1q_cfg = Cfg(
            max_q                   = 1,
            max_seq                 = 8000,
            min_chain_num           = 1,
            max_chain_num           = 6,
            max_indirct_ptr         = 6,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [12],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [],
            dma_latency             = 512,
            forced_shutdown         = True
        ) 

forced_shutdown_mq_cfg = Cfg(
            max_q                   = 8,
            max_seq                 = 3000,
            min_chain_num           = 1,
            max_chain_num           = 20,
            max_indirct_ptr         = 20,
            max_indirct_desc_size   = (64*1024//16),
            qdepth_list             = [12, 15],
            max_size                = 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
            defect_injection        = [],
            dma_latency             = 512,
            forced_shutdown         = True
        ) 

def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)

AllocSlotReqBus, _, AllocSlotReqSource, _, _ = define_stream("alloc_slot_req",
    signals=["vq", "dev_id", "pkt_id"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

AllocSlotRspBus, _, _, AllocSlotRspSink, _ = define_stream("alloc_slot_rsp",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

AvailIdReqBus, _, _, AvailIdReqSink, _ = define_stream("avail_id_req",
    signals=["vq", "nid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

AvailIdRspBus, _, AvailIdRspSource, _, _ = define_stream("avail_id_rsp",
    signals=["dat", "eop"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)


DescRspBus, _, _, DescRspSink, _ = define_stream("desc_rsp",
    signals=["sbd", "sop", "eop", "dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

CtxInfoRdReqBus, CtxInfoRdRspBus, _, _, CtxInfoRdRspTransaction, _, _, CtxInfoRdTbl = define_ram_tbl("ctx_info", 
    rd_req_signals=["rd_req_vq"], 
    rd_rsp_signals=["rd_rsp_desc_tbl_addr", "rd_rsp_qdepth", "rd_rsp_forced_shutdown", "rd_rsp_indirct_support", "rd_rsp_bdf", "rd_rsp_max_len"], 
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

LimitPerQueueRdReqBus, LimitPerQueueRdRspBus, _, _, LimitPerQueueRdRspTransaction, _, _, LimitPerQueueRdTbl = define_ram_tbl("limit_per_queue", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld"
)

LimitPerDevRdReqBus, LimitPerDevRdRspBus, _, _, LimitPerDevRdRspTransaction, _, _, LimitPerDevRdTbl = define_ram_tbl("limit_per_dev", 
    rd_req_signals=["rd_req_dev_id"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld"
)