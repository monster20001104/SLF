#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : defines.py
#* 作者名称 : matao
#* 创建日期 : 2025/07/30
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   07/30       matao       初始化版本
#******************************************************************************/
from stream_bus import define_stream
from ram_tbl import define_ram_tbl

import sys
sys.path.append('..')

IrqInBus, IrqInTransaction, IrqInSource, IrqInSink, IrqInMonitor = define_stream("IrqIn_master",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)    
IrqOutBus, IrqOutTransaction, IrqOutSource, IrqOutSink, IrqOutMonitor = define_stream("IrqOut_slave",
    signals=["qid"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy",
    signal_widths=None
)    

MsixTimeRdReqBus, MsixTimeRdRspBus, _, _, MsixTimeRdRspTransaction, _, _, MsixTimeRdTbl = define_ram_tbl("MsixTime_rd", 
    rd_req_signals=["rd_req_idx"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld"
)

MsixThresholdRdReqBus, MsixThresholdRdRspBus, _, _, MsixThresholdRdRspTransaction, _, _, MsixThresholdRdTbl = define_ram_tbl("MsixThreshold_rd", 
    rd_req_signals=["rd_req_idx"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld"
)

MsixInfoRdReqBus, MsixInfoRdRspBus, MsixInfoWrBus, _, MsixInfoRdRspTransaction, _, _, MsixInfoTbl = define_ram_tbl("MsixInfo", 
    rd_req_signals=["rd_req_idx"], 
    rd_rsp_signals=["rd_rsp_dat"], 
    wr_signals=["wr_idx", "wr_dat"], 
    rd_req_vld_signal="rd_req_vld",
    rd_rsp_vld_signal="rd_rsp_vld",
    wr_vld_signal="wr_vld"
)

