/******************************************************************************
 * 文件名称 : virtio_desc_engine_top.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/07/16
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/16     Joe Jiang   初始化版本
 ******************************************************************************/
 `include "virtio_define.svh"
 module virtio_desc_engine_top #(
    parameter Q_NUM                          = 256,
    parameter Q_WIDTH                        = $clog2(Q_NUM),
    parameter DEV_ID_NUM                     = 1024,
    parameter DEV_ID_WIDTH                   = $clog2(DEV_ID_NUM),
    parameter DATA_WIDTH                     = 256,
    parameter EMPTH_WIDTH                    = $clog2(DATA_WIDTH/8),
    parameter PKT_ID_NUM                     = 1024,
    parameter PKT_ID_WIDTH                   = $clog2(PKT_ID_NUM),
    parameter SLOT_NUM                       = 32,
    parameter SLOT_WIDTH                     = $clog2(SLOT_NUM),
    parameter BUCKET_NUM                     = 128,
    parameter BUCKET_WIDTH                   = $clog2(BUCKET_NUM),
    parameter LINE_NUM                       = 8,
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

    tlp_adap_dma_rd_req_if.src                                  net_rx_dma_desc_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  net_rx_dma_desc_rd_rsp_if,
    tlp_adap_dma_rd_req_if.src                                  net_tx_dma_desc_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  net_tx_dma_desc_rd_rsp_if,

    input  logic                                                net_rx_alloc_slot_req_vld,
    output logic                                                net_rx_alloc_slot_req_rdy,
    input  logic [9:0]                                          net_rx_alloc_slot_req_dev_id,
    input  logic [PKT_ID_WIDTH-1:0]                             net_rx_alloc_slot_req_pkt_id,
    input  virtio_vq_t                                          net_rx_alloc_slot_req_vq,
    output logic                                                net_rx_alloc_slot_rsp_vld,
    output virtio_desc_eng_slot_rsp_t                           net_rx_alloc_slot_rsp_dat,
    input  logic                                                net_rx_alloc_slot_rsp_rdy,

    input  logic                                                net_tx_alloc_slot_req_vld,
    output logic                                                net_tx_alloc_slot_req_rdy,
    input  logic [9:0]                                          net_tx_alloc_slot_req_dev_id,
    input  logic [9:0]                                          net_tx_alloc_slot_req_pkt_id,
    input  virtio_vq_t                                          net_tx_alloc_slot_req_vq,
    output logic                                                net_tx_alloc_slot_rsp_vld,
    output virtio_desc_eng_slot_rsp_t                           net_tx_alloc_slot_rsp_dat,
    input  logic                                                net_tx_alloc_slot_rsp_rdy,

    output logic                                                net_rx_avail_id_req_vld,
    output logic [3:0]                                          net_rx_avail_id_req_nid,
    input  logic                                                net_rx_avail_id_req_rdy,
    output virtio_vq_t                                          net_rx_avail_id_req_vq,
    input  logic                                                net_rx_avail_id_rsp_vld,
    input  logic                                                net_rx_avail_id_rsp_eop,
    output logic                                                net_rx_avail_id_rsp_rdy,
    input  virtio_avail_id_rsp_dat_t                            net_rx_avail_id_rsp_dat,

    output logic                                                net_tx_avail_id_req_vld,
    output logic [3:0]                                          net_tx_avail_id_req_nid,
    input  logic                                                net_tx_avail_id_req_rdy,
    output virtio_vq_t                                          net_tx_avail_id_req_vq,
    input  logic                                                net_tx_avail_id_rsp_vld,
    input  logic                                                net_tx_avail_id_rsp_eop,
    output logic                                                net_tx_avail_id_rsp_rdy,
    input  virtio_avail_id_rsp_dat_t                            net_tx_avail_id_rsp_dat,

    output logic                                                net_rx_desc_rsp_vld,
    output virtio_desc_eng_desc_rsp_sbd_t                       net_rx_desc_rsp_sbd,
    output logic                                                net_rx_desc_rsp_sop,
    output logic                                                net_rx_desc_rsp_eop,
    output virtq_desc_t                                         net_rx_desc_rsp_dat,
    input  logic                                                net_rx_desc_rsp_rdy, 

    output logic                                                net_tx_desc_rsp_vld,
    output virtio_desc_eng_desc_rsp_sbd_t                       net_tx_desc_rsp_sbd,
    output logic                                                net_tx_desc_rsp_sop,
    output logic                                                net_tx_desc_rsp_eop,
    output virtq_desc_t                                         net_tx_desc_rsp_dat,
    input  logic                                                net_tx_desc_rsp_rdy, 

    output logic                                                net_rx_ctx_info_rd_req_vld,
    output virtio_vq_t                                          net_rx_ctx_info_rd_req_vq,
    input  logic                                                net_rx_ctx_info_rd_rsp_vld,
    input  logic [63:0]                                         net_rx_ctx_info_rd_rsp_desc_tbl_addr,
    input  logic [3:0]                                          net_rx_ctx_info_rd_rsp_qdepth,
    input  logic                                                net_rx_ctx_info_rd_rsp_forced_shutdown,
    input  logic                                                net_rx_ctx_info_rd_rsp_indirct_support,
    input  logic [19:0]                                         net_rx_ctx_info_rd_rsp_max_len,
    input  logic [15:0]                                         net_rx_ctx_info_rd_rsp_bdf,
    output logic                                                net_rx_ctx_slot_chain_rd_req_vld,
    output virtio_vq_t                                          net_rx_ctx_slot_chain_rd_req_vq,
    input  logic                                                net_rx_ctx_slot_chain_rd_rsp_vld,
    input  logic [SLOT_WIDTH-1:0]                               net_rx_ctx_slot_chain_rd_rsp_head_slot,
    input  logic                                                net_rx_ctx_slot_chain_rd_rsp_head_slot_vld,
    input  logic [SLOT_WIDTH-1:0]                               net_rx_ctx_slot_chain_rd_rsp_tail_slot,
    output logic                                                net_rx_ctx_slot_chain_wr_vld,
    output virtio_vq_t                                          net_rx_ctx_slot_chain_wr_vq,
    output logic [SLOT_WIDTH-1:0]                               net_rx_ctx_slot_chain_wr_head_slot,
    output logic                                                net_rx_ctx_slot_chain_wr_head_slot_vld,
    output logic [SLOT_WIDTH-1:0]                               net_rx_ctx_slot_chain_wr_tail_slot,

    output logic                                                net_tx_ctx_info_rd_req_vld,
    output virtio_vq_t                                          net_tx_ctx_info_rd_req_vq,
    input  logic                                                net_tx_ctx_info_rd_rsp_vld,
    input  logic [63:0]                                         net_tx_ctx_info_rd_rsp_desc_tbl_addr,
    input  logic [3:0]                                          net_tx_ctx_info_rd_rsp_qdepth,
    input  logic                                                net_tx_ctx_info_rd_rsp_forced_shutdown,
    input  logic                                                net_tx_ctx_info_rd_rsp_indirct_support,
    input  logic [19:0]                                         net_tx_ctx_info_rd_rsp_max_len,
    input  logic [15:0]                                         net_tx_ctx_info_rd_rsp_bdf,
    output logic                                                net_tx_ctx_slot_chain_rd_req_vld,
    output virtio_vq_t                                          net_tx_ctx_slot_chain_rd_req_vq,
    input  logic                                                net_tx_ctx_slot_chain_rd_rsp_vld,
    input  logic [SLOT_WIDTH-1:0]                               net_tx_ctx_slot_chain_rd_rsp_head_slot,
    input  logic                                                net_tx_ctx_slot_chain_rd_rsp_head_slot_vld,
    input  logic [SLOT_WIDTH-1:0]                               net_tx_ctx_slot_chain_rd_rsp_tail_slot,
    output logic                                                net_tx_ctx_slot_chain_wr_vld,
    output virtio_vq_t                                          net_tx_ctx_slot_chain_wr_vq,
    output logic [SLOT_WIDTH-1:0]                               net_tx_ctx_slot_chain_wr_head_slot,
    output logic                                                net_tx_ctx_slot_chain_wr_head_slot_vld,
    output logic [SLOT_WIDTH-1:0]                               net_tx_ctx_slot_chain_wr_tail_slot,

    output logic                                                net_tx_limit_per_queue_rd_req_vld,
    output logic [Q_WIDTH-1:0]                                  net_tx_limit_per_queue_rd_req_qid,
    input  logic                                                net_tx_limit_per_queue_rd_rsp_vld,
    input  logic [7:0]                                          net_tx_limit_per_queue_rd_rsp_dat,
    output logic                                                net_tx_limit_per_dev_rd_req_vld,
    output logic [DEV_ID_WIDTH-1:0]                             net_tx_limit_per_dev_rd_req_dev_id,
    input  logic                                                net_tx_limit_per_dev_rd_rsp_vld,
    input  logic [7:0]                                          net_tx_limit_per_dev_rd_rsp_dat,
    mlite_if.slave                                              dfx_if
 );

    logic                                                net_rx_slot_submit_vld;
    logic [SLOT_WIDTH-1:0]                               net_rx_slot_submit_slot_id;
    virtio_vq_t                                          net_rx_slot_submit_vq;
    logic [DEV_ID_WIDTH-1:0]                             net_rx_slot_submit_dev_id;
    logic [PKT_ID_WIDTH-1:0]                             net_rx_slot_submit_pkt_id;
    logic [15:0]                                         net_rx_slot_submit_ring_id;
    logic [15:0]                                         net_rx_slot_submit_avail_idx;
    virtio_err_info_t                                    net_rx_slot_submit_err;
    logic                                                net_rx_slot_submit_rdy;
    logic                                                net_tx_slot_submit_vld;
    logic [SLOT_WIDTH-1:0]                               net_tx_slot_submit_slot_id;
    virtio_vq_t                                          net_tx_slot_submit_vq;
    logic [DEV_ID_WIDTH-1:0]                             net_tx_slot_submit_dev_id;
    logic [PKT_ID_WIDTH-1:0]                             net_tx_slot_submit_pkt_id;
    logic [15:0]                                         net_tx_slot_submit_ring_id;
    logic [15:0]                                         net_tx_slot_submit_avail_idx;
    virtio_err_info_t                                    net_tx_slot_submit_err;
    logic                                                net_tx_slot_submit_rdy;

    logic                                                net_rx_slot_cpl_vld;
    logic [SLOT_WIDTH-1:0]                               net_rx_slot_cpl_slot_id;
    virtio_vq_t                                          net_rx_slot_cpl_vq;
    logic                                                net_rx_slot_cpl_sav;
    logic                                                net_rx_rd_desc_req_vld;
    logic [SLOT_WIDTH-1:0]                               net_rx_rd_desc_req_slot_id;
    logic                                                net_rx_rd_desc_req_rdy;
    logic                                                net_rx_rd_desc_rsp_vld;
    virtio_desc_eng_desc_rsp_sbd_t                       net_rx_rd_desc_rsp_sbd;
    logic                                                net_rx_rd_desc_rsp_sop;
    logic                                                net_rx_rd_desc_rsp_eop;
    virtq_desc_t                                         net_rx_rd_desc_rsp_dat;
    logic                                                net_rx_rd_desc_rsp_rdy;

    logic                                                net_tx_slot_cpl_vld;
    logic [SLOT_WIDTH-1:0]                               net_tx_slot_cpl_slot_id;
    virtio_vq_t                                          net_tx_slot_cpl_vq;
    logic                                                net_tx_slot_cpl_sav;
    logic                                                net_tx_rd_desc_req_vld;
    logic [SLOT_WIDTH-1:0]                               net_tx_rd_desc_req_slot_id;
    logic                                                net_tx_rd_desc_req_rdy;
    logic                                                net_tx_rd_desc_rsp_vld;
    virtio_desc_eng_desc_rsp_sbd_t                       net_tx_rd_desc_rsp_sbd;
    logic                                                net_tx_rd_desc_rsp_sop;
    logic                                                net_tx_rd_desc_rsp_eop;
    virtq_desc_t                                         net_tx_rd_desc_rsp_dat;
    logic                                                net_tx_rd_desc_rsp_rdy;

    logic [27:0]                                         slot_mgmt_tx_dfx_err, slot_mgmt_tx_dfx_err_q;
    logic [19:0]                                         slot_mgmt_tx_dfx_status;
    logic [7:0]                                          slot_mgmt_tx_alloc_slot_req_cnt; 
    logic [7:0]                                          slot_mgmt_tx_alloc_slot_rsp_cnt; 
    logic [7:0]                                          slot_mgmt_tx_alloc_slot_limit_cnt;
    logic [7:0]                                          slot_mgmt_tx_alloc_slot_ok_cnt;
    logic [7:0]                                          slot_mgmt_tx_avail_id_req_cnt; 
    logic [7:0]                                          slot_mgmt_tx_avail_id_rsp_cnt; 
    logic [7:0]                                          slot_mgmt_tx_avail_id_rsp_pkt_cnt;
    logic [7:0]                                          slot_mgmt_tx_avail_id_got_id_cnt;
    logic [7:0]                                          slot_mgmt_tx_avail_id_err_cnt;
    logic [7:0]                                          slot_mgmt_tx_slot_submit_cnt; 
    logic [7:0]                                          slot_mgmt_tx_slot_cpl_cnt;
    logic [7:0]                                          slot_mgmt_tx_rd_desc_req_cnt; 
    logic [7:0]                                          slot_mgmt_tx_rd_desc_rsp_cnt; 
    logic [7:0]                                          slot_mgmt_tx_rd_desc_rsp_pkt_cnt;
    logic [7:0]                                          slot_mgmt_tx_slot_err_cnt;
    logic [7:0]                                          slot_mgmt_tx_desc_rsp_cnt; 
    logic [7:0]                                          slot_mgmt_tx_desc_rsp_pkt_cnt;

    logic [27:0]                                         slot_mgmt_rx_dfx_err, slot_mgmt_rx_dfx_err_q;
    logic [19:0]                                         slot_mgmt_rx_dfx_status;
    logic [7:0]                                          slot_mgmt_rx_alloc_slot_req_cnt; 
    logic [7:0]                                          slot_mgmt_rx_alloc_slot_rsp_cnt; 
    logic [7:0]                                          slot_mgmt_rx_alloc_slot_limit_cnt;
    logic [7:0]                                          slot_mgmt_rx_alloc_slot_ok_cnt;
    logic [7:0]                                          slot_mgmt_rx_avail_id_req_cnt; 
    logic [7:0]                                          slot_mgmt_rx_avail_id_rsp_cnt; 
    logic [7:0]                                          slot_mgmt_rx_avail_id_rsp_pkt_cnt;
    logic [7:0]                                          slot_mgmt_rx_avail_id_got_id_cnt;
    logic [7:0]                                          slot_mgmt_rx_avail_id_err_cnt;
    logic [7:0]                                          slot_mgmt_rx_slot_submit_cnt; 
    logic [7:0]                                          slot_mgmt_rx_slot_cpl_cnt;
    logic [7:0]                                          slot_mgmt_rx_rd_desc_req_cnt; 
    logic [7:0]                                          slot_mgmt_rx_rd_desc_rsp_cnt; 
    logic [7:0]                                          slot_mgmt_rx_rd_desc_rsp_pkt_cnt;
    logic [7:0]                                          slot_mgmt_rx_slot_err_cnt;
    logic [7:0]                                          slot_mgmt_rx_desc_rsp_cnt; 
    logic [7:0]                                          slot_mgmt_rx_desc_rsp_pkt_cnt;

    logic [44:0]                                         core_tx_dfx_err, core_tx_dfx_err_q;
    logic [62:0]                                         core_tx_dfx_status;
    logic [7:0]                                          core_tx_dma_req_cnt;
    logic [7:0]                                          core_tx_dma_rsp_cnt;
    logic [7:0]                                          core_tx_sch_out_forced_shutdown_cnt;
    logic [7:0]                                          core_tx_sch_out_wake_up_cnt;
    logic [7:0]                                          core_tx_sch_out_desc_rsp_cnt;
    logic [7:0]                                          core_tx_desc_buf_order_wr_cnt; 
    logic [7:0]                                          core_tx_desc_buf_info_rd_cnt;
    logic [7:0]                                          core_tx_wake_up_cnt;

    logic [44:0]                                         core_rx_dfx_err, core_rx_dfx_err_q;
    logic [62:0]                                         core_rx_dfx_status;
    logic [7:0]                                          core_rx_dma_req_cnt;
    logic [7:0]                                          core_rx_dma_rsp_cnt;
    logic [7:0]                                          core_rx_sch_out_forced_shutdown_cnt;
    logic [7:0]                                          core_rx_sch_out_wake_up_cnt;
    logic [7:0]                                          core_rx_sch_out_desc_rsp_cnt;
    logic [7:0]                                          core_rx_desc_buf_order_wr_cnt; 
    logic [7:0]                                          core_rx_desc_buf_info_rd_cnt;
    logic [7:0]                                          core_rx_wake_up_cnt;
    logic [15:0]                                         rx_used_slot_num, tx_used_slot_num;

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
        .MAX_BUCKET_PER_SLOT_WIDTH(MAX_BUCKET_PER_SLOT_WIDTH),
        .NET_RX                   (1                        )
    ) net_rx_desc_engine_core (
        .clk                                 (clk                                 ),
        .rst                                 (rst                                 ),
        .dma_desc_rd_req_if                  (net_rx_dma_desc_rd_req_if                  ),
        .dma_desc_rd_rsp_if                  (net_rx_dma_desc_rd_rsp_if                  ),
        .slot_submit_vld                     (net_rx_slot_submit_vld                     ),
        .slot_submit_slot_id                 (net_rx_slot_submit_slot_id                 ),
        .slot_submit_vq                      (net_rx_slot_submit_vq                      ),
        .slot_submit_dev_id                  (net_rx_slot_submit_dev_id                  ),
        .slot_submit_pkt_id                  (net_rx_slot_submit_pkt_id                  ),
        .slot_submit_ring_id                 (net_rx_slot_submit_ring_id                 ),
        .slot_submit_avail_idx               (net_rx_slot_submit_avail_idx               ),
        .slot_submit_err                     (net_rx_slot_submit_err                     ),
        .slot_submit_rdy                     (net_rx_slot_submit_rdy                     ),
        .slot_cpl_vld                        (net_rx_slot_cpl_vld                        ),
        .slot_cpl_slot_id                    (net_rx_slot_cpl_slot_id                    ),
        .slot_cpl_vq                         (net_rx_slot_cpl_vq                         ),
        .slot_cpl_sav                        (net_rx_slot_cpl_sav                        ),
        .rd_desc_req_vld                     (net_rx_rd_desc_req_vld                     ),
        .rd_desc_req_slot_id                 (net_rx_rd_desc_req_slot_id                 ),
        .rd_desc_req_rdy                     (net_rx_rd_desc_req_rdy                     ),
        .rd_desc_rsp_vld                     (net_rx_rd_desc_rsp_vld                     ),
        .rd_desc_rsp_sbd                     (net_rx_rd_desc_rsp_sbd                     ),
        .rd_desc_rsp_sop                     (net_rx_rd_desc_rsp_sop                     ),
        .rd_desc_rsp_eop                     (net_rx_rd_desc_rsp_eop                     ),
        .rd_desc_rsp_dat                     (net_rx_rd_desc_rsp_dat                     ),
        .rd_desc_rsp_rdy                     (net_rx_rd_desc_rsp_rdy                     ),
        .ctx_info_rd_req_vld                 (net_rx_ctx_info_rd_req_vld                   ),
        .ctx_info_rd_req_vq                  (net_rx_ctx_info_rd_req_vq                    ),
        .ctx_info_rd_rsp_vld                 (net_rx_ctx_info_rd_rsp_vld                   ),
        .ctx_info_rd_rsp_desc_tbl_addr       (net_rx_ctx_info_rd_rsp_desc_tbl_addr         ),   
        .ctx_info_rd_rsp_qdepth              (net_rx_ctx_info_rd_rsp_qdepth                ),
        .ctx_info_rd_rsp_forced_shutdown     (net_rx_ctx_info_rd_rsp_forced_shutdown       ),   
        .ctx_info_rd_rsp_indirct_support     (net_rx_ctx_info_rd_rsp_indirct_support       ),   
        .ctx_info_rd_rsp_max_len             (net_rx_ctx_info_rd_rsp_max_len               ),
        .ctx_info_rd_rsp_bdf                 (net_rx_ctx_info_rd_rsp_bdf                   ),
        .ctx_slot_chain_rd_req_vld           (net_rx_ctx_slot_chain_rd_req_vld             ),
        .ctx_slot_chain_rd_req_vq            (net_rx_ctx_slot_chain_rd_req_vq              ),
        .ctx_slot_chain_rd_rsp_vld           (net_rx_ctx_slot_chain_rd_rsp_vld             ),
        .ctx_slot_chain_rd_rsp_head_slot     (net_rx_ctx_slot_chain_rd_rsp_head_slot       ),
        .ctx_slot_chain_rd_rsp_head_slot_vld (net_rx_ctx_slot_chain_rd_rsp_head_slot_vld   ),
        .ctx_slot_chain_rd_rsp_tail_slot     (net_rx_ctx_slot_chain_rd_rsp_tail_slot       ),
        .ctx_slot_chain_wr_vld               (net_rx_ctx_slot_chain_wr_vld                 ),
        .ctx_slot_chain_wr_vq                (net_rx_ctx_slot_chain_wr_vq                  ),       
        .ctx_slot_chain_wr_head_slot         (net_rx_ctx_slot_chain_wr_head_slot           ),
        .ctx_slot_chain_wr_head_slot_vld     (net_rx_ctx_slot_chain_wr_head_slot_vld       ),
        .ctx_slot_chain_wr_tail_slot         (net_rx_ctx_slot_chain_wr_tail_slot           ),
        .dfx_err                             (core_rx_dfx_err                              ),
        .dfx_status                          (core_rx_dfx_status                           ),
        .dma_req_cnt                         (core_rx_dma_req_cnt                          ),
        .dma_rsp_cnt                         (core_rx_dma_rsp_cnt                          ),
        .sch_out_forced_shutdown_cnt         (core_rx_sch_out_forced_shutdown_cnt          ), 
        .sch_out_wake_up_cnt                 (core_rx_sch_out_wake_up_cnt                  ), 
        .sch_out_desc_rsp_cnt                (core_rx_sch_out_desc_rsp_cnt                 ),
        .desc_buf_order_wr_cnt               (core_rx_desc_buf_order_wr_cnt                ), 
        .desc_buf_info_rd_cnt                (core_rx_desc_buf_info_rd_cnt                 ), 
        .wake_up_cnt                         (core_rx_wake_up_cnt                          )
    );

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
        .MAX_BUCKET_PER_SLOT_WIDTH(MAX_BUCKET_PER_SLOT_WIDTH),
        .NET_RX                   (0                        )
    ) net_tx_desc_engine_core (
        .clk                                 (clk                                 ),
        .rst                                 (rst                                 ),
        .dma_desc_rd_req_if                  (net_tx_dma_desc_rd_req_if                  ),
        .dma_desc_rd_rsp_if                  (net_tx_dma_desc_rd_rsp_if                  ),
        .slot_submit_vld                     (net_tx_slot_submit_vld                     ),
        .slot_submit_slot_id                 (net_tx_slot_submit_slot_id                 ),
        .slot_submit_vq                      (net_tx_slot_submit_vq                      ),
        .slot_submit_dev_id                  (net_tx_slot_submit_dev_id                  ),
        .slot_submit_pkt_id                  (net_tx_slot_submit_pkt_id                  ),
        .slot_submit_ring_id                 (net_tx_slot_submit_ring_id                 ),
        .slot_submit_avail_idx               (net_tx_slot_submit_avail_idx               ),
        .slot_submit_err                     (net_tx_slot_submit_err                     ),
        .slot_submit_rdy                     (net_tx_slot_submit_rdy                     ),
        .slot_cpl_vld                        (net_tx_slot_cpl_vld                        ),
        .slot_cpl_slot_id                    (net_tx_slot_cpl_slot_id                    ),
        .slot_cpl_vq                         (net_tx_slot_cpl_vq                         ),
        .slot_cpl_sav                        (net_tx_slot_cpl_sav                        ),
        .rd_desc_req_vld                     (net_tx_rd_desc_req_vld                     ),
        .rd_desc_req_slot_id                 (net_tx_rd_desc_req_slot_id                 ),
        .rd_desc_req_rdy                     (net_tx_rd_desc_req_rdy                     ),
        .rd_desc_rsp_vld                     (net_tx_rd_desc_rsp_vld                     ),
        .rd_desc_rsp_sbd                     (net_tx_rd_desc_rsp_sbd                     ),
        .rd_desc_rsp_sop                     (net_tx_rd_desc_rsp_sop                     ),
        .rd_desc_rsp_eop                     (net_tx_rd_desc_rsp_eop                     ),
        .rd_desc_rsp_dat                     (net_tx_rd_desc_rsp_dat                     ),
        .rd_desc_rsp_rdy                     (net_tx_rd_desc_rsp_rdy                     ),
        .ctx_info_rd_req_vld                 (net_tx_ctx_info_rd_req_vld                   ),
        .ctx_info_rd_req_vq                  (net_tx_ctx_info_rd_req_vq                    ),
        .ctx_info_rd_rsp_vld                 (net_tx_ctx_info_rd_rsp_vld                   ),
        .ctx_info_rd_rsp_desc_tbl_addr       (net_tx_ctx_info_rd_rsp_desc_tbl_addr         ),   
        .ctx_info_rd_rsp_qdepth              (net_tx_ctx_info_rd_rsp_qdepth                ),
        .ctx_info_rd_rsp_forced_shutdown     (net_tx_ctx_info_rd_rsp_forced_shutdown       ),   
        .ctx_info_rd_rsp_indirct_support     (net_tx_ctx_info_rd_rsp_indirct_support       ),  
        .ctx_info_rd_rsp_max_len             (net_tx_ctx_info_rd_rsp_max_len               ), 
        .ctx_info_rd_rsp_bdf                 (net_tx_ctx_info_rd_rsp_bdf                   ),
        .ctx_slot_chain_rd_req_vld           (net_tx_ctx_slot_chain_rd_req_vld             ),
        .ctx_slot_chain_rd_req_vq            (net_tx_ctx_slot_chain_rd_req_vq              ),
        .ctx_slot_chain_rd_rsp_vld           (net_tx_ctx_slot_chain_rd_rsp_vld             ),
        .ctx_slot_chain_rd_rsp_head_slot     (net_tx_ctx_slot_chain_rd_rsp_head_slot       ),
        .ctx_slot_chain_rd_rsp_head_slot_vld (net_tx_ctx_slot_chain_rd_rsp_head_slot_vld   ),
        .ctx_slot_chain_rd_rsp_tail_slot     (net_tx_ctx_slot_chain_rd_rsp_tail_slot       ),
        .ctx_slot_chain_wr_vld               (net_tx_ctx_slot_chain_wr_vld                 ),
        .ctx_slot_chain_wr_vq                (net_tx_ctx_slot_chain_wr_vq                  ),       
        .ctx_slot_chain_wr_head_slot         (net_tx_ctx_slot_chain_wr_head_slot           ),
        .ctx_slot_chain_wr_head_slot_vld     (net_tx_ctx_slot_chain_wr_head_slot_vld       ),
        .ctx_slot_chain_wr_tail_slot         (net_tx_ctx_slot_chain_wr_tail_slot           ),
        .dfx_err                             (core_tx_dfx_err                              ),
        .dfx_status                          (core_tx_dfx_status                           ),
        .dma_req_cnt                         (core_tx_dma_req_cnt                          ),
        .dma_rsp_cnt                         (core_tx_dma_rsp_cnt                          ),
        .sch_out_forced_shutdown_cnt         (core_tx_sch_out_forced_shutdown_cnt          ), 
        .sch_out_wake_up_cnt                 (core_tx_sch_out_wake_up_cnt                  ), 
        .sch_out_desc_rsp_cnt                (core_tx_sch_out_desc_rsp_cnt                 ),
        .desc_buf_order_wr_cnt               (core_tx_desc_buf_order_wr_cnt                ), 
        .desc_buf_info_rd_cnt                (core_tx_desc_buf_info_rd_cnt                 ), 
        .wake_up_cnt                         (core_tx_wake_up_cnt                          )
    );

    virtio_desc_engine_slot_mgmt #(
        .TXQ                      (0                        ),
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
    ) net_rx_desc_engine_slot_mgmt (
        .clk                         (clk                                ),
        .rst                         (rst                                ),
        .alloc_slot_req_vld          (net_rx_alloc_slot_req_vld          ),
        .alloc_slot_req_rdy          (net_rx_alloc_slot_req_rdy          ),
        .alloc_slot_req_dev_id       (net_rx_alloc_slot_req_dev_id       ),
        .alloc_slot_req_pkt_id       (net_rx_alloc_slot_req_pkt_id       ),
        .alloc_slot_req_vq           (net_rx_alloc_slot_req_vq           ),
        .alloc_slot_rsp_vld          (net_rx_alloc_slot_rsp_vld          ),
        .alloc_slot_rsp_dat          (net_rx_alloc_slot_rsp_dat          ),
        .alloc_slot_rsp_rdy          (net_rx_alloc_slot_rsp_rdy          ),
        .avail_id_req_vld            (net_rx_avail_id_req_vld            ),
        .avail_id_req_nid            (net_rx_avail_id_req_nid            ),
        .avail_id_req_rdy            (net_rx_avail_id_req_rdy            ),
        .avail_id_req_vq             (net_rx_avail_id_req_vq             ),
        .avail_id_rsp_vld            (net_rx_avail_id_rsp_vld            ),
        .avail_id_rsp_eop            (net_rx_avail_id_rsp_eop            ),
        .avail_id_rsp_rdy            (net_rx_avail_id_rsp_rdy            ),
        .avail_id_rsp_dat            (net_rx_avail_id_rsp_dat            ),
        .slot_submit_vld             (net_rx_slot_submit_vld             ),
        .slot_submit_slot_id         (net_rx_slot_submit_slot_id         ),
        .slot_submit_vq              (net_rx_slot_submit_vq              ),
        .slot_submit_dev_id          (net_rx_slot_submit_dev_id          ),
        .slot_submit_pkt_id          (net_rx_slot_submit_pkt_id          ),
        .slot_submit_ring_id         (net_rx_slot_submit_ring_id         ),
        .slot_submit_avail_idx       (net_rx_slot_submit_avail_idx       ),
        .slot_submit_err             (net_rx_slot_submit_err             ),
        .slot_submit_rdy             (net_rx_slot_submit_rdy             ),
        .slot_cpl_vld                (net_rx_slot_cpl_vld                ),
        .slot_cpl_slot_id            (net_rx_slot_cpl_slot_id            ),
        .slot_cpl_vq                 (net_rx_slot_cpl_vq                 ),
        .slot_cpl_sav                (net_rx_slot_cpl_sav                ),
        .rd_desc_req_vld             (net_rx_rd_desc_req_vld             ),
        .rd_desc_req_slot_id         (net_rx_rd_desc_req_slot_id         ),
        .rd_desc_req_rdy             (net_rx_rd_desc_req_rdy             ),
        .rd_desc_rsp_vld             (net_rx_rd_desc_rsp_vld             ),
        .rd_desc_rsp_sbd             (net_rx_rd_desc_rsp_sbd             ),
        .rd_desc_rsp_sop             (net_rx_rd_desc_rsp_sop             ),
        .rd_desc_rsp_eop             (net_rx_rd_desc_rsp_eop             ),
        .rd_desc_rsp_dat             (net_rx_rd_desc_rsp_dat             ),
        .rd_desc_rsp_rdy             (net_rx_rd_desc_rsp_rdy             ),
        .desc_rsp_vld                (net_rx_desc_rsp_vld                ),
        .desc_rsp_sbd                (net_rx_desc_rsp_sbd                ),
        .desc_rsp_sop                (net_rx_desc_rsp_sop                ),
        .desc_rsp_eop                (net_rx_desc_rsp_eop                ),
        .desc_rsp_dat                (net_rx_desc_rsp_dat                ),
        .desc_rsp_rdy                (net_rx_desc_rsp_rdy                ), 
        .limit_per_queue_rd_req_vld  (                                   ),
        .limit_per_queue_rd_req_qid  (                                   ),
        .limit_per_queue_rd_rsp_vld  (1'h0                               ),
        .limit_per_queue_rd_rsp_dat  (8'h0                               ),
        .limit_per_dev_rd_req_vld    (                                   ),
        .limit_per_dev_rd_req_dev_id (                                   ),
        .limit_per_dev_rd_rsp_vld    (1'h0                               ),
        .limit_per_dev_rd_rsp_dat    (8'h0                               ),
        .dfx_err                     (slot_mgmt_rx_dfx_err               ),
        .dfx_status                  (slot_mgmt_rx_dfx_status            ),
        .alloc_slot_req_cnt          (slot_mgmt_rx_alloc_slot_req_cnt    ), 
        .alloc_slot_rsp_cnt          (slot_mgmt_rx_alloc_slot_rsp_cnt    ), 
        .alloc_slot_limit_cnt        (slot_mgmt_rx_alloc_slot_limit_cnt  ), 
        .alloc_slot_ok_cnt           (slot_mgmt_rx_alloc_slot_ok_cnt     ),
        .avail_id_req_cnt            (slot_mgmt_rx_avail_id_req_cnt      ), 
        .avail_id_rsp_cnt            (slot_mgmt_rx_avail_id_rsp_cnt      ), 
        .avail_id_rsp_pkt_cnt        (slot_mgmt_rx_avail_id_rsp_pkt_cnt  ), 
        .avail_id_got_id_cnt         (slot_mgmt_rx_avail_id_got_id_cnt   ), 
        .avail_id_err_cnt            (slot_mgmt_rx_avail_id_err_cnt      ),
        .slot_submit_cnt             (slot_mgmt_rx_slot_submit_cnt       ), 
        .slot_cpl_cnt                (slot_mgmt_rx_slot_cpl_cnt          ),
        .rd_desc_req_cnt             (slot_mgmt_rx_rd_desc_req_cnt       ), 
        .rd_desc_rsp_cnt             (slot_mgmt_rx_rd_desc_rsp_cnt       ), 
        .rd_desc_rsp_pkt_cnt         (slot_mgmt_rx_rd_desc_rsp_pkt_cnt   ), 
        .slot_err_cnt                (slot_mgmt_rx_slot_err_cnt          ),
        .desc_rsp_cnt                (slot_mgmt_rx_desc_rsp_cnt          ), 
        .desc_rsp_pkt_cnt            (slot_mgmt_rx_desc_rsp_pkt_cnt      ),
        .used_slot_num               (rx_used_slot_num                   )
    );

    virtio_desc_engine_slot_mgmt #(
        .TXQ                      (1                        ),
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
    ) net_tx_desc_engine_slot_mgmt (
        .clk                         (clk                                ),
        .rst                         (rst                                ),
        .alloc_slot_req_vld          (net_tx_alloc_slot_req_vld          ),
        .alloc_slot_req_rdy          (net_tx_alloc_slot_req_rdy          ),
        .alloc_slot_req_dev_id       (net_tx_alloc_slot_req_dev_id       ),
        .alloc_slot_req_pkt_id       (net_tx_alloc_slot_req_pkt_id       ),
        .alloc_slot_req_vq           (net_tx_alloc_slot_req_vq           ),
        .alloc_slot_rsp_vld          (net_tx_alloc_slot_rsp_vld          ),
        .alloc_slot_rsp_dat          (net_tx_alloc_slot_rsp_dat          ),
        .alloc_slot_rsp_rdy          (net_tx_alloc_slot_rsp_rdy          ),
        .avail_id_req_vld            (net_tx_avail_id_req_vld            ),
        .avail_id_req_nid            (net_tx_avail_id_req_nid            ),
        .avail_id_req_rdy            (net_tx_avail_id_req_rdy            ),
        .avail_id_req_vq             (net_tx_avail_id_req_vq             ),
        .avail_id_rsp_vld            (net_tx_avail_id_rsp_vld            ),
        .avail_id_rsp_eop            (net_tx_avail_id_rsp_eop            ),
        .avail_id_rsp_rdy            (net_tx_avail_id_rsp_rdy            ),
        .avail_id_rsp_dat            (net_tx_avail_id_rsp_dat            ),
        .slot_submit_vld             (net_tx_slot_submit_vld             ),
        .slot_submit_slot_id         (net_tx_slot_submit_slot_id         ),
        .slot_submit_vq              (net_tx_slot_submit_vq              ),
        .slot_submit_dev_id          (net_tx_slot_submit_dev_id          ),
        .slot_submit_pkt_id          (net_tx_slot_submit_pkt_id          ),
        .slot_submit_ring_id         (net_tx_slot_submit_ring_id         ),
        .slot_submit_avail_idx       (net_tx_slot_submit_avail_idx       ),
        .slot_submit_err             (net_tx_slot_submit_err             ),
        .slot_submit_rdy             (net_tx_slot_submit_rdy             ),
        .slot_cpl_vld                (net_tx_slot_cpl_vld                ),
        .slot_cpl_slot_id            (net_tx_slot_cpl_slot_id            ),
        .slot_cpl_vq                 (net_tx_slot_cpl_vq                 ),
        .slot_cpl_sav                (net_tx_slot_cpl_sav                ),
        .rd_desc_req_vld             (net_tx_rd_desc_req_vld             ),
        .rd_desc_req_slot_id         (net_tx_rd_desc_req_slot_id         ),
        .rd_desc_req_rdy             (net_tx_rd_desc_req_rdy             ),
        .rd_desc_rsp_vld             (net_tx_rd_desc_rsp_vld             ),
        .rd_desc_rsp_sbd             (net_tx_rd_desc_rsp_sbd             ),
        .rd_desc_rsp_sop             (net_tx_rd_desc_rsp_sop             ),
        .rd_desc_rsp_eop             (net_tx_rd_desc_rsp_eop             ),
        .rd_desc_rsp_dat             (net_tx_rd_desc_rsp_dat             ),
        .rd_desc_rsp_rdy             (net_tx_rd_desc_rsp_rdy             ),
        .desc_rsp_vld                (net_tx_desc_rsp_vld                ),
        .desc_rsp_sbd                (net_tx_desc_rsp_sbd                ),
        .desc_rsp_sop                (net_tx_desc_rsp_sop                ),
        .desc_rsp_eop                (net_tx_desc_rsp_eop                ),
        .desc_rsp_dat                (net_tx_desc_rsp_dat                ),
        .desc_rsp_rdy                (net_tx_desc_rsp_rdy                ), 
        .limit_per_queue_rd_req_vld  (net_tx_limit_per_queue_rd_req_vld  ),
        .limit_per_queue_rd_req_qid  (net_tx_limit_per_queue_rd_req_qid  ),
        .limit_per_queue_rd_rsp_vld  (net_tx_limit_per_queue_rd_rsp_vld  ),
        .limit_per_queue_rd_rsp_dat  (net_tx_limit_per_queue_rd_rsp_dat  ),
        .limit_per_dev_rd_req_vld    (net_tx_limit_per_dev_rd_req_vld    ),
        .limit_per_dev_rd_req_dev_id (net_tx_limit_per_dev_rd_req_dev_id ),
        .limit_per_dev_rd_rsp_vld    (net_tx_limit_per_dev_rd_rsp_vld    ),
        .limit_per_dev_rd_rsp_dat    (net_tx_limit_per_dev_rd_rsp_dat    ),
        .dfx_err                     (slot_mgmt_tx_dfx_err               ),
        .dfx_status                  (slot_mgmt_tx_dfx_status            ),
        .alloc_slot_req_cnt          (slot_mgmt_tx_alloc_slot_req_cnt    ), 
        .alloc_slot_rsp_cnt          (slot_mgmt_tx_alloc_slot_rsp_cnt    ), 
        .alloc_slot_limit_cnt        (slot_mgmt_tx_alloc_slot_limit_cnt  ), 
        .alloc_slot_ok_cnt           (slot_mgmt_tx_alloc_slot_ok_cnt     ),
        .avail_id_req_cnt            (slot_mgmt_tx_avail_id_req_cnt      ), 
        .avail_id_rsp_cnt            (slot_mgmt_tx_avail_id_rsp_cnt      ), 
        .avail_id_rsp_pkt_cnt        (slot_mgmt_tx_avail_id_rsp_pkt_cnt  ), 
        .avail_id_got_id_cnt         (slot_mgmt_tx_avail_id_got_id_cnt   ), 
        .avail_id_err_cnt            (slot_mgmt_tx_avail_id_err_cnt      ),
        .slot_submit_cnt             (slot_mgmt_tx_slot_submit_cnt       ), 
        .slot_cpl_cnt                (slot_mgmt_tx_slot_cpl_cnt          ),
        .rd_desc_req_cnt             (slot_mgmt_tx_rd_desc_req_cnt       ), 
        .rd_desc_rsp_cnt             (slot_mgmt_tx_rd_desc_rsp_cnt       ), 
        .rd_desc_rsp_pkt_cnt         (slot_mgmt_tx_rd_desc_rsp_pkt_cnt   ), 
        .slot_err_cnt                (slot_mgmt_tx_slot_err_cnt          ),
        .desc_rsp_cnt                (slot_mgmt_tx_desc_rsp_cnt          ), 
        .desc_rsp_pkt_cnt            (slot_mgmt_tx_desc_rsp_pkt_cnt      ),
        .used_slot_num               (tx_used_slot_num                   )
    );

`ifdef PMON_EN
    localparam PP_IF_NUM = 4      ;
    localparam CNT_WIDTH = 32     ;
    localparam MS_100_CLEAN_CNT = `MS_100_CLEAN_CNT_AT_USER_CLK;
    logic   [PP_IF_NUM*CNT_WIDTH-1:0]   bp_block_cnt        ;
    logic   [PP_IF_NUM*CNT_WIDTH-1:0]   bp_vdata_cnt        ;
    logic   [PP_IF_NUM-1:0]             bp_vld              ;
    logic   [PP_IF_NUM-1:0]             bp_sav              ;
    logic   [PP_IF_NUM-1:0]             hs_vld              ;
    logic   [PP_IF_NUM-1:0]             hs_rdy              ;
    logic   [CNT_WIDTH-1:0]             mon_tick_interval   ;

    assign mon_tick_interval = MS_100_CLEAN_CNT;
    assign bp_vld = {net_tx_dma_desc_rd_rsp_if.vld, net_tx_dma_desc_rd_req_if.vld, net_rx_dma_desc_rd_rsp_if.vld, net_rx_dma_desc_rd_req_if.vld};
    assign bp_sav = {1'b1, net_tx_dma_desc_rd_req_if.sav, 1'b1, net_rx_dma_desc_rd_req_if.sav};
    assign hs_vld = '0;
    assign hs_rdy = '0;

    performance_probe#(
        .PP_IF_NUM          ( PP_IF_NUM ),
        .CNT_WIDTH          ( CNT_WIDTH )
    )u_beq_performance_probe(
        .clk                ( clk                ),
        .rst                ( rst                ),
        .backpressure_vld   ( bp_vld             ),
        .backpressure_sav   ( bp_sav             ),
        .handshake_vld      ( hs_vld             ),
        .handshake_rdy      ( hs_rdy             ),
        .mon_tick_interval  ( mon_tick_interval  ),
        .backpressure_block_cnt    ( bp_block_cnt       ),
        .backpressure_vdata_cnt    ( bp_vdata_cnt       ),
        .handshake_block_cnt       (                    ),
        .handshake_vdata_cnt       (                    )
    );
`endif 

    virtio_desc_engine_dfx #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(64)
    )u_virtio_desc_engine_dfx(
        .clk                                                            (clk),    
        .rst                                                            (rst),  
        .slot_mgmt_tx_dfx_err_slot_mgmt_tx_dfx_err_we                   (|slot_mgmt_tx_dfx_err),             //! Control HW write (active high)
        .slot_mgmt_tx_dfx_err_slot_mgmt_tx_dfx_err_wdata                (slot_mgmt_tx_dfx_err | slot_mgmt_tx_dfx_err_q),          //! HW write data
        .slot_mgmt_tx_dfx_err_slot_mgmt_tx_dfx_err_q                    (slot_mgmt_tx_dfx_err_q),              //! Current field value
        .slot_mgmt_tx_dfx_status_slot_mgmt_tx_dfx_status_wdata          (slot_mgmt_tx_dfx_status),          //! HW write data
        .slot_mgmt_tx_alloc_slot_cnt_slot_mgmt_tx_alloc_slot_cnt_wdata  ({slot_mgmt_tx_alloc_slot_ok_cnt, slot_mgmt_tx_alloc_slot_limit_cnt, slot_mgmt_tx_alloc_slot_rsp_cnt, slot_mgmt_tx_alloc_slot_req_cnt}),          //! HW write data
        .slot_mgmt_tx_avail_id_cnt_slot_mgmt_tx_avail_id_cnt_wdata      ({slot_mgmt_tx_avail_id_err_cnt, slot_mgmt_tx_avail_id_got_id_cnt, slot_mgmt_tx_avail_id_rsp_pkt_cnt, slot_mgmt_tx_avail_id_rsp_cnt, slot_mgmt_tx_avail_id_req_cnt}),          //! HW write data
        .slot_mgmt_tx_slot_cnt_slot_mgmt_tx_slot_cnt_wdata              ({slot_mgmt_tx_slot_err_cnt, slot_mgmt_tx_slot_cpl_cnt, slot_mgmt_tx_slot_submit_cnt}),          //! HW write data
        .slot_mgmt_tx_rd_desc_cnt_slot_mgmt_tx_rd_desc_cnt_wdata        ({slot_mgmt_tx_rd_desc_rsp_pkt_cnt, slot_mgmt_tx_rd_desc_rsp_cnt, slot_mgmt_tx_rd_desc_req_cnt}),          //! HW write data
        .slot_mgmt_tx_desc_cnt_slot_mgmt_tx_desc_cnt_wdata              ({slot_mgmt_tx_desc_rsp_pkt_cnt, slot_mgmt_tx_desc_rsp_cnt}),//! HW write data
        .slot_mgmt_rx_dfx_err_slot_mgmt_rx_dfx_err_we                   (|slot_mgmt_rx_dfx_err),             //! Control HW write (active high)
        .slot_mgmt_rx_dfx_err_slot_mgmt_rx_dfx_err_wdata                (slot_mgmt_rx_dfx_err | slot_mgmt_rx_dfx_err_q),          //! HW write data
        .slot_mgmt_rx_dfx_err_slot_mgmt_rx_dfx_err_q                    (slot_mgmt_rx_dfx_err_q),              //! Current field value
        .slot_mgmt_rx_dfx_status_slot_mgmt_rx_dfx_status_wdata          (slot_mgmt_rx_dfx_status),          //! HW write data
        .slot_mgmt_rx_alloc_slot_cnt_slot_mgmt_rx_alloc_slot_cnt_wdata  ({slot_mgmt_rx_alloc_slot_ok_cnt, slot_mgmt_rx_alloc_slot_limit_cnt, slot_mgmt_rx_alloc_slot_rsp_cnt, slot_mgmt_rx_alloc_slot_req_cnt}),          //! HW write data
        .slot_mgmt_rx_avail_id_cnt_slot_mgmt_rx_avail_id_cnt_wdata      ({slot_mgmt_rx_avail_id_err_cnt, slot_mgmt_rx_avail_id_got_id_cnt, slot_mgmt_rx_avail_id_rsp_pkt_cnt, slot_mgmt_rx_avail_id_rsp_cnt, slot_mgmt_rx_avail_id_req_cnt}),          //! HW write data
        .slot_mgmt_rx_slot_cnt_slot_mgmt_rx_slot_cnt_wdata              ({slot_mgmt_rx_slot_err_cnt, slot_mgmt_rx_slot_cpl_cnt, slot_mgmt_rx_slot_submit_cnt}),          //! HW write data
        .slot_mgmt_rx_rd_desc_cnt_slot_mgmt_rx_rd_desc_cnt_wdata        ({slot_mgmt_rx_rd_desc_rsp_pkt_cnt, slot_mgmt_rx_rd_desc_rsp_cnt, slot_mgmt_rx_rd_desc_req_cnt}),          //! HW write data
        .slot_mgmt_rx_desc_cnt_slot_mgmt_rx_desc_cnt_wdata              ({slot_mgmt_rx_desc_rsp_pkt_cnt, slot_mgmt_rx_desc_rsp_cnt}),//! HW write data
        .core_rx_dfx_err_core_rx_dfx_err_we                             (|core_rx_dfx_err),                //! Control HW write (active high)
        .core_rx_dfx_err_core_rx_dfx_err_wdata                          (core_rx_dfx_err|core_rx_dfx_err_q),          //! HW write data
        .core_rx_dfx_err_core_rx_dfx_err_q                              (core_rx_dfx_err_q),              //! Current field value
        .core_rx_dfx_status_core_rx_dfx_status_wdata                    (core_rx_dfx_status),          //! HW write data
        .core_rx_dma_cnt_core_rx_dma_cnt_wdata                          ({core_rx_dma_rsp_cnt, core_rx_dma_req_cnt}),          //! HW write data
        .core_rx_sch_out_cnt_core_rx_sch_out_cnt_wdata                  ({core_rx_sch_out_desc_rsp_cnt, core_rx_sch_out_wake_up_cnt, core_rx_sch_out_forced_shutdown_cnt}),          //! HW write data
        .core_rx_desc_buf_cnt_core_rx_desc_buf_cnt_wdata                ({core_rx_desc_buf_info_rd_cnt, core_rx_desc_buf_order_wr_cnt}),          //! HW write data
        .core_rx_wake_up_cnt_core_rx_wake_up_cnt_wdata                  (core_rx_wake_up_cnt),          //! HW write data
        .core_tx_dfx_err_core_tx_dfx_err_we                             (|core_tx_dfx_err),                //! Control HW write (active high)
        .core_tx_dfx_err_core_tx_dfx_err_wdata                          (core_tx_dfx_err|core_tx_dfx_err_q),          //! HW write data
        .core_tx_dfx_err_core_tx_dfx_err_q                              (core_tx_dfx_err_q),              //! Current field value
        .core_tx_dfx_status_core_tx_dfx_status_wdata                    (core_tx_dfx_status),          //! HW write data
        .core_tx_dma_cnt_core_tx_dma_cnt_wdata                          ({core_tx_dma_rsp_cnt, core_tx_dma_req_cnt}),          //! HW write data
        .core_tx_sch_out_cnt_core_tx_sch_out_cnt_wdata                  ({core_tx_sch_out_desc_rsp_cnt, core_tx_sch_out_wake_up_cnt, core_tx_sch_out_forced_shutdown_cnt}),          //! HW write data
        .core_tx_desc_buf_cnt_core_tx_desc_buf_cnt_wdata                ({core_tx_desc_buf_info_rd_cnt, core_tx_desc_buf_order_wr_cnt}),          //! HW write data
        .core_tx_wake_up_cnt_core_tx_wake_up_cnt_wdata                  (core_tx_wake_up_cnt),          //! HW write data
`ifdef PMON_EN
        .rx_dma_rd_req_cnt_rx_dma_rd_req_cnt_wdata                      ({bp_block_cnt[31:0], bp_vdata_cnt[31:0]}),          //! HW write data
        .rx_dma_rd_rsp_cnt_rx_dma_rd_rsp_cnt_wdata                      (bp_vdata_cnt[63:32]),          //! HW write data
        .tx_dma_rd_req_cnt_tx_dma_rd_req_cnt_wdata                      ({bp_block_cnt[95:64], bp_vdata_cnt[95:64]}),          //! HW write data
        .tx_dma_rd_rsp_cnt_tx_dma_rd_rsp_cnt_wdata                      (bp_vdata_cnt[127:96]),          //! HW write data
        .used_slot_num_used_slot_num_wdata                              ({tx_used_slot_num, rx_used_slot_num}),          //! HW write data
`endif 
        .csr_if                                                         (dfx_if)
    );
    
 endmodule