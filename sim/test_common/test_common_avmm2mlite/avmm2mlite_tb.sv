/******************************************************************************
 * 文件名称 : avmm2mlite_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/09/12
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  09/12     Joe Jiang   初始化版本
 ******************************************************************************/
`include "mlite_if.svh"
module avmm2mlite_tb #(
  parameter ADDR_WIDTH = 64,
  parameter DATA_WIDTH = 64
)(
    input logic                                 clk,              //! Default clock
    input logic                                 rst,              //! Default reset

    input     logic                             avmm_write,             // Asserted for writes access
    input     logic                             avmm_read,              // Asserted for read access
    input     logic [ADDR_WIDTH-1:0]            avmm_address,              // Target address //avmm_addr[26:24] = bar_num
    input     logic [DATA_WIDTH/8-1:0]          avmm_byteenable,        // Byte enables
    input     logic [DATA_WIDTH-1:0]            avmm_writedata,        // Write data. Valid for writes - little endian format
    output  var logic                           avmm_waitrequest,      // Asserted by slave when it is unable to process request
    output  var logic [DATA_WIDTH-1:0]        avmm_readdata,         // Read data response from slave
    output  var logic                           avmm_readdatavalid,     // Asserted to indicate that avmm_read_data_i contains valid read data

    // Register Bus
    input logic                                 csr_if_ready,
    output  logic                               csr_if_valid,
    output  logic                               csr_if_read,
    output  logic [ADDR_WIDTH-1:0]              csr_if_addr,
    output  logic [DATA_WIDTH-1:0]              csr_if_wdata,
    output  logic [DATA_WIDTH/8-1:0]            csr_if_wmask,
    input logic [DATA_WIDTH-1:0]                csr_if_rdata,
    input logic                                 csr_if_rvalid,
    output  logic                               csr_if_rready
);

initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, avmm2mlite_tb, "+all");
    $fsdbDumpMDA();
end

mlite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) csr_if();

assign csr_if.ready = csr_if_ready;
assign csr_if_valid = csr_if.valid;
assign csr_if_read  = csr_if.read ;
assign csr_if_addr  = csr_if.addr ;
assign csr_if_wdata = csr_if.wdata;
assign csr_if_wmask = csr_if.wmask;

assign csr_if.rdata   = csr_if_rdata;
assign csr_if.rvalid  = csr_if_rvalid;
assign csr_if_rready  = csr_if.rready;

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
  .csr_if            ( csr_if            )
);

endmodule