#!/usr/bin/env python3
################################################################################
#  文件名称 : tlp_adap_dma_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/01
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/01     Joe Jiang   初始化版本
################################################################################
import sys
import cocotb
from scapy.all import Packet, BitField
sys.path.append('..')
from backpressure_bus import define_backpressure

RD2RSP_LB_BITS = 104

class Desc(Packet):
    name = 'desc'
    fields_desc = [
        BitField("dev_id", 0,  10),
        BitField("bdf", 0,  16),
        BitField("vf_active", 0, 1),
        BitField("tc", 0, 3),#
        BitField("attr", 0, 3),#
        BitField("th", 0, 1),#
        BitField("td", 0, 1),#
        BitField("ep", 0, 1),#
        BitField("at", 0, 2),#
        BitField("ph", 0, 2),#
        BitField("pcie_addr", 0, 64),
        BitField("pcie_length", 0, 24),
        BitField("rd2rsp_loop", 0, RD2RSP_LB_BITS)
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
        return Desc(data.buff)

#write channel
DmaWrReqBus, DmaWrReqTransaction, DmaWrReqSource, DmaWrReqSink, DmaWrReqMonitor = define_backpressure("DmaWrReq",
    signals=["wr_req_sop", "wr_req_eop", "wr_req_data", "wr_req_sty", "wr_req_mty", "wr_req_desc"], 
    optional_signals=None,
    vld_signal = "wr_req_val",
    sav_signal = "wr_req_sav",
    signal_widths={"wr_req_sop": 1, "wr_req_eop": 1}
)
#write rsp channel
DmaWrRspBus, DmaWrRspTransaction, DmaWrRspSource, DmaWrRspSink, DmaWrRspMonitor = define_backpressure("DmaWrRsp",
    signals=["wr_rsp_rd2rsp_loop"], 
    optional_signals=None,
    vld_signal = "wr_rsp_val",
    sav_signal = None,
    signal_widths=None
)
#write rsp channel have has_sav
DmaWrRspBusSav, DmaWrRspTransactionSav, DmaWrRspSourceSav, DmaWrRspSinkSav, DmaWrRspMonitorSav = define_backpressure("DmaWrRsp",
    signals=["wr_rsp_rd2rsp_loop"], 
    optional_signals=["wr_rsp_dirty_log"],
    vld_signal = "wr_rsp_val",
    sav_signal = "wr_rsp_sav",
    signal_widths=None
)

#read req channel
DmaRdReqBus, DmaRdReqTransaction, DmaRdReqSource, DmaRdReqSink, DmaRdReqMonitor = define_backpressure("DmaRdReq",
    signals=["rd_req_sty", "rd_req_desc"], 
    optional_signals=None,
    vld_signal = "rd_req_val",
    sav_signal = "rd_req_sav",
    signal_widths=None
)

#read rsp channel
DmaRdRspBus, DmaRdRspTransaction, DmaRdRspSource, DmaRdRspSink, DmaRdRspMonitor = define_backpressure("DmaRdRsp",
    signals=["rd_rsp_sop", "rd_rsp_eop", "rd_rsp_err", "rd_rsp_data", "rd_rsp_sty", "rd_rsp_mty", "rd_rsp_desc"], 
    optional_signals=None,
    vld_signal = "rd_rsp_val",
    sav_signal = None,
    signal_widths={"rd_rsp_sop": 1, "rd_rsp_eop": 1, "rd_rsp_err":1}
)
#read rsp channel have has_sav
DmaRdRspBusSav, DmaRdRspTransactionSav, DmaRdRspSourceSav, DmaRdRspSinkSav, DmaRdRspMonitorSav = define_backpressure("DmaRdRsp",
    signals=["rd_rsp_sop", "rd_rsp_eop", "rd_rsp_err", "rd_rsp_data", "rd_rsp_sty", "rd_rsp_mty", "rd_rsp_desc"], 
    optional_signals=None,
    vld_signal = "rd_rsp_val",
    sav_signal = "rd_rsp_sav",
    signal_widths={"rd_rsp_sop": 1, "rd_rsp_eop": 1, "rd_rsp_err":1}
)

class DmaWriteBus:
    def __init__(self, wr_req=None, wr_rsp=None, has_sav=None):
        self.wr_req = wr_req
        self.wr_rsp = wr_rsp
        self.has_sav = has_sav

    @classmethod
    def from_entity(cls, entity, has_sav=None, **kwargs):
        wr_req = DmaWrReqBus.from_entity(entity, **kwargs)
        if has_sav == None:
            wr_rsp = DmaWrRspBus.from_entity(entity, **kwargs)
        else :
            wr_rsp = DmaWrRspBusSav.from_entity(entity, **kwargs)            
        return cls(wr_req, wr_rsp, has_sav = has_sav)

    @classmethod
    def from_prefix(cls, entity, prefix, has_sav=None, **kwargs):
        wr_req = DmaWrReqBus.from_prefix(entity, prefix, **kwargs)
        if has_sav == None:
            wr_rsp = DmaWrRspBus.from_prefix(entity, prefix, **kwargs)
        else :
            wr_rsp = DmaWrRspBusSav.from_prefix(entity, prefix, **kwargs)
        return cls(wr_req, wr_rsp, has_sav = has_sav)

    @classmethod
    def from_channels(cls, wr_req, wr_rsp):
        return cls(wr_req, wr_rsp)


class DmaReadBus:
    def __init__(self, rd_req=None, rd_rsp=None ,has_sav=None):
        self.rd_req = rd_req
        self.rd_rsp = rd_rsp
        self.has_sav = has_sav
    @classmethod
    def from_entity(cls, entity, has_sav=None, **kwargs):
        rd_req = DmaRdReqBus.from_entity(entity, **kwargs)
        if has_sav == None:
            rd_rsp = DmaRdRspBus.from_entity(entity, **kwargs)
        else :
            rd_rsp = DmaRdRspBusSav.from_entity(entity, **kwargs)
        return cls(rd_req, rd_rsp, has_sav = has_sav)

    @classmethod
    def from_prefix(cls, entity, prefix, has_sav=None, **kwargs):
        rd_req = DmaRdReqBus.from_prefix(entity, prefix, **kwargs)
        if has_sav == None:
            rd_rsp = DmaRdRspBus.from_prefix(entity, prefix, **kwargs)
        else :
            rd_rsp = DmaRdRspBusSav.from_prefix(entity, prefix, **kwargs)
        return cls(rd_req, rd_rsp, has_sav = has_sav)

    @classmethod
    def from_channels(cls, rd_req, rd_rsp):
        return cls(rd_req, rd_rsp)


class DmaBus:
    def __init__(self, write=None, read=None, has_sav=None, **kwargs):
        self.write = write
        self.read = read
        self.has_sav = has_sav
    @classmethod
    def from_entity(cls, entity, has_sav=None, **kwargs):
        write = DmaWriteBus.from_entity(entity, has_sav, **kwargs)
        read = DmaReadBus.from_entity(entity, has_sav, **kwargs)
        return cls(write, read ,has_sav=has_sav)

    @classmethod
    def from_prefix(cls, entity, prefix, has_sav=None, **kwargs):
        write = DmaWriteBus.from_prefix(entity, prefix, has_sav, **kwargs)
        read = DmaReadBus.from_prefix(entity, prefix, has_sav, **kwargs)
        return cls(write, read ,has_sav=has_sav)

    @classmethod
    def from_channels(cls, wr_req, rd_req, rd_rsp):
        write = DmaWriteBus.from_channels(wr_req)
        read = DmaReadBus.from_channels(rd_req, rd_rsp)
        return cls(write, read)
