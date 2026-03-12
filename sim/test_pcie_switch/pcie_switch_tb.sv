/***************************************************
* 文件名称 : pcie_switch_tb
* 作者名称 : 崔飞翔
* 创建日期 : 2025/02/18
* 功能描述 : 
* 
* 修改记录 : 
* 
* 修改日期 : 2025/02/18
* 版本号    修改人    修改内容
* v1.0     崔飞翔     初始化版本
***************************************************/
`include "mlite_if.svh"
`include "pcie_switch_define.svh"
module pcie_switch_tb 
    import alt_tlp_adaptor_pkg::*;
#(
    parameter DATA_WIDTH = 256,
    parameter REG_DATA_WIDTH = 64,
    parameter REG_ADDR_WIDTH = 32
)(
    input  logic                             clk                        ,
    input  logic                             rst                        ,
    input  logic                             linkdown                   ,

    input  logic                             hardip_clk                 ,
    input  logic                             hardip_rst                 ,

	output logic 							 event_vld  				,//switch2emu event
	output logic  [7:0]						 event_data 				,
	input  logic  							 event_rdy  			    ,

	input  [$bits(tlp_bypass_hdr_t)-1:0]     host2switch_tlp_bypass_req_hdr       ,//host2switch req
    input  logic  [7:0]                      host2switch_tlp_bypass_req_gen       ,
    input  logic                             host2switch_tlp_bypass_req_sop       ,
    input  logic                             host2switch_tlp_bypass_req_eop       ,
    input  logic  [DATA_WIDTH-1:0]           host2switch_tlp_bypass_req_data      ,
    input  logic                             host2switch_tlp_bypass_req_vld       ,
    output logic                             host2switch_tlp_bypass_req_sav		  ,

	output [$bits(tlp_bypass_hdr_t)-1:0]     switch2emu_tlp_bypass_req_hdr        ,//switch2emu req
    output logic  [7:0]                      switch2emu_tlp_bypass_req_gen        ,
    output logic                             switch2emu_tlp_bypass_req_sop        ,
    output logic                             switch2emu_tlp_bypass_req_eop        ,
    output logic  [DATA_WIDTH-1:0]           switch2emu_tlp_bypass_req_data       ,
    output logic                             switch2emu_tlp_bypass_req_vld        ,
    input  logic                             switch2emu_tlp_bypass_req_sav		  ,

	output [$bits(tlp_bypass_hdr_t)-1:0]     host2switch_tlp_bypass_cpl_hdr       ,//host2switch cpl
    output logic  [7:0]                      host2switch_tlp_bypass_cpl_gen       ,
    output logic                             host2switch_tlp_bypass_cpl_sop       ,
    output logic                             host2switch_tlp_bypass_cpl_eop       ,
    output logic  [DATA_WIDTH-1:0]           host2switch_tlp_bypass_cpl_data      ,
    output logic                             host2switch_tlp_bypass_cpl_vld       ,
    input  logic                             host2switch_tlp_bypass_cpl_rdy		  ,

	input  [$bits(tlp_bypass_hdr_t)-1:0]     switch2emu_tlp_bypass_cpl_hdr        ,//switch2emu cpl
    input  logic  [7:0]                      switch2emu_tlp_bypass_cpl_gen        ,
    input  logic                             switch2emu_tlp_bypass_cpl_sop        ,
    input  logic                             switch2emu_tlp_bypass_cpl_eop        ,
    input  logic  [DATA_WIDTH-1:0]           switch2emu_tlp_bypass_cpl_data       ,
    input  logic                             switch2emu_tlp_bypass_cpl_vld        ,
    output logic                             switch2emu_tlp_bypass_cpl_rdy		  ,

    output logic                             csr_if_ready               ,
    input  logic                             csr_if_valid               ,
    input  logic                             csr_if_read                ,
    input  logic  [REG_ADDR_WIDTH-1:0]       csr_if_addr                ,
    input  logic  [REG_DATA_WIDTH-1:0]       csr_if_wdata               ,
    input  logic  [REG_DATA_WIDTH/8-1:0]     csr_if_wmask               ,
    output logic  [REG_DATA_WIDTH-1:0]       csr_if_rdata               ,
    output logic                             csr_if_rvalid              ,
    input  logic                             csr_if_rready              ,

    input  logic  [3:0]                      current_ls                 ,
    input  logic  [5:0]                      negotiated_lw              ,

    output logic [12:0]                      link2csr                   ,
    output logic                             comclk_reg                 ,
    output logic                             extsy_reg                  ,
    output logic [2:0]                       max_pload                  ,
    output logic                             tx_ecrcgen                 ,
    output logic                             rx_ecrchk                  ,
    output logic                             secbus7                    ,
    output logic [6:0]                       secbus6_0                  ,
    output logic                             linkcsr_bit0               ,
    output logic                             tx_req_pm                  ,
    output logic [2:0]                       tx_typ_pm                  ,
    output logic [3:0]                       req_phypm                  ,
    output logic [3:0]                       req_phycfg                 ,
    output logic [6:0]                       vc0_tcmap_pld              ,
    output logic                             inh_dllp                   ,
    output logic                             inh_tx_tlp                 ,
    output logic                             req_wake                   ,
    output logic                             link3_ctl1                 ,
    output logic                             link3_ctl0                 ,
    input  logic [7:0]                       lane_err                   ,
    input  logic                             err_uncorr_internal        ,
    input  logic                             rx_corr_internal           ,
    input  logic                             err_tlrcvovf               ,
    input  logic                             txfc_err                   ,
    input  logic                             err_tlmalf                 ,
    input  logic                             err_surpdwn_dll            ,
    input  logic                             err_dllrev                 ,
    input  logic                             err_dll_repnum             ,
    input  logic                             err_dllreptim              ,
    input  logic                             err_dllp_baddllp           ,
    input  logic                             err_dll_badtlp             ,
    input  logic                             err_phy_tng                ,
    input  logic                             err_phy_rcv                

);


bypass_conf_if                                            hip_bypass_config_if();
mlite_if                #(.DATA_WIDTH(REG_DATA_WIDTH))    csr_if();

initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, pcie_switch_tb, "+all");
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

assign link2csr      = hip_bypass_config_if.link2csr     ;
assign comclk_reg    = hip_bypass_config_if.comclk_reg   ;
assign extsy_reg     = hip_bypass_config_if.extsy_reg    ;
assign max_pload     = hip_bypass_config_if.max_pload    ;
assign tx_ecrcgen    = hip_bypass_config_if.tx_ecrcgen   ;
assign rx_ecrchk     = hip_bypass_config_if.rx_ecrchk    ;
assign secbus7       = hip_bypass_config_if.secbus7      ;
assign secbus6_0     = hip_bypass_config_if.secbus6_0    ;
assign linkcsr_bit0  = hip_bypass_config_if.linkcsr_bit0 ;
assign tx_req_pm     = hip_bypass_config_if.tx_req_pm    ;
assign tx_typ_pm     = hip_bypass_config_if.tx_typ_pm    ;
assign req_phypm     = hip_bypass_config_if.req_phypm    ;
assign req_phycfg    = hip_bypass_config_if.req_phycfg   ;
assign vc0_tcmap_pld = hip_bypass_config_if.vc0_tcmap_pld;
assign inh_dllp      = hip_bypass_config_if.inh_dllp     ;
assign inh_tx_tlp    = hip_bypass_config_if.inh_tx_tlp   ;
assign req_wake      = hip_bypass_config_if.req_wake     ;
assign link3_ctl1    = hip_bypass_config_if.link3_ctl1   ;
assign link3_ctl0    = hip_bypass_config_if.link3_ctl0   ;

assign hip_bypass_config_if.lane_err             = lane_err                           ;
assign hip_bypass_config_if.err_uncorr_initernal = err_uncorr_internal                ;
assign hip_bypass_config_if.err_corr_internal    = rx_corr_internal                   ; 
assign hip_bypass_config_if.err_tlrcvovf         = err_tlrcvovf                       ; 
assign hip_bypass_config_if.txfc_err             = txfc_err                           ; 
assign hip_bypass_config_if.err_tlmalf           = err_tlmalf                         ; 
assign hip_bypass_config_if.err_surpdwn_dll      = err_surpdwn_dll                    ; 
assign hip_bypass_config_if.err_dllrcv           = err_dllrev                         ;      
assign hip_bypass_config_if.err_dll_repnum       = err_dll_repnum                     ; 
assign hip_bypass_config_if.err_dllreptim        = err_dllreptim                      ; 
assign hip_bypass_config_if.err_dllp_baddllp     = err_dllp_baddllp                   ; 
assign hip_bypass_config_if.err_dll_badtlp       = err_dll_badtlp                     ; 
assign hip_bypass_config_if.err_phy_tng          = err_phy_tng                        ; 
assign hip_bypass_config_if.err_phy_rcv          = err_phy_rcv                        ; 

assign hip_bypass_config_if.current_ls = current_ls;
assign hip_bypass_config_if.negotiated_lw = negotiated_lw;



pcie_switch_top#(
    .DATA_WIDTH                 ( DATA_WIDTH     ),
    .REG_DATA_WIDTH             ( REG_DATA_WIDTH ),
    .REG_ADDR_WIDTH             ( REG_ADDR_WIDTH )
)u_pcie_switch_top(
    .clk                                   ( clk                                   ),
    .rst                                   ( rst                                   ),
    .hardip_clk                            ( hardip_clk                            ),
    .hardip_rst                            ( hardip_rst                            ),
    .event_vld                             ( event_vld                             ),
    .event_data                            ( event_data                            ),
    .event_rdy                             ( event_rdy                             ),
    .host2switch_tlp_bypass_req_hdr        ( host2switch_tlp_bypass_req_hdr        ),
    .host2switch_tlp_bypass_req_linkdown   ( linkdown                              ),
    .host2switch_tlp_bypass_req_host_gen   ( host2switch_tlp_bypass_req_gen        ),
    .host2switch_tlp_bypass_req_sop        ( host2switch_tlp_bypass_req_sop        ),
    .host2switch_tlp_bypass_req_eop        ( host2switch_tlp_bypass_req_eop        ),
    .host2switch_tlp_bypass_req_data       ( host2switch_tlp_bypass_req_data       ),
    .host2switch_tlp_bypass_req_vld        ( host2switch_tlp_bypass_req_vld        ),
    .host2switch_tlp_bypass_req_sav		   ( host2switch_tlp_bypass_req_sav		   ),
    .switch2emu_tlp_bypass_req_hdr         ( switch2emu_tlp_bypass_req_hdr         ),
    .switch2emu_tlp_bypass_req_host_gen    ( switch2emu_tlp_bypass_req_gen         ),
    .switch2emu_tlp_bypass_req_sop         ( switch2emu_tlp_bypass_req_sop         ),
    .switch2emu_tlp_bypass_req_eop         ( switch2emu_tlp_bypass_req_eop         ),
    .switch2emu_tlp_bypass_req_data        ( switch2emu_tlp_bypass_req_data        ),
    .switch2emu_tlp_bypass_req_vld         ( switch2emu_tlp_bypass_req_vld         ),
    .switch2emu_tlp_bypass_req_sav		   ( switch2emu_tlp_bypass_req_sav		   ),
    .host2switch_tlp_bypass_cpl_hdr        ( host2switch_tlp_bypass_cpl_hdr        ),
    .host2switch_tlp_bypass_cpl_host_gen   ( host2switch_tlp_bypass_cpl_gen        ),
    .host2switch_tlp_bypass_cpl_sop        ( host2switch_tlp_bypass_cpl_sop        ),
    .host2switch_tlp_bypass_cpl_eop        ( host2switch_tlp_bypass_cpl_eop        ),
    .host2switch_tlp_bypass_cpl_data       ( host2switch_tlp_bypass_cpl_data       ),
    .host2switch_tlp_bypass_cpl_vld        ( host2switch_tlp_bypass_cpl_vld        ),
    .host2switch_tlp_bypass_cpl_rdy		   ( host2switch_tlp_bypass_cpl_rdy		   ),
    .switch2emu_tlp_bypass_cpl_hdr         ( switch2emu_tlp_bypass_cpl_hdr         ),
    .switch2emu_tlp_bypass_cpl_host_gen    ( switch2emu_tlp_bypass_cpl_gen         ),
    .switch2emu_tlp_bypass_cpl_sop         ( switch2emu_tlp_bypass_cpl_sop         ),
    .switch2emu_tlp_bypass_cpl_eop         ( switch2emu_tlp_bypass_cpl_eop         ),
    .switch2emu_tlp_bypass_cpl_data        ( switch2emu_tlp_bypass_cpl_data        ),
    .switch2emu_tlp_bypass_cpl_vld         ( switch2emu_tlp_bypass_cpl_vld         ),
    .switch2emu_tlp_bypass_cpl_rdy		   ( switch2emu_tlp_bypass_cpl_rdy		   ),
    .hip_bypass_config_if                  ( hip_bypass_config_if                  ),
    .csr_if                                ( csr_if                                )
);




endmodule