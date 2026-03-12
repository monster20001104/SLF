/******************************************************************************
 * 文件名称 : tso_csum_tb.sv
 * 作者名称 : matao
 * 创建日期 : 2025/05/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   05/23       matao       初始化版本
 ******************************************************************************/
`include "mlite_if.svh"
`include "tso_csum_define.svh"
module tso_csum_tb #(
    parameter DATA_WIDTH            = 256                                           ,
    parameter EMPTH_WIDTH           = $clog2(DATA_WIDTH/8)                          ,
    parameter REG_ADDR_WIDTH        = 17                                            ,   
    parameter REG_DATA_WIDTH        = 64                                            ,
    parameter TCP_CSUM_SIM_WIDTH    = 256                                           
)
(
    input                                       clk                         ,
    input                                       rst                         ,

    // Register Bus
    output logic                                csr_if_ready                ,
    input  logic                                csr_if_valid                ,
    input  logic                                csr_if_read                 ,
    input  logic [REG_ADDR_WIDTH-1:0]           csr_if_addr                 ,
    input  logic [REG_DATA_WIDTH-1:0]           csr_if_wdata                ,
    input  logic [REG_DATA_WIDTH/8-1:0]         csr_if_wmask                ,
    output logic [REG_DATA_WIDTH-1:0]           csr_if_rdata                ,
    output logic                                csr_if_rvalid               ,
    input  logic                                csr_if_rready               ,

    //net 2 tso_csum
    output logic                                net2tso_sav                 ,
    input  logic                                net2tso_vld                 ,
    input  logic  [DATA_WIDTH-1:0]              net2tso_data                ,
    input  logic  [EMPTH_WIDTH-1:0]             net2tso_sty                 ,
    input  logic  [EMPTH_WIDTH-1:0]             net2tso_mty                 ,
    input  logic                                net2tso_sop                 ,
    input  logic                                net2tso_eop                 ,
    input  logic                                net2tso_err                 ,
    input  logic  [7:0]                         net2tso_qid                 ,
    input  logic  [17:0]                        net2tso_length              ,
    input  logic  [7:0]                         net2tso_gen                 ,
    input  logic                                net2tso_tso_en              ,
    input  logic                                net2tso_csum_en             ,
    
    //net 2 tso_parser
    output logic                                vio_net2tso_sav             ,
    input  logic                                vio_net2tso_vld             ,
    input  logic  [DATA_WIDTH-1:0]              vio_net2tso_data            ,
    input  logic  [EMPTH_WIDTH-1:0]             vio_net2tso_sty             ,
    input  logic  [EMPTH_WIDTH-1:0]             vio_net2tso_mty             ,
    input  logic                                vio_net2tso_sop             ,
    input  logic                                vio_net2tso_eop             ,
    input  logic                                vio_net2tso_err             ,
    input  logic  [7:0]                         vio_net2tso_qid             ,
    input  logic  [17:0]                        vio_net2tso_length          ,
    input  logic  [7:0]                         vio_net2tso_gen             ,

    //tso-csum 2 beq
    input  logic                                tso2beq_sav                 ,
    output logic                                tso2beq_vld                 ,
    output logic  [DATA_WIDTH-1:0]              tso2beq_data                ,
    output logic  [EMPTH_WIDTH-1:0]             tso2beq_sty                 ,
    output logic  [EMPTH_WIDTH-1:0]             tso2beq_mty                 ,
    output logic                                tso2beq_sop                 ,
    output logic                                tso2beq_eop                 ,
    output logic  [$bits(beq_rxq_sbd_t)-1:0]    tso2beq_sbd                 ,

    //tcp csum
    input  logic [15:0]                         tcp_calc_i_csum_info         ,
    input  logic [TCP_CSUM_SIM_WIDTH-1:0]       tcp_calc_i_csum_data         ,
    input  logic                                tcp_calc_i_csum_vld          ,
    input  logic                                tcp_calc_i_csum_eop          ,
    input  logic                                tcp_calc_i_csum_err          ,
    output logic [15:0]                         tcp_calc_o_csum_data         ,
    output logic                                tcp_calc_o_csum_vld          ,
    output logic                                tcp_calc_o_csum_err          ,
    output logic [15:0]                         tcp_calc_o_csum_info         

);

beq_rxq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   tso2beq_if();
mlite_if #(.ADDR_WIDTH(REG_ADDR_WIDTH), .DATA_WIDTH(REG_DATA_WIDTH)) csr_if();


assign tso2beq_if.sav             = tso2beq_sav;
assign tso2beq_vld                = tso2beq_if.vld;
assign tso2beq_sop                = tso2beq_if.sop;
assign tso2beq_eop                = tso2beq_if.eop;
assign tso2beq_sbd                = tso2beq_if.sbd;
assign tso2beq_sty                = tso2beq_if.sty;
assign tso2beq_mty                = tso2beq_if.mty;
assign tso2beq_data               = tso2beq_if.data;

assign csr_if_ready     = csr_if.ready      ;
assign csr_if.valid     = csr_if_valid      ;
assign csr_if.read      = csr_if_read       ;
assign csr_if.addr      = csr_if_addr       ;
assign csr_if.wdata     = csr_if_wdata      ;
assign csr_if.wmask     = csr_if_wmask      ;
assign csr_if_rdata     = csr_if.rdata      ;
assign csr_if_rvalid    = csr_if.rvalid     ;
assign csr_if.rready    = csr_if_rready     ;


initial begin
    $fsdbAutoSwitchDumpfile(2000, "top.fsdb", 30);
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, tso_csum_tb, "+all");
    $fsdbDumpMDA();
end

tso_csum #(
    .DATA_WIDTH     (DATA_WIDTH     ),
    .EMPTH_WIDTH    (EMPTH_WIDTH    ),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH ),
    .REG_DATA_WIDTH (REG_DATA_WIDTH )
) u_tso_csum (
    .clk                    (clk                    ),        
    .rst                    (rst                    ),        
    .vio_net2tso_sav        (net2tso_sav            ),
    .vio_net2tso_vld        (net2tso_vld            ),
    .vio_net2tso_data       (net2tso_data           ),
    .vio_net2tso_sty        (net2tso_sty            ),
    .vio_net2tso_mty        (net2tso_mty            ),
    .vio_net2tso_sop        (net2tso_sop            ),
    .vio_net2tso_eop        (net2tso_eop            ),
    .vio_net2tso_err        (net2tso_err            ),
    .vio_net2tso_qid        (net2tso_qid            ),
    .vio_net2tso_length     (net2tso_length         ),
    .vio_net2tso_gen        (net2tso_gen            ),
    .vio_net2tso_tso_en     (net2tso_tso_en         ),
    .vio_net2tso_csum_en    (net2tso_csum_en        ),
    .tso2beq_if             (tso2beq_if             ),
    .csr_if                 (csr_if                 )
);

tso_csum_trans_calc_csum #(
    .DATA_WIDTH     (256                ),
    .CSUM_WIDTH     (16                 ),
    .INFO_FF_WIDTH  (16                 )
) u1_tso_csum_trans_calc_csum(
    .clk                        (clk                      ),
    .rst                        (rst                      ),
    .trans_calc_csum_info_i     (tcp_calc_i_csum_info     ),
    .trans_calc_csum_data_i     (tcp_calc_i_csum_data     ),
    .trans_calc_csum_vld_i      (tcp_calc_i_csum_vld      ),
    .trans_calc_csum_eop_i      (tcp_calc_i_csum_eop      ),
    .trans_calc_csum_err_i      (tcp_calc_i_csum_err      ),
    .trans_calc_csum_data_o     (tcp_calc_o_csum_data     ),
    .trans_calc_csum_vld_o      (tcp_calc_o_csum_vld      ),
    .trans_calc_csum_err_o      (tcp_calc_o_csum_err      ),
    .trans_calc_csum_info_o     (tcp_calc_o_csum_info     )
);

endmodule