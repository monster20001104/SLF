/******************************************************************************
 * 文件名称 : virtio_avail_ring_svh.sv
 * 作者名称 : Feilong Yun
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/23     Feilong Yun   初始化版本
******************************************************************************/

`timescale 1ns / 1ps

`ifndef _VIRTIO_AVAIL_RING_DEFINE_
`define _VIRTIO_AVAIL_RING_DEFINE_

`default_nettype none


`include "virtio_define.svh"


typedef struct packed{
    virtio_q_type_t typ;
    logic [`VIRTIO_Q_WIDTH-1:0] qid;
    logic [255:0] ring_id_data;
    logic [15:0] qdepth;
    logic [15:0] avail_ui;
    logic [4:0]  rd_num;
    logic        tlp_err;
} virtio_ring_id_rsp;



`default_nettype wire

`endif