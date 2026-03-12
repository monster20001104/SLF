/******************************************************************************
 * 文件名称 : virtio_blk_desc_engine_top.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/07/07
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   07/07      Liuch       初始化版本
 ******************************************************************************/
`include "../virtio_define.svh"
`include "virtio_blk_desc_engine_define.svh"
`include "virtio_desc_engine_define.svh"
module virtio_blk_desc_engine_top #(
    parameter DATA_WIDTH = 256,
    parameter QID_NUM    = 256,
    parameter QID_WIDTH  = $clog2(QID_NUM),
    parameter SLOT_NUM   = 4,
    parameter LINE_NUM   = 8,
    parameter BUCKET_NUM = 4
) (
    input  logic                                          clk,
    input  logic                                          rst,
    // alloc_slot_req
    input  logic                                          alloc_slot_req_vld,
    output logic                                          alloc_slot_req_rdy,
    input  virtio_vq_t                                    alloc_slot_req_vq,
    // alloc_slot_rsp
    output logic                                          alloc_slot_rsp_vld,
    input  logic                                          alloc_slot_rsp_rdy,
    output virtio_desc_eng_slot_rsp_t                     alloc_slot_rsp_dat,
    // avail_id_req
    output logic                                          avail_id_req_vld,
    input  logic                                          avail_id_req_rdy,
    output logic                          [QID_WIDTH-1:0] avail_id_req_vq,
    // avail_id_rsp
    input  logic                                          avail_id_rsp_vld,
    output logic                                          avail_id_rsp_rdy,
    input  virtio_avail_id_rsp_dat_t                      avail_id_rsp_dat,
    // desc_dma_rd_req
           tlp_adap_dma_rd_req_if.src                     desc_dma_rd_req,
    // desc_dma_rd_rsp
           tlp_adap_dma_rd_rsp_if.snk                     desc_dma_rd_rsp,
    // blk_desc
    output logic                                          blk_desc_vld,
    input  logic                                          blk_desc_rdy,
    output logic                                          blk_desc_sop,
    output logic                                          blk_desc_eop,
    output virtio_desc_eng_desc_rsp_sbd_t                 blk_desc_sbd,
    output virtq_desc_t                                   blk_desc_dat,
    // blk_desc_resummer_rd_req
    output logic                                          blk_desc_resummer_rd_req_vld,
    output logic                          [QID_WIDTH-1:0] blk_desc_resummer_rd_req_qid,
    // blk_desc_resummer_rd_rsp
    input  logic                                          blk_desc_resummer_rd_rsp_vld,
    input  logic                                          blk_desc_resummer_rd_rsp_dat,
    // blk_desc_resumer_wr
    output logic                                          blk_desc_resumer_wr_vld,
    output logic                          [QID_WIDTH-1:0] blk_desc_resumer_wr_qid,
    output logic                                          blk_desc_resumer_wr_dat,
    // blk_desc_global_info_rd_req
    output logic                                          blk_desc_global_info_rd_req_vld,
    output logic                          [QID_WIDTH-1:0] blk_desc_global_info_rd_req_qid,
    // blk_desc_global_info_rd_rsp
    input  logic                                          blk_desc_global_info_rd_rsp_vld,
    input  logic                          [15:0]          blk_desc_global_info_rd_rsp_bdf,
    input  logic                                          blk_desc_global_info_rd_rsp_forced_shutdown,
    input  logic                          [63:0]          blk_desc_global_info_rd_rsp_desc_tbl_addr,
    input  logic                          [3:0]           blk_desc_global_info_rd_rsp_qdepth,
    input  logic                                          blk_desc_global_info_rd_rsp_indirct_support,
    input  logic                          [19:0]          blk_desc_global_info_rd_rsp_segment_size_blk,
    // blk_desc_local_info_rd_req
    output logic                                          blk_desc_local_info_rd_req_vld,
    output logic                          [QID_WIDTH-1:0] blk_desc_local_info_rd_req_qid,
    // blk_desc_local_info_rd_rsp
    input  logic                                          blk_desc_local_info_rd_rsp_vld,
    input  logic                          [63:0]          blk_desc_local_info_rd_rsp_desc_tbl_addr_blk,
    input  logic                          [31:0]          blk_desc_local_info_rd_rsp_desc_tbl_size_blk,
    input  logic                          [15:0]          blk_desc_local_info_rd_rsp_desc_tbl_next_blk,
    input  logic                          [15:0]          blk_desc_local_info_rd_rsp_desc_tbl_id_blk,
    input  logic                          [19:0]          blk_desc_local_info_rd_rsp_desc_cnt,
    input  logic                          [20:0]          blk_desc_local_info_rd_rsp_data_len,
    input  logic                                          blk_desc_local_info_rd_rsp_is_indirct,
    // blk_desc_local_info_wr
    output logic                                          blk_desc_local_info_wr_vld,
    output logic                          [QID_WIDTH-1:0] blk_desc_local_info_wr_qid,
    output logic                          [63:0]          blk_desc_local_info_wr_desc_tbl_addr_blk,
    output logic                          [31:0]          blk_desc_local_info_wr_desc_tbl_size_blk,
    output logic                          [15:0]          blk_desc_local_info_wr_desc_tbl_next_blk,
    output logic                          [15:0]          blk_desc_local_info_wr_desc_tbl_id_blk,
    output logic                          [19:0]          blk_desc_local_info_wr_desc_cnt,
    output logic                          [20:0]          blk_desc_local_info_wr_data_len,
    output logic                                          blk_desc_local_info_wr_is_indirct,
           mlite_if.slave                                 dfx_if

);
    localparam SLOT_ID_WIDTH = $clog2(SLOT_NUM);
    localparam SLOT_ID_FF_DEPTH = SLOT_NUM << 1;
    localparam SLOT_ID_FF_WIDTH = SLOT_ID_WIDTH;
    localparam SLOT_CPL_FF_WIDTH = QID_WIDTH + SLOT_ID_WIDTH + 1 + 8 + 21 + 16 + 16;
    localparam SLOT_CPL_FF_DEPTH = 32;
    localparam SLOT_CPL_FF_USEDW = $clog2(SLOT_CPL_FF_DEPTH + 1);
    localparam LINE_WIDTH = $clog2(LINE_NUM);
    localparam BUCKET_WIDTH = $clog2(BUCKET_NUM);
    localparam DESC_BUF_DEPTH = (BUCKET_NUM * LINE_NUM);


    // slot_id_ff_rd
    logic                                                                                                     slot_id_ff_rden;
    logic                                 [SLOT_ID_FF_WIDTH-1:0]                                              slot_id_ff_dout;
    logic                                                                                                     slot_id_ff_empty;
    logic                                                                                                     slot_id_ff_cycle_flag;
    // slot_order_ff_rd
    logic                                                                                                     slot_order_ff_rden;
    logic                                 [SLOT_ID_FF_WIDTH-1:0]                                              slot_order_ff_dout;
    logic                                                                                                     slot_order_ff_empty;
    // slot_cpl_ff_rd
    // logic                                                                                                    slot_cpl_ff_rden;
    // logic                                [SLOT_CPL_FF_WIDTH-1:0]                                             slot_cpl_ff_dout;
    // logic                                                                                                    slot_cpl_ff_empty;
    logic                                 [SLOT_ID_WIDTH-1:0]                                                 slot_cpl_ram_raddr;
    logic                                 [SLOT_CPL_FF_WIDTH:0]                                               slot_cpl_ram_rdata;


    // desc_ram_rd
    logic                                 [$clog2(DESC_BUF_DEPTH)+$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:0] desc_buf_rd_req_addr;
    logic                                                                                                     desc_buf_rd_req_vld;
    virtq_desc_t                                                                                              desc_buf_rd_rsp_dat;
    logic                                                                                                     desc_buf_rd_rsp_vld;
    // first_submit
    logic                                                                                                     first_submit_vld;
    logic                                                                                                     first_submit_rdy;
    logic                                 [QID_WIDTH-1:0]                                                     first_submit_qid;
    logic                                 [15:0]                                                              first_submit_idx;
    logic                                 [15:0]                                                              first_submit_id;
    logic                                                                                                     first_submit_resummer;
    logic                                 [SLOT_ID_WIDTH-1:0]                                                 first_submit_slot_id;
    logic                                                                                                     first_submit_cycle_flag;
    // rsp_submit
    logic                                                                                                     info_rd_vld;
    virtio_desc_eng_core_info_ff_t                                                                            info_rd_dat;
    logic                                                                                                     info_rd_rdy;
    // order_wr
    logic                                                                                                     order_wr_vld;
    virtio_desc_eng_core_rd_desc_order_t                                                                      order_wr_dat;
    // logic                                 [20:0]                                                              state;
    // logic                                 [23:0]                                                              err;
    virtio_blk_desc_engine_alloc_status_t                                                                     alloc_state;
    virtio_blk_desc_engine_alloc_err_t                                                                        alloc_err;
    virtio_blk_desc_engine_free_status_t                                                                      free_state;
    virtio_blk_desc_engine_free_err_t                                                                         free_err;
    virtio_blk_desc_engine_core_status_t                                                                      core_state;
    virtio_blk_desc_engine_core_err_t                                                                         core_err;
    logic                                                                                                     flush_resummer;
    logic                                 [19:0]                                                              virtio_blk_desc_engine_max_chain_len;

    virtio_blk_desc_engine_alloc #(
        .QID_NUM (QID_NUM),
        .SLOT_NUM(SLOT_NUM)
    ) u_virtio_blk_desc_engine_alloc (
        .clk                         (clk),
        .rst                         (rst),
        // alloc_slot_req
        .alloc_slot_req_vld          (alloc_slot_req_vld),
        .alloc_slot_req_rdy          (alloc_slot_req_rdy),
        .alloc_slot_req_vq           (alloc_slot_req_vq),
        // alloc_slot_rsp
        .alloc_slot_rsp_vld          (alloc_slot_rsp_vld),
        .alloc_slot_rsp_rdy          (alloc_slot_rsp_rdy),
        .alloc_slot_rsp_dat          (alloc_slot_rsp_dat),
        // avail_id_req
        .avail_id_req_vld            (avail_id_req_vld),
        .avail_id_req_rdy            (avail_id_req_rdy),
        .avail_id_req_vq             (avail_id_req_vq),
        // avail_id_rsp
        .avail_id_rsp_vld            (avail_id_rsp_vld),
        .avail_id_rsp_rdy            (avail_id_rsp_rdy),
        .avail_id_rsp_dat            (avail_id_rsp_dat),
        // slot_id_ff_rd
        .slot_id_ff_rden             (slot_id_ff_rden),
        .slot_id_ff_dout             (slot_id_ff_dout),
        .slot_id_ff_cycle_flag       (slot_id_ff_cycle_flag),
        .slot_id_ff_empty            (slot_id_ff_empty),
        // first_submit
        .first_submit_vld            (first_submit_vld),
        .first_submit_rdy            (first_submit_rdy),
        .first_submit_qid            (first_submit_qid),
        .first_submit_idx            (first_submit_idx),
        .first_submit_id             (first_submit_id),
        .first_submit_resummer       (first_submit_resummer),
        .first_submit_slot_id        (first_submit_slot_id),
        .first_submit_cycle_flag     (first_submit_cycle_flag),
        // slot_order_ff_rd
        .slot_order_ff_rden          (slot_order_ff_rden),
        .slot_order_ff_dout          (slot_order_ff_dout),
        .slot_order_ff_empty         (slot_order_ff_empty),
        // blk_desc_resummer_rd_req
        .blk_desc_resummer_rd_req_vld(blk_desc_resummer_rd_req_vld),
        .blk_desc_resummer_rd_req_qid(blk_desc_resummer_rd_req_qid),
        // blk_desc_resummer_rd_rsp
        .blk_desc_resummer_rd_rsp_vld(blk_desc_resummer_rd_rsp_vld),
        .blk_desc_resummer_rd_rsp_dat(blk_desc_resummer_rd_rsp_dat),
        .state                       (alloc_state),
        .err                         (alloc_err),
        .flush_resummer              (flush_resummer)
    );


    virtio_blk_desc_engine_free #(
        .QID_NUM (QID_NUM),
        .SLOT_NUM(SLOT_NUM)
    ) u_virtio_blk_desc_engine_free (
        .clk                  (clk),
        .rst                  (rst),
        .slot_id_ff_rden      (slot_id_ff_rden),
        .slot_id_ff_dout      (slot_id_ff_dout),
        .slot_id_ff_empty     (slot_id_ff_empty),
        .slot_id_ff_cycle_flag(slot_id_ff_cycle_flag),
        // slot_order_ff_rd
        .slot_order_ff_rden   (slot_order_ff_rden),
        .slot_order_ff_dout   (slot_order_ff_dout),
        .slot_order_ff_empty  (slot_order_ff_empty),
        // slot_cpl_ff_rd
        // .slot_cpl_ff_rden     (slot_cpl_ff_rden),
        // .slot_cpl_ff_dout     (slot_cpl_ff_dout),
        // .slot_cpl_ff_empty    (slot_cpl_ff_empty),
        .slot_cpl_ram_raddr   (slot_cpl_ram_raddr),
        .slot_cpl_ram_rdata   (slot_cpl_ram_rdata),
        // desc_buf_rd
        .desc_buf_rd_req_addr (desc_buf_rd_req_addr),
        .desc_buf_rd_req_vld  (desc_buf_rd_req_vld),
        .desc_buf_rd_rsp_dat  (desc_buf_rd_rsp_dat),
        .desc_buf_rd_rsp_vld  (desc_buf_rd_rsp_vld),
        // blk_desc
        .blk_desc_vld         (blk_desc_vld),
        .blk_desc_rdy         (blk_desc_rdy),
        // .blk_desc_rdy        (1'b1),
        .blk_desc_sop         (blk_desc_sop),
        .blk_desc_eop         (blk_desc_eop),
        .blk_desc_sbd         (blk_desc_sbd),
        .blk_desc_dat         (blk_desc_dat),
        .state                (free_state),
        .err                  (free_err)

    );


    virtio_blk_desc_engine_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .QID_NUM(QID_NUM),
        .SLOT_NUM(SLOT_NUM)
    ) u_virtio_blk_desc_engine_core (
        .clk                                         (clk),
        .rst                                         (rst),
        // first_submit
        .first_submit_vld                            (first_submit_vld),
        .first_submit_rdy                            (first_submit_rdy),
        .first_submit_qid                            (first_submit_qid),
        .first_submit_idx                            (first_submit_idx),
        .first_submit_id                             (first_submit_id),
        .first_submit_resummer                       (first_submit_resummer),
        .first_submit_cycle_flag                     (first_submit_cycle_flag),
        .first_submit_slot_id                        (first_submit_slot_id),
        // desc_dma_rd_req
        .desc_dma_rd_req                             (desc_dma_rd_req),
        // rsp_submit
        .info_rd_vld                                 (info_rd_vld),
        .info_rd_dat                                 (info_rd_dat),
        .info_rd_rdy                                 (info_rd_rdy),
        // slot_cpl_ff_rd
        // .slot_cpl_ff_rden                         (slot_cpl_ff_rden),
        // .slot_cpl_ff_dout                         (slot_cpl_ff_dout),
        // .slot_cpl_ff_empty                        (slot_cpl_ff_empty),
        .slot_cpl_ram_raddr                          (slot_cpl_ram_raddr),
        .slot_cpl_ram_rdata                          (slot_cpl_ram_rdata),
        // order_wr
        .order_wr_vld                                (order_wr_vld),
        .order_wr_dat                                (order_wr_dat),
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
        .blk_desc_local_info_wr_desc_cnt             (blk_desc_local_info_wr_desc_cnt),
        .blk_desc_local_info_wr_data_len             (blk_desc_local_info_wr_data_len),
        .blk_desc_local_info_wr_is_indirct           (blk_desc_local_info_wr_is_indirct),
        // blk_desc_resumer_wr
        .blk_desc_resumer_wr_vld                     (blk_desc_resumer_wr_vld),
        .blk_desc_resumer_wr_qid                     (blk_desc_resumer_wr_qid),
        .blk_desc_resumer_wr_dat                     (blk_desc_resumer_wr_dat),
        .state                                       (core_state),
        .err                                         (core_err),
        .flush_resummer                              (flush_resummer),
        .virtio_blk_desc_engine_max_chain_len        (virtio_blk_desc_engine_max_chain_len)
    );

    virtio_desc_engine_desc_buf #(
        .DATA_WIDTH(DATA_WIDTH),
        .SLOT_NUM(32),  // inside slot use 4 will be 4-8 = -4 error
        .LINE_NUM(LINE_NUM),
        .BUCKET_NUM(BUCKET_NUM)
    ) u_virtio_blk_desc_engine_desc_buf (
        .clk                 (clk),
        .rst                 (rst),
        .dma_desc_rd_rsp_if  (desc_dma_rd_rsp),
        .order_wr_vld        (order_wr_vld),
        .order_wr_dat        (order_wr_dat),
        .info_rd_vld         (info_rd_vld),
        .info_rd_dat         (info_rd_dat),
        .info_rd_rdy         (info_rd_rdy),
        .desc_buf_rd_req_addr(desc_buf_rd_req_addr),
        .desc_buf_rd_req_vld (desc_buf_rd_req_vld),
        .desc_buf_rd_rsp_dat (desc_buf_rd_rsp_dat),
        .desc_buf_rd_rsp_vld (desc_buf_rd_rsp_vld)
    );

    // assign state = {alloc_state, free_state, core_state};
    // assign err   = {alloc_err, free_err, core_err};

    logic [19:0] virtio_blk_desc_engine_max_chain_len_virtio_blk_desc_engine_max_chain_len_q;

    logic        virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_we;
    logic [63:0] virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_wdata;
    logic [63:0] virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_q;

    logic        virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_we;
    logic [63:0] virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_wdata;
    logic [63:0] virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_q;

    logic        virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_we;
    logic [63:0] virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_wdata;
    logic [63:0] virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_q;

    logic [63:0] virtio_blk_desc_engine_alloc_status_virtio_blk_desc_engine_alloc_status_wdata;
    logic [63:0] virtio_blk_desc_engine_free_status_virtio_blk_desc_engine_free_status_wdata;
    logic [63:0] virtio_blk_desc_engine_core_status_virtio_blk_desc_engine_core_status_wdata;



    virtio_blk_desc_engine_dfx #(
        .ADDR_OFFSET(0),
        .ADDR_WIDTH (12),
        .DATA_WIDTH (64)
    ) u_virtio_blk_desc_engine_dfx (
        .clk                                                                          (clk),
        .rst                                                                          (rst),
        .virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_we         (virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_we),
        .virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_wdata      (virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_wdata),
        .virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_q          (virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_q),
        .virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_we           (virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_we),
        .virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_wdata        (virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_wdata),
        .virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_q            (virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_q),
        .virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_we           (virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_we),
        .virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_wdata        (virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_wdata),
        .virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_q            (virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_q),
        .virtio_blk_desc_engine_alloc_status_virtio_blk_desc_engine_alloc_status_wdata(virtio_blk_desc_engine_alloc_status_virtio_blk_desc_engine_alloc_status_wdata),
        .virtio_blk_desc_engine_free_status_virtio_blk_desc_engine_free_status_wdata  (virtio_blk_desc_engine_free_status_virtio_blk_desc_engine_free_status_wdata),
        .virtio_blk_desc_engine_core_status_virtio_blk_desc_engine_core_status_wdata  (virtio_blk_desc_engine_core_status_virtio_blk_desc_engine_core_status_wdata),
        .virtio_blk_desc_engine_max_chain_len_virtio_blk_desc_engine_max_chain_len_q  (virtio_blk_desc_engine_max_chain_len_virtio_blk_desc_engine_max_chain_len_q),
        .csr_if                                                                       (dfx_if)
    );



    assign virtio_blk_desc_engine_alloc_status_virtio_blk_desc_engine_alloc_status_wdata = {'b0, alloc_state};
    assign virtio_blk_desc_engine_free_status_virtio_blk_desc_engine_free_status_wdata   = {'b0, free_state};
    assign virtio_blk_desc_engine_core_status_virtio_blk_desc_engine_core_status_wdata   = {'b0, core_state};

    assign virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_we          = |alloc_err;
    assign virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_wdata       = virtio_blk_desc_engine_alloc_err_virtio_blk_desc_engine_alloc_err_q | alloc_err;

    assign virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_we            = |free_err;
    assign virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_wdata         = virtio_blk_desc_engine_free_err_virtio_blk_desc_engine_free_err_q | free_err;

    assign virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_we            = |core_err;
    assign virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_wdata         = virtio_blk_desc_engine_core_err_virtio_blk_desc_engine_core_err_q | core_err;





    assign virtio_blk_desc_engine_max_chain_len                                          = virtio_blk_desc_engine_max_chain_len_virtio_blk_desc_engine_max_chain_len_q;



endmodule : virtio_blk_desc_engine_top
