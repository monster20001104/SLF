#!/usr/bin/env python3
################################################################################
#  文件名称 : reset.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/01
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/01     Joe Jiang   初始化版本
################################################################################
import cocotb
from cocotb.triggers import RisingEdge, FallingEdge


class Reset:
    def _init_reset(self, reset_signal=None, active_level=True):
        self._local_reset = False
        self._ext_reset = False
        self._reset_state = True

        if reset_signal is not None:
            cocotb.start_soon(self._run_reset(reset_signal, bool(active_level)))

        self._update_reset()

    def assert_reset(self, val=None):
        if val is None:
            self.assert_reset(True)
            self.assert_reset(False)
        else:
            self._local_reset = bool(val)
            self._update_reset()

    def _update_reset(self):
        new_state = self._local_reset or self._ext_reset
        if self._reset_state != new_state:
            self._reset_state = new_state
            self._handle_reset(new_state)

    def _handle_reset(self, state):
        pass

    async def _run_reset(self, reset_signal, active_level):
        while True:
            if bool(reset_signal.value):
                await FallingEdge(reset_signal)
                self._ext_reset = not active_level
                self._update_reset()
            else:
                await RisingEdge(reset_signal)
                self._ext_reset = active_level
                self._update_reset()