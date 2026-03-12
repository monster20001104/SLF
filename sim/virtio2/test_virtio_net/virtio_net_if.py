from dataclasses import dataclass, field
from typing import Optional, List


from stream_bus import define_stream, StreamSink, StreamDriver
from backpressure_bus import define_backpressure, BackpressureSink, BackpressureSource
from monitors.tlp_adap_dma_bus import DmaRam
from drivers.beq_data_bus import BeqTxqMaster
from drivers.mlite_bus import MliteBusMaster

DoorbellReqBus, _, DoorbellReqSource, _, _ = define_stream("doorbell_req", signals=["vq"], optional_signals=None, vld_signal="vld", rdy_signal="rdy")

Net2TsoBus, _, _, Net2TsoSink, _ = define_backpressure(
    "Net2Tso",
    signals=["data", "sty", "mty", "sop", "eop", "err", "qid", "length", "gen", "tso_en", "csum_en"],
    optional_signals=None,
    vld_signal="vld",
    sav_signal="sav",
    signal_widths={"sop": 1, "eop": 1},
)

QosReqBus, QosReqTrans, QosReqMaster, QosReqSlaver, QosReqMoniter = define_stream(
    "qos_query_req",
    signals=["uid"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)
QosRspBus, QosRspTrans, QosRspMaster, QosRspSlaver, QosRspMoniter = define_stream(
    "qos_query_rsp",
    signals=["ok"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)
QosUpdateBus, QosUpdateTrans, QosUpdateMaster, QosUpdateSlaver, QosUpdateMoniter = define_stream(
    "qos_update",
    signals=["uid", "len", "pkt_num"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)


@dataclass
class QosIf:
    query_req_if: Optional[StreamSink] = None
    query_rsp_if: Optional[StreamDriver] = None
    update_if: Optional[StreamSink] = None


@dataclass
class Interfaces:
    dma_if: Optional[DmaRam] = None
    doorbell_if: Optional[StreamDriver] = None
    net2tso_if: Optional[BackpressureSink] = None
    beq2net_if: Optional[BeqTxqMaster] = None
    csr_if: Optional[MliteBusMaster] = None
    tx_qos: QosIf = field(default_factory=QosIf)
    rx_qos: QosIf = field(default_factory=QosIf)
