/***************************************************
* 文件名称 : host_tlp_tracing_tb
* 作者名称 : 崔飞翔
* 创建日期 : 2025/08/27
* 功能描述 : 
* 
* 修改记录 : 
* 
* 修改日期 : 2025/08/27
* 版本号    修改人    修改内容
* v1.0     崔飞翔     初始化版本
***************************************************/
module host_tlp_tracing_tb 
  import alt_tlp_adaptor_pkg::*;
#(
    parameter  DW = 256
)(
    input   logic                                       clk                     ,
    input   logic                                       rst                     ,

    input   logic   [255:0]                             tx_st_data              ,
    input   logic   [1:0]                               tx_st_sop               ,
    input   logic   [1:0]                               tx_st_eop               ,
    input   logic   [1:0]                               tx_st_valid             ,

    input   logic   [$bits(tlp_bypass_hdr_t)-1:0]       tlp_bypass_req_hdr      ,
    input   logic   [7:0]                               tlp_bypass_req_gen      ,
    input   logic                                       tlp_bypass_req_vld      ,
    input   logic                                       tlp_bypass_req_sop      ,
    input   logic                                       tlp_bypass_req_eop      ,
    input   logic   [DW-1:0]                            tlp_bypass_req_data     ,
    output  logic                                       tlp_bypass_req_sav      ,

    output   logic   [$bits(tlp_bypass_hdr_t)-1:0]      tlp_bypass_cpl_hdr      ,
    output   logic   [7:0]                              tlp_bypass_cpl_gen      ,
    output   logic                                      tlp_bypass_cpl_vld      ,
    output   logic                                      tlp_bypass_cpl_sop      ,
    output   logic                                      tlp_bypass_cpl_eop      ,
    output   logic   [DW-1:0]                           tlp_bypass_cpl_data     ,
    input    logic                                      tlp_bypass_cpl_rdy      ,    


    output  logic                                       csr_if_ready            ,
    input   logic                                       csr_if_valid            ,
    input   logic                                       csr_if_read             ,
    input   logic   [31:0]                              csr_if_addr             ,
    input   logic   [63:0]                              csr_if_wdata            ,
    input   logic   [7:0]                               csr_if_wmask            ,
    output  logic   [63:0]                              csr_if_rdata            ,
    output  logic                                       csr_if_rvalid           ,
    input   logic                                       csr_if_rready   
);


initial begin
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 100);
    $fsdbDumpvars(0, host_tlp_tracing_tb, "+all");
    $fsdbDumpMDA();
end


assign tlp_bypass_req_sav = 1'b1;

assign csr_if_ready                = csr_if.ready;
assign csr_if.valid                = csr_if_valid;
assign csr_if.read                 = csr_if_read;
assign csr_if.addr                 = csr_if_addr;
assign csr_if.wdata                = csr_if_wdata;
assign csr_if.wmask                = csr_if_wmask;
assign csr_if_rdata                = csr_if.rdata;
assign csr_if_rvalid               = csr_if.rvalid;
assign csr_if.rready               = csr_if_rready;


mlite_if                #(.DATA_WIDTH(64))    csr_if();


AVST128QW_mppc_t[1:0]	    hip_tlp_tx_mppc; 
tlp_cmd_t                   rx_tlp_cmd     ;


assign hip_tlp_tx_mppc[0].valid = tx_st_valid[0]  ; 
assign hip_tlp_tx_mppc[0].sop   = tx_st_sop[0]    ;
assign hip_tlp_tx_mppc[0].eop   = tx_st_eop[0]    ;
assign hip_tlp_tx_mppc[0].dat  = tx_st_data[127:0]   ;
assign hip_tlp_tx_mppc[0].empty = '0;

assign hip_tlp_tx_mppc[1].valid = tx_st_valid[1]  ; 
assign hip_tlp_tx_mppc[1].sop   = tx_st_sop[1]    ;
assign hip_tlp_tx_mppc[1].eop   = tx_st_eop[1]    ;
assign hip_tlp_tx_mppc[1].dat  = tx_st_data[255:128]   ;
assign hip_tlp_tx_mppc[1].empty = '0;


assign rx_tlp_cmd[$bits(tlp_bypass_hdr_t)-1:0] = tlp_bypass_req_hdr;
assign rx_tlp_cmd.valid = tlp_bypass_req_vld    ; 
assign rx_tlp_cmd.sop   = tlp_bypass_req_sop    ;
assign rx_tlp_cmd.eop   = tlp_bypass_req_eop    ;
assign rx_tlp_cmd.data  = tlp_bypass_req_data   ;

alt_tlp_adaptor_tracing#(
    .REG_ADDR_WIDTH     ( 19 ),
    .REG_DATA_WIDTH     ( 64 )
)u_alt_tlp_adaptor_tracing(
    .clk_i              ( clk                   ),
    .srst_i             ( rst                   ),
    .hip_tlp_tx_mppc_i  ( hip_tlp_tx_mppc       ),
    .rx_tlp_cmd_i       ( rx_tlp_cmd            ),
    .dfx_tracing        ( dfx_tracing           ),
    .csr_if             ( csr_if                )
);

    
endmodule