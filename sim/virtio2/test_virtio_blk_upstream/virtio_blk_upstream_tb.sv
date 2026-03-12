/******************************************************************************
 * 文件名称 : virtio_blk_upstream_tb.sv
 * 作者名称 : cui naiwan
 * 创建日期 : 2025/07/08
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/08     cui naiwan   初始化版本
 ******************************************************************************/
 `include "tlp_adap_dma_if.svh"
 `include "virtio_define.svh"
 `include "beq_data_if.svh"
 
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

module virtio_blk_upstream_tb
    import alt_tlp_adaptor_pkg::*;
 #(
    parameter CSR_ADDR_WIDTH= 64,
    parameter CSR_DATA_WIDTH= 64,
    parameter Q_NUM = 256,
    parameter Q_WIDTH = $clog2(Q_NUM),
    parameter DATA_WIDTH = 256,
    parameter EMPTH_WIDTH = $clog2(DATA_WIDTH/8)
 )(
    input                                       clk,
    input                                       rst,
    //======from or to beq=======================//
    output  logic                               beq2blk_sav,
    input   logic                               beq2blk_vld,
    input   logic  [DATA_WIDTH-1:0]             beq2blk_data,
    input   logic  [EMPTH_WIDTH-1:0]            beq2blk_sty,
    input   logic  [EMPTH_WIDTH-1:0]            beq2blk_mty,
    input   logic                               beq2blk_sop,
    input   logic                               beq2blk_eop,
    input   logic  [$bits(beq_txq_sbd_t)-1:0]   beq2blk_sbd,
    //=============dma_data_wr_if=================//
    input      logic                            dma_data_wr_req_sav          ,// wr_req_val_i must de-assert within 3 cycles after de-assertion of wr_req_rdy_o
    output     logic                            dma_data_wr_req_val          ,// Request is taken when asserted
    output     logic                            dma_data_wr_req_sop          ,// Indicates first dataword
    output     logic                            dma_data_wr_req_eop          ,// Indicates last dataword
    output     logic  [DATA_WIDTH-1:0]          dma_data_wr_req_data         ,// Data to write to host in big endian format
    output     logic  [EMPTH_WIDTH-1:0]         dma_data_wr_req_sty          ,// Points to first valid payload byte. Valid when wr_req_sop_i=1
    output     logic  [EMPTH_WIDTH-1:0]         dma_data_wr_req_mty          ,// Number of unused bytes in last dataword. Valid when wr_req_eop_i=1
    output     logic  [$bits(desc_t)-1:0]       dma_data_wr_req_desc         ,// Descriptor for write. Valid when wr_req_sop_i=1
    // Write response interface from DMA core
    input  logic [13:0]                         dma_data_wr_rsp_rd2rsp_loop  ,
    input  logic                                dma_data_wr_rsp_val          ,
    //======from or to virtio_used==============//
    output logic                                wr_used_info_vld,
    output [$bits(virtio_used_info_t)-1:0]      wr_used_info_dat,
    input  logic                                wr_used_info_rdy,
    //========from or to ctx================//
    output logic                                blk_upstream_ctx_req_vld,
    output logic [Q_WIDTH-1:0]                  blk_upstream_ctx_req_qid, 
    
    input  logic                                blk_upstream_ctx_rsp_vld, 
    input  logic                                blk_upstream_ctx_rsp_forced_shutdown,
    input  logic [7:0]                          blk_upstream_ctx_rsp_generation,                 
    input  logic [9:0]                          blk_upstream_ctx_rsp_dev_id, 
    input  logic [15:0]                         blk_upstream_ctx_rsp_bdf, 

    output logic                                blk_upstream_ptr_rd_req_vld,
    output logic [Q_WIDTH-1:0]                  blk_upstream_ptr_rd_req_qid,
    input  logic                                blk_upstream_ptr_rd_rsp_vld,
    input  logic [15:0]                         blk_upstream_ptr_rd_rsp_dat,

    output logic                                blk_upstream_ptr_wr_req_vld,
    output logic [Q_WIDTH-1:0]                  blk_upstream_ptr_wr_req_qid,
    output logic [15:0]                         blk_upstream_ptr_wr_req_dat,
    //========to mon===================//
    output virtio_vq_t                          mon_send_io_qid,
    output logic                                mon_send_io,

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
        $fsdbDumpvars(0, virtio_blk_upstream_tb, "+all");
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

    beq_txq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   beq2blk_if();
    tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_data_wr_req_if();
    tlp_adap_dma_wr_rsp_if                               dma_data_wr_rsp_if();

    assign beq2blk_sav                = beq2blk_if.sav;
    assign beq2blk_if.vld             = beq2blk_vld;
    assign beq2blk_if.sop             = beq2blk_sop;
    assign beq2blk_if.eop             = beq2blk_eop;
    assign beq2blk_if.sbd             = beq2blk_sbd;
    assign beq2blk_if.sty             = beq2blk_sty;
    assign beq2blk_if.mty             = beq2blk_mty;
    assign beq2blk_if.data            = beq2blk_data;

    assign dma_data_wr_req_if.sav            = dma_data_wr_req_sav;
    assign dma_data_wr_req_sop               = dma_data_wr_req_if.sop;
    assign dma_data_wr_req_eop               = dma_data_wr_req_if.eop;
    assign dma_data_wr_req_val               = dma_data_wr_req_if.vld;
    assign dma_data_wr_req_data              = dma_data_wr_req_if.data;
    assign dma_data_wr_req_sty               = dma_data_wr_req_if.sty;
    assign dma_data_wr_req_mty               = dma_data_wr_req_if.mty;
    clear_x #(.DW($bits(desc_t))) u_dma_data_wr_req_desc_clearx (.in(dma_data_wr_req_if.desc), .out(dma_data_wr_req_desc));
    assign dma_data_wr_rsp_if.vld            = dma_data_wr_rsp_val;
    assign dma_data_wr_rsp_if.rd2rsp_loop    = dma_data_wr_rsp_rd2rsp_loop;

    virtio_blk_upstream_top #(
        .Q_NUM       (Q_NUM      ),
        .Q_WIDTH     (Q_WIDTH    ),
        .DATA_WIDTH  (DATA_WIDTH ),
        .EMPTH_WIDTH (EMPTH_WIDTH)
    ) u_virtio_blk_upstream_top(
        .clk                                  (clk),
        .rst                                  (rst),
        .beq2blk_if                           (beq2blk_if),
        .dma_data_wr_req_if                   (dma_data_wr_req_if),
        .dma_data_wr_rsp_if                   (dma_data_wr_rsp_if),
        .wr_used_info_vld                     (wr_used_info_vld),
        .wr_used_info_dat                     (wr_used_info_dat),
        .wr_used_info_rdy                     (wr_used_info_rdy),
        .blk_upstream_ctx_req_vld             (blk_upstream_ctx_req_vld),
        .blk_upstream_ctx_req_qid             (blk_upstream_ctx_req_qid),
        .blk_upstream_ctx_rsp_vld             (blk_upstream_ctx_rsp_vld),
        .blk_upstream_ctx_rsp_forced_shutdown (blk_upstream_ctx_rsp_forced_shutdown),
        .blk_upstream_ctx_rsp_generation      (blk_upstream_ctx_rsp_generation),
        .blk_upstream_ctx_rsp_dev_id          (blk_upstream_ctx_rsp_dev_id),
        .blk_upstream_ctx_rsp_bdf             (blk_upstream_ctx_rsp_bdf),
        .blk_upstream_ptr_rd_req_vld          (blk_upstream_ptr_rd_req_vld),
        .blk_upstream_ptr_rd_req_qid          (blk_upstream_ptr_rd_req_qid),
        .blk_upstream_ptr_rd_rsp_vld          (blk_upstream_ptr_rd_rsp_vld),
        .blk_upstream_ptr_rd_rsp_dat          (blk_upstream_ptr_rd_rsp_dat),
        .blk_upstream_ptr_wr_req_vld          (blk_upstream_ptr_wr_req_vld),
        .blk_upstream_ptr_wr_req_qid          (blk_upstream_ptr_wr_req_qid),
        .blk_upstream_ptr_wr_req_dat          (blk_upstream_ptr_wr_req_dat),
        .mon_send_io_qid                      (mon_send_io_qid),
        .mon_send_io                          (mon_send_io),
        .dfx_if                               (csr_if)
    );

  endmodule

