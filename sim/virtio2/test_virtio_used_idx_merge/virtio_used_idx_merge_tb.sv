/******************************************************************************
 * 文件名称 : virtio_used_idx_merge_tb.sv
 * 作者名称 : cui naiwan
 * 创建日期 : 2025/07/29
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/29     cui naiwan   初始化版本
 ******************************************************************************/

`include "virtio_define.svh"
`include "virtio_used_define.svh"

module virtio_used_idx_merge_tb #(
    parameter Q_NUM = 256,
    parameter Q_WIDTH = $clog2(Q_NUM),
    parameter CLOCK_FREQ_MHZ = 200
)(
    input                                clk,
    input                                rst,
    //===========from or to virtio_used_top==================//
    input  [$bits(virtio_vq_t)-1:0]      used_idx_merge_in_qid,
    input  logic                         used_idx_merge_in_vld,
    output logic                         used_idx_merge_in_sav,
    //==============from or to irq_merge_core_tx============//
    output [$bits(virtio_vq_t)-1:0]      used_idx_merge_out_to_net_tx_qid,
    output logic                         used_idx_merge_out_to_net_tx_vld,
    input  logic                         used_idx_merge_out_to_net_tx_rdy,
    //==============from or to irq_merge_core_rx============//
    output [$bits(virtio_vq_t)-1:0]      used_idx_merge_out_to_net_rx_qid,
    output logic                         used_idx_merge_out_to_net_rx_vld,
    input  logic                         used_idx_merge_out_to_net_rx_rdy,
    //===============from or to used_idx_irq_merge==========//
    output [$bits(net_used_idx_irq_ff_entry_t)-1:0]   used_idx_merge_out_dat,
    output logic                         used_idx_merge_out_vld,
    input  logic                         used_idx_merge_out_rdy,
    //==============form or to dfx============================//
    input  logic [5:0]                   dfx_used_idx_merge_used_idx_num_threshold,     //1/4/8/16/32,default is 8,config 1->not merge
    input  logic [2:0]                   dfx_used_idx_merge_timeout_time,  //0: 0.5us 1: 1us 2: 2us 3: 4us 4:8us,default is 2us
    output logic [13:0]                  dfx_used_idx_merge_err,
    output logic [12:0]                  dfx_used_idx_merge_status
);

    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, virtio_used_idx_merge_tb, "+all");
        $fsdbDumpMDA();
    end

    virtio_used_idx_merge #(
        .Q_NUM          (Q_NUM),
        .Q_WIDTH        (Q_WIDTH),
        .CLOCK_FREQ_MHZ (CLOCK_FREQ_MHZ)
    ) u_virtio_used_idx_merge(
        .clk                                        (clk),
        .rst                                        (rst),
        .used_idx_merge_in_qid                      (used_idx_merge_in_qid),
        .used_idx_merge_in_vld                      (used_idx_merge_in_vld),
        .used_idx_merge_in_sav                      (used_idx_merge_in_sav),
        .used_idx_merge_out_to_net_tx_qid           (used_idx_merge_out_to_net_tx_qid),
        .used_idx_merge_out_to_net_tx_vld           (used_idx_merge_out_to_net_tx_vld),
        .used_idx_merge_out_to_net_tx_rdy           (used_idx_merge_out_to_net_tx_rdy),
        .used_idx_merge_out_to_net_rx_qid           (used_idx_merge_out_to_net_rx_qid),
        .used_idx_merge_out_to_net_rx_vld           (used_idx_merge_out_to_net_rx_vld),
        .used_idx_merge_out_to_net_rx_rdy           (used_idx_merge_out_to_net_rx_rdy),
        .used_idx_merge_out_dat                     (used_idx_merge_out_dat),
        .used_idx_merge_out_vld                     (used_idx_merge_out_vld),
        .used_idx_merge_out_rdy                     (used_idx_merge_out_rdy),
        .dfx_used_idx_merge_used_idx_num_threshold  (8),
        .dfx_used_idx_merge_timeout_time            (2),
        .dfx_used_idx_merge_err                     (dfx_used_idx_merge_err),
        .dfx_used_idx_merge_status                  (dfx_used_idx_merge_status)
    );

endmodule