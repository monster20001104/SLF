#!/usr/bin/env python3
################################################################################
#  文件名称 : mlite_bus.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/09/06
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  09/06     Joe Jiang   初始化版本
################################################################################
import sys
import cocotb
from typing import List, NamedTuple, Union
from cocotb.triggers import Event

sys.path.append('..')
from stream_bus import define_stream

MliteReqBus, MliteReqTransaction, MliteReqSource, MliteReqSink, MliteReqMonitor = define_stream("MliteReq",
    signals=["read", "addr", "wdata", "wmask"], 
    optional_signals=None,
    vld_signal = "valid",
    rdy_signal = "ready",
    signal_widths={"read": 1}
)

MliteRspBus, MliteRspTransaction, MliteRspSource, MliteRspSink, MliteRspMonitor = define_stream("MliteRsp",
    signals=["rdata"], 
    optional_signals=None,
    vld_signal = "rvalid",
    rdy_signal = "rready",
    signal_widths=None
)

class MliteBus:
    def __init__(self, req=None, rsp=None):
        self.req = req
        self.rsp = rsp

    @classmethod
    def from_entity(cls, entity, **kwargs):
        req = MliteReqBus.from_entity(entity, **kwargs)
        rsp = MliteRspBus.from_entity(entity, **kwargs)
        return cls(req, rsp)

    @classmethod
    def from_prefix(cls, entity, prefix, **kwargs):
        req = MliteReqBus.from_prefix(entity, prefix, **kwargs)
        rsp = MliteRspBus.from_prefix(entity, prefix, **kwargs)
        return cls(req, rsp)

    @classmethod
    def from_channels(cls, req, rsp):
        return cls(req, rsp)