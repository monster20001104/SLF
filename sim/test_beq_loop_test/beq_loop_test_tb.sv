/***************************************************
* 文件名称 : loop_test_tb
* 作者名称 : 崔飞翔
* 创建日期 : 2025/01/10
* 功能描述 : 
* 
* 修改记录 : 
* 
* 修改日期 : 2025/01/10
* 版本号    修改人    修改内容
* v1.0     崔飞翔     初始化版本
***************************************************/
`include "beq_data_if.svh"
`include "mlite_if.svh"
module beq_loop_test_tb #(
    parameter DATA_WIDTH = 256,
    parameter REG_DATA_WIDTH = 64,
    parameter REG_ADDR_WIDTH = 32,
    parameter EMPTH_WIDTH   = $clog2(DATA_WIDTH/8)
)(
    input      logic                             clk_i              ,
    input      logic                             rst_i              ,

    output     logic                             csr_if_ready       ,
    input      logic                             csr_if_valid       ,
    input      logic                             csr_if_read        ,
    input      logic  [REG_ADDR_WIDTH-1:0]       csr_if_addr        ,
    input      logic  [REG_DATA_WIDTH-1:0]       csr_if_wdata       ,
    input      logic  [REG_DATA_WIDTH/8-1:0]     csr_if_wmask       ,
    output     logic  [REG_DATA_WIDTH-1:0]       csr_if_rdata       ,
    output     logic                             csr_if_rvalid      ,
    input      logic                             csr_if_rready      ,                              

    output     logic                             beq2loop_sav       ,///loop RX  beq TX
    input      logic                             beq2loop_vld       ,
    input      logic  [DATA_WIDTH-1:0]           beq2loop_data      ,
    input      logic  [EMPTH_WIDTH-1:0]          beq2loop_sty       ,
    input      logic  [EMPTH_WIDTH-1:0]          beq2loop_mty       ,
    input      logic                             beq2loop_sop       ,
    input      logic                             beq2loop_eop       ,
    input      logic  [$bits(beq_txq_sbd_t)-1:0] beq2loop_sbd       ,
    
    input      logic                             loop2beq_sav          ,//loop TX   beq RX
    output     logic                             loop2beq_vld          ,
    output     logic  [DATA_WIDTH-1:0]           loop2beq_data         ,
    output     logic  [EMPTH_WIDTH-1:0]          loop2beq_sty          ,
    output     logic  [EMPTH_WIDTH-1:0]          loop2beq_mty          ,
    output     logic                             loop2beq_sop          ,
    output     logic                             loop2beq_eop          ,
    output     logic  [$bits(beq_rxq_sbd_t)-1:0] loop2beq_sbd          
);

//////////////////////////信号/////////////////////////////
beq_txq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   beq2loop_if();
beq_rxq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   loop2beq_if();
mlite_if                #(.DATA_WIDTH(REG_DATA_WIDTH))    csr_if();

//////////////////////////逻辑/////////////////////////////
initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, beq_loop_test_tb, "+all");
    $fsdbDumpMDA();
end




assign csr_if_ready                = csr_if.ready;
assign csr_if.valid                = csr_if_valid;
assign csr_if.read                 = csr_if_read;
assign csr_if.addr                 = csr_if_addr;
assign csr_if.wdata                = csr_if_wdata;
assign csr_if.wmask                = csr_if_wmask;
assign csr_if_rdata                = csr_if.rdata;
assign csr_if_rvalid               = csr_if.rvalid;
assign csr_if.rready               = csr_if_rready;


assign beq2loop_sav                = beq2loop_if.sav;
assign beq2loop_if.vld             = beq2loop_vld;
assign beq2loop_if.sop             = beq2loop_sop;
assign beq2loop_if.eop             = beq2loop_eop;
assign beq2loop_if.sbd             = beq2loop_sbd;
assign beq2loop_if.sty             = beq2loop_sty;
assign beq2loop_if.mty             = beq2loop_mty;
assign beq2loop_if.data            = beq2loop_data;

assign loop2beq_if.sav             = loop2beq_sav;
assign loop2beq_vld                = loop2beq_if.vld;
assign loop2beq_sop                = loop2beq_if.sop;
assign loop2beq_eop                = loop2beq_if.eop;
assign loop2beq_sbd                = loop2beq_if.sbd;
assign loop2beq_sty                = loop2beq_if.sty;
assign loop2beq_mty                = loop2beq_if.mty;
assign loop2beq_data               = loop2beq_if.data;


//////////////////////////例化/////////////////////////////

beq_loop_test_top#(
    .REG_DATA_WIDTH         ( REG_DATA_WIDTH ),
    .REG_ADDR_WIDTH         ( REG_ADDR_WIDTH ),
    .DATA_WIDTH             ( DATA_WIDTH )
)u0_beq_loop_test_top(
    .clk_i        (clk_i        ),
    .rst_i        (rst_i        ),
    .csr_if       (csr_if       ),
    .beq2loop_if  (beq2loop_if  ),
    .loop2beq_if  (loop2beq_if  )
);


endmodule