/******************************************************************************
 * 文件名称 : virtio_desc_engine_define.svh
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/06/24
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/24     Joe Jiang   初始化版本
 ******************************************************************************/
`timescale 1ns / 1ps

`ifndef _VIRTIO_DESC_ENGINE_DEFINES_
`define _VIRTIO_DESC_ENGINE_DEFINES_

`default_nettype none

`include "virtio_define.svh"


`define VIRTIO_DESC_ENG_SLOT_NUM 32
`define VIRTIO_DESC_ENG_SLOT_WIDTH $clog2(`VIRTIO_DESC_ENG_SLOT_NUM)


`define VIRTIO_DESC_ENG_LINE_NUM 8
`define VIRTIO_DESC_ENG_LINE_WIDTH $clog2(`VIRTIO_DESC_ENG_LINE_NUM)

`define VIRTIO_DESC_ENG_BUCKET_NUM 128
`define VIRTIO_DESC_ENG_BUCKET_WIDTH $clog2(`VIRTIO_DESC_ENG_BUCKET_NUM)

`define VIRTIO_DESC_ENG_DESC_BUF_DEPTH (`VIRTIO_DESC_ENG_BUCKET_NUM*`VIRTIO_DESC_ENG_LINE_NUM)

typedef struct packed{
    logic [`VIRTIO_DESC_ENG_SLOT_WIDTH-1:0]     slot_id;
    logic [`VIRTIO_DESC_ENG_BUCKET_WIDTH+`VIRTIO_DESC_ENG_LINE_WIDTH-1:0]   desc_buf_local_offset;
    logic                                       indirct_processing;
    logic [15:0]                                idx;
    logic [15:0]                                valid_desc_cnt;
    logic [20:0]                                total_buf_length;
    logic                                       cycle_flag; //only blk
    logic [3:0]                                 qdepth;
    logic                                       indirct_support; 
    logic [16:0]                                indirct_desc_size;  
    virtio_vq_t                                 vq;  
    logic [1:0]                                 dirct_desc_bitmap;
}virtio_desc_eng_core_desc_rd2rsp_t;



typedef struct packed{
    virtio_vq_t                                 vq;
    logic [`VIRTIO_DESC_ENG_SLOT_WIDTH-1:0]     slot_id;
    logic [`VIRTIO_DESC_ENG_BUCKET_WIDTH+`VIRTIO_DESC_ENG_LINE_WIDTH-1:0]   desc_buf_local_offset; 
    logic [19:0]                                max_len;

}virtio_desc_eng_core_rd_desc_order_t;

typedef struct packed{
    virtio_vq_t                                                         vq;
    logic [`VIRTIO_DESC_ENG_SLOT_WIDTH-1:0]                             slot_id;
    logic [20:0]                                                        total_buf_length;
    logic [15:0]                                                        next;
    logic                                                               flag_last; //有chain尾
    logic [63:0]                                                        indirct_addr;
    logic [16:0]                                                        indirct_desc_size;              
    logic                                                               flag_indirct; //读到indirct desc
    logic                                                               indirct_processing;
    logic [7:0]                                                         vld_cnt;
    logic [3:0]                                                         qdepth;
    logic [19:0]                                                        max_len;
    logic                                                               cycle_flag; //only blk
    ///////////////err bits
    logic                                                               pcie_err;
    logic                                                               indirct_desc_next_must_be_zero;
    logic                                                               desc_zero_len;
    logic                                                               desc_buf_len_oversize;
    logic                                                               indirct_nexted_desc;
    logic                                                               write_only_invalid;
    logic                                                               unsupport_indirct;
}virtio_desc_eng_core_info_ff_t;

typedef enum logic [1:0]  {
    SLOT_STATUS_NOMAL   = 2'b00,
    SLOT_STATUS_DORMANT = 2'b01,
    SLOT_STATUS_ANGRY   = 2'b10
}virtio_slot_status_t;

typedef struct packed{
    virtio_vq_t                             vq;
    logic [ `VIRTIO_RX_BUF_PKT_NUM_WIDTH-1:0]      pkt_id;
    logic [ `DEV_ID_WIDTH-1:0]               dev_id;
    logic                                   cpl;
    logic                                   forced_shutdown;
    logic                                   nxt_vld;
    logic [ `VIRTIO_DESC_ENG_SLOT_WIDTH-1:0] nxt_slot;
    logic                                   prev_vld;
    logic [ `VIRTIO_DESC_ENG_SLOT_WIDTH-1:0] prev_slot;
    logic [7:0]                             valid_desc_cnt;
    logic [63:0]                            desc_base_addr;
    logic [19:0]                            max_len;
    logic [15:0]                            bdf;
    logic [ 3:0]                            qdepth;
    logic [15:0]                            next_desc;
    logic [16:0]                            indirct_desc_size;
    logic                                   is_indirct;
    logic                                   indirct_processing;
    logic                                   indirct_support;
    logic [15:0]                            ring_id;
    logic [15:0]                            avail_idx;
    virtio_err_info_t                       err_info;
    logic [20:0]                            total_buf_length; //65562 + 16 * 65562, #64KB max TCP payload + 12B virtio-net header + 14B eth header
}virtio_desc_eng_core_slot_ctx_t;

typedef enum logic [2:0]  { 
        SHUTDOWN    = 3'b001,
        DESC_RSP    = 3'b010,
        WAKE_UP     = 3'b100
} req_type_t;

typedef struct packed{
        virtio_vq_t                                 vq;
        logic [`VIRTIO_DESC_ENG_SLOT_WIDTH-1:0]      slot_id; 
}virtio_desc_eng_core_wakeup_info;

`default_nettype wire

`endif