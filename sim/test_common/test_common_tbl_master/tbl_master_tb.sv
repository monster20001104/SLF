/******************************************************************************
 * 文件名称 : tbl_master_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/12/20
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  12/20     Joe Jiang   初始化版本
 ******************************************************************************/
 module tbl_master_tb (
    input                                       clk,
    input                                       rst,
    input  logic [7:0]                          tb_rd_req_qid,
    input  logic                                tb_rd_req_vld,
    output logic [15:0]                         tb_rd_rsp_dat,
    output logic                                tb_rd_rsp_vld,
    input  logic                                tb_wr_vld,
    input  logic [7:0]                          tb_wr_qid,
    input  logic [15:0]                         tb_wr_dat
);

  logic [15:0] data_ram_dina, data_ram_doutb;
  logic [7:0] data_ram_addra, data_ram_addrb;
  logic data_ram_wea;
  logic [1:0] parity_ecc_err;

  assign data_ram_dina = tb_wr_dat;
  assign data_ram_addra = tb_wr_qid;
  assign data_ram_wea = tb_wr_vld;

  assign data_ram_addrb = tb_rd_req_qid;
  assign tb_rd_rsp_dat = data_ram_doutb;
  always @(posedge clk) begin
    if(rst)begin
      tb_rd_rsp_vld <= 1'b0;
    end else begin
      tb_rd_rsp_vld <= tb_rd_req_vld;
    end
  end

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH    (16   ),
        .ADDRA_WIDTH    ( 8   ),
        .DATAB_WIDTH    (16   ),
        .ADDRB_WIDTH    ( 8   ),
        .REG_EN         (0                  ),
        .INIT           (0                  ),
        .ADD_INIT_FILE  (0                  ),
        .RAM_MODE       ("blk"              ),
        .CHECK_ON       (1                  ),
        .CHECK_MODE     ("parity"           )       
    )u_tbl_ram(
        .clk            (clk           ),
        .rst            (rst           ), 
        .dina           (data_ram_dina ),
        .addra          (data_ram_addra),
        .wea            (data_ram_wea  ),
        .addrb          (data_ram_addrb),
        .doutb          (data_ram_doutb),
        .parity_ecc_err (parity_ecc_err)
    );

initial begin
    $fsdbAutoSwitchDumpfile(2000, "top.fsdb", 20);
    $fsdbDumpvars(0, tbl_master_tb, "+all");
    $fsdbDumpMDA();
end
    
 endmodule