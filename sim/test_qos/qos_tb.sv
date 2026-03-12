/******************************************************************************
 * 文件名称 : qos_tb.sv
 * 作者名称 : matao
 * 创建日期 : 2025/04/03
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   04/03       matao       初始化版本
 #* v1.1   07/25       matao       query由5通道改成3通道，取消rr调度使用3个ram
 ******************************************************************************/
`include "mlite_if.svh"
module qos_tb #(
    parameter REG_ADDR_WIDTH    = 23   ,   
    parameter REG_DATA_WIDTH    = 64   ,
    parameter UID_NUM_WIDTH     = 10   ,
    parameter TIME_WIDTH        = 23   ,
    parameter CIR_WIDTH         = 19   ,
    parameter CBS_WIDTH         = 42   ,
    parameter TOKEN_WIDTH       = 44   ,
    parameter TOKEN_REG_WIDTH   = TIME_WIDTH + TOKEN_WIDTH
)
(
    input                                       clk                         ,
    input                                       rst                         ,

    //update
    input  logic                                update0_vld                 ,
    input  logic [UID_NUM_WIDTH-1:0]            update0_uid                 ,
    output logic                                update0_rdy                 ,
    input  logic [19:0]                         update0_len                 ,
    input  logic [7:0]                          update0_pkt_num             ,

    input  logic                                update1_vld                 ,
    input  logic [UID_NUM_WIDTH-1:0]            update1_uid                 ,
    output logic                                update1_rdy                 ,
    input  logic [19:0]                         update1_len                 ,
    input  logic [7:0]                          update1_pkt_num             ,

    input  logic                                update2_vld                 ,
    input  logic [UID_NUM_WIDTH-1:0]            update2_uid                 ,
    output logic                                update2_rdy                 ,
    input  logic [19:0]                         update2_len                 ,
    input  logic [7:0]                          update2_pkt_num             ,

    //query 
    input  logic                                query0_req_vld              ,
    input  logic [UID_NUM_WIDTH-1:0]            query0_req_uid              ,
    output logic                                query0_req_rdy              ,
    output logic                                query0_rsp_vld              ,
    output logic                                query0_rsp_ok               ,
    input  logic                                query0_rsp_rdy              ,
   
    input  logic                                query1_req_vld              ,
    input  logic [UID_NUM_WIDTH-1:0]            query1_req_uid              ,
    output logic                                query1_req_rdy              ,
    output logic                                query1_rsp_vld              ,
    output logic                                query1_rsp_ok               ,
    input  logic                                query1_rsp_rdy              ,

    input  logic                                query4_req_vld              ,
    input  logic [UID_NUM_WIDTH-1:0]            query4_req_uid              ,
    output logic                                query4_req_rdy              ,
    output logic                                query4_rsp_vld              ,
    output logic                                query4_rsp_ok               ,
    input  logic                                query4_rsp_rdy              ,

    input  logic                                query2_req_vld              ,
    input  logic [UID_NUM_WIDTH-1:0]            query2_req_uid              ,
    output logic                                query2_req_rdy              ,
    output logic                                query2_rsp_vld              ,
    output logic                                query2_rsp_ok               ,
    input  logic                                query2_rsp_rdy              ,

    input  logic                                query3_req_vld              ,
    input  logic [UID_NUM_WIDTH-1:0]            query3_req_uid              ,
    output logic                                query3_req_rdy              ,
    output logic                                query3_rsp_vld              ,
    output logic                                query3_rsp_ok               ,
    input  logic                                query3_rsp_rdy              ,


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

    input  logic [UID_NUM_WIDTH:0]              calc_uid                    ,//highbit type updata/auto

    //signal dsp
    input  logic [TIME_WIDTH-1:0]               calc_curr_time              ,
    input  logic [TIME_WIDTH-1:0]               calc_bw_last_time           ,
    input  logic [TIME_WIDTH-1:0]               calc_qps_last_time          ,
    input  logic [CIR_WIDTH-1:0]                calc_bw_cir                 ,
    input  logic [CIR_WIDTH-1:0]                calc_qps_cir                ,

    //signal csa
    input  logic [CBS_WIDTH-1:0]                calc_bw_cbs                 ,
    input  logic [CBS_WIDTH-1:0]                calc_qps_cbs                ,
    input  logic [TOKEN_WIDTH-1:0]              calc_bw_token               ,
    input  logic [TOKEN_WIDTH-1:0]              calc_qps_token              ,
    input  logic [19:0]                         calc_bw_len                 ,
    input  logic [7:0]                          calc_qps_pkt_num            ,
    input  logic                                calc_control                ,

    output logic [TOKEN_WIDTH-1:0]              calc_bw_token_result        ,
    output logic [TOKEN_WIDTH-1:0]              calc_qps_token_result       ,
    output logic                                calc_token_result_vld       ,
    output logic [UID_NUM_WIDTH:0]              calc_token_result_uid       

);

mlite_if #(.ADDR_WIDTH(REG_ADDR_WIDTH), .DATA_WIDTH(REG_DATA_WIDTH)) csr_if();

logic [2:0]                              update_vld                      ;
logic [UID_NUM_WIDTH-1:0]                update_uid[2:0]                 ;
logic [2:0]                              update_rdy                      ;
logic [19:0]                             update_len[2:0]                 ;
logic [7:0]                              update_pkt_num[2:0]             ;

logic [4:0]                              query_req_vld                   ;
logic [UID_NUM_WIDTH-1:0]                query_req_uid[4:0]              ;
logic [4:0]                              query_req_rdy                   ;
logic [4:0]                              query_rsp_vld                   ;
logic [4:0]                              query_rsp_ok                    ;
logic [4:0]                              query_rsp_rdy                   ;

logic                                    calc_bitmap_vld                 ;
logic [3:0]                              calc_bitmap_vld_stage3          ;
logic [UID_NUM_WIDTH-1:0]                calc_stage_uid[3:0]             ;

assign update_vld[0]     = update0_vld      ;     
assign update_uid[0]     = update0_uid      ;     
assign update0_rdy       = update_rdy[0]    ;  
assign update_len[0]     = update0_len      ;     
assign update_pkt_num[0] = update0_pkt_num  ;

assign update_vld[1]     = update1_vld      ;     
assign update_uid[1]     = update1_uid      ;     
assign update1_rdy       = update_rdy[1]    ;  
assign update_len[1]     = update1_len      ;     
assign update_pkt_num[1] = update1_pkt_num  ;

assign update_vld[2]     = update2_vld      ;     
assign update_uid[2]     = update2_uid      ;     
assign update2_rdy       = update_rdy[2]    ;  
assign update_len[2]     = update2_len      ;     
assign update_pkt_num[2] = update2_pkt_num  ;

assign query_req_vld[0] = query0_req_vld    ;
assign query_req_uid[0] = query0_req_uid    ;
assign query0_req_rdy   = query_req_rdy[0]  ;
assign query0_rsp_vld   = query_rsp_vld[0]  ;
assign query0_rsp_ok    = query_rsp_ok [0]  ;
assign query_rsp_rdy[0] = query0_rsp_rdy    ;

assign query_req_vld[1] = query1_req_vld    ;
assign query_req_uid[1] = query1_req_uid    ;
assign query1_req_rdy   = query_req_rdy[1]  ;
assign query1_rsp_vld   = query_rsp_vld[1]  ;
assign query1_rsp_ok    = query_rsp_ok [1]  ;
assign query_rsp_rdy[1] = query1_rsp_rdy    ;

assign query_req_vld[2] = query2_req_vld    ;
assign query_req_uid[2] = query2_req_uid    ;
assign query2_req_rdy   = query_req_rdy[2]  ;
assign query2_rsp_vld   = query_rsp_vld[2]  ;
assign query2_rsp_ok    = query_rsp_ok [2]  ;
assign query_rsp_rdy[2] = query2_rsp_rdy    ;

assign query_req_vld[3] = query3_req_vld    ;
assign query_req_uid[3] = query3_req_uid    ;
assign query3_req_rdy   = query_req_rdy[3]  ;
assign query3_rsp_vld   = query_rsp_vld[3]  ;
assign query3_rsp_ok    = query_rsp_ok [3]  ;
assign query_rsp_rdy[3] = query3_rsp_rdy    ;

assign query_req_vld[4] = query4_req_vld    ;
assign query_req_uid[4] = query4_req_uid    ;
assign query4_req_rdy   = query_req_rdy[4]  ;
assign query4_rsp_vld   = query_rsp_vld[4]  ;
assign query4_rsp_ok    = query_rsp_ok [4]  ;
assign query_rsp_rdy[4] = query4_rsp_rdy    ;

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
    $fsdbAutoSwitchDumpfile(600, "top.fsdb", 30);
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, qos_tb, "+all");
    $fsdbDumpMDA();
end

qos #(
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH  ),
    .REG_DATA_WIDTH (REG_DATA_WIDTH  ),
    .UID_NUM_WIDTH  (UID_NUM_WIDTH   )
) u_qos (
    .clk                    (clk                    ),        
    .rst                    (rst                    ),        
    .update_vld             (update_vld             ),    
    .update_uid             (update_uid             ),    
    .update_rdy             (update_rdy             ),    
    .update_len             (update_len             ),    
    .update_pkt_num         (update_pkt_num         ),            
    .query_req_vld          (query_req_vld[2:0]     ),     
    .query_req_uid          (query_req_uid[2:0]     ),     
    .query_req_rdy          (query_req_rdy[2:0]     ),     
    .query_rsp_vld          (query_rsp_vld[2:0]     ),     
    .query_rsp_ok           (query_rsp_ok[2:0]      ),     
    .query_rsp_rdy          (query_rsp_rdy[2:0]     ),
    .csr_if                 (csr_if                 )
);


qos_credit_calc #(
    .UID_NUM_WIDTH      (10          )
) u_qos_credit_calc_test(
    .clk                    (clk                    ),
    .rst                    (rst                    ),
    .calc_uid               (calc_uid               ),
    .calc_curr_time         (calc_curr_time         ),
    .calc_bw_last_time      (calc_bw_last_time      ),
    .calc_qps_last_time     (calc_qps_last_time     ), 
    .calc_bw_cir            (calc_bw_cir            ),    
    .calc_qps_cir           (calc_qps_cir           ),    
    .calc_bw_cbs            (calc_bw_cbs            ),    
    .calc_qps_cbs           (calc_qps_cbs           ), 
    .calc_bw_token          (calc_bw_token          ),
    .calc_qps_token         (calc_qps_token         ),
    .calc_bw_len            (calc_bw_len            ),
    .calc_qps_pkt_num       (calc_qps_pkt_num       ),
    .calc_control           (calc_control           ),
    .calc_bitmap_vld        (calc_bitmap_vld        ),
    .calc_bw_token_result   (calc_bw_token_result   ),
    .calc_qps_token_result  (calc_qps_token_result  ),
    .calc_token_result_vld  (calc_token_result_vld  ),
    .calc_token_result_uid  (calc_token_result_uid  ),
    .calc_stage_uid         (calc_stage_uid         ),
    .calc_bitmap_vld_stage3 (calc_bitmap_vld_stage3 )
);    

endmodule