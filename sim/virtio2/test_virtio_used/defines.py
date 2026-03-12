#!/usr/bin/env python3
################################################################################
#  文件名称 : defines.py
#  作者名称 : cui naiwan
#  创建日期 : 2025/07/25
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  07/25     cui naiwan   初始化版本
################################################################################
import sys
sys.path.append('../../common')
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union


UsedCtxRdReqBus, UsedCtxRdRspBus, _, _, UsedCtxRdRspTransaction, _, _, UsedCtxRdTblIf = define_ram_tbl("used_ring_irq", 
    rd_req_signals=["req_qid"], 
    rd_rsp_signals=["rsp_forced_shutdown", "rsp_msix_addr", "rsp_msix_data", "rsp_dev_id", "rsp_bdf", "rsp_msix_mask", "rsp_msix_pending", "rsp_used_ring_addr", "rsp_qdepth", "rsp_msix_enable", "rsp_q_status", "rsp_err_fatal"], 
    rd_req_vld_signal="req_vld",
    rd_rsp_vld_signal="rsp_vld"
)

UsedElemPtrRdReqBus, UsedElemPtrRdRspBus, UsedElemPtrWrBus, _, UsedElemPtrRdRspTransaction, _, _, UsedElemPtrTblIf = define_ram_tbl("used_elem_ptr", 
    rd_req_signals=["rd_req_qid"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    wr_signals=["wr_qid", "wr_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld"
)

_, _, ErrfatalWrBus, _, _, _, _, ErrfatalWrTblIf = define_ram_tbl("err_fatal",
    wr_signals=["wr_qid", "wr_dat"],
    wr_vld_signal="wr_vld"
)

_, _, DmawrusedidxirqflagWrBus, _, _, _, _, DmawrusedidxirqflagWrTblIf = define_ram_tbl("dma_write_used_idx_irq_flag",
    wr_signals=["wr_qid", "wr_dat"],
    wr_vld_signal="wr_vld"
)

_, _, UsedIdxWrBus, _, _, _, _, UsedIdxTblIf = define_ram_tbl("used_idx",
    wr_signals=["wr_qid", "wr_dat"],
    wr_vld_signal="wr_vld"
)

_, _, MsixWrBus, _, _, _, _, MsixTblIf = define_ram_tbl("msix_tbl",
    wr_signals=["wr_qid", "wr_mask", "wr_pending"],
    wr_vld_signal="wr_vld"
)

WrusedinfoBus, _, WrusedinfoSource, WrusedinfoSink, WrusedinfoMonitor = define_stream("wr_used_info",
    signals=["dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

ErrhandleBus, _, _, ErrhandleSink, ErrhandleMonitor = define_stream("err_handle",
    signals=["qid", "dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

SetmaskBus, _, SetmaskSource, SetmaskSink, SetmaskMonitor = define_stream("set_mask_req",
    signals=["qid", "dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

WrblkdserrinfoBus, _, WrblkdserrinfoSource, WrblkdserrinfoSink, WrblkdserrinfoMonitor = define_stream("blk_ds_err_info_wr",
    signals=["qid", "dat"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

TxMsixTimeRdReqBus, TxMsixTimeRdRspBus, _, _, TxMsixTimeRdRspTransaction, _, _, TxMsixTimeRdTbl = define_ram_tbl("msix_aggregation_time", 
    rd_req_signals=["rd_req_qid_net_tx"], 
    rd_rsp_signals=["rd_rsp_dat_net_tx"], 
    rd_req_vld_signal="rd_req_vld_net_tx",
    rd_rsp_vld_signal="rd_rsp_vld_net_tx"
)

TxMsixThresholdRdReqBus, TxMsixThresholdRdRspBus, _, _, TxMsixThresholdRdRspTransaction, _, _, TxMsixThresholdRdTbl = define_ram_tbl("msix_aggregation_threshold", 
    rd_req_signals=["rd_req_qid_net_tx"], 
    rd_rsp_signals=["rd_rsp_dat_net_tx"], 
    rd_req_vld_signal="rd_req_vld_net_tx",
    rd_rsp_vld_signal="rd_rsp_vld_net_tx"
)

RxMsixTimeRdReqBus, RxMsixTimeRdRspBus, _, _, RxMsixTimeRdRspTransaction, _, _, RxMsixTimeRdTbl = define_ram_tbl("msix_aggregation_time", 
    rd_req_signals=["rd_req_qid_net_rx"], 
    rd_rsp_signals=["rd_rsp_dat_net_rx"], 
    rd_req_vld_signal="rd_req_vld_net_rx",
    rd_rsp_vld_signal="rd_rsp_vld_net_rx"
)

RxMsixThresholdRdReqBus, RxMsixThresholdRdRspBus, _, _, RxMsixThresholdRdRspTransaction, _, _, RxMsixThresholdRdTbl = define_ram_tbl("msix_aggregation_threshold", 
    rd_req_signals=["rd_req_qid_net_rx"], 
    rd_rsp_signals=["rd_rsp_dat_net_rx"], 
    rd_req_vld_signal="rd_req_vld_net_rx",
    rd_rsp_vld_signal="rd_rsp_vld_net_rx"
)

TxMsixInfoRdReqBus, TxMsixInfoRdRspBus, TxMsixInfoWrBus, _, TxMsixInfoRdRspTransaction, _, _, TxMsixInfoTbl = define_ram_tbl("msix_aggregation_info", 
    rd_req_signals=["rd_req_qid_net_tx"], 
    rd_rsp_signals=["rd_rsp_dat_net_tx"], 
    wr_signals=["wr_qid_net_tx", "wr_dat_net_tx"], 
    rd_req_vld_signal="rd_req_vld_net_tx",
    rd_rsp_vld_signal="rd_rsp_vld_net_tx",
    wr_vld_signal="wr_vld_net_tx"
)

RxMsixInfoRdReqBus, RxMsixInfoRdRspBus, RxMsixInfoWrBus, _, RxMsixInfoRdRspTransaction, _, _, RxMsixInfoTbl = define_ram_tbl("msix_aggregation_info", 
    rd_req_signals=["rd_req_qid_net_rx"], 
    rd_rsp_signals=["rd_rsp_dat_net_rx"], 
    wr_signals=["wr_qid_net_rx", "wr_dat_net_rx"], 
    rd_req_vld_signal="rd_req_vld_net_rx",
    rd_rsp_vld_signal="rd_rsp_vld_net_rx",
    wr_vld_signal="wr_vld_net_rx"
)



class wr_used_info(Packet):
    name = 'wr_used_info'
    fields_desc = [
        BitField("qid_type"       ,   0,  2),
        BitField("qid"            ,   0,  8),
        BitField("used_elem"      ,   0,  64),
        BitField("used_idx"       ,   0,  16),
        BitField("forced_shutdown",   0,  1),
        BitField("fatal"          ,   0,  1),
        BitField("err_info"       ,   0,  7)
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
        assert type(data) == cocotb.binary.BinaryValue
        return cls(data.buff)

