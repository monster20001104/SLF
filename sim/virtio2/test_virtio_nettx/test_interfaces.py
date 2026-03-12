from dataclasses import dataclass
from typing import Optional
from stream_bus import define_stream, StreamSink, StreamDriver
from backpressure_bus import define_backpressure, BackpressureSink
from ram_tbl import define_ram_tbl, RamTblSlaver
from monitors.tlp_adap_dma_bus import DmaRam

SchReqBus, SchReqTrans, SchReqSource, _, _ = define_stream(
    "sch_req",
    signals=["qid"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

SlotReqBus, SlotReqTrans, _, SlotReqSink, _ = define_stream(
    "nettx_alloc_slot_req",
    signals=["data", "dev_id"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

SlotRspBus, SlotRspTrans, SlotRspSource, _, _ = define_stream(
    "nettx_alloc_slot_rsp",
    signals=["data"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

SlotCtxReqBus, SlotCtxRspBus, _, _, SlotCtxRspTrans, _, _, SlotCtxTbl = define_ram_tbl(
    "slot_ctrl_ctx_info_rd",
    rd_req_signals=["req_qid"],
    rd_rsp_signals=["rsp_qos_unit", "rsp_qos_enable", "rsp_dev_id"],
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld",
)

QosQueryReqBus, QosQueryReqTrans, _, QosQueryReqSink, _ = define_stream(
    "qos_query_req",
    signals=["uid"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

QosQueryRspBus, QosQueryRspTrans, QosQueryRspSource, _, _ = define_stream(
    "qos_query_rsp",
    signals=["data"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

NettxDescBus, NettxDescTrans, NettxDescSource, _, _ = define_stream(
    "nettx_desc_rsp",
    signals=["sop", "eop", "sbd", "data"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

QosUpdateBus, QosUpdateTrans, _, QosUpdateSink, _ = define_stream(
    "qos_update",
    signals=["uid", "len", "pkt_num"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

RdDataCtxReqBus, RdDataCtxRspBus, _, _, RdDataCtxRspTrans, _, _, RdDataCtxTbl = define_ram_tbl(
    "rd_data_ctx_info_rd",
    rd_req_signals=["req_qid"],
    rd_rsp_signals=[
        "rsp_bdf",
        "rsp_forced_shutdown",
        "rsp_qos_enable",
        "rsp_qos_unit",
        "rsp_tso_en",
        "rsp_csum_en",
        "rsp_gen",
    ],
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld",
)

Net2TsoBus, Net2TsoTrans, _, Net2TsoSink, _ = define_backpressure(
    "net2tso",
    signals=[
        "sop",
        "eop",
        "sty",
        "mty",
        "err",
        "data",
        "qid",
        "len",
        "gen",
        "tso_en",
        "csum_en",
    ],
    optional_signals=None,
    vld_signal="vld",
    sav_signal="sav",
)

UsedInfoBus, UsedInfoTrans, _, UsedInfoSink, _ = define_stream(
    "used_info",
    signals=["data"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)


@dataclass
class Interfaces:

    sch_req_if: Optional[StreamDriver] = None
    nettx_alloc_slot_req_if: Optional[StreamSink] = None
    nettx_alloc_slot_rsp_if: Optional[StreamDriver] = None
    slot_ctrl_ctx_if: Optional[RamTblSlaver] = None
    qos_query_req_if: Optional[StreamSink] = None
    qos_query_rsp_if: Optional[StreamDriver] = None
    qos_update_if: Optional[StreamSink] = None
    nettx_desc_rsp_if: Optional[StreamDriver] = None
    rd_data_ctx_if: Optional[RamTblSlaver] = None
    net2tso_if: Optional[BackpressureSink] = None
    used_info_if: Optional[StreamSink] = None
    dma_if: Optional[DmaRam] = None
