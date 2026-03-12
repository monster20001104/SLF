/******************************************************************************
 * 文件名称 : fifo_tb.sv
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
module fifo_tb
#(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 32,
    parameter CHECK_ON = 0,
    parameter CHECK_MODE = "parity",
    parameter DEPTH_PFULL = FIFO_DEPTH*3/4,
    parameter DEPTH_PEMPTY = FIFO_DEPTH/4,
    parameter RAM_MODE = "blk", //blk, dist
    parameter FIFO_MODE = "fwft" //std, fwft
)(

    input                          clk              ,
    input                          rst              ,
    input                          wr_vld        ,
    input   [DATA_WIDTH-1 : 0]     wr_dat        ,
    output                         wr_sav        ,
    input                          rd_vld        ,
    output  [DATA_WIDTH-1 : 0]     rd_dat        ,
    output                         rd_sav        
);

    logic wren, pfull, empty;
    logic overflow, underflow;
    logic [DATA_WIDTH-1 : 0] din, dout;
    logic [1:0] parity_ecc_err;
    
    logic [5:0] not_sav_cnt;
    logic ready;

    yucca_sync_fifo #(
            .DATA_WIDTH     (DATA_WIDTH     ),
            .FIFO_DEPTH     (FIFO_DEPTH     ),
            .CHECK_ON       (CHECK_ON       ),
            .CHECK_MODE     (CHECK_MODE     ),
            .DEPTH_PFULL    (DEPTH_PFULL    ),
            .DEPTH_PEMPTY   (DEPTH_PEMPTY   ),
            .RAM_MODE       (RAM_MODE       ),
            .FIFO_MODE      (FIFO_MODE      )
    )u_sync_fifo
    (

        .clk           (clk             ),
        .rst           (rst             ),
        .wren          (wren            ),
        .din           (din             ),
        .full          (full            ),
        .pfull         (pfull           ),
        .overflow      (overflow        ),
        .rden          (rden            ),
        .dout          (dout            ),
        .empty         (empty           ),
        .pempty        (pempty          ),
        .underflow     (underflow       ),
        .usedw         (usedw           ),
        .parity_ecc_err(parity_ecc_err  )
  );

    assign wren       = wr_vld;
    assign wr_sav     = ~pfull;
    assign din        = wr_dat;

    assign rden       = !empty && ready;
    assign rd_vld     = rden;
    assign rd_dat     = dout;

    assign ready = not_sav_cnt <= 7;

    always @(posedge clk) begin
        if(rst)begin
            not_sav_cnt <= 'h0;
        end else if(rd_sav)begin
            not_sav_cnt <= 'h0;
        end else if(not_sav_cnt < 'h10) begin
            not_sav_cnt <= not_sav_cnt + 1'b1;
        end
    end

    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, fifo_tb, "+all");
        $fsdbDumpMDA();
    end

endmodule
