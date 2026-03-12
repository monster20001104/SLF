/******************************************************************************
 * 文件名称 : virtio_top.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/09/08
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  09/08     Joe Jiang   初始化版本
 ******************************************************************************/
`include "tlp_adap_dma_if.svh"
`include "virtio_define.svh"
`include "virtio_desc_engine_define.svh"
`include "virtio_rx_buf_define.svh"
`include "virtio_used_define.svh"
 module virtio_top #(
    parameter IRQ_MERGE_UINT_NUM             = 8,
    parameter IRQ_MERGE_UINT_NUM_WIDTH       = $clog2(IRQ_MERGE_UINT_NUM),
    parameter TIME_MAP_WIDTH                 = 2,
    parameter Q_NUM                          = 256,
    parameter Q_WIDTH                        = $clog2(Q_NUM),
    parameter DEV_ID_NUM                     = 1024,
    parameter DEV_ID_WIDTH                   = $clog2(DEV_ID_NUM),
    parameter DATA_WIDTH                     = 256,
    parameter EMPTH_WIDTH                    = $clog2(DATA_WIDTH/8),
    parameter PKT_ID_NUM                     = 1024,
    parameter PKT_ID_WIDTH                   = $clog2(PKT_ID_NUM),
    parameter NET_SLOT_NUM                   = 32,
    parameter NET_SLOT_WIDTH                 = $clog2(NET_SLOT_NUM),
    parameter NET_BUCKET_NUM                 = 128,
    parameter NET_BUCKET_WIDTH               = $clog2(NET_BUCKET_NUM),
    parameter BLK_SLOT_NUM                   = 4,
    parameter BLK_SLOT_WIDTH                 = $clog2(BLK_SLOT_NUM),
    parameter BLK_BUCKET_NUM                 = 4,
    parameter BLK_BUCKET_WIDTH               = $clog2(BLK_BUCKET_NUM),
    parameter LINE_NUM                       = 8,
    parameter LINE_WIDTH                     = $clog2(LINE_NUM),
    parameter UID_NUM                        = 1024,
    parameter UID_WIDTH                      = $clog2(UID_NUM),
    parameter GEN_WIDTH                      = 8,
    parameter CLOCK_FREQ_MHZ                 = 200,
    parameter TIME_STAMP_UNIT_NS             = 500,
    parameter DESC_PER_BUCKET_NUM            = LINE_NUM*DATA_WIDTH/$bits(virtq_desc_t),
    parameter DESC_PER_BUCKET_WIDTH          = $clog2(DESC_PER_BUCKET_NUM),
    parameter NET_DESC_BUF_DEPTH             = (NET_BUCKET_NUM*LINE_NUM),
    parameter BLK_DESC_BUF_DEPTH             = (BLK_BUCKET_NUM*LINE_NUM),
    parameter MAX_CHAIN_SIZE                 = 128,
    parameter MAX_BUCKET_PER_SLOT            = MAX_CHAIN_SIZE/LINE_NUM/(DATA_WIDTH/$bits(virtq_desc_t)),
    parameter MAX_BUCKET_PER_SLOT_WIDTH      = $clog2(MAX_BUCKET_PER_SLOT)
 ) (
    input                                                       clk,
    input logic [6:0]                                           rst,
    tlp_adap_dma_rd_req_if.src                                  idx_eng_dma_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  idx_eng_dma_rd_rsp_if,
    tlp_adap_dma_wr_req_if.src                                  idx_eng_dma_wr_req_if,
    tlp_adap_dma_wr_rsp_if.snk                                  idx_eng_dma_wr_rsp_if,
    tlp_adap_dma_rd_req_if.src                                  avail_ring_dma_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  avail_ring_dma_rd_rsp_if,
    tlp_adap_dma_rd_req_if.src                                  net_tx_desc_dma_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  net_tx_desc_dma_rd_rsp_if,
    tlp_adap_dma_rd_req_if.src                                  net_rx_desc_dma_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  net_rx_desc_dma_rd_rsp_if,
    tlp_adap_dma_rd_req_if.src                                  net_tx_data_dma_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  net_tx_data_dma_rd_rsp_if,
    tlp_adap_dma_wr_req_if.src                                  net_rx_data_dma_wr_req_if,
    tlp_adap_dma_wr_rsp_if.snk                                  net_rx_data_dma_wr_rsp_if,
    tlp_adap_dma_rd_req_if.src                                  blk_desc_dma_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  blk_desc_dma_rd_rsp_if,
    tlp_adap_dma_rd_req_if.src                                  blk_downstream_data_dma_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  blk_downstream_data_dma_rd_rsp_if,
    tlp_adap_dma_wr_req_if.src                                  blk_upstream_data_dma_wr_req_if,
    tlp_adap_dma_wr_rsp_if.snk                                  blk_upstream_data_dma_wr_rsp_if,
    tlp_adap_dma_wr_req_if.src                                  used_dma_wr_req_if,
    tlp_adap_dma_wr_rsp_if.snk                                  used_dma_wr_rsp_if,
    //doorbell
    input logic                                                doorbell_req_vld,
    input virtio_vq_t                                          doorbell_req_vq,
    output  logic                                              doorbell_req_rdy,
    //net
    input                                                       net2tso_sav             ,
    output logic                                                net2tso_vld             ,
    output logic  [DATA_WIDTH-1:0]                              net2tso_data            ,
    output logic  [EMPTH_WIDTH-1:0]                             net2tso_sty             ,
    output logic  [EMPTH_WIDTH-1:0]                             net2tso_mty             ,
    output logic                                                net2tso_sop             ,
    output logic                                                net2tso_eop             ,
    output logic                                                net2tso_err             ,
    output logic  [7:0]                                         net2tso_qid             ,
    output logic  [17:0]                                        net2tso_length          ,
    output logic  [7:0]                                         net2tso_gen             ,
    output logic                                                net2tso_tso_en          ,
    output logic                                                net2tso_csum_en         ,
    beq_txq_bus_if.snk                                          beq2net_if              ,
    //blk           
    beq_txq_bus_if.snk                                          beq2blk_if              ,
    output logic                                                blk_to_beq_cred_fc      ,
    beq_rxq_bus_if.src                                          blk2beq_if              , 
    //qos
    output logic                                              net_rx_qos_query_req_vld,
    input  logic                                              net_rx_qos_query_req_rdy,
    output logic [UID_WIDTH-1:0]                              net_rx_qos_query_req_uid,
    input  logic                                              net_rx_qos_query_rsp_vld,
    input  logic                                              net_rx_qos_query_rsp_ok,
    output logic                                              net_rx_qos_query_rsp_rdy,
    output logic                                              net_rx_qos_update_vld,
    output logic [UID_WIDTH-1:0]                              net_rx_qos_update_uid,
    input  logic                                              net_rx_qos_update_rdy,
    output logic [19:0]                                       net_rx_qos_update_len,
    output logic [7:0]                                        net_rx_qos_update_pkt_num, 

    output logic                                              net_tx_qos_query_req_vld  ,
    output logic [UID_WIDTH-1:0]                              net_tx_qos_query_req_uid  ,
    input  logic                                              net_tx_qos_query_req_rdy  ,
    input  logic                                              net_tx_qos_query_rsp_vld  ,
    input  logic                                              net_tx_qos_query_rsp_ok   ,
    output logic                                              net_tx_qos_query_rsp_rdy  ,
    input  logic                                              net_tx_qos_update_rdy     ,
    output logic                                              net_tx_qos_update_vld     ,
    output logic [UID_WIDTH-1:0]                              net_tx_qos_update_uid     ,
    output logic [19:0]                                       net_tx_qos_update_len     ,
    output logic [9:0]                                        net_tx_qos_update_pkt_num ,  

    input  logic                                              blk_qos_query_req_rdy           ,
    output logic  [UID_WIDTH-1:0]                             blk_qos_query_req_uid           ,
    output logic                                              blk_qos_query_req_vld           ,
    input  logic                                              blk_qos_query_rsp_vld           ,
    input  logic                                              blk_qos_query_rsp_ok            ,
    output logic                                              blk_qos_query_rsp_rdy           ,
    input  logic                                              blk_qos_update_rdy              ,
    output logic                                              blk_qos_update_vld              ,
    output logic [UID_WIDTH-1:0]                              blk_qos_update_uid              ,
    output logic [19:0]                                       blk_qos_update_len              ,
    output logic [7:0]                                        blk_qos_update_pkt_num          ,
    //csr                           
    mlite_if.slave                                            csr_if
);
    
    logic                                                used_dma_write_used_idx_irq_flag_wr_vld;
    virtio_vq_t                                          used_dma_write_used_idx_irq_flag_wr_qid;
    logic                                                used_dma_write_used_idx_irq_flag_wr_dat;
    logic                                                idx_engine_err_info_wr_req_vld                         ;
    virtio_vq_t                                          idx_engine_err_info_wr_req_qid                         ;
    logic [$bits(virtio_err_info_t)-1:0]                 idx_engine_err_info_wr_req_dat                         ;
    logic                                                idx_engine_err_info_wr_req_rdy                         ;
    logic [63:0]                                         idx_engine_ctx_rd_rsp_avail_addr                       ;
    logic [63:0]                                         idx_engine_ctx_rd_rsp_used_addr                        ;
    logic                                                idx_engine_ctx_rd_req_vld                              ;
    virtio_vq_t                                          idx_engine_ctx_rd_req_qid                              ;
    logic                                                idx_engine_ctx_rd_rsp_vld                              ;
    logic [DEV_ID_WIDTH-1:0]                             idx_engine_ctx_rd_rsp_dev_id                           ;
    logic [15:0]                                         idx_engine_ctx_rd_rsp_bdf                              ;
    logic [3:0]                                          idx_engine_ctx_rd_rsp_qdepth                           ;
    logic [15:0]                                         idx_engine_ctx_rd_rsp_avail_idx                        ;
    logic [15:0]                                         idx_engine_ctx_rd_rsp_avail_ui                         ;
    logic                                                idx_engine_ctx_rd_rsp_no_notify                        ;
    logic                                                idx_engine_ctx_rd_rsp_no_change                        ;
    logic [$bits(virtio_qstat_t)-1:0]                    idx_engine_ctx_rd_rsp_ctrl                             ;
    logic                                                idx_engine_ctx_rd_rsp_force_shutdown                   ;
    logic [6:0]                                          idx_engine_ctx_rd_rsp_rd_req_num                       ;
    logic [6:0]                                          idx_engine_ctx_rd_rsp_rd_rsp_num                       ;
    logic                                                idx_engine_ctx_wr_vld                                  ;   
    virtio_vq_t                                          idx_engine_ctx_wr_qid                                  ;
    logic [15:0]                                         idx_engine_ctx_wr_avail_idx                            ;
    logic                                                idx_engine_ctx_wr_no_notify                            ;
    logic [6:0]                                          idx_engine_ctx_wr_dma_req_num                          ;
    logic [6:0]                                          idx_engine_ctx_wr_dma_rsp_num                          ;
    logic                                                avail_ring_dma_ctx_info_rd_req_vld                     ;
    virtio_vq_t                                          avail_ring_dma_ctx_info_rd_req_qid                     ;     
    logic                                                avail_ring_dma_ctx_info_rd_rsp_vld                     ;
    logic                                                avail_ring_dma_ctx_info_rd_rsp_forced_shutdown         ;
    logic [$bits(virtio_qstat_t)-1:0]                    avail_ring_dma_ctx_info_rd_rsp_ctrl                    ;
    logic [15:0]                                         avail_ring_dma_ctx_info_rd_rsp_bdf                     ;
    logic [3:0]                                          avail_ring_dma_ctx_info_rd_rsp_qdepth                  ;
    logic [15:0]                                         avail_ring_dma_ctx_info_rd_rsp_avail_idx               ;
    logic [15:0]                                         avail_ring_dma_ctx_info_rd_rsp_avail_ui                ;
    logic [15:0]                                         avail_ring_dma_ctx_info_rd_rsp_avail_ci                ;         
    logic                                                avail_ring_desc_engine_ctx_info_rd_req_vld             ;
    virtio_vq_t                                          avail_ring_desc_engine_ctx_info_rd_req_qid             ;
    logic                                                avail_ring_desc_engine_ctx_info_rd_rsp_vld             ;
    logic                                                avail_ring_desc_engine_ctx_info_rd_rsp_forced_shutdown ;
    logic [$bits(virtio_qstat_t)-1:0]                    avail_ring_desc_engine_ctx_info_rd_rsp_ctrl            ;
    logic [15:0]                                         avail_ring_desc_engine_ctx_info_rd_rsp_avail_pi        ;
    logic [15:0]                                         avail_ring_desc_engine_ctx_info_rd_rsp_avail_idx       ;
    logic [15:0]                                         avail_ring_desc_engine_ctx_info_rd_rsp_avail_ui        ;
    logic [15:0]                                         avail_ring_desc_engine_ctx_info_rd_rsp_avail_ci        ;
    logic                                                avail_ring_avail_addr_rd_req_vld                       ;
    virtio_vq_t                                          avail_ring_avail_addr_rd_req_qid                       ;
    logic                                                avail_ring_avail_addr_rd_req_rdy                       ;
    logic                                                avail_ring_avail_addr_rd_rsp_vld                       ;
    logic [63:0]                                         avail_ring_avail_addr_rd_rsp_dat                       ;
    logic                                                avail_ring_avail_ci_wr_req_vld                         ;
    logic [15:0]                                         avail_ring_avail_ci_wr_req_dat                         ;
    virtio_vq_t                                          avail_ring_avail_ci_wr_req_qid                         ;
    logic                                                avail_ring_avail_ui_wr_req_vld                         ;
    logic [15:0]                                         avail_ring_avail_ui_wr_req_dat                         ;
    virtio_vq_t                                          avail_ring_avail_ui_wr_req_qid                         ;
    logic                                                avail_ring_avail_pi_wr_req_vld                         ;
    logic [15:0]                                         avail_ring_avail_pi_wr_req_dat                         ;
    virtio_vq_t                                          avail_ring_avail_pi_wr_req_qid                         ;
    logic                                                desc_engine_net_rx_ctx_info_rd_req_vld                 ;
    virtio_vq_t                                          desc_engine_net_rx_ctx_info_rd_req_vq                  ;
    logic                                                desc_engine_net_rx_ctx_info_rd_rsp_vld                 ;
    logic [63:0]                                         desc_engine_net_rx_ctx_info_rd_rsp_desc_tbl_addr       ;
    logic [3:0]                                          desc_engine_net_rx_ctx_info_rd_rsp_qdepth              ;
    logic                                                desc_engine_net_rx_ctx_info_rd_rsp_forced_shutdown     ;
    logic                                                desc_engine_net_rx_ctx_info_rd_rsp_indirct_support     ;
    logic [19:0]                                         desc_engine_net_rx_ctx_info_rd_rsp_max_len             ;
    logic [15:0]                                         desc_engine_net_rx_ctx_info_rd_rsp_bdf                 ;
    logic                                                desc_engine_net_rx_ctx_slot_chain_rd_req_vld           ;
    virtio_vq_t                                          desc_engine_net_rx_ctx_slot_chain_rd_req_vq            ;
    logic                                                desc_engine_net_rx_ctx_slot_chain_rd_rsp_vld           ;
    logic [NET_SLOT_WIDTH-1:0]                           desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot     ;
    logic                                                desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot_vld ;
    logic [NET_SLOT_WIDTH-1:0]                           desc_engine_net_rx_ctx_slot_chain_rd_rsp_tail_slot     ;
    logic                                                desc_engine_net_rx_ctx_slot_chain_wr_vld               ;
    virtio_vq_t                                          desc_engine_net_rx_ctx_slot_chain_wr_vq                ;
    logic [NET_SLOT_WIDTH-1:0]                           desc_engine_net_rx_ctx_slot_chain_wr_head_slot         ;
    logic                                                desc_engine_net_rx_ctx_slot_chain_wr_head_slot_vld     ;
    logic [NET_SLOT_WIDTH-1:0]                           desc_engine_net_rx_ctx_slot_chain_wr_tail_slot         ;
    logic                                                desc_engine_net_tx_ctx_info_rd_req_vld                 ;
    virtio_vq_t                                          desc_engine_net_tx_ctx_info_rd_req_vq                  ;
    logic                                                desc_engine_net_tx_ctx_info_rd_rsp_vld                 ;
    logic [63:0]                                         desc_engine_net_tx_ctx_info_rd_rsp_desc_tbl_addr       ;
    logic [3:0]                                          desc_engine_net_tx_ctx_info_rd_rsp_qdepth              ;
    logic                                                desc_engine_net_tx_ctx_info_rd_rsp_forced_shutdown     ;
    logic                                                desc_engine_net_tx_ctx_info_rd_rsp_indirct_support     ;
    logic [19:0]                                         desc_engine_net_tx_ctx_info_rd_rsp_max_len             ;
    logic [15:0]                                         desc_engine_net_tx_ctx_info_rd_rsp_bdf                 ;
    logic                                                desc_engine_net_tx_ctx_slot_chain_rd_req_vld           ;
    virtio_vq_t                                          desc_engine_net_tx_ctx_slot_chain_rd_req_vq            ;
    logic                                                desc_engine_net_tx_ctx_slot_chain_rd_rsp_vld           ;
    logic [NET_SLOT_WIDTH-1:0]                           desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot     ;
    logic                                                desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot_vld ;
    logic [NET_SLOT_WIDTH-1:0]                           desc_engine_net_tx_ctx_slot_chain_rd_rsp_tail_slot     ;
    logic                                                desc_engine_net_tx_ctx_slot_chain_wr_vld               ;
    virtio_vq_t                                          desc_engine_net_tx_ctx_slot_chain_wr_vq                ;
    logic [NET_SLOT_WIDTH-1:0]                           desc_engine_net_tx_ctx_slot_chain_wr_head_slot         ;
    logic                                                desc_engine_net_tx_ctx_slot_chain_wr_head_slot_vld     ;
    logic [NET_SLOT_WIDTH-1:0]                           desc_engine_net_tx_ctx_slot_chain_wr_tail_slot         ;
    logic                                                desc_engine_net_tx_limit_per_queue_rd_req_vld          ;
    logic [Q_WIDTH-1:0]                                  desc_engine_net_tx_limit_per_queue_rd_req_qid          ;
    logic                                                desc_engine_net_tx_limit_per_queue_rd_rsp_vld          ;
    logic [7:0]                                          desc_engine_net_tx_limit_per_queue_rd_rsp_dat          ;
    logic                                                desc_engine_net_tx_limit_per_dev_rd_req_vld            ;
    logic [DEV_ID_WIDTH-1:0]                             desc_engine_net_tx_limit_per_dev_rd_req_dev_id         ;
    logic                                                desc_engine_net_tx_limit_per_dev_rd_rsp_vld            ;
    logic [7:0]                                          desc_engine_net_tx_limit_per_dev_rd_rsp_dat            ;
    logic                                                blk_desc_engine_resummer_rd_req_vld                    ;
    logic [Q_WIDTH-1:0]                                  blk_desc_engine_resummer_rd_req_qid                    ;
    logic                                                blk_desc_engine_resummer_rd_rsp_vld                    ;
    logic                                                blk_desc_engine_resummer_rd_rsp_dat                    ;                   
    logic                                                blk_desc_engine_resumer_wr_vld                         ;
    logic [Q_WIDTH-1:0]                                  blk_desc_engine_resumer_wr_qid                         ;
    logic                                                blk_desc_engine_resumer_wr_dat                         ;                    
    logic                                                blk_desc_engine_global_info_rd_req_vld                 ;
    logic [Q_WIDTH-1:0]                                  blk_desc_engine_global_info_rd_req_qid                 ;                    
    logic                                                blk_desc_engine_global_info_rd_rsp_vld                 ;
    logic [15:0]                                         blk_desc_engine_global_info_rd_rsp_bdf                 ;
    logic                                                blk_desc_engine_global_info_rd_rsp_forced_shutdown     ;
    logic [63:0]                                         blk_desc_engine_global_info_rd_rsp_desc_tbl_addr       ;
    logic [3:0]                                          blk_desc_engine_global_info_rd_rsp_qdepth              ;
    logic                                                blk_desc_engine_global_info_rd_rsp_indirct_support     ;
    logic [19:0]                                         blk_desc_engine_global_info_rd_rsp_segment_size_blk    ;                 
    logic                                                blk_desc_engine_local_info_rd_req_vld                  ;
    logic [Q_WIDTH-1:0]                                  blk_desc_engine_local_info_rd_req_qid                  ;                  
    logic                                                blk_desc_engine_local_info_rd_rsp_vld                  ;
    logic [63:0]                                         blk_desc_engine_local_info_rd_rsp_desc_tbl_addr        ;
    logic [31:0]                                         blk_desc_engine_local_info_rd_rsp_desc_tbl_size        ;
    logic [15:0]                                         blk_desc_engine_local_info_rd_rsp_desc_tbl_next        ;
    logic [15:0]                                         blk_desc_engine_local_info_rd_rsp_desc_tbl_id          ;
    logic [19:0]                                         blk_desc_engine_local_info_rd_rsp_qid_desc_cnt         ;
    logic [20:0]                                         blk_desc_engine_local_info_rd_rsp_qid_data_len         ;
    logic                                                blk_desc_engine_local_info_rd_rsp_qid_is_indirct       ;                   
    logic                                                blk_desc_engine_local_info_wr_vld                      ;
    logic [Q_WIDTH-1:0]                                  blk_desc_engine_local_info_wr_qid                      ;
    logic [63:0]                                         blk_desc_engine_local_info_wr_desc_tbl_addr            ;
    logic [31:0]                                         blk_desc_engine_local_info_wr_desc_tbl_size            ;
    logic [15:0]                                         blk_desc_engine_local_info_wr_desc_tbl_next            ;
    logic [15:0]                                         blk_desc_engine_local_info_wr_desc_tbl_id              ;
    logic [19:0]                                         blk_desc_engine_local_info_wr_qid_desc_cnt             ;
    logic [20:0]                                         blk_desc_engine_local_info_wr_qid_data_len             ;
    logic                                                blk_desc_engine_local_info_wr_qid_is_indirct           ;
    logic                                                blk_down_stream_ptr_rd_req_vld                         ;
    logic [Q_WIDTH-1:0]                                  blk_down_stream_ptr_rd_req_qid                         ;
    logic                                                blk_down_stream_ptr_rd_rsp_vld                         ;
    logic [15:0]                                         blk_down_stream_ptr_rd_rsp_dat                         ;
    logic                                                blk_down_stream_ptr_wr_req_vld                         ;
    logic [Q_WIDTH-1:0]                                  blk_down_stream_ptr_wr_req_qid                         ;
    logic [15:0]                                         blk_down_stream_ptr_wr_req_dat                         ;
    logic                                                blk_down_stream_qos_info_rd_req_vld                    ;
    logic [Q_WIDTH-1:0]                                  blk_down_stream_qos_info_rd_req_qid                    ;
    logic                                                blk_down_stream_qos_info_rd_rsp_vld                    ;
    logic                                                blk_down_stream_qos_info_rd_rsp_qos_enable             ;
    logic [UID_WIDTH-1:0]                                blk_down_stream_qos_info_rd_rsp_qos_unit               ;
    logic                                                blk_down_stream_dma_info_rd_req_vld                    ;
    logic [Q_WIDTH-1:0]                                  blk_down_stream_dma_info_rd_req_qid                    ;
    logic                                                blk_down_stream_dma_info_rd_rsp_vld                    ;
    logic [15:0]                                         blk_down_stream_dma_info_rd_rsp_bdf                    ;
    logic                                                blk_down_stream_dma_info_rd_rsp_forcedown              ;
    logic [7:0]                                          blk_down_stream_dma_info_rd_rsp_generation             ;
    logic                                                blk_upstream_ctx_req_vld                               ;
    logic [Q_WIDTH-1:0]                                  blk_upstream_ctx_req_qid                               ;
    logic                                                blk_upstream_ctx_rsp_vld                               ;
    logic                                                blk_upstream_ctx_rsp_forced_shutdown                   ;
    logic [$bits(virtio_qstat_t)-1:0]                    blk_upstream_ctx_rsp_q_status                          ;
    logic [7:0]                                          blk_upstream_ctx_rsp_generation                        ;        
    logic [DEV_ID_WIDTH-1:0]                             blk_upstream_ctx_rsp_dev_id                            ;
    logic [15:0]                                         blk_upstream_ctx_rsp_bdf                               ; 
    logic                                                blk_upstream_ptr_rd_req_vld                            ;
    logic [Q_WIDTH-1:0]                                  blk_upstream_ptr_rd_req_qid                            ;
    logic                                                blk_upstream_ptr_rd_rsp_vld                            ;
    logic [15:0]                                         blk_upstream_ptr_rd_rsp_dat                            ;
    logic                                                blk_upstream_ptr_wr_req_vld                            ;
    logic [Q_WIDTH-1:0]                                  blk_upstream_ptr_wr_req_qid                            ;
    logic [15:0]                                         blk_upstream_ptr_wr_req_dat                            ;  
    virtio_vq_t                                          blk_upstream_mon_send_io_qid                           ;
    logic                                                blk_upstream_mon_send_io                               ;
    virtio_vq_t                                          blk_upstream_mon_drop_qid                              ;
    logic                                                blk_upstream_mon_drop_a_pkt                            ;
    logic                                                blk_upstream_mon_tran_a_pkt                            ;
    logic                                                net_tx_slot_ctrl_ctx_info_rd_req_vld                   ;
    virtio_vq_t                                          net_tx_slot_ctrl_ctx_info_rd_req_qid                   ;       
    logic                                                net_tx_slot_ctrl_ctx_info_rd_rsp_vld                   ;
    logic [Q_WIDTH+1:0]                                  net_tx_slot_ctrl_ctx_info_rd_rsp_qos_unit              ;
    logic                                                net_tx_slot_ctrl_ctx_info_rd_rsp_qos_enable            ;
    logic [DEV_ID_WIDTH-1:0]                             net_tx_slot_ctrl_ctx_info_rd_rsp_dev_id                ;
    logic                                                net_tx_rd_data_ctx_info_rd_req_vld                     ;
    virtio_vq_t                                          net_tx_rd_data_ctx_info_rd_req_vq                      ;          
    logic                                                net_tx_rd_data_ctx_info_rd_rsp_vld                     ;
    logic [15:0]                                         net_tx_rd_data_ctx_info_rd_rsp_bdf                     ;
    logic                                                net_tx_rd_data_ctx_info_rd_rsp_forced_shutdown         ;
    logic                                                net_tx_rd_data_ctx_info_rd_rsp_qos_enable              ;
    logic [Q_WIDTH+1:0]                                  net_tx_rd_data_ctx_info_rd_rsp_qos_unit                ;
    logic                                                net_tx_rd_data_ctx_info_rd_rsp_tso_en                  ;
    logic                                                net_tx_rd_data_ctx_info_rd_rsp_csum_en                 ;
    logic [7:0]                                          net_tx_rd_data_ctx_info_rd_rsp_generation              ;
    logic                                                net_rx_slot_ctrl_dev_id_rd_req_vld                     ;
    virtio_vq_t                                          net_rx_slot_ctrl_dev_id_rd_req_qid                     ;         
    logic                                                net_rx_slot_ctrl_dev_id_rd_rsp_vld                     ;
    logic [DEV_ID_WIDTH-1:0]                             net_rx_slot_ctrl_dev_id_rd_rsp_dat                     ;
    logic                                                net_rx_wr_data_ctx_rd_req_vld                          ;
    virtio_vq_t                                          net_rx_wr_data_ctx_rd_req_qid                          ;
    logic                                                net_rx_wr_data_ctx_rd_rsp_vld                          ;
    logic [15:0]                                         net_rx_wr_data_ctx_rd_rsp_bdf                          ;
    logic                                                net_rx_wr_data_ctx_rd_rsp_forced_shutdown              ;
    logic                                                net_rx_buf_drop_info_rd_req_vld                        ;
    logic [Q_WIDTH-1:0]                                  net_rx_buf_drop_info_rd_req_qid                        ;
    logic                                                net_rx_buf_drop_info_rd_rsp_vld                        ;
    logic [GEN_WIDTH-1:0]                                net_rx_buf_drop_info_rd_rsp_generation                 ;
    logic [UID_WIDTH-1:0]                                net_rx_buf_drop_info_rd_rsp_qos_unit                   ;
    logic                                                net_rx_buf_drop_info_rd_rsp_qos_enable                 ;
    logic                                                net_rx_buf_req_idx_per_queue_rd_req_vld                ;
    logic [Q_WIDTH-1:0]                                  net_rx_buf_req_idx_per_queue_rd_req_qid                ;
    logic                                                net_rx_buf_req_idx_per_queue_rd_rsp_vld                ;
    logic [DEV_ID_WIDTH-1:0]                             net_rx_buf_req_idx_per_queue_rd_rsp_dev_id             ;
    logic [7:0]                                          net_rx_buf_req_idx_per_queue_rd_rsp_limit              ;
    logic                                                net_rx_buf_req_idx_per_dev_rd_req_vld                  ;
    logic [DEV_ID_WIDTH-1:0]                             net_rx_buf_req_idx_per_dev_rd_req_dev_id               ;
    logic                                                net_rx_buf_req_idx_per_dev_rd_rsp_vld                  ;
    logic [7:0]                                          net_rx_buf_req_idx_per_dev_rd_rsp_limit                ;
    logic                                                used_ring_irq_rd_req_vld                               ;
    virtio_vq_t                                          used_ring_irq_rd_req_qid                               ;
    logic                                                used_ring_irq_rd_rsp_vld                               ;
    logic                                                used_ring_irq_rd_rsp_forced_shutdown                   ;
    logic [63:0]                                         used_ring_irq_rd_rsp_msix_addr                         ;
    logic [31:0]                                         used_ring_irq_rd_rsp_msix_data                         ;
    logic [15:0]                                         used_ring_irq_rd_rsp_bdf                               ;
    logic [DEV_ID_WIDTH-1:0]                             used_ring_irq_rd_rsp_dev_id                            ;
    logic                                                used_ring_irq_rd_rsp_msix_mask                         ;
    logic                                                used_ring_irq_rd_rsp_msix_pending                      ;
    logic [63:0]                                         used_ring_irq_rd_rsp_used_ring_addr                    ;
    logic [3:0]                                          used_ring_irq_rd_rsp_qdepth                            ;
    logic                                                used_ring_irq_rd_rsp_msix_enable                       ;
    logic [$bits(virtio_qstat_t)-1:0]                    used_ring_irq_rd_rsp_q_status                          ;
    logic                                                used_ring_irq_rd_rsp_err_fatal                         ;
    logic                                                used_err_fatal_wr_vld                                  ;
    virtio_vq_t                                          used_err_fatal_wr_qid                                  ;
    logic                                                used_err_fatal_wr_dat                                  ;
    logic                                                used_elem_ptr_rd_req_vld                               ;
    virtio_vq_t                                          used_elem_ptr_rd_req_qid                               ;
    logic                                                used_elem_ptr_rd_rsp_vld                               ;
    logic [$bits(virtio_used_elem_ptr_info_t)-1:0]       used_elem_ptr_rd_rsp_dat                               ;
    logic                                                used_elem_ptr_wr_vld                                   ;
    virtio_vq_t                                          used_elem_ptr_wr_qid                                   ;
    logic [$bits(virtio_used_elem_ptr_info_t)-1:0]       used_elem_ptr_wr_dat                                   ;
    logic                                                used_idx_wr_vld                                        ;
    virtio_vq_t                                          used_idx_wr_qid                                        ;
    logic [15:0]                                         used_idx_wr_dat                                        ;
    logic                                                used_msix_tbl_wr_vld                                   ;
    virtio_vq_t                                          used_msix_tbl_wr_qid                                   ;
    logic                                                used_msix_tbl_wr_mask                                  ;
    logic                                                used_msix_tbl_wr_pending                               ;
    logic                                                msix_aggregation_time_rd_req_vld_net_tx                ;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_time_rd_req_qid_net_tx                ;      
    logic                                                msix_aggregation_time_rd_rsp_vld_net_tx                ;
    logic [IRQ_MERGE_UINT_NUM*3-1:0]                     msix_aggregation_time_rd_rsp_dat_net_tx                ;  
    logic                                                msix_aggregation_threshold_rd_req_vld_net_tx           ;
    logic [Q_WIDTH-1:0]                                  msix_aggregation_threshold_rd_req_qid_net_tx           ;
    logic                                                msix_aggregation_threshold_rd_rsp_vld_net_tx           ;
    logic [6:0]                                          msix_aggregation_threshold_rd_rsp_dat_net_tx           ;         
    logic                                                msix_aggregation_info_rd_req_vld_net_tx                ;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_info_rd_req_qid_net_tx                ;
    logic                                                msix_aggregation_info_rd_rsp_vld_net_tx                ;
    logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0]    msix_aggregation_info_rd_rsp_dat_net_tx                ;      
    logic                                                msix_aggregation_info_wr_vld_net_tx                    ;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_info_wr_qid_net_tx                    ;
    logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0]    msix_aggregation_info_wr_dat_net_tx                    ;
    logic                                                msix_aggregation_time_rd_req_vld_net_rx                ;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_time_rd_req_qid_net_rx                ;        
    logic                                                msix_aggregation_time_rd_rsp_vld_net_rx                ;
    logic [IRQ_MERGE_UINT_NUM*3-1:0]                     msix_aggregation_time_rd_rsp_dat_net_rx                ;    
    logic                                                msix_aggregation_threshold_rd_req_vld_net_rx           ;
    logic [Q_WIDTH-1:0]                                  msix_aggregation_threshold_rd_req_qid_net_rx           ;
    logic                                                msix_aggregation_threshold_rd_rsp_vld_net_rx           ;
    logic [6:0]                                          msix_aggregation_threshold_rd_rsp_dat_net_rx           ;         
    logic                                                msix_aggregation_info_rd_req_vld_net_rx                ;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_info_rd_req_qid_net_rx                ;
    logic                                                msix_aggregation_info_rd_rsp_vld_net_rx                ;
    logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0]    msix_aggregation_info_rd_rsp_dat_net_rx                ;      
    logic                                                msix_aggregation_info_wr_vld_net_rx                    ;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_info_wr_qid_net_rx                    ;
    logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0]    msix_aggregation_info_wr_dat_net_rx                    ;
    logic                                                used_err_info_wr_vld                                   ;
    virtio_vq_t                                          used_err_info_wr_qid                                   ;
    logic [$bits(virtio_err_info_t)-1:0]                 used_err_info_wr_dat                                   ;
    logic                                                used_err_info_wr_rdy                                   ;
    logic                                                used_set_mask_req_vld                                  ;
    virtio_vq_t                                          used_set_mask_req_qid                                  ;
    logic                                                used_set_mask_req_dat                                  ;
    logic                                                used_set_mask_req_rdy                                  ;
    logic                                                used_mon_send_a_irq                                    ;
    virtio_vq_t                                          used_mon_send_irq_vq                                   ;
    logic                                                soc_notify_req_vld                                     ;
    virtio_vq_t                                          soc_notify_req_qid                                     ;
    logic                                                soc_notify_req_rdy                                     ;
    logic                                                notify_req_vld                                         ;
    virtio_vq_t                                          notify_req_qid                                         ;
    logic                                                notify_req_rdy                                         ;
    logic                                                idx_eng_notify_req_vld                                 ;
    logic                                                idx_eng_notify_req_rdy                                 ;
    virtio_vq_t                                          idx_eng_notify_req_vq                                  ;
    logic                                                idx_eng_notify_rsp_vld                                 ;
    logic                                                idx_eng_notify_rsp_rdy                                 ;
    logic                                                idx_eng_notify_rsp_cold                                ;
    logic                                                idx_eng_notify_rsp_done                                ;
    virtio_vq_t                                          idx_eng_notify_rsp_vq                                  ;
    logic                                                avail_ring_notify_vld                                  ;
    virtio_vq_t                                          avail_ring_notify_vq                                   ;
    logic                                                avail_ring_notify_rdy                                  ;
    logic                                                avail_ring_notify_req_vld                                 ;
    logic                                                avail_ring_notify_req_rdy                                 ;
    virtio_vq_t                                          avail_ring_notify_req_vq                                  ;
    logic                                                avail_ring_notify_rsp_vld                                 ;
    logic                                                avail_ring_notify_rsp_rdy                                 ;
    logic                                                avail_ring_notify_rsp_cold                                ;
    logic                                                avail_ring_notify_rsp_done                                ;
    virtio_vq_t                                          avail_ring_notify_rsp_vq                                  ;
    logic                                                blk_ds_err_info_wr_rdy;
    logic                                                blk_ds_err_info_wr_vld;
    virtio_vq_t                                          blk_ds_err_info_wr_qid;
    virtio_err_info_t                                    blk_ds_err_info_wr_dat;

    logic                       nettx_notify_vld;
    logic   [Q_WIDTH-1:0]       nettx_notify_qid;
    logic                       nettx_notify_rdy;
    logic                       nettx_notify_req_vld ;
    logic                       nettx_notify_req_rdy ;
    logic   [Q_WIDTH-1:0]       nettx_notify_req_qid ;
    logic                       nettx_notify_rsp_vld ;
    logic                       nettx_notify_rsp_rdy ;
    logic   [Q_WIDTH-1:0]       nettx_notify_rsp_qid ;
    logic                       nettx_notify_rsp_done;
    logic                       nettx_notify_rsp_cold;

    logic                       blk_notify_vld;
    logic   [Q_WIDTH-1:0]       blk_notify_qid;
    logic                       blk_notify_rdy;
    logic                       blk_notify_req_vld ;
    logic                       blk_notify_req_rdy ;
    logic   [Q_WIDTH-1:0]       blk_notify_req_qid ;
    logic                       blk_notify_rsp_vld ;
    logic                       blk_notify_rsp_rdy ;
    logic   [Q_WIDTH-1:0]       blk_notify_rsp_qid ;
    logic                       blk_notify_rsp_done;
    logic                       blk_notify_rsp_cold;

    logic                       netrx_avail_id_req_vld ;
    virtio_vq_t                 netrx_avail_id_req_vq  ;
    logic   [3:0]               netrx_avail_id_req_nid ;
    logic                       netrx_avail_id_req_rdy ;
    logic                       netrx_avail_id_rsp_vld ;
    virtio_avail_id_rsp_dat_t   netrx_avail_id_rsp_dat ;
    logic                       netrx_avail_id_rsp_eop ;
    logic                       netrx_avail_id_rsp_rdy ;
    logic                       nettx_avail_id_req_vld ;
    virtio_vq_t                 nettx_avail_id_req_vq  ;
    logic   [3:0]               nettx_avail_id_req_nid ;
    logic                       nettx_avail_id_req_rdy ;
    logic                       nettx_avail_id_rsp_vld ;
    virtio_avail_id_rsp_dat_t   nettx_avail_id_rsp_dat ;
    logic                       nettx_avail_id_rsp_eop ;
    logic                       nettx_avail_id_rsp_rdy ;
    logic                       blk_avail_id_req_vld   ;
    logic   [Q_WIDTH-1:0]       blk_avail_id_req_vq   ;
    logic                       blk_avail_id_req_rdy   ;
    logic                       blk_avail_id_rsp_vld   ;
    virtio_avail_id_rsp_dat_t   blk_avail_id_rsp_dat   ;
    logic                       blk_avail_id_rsp_eop   ;
    logic                       blk_avail_id_rsp_rdy   ;

    logic                                                net_rx_alloc_slot_req_vld      ;
    logic                                                net_rx_alloc_slot_req_rdy      ;
    logic [9:0]                                          net_rx_alloc_slot_req_dev_id   ;
    logic [PKT_ID_WIDTH-1:0]                             net_rx_alloc_slot_req_pkt_id   ;
    virtio_vq_t                                          net_rx_alloc_slot_req_vq       ;
    logic                                                net_rx_alloc_slot_rsp_vld      ;
    virtio_desc_eng_slot_rsp_t                           net_rx_alloc_slot_rsp_dat      ;
    logic                                                net_rx_alloc_slot_rsp_rdy      ;
    logic                                                net_tx_alloc_slot_req_vld      ;
    logic                                                net_tx_alloc_slot_req_rdy      ;
    logic [9:0]                                          net_tx_alloc_slot_req_dev_id   ;
    virtio_vq_t                                          net_tx_alloc_slot_req_vq       ;
    logic                                                net_tx_alloc_slot_rsp_vld      ;
    virtio_desc_eng_slot_rsp_t                           net_tx_alloc_slot_rsp_dat      ;
    logic                                                net_tx_alloc_slot_rsp_rdy      ;
    logic                                                net_rx_desc_rsp_vld;
    virtio_desc_eng_desc_rsp_sbd_t                       net_rx_desc_rsp_sbd;
    logic                                                net_rx_desc_rsp_sop;
    logic                                                net_rx_desc_rsp_eop;
    virtq_desc_t                                         net_rx_desc_rsp_dat;
    logic                                                net_rx_desc_rsp_rdy; 
    logic                                                net_tx_desc_rsp_vld;
    virtio_desc_eng_desc_rsp_sbd_t                       net_tx_desc_rsp_sbd;
    logic                                                net_tx_desc_rsp_sop;
    logic                                                net_tx_desc_rsp_eop;
    virtq_desc_t                                         net_tx_desc_rsp_dat;
    logic                                                net_tx_desc_rsp_rdy; 

    logic                           netrx_buf_info_vld;
    virtio_rx_buf_req_info_t        netrx_buf_info_dat;
    logic                           netrx_buf_info_rdy;

    logic                                              netrx_buf_rd_data_req_vld;
    logic                                              netrx_buf_rd_data_req_rdy;
    virtio_rx_buf_rd_data_req_t                        netrx_buf_rd_data_req_dat;
    logic                           [DATA_WIDTH-1:0]   netrx_buf_rd_data_rsp_dat;
    logic                           [EMPTH_WIDTH-1:0]  netrx_buf_rd_data_rsp_sty;
    logic                           [EMPTH_WIDTH-1:0]  netrx_buf_rd_data_rsp_mty;
    logic                                              netrx_buf_rd_data_rsp_sop;
    logic                                              netrx_buf_rd_data_rsp_eop;
    virtio_rx_buf_rd_data_rsp_sbd_t                    netrx_buf_rd_data_rsp_sbd;
    logic                                              netrx_buf_rd_data_rsp_vld;
    logic                                              netrx_buf_rd_data_rsp_rdy;

    logic                           net_rx_used_info_vld;
    virtio_used_info_t              net_rx_used_info_dat;
    logic                           net_rx_used_info_rdy;
    logic                           net_tx_used_info_vld;
    virtio_used_info_t              net_tx_used_info_dat;
    logic                           net_tx_used_info_rdy;
    logic                           blk_used_info_vld   ;
    virtio_used_info_t              blk_used_info_dat   ;
    logic                           blk_used_info_rdy   ;
     
    logic                           wr_used_info_vld;             
    virtio_used_info_t              wr_used_info_dat;             
    logic                           wr_used_info_rdy;

    logic                          blk_alloc_slot_req_vld   ;
    logic                          blk_alloc_slot_req_rdy   ;
    virtio_vq_t                    blk_alloc_slot_req_vq    ;
    logic                          blk_alloc_slot_rsp_vld   ;
    logic                          blk_alloc_slot_rsp_rdy   ;
    virtio_desc_eng_slot_rsp_t     blk_alloc_slot_rsp_dat   ;

    logic                          blk_desc_rsp_vld;
    logic                          blk_desc_rsp_rdy;
    logic                          blk_desc_rsp_sop;
    logic                          blk_desc_rsp_eop;
    virtio_desc_eng_desc_rsp_sbd_t blk_desc_rsp_sbd;
    virtq_desc_t                   blk_desc_rsp_dat;

    logic                          blk_down_stream_chain_fst_seg_rd_req_vld;
    logic [Q_WIDTH-1:0]            blk_down_stream_chain_fst_seg_rd_req_qid;
    logic                          blk_down_stream_chain_fst_seg_rd_rsp_vld;
    logic                          blk_down_stream_chain_fst_seg_rd_rsp_dat;
    logic                          blk_down_stream_chain_fst_seg_wr_vld    ;
    logic [Q_WIDTH-1:0]            blk_down_stream_chain_fst_seg_wr_qid    ;
    logic                          blk_down_stream_chain_fst_seg_wr_dat    ;


    logic                          vq_pending_chk_req_vld;
    virtio_vq_t                    vq_pending_chk_req_vq;
    logic                          vq_pending_chk_rsp_vld;
    logic                          vq_pending_chk_rsp_busy;

    logic [12:0]  m_br_enable;
    logic [22:0] chn_addr;
    mlite_if #(.ADDR_WIDTH(22), .DATA_WIDTH(64)) m_br_if[13]();

    virtio_ctx #(
        .Q_NUM                    (Q_NUM              ),
        .Q_WIDTH                  (Q_WIDTH            ),
        .SLOT_NUM                 (NET_SLOT_NUM       ),
        .SLOT_WIDTH               (NET_SLOT_WIDTH     ),
        .DEV_ID_NUM               (DEV_ID_NUM         ),
        .DEV_ID_WIDTH             (DEV_ID_WIDTH       ),
        .QOS_QUERY_UID_WIDTH      (UID_WIDTH          ),
        .UID_DEPTH                (UID_NUM            ),
        .UID_WIDTH                (UID_WIDTH          ),
        .GEN_WIDTH                (GEN_WIDTH          ),
        .IRQ_MERGE_UINT_NUM       (IRQ_MERGE_UINT_NUM ),
        .IRQ_MERGE_UINT_NUM_WIDTH (IRQ_MERGE_UINT_NUM_WIDTH          ),
        .TIME_MAP_WIDTH           (TIME_MAP_WIDTH     )
    ) u_virtio_ctx (
        .clk                                                    (clk                                                    ),
        .rst                                                    (rst[0]                                                 ),
        .idx_engine_err_info_wr_req_vld                         (idx_engine_err_info_wr_req_vld                         ),
        .idx_engine_err_info_wr_req_qid                         (idx_engine_err_info_wr_req_qid                         ),
        .idx_engine_err_info_wr_req_dat                         (idx_engine_err_info_wr_req_dat                         ), 
        .idx_engine_err_info_wr_req_rdy                         (idx_engine_err_info_wr_req_rdy                         ), 
        .idx_engine_ctx_rd_req_vld                              (idx_engine_ctx_rd_req_vld                              ),
        .idx_engine_ctx_rd_req_qid                              (idx_engine_ctx_rd_req_qid                              ),
        .idx_engine_ctx_rd_rsp_vld                              (idx_engine_ctx_rd_rsp_vld                              ),
        .idx_engine_ctx_rd_rsp_dev_id                           (idx_engine_ctx_rd_rsp_dev_id                           ),
        .idx_engine_ctx_rd_rsp_bdf                              (idx_engine_ctx_rd_rsp_bdf                              ),
        .idx_engine_ctx_rd_rsp_avail_addr                       (idx_engine_ctx_rd_rsp_avail_addr                       ),
        .idx_engine_ctx_rd_rsp_used_addr                        (idx_engine_ctx_rd_rsp_used_addr                        ),
        .idx_engine_ctx_rd_rsp_qdepth                           (idx_engine_ctx_rd_rsp_qdepth                           ),
        .idx_engine_ctx_rd_rsp_ctrl                             (idx_engine_ctx_rd_rsp_ctrl                             ),
        .idx_engine_ctx_rd_rsp_force_shutdown                   (idx_engine_ctx_rd_rsp_force_shutdown                   ),
        .idx_engine_ctx_rd_rsp_avail_idx                        (idx_engine_ctx_rd_rsp_avail_idx                        ),
        .idx_engine_ctx_rd_rsp_avail_ui                         (idx_engine_ctx_rd_rsp_avail_ui                         ),
        .idx_engine_ctx_rd_rsp_no_notify                        (idx_engine_ctx_rd_rsp_no_notify                        ),
        .idx_engine_ctx_rd_rsp_no_change                        (idx_engine_ctx_rd_rsp_no_change                        ),
        .idx_engine_ctx_rd_rsp_dma_req_num                      (idx_engine_ctx_rd_rsp_rd_req_num                       ),
        .idx_engine_ctx_rd_rsp_dma_rsp_num                      (idx_engine_ctx_rd_rsp_rd_rsp_num                       ),
        .idx_engine_ctx_wr_vld                                  (idx_engine_ctx_wr_vld                                  ),
        .idx_engine_ctx_wr_qid                                  (idx_engine_ctx_wr_qid                                  ),
        .idx_engine_ctx_wr_avail_idx                            (idx_engine_ctx_wr_avail_idx                            ),
        .idx_engine_ctx_wr_no_notify                            (idx_engine_ctx_wr_no_notify                            ),
        .idx_engine_ctx_wr_dma_req_num                          (idx_engine_ctx_wr_dma_req_num                          ),
        .idx_engine_ctx_wr_dma_rsp_num                          (idx_engine_ctx_wr_dma_rsp_num                          ),
        .avail_ring_dma_ctx_info_rd_req_vld                     (avail_ring_dma_ctx_info_rd_req_vld                     ),
        .avail_ring_dma_ctx_info_rd_req_qid                     (avail_ring_dma_ctx_info_rd_req_qid                     ),    
        .avail_ring_dma_ctx_info_rd_rsp_vld                     (avail_ring_dma_ctx_info_rd_rsp_vld                     ),
        .avail_ring_dma_ctx_info_rd_rsp_forced_shutdown         (avail_ring_dma_ctx_info_rd_rsp_forced_shutdown         ),
        .avail_ring_dma_ctx_info_rd_rsp_ctrl                    (avail_ring_dma_ctx_info_rd_rsp_ctrl                    ),
        .avail_ring_dma_ctx_info_rd_rsp_bdf                     (avail_ring_dma_ctx_info_rd_rsp_bdf                     ),
        .avail_ring_dma_ctx_info_rd_rsp_qdepth                  (avail_ring_dma_ctx_info_rd_rsp_qdepth                  ),
        .avail_ring_dma_ctx_info_rd_rsp_avail_idx               (avail_ring_dma_ctx_info_rd_rsp_avail_idx               ),
        .avail_ring_dma_ctx_info_rd_rsp_avail_ui                (avail_ring_dma_ctx_info_rd_rsp_avail_ui                ),
        .avail_ring_dma_ctx_info_rd_rsp_avail_ci                (avail_ring_dma_ctx_info_rd_rsp_avail_ci                ),    
        .avail_ring_desc_engine_ctx_info_rd_req_vld             (avail_ring_desc_engine_ctx_info_rd_req_vld             ),
        .avail_ring_desc_engine_ctx_info_rd_req_qid             (avail_ring_desc_engine_ctx_info_rd_req_qid             ),
        .avail_ring_desc_engine_ctx_info_rd_rsp_vld             (avail_ring_desc_engine_ctx_info_rd_rsp_vld             ),
        .avail_ring_desc_engine_ctx_info_rd_rsp_forced_shutdown (avail_ring_desc_engine_ctx_info_rd_rsp_forced_shutdown ),
        .avail_ring_desc_engine_ctx_info_rd_rsp_ctrl            (avail_ring_desc_engine_ctx_info_rd_rsp_ctrl            ),
        .avail_ring_desc_engine_ctx_info_rd_rsp_avail_pi        (avail_ring_desc_engine_ctx_info_rd_rsp_avail_pi        ),
        .avail_ring_desc_engine_ctx_info_rd_rsp_avail_idx       (avail_ring_desc_engine_ctx_info_rd_rsp_avail_idx       ),
        .avail_ring_desc_engine_ctx_info_rd_rsp_avail_ui        (avail_ring_desc_engine_ctx_info_rd_rsp_avail_ui        ),
        .avail_ring_desc_engine_ctx_info_rd_rsp_avail_ci        (avail_ring_desc_engine_ctx_info_rd_rsp_avail_ci        ),  
        .avail_ring_avail_addr_rd_req_vld                       (avail_ring_avail_addr_rd_req_vld                       ),
        .avail_ring_avail_addr_rd_req_qid                       (avail_ring_avail_addr_rd_req_qid                       ),
        .avail_ring_avail_addr_rd_req_rdy                       (avail_ring_avail_addr_rd_req_rdy                       ),
        .avail_ring_avail_addr_rd_rsp_vld                       (avail_ring_avail_addr_rd_rsp_vld                       ),
        .avail_ring_avail_addr_rd_rsp_dat                       (avail_ring_avail_addr_rd_rsp_dat                       ),    
        .avail_ring_avail_ci_wr_req_vld                         (avail_ring_avail_ci_wr_req_vld                         ),
        .avail_ring_avail_ci_wr_req_dat                         (avail_ring_avail_ci_wr_req_dat                         ),
        .avail_ring_avail_ci_wr_req_qid                         (avail_ring_avail_ci_wr_req_qid                         ),    
        .avail_ring_avail_ui_wr_req_vld                         (avail_ring_avail_ui_wr_req_vld                         ),
        .avail_ring_avail_ui_wr_req_dat                         (avail_ring_avail_ui_wr_req_dat                         ),
        .avail_ring_avail_ui_wr_req_qid                         (avail_ring_avail_ui_wr_req_qid                         ),    
        .avail_ring_avail_pi_wr_req_vld                         (avail_ring_avail_pi_wr_req_vld                         ),
        .avail_ring_avail_pi_wr_req_dat                         (avail_ring_avail_pi_wr_req_dat                         ),
        .avail_ring_avail_pi_wr_req_qid                         (avail_ring_avail_pi_wr_req_qid                         ),
        .desc_engine_net_rx_ctx_info_rd_req_vld                 (desc_engine_net_rx_ctx_info_rd_req_vld                 ),
        .desc_engine_net_rx_ctx_info_rd_req_vq                  (desc_engine_net_rx_ctx_info_rd_req_vq                  ),
        .desc_engine_net_rx_ctx_info_rd_rsp_vld                 (desc_engine_net_rx_ctx_info_rd_rsp_vld                 ),
        .desc_engine_net_rx_ctx_info_rd_rsp_desc_tbl_addr       (desc_engine_net_rx_ctx_info_rd_rsp_desc_tbl_addr       ),
        .desc_engine_net_rx_ctx_info_rd_rsp_qdepth              (desc_engine_net_rx_ctx_info_rd_rsp_qdepth              ),
        .desc_engine_net_rx_ctx_info_rd_rsp_forced_shutdown     (desc_engine_net_rx_ctx_info_rd_rsp_forced_shutdown     ),
        .desc_engine_net_rx_ctx_info_rd_rsp_indirct_support     (desc_engine_net_rx_ctx_info_rd_rsp_indirct_support     ),
        .desc_engine_net_rx_ctx_info_rd_rsp_max_len             (desc_engine_net_rx_ctx_info_rd_rsp_max_len             ),
        .desc_engine_net_rx_ctx_info_rd_rsp_bdf                 (desc_engine_net_rx_ctx_info_rd_rsp_bdf                 ),
        .desc_engine_net_rx_ctx_slot_chain_rd_req_vld           (desc_engine_net_rx_ctx_slot_chain_rd_req_vld           ),
        .desc_engine_net_rx_ctx_slot_chain_rd_req_vq            (desc_engine_net_rx_ctx_slot_chain_rd_req_vq            ),
        .desc_engine_net_rx_ctx_slot_chain_rd_rsp_vld           (desc_engine_net_rx_ctx_slot_chain_rd_rsp_vld           ),
        .desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot     (desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot     ),
        .desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot_vld (desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot_vld ),
        .desc_engine_net_rx_ctx_slot_chain_rd_rsp_tail_slot     (desc_engine_net_rx_ctx_slot_chain_rd_rsp_tail_slot     ),
        .desc_engine_net_rx_ctx_slot_chain_wr_vld               (desc_engine_net_rx_ctx_slot_chain_wr_vld               ),
        .desc_engine_net_rx_ctx_slot_chain_wr_vq                (desc_engine_net_rx_ctx_slot_chain_wr_vq                ),
        .desc_engine_net_rx_ctx_slot_chain_wr_head_slot         (desc_engine_net_rx_ctx_slot_chain_wr_head_slot         ),
        .desc_engine_net_rx_ctx_slot_chain_wr_head_slot_vld     (desc_engine_net_rx_ctx_slot_chain_wr_head_slot_vld     ),
        .desc_engine_net_rx_ctx_slot_chain_wr_tail_slot         (desc_engine_net_rx_ctx_slot_chain_wr_tail_slot         ),
        .desc_engine_net_tx_ctx_info_rd_req_vld                 (desc_engine_net_tx_ctx_info_rd_req_vld                 ),
        .desc_engine_net_tx_ctx_info_rd_req_vq                  (desc_engine_net_tx_ctx_info_rd_req_vq                  ),
        .desc_engine_net_tx_ctx_info_rd_rsp_vld                 (desc_engine_net_tx_ctx_info_rd_rsp_vld                 ),
        .desc_engine_net_tx_ctx_info_rd_rsp_desc_tbl_addr       (desc_engine_net_tx_ctx_info_rd_rsp_desc_tbl_addr       ),
        .desc_engine_net_tx_ctx_info_rd_rsp_qdepth              (desc_engine_net_tx_ctx_info_rd_rsp_qdepth              ),
        .desc_engine_net_tx_ctx_info_rd_rsp_forced_shutdown     (desc_engine_net_tx_ctx_info_rd_rsp_forced_shutdown     ),
        .desc_engine_net_tx_ctx_info_rd_rsp_indirct_support     (desc_engine_net_tx_ctx_info_rd_rsp_indirct_support     ),
        .desc_engine_net_tx_ctx_info_rd_rsp_max_len             (desc_engine_net_tx_ctx_info_rd_rsp_max_len             ),
        .desc_engine_net_tx_ctx_info_rd_rsp_bdf                 (desc_engine_net_tx_ctx_info_rd_rsp_bdf                 ),
        .desc_engine_net_tx_ctx_slot_chain_rd_req_vld           (desc_engine_net_tx_ctx_slot_chain_rd_req_vld           ),
        .desc_engine_net_tx_ctx_slot_chain_rd_req_vq            (desc_engine_net_tx_ctx_slot_chain_rd_req_vq            ),
        .desc_engine_net_tx_ctx_slot_chain_rd_rsp_vld           (desc_engine_net_tx_ctx_slot_chain_rd_rsp_vld           ),
        .desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot     (desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot     ),
        .desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot_vld (desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot_vld ),
        .desc_engine_net_tx_ctx_slot_chain_rd_rsp_tail_slot     (desc_engine_net_tx_ctx_slot_chain_rd_rsp_tail_slot     ),
        .desc_engine_net_tx_ctx_slot_chain_wr_vld               (desc_engine_net_tx_ctx_slot_chain_wr_vld               ),
        .desc_engine_net_tx_ctx_slot_chain_wr_vq                (desc_engine_net_tx_ctx_slot_chain_wr_vq                ),
        .desc_engine_net_tx_ctx_slot_chain_wr_head_slot         (desc_engine_net_tx_ctx_slot_chain_wr_head_slot         ),
        .desc_engine_net_tx_ctx_slot_chain_wr_head_slot_vld     (desc_engine_net_tx_ctx_slot_chain_wr_head_slot_vld     ),
        .desc_engine_net_tx_ctx_slot_chain_wr_tail_slot         (desc_engine_net_tx_ctx_slot_chain_wr_tail_slot         ),
        .desc_engine_net_tx_limit_per_queue_rd_req_vld          (desc_engine_net_tx_limit_per_queue_rd_req_vld          ),
        .desc_engine_net_tx_limit_per_queue_rd_req_qid          (desc_engine_net_tx_limit_per_queue_rd_req_qid          ),
        .desc_engine_net_tx_limit_per_queue_rd_rsp_vld          (desc_engine_net_tx_limit_per_queue_rd_rsp_vld          ),
        .desc_engine_net_tx_limit_per_queue_rd_rsp_dat          (desc_engine_net_tx_limit_per_queue_rd_rsp_dat          ),
        .desc_engine_net_tx_limit_per_dev_rd_req_vld            (desc_engine_net_tx_limit_per_dev_rd_req_vld            ),
        .desc_engine_net_tx_limit_per_dev_rd_req_dev_id         (desc_engine_net_tx_limit_per_dev_rd_req_dev_id         ),
        .desc_engine_net_tx_limit_per_dev_rd_rsp_vld            (desc_engine_net_tx_limit_per_dev_rd_rsp_vld            ),
        .desc_engine_net_tx_limit_per_dev_rd_rsp_dat            (desc_engine_net_tx_limit_per_dev_rd_rsp_dat            ),
        .blk_desc_engine_resumer_rd_req_vld                     (blk_desc_engine_resummer_rd_req_vld                    ),
        .blk_desc_engine_resumer_rd_req_qid                     (blk_desc_engine_resummer_rd_req_qid                    ),
        .blk_desc_engine_resumer_rd_rsp_vld                     (blk_desc_engine_resummer_rd_rsp_vld                    ),
        .blk_desc_engine_resumer_rd_rsp_dat                     (blk_desc_engine_resummer_rd_rsp_dat                    ),    
        .blk_desc_engine_resumer_wr_vld                         (blk_desc_engine_resumer_wr_vld                         ),
        .blk_desc_engine_resumer_wr_qid                         (blk_desc_engine_resumer_wr_qid                         ),
        .blk_desc_engine_resumer_wr_dat                         (blk_desc_engine_resumer_wr_dat                         ),    
        .blk_desc_engine_global_info_rd_req_vld                 (blk_desc_engine_global_info_rd_req_vld                 ),
        .blk_desc_engine_global_info_rd_req_qid                 (blk_desc_engine_global_info_rd_req_qid                 ),    
        .blk_desc_engine_global_info_rd_rsp_vld                 (blk_desc_engine_global_info_rd_rsp_vld                 ),
        .blk_desc_engine_global_info_rd_rsp_bdf                 (blk_desc_engine_global_info_rd_rsp_bdf                 ),
        .blk_desc_engine_global_info_rd_rsp_forced_shutdown     (blk_desc_engine_global_info_rd_rsp_forced_shutdown     ),
        .blk_desc_engine_global_info_rd_rsp_desc_tbl_addr       (blk_desc_engine_global_info_rd_rsp_desc_tbl_addr       ),
        .blk_desc_engine_global_info_rd_rsp_qdepth              (blk_desc_engine_global_info_rd_rsp_qdepth              ),
        .blk_desc_engine_global_info_rd_rsp_indirct_support     (blk_desc_engine_global_info_rd_rsp_indirct_support     ),
        .blk_desc_engine_global_info_rd_rsp_segment_size_blk    (blk_desc_engine_global_info_rd_rsp_segment_size_blk    ),    
        .blk_desc_engine_local_info_rd_req_vld                  (blk_desc_engine_local_info_rd_req_vld                  ),
        .blk_desc_engine_local_info_rd_req_qid                  (blk_desc_engine_local_info_rd_req_qid                  ),    
        .blk_desc_engine_local_info_rd_rsp_vld                  (blk_desc_engine_local_info_rd_rsp_vld                  ),
        .blk_desc_engine_local_info_rd_rsp_desc_tbl_addr        (blk_desc_engine_local_info_rd_rsp_desc_tbl_addr        ),
        .blk_desc_engine_local_info_rd_rsp_desc_tbl_size        (blk_desc_engine_local_info_rd_rsp_desc_tbl_size        ),
        .blk_desc_engine_local_info_rd_rsp_desc_tbl_next        (blk_desc_engine_local_info_rd_rsp_desc_tbl_next        ),
        .blk_desc_engine_local_info_rd_rsp_desc_tbl_id          (blk_desc_engine_local_info_rd_rsp_desc_tbl_id          ),
        .blk_desc_engine_local_info_rd_rsp_desc_cnt             (blk_desc_engine_local_info_rd_rsp_qid_desc_cnt         ),
        .blk_desc_engine_local_info_rd_rsp_data_len             (blk_desc_engine_local_info_rd_rsp_qid_data_len         ),
        .blk_desc_engine_local_info_rd_rsp_is_indirct           (blk_desc_engine_local_info_rd_rsp_qid_is_indirct       ),    
        .blk_desc_engine_local_info_wr_vld                      (blk_desc_engine_local_info_wr_vld                      ),
        .blk_desc_engine_local_info_wr_qid                      (blk_desc_engine_local_info_wr_qid                      ),
        .blk_desc_engine_local_info_wr_desc_tbl_addr            (blk_desc_engine_local_info_wr_desc_tbl_addr            ),
        .blk_desc_engine_local_info_wr_desc_tbl_size            (blk_desc_engine_local_info_wr_desc_tbl_size            ),
        .blk_desc_engine_local_info_wr_desc_tbl_next            (blk_desc_engine_local_info_wr_desc_tbl_next            ),
        .blk_desc_engine_local_info_wr_desc_tbl_id              (blk_desc_engine_local_info_wr_desc_tbl_id              ),
        .blk_desc_engine_local_info_wr_desc_cnt                 (blk_desc_engine_local_info_wr_qid_desc_cnt             ),
        .blk_desc_engine_local_info_wr_data_len                 (blk_desc_engine_local_info_wr_qid_data_len             ),
        .blk_desc_engine_local_info_wr_is_indirct               (blk_desc_engine_local_info_wr_qid_is_indirct           ),
        .blk_down_stream_ptr_rd_req_vld                         (blk_down_stream_ptr_rd_req_vld                         ),
        .blk_down_stream_ptr_rd_req_qid                         (blk_down_stream_ptr_rd_req_qid                         ),
        .blk_down_stream_ptr_rd_rsp_vld                         (blk_down_stream_ptr_rd_rsp_vld                         ),
        .blk_down_stream_ptr_rd_rsp_dat                         (blk_down_stream_ptr_rd_rsp_dat                         ),
        .blk_down_stream_ptr_wr_req_vld                         (blk_down_stream_ptr_wr_req_vld                         ),
        .blk_down_stream_ptr_wr_req_qid                         (blk_down_stream_ptr_wr_req_qid                         ),
        .blk_down_stream_ptr_wr_req_dat                         (blk_down_stream_ptr_wr_req_dat                         ),
        .blk_down_stream_qos_info_rd_req_vld                    (blk_down_stream_qos_info_rd_req_vld                    ),
        .blk_down_stream_qos_info_rd_req_qid                    (blk_down_stream_qos_info_rd_req_qid                    ),
        .blk_down_stream_qos_info_rd_rsp_vld                    (blk_down_stream_qos_info_rd_rsp_vld                    ),
        .blk_down_stream_qos_info_rd_rsp_qos_enable             (blk_down_stream_qos_info_rd_rsp_qos_enable             ),
        .blk_down_stream_qos_info_rd_rsp_qos_unit               (blk_down_stream_qos_info_rd_rsp_qos_unit               ),    
        .blk_down_stream_dma_info_rd_req_vld                    (blk_down_stream_dma_info_rd_req_vld                    ),
        .blk_down_stream_dma_info_rd_req_qid                    (blk_down_stream_dma_info_rd_req_qid                    ),
        .blk_down_stream_dma_info_rd_rsp_vld                    (blk_down_stream_dma_info_rd_rsp_vld                    ),
        .blk_down_stream_dma_info_rd_rsp_bdf                    (blk_down_stream_dma_info_rd_rsp_bdf                    ),
        .blk_down_stream_dma_info_rd_rsp_forcedown              (blk_down_stream_dma_info_rd_rsp_forcedown              ),
        .blk_down_stream_dma_info_rd_rsp_generation             (blk_down_stream_dma_info_rd_rsp_generation             ),
        .blk_down_stream_chain_fst_seg_rd_req_vld               (blk_down_stream_chain_fst_seg_rd_req_vld),
        .blk_down_stream_chain_fst_seg_rd_req_qid               (blk_down_stream_chain_fst_seg_rd_req_qid),
        .blk_down_stream_chain_fst_seg_rd_rsp_vld               (blk_down_stream_chain_fst_seg_rd_rsp_vld),
        .blk_down_stream_chain_fst_seg_rd_rsp_dat               (blk_down_stream_chain_fst_seg_rd_rsp_dat),
        .blk_down_stream_chain_fst_seg_wr_vld                   (blk_down_stream_chain_fst_seg_wr_vld    ),
        .blk_down_stream_chain_fst_seg_wr_qid                   (blk_down_stream_chain_fst_seg_wr_qid    ),
        .blk_down_stream_chain_fst_seg_wr_dat                   (blk_down_stream_chain_fst_seg_wr_dat    ),
        .blk_upstream_ctx_req_vld                               (blk_upstream_ctx_req_vld                               ),
        .blk_upstream_ctx_req_qid                               (blk_upstream_ctx_req_qid                               ),    
        .blk_upstream_ctx_rsp_vld                               (blk_upstream_ctx_rsp_vld                               ), 
        .blk_upstream_ctx_rsp_forced_shutdown                   (blk_upstream_ctx_rsp_forced_shutdown                   ),
        .blk_upstream_ctx_rsp_q_status                          (blk_upstream_ctx_rsp_q_status                          ),
        .blk_upstream_ctx_rsp_generation                        (blk_upstream_ctx_rsp_generation                        ),    
        .blk_upstream_ctx_rsp_dev_id                            (blk_upstream_ctx_rsp_dev_id                            ), 
        .blk_upstream_ctx_rsp_bdf                               (blk_upstream_ctx_rsp_bdf                               ),
        .blk_upstream_ptr_rd_req_vld                            (blk_upstream_ptr_rd_req_vld),
        .blk_upstream_ptr_rd_req_qid                            (blk_upstream_ptr_rd_req_qid),
        .blk_upstream_ptr_rd_rsp_vld                            (blk_upstream_ptr_rd_rsp_vld),
        .blk_upstream_ptr_rd_rsp_dat                            (blk_upstream_ptr_rd_rsp_dat),
        .blk_upstream_ptr_wr_req_vld                            (blk_upstream_ptr_wr_req_vld),
        .blk_upstream_ptr_wr_req_qid                            (blk_upstream_ptr_wr_req_qid),
        .blk_upstream_ptr_wr_req_dat                            (blk_upstream_ptr_wr_req_dat),
        .blk_upstream_mon_send_io_qid                           (blk_upstream_mon_send_io_qid                           ),
        .blk_upstream_mon_send_io                               (blk_upstream_mon_send_io                               ),  
        .net_tx_slot_ctrl_ctx_info_rd_req_vld                   (net_tx_slot_ctrl_ctx_info_rd_req_vld                   ),
        .net_tx_slot_ctrl_ctx_info_rd_req_qid                   (net_tx_slot_ctrl_ctx_info_rd_req_qid                   ),    
        .net_tx_slot_ctrl_ctx_info_rd_rsp_vld                   (net_tx_slot_ctrl_ctx_info_rd_rsp_vld                   ),
        .net_tx_slot_ctrl_ctx_info_rd_rsp_qos_unit              (net_tx_slot_ctrl_ctx_info_rd_rsp_qos_unit              ),
        .net_tx_slot_ctrl_ctx_info_rd_rsp_qos_enable            (net_tx_slot_ctrl_ctx_info_rd_rsp_qos_enable            ),
        .net_tx_slot_ctrl_ctx_info_rd_rsp_dev_id                (net_tx_slot_ctrl_ctx_info_rd_rsp_dev_id                ),
        .net_tx_rd_data_ctx_info_rd_req_vld                     (net_tx_rd_data_ctx_info_rd_req_vld                     ),
        .net_tx_rd_data_ctx_info_rd_req_qid                     (net_tx_rd_data_ctx_info_rd_req_vq                      ),    
        .net_tx_rd_data_ctx_info_rd_rsp_vld                     (net_tx_rd_data_ctx_info_rd_rsp_vld                     ),
        .net_tx_rd_data_ctx_info_rd_rsp_bdf                     (net_tx_rd_data_ctx_info_rd_rsp_bdf                     ),
        .net_tx_rd_data_ctx_info_rd_rsp_forced_shutdown         (net_tx_rd_data_ctx_info_rd_rsp_forced_shutdown         ),
        .net_tx_rd_data_ctx_info_rd_rsp_qos_enable              (net_tx_rd_data_ctx_info_rd_rsp_qos_enable              ),
        .net_tx_rd_data_ctx_info_rd_rsp_qos_unit                (net_tx_rd_data_ctx_info_rd_rsp_qos_unit                ),
        .net_tx_rd_data_ctx_info_rd_rsp_tso_en                  (net_tx_rd_data_ctx_info_rd_rsp_tso_en                  ),
        .net_tx_rd_data_ctx_info_rd_rsp_csum_en                 (net_tx_rd_data_ctx_info_rd_rsp_csum_en                 ),
        .net_tx_rd_data_ctx_info_rd_rsp_generation              (net_tx_rd_data_ctx_info_rd_rsp_generation              ),
        .net_rx_slot_ctrl_dev_id_rd_req_vld                     (net_rx_slot_ctrl_dev_id_rd_req_vld                     ),
        .net_rx_slot_ctrl_dev_id_rd_req_qid                     (net_rx_slot_ctrl_dev_id_rd_req_qid                     ),    
        .net_rx_slot_ctrl_dev_id_rd_rsp_vld                     (net_rx_slot_ctrl_dev_id_rd_rsp_vld                     ),
        .net_rx_slot_ctrl_dev_id_rd_rsp_dat                     (net_rx_slot_ctrl_dev_id_rd_rsp_dat                     ),
        .net_rx_wr_data_ctx_rd_req_vld                          (net_rx_wr_data_ctx_rd_req_vld                          ),
        .net_rx_wr_data_ctx_rd_req_qid                          (net_rx_wr_data_ctx_rd_req_qid                          ),    
        .net_rx_wr_data_ctx_rd_rsp_vld                          (net_rx_wr_data_ctx_rd_rsp_vld                          ),
        .net_rx_wr_data_ctx_rd_rsp_bdf                          (net_rx_wr_data_ctx_rd_rsp_bdf                          ),
        .net_rx_wr_data_ctx_rd_rsp_forced_shutdown              (net_rx_wr_data_ctx_rd_rsp_forced_shutdown              ),
        .net_rx_buf_drop_info_rd_req_vld                        (net_rx_buf_drop_info_rd_req_vld                        ),
        .net_rx_buf_drop_info_rd_req_qid                        (net_rx_buf_drop_info_rd_req_qid                        ),
        .net_rx_buf_drop_info_rd_rsp_vld                        (net_rx_buf_drop_info_rd_rsp_vld                        ),
        .net_rx_buf_drop_info_rd_rsp_generation                 (net_rx_buf_drop_info_rd_rsp_generation                 ),
        .net_rx_buf_drop_info_rd_rsp_qos_unit                   (net_rx_buf_drop_info_rd_rsp_qos_unit                   ),
        .net_rx_buf_drop_info_rd_rsp_qos_enable                 (net_rx_buf_drop_info_rd_rsp_qos_enable                 ),
        .net_rx_buf_req_idx_per_queue_rd_req_vld                (net_rx_buf_req_idx_per_queue_rd_req_vld                ),
        .net_rx_buf_req_idx_per_queue_rd_req_qid                (net_rx_buf_req_idx_per_queue_rd_req_qid                ),
        .net_rx_buf_req_idx_per_queue_rd_rsp_vld                (net_rx_buf_req_idx_per_queue_rd_rsp_vld                ),
        .net_rx_buf_req_idx_per_queue_rd_rsp_dev_id             (net_rx_buf_req_idx_per_queue_rd_rsp_dev_id             ),
        .net_rx_buf_req_idx_per_queue_rd_rsp_limit              (net_rx_buf_req_idx_per_queue_rd_rsp_limit              ),
        .net_rx_buf_req_idx_per_dev_rd_req_vld                  (net_rx_buf_req_idx_per_dev_rd_req_vld                  ),
        .net_rx_buf_req_idx_per_dev_rd_req_dev_id               (net_rx_buf_req_idx_per_dev_rd_req_dev_id               ),
        .net_rx_buf_req_idx_per_dev_rd_rsp_vld                  (net_rx_buf_req_idx_per_dev_rd_rsp_vld                  ),
        .net_rx_buf_req_idx_per_dev_rd_rsp_limit                (net_rx_buf_req_idx_per_dev_rd_rsp_limit                ),
        .used_ring_irq_rd_req_vld                               (used_ring_irq_rd_req_vld                               ),
        .used_ring_irq_rd_req_qid                               (used_ring_irq_rd_req_qid                               ),
        .used_ring_irq_rd_rsp_vld                               (used_ring_irq_rd_rsp_vld                               ),
        .used_ring_irq_rd_rsp_forced_shutdown                   (used_ring_irq_rd_rsp_forced_shutdown                   ),
        .used_ring_irq_rd_rsp_msix_addr                         (used_ring_irq_rd_rsp_msix_addr                         ),
        .used_ring_irq_rd_rsp_msix_data                         (used_ring_irq_rd_rsp_msix_data                         ),
        .used_ring_irq_rd_rsp_bdf                               (used_ring_irq_rd_rsp_bdf                               ),
        .used_ring_irq_rd_rsp_dev_id                            (used_ring_irq_rd_rsp_dev_id                            ),
        .used_ring_irq_rd_rsp_msix_mask                         (used_ring_irq_rd_rsp_msix_mask                         ),
        .used_ring_irq_rd_rsp_msix_pending                      (used_ring_irq_rd_rsp_msix_pending                      ),
        .used_ring_irq_rd_rsp_used_ring_addr                    (used_ring_irq_rd_rsp_used_ring_addr                    ),
        .used_ring_irq_rd_rsp_qdepth                            (used_ring_irq_rd_rsp_qdepth                            ),
        .used_ring_irq_rd_rsp_msix_enable                       (used_ring_irq_rd_rsp_msix_enable                       ),
        .used_ring_irq_rd_rsp_q_status                          (used_ring_irq_rd_rsp_q_status                          ),
        .used_ring_irq_rd_rsp_err_fatal                         (used_ring_irq_rd_rsp_err_fatal                         ),
        .used_err_fatal_wr_vld                                  (used_err_fatal_wr_vld                                  ),
        .used_err_fatal_wr_qid                                  (used_err_fatal_wr_qid                                  ),
        .used_err_fatal_wr_dat                                  (used_err_fatal_wr_dat                                  ),    
        .used_elem_ptr_rd_req_vld                               (used_elem_ptr_rd_req_vld                               ),
        .used_elem_ptr_rd_req_qid                               (used_elem_ptr_rd_req_qid                               ),
        .used_elem_ptr_rd_rsp_vld                               (used_elem_ptr_rd_rsp_vld                               ),
        .used_elem_ptr_rd_rsp_dat                               (used_elem_ptr_rd_rsp_dat                               ),    
        .used_elem_ptr_wr_vld                                   (used_elem_ptr_wr_vld                                   ),
        .used_elem_ptr_wr_qid                                   (used_elem_ptr_wr_qid                                   ),
        .used_elem_ptr_wr_dat                                   (used_elem_ptr_wr_dat                                   ),   
        .used_idx_wr_vld                                        (used_idx_wr_vld                                        ),
        .used_idx_wr_qid                                        (used_idx_wr_qid                                        ),
        .used_idx_wr_dat                                        (used_idx_wr_dat                                        ),    
        .used_msix_tbl_wr_vld                                   (used_msix_tbl_wr_vld                                   ),
        .used_msix_tbl_wr_qid                                   (used_msix_tbl_wr_qid                                   ),
        .used_msix_tbl_wr_mask                                  (used_msix_tbl_wr_mask                                  ),
        .used_msix_tbl_wr_pending                               (used_msix_tbl_wr_pending                               ),
        .msix_aggregation_time_rd_req_vld_net_tx                (msix_aggregation_time_rd_req_vld_net_tx                ),
        .msix_aggregation_time_rd_req_qid_net_tx                (msix_aggregation_time_rd_req_qid_net_tx                ),    
        .msix_aggregation_time_rd_rsp_vld_net_tx                (msix_aggregation_time_rd_rsp_vld_net_tx                ),
        .msix_aggregation_time_rd_rsp_dat_net_tx                (msix_aggregation_time_rd_rsp_dat_net_tx                ),    
        .msix_aggregation_threshold_rd_req_vld_net_tx           (msix_aggregation_threshold_rd_req_vld_net_tx           ),
        .msix_aggregation_threshold_rd_req_qid_net_tx           (msix_aggregation_threshold_rd_req_qid_net_tx           ),
        .msix_aggregation_threshold_rd_rsp_vld_net_tx           (msix_aggregation_threshold_rd_rsp_vld_net_tx           ),
        .msix_aggregation_threshold_rd_rsp_dat_net_tx           (msix_aggregation_threshold_rd_rsp_dat_net_tx           ),    
        .msix_aggregation_info_rd_req_vld_net_tx                (msix_aggregation_info_rd_req_vld_net_tx                ),
        .msix_aggregation_info_rd_req_qid_net_tx                (msix_aggregation_info_rd_req_qid_net_tx                ),
        .msix_aggregation_info_rd_rsp_vld_net_tx                (msix_aggregation_info_rd_rsp_vld_net_tx                ),
        .msix_aggregation_info_rd_rsp_dat_net_tx                (msix_aggregation_info_rd_rsp_dat_net_tx                ),    
        .msix_aggregation_info_wr_vld_net_tx                    (msix_aggregation_info_wr_vld_net_tx                    ),
        .msix_aggregation_info_wr_qid_net_tx                    (msix_aggregation_info_wr_qid_net_tx                    ),
        .msix_aggregation_info_wr_dat_net_tx                    (msix_aggregation_info_wr_dat_net_tx                    ),    
        .msix_aggregation_time_rd_req_vld_net_rx                (msix_aggregation_time_rd_req_vld_net_rx                ),
        .msix_aggregation_time_rd_req_qid_net_rx                (msix_aggregation_time_rd_req_qid_net_rx                ),    
        .msix_aggregation_time_rd_rsp_vld_net_rx                (msix_aggregation_time_rd_rsp_vld_net_rx                ),
        .msix_aggregation_time_rd_rsp_dat_net_rx                (msix_aggregation_time_rd_rsp_dat_net_rx                ),    
        .msix_aggregation_threshold_rd_req_vld_net_rx           (msix_aggregation_threshold_rd_req_vld_net_rx           ),
        .msix_aggregation_threshold_rd_req_qid_net_rx           (msix_aggregation_threshold_rd_req_qid_net_rx           ),
        .msix_aggregation_threshold_rd_rsp_vld_net_rx           (msix_aggregation_threshold_rd_rsp_vld_net_rx           ),
        .msix_aggregation_threshold_rd_rsp_dat_net_rx           (msix_aggregation_threshold_rd_rsp_dat_net_rx           ),    
        .msix_aggregation_info_rd_req_vld_net_rx                (msix_aggregation_info_rd_req_vld_net_rx                ),
        .msix_aggregation_info_rd_req_qid_net_rx                (msix_aggregation_info_rd_req_qid_net_rx                ),
        .msix_aggregation_info_rd_rsp_vld_net_rx                (msix_aggregation_info_rd_rsp_vld_net_rx                ),
        .msix_aggregation_info_rd_rsp_dat_net_rx                (msix_aggregation_info_rd_rsp_dat_net_rx                ),    
        .msix_aggregation_info_wr_vld_net_rx                    (msix_aggregation_info_wr_vld_net_rx                    ),
        .msix_aggregation_info_wr_qid_net_rx                    (msix_aggregation_info_wr_qid_net_rx                    ),
        .msix_aggregation_info_wr_dat_net_rx                    (msix_aggregation_info_wr_dat_net_rx                    ),
        .used_err_info_wr_vld                                   (used_err_info_wr_vld                                   ),
        .used_err_info_wr_qid                                   (used_err_info_wr_qid                                   ),
        .used_err_info_wr_dat                                   (used_err_info_wr_dat                                   ),
        .used_err_info_wr_rdy                                   (used_err_info_wr_rdy                                   ),    
        .used_set_mask_req_vld                                  (used_set_mask_req_vld                                  ),
        .used_set_mask_req_qid                                  (used_set_mask_req_qid                                  ),
        .used_set_mask_req_dat                                  (used_set_mask_req_dat                                  ),
        .used_set_mask_req_rdy                                  (used_set_mask_req_rdy                                  ),
        .used_dma_write_used_idx_irq_flag_wr_vld                (used_dma_write_used_idx_irq_flag_wr_vld                ),
        .used_dma_write_used_idx_irq_flag_wr_qid                (used_dma_write_used_idx_irq_flag_wr_qid                ),
        .used_dma_write_used_idx_irq_flag_wr_dat                (used_dma_write_used_idx_irq_flag_wr_dat                ),
        .mon_send_a_irq                                         (used_mon_send_a_irq                                    ),
        .mon_send_irq_vq                                        (used_mon_send_irq_vq                                   ),
        .soc_notify_req_vld                                     (soc_notify_req_vld                                     ),
        .soc_notify_req_qid                                     (soc_notify_req_qid                                     ),
        .soc_notify_req_rdy                                     (soc_notify_req_rdy                                     ),
        .vq_pending_chk_req_vld                                 (vq_pending_chk_req_vld                                 ),
        .vq_pending_chk_req_vq                                  (vq_pending_chk_req_vq                                  ),
        .vq_pending_chk_rsp_vld                                 (vq_pending_chk_rsp_vld                                 ),
        .vq_pending_chk_rsp_busy                                (vq_pending_chk_rsp_busy                                ),
        .csr_if                                                 (m_br_if[0]                                             ),
        .dfx_if                                                 (m_br_if[12]                                            )
    );

    virtio_db_sch #(
        .Q_WIDTH($bits(virtio_vq_t))
    ) u_virtio_db_sch (
        .clk                (clk                ),
        .rst                (rst[1]                ),
        .doorbell_req_vq   (doorbell_req_vq   ),
        .doorbell_req_vld   (doorbell_req_vld   ),
        .doorbell_req_rdy   (doorbell_req_rdy   ),
        .soc_notify_req_qid (soc_notify_req_qid ),
        .soc_notify_req_vld (soc_notify_req_vld ),
        .soc_notify_req_rdy (soc_notify_req_rdy ),
        .notify_req_qid     (notify_req_qid     ),
        .notify_req_vld     (notify_req_vld     ),
        .notify_req_rdy     (notify_req_rdy     )

    );

    virtio_sch #(
        .VQ_WIDTH($bits(virtio_vq_t))
    ) u_virtio_idx_eng_sch (
        .clk            (clk                            ),
        .rst            (rst[1]                            ),
        .sch_req_vld    (notify_req_vld                 ),
        .sch_req_rdy    (notify_req_rdy                 ),
        .sch_req_qid    (notify_req_qid                 ),
        .notify_req_vld (idx_eng_notify_req_vld         ),
        .notify_req_rdy (idx_eng_notify_req_rdy         ),
        .notify_req_qid (idx_eng_notify_req_vq          ),
        .notify_rsp_vld (idx_eng_notify_rsp_vld         ),
        .notify_rsp_rdy (idx_eng_notify_rsp_rdy         ),
        .notify_rsp_qid (idx_eng_notify_rsp_vq          ),
        .notify_rsp_done(idx_eng_notify_rsp_done        ),
        .notify_rsp_cold(idx_eng_notify_rsp_cold        ),
        .hot_weight     (4'h2                           ),
        .cold_weight    (4'h1                           ),
        .dfx_err        (                               ),
        .dfx_status     (                               ),
        .notify_req_cnt (                               ),
        .notify_rsp_cnt (                               )
    );

    virtio_idx_engine_top #(
        .DATA_WIDTH     (DATA_WIDTH    ),
        .EMPTH_WIDTH    (EMPTH_WIDTH   )
    ) u_virtio_idx_engine_top ( 
        .clk                                    (clk                                    ),
        .rst                                    (rst[1]                                 ),
        .notify_req_vld                         (idx_eng_notify_req_vld                 ),
        .notify_req_rdy                         (idx_eng_notify_req_rdy                 ),
        .notify_req_vq                          (idx_eng_notify_req_vq                  ),
        .notify_rsp_vld                         (idx_eng_notify_rsp_vld                 ),
        .notify_rsp_rdy                         (idx_eng_notify_rsp_rdy                 ),
        .notify_rsp_cold                        (idx_eng_notify_rsp_cold                ),
        .notify_rsp_done                        (idx_eng_notify_rsp_done                ),
        .notify_rsp_vq                          (idx_eng_notify_rsp_vq                  ),
        .idx_eng_dma_rd_req                     (idx_eng_dma_rd_req_if                  ),
        .idx_eng_dma_rd_rsp                     (idx_eng_dma_rd_rsp_if                  ),
        .idx_eng_dma_wr_req                     (idx_eng_dma_wr_req_if                  ),
        .idx_eng_dma_wr_rsp                     (idx_eng_dma_wr_rsp_if                  ),
        .idx_notify_vld                         (avail_ring_notify_vld                  ),
        .idx_notify_vq                          (avail_ring_notify_vq                   ),
        .idx_notify_rdy                         (avail_ring_notify_rdy                  ),
        .idx_engine_ctx_rd_req_vld              (idx_engine_ctx_rd_req_vld              ),
        .idx_engine_ctx_rd_req_vq               (idx_engine_ctx_rd_req_qid              ),
        .idx_engine_ctx_rd_rsp_vld              (idx_engine_ctx_rd_rsp_vld              ),
        .idx_engine_ctx_rd_rsp_dev_id           (idx_engine_ctx_rd_rsp_dev_id           ),
        .idx_engine_ctx_rd_rsp_bdf              (idx_engine_ctx_rd_rsp_bdf              ),
        .idx_engine_ctx_rd_rsp_avail_addr       (idx_engine_ctx_rd_rsp_avail_addr       ),
        .idx_engine_ctx_rd_rsp_used_addr        (idx_engine_ctx_rd_rsp_used_addr        ),
        .idx_engine_ctx_rd_rsp_qdepth           (idx_engine_ctx_rd_rsp_qdepth           ),
        .idx_engine_ctx_rd_rsp_ctrl             (idx_engine_ctx_rd_rsp_ctrl             ),
        .idx_engine_ctx_rd_rsp_force_shutdown   (idx_engine_ctx_rd_rsp_force_shutdown   ),
        .idx_engine_ctx_rd_rsp_avail_idx        (idx_engine_ctx_rd_rsp_avail_idx        ),
        .idx_engine_ctx_rd_rsp_avail_ui         (idx_engine_ctx_rd_rsp_avail_ui         ),
        .idx_engine_ctx_rd_rsp_no_notify        (idx_engine_ctx_rd_rsp_no_notify        ),
        .idx_engine_ctx_rd_rsp_no_change        (idx_engine_ctx_rd_rsp_no_change        ),
        .idx_engine_ctx_rd_rsp_dma_req_num      (idx_engine_ctx_rd_rsp_rd_req_num       ),
        .idx_engine_ctx_rd_rsp_dma_rsp_num      (idx_engine_ctx_rd_rsp_rd_rsp_num       ),
        .idx_engine_ctx_wr_vld                  (idx_engine_ctx_wr_vld                  ),
        .idx_engine_ctx_wr_vq                   (idx_engine_ctx_wr_qid                  ),
        .idx_engine_ctx_wr_avail_idx            (idx_engine_ctx_wr_avail_idx            ),
        .idx_engine_ctx_wr_no_notify            (idx_engine_ctx_wr_no_notify            ),
        .idx_engine_ctx_wr_dma_req_num          (idx_engine_ctx_wr_dma_req_num          ),
        .idx_engine_ctx_wr_dma_rsp_num          (idx_engine_ctx_wr_dma_rsp_num          ),
        .err_code_wr_req_vld                    (idx_engine_err_info_wr_req_vld         ),
        .err_code_wr_req_vq                     (idx_engine_err_info_wr_req_qid         ),
        .err_code_wr_req_data                   (idx_engine_err_info_wr_req_dat         ),
        .err_code_wr_req_rdy                    (idx_engine_err_info_wr_req_rdy         ),
        .dfx_slave                              (m_br_if[1]                             )
    );

    virtio_sch #(
        .VQ_WIDTH($bits(virtio_vq_t))
    ) u_virtio_avail_ring_sch (
        .clk            (clk                            ),
        .rst            (rst[1]                            ),
        .sch_req_vld    (avail_ring_notify_vld          ),
        .sch_req_rdy    (avail_ring_notify_rdy          ),
        .sch_req_qid    (avail_ring_notify_vq           ),
        .notify_req_vld (avail_ring_notify_req_vld      ),
        .notify_req_rdy (avail_ring_notify_req_rdy      ),
        .notify_req_qid (avail_ring_notify_req_vq       ),
        .notify_rsp_vld (avail_ring_notify_rsp_vld      ),
        .notify_rsp_rdy (avail_ring_notify_rsp_rdy      ),
        .notify_rsp_qid (avail_ring_notify_rsp_vq       ),
        .notify_rsp_done(avail_ring_notify_rsp_done     ),
        .notify_rsp_cold(avail_ring_notify_rsp_cold     ),
        .hot_weight     (4'h2                           ),
        .cold_weight    (4'h1                           ),
        .dfx_err        (                               ),
        .dfx_status     (                               ),
        .notify_req_cnt (                               ),
        .notify_rsp_cnt (                               )
    );

    virtio_avail_ring #(
        .DATA_WIDTH    (DATA_WIDTH     ),
        .DATA_EMPTY    (EMPTH_WIDTH    ),
        .VIRTIO_Q_NUM  (Q_NUM          ),
        .VIRTIO_Q_WIDTH(Q_WIDTH        )
    ) u_virtio_avail_ring (
        .clk                                        (clk                                                    ),
        .rst                                        (rst[1]                                                    ),
        .notify_req_vld                             (avail_ring_notify_req_vld                              ),
        .notify_req_qid                             (avail_ring_notify_req_vq                               ),
        .notify_req_rdy                             (avail_ring_notify_req_rdy                              ),
        .notify_rsp_vld                             (avail_ring_notify_rsp_vld                              ),
        .notify_rsp_qid                             (avail_ring_notify_rsp_vq                               ),
        .notify_rsp_cold                            (avail_ring_notify_rsp_cold                             ),
        .notify_rsp_done                            (avail_ring_notify_rsp_done                             ),
        .notify_rsp_rdy                             (avail_ring_notify_rsp_rdy                              ),
        .dma_ring_id_rd_req                         (avail_ring_dma_rd_req_if                               ),
        .dma_ring_id_rd_rsp                         (avail_ring_dma_rd_rsp_if                               ),
        .avail_addr_rd_req_vld                      (avail_ring_avail_addr_rd_req_vld                       ),
        .avail_addr_rd_req_qid                      (avail_ring_avail_addr_rd_req_qid                       ),
        .avail_addr_rd_req_rdy                      (avail_ring_avail_addr_rd_req_rdy                       ),
        .avail_addr_rd_rsp_vld                      (avail_ring_avail_addr_rd_rsp_vld                       ),
        .avail_addr_rd_rsp_data                     (avail_ring_avail_addr_rd_rsp_dat                       ),
        .avail_ci_wr_req_vld                        (avail_ring_avail_ci_wr_req_vld                         ),
        .avail_ci_wr_req_data                       (avail_ring_avail_ci_wr_req_dat                         ),
        .avail_ci_wr_req_qid                        (avail_ring_avail_ci_wr_req_qid                         ),
        .avail_ui_wr_req_vld                        (avail_ring_avail_ui_wr_req_vld                         ),
        .avail_ui_wr_req_data                       (avail_ring_avail_ui_wr_req_dat                         ),
        .avail_ui_wr_req_qid                        (avail_ring_avail_ui_wr_req_qid                         ),
        .avail_pi_wr_req_vld                        (avail_ring_avail_pi_wr_req_vld                         ),
        .avail_pi_wr_req_data                       (avail_ring_avail_pi_wr_req_dat                         ),
        .avail_pi_wr_req_qid                        (avail_ring_avail_pi_wr_req_qid                         ),
        .nettx_notify_req_vld                       (nettx_notify_vld                                       ),
        .nettx_notify_req_qid                       (nettx_notify_qid                                       ),
        .nettx_notify_req_rdy                       (nettx_notify_rdy                                       ),
        .blk_notify_req_vld                         (blk_notify_vld                                         ),
        .blk_notify_req_qid                         (blk_notify_qid                                         ),
        .blk_notify_req_rdy                         (blk_notify_rdy                                         ),
        .dma_ctx_info_rd_req_vld                    (avail_ring_dma_ctx_info_rd_req_vld                     ),
        .dma_ctx_info_rd_req_qid                    (avail_ring_dma_ctx_info_rd_req_qid                     ),
        .dma_ctx_info_rd_rsp_vld                    (avail_ring_dma_ctx_info_rd_rsp_vld                     ),
        .dma_ctx_info_rd_rsp_force_shutdown         (avail_ring_dma_ctx_info_rd_rsp_forced_shutdown         ),
        .dma_ctx_info_rd_rsp_ctrl                   (avail_ring_dma_ctx_info_rd_rsp_ctrl                    ),
        .dma_ctx_info_rd_rsp_bdf                    (avail_ring_dma_ctx_info_rd_rsp_bdf                     ),
        .dma_ctx_info_rd_rsp_qdepth                 (avail_ring_dma_ctx_info_rd_rsp_qdepth                  ),
        .dma_ctx_info_rd_rsp_avail_idx              (avail_ring_dma_ctx_info_rd_rsp_avail_idx               ),
        .dma_ctx_info_rd_rsp_avail_ui               (avail_ring_dma_ctx_info_rd_rsp_avail_ui                ),
        .dma_ctx_info_rd_rsp_avail_ci               (avail_ring_dma_ctx_info_rd_rsp_avail_ci                ),
        .netrx_avail_id_req_vld                     (netrx_avail_id_req_vld                                 ),
        .netrx_avail_id_req_data                    (netrx_avail_id_req_vq.qid                              ),
        .netrx_avail_id_req_nid                     (netrx_avail_id_req_nid                                 ),
        .netrx_avail_id_req_rdy                     (netrx_avail_id_req_rdy                                 ),
        .netrx_avail_id_rsp_vld                     (netrx_avail_id_rsp_vld                                 ),
        .netrx_avail_id_rsp_data                    (netrx_avail_id_rsp_dat                                 ),
        .netrx_avail_id_rsp_eop                     (netrx_avail_id_rsp_eop                                 ),
        .netrx_avail_id_rsp_rdy                     (netrx_avail_id_rsp_rdy                                 ),
        .nettx_avail_id_req_vld                     (nettx_avail_id_req_vld                                 ),
        .nettx_avail_id_req_data                    (nettx_avail_id_req_vq.qid                              ),
        .nettx_avail_id_req_nid                     (nettx_avail_id_req_nid                                 ),
        .nettx_avail_id_req_rdy                     (nettx_avail_id_req_rdy                                 ),
        .nettx_avail_id_rsp_vld                     (nettx_avail_id_rsp_vld                                 ),
        .nettx_avail_id_rsp_data                    (nettx_avail_id_rsp_dat                                 ),
        .nettx_avail_id_rsp_eop                     (nettx_avail_id_rsp_eop                                 ),
        .nettx_avail_id_rsp_rdy                     (nettx_avail_id_rsp_rdy                                 ),
        .blk_avail_id_req_vld                       (blk_avail_id_req_vld                                   ),
        .blk_avail_id_req_data                      (blk_avail_id_req_vq                                   ),
        .blk_avail_id_req_nid                       (4'h1                                                    ),
        .blk_avail_id_req_rdy                       (blk_avail_id_req_rdy                                   ),
        .blk_avail_id_rsp_vld                       (blk_avail_id_rsp_vld                                   ),
        .blk_avail_id_rsp_data                      (blk_avail_id_rsp_dat                                   ),
        .blk_avail_id_rsp_eop                       (blk_avail_id_rsp_eop                                   ),
        .blk_avail_id_rsp_rdy                       (blk_avail_id_rsp_rdy                                   ),
        .desc_engine_ctx_info_rd_req_vld            (avail_ring_desc_engine_ctx_info_rd_req_vld             ),
        .desc_engine_ctx_info_rd_req_qid            (avail_ring_desc_engine_ctx_info_rd_req_qid             ),
        .desc_engine_ctx_info_rd_rsp_vld            (avail_ring_desc_engine_ctx_info_rd_rsp_vld             ),
        .desc_engine_ctx_info_rd_rsp_force_shutdown (avail_ring_desc_engine_ctx_info_rd_rsp_forced_shutdown ),
        .desc_engine_ctx_info_rd_rsp_ctrl           (avail_ring_desc_engine_ctx_info_rd_rsp_ctrl            ),
        .desc_engine_ctx_info_rd_rsp_avail_pi       (avail_ring_desc_engine_ctx_info_rd_rsp_avail_pi        ),
        .desc_engine_ctx_info_rd_rsp_avail_idx      (avail_ring_desc_engine_ctx_info_rd_rsp_avail_idx       ),
        .desc_engine_ctx_info_rd_rsp_avail_ui       (avail_ring_desc_engine_ctx_info_rd_rsp_avail_ui        ),
        .desc_engine_ctx_info_rd_rsp_avail_ci       (avail_ring_desc_engine_ctx_info_rd_rsp_avail_ci        ),
        .vq_pending_chk_req_vld                     (vq_pending_chk_req_vld                                 ),
        .vq_pending_chk_req_vq                      (vq_pending_chk_req_vq                                  ),
        .vq_pending_chk_rsp_vld                     (vq_pending_chk_rsp_vld                                 ),
        .vq_pending_chk_rsp_busy                    (vq_pending_chk_rsp_busy                                ),
        .dfx_slave                                  (m_br_if[2]                                             )
    );

    virtio_desc_engine_top #(
        .Q_NUM                    (Q_NUM                    ),
        .Q_WIDTH                  (Q_WIDTH                  ),
        .DEV_ID_NUM               (DEV_ID_NUM               ),
        .DEV_ID_WIDTH             (DEV_ID_WIDTH             ),
        .DATA_WIDTH               (DATA_WIDTH               ),
        .EMPTH_WIDTH              (EMPTH_WIDTH              ),
        .PKT_ID_NUM               (PKT_ID_NUM               ),
        .PKT_ID_WIDTH             (PKT_ID_WIDTH             ),
        .SLOT_NUM                 (NET_SLOT_NUM             ),
        .SLOT_WIDTH               (NET_SLOT_WIDTH           ),
        .BUCKET_NUM               (NET_BUCKET_NUM           ),
        .BUCKET_WIDTH             (NET_BUCKET_WIDTH         ),
        .LINE_NUM                 (LINE_NUM                 ),
        .LINE_WIDTH               (LINE_WIDTH               ),
        .DESC_PER_BUCKET_NUM      (DESC_PER_BUCKET_NUM      ),
        .DESC_PER_BUCKET_WIDTH    (DESC_PER_BUCKET_WIDTH    ),
        .DESC_BUF_DEPTH           (NET_DESC_BUF_DEPTH       ),
        .MAX_CHAIN_SIZE           (MAX_CHAIN_SIZE           ),
        .MAX_BUCKET_PER_SLOT      (MAX_BUCKET_PER_SLOT      ),
        .MAX_BUCKET_PER_SLOT_WIDTH(MAX_BUCKET_PER_SLOT_WIDTH)
    ) u_virtio_desc_engine_top (
        .clk                                        (clk                                                    ),
        .rst                                        (rst[5]                                                    ),
        .net_rx_dma_desc_rd_req_if                  (net_rx_desc_dma_rd_req_if                              ),
        .net_rx_dma_desc_rd_rsp_if                  (net_rx_desc_dma_rd_rsp_if                              ),
        .net_tx_dma_desc_rd_req_if                  (net_tx_desc_dma_rd_req_if                              ),
        .net_tx_dma_desc_rd_rsp_if                  (net_tx_desc_dma_rd_rsp_if                              ),
        .net_rx_alloc_slot_req_vld                  (net_rx_alloc_slot_req_vld                              ),
        .net_rx_alloc_slot_req_rdy                  (net_rx_alloc_slot_req_rdy                              ),
        .net_rx_alloc_slot_req_dev_id               (net_rx_alloc_slot_req_dev_id                           ),
        .net_rx_alloc_slot_req_pkt_id               (net_rx_alloc_slot_req_pkt_id                           ),
        .net_rx_alloc_slot_req_vq                   (net_rx_alloc_slot_req_vq                               ),
        .net_rx_alloc_slot_rsp_vld                  (net_rx_alloc_slot_rsp_vld                              ),
        .net_rx_alloc_slot_rsp_dat                  (net_rx_alloc_slot_rsp_dat                              ),
        .net_rx_alloc_slot_rsp_rdy                  (net_rx_alloc_slot_rsp_rdy                              ),
        .net_tx_alloc_slot_req_vld                  (net_tx_alloc_slot_req_vld                              ),
        .net_tx_alloc_slot_req_rdy                  (net_tx_alloc_slot_req_rdy                              ),
        .net_tx_alloc_slot_req_dev_id               (net_tx_alloc_slot_req_dev_id                           ),
        .net_tx_alloc_slot_req_pkt_id               ('0                                                     ),
        .net_tx_alloc_slot_req_vq                   (net_tx_alloc_slot_req_vq                               ),
        .net_tx_alloc_slot_rsp_vld                  (net_tx_alloc_slot_rsp_vld                              ),
        .net_tx_alloc_slot_rsp_dat                  (net_tx_alloc_slot_rsp_dat                              ),
        .net_tx_alloc_slot_rsp_rdy                  (net_tx_alloc_slot_rsp_rdy                              ),
        .net_rx_avail_id_req_vld                    (netrx_avail_id_req_vld                                 ),
        .net_rx_avail_id_req_nid                    (netrx_avail_id_req_nid                                 ),
        .net_rx_avail_id_req_rdy                    (netrx_avail_id_req_rdy                                 ),
        .net_rx_avail_id_req_vq                     (netrx_avail_id_req_vq                                  ),
        .net_rx_avail_id_rsp_vld                    (netrx_avail_id_rsp_vld                                 ),
        .net_rx_avail_id_rsp_eop                    (netrx_avail_id_rsp_eop                                 ),
        .net_rx_avail_id_rsp_rdy                    (netrx_avail_id_rsp_rdy                                 ),
        .net_rx_avail_id_rsp_dat                    (netrx_avail_id_rsp_dat                                 ),
        .net_tx_avail_id_req_vld                    (nettx_avail_id_req_vld                                 ),
        .net_tx_avail_id_req_nid                    (nettx_avail_id_req_nid                                 ),
        .net_tx_avail_id_req_rdy                    (nettx_avail_id_req_rdy                                 ),
        .net_tx_avail_id_req_vq                     (nettx_avail_id_req_vq                                  ),
        .net_tx_avail_id_rsp_vld                    (nettx_avail_id_rsp_vld                                 ),
        .net_tx_avail_id_rsp_eop                    (nettx_avail_id_rsp_eop                                 ),
        .net_tx_avail_id_rsp_rdy                    (nettx_avail_id_rsp_rdy                                 ),
        .net_tx_avail_id_rsp_dat                    (nettx_avail_id_rsp_dat                                 ),
        .net_rx_desc_rsp_vld                        (net_rx_desc_rsp_vld                                    ),
        .net_rx_desc_rsp_sbd                        (net_rx_desc_rsp_sbd                                    ),
        .net_rx_desc_rsp_sop                        (net_rx_desc_rsp_sop                                    ),
        .net_rx_desc_rsp_eop                        (net_rx_desc_rsp_eop                                    ),
        .net_rx_desc_rsp_dat                        (net_rx_desc_rsp_dat                                    ),
        .net_rx_desc_rsp_rdy                        (net_rx_desc_rsp_rdy                                    ), 
        .net_tx_desc_rsp_vld                        (net_tx_desc_rsp_vld                                    ),
        .net_tx_desc_rsp_sbd                        (net_tx_desc_rsp_sbd                                    ),
        .net_tx_desc_rsp_sop                        (net_tx_desc_rsp_sop                                    ),
        .net_tx_desc_rsp_eop                        (net_tx_desc_rsp_eop                                    ),
        .net_tx_desc_rsp_dat                        (net_tx_desc_rsp_dat                                    ),
        .net_tx_desc_rsp_rdy                        (net_tx_desc_rsp_rdy                                    ), 
        .net_rx_ctx_info_rd_req_vld                 (desc_engine_net_rx_ctx_info_rd_req_vld                 ),
        .net_rx_ctx_info_rd_req_vq                  (desc_engine_net_rx_ctx_info_rd_req_vq                  ),
        .net_rx_ctx_info_rd_rsp_vld                 (desc_engine_net_rx_ctx_info_rd_rsp_vld                 ),
        .net_rx_ctx_info_rd_rsp_desc_tbl_addr       (desc_engine_net_rx_ctx_info_rd_rsp_desc_tbl_addr       ),
        .net_rx_ctx_info_rd_rsp_qdepth              (desc_engine_net_rx_ctx_info_rd_rsp_qdepth              ),
        .net_rx_ctx_info_rd_rsp_forced_shutdown     (desc_engine_net_rx_ctx_info_rd_rsp_forced_shutdown     ),
        .net_rx_ctx_info_rd_rsp_indirct_support     (desc_engine_net_rx_ctx_info_rd_rsp_indirct_support     ),
        .net_rx_ctx_info_rd_rsp_max_len             (desc_engine_net_rx_ctx_info_rd_rsp_max_len             ),
        .net_rx_ctx_info_rd_rsp_bdf                 (desc_engine_net_rx_ctx_info_rd_rsp_bdf                 ),
        .net_rx_ctx_slot_chain_rd_req_vld           (desc_engine_net_rx_ctx_slot_chain_rd_req_vld           ),
        .net_rx_ctx_slot_chain_rd_req_vq            (desc_engine_net_rx_ctx_slot_chain_rd_req_vq            ),
        .net_rx_ctx_slot_chain_rd_rsp_vld           (desc_engine_net_rx_ctx_slot_chain_rd_rsp_vld           ),
        .net_rx_ctx_slot_chain_rd_rsp_head_slot     (desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot     ),
        .net_rx_ctx_slot_chain_rd_rsp_head_slot_vld (desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot_vld ),
        .net_rx_ctx_slot_chain_rd_rsp_tail_slot     (desc_engine_net_rx_ctx_slot_chain_rd_rsp_tail_slot     ),
        .net_rx_ctx_slot_chain_wr_vld               (desc_engine_net_rx_ctx_slot_chain_wr_vld               ),
        .net_rx_ctx_slot_chain_wr_vq                (desc_engine_net_rx_ctx_slot_chain_wr_vq                ),
        .net_rx_ctx_slot_chain_wr_head_slot         (desc_engine_net_rx_ctx_slot_chain_wr_head_slot         ),
        .net_rx_ctx_slot_chain_wr_head_slot_vld     (desc_engine_net_rx_ctx_slot_chain_wr_head_slot_vld     ),
        .net_rx_ctx_slot_chain_wr_tail_slot         (desc_engine_net_rx_ctx_slot_chain_wr_tail_slot         ),
        .net_tx_ctx_info_rd_req_vld                 (desc_engine_net_tx_ctx_info_rd_req_vld                 ),
        .net_tx_ctx_info_rd_req_vq                  (desc_engine_net_tx_ctx_info_rd_req_vq                  ),
        .net_tx_ctx_info_rd_rsp_vld                 (desc_engine_net_tx_ctx_info_rd_rsp_vld                 ),
        .net_tx_ctx_info_rd_rsp_desc_tbl_addr       (desc_engine_net_tx_ctx_info_rd_rsp_desc_tbl_addr       ),
        .net_tx_ctx_info_rd_rsp_qdepth              (desc_engine_net_tx_ctx_info_rd_rsp_qdepth              ),
        .net_tx_ctx_info_rd_rsp_forced_shutdown     (desc_engine_net_tx_ctx_info_rd_rsp_forced_shutdown     ),
        .net_tx_ctx_info_rd_rsp_indirct_support     (desc_engine_net_tx_ctx_info_rd_rsp_indirct_support     ),
        .net_tx_ctx_info_rd_rsp_max_len             (desc_engine_net_tx_ctx_info_rd_rsp_max_len             ),
        .net_tx_ctx_info_rd_rsp_bdf                 (desc_engine_net_tx_ctx_info_rd_rsp_bdf                 ),
        .net_tx_ctx_slot_chain_rd_req_vld           (desc_engine_net_tx_ctx_slot_chain_rd_req_vld           ),
        .net_tx_ctx_slot_chain_rd_req_vq            (desc_engine_net_tx_ctx_slot_chain_rd_req_vq            ),
        .net_tx_ctx_slot_chain_rd_rsp_vld           (desc_engine_net_tx_ctx_slot_chain_rd_rsp_vld           ),
        .net_tx_ctx_slot_chain_rd_rsp_head_slot     (desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot     ),
        .net_tx_ctx_slot_chain_rd_rsp_head_slot_vld (desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot_vld ),
        .net_tx_ctx_slot_chain_rd_rsp_tail_slot     (desc_engine_net_tx_ctx_slot_chain_rd_rsp_tail_slot     ),
        .net_tx_ctx_slot_chain_wr_vld               (desc_engine_net_tx_ctx_slot_chain_wr_vld               ),
        .net_tx_ctx_slot_chain_wr_vq                (desc_engine_net_tx_ctx_slot_chain_wr_vq                ),
        .net_tx_ctx_slot_chain_wr_head_slot         (desc_engine_net_tx_ctx_slot_chain_wr_head_slot         ),
        .net_tx_ctx_slot_chain_wr_head_slot_vld     (desc_engine_net_tx_ctx_slot_chain_wr_head_slot_vld     ),
        .net_tx_ctx_slot_chain_wr_tail_slot         (desc_engine_net_tx_ctx_slot_chain_wr_tail_slot         ),
        .net_tx_limit_per_queue_rd_req_vld          (desc_engine_net_tx_limit_per_queue_rd_req_vld          ),
        .net_tx_limit_per_queue_rd_req_qid          (desc_engine_net_tx_limit_per_queue_rd_req_qid          ),
        .net_tx_limit_per_queue_rd_rsp_vld          (desc_engine_net_tx_limit_per_queue_rd_rsp_vld          ),
        .net_tx_limit_per_queue_rd_rsp_dat          (desc_engine_net_tx_limit_per_queue_rd_rsp_dat          ),
        .net_tx_limit_per_dev_rd_req_vld            (desc_engine_net_tx_limit_per_dev_rd_req_vld            ),
        .net_tx_limit_per_dev_rd_req_dev_id         (desc_engine_net_tx_limit_per_dev_rd_req_dev_id         ),
        .net_tx_limit_per_dev_rd_rsp_vld            (desc_engine_net_tx_limit_per_dev_rd_rsp_vld            ),
        .net_tx_limit_per_dev_rd_rsp_dat            (desc_engine_net_tx_limit_per_dev_rd_rsp_dat            ),
        .dfx_if                                     (m_br_if[3]                                             )
    );

    virtio_rx_buf_top #(
        .DATA_WIDTH  (DATA_WIDTH   ),
        .GEN_WIDTH   (GEN_WIDTH    ),
        .QID_NUM     (Q_NUM        ),
        .UID_NUM     (UID_NUM      ),
        .DEV_NUM     (DEV_ID_NUM   ),
        .EMPTH_WIDTH (EMPTH_WIDTH  ),
        .QID_WIDTH   (Q_WIDTH      ),
        .UID_WIDTH   (UID_WIDTH    ),
        .BKT_FF_DEPTH(PKT_ID_NUM),
        .DEV_WIDTH   (DEV_ID_WIDTH    ) 
    ) u_virtio_rx_buf_top (
        .clk                                                (clk                                        ),
        .rst                                                (rst[4]                                     ),
        .beq2net                                            (beq2net_if                                 ),
        .dfx_if                                             (m_br_if[4]                                 ),
        .drop_info_rd_req_vld                               (net_rx_buf_drop_info_rd_req_vld            ),
        .drop_info_rd_req_qid                               (net_rx_buf_drop_info_rd_req_qid            ),
        .drop_info_rd_rsp_vld                               (net_rx_buf_drop_info_rd_rsp_vld            ),
        .drop_info_rd_rsp_generation                        (net_rx_buf_drop_info_rd_rsp_generation     ),
        .drop_info_rd_rsp_qos_unit                          (net_rx_buf_drop_info_rd_rsp_qos_unit       ),
        .drop_info_rd_rsp_qos_enable                        (net_rx_buf_drop_info_rd_rsp_qos_enable     ),
        .qos_query_req_vld                                  (net_rx_qos_query_req_vld                   ),
        .qos_query_req_rdy                                  (net_rx_qos_query_req_rdy                   ),
        .qos_query_req_uid                                  (net_rx_qos_query_req_uid                   ),
        .qos_query_rsp_vld                                  (net_rx_qos_query_rsp_vld                   ),
        .qos_query_rsp_ok                                   (net_rx_qos_query_rsp_ok                    ),
        .qos_query_rsp_rdy                                  (net_rx_qos_query_rsp_rdy                   ),
        .qos_update_vld                                     (net_rx_qos_update_vld                      ),
        .qos_update_uid                                     (net_rx_qos_update_uid                      ),
        .qos_update_rdy                                     (net_rx_qos_update_rdy                      ),
        .qos_update_len                                     (net_rx_qos_update_len                      ),
        .qos_update_pkt_num                                 (net_rx_qos_update_pkt_num                  ),
        .req_idx_per_queue_rd_req_vld                       (net_rx_buf_req_idx_per_queue_rd_req_vld    ),
        .req_idx_per_queue_rd_req_qid                       (net_rx_buf_req_idx_per_queue_rd_req_qid    ),
        .req_idx_per_queue_rd_rsp_vld                       (net_rx_buf_req_idx_per_queue_rd_rsp_vld    ),
        .req_idx_per_queue_rd_rsp_dev_id                    (net_rx_buf_req_idx_per_queue_rd_rsp_dev_id ),
        .req_idx_per_queue_rd_rsp_idx_limit_per_queue       (net_rx_buf_req_idx_per_queue_rd_rsp_limit  ),
        .req_idx_per_dev_rd_req_vld                         (net_rx_buf_req_idx_per_dev_rd_req_vld      ),
        .req_idx_per_dev_rd_req_dev_id                      (net_rx_buf_req_idx_per_dev_rd_req_dev_id   ),
        .req_idx_per_dev_rd_rsp_vld                         (net_rx_buf_req_idx_per_dev_rd_rsp_vld      ),
        .req_idx_per_dev_rd_rsp_idx_limit_per_dev           (net_rx_buf_req_idx_per_dev_rd_rsp_limit    ),
        .info_out_data                                      (netrx_buf_info_dat                         ),
        .info_out_vld                                       (netrx_buf_info_vld                         ),
        .info_out_rdy                                       (netrx_buf_info_rdy                         ),
        .rd_data_req_vld                                    (netrx_buf_rd_data_req_vld                  ),
        .rd_data_req_rdy                                    (netrx_buf_rd_data_req_rdy                  ),
        .rd_data_req_data                                   (netrx_buf_rd_data_req_dat                  ),
        .rd_data_rsp_data                                   (netrx_buf_rd_data_rsp_dat                  ),
        .rd_data_rsp_sty                                    (netrx_buf_rd_data_rsp_sty                  ),
        .rd_data_rsp_mty                                    (netrx_buf_rd_data_rsp_mty                  ),
        .rd_data_rsp_sop                                    (netrx_buf_rd_data_rsp_sop                  ),
        .rd_data_rsp_eop                                    (netrx_buf_rd_data_rsp_eop                  ),
        .rd_data_rsp_sbd                                    (netrx_buf_rd_data_rsp_sbd                  ),
        .rd_data_rsp_vld                                    (netrx_buf_rd_data_rsp_vld                  ),
        .rd_data_rsp_rdy                                    (netrx_buf_rd_data_rsp_rdy                  )
    );

    virtio_netrx_top #(
        .DATA_WIDTH        (DATA_WIDTH     ),
        .DATA_EMPTY        (EMPTH_WIDTH    ),
        .VIRTIO_Q_NUM      (Q_NUM        ),
        .VIRTIO_Q_WIDTH    (Q_WIDTH      )
    ) u_virtio_netrx_top (
        .clk                                (clk                                        ),
        .rst                                (rst[2]                                        ),
        .netrx_info_vld                     (netrx_buf_info_vld                         ),
        .netrx_info_data                    (netrx_buf_info_dat                         ),
        .netrx_info_rdy                     (netrx_buf_info_rdy                         ),
        .netrx_alloc_slot_req_vld           (net_rx_alloc_slot_req_vld                  ),
        .netrx_alloc_slot_req_data          (net_rx_alloc_slot_req_vq                   ),
        .netrx_alloc_slot_req_dev_id        (net_rx_alloc_slot_req_dev_id               ),
        .netrx_alloc_slot_req_pkt_id        (net_rx_alloc_slot_req_pkt_id               ),
        .netrx_alloc_slot_req_rdy           (net_rx_alloc_slot_req_rdy                  ),
        .netrx_alloc_slot_rsp_vld           (net_rx_alloc_slot_rsp_vld                  ),
        .netrx_alloc_slot_rsp_data          (net_rx_alloc_slot_rsp_dat                  ),
        .netrx_alloc_slot_rsp_rdy           (net_rx_alloc_slot_rsp_rdy                  ),
        .slot_ctrl_dev_id_rd_req_vld        (net_rx_slot_ctrl_dev_id_rd_req_vld         ),
        .slot_ctrl_dev_id_rd_req_qid        (net_rx_slot_ctrl_dev_id_rd_req_qid         ),
        .slot_ctrl_dev_id_rd_rsp_vld        (net_rx_slot_ctrl_dev_id_rd_rsp_vld         ),
        .slot_ctrl_dev_id_rd_rsp_data       (net_rx_slot_ctrl_dev_id_rd_rsp_dat         ),
        .netrx_desc_rsp_rdy                 (net_rx_desc_rsp_rdy                        ),
        .netrx_desc_rsp_vld                 (net_rx_desc_rsp_vld                        ),
        .netrx_desc_rsp_sop                 (net_rx_desc_rsp_sop                        ),
        .netrx_desc_rsp_eop                 (net_rx_desc_rsp_eop                        ),
        .netrx_desc_rsp_sbd                 (net_rx_desc_rsp_sbd                        ),
        .netrx_desc_rsp_data                (net_rx_desc_rsp_dat                        ),
        .rd_data_req_vld                    (netrx_buf_rd_data_req_vld                  ),
        .rd_data_req_data                   (netrx_buf_rd_data_req_dat                  ),
        .rd_data_req_rdy                    (netrx_buf_rd_data_req_rdy                  ),
        .rd_data_rsp_vld                    (netrx_buf_rd_data_rsp_vld                  ),
        .rd_data_rsp_sop                    (netrx_buf_rd_data_rsp_sop                  ),
        .rd_data_rsp_eop                    (netrx_buf_rd_data_rsp_eop                  ),
        .rd_data_rsp_sty                    (netrx_buf_rd_data_rsp_sty                  ),
        .rd_data_rsp_mty                    (netrx_buf_rd_data_rsp_mty                  ),
        .rd_data_rsp_data                   (netrx_buf_rd_data_rsp_dat                  ),
        .rd_data_rsp_rdy                    (netrx_buf_rd_data_rsp_rdy                  ),
        .rd_data_rsp_sbd                    (netrx_buf_rd_data_rsp_sbd                  ),
        .dma_wr_req                         (net_rx_data_dma_wr_req_if                  ),
        .dma_wr_rsp                         (net_rx_data_dma_wr_rsp_if                  ),
        .wr_data_ctx_rd_req_vld             (net_rx_wr_data_ctx_rd_req_vld              ),
        .wr_data_ctx_rd_req_qid             (net_rx_wr_data_ctx_rd_req_qid              ),
        .wr_data_ctx_rd_rsp_vld             (net_rx_wr_data_ctx_rd_rsp_vld              ),
        .wr_data_ctx_rd_rsp_bdf             (net_rx_wr_data_ctx_rd_rsp_bdf              ),
        .wr_data_ctx_rd_rsp_forced_shutdown (net_rx_wr_data_ctx_rd_rsp_forced_shutdown  ),
        .used_info_vld                      (net_rx_used_info_vld                       ),
        .used_info_data                     (net_rx_used_info_dat                       ),
        .used_info_rdy                      (net_rx_used_info_rdy                       ),
        .dfx_slave                          (m_br_if[5]                                 )
    );

    virtio_sch #(
        .VQ_WIDTH(Q_WIDTH)
    ) u_net_tx_sch (
        .clk            (clk                       ),
        .rst            (rst[2]                       ),
        .sch_req_vld    (nettx_notify_vld          ),
        .sch_req_rdy    (nettx_notify_rdy          ),
        .sch_req_qid    (nettx_notify_qid          ),
        .notify_req_vld (nettx_notify_req_vld      ),
        .notify_req_rdy (nettx_notify_req_rdy      ),
        .notify_req_qid (nettx_notify_req_qid      ),
        .notify_rsp_vld (nettx_notify_rsp_vld      ),
        .notify_rsp_rdy (nettx_notify_rsp_rdy      ),
        .notify_rsp_qid (nettx_notify_rsp_qid      ),
        .notify_rsp_done(nettx_notify_rsp_done     ),
        .notify_rsp_cold(nettx_notify_rsp_cold     ),
        .hot_weight     (4'h2                      ),
        .cold_weight    (4'h1                      ),
        .dfx_err        (                          ),
        .dfx_status     (                          ),
        .notify_req_cnt (                          ),
        .notify_rsp_cnt (                          )
    );

    virtio_nettx_top #(
        .DATA_WIDTH    (DATA_WIDTH ),
        .DATA_EMPTY    (EMPTH_WIDTH),
        .VIRTIO_Q_NUM  (Q_NUM      ),
        .VIRTIO_Q_WIDTH(Q_WIDTH    )
    ) u_virtio_nettx_top (
        .clk            (clk                    ),
        .rst            (rst[2]                    ),
        .notify_req_vld (nettx_notify_req_vld   ),
        .notify_req_qid (nettx_notify_req_qid   ),
        .notify_req_rdy (nettx_notify_req_rdy   ),
        .notify_rsp_vld (nettx_notify_rsp_vld   ),
        .notify_rsp_qid (nettx_notify_rsp_qid   ),
        .notify_rsp_cold(nettx_notify_rsp_cold  ),
        .notify_rsp_done(nettx_notify_rsp_done  ),
        .notify_rsp_rdy (nettx_notify_rsp_rdy   ),
        .nettx_alloc_slot_req_vld       (net_tx_alloc_slot_req_vld),
        .nettx_alloc_slot_req_data      (net_tx_alloc_slot_req_vq),
        .nettx_alloc_slot_req_dev_id    (net_tx_alloc_slot_req_dev_id),
        .nettx_alloc_slot_req_rdy       (net_tx_alloc_slot_req_rdy),
        .nettx_alloc_slot_rsp_vld       (net_tx_alloc_slot_rsp_vld),
        .nettx_alloc_slot_rsp_data      (net_tx_alloc_slot_rsp_dat),
        .nettx_alloc_slot_rsp_rdy       (net_tx_alloc_slot_rsp_rdy),
        .slot_ctrl_ctx_info_rd_req_vld        (net_tx_slot_ctrl_ctx_info_rd_req_vld       ),
        .slot_ctrl_ctx_info_rd_req_qid        (net_tx_slot_ctrl_ctx_info_rd_req_qid       ),
        .slot_ctrl_ctx_info_rd_rsp_vld        (net_tx_slot_ctrl_ctx_info_rd_rsp_vld       ),
        .slot_ctrl_ctx_info_rd_rsp_qos_unit   (net_tx_slot_ctrl_ctx_info_rd_rsp_qos_unit  ),
        .slot_ctrl_ctx_info_rd_rsp_qos_enable (net_tx_slot_ctrl_ctx_info_rd_rsp_qos_enable),
        .slot_ctrl_ctx_info_rd_rsp_dev_id     (net_tx_slot_ctrl_ctx_info_rd_rsp_dev_id    ),
        .qos_query_req_vld   (net_tx_qos_query_req_vld ),
        .qos_query_req_uid   (net_tx_qos_query_req_uid ),
        .qos_query_req_rdy   (net_tx_qos_query_req_rdy ),
        .qos_query_rsp_vld   (net_tx_qos_query_rsp_vld ),
        .qos_query_rsp_data  (net_tx_qos_query_rsp_ok  ),
        .qos_query_rsp_rdy   (net_tx_qos_query_rsp_rdy ),
        .qos_update_rdy      (net_tx_qos_update_rdy    ),
        .qos_update_vld      (net_tx_qos_update_vld    ),
        .qos_update_uid      (net_tx_qos_update_uid    ),
        .qos_update_len      (net_tx_qos_update_len    ),
        .qos_update_pkt_num  (net_tx_qos_update_pkt_num),
        .nettx_desc_rsp_rdy  (net_tx_desc_rsp_rdy),
        .nettx_desc_rsp_vld  (net_tx_desc_rsp_vld),
        .nettx_desc_rsp_sop  (net_tx_desc_rsp_sop),
        .nettx_desc_rsp_eop  (net_tx_desc_rsp_eop),
        .nettx_desc_rsp_sbd  (net_tx_desc_rsp_sbd),
        .nettx_desc_rsp_data (net_tx_desc_rsp_dat),
        .rd_data_ctx_info_rd_req_vld            (net_tx_rd_data_ctx_info_rd_req_vld            ),
        .rd_data_ctx_info_rd_req_qid            (net_tx_rd_data_ctx_info_rd_req_vq             ),
        .rd_data_ctx_info_rd_rsp_vld            (net_tx_rd_data_ctx_info_rd_rsp_vld            ),
        .rd_data_ctx_info_rd_rsp_bdf            (net_tx_rd_data_ctx_info_rd_rsp_bdf            ),
        .rd_data_ctx_info_rd_rsp_forced_shutdown(net_tx_rd_data_ctx_info_rd_rsp_forced_shutdown),
        .rd_data_ctx_info_rd_rsp_qos_enable     (net_tx_rd_data_ctx_info_rd_rsp_qos_enable     ),
        .rd_data_ctx_info_rd_rsp_qos_unit       (net_tx_rd_data_ctx_info_rd_rsp_qos_unit       ),
        .rd_data_ctx_info_rd_rsp_tso_en         (net_tx_rd_data_ctx_info_rd_rsp_tso_en         ),
        .rd_data_ctx_info_rd_rsp_csum_en        (net_tx_rd_data_ctx_info_rd_rsp_csum_en        ),
        .rd_data_ctx_info_rd_rsp_gen            (net_tx_rd_data_ctx_info_rd_rsp_generation     ),
        .dma_rd_req(net_tx_data_dma_rd_req_if),
        .dma_rd_rsp(net_tx_data_dma_rd_rsp_if),
        .net2tso_sav        (net2tso_sav    ),
        .net2tso_vld        (net2tso_vld    ),
        .net2tso_sop        (net2tso_sop    ),
        .net2tso_eop        (net2tso_eop    ),
        .net2tso_sty        (net2tso_sty    ),
        .net2tso_mty        (net2tso_mty    ),
        .net2tso_err        (net2tso_err    ),
        .net2tso_data       (net2tso_data   ),
        .net2tso_qid        (net2tso_qid    ),
        .net2tso_len        (net2tso_length ),
        .net2tso_gen        (net2tso_gen    ),
        .net2tso_tso_en     (net2tso_tso_en ),
        .net2tso_csum_en    (net2tso_csum_en),
        .used_info_vld  (net_tx_used_info_vld),
        .used_info_rdy  (net_tx_used_info_rdy),
        .used_info_data (net_tx_used_info_dat),
        .dfx_slave      (m_br_if[6])
    );

    virtio_blk_desc_engine_top #(
        .DATA_WIDTH        (DATA_WIDTH    ),
        .QID_NUM           (Q_NUM         ),
        .QID_WIDTH         (Q_WIDTH       ),
        .SLOT_NUM          (BLK_SLOT_NUM  ),
        .LINE_NUM          (LINE_NUM      ),
        .BUCKET_NUM        (BLK_BUCKET_NUM    )
    ) u_virtio_blk_desc_engine_top (
        .clk(clk),
        .rst(rst[1]),
        .alloc_slot_req_vld (blk_alloc_slot_req_vld),
        .alloc_slot_req_rdy (blk_alloc_slot_req_rdy),
        .alloc_slot_req_vq  (blk_alloc_slot_req_vq ),
        .alloc_slot_rsp_vld (blk_alloc_slot_rsp_vld),
        .alloc_slot_rsp_rdy (blk_alloc_slot_rsp_rdy),
        .alloc_slot_rsp_dat (blk_alloc_slot_rsp_dat),
        .avail_id_req_vld   (blk_avail_id_req_vld),
        .avail_id_req_rdy   (blk_avail_id_req_rdy),
        .avail_id_req_vq    (blk_avail_id_req_vq ),
        .avail_id_rsp_vld   (blk_avail_id_rsp_vld),
        .avail_id_rsp_rdy   (blk_avail_id_rsp_rdy),
        .avail_id_rsp_dat   (blk_avail_id_rsp_dat),
        .desc_dma_rd_req    (blk_desc_dma_rd_req_if),
        .desc_dma_rd_rsp    (blk_desc_dma_rd_rsp_if),
        .blk_desc_vld       (blk_desc_rsp_vld),
        .blk_desc_rdy       (blk_desc_rsp_rdy),
        .blk_desc_sop       (blk_desc_rsp_sop),
        .blk_desc_eop       (blk_desc_rsp_eop),
        .blk_desc_sbd       (blk_desc_rsp_sbd),
        .blk_desc_dat       (blk_desc_rsp_dat),
        .blk_desc_resummer_rd_req_vld(blk_desc_engine_resummer_rd_req_vld),
        .blk_desc_resummer_rd_req_qid(blk_desc_engine_resummer_rd_req_qid),
        .blk_desc_resummer_rd_rsp_vld(blk_desc_engine_resummer_rd_rsp_vld),
        .blk_desc_resummer_rd_rsp_dat(blk_desc_engine_resummer_rd_rsp_dat),
        .blk_desc_resumer_wr_vld     (blk_desc_engine_resumer_wr_vld     ),
        .blk_desc_resumer_wr_qid     (blk_desc_engine_resumer_wr_qid     ),
        .blk_desc_resumer_wr_dat     (blk_desc_engine_resumer_wr_dat     ),
        .blk_desc_global_info_rd_req_vld               (blk_desc_engine_global_info_rd_req_vld             ),
        .blk_desc_global_info_rd_req_qid               (blk_desc_engine_global_info_rd_req_qid             ),
        .blk_desc_global_info_rd_rsp_vld               (blk_desc_engine_global_info_rd_rsp_vld             ),
        .blk_desc_global_info_rd_rsp_bdf               (blk_desc_engine_global_info_rd_rsp_bdf             ),
        .blk_desc_global_info_rd_rsp_forced_shutdown   (blk_desc_engine_global_info_rd_rsp_forced_shutdown ),
        .blk_desc_global_info_rd_rsp_desc_tbl_addr     (blk_desc_engine_global_info_rd_rsp_desc_tbl_addr   ),
        .blk_desc_global_info_rd_rsp_qdepth            (blk_desc_engine_global_info_rd_rsp_qdepth          ),
        .blk_desc_global_info_rd_rsp_indirct_support   (blk_desc_engine_global_info_rd_rsp_indirct_support ),
        .blk_desc_global_info_rd_rsp_segment_size_blk  (blk_desc_engine_global_info_rd_rsp_segment_size_blk),
        .blk_desc_local_info_rd_req_vld                (blk_desc_engine_local_info_rd_req_vld           ),
        .blk_desc_local_info_rd_req_qid                (blk_desc_engine_local_info_rd_req_qid           ),
        .blk_desc_local_info_rd_rsp_vld                (blk_desc_engine_local_info_rd_rsp_vld           ),
        .blk_desc_local_info_rd_rsp_desc_tbl_addr_blk  (blk_desc_engine_local_info_rd_rsp_desc_tbl_addr ),
        .blk_desc_local_info_rd_rsp_desc_tbl_size_blk  (blk_desc_engine_local_info_rd_rsp_desc_tbl_size ),
        .blk_desc_local_info_rd_rsp_desc_tbl_next_blk  (blk_desc_engine_local_info_rd_rsp_desc_tbl_next ),
        .blk_desc_local_info_rd_rsp_desc_tbl_id_blk    (blk_desc_engine_local_info_rd_rsp_desc_tbl_id   ),
        .blk_desc_local_info_rd_rsp_desc_cnt           (blk_desc_engine_local_info_rd_rsp_qid_desc_cnt  ),
        .blk_desc_local_info_rd_rsp_data_len           (blk_desc_engine_local_info_rd_rsp_qid_data_len  ),
        .blk_desc_local_info_rd_rsp_is_indirct         (blk_desc_engine_local_info_rd_rsp_qid_is_indirct),
        .blk_desc_local_info_wr_vld                    (blk_desc_engine_local_info_wr_vld               ),
        .blk_desc_local_info_wr_qid                    (blk_desc_engine_local_info_wr_qid               ),
        .blk_desc_local_info_wr_desc_tbl_addr_blk      (blk_desc_engine_local_info_wr_desc_tbl_addr     ),
        .blk_desc_local_info_wr_desc_tbl_size_blk      (blk_desc_engine_local_info_wr_desc_tbl_size     ),
        .blk_desc_local_info_wr_desc_tbl_next_blk      (blk_desc_engine_local_info_wr_desc_tbl_next     ),
        .blk_desc_local_info_wr_desc_tbl_id_blk        (blk_desc_engine_local_info_wr_desc_tbl_id       ),
        .blk_desc_local_info_wr_desc_cnt               (blk_desc_engine_local_info_wr_qid_desc_cnt      ),
        .blk_desc_local_info_wr_data_len               (blk_desc_engine_local_info_wr_qid_data_len      ),
        .blk_desc_local_info_wr_is_indirct             (blk_desc_engine_local_info_wr_qid_is_indirct    ),
        .dfx_if                                        (m_br_if[7]                                      )
    );

    virtio_sch #(
        .VQ_WIDTH(Q_WIDTH)
    ) u_blk_sch (
        .clk            (clk                        ),
        .rst            (rst[3]                        ),
        .sch_req_vld    (blk_notify_vld             ),
        .sch_req_rdy    (blk_notify_rdy             ),
        .sch_req_qid    (blk_notify_qid             ),
        .notify_req_vld (blk_notify_req_vld         ),
        .notify_req_rdy (blk_notify_req_rdy         ),
        .notify_req_qid (blk_notify_req_qid         ),
        .notify_rsp_vld (blk_notify_rsp_vld         ),
        .notify_rsp_rdy (blk_notify_rsp_rdy         ),
        .notify_rsp_qid (blk_notify_rsp_qid         ),
        .notify_rsp_done(blk_notify_rsp_done        ),
        .notify_rsp_cold(blk_notify_rsp_cold        ),
        .hot_weight     (4'h2                       ),
        .cold_weight    (4'h1                       ),
        .dfx_err        (                           ),
        .dfx_status     (                           ),
        .notify_req_cnt (                           ),
        .notify_rsp_cnt (                           )
    );

    virtio_blk_downstream #(
        .QOS_QUERY_UID_WIDTH(UID_WIDTH  ),
        .VIRTIO_Q_WIDTH     (Q_WIDTH    ),
        .DATA_WIDTH         (DATA_WIDTH )
    ) u_virtio_blk_downstream (
        .clk                         (clk),
        .rst                         (rst[3]),
        .notify_req_vld (blk_notify_req_vld ),
        .notify_req_qid (blk_notify_req_qid ),
        .notify_req_rdy (blk_notify_req_rdy ),
        .notify_rsp_rdy (blk_notify_rsp_rdy ),
        .notify_rsp_vld (blk_notify_rsp_vld ),
        .notify_rsp_qid (blk_notify_rsp_qid ),
        .notify_rsp_cold(blk_notify_rsp_cold),
        .notify_rsp_done(blk_notify_rsp_done),
        .qos_query_req_rdy  (blk_qos_query_req_rdy ),
        .qos_query_req_uid  (blk_qos_query_req_uid ),
        .qos_query_req_vld  (blk_qos_query_req_vld ),
        .qos_query_rsp_vld  (blk_qos_query_rsp_vld ),
        .qos_query_rsp_ok   (blk_qos_query_rsp_ok  ),
        .qos_query_rsp_rdy  (blk_qos_query_rsp_rdy ),
        .qos_update_rdy     (blk_qos_update_rdy    ),
        .qos_update_vld     (blk_qos_update_vld    ),
        .qos_update_uid     (blk_qos_update_uid    ),
        .qos_update_len     (blk_qos_update_len    ),
        .qos_update_pkt_num (blk_qos_update_pkt_num),
        .alloc_slot_req_rdy (blk_alloc_slot_req_rdy),
        .alloc_slot_req_vld (blk_alloc_slot_req_vld),
        .alloc_slot_req_dat (blk_alloc_slot_req_vq ),
        .alloc_slot_rsp_vld (blk_alloc_slot_rsp_vld),
        .alloc_slot_rsp_dat (blk_alloc_slot_rsp_dat),
        .alloc_slot_rsp_rdy (blk_alloc_slot_rsp_rdy),
        .blk_desc_vld       (blk_desc_rsp_vld),
        .blk_desc_sop       (blk_desc_rsp_sop),
        .blk_desc_eop       (blk_desc_rsp_eop),
        .blk_desc_sbd       (blk_desc_rsp_sbd),
        .blk_desc_dat       (blk_desc_rsp_dat),
        .blk_desc_rdy       (blk_desc_rsp_rdy),
        .desc_rd_data_req_if(blk_downstream_data_dma_rd_req_if),
        .desc_rd_data_rsp_if(blk_downstream_data_dma_rd_rsp_if),
        .blk2beq_if         (blk2beq_if),
        .qos_info_rd_req_vld         (blk_down_stream_qos_info_rd_req_vld       ),
        .qos_info_rd_req_qid         (blk_down_stream_qos_info_rd_req_qid       ),
        .qos_info_rd_rsp_vld         (blk_down_stream_qos_info_rd_rsp_vld       ),
        .qos_info_rd_rsp_qos_enable  (blk_down_stream_qos_info_rd_rsp_qos_enable),
        .qos_info_rd_rsp_qos_unit    (blk_down_stream_qos_info_rd_rsp_qos_unit  ),
        .dma_info_rd_req_vld         (blk_down_stream_dma_info_rd_req_vld       ),
        .dma_info_rd_req_qid         (blk_down_stream_dma_info_rd_req_qid       ),
        .dma_info_rd_rsp_vld         (blk_down_stream_dma_info_rd_rsp_vld       ),
        .dma_info_rd_rsp_bdf         (blk_down_stream_dma_info_rd_rsp_bdf       ),
        .dma_info_rd_rsp_forcedown   (blk_down_stream_dma_info_rd_rsp_forcedown ),
        .dma_info_rd_rsp_generation  (blk_down_stream_dma_info_rd_rsp_generation),
        .blk_ds_ptr_rd_req_vld       (blk_down_stream_ptr_rd_req_vld),       
        .blk_ds_ptr_rd_req_qid       (blk_down_stream_ptr_rd_req_qid),
        .blk_ds_ptr_rd_rsp_vld       (blk_down_stream_ptr_rd_rsp_vld),
        .blk_ds_ptr_rd_rsp_dat       (blk_down_stream_ptr_rd_rsp_dat),
        .blk_ds_ptr_wr_vld           (blk_down_stream_ptr_wr_req_vld),
        .blk_ds_ptr_wr_qid           (blk_down_stream_ptr_wr_req_qid),
        .blk_ds_ptr_wr_dat           (blk_down_stream_ptr_wr_req_dat),
        .blk_chain_fst_seg_rd_req_vld               (blk_down_stream_chain_fst_seg_rd_req_vld),
        .blk_chain_fst_seg_rd_req_qid               (blk_down_stream_chain_fst_seg_rd_req_qid),
        .blk_chain_fst_seg_rd_rsp_vld               (blk_down_stream_chain_fst_seg_rd_rsp_vld),
        .blk_chain_fst_seg_rd_rsp_dat               (blk_down_stream_chain_fst_seg_rd_rsp_dat),
        .blk_chain_fst_seg_wr_vld                   (blk_down_stream_chain_fst_seg_wr_vld    ),
        .blk_chain_fst_seg_wr_qid                   (blk_down_stream_chain_fst_seg_wr_qid    ),
        .blk_chain_fst_seg_wr_dat                   (blk_down_stream_chain_fst_seg_wr_dat    ),
        .blk_ds_err_info_wr_rdy                     (blk_ds_err_info_wr_rdy),
        .blk_ds_err_info_wr_vld                     (blk_ds_err_info_wr_vld),
        .blk_ds_err_info_wr_qid                     (blk_ds_err_info_wr_qid),
        .blk_ds_err_info_wr_dat                     (blk_ds_err_info_wr_dat),
        .csr_if                      (m_br_if[8]                                )
    );


    virtio_blk_upstream_top #(
        .Q_NUM      (Q_NUM      ),
        .Q_WIDTH    (Q_WIDTH    ),
        .DATA_WIDTH (DATA_WIDTH ),
        .EMPTH_WIDTH(EMPTH_WIDTH)
    ) u_virtio_blk_upstream_top (
        .clk                                    (clk                            ),
        .rst                                    (rst[3]                            ),
        .beq2blk_if                             (beq2blk_if                     ),
        .dma_data_wr_req_if                     (blk_upstream_data_dma_wr_req_if),
        .dma_data_wr_rsp_if                     (blk_upstream_data_dma_wr_rsp_if),
        .wr_used_info_vld                       (blk_used_info_vld              ),
        .wr_used_info_dat                       (blk_used_info_dat              ),
        .wr_used_info_rdy                       (blk_used_info_rdy              ),
        .blk_upstream_ctx_req_vld               (blk_upstream_ctx_req_vld            ),
        .blk_upstream_ctx_req_qid               (blk_upstream_ctx_req_qid            ), 
        .blk_upstream_ctx_rsp_vld               (blk_upstream_ctx_rsp_vld            ), 
        .blk_upstream_ctx_rsp_forced_shutdown   (blk_upstream_ctx_rsp_forced_shutdown),
        .blk_upstream_ctx_rsp_q_status          (blk_upstream_ctx_rsp_q_status       ),
        .blk_upstream_ctx_rsp_generation        (blk_upstream_ctx_rsp_generation     ),                 
        .blk_upstream_ctx_rsp_dev_id            (blk_upstream_ctx_rsp_dev_id         ), 
        .blk_upstream_ctx_rsp_bdf               (blk_upstream_ctx_rsp_bdf            ), 
        .blk_upstream_ptr_rd_req_vld            (blk_upstream_ptr_rd_req_vld),
        .blk_upstream_ptr_rd_req_qid            (blk_upstream_ptr_rd_req_qid),
        .blk_upstream_ptr_rd_rsp_vld            (blk_upstream_ptr_rd_rsp_vld),
        .blk_upstream_ptr_rd_rsp_dat            (blk_upstream_ptr_rd_rsp_dat),
        .blk_upstream_ptr_wr_req_vld            (blk_upstream_ptr_wr_req_vld),
        .blk_upstream_ptr_wr_req_qid            (blk_upstream_ptr_wr_req_qid),
        .blk_upstream_ptr_wr_req_dat            (blk_upstream_ptr_wr_req_dat),
        .blk_to_beq_cred_fc                     (blk_to_beq_cred_fc         ),
        .mon_send_io_qid                        (blk_upstream_mon_send_io_qid),
        .mon_send_io                            (blk_upstream_mon_send_io    ),
        .dfx_if                                 (m_br_if[9]                  )
    );

    virtio_used_sch u_virtio_used_sch(
        .clk                            (clk                    ),
        .rst                            (rst[6]                    ),
        .blk_upstream_wr_used_info_vld  (blk_used_info_vld      ),
        .blk_upstream_wr_used_info_dat  (blk_used_info_dat      ),
        .blk_upstream_wr_used_info_rdy  (blk_used_info_rdy      ),
        .net_tx_wr_used_info_vld        (net_tx_used_info_vld   ),
        .net_tx_wr_used_info_dat        (net_tx_used_info_dat   ),
        .net_tx_wr_used_info_rdy        (net_tx_used_info_rdy   ), 
        .net_rx_wr_used_info_vld        (net_rx_used_info_vld   ),
        .net_rx_wr_used_info_dat        (net_rx_used_info_dat   ),
        .net_rx_wr_used_info_rdy        (net_rx_used_info_rdy   ), 
        .wr_used_info_vld               (wr_used_info_vld       ),
        .wr_used_info_dat               (wr_used_info_dat       ),
        .wr_used_info_rdy               (wr_used_info_rdy       )
    );

    virtio_used_top #(
        .IRQ_MERGE_UINT_NUM      (IRQ_MERGE_UINT_NUM      ),
        .IRQ_MERGE_UINT_NUM_WIDTH(IRQ_MERGE_UINT_NUM_WIDTH),
        .Q_NUM         (Q_NUM      ),
        .Q_WIDTH       (Q_WIDTH    ),
        .DATA_WIDTH    (DATA_WIDTH ),
        .EMPTH_WIDTH   (EMPTH_WIDTH), 
        .TIME_MAP_WIDTH(TIME_MAP_WIDTH),
        .CLOCK_FREQ_MHZ(CLOCK_FREQ_MHZ),   
        .TIME_STAMP_UNIT_NS(TIME_STAMP_UNIT_NS)
    ) u_virtio_used_top (
        .clk(clk    ),
        .rst(rst[6]    ),
        .wr_used_info_vld(wr_used_info_vld),
        .wr_used_info_dat(wr_used_info_dat),
        .wr_used_info_rdy(wr_used_info_rdy),
        .dma_data_wr_req_if(used_dma_wr_req_if),
        .dma_data_wr_rsp_if(used_dma_wr_rsp_if),
        .err_handle_vld    (used_err_info_wr_vld ),
        .err_handle_qid    (used_err_info_wr_qid ),
        .err_handle_dat    (used_err_info_wr_dat ),
        .err_handle_rdy    (used_err_info_wr_rdy ),
        .set_mask_req_vld  (used_set_mask_req_vld),
        .set_mask_req_qid  (used_set_mask_req_qid),
        .set_mask_req_dat  (used_set_mask_req_dat),
        .set_mask_req_rdy  (used_set_mask_req_rdy),
        .used_ring_irq_req_vld              (used_ring_irq_rd_req_vld            ),
        .used_ring_irq_req_qid              (used_ring_irq_rd_req_qid            ),
        .used_ring_irq_rsp_vld              (used_ring_irq_rd_rsp_vld            ),
        .used_ring_irq_rsp_forced_shutdown  (used_ring_irq_rd_rsp_forced_shutdown),
        .used_ring_irq_rsp_msix_addr        (used_ring_irq_rd_rsp_msix_addr      ),
        .used_ring_irq_rsp_msix_data        (used_ring_irq_rd_rsp_msix_data      ),
        .used_ring_irq_rsp_bdf              (used_ring_irq_rd_rsp_bdf            ),
        .used_ring_irq_rsp_dev_id           (used_ring_irq_rd_rsp_dev_id         ),
        .used_ring_irq_rsp_msix_mask        (used_ring_irq_rd_rsp_msix_mask      ),
        .used_ring_irq_rsp_msix_pending     (used_ring_irq_rd_rsp_msix_pending   ),
        .used_ring_irq_rsp_used_ring_addr   (used_ring_irq_rd_rsp_used_ring_addr ),
        .used_ring_irq_rsp_qdepth           (used_ring_irq_rd_rsp_qdepth         ),
        .used_ring_irq_rsp_msix_enable      (used_ring_irq_rd_rsp_msix_enable    ),
        .used_ring_irq_rsp_q_status         (used_ring_irq_rd_rsp_q_status       ),
        .used_ring_irq_rsp_err_fatal        (used_ring_irq_rd_rsp_err_fatal      ),
        
        .err_fatal_wr_vld                   (used_err_fatal_wr_vld              ),
        .err_fatal_wr_qid                   (used_err_fatal_wr_qid              ),
        .err_fatal_wr_dat                   (used_err_fatal_wr_dat              ),
        .used_elem_ptr_rd_req_vld           (used_elem_ptr_rd_req_vld           ),
        .used_elem_ptr_rd_req_qid           (used_elem_ptr_rd_req_qid           ),
        .used_elem_ptr_rd_rsp_vld           (used_elem_ptr_rd_rsp_vld           ),
        .used_elem_ptr_rd_rsp_dat           (used_elem_ptr_rd_rsp_dat           ),
        .used_elem_ptr_wr_vld               (used_elem_ptr_wr_vld               ),
        .used_elem_ptr_wr_qid               (used_elem_ptr_wr_qid               ),
        .used_elem_ptr_wr_dat               (used_elem_ptr_wr_dat               ),
        .used_idx_wr_vld                    (used_idx_wr_vld                    ),
        .used_idx_wr_qid                    (used_idx_wr_qid                    ),
        .used_idx_wr_dat                    (used_idx_wr_dat                    ),
        .msix_tbl_wr_vld                    (used_msix_tbl_wr_vld               ),
        .msix_tbl_wr_qid                    (used_msix_tbl_wr_qid               ),
        .msix_tbl_wr_mask                   (used_msix_tbl_wr_mask              ),
        .msix_tbl_wr_pending                (used_msix_tbl_wr_pending           ),
        .dma_write_used_idx_irq_flag_wr_vld (used_dma_write_used_idx_irq_flag_wr_vld),
        .dma_write_used_idx_irq_flag_wr_qid (used_dma_write_used_idx_irq_flag_wr_qid),
        .dma_write_used_idx_irq_flag_wr_dat (used_dma_write_used_idx_irq_flag_wr_dat),
        .mon_send_a_irq                     (used_mon_send_a_irq                                    ),
        .mon_send_irq_vq                    (used_mon_send_irq_vq                                   ),
        .msix_aggregation_time_rd_req_vld_net_tx        (msix_aggregation_time_rd_req_vld_net_tx        ),
        .msix_aggregation_time_rd_req_qid_net_tx        (msix_aggregation_time_rd_req_qid_net_tx        ),
        .msix_aggregation_time_rd_rsp_vld_net_tx        (msix_aggregation_time_rd_rsp_vld_net_tx        ),
        .msix_aggregation_time_rd_rsp_dat_net_tx        (msix_aggregation_time_rd_rsp_dat_net_tx        ),       
        .msix_aggregation_threshold_rd_req_vld_net_tx   (msix_aggregation_threshold_rd_req_vld_net_tx   ),
        .msix_aggregation_threshold_rd_req_qid_net_tx   (msix_aggregation_threshold_rd_req_qid_net_tx   ),
        .msix_aggregation_threshold_rd_rsp_vld_net_tx   (msix_aggregation_threshold_rd_rsp_vld_net_tx   ),
        .msix_aggregation_threshold_rd_rsp_dat_net_tx   (msix_aggregation_threshold_rd_rsp_dat_net_tx   ),
        .msix_aggregation_info_rd_req_vld_net_tx        (msix_aggregation_info_rd_req_vld_net_tx        ),
        .msix_aggregation_info_rd_req_qid_net_tx        (msix_aggregation_info_rd_req_qid_net_tx        ),
        .msix_aggregation_info_rd_rsp_vld_net_tx        (msix_aggregation_info_rd_rsp_vld_net_tx        ),
        .msix_aggregation_info_rd_rsp_dat_net_tx        (msix_aggregation_info_rd_rsp_dat_net_tx        ),
        .msix_aggregation_info_wr_vld_net_tx            (msix_aggregation_info_wr_vld_net_tx            ),
        .msix_aggregation_info_wr_qid_net_tx            (msix_aggregation_info_wr_qid_net_tx            ),
        .msix_aggregation_info_wr_dat_net_tx            (msix_aggregation_info_wr_dat_net_tx            ),
        .msix_aggregation_time_rd_req_vld_net_rx        (msix_aggregation_time_rd_req_vld_net_rx        ),
        .msix_aggregation_time_rd_req_qid_net_rx        (msix_aggregation_time_rd_req_qid_net_rx        ),
        .msix_aggregation_time_rd_rsp_vld_net_rx        (msix_aggregation_time_rd_rsp_vld_net_rx        ),
        .msix_aggregation_time_rd_rsp_dat_net_rx        (msix_aggregation_time_rd_rsp_dat_net_rx        ),       
        .msix_aggregation_threshold_rd_req_vld_net_rx   (msix_aggregation_threshold_rd_req_vld_net_rx   ),
        .msix_aggregation_threshold_rd_req_qid_net_rx   (msix_aggregation_threshold_rd_req_qid_net_rx   ),
        .msix_aggregation_threshold_rd_rsp_vld_net_rx   (msix_aggregation_threshold_rd_rsp_vld_net_rx   ),
        .msix_aggregation_threshold_rd_rsp_dat_net_rx   (msix_aggregation_threshold_rd_rsp_dat_net_rx   ),
        .msix_aggregation_info_rd_req_vld_net_rx        (msix_aggregation_info_rd_req_vld_net_rx        ),
        .msix_aggregation_info_rd_req_qid_net_rx        (msix_aggregation_info_rd_req_qid_net_rx        ),
        .msix_aggregation_info_rd_rsp_vld_net_rx        (msix_aggregation_info_rd_rsp_vld_net_rx        ),
        .msix_aggregation_info_rd_rsp_dat_net_rx        (msix_aggregation_info_rd_rsp_dat_net_rx        ),
        .msix_aggregation_info_wr_vld_net_rx            (msix_aggregation_info_wr_vld_net_rx            ),
        .msix_aggregation_info_wr_qid_net_rx            (msix_aggregation_info_wr_qid_net_rx            ),
        .msix_aggregation_info_wr_dat_net_rx            (msix_aggregation_info_wr_dat_net_rx            ),
        .blk_ds_err_info_wr_rdy                         (blk_ds_err_info_wr_rdy                         ),
        .blk_ds_err_info_wr_vld                         (blk_ds_err_info_wr_vld                         ),
        .blk_ds_err_info_wr_qid                         (blk_ds_err_info_wr_qid                         ),
        .blk_ds_err_info_wr_dat                         (blk_ds_err_info_wr_dat                         ),
        .dfx_if                                         (m_br_if[10]                                    )
    );

    assign m_br_enable[ 0] = chn_addr[22:20] != 3'b111 && chn_addr[22:20] != 3'b110;//0x000000 - 0x5fffff 
    assign m_br_enable[ 1] = chn_addr[22:20] == 3'b110 && chn_addr[19:17] == 3'b000;//0x600000 - 0x61ffff
    assign m_br_enable[ 2] = chn_addr[22:20] == 3'b110 && chn_addr[19:17] == 3'b001;//0x620000 - 0x63ffff
    assign m_br_enable[ 3] = chn_addr[22:20] == 3'b110 && chn_addr[19:17] == 3'b010;//0x640000 - 0x65ffff
    assign m_br_enable[ 4] = chn_addr[22:20] == 3'b110 && chn_addr[19:17] == 3'b011;//0x660000 - 0x67ffff
    assign m_br_enable[ 5] = chn_addr[22:20] == 3'b110 && chn_addr[19:17] == 3'b100;//0x680000 - 0x69ffff
    assign m_br_enable[ 6] = chn_addr[22:20] == 3'b110 && chn_addr[19:17] == 3'b101;//0x6a0000 - 0x6bffff 
    assign m_br_enable[ 7] = chn_addr[22:20] == 3'b110 && chn_addr[19:17] == 3'b110;//0x6c0000 - 0x6dffff
    assign m_br_enable[ 8] = chn_addr[22:20] == 3'b110 && chn_addr[19:17] == 3'b111;//0x6e0000 - 0x6fffff
    assign m_br_enable[ 9] = chn_addr[22:20] == 3'b111 && chn_addr[19:17] == 3'b000;//0x700000 - 0x71ffff
    assign m_br_enable[10] = chn_addr[22:20] == 3'b111 && chn_addr[19:17] == 3'b001;//0x720000 - 0x73ffff
    assign m_br_enable[11] = chn_addr[22:20] == 3'b111 && chn_addr[19:17] == 3'b010;//0x740000 - 0x75ffff
    assign m_br_enable[12] = chn_addr[22:20] == 3'b111 && chn_addr[19:17] == 3'b011;//0x760000 - 0x77ffff
    
    mlite_crossbar#(
        .CHN_NUM   (13  ), 
        .ADDR_WIDTH(23  ), 
        .DATA_WIDTH(64  )
    )u_mlite_crossbar(
        .clk            (clk),
        .rst            (rst[0]),
        .chn_enable     (m_br_enable),
        .slave          (csr_if),             
        .master         (m_br_if),   
        .chn_addr       (chn_addr)
    );

    mlite_rsv #(
        .ADDR_WIDTH(17),
        .DATA_WIDTH(64)
    )u_common_dfx_rsv(
        .clk(clk),
        .rst(rst[0]),
        .csr_if(m_br_if[11])
    );

endmodule
