/******************************************************************************
 * 文件名称 : virtio_desc_engine_core_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/07/09
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/09     Joe Jiang   初始化版本
 ******************************************************************************/
 `include "tlp_adap_dma_if.svh"
 `include "virtio_define.svh"
 `include "virtio_desc_engine_define.svh"

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
 
 module virtio_desc_engine_core_tb 
 import alt_tlp_adaptor_pkg::*;
 #(
   parameter Q_NUM                          = `VIRTIO_Q_NUM,
   parameter Q_WIDTH                        = $clog2(Q_NUM),
   parameter DEV_ID_NUM                     = `DEV_NUM,
   parameter DEV_ID_WIDTH                   = $clog2(DEV_ID_NUM),
   parameter DATA_WIDTH                     = `DATA_WIDTH,
   parameter EMPTH_WIDTH                    = $clog2(DATA_WIDTH/8),
   parameter PKT_ID_NUM                     = `VIRTIO_RX_BUF_PKT_NUM,
   parameter PKT_ID_WIDTH                   = $clog2(PKT_ID_NUM),
   parameter SLOT_NUM                       = `VIRTIO_DESC_ENG_SLOT_NUM,
   parameter SLOT_WIDTH                     = $clog2(SLOT_NUM),
   parameter BUCKET_NUM                     = `VIRTIO_DESC_ENG_BUCKET_NUM,
   parameter BUCKET_WIDTH                   = $clog2(BUCKET_NUM),
   parameter LINE_NUM                       = `VIRTIO_DESC_ENG_LINE_NUM,
   parameter LINE_WIDTH                     = $clog2(LINE_NUM),
   parameter DESC_PER_BUCKET_NUM            = LINE_NUM*DATA_WIDTH/$bits(virtq_desc_t),
   parameter DESC_PER_BUCKET_WIDTH          = $clog2(DESC_PER_BUCKET_NUM),
   parameter DESC_BUF_DEPTH                 = (BUCKET_NUM*LINE_NUM),
   parameter MAX_CHAIN_SIZE                 = 128,
   parameter MAX_BUCKET_PER_SLOT            = MAX_CHAIN_SIZE/LINE_NUM/(DATA_WIDTH/$bits(virtq_desc_t)),
   parameter MAX_BUCKET_PER_SLOT_WIDTH      = $clog2(MAX_BUCKET_PER_SLOT)
 ) (
    input                                                       clk,
    input                                                       rst,

    // Read request interface from DMA core
    input      logic                                           dma_desc_rd_req_sav  ,
    output     logic                                           dma_desc_rd_req_val  ,
    output     logic  [EMPTH_WIDTH-1:0]                        dma_desc_rd_req_sty  ,
    output     logic  [$bits(desc_t)-1:0]                      dma_desc_rd_req_desc ,
    // Read response interface back to DMA core             
    input      logic                                           dma_desc_rd_rsp_val  ,
    input      logic                                           dma_desc_rd_rsp_sop  ,
    input      logic                                           dma_desc_rd_rsp_eop  ,
    input      logic                                           dma_desc_rd_rsp_err  ,
    input      logic  [DATA_WIDTH-1:0]                         dma_desc_rd_rsp_data ,
    input      logic  [EMPTH_WIDTH-1:0]                        dma_desc_rd_rsp_sty  ,
    input      logic  [EMPTH_WIDTH-1:0]                        dma_desc_rd_rsp_mty  ,
    input      logic  [$bits(desc_t)-1:0]                      dma_desc_rd_rsp_desc ,

    input  logic                                                slot_submit_vld,
    input  logic [SLOT_WIDTH-1:0]                               slot_submit_slot_id,
    input  logic [$bits(virtio_vq_t)-1:0]                       slot_submit_vq,
    input  logic [DEV_ID_WIDTH-1:0]                             slot_submit_dev_id,
    input  logic [PKT_ID_WIDTH-1:0]                             slot_submit_pkt_id,
    input  logic [15:0]                                         slot_submit_ring_id,
    input  logic [15:0]                                         slot_submit_avail_idx,
    input  logic [$bits(virtio_err_info_t)-1:0]                 slot_submit_err,
    output logic                                                slot_submit_rdy,

    output logic                                                slot_cpl_vld,
    output logic [SLOT_WIDTH-1:0]                               slot_cpl_slot_id,
    output logic [$bits(virtio_vq_t)-1:0]                       slot_cpl_vq,
    input  logic                                                slot_cpl_sav,

    input  logic                                                rd_desc_req_vld,
    input  logic [SLOT_WIDTH-1:0]                               rd_desc_req_slot_id,
    output logic                                                rd_desc_req_rdy,

    output logic                                                rd_desc_rsp_vld,
    output logic [$bits(virtio_desc_eng_desc_rsp_sbd_t)-1:0]    rd_desc_rsp_sbd,
    output logic                                                rd_desc_rsp_sop,
    output logic                                                rd_desc_rsp_eop,
    output logic [$bits(virtq_desc_t)-1:0]                      rd_desc_rsp_dat,
    input  logic                                                rd_desc_rsp_rdy,

    output logic                                                ctx_info_rd_req_vld,
    output logic [$bits(virtio_vq_t)-1:0]                       ctx_info_rd_req_vq,
    input  logic                                                ctx_info_rd_rsp_vld,
    input  logic [63:0]                                         ctx_info_rd_rsp_desc_tbl_addr,
    input  logic [3:0]                                          ctx_info_rd_rsp_qdepth,
    input  logic                                                ctx_info_rd_rsp_forced_shutdown,
    input  logic                                                ctx_info_rd_rsp_indirct_support,
    input  logic [19:0]                                         ctx_info_rd_rsp_max_len,
    input  logic [15:0]                                         ctx_info_rd_rsp_bdf,

    output logic                                                ctx_slot_chain_rd_req_vld,
    output logic [$bits(virtio_vq_t)-1:0]                       ctx_slot_chain_rd_req_vq,
    input  logic                                                ctx_slot_chain_rd_rsp_vld,
    input  logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_rd_rsp_head_slot,
    input  logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_rd_rsp_head_slot_vld,
    input  logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_rd_rsp_tail_slot,
    output logic                                                ctx_slot_chain_wr_vld,
    output logic [$bits(virtio_vq_t)-1:0]                       ctx_slot_chain_wr_vq,
    output logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_wr_head_slot,
    output logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_wr_head_slot_vld,
    output logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_wr_tail_slot
 );

   initial begin
      $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
      $fsdbDumpvars(0, virtio_desc_engine_core_tb, "+all");
      $fsdbDumpMDA();
   end

   tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_desc_rd_req_if();
   tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_desc_rd_rsp_if();

   assign dma_desc_rd_req_if.sav            = dma_desc_rd_req_sav;
   assign dma_desc_rd_req_val               = dma_desc_rd_req_if.vld;
   assign dma_desc_rd_req_sty               = dma_desc_rd_req_if.sty;
   assign dma_desc_rd_req_desc              = dma_desc_rd_req_if.desc;

   assign dma_desc_rd_rsp_if.vld            = dma_desc_rd_rsp_val;
   assign dma_desc_rd_rsp_if.sop            = dma_desc_rd_rsp_sop;
   assign dma_desc_rd_rsp_if.eop            = dma_desc_rd_rsp_eop;
   assign dma_desc_rd_rsp_if.sty            = dma_desc_rd_rsp_sty;
   assign dma_desc_rd_rsp_if.mty            = dma_desc_rd_rsp_mty;
   assign dma_desc_rd_rsp_if.data           = dma_desc_rd_rsp_data;
   assign dma_desc_rd_rsp_if.err            = dma_desc_rd_rsp_err;
   assign dma_desc_rd_rsp_if.desc           = dma_desc_rd_rsp_desc;


   virtio_desc_engine_core #(
      .Q_NUM                    (Q_NUM                    ),
      .Q_WIDTH                  (Q_WIDTH                  ),
      .DEV_ID_NUM               (DEV_ID_NUM               ),
      .DEV_ID_WIDTH             (DEV_ID_WIDTH             ),
      .DATA_WIDTH               (DATA_WIDTH               ),
      .EMPTH_WIDTH              (EMPTH_WIDTH              ),
      .PKT_ID_NUM               (PKT_ID_NUM               ),
      .PKT_ID_WIDTH             (PKT_ID_WIDTH             ),
      .SLOT_NUM                 (SLOT_NUM                 ),
      .SLOT_WIDTH               (SLOT_WIDTH               ),
      .BUCKET_NUM               (BUCKET_NUM               ),
      .BUCKET_WIDTH             (BUCKET_WIDTH             ),
      .LINE_NUM                 (LINE_NUM                 ),
      .LINE_WIDTH               (LINE_WIDTH               ),
      .DESC_PER_BUCKET_NUM      (DESC_PER_BUCKET_NUM      ),
      .DESC_PER_BUCKET_WIDTH    (DESC_PER_BUCKET_WIDTH    ),
      .DESC_BUF_DEPTH           (DESC_BUF_DEPTH           ),
      .MAX_CHAIN_SIZE           (MAX_CHAIN_SIZE           ),
      .MAX_BUCKET_PER_SLOT      (MAX_BUCKET_PER_SLOT      ),
      .MAX_BUCKET_PER_SLOT_WIDTH(MAX_BUCKET_PER_SLOT_WIDTH)
   )u_virtio_desc_engine_core(
      .clk                                   (clk                                   ),
      .rst                                   (rst                                   ),

      .dma_desc_rd_req_if                    (dma_desc_rd_req_if                    ),
      .dma_desc_rd_rsp_if                    (dma_desc_rd_rsp_if                    ),

      .slot_submit_vld                       (slot_submit_vld                       ),
      .slot_submit_slot_id                   (slot_submit_slot_id                   ),
      .slot_submit_vq                        (slot_submit_vq                        ),
      .slot_submit_dev_id                    (slot_submit_dev_id                    ),
      .slot_submit_pkt_id                    (slot_submit_pkt_id                    ),
      .slot_submit_ring_id                   (slot_submit_ring_id                   ),
      .slot_submit_avail_idx                 (slot_submit_avail_idx                 ),
      .slot_submit_err                       (slot_submit_err                       ),
      .slot_submit_rdy                       (slot_submit_rdy                       ),
      .slot_cpl_vld                          (slot_cpl_vld                          ),
      .slot_cpl_slot_id                      (slot_cpl_slot_id                      ),
      .slot_cpl_vq                           (slot_cpl_vq                           ),
      .slot_cpl_sav                          (slot_cpl_sav                          ),
      .rd_desc_req_vld                       (rd_desc_req_vld                       ),
      .rd_desc_req_slot_id                   (rd_desc_req_slot_id                   ),
      .rd_desc_req_rdy                       (rd_desc_req_rdy                       ),                            
      .rd_desc_rsp_vld                       (rd_desc_rsp_vld                       ),
      .rd_desc_rsp_sbd                       (rd_desc_rsp_sbd                       ),
      .rd_desc_rsp_sop                       (rd_desc_rsp_sop                       ),
      .rd_desc_rsp_eop                       (rd_desc_rsp_eop                       ),
      .rd_desc_rsp_dat                       (rd_desc_rsp_dat                       ),
      .rd_desc_rsp_rdy                       (rd_desc_rsp_rdy                       ),
      .ctx_info_rd_req_vld                   (ctx_info_rd_req_vld                   ),
      .ctx_info_rd_req_vq                    (ctx_info_rd_req_vq                    ),
      .ctx_info_rd_rsp_vld                   (ctx_info_rd_rsp_vld                   ),
      .ctx_info_rd_rsp_desc_tbl_addr         (ctx_info_rd_rsp_desc_tbl_addr         ),   
      .ctx_info_rd_rsp_qdepth                (ctx_info_rd_rsp_qdepth                ),
      .ctx_info_rd_rsp_forced_shutdown       (ctx_info_rd_rsp_forced_shutdown       ),   
      .ctx_info_rd_rsp_indirct_support       (ctx_info_rd_rsp_indirct_support       ),   
      .ctx_info_rd_rsp_max_len               (ctx_info_rd_rsp_max_len               ),
      .ctx_info_rd_rsp_bdf                   (ctx_info_rd_rsp_bdf                   ),
      .ctx_slot_chain_rd_req_vld             (ctx_slot_chain_rd_req_vld             ),
      .ctx_slot_chain_rd_req_vq              (ctx_slot_chain_rd_req_vq              ),
      .ctx_slot_chain_rd_rsp_vld             (ctx_slot_chain_rd_rsp_vld             ),
      .ctx_slot_chain_rd_rsp_head_slot       (ctx_slot_chain_rd_rsp_head_slot       ),
      .ctx_slot_chain_rd_rsp_head_slot_vld   (ctx_slot_chain_rd_rsp_head_slot_vld   ),
      .ctx_slot_chain_rd_rsp_tail_slot       (ctx_slot_chain_rd_rsp_tail_slot       ),
      .ctx_slot_chain_wr_vld                 (ctx_slot_chain_wr_vld                 ),
      .ctx_slot_chain_wr_vq                  (ctx_slot_chain_wr_vq                  ),       
      .ctx_slot_chain_wr_head_slot           (ctx_slot_chain_wr_head_slot           ),
      .ctx_slot_chain_wr_head_slot_vld       (ctx_slot_chain_wr_head_slot_vld       ),
      .ctx_slot_chain_wr_tail_slot           (ctx_slot_chain_wr_tail_slot           )
   );

 endmodule