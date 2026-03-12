/******************************************************************************
 * 文件名称 : mlite_64to32_splitter_tb.sv
 * 作者名称 : matao
 * 创建日期 : 2025/08/19
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   08/19       matao       初始化版本
 ******************************************************************************/
`include "mlite_if.svh"
module mlite_64to32_splitter_tb #(
    parameter ADDR_WIDTH = 64,
    parameter SLAVE_DATA_WIDTH = 64,
    parameter MASTER_DATA_WIDTH = 32
)(
    input logic                                 clk,              //! Default clock
    input logic                                 rst,              //! Default reset

    // Register Bus
    input   logic                               mlite_master_ready  ,
    output  logic                               mlite_master_valid  ,
    output  logic                               mlite_master_read   ,
    output  logic [ADDR_WIDTH-1:0]              mlite_master_addr   ,
    output  logic [MASTER_DATA_WIDTH-1:0]       mlite_master_wdata  ,
    output  logic [MASTER_DATA_WIDTH/8-1:0]     mlite_master_wmask  ,
    input   logic [MASTER_DATA_WIDTH-1:0]       mlite_master_rdata  ,
    input   logic                               mlite_master_rvalid ,
    output  logic                               mlite_master_rready ,

    input   logic                               mlite_slave_valid,
    input   logic                               mlite_slave_read,
    input   logic [ADDR_WIDTH-1:0]              mlite_slave_addr,
    input   logic [SLAVE_DATA_WIDTH-1:0]        mlite_slave_wdata,
    input   logic [SLAVE_DATA_WIDTH/8-1:0]      mlite_slave_wmask,
    input   logic                               mlite_slave_rready,
    output  logic                               mlite_slave_ready,
    output  logic                               mlite_slave_rvalid,
    output  logic [SLAVE_DATA_WIDTH-1:0]        mlite_slave_rdata
);

initial begin
    $fsdbAutoSwitchDumpfile(600, "top.fsdb", 30);
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, mlite_64to32_splitter_tb, "+all");
    $fsdbDumpMDA();
end
mlite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(SLAVE_DATA_WIDTH)) slave_csr_if();
mlite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(MASTER_DATA_WIDTH)) master_csr_if();

assign mlite_slave_ready = slave_csr_if.ready;
assign slave_csr_if.valid = mlite_slave_valid;
assign slave_csr_if.read  = mlite_slave_read ;
assign slave_csr_if.addr  = mlite_slave_addr ;
assign slave_csr_if.wdata = mlite_slave_wdata;
assign slave_csr_if.wmask = mlite_slave_wmask;

assign mlite_slave_rdata   = slave_csr_if.rdata;
assign mlite_slave_rvalid  = slave_csr_if.rvalid;
assign slave_csr_if.rready  = mlite_slave_rready;

assign master_csr_if.ready = mlite_master_ready;
assign mlite_master_valid = master_csr_if.valid;
assign mlite_master_read  = master_csr_if.read ;
assign mlite_master_addr  = master_csr_if.addr ;
assign mlite_master_wdata = master_csr_if.wdata;
assign mlite_master_wmask = master_csr_if.wmask;

assign master_csr_if.rdata   = mlite_master_rdata;
assign master_csr_if.rvalid  = mlite_master_rvalid;
assign mlite_master_rready  = master_csr_if.rready;

mlite_64to32_splitter #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .SLAVE_DATA_WIDTH(SLAVE_DATA_WIDTH),
  .MASTER_DATA_WIDTH(MASTER_DATA_WIDTH)
)u_mlite_64to32_splitter(
  .clk               ( clk               ),
  .rst               ( rst               ),
  .slave_64w         ( slave_csr_if      ),
  .master_32w        ( master_csr_if     )
);

endmodule