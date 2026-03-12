/******************************************************************************
 * 文件名称 : virtio_blk_downstream_define.svh
 * 作者名称 : matao
 * 创建日期 : 2025/07/07
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   07/07       matao       初始化版本
 ******************************************************************************/
`timescale 1ns / 1ps
`ifndef _VIRTIO_BLK_DS_DEFINES_
`define _VIRTIO_BLK_DS_DEFINES_

`default_nettype none
`include "../virtio_define.svh"


typedef struct packed{
    logic [15:0]        magic_num           ;
    logic [7:0]         reserved            ;
    logic [7:0]         resv0               ;
    logic [31:0]        host_buffer_length  ;
    logic [63:0]        host_buffer_addr    ;
    logic [15:0]        virtio_flags        ;
    logic [15:0]        virtio_desc_index   ;
    logic [7:0]         resv1               ;
    logic [7:0]         vq_gen              ;
    logic [15:0]        vq_qid              ;
} virtio_blk_downstream_buffer_header_t;

typedef struct packed{
    logic [7:0]         desc_info_qid           ;
    logic [7:0]         desc_info_gen           ;
    virtio_err_info_t   desc_info_err_info      ;
    logic [15:0]        desc_info_ring_id       ;
    virtq_desc_flags_t  desc_info_flags         ;
    logic [63:0]        desc_info_addr          ;
    logic [31:0]        desc_info_length        ;
    logic               desc_info_ext_shutdown  ;
    logic               desc_info_int_shutdown  ;
    logic               desc_info_eop           ;
} virtio_blk_downstream_desc_info_t;

`default_nettype wire

`endif