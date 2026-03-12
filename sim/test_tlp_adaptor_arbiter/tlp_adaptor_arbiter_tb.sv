/******************************************************************************
 * 文件名称 : tlp_adaptor_arbiter_tb.sv
 * 作者名称 : matao
 * 创建日期 : 2024/12/31
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  12/31       matao       初始化版本
 ******************************************************************************/
`include "beq_data_if.svh"
`include "tlp_adap_dma_if.svh"

module tlp_adaptor_arbiter_tb
  import alt_tlp_adaptor_pkg::*;
 #(
    parameter INTERFACE_NUM_WR  = 8                     ,//定义写输入的接口组数
    parameter INTERFACE_NUM_RD  = 8                     ,
    parameter DATA_WIDTH        = 256                   ,
    parameter EMPTH_WIDTH       = $clog2(DATA_WIDTH/8)  ,
    parameter DWRR_WEIGHT_WID   = 4                     ,
    parameter REG_ADDR_WIDTH    = 20                    ,   
    parameter REG_DATA_WIDTH    = 64   
) (
    input                                       clk                             ,
    input                                       rst                             ,
    // Write request interface from DMA core0   
    output     logic                            slave0_wr_req_sav               ,
    input      logic                            slave0_wr_req_val               ,
    input      logic                            slave0_wr_req_sop               ,
    input      logic                            slave0_wr_req_eop               ,
    input      logic  [DATA_WIDTH-1:0]          slave0_wr_req_data              ,
    input      logic  [EMPTH_WIDTH-1:0]         slave0_wr_req_sty               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave0_wr_req_mty               ,
    input      logic  [$bits(desc_t)-1:0]       slave0_wr_req_desc              ,
    // Write response interface from DMA core0  
    output     logic  [111:0]                   slave0_wr_rsp_rd2rsp_loop       ,
    output     logic                            slave0_wr_rsp_val               ,
    // Read request interface from DMA core0  
    output     logic                            slave0_rd_req_sav               ,
    input      logic                            slave0_rd_req_val               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave0_rd_req_sty               ,
    input      logic  [$bits(desc_t)-1:0]       slave0_rd_req_desc              ,
    // Read response interface back to DMA core0  
    output     logic                            slave0_rd_rsp_val               ,
    output     logic                            slave0_rd_rsp_sop               ,
    output     logic                            slave0_rd_rsp_eop               ,
    output     logic                            slave0_rd_rsp_err               ,
    output     logic  [DATA_WIDTH-1:0]          slave0_rd_rsp_data              ,
    output     logic  [EMPTH_WIDTH-1:0]         slave0_rd_rsp_sty               ,
    output     logic  [EMPTH_WIDTH-1:0]         slave0_rd_rsp_mty               ,
    output     logic  [$bits(desc_t)-1:0]       slave0_rd_rsp_desc              ,
  
    // Write request interface from DMA core0  
    output     logic                            slave1_wr_req_sav               ,
    input      logic                            slave1_wr_req_val               ,
    input      logic                            slave1_wr_req_sop               ,
    input      logic                            slave1_wr_req_eop               ,
    input      logic  [DATA_WIDTH-1:0]          slave1_wr_req_data              ,
    input      logic  [EMPTH_WIDTH-1:0]         slave1_wr_req_sty               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave1_wr_req_mty               ,
    input      logic  [$bits(desc_t)-1:0]       slave1_wr_req_desc              ,
    // Write response interface from DMA core0  
    output     logic  [111:0]                   slave1_wr_rsp_rd2rsp_loop       ,
    output     logic                            slave1_wr_rsp_val               ,
    // Read request interface from DMA core0  
    output     logic                            slave1_rd_req_sav               ,
    input      logic                            slave1_rd_req_val               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave1_rd_req_sty               ,
    input      logic  [$bits(desc_t)-1:0]       slave1_rd_req_desc              ,
    // Read response interface back to DMA core0  
    output     logic                            slave1_rd_rsp_val               ,
    output     logic                            slave1_rd_rsp_sop               ,
    output     logic                            slave1_rd_rsp_eop               ,
    output     logic                            slave1_rd_rsp_err               ,
    output     logic  [DATA_WIDTH-1:0]          slave1_rd_rsp_data              ,
    output     logic  [EMPTH_WIDTH-1:0]         slave1_rd_rsp_sty               ,
    output     logic  [EMPTH_WIDTH-1:0]         slave1_rd_rsp_mty               ,
    output     logic  [$bits(desc_t)-1:0]       slave1_rd_rsp_desc              ,
  
    // Write request interface from DMA core0  
    output     logic                            slave2_wr_req_sav               ,
    input      logic                            slave2_wr_req_val               ,
    input      logic                            slave2_wr_req_sop               ,
    input      logic                            slave2_wr_req_eop               ,
    input      logic  [DATA_WIDTH-1:0]          slave2_wr_req_data              ,
    input      logic  [EMPTH_WIDTH-1:0]         slave2_wr_req_sty               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave2_wr_req_mty               ,
    input      logic  [$bits(desc_t)-1:0]       slave2_wr_req_desc              ,
    // Write response interface from DMA core0  
    output     logic  [111:0]                   slave2_wr_rsp_rd2rsp_loop       ,
    output     logic                            slave2_wr_rsp_val               ,
    // Read request interface from DMA core0  
    output     logic                            slave2_rd_req_sav               ,
    input      logic                            slave2_rd_req_val               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave2_rd_req_sty               ,
    input      logic  [$bits(desc_t)-1:0]       slave2_rd_req_desc              ,
    // Read response interface back to DMA core0  
    output     logic                            slave2_rd_rsp_val               ,
    output     logic                            slave2_rd_rsp_sop               ,
    output     logic                            slave2_rd_rsp_eop               ,
    output     logic                            slave2_rd_rsp_err               ,
    output     logic  [DATA_WIDTH-1:0]          slave2_rd_rsp_data              ,
    output     logic  [EMPTH_WIDTH-1:0]         slave2_rd_rsp_sty               ,
    output     logic  [EMPTH_WIDTH-1:0]         slave2_rd_rsp_mty               ,
    output     logic  [$bits(desc_t)-1:0]       slave2_rd_rsp_desc              ,
      
    // Write request interface from DMA core0  
    output     logic                            slave3_wr_req_sav               ,
    input      logic                            slave3_wr_req_val               ,
    input      logic                            slave3_wr_req_sop               ,
    input      logic                            slave3_wr_req_eop               ,
    input      logic  [DATA_WIDTH-1:0]          slave3_wr_req_data              ,
    input      logic  [EMPTH_WIDTH-1:0]         slave3_wr_req_sty               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave3_wr_req_mty               ,
    input      logic  [$bits(desc_t)-1:0]       slave3_wr_req_desc              ,
    // Write response interface from DMA core0  
    output     logic  [111:0]                   slave3_wr_rsp_rd2rsp_loop       ,
    output     logic                            slave3_wr_rsp_val               ,
    // Read request interface from DMA core0  
    output     logic                            slave3_rd_req_sav               ,
    input      logic                            slave3_rd_req_val               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave3_rd_req_sty               ,
    input      logic  [$bits(desc_t)-1:0]       slave3_rd_req_desc              ,
    // Read response interface back to DMA core0  
    output     logic                            slave3_rd_rsp_val               ,
    output     logic                            slave3_rd_rsp_sop               ,
    output     logic                            slave3_rd_rsp_eop               ,
    output     logic                            slave3_rd_rsp_err               ,
    output     logic  [DATA_WIDTH-1:0]          slave3_rd_rsp_data              ,
    output     logic  [EMPTH_WIDTH-1:0]         slave3_rd_rsp_sty               ,
    output     logic  [EMPTH_WIDTH-1:0]         slave3_rd_rsp_mty               ,
    output     logic  [$bits(desc_t)-1:0]       slave3_rd_rsp_desc              ,

    // Write request interface from DMA core0
    output     logic                            slave4_wr_req_sav               ,
    input      logic                            slave4_wr_req_val               ,
    input      logic                            slave4_wr_req_sop               ,
    input      logic                            slave4_wr_req_eop               ,
    input      logic  [DATA_WIDTH-1:0]          slave4_wr_req_data              ,
    input      logic  [EMPTH_WIDTH-1:0]         slave4_wr_req_sty               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave4_wr_req_mty               ,
    input      logic  [$bits(desc_t)-1:0]       slave4_wr_req_desc              ,
    // Write response interface from DMA core0  
    output     logic  [111:0]                   slave4_wr_rsp_rd2rsp_loop       ,
    output     logic                            slave4_wr_rsp_val               ,
    // Read request interface from DMA core0  
    output     logic                            slave4_rd_req_sav               ,
    input      logic                            slave4_rd_req_val               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave4_rd_req_sty               ,
    input      logic  [$bits(desc_t)-1:0]       slave4_rd_req_desc              ,
    // Read response interface back to DMA core0  
    output     logic                            slave4_rd_rsp_val               ,
    output     logic                            slave4_rd_rsp_sop               ,
    output     logic                            slave4_rd_rsp_eop               ,
    output     logic                            slave4_rd_rsp_err               ,
    output     logic  [DATA_WIDTH-1:0]          slave4_rd_rsp_data              ,
    output     logic  [EMPTH_WIDTH-1:0]         slave4_rd_rsp_sty               ,
    output     logic  [EMPTH_WIDTH-1:0]         slave4_rd_rsp_mty               ,
    output     logic  [$bits(desc_t)-1:0]       slave4_rd_rsp_desc              ,
  
    // Write request interface from DMA core0  
    output     logic                            slave5_wr_req_sav               ,
    input      logic                            slave5_wr_req_val               ,
    input      logic                            slave5_wr_req_sop               ,
    input      logic                            slave5_wr_req_eop               ,
    input      logic  [DATA_WIDTH-1:0]          slave5_wr_req_data              ,
    input      logic  [EMPTH_WIDTH-1:0]         slave5_wr_req_sty               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave5_wr_req_mty               ,
    input      logic  [$bits(desc_t)-1:0]       slave5_wr_req_desc              ,
    // Write response interface from DMA core0  
    output     logic  [111:0]                   slave5_wr_rsp_rd2rsp_loop       ,
    output     logic                            slave5_wr_rsp_val               ,
    // Read request interface from DMA core0  
    output     logic                            slave5_rd_req_sav               ,
    input      logic                            slave5_rd_req_val               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave5_rd_req_sty               ,
    input      logic  [$bits(desc_t)-1:0]       slave5_rd_req_desc              ,
    // Read response interface back to DMA core0  
    output     logic                            slave5_rd_rsp_val               ,
    output     logic                            slave5_rd_rsp_sop               ,
    output     logic                            slave5_rd_rsp_eop               ,
    output     logic                            slave5_rd_rsp_err               ,
    output     logic  [DATA_WIDTH-1:0]          slave5_rd_rsp_data              ,
    output     logic  [EMPTH_WIDTH-1:0]         slave5_rd_rsp_sty               ,
    output     logic  [EMPTH_WIDTH-1:0]         slave5_rd_rsp_mty               ,
    output     logic  [$bits(desc_t)-1:0]       slave5_rd_rsp_desc              ,
  
    // Write request interface from DMA core0  
    output     logic                            slave6_wr_req_sav               ,
    input      logic                            slave6_wr_req_val               ,
    input      logic                            slave6_wr_req_sop               ,
    input      logic                            slave6_wr_req_eop               ,
    input      logic  [DATA_WIDTH-1:0]          slave6_wr_req_data              ,
    input      logic  [EMPTH_WIDTH-1:0]         slave6_wr_req_sty               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave6_wr_req_mty               ,
    input      logic  [$bits(desc_t)-1:0]       slave6_wr_req_desc              ,
    // Write response interface from DMA core0  
    output     logic  [111:0]                   slave6_wr_rsp_rd2rsp_loop       ,
    output     logic                            slave6_wr_rsp_val               ,
    // Read request interface from DMA core0  
    output     logic                            slave6_rd_req_sav               ,
    input      logic                            slave6_rd_req_val               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave6_rd_req_sty               ,
    input      logic  [$bits(desc_t)-1:0]       slave6_rd_req_desc              ,
    // Read response interface back to DMA core0  
    output     logic                            slave6_rd_rsp_val               ,
    output     logic                            slave6_rd_rsp_sop               ,
    output     logic                            slave6_rd_rsp_eop               ,
    output     logic                            slave6_rd_rsp_err               ,
    output     logic  [DATA_WIDTH-1:0]          slave6_rd_rsp_data              ,
    output     logic  [EMPTH_WIDTH-1:0]         slave6_rd_rsp_sty               ,
    output     logic  [EMPTH_WIDTH-1:0]         slave6_rd_rsp_mty               ,
    output     logic  [$bits(desc_t)-1:0]       slave6_rd_rsp_desc              ,
      
    // Write request interface from DMA core0  
    output     logic                            slave7_wr_req_sav               ,
    input      logic                            slave7_wr_req_val               ,
    input      logic                            slave7_wr_req_sop               ,
    input      logic                            slave7_wr_req_eop               ,
    input      logic  [DATA_WIDTH-1:0]          slave7_wr_req_data              ,
    input      logic  [EMPTH_WIDTH-1:0]         slave7_wr_req_sty               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave7_wr_req_mty               ,
    input      logic  [$bits(desc_t)-1:0]       slave7_wr_req_desc              ,
    // Write response interface from DMA core0  
    output     logic  [111:0]                   slave7_wr_rsp_rd2rsp_loop       ,
    output     logic                            slave7_wr_rsp_val               ,
    // Read request interface from DMA core0  
    output     logic                            slave7_rd_req_sav               ,
    input      logic                            slave7_rd_req_val               ,
    input      logic  [EMPTH_WIDTH-1:0]         slave7_rd_req_sty               ,
    input      logic  [$bits(desc_t)-1:0]       slave7_rd_req_desc              ,
    // Read response interface back to DMA core0  
    output     logic                            slave7_rd_rsp_val               ,
    output     logic                            slave7_rd_rsp_sop               ,
    output     logic                            slave7_rd_rsp_eop               ,
    output     logic                            slave7_rd_rsp_err               ,
    output     logic  [DATA_WIDTH-1:0]          slave7_rd_rsp_data              ,
    output     logic  [EMPTH_WIDTH-1:0]         slave7_rd_rsp_sty               ,
    output     logic  [EMPTH_WIDTH-1:0]         slave7_rd_rsp_mty               ,
    output     logic  [$bits(desc_t)-1:0]       slave7_rd_rsp_desc              ,

    //slave wr req
    input      logic                            master_wr_req_sav               ,
    output     logic                            master_wr_req_val               ,
    output     logic                            master_wr_req_sop               ,
    output     logic                            master_wr_req_eop               ,
    output     logic  [DATA_WIDTH-1:0]          master_wr_req_data              ,
    output     logic  [EMPTH_WIDTH-1:0]         master_wr_req_sty               ,
    output     logic  [EMPTH_WIDTH-1:0]         master_wr_req_mty               ,
    output     logic  [$bits(desc_t)-1:0]       master_wr_req_desc              ,
    //slave wr rsp
    input      logic  [111:0]                   master_wr_rsp_rd2rsp_loop       ,
    input      logic                            master_wr_rsp_val               ,
    //slave rd req
    input      logic                            master_rd_req_sav               ,
    output     logic                            master_rd_req_val               ,
    output     logic  [EMPTH_WIDTH-1:0]         master_rd_req_sty               ,
    output     logic  [$bits(desc_t)-1:0]       master_rd_req_desc              ,
    // slave rd rsp
    input      logic                            master_rd_rsp_val               ,
    input      logic                            master_rd_rsp_sop               ,
    input      logic                            master_rd_rsp_eop               ,
    input      logic                            master_rd_rsp_err               ,
    input      logic  [DATA_WIDTH-1:0]          master_rd_rsp_data              ,
    input      logic  [EMPTH_WIDTH-1:0]         master_rd_rsp_sty               ,
    input      logic  [EMPTH_WIDTH-1:0]         master_rd_rsp_mty               ,
    input      logic  [$bits(desc_t)-1:0]       master_rd_rsp_desc              ,

    // Register Bus
    output logic                                csr_if_ready                    ,
    input  logic                                csr_if_valid                    ,
    input  logic                                csr_if_read                     ,
    input  logic [REG_ADDR_WIDTH-1:0]           csr_if_addr                     ,
    input  logic [REG_DATA_WIDTH-1:0]           csr_if_wdata                    ,
    input  logic [REG_DATA_WIDTH/8-1:0]         csr_if_wmask                    ,
    output logic [REG_DATA_WIDTH-1:0]           csr_if_rdata                    ,
    output logic                                csr_if_rvalid                   ,
    input  logic                                csr_if_rready
);


initial begin
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, tlp_adaptor_arbiter_tb, "+all");
    $fsdbDumpMDA();
end

mlite_if #(.ADDR_WIDTH(REG_ADDR_WIDTH), .DATA_WIDTH(REG_DATA_WIDTH)) csr_if();

//sgdma2tlp_adaptor_arbiter             
tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))    slave_wr_req_if[INTERFACE_NUM_WR-1:0]()    ;
tlp_adap_dma_wr_rsp_if                                slave_wr_rsp_if[INTERFACE_NUM_WR-1:0]()    ;
tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))    slave_rd_req_if[INTERFACE_NUM_RD-1:0]()    ;
tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))    slave_rd_rsp_if[INTERFACE_NUM_RD-1:0]()    ;
//tlp_adaptor_arbiter2pcie              
tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))    master_wr_req_if()                         ;
tlp_adap_dma_wr_rsp_if                                master_wr_rsp_if()                         ;
tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))    master_rd_req_if()                         ;
tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))    master_rd_rsp_if()                         ;

logic [INTERFACE_NUM_RD-1:0]      rd_chn_shaping_en ;

assign master_wr_req_if.sav            = master_wr_req_sav              ;
assign master_wr_req_sop               = master_wr_req_if.sop           ;
assign master_wr_req_eop               = master_wr_req_if.eop           ;
assign master_wr_req_val               = master_wr_req_if.vld           ;
assign master_wr_req_data              = master_wr_req_if.data          ;
assign master_wr_req_sty               = master_wr_req_if.sty           ;
assign master_wr_req_mty               = master_wr_req_if.mty           ;
assign master_wr_req_desc              = master_wr_req_if.desc          ;

assign master_wr_rsp_if.vld            = master_wr_rsp_val              ;
assign master_wr_rsp_if.rd2rsp_loop    = master_wr_rsp_rd2rsp_loop      ;

assign master_rd_req_if.sav            = master_rd_req_sav              ;
assign master_rd_req_val               = master_rd_req_if.vld           ;
assign master_rd_req_sty               = master_rd_req_if.sty           ;
assign master_rd_req_desc              = master_rd_req_if.desc          ;

assign master_rd_rsp_if.vld            = master_rd_rsp_val              ;
assign master_rd_rsp_if.sop            = master_rd_rsp_sop              ;
assign master_rd_rsp_if.eop            = master_rd_rsp_eop              ;
assign master_rd_rsp_if.sty            = master_rd_rsp_sty              ;
assign master_rd_rsp_if.mty            = master_rd_rsp_mty              ;
assign master_rd_rsp_if.data           = master_rd_rsp_data             ;
assign master_rd_rsp_if.err            = master_rd_rsp_err              ;
assign master_rd_rsp_if.desc           = master_rd_rsp_desc             ;

//slave0
assign slave0_wr_req_sav               = slave_wr_req_if[0].sav         ;
assign slave_wr_req_if[0].sop          = slave0_wr_req_sop              ;
assign slave_wr_req_if[0].eop          = slave0_wr_req_eop              ;
assign slave_wr_req_if[0].vld          = slave0_wr_req_val              ;
assign slave_wr_req_if[0].data         = slave0_wr_req_data             ;
assign slave_wr_req_if[0].sty          = slave0_wr_req_sty              ;
assign slave_wr_req_if[0].mty          = slave0_wr_req_mty              ;
assign slave_wr_req_if[0].desc         = slave0_wr_req_desc             ;

assign slave0_wr_rsp_val               = slave_wr_rsp_if[0].vld         ;
assign slave0_wr_rsp_rd2rsp_loop       = slave_wr_rsp_if[0].rd2rsp_loop ;

assign slave0_rd_req_sav               = slave_rd_req_if[0].sav         ;
assign slave_rd_req_if[0].vld          = slave0_rd_req_val              ;
assign slave_rd_req_if[0].sty          = slave0_rd_req_sty              ;
assign slave_rd_req_if[0].desc         = slave0_rd_req_desc             ;

assign slave0_rd_rsp_val               = slave_rd_rsp_if[0].vld         ;
assign slave0_rd_rsp_sop               = slave_rd_rsp_if[0].sop         ;
assign slave0_rd_rsp_eop               = slave_rd_rsp_if[0].eop         ;
assign slave0_rd_rsp_sty               = slave_rd_rsp_if[0].sty         ;
assign slave0_rd_rsp_mty               = slave_rd_rsp_if[0].mty         ;
assign slave0_rd_rsp_data              = slave_rd_rsp_if[0].data        ;
assign slave0_rd_rsp_err               = slave_rd_rsp_if[0].err         ;
assign slave0_rd_rsp_desc              = slave_rd_rsp_if[0].desc        ;

//slave1
assign slave1_wr_req_sav               = slave_wr_req_if[1].sav         ;
assign slave_wr_req_if[1].sop          = slave1_wr_req_sop              ;
assign slave_wr_req_if[1].eop          = slave1_wr_req_eop              ;
assign slave_wr_req_if[1].vld          = slave1_wr_req_val              ;
assign slave_wr_req_if[1].data         = slave1_wr_req_data             ;
assign slave_wr_req_if[1].sty          = slave1_wr_req_sty              ;
assign slave_wr_req_if[1].mty          = slave1_wr_req_mty              ;
assign slave_wr_req_if[1].desc         = slave1_wr_req_desc             ;

assign slave1_wr_rsp_val               = slave_wr_rsp_if[1].vld         ;
assign slave1_wr_rsp_rd2rsp_loop       = slave_wr_rsp_if[1].rd2rsp_loop ;

assign slave1_rd_req_sav               = slave_rd_req_if[1].sav         ;
assign slave_rd_req_if[1].vld          = slave1_rd_req_val              ;
assign slave_rd_req_if[1].sty          = slave1_rd_req_sty              ;
assign slave_rd_req_if[1].desc         = slave1_rd_req_desc             ;

assign slave1_rd_rsp_val               = slave_rd_rsp_if[1].vld         ;
assign slave1_rd_rsp_sop               = slave_rd_rsp_if[1].sop         ;
assign slave1_rd_rsp_eop               = slave_rd_rsp_if[1].eop         ;
assign slave1_rd_rsp_sty               = slave_rd_rsp_if[1].sty         ;
assign slave1_rd_rsp_mty               = slave_rd_rsp_if[1].mty         ;
assign slave1_rd_rsp_data              = slave_rd_rsp_if[1].data        ;
assign slave1_rd_rsp_err               = slave_rd_rsp_if[1].err         ;
assign slave1_rd_rsp_desc              = slave_rd_rsp_if[1].desc        ;

//slave2
assign slave2_wr_req_sav               = slave_wr_req_if[2].sav         ;
assign slave_wr_req_if[2].sop          = slave2_wr_req_sop              ;
assign slave_wr_req_if[2].eop          = slave2_wr_req_eop              ;
assign slave_wr_req_if[2].vld          = slave2_wr_req_val              ;
assign slave_wr_req_if[2].data         = slave2_wr_req_data             ;
assign slave_wr_req_if[2].sty          = slave2_wr_req_sty              ;
assign slave_wr_req_if[2].mty          = slave2_wr_req_mty              ;
assign slave_wr_req_if[2].desc         = slave2_wr_req_desc             ;

assign slave2_wr_rsp_val               = slave_wr_rsp_if[2].vld         ;
assign slave2_wr_rsp_rd2rsp_loop       = slave_wr_rsp_if[2].rd2rsp_loop ;

assign slave2_rd_req_sav               = slave_rd_req_if[2].sav         ;
assign slave_rd_req_if[2].vld          = slave2_rd_req_val              ;
assign slave_rd_req_if[2].sty          = slave2_rd_req_sty              ;
assign slave_rd_req_if[2].desc         = slave2_rd_req_desc             ;

assign slave2_rd_rsp_val               = slave_rd_rsp_if[2].vld         ;
assign slave2_rd_rsp_sop               = slave_rd_rsp_if[2].sop         ;
assign slave2_rd_rsp_eop               = slave_rd_rsp_if[2].eop         ;
assign slave2_rd_rsp_sty               = slave_rd_rsp_if[2].sty         ;
assign slave2_rd_rsp_mty               = slave_rd_rsp_if[2].mty         ;
assign slave2_rd_rsp_data              = slave_rd_rsp_if[2].data        ;
assign slave2_rd_rsp_err               = slave_rd_rsp_if[2].err         ;
assign slave2_rd_rsp_desc              = slave_rd_rsp_if[2].desc        ;

//slave3
assign slave3_wr_req_sav               = slave_wr_req_if[3].sav         ;
assign slave_wr_req_if[3].sop          = slave3_wr_req_sop              ;
assign slave_wr_req_if[3].eop          = slave3_wr_req_eop              ;
assign slave_wr_req_if[3].vld          = slave3_wr_req_val              ;
assign slave_wr_req_if[3].data         = slave3_wr_req_data             ;
assign slave_wr_req_if[3].sty          = slave3_wr_req_sty              ;
assign slave_wr_req_if[3].mty          = slave3_wr_req_mty              ;
assign slave_wr_req_if[3].desc         = slave3_wr_req_desc             ;

assign slave3_wr_rsp_val               = slave_wr_rsp_if[3].vld         ;
assign slave3_wr_rsp_rd2rsp_loop       = slave_wr_rsp_if[3].rd2rsp_loop ;

assign slave3_rd_req_sav               = slave_rd_req_if[3].sav         ;
assign slave_rd_req_if[3].vld          = slave3_rd_req_val              ;
assign slave_rd_req_if[3].sty          = slave3_rd_req_sty              ;
assign slave_rd_req_if[3].desc         = slave3_rd_req_desc             ;

assign slave3_rd_rsp_val               = slave_rd_rsp_if[3].vld         ;
assign slave3_rd_rsp_sop               = slave_rd_rsp_if[3].sop         ;
assign slave3_rd_rsp_eop               = slave_rd_rsp_if[3].eop         ;
assign slave3_rd_rsp_sty               = slave_rd_rsp_if[3].sty         ;
assign slave3_rd_rsp_mty               = slave_rd_rsp_if[3].mty         ;
assign slave3_rd_rsp_data              = slave_rd_rsp_if[3].data        ;
assign slave3_rd_rsp_err               = slave_rd_rsp_if[3].err         ;
assign slave3_rd_rsp_desc              = slave_rd_rsp_if[3].desc        ;

//slave4
assign slave4_wr_req_sav               = slave_wr_req_if[4].sav         ;
assign slave_wr_req_if[4].sop          = slave4_wr_req_sop              ;
assign slave_wr_req_if[4].eop          = slave4_wr_req_eop              ;
assign slave_wr_req_if[4].vld          = slave4_wr_req_val              ;
assign slave_wr_req_if[4].data         = slave4_wr_req_data             ;
assign slave_wr_req_if[4].sty          = slave4_wr_req_sty              ;
assign slave_wr_req_if[4].mty          = slave4_wr_req_mty              ;
assign slave_wr_req_if[4].desc         = slave4_wr_req_desc             ;

assign slave4_wr_rsp_val               = slave_wr_rsp_if[4].vld         ;
assign slave4_wr_rsp_rd2rsp_loop       = slave_wr_rsp_if[4].rd2rsp_loop ;

assign slave4_rd_req_sav               = slave_rd_req_if[4].sav         ;
assign slave_rd_req_if[4].vld          = slave4_rd_req_val              ;
assign slave_rd_req_if[4].sty          = slave4_rd_req_sty              ;
assign slave_rd_req_if[4].desc         = slave4_rd_req_desc             ;

assign slave4_rd_rsp_val               = slave_rd_rsp_if[4].vld         ;
assign slave4_rd_rsp_sop               = slave_rd_rsp_if[4].sop         ;
assign slave4_rd_rsp_eop               = slave_rd_rsp_if[4].eop         ;
assign slave4_rd_rsp_sty               = slave_rd_rsp_if[4].sty         ;
assign slave4_rd_rsp_mty               = slave_rd_rsp_if[4].mty         ;
assign slave4_rd_rsp_data              = slave_rd_rsp_if[4].data        ;
assign slave4_rd_rsp_err               = slave_rd_rsp_if[4].err         ;
assign slave4_rd_rsp_desc              = slave_rd_rsp_if[4].desc        ;

//slave5
assign slave5_wr_req_sav               = slave_wr_req_if[5].sav         ;
assign slave_wr_req_if[5].sop          = slave5_wr_req_sop              ;
assign slave_wr_req_if[5].eop          = slave5_wr_req_eop              ;
assign slave_wr_req_if[5].vld          = slave5_wr_req_val              ;
assign slave_wr_req_if[5].data         = slave5_wr_req_data             ;
assign slave_wr_req_if[5].sty          = slave5_wr_req_sty              ;
assign slave_wr_req_if[5].mty          = slave5_wr_req_mty              ;
assign slave_wr_req_if[5].desc         = slave5_wr_req_desc             ;

assign slave5_wr_rsp_val               = slave_wr_rsp_if[5].vld         ;
assign slave5_wr_rsp_rd2rsp_loop       = slave_wr_rsp_if[5].rd2rsp_loop ;

assign slave5_rd_req_sav               = slave_rd_req_if[5].sav         ;
assign slave_rd_req_if[5].vld          = slave5_rd_req_val              ;
assign slave_rd_req_if[5].sty          = slave5_rd_req_sty              ;
assign slave_rd_req_if[5].desc         = slave5_rd_req_desc             ;

assign slave5_rd_rsp_val               = slave_rd_rsp_if[5].vld         ;
assign slave5_rd_rsp_sop               = slave_rd_rsp_if[5].sop         ;
assign slave5_rd_rsp_eop               = slave_rd_rsp_if[5].eop         ;
assign slave5_rd_rsp_sty               = slave_rd_rsp_if[5].sty         ;
assign slave5_rd_rsp_mty               = slave_rd_rsp_if[5].mty         ;
assign slave5_rd_rsp_data              = slave_rd_rsp_if[5].data        ;
assign slave5_rd_rsp_err               = slave_rd_rsp_if[5].err         ;
assign slave5_rd_rsp_desc              = slave_rd_rsp_if[5].desc        ;

//slave6
assign slave6_wr_req_sav               = slave_wr_req_if[6].sav         ;
assign slave_wr_req_if[6].sop          = slave6_wr_req_sop              ;
assign slave_wr_req_if[6].eop          = slave6_wr_req_eop              ;
assign slave_wr_req_if[6].vld          = slave6_wr_req_val              ;
assign slave_wr_req_if[6].data         = slave6_wr_req_data             ;
assign slave_wr_req_if[6].sty          = slave6_wr_req_sty              ;
assign slave_wr_req_if[6].mty          = slave6_wr_req_mty              ;
assign slave_wr_req_if[6].desc         = slave6_wr_req_desc             ;

assign slave6_wr_rsp_val               = slave_wr_rsp_if[6].vld         ;
assign slave6_wr_rsp_rd2rsp_loop       = slave_wr_rsp_if[6].rd2rsp_loop ;

assign slave6_rd_req_sav               = slave_rd_req_if[6].sav         ;
assign slave_rd_req_if[6].vld          = slave6_rd_req_val              ;
assign slave_rd_req_if[6].sty          = slave6_rd_req_sty              ;
assign slave_rd_req_if[6].desc         = slave6_rd_req_desc             ;

assign slave6_rd_rsp_val               = slave_rd_rsp_if[6].vld         ;
assign slave6_rd_rsp_sop               = slave_rd_rsp_if[6].sop         ;
assign slave6_rd_rsp_eop               = slave_rd_rsp_if[6].eop         ;
assign slave6_rd_rsp_sty               = slave_rd_rsp_if[6].sty         ;
assign slave6_rd_rsp_mty               = slave_rd_rsp_if[6].mty         ;
assign slave6_rd_rsp_data              = slave_rd_rsp_if[6].data        ;
assign slave6_rd_rsp_err               = slave_rd_rsp_if[6].err         ;
assign slave6_rd_rsp_desc              = slave_rd_rsp_if[6].desc        ;

//slave7
assign slave7_wr_req_sav               = slave_wr_req_if[7].sav         ;
assign slave_wr_req_if[7].sop          = slave7_wr_req_sop              ;
assign slave_wr_req_if[7].eop          = slave7_wr_req_eop              ;
assign slave_wr_req_if[7].vld          = slave7_wr_req_val              ;
assign slave_wr_req_if[7].data         = slave7_wr_req_data             ;
assign slave_wr_req_if[7].sty          = slave7_wr_req_sty              ;
assign slave_wr_req_if[7].mty          = slave7_wr_req_mty              ;
assign slave_wr_req_if[7].desc         = slave7_wr_req_desc             ;

assign slave7_wr_rsp_val               = slave_wr_rsp_if[7].vld         ;
assign slave7_wr_rsp_rd2rsp_loop       = slave_wr_rsp_if[7].rd2rsp_loop ;

assign slave7_rd_req_sav               = slave_rd_req_if[7].sav         ;
assign slave_rd_req_if[7].vld          = slave7_rd_req_val              ;
assign slave_rd_req_if[7].sty          = slave7_rd_req_sty              ;
assign slave_rd_req_if[7].desc         = slave7_rd_req_desc             ;

assign slave7_rd_rsp_val               = slave_rd_rsp_if[7].vld         ;
assign slave7_rd_rsp_sop               = slave_rd_rsp_if[7].sop         ;
assign slave7_rd_rsp_eop               = slave_rd_rsp_if[7].eop         ;
assign slave7_rd_rsp_sty               = slave_rd_rsp_if[7].sty         ;
assign slave7_rd_rsp_mty               = slave_rd_rsp_if[7].mty         ;
assign slave7_rd_rsp_data              = slave_rd_rsp_if[7].data        ;
assign slave7_rd_rsp_err               = slave_rd_rsp_if[7].err         ;
assign slave7_rd_rsp_desc              = slave_rd_rsp_if[7].desc        ;

assign csr_if_ready                    = csr_if.ready                   ;
assign csr_if.valid                    = csr_if_valid                   ;
assign csr_if.read                     = csr_if_read                    ;
assign csr_if.addr                     = csr_if_addr                    ;
assign csr_if.wdata                    = csr_if_wdata                   ;
assign csr_if.wmask                    = csr_if_wmask                   ;
assign csr_if_rdata                    = csr_if.rdata                   ;
assign csr_if_rvalid                   = csr_if.rvalid                  ;
assign csr_if.rready                   = csr_if_rready                  ;

tlp_adaptor_arbiter #(
    .INTERFACE_NUM_WR   (INTERFACE_NUM_WR   ),
    .INTERFACE_NUM_RD   (INTERFACE_NUM_RD   ),
    .DATA_WIDTH         (DATA_WIDTH         ),
    .EMPTH_WIDTH        (EMPTH_WIDTH        ),
    .DWRR_WEIGHT_WID    (DWRR_WEIGHT_WID    ),
    .REG_ADDR_WIDTH     (REG_ADDR_WIDTH     ),
    .REG_DATA_WIDTH     (REG_DATA_WIDTH     )
) u_tlp_adaptor_arbiter (
    .clk                    (clk                    ),        
    .rst                    (rst                    ),        
    .master_wr_req_if       (master_wr_req_if       ),    
    .master_wr_rsp_if       (master_wr_rsp_if       ),    
    .master_rd_req_if       (master_rd_req_if       ),    
    .master_rd_rsp_if       (master_rd_rsp_if       ),    
    .slave_wr_req_if        (slave_wr_req_if        ),        
    .slave_wr_rsp_if        (slave_wr_rsp_if        ),        
    .slave_rd_req_if        (slave_rd_req_if        ),        
    .slave_rd_rsp_if        (slave_rd_rsp_if        ),        
    .rd_chn_shaping_en      (rd_chn_shaping_en      ),
    .csr_if                 (csr_if                 )    
);

endmodule