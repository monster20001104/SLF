#!/usr/bin/env python3
################################################################################
#  文件名称 : defines.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/08/08
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/08     Joe Jiang   初始化版本
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



class TestType:
    NETRX = 0x1
    NETTX = 0x0
    BLK = 0x2

class q_status_type_t:
    idle        = 1
    starting    = 2
    doing       = 4
    stopping    = 8

def q_stat_str(status):
    _status_map = {q_status_type_t.idle:"idle", q_status_type_t.starting:"starting", q_status_type_t.doing:"doing", q_status_type_t.stopping:"stopping"}
    return _status_map[status]

def typ_map(typ):
    _typ_map = {TestType.NETTX:"nettx", TestType.NETRX:"netrx", TestType.BLK:"blk"}
    return _typ_map[typ]

def qid2vq(qid, typ):
    return VirtioVq(qid=qid, typ=typ).pack()

def vq2qid(vq):
    vq = VirtioVq().unpack(vq)
    return vq.qid, vq.typ

def vq_str(vq):
    vq = VirtioVq().unpack(vq)
    return f"(qid:{vq.qid},typ:{typ_map(vq.typ)})"


class RefResult(NamedTuple):
    ring_id     : int
    avail_idx   : int
    err         : ErrInfo
    seq_num     : int

SchReqBus, _, SchReqSource, _, _ = define_stream("sch_req",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

AvailIdRdReqBus, AvailIdRdRspBus, _, _, AvailIdRdRspTransaction, _, _, AvailIdRdTbl = define_ram_tbl("avail_addr", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_data"], 
    rd_req_vld_signal="rd_req_vld",
    rd_req_rdy_signal="rd_req_rdy",
    rd_rsp_vld_signal="rd_rsp_vld"
)

_, _, AvailPiWrBus, _, AvailPiTransaction, _, _, AvailPiTbl = define_ram_tbl("avail_pi", 
    wr_signals=["wr_req_qid", "wr_req_data"], 
    wr_vld_signal="wr_req_vld"
)

_, _, AvailUiWrBus, _, AvailUiTransaction, _, _, AvailUiTbl = define_ram_tbl("avail_ui", 
    wr_signals=["wr_req_qid", "wr_req_data"], 
    wr_vld_signal="wr_req_vld"
)

NettxNotifyReqBus, _, _, NettxNotifyReqSink, _ = define_stream("nettx_notify_req",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

BlkNotifyReqBus, _, _, BlkNotifyReqSink, _ = define_stream("blk_notify_req",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

DmaCtxInfoRdReqBus, DmaCtxInfoRdRspBus, _, _, DmaCtxInfoRdRspTransaction, _, _, DmaCtxInfoRdTbl = define_ram_tbl("dma_ctx_info", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_force_shutdown", "rd_rsp_ctrl", "rd_rsp_bdf", "rd_rsp_qdepth", "rd_rsp_avail_idx", "rd_rsp_avail_ui", "rd_rsp_avail_ci"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld"
)

NetrxAvailIdReqBus, _, NetrxAvailIdReqSource, _, _ = define_stream("netrx_avail_id_req",
    signals=["data", "nid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NetrxAvailIdRspBus, _, _, NetrxAvailIdRspSink, _ = define_stream("netrx_avail_id_rsp",
    signals=["data", "eop"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NettxAvailIdReqBus, _, NettxAvailIdReqSource, _, _ = define_stream("nettx_avail_id_req",
    signals=["data", "nid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

NettxAvailIdRspBus, _, _, NettxAvailIdRspSink, _ = define_stream("nettx_avail_id_rsp",
    signals=["data", "eop"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

BlkAvailIdReqBus, _, BlkAvailIdReqSource, _, _ = define_stream("blk_avail_id_req",
    signals=["data", "nid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

BlkAvailIdRspBus, _, _, BlkAvailIdRspSink, _ = define_stream("blk_avail_id_rsp",
    signals=["data", "eop"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

_, _, AvailCiWrBus, _, AvailCiTransaction, _, _, AvailCiTbl = define_ram_tbl("avail_ci", 
    wr_signals=["wr_req_qid", "wr_req_data"], 
    wr_vld_signal="wr_req_vld"
)

DescEngineCtxInfoRdReqBus, DescEngineCtxInfoRdRspBus, _, _, DescEngineCtxInfoRdRspTransaction, _, _, DescEngineCtxInfoRdTbl = define_ram_tbl("desc_engine_ctx_info", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_force_shutdown", "rd_rsp_ctrl", "rd_rsp_avail_pi", "rd_rsp_avail_idx", "rd_rsp_avail_ui", "rd_rsp_avail_ci"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld"
)


VqPendingChkReqBus, _, VqPendingChkReqSource, _, _ = define_stream("vq_pending_chk_req",
    signals=["vq"], 
    optional_signals=None,
    vld_signal = "vld"
)

VqPendingChkRspBus, _, _, VqPendingChkRspSink, _ = define_stream("vq_pending_chk_rsp",
    signals=["busy"], 
    optional_signals=None,
    vld_signal = "vld"
)