/******************************************************************************
 * 文件名称 : pkt_fifo_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/12/20
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  12/20     Joe Jiang   初始化版本
 ******************************************************************************/
module pkt_fifo_tb #(
    parameter DW = 64
) (
    input                   clk,
    input                   rst,
    input  logic            dist_in_vld,
    input  logic            dist_in_eop,
    input  logic [DW-1:0]   dist_in_dat,
    input  logic            dist_in_drop,
    output logic            dist_in_rdy,

    output logic            dist_out_vld,
    output logic            dist_out_eop,
    output logic [DW-1:0]   dist_out_dat,
    output logic            dist_out_drop,
    input  logic            dist_out_rdy,

    input  logic            blk_in_vld,
    input  logic            blk_in_eop,
    input  logic [DW-1:0]   blk_in_dat,
    input  logic            blk_in_drop,
    output logic            blk_in_rdy,
    
    output logic            blk_out_vld,
    output logic            blk_out_eop,
    output logic [DW-1:0]   blk_out_dat,
    output logic            blk_out_drop,
    input  logic            blk_out_rdy
);

initial begin
    $fsdbAutoSwitchDumpfile(2000, "top.fsdb", 20);
    $fsdbDumpvars(0, pkt_fifo_tb, "+all");
    $fsdbDumpMDA();
end

logic [DW:0]    dist_din           ;
logic [DW:0]    dist_dout          ;
logic           dist_wren          ;
logic           dist_wr_end        ;
logic           dist_full          ;
logic           dist_rden          ;
logic           dist_empty         ;

logic [DW:0]    blk_din           ;
logic [DW:0]    blk_dout          ;
logic           blk_wren          ;
logic           blk_wr_end        ;
logic           blk_full          ;
logic           blk_rden          ;
logic           blk_empty         ;

assign dist_wren = dist_in_vld && dist_in_rdy;
assign dist_in_rdy = !dist_full;
assign dist_din = {dist_in_eop, dist_in_dat};
assign dist_wr_end = dist_in_eop;

assign dist_out_vld = !dist_empty;
assign dist_rden = dist_out_vld && dist_out_rdy;
assign {dist_out_eop, dist_out_dat} = dist_dout;
assign dist_out_drop = 1'b0;

assign blk_wren = blk_in_vld && blk_in_rdy;
assign blk_in_rdy = !blk_full;
assign blk_din = {blk_in_eop, blk_in_dat};
assign blk_wr_end = blk_in_eop;

assign blk_out_vld = !blk_empty;
assign blk_rden = blk_out_vld && blk_out_rdy;
assign {blk_out_eop, blk_out_dat} = blk_dout;
assign blk_out_drop = 1'b0;

pkt_fifo #(
        .DATA_WIDTH (DW+1       ),
        .RAM_MODE   ("dist"     ),
        .CHECK_ON   ( 1         )
) u0_pkt_fifo (
    .clk            (clk            ),
    .rst            (rst            ),
    .wren           (dist_wren      ),
    .din            (dist_din       ),
    .wr_end         (dist_wr_end    ),
    .wr_drop        (dist_in_drop   ),
    .full           (dist_full      ),
    .overflow       (               ),
    .rden           (dist_rden      ),
    .dout           (dist_dout      ),
    .empty          (dist_empty     ),
    .underflow      (               ),
    .parity_ecc_err (               )
);

pkt_fifo #(
        .DATA_WIDTH (DW+1       ),
        .RAM_MODE   ("blk"     ),
        .CHECK_ON   ( 1         )
) u1_pkt_fifo (
    .clk            (clk            ),
    .rst            (rst            ),
    .wren           (blk_wren       ),
    .din            (blk_din        ),
    .wr_end         (blk_wr_end     ),
    .wr_drop        (blk_in_drop    ),
    .full           (blk_full       ),
    .overflow       (               ),
    .rden           (blk_rden       ),
    .dout           (blk_dout       ),
    .empty          (blk_empty      ),
    .underflow      (               ),
    .parity_ecc_err (               )
);

endmodule