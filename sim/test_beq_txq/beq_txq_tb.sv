/******************************************************************************
 * 文件名称 : beq_txq_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/12/09
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  12/09     Joe Jiang   初始化版本
 ******************************************************************************/
 `include "tlp_adap_dma_if.svh"
 
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

  module beq_txq_tb
    import alt_tlp_adaptor_pkg::*;
 #(
    parameter CSR_ADDR_WIDTH= 64,
    parameter CSR_DATA_WIDTH= 64,  
    parameter Q_NUM         = 64,
    parameter Q_WIDTH       = $clog2(Q_NUM),
    parameter DATA_WIDTH    = 256,
    parameter EMPTH_WIDTH   = $clog2(DATA_WIDTH/8),
    parameter CACHE_LINE_WIDTH = 512,
    parameter CACHE_LINE_EMPTH_WIDTH = $clog2(CACHE_LINE_WIDTH/8),
    parameter MAX_DESC_SIZE = 8192,
    parameter DATA_FF_DEPTH = 1024
 ) (
    input                                       clk,
    input                                       rst,
    /////////////
    input  logic                                notify_req_vld,
    input  [$bits(beq_wrr_sch_notify_t)-1:0]    notify_req_dat,
    output logic                                notify_req_rdy,

    output logic                                notify_rsp_vld,
    output [$bits(beq_wrr_sch_notify_t)-1:0]    notify_rsp_dat,
    input  logic                                notify_rsp_rdy,

    output logic                                rd_ndesc_req_vld,
    input  logic                                rd_ndesc_req_rdy,
    output [$bits(beq_rd_ndesc_req_t)-1:0]      rd_ndesc_req_dat,

    output logic                                rd_ndesc_rsp_rdy,
    input  logic                                rd_ndesc_rsp_vld,
    input  [$bits(beq_rd_ndesc_rsp_t)-1:0]      rd_ndesc_rsp_sbd,
    input  logic                                rd_ndesc_rsp_sop,
    input  logic                                rd_ndesc_rsp_eop,
    input  [$bits(beq_avail_desc_t)-1:0]        rd_ndesc_rsp_dat,
    input  logic [3:0]                          rd_ndesc_rsp_tag,
    input  logic                                rd_ndesc_rsp_err,

    input                                       beq2emu_sav           ,
    output     logic                            beq2emu_vld           ,
    output     logic  [DATA_WIDTH-1:0]          beq2emu_data          ,
    output     logic  [EMPTH_WIDTH-1:0]         beq2emu_sty           ,
    output     logic  [EMPTH_WIDTH-1:0]         beq2emu_mty           ,
    output     logic                            beq2emu_sop           ,
    output     logic                            beq2emu_eop           ,
    output     logic  [$bits(beq_txq_sbd_t)-1:0]beq2emu_sbd           ,

    input                                       beq2net_sav           ,
    output     logic                            beq2net_vld           ,
    output     logic  [DATA_WIDTH-1:0]          beq2net_data          ,
    output     logic  [EMPTH_WIDTH-1:0]         beq2net_sty           ,
    output     logic  [EMPTH_WIDTH-1:0]         beq2net_mty           ,
    output     logic                            beq2net_sop           ,
    output     logic                            beq2net_eop           ,
    output     logic  [$bits(beq_txq_sbd_t)-1:0]beq2net_sbd           ,

    input                                       beq2blk_sav           ,
    output     logic                            beq2blk_vld           ,
    output     logic  [DATA_WIDTH-1:0]          beq2blk_data          ,
    output     logic  [EMPTH_WIDTH-1:0]         beq2blk_sty           ,
    output     logic  [EMPTH_WIDTH-1:0]         beq2blk_mty           ,
    output     logic                            beq2blk_sop           ,
    output     logic                            beq2blk_eop           ,
    output     logic  [$bits(beq_txq_sbd_t)-1:0]beq2blk_sbd           ,

    input                                       beq2sgdma_sav           ,
    output     logic                            beq2sgdma_vld           ,
    output     logic  [DATA_WIDTH-1:0]          beq2sgdma_data          ,
    output     logic  [EMPTH_WIDTH-1:0]         beq2sgdma_sty           ,
    output     logic  [EMPTH_WIDTH-1:0]         beq2sgdma_mty           ,
    output     logic                            beq2sgdma_sop           ,
    output     logic                            beq2sgdma_eop           ,
    output     logic  [$bits(beq_txq_sbd_t)-1:0]beq2sgdma_sbd           ,


    // Write request interface from DMA core
    input      logic                            dma_ci_wr_req_sav          ,// wr_req_val_i must de-assert within 3 cycles after de-assertion of wr_req_rdy_o
    output     logic                            dma_ci_wr_req_val          ,// Request is taken when asserted
    output     logic                            dma_ci_wr_req_sop          ,// Indicates first dataword
    output     logic                            dma_ci_wr_req_eop          ,// Indicates last dataword
    output     logic  [DATA_WIDTH-1:0]          dma_ci_wr_req_data         ,// Data to write to host in big endian format
    output     logic  [EMPTH_WIDTH-1:0]         dma_ci_wr_req_sty          ,// Points to first valid payload byte. Valid when wr_req_sop_i=1
    output     logic  [EMPTH_WIDTH-1:0]         dma_ci_wr_req_mty          ,// Number of unused bytes in last dataword. Valid when wr_req_eop_i=1
    output     logic  [$bits(desc_t)-1:0]       dma_ci_wr_req_desc         ,// Descriptor for write. Valid when wr_req_sop_i=1
    // Write response interface from DMA core
    input  logic [111:0]                        dma_ci_wr_rsp_rd2rsp_loop  ,
    input  logic                                dma_ci_wr_rsp_val          ,
    // Read request interface from DMA core
    input        logic                            dma_data_rd_req_sav          ,// rd_req_val_i must de-assert within 3 cycles after de-assertion of rd_req_rdy_o
    output       logic                            dma_data_rd_req_val          ,// Request is taken when asserted
    output       logic  [EMPTH_WIDTH-1:0]         dma_data_rd_req_sty          ,// Determines where first valid payload byte is placed in rd_rsp_data_o
    output       logic  [$bits(desc_t)-1:0]       dma_data_rd_req_desc         ,// Descriptor for read
    // Read response interface back to DMA core
    input      logic                            dma_data_rd_rsp_val          ,// Asserted when response is valid
    input      logic                            dma_data_rd_rsp_sop          ,// Indicates first dataword
    input      logic                            dma_data_rd_rsp_eop          ,// Indicates last dataword
    input      logic                            dma_data_rd_rsp_err          ,// Asserted if completion from host has non-succesfull status or poison bit set
    input      logic  [DATA_WIDTH-1:0]          dma_data_rd_rsp_data         ,// Response data
    input      logic  [EMPTH_WIDTH-1:0]         dma_data_rd_rsp_sty          ,// Points to first valid payload byte. Valid when rd_rsp_sop_o=1
    input      logic  [EMPTH_WIDTH-1:0]         dma_data_rd_rsp_mty          ,// Number of unused bytes in last dataword. Valid when rd_rsp_eop_o=1
    input      logic  [$bits(desc_t)-1:0]       dma_data_rd_rsp_desc         ,// Descriptor for response. Valid when rd_rsp_sop_o=1


    output logic [Q_WIDTH-1:0]                  ring_ci_addr_rd_req_qid,
    output logic                                ring_ci_addr_rd_req_vld,
    input  logic [63:0]                         ring_ci_addr_rd_rsp_dat,
    input  logic                                ring_ci_addr_rd_rsp_vld,

    output logic [Q_WIDTH-1:0]                  err_info_rd_req_qid,
    output logic                                err_info_rd_req_vld,
    input  logic  [$bits(beq_err_info)-1:0]     err_info_rd_rsp_dat,
    input  logic                                err_info_rd_rsp_vld,
    output logic [Q_WIDTH-1:0]                  err_info_wr_qid,
    output logic                                err_info_wr_vld,
    output logic [$bits(beq_err_info)-1:0]      err_info_wr_dat,

    output logic                                err_stop_vld,
    output logic [Q_WIDTH-1:0]                  err_stop_qid,
    input logic                                 err_stop_sav,

    output logic [Q_WIDTH-1:0]                  ring_ci_rd_req_qid,
    output logic                                ring_ci_rd_req_vld,
    input  logic [15:0]                         ring_ci_rd_rsp_dat,
    input  logic                                ring_ci_rd_rsp_vld,

    output logic                                ring_ci_wr_vld,
    output logic [Q_WIDTH-1:0]                  ring_ci_wr_qid,
    output logic [15:0]                         ring_ci_wr_dat,

    output logic [Q_WIDTH-1:0]                  mon_qid,
    output logic                                mon_send_a_pkt,

    //===========beq_txq_flow_ctrl===================//
    input  logic                                emu_to_beq_cred_fc,
    input  logic                                blk_to_beq_cred_fc,
    input  logic                                sgdma_to_beq_cred_fc, 

    // Register Bus
    output logic                                csr_if_ready,
    input  logic                                csr_if_valid,
    input  logic                                csr_if_read,
    input  logic [CSR_ADDR_WIDTH-1:0]           csr_if_addr,
    input  logic [CSR_DATA_WIDTH-1:0]           csr_if_wdata,
    input  logic [CSR_DATA_WIDTH/8-1:0]         csr_if_wmask,
    output logic [CSR_DATA_WIDTH-1:0]           csr_if_rdata,
    output logic                                csr_if_rvalid,
    input  logic                                csr_if_rready
    

 );

initial begin
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
    $fsdbDumpvars(0, beq_txq_tb, "+all");
    $fsdbDumpMDA();
end

mlite_if #(.ADDR_WIDTH(CSR_ADDR_WIDTH), .DATA_WIDTH(CSR_DATA_WIDTH)) csr_if();

assign csr_if_ready     = csr_if.ready;
assign csr_if.valid     = csr_if_valid;
assign csr_if.read      = csr_if_read;
assign csr_if.addr      = csr_if_addr;
assign csr_if.wdata     = csr_if_wdata;
assign csr_if.wmask     = csr_if_wmask;
assign csr_if_rdata     = csr_if.rdata;
assign csr_if_rvalid    = csr_if.rvalid;
assign csr_if.rready    = csr_if_rready;

tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_ci_wr_req_if();
tlp_adap_dma_wr_rsp_if                               dma_ci_wr_rsp_if();
tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_data_rd_req_if();
tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_data_rd_rsp_if();

beq_txq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   beq2user_if[3:0]();


assign dma_ci_wr_req_if.sav            = dma_ci_wr_req_sav;
assign dma_ci_wr_req_sop               = dma_ci_wr_req_if.sop;
assign dma_ci_wr_req_eop               = dma_ci_wr_req_if.eop;
assign dma_ci_wr_req_val               = dma_ci_wr_req_if.vld;
assign dma_ci_wr_req_data              = dma_ci_wr_req_if.data;
assign dma_ci_wr_req_sty               = dma_ci_wr_req_if.sty;
assign dma_ci_wr_req_mty               = dma_ci_wr_req_if.mty;
//assign dma_ci_wr_req_desc              = dma_ci_wr_req_if.desc;

clear_x #(.DW($bits(desc_t))) u_dma_ci_wr_req_desc_clearx (.in(dma_ci_wr_req_if.desc), .out(dma_ci_wr_req_desc));


assign dma_ci_wr_rsp_if.vld            = dma_ci_wr_rsp_val;
assign dma_ci_wr_rsp_if.rd2rsp_loop    = dma_ci_wr_rsp_rd2rsp_loop;

assign dma_data_rd_req_if.sav            = dma_data_rd_req_sav;
assign dma_data_rd_req_val               = dma_data_rd_req_if.vld;
assign dma_data_rd_req_sty               = dma_data_rd_req_if.sty;
//assign dma_data_rd_req_desc              = dma_data_rd_req_if.desc;
clear_x #(.DW($bits(desc_t))) u_dma_data_rd_req_desc_clearx (.in(dma_data_rd_req_if.desc), .out(dma_data_rd_req_desc));

assign dma_data_rd_rsp_if.vld            = dma_data_rd_rsp_val;
assign dma_data_rd_rsp_if.sop            = dma_data_rd_rsp_sop;
assign dma_data_rd_rsp_if.eop            = dma_data_rd_rsp_eop;
assign dma_data_rd_rsp_if.sty            = dma_data_rd_rsp_sty;
assign dma_data_rd_rsp_if.mty            = dma_data_rd_rsp_mty;
assign dma_data_rd_rsp_if.data           = dma_data_rd_rsp_data;
assign dma_data_rd_rsp_if.err            = dma_data_rd_rsp_err;
assign dma_data_rd_rsp_if.desc           = dma_data_rd_rsp_desc;
//clear_x #(.DW($bits(desc_t))) u_dma_data_rd_rsp_desc_clearx (.in(dma_data_rd_rsp_if.desc), .out(dma_data_rd_rsp_desc));

assign beq2user_if[0].sav         = beq2emu_sav;
assign beq2emu_vld                = beq2user_if[0].vld;
assign beq2emu_sop                = beq2user_if[0].sop;
assign beq2emu_eop                = beq2user_if[0].eop;
assign beq2emu_sbd                = beq2user_if[0].sbd;
assign beq2emu_sty                = beq2user_if[0].sty;
assign beq2emu_mty                = beq2user_if[0].mty;
assign beq2emu_data               = beq2user_if[0].data;


assign beq2user_if[1].sav         = beq2net_sav;
assign beq2net_vld                = beq2user_if[1].vld;
assign beq2net_sop                = beq2user_if[1].sop;
assign beq2net_eop                = beq2user_if[1].eop;
assign beq2net_sbd                = beq2user_if[1].sbd;
assign beq2net_sty                = beq2user_if[1].sty;
assign beq2net_mty                = beq2user_if[1].mty;
assign beq2net_data               = beq2user_if[1].data;


assign beq2user_if[2].sav         = beq2blk_sav;
assign beq2blk_vld                = beq2user_if[2].vld;
assign beq2blk_sop                = beq2user_if[2].sop;
assign beq2blk_eop                = beq2user_if[2].eop;
assign beq2blk_sbd                = beq2user_if[2].sbd;
assign beq2blk_sty                = beq2user_if[2].sty;
assign beq2blk_mty                = beq2user_if[2].mty;
assign beq2blk_data               = beq2user_if[2].data;

assign beq2user_if[3].sav           = beq2sgdma_sav;
assign beq2sgdma_vld                = beq2user_if[3].vld;
assign beq2sgdma_sop                = beq2user_if[3].sop;
assign beq2sgdma_eop                = beq2user_if[3].eop;
assign beq2sgdma_sbd                = beq2user_if[3].sbd;
assign beq2sgdma_sty                = beq2user_if[3].sty;
assign beq2sgdma_mty                = beq2user_if[3].mty;
assign beq2sgdma_data               = beq2user_if[3].data;



beq_txq #(
    .Q_NUM               (Q_NUM               ),
    .Q_WIDTH             (Q_WIDTH             ),
    .DATA_WIDTH          (DATA_WIDTH          ),
    .EMPTH_WIDTH         (EMPTH_WIDTH         ),
    .CACHE_LINE_WIDTH    (CACHE_LINE_WIDTH),
    .CACHE_LINE_EMPTH_WIDTH (CACHE_LINE_EMPTH_WIDTH),
    .MAX_DESC_SIZE       (MAX_DESC_SIZE       ),
    .DATA_FF_DEPTH       (DATA_FF_DEPTH       )
 ) u_beq_txq (
    .clk(clk),
    .rst(rst),

    .notify_req_vld(notify_req_vld),
    .notify_req_dat(notify_req_dat),
    .notify_req_rdy(notify_req_rdy),

    .notify_rsp_vld(notify_rsp_vld),
    .notify_rsp_dat(notify_rsp_dat),
    .notify_rsp_rdy(notify_rsp_rdy),

    .rd_ndesc_req_vld(rd_ndesc_req_vld),
    .rd_ndesc_req_rdy(rd_ndesc_req_rdy),
    .rd_ndesc_req_dat(rd_ndesc_req_dat),

    .rd_ndesc_rsp_rdy(rd_ndesc_rsp_rdy),
    .rd_ndesc_rsp_vld(rd_ndesc_rsp_vld),
    .rd_ndesc_rsp_sbd(rd_ndesc_rsp_sbd),
    .rd_ndesc_rsp_sop(rd_ndesc_rsp_sop),
    .rd_ndesc_rsp_eop(rd_ndesc_rsp_eop),
    .rd_ndesc_rsp_dat(rd_ndesc_rsp_dat),
    .rd_ndesc_rsp_tag(rd_ndesc_rsp_tag),
    .rd_ndesc_rsp_err(1'b0),
    //.rd_ndesc_rsp_err(rd_ndesc_rsp_err),

    .beq2user_if(beq2user_if),

    .dma_data_rd_req_if(dma_data_rd_req_if),
    .dma_data_rd_rsp_if(dma_data_rd_rsp_if),

    .dma_ci_wr_req_if(dma_ci_wr_req_if),
    .dma_ci_wr_rsp_if(dma_ci_wr_rsp_if),

    .ring_ci_addr_rd_req_qid(ring_ci_addr_rd_req_qid),
    .ring_ci_addr_rd_req_vld(ring_ci_addr_rd_req_vld),
    .ring_ci_addr_rd_rsp_dat(ring_ci_addr_rd_rsp_dat),
    .ring_ci_addr_rd_rsp_vld(ring_ci_addr_rd_rsp_vld),

    .err_stop_vld(err_stop_vld),
    .err_stop_qid(err_stop_qid),
    .err_stop_sav(1'b1),

    .ring_ci_rd_req_qid(ring_ci_rd_req_qid),
    .ring_ci_rd_req_vld(ring_ci_rd_req_vld),
    .ring_ci_rd_rsp_dat(ring_ci_rd_rsp_dat),
    .ring_ci_rd_rsp_vld(ring_ci_rd_rsp_vld),

    .err_info_rd_req_qid(err_info_rd_req_qid),
    .err_info_rd_req_vld(err_info_rd_req_vld),
    .err_info_rd_rsp_dat(err_info_rd_rsp_dat),
    .err_info_rd_rsp_vld(err_info_rd_rsp_vld),
    .err_info_wr_qid    (err_info_wr_qid    ),
    .err_info_wr_vld    (err_info_wr_vld    ),
    .err_info_wr_dat    (err_info_wr_dat    ),

    .ring_ci_wr_vld(ring_ci_wr_vld),
    .ring_ci_wr_qid(ring_ci_wr_qid),
    .ring_ci_wr_dat(ring_ci_wr_dat),

    .mon_qid(mon_qid),
    .mon_send_a_pkt(mon_send_a_pkt),

    .emu_cred_fc(emu_to_beq_cred_fc),
    .blk_cred_fc(blk_to_beq_cred_fc),
    .sgdma_cred_fc(sgdma_to_beq_cred_fc),

    .dfx_if(csr_if)
 );

 endmodule