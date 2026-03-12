/******************************************************************************
 * 文件名称 : emu_tb.sv
 * 作者名称 : matao
 * 创建日期 : 2025/01/20
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   01/20       matao       初始化版本
 ******************************************************************************/
`include "beq_data_if.svh"
`include "mlite_if.svh"
module clear_x #(
    parameter DW = 512
)(
    input  logic [DW-1:0] in,
    output logic [DW-1:0] out
);
    generate
    genvar i;
    for(i=0;i<DW;i++)begin
      always_comb begin
        case(in[i])
          1'b1: out[i] = 1'b1;
          1'b0: out[i] = 1'b0;
          default: out[i] = 1'b0;
        endcase
      end
    end
  endgenerate
    
endmodule


module emu_tb
  import alt_tlp_adaptor_pkg::*;
 #(
    parameter DATA_WIDTH    	= 256                                       ,
    parameter EMPTH_WIDTH   	= $clog2(DATA_WIDTH/8)                      ,
    parameter REQ_DFF_WIDTH     = DATA_WIDTH + $bits(tlp_bypass_hdr_t) +10  ,
    parameter MAX_VF_NUM_PRE_PF = 32                                        ,
    parameter PF_NUM      		= 16                                        ,
    parameter REG_ADDR_WIDTH  	= 23                                        ,   
    parameter REG_DATA_WIDTH  	= 64   
) (
    input                                       clk                         ,
    input                                       rst                         ,

    //event_i
	input  logic 								event_master_vld		    ,
	input  logic  [7:0]							event_master_data		    ,
	output logic  								event_master_rdy		    ,

	//tlp_bypass_req_if
	input  logic [$bits(tlp_bypass_hdr_t)-1:0]  tlp_bypass_master_req_hdr   ,
    input  logic  [7:0]                        	tlp_bypass_master_req_gen  	,
    input  logic                               	tlp_bypass_master_req_sop   ,
    input  logic                               	tlp_bypass_master_req_eop   ,
    input  logic  [DATA_WIDTH-1:0]             	tlp_bypass_master_req_data  ,
    input  logic                               	tlp_bypass_master_req_vld   ,
    output logic                               	tlp_bypass_master_req_sav   ,

    //tlp_bypass_cpl_if
	output logic [$bits(tlp_bypass_hdr_t)-1:0]  tlp_bypass_master_cpl_hdr   ,
    output logic  [7:0]                        	tlp_bypass_master_cpl_gen  	,
    output logic                               	tlp_bypass_master_cpl_sop   ,
    output logic                               	tlp_bypass_master_cpl_eop   ,
    output logic  [DATA_WIDTH-1:0]             	tlp_bypass_master_cpl_data  ,
    output logic                               	tlp_bypass_master_cpl_vld   ,
    input  logic                               	tlp_bypass_master_cpl_rdy   ,


	//fe_doorbell_if
	input  logic  								fe_doorbell_rdy			    ,
	output logic  								fe_doorbell_vld			    ,
	output logic  [($bits(emu_doorbell_t))-1:0]	fe_doorbell_qid			    ,

    //beq2emu
    output                                      beq2emu_sav                 ,
    input  logic                                beq2emu_vld                 ,
    input  logic  [DATA_WIDTH-1:0]              beq2emu_data                ,
    input  logic  [EMPTH_WIDTH-1:0]             beq2emu_sty                 ,
    input  logic  [EMPTH_WIDTH-1:0]             beq2emu_mty                 ,
    input  logic                                beq2emu_sop                 ,
    input  logic                                beq2emu_eop                 ,
    input  logic  [$bits(beq_txq_sbd_t)-1:0]    beq2emu_sbd                 ,
    
    //emu2beq
    input  logic                                emu2beq_sav                 ,
    output logic                                emu2beq_vld                 ,
    output logic  [DATA_WIDTH-1:0]              emu2beq_data                ,
    output logic  [EMPTH_WIDTH-1:0]             emu2beq_sty                 ,
    output logic  [EMPTH_WIDTH-1:0]             emu2beq_mty                 ,
    output logic                                emu2beq_sop                 ,
    output logic                                emu2beq_eop                 ,
    output logic  [$bits(beq_rxq_sbd_t)-1:0]    emu2beq_sbd                 ,
  
    // Register Bus
    output logic                                csr_if_ready                ,
    input  logic                                csr_if_valid                ,
    input  logic                                csr_if_read                 ,
    input  logic [REG_ADDR_WIDTH-1:0]           csr_if_addr                 ,
    input  logic [REG_DATA_WIDTH-1:0]           csr_if_wdata                ,
    input  logic [REG_DATA_WIDTH/8-1:0]         csr_if_wmask                ,
    output logic [REG_DATA_WIDTH-1:0]           csr_if_rdata                ,
    output logic                                csr_if_rvalid               ,
    input  logic                                csr_if_rready
);

beq_txq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   beq2emu_if();
beq_rxq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   emu2beq_if();

mlite_if #(.ADDR_WIDTH(REG_ADDR_WIDTH), .DATA_WIDTH(REG_DATA_WIDTH)) csr_if();

assign beq2emu_sav      = beq2emu_if.sav    ;
assign beq2emu_if.vld   = beq2emu_vld       ;
assign beq2emu_if.sop   = beq2emu_sop       ;
assign beq2emu_if.eop   = beq2emu_eop       ;
assign beq2emu_if.sbd   = beq2emu_sbd       ;
assign beq2emu_if.sty   = beq2emu_sty       ;
assign beq2emu_if.mty   = beq2emu_mty       ;
assign beq2emu_if.data  = beq2emu_data      ;

assign emu2beq_if.sav   = emu2beq_sav       ;
assign emu2beq_vld      = emu2beq_if.vld    ;
assign emu2beq_sop      = emu2beq_if.sop    ;
assign emu2beq_eop      = emu2beq_if.eop    ;
assign emu2beq_sbd      = emu2beq_if.sbd    ;
assign emu2beq_sty      = emu2beq_if.sty    ;
assign emu2beq_mty      = emu2beq_if.mty    ;
assign emu2beq_data     = emu2beq_if.data   ;

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
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, emu_tb, "+all");
    $fsdbDumpMDA();
end

logic [$bits(tlp_bypass_hdr_t)-1:0]      tlp_bypass_cpl_hdr_tmp,tlp_bypass_req_hdr_tmp;
assign tlp_bypass_req_hdr_tmp = tlp_bypass_master_req_hdr;
clear_x #(.DW($bits(tlp_bypass_hdr_t))) u_tlp_bypass_cpl_hdr_clearx (.in(tlp_bypass_cpl_hdr_tmp), .out(tlp_bypass_master_cpl_hdr));
emu #(
	.DATA_WIDTH         (DATA_WIDTH         ),
    .EMPTH_WIDTH        (EMPTH_WIDTH        ),
	.REQ_DFF_WIDTH      (REQ_DFF_WIDTH      ),
    .MAX_VF_NUM_PRE_PF  (MAX_VF_NUM_PRE_PF  ),
	.PF_NUM             (PF_NUM             ),
	.REG_ADDR_WIDTH     (REG_ADDR_WIDTH     ),
	.REG_DATA_WIDTH     (REG_DATA_WIDTH     )
) u_emu (
	.clk                        (clk                        ),		
	.rst                        (rst                        ),		
	.event_vld_i		        (event_master_vld		    ),	
	.event_data_i		        (event_master_data	        ),	
	.event_rdy_o		        (event_master_rdy           ),	
	.tlp_bypass_req_hdr_i       (tlp_bypass_req_hdr_tmp     ),	
	.tlp_bypass_req_host_gen_i  (tlp_bypass_master_req_gen  ),		
	.tlp_bypass_req_sop_i       (tlp_bypass_master_req_sop  ),		
	.tlp_bypass_req_eop_i       (tlp_bypass_master_req_eop  ),		
	.tlp_bypass_req_data_i      (tlp_bypass_master_req_data ),		
	.tlp_bypass_req_vld_i       (tlp_bypass_master_req_vld  ),	
    .tlp_bypass_req_sav_o       (tlp_bypass_master_req_sav  ), 
    .tlp_bypass_cpl_hdr_o       (tlp_bypass_cpl_hdr_tmp     ), 	
    .tlp_bypass_cpl_host_gen_o  (tlp_bypass_master_cpl_gen  ), 	
    .tlp_bypass_cpl_sop_o       (tlp_bypass_master_cpl_sop  ), 	
    .tlp_bypass_cpl_eop_o       (tlp_bypass_master_cpl_eop  ), 	
    .tlp_bypass_cpl_data_o      (tlp_bypass_master_cpl_data ), 	
    .tlp_bypass_cpl_vld_o       (tlp_bypass_master_cpl_vld  ), 	
    .tlp_bypass_cpl_rdy_i		(tlp_bypass_master_cpl_rdy	),
    .fe_doorbell_rdy_i          (fe_doorbell_rdy            ), 
    .fe_doorbell_vld_o          (fe_doorbell_vld            ), 
    .fe_doorbell_qid_o          (fe_doorbell_qid            ), 
    .emu2beq_if                 (emu2beq_if                 ), 
    .beq2emu_if                 (beq2emu_if                 ), 
    .csr_if                     (csr_if                     )
);



endmodule