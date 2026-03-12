/******************************************************************************
 * 文件名称 : sgdma_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/09/24
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  09/24     Joe Jiang   初始化版本
 ******************************************************************************/
`include "tlp_adap_dma_if.svh"

module sgdma_tb
  import alt_tlp_adaptor_pkg::*;
 #(
    parameter DATA_WIDTH        = 256,
    parameter EMPTH_WIDTH       = $clog2(DATA_WIDTH/8),
    parameter REG_ADDR_WIDTH  	= 23   ,   //CSR寄存器的地址位宽
    parameter REG_DATA_WIDTH  	= 64   
) (
    input                           clk                                 ,
    input                           rst                                 ,
    // Write request interface from DMA core
    input      logic                            dma_wr_req_sav          ,// wr_req_val_i must de-assert within 3 cycles after de-assertion of wr_req_rdy_o
    output     logic                            dma_wr_req_val          ,// Request is taken when asserted
    output     logic                            dma_wr_req_sop          ,// Indicates first dataword
    output     logic                            dma_wr_req_eop          ,// Indicates last dataword
    output     logic  [DATA_WIDTH-1:0]          dma_wr_req_data         ,// Data to write to host in big endian format
    output     logic  [EMPTH_WIDTH-1:0]         dma_wr_req_sty          ,// Points to first valid payload byte. Valid when wr_req_sop_i=1
    output     logic  [EMPTH_WIDTH-1:0]         dma_wr_req_mty          ,// Number of unused bytes in last dataword. Valid when wr_req_eop_i=1
    output     logic  [$bits(desc_t)-1:0]       dma_wr_req_desc         ,// Descriptor for write. Valid when wr_req_sop_i=1
    // Write response interface from DMA core
    input  logic [111:0]                        dma_wr_rsp_rd2rsp_loop  ,
    input  logic                                dma_wr_rsp_val          ,
    // Read request interface from DMA core
    input        logic                            dma_rd_req_sav          ,// rd_req_val_i must de-assert within 3 cycles after de-assertion of rd_req_rdy_o
    output       logic                            dma_rd_req_val          ,// Request is taken when asserted
    output       logic  [EMPTH_WIDTH-1:0]         dma_rd_req_sty          ,// Determines where first valid payload byte is placed in rd_rsp_data_o
    output       logic  [$bits(desc_t)-1:0]       dma_rd_req_desc         ,// Descriptor for read
    // Read response interface back to DMA core
    input      logic                            dma_rd_rsp_val          ,// Asserted when response is valid
    input      logic                            dma_rd_rsp_sop          ,// Indicates first dataword
    input      logic                            dma_rd_rsp_eop          ,// Indicates last dataword
    input      logic                            dma_rd_rsp_err          ,// Asserted if completion from host has non-succesfull status or poison bit set
    input      logic  [DATA_WIDTH-1:0]          dma_rd_rsp_data         ,// Response data
    input      logic  [EMPTH_WIDTH-1:0]         dma_rd_rsp_sty          ,// Points to first valid payload byte. Valid when rd_rsp_sop_o=1
    input      logic  [EMPTH_WIDTH-1:0]         dma_rd_rsp_mty          ,// Number of unused bytes in last dataword. Valid when rd_rsp_eop_o=1
    input      logic  [$bits(desc_t)-1:0]       dma_rd_rsp_desc         ,// Descriptor for response. Valid when rd_rsp_sop_o=1

    output                                      beq2sgdma_sav           ,
    input      logic                            beq2sgdma_vld           ,
    input      logic  [DATA_WIDTH-1:0]          beq2sgdma_data          ,
    input      logic  [EMPTH_WIDTH-1:0]         beq2sgdma_sty           ,
    input      logic  [EMPTH_WIDTH-1:0]         beq2sgdma_mty           ,
    input      logic                            beq2sgdma_sop           ,
    input      logic                            beq2sgdma_eop           ,
    input      logic  [$bits(beq_txq_sbd_t)-1:0]beq2sgdma_sbd           ,
    
    input      logic                            sgdma2beq_sav           ,
    output     logic                            sgdma2beq_vld           ,
    output     logic  [DATA_WIDTH-1:0]          sgdma2beq_data          ,
    output     logic  [EMPTH_WIDTH-1:0]         sgdma2beq_sty           ,
    output     logic  [EMPTH_WIDTH-1:0]         sgdma2beq_mty           ,
    output     logic                            sgdma2beq_sop           ,
    output     logic                            sgdma2beq_eop           ,
    output     logic  [$bits(beq_rxq_sbd_t)-1:0]sgdma2beq_sbd           ,

    // Register Bus
    output logic                                csr_if_ready            ,
    input  logic                                csr_if_valid            ,
    input  logic                                csr_if_read             , //1是读 0是写
    input  logic [REG_ADDR_WIDTH-1:0]           csr_if_addr             ,
    input  logic [REG_DATA_WIDTH-1:0]           csr_if_wdata            ,
    input  logic [REG_DATA_WIDTH/8-1:0]         csr_if_wmask            ,
    output logic [REG_DATA_WIDTH-1:0]           csr_if_rdata            ,
    output logic                                csr_if_rvalid           ,
    input  logic                                csr_if_rready
);
// $表示sysverilog仿真系统函数 采集仿真波形用于波形分析调试
// FSBD是VCS仿真器的专用波形格式
// 数字代表从根节点往下采集的层级
initial begin
    $fsdbAutoSwitchDumpfile(600, "top.fsdb", 30); //自动切分超大波形 600表示单个文件最大600MB 30表示最多30个文件
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, sgdma_tb, "+all");// 指定需要采集信号的范围
    $fsdbDumpMDA();// 开启多维数组/存储器的波形采集
end

tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_wr_req_if();
tlp_adap_dma_wr_rsp_if                               dma_wr_rsp_if();
tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_rd_req_if();
tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_rd_rsp_if();

beq_txq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   beq2sgdma_if();
beq_rxq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   sgdma2beq_if();

mlite_if #(.ADDR_WIDTH(REG_ADDR_WIDTH), .DATA_WIDTH(REG_DATA_WIDTH)) csr_if();

assign dma_wr_req_if.sav            = dma_wr_req_sav;
assign dma_wr_req_sop               = dma_wr_req_if.sop;
assign dma_wr_req_eop               = dma_wr_req_if.eop;
assign dma_wr_req_val               = dma_wr_req_if.vld;
assign dma_wr_req_data              = dma_wr_req_if.data;
assign dma_wr_req_sty               = dma_wr_req_if.sty;
assign dma_wr_req_mty               = dma_wr_req_if.mty;
assign dma_wr_req_desc              = dma_wr_req_if.desc;

assign dma_wr_rsp_if.vld            = dma_wr_rsp_val;
assign dma_wr_rsp_if.rd2rsp_loop    = dma_wr_rsp_rd2rsp_loop;

assign dma_rd_req_if.sav            = dma_rd_req_sav;
assign dma_rd_req_val               = dma_rd_req_if.vld;
assign dma_rd_req_sty               = dma_rd_req_if.sty;
assign dma_rd_req_desc              = dma_rd_req_if.desc;

assign dma_rd_rsp_if.vld            = dma_rd_rsp_val;
assign dma_rd_rsp_if.sop            = dma_rd_rsp_sop;
assign dma_rd_rsp_if.eop            = dma_rd_rsp_eop;
assign dma_rd_rsp_if.sty            = dma_rd_rsp_sty;
assign dma_rd_rsp_if.mty            = dma_rd_rsp_mty;
assign dma_rd_rsp_if.data           = dma_rd_rsp_data;
assign dma_rd_rsp_if.err            = dma_rd_rsp_err;
assign dma_rd_rsp_if.desc           = dma_rd_rsp_desc;

assign beq2sgdma_sav                = beq2sgdma_if.sav;
assign beq2sgdma_if.vld             = beq2sgdma_vld;
assign beq2sgdma_if.sop             = beq2sgdma_sop;
assign beq2sgdma_if.eop             = beq2sgdma_eop;
assign beq2sgdma_if.sbd             = beq2sgdma_sbd;
assign beq2sgdma_if.sty             = beq2sgdma_sty;
assign beq2sgdma_if.mty             = beq2sgdma_mty;
assign beq2sgdma_if.data            = beq2sgdma_data;

assign sgdma2beq_if.sav             = sgdma2beq_sav;
assign sgdma2beq_vld                = sgdma2beq_if.vld;
assign sgdma2beq_sop                = sgdma2beq_if.sop;
assign sgdma2beq_eop                = sgdma2beq_if.eop;
assign sgdma2beq_sbd                = sgdma2beq_if.sbd;
assign sgdma2beq_sty                = sgdma2beq_if.sty;
assign sgdma2beq_mty                = sgdma2beq_if.mty;
assign sgdma2beq_data               = sgdma2beq_if.data;

assign csr_if_ready                 = csr_if.ready      ;
assign csr_if.valid                 = csr_if_valid      ;
assign csr_if.read                  = csr_if_read       ;
assign csr_if.addr                  = csr_if_addr       ;
assign csr_if.wdata                 = csr_if_wdata      ;
assign csr_if.wmask                 = csr_if_wmask      ;
assign csr_if_rdata                 = csr_if.rdata      ;
assign csr_if_rvalid                = csr_if.rvalid     ;
assign csr_if.rready                = csr_if_rready     ;

sgdma #(
    .DATA_WIDTH (DATA_WIDTH ),
    .EMPTH_WIDTH(EMPTH_WIDTH)
) u_sgdma (
    .clk            (clk            ),
    .rst            (rst            ),
    .dma_wr_req_if  (dma_wr_req_if  ),
    .dma_wr_rsp_if  (dma_wr_rsp_if  ),
    .dma_rd_req_if  (dma_rd_req_if  ),
    .dma_rd_rsp_if  (dma_rd_rsp_if  ),
    .beq2sgdma_if   (beq2sgdma_if   ),
    .sgdma2beq_if   (sgdma2beq_if   ),
    .csr_if         (csr_if         )
);

endmodule