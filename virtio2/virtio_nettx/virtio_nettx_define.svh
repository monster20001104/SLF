/******************************************************************************
 * 文件名称 : virtio_nettx_svh.sv
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

`ifndef _VIRTIO_NETTX_DEFINE_
`define _VIRTIO_NETTX_DEFINE_

`default_nettype none

 `include "virtio_define.svh"   

 typedef struct packed{
        logic        sop;
        logic        eop;
        virtq_desc_t   desc;
        logic [`VIRTIO_Q_WIDTH-1:0] qid;
        logic [15:0] ring_id;
        logic [15:0] avail_idx;
        logic        drop;
        logic [9:0]  dev_id;
        logic        chain_tail;
        logic        forced_shutdown;
        logic [17:0] total_buf_len;
        logic [3:0]  cnt_chain;
        virtio_err_info_t err_info;
    } virtio_nettx_cmd_t;


    typedef struct packed{
        logic [`VIRTIO_Q_WIDTH-1:0] qid;
        logic        enable_rd;
        logic [15:0] ring_id;
        logic [15:0] avail_idx;
        logic        chain_tail;
        logic        tso_en;
        logic        csum_en;
        logic [7:0]  gen;
        logic [17:0] total_buf_len;
        logic        forced_shutdown;
        logic        chain_stop;
        virtio_err_info_t err_info;
    } virtio_nettx_order_t;

    typedef struct packed{
        logic [`VIRTIO_Q_WIDTH-1:0] qid;
        logic [15:0]          ring_id;
        logic                 tlp_err;
        logic [19:0]          len;
    } virtio_nettx_rsp_sbd_t;

    typedef struct packed{
        logic                        sop;
        logic                        eop;
        logic  [`DATA_EMPTY-1:0] sty;
        logic  [`DATA_EMPTY-1:0] mty;
        logic  [`DATA_WIDTH-1:0] data;
        logic                        err;
    } virtio_nettx_rsp_data_t;

    typedef struct packed{
       virtio_vq_t vq;
       virtq_used_elem_t elem;
       logic [15:0] used_idx;
       virtio_err_info_t err_info;
       logic      force_down;
       logic      chain_stop;
    } virtio_nettx_used_info_sim_t;



`default_nettype wire

`endif