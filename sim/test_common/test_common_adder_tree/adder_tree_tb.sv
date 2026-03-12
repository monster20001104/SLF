/******************************************************************************
 * 文件名称 : adder_tree_tb.sv
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
module adder_tree_tb #(
    parameter WIDTH = 16,
    // parameter IDATA_WIDTH = 3,
    parameter DEPTH = 5
) (

    input  logic                              clk,
    input  logic                              rst,
    // master
    input  logic [ 2 ** DEPTH-1:0][WIDTH-1:0] in_data,
    input  logic                              in_vld,
    // slave
    output logic [WIDTH-1+DEPTH:0]            out_sum,
    output logic                              out_vld
);



    adder_tree #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) u0_adder_tree (
        .clk    (clk),
        .rst    (rst),
        .in_data(in_data),
        .in_vld (in_vld),
        .in_pause(0),
        .out_sum(out_sum),
        .out_vld(out_vld)
    );

    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, adder_tree_tb, "+all");
        $fsdbDumpMDA();
    end

endmodule
