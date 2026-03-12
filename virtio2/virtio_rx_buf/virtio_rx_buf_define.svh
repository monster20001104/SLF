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

`ifndef _VIRTIO_RX_BUF_DEFINE_
`define _VIRTIO_RX_BUF_DEFINE_

`default_nettype none
`include "../virtio_define.svh"

typedef struct packed {
    virtio_vq_t vq;  //type用固定值，VIRTIO_NET_RX_TYPE
    logic [`VIRTIO_RX_BUF_PKT_NUM_WIDTH-1:0] pkt_id;  //不一定连续的
} virtio_rx_buf_req_info_t;

typedef struct packed {
    virtio_vq_t vq;
    logic [`VIRTIO_RX_BUF_PKT_NUM_WIDTH-1:0] pkt_id;
    logic drop;  //通知rx buf模块将pkt_id对应的报文丢弃
} virtio_rx_buf_rd_data_req_t;

typedef struct packed {
    virtio_vq_t  vq;
    // logic [7:0] gen;
    logic [17:0] pkt_len;
} virtio_rx_buf_rd_data_rsp_sbd_t;


// dfx

typedef struct packed {
    logic [1:0] recv_pkt_num_ram_err;
    logic parser_data_ff_overflow;
    logic parser_data_ff_underflow;
    logic [1:0] parser_data_ff_err;
    logic parser_info_ff_overflow;
    logic parser_info_ff_underflow;
    logic [1:0] parser_info_ff_err;
} virtio_rx_buf_parser_err_t;

typedef struct packed {
    logic beq2net_vld;
    logic beq2net_sav;
    logic parser_data_ff_pfull;
    logic parser_data_ff_empty;
    logic parser_info_ff_pfull;
    logic parser_info_ff_empty;
} virtio_rx_buf_parser_status_t;



typedef struct packed {
    logic [1:0] ip_csum_err;
    logic [1:0] trans_csum_err;
    logic csum_info_ff_overflow;
    logic csum_info_ff_underflow;
    logic [1:0] csum_info_ff_err;
    logic csum_data_ff_overflow;
    logic csum_data_ff_underflow;
    logic [1:0] csum_data_ff_err;
} virtio_rx_buf_csum_err_t;

typedef struct packed {
    logic [1:0] csum_drop_ram_err;
    logic [1:0] qos_drop_ram_err;
    logic [1:0] pfull_drop_ram_err;
    logic qos_info_ff_overflow;
    logic qos_info_ff_underflow;
    logic [1:0] qos_info_ff_err;
} virtio_rx_buf_drop_err_t;

typedef struct packed {
    logic [13:0] sch_err;  //44
    logic [1:0] frame_data_err;  // 30
    logic [1:0] link_info_err;
    logic [1:0] pc_fsm_info_err_0;
    logic [1:0] pc_fsm_info_err_1;
    logic [1:0] s_fsm_info_err;
    logic [1:0] next_info_err;
    logic [1:0] idx_que_err_0;
    logic [1:0] idx_que_err_1;
    logic [1:0] idx_dev_err;
    logic [1:0] frame_info_err;
    logic bkt_ff_overflow;  //10
    logic bkt_ff_underflow;
    logic [1:0] bkt_ff_err;  // 8
    logic rd_data_ff_overflow;
    logic rd_data_ff_underflow;
    logic [1:0] rd_data_ff_err;  //4
    logic [1:0] send_time_err;  //2
} virtio_rx_buf_link_err_t;

typedef struct packed {
    logic [3:0] drop_cstat;      // 4bit（bit4~bit7，最高位区域，累计8bit，总位宽）
    logic [3:0] drop_ctx_cstat;  // 4bit（bit0~bit3，最低位区域，累计4bit）
} virtio_rx_buf_drop_stat_t;

typedef struct packed { // 59 bit
    logic        drop_data_ff_rdy; 
    logic        drop_data_ff_vld; 
    logic        info_out_rdy;     
    logic        info_out_vld;     
    logic        rd_data_req_vld;  
    logic        rd_data_req_rdy;  
    logic        rd_data_rsp_vld;  
    logic        rd_data_rsp_rdy;  
    logic [11:0] sch_status;       
    logic [4:0]  rom_cstat;        
    logic [2:0]  time_up_cstat;    
    logic [6:0]  ram_rd_cstat;     
    logic [1:0]  bkt_rd_cstat;     
    logic [7:0]  c_fsm_cstat;      
    logic [7:0]  s_fsm_cstat;      
    logic [3:0]  p_fsm_cstat;      
    logic [1:0]  ram_wr_cstat;     
} virtio_rx_buf_link_stat_t;






`default_nettype wire

`endif
