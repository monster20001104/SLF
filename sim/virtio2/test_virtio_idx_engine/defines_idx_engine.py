#!/usr/bin/env python3
################################################################################
#  文件名称 : defines_idx_engine.py
#  作者名称 : Yun Feilong
#  创建日期 : 2025/08/08
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/08     Yun Feilong   初始化版本
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

SchReqBus, _, SchReqSource, _, _ = define_stream("sch_req",
    signals=["vq"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

ErrCodeBus, _, _, ErrCodeSink, _ = define_stream("err_code_wr_req",
    signals=["vq","data"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

IdxNotifyBus, _, IdxNotifySource, IdxNotifySink, IdxNotifyMonitor = define_stream("idx_notify",
    signals=["vq"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

CtxInfoRdReqBus, CtxInfoRdRspBus, CtxInfoWrBus, _, CtxInfoRdRspTransaction, CtxInfoWrTransaction, _, CtxInfoRdTbl = define_ram_tbl("idx_engine_ctx", 
    rd_req_signals=["rd_req_vq"], 
    rd_rsp_signals=["rd_rsp_dev_id", "rd_rsp_bdf", "rd_rsp_avail_addr", "rd_rsp_used_addr", "rd_rsp_qdepth", "rd_rsp_avail_idx", "rd_rsp_avail_ui", "rd_rsp_ctrl", "rd_rsp_force_shutdown",  "rd_rsp_no_change", "rd_rsp_no_notify", "rd_rsp_dma_req_num", "rd_rsp_dma_rsp_num"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld",
    wr_signals=["wr_vq", "wr_avail_idx", "wr_no_notify", "wr_no_change", "wr_dma_req_num", "wr_dma_rsp_num"]
)

VIRTQ_USED_F_NO_NOTIFY = 1

class ERR_CODE  :
    VIRTIO_ERR_CODE_NONE                                        = 0x00
    VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR                            = 0x71
    VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX                         = 0x72

class TestType:
    NETRX = 0x1
    NETTX = 0x0
    BLK = 0x2

class q_status_type_t:
    idle        = 1
    starting    = 2
    doing       = 4
    stopping    = 8

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

def err_code_str(err_code):
    _err_code_map = {ERR_CODE.VIRTIO_ERR_CODE_NONE:"None", ERR_CODE.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR:"pcie_err", ERR_CODE.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX:"invalid_idx"}
    return _err_code_map[err_code]

def q_stat_str(status):
    _status_map = {q_status_type_t.idle:"idle", q_status_type_t.starting:"starting", q_status_type_t.doing:"doing", q_status_type_t.stopping:"stopping"}
    return _status_map[status]

def typ_map(typ):
    _typ_map = {TestType.NETTX:"nettx", TestType.NETRX:"netrx", TestType.BLK:"blk"}
    return _typ_map[typ]

def raw2vq(dat):
    vq = VirtioVq().unpack(dat)
    return qid2vq(vq.qid, vq.typ)

def qid2vq(qid, typ):
    return VirtioVq(qid=qid, typ=typ).pack()

def vq2qid(vq):
    vq = VirtioVq().unpack(vq)
    return vq.qid, vq.typ

def vq_str(vq):
    vq = VirtioVq().unpack(vq)
    return f"(qid:{vq.qid},typ:{typ_map(vq.typ)})"

def gen_q_list(q_num):
    return random.sample(range(0, 255), q_num)


class Cfg(NamedTuple):
    q_num                   : int
    type_list               : List
    max_seq                 : int
    qsz_width_list          : List
    life_cycle_en           : bool
    force_shutdown_en       : bool
    fault_injection_en      : bool
    fault_list              : List

smoke_cfg = Cfg(
    q_num               = 8,
    type_list           = [TestType.NETRX, TestType.NETTX, TestType.BLK],
    max_seq             = 1000,
    qsz_width_list      = [8, 8, 9, 9, 10, 13],
    life_cycle_en       = False,
    force_shutdown_en   = False,
    fault_injection_en  = False,
    fault_list          = []
)

life_cycle_cfg = Cfg(
    q_num               = 2,
    type_list           = [TestType.NETRX, TestType.NETTX, TestType.BLK],
    max_seq             = 1000,
    qsz_width_list      = [8, 8, 9, 9, 10, 13],
    life_cycle_en       = True,
    force_shutdown_en   = False,
    fault_injection_en  = False,
    fault_list          = []
)

force_shutdown_cfg = Cfg(
    q_num               = 2,
    type_list           = [TestType.NETRX, TestType.NETTX, TestType.BLK],
    max_seq             = 1000,
    qsz_width_list      = [8, 8, 9, 9, 10, 13],
    life_cycle_en       = True,
    force_shutdown_en   = True,
    fault_injection_en  = False,
    fault_list          = []
)

fault_injection_cfg = Cfg(
    q_num               = 8,
    type_list           = [TestType.NETRX, TestType.NETTX, TestType.BLK],
    max_seq             = 100000,
    qsz_width_list      = [8, 8, 9, 9, 10, 13],
    life_cycle_en       = False,
    force_shutdown_en   = False,
    fault_injection_en  = True,
    fault_list          = [ERR_CODE.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR, ERR_CODE.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX]
)