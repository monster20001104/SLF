/******************************************************************************
 * 文件名称 : virtio_avail_ring_tb.sv
 * 作者名称 : Feilong Yun
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/23     Feilong Yun   初始化版本
******************************************************************************/
 `include "virtio_avail_ring_define.svh"
module virtio_avail_ring_tb 
    import alt_tlp_adaptor_pkg::*;
    #(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM)

 )(

    input                        clk,
    input                        rst,

    input                        sch_req_vld,
    output logic                 sch_req_rdy,
    input  [$bits(virtio_vq_t)-1:0]           sch_req_qid,

    output                       dma_ring_id_rd_req_val,
    output                       dma_ring_id_rd_req_sty,
    output   [$bits(desc_t)-1:0] dma_ring_id_rd_req_desc,
    input                        dma_ring_id_rd_req_sav,

    input                        dma_ring_id_rd_rsp_val,
    input                        dma_ring_id_rd_rsp_sop,
    input                        dma_ring_id_rd_rsp_eop,
    input                        dma_ring_id_rd_rsp_err,
    input   [DATA_WIDTH-1:0]dma_ring_id_rd_rsp_data,
    input   [DATA_EMPTY-1:0]dma_ring_id_rd_rsp_sty,
    input   [DATA_EMPTY-1:0]dma_ring_id_rd_rsp_mty,
    input    [$bits(desc_t)-1:0] dma_ring_id_rd_rsp_desc,

    output                       avail_addr_rd_req_vld,
    output   [$bits(virtio_vq_t)-1:0]avail_addr_rd_req_qid,
    input                        avail_addr_rd_req_rdy,

    input                        avail_addr_rd_rsp_vld,
    input     [63:0]             avail_addr_rd_rsp_data,

    output                       avail_ui_wr_req_vld,
    output    [15:0]             avail_ui_wr_req_data,
    output    [$bits(virtio_vq_t)-1:0]avail_ui_wr_req_qid,

    output                       avail_pi_wr_req_vld,
    output    [15:0]             avail_pi_wr_req_data,
    output    [$bits(virtio_vq_t)-1:0]avail_pi_wr_req_qid,

    output                       nettx_notify_req_vld,
    output   [VIRTIO_Q_WIDTH-1:0]     nettx_notify_req_qid,
    input                        nettx_notify_req_rdy,

    output                       blk_notify_req_vld,
    output   [VIRTIO_Q_WIDTH-1:0] blk_notify_req_qid,
    input                        blk_notify_req_rdy,

    output                       dma_ctx_info_rd_req_vld,
    output   [$bits(virtio_vq_t)-1:0]dma_ctx_info_rd_req_qid,

    input                        dma_ctx_info_rd_rsp_vld,
    input                        dma_ctx_info_rd_rsp_force_shutdown,
    input     [$bits(virtio_qstat_t)-1:0]              dma_ctx_info_rd_rsp_ctrl,
    input     [15:0]             dma_ctx_info_rd_rsp_bdf,
    input     [15:0]             dma_ctx_info_rd_rsp_qdepth,
    input     [15:0]             dma_ctx_info_rd_rsp_avail_idx,
    input     [15:0]             dma_ctx_info_rd_rsp_avail_ui,
    input     [15:0]             dma_ctx_info_rd_rsp_avail_ci,

    input                        netrx_avail_id_req_vld,
    input    [VIRTIO_Q_WIDTH-1:0]     netrx_avail_id_req_data,
    input    [3:0]               netrx_avail_id_req_nid,
    output                       netrx_avail_id_req_rdy,

    output                       netrx_avail_id_rsp_vld,
    output [$bits(virtio_avail_id_rsp_dat_t)-1:0]  netrx_avail_id_rsp_data,
    output                       netrx_avail_id_rsp_eop,
    input                        netrx_avail_id_rsp_rdy,

    input                        nettx_avail_id_req_vld,
    input    [VIRTIO_Q_WIDTH-1:0]     nettx_avail_id_req_data,
    input    [3:0]               nettx_avail_id_req_nid,
    output                       nettx_avail_id_req_rdy,

    output                       nettx_avail_id_rsp_vld,
    output [$bits(virtio_avail_id_rsp_dat_t)-1:0] nettx_avail_id_rsp_data,
    output                       nettx_avail_id_rsp_eop,
    input                        nettx_avail_id_rsp_rdy,

    input                        blk_avail_id_req_vld,
    input    [VIRTIO_Q_WIDTH-1:0]     blk_avail_id_req_data,
    input    [3:0]               blk_avail_id_req_nid,
    output                       blk_avail_id_req_rdy,

    output                       blk_avail_id_rsp_vld,
    output [$bits(virtio_avail_id_rsp_dat_t)-1:0] blk_avail_id_rsp_data,
    output                       blk_avail_id_rsp_eop,
    input                        blk_avail_id_rsp_rdy,

    output                       avail_ci_wr_req_vld,
    output    [15:0]             avail_ci_wr_req_data,
    output    [$bits(virtio_vq_t)-1:0]avail_ci_wr_req_qid,

    output                       desc_engine_ctx_info_rd_req_vld,
    output   [$bits(virtio_vq_t)-1:0]desc_engine_ctx_info_rd_req_qid,

    input                        desc_engine_ctx_info_rd_rsp_vld,
    input                        desc_engine_ctx_info_rd_rsp_force_shutdown,
    input     [$bits(virtio_qstat_t)-1:0]              desc_engine_ctx_info_rd_rsp_ctrl,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_pi,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_idx,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_ui,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_ci,
    input                        vq_pending_chk_req_vld  ,
    input    [$bits(virtio_vq_t)-1:0]         vq_pending_chk_req_vq   ,
    output                       vq_pending_chk_rsp_vld  ,
    output                       vq_pending_chk_rsp_busy 

    
 );

logic                             notify_req_vld;
logic  [$bits(virtio_vq_t)-1:0]   notify_req_qid;
logic                             notify_req_rdy;
logic                             notify_rsp_vld;
logic  [$bits(virtio_vq_t)-1:0]   notify_rsp_qid;
logic                             notify_rsp_cold;
logic                             notify_rsp_done;
logic                             notify_rsp_rdy;

mlite_if #(.ADDR_WIDTH (64), .DATA_WIDTH (64), .CHANNEL_NUM(1))   mlite_master();

    tlp_adap_dma_rd_req_if #(.DATA_WIDTH(DATA_WIDTH)) dma_ring_id_rd_req ();
    assign dma_ring_id_rd_req_val  = dma_ring_id_rd_req.vld;
    assign dma_ring_id_rd_req.sav  = dma_ring_id_rd_req_sav;
    assign dma_ring_id_rd_req_sty  = dma_ring_id_rd_req.sty;
    assign dma_ring_id_rd_req_desc = dma_ring_id_rd_req.desc;
    tlp_adap_dma_rd_rsp_if #(.DATA_WIDTH(DATA_WIDTH)) dma_ring_id_rd_rsp ();
    assign dma_ring_id_rd_rsp.vld  = dma_ring_id_rd_rsp_val;
    assign dma_ring_id_rd_rsp.sop  = dma_ring_id_rd_rsp_sop;
    assign dma_ring_id_rd_rsp.eop  = dma_ring_id_rd_rsp_eop;
    assign dma_ring_id_rd_rsp.err  = dma_ring_id_rd_rsp_err;
    assign dma_ring_id_rd_rsp.data = dma_ring_id_rd_rsp_data;
    assign dma_ring_id_rd_rsp.sty  = dma_ring_id_rd_rsp_sty;
    assign dma_ring_id_rd_rsp.mty  = dma_ring_id_rd_rsp_mty;
    assign dma_ring_id_rd_rsp.desc = dma_ring_id_rd_rsp_desc;

 virtio_sch #(
    .WEIGHT_WIDTH(4                     ),
    .VQ_WIDTH    ($bits(virtio_vq_t)    )
) u_virtio_avail_sch (
    .clk            (clk            ),
    .rst            (rst            ),
    .sch_req_vld    (sch_req_vld    ),
    .sch_req_rdy    (sch_req_rdy    ),
    .sch_req_qid    (sch_req_qid    ),
    .notify_req_vld (notify_req_vld ),
    .notify_req_rdy (notify_req_rdy ),
    .notify_req_qid (notify_req_qid ),
    .notify_rsp_vld (notify_rsp_vld ),
    .notify_rsp_rdy (notify_rsp_rdy ),
    .notify_rsp_qid (notify_rsp_qid ),
    .notify_rsp_done(notify_rsp_done),
    .notify_rsp_cold(notify_rsp_cold),
    .hot_weight     ('h2),
    .cold_weight    ('h1),
    .dfx_err        (),
    .dfx_status     (),
    .notify_req_cnt (),
    .notify_rsp_cnt ()
);


virtio_avail_ring #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .DATA_EMPTY ( DATA_EMPTY ),
    .VIRTIO_Q_NUM ( VIRTIO_Q_NUM ),
    .VIRTIO_Q_WIDTH ( VIRTIO_Q_WIDTH)

)u_virtio_avail_ring(

   .clk   ( clk ),
   .rst  ( rst ),

   .notify_req_vld  ( notify_req_vld ),
   .notify_req_qid  ( notify_req_qid ),
   .notify_req_rdy  ( notify_req_rdy ),

   .notify_rsp_vld  ( notify_rsp_vld ),
   .notify_rsp_qid  ( notify_rsp_qid ),
   .notify_rsp_cold  ( notify_rsp_cold ),
   .notify_rsp_done  ( notify_rsp_done ),
   .notify_rsp_rdy  ( notify_rsp_rdy ),

   .dma_ring_id_rd_req ( dma_ring_id_rd_req ),
   .dma_ring_id_rd_rsp ( dma_ring_id_rd_rsp ),

   .avail_addr_rd_req_vld  ( avail_addr_rd_req_vld ),
   .avail_addr_rd_req_qid  ( avail_addr_rd_req_qid ),
   .avail_addr_rd_req_rdy  ( avail_addr_rd_req_rdy ),

   .avail_addr_rd_rsp_vld  ( avail_addr_rd_rsp_vld ),
   .avail_addr_rd_rsp_data  ( avail_addr_rd_rsp_data ),

   .avail_ui_wr_req_vld  ( avail_ui_wr_req_vld ) ,
   .avail_ui_wr_req_data  ( avail_ui_wr_req_data ),
   .avail_ui_wr_req_qid  ( avail_ui_wr_req_qid ),

   .avail_pi_wr_req_vld  ( avail_pi_wr_req_vld ),
   .avail_pi_wr_req_data  ( avail_pi_wr_req_data ),
   .avail_pi_wr_req_qid  ( avail_pi_wr_req_qid ),

   .nettx_notify_req_vld  ( nettx_notify_req_vld ),
   .nettx_notify_req_qid  ( nettx_notify_req_qid ),
   .nettx_notify_req_rdy  ( nettx_notify_req_rdy ),

   .blk_notify_req_vld  ( blk_notify_req_vld ),
   .blk_notify_req_qid  ( blk_notify_req_qid ),
   .blk_notify_req_rdy  ( blk_notify_req_rdy ),

   .dma_ctx_info_rd_req_vld  ( dma_ctx_info_rd_req_vld ),
   .dma_ctx_info_rd_req_qid  ( dma_ctx_info_rd_req_qid ),

   .dma_ctx_info_rd_rsp_vld  ( dma_ctx_info_rd_rsp_vld ),
   .dma_ctx_info_rd_rsp_force_shutdown  ( dma_ctx_info_rd_rsp_force_shutdown ),
   .dma_ctx_info_rd_rsp_ctrl  ( dma_ctx_info_rd_rsp_ctrl ),
   .dma_ctx_info_rd_rsp_bdf  ( dma_ctx_info_rd_rsp_bdf ),
   .dma_ctx_info_rd_rsp_qdepth  ( dma_ctx_info_rd_rsp_qdepth ),
   .dma_ctx_info_rd_rsp_avail_idx  ( dma_ctx_info_rd_rsp_avail_idx ),
   .dma_ctx_info_rd_rsp_avail_ui  ( dma_ctx_info_rd_rsp_avail_ui ),
   .dma_ctx_info_rd_rsp_avail_ci  ( dma_ctx_info_rd_rsp_avail_ci ),

   .netrx_avail_id_req_vld  ( netrx_avail_id_req_vld ),
   .netrx_avail_id_req_data  ( netrx_avail_id_req_data ),
   .netrx_avail_id_req_nid   ( netrx_avail_id_req_nid ),
   .netrx_avail_id_req_rdy  ( netrx_avail_id_req_rdy ),

   .netrx_avail_id_rsp_vld  ( netrx_avail_id_rsp_vld ),
   .netrx_avail_id_rsp_data  ( netrx_avail_id_rsp_data ),
   .netrx_avail_id_rsp_eop   ( netrx_avail_id_rsp_eop ),
   .netrx_avail_id_rsp_rdy  ( netrx_avail_id_rsp_rdy ),

   .nettx_avail_id_req_vld  ( nettx_avail_id_req_vld ),
   .nettx_avail_id_req_data  ( nettx_avail_id_req_data ),
   .nettx_avail_id_req_nid   ( nettx_avail_id_req_nid ),
   .nettx_avail_id_req_rdy  ( nettx_avail_id_req_rdy ),

   .nettx_avail_id_rsp_vld  ( nettx_avail_id_rsp_vld ),
   .nettx_avail_id_rsp_data  ( nettx_avail_id_rsp_data ),
   .nettx_avail_id_rsp_eop   ( nettx_avail_id_rsp_eop ),
   .nettx_avail_id_rsp_rdy  ( nettx_avail_id_rsp_rdy ),

   .blk_avail_id_req_vld  ( blk_avail_id_req_vld ),
   .blk_avail_id_req_data  ( blk_avail_id_req_data ),
   .blk_avail_id_req_nid   ( blk_avail_id_req_nid ),
   .blk_avail_id_req_rdy  ( blk_avail_id_req_rdy ),

   .blk_avail_id_rsp_vld  ( blk_avail_id_rsp_vld ),
   .blk_avail_id_rsp_data  ( blk_avail_id_rsp_data ),
   .blk_avail_id_rsp_eop   ( blk_avail_id_rsp_eop ),
   .blk_avail_id_rsp_rdy  ( blk_avail_id_rsp_rdy ),

   .avail_ci_wr_req_vld  ( avail_ci_wr_req_vld ),
   .avail_ci_wr_req_data  ( avail_ci_wr_req_data ),
   .avail_ci_wr_req_qid  ( avail_ci_wr_req_qid ),

   .desc_engine_ctx_info_rd_req_vld  ( desc_engine_ctx_info_rd_req_vld ),
   .desc_engine_ctx_info_rd_req_qid  ( desc_engine_ctx_info_rd_req_qid ),

   .desc_engine_ctx_info_rd_rsp_vld  ( desc_engine_ctx_info_rd_rsp_vld ),
   .desc_engine_ctx_info_rd_rsp_force_shutdown  ( desc_engine_ctx_info_rd_rsp_force_shutdown ),
   .desc_engine_ctx_info_rd_rsp_ctrl  ( desc_engine_ctx_info_rd_rsp_ctrl ),
   .desc_engine_ctx_info_rd_rsp_avail_pi  ( desc_engine_ctx_info_rd_rsp_avail_pi ),
   .desc_engine_ctx_info_rd_rsp_avail_idx ( desc_engine_ctx_info_rd_rsp_avail_idx ),
   .desc_engine_ctx_info_rd_rsp_avail_ui  ( desc_engine_ctx_info_rd_rsp_avail_ui ),
   .desc_engine_ctx_info_rd_rsp_avail_ci  ( desc_engine_ctx_info_rd_rsp_avail_ci ),
   .vq_pending_chk_req_vld                ( vq_pending_chk_req_vld               ),
   .vq_pending_chk_req_vq                 ( vq_pending_chk_req_vq                ),
   .vq_pending_chk_rsp_vld                ( vq_pending_chk_rsp_vld               ),
   .vq_pending_chk_rsp_busy               ( vq_pending_chk_rsp_busy              ),


   .dfx_slave   ( mlite_master )

        
    
 );

initial begin
      $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
      $fsdbDumpvars(0, virtio_avail_ring_tb, "+all");
      $fsdbDumpMDA();
end

endmodule
