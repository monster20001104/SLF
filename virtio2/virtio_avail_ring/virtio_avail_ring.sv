/******************************************************************************
 *              : virtio_avail_ring.sv
 *              : Feilong Yun
 *              : 2025/06/23
 *              : 
 *
 *              : 
 *
 *                                                     
 * v1.0  06/23     Feilong Yun                  
******************************************************************************/
 `include "virtio_avail_ring_define.svh"
  `include "tlp_adap_dma_if.svh"

module virtio_avail_ring 
    import alt_tlp_adaptor_pkg::*;
#(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM),
    parameter DFX_ADDR_OFFSET  = 0

 ) (
    input                        clk,
    input                        rst,

    input                        notify_req_vld,
    input     virtio_vq_t        notify_req_qid,
    output                       notify_req_rdy,

    output                       notify_rsp_vld,
    output   virtio_vq_t         notify_rsp_qid,
    output                       notify_rsp_cold,
    output                       notify_rsp_done,
    input                        notify_rsp_rdy,

    tlp_adap_dma_rd_req_if.src   dma_ring_id_rd_req,
    tlp_adap_dma_rd_rsp_if.snk   dma_ring_id_rd_rsp,

    output                       avail_addr_rd_req_vld,
    output   virtio_vq_t         avail_addr_rd_req_qid,
    input                        avail_addr_rd_req_rdy,

    input                        avail_addr_rd_rsp_vld,
    input     [63:0]             avail_addr_rd_rsp_data,

    output                       avail_ui_wr_req_vld,
    output    [15:0]             avail_ui_wr_req_data,
    output    virtio_vq_t        avail_ui_wr_req_qid,

    output                       avail_pi_wr_req_vld,
    output    [15:0]             avail_pi_wr_req_data,
    output    virtio_vq_t        avail_pi_wr_req_qid,

    output                       nettx_notify_req_vld,
    output   [VIRTIO_Q_WIDTH-1:0]nettx_notify_req_qid,
    input                        nettx_notify_req_rdy,

    output                       blk_notify_req_vld,
    output   [VIRTIO_Q_WIDTH-1:0] blk_notify_req_qid,
    input                        blk_notify_req_rdy,

    output                       dma_ctx_info_rd_req_vld,
    output   virtio_vq_t         dma_ctx_info_rd_req_qid,

    input                        dma_ctx_info_rd_rsp_vld,
    input                        dma_ctx_info_rd_rsp_force_shutdown,
    input     [$bits(virtio_qstat_t)-1:0]dma_ctx_info_rd_rsp_ctrl,
    input     [15:0]             dma_ctx_info_rd_rsp_bdf,
    input     [3:0]              dma_ctx_info_rd_rsp_qdepth,
    input     [15:0]             dma_ctx_info_rd_rsp_avail_idx,
    input     [15:0]             dma_ctx_info_rd_rsp_avail_ui,
    input     [15:0]             dma_ctx_info_rd_rsp_avail_ci,

    input                        netrx_avail_id_req_vld,
    input    [VIRTIO_Q_WIDTH-1:0]netrx_avail_id_req_data,
    input    [3:0]               netrx_avail_id_req_nid,
    output                       netrx_avail_id_req_rdy,

    output                       netrx_avail_id_rsp_vld,
    output virtio_avail_id_rsp_dat_t netrx_avail_id_rsp_data,
    output   logic               netrx_avail_id_rsp_eop,
    input                        netrx_avail_id_rsp_rdy,

    input                        nettx_avail_id_req_vld,
    input    [VIRTIO_Q_WIDTH-1:0]nettx_avail_id_req_data,
    input    [3:0]               nettx_avail_id_req_nid,
    output                       nettx_avail_id_req_rdy,

    output                       nettx_avail_id_rsp_vld,
    output virtio_avail_id_rsp_dat_t nettx_avail_id_rsp_data,
    output   logic               nettx_avail_id_rsp_eop,
    input                        nettx_avail_id_rsp_rdy,

    input                        blk_avail_id_req_vld,
    input    [VIRTIO_Q_WIDTH-1:0]blk_avail_id_req_data,
    input    [3:0]               blk_avail_id_req_nid,
    output                       blk_avail_id_req_rdy,

    output                       blk_avail_id_rsp_vld,
    output virtio_avail_id_rsp_dat_t blk_avail_id_rsp_data,
    output   logic               blk_avail_id_rsp_eop,
    input                        blk_avail_id_rsp_rdy,

    output                       avail_ci_wr_req_vld,
    output    [15:0]             avail_ci_wr_req_data,
    output    virtio_vq_t        avail_ci_wr_req_qid,

    output                       desc_engine_ctx_info_rd_req_vld,
    output   virtio_vq_t         desc_engine_ctx_info_rd_req_qid,

    input                        desc_engine_ctx_info_rd_rsp_vld,
    input                        desc_engine_ctx_info_rd_rsp_force_shutdown,
    input     [$bits(virtio_qstat_t)-1:0]desc_engine_ctx_info_rd_rsp_ctrl,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_pi,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_idx,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_ui,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_ci,

    input                        vq_pending_chk_req_vld  ,
    input    virtio_vq_t         vq_pending_chk_req_vq   ,
    output                       vq_pending_chk_rsp_vld  ,
    output                       vq_pending_chk_rsp_busy ,

    mlite_if.slave               dfx_slave


 );

    logic                        rd_ring_id_nettx_req_vld   ;
    logic   [VIRTIO_Q_WIDTH+4:0] rd_ring_id_nettx_req_addr  ;
    logic                        rd_ring_id_nettx_rsp_vld   ;
    logic   [17:0]               rd_ring_id_nettx_rsp_data  ;

    logic                        rd_ring_id_netrx_req_vld   ;
    logic   [VIRTIO_Q_WIDTH+4:0] rd_ring_id_netrx_req_addr  ;
    logic                        rd_ring_id_netrx_rsp_vld   ;
    logic   [17:0]               rd_ring_id_netrx_rsp_data  ;

    logic                        rd_ring_id_blk_req_vld     ;
    logic   [VIRTIO_Q_WIDTH+4:0] rd_ring_id_blk_req_addr    ;
    logic                        rd_ring_id_blk_rsp_vld     ;
    logic   [17:0]               rd_ring_id_blk_rsp_data    ;

    logic   [63:0]               dfx_err[1:0]               ;
    logic   [63:0]               dfx_status[1:0]            ;


    logic   [7:0]                rd_issued_cnt              ;
    logic   [7:0]                rd_rsp_cnt                 ;

    logic   [19:0]               netrx_local_ring_empty_cnt ;
    logic   [19:0]               netrx_avail_ring_empty_cnt ;
    logic   [19:0]               netrx_ring_empty_diff_cnt  ;
               
    logic   [19:0]               nettx_local_ring_empty_cnt ;
    logic   [19:0]               nettx_avail_ring_empty_cnt ;
    logic   [19:0]               nettx_ring_empty_diff_cnt  ;
               
    logic   [19:0]               blk_local_ring_empty_cnt   ;
    logic   [19:0]               blk_avail_ring_empty_cnt   ;
    logic   [19:0]               blk_ring_empty_diff_cnt    ;

    logic   [63:0]               dfx_ring_empty_cnt0        ;
    logic   [63:0]               dfx_ring_empty_cnt1        ;   
    logic   [63:0]               dfx_ring_empty_cnt2        ; 

    localparam NETTX_PERQ_RING_ID_NUM = 32;
    localparam NETRX_PERQ_RING_ID_NUM = 32;
    localparam BLK_PERQ_RING_ID_NUM = 8;
//netrx
   always @(posedge clk) begin
      if (rst) begin
         netrx_local_ring_empty_cnt <= 20'b0;
      end else begin
         if (netrx_avail_id_rsp_vld && netrx_avail_id_rsp_rdy && netrx_avail_id_rsp_data.local_ring_empty) begin
            netrx_local_ring_empty_cnt <= netrx_local_ring_empty_cnt + 1'b1;
         end
      end
   end

   always @(posedge clk) begin
      if (rst) begin
         netrx_avail_ring_empty_cnt <= 20'b0;
      end else begin
         if (netrx_avail_id_rsp_vld && netrx_avail_id_rsp_rdy && netrx_avail_id_rsp_data.avail_ring_empty) begin
            netrx_avail_ring_empty_cnt <= netrx_avail_ring_empty_cnt + 1'b1;
         end
      end
   end

   always @(posedge clk) begin
      if (rst) begin
         netrx_ring_empty_diff_cnt <= 20'b0;
      end else begin
         netrx_ring_empty_diff_cnt <= netrx_local_ring_empty_cnt - netrx_avail_ring_empty_cnt;
      end
   end

//nettx
   always @(posedge clk) begin
      if (rst) begin
         nettx_local_ring_empty_cnt <= 20'b0;
      end else begin
         if (nettx_avail_id_rsp_vld && nettx_avail_id_rsp_rdy && nettx_avail_id_rsp_data.local_ring_empty) begin
            nettx_local_ring_empty_cnt <= nettx_local_ring_empty_cnt + 1'b1;
         end
      end
   end

   always @(posedge clk) begin
      if (rst) begin
         nettx_avail_ring_empty_cnt <= 20'b0;
      end else begin
         if (nettx_avail_id_rsp_vld && nettx_avail_id_rsp_rdy && nettx_avail_id_rsp_data.avail_ring_empty) begin
            nettx_avail_ring_empty_cnt <= nettx_avail_ring_empty_cnt + 1'b1;
         end
      end
   end

   always @(posedge clk) begin
      if (rst) begin
         nettx_ring_empty_diff_cnt <= 20'b0;
      end else begin
         nettx_ring_empty_diff_cnt <= nettx_local_ring_empty_cnt - nettx_avail_ring_empty_cnt;
      end
   end

//blk
   always @(posedge clk) begin
      if (rst) begin
         blk_local_ring_empty_cnt <= 20'b0;
      end else begin
         if (blk_avail_id_rsp_vld && blk_avail_id_rsp_rdy && blk_avail_id_rsp_data.local_ring_empty) begin
            blk_local_ring_empty_cnt <= blk_local_ring_empty_cnt + 1'b1;
         end
      end
   end

   always @(posedge clk) begin
      if (rst) begin
         blk_avail_ring_empty_cnt <= 20'b0;
      end else begin
         if (blk_avail_id_rsp_vld && blk_avail_id_rsp_rdy && blk_avail_id_rsp_data.avail_ring_empty) begin
            blk_avail_ring_empty_cnt <= blk_avail_ring_empty_cnt + 1'b1;
         end
      end
   end

   always @(posedge clk) begin
      if (rst) begin
         blk_ring_empty_diff_cnt <= 20'b0;
      end else begin
         blk_ring_empty_diff_cnt <= blk_local_ring_empty_cnt - blk_avail_ring_empty_cnt;
      end
   end

   assign dfx_ring_empty_cnt0 = {4'd0, netrx_ring_empty_diff_cnt, netrx_local_ring_empty_cnt, netrx_avail_ring_empty_cnt};
   assign dfx_ring_empty_cnt1 = {4'd0, nettx_ring_empty_diff_cnt, nettx_local_ring_empty_cnt, nettx_avail_ring_empty_cnt};
   assign dfx_ring_empty_cnt2 = {4'd0, blk_ring_empty_diff_cnt, blk_local_ring_empty_cnt, blk_avail_ring_empty_cnt};

virtio_ring_id_engine #(
    .DATA_WIDTH (DATA_WIDTH),
    .DATA_EMPTY ($clog2(DATA_WIDTH/8)),
    .VIRTIO_Q_NUM (VIRTIO_Q_NUM),
    .VIRTIO_Q_WIDTH ($clog2(VIRTIO_Q_NUM)),
    .NETTX_PERQ_RING_ID_NUM ( NETTX_PERQ_RING_ID_NUM ),
    .NETRX_PERQ_RING_ID_NUM ( NETRX_PERQ_RING_ID_NUM ),
    .BLK_PERQ_RING_ID_NUM ( BLK_PERQ_RING_ID_NUM )

 )u_virtio_ring_id_engine
 (  
    .clk                                 ( clk ),
    .rst                                 ( rst ),

    .notify_req_vld                      ( notify_req_vld ),
    .notify_req_qid                      ( notify_req_qid ),
    .notify_req_rdy                      ( notify_req_rdy ),

    .notify_rsp_vld                      ( notify_rsp_vld ),
    .notify_rsp_qid                      ( notify_rsp_qid ),
    .notify_rsp_cold                     ( notify_rsp_cold ),
    .notify_rsp_done                     ( notify_rsp_done ),
    .notify_rsp_rdy                      ( notify_rsp_rdy ),

    .dma_ring_id_rd_req                  ( dma_ring_id_rd_req ),
    .dma_ring_id_rd_rsp                  ( dma_ring_id_rd_rsp ),

    .avail_addr_rd_req_vld               ( avail_addr_rd_req_vld ),
    .avail_addr_rd_req_qid               ( avail_addr_rd_req_qid ),
    .avail_addr_rd_req_rdy               ( avail_addr_rd_req_rdy ),
 
    .avail_addr_rd_rsp_vld               ( avail_addr_rd_rsp_vld ),
    .avail_addr_rd_rsp_data              ( avail_addr_rd_rsp_data ),

    .avail_ui_wr_req_vld                 ( avail_ui_wr_req_vld ),
    .avail_ui_wr_req_data                ( avail_ui_wr_req_data ),
    .avail_ui_wr_req_qid                 ( avail_ui_wr_req_qid ),

    .avail_pi_wr_req_vld                 ( avail_pi_wr_req_vld ),
    .avail_pi_wr_req_data                ( avail_pi_wr_req_data ),
    .avail_pi_wr_req_qid                 ( avail_pi_wr_req_qid ),
 
    .nettx_notify_req_vld                ( nettx_notify_req_vld ),
    .nettx_notify_req_qid                ( nettx_notify_req_qid ),
    .nettx_notify_req_rdy                ( nettx_notify_req_rdy ),

    .blk_notify_req_vld                  ( blk_notify_req_vld ),
    .blk_notify_req_qid                  ( blk_notify_req_qid ),
    .blk_notify_req_rdy                  ( blk_notify_req_rdy ),

    .dma_ctx_info_rd_req_vld             ( dma_ctx_info_rd_req_vld ),
    .dma_ctx_info_rd_req_qid             ( dma_ctx_info_rd_req_qid ),

    .dma_ctx_info_rd_rsp_vld             ( dma_ctx_info_rd_rsp_vld ), 
    .dma_ctx_info_rd_rsp_force_shutdown  ( dma_ctx_info_rd_rsp_force_shutdown ),
    .dma_ctx_info_rd_rsp_ctrl            ( dma_ctx_info_rd_rsp_ctrl ),
    .dma_ctx_info_rd_rsp_bdf             ( dma_ctx_info_rd_rsp_bdf ),
    .dma_ctx_info_rd_rsp_qdepth          ( dma_ctx_info_rd_rsp_qdepth ),
    .dma_ctx_info_rd_rsp_avail_idx       ( dma_ctx_info_rd_rsp_avail_idx ),
    .dma_ctx_info_rd_rsp_avail_ui        ( dma_ctx_info_rd_rsp_avail_ui ),
    .dma_ctx_info_rd_rsp_avail_ci        ( dma_ctx_info_rd_rsp_avail_ci ),

    .rd_ring_id_nettx_req_vld            ( rd_ring_id_nettx_req_vld ),
    .rd_ring_id_nettx_req_addr           ( rd_ring_id_nettx_req_addr ),
    .rd_ring_id_nettx_rsp_vld            ( rd_ring_id_nettx_rsp_vld ),
    .rd_ring_id_nettx_rsp_data           ( rd_ring_id_nettx_rsp_data ),

    .rd_ring_id_netrx_req_vld            ( rd_ring_id_netrx_req_vld ),
    .rd_ring_id_netrx_req_addr           ( rd_ring_id_netrx_req_addr ),
    .rd_ring_id_netrx_rsp_vld            ( rd_ring_id_netrx_rsp_vld ),
    .rd_ring_id_netrx_rsp_data           ( rd_ring_id_netrx_rsp_data ),

    .rd_ring_id_blk_req_vld              ( rd_ring_id_blk_req_vld ),
    .rd_ring_id_blk_req_addr             ( rd_ring_id_blk_req_addr ),
    .rd_ring_id_blk_rsp_vld              ( rd_ring_id_blk_rsp_vld ),
    .rd_ring_id_blk_rsp_data             ( rd_ring_id_blk_rsp_data ),

    .rd_issued_cnt                       ( rd_issued_cnt ),
    .rd_rsp_cnt                          ( rd_rsp_cnt ),

    .dfx_status                          ( dfx_status[0] ),
    .dfx_err                             ( dfx_err[0] )

 );


 virtio_desc_req_ctrl #(
    .DATA_WIDTH (DATA_WIDTH),
    .DATA_EMPTY ($clog2(DATA_WIDTH/8)),
    .VIRTIO_Q_NUM (VIRTIO_Q_NUM),
    .VIRTIO_Q_WIDTH ($clog2(VIRTIO_Q_NUM)),
    .NETTX_PERQ_RING_ID_NUM ( NETTX_PERQ_RING_ID_NUM ),
    .NETRX_PERQ_RING_ID_NUM ( NETRX_PERQ_RING_ID_NUM ),
    .BLK_PERQ_RING_ID_NUM ( BLK_PERQ_RING_ID_NUM )
 )u_virtio_desc_req_ctrl
 (

    .clk                                        ( clk ),
    .rst                                        ( rst ),

    .netrx_avail_id_req_vld                     ( netrx_avail_id_req_vld ),
    .netrx_avail_id_req_data                    ( netrx_avail_id_req_data ),
    .netrx_avail_id_req_nid                     ( netrx_avail_id_req_nid ),
    .netrx_avail_id_req_rdy                     ( netrx_avail_id_req_rdy ),

    .netrx_avail_id_rsp_vld                     ( netrx_avail_id_rsp_vld ),
    .netrx_avail_id_rsp_data                    ( netrx_avail_id_rsp_data ),
    .netrx_avail_id_rsp_eop                     ( netrx_avail_id_rsp_eop ),
    .netrx_avail_id_rsp_rdy                     ( netrx_avail_id_rsp_rdy ),

    .rd_ring_id_netrx_req_vld                   ( rd_ring_id_netrx_req_vld ),
    .rd_ring_id_netrx_req_addr                  ( rd_ring_id_netrx_req_addr ),
    .rd_ring_id_netrx_rsp_vld                   ( rd_ring_id_netrx_rsp_vld ),
    .rd_ring_id_netrx_rsp_data                  ( rd_ring_id_netrx_rsp_data ),

    .nettx_avail_id_req_vld                     ( nettx_avail_id_req_vld ),
    .nettx_avail_id_req_data                    ( nettx_avail_id_req_data ),
    .nettx_avail_id_req_nid                     ( nettx_avail_id_req_nid ),
    .nettx_avail_id_req_rdy                     ( nettx_avail_id_req_rdy ),

    .nettx_avail_id_rsp_vld                     ( nettx_avail_id_rsp_vld ),
    .nettx_avail_id_rsp_eop                     ( nettx_avail_id_rsp_eop ),
    .nettx_avail_id_rsp_data                    ( nettx_avail_id_rsp_data ),
    .nettx_avail_id_rsp_rdy                     ( nettx_avail_id_rsp_rdy ),

    .rd_ring_id_nettx_req_vld                   ( rd_ring_id_nettx_req_vld ),
    .rd_ring_id_nettx_req_addr                  ( rd_ring_id_nettx_req_addr ), 
    .rd_ring_id_nettx_rsp_vld                   ( rd_ring_id_nettx_rsp_vld ),
    .rd_ring_id_nettx_rsp_data                  ( rd_ring_id_nettx_rsp_data ),

    .blk_avail_id_req_vld                       ( blk_avail_id_req_vld ),
    .blk_avail_id_req_data                      ( blk_avail_id_req_data ),
    .blk_avail_id_req_nid                       ( blk_avail_id_req_nid ),
    .blk_avail_id_req_rdy                       ( blk_avail_id_req_rdy ),

    .blk_avail_id_rsp_vld                       ( blk_avail_id_rsp_vld ),
    .blk_avail_id_rsp_data                      ( blk_avail_id_rsp_data ),
    .blk_avail_id_rsp_eop                       ( blk_avail_id_rsp_eop ),
    .blk_avail_id_rsp_rdy                       ( blk_avail_id_rsp_rdy ),

    .rd_ring_id_blk_req_vld                     ( rd_ring_id_blk_req_vld ),
    .rd_ring_id_blk_req_addr                    ( rd_ring_id_blk_req_addr ),
    .rd_ring_id_blk_rsp_vld                     ( rd_ring_id_blk_rsp_vld ),
    .rd_ring_id_blk_rsp_data                    ( rd_ring_id_blk_rsp_data ),

    .avail_ci_wr_req_vld                        ( avail_ci_wr_req_vld ),
    .avail_ci_wr_req_data                       ( avail_ci_wr_req_data ),
    .avail_ci_wr_req_qid                        ( avail_ci_wr_req_qid ),

    .desc_engine_ctx_info_rd_req_vld            ( desc_engine_ctx_info_rd_req_vld ),
    .desc_engine_ctx_info_rd_req_qid            ( desc_engine_ctx_info_rd_req_qid ),

    .desc_engine_ctx_info_rd_rsp_vld            ( desc_engine_ctx_info_rd_rsp_vld ),
    .desc_engine_ctx_info_rd_rsp_force_shutdown ( desc_engine_ctx_info_rd_rsp_force_shutdown ),
    .desc_engine_ctx_info_rd_rsp_ctrl           ( desc_engine_ctx_info_rd_rsp_ctrl ),
    .desc_engine_ctx_info_rd_rsp_avail_pi       ( desc_engine_ctx_info_rd_rsp_avail_pi ),
    .desc_engine_ctx_info_rd_rsp_avail_idx      ( desc_engine_ctx_info_rd_rsp_avail_idx ),
    .desc_engine_ctx_info_rd_rsp_avail_ui       ( desc_engine_ctx_info_rd_rsp_avail_ui ),
    .desc_engine_ctx_info_rd_rsp_avail_ci       ( desc_engine_ctx_info_rd_rsp_avail_ci ),

    .vq_pending_chk_req_vld                     (vq_pending_chk_req_vld ),
    .vq_pending_chk_req_vq                      (vq_pending_chk_req_vq ),
    .vq_pending_chk_rsp_vld                     (vq_pending_chk_rsp_vld ),
    .vq_pending_chk_rsp_busy                    (vq_pending_chk_rsp_busy ),

    .dfx_err                                    ( dfx_err[1] ),
    .dfx_status                                 ( dfx_status[1])

 );
 

  logic [63:0]dfx_err0_dfx_err_q,dfx_err1_dfx_err_q;
    virtio_avail_ring_reg_dfx #(
        .ADDR_OFFSET (0),  //! Module's offset in the main address map
        .ADDR_WIDTH (16),   //! Width of SW address bus
        .DATA_WIDTH (64)    //! Width of SW data bus
    )u_virtio_avail_ring_reg_dfx
    (
        .clk                                    ( clk ),     //! Default clock
        .rst                                    ( rst ),  //! Default reset
    
        .dfx_err0_dfx_err_we                    ( | dfx_err[0] ),             //! Control HW write (active high)     offset_addr= 0x00
        .dfx_err0_dfx_err_wdata                 ( dfx_err[0] | dfx_err0_dfx_err_q),          //! HW write data
        .dfx_err0_dfx_err_q                     ( dfx_err0_dfx_err_q ) ,
    
        .dfx_err1_dfx_err_we                    ( | dfx_err[1] ),             //! Control HW write (active high)
        .dfx_err1_dfx_err_wdata                 ( dfx_err[1] | dfx_err1_dfx_err_q),          //! HW write data
        .dfx_err1_dfx_err_q                     ( dfx_err1_dfx_err_q),
    
    
        .dfx_status0_dfx_status_wdata           ( dfx_status[0] ),          //! HW write data  offset_addr= 0x100
        .dfx_status1_dfx_status_wdata           ( dfx_status[1]),           //! HW write data

        .rd_issued_cnt_dfx_cnt_wdata            ( rd_issued_cnt ),
        .rd_rsp_cnt_dfx_cnt_wdata               ( rd_rsp_cnt ),
        
        .dfx_ring_empty_cnt0_dfx_ring_empty_cnt0_wdata(dfx_ring_empty_cnt0),
        .dfx_ring_empty_cnt1_dfx_ring_empty_cnt1_wdata(dfx_ring_empty_cnt1),
        .dfx_ring_empty_cnt2_dfx_ring_empty_cnt2_wdata(dfx_ring_empty_cnt2),
        .dfx_threshold0_dfx_threshold_swmod      ( ),          //! Indicates SW has modified this field  offset_addr = 0x400
        .dfx_threshold0_dfx_threshold_q          ( ),              //! Current field value        
    
    
    
        .csr_if                                 ( dfx_slave )
    
    );



endmodule


