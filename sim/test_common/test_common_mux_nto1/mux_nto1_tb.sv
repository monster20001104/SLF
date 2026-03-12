/******************************************************************************
 * 文件名称 : mux_nto1_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/12/28
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  12/28     Joe Jiang   初始化版本
 ******************************************************************************/
`timescale 1ns / 1ns
module mux_nto1_tb #(
    parameter N = 8
) (

    input  logic         clk,
    input  logic         rst,
    // master
    input  logic [N-1:0] mux_in_dat,
    input  logic         mux_in_vld,
    output logic         mux_in_rdy,
    // slave
    output logic [N-1:0] mux_out_dat,
    output logic         mux_out_vld,
    input  logic         mux_out_rdy
);



    mux_nto1 #(
        .N(N)
    ) u0_mux_nto1 (
        .clk        (clk),
        .rst        (rst),
        .mux_in_dat (mux_in_dat),
        .mux_in_vld (mux_in_vld),
        .mux_in_rdy (mux_in_rdy),
        .mux_out_dat(mux_out_dat),
        .mux_out_vld(mux_out_vld),
        .mux_out_rdy(mux_out_rdy)
    );

    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, mux_nto1_tb, "+all");
        $fsdbDumpMDA();
    end

endmodule
