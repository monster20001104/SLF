#!/usr/bin/env python3
#******************************************************************************
#* 文件名称 : virtio_irq_merge_core_ctx_ctrl.py
#* 作者名称 : matao
#* 创建日期 : 2025/07/30
#* 功能描述 : 
#*
#* 修改记录 : 
#*
#* 版本号  日期        修改人       修改内容
#* v1.0   07/30       matao       初始化版本
#******************************************************************************/
import cocotb
from cocotb.log import SimLog
from defines import *

class irq_merge_core_ctx(object):
    def __init__(self, msix_time, msix_threshold):
        self.msix_time = msix_time
        self.msix_threshold = msix_threshold

class irq_merge_core_local_ctx(object):
    def __init__(self, msix_info):
        self.msix_info = msix_info


class irq_merge_core_ctx_ctrl_callback(object):
    def _TimeRdCallback(self, req_obj):
        idx = int(req_obj.rd_req_idx)
        combined_dat = 0
        rsp = MsixTimeRdRspTransaction()
        for i in range(8):
            target_idx  = (idx << 3) + i #左移3位对应RTL例化8组eng
            if target_idx  not in self.ctxs.keys():
                #raise ValueError("The queue(idx:{}) is not exists".format(idx))
                combined_dat |= (0 << (3 * i))
            else:
                msix_time = self.ctxs[target_idx ].msix_time & 0x7 # 截断为3位（0~7）
                combined_dat |= (msix_time << (3 * i)) #对应每个time位宽3bit
        rsp.rd_rsp_dat = combined_dat
        return rsp

    def _ThresholdRdCallback(self, req_obj):
        idx = int(req_obj.rd_req_idx)
        if idx not in self.ctxs.keys():
            #raise ValueError("The queue(idx:{}) is not exists".format(idx))
            rsp = MsixThresholdRdRspTransaction()
            rsp.rd_rsp_dat = 0
            return rsp
        else:
            rsp = MsixThresholdRdRspTransaction()
            rsp.rd_rsp_dat = self.ctxs[idx].msix_threshold
            return rsp

    def _InfoWrCallback(self, req_obj):
        idx = int(req_obj.wr_idx)
        data = int(req_obj.wr_dat)
        # data width：TIME_MAP_WIDTH + 8 = 2 + 8 
        group_bit_width = 10
        group_mask = (1 << group_bit_width) - 1  # 10位掩码（0x3FF）
        for i in range(8):
            target_idx = (idx << 3) + i
            group_data = (data >> (i * group_bit_width)) & group_mask
            if target_idx not in self.local_ctxs.keys():
                #raise ValueError("The queue(idx:{}) is not exists".format(idx))
                local_ctx = irq_merge_core_local_ctx(0)
                self.local_ctxs[target_idx] = local_ctx
            else:
                local_ctx = irq_merge_core_local_ctx(group_data)
                self.local_ctxs[target_idx] = local_ctx

    def _InfoRdCallback(self, req_obj):
        idx = int(req_obj.rd_req_idx)
        combined_dat = 0
        group_bit_width = 10
        rsp = MsixInfoRdRspTransaction()
        for i in range(8):
            target_idx  = (idx << 3) + i
            if target_idx not in self.local_ctxs.keys():
                group_data = 0
            else:
                group_data = self.local_ctxs[target_idx].msix_info & ((1 << group_bit_width) - 1)
            combined_dat |= (group_data << (i * group_bit_width))
        rsp.rd_rsp_dat = combined_dat
        return rsp


class irq_merge_core_ctx_ctrl(irq_merge_core_ctx_ctrl_callback):
    def __init__(self, TimeRdTblIf, ThresholdRdTblIf, InfoTbl):
        self.log = SimLog("cocotb.tb")
        self.TimeRdTblIf = TimeRdTblIf
        self.ThresholdRdTblIf = ThresholdRdTblIf
        self.InfoTbl = InfoTbl

        self.TimeRdTblIf.set_callback(self._TimeRdCallback)
        self.ThresholdRdTblIf.set_callback(self._ThresholdRdCallback)
        self.InfoTbl.set_callback(self._InfoRdCallback)
        self.InfoTbl.set_wr_callback(self._InfoWrCallback)

        self.ctxs = {}
        self.local_ctxs = {}

    def create_queue(self, idx, msix_time, msix_threshold):
        ctx = irq_merge_core_ctx(msix_time, msix_threshold)
        if idx in self.ctxs.keys():
            raise ValueError("The queue(idx:{}) is already exists".format(idx))
        self.ctxs[idx] = ctx

    def clear_queue(self):
        self.ctxs.clear()
        self.local_ctxs.clear()

