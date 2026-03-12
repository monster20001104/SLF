from dataclasses import dataclass
from test_func import BasePacket
from scapy.all import BitField
from stream_bus import define_stream, StreamSink, StreamDriver
from backpressure_bus import define_backpressure, BackpressureSink, BackpressureSource
from typing import Optional


from monitors.tlp_adap_dma_bus import DmaRam
from ram_tbl import define_ram_tbl, RamTblSlaver

NetrxInfoBus, NetrxInfoTrans, NetrxInfoSource, _, _ = define_stream(
    "netrx_info",
    signals=["data"],
    optional_signals=None,  # 可选信号比如sop、eop
    vld_signal="vld",
    rdy_signal="rdy",
)

SlotReqBus, SlotReqTrans, _, SlotReqSink, _ = define_stream(
    "netrx_alloc_slot_req",
    signals=["data", "dev_id", "pkt_id"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

SlotRspBus, SlotRspTrans, SlotRspSource, _, _ = define_stream(
    "netrx_alloc_slot_rsp",
    signals=["data"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)


NetrxDescBus, NetrxDescTrans, NetrxDescSource, _, _ = define_stream(
    "netrx_desc_rsp",
    signals=["sop", "eop", "sbd", "data"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

RdDataReqBus, _, _, RdDataReqSink, _ = define_stream(
    "rd_data_req",
    signals=["data"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

RdDataRspBus, RdDataRspTrans, RdDataRspSource, _, _ = define_stream(
    "rd_data_rsp",
    signals=["data", "sop", "eop", "sty", "mty", "sbd"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)


SlotCtrlDevIdReqBus, SlotCtrlDevIdRspBus, _, _, SlotCtrlDevIdRspTrans, _, _, SlotCtrlDevIdTbl = define_ram_tbl(
    "slot_ctrl_dev_id",
    rd_req_signals=["req_qid"],
    rd_rsp_signals=["rsp_data"],
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld",

)


WrDataCtxReqBus, WrDataCtxRspBus, _, _, WrDataCtxRspTrans, _, _, WrDataCtxTbl = define_ram_tbl(
    "wr_data_ctx",
    rd_req_signals=["req_qid"],
    rd_rsp_signals=["rsp_bdf", "rsp_forced_shutdown"],
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld",
)


UsedInfoBus, _, UsedInfoSource, UsedInfoSink, UsedInfoMonitor = define_stream(
    "used_info",
    signals=["data"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

# 集中管理和存放所有的硬件接口对象
@dataclass
class Interfaces:
    netrx_info_if: Optional[StreamDriver] = None                #方括号里面表示可以存放的类型，等于号后面表示初始值

    netrx_alloc_slot_req_if: Optional[StreamSink] = None
    netrx_alloc_slot_rsp_if: Optional[StreamDriver] = None

    slot_ctrl_dev_id_if: Optional[RamTblSlaver] = None          # DUT是发起者TB返回数据 RamTB表示模拟一块硬件RAM或查找表
                                                                # DUT发起读请求，自动触发回调函数来返回数据
    netrx_desc_rsp_if: Optional[StreamDriver] = None

    rd_data_req_if: Optional[StreamSink] = None
    rd_data_rsp_if: Optional[StreamDriver] = None

    wr_data_ctx_if: Optional[RamTblSlaver] = None

    used_info_if: Optional[StreamSink] = None

    dma_if: Optional[DmaRam] = None                             # DMA内存模型接口
