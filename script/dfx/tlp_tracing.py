#!/usr/bin/python3
# -*- coding: utf-8 -*-
import argparse
from tlp_tracing_read import Tracing

class Tlp_Tracing():
    def default(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()     

    def first_loop_capture(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
#######################循环抓###########################
##全抓
    def loop_capture_tx_rx_all_type(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=1,tx_cpl_cpld_flag=1,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##tx全抓
    def loop_capture_tx_all_type(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=1,tx_cpl_cpld_flag=1,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx全抓
    def loop_capture_rx_all_type(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##tx--mrd
    def loop_capture_tx_mrd(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##tx--mwr
    def loop_capture_tx_mwr(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=0,tx_mwr_flag=1,tx_cpl_cpld_flag=0,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##tx--cpl
    def loop_capture_tx_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=1,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mrd
    def loop_capture_rx_mrd(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mwr
    def loop_capture_rx_mwr(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=1,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--cpl
    def loop_capture_rx_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=1,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--cfg
    def loop_capture_rx_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=1,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##tx--mrd and mwr
    def loop_capture_tx_mrd_mwr(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=1,tx_cpl_cpld_flag=0,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##tx--mwr and cpl
    def loop_capture_tx_mwr_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=0,tx_mwr_flag=1,tx_cpl_cpld_flag=1,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##tx--mrd and cpl
    def loop_capture_tx_mrd_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=0,tx_cpl_cpld_flag=1,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mrd and mwr
    def loop_capture_rx_mrd_mwr(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mwr and cpl
    def loop_capture_rx_mwr_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mrd and cpl
    def loop_capture_rx_mrd_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=0,rx_cpl_cpld_flag=1,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--cpl and cfg
    def loop_capture_rx_cpl_cpld_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mrd and cfg
    def loop_capture_rx_mrd_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=1,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mwr and cfg
    def loop_capture_rx_mwr_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=1,rx_cpl_cpld_flag=0,rx_cfg_flag=1,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mrd and mwr and cpl
    def loop_capture_rx_mrd_mwr_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mrd and mwr and cfg
    def loop_capture_rx_mrd_mwr_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=0,rx_cfg_flag=1,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mrd and cpl and cfg
    def loop_capture_rx_mrd_cpl_cpld_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=0,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--mwr and cpl and cfg
    def loop_capture_rx_mwr_cpl_cpld_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
##rx--cpld_cpl and tx mrd mwr
    def loop_capture_tx_mrd_mwr_rx_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=1,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=1,rx_cfg_flag=0,single_start_flag=0,loop_start_flag=1)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_loop_read_data()
#######################单次抓###########################
##全抓
    def single_capture_tx_rx_all_type(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=1,tx_cpl_cpld_flag=1,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##tx全抓
    def single_capture_tx_all_type(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=1,tx_cpl_cpld_flag=1,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx全抓
    def single_capture_rx_all_type(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##tx--mrd
    def single_capture_tx_mrd(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##tx--mwr
    def single_capture_tx_mwr(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=0,tx_mwr_flag=1,tx_cpl_cpld_flag=0,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##tx--cpl
    def single_capture_tx_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=1,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mrd
    def single_capture_rx_mrd(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mwr
    def single_capture_rx_mwr(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=1,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--cpl
    def single_capture_rx_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=1,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--cfg
    def single_capture_rx_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=1,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##tx--mrd and mwr
    def single_capture_tx_mrd_mwr(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=1,tx_cpl_cpld_flag=0,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##tx--mwr and cpl
    def single_capture_tx_mwr_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=0,tx_mwr_flag=1,tx_cpl_cpld_flag=1,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##tx--mrd and cpl
    def single_capture_tx_mrd_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=1,tx_mrd_flag=1,tx_mwr_flag=0,tx_cpl_cpld_flag=1,rx_flag=0,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mrd and mwr
    def single_capture_rx_mrd_mwr(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=0,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mwr and cpl
    def single_capture_rx_mwr_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mrd and cpl
    def single_capture_rx_mrd_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=0,rx_cpl_cpld_flag=1,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--cpl and cfg
    def single_capture_rx_cpl_cpld_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=0,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mrd and cfg
    def single_capture_rx_mrd_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=0,rx_cpl_cpld_flag=0,rx_cfg_flag=1,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mwr and cfg
    def single_capture_rx_mwr_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=1,rx_cpl_cpld_flag=0,rx_cfg_flag=1,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mrd and mwr and cpl
    def single_capture_rx_mrd_mwr_cpl_cpld(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=0,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mrd and mwr and cfg
    def single_capture_rx_mrd_mwr_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=1,rx_cpl_cpld_flag=0,rx_cfg_flag=1,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mrd and cpl and cfg
    def single_capture_rx_mrd_cpl_cpld_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=1,rx_mwr_flag=0,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()
##rx--mwr and cpl and cfg
    def single_capture_rx_mwr_cpl_cpld_cfg(self,bdf,base_addr):
        tracing = Tracing(bdf,base_addr)
        tracing.tracing_stop()
        tracing.tracing_init(tx_flag=0,tx_mrd_flag=0,tx_mwr_flag=0,tx_cpl_cpld_flag=0,rx_flag=1,rx_mrd_flag=0,rx_mwr_flag=1,rx_cpl_cpld_flag=1,rx_cfg_flag=1,single_start_flag=1,loop_start_flag=0)
        input("=== 回车后停止采集并打印至trace.log文件 ===>")
        tracing.tracing_stop()
        tracing.tracing_single_read_data()

if __name__=="__main__":
    tracing = Tlp_Tracing()
    methods = [m_name for m_name in dir(tracing) if m_name[0:2] != '__']
    parser = argparse.ArgumentParser(description="used for tracing debug!")
    parser.add_argument("-bdf", "--bdf", type=str, default='01:00.0', help = "BDF stands for the Bus:Device.Function notation used to succinctly describe PCI and PCIe devices.")
    parser.add_argument("-base_addr", "--base_addr", type=lambda x: int(x, 0), default=0x200000, help="host = 0x200000 soc = 0x300000")
    parser.add_argument("-m", "--method", type=str, default='default', choices=methods)
    args = parser.parse_args()
    getattr(tracing, args.method)(args.bdf,args.base_addr)