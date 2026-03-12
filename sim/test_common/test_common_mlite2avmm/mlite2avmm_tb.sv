/******************************************************************************
 * 文件名称 : mlite2avmm_tb.sv
 * 作者名称 : matao
 * 创建日期 : 2025/08/20
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   08/20       matao       初始化版本
 ******************************************************************************/
`include "mlite_if.svh"
module mlite2avmm_tb #(
  parameter ADDR_WIDTH = 64,
  parameter DATA_WIDTH = 64
)(
    input  logic                                clk,              //! Default clock
    input  logic                                rst,              //! Default reset

    // Register Bus
    input   logic                               mlite_master_ready  ,
    output  logic                               mlite_master_valid  ,
    output  logic                               mlite_master_read   ,
    output  logic [ADDR_WIDTH-1:0]              mlite_master_addr   ,
    output  logic [DATA_WIDTH-1:0]              mlite_master_wdata  ,
    output  logic [DATA_WIDTH/8-1:0]            mlite_master_wmask  ,
    input   logic [DATA_WIDTH-1:0]              mlite_master_rdata  ,
    input   logic                               mlite_master_rvalid ,
    output  logic                               mlite_master_rready ,

    input   logic                               mlite_slave_valid,
    input   logic                               mlite_slave_read,
    input   logic [ADDR_WIDTH-1:0]              mlite_slave_addr,
    input   logic [DATA_WIDTH-1:0]              mlite_slave_wdata,
    input   logic [DATA_WIDTH/8-1:0]            mlite_slave_wmask,
    input   logic                               mlite_slave_rready,
    output  logic                               mlite_slave_ready,
    output  logic                               mlite_slave_rvalid,
    output  logic [DATA_WIDTH-1:0]              mlite_slave_rdata
);

initial begin
    $fsdbAutoSwitchDumpfile(600, "top.fsdb", 30);
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, mlite2avmm_tb, "+all");
    $fsdbDumpMDA();
end

mlite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) mlite_master();
mlite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) mlite_slave();

logic                           avmm_write        ;
logic                           avmm_read         ;
logic [ADDR_WIDTH-1:0]          avmm_address      ;
logic [DATA_WIDTH/8-1:0]        avmm_byteenable   ;
logic [DATA_WIDTH-1:0]          avmm_writedata    ;
logic                           avmm_waitrequest  ;
logic [DATA_WIDTH-1:0]          avmm_readdata     ;
logic                           avmm_readdatavalid;


assign mlite_slave_ready = mlite_slave.ready;
assign mlite_slave.valid = mlite_slave_valid;
assign mlite_slave.read  = mlite_slave_read ;
assign mlite_slave.addr  = mlite_slave_addr ;
assign mlite_slave.wdata = mlite_slave_wdata;
assign mlite_slave.wmask = mlite_slave_wmask;

assign mlite_slave_rdata   = mlite_slave.rdata;
assign mlite_slave_rvalid  = mlite_slave.rvalid;
assign mlite_slave.rready  = mlite_slave_rready;

assign mlite_master.ready = mlite_master_ready;
assign mlite_master_valid = mlite_master.valid;
assign mlite_master_read  = mlite_master.read ;
assign mlite_master_addr  = mlite_master.addr ;
assign mlite_master_wdata = mlite_master.wdata;
assign mlite_master_wmask = mlite_master.wmask;

assign mlite_master.rdata   = mlite_master_rdata;
assign mlite_master.rvalid  = mlite_master_rvalid;
assign mlite_master_rready  = mlite_master.rready;


mlite2avmm #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH)
)u_mlite2avmm(
  .clk               ( clk               ),
  .rst               ( rst               ),
  .avmm_write        ( avmm_write        ),
  .avmm_read         ( avmm_read         ),
  .avmm_address      ( avmm_address      ),
  .avmm_byteenable   ( avmm_byteenable   ),
  .avmm_writedata    ( avmm_writedata    ),
  .avmm_waitrequest  ( avmm_waitrequest  ),
  .avmm_readdata     ( avmm_readdata     ),
  .avmm_readdatavalid( avmm_readdatavalid),
  .csr_if            ( mlite_slave       )
);


avmm2mlite #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH)
)u_avmm2mlite(
  .clk               ( clk               ),
  .rst               ( rst               ),
  .avmm_write        ( avmm_write        ),
  .avmm_read         ( avmm_read         ),
  .avmm_address      ( avmm_address      ),
  .avmm_byteenable   ( avmm_byteenable   ),
  .avmm_writedata    ( avmm_writedata    ),
  .avmm_waitrequest  ( avmm_waitrequest  ),
  .avmm_readdata     ( avmm_readdata     ),
  .avmm_readdatavalid( avmm_readdatavalid),
  .csr_if            ( mlite_master      )
);
endmodule