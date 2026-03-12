/******************************************************************************
 * 文件名称 : virtio_blk_desc_engine_tb.sv
 * 作者名称 : LCH
 * 创建日期 : 2024/12/28
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  12/28       LCH          初始化版本
 ******************************************************************************/
`timescale 1ns / 1ns
`include "../virtio_define.svh"
`include "virtio_blk_desc_engine_define.svh"
`include "tlp_adap_dma_if.svh"
module virtio_blk_desc_engine_tb
    import alt_tlp_adaptor_pkg::*;
#(
    parameter DATA_WIDTH = 256,
    parameter EMPTH_WIDTH = $clog2(DATA_WIDTH / 8),
    parameter QID_NUM = 256,
    parameter QID_WIDTH = $clog2(QID_NUM),
    parameter SLOT_NUM = 4
) (
    input  logic                                             clk,
    input  logic                                             rst,
    //
    input  logic                                             sch_req_vld,
    output logic                                             sch_req_sav,
    input  logic [                   $bits(virtio_vq_t)-1:0] sch_req_vq,
    // alloc_slot_req
    input  logic                                             notify_rsp_vld,
    output logic                                             notify_rsp_rdy,
    input  logic [                   $bits(virtio_vq_t)-1:0] notify_rsp_vq,
    input  logic                                             notify_rsp_done,
    input  logic                                             notify_rsp_cold,
    // alloc_slot_rsp
    output logic                                             alloc_slot_rsp_vld,
    input  logic                                             alloc_slot_rsp_rdy,
    output logic [                   $bits(virtio_vq_t)-1:0] alloc_slot_rsp_dat_vq,
    output logic [                                      9:0] alloc_slot_rsp_dat_pkt_id,
    output logic                                             alloc_slot_rsp_dat_ok,
    output logic                                             alloc_slot_rsp_dat_local_ring_empty,
    output logic                                             alloc_slot_rsp_dat_avail_ring_empty,
    output logic                                             alloc_slot_rsp_dat_q_stat_doing,
    output logic                                             alloc_slot_rsp_dat_q_stat_stopping,
    output logic                                             alloc_slot_rsp_dat_desc_engine_limit,
    output logic [                                      7:0] alloc_slot_rsp_dat_err_info,
    // avail_id_req
    output logic                                             avail_id_req_vld,
    input  logic                                             avail_id_req_rdy,
    output logic [                   $bits(virtio_vq_t)-1:0] avail_id_req_vq,
    // avail_id_rsp
    input  logic                                             avail_id_rsp_vld,
    output logic                                             avail_id_rsp_rdy,
    input  logic [                                   16-1:0] avail_id_rsp_dat_id,
    input  logic [                                   16-1:0] avail_id_rsp_dat_idx,
    input  logic [                   $bits(virtio_vq_t)-1:0] avail_id_rsp_dat_vq,
    input  logic                                             avail_id_rsp_dat_local_ring_empty,
    input  logic                                             avail_id_rsp_dat_avail_ring_empty,
    input  logic                                             avail_id_rsp_dat_q_stat_doing,
    input  logic                                             avail_id_rsp_dat_q_stat_stopping,
    input  logic [                                      7:0] avail_id_rsp_dat_err_info,
    // desc_dma_rd_req
    output logic                                             desc_dma_rd_req_val,
    input  logic                                             desc_dma_rd_req_sav,
    output logic [                          EMPTH_WIDTH-1:0] desc_dma_rd_req_sty,
    output logic [                        $bits(desc_t)-1:0] desc_dma_rd_req_desc,
    // desc_dma_rd_req
    input  logic                                             desc_dma_rd_rsp_val,
    input  logic                                             desc_dma_rd_rsp_sop,
    input  logic                                             desc_dma_rd_rsp_eop,
    input  logic                                             desc_dma_rd_rsp_err,
    input  logic [                           DATA_WIDTH-1:0] desc_dma_rd_rsp_data,
    input  logic [                          EMPTH_WIDTH-1:0] desc_dma_rd_rsp_sty,
    input  logic [                          EMPTH_WIDTH-1:0] desc_dma_rd_rsp_mty,
    input  logic [                        $bits(desc_t)-1:0] desc_dma_rd_rsp_desc,
    //
    output logic                                             blk_desc_vld,
    input  logic                                             blk_desc_rdy,
    output logic                                             blk_desc_sop,
    output logic                                             blk_desc_eop,
    output logic [$bits(virtio_desc_eng_desc_rsp_sbd_t)-1:0] blk_desc_sbd,
    output logic [                  $bits(virtq_desc_t)-1:0] blk_desc_dat,
    // blk_desc_resummer_rd_req
    output logic                                             blk_desc_resummer_rd_req_vld,
    output logic [                            QID_WIDTH-1:0] blk_desc_resummer_rd_req_qid,
    // blk_desc_resummer_rd_rsp
    input  logic                                             blk_desc_resummer_rd_rsp_vld,
    input  logic                                             blk_desc_resummer_rd_rsp_dat,
    // blk_desc_resumer_wr
    output logic                                             blk_desc_resumer_wr_vld,
    output logic [                            QID_WIDTH-1:0] blk_desc_resumer_wr_qid,
    output logic                                             blk_desc_resumer_wr_dat,
    // blk_desc_global_info_rd_req
    output logic                                             blk_desc_global_info_rd_req_vld,
    output logic [                            QID_WIDTH-1:0] blk_desc_global_info_rd_req_qid,
    // blk_desc_global_info_rd_rsp
    input  logic                                             blk_desc_global_info_rd_rsp_vld,
    input  logic [                                     15:0] blk_desc_global_info_rd_rsp_bdf,
    input  logic                                             blk_desc_global_info_rd_rsp_forced_shutdown,
    input  logic [                                     63:0] blk_desc_global_info_rd_rsp_desc_tbl_addr,
    input  logic [                                      3:0] blk_desc_global_info_rd_rsp_qdepth,
    input  logic                                             blk_desc_global_info_rd_rsp_indirct_support,
    input  logic [                                     19:0] blk_desc_global_info_rd_rsp_segment_size_blk,
    // blk_desc_local_info_rd_req
    output logic                                             blk_desc_local_info_rd_req_vld,
    output logic [                            QID_WIDTH-1:0] blk_desc_local_info_rd_req_qid,
    // blk_desc_local_info_rd_rsp
    input  logic                                             blk_desc_local_info_rd_rsp_vld,
    input  logic [                                     63:0] blk_desc_local_info_rd_rsp_desc_tbl_addr_blk,
    input  logic [                                     31:0] blk_desc_local_info_rd_rsp_desc_tbl_size_blk,
    input  logic [                                     15:0] blk_desc_local_info_rd_rsp_desc_tbl_next_blk,
    input  logic [                                     15:0] blk_desc_local_info_rd_rsp_desc_tbl_id_blk,
    input  logic [                                     19:0] blk_desc_local_info_rd_rsp_desc_cnt,
    input  logic [                                     20:0] blk_desc_local_info_rd_rsp_data_len,
    input  logic                                             blk_desc_local_info_rd_rsp_is_indirct,
    // blk_desc_local_info_wr
    output logic                                             blk_desc_local_info_wr_vld,
    output logic [                            QID_WIDTH-1:0] blk_desc_local_info_wr_qid,
    output logic [                                     63:0] blk_desc_local_info_wr_desc_tbl_addr_blk,
    output logic [                                     31:0] blk_desc_local_info_wr_desc_tbl_size_blk,
    output logic [                                     15:0] blk_desc_local_info_wr_desc_tbl_next_blk,
    output logic [                                     15:0] blk_desc_local_info_wr_desc_tbl_id_blk,
    output logic [                                     19:0] blk_desc_local_info_wr_desc_cnt,
    output logic [                                     20:0] blk_desc_local_info_wr_data_len,
    output logic                                             blk_desc_local_info_wr_is_indirct,
    input                                                    dfx_if_valid,
    input                                                    dfx_if_read,
    input        [                                   32-1:0] dfx_if_addr,
    input        [                                   64-1:0] dfx_if_wdata,
    input        [                                 64/8-1:0] dfx_if_wmask,
    input                                                    dfx_if_rready,
    output                                                   dfx_if_ready,
    output                                                   dfx_if_rvalid,
    output       [                                   64-1:0] dfx_if_rdata
);

    logic                      alloc_slot_req_vld;
    logic                      alloc_slot_req_rdy;
    virtio_vq_t                alloc_slot_req_vq;

    virtio_desc_eng_slot_rsp_t alloc_slot_rsp_dat;
    assign alloc_slot_rsp_dat_vq                = alloc_slot_rsp_dat.vq;
    assign alloc_slot_rsp_dat_pkt_id            = alloc_slot_rsp_dat.pkt_id;
    assign alloc_slot_rsp_dat_ok                = alloc_slot_rsp_dat.ok;
    assign alloc_slot_rsp_dat_local_ring_empty  = alloc_slot_rsp_dat.local_ring_empty;
    assign alloc_slot_rsp_dat_avail_ring_empty  = alloc_slot_rsp_dat.avail_ring_empty;
    assign alloc_slot_rsp_dat_q_stat_doing      = alloc_slot_rsp_dat.q_stat_doing;
    assign alloc_slot_rsp_dat_q_stat_stopping   = alloc_slot_rsp_dat.q_stat_stopping;
    assign alloc_slot_rsp_dat_desc_engine_limit = alloc_slot_rsp_dat.desc_engine_limit;
    assign alloc_slot_rsp_dat_err_info          = alloc_slot_rsp_dat.err_info;
    virtio_avail_id_rsp_dat_t avail_id_rsp_dat;
    assign avail_id_rsp_dat.vq               = avail_id_rsp_dat_vq;
    assign avail_id_rsp_dat.id               = avail_id_rsp_dat_id;
    assign avail_id_rsp_dat.local_ring_empty = avail_id_rsp_dat_local_ring_empty;
    assign avail_id_rsp_dat.avail_ring_empty = avail_id_rsp_dat_avail_ring_empty;
    assign avail_id_rsp_dat.q_stat_doing     = avail_id_rsp_dat_q_stat_doing;
    assign avail_id_rsp_dat.q_stat_stopping  = avail_id_rsp_dat_q_stat_stopping;
    assign avail_id_rsp_dat.avail_idx        = avail_id_rsp_dat_idx;
    assign avail_id_rsp_dat.err_info         = avail_id_rsp_dat_err_info;
    tlp_adap_dma_rd_req_if #(.DATA_WIDTH(DATA_WIDTH)) desc_dma_rd_req ();
    assign desc_dma_rd_req_val  = desc_dma_rd_req.vld;
    assign desc_dma_rd_req.sav  = desc_dma_rd_req_sav;
    assign desc_dma_rd_req_sty  = desc_dma_rd_req.sty;
    assign desc_dma_rd_req_desc = desc_dma_rd_req.desc;
    tlp_adap_dma_rd_rsp_if #(.DATA_WIDTH(DATA_WIDTH)) desc_dma_rd_rsp ();
    assign desc_dma_rd_rsp.vld  = desc_dma_rd_rsp_val;
    assign desc_dma_rd_rsp.sop  = desc_dma_rd_rsp_sop;
    assign desc_dma_rd_rsp.eop  = desc_dma_rd_rsp_eop;
    assign desc_dma_rd_rsp.err  = desc_dma_rd_rsp_err;
    assign desc_dma_rd_rsp.data = desc_dma_rd_rsp_data;
    assign desc_dma_rd_rsp.sty  = desc_dma_rd_rsp_sty;
    assign desc_dma_rd_rsp.mty  = desc_dma_rd_rsp_mty;
    assign desc_dma_rd_rsp.desc = desc_dma_rd_rsp_desc;
    mlite_if #(.DATA_WIDTH(64)) dfx_if ();
    assign dfx_if.valid  = dfx_if_valid;
    assign dfx_if.read   = dfx_if_read;
    assign dfx_if.addr   = dfx_if_addr;
    assign dfx_if.wdata  = dfx_if_wdata;
    assign dfx_if.wmask  = dfx_if_wmask;
    assign dfx_if.rready = dfx_if_rready;

    assign dfx_if_ready  = dfx_if.ready;
    assign dfx_if_rvalid = dfx_if.rvalid;
    assign dfx_if_rdata  = dfx_if.rdata;
    virtio_blk_desc_engine_top #(
        .QID_NUM (QID_NUM),
        .SLOT_NUM(SLOT_NUM)
    ) u_virtio_blk_desc_engine_top (
        .clk                                         (clk),
        .rst                                         (rst),
        // alloc_slot_req
        .alloc_slot_req_vld                          (alloc_slot_req_vld),
        .alloc_slot_req_rdy                          (alloc_slot_req_rdy),
        .alloc_slot_req_vq                           (alloc_slot_req_vq),
        // alloc_slot_rsp
        .alloc_slot_rsp_vld                          (alloc_slot_rsp_vld),
        .alloc_slot_rsp_rdy                          (alloc_slot_rsp_rdy),
        .alloc_slot_rsp_dat                          (alloc_slot_rsp_dat),
        // avail_id_req
        .avail_id_req_vld                            (avail_id_req_vld),
        .avail_id_req_rdy                            (avail_id_req_rdy),
        .avail_id_req_vq                             (avail_id_req_vq),
        // avail_id_rsp
        .avail_id_rsp_vld                            (avail_id_rsp_vld),
        .avail_id_rsp_rdy                            (avail_id_rsp_rdy),
        .avail_id_rsp_dat                            (avail_id_rsp_dat),
        // desc_dma_rd_req
        .desc_dma_rd_req                             (desc_dma_rd_req),
        // desc_dma_rd_rsp
        .desc_dma_rd_rsp                             (desc_dma_rd_rsp),
        //blk_desc
        .blk_desc_vld                                (blk_desc_vld),
        .blk_desc_rdy                                (blk_desc_rdy),
        .blk_desc_sop                                (blk_desc_sop),
        .blk_desc_eop                                (blk_desc_eop),
        .blk_desc_sbd                                (blk_desc_sbd),
        .blk_desc_dat                                (blk_desc_dat),
        // blk_desc_resummer_rd_req
        .blk_desc_resummer_rd_req_vld                (blk_desc_resummer_rd_req_vld),
        .blk_desc_resummer_rd_req_qid                (blk_desc_resummer_rd_req_qid),
        // blk_desc_resummer_rd_rsp
        .blk_desc_resummer_rd_rsp_vld                (blk_desc_resummer_rd_rsp_vld),
        .blk_desc_resummer_rd_rsp_dat                (blk_desc_resummer_rd_rsp_dat),
        // blk_desc_resumer_wr
        .blk_desc_resumer_wr_vld                     (blk_desc_resumer_wr_vld),
        .blk_desc_resumer_wr_qid                     (blk_desc_resumer_wr_qid),
        .blk_desc_resumer_wr_dat                     (blk_desc_resumer_wr_dat),
        // blk_desc_global_info_rd_req
        .blk_desc_global_info_rd_req_vld             (blk_desc_global_info_rd_req_vld),
        .blk_desc_global_info_rd_req_qid             (blk_desc_global_info_rd_req_qid),
        // blk_desc_global_info_rd_rsp
        .blk_desc_global_info_rd_rsp_vld             (blk_desc_global_info_rd_rsp_vld),
        .blk_desc_global_info_rd_rsp_bdf             (blk_desc_global_info_rd_rsp_bdf),
        .blk_desc_global_info_rd_rsp_forced_shutdown (blk_desc_global_info_rd_rsp_forced_shutdown),
        .blk_desc_global_info_rd_rsp_desc_tbl_addr   (blk_desc_global_info_rd_rsp_desc_tbl_addr),
        .blk_desc_global_info_rd_rsp_qdepth          (blk_desc_global_info_rd_rsp_qdepth),
        .blk_desc_global_info_rd_rsp_indirct_support (blk_desc_global_info_rd_rsp_indirct_support),
        .blk_desc_global_info_rd_rsp_segment_size_blk(blk_desc_global_info_rd_rsp_segment_size_blk),
        // blk_desc_local_info_rd_req
        .blk_desc_local_info_rd_req_vld              (blk_desc_local_info_rd_req_vld),
        .blk_desc_local_info_rd_req_qid              (blk_desc_local_info_rd_req_qid),
        // blk_desc_local_info_rd_rsp
        .blk_desc_local_info_rd_rsp_vld              (blk_desc_local_info_rd_rsp_vld),
        .blk_desc_local_info_rd_rsp_desc_tbl_addr_blk(blk_desc_local_info_rd_rsp_desc_tbl_addr_blk),
        .blk_desc_local_info_rd_rsp_desc_tbl_size_blk(blk_desc_local_info_rd_rsp_desc_tbl_size_blk),
        .blk_desc_local_info_rd_rsp_desc_tbl_next_blk(blk_desc_local_info_rd_rsp_desc_tbl_next_blk),
        .blk_desc_local_info_rd_rsp_desc_tbl_id_blk  (blk_desc_local_info_rd_rsp_desc_tbl_id_blk),
        .blk_desc_local_info_rd_rsp_desc_cnt         (blk_desc_local_info_rd_rsp_desc_cnt),
        .blk_desc_local_info_rd_rsp_data_len         (blk_desc_local_info_rd_rsp_data_len),
        .blk_desc_local_info_rd_rsp_is_indirct       (blk_desc_local_info_rd_rsp_is_indirct),
        // blk_desc_local_info_wr
        .blk_desc_local_info_wr_vld                  (blk_desc_local_info_wr_vld),
        .blk_desc_local_info_wr_qid                  (blk_desc_local_info_wr_qid),
        .blk_desc_local_info_wr_desc_tbl_addr_blk    (blk_desc_local_info_wr_desc_tbl_addr_blk),
        .blk_desc_local_info_wr_desc_tbl_size_blk    (blk_desc_local_info_wr_desc_tbl_size_blk),
        .blk_desc_local_info_wr_desc_tbl_next_blk    (blk_desc_local_info_wr_desc_tbl_next_blk),
        .blk_desc_local_info_wr_desc_tbl_id_blk      (blk_desc_local_info_wr_desc_tbl_id_blk),
        .blk_desc_local_info_wr_desc_cnt         (blk_desc_local_info_wr_desc_cnt),
        .blk_desc_local_info_wr_data_len         (blk_desc_local_info_wr_data_len),
        .blk_desc_local_info_wr_is_indirct       (blk_desc_local_info_wr_is_indirct),
        .dfx_if                                      (dfx_if)
    );

    virtio_sch #(
        .VQ_WIDTH($bits(virtio_vq_t))
    ) u_virtio_sch (
        .clk            (clk),
        .rst            (rst),
        .sch_req_vld    (sch_req_vld),
        .sch_req_rdy    (sch_req_rdy),
        .sch_req_qid    (sch_req_vq),
        .notify_req_vld (alloc_slot_req_vld),
        .notify_req_rdy (alloc_slot_req_rdy),
        .notify_req_qid (alloc_slot_req_vq),
        .notify_rsp_vld (notify_rsp_vld),
        .notify_rsp_rdy (notify_rsp_rdy),
        .notify_rsp_qid (notify_rsp_vq),
        .notify_rsp_done(notify_rsp_done),
        .notify_rsp_cold(notify_rsp_cold),
        .hot_weight     (4'd1),
        .cold_weight    (4'd1)
    );




    initial begin
        $fsdbAutoSwitchDumpfile(100, "top.fsdb", 200);
        $fsdbDumpvars(0, virtio_blk_desc_engine_tb, "+all");
        $fsdbDumpMDA();
    end

endmodule
