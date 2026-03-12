/******************************************************************************
 * 文件名称 : virtio_used_define.svh
 * 作者名称 : cui naiwan
 * 创建日期 : 2025/06/24
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/24     cui naiwan   初始化版本
 ******************************************************************************/
`timescale 1ns / 1ps

`ifndef _VIRTIO_USED_DEFINE_
`define _VIRTIO_USED_DEFINE_

`default_nettype none
`include "../virtio_define.svh"

typedef enum logic { 
    USED_INFO    = 1'b0,
    USED_IDX_IRQ = 1'b1
}virtio_used_irq_ff_wr_type_t; 

typedef enum logic { 
    NET_TX_USED_IDX_IRQ = 1'b0,
    NET_RX_USED_IDX_IRQ = 1'b1
} net_used_idx_irq_ff_wr_type_t; 

typedef enum logic [2:0] { 
    IS_SET_MASK        = 3'b001,
    IS_USED_INFO_IRQ   = 3'b010,
    IS_BLK_DS_ERR_INFO = 3'b100
} used_top_sch_result_type_t; 

typedef struct packed {
    net_used_idx_irq_ff_wr_type_t     typ;     
    virtio_vq_t                       qid;    
} net_used_idx_irq_ff_entry_t;

typedef struct packed {
    virtio_used_irq_ff_wr_type_t   typ;     
    virtio_used_info_t             used_info;    
} used_irq_ff_entry_t;

typedef struct packed {
    logic                        wr_flag;
    logic [15:0]                 used_idx;
} virtio_used_elem_ptr_info_t;

typedef struct packed {
    virtio_vq_t                  vq;
    used_top_sch_result_type_t   typ;
    used_irq_ff_entry_t          used_dat;
} virtio_used_handshake_reg_info_t;

    

`default_nettype wire

`endif
