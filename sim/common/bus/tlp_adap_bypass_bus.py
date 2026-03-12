#!/usr/bin/env python3
################################################################################
#  文件名称 : tlp_adap_bypass_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/09
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/09     Joe Jiang   初始化版本
################################################################################
import sys
import cocotb
from typing import List, NamedTuple, Union
from scapy.all import Packet, BitField
from cocotb.triggers import Event

sys.path.append('..')
from backpressure_bus import define_backpressure
from stream_bus import define_stream
from enum import Enum
from cocotbext.pcie.core.tlp import Tlp, TlpType, CplStatus
from cocotbext.pcie.core.utils import PcieId

class OpCode(Enum):
    MRd         = 1
    MRdLk       = 2
    MWr         = 3
    CplD        = 4
    Cpl         = 5
    CplLk       = 6
    CplDLk      = 7
    IORd        = 8
    IOWr        = 9
    Msg         = 10
    MsgD        = 11
    CFGRd0      = 12
    CFGRd1      = 13
    CFGWr0      = 14
    CFGWr1      = 0
    Unsupported = 15

class ComplStatus(Enum):
    SC  = 0
    UR  = 1
    CRS = 2
    CA  = 4

class TlpBypass():
    def get_first_be_offset(self):
        if self.first_be & 0x7 == 0:
            return 3
        elif self.first_be & 0x3 == 0:
            return 2
        elif self.first_be & 0x1 == 0:
            return 1
        else:
            return 0
    def get_last_be_offset(self):
        if self.byte_length == 4:
            be = self.first_be
        else:
            be = self.last_be
        if be & 0xf == 0x1:
            return 3
        elif be & 0xe == 0x2:
            return 2
        elif be & 0xc == 0x4:
            return 1
        else:
            return 0
    def get_be_byte_count(self):
        return self.byte_length - self.get_first_be_offset() - self.get_last_be_offset()

class TlpBypassReqBase(NamedTuple):
    op_code: OpCode
    addr: int
    byte_length: int
    tag: int
    req_id: int #upstream bdf
    first_be: int
    last_be: int
    dest_id: int
    ext_reg_num: int
    reg_num: int
    data: bytes
    event: Event

class TlpBypassRspBase(NamedTuple):
    op_code: OpCode
    addr: int
    cpl_byte_count: int
    byte_length: int
    tag: int
    cpl_id: int #req.req_id
    req_id: int #dev bdf
    cpl_status: ComplStatus
    first_be: int
    last_be: int
    data: bytes
    event: Event

class TlpBypassReq(TlpBypassReqBase, TlpBypass):
    pass

class TlpBypassRsp(TlpBypassRspBase, TlpBypass):
    pass

def TlpBypassReq2CfgTlp(req):
    tlp = Tlp()
    if req.op_code == OpCode.CFGRd0:
        tlp.fmt_type = TlpType.CFG_READ_0
    elif req.op_code == OpCode.CFGRd1:
        tlp.fmt_type = TlpType.CFG_READ_1
    elif req.op_code == OpCode.CFGWr0:
        tlp.fmt_type = TlpType.CFG_WRITE_0
    elif req.op_code == OpCode.CFGWr1:
        tlp.fmt_type = TlpType.CFG_WRITE_1
    tlp.requester_id = PcieId.from_int(req.req_id)
    tlp.dest_id = PcieId.from_int(req.dest_id)

    byte_length = req.get_be_byte_count()#bin(req.first_be).count('1')
    first_pad = req.get_first_be_offset()
    addr = req.reg_num*4 + first_pad
    tlp.set_addr_be(addr, byte_length)

    tlp.tag = req.tag
    tlp.register_number = (req.ext_reg_num << 6) + req.reg_num
    tlp.data = bytearray()
    first_be = req.first_be
    for i in range(4):
        if first_be & 0x1:
            tmp = req.data[i]
            tlp.data.extend(tmp.to_bytes(1, "little"))
        else:
            tlp.data.extend(b'\x00')
        first_be = first_be >> 1
    return tlp

def Tlp2TlpBypassCpl(tlp):
    if tlp.fmt_type == TlpType.CPL:
        op_code = OpCode.Cpl
    elif tlp.fmt_type == TlpType.CPL_DATA:
        op_code = OpCode.CplD
    else:
        raise ValueError("OPCODE_Unsupportedl")
    addr = 0
    byte_length = tlp.get_be_byte_count()
    tag = tlp.tag
    cpl_id = int(tlp.completer_id)
    req_id = int(tlp.requester_id)
    if tlp.status == CplStatus.SC:
        cpl_status = ComplStatus.SC
    elif tlp.status == CplStatus.CA:
        cpl_status = ComplStatus.CA
    elif tlp.status == CplStatus.UR:
        cpl_status = ComplStatus.UR
    elif tlp.status == CplStatus.CRS:
        cpl_status = ComplStatus.CRS
    if tlp.byte_count == 4:
        first_be = 0xf
    else:
        first_be = 0x0
    last_be = 0
    data = tlp.data
    cpl_byte_count = byte_length
    return TlpBypassRsp(op_code, addr, byte_length, cpl_byte_count, tag, cpl_id, req_id, cpl_status, first_be, last_be, data, None)

class Header(Packet):
    name = 'hdr'
    fields_desc = [
        BitField("op_code"          , 15,   4),
        BitField("addr"             , 0,  64),
        BitField("byte_length"      , 0,  13),
        BitField("ph"               , 0,  2 ),#0
        BitField("td"               , 0,  1 ),#0
        BitField("tc"               , 0,  3 ),#0
        BitField("th"               , 0,  1 ),#0
        BitField("tag"              , 0,  8 ),
        BitField("req_id"           , 0,  16),
        BitField("attr"             , 0,  3 ),#0
        BitField("ep"               , 0,  1 ),#0
        BitField("at"               , 0,  2 ),#0
        BitField("cpl_id"           , 0,  16),
        BitField("cpl_status"       , 0,  3 ),
        BitField("cpl_byte_count"   , 0,  13),
        BitField("first_be"         , 0,  4 ),
        BitField("last_be"          , 0,  4 ),
        BitField("bar_range"        , 0,  3 ),
        BitField("bdf"              , 0,  16 ),
        BitField("vf_active"        , 0,  1 ),
        BitField("dest_id"          , 0,  16 ),
        BitField("ext_reg_num"  , 0,  4  ),
        BitField("reg_num"      , 0,  6  )
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
    def unpack(self, data):
        assert type(data) == cocotb.binary.BinaryValue 
        return Header(data.buff)

#tlp req
TlpBypassReqBus, TlpBypassReqTransaction, TlpBypassReqSource, TlpBypassReqSink, TlpBypassReqMonitor = define_backpressure("TlpBypassReq",
    signals=["req_hdr", "req_sop", "req_eop", "req_data",  "req_gen"], 
    optional_signals=["req_linkdown"],
    vld_signal = "req_vld",
    sav_signal = "req_sav",
    signal_widths={"req_sop": 1, "req_eop": 1}
)

TlpBypassRspBus, TlpBypassRspTransaction, TlpBypassRspSource, TlpBypassRspSink, TlpBypassRspMonitor = define_stream("TlpBypassRsp",
    signals=["cpl_hdr", "cpl_sop", "cpl_eop", "cpl_data",  "cpl_gen"], 
    optional_signals=None,
    vld_signal = "cpl_vld",
    rdy_signal = "cpl_rdy",
    signal_widths={"cpl_sop": 1, "cpl_eop": 1}
)

class TlpBypassBus:
    def __init__(self, req=None, rsp=None):
        self.req = req
        self.rsp = rsp

    @classmethod
    def from_entity(cls, entity, **kwargs):
        req = TlpBypassReqBus.from_entity(entity, **kwargs)
        rsp = TlpBypassRspBus.from_entity(entity, **kwargs)
        return cls(req, rsp)

    @classmethod
    def from_prefix(cls, entity, prefix, **kwargs):
        req = TlpBypassReqBus.from_prefix(entity, prefix, **kwargs)
        rsp = TlpBypassRspBus.from_prefix(entity, prefix, **kwargs)
        return cls(req, rsp)

    @classmethod
    def from_channels(cls, req, rsp):
        return cls(req, rsp)