/***************************************************
* 文件名称 : p_probe_tb
* 作者名称 : 崔飞翔
* 创建日期 : 2025/03/06
* 功能描述 : 
* 
* 修改记录 : 
* 
* 修改日期 : 2025/03/06
* 版本号    修改人    修改内容
* v1.0     崔飞翔     初始化版本
***************************************************/

module p_probe_tb 
    import alt_tlp_adaptor_pkg::*;
#(
    parameter PP_IF_NUM = 2,
    parameter CNT_WIDTH = 21,
    parameter DATA_WIDTH = 256
)(
    input   logic                               clk             ,
    input   logic                               rst             ,

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

    
    input   logic   [CNT_WIDTH-1:0]             timer           ,

    output  logic   [PP_IF_NUM*CNT_WIDTH-1:0]   bp_block_cnt    ,
    output  logic   [PP_IF_NUM*CNT_WIDTH-1:0]   bp_vdata_cnt    ,

    output  logic   [PP_IF_NUM*CNT_WIDTH-1:0]   hs_block_cnt    ,
    output  logic   [PP_IF_NUM*CNT_WIDTH-1:0]   hs_vdata_cnt    

);

initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, p_probe_tb, "+all");
    $fsdbDumpMDA();
end

assign switch2emu_tlp_bypass_req_hdr  = host2switch_tlp_bypass_req_hdr ; 
assign switch2emu_tlp_bypass_req_gen  = host2switch_tlp_bypass_req_gen ;
assign switch2emu_tlp_bypass_req_sop  = host2switch_tlp_bypass_req_sop ;
assign switch2emu_tlp_bypass_req_eop  = host2switch_tlp_bypass_req_eop ;
assign switch2emu_tlp_bypass_req_data = host2switch_tlp_bypass_req_data;
assign switch2emu_tlp_bypass_req_vld  = host2switch_tlp_bypass_req_vld ; 
assign host2switch_tlp_bypass_req_sav = switch2emu_tlp_bypass_req_sav  ;

assign host2switch_tlp_bypass_cpl_hdr  = switch2emu_tlp_bypass_cpl_hdr ;
assign host2switch_tlp_bypass_cpl_gen  = switch2emu_tlp_bypass_cpl_gen ;
assign host2switch_tlp_bypass_cpl_sop  = switch2emu_tlp_bypass_cpl_sop ;
assign host2switch_tlp_bypass_cpl_eop  = switch2emu_tlp_bypass_cpl_eop ;
assign host2switch_tlp_bypass_cpl_data = switch2emu_tlp_bypass_cpl_data;
assign host2switch_tlp_bypass_cpl_vld  = switch2emu_tlp_bypass_cpl_vld ;
assign switch2emu_tlp_bypass_cpl_rdy = host2switch_tlp_bypass_cpl_rdy;



performance_probe #(
    .PP_IF_NUM    (PP_IF_NUM),
    .CNT_WIDTH    (CNT_WIDTH)
) u_performance_probe(
    .clk                       (clk                   ),
    .rst                       (rst                   ),
    .backpressure_vld          ({host2switch_tlp_bypass_req_vld,host2switch_tlp_bypass_req_vld}     ),
    .backpressure_sav          ({host2switch_tlp_bypass_req_sav,host2switch_tlp_bypass_req_sav}     ),
    .handshake_vld             ({host2switch_tlp_bypass_cpl_vld,host2switch_tlp_bypass_cpl_vld}     ),
    .handshake_rdy             ({host2switch_tlp_bypass_cpl_rdy,host2switch_tlp_bypass_cpl_rdy}     ),
    .mon_tick_interval         (timer       ),
    .backpressure_block_cnt    (bp_block_cnt),
    .backpressure_vdata_cnt    (bp_vdata_cnt),
    .handshake_block_cnt       (hs_block_cnt),
    .handshake_vdata_cnt       (hs_vdata_cnt)
);
endmodule