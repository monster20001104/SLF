/******************************************************************************
 * 文件名称 : virtio_netrx_svh.sv
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

`ifndef _VIRTIO_NETRX_DEFINE_
`define _VIRTIO_NETRX_DEFINE_

`default_nettype none

 `include "virtio_define.svh"  
 `include "../virtio_rx_buf/virtio_rx_buf_define.svh" 

    
    typedef struct packed{
        logic              sop;
        logic              eop;
        virtio_desc_eng_desc_rsp_sbd_t  netrx_desc_rsp_sbd;
        virtq_desc_t       netrx_desc_rsp_data;
        logic              ring_id_empty;
        logic [`VIRTIO_RX_BUF_PKT_NUM_WIDTH -1:0]        pkt_id;
    } virtio_netrx_sch_cmd_t;

    typedef struct packed{
        logic [`VIRTIO_Q_WIDTH-1:0]  qid;
        logic [15:0]           ring_id;
        logic [15:0]           avail_idx;
        logic [16:0]           len;
        logic                  enable_wr;
        virtio_err_info_t      err_info;
        logic                  force_down;
    } virtio_netrx_order_t;


    typedef struct packed{
        logic                           sop;
        logic                           eop;
        logic [`DATA_EMPTY-1:0]     mty;
        logic [`DATA_EMPTY-1:0]     sty;
        logic [`DATA_WIDTH-1:0]     data;
    } virtio_netrx_data_buf_t;

    typedef struct packed{
        logic              sop;
        logic              eop;
        virtio_desc_eng_desc_rsp_sbd_t  netrx_desc_rsp_sbd;
        virtq_desc_t       netrx_desc_rsp_data;
    } virtio_netrx_wr_cmd_t;

    typedef struct packed{
        logic                  tail;
        logic [`VIRTIO_Q_WIDTH-1:0]  qid;
    } virtio_netrx_sbd_t;

    typedef struct packed{
       virtio_vq_t vq;
       virtq_used_elem_t elem;
       logic [15:0] used_idx;
       virtio_err_info_t err_info;
       logic      force_down;
    } virtio_netrx_used_info_sim_t;

    typedef struct packed{
        logic [`VIRTIO_Q_WIDTH-1:0]  qid;
        logic                        empty;
    } virtio_netrx_pktet_order_t;




`default_nettype wire

`endif