/******************************************************************************
 * 文件名称 : virtio_nettx_tb.sv
 * 作者名称 : Feilong Yun
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/23     Feilong Yun   初始化版本
******************************************************************************/
 `include "virtio_nettx_define.svh"
  `include "tlp_adap_dma_if.svh"
module virtio_nettx_tb 
    import alt_tlp_adaptor_pkg::*;
    #(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM)

 )(


    input                          clk,
    input                          rst,

    input                          sch_req_vld,
    input      [VIRTIO_Q_WIDTH-1:0]     sch_req_qid,
    output                         sch_req_rdy,

    output                         nettx_alloc_slot_req_vld,
    output     [$bits(virtio_vq_t)-1:0]    nettx_alloc_slot_req_data,
    output     [15:0]              nettx_alloc_slot_req_dev_id,
    input                          nettx_alloc_slot_req_rdy,

    input                          nettx_alloc_slot_rsp_vld,
    input    [$bits(virtio_desc_eng_slot_rsp_t)-1:0]   nettx_alloc_slot_rsp_data,
    output                         nettx_alloc_slot_rsp_rdy,

    output                         slot_ctrl_ctx_info_rd_req_vld,
    output    [$bits(virtio_vq_t)-1:0]      slot_ctrl_ctx_info_rd_req_qid,

    input                          slot_ctrl_ctx_info_rd_rsp_vld,
    input     [VIRTIO_Q_WIDTH+1:0]      slot_ctrl_ctx_info_rd_rsp_qos_unit,
    input                          slot_ctrl_ctx_info_rd_rsp_qos_enable,
    input     [15:0]               slot_ctrl_ctx_info_rd_rsp_dev_id,

    output                         qos_query_req_vld,
    output    [VIRTIO_Q_WIDTH+1:0]      qos_query_req_uid,
    input                          qos_query_req_rdy,

    input                          qos_query_rsp_vld,
    input                          qos_query_rsp_data,
    output                         qos_query_rsp_rdy,

    output                          nettx_desc_rsp_rdy,
    input                           nettx_desc_rsp_vld,
    input                           nettx_desc_rsp_sop,
    input                           nettx_desc_rsp_eop,
    input  [$bits(virtio_desc_eng_desc_rsp_sbd_t)-1:0]  nettx_desc_rsp_sbd,
    input  [$bits(virtq_desc_t)-1:0]nettx_desc_rsp_data,

    input                           qos_update_rdy,
    output                          qos_update_vld,
    output  [VIRTIO_Q_WIDTH+1:0]         qos_update_uid,
    output  [19:0]                  qos_update_len,
    output  [9:0]                   qos_update_pkt_num,

    output                          dma_rd_req_val,
    output  [$bits(desc_t)-1:0]     dma_rd_req_desc,
    output  [DATA_EMPTY-1:0]   dma_rd_req_sty,
    input                           dma_rd_req_sav,

    output                          rd_data_ctx_info_rd_req_vld,
    output  [$bits(virtio_vq_t)-1:0] rd_data_ctx_info_rd_req_qid,

    input                           rd_data_ctx_info_rd_rsp_vld,
    input   [15:0]                  rd_data_ctx_info_rd_rsp_bdf,
    input                           rd_data_ctx_info_rd_rsp_forced_shutdown,
    input                           rd_data_ctx_info_rd_rsp_qos_enable,
    input   [VIRTIO_Q_WIDTH+1:0]         rd_data_ctx_info_rd_rsp_qos_unit,
    input                           rd_data_ctx_info_rd_rsp_tso_en,
    input                           rd_data_ctx_info_rd_rsp_csum_en,
    input   [7:0]                   rd_data_ctx_info_rd_rsp_gen,

    input                           dma_rd_rsp_val,
    input                           dma_rd_rsp_sop,
    input                           dma_rd_rsp_eop,
    input                           dma_rd_rsp_err,
    input    [DATA_WIDTH-1:0]  dma_rd_rsp_data,
    input    [DATA_EMPTY-1:0]  dma_rd_rsp_sty,
    input    [DATA_EMPTY-1:0]  dma_rd_rsp_mty,
    input    [$bits(desc_t)-1:0]    dma_rd_rsp_desc,

    input                           net2tso_sav,
    output                          net2tso_vld,
    output   [DATA_EMPTY-1:0]  net2tso_sty,
    output   [DATA_EMPTY-1:0]  net2tso_mty,
    output   [DATA_EMPTY-1:0]  net2tso_sop,
    output   [DATA_EMPTY-1:0]  net2tso_eop,
    output                          net2tso_err,
    output   [DATA_WIDTH-1:0]  net2tso_data,
    output   [VIRTIO_Q_WIDTH-1:0]        net2tso_qid,
    output   [19:0]                 net2tso_len,
    output   [7:0]                  net2tso_gen,
    output                          net2tso_tso_en,
    output                          net2tso_csum_en,

    output                          used_info_vld,
    input                           used_info_rdy,
    output   [$bits(virtio_used_info_t)-1:0]     used_info_data


 );


   logic                        notify_req_vld;
   logic                        notify_req_rdy;
   logic [$bits(virtio_vq_t)-1:0] notify_req_qid;

   logic                        notify_rsp_vld;
   logic                        notify_rsp_rdy;
   logic                        notify_rsp_cold;
   logic                        notify_rsp_done;
   logic [$bits(virtio_vq_t)-1:0]notify_rsp_qid;

    mlite_if #(.ADDR_WIDTH (64), .DATA_WIDTH (64), .CHANNEL_NUM(1))   mlite_master();

    tlp_adap_dma_rd_req_if #(.DATA_WIDTH(DATA_WIDTH)) dma_rd_req ();
    assign dma_rd_req_val  = dma_rd_req.vld;
    assign dma_rd_req.sav  = dma_rd_req_sav;
    assign dma_rd_req_sty  = dma_rd_req.sty;
    assign dma_rd_req_desc = dma_rd_req.desc;
    tlp_adap_dma_rd_rsp_if #(.DATA_WIDTH(DATA_WIDTH)) dma_rd_rsp ();
    assign dma_rd_rsp.vld  = dma_rd_rsp_val;
    assign dma_rd_rsp.sop  = dma_rd_rsp_sop;
    assign dma_rd_rsp.eop  = dma_rd_rsp_eop;
    assign dma_rd_rsp.err  = dma_rd_rsp_err;
    assign dma_rd_rsp.data = dma_rd_rsp_data;
    assign dma_rd_rsp.sty  = dma_rd_rsp_sty;
    assign dma_rd_rsp.mty  = dma_rd_rsp_mty;
    assign dma_rd_rsp.desc = dma_rd_rsp_desc;


   virtio_sch #(
    .WEIGHT_WIDTH(4                     ),
    .VQ_WIDTH    ($bits(virtio_vq_t)    )
   ) u_virtio_nettx_sch (
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
    .hot_weight     ('h5),
    .cold_weight    ('h2),
    .dfx_err        (),
    .dfx_status     (),
    .notify_req_cnt (),
    .notify_rsp_cnt ()
);



virtio_nettx_top #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .DATA_EMPTY ( DATA_EMPTY ),
    .VIRTIO_Q_NUM ( VIRTIO_Q_NUM ),
    .VIRTIO_Q_WIDTH ( VIRTIO_Q_WIDTH)

)u_virtio_nettx_top(

   .clk   ( clk ),
   .rst   ( rst ),

   .notify_req_vld   ( notify_req_vld ),
   .notify_req_qid   ( notify_req_qid ),
   .notify_req_rdy   ( notify_req_rdy ),

   .notify_rsp_vld   ( notify_rsp_vld ),
   .notify_rsp_qid   ( notify_rsp_qid ),
   .notify_rsp_cold   ( notify_rsp_cold ),
   .notify_rsp_done   ( notify_rsp_done ),
   .notify_rsp_rdy   ( notify_rsp_rdy ),

   .nettx_alloc_slot_req_vld   ( nettx_alloc_slot_req_vld),
   .nettx_alloc_slot_req_data   ( nettx_alloc_slot_req_data ),
   .nettx_alloc_slot_req_dev_id   ( nettx_alloc_slot_req_dev_id ),
   .nettx_alloc_slot_req_rdy   ( nettx_alloc_slot_req_rdy ),

   .nettx_alloc_slot_rsp_vld   ( nettx_alloc_slot_rsp_vld ),
   .nettx_alloc_slot_rsp_data   ( nettx_alloc_slot_rsp_data ),
   .nettx_alloc_slot_rsp_rdy   ( nettx_alloc_slot_rsp_rdy ),

   .slot_ctrl_ctx_info_rd_req_vld   ( slot_ctrl_ctx_info_rd_req_vld ),
   .slot_ctrl_ctx_info_rd_req_qid   ( slot_ctrl_ctx_info_rd_req_qid ),

   .slot_ctrl_ctx_info_rd_rsp_vld   ( slot_ctrl_ctx_info_rd_rsp_vld ),
   .slot_ctrl_ctx_info_rd_rsp_qos_unit   ( slot_ctrl_ctx_info_rd_rsp_qos_unit ),
   .slot_ctrl_ctx_info_rd_rsp_qos_enable   ( slot_ctrl_ctx_info_rd_rsp_qos_enable ),
   .slot_ctrl_ctx_info_rd_rsp_dev_id   ( slot_ctrl_ctx_info_rd_rsp_dev_id ),

   .qos_query_req_vld   ( qos_query_req_vld ),
   .qos_query_req_uid   ( qos_query_req_uid ),
   .qos_query_req_rdy   ( qos_query_req_rdy ),

   .qos_query_rsp_vld   ( qos_query_rsp_vld ),
   .qos_query_rsp_data   ( qos_query_rsp_data ),
   .qos_query_rsp_rdy   ( qos_query_rsp_rdy ),

   .nettx_desc_rsp_rdy   ( nettx_desc_rsp_rdy ),
   .nettx_desc_rsp_vld   ( nettx_desc_rsp_vld ),
   .nettx_desc_rsp_sop   ( nettx_desc_rsp_sop ),
   .nettx_desc_rsp_eop   ( nettx_desc_rsp_eop ),
   .nettx_desc_rsp_sbd   ( nettx_desc_rsp_sbd ),
   .nettx_desc_rsp_data   ( nettx_desc_rsp_data ),

   .qos_update_rdy   ( qos_update_rdy ),
   .qos_update_vld   ( qos_update_vld),
   .qos_update_uid   ( qos_update_uid ),
   .qos_update_len   ( qos_update_len ),
   .qos_update_pkt_num   ( qos_update_pkt_num ),

    .dma_rd_req  ( dma_rd_req ),
    .dma_rd_rsp  ( dma_rd_rsp ),

   .rd_data_ctx_info_rd_req_vld   ( rd_data_ctx_info_rd_req_vld ),
   .rd_data_ctx_info_rd_req_qid   ( rd_data_ctx_info_rd_req_qid ),

   .rd_data_ctx_info_rd_rsp_vld   ( rd_data_ctx_info_rd_rsp_vld ),
   .rd_data_ctx_info_rd_rsp_bdf   ( rd_data_ctx_info_rd_rsp_bdf ),
   .rd_data_ctx_info_rd_rsp_forced_shutdown   ( rd_data_ctx_info_rd_rsp_forced_shutdown ),
   .rd_data_ctx_info_rd_rsp_qos_enable   ( rd_data_ctx_info_rd_rsp_qos_enable ),
   .rd_data_ctx_info_rd_rsp_qos_unit   ( rd_data_ctx_info_rd_rsp_qos_unit ),
    .rd_data_ctx_info_rd_rsp_tso_en ( rd_data_ctx_info_rd_rsp_tso_en ),
    .rd_data_ctx_info_rd_rsp_csum_en ( rd_data_ctx_info_rd_rsp_csum_en ),
    .rd_data_ctx_info_rd_rsp_gen ( rd_data_ctx_info_rd_rsp_gen ),

   .net2tso_sav   ( net2tso_sav ),
   .net2tso_vld   ( net2tso_vld ),
   .net2tso_sty   ( net2tso_sty ),
   .net2tso_sop   ( net2tso_sop ),
   .net2tso_eop   ( net2tso_eop ),
   .net2tso_mty   ( net2tso_mty ),
   .net2tso_err   ( net2tso_err ),
   .net2tso_data   ( net2tso_data ),
   .net2tso_qid   ( net2tso_qid ),
   .net2tso_len   ( net2tso_len ),
   .net2tso_gen   ( net2tso_gen ),   
   .net2tso_tso_en   ( net2tso_tso_en ),
   .net2tso_csum_en   ( net2tso_csum_en ),

   .used_info_vld   ( used_info_vld ),
   .used_info_rdy   ( used_info_rdy ),
   .used_info_data   ( used_info_data ),



   .dfx_slave   ( mlite_master )
        
   
 );


initial begin
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
    $fsdbDumpvars(0, virtio_nettx_tb, "+all");
    $fsdbDumpMDA();
end
endmodule
