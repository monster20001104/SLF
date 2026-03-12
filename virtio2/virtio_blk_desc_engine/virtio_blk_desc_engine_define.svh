/******************************************************************************
 * 文件名称 : virtio_rx_buf_define.svh
 * 作者名称 : lch
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   06/23       lch       初始化版本
 ******************************************************************************/
`timescale 1ns / 1ps

`ifndef _VIRTIO_BLK_DESC_ENGINE_DEFINES_
`define _VIRTIO_BLK_DESC_ENGINE_DEFINES_

`default_nettype none

`include "virtio_define.svh"


`define VIRTIO_BLK_DESC_ENG_SLOT_NUM 4
`define VIRTIO_BLK_DESC_ENG_SLOT_WIDTH $clog2(`VIRTIO_BLK_DESC_ENG_SLOT_NUM)


`define VIRTIO_BLK_DESC_ENG_LINE_NUM 8
`define VIRTIO_BLK_DESC_ENG_LINE_WIDTH $clog2(`VIRTIO_BLK_DESC_ENG_LINE_NUM)

`define VIRTIO_BLK_DESC_ENG_BUCKET_NUM 8
`define VIRTIO_BLK_DESC_ENG_BUCKET_WIDTH $clog2(`VIRTIO_BLK_DESC_ENG_BUCKET_NUM)

`default_nettype wire

typedef struct packed { // width: 21
    logic                     alloc_slot_req_vld;      // [20] width: 1
    logic                     alloc_slot_req_rdy;      // [19] width: 1
    logic                     alloc_slot_rsp_vld;      // [18] width: 1
    logic                     alloc_slot_rsp_rdy;      // [17] width: 1
    logic                     avail_id_req_vld;        // [16] width: 1
    logic                     avail_id_req_rdy;        // [15] width: 1
    logic                     avail_id_rsp_vld;        // [14] width: 1
    logic                     avail_id_rsp_rdy;        // [13] width: 1
    logic                     first_submit_vld;        // [12] width: 1
    logic                     first_submit_rdy;        // [11] width: 1
    logic                     avail_id_ff_full;        // [10] width: 1
    logic                     avail_id_ff_empty;       // [9] width: 1
    logic [$clog2(4 + 1)-1:0] slot_order_ff_usedw;     // [8:6] width: 3 ($clog2(5)=3)
    logic [2:0]               alloc_rsp_cstat;         // [5:3] width: 3
    logic [2:0]               resumer_cstat;           // [2:0] width: 3
} virtio_blk_desc_engine_alloc_status_t;

typedef struct packed { // width: 9
    logic       avail_id_err;               // [8] width: 1
    logic       slot_order_ff_overflow;     // [7] width: 1
    logic       slot_order_ff_underflow;    // [6] width: 1
    logic [1:0] slot_order_ff_err;          // [5:4] width: 2
    logic       avail_id_ff_overflow;       // [3] width: 1
    logic       avail_id_ff_underflow;      // [2] width: 1
    logic [1:0] avail_id_ff_err;            // [1:0] width: 2
} virtio_blk_desc_engine_alloc_err_t;

typedef struct packed { // width: 13
    logic                     blk_desc_vld;            // [12] width: 1
    logic                     blk_desc_rdy;            // [11] width: 1
    logic                     slot_cpl_ff_empty;       // [10] width: 1
    logic [$clog2(4 + 1)-1:0] slot_id_ff_usedw;        // [9:7] width: 3 ($clog2(5)=3)
    logic [4:0]               blk_desc_cstat;          // [6:2] width: 5
    logic [1:0]               slot_ff_cstat;           // [1:0] width: 2
} virtio_blk_desc_engine_free_status_t;

typedef struct packed { // width: 4
    logic       slot_id_ff_underflow;       // [3] width: 1
    logic       slot_id_ff_overflow;        // [2] width: 1
    logic [1:0] slot_id_ff_err;             // [1:0] width: 2
} virtio_blk_desc_engine_free_err_t;

typedef struct packed { // width: 13
    logic       info_rd_vld;                // [12] width: 1
    logic       info_rd_rdy;                // [11] width: 1
    logic       desc_dma_rd_req_vld;        // [10] width: 1
    logic       desc_dma_rd_req_sav;        // [9] width: 1
    logic [8:0] core_cstat;                 // [8:0] width: 9
} virtio_blk_desc_engine_core_status_t;

typedef struct packed { // width: 4
    logic       blk_desc_global_info_rd_req_err; // [3] width: 1
    logic       blk_desc_local_info_rd_req_err;  // [2] width: 1
    logic [1:0] slot_cpl_ram_err;               // [1:0] width: 2
} virtio_blk_desc_engine_core_err_t;



`endif
