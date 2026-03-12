/******************************************************************************
 * 文件名称 : virtio_used_sch_tb.sv
 * 作者名称 : cui naiwan
 * 创建日期 : 2025/07/08
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/08     cui naiwan   初始化版本
 ******************************************************************************/
 `include "virtio_define.svh"

 module virtio_used_sch_tb (
    input                                            clk,
    input                                            rst,
    //===============from or to blk_upstream================//
    input logic                                      blk_upstream_wr_used_info_vld,
    input logic [$bits(virtio_used_info_t)-1:0]      blk_upstream_wr_used_info_dat,
    output logic                                     blk_upstream_wr_used_info_rdy,
    //===============from or to net_tx=======================//
    input logic                                      net_tx_wr_used_info_vld,
    input logic [$bits(virtio_used_info_t)-1:0]      net_tx_wr_used_info_dat,
    output logic                                     net_tx_wr_used_info_rdy, 
    //===============from or to net_rx=======================//
    input logic                                      net_rx_wr_used_info_vld,
    input logic [$bits(virtio_used_info_t)-1:0]      net_rx_wr_used_info_dat,
    output logic                                     net_rx_wr_used_info_rdy, 
    //================from or to virtio_used=================//
    output logic                                     wr_used_info_vld,
    output logic [$bits(virtio_used_info_t)-1:0]     wr_used_info_dat,
    input  logic                                     wr_used_info_rdy
 );

    initial begin
        $fsdbDumpfile("top.fsdb");
        $fsdbDumpvars(0, virtio_used_sch_tb, "+all");
        $fsdbDumpMDA();
    end

    virtio_used_sch u_virtio_used_sch(
        .clk                           (clk                          ),
        .rst                           (rst                          ),
        .blk_upstream_wr_used_info_vld (blk_upstream_wr_used_info_vld),
        .blk_upstream_wr_used_info_dat (blk_upstream_wr_used_info_dat),
        .blk_upstream_wr_used_info_rdy (blk_upstream_wr_used_info_rdy),
        .net_tx_wr_used_info_vld       (net_tx_wr_used_info_vld      ),
        .net_tx_wr_used_info_dat       (net_tx_wr_used_info_dat      ),
        .net_tx_wr_used_info_rdy       (net_tx_wr_used_info_rdy      ),
        .net_rx_wr_used_info_vld       (net_rx_wr_used_info_vld      ),
        .net_rx_wr_used_info_dat       (net_rx_wr_used_info_dat      ),
        .net_rx_wr_used_info_rdy       (net_rx_wr_used_info_rdy      ),
        .wr_used_info_vld              (wr_used_info_vld             ),
        .wr_used_info_dat              (wr_used_info_dat             ),
        .wr_used_info_rdy              (wr_used_info_rdy             )
    );

 endmodule