/******************************************************************************
 * 文件名称 : virtio_irq_merge_core_tb.sv
 * 作者名称 : LCH
 * 创建日期 : 2025/07/28
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/28       LCH          初始化版本
 ******************************************************************************/
`timescale 1ns / 1ns
module virtio_irq_merge_core_tb #(
    parameter IRQ_MERGE_UINT_NUM       = 8,
    parameter IRQ_MERGE_UINT_NUM_WIDTH = $clog2(IRQ_MERGE_UINT_NUM),
    parameter QID_NUM                  = 256,
    parameter QID_WIDTH                = $clog2(QID_NUM),
    parameter TIME_MAP_WIDTH           = 2,
    parameter CLK_FREQ_M               = 200,
    parameter TIME_STAMP_UNIT_NS       = 500
) (
    input  logic                                             clk,
    input  logic                                             rst,
    // irq_in
    input  logic [                            QID_WIDTH-1:0] irq_in_qid,
    input  logic                                             irq_in_vld,
    output logic                                             irq_in_rdy,
    // irq_out
    output logic [                            QID_WIDTH-1:0] irq_out_qid,
    output logic                                             irq_out_vld,
    input  logic                                             irq_out_rdy,
    // msix_aggregation_time_rd_req
    output logic                                             msix_aggregation_time_rd_req_vld,
    output logic [ (QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] msix_aggregation_time_rd_req_idx,
    // msix_aggregation_time_rd_rsp 
    input  logic                                             msix_aggregation_time_rd_rsp_vld,
    input  logic [                 IRQ_MERGE_UINT_NUM*3-1:0] msix_aggregation_time_rd_rsp_dat,       // list_len = 8
    // msix_aggregation_threshold_rd_req
    output logic                                             msix_aggregation_threshold_rd_req_vld,
    output logic [                            QID_WIDTH-1:0] msix_aggregation_threshold_rd_req_idx,
    // msix_aggregation_threshold_rd_rsp
    input  logic                                             msix_aggregation_threshold_rd_rsp_vld,
    input  logic [                                      6:0] msix_aggregation_threshold_rd_rsp_dat,
    // msix_aggregation_info_rd_req
    output logic                                             msix_aggregation_info_rd_req_vld,
    output logic [ (QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] msix_aggregation_info_rd_req_idx,
    // msix_aggregation_info_rd_rsp
    input  logic                                             msix_aggregation_info_rd_rsp_vld,
    input  logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0] msix_aggregation_info_rd_rsp_dat,
    // msix_aggregation_info_wr
    output logic                                             msix_aggregation_info_wr_vld,
    output logic [ (QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] msix_aggregation_info_wr_idx,
    output logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0] msix_aggregation_info_wr_dat
);
    //cocotb probe
    logic                 tb_eng_in_flag;
    logic                 tb_eng_in_flag_d2;
    logic [          4:0] tb_scan_out_qid_d2;
    logic                 tb_scan_out_vld_d2;
    logic                 tb_scan_out_rdy_d2;
    logic                 tb_time_stamp_imp;
    logic [          6:0] tb_time_cycle_cnt;
    logic [         15:0] tb_time_stamp;
    logic [         15:0] tb_time_stamp_d2;
    logic [QID_WIDTH-1:0] tb_irq_in_qid_d2;
    logic                 tb_irq_in_vld_d2;
    logic                 tb_irq_in_rdy_d2;


    virtio_irq_merge_core_top #(
        .IRQ_MERGE_UINT_NUM      (IRQ_MERGE_UINT_NUM),
        .IRQ_MERGE_UINT_NUM_WIDTH(IRQ_MERGE_UINT_NUM_WIDTH),
        .QID_NUM                 (QID_NUM),
        .QID_WIDTH               (QID_WIDTH),
        .TIME_MAP_WIDTH          (TIME_MAP_WIDTH),
        .CLK_FREQ_M              (CLK_FREQ_M),
        .TIME_STAMP_UNIT_NS      (TIME_STAMP_UNIT_NS)
    ) u_virtio_irq_merge_core_top (
        .clk                                  (clk),
        .rst                                  (rst),
        // irq_in
        .irq_in_qid                           (irq_in_qid),
        .irq_in_vld                           (irq_in_vld),
        .irq_in_rdy                           (irq_in_rdy),
        // irq_out
        .irq_out_qid                          (irq_out_qid),
        .irq_out_vld                          (irq_out_vld),
        .irq_out_rdy                          (irq_out_rdy),
        // msix_aggregation_time_rd_req
        .msix_aggregation_time_rd_req_vld     (msix_aggregation_time_rd_req_vld),
        .msix_aggregation_time_rd_req_idx     (msix_aggregation_time_rd_req_idx),
        // msix_aggregation_time_rd_rsp
        .msix_aggregation_time_rd_rsp_vld     (msix_aggregation_time_rd_rsp_vld),
        .msix_aggregation_time_rd_rsp_dat     (msix_aggregation_time_rd_rsp_dat),
        // msix_aggregation_threshold_rd_req
        .msix_aggregation_threshold_rd_req_vld(msix_aggregation_threshold_rd_req_vld),
        .msix_aggregation_threshold_rd_req_idx(msix_aggregation_threshold_rd_req_idx),
        // msix_aggregation_threshold_rd_rsp
        .msix_aggregation_threshold_rd_rsp_vld(msix_aggregation_threshold_rd_rsp_vld),
        .msix_aggregation_threshold_rd_rsp_dat(msix_aggregation_threshold_rd_rsp_dat),
        // msix_aggregation_info_rd_req
        .msix_aggregation_info_rd_req_vld     (msix_aggregation_info_rd_req_vld),
        .msix_aggregation_info_rd_req_idx     (msix_aggregation_info_rd_req_idx),
        // msix_aggregation_info_rd_rsp
        .msix_aggregation_info_rd_rsp_vld     (msix_aggregation_info_rd_rsp_vld),
        .msix_aggregation_info_rd_rsp_dat     (msix_aggregation_info_rd_rsp_dat),
        // msix_aggregation_info_wr
        .msix_aggregation_info_wr_vld         (msix_aggregation_info_wr_vld),
        .msix_aggregation_info_wr_idx         (msix_aggregation_info_wr_idx),
        .msix_aggregation_info_wr_dat         (msix_aggregation_info_wr_dat)

    );

    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, virtio_irq_merge_core_tb, "+all");
        $fsdbDumpMDA();
    end

endmodule
