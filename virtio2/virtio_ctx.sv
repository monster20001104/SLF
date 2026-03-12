/******************************************************************************
 * 文件名称 : virtio_ctx.sv
 * 作者名称 : cui naiwan
 * 创建日期 : 2025/09/06
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  09/06     cui naiwan   初始化版本
 ******************************************************************************/
 `include "virtio_define.svh"
 `include "virtio_used_define.svh"
 module virtio_ctx #(
    parameter Q_NUM                          = 256,
    parameter Q_WIDTH                        = $clog2(Q_NUM),
    parameter SLOT_NUM                       = 32,
    parameter SLOT_WIDTH                     = $clog2(SLOT_NUM),
    parameter DEV_ID_NUM                     = 1024,
    parameter DEV_ID_WIDTH                   = $clog2(DEV_ID_NUM),
    parameter QOS_QUERY_UID_WIDTH            = 10,
    parameter UID_DEPTH                      = 1024,
    parameter UID_WIDTH                      = $clog2(UID_DEPTH),
    parameter GEN_WIDTH                      = 8,
    parameter IRQ_MERGE_UINT_NUM             = 8,
    parameter IRQ_MERGE_UINT_NUM_WIDTH       = $clog2(IRQ_MERGE_UINT_NUM),
    parameter TIME_MAP_WIDTH                 = 2
 )(
    input  logic                                                clk,
    input  logic                                                rst,
    
    //=================form or to idx_engine module===================//
    input  logic                                                idx_engine_err_info_wr_req_vld,
    input  virtio_vq_t                                          idx_engine_err_info_wr_req_qid,
    input  virtio_err_info_t                                    idx_engine_err_info_wr_req_dat,
    output logic                                                idx_engine_err_info_wr_req_rdy,

    input  logic                                                idx_engine_ctx_rd_req_vld,
    input  virtio_vq_t                                          idx_engine_ctx_rd_req_qid,
    output logic                                                idx_engine_ctx_rd_rsp_vld,
    output logic [DEV_ID_WIDTH-1:0]                             idx_engine_ctx_rd_rsp_dev_id,
    output logic [15:0]                                         idx_engine_ctx_rd_rsp_bdf,
    output logic [63:0]                                         idx_engine_ctx_rd_rsp_avail_addr,
    output logic [63:0]                                         idx_engine_ctx_rd_rsp_used_addr,
    output logic [3:0]                                          idx_engine_ctx_rd_rsp_qdepth,
    output virtio_qstat_t                                       idx_engine_ctx_rd_rsp_ctrl,
    output logic                                                idx_engine_ctx_rd_rsp_force_shutdown,
    output logic [15:0]                                         idx_engine_ctx_rd_rsp_avail_idx,
    output logic [15:0]                                         idx_engine_ctx_rd_rsp_avail_ui,
    output logic                                                idx_engine_ctx_rd_rsp_no_notify,
    output logic                                                idx_engine_ctx_rd_rsp_no_change,
    output logic [6:0]                                          idx_engine_ctx_rd_rsp_dma_req_num,
    output logic [6:0]                                          idx_engine_ctx_rd_rsp_dma_rsp_num,
    
    input logic                                                 idx_engine_ctx_wr_vld,
    input virtio_vq_t                                           idx_engine_ctx_wr_qid,
    input logic [15:0]                                          idx_engine_ctx_wr_avail_idx,
    input logic                                                 idx_engine_ctx_wr_no_notify,
    input logic                                                 idx_engine_ctx_wr_no_change,
    input logic [6:0]                                           idx_engine_ctx_wr_dma_req_num,
    input logic [6:0]                                           idx_engine_ctx_wr_dma_rsp_num,
    
    //=================from or to avail_ring module=========================//
    input  logic                                                avail_ring_dma_ctx_info_rd_req_vld,
    input  virtio_vq_t                                          avail_ring_dma_ctx_info_rd_req_qid,              
    output logic                                                avail_ring_dma_ctx_info_rd_rsp_vld,
    output logic                                                avail_ring_dma_ctx_info_rd_rsp_forced_shutdown,
    output virtio_qstat_t                                       avail_ring_dma_ctx_info_rd_rsp_ctrl,
    output logic [15:0]                                         avail_ring_dma_ctx_info_rd_rsp_bdf,
    output logic [3:0]                                          avail_ring_dma_ctx_info_rd_rsp_qdepth,
    output logic [15:0]                                         avail_ring_dma_ctx_info_rd_rsp_avail_idx,
    output logic [15:0]                                         avail_ring_dma_ctx_info_rd_rsp_avail_ui,
    output logic [15:0]                                         avail_ring_dma_ctx_info_rd_rsp_avail_ci,
                            
    input  logic                                                avail_ring_desc_engine_ctx_info_rd_req_vld,
    input  virtio_vq_t                                          avail_ring_desc_engine_ctx_info_rd_req_qid,
    output logic                                                avail_ring_desc_engine_ctx_info_rd_rsp_vld,
    output logic                                                avail_ring_desc_engine_ctx_info_rd_rsp_forced_shutdown,
    output virtio_qstat_t                                       avail_ring_desc_engine_ctx_info_rd_rsp_ctrl,
    output logic [15:0]                                         avail_ring_desc_engine_ctx_info_rd_rsp_avail_pi,
    output logic [15:0]                                         avail_ring_desc_engine_ctx_info_rd_rsp_avail_idx,
    output logic [15:0]                                         avail_ring_desc_engine_ctx_info_rd_rsp_avail_ui,
    output logic [15:0]                                         avail_ring_desc_engine_ctx_info_rd_rsp_avail_ci,
            
    input  logic                                                avail_ring_avail_addr_rd_req_vld,
    input  virtio_vq_t                                          avail_ring_avail_addr_rd_req_qid,
    output logic                                                avail_ring_avail_addr_rd_req_rdy,
    output logic                                                avail_ring_avail_addr_rd_rsp_vld,
    output logic [63:0]                                         avail_ring_avail_addr_rd_rsp_dat,
                
    input  logic                                                avail_ring_avail_ci_wr_req_vld,
    input  logic [15:0]                                         avail_ring_avail_ci_wr_req_dat,
    input  virtio_vq_t                                          avail_ring_avail_ci_wr_req_qid,
              
    input  logic                                                avail_ring_avail_ui_wr_req_vld,
    input  logic [15:0]                                         avail_ring_avail_ui_wr_req_dat,
    input  virtio_vq_t                                          avail_ring_avail_ui_wr_req_qid,
            
    input  logic                                                avail_ring_avail_pi_wr_req_vld,
    input  logic [15:0]                                         avail_ring_avail_pi_wr_req_dat,
    input  virtio_vq_t                                          avail_ring_avail_pi_wr_req_qid,

    output logic                                                vq_pending_chk_req_vld,
    output virtio_vq_t                                          vq_pending_chk_req_vq,
    input  logic                                                vq_pending_chk_rsp_vld,
    input  logic                                                vq_pending_chk_rsp_busy,

    //===================from or to desc_engine module===================================//
    input  logic                                                desc_engine_net_rx_ctx_info_rd_req_vld,
    input  virtio_vq_t                                          desc_engine_net_rx_ctx_info_rd_req_vq,
    output logic                                                desc_engine_net_rx_ctx_info_rd_rsp_vld,
    output logic [63:0]                                         desc_engine_net_rx_ctx_info_rd_rsp_desc_tbl_addr,
    output logic [3:0]                                          desc_engine_net_rx_ctx_info_rd_rsp_qdepth,
    output logic                                                desc_engine_net_rx_ctx_info_rd_rsp_forced_shutdown,
    output logic                                                desc_engine_net_rx_ctx_info_rd_rsp_indirct_support,
    output logic [19:0]                                         desc_engine_net_rx_ctx_info_rd_rsp_max_len,
    output logic [15:0]                                         desc_engine_net_rx_ctx_info_rd_rsp_bdf,
    input  logic                                                desc_engine_net_rx_ctx_slot_chain_rd_req_vld,
    input  virtio_vq_t                                          desc_engine_net_rx_ctx_slot_chain_rd_req_vq,
    output logic                                                desc_engine_net_rx_ctx_slot_chain_rd_rsp_vld,
    output logic [SLOT_WIDTH-1:0]                               desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot,
    output logic                                                desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot_vld,
    output logic [SLOT_WIDTH-1:0]                               desc_engine_net_rx_ctx_slot_chain_rd_rsp_tail_slot,
    input  logic                                                desc_engine_net_rx_ctx_slot_chain_wr_vld,
    input  virtio_vq_t                                          desc_engine_net_rx_ctx_slot_chain_wr_vq,
    input  logic [SLOT_WIDTH-1:0]                               desc_engine_net_rx_ctx_slot_chain_wr_head_slot,
    input  logic                                                desc_engine_net_rx_ctx_slot_chain_wr_head_slot_vld,
    input  logic [SLOT_WIDTH-1:0]                               desc_engine_net_rx_ctx_slot_chain_wr_tail_slot,

    input  logic                                                desc_engine_net_tx_ctx_info_rd_req_vld,
    input  virtio_vq_t                                          desc_engine_net_tx_ctx_info_rd_req_vq,
    output logic                                                desc_engine_net_tx_ctx_info_rd_rsp_vld,
    output logic [63:0]                                         desc_engine_net_tx_ctx_info_rd_rsp_desc_tbl_addr,
    output logic [3:0]                                          desc_engine_net_tx_ctx_info_rd_rsp_qdepth,
    output logic                                                desc_engine_net_tx_ctx_info_rd_rsp_forced_shutdown,
    output logic                                                desc_engine_net_tx_ctx_info_rd_rsp_indirct_support,
    output logic [19:0]                                         desc_engine_net_tx_ctx_info_rd_rsp_max_len,
    output logic [15:0]                                         desc_engine_net_tx_ctx_info_rd_rsp_bdf,
    input  logic                                                desc_engine_net_tx_ctx_slot_chain_rd_req_vld,
    input  virtio_vq_t                                          desc_engine_net_tx_ctx_slot_chain_rd_req_vq,
    output logic                                                desc_engine_net_tx_ctx_slot_chain_rd_rsp_vld,
    output logic [SLOT_WIDTH-1:0]                               desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot,
    output logic                                                desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot_vld,
    output logic [SLOT_WIDTH-1:0]                               desc_engine_net_tx_ctx_slot_chain_rd_rsp_tail_slot,
    input  logic                                                desc_engine_net_tx_ctx_slot_chain_wr_vld,
    input  virtio_vq_t                                          desc_engine_net_tx_ctx_slot_chain_wr_vq,
    input  logic [SLOT_WIDTH-1:0]                               desc_engine_net_tx_ctx_slot_chain_wr_head_slot,
    input  logic                                                desc_engine_net_tx_ctx_slot_chain_wr_head_slot_vld,
    input  logic [SLOT_WIDTH-1:0]                               desc_engine_net_tx_ctx_slot_chain_wr_tail_slot,

    input  logic                                                desc_engine_net_tx_limit_per_queue_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  desc_engine_net_tx_limit_per_queue_rd_req_qid,
    output logic                                                desc_engine_net_tx_limit_per_queue_rd_rsp_vld,
    output logic [7:0]                                          desc_engine_net_tx_limit_per_queue_rd_rsp_dat,
    input  logic                                                desc_engine_net_tx_limit_per_dev_rd_req_vld,
    input  logic [DEV_ID_WIDTH-1:0]                             desc_engine_net_tx_limit_per_dev_rd_req_dev_id,
    output logic                                                desc_engine_net_tx_limit_per_dev_rd_rsp_vld,
    output logic [7:0]                                          desc_engine_net_tx_limit_per_dev_rd_rsp_dat,
    
    //=============================from or to blk_desc_engine module================================//
    input  logic                                                blk_desc_engine_resumer_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_desc_engine_resumer_rd_req_qid,
    output logic                                                blk_desc_engine_resumer_rd_rsp_vld,
    output logic                                                blk_desc_engine_resumer_rd_rsp_dat,
                                   
    input  logic                                                blk_desc_engine_resumer_wr_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_desc_engine_resumer_wr_qid,
    input  logic                                                blk_desc_engine_resumer_wr_dat,
                                   
    input  logic                                                blk_desc_engine_global_info_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_desc_engine_global_info_rd_req_qid,
                                   
    output logic                                                blk_desc_engine_global_info_rd_rsp_vld,
    output logic [15:0]                                         blk_desc_engine_global_info_rd_rsp_bdf,
    output logic                                                blk_desc_engine_global_info_rd_rsp_forced_shutdown,
    output logic [63:0]                                         blk_desc_engine_global_info_rd_rsp_desc_tbl_addr,
    output logic [3:0]                                          blk_desc_engine_global_info_rd_rsp_qdepth,
    output logic                                                blk_desc_engine_global_info_rd_rsp_indirct_support,
    output logic [19:0]                                         blk_desc_engine_global_info_rd_rsp_segment_size_blk,
                                   
    input  logic                                                blk_desc_engine_local_info_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_desc_engine_local_info_rd_req_qid,
                                  
    output logic                                                blk_desc_engine_local_info_rd_rsp_vld,
    output logic [63:0]                                         blk_desc_engine_local_info_rd_rsp_desc_tbl_addr,
    output logic [31:0]                                         blk_desc_engine_local_info_rd_rsp_desc_tbl_size,
    output logic [15:0]                                         blk_desc_engine_local_info_rd_rsp_desc_tbl_next,
    output logic [15:0]                                         blk_desc_engine_local_info_rd_rsp_desc_tbl_id,
    output logic [19:0]                                         blk_desc_engine_local_info_rd_rsp_desc_cnt,
    output logic [20:0]                                         blk_desc_engine_local_info_rd_rsp_data_len,
    output logic                                                blk_desc_engine_local_info_rd_rsp_is_indirct,
                                  
    input  logic                                                blk_desc_engine_local_info_wr_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_desc_engine_local_info_wr_qid,
    input  logic [63:0]                                         blk_desc_engine_local_info_wr_desc_tbl_addr,
    input  logic [31:0]                                         blk_desc_engine_local_info_wr_desc_tbl_size,
    input  logic [15:0]                                         blk_desc_engine_local_info_wr_desc_tbl_next,
    input  logic [15:0]                                         blk_desc_engine_local_info_wr_desc_tbl_id,
    input  logic [19:0]                                         blk_desc_engine_local_info_wr_desc_cnt,
    input  logic [20:0]                                         blk_desc_engine_local_info_wr_data_len,
    input  logic                                                blk_desc_engine_local_info_wr_is_indirct,

    //=========================from or to blk_down_stream module===============================//
    input  logic                                                blk_down_stream_ptr_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_down_stream_ptr_rd_req_qid,
    output logic                                                blk_down_stream_ptr_rd_rsp_vld,
    output logic [15:0]                                         blk_down_stream_ptr_rd_rsp_dat,

    input  logic                                                blk_down_stream_ptr_wr_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_down_stream_ptr_wr_req_qid,
    input  logic [15:0]                                         blk_down_stream_ptr_wr_req_dat,

    input  logic                                                blk_down_stream_qos_info_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_down_stream_qos_info_rd_req_qid,
    output logic                                                blk_down_stream_qos_info_rd_rsp_vld,
    output logic                                                blk_down_stream_qos_info_rd_rsp_qos_enable,
    output logic [QOS_QUERY_UID_WIDTH-1:0]                      blk_down_stream_qos_info_rd_rsp_qos_unit,
            
    input  logic                                                blk_down_stream_dma_info_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_down_stream_dma_info_rd_req_qid,
    output logic                                                blk_down_stream_dma_info_rd_rsp_vld,
    output logic [15:0]                                         blk_down_stream_dma_info_rd_rsp_bdf,
    output logic                                                blk_down_stream_dma_info_rd_rsp_forcedown,
    output logic [7:0]                                          blk_down_stream_dma_info_rd_rsp_generation,

    input  logic                                                blk_down_stream_chain_fst_seg_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_down_stream_chain_fst_seg_rd_req_qid,
    output logic                                                blk_down_stream_chain_fst_seg_rd_rsp_vld,
    output logic                                                blk_down_stream_chain_fst_seg_rd_rsp_dat,
    input  logic                                                blk_down_stream_chain_fst_seg_wr_vld    ,
    input  logic [Q_WIDTH-1:0]                                  blk_down_stream_chain_fst_seg_wr_qid    ,
    input  logic                                                blk_down_stream_chain_fst_seg_wr_dat    ,

    //=============================from or to blk_upstream module===============================//
    input  logic                                                blk_upstream_ctx_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_upstream_ctx_req_qid,     
    output logic                                                blk_upstream_ctx_rsp_vld, 
    output logic                                                blk_upstream_ctx_rsp_forced_shutdown,
    output virtio_qstat_t                                       blk_upstream_ctx_rsp_q_status,
    output logic [7:0]                                          blk_upstream_ctx_rsp_generation,                  
    output logic [DEV_ID_WIDTH-1:0]                             blk_upstream_ctx_rsp_dev_id, 
    output logic [15:0]                                         blk_upstream_ctx_rsp_bdf, 

    input  logic                                                blk_upstream_ptr_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_upstream_ptr_rd_req_qid,
    output logic                                                blk_upstream_ptr_rd_rsp_vld,
    output logic [15:0]                                         blk_upstream_ptr_rd_rsp_dat,

    input  logic                                                blk_upstream_ptr_wr_req_vld,
    input  logic [Q_WIDTH-1:0]                                  blk_upstream_ptr_wr_req_qid,
    input  logic [15:0]                                         blk_upstream_ptr_wr_req_dat,
                    
    input  virtio_vq_t                                          blk_upstream_mon_send_io_qid,
    input  logic                                                blk_upstream_mon_send_io,

    //===========================from or to net_tx module=======================================//
    input  logic                                                net_tx_slot_ctrl_ctx_info_rd_req_vld,
    input  virtio_vq_t                                          net_tx_slot_ctrl_ctx_info_rd_req_qid,
                        
    output logic                                                net_tx_slot_ctrl_ctx_info_rd_rsp_vld,
    output logic [Q_WIDTH+1:0]                                  net_tx_slot_ctrl_ctx_info_rd_rsp_qos_unit,
    output logic                                                net_tx_slot_ctrl_ctx_info_rd_rsp_qos_enable,
    output logic [DEV_ID_WIDTH-1:0]                             net_tx_slot_ctrl_ctx_info_rd_rsp_dev_id,

    input  logic                                                net_tx_rd_data_ctx_info_rd_req_vld,
    input  virtio_vq_t                                          net_tx_rd_data_ctx_info_rd_req_qid,
                       
    output logic                                                net_tx_rd_data_ctx_info_rd_rsp_vld,
    output logic [15:0]                                         net_tx_rd_data_ctx_info_rd_rsp_bdf,
    output logic                                                net_tx_rd_data_ctx_info_rd_rsp_forced_shutdown,
    output logic                                                net_tx_rd_data_ctx_info_rd_rsp_qos_enable,
    output logic [Q_WIDTH+1:0]                                  net_tx_rd_data_ctx_info_rd_rsp_qos_unit,
    output logic                                                net_tx_rd_data_ctx_info_rd_rsp_tso_en,
    output logic                                                net_tx_rd_data_ctx_info_rd_rsp_csum_en,
    output logic [7:0]                                          net_tx_rd_data_ctx_info_rd_rsp_generation,

    //============================from or to net_rx module=======================================//
    input  logic                                                net_rx_slot_ctrl_dev_id_rd_req_vld,
    input  virtio_vq_t                                          net_rx_slot_ctrl_dev_id_rd_req_qid,                  
    output logic                                                net_rx_slot_ctrl_dev_id_rd_rsp_vld,
    output logic [DEV_ID_WIDTH-1:0]                             net_rx_slot_ctrl_dev_id_rd_rsp_dat,
    
    input  logic                                                net_rx_wr_data_ctx_rd_req_vld,
    input  virtio_vq_t                                          net_rx_wr_data_ctx_rd_req_qid,         
    output logic                                                net_rx_wr_data_ctx_rd_rsp_vld,
    output logic [15:0]                                         net_rx_wr_data_ctx_rd_rsp_bdf,
    output logic                                                net_rx_wr_data_ctx_rd_rsp_forced_shutdown,

    //=============================from or to net_rx_buf module==================================//
    input  logic                                                net_rx_buf_drop_info_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  net_rx_buf_drop_info_rd_req_qid,
    output logic                                                net_rx_buf_drop_info_rd_rsp_vld,
    output logic [GEN_WIDTH-1:0]                                net_rx_buf_drop_info_rd_rsp_generation,
    output logic [UID_WIDTH-1:0]                                net_rx_buf_drop_info_rd_rsp_qos_unit,
    output logic                                                net_rx_buf_drop_info_rd_rsp_qos_enable,
    
    input  logic                                                net_rx_buf_req_idx_per_queue_rd_req_vld,
    input  logic [Q_WIDTH-1:0]                                  net_rx_buf_req_idx_per_queue_rd_req_qid,
    output logic                                                net_rx_buf_req_idx_per_queue_rd_rsp_vld,
    output logic [DEV_ID_WIDTH-1:0]                             net_rx_buf_req_idx_per_queue_rd_rsp_dev_id,
    output logic [7:0]                                          net_rx_buf_req_idx_per_queue_rd_rsp_limit,
    
    input  logic                                                net_rx_buf_req_idx_per_dev_rd_req_vld,
    input  logic [DEV_ID_WIDTH-1:0]                             net_rx_buf_req_idx_per_dev_rd_req_dev_id,
    output logic                                                net_rx_buf_req_idx_per_dev_rd_rsp_vld,
    output logic [7:0]                                          net_rx_buf_req_idx_per_dev_rd_rsp_limit,

    //===============================from or to used module==========================================//
    input  logic                                                used_ring_irq_rd_req_vld,
    input  virtio_vq_t                                          used_ring_irq_rd_req_qid,
    output logic                                                used_ring_irq_rd_rsp_vld,
    output logic                                                used_ring_irq_rd_rsp_forced_shutdown,
    output logic [63:0]                                         used_ring_irq_rd_rsp_msix_addr,
    output logic [31:0]                                         used_ring_irq_rd_rsp_msix_data,
    output logic [15:0]                                         used_ring_irq_rd_rsp_bdf,
    output logic [DEV_ID_WIDTH-1:0]                             used_ring_irq_rd_rsp_dev_id,
    output logic                                                used_ring_irq_rd_rsp_msix_mask,
    output logic                                                used_ring_irq_rd_rsp_msix_pending,
    output logic [63:0]                                         used_ring_irq_rd_rsp_used_ring_addr,
    output logic [3:0]                                          used_ring_irq_rd_rsp_qdepth,
    output logic                                                used_ring_irq_rd_rsp_msix_enable,
    output virtio_qstat_t                                       used_ring_irq_rd_rsp_q_status,
    output logic                                                used_ring_irq_rd_rsp_err_fatal,
 
    input  logic                                                used_err_fatal_wr_vld,
    input  virtio_vq_t                                          used_err_fatal_wr_qid,
    input  logic                                                used_err_fatal_wr_dat,
           
    input  logic                                                used_elem_ptr_rd_req_vld,
    input  virtio_vq_t                                          used_elem_ptr_rd_req_qid,
    output logic                                                used_elem_ptr_rd_rsp_vld,
    output logic [$bits(virtio_used_elem_ptr_info_t)-1:0]       used_elem_ptr_rd_rsp_dat,
           
    input  logic                                                used_elem_ptr_wr_vld,
    input  virtio_vq_t                                          used_elem_ptr_wr_qid,
    input  logic [$bits(virtio_used_elem_ptr_info_t)-1:0]       used_elem_ptr_wr_dat,
           
    input  logic                                                used_idx_wr_vld,
    input  virtio_vq_t                                          used_idx_wr_qid,
    input  logic [15:0]                                         used_idx_wr_dat,
               
    input  logic                                                used_msix_tbl_wr_vld,
    input  virtio_vq_t                                          used_msix_tbl_wr_qid,
    input  logic                                                used_msix_tbl_wr_mask,
    input  logic                                                used_msix_tbl_wr_pending,

    input  logic                                                msix_aggregation_time_rd_req_vld_net_tx,
    input  logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_time_rd_req_qid_net_tx,               
    output logic                                                msix_aggregation_time_rd_rsp_vld_net_tx,
    output logic [IRQ_MERGE_UINT_NUM*3-1:0]                     msix_aggregation_time_rd_rsp_dat_net_tx,       
           
    input  logic                                                msix_aggregation_threshold_rd_req_vld_net_tx,
    input  logic [Q_WIDTH-1:0]                                  msix_aggregation_threshold_rd_req_qid_net_tx,
    output logic                                                msix_aggregation_threshold_rd_rsp_vld_net_tx,
    output logic [6:0]                                          msix_aggregation_threshold_rd_rsp_dat_net_tx,
                         
    input  logic                                                msix_aggregation_info_rd_req_vld_net_tx,
    input  logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_info_rd_req_qid_net_tx,
    output logic                                                msix_aggregation_info_rd_rsp_vld_net_tx,
    output logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0]    msix_aggregation_info_rd_rsp_dat_net_tx,               
    input  logic                                                msix_aggregation_info_wr_vld_net_tx,
    input  logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_info_wr_qid_net_tx,
    input  logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0]    msix_aggregation_info_wr_dat_net_tx,
           
    input  logic                                                msix_aggregation_time_rd_req_vld_net_rx,
    input  logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_time_rd_req_qid_net_rx,                 
    output logic                                                msix_aggregation_time_rd_rsp_vld_net_rx,
    output logic [IRQ_MERGE_UINT_NUM*3-1:0]                     msix_aggregation_time_rd_rsp_dat_net_rx,       
           
    input  logic                                                msix_aggregation_threshold_rd_req_vld_net_rx,
    input  logic [Q_WIDTH-1:0]                                  msix_aggregation_threshold_rd_req_qid_net_rx,
    output logic                                                msix_aggregation_threshold_rd_rsp_vld_net_rx,
    output logic [6:0]                                          msix_aggregation_threshold_rd_rsp_dat_net_rx,
                          
    input  logic                                                msix_aggregation_info_rd_req_vld_net_rx,
    input  logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_info_rd_req_qid_net_rx,
    output logic                                                msix_aggregation_info_rd_rsp_vld_net_rx,
    output logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0]    msix_aggregation_info_rd_rsp_dat_net_rx,               
    input  logic                                                msix_aggregation_info_wr_vld_net_rx,
    input  logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]       msix_aggregation_info_wr_qid_net_rx,
    input  logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0]    msix_aggregation_info_wr_dat_net_rx,

    input  logic                                                used_err_info_wr_vld,
    input  virtio_vq_t                                          used_err_info_wr_qid,
    input  virtio_err_info_t                                    used_err_info_wr_dat,
    output logic                                                used_err_info_wr_rdy,
               
    output logic                                                used_set_mask_req_vld,
    output virtio_vq_t                                          used_set_mask_req_qid,
    output logic                                                used_set_mask_req_dat,
    input  logic                                                used_set_mask_req_rdy,

    input  logic                                                used_dma_write_used_idx_irq_flag_wr_vld,
    input  virtio_vq_t                                          used_dma_write_used_idx_irq_flag_wr_qid,
    input  logic                                                used_dma_write_used_idx_irq_flag_wr_dat,

    input  logic                                                mon_send_a_irq,
    input  virtio_vq_t                                          mon_send_irq_vq,

    //============================from or to db_sch module===========================//
    output logic                                                soc_notify_req_vld,
    output virtio_vq_t                                          soc_notify_req_qid,
    input  logic                                                soc_notify_req_rdy,

    mlite_if.slave                                              csr_if,
    mlite_if.slave                                              dfx_if

 );

    localparam ERR_INFO_WIDTH = $bits(virtio_err_info_t);
    localparam VQ_WIDTH = $bits(virtio_vq_t);
    localparam MSIX_BLK_WIDTH = TIME_MAP_WIDTH+8;
    localparam MSIX_TIME_WIDTH = 3;
 
    typedef struct packed{
       logic          forced_shutdown;
       virtio_qstat_t q_status;
    } virtio_ctrl_info_t;
 
    logic [21:0] csr_if_addr;
    logic [63:0] csr_if_wdata, csr_if_rdata;
    logic csr_if_read;
    
    logic ctrl_ram_flush, desc_engine_net_tx_ctrl_ram_flush, flush_idx_limit_per_dev;
    logic [VQ_WIDTH-1:0] ctrl_ram_flush_id;
    logic [Q_WIDTH-1:0] desc_engine_net_tx_ctrl_ram_flush_id;
    logic [DEV_ID_WIDTH-1:0] flush_idx_limit_per_dev_id;
 
    logic init_pi_ptr, init_ui_ptr, init_ci_ptr, init_used_ptr, init_blk_ds_ptr, init_err_info, init_idx_eng_no_notify_rd_req_rsp_num, init_msix_aggregation_info_net_tx, init_msix_aggregation_info_net_rx, init_blk_us_ptr, init_used_elem_ptr, init_blk_ds_chain_1st_seg_flag, init_used_dma_wr_used_idx_irq_flag;
    logic init_all_ram_idx;
 
    logic stop_ptr_equal, blk_forced_shutdown_stop, q_stop_en, idx_eng_err_wait_process, indirct_support;
    logic vq_pending_chk_rsp_ok;
 
    logic rd_err_info_done;            
    logic rd_ctrl_done;                                       
    logic rd_bdf_done;                                        
    logic rd_qdepth_done;                                     
    logic rd_no_notify_req_rsp_num_done;                                
    logic rd_avail_idx_blk_ds_ptr_blk_us_ptr_done;                       
    logic rd_ui_pi_ci_used_ptr_done;                          
    logic rd_used_elem_ptr_err_fatal_flag_done;               
    logic rd_dev_id_done;                                     
    logic rd_used_ring_addr_done;                             
    logic rd_used_err_fatal_flag_done;                        
    logic rd_msix_addr_done;                                  
    logic rd_msix_data_done;                                  
    logic rd_msix_enable_done;                                
    logic rd_msix_mask_done;                                  
    logic rd_msix_pending_done;                               
    logic rd_avail_ring_addr_done;                            
    logic rd_desc_tbl_addr_done;                              
    logic rd_max_len_done;                                    
    logic rd_msix_aggregation_time_done;                      
    logic rd_msix_aggregation_threshold_done;                 
    logic rd_msix_aggregation_info_done;                      
    logic rd_qos_enable_done;                                 
    logic rd_qos_l1_unit_done;                                
    logic rd_generation_done;                                 
    logic rd_blk_desc_eng_desc_tbl_addr_done;                 
    logic rd_blk_desc_eng_desc_tbl_size_done;                 
    logic rd_blk_desc_eng_desc_next_id_desc_cnt_done;
    logic rd_blk_desc_eng_is_indirct_resumer_data_len_done;            
    logic rd_indirct_support_tso_en_csum_en_done;             
    logic rd_net_idx_limit_per_queue_done;                    
    logic rd_net_tx_idx_limit_per_dev_done;                   
    logic rd_net_rx_idx_limit_per_dev_done;                  
    logic rd_net_desc_eng_tail_vld_head_slot_done;
    logic wr_msix_mask_done, wr_avail_idx_done;

    logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0] msix_aggregation_info_net_tx_value, msix_aggregation_info_net_rx_value, init_msix_aggregation_info_value_mask, init_msix_aggregation_info_net_tx_value, init_msix_aggregation_info_net_rx_value;
 
    logic need_starting, forced_shutdown, software_initiated_start;
    
    logic hardware_stop_vld, hardware_stop_en, software_wr_vld;
    virtio_ctrl_info_t hardware_stop_dat;
    virtio_vq_t hardware_stop_qid;
 
    logic err_stop_rdy, used_wr_used_info_ram_en, used_err_process_finish, idx_eng_err_process_finish, err_stop_vld;
    logic idx_eng_err_info_wen, used_err_info_wen;
 
    logic err_info_ram_wea;
    logic [VQ_WIDTH-1:0] err_info_ram_addra, err_info_ram_addrb;
    logic [$bits(virtio_err_info_t)-1:0] err_info_ram_dina, err_info_ram_doutb, err_info_init_dat;
    logic [1:0] err_info_ram_parity_ecc_err;

    logic err_info_clone_ram_wea;
    logic [VQ_WIDTH-1:0] err_info_clone_ram_addra, err_info_clone_ram_addrb;          
    logic [$bits(virtio_err_info_t)-1:0] err_info_clone_ram_dina, err_info_clone_ram_doutb;          
    logic [1:0] err_info_clone_ram_parity_ecc_err;
 
    logic ctrl_ram_wea;
    logic [VQ_WIDTH-1:0] ctrl_ram_addra, ctrl_ram_addrb;
    logic [$bits(virtio_ctrl_info_t)-1:0] ctrl_ram_dina, ctrl_ram_doutb;
    logic [1:0] ctrl_ram_parity_ecc_err;
 
    logic idx_engine_ctrl_ram_wea;
    logic [VQ_WIDTH-1:0] idx_engine_ctrl_ram_addra, idx_engine_ctrl_ram_addrb;
    logic [$bits(virtio_ctrl_info_t)-1:0] idx_engine_ctrl_ram_dina, idx_engine_ctrl_ram_doutb;       
    logic [1:0] idx_engine_ctrl_ram_parity_ecc_err;
 
    logic ctx_ctrl_ram_wea;
    logic [$bits(virtio_ctrl_info_t)-1:0] ctx_ctrl_ram_dina,ctx_ctrl_ram_doutb;          
    logic [VQ_WIDTH-1:0] ctx_ctrl_ram_addra, ctx_ctrl_ram_addrb;         
    logic [1:0] ctx_ctrl_ram_parity_ecc_err;

    logic avail_ring_ctrl_ram_wea;
    logic [$bits(virtio_ctrl_info_t)-1:0] avail_ring_ctrl_ram_dina, avail_ring_ctrl_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_ctrl_ram_addra, avail_ring_ctrl_ram_addrb;         
    logic [1:0] avail_ring_ctrl_ram_parity_ecc_err;
    
    logic avail_ring_clone_ctrl_ram_wea;
    logic [$bits(virtio_ctrl_info_t)-1:0] avail_ring_clone_ctrl_ram_dina, avail_ring_clone_ctrl_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_clone_ctrl_ram_addra, avail_ring_clone_ctrl_ram_addrb;         
    logic [1:0] avail_ring_clone_ctrl_ram_parity_ecc_err;

    logic desc_engine_net_tx_ctrl_ram_wea, desc_engine_net_tx_software_wr_vld, desc_engine_net_tx_hardware_stop_vld;
    logic [$bits(virtio_ctrl_info_t)-1:0] desc_engine_net_tx_ctrl_ram_dina, desc_engine_net_tx_ctrl_ram_doutb;          
    logic [Q_WIDTH-1:0] desc_engine_net_tx_ctrl_ram_addra, desc_engine_net_tx_ctrl_ram_addrb;                  
    logic [1:0] desc_engine_net_tx_ctrl_ram_parity_ecc_err;

    logic desc_engine_net_rx_ctrl_ram_wea, desc_engine_net_rx_software_wr_vld, desc_engine_net_rx_hardware_stop_vld;
    logic [$bits(virtio_ctrl_info_t)-1:0] desc_engine_net_rx_ctrl_ram_dina, desc_engine_net_rx_ctrl_ram_doutb;          
    logic [Q_WIDTH-1:0] desc_engine_net_rx_ctrl_ram_addra, desc_engine_net_rx_ctrl_ram_addrb;             
    logic [1:0] desc_engine_net_rx_ctrl_ram_parity_ecc_err;

    logic net_tx_ctrl_ram_wea;
    logic [$bits(virtio_ctrl_info_t)-1:0] net_tx_ctrl_ram_dina, net_tx_ctrl_ram_doutb;          
    logic [Q_WIDTH-1:0] net_tx_ctrl_ram_addra, net_tx_ctrl_ram_addrb;               
    logic [1:0] net_tx_ctrl_ram_parity_ecc_err;

    logic net_rx_ctrl_ram_wea;
    logic [$bits(virtio_ctrl_info_t)-1:0] net_rx_ctrl_ram_dina, net_rx_ctrl_ram_doutb;          
    logic [Q_WIDTH-1:0] net_rx_ctrl_ram_addra, net_rx_ctrl_ram_addrb;         
    logic [1:0] net_rx_ctrl_ram_parity_ecc_err;

    logic blk_desc_engine_ctrl_ram_wea, blk_software_wr_vld, blk_hardware_stop_vld;
    logic [$bits(virtio_ctrl_info_t)-1:0] blk_desc_engine_ctrl_ram_dina, blk_desc_engine_ctrl_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_desc_engine_ctrl_ram_addra, blk_desc_engine_ctrl_ram_addrb;         
    logic [1:0] blk_desc_engine_ctrl_ram_parity_ecc_err;

    logic blk_down_stream_ctrl_ram_wea;
    logic [$bits(virtio_ctrl_info_t)-1:0] blk_down_stream_ctrl_ram_dina, blk_down_stream_ctrl_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_down_stream_ctrl_ram_addra, blk_down_stream_ctrl_ram_addrb;          
    logic [1:0] blk_down_stream_ctrl_ram_parity_ecc_err;

    logic blk_upstream_ctrl_ram_wea;
    logic [$bits(virtio_ctrl_info_t)-1:0] blk_upstream_ctrl_ram_dina, blk_upstream_ctrl_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_upstream_ctrl_ram_addra, blk_upstream_ctrl_ram_addrb;            
    logic [1:0] blk_upstream_ctrl_ram_parity_ecc_err;

    logic used_dev_id_ram_wea;
    logic [DEV_ID_WIDTH-1:0] used_dev_id_ram_dina, used_dev_id_ram_doutb;          
    logic [VQ_WIDTH-1:0] used_dev_id_ram_addra, used_dev_id_ram_addrb;         
    logic [1:0] used_dev_id_ram_parity_ecc_err;

    logic idx_engine_dev_id_ram_wea;
    logic [DEV_ID_WIDTH-1:0] idx_engine_dev_id_ram_dina, idx_engine_dev_id_ram_doutb;         
    logic [VQ_WIDTH-1:0] idx_engine_dev_id_ram_addra, idx_engine_dev_id_ram_addrb;          
    logic [1:0] idx_engine_dev_id_ram_parity_ecc_err;

    logic blk_upstream_dev_id_ram_wea;
    logic [DEV_ID_WIDTH-1:0] blk_upstream_dev_id_ram_dina, blk_upstream_dev_id_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_upstream_dev_id_ram_addra, blk_upstream_dev_id_ram_addrb;         
    logic [1:0] blk_upstream_dev_id_ram_parity_ecc_err;

    logic net_tx_dev_id_ram_wea;
    logic [DEV_ID_WIDTH-1:0] net_tx_dev_id_ram_dina, net_tx_dev_id_ram_doutb;          
    logic [Q_WIDTH-1:0] net_tx_dev_id_ram_addra, net_tx_dev_id_ram_addrb;               
    logic [1:0] net_tx_dev_id_ram_parity_ecc_err;

    logic net_rx_dev_id_ram_wea;
    logic [DEV_ID_WIDTH-1:0] net_rx_dev_id_ram_dina, net_rx_dev_id_ram_doutb;          
    logic [Q_WIDTH-1:0] net_rx_dev_id_ram_addra, net_rx_dev_id_ram_addrb;         
    logic [1:0] net_rx_dev_id_ram_parity_ecc_err;

    logic net_rx_buf_dev_id_ram_wea;
    logic [DEV_ID_WIDTH-1:0] net_rx_buf_dev_id_ram_dina, net_rx_buf_dev_id_ram_doutb;          
    logic [Q_WIDTH-1:0] net_rx_buf_dev_id_ram_addra, net_rx_buf_dev_id_ram_addrb;         
    logic [1:0] net_rx_buf_dev_id_ram_parity_ecc_err;

    logic idx_engine_bdf_ram_wea;
    logic [15:0] idx_engine_bdf_ram_dina, idx_engine_bdf_ram_doutb;          
    logic [VQ_WIDTH-1:0] idx_engine_bdf_ram_addra, idx_engine_bdf_ram_addrb;         
    logic [1:0] idx_engine_bdf_ram_parity_ecc_err;

    logic avail_ring_bdf_ram_wea;
    logic [15:0] avail_ring_bdf_ram_dina, avail_ring_bdf_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_bdf_ram_addra, avail_ring_bdf_ram_addrb;         
    logic [1:0] avail_ring_bdf_ram_parity_ecc_err;

    logic used_bdf_ram_wea;
    logic [15:0] used_bdf_ram_dina, used_bdf_ram_doutb;          
    logic [VQ_WIDTH-1:0] used_bdf_ram_addra, used_bdf_ram_addrb;         
    logic [1:0] used_bdf_ram_parity_ecc_err;

    logic desc_engine_net_tx_bdf_ram_wea;
    logic [15:0] desc_engine_net_tx_bdf_ram_dina, desc_engine_net_tx_bdf_ram_doutb;          
    logic [Q_WIDTH-1:0] desc_engine_net_tx_bdf_ram_addra, desc_engine_net_tx_bdf_ram_addrb;         
    logic [1:0] desc_engine_net_tx_bdf_ram_parity_ecc_err;

    logic desc_engine_net_rx_bdf_ram_wea;
    logic [15:0] desc_engine_net_rx_bdf_ram_dina, desc_engine_net_rx_bdf_ram_doutb;          
    logic [Q_WIDTH-1:0] desc_engine_net_rx_bdf_ram_addra, desc_engine_net_rx_bdf_ram_addrb;         
    logic [1:0] desc_engine_net_rx_bdf_ram_parity_ecc_err;

    logic net_tx_bdf_ram_wea;
    logic [15:0] net_tx_bdf_ram_dina, net_tx_bdf_ram_doutb;          
    logic [Q_WIDTH-1:0] net_tx_bdf_ram_addra, net_tx_bdf_ram_addrb;         
    logic [1:0] net_tx_bdf_ram_parity_ecc_err;

    logic net_rx_bdf_ram_wea;
    logic [15:0] net_rx_bdf_ram_dina, net_rx_bdf_ram_doutb;          
    logic [Q_WIDTH-1:0] net_rx_bdf_ram_addra, net_rx_bdf_ram_addrb;         
    logic [1:0] net_rx_bdf_ram_parity_ecc_err;

    logic blk_desc_engine_bdf_ram_wea;
    logic [15:0] blk_desc_engine_bdf_ram_dina, blk_desc_engine_bdf_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_desc_engine_bdf_ram_addra, blk_desc_engine_bdf_ram_addrb;         
    logic [1:0] blk_desc_engine_bdf_ram_parity_ecc_err;

    logic blk_down_stream_bdf_ram_wea;
    logic [15:0] blk_down_stream_bdf_ram_dina, blk_down_stream_bdf_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_down_stream_bdf_ram_addra, blk_down_stream_bdf_ram_addrb;         
    logic [1:0] blk_down_stream_bdf_ram_parity_ecc_err;

    logic blk_upstream_bdf_ram_wea;
    logic [15:0] blk_upstream_bdf_ram_dina, blk_upstream_bdf_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_upstream_bdf_ram_addra, blk_upstream_bdf_ram_addrb;              
    logic [1:0] blk_upstream_bdf_ram_parity_ecc_err;

    logic idx_engine_avail_ring_addr_ram_wea;
    logic [63:0] idx_engine_avail_ring_addr_ram_dina, idx_engine_avail_ring_addr_ram_doutb;          
    logic [VQ_WIDTH-1:0] idx_engine_avail_ring_addr_ram_addra, idx_engine_avail_ring_addr_ram_addrb;         
    logic [1:0] idx_engine_avail_ring_addr_ram_parity_ecc_err;

    logic avail_ring_addr_ram_wea;
    logic [63:0] avail_ring_addr_ram_dina, avail_ring_addr_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_addr_ram_addra, avail_ring_addr_ram_addrb;     
    logic [1:0] avail_ring_addr_ram_parity_ecc_err;

    //logic avail_addr_flag, avail_ring_avail_addr_rd_en_d1, idx_eng_avail_addr_rd_en_d1, avail_ring_avail_addr_rd_en, idx_eng_avail_addr_rd_en;  

    logic used_ring_addr_ram_wea;
    logic [63:0] used_ring_addr_ram_dina, used_ring_addr_ram_doutb;          
    logic [VQ_WIDTH-1:0] used_ring_addr_ram_addra, used_ring_addr_ram_addrb;         
    logic [1:0] used_ring_addr_ram_parity_ecc_err;

    logic idx_engine_used_addr_ram_wea;
    logic [63:0] idx_engine_used_addr_ram_dina, idx_engine_used_addr_ram_doutb;          
    logic [VQ_WIDTH-1:0] idx_engine_used_addr_ram_addra, idx_engine_used_addr_ram_addrb;        
    logic [1:0] idx_engine_used_addr_ram_parity_ecc_err;

    logic desc_engine_net_tx_desc_tbl_addr_ram_wea;
    logic [63:0] desc_engine_net_tx_desc_tbl_addr_ram_dina, desc_engine_net_tx_desc_tbl_addr_ram_doutb;          
    logic [Q_WIDTH-1:0] desc_engine_net_tx_desc_tbl_addr_ram_addra, desc_engine_net_tx_desc_tbl_addr_ram_addrb;         
    logic [1:0] desc_engine_net_tx_desc_tbl_addr_ram_parity_ecc_err;

    logic desc_engine_net_rx_desc_tbl_addr_ram_wea;
    logic [63:0] desc_engine_net_rx_desc_tbl_addr_ram_dina, desc_engine_net_rx_desc_tbl_addr_ram_doutb;          
    logic [Q_WIDTH-1:0] desc_engine_net_rx_desc_tbl_addr_ram_addra, desc_engine_net_rx_desc_tbl_addr_ram_addrb;         
    logic [1:0] desc_engine_net_rx_desc_tbl_addr_ram_parity_ecc_err;

    logic blk_desc_engine_desc_tbl_addr_ram_wea;
    logic [63:0] blk_desc_engine_desc_tbl_addr_ram_dina, blk_desc_engine_desc_tbl_addr_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_desc_engine_desc_tbl_addr_ram_addra, blk_desc_engine_desc_tbl_addr_ram_addrb;         
    logic [1:0] blk_desc_engine_desc_tbl_addr_ram_parity_ecc_err;

    logic desc_engine_net_tx_qdepth_ram_wea;
    logic [3:0] desc_engine_net_tx_qdepth_ram_dina, desc_engine_net_tx_qdepth_ram_doutb;          
    logic [Q_WIDTH-1:0] desc_engine_net_tx_qdepth_ram_addra, desc_engine_net_tx_qdepth_ram_addrb;         
    logic [1:0] desc_engine_net_tx_qdepth_ram_parity_ecc_err;

    logic desc_engine_net_rx_qdepth_ram_wea;
    logic [3:0] desc_engine_net_rx_qdepth_ram_dina, desc_engine_net_rx_qdepth_ram_doutb;          
    logic [Q_WIDTH-1:0] desc_engine_net_rx_qdepth_ram_addra, desc_engine_net_rx_qdepth_ram_addrb;                 
    logic [1:0] desc_engine_net_rx_qdepth_ram_parity_ecc_err;

    logic blk_desc_engine_qdepth_ram_wea;
    logic [3:0] blk_desc_engine_qdepth_ram_dina, blk_desc_engine_qdepth_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_desc_engine_qdepth_ram_addra, blk_desc_engine_qdepth_ram_addrb;         
    logic [1:0] blk_desc_engine_qdepth_ram_parity_ecc_err;

    logic idx_engine_qdepth_ram_wea;
    logic [3:0] idx_engine_qdepth_ram_dina, idx_engine_qdepth_ram_doutb;          
    logic [VQ_WIDTH-1:0] idx_engine_qdepth_ram_addra, idx_engine_qdepth_ram_addrb;         
    logic [1:0] idx_engine_qdepth_ram_parity_ecc_err;   

    logic avail_ring_qdepth_ram_wea;
    logic [3:0] avail_ring_qdepth_ram_dina, avail_ring_qdepth_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_qdepth_ram_addra, avail_ring_qdepth_ram_addrb;         
    logic [1:0] avail_ring_qdepth_ram_parity_ecc_err;

    logic used_qdepth_ram_wea;
    logic [3:0] used_qdepth_ram_dina, used_qdepth_ram_doutb;          
    logic [VQ_WIDTH-1:0] used_qdepth_ram_addra, used_qdepth_ram_addrb;             
    logic [1:0] used_qdepth_ram_parity_ecc_err;

    logic idx_engine_avail_idx_ram_wea, idx_engine_avail_idx_ram_wea_sw;
    logic [15:0] idx_engine_avail_idx_ram_dina, idx_engine_avail_idx_ram_doutb;          
    logic [VQ_WIDTH-1:0] idx_engine_avail_idx_ram_addra, idx_engine_avail_idx_ram_addrb;         
    logic [1:0] idx_engine_avail_idx_ram_parity_ecc_err;

    logic avail_ring_avail_idx_ram_wea;
    logic [15:0] avail_ring_avail_idx_ram_dina, avail_ring_avail_idx_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_avail_idx_ram_addra, avail_ring_avail_idx_ram_addrb;         
    logic [1:0] avail_ring_avail_idx_ram_parity_ecc_err;

    logic avail_ring_clone_avail_idx_ram_wea;
    logic [15:0] avail_ring_clone_avail_idx_ram_dina, avail_ring_clone_avail_idx_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_clone_avail_idx_ram_addra, avail_ring_clone_avail_idx_ram_addrb;         
    logic [1:0] avail_ring_clone_avail_idx_ram_parity_ecc_err;

    logic avail_ring_avail_ui_ptr_ram_wea;
    logic [15:0] avail_ring_avail_ui_ptr_ram_dina, avail_ring_avail_ui_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_avail_ui_ptr_ram_addra, avail_ring_avail_ui_ptr_ram_addrb;         
    logic [1:0] avail_ring_avail_ui_ptr_ram_parity_ecc_err; 

    logic avail_ring_clone_avail_ui_ptr_ram_wea;
    logic [15:0] avail_ring_clone_avail_ui_ptr_ram_dina, avail_ring_clone_avail_ui_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_clone_avail_ui_ptr_ram_addra, avail_ring_clone_avail_ui_ptr_ram_addrb;         
    logic [1:0] avail_ring_clone_avail_ui_ptr_ram_parity_ecc_err;

    logic idx_engine_avail_ui_ptr_ram_wea;
    logic [15:0] idx_engine_avail_ui_ptr_ram_dina, idx_engine_avail_ui_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] idx_engine_avail_ui_ptr_ram_addra, idx_engine_avail_ui_ptr_ram_addrb;         
    logic [1:0] idx_engine_avail_ui_ptr_ram_parity_ecc_err;

    logic ui_ptr_ram_wea;
    logic [15:0] ui_ptr_ram_dina, ui_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] ui_ptr_ram_addra, ui_ptr_ram_addrb;              
    logic [1:0] ui_ptr_ram_parity_ecc_err;

    logic avail_ring_avail_pi_ptr_ram_wea;
    logic [15:0] avail_ring_avail_pi_ptr_ram_dina, avail_ring_avail_pi_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_avail_pi_ptr_ram_addra, avail_ring_avail_pi_ptr_ram_addrb;         
    logic [1:0] avail_ring_avail_pi_ptr_ram_parity_ecc_err;

    logic pi_ptr_ram_wea;
    logic [15:0] pi_ptr_ram_dina, pi_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] pi_ptr_ram_addra, pi_ptr_ram_addrb;           
    logic [1:0] pi_ptr_ram_parity_ecc_err;

    logic avail_ring_avail_ci_ptr_ram_wea;
    logic [15:0] avail_ring_avail_ci_ptr_ram_dina, avail_ring_avail_ci_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_avail_ci_ptr_ram_addra, avail_ring_avail_ci_ptr_ram_addrb;         
    logic [1:0] avail_ring_avail_ci_ptr_ram_parity_ecc_err;

    logic avail_ring_clone_avail_ci_ptr_ram_wea;
    logic [15:0] avail_ring_clone_avail_ci_ptr_ram_dina, avail_ring_clone_avail_ci_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] avail_ring_clone_avail_ci_ptr_ram_addra, avail_ring_clone_avail_ci_ptr_ram_addrb;              
    logic [1:0] avail_ring_clone_avail_ci_ptr_ram_parity_ecc_err;

    logic ci_ptr_ram_wea;
    logic [15:0] ci_ptr_ram_dina, ci_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] ci_ptr_ram_addra, ci_ptr_ram_addrb;            
    logic [1:0] ci_ptr_ram_parity_ecc_err;

    logic idx_engine_no_notify_rd_req_rsp_num_ram_wea;
    logic [15:0] idx_engine_no_notify_rd_req_rsp_num_ram_dina, idx_engine_no_notify_rd_req_rsp_num_ram_doutb;          
    logic [VQ_WIDTH-1:0] idx_engine_no_notify_rd_req_rsp_num_ram_addra, idx_engine_no_notify_rd_req_rsp_num_ram_addrb;           
    logic [1:0] idx_engine_no_notify_rd_req_rsp_num_ram_parity_ecc_err;

    logic no_notify_rd_req_rsp_num_ram_wea;
    logic [15:0] no_notify_rd_req_rsp_num_ram_dina, no_notify_rd_req_rsp_num_ram_doutb;          
    logic [VQ_WIDTH-1:0] no_notify_rd_req_rsp_num_ram_addra, no_notify_rd_req_rsp_num_ram_addrb;                  
    logic [1:0] no_notify_rd_req_rsp_num_ram_parity_ecc_err;

    logic blk_down_stream_ptr_ram_wea;           
    logic [15:0] blk_down_stream_ptr_ram_dina, blk_down_stream_ptr_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_down_stream_ptr_ram_addra, blk_down_stream_ptr_ram_addrb;         
    logic [1:0] blk_down_stream_ptr_ram_parity_ecc_err;

    logic blk_ds_ptr_ram_wea;
    logic [15:0] blk_ds_ptr_ram_dina, blk_ds_ptr_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_ds_ptr_ram_addra, blk_ds_ptr_ram_addrb;            
    logic [1:0] blk_ds_ptr_ram_parity_ecc_err;

    logic used_ptr_ram_wea;
    logic [15:0] used_ptr_ram_dina, used_ptr_ram_doutb;          
    logic [VQ_WIDTH-1:0] used_ptr_ram_addra, used_ptr_ram_addrb;            
    logic [1:0] used_ptr_ram_parity_ecc_err;

    logic blk_upstream_ptr_ram_wea;
    logic [15:0] blk_upstream_ptr_ram_dina, blk_upstream_ptr_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_upstream_ptr_ram_addra, blk_upstream_ptr_ram_addrb;         
    logic [1:0] blk_upstream_ptr_ram_parity_ecc_err;

    logic blk_us_ptr_ram_wea;
    logic [15:0] blk_us_ptr_ram_dina, blk_us_ptr_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_us_ptr_ram_addra, blk_us_ptr_ram_addrb;         
    logic [1:0] blk_us_ptr_ram_parity_ecc_err;

    logic used_elem_ptr_ram_wea;
    logic [$bits(virtio_used_elem_ptr_info_t)-1:0] used_elem_ptr_ram_dina, used_elem_ptr_ram_doutb;
    logic [VQ_WIDTH-1:0] used_elem_ptr_ram_addra, used_elem_ptr_ram_addrb;
    logic [1:0] used_elem_ptr_ram_parity_ecc_err;
    
    logic used_err_fatal_flag_ram_wea;
    logic used_err_fatal_flag_ram_dina, used_err_fatal_flag_ram_doutb;
    logic [VQ_WIDTH-1:0] used_err_fatal_flag_ram_addra, used_err_fatal_flag_ram_addrb;
    logic [1:0] used_err_fatal_flag_ram_parity_ecc_err;
    
    logic used_msix_addr_ram_wea;
    logic [63:0] used_msix_addr_ram_dina, used_msix_addr_ram_doutb;
    logic [VQ_WIDTH-1:0] used_msix_addr_ram_addra, used_msix_addr_ram_addrb;
    logic [1:0] used_msix_addr_ram_parity_ecc_err;
    
    logic used_msix_data_ram_wea;
    logic [31:0] used_msix_data_ram_dina, used_msix_data_ram_doutb;
    logic [VQ_WIDTH-1:0] used_msix_data_ram_addra, used_msix_data_ram_addrb;
    logic [1:0] used_msix_data_ram_parity_ecc_err;
    
    logic used_msix_enable_mask_pending_ram_wea, used_msix_enable_mask_pending_ram_wea_sw;
    logic [2:0] used_msix_enable_mask_pending_ram_dina, used_msix_enable_mask_pending_ram_doutb;
    logic [VQ_WIDTH-1:0] used_msix_enable_mask_pending_ram_addra, used_msix_enable_mask_pending_ram_addrb;
    logic [1:0] used_msix_enable_mask_pending_ram_parity_ecc_err;
    
    logic used_msix_aggregation_time_net_tx_ram_wea;
    logic [(IRQ_MERGE_UINT_NUM*3)-1:0] used_msix_aggregation_time_net_tx_ram_dina, used_msix_aggregation_time_net_tx_ram_doutb;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] used_msix_aggregation_time_net_tx_ram_addra, used_msix_aggregation_time_net_tx_ram_addrb;
    logic [1:0] used_msix_aggregation_time_net_tx_ram_parity_ecc_err;
    
    logic used_msix_aggregation_time_net_rx_ram_wea;
    logic [(IRQ_MERGE_UINT_NUM*3)-1:0] used_msix_aggregation_time_net_rx_ram_dina, used_msix_aggregation_time_net_rx_ram_doutb;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] used_msix_aggregation_time_net_rx_ram_addra, used_msix_aggregation_time_net_rx_ram_addrb;
    logic [1:0] used_msix_aggregation_time_net_rx_ram_parity_ecc_err;
    
    logic used_msix_aggregation_threshold_net_tx_ram_wea;
    logic [6:0] used_msix_aggregation_threshold_net_tx_ram_dina, used_msix_aggregation_threshold_net_tx_ram_doutb;
    logic [Q_WIDTH-1:0] used_msix_aggregation_threshold_net_tx_ram_addra, used_msix_aggregation_threshold_net_tx_ram_addrb;
    logic [1:0] used_msix_aggregation_threshold_net_tx_ram_parity_ecc_err;
    
    logic used_msix_aggregation_threshold_net_rx_ram_wea;
    logic [6:0] used_msix_aggregation_threshold_net_rx_ram_dina, used_msix_aggregation_threshold_net_rx_ram_doutb;
    logic [Q_WIDTH-1:0] used_msix_aggregation_threshold_net_rx_ram_addra, used_msix_aggregation_threshold_net_rx_ram_addrb;
    logic [1:0] used_msix_aggregation_threshold_net_rx_ram_parity_ecc_err;
    
    logic used_msix_aggregation_info_net_tx_ram_wea;
    logic [(IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8))-1:0] used_msix_aggregation_info_net_tx_ram_dina, used_msix_aggregation_info_net_tx_ram_doutb;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] used_msix_aggregation_info_net_tx_ram_addra, used_msix_aggregation_info_net_tx_ram_addrb;
    logic [1:0] used_msix_aggregation_info_net_tx_ram_parity_ecc_err;
    
    logic used_msix_aggregation_info_net_rx_ram_wea;
    logic [(IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8))-1:0] used_msix_aggregation_info_net_rx_ram_dina, used_msix_aggregation_info_net_rx_ram_doutb;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] used_msix_aggregation_info_net_rx_ram_addra, used_msix_aggregation_info_net_rx_ram_addrb;
    logic [1:0] used_msix_aggregation_info_net_rx_ram_parity_ecc_err;
    
    logic net_tx_qos_unit_ram_wea;
    logic [15:0] net_tx_qos_unit_ram_dina, net_tx_qos_unit_ram_doutb;
    logic [Q_WIDTH-1:0] net_tx_qos_unit_ram_addra, net_tx_qos_unit_ram_addrb;
    logic [1:0] net_tx_qos_unit_ram_parity_ecc_err;

    logic net_tx_qos_enable_ram_wea;
    logic net_tx_qos_enable_ram_dina, net_tx_qos_enable_ram_doutb;
    logic [Q_WIDTH-1:0] net_tx_qos_enable_ram_addra, net_tx_qos_enable_ram_addrb;
    logic [1:0] net_tx_qos_enable_ram_parity_ecc_err;
    
    logic net_tx_qos_unit_clone_ram_wea;
    logic [15:0] net_tx_qos_unit_clone_ram_dina, net_tx_qos_unit_clone_ram_doutb;
    logic [Q_WIDTH-1:0] net_tx_qos_unit_clone_ram_addra, net_tx_qos_unit_clone_ram_addrb;
    logic [1:0] net_tx_qos_unit_clone_ram_parity_ecc_err;
    
    logic net_tx_qos_enable_clone_ram_wea;
    logic net_tx_qos_enable_clone_ram_dina, net_tx_qos_enable_clone_ram_doutb;
    logic [Q_WIDTH-1:0] net_tx_qos_enable_clone_ram_addra, net_tx_qos_enable_clone_ram_addrb;
    logic [1:0] net_tx_qos_enable_clone_ram_parity_ecc_err;

    logic net_rx_buf_qos_unit_ram_wea;
    logic [15:0] net_rx_buf_qos_unit_ram_dina, net_rx_buf_qos_unit_ram_doutb;
    logic [Q_WIDTH-1:0] net_rx_buf_qos_unit_ram_addra, net_rx_buf_qos_unit_ram_addrb;
    logic [1:0] net_rx_buf_qos_unit_ram_parity_ecc_err;

    logic net_rx_buf_qos_enable_ram_wea;
    logic net_rx_buf_qos_enable_ram_dina, net_rx_buf_qos_enable_ram_doutb;
    logic [Q_WIDTH-1:0] net_rx_buf_qos_enable_ram_addra, net_rx_buf_qos_enable_ram_addrb;
    logic [1:0] net_rx_buf_qos_enable_ram_parity_ecc_err;
    
    logic blk_down_stream_qos_unit_ram_wea;
    logic [15:0] blk_down_stream_qos_unit_ram_dina, blk_down_stream_qos_unit_ram_doutb;
    logic [Q_WIDTH-1:0] blk_down_stream_qos_unit_ram_addra, blk_down_stream_qos_unit_ram_addrb;
    logic [1:0] blk_down_stream_qos_unit_ram_parity_ecc_err;

    logic blk_down_stream_qos_enable_ram_wea;
    logic blk_down_stream_qos_enable_ram_dina, blk_down_stream_qos_enable_ram_doutb;
    logic [Q_WIDTH-1:0] blk_down_stream_qos_enable_ram_addra, blk_down_stream_qos_enable_ram_addrb;
    logic [1:0] blk_down_stream_qos_enable_ram_parity_ecc_err;
    
    logic blk_down_stream_generation_ram_wea;
    logic [7:0] blk_down_stream_generation_ram_dina, blk_down_stream_generation_ram_doutb;
    logic [Q_WIDTH-1:0] blk_down_stream_generation_ram_addra, blk_down_stream_generation_ram_addrb;
    logic [1:0] blk_down_stream_generation_ram_parity_ecc_err;
    
    logic net_rx_buf_generation_ram_wea;
    logic [7:0] net_rx_buf_generation_ram_dina, net_rx_buf_generation_ram_doutb;
    logic [Q_WIDTH-1:0] net_rx_buf_generation_ram_addra, net_rx_buf_generation_ram_addrb;
    logic [1:0] net_rx_buf_generation_ram_parity_ecc_err;
    
    logic blk_upstream_generation_ram_wea;
    logic [7:0] blk_upstream_generation_ram_dina, blk_upstream_generation_ram_doutb;
    logic [Q_WIDTH-1:0] blk_upstream_generation_ram_addra, blk_upstream_generation_ram_addrb;
    logic [1:0] blk_upstream_generation_ram_parity_ecc_err;
    
    logic net_tx_generation_ram_wea;
    logic [7:0] net_tx_generation_ram_dina, net_tx_generation_ram_doutb;
    logic [Q_WIDTH-1:0] net_tx_generation_ram_addra, net_tx_generation_ram_addrb;
    logic [1:0] net_tx_generation_ram_parity_ecc_err;
    
    logic blk_desc_eng_desc_tbl_addr_ram_wea;
    logic [63:0] blk_desc_eng_desc_tbl_addr_ram_dina, blk_desc_eng_desc_tbl_addr_ram_doutb;
    logic [Q_WIDTH-1:0] blk_desc_eng_desc_tbl_addr_ram_addra, blk_desc_eng_desc_tbl_addr_ram_addrb;
    logic [1:0] blk_desc_eng_desc_tbl_addr_ram_parity_ecc_err;
    
    logic blk_desc_eng_desc_tbl_size_ram_wea;
    logic [31:0] blk_desc_eng_desc_tbl_size_ram_dina, blk_desc_eng_desc_tbl_size_ram_doutb;
    logic [Q_WIDTH-1:0] blk_desc_eng_desc_tbl_size_ram_addra, blk_desc_eng_desc_tbl_size_ram_addrb;
    logic [1:0] blk_desc_eng_desc_tbl_size_ram_parity_ecc_err;
    
    logic blk_desc_eng_desc_tbl_next_id_ram_wea;
    logic [31:0] blk_desc_eng_desc_tbl_next_id_ram_dina, blk_desc_eng_desc_tbl_next_id_ram_doutb;
    logic [Q_WIDTH-1:0] blk_desc_eng_desc_tbl_next_id_ram_addra, blk_desc_eng_desc_tbl_next_id_ram_addrb;
    logic [1:0] blk_desc_eng_desc_tbl_next_id_ram_parity_ecc_err;
    
    logic blk_desc_eng_desc_cnt_ram_wea;
    logic [19:0] blk_desc_eng_desc_cnt_ram_dina, blk_desc_eng_desc_cnt_ram_doutb;
    logic [Q_WIDTH-1:0] blk_desc_eng_desc_cnt_ram_addra, blk_desc_eng_desc_cnt_ram_addrb;
    logic [1:0] blk_desc_eng_desc_cnt_ram_parity_ecc_err;

    logic blk_desc_eng_data_len_ram_wea;
    logic [20:0] blk_desc_eng_data_len_ram_dina, blk_desc_eng_data_len_ram_doutb;
    logic [Q_WIDTH-1:0] blk_desc_eng_data_len_ram_addra, blk_desc_eng_data_len_ram_addrb;
    logic [1:0] blk_desc_eng_data_len_ram_parity_ecc_err;
    
    logic blk_desc_eng_is_indirct_ram_wea;
    logic blk_desc_eng_is_indirct_ram_dina, blk_desc_eng_is_indirct_ram_doutb;
    logic [Q_WIDTH-1:0] blk_desc_eng_is_indirct_ram_addra, blk_desc_eng_is_indirct_ram_addrb;
    logic [1:0] blk_desc_eng_is_indirct_ram_parity_ecc_err;
    
    logic blk_desc_eng_resumer_ram_wea;
    logic blk_desc_eng_resumer_ram_dina, blk_desc_eng_resumer_ram_doutb;
    logic [Q_WIDTH-1:0] blk_desc_eng_resumer_ram_addra, blk_desc_eng_resumer_ram_addrb;
    logic [1:0] blk_desc_eng_resumer_ram_parity_ecc_err;
    
    logic blk_desc_eng_indirct_support_ram_wea;
    logic blk_desc_eng_indirct_support_ram_dina, blk_desc_eng_indirct_support_ram_doutb;
    logic [Q_WIDTH-1:0] blk_desc_eng_indirct_support_ram_addra, blk_desc_eng_indirct_support_ram_addrb;
    logic [1:0] blk_desc_eng_indirct_support_ram_parity_ecc_err;
    
    logic desc_eng_net_tx_indirct_support_ram_wea;
    logic desc_eng_net_tx_indirct_support_ram_dina, desc_eng_net_tx_indirct_support_ram_doutb;
    logic [Q_WIDTH-1:0] desc_eng_net_tx_indirct_support_ram_addra, desc_eng_net_tx_indirct_support_ram_addrb;
    logic [1:0] desc_eng_net_tx_indirct_support_ram_parity_ecc_err;
    
    logic desc_eng_net_rx_indirct_support_ram_wea;
    logic desc_eng_net_rx_indirct_support_ram_dina, desc_eng_net_rx_indirct_support_ram_doutb;
    logic [Q_WIDTH-1:0] desc_eng_net_rx_indirct_support_ram_addra, desc_eng_net_rx_indirct_support_ram_addrb;
    logic [1:0] desc_eng_net_rx_indirct_support_ram_parity_ecc_err;
    
    logic net_tx_tso_en_csum_en_ram_wea;
    logic [1:0] net_tx_tso_en_csum_en_ram_dina, net_tx_tso_en_csum_en_ram_doutb;
    logic [Q_WIDTH-1:0] net_tx_tso_en_csum_en_ram_addra, net_tx_tso_en_csum_en_ram_addrb;
    logic [1:0] net_tx_tso_en_csum_en_ram_parity_ecc_err;
    
    logic desc_eng_net_tx_max_len_ram_wea;
    logic [19:0] desc_eng_net_tx_max_len_ram_dina, desc_eng_net_tx_max_len_ram_doutb;
    logic [Q_WIDTH-1:0] desc_eng_net_tx_max_len_ram_addra, desc_eng_net_tx_max_len_ram_addrb;
    logic [1:0] desc_eng_net_tx_max_len_ram_parity_ecc_err;
    
    logic desc_eng_net_rx_max_len_ram_wea;
    logic [19:0] desc_eng_net_rx_max_len_ram_dina, desc_eng_net_rx_max_len_ram_doutb;
    logic [Q_WIDTH-1:0] desc_eng_net_rx_max_len_ram_addra, desc_eng_net_rx_max_len_ram_addrb;
    logic [1:0] desc_eng_net_rx_max_len_ram_parity_ecc_err;
    
    logic blk_desc_eng_max_len_ram_wea;
    logic [19:0] blk_desc_eng_max_len_ram_dina, blk_desc_eng_max_len_ram_doutb;
    logic [Q_WIDTH-1:0] blk_desc_eng_max_len_ram_addra, blk_desc_eng_max_len_ram_addrb;
    logic [1:0] blk_desc_eng_max_len_ram_parity_ecc_err;
    
    logic net_rx_buf_idx_limit_per_queue_ram_wea;
    logic [7:0] net_rx_buf_idx_limit_per_queue_ram_dina, net_rx_buf_idx_limit_per_queue_ram_doutb;
    logic [Q_WIDTH-1:0] net_rx_buf_idx_limit_per_queue_ram_addra, net_rx_buf_idx_limit_per_queue_ram_addrb;
    logic [1:0] net_rx_buf_idx_limit_per_queue_ram_parity_ecc_err;
    
    logic desc_eng_net_tx_idx_limit_per_queue_ram_wea;
    logic [7:0] desc_eng_net_tx_idx_limit_per_queue_ram_dina, desc_eng_net_tx_idx_limit_per_queue_ram_doutb;
    logic [Q_WIDTH-1:0] desc_eng_net_tx_idx_limit_per_queue_ram_addra, desc_eng_net_tx_idx_limit_per_queue_ram_addrb;
    logic [1:0] desc_eng_net_tx_idx_limit_per_queue_ram_parity_ecc_err;
    
    logic desc_eng_net_tx_idx_limit_per_dev_ram_wea, desc_eng_net_tx_idx_limit_per_dev_ram_wea_sw;
    logic [7:0] desc_eng_net_tx_idx_limit_per_dev_ram_dina, desc_eng_net_tx_idx_limit_per_dev_ram_doutb;
    logic [DEV_ID_WIDTH-1:0] desc_eng_net_tx_idx_limit_per_dev_ram_addra, desc_eng_net_tx_idx_limit_per_dev_ram_addrb;
    logic [1:0] desc_eng_net_tx_idx_limit_per_dev_ram_parity_ecc_err;
    
    logic net_rx_buf_idx_limit_per_dev_ram_wea, net_rx_buf_idx_limit_per_dev_ram_wea_sw;
    logic [7:0] net_rx_buf_idx_limit_per_dev_ram_dina, net_rx_buf_idx_limit_per_dev_ram_doutb;
    logic [DEV_ID_WIDTH-1:0] net_rx_buf_idx_limit_per_dev_ram_addra, net_rx_buf_idx_limit_per_dev_ram_addrb;
    logic [1:0] net_rx_buf_idx_limit_per_dev_ram_parity_ecc_err;
    
    logic desc_eng_net_tx_tail_vld_head_slot_ram_wea;
    logic [(SLOT_WIDTH*2+1)-1:0] desc_eng_net_tx_tail_vld_head_slot_ram_dina, desc_eng_net_tx_tail_vld_head_slot_ram_doutb;
    logic [Q_WIDTH-1:0] desc_eng_net_tx_tail_vld_head_slot_ram_addra, desc_eng_net_tx_tail_vld_head_slot_ram_addrb;
    logic [1:0] desc_eng_net_tx_tail_vld_head_slot_ram_parity_ecc_err;
    
    logic desc_eng_net_rx_tail_vld_head_slot_ram_wea;
    logic [(SLOT_WIDTH*2+1)-1:0] desc_eng_net_rx_tail_vld_head_slot_ram_dina, desc_eng_net_rx_tail_vld_head_slot_ram_doutb;
    logic [Q_WIDTH-1:0] desc_eng_net_rx_tail_vld_head_slot_ram_addra, desc_eng_net_rx_tail_vld_head_slot_ram_addrb;
    logic [1:0] desc_eng_net_rx_tail_vld_head_slot_ram_parity_ecc_err;

    logic used_dma_write_used_idx_irq_flag_ram_wea;
    logic used_dma_write_used_idx_irq_flag_ram_dina, used_dma_write_used_idx_irq_flag_ram_doutb;          
    logic [VQ_WIDTH-1:0] used_dma_write_used_idx_irq_flag_ram_addra, used_dma_write_used_idx_irq_flag_ram_addrb;         
    logic [1:0] used_dma_write_used_idx_irq_flag_ram_parity_ecc_err;

    logic blk_down_stream_chain_fst_seg_ram_wea;
    logic blk_down_stream_chain_fst_seg_ram_dina, blk_down_stream_chain_fst_seg_ram_doutb;          
    logic [Q_WIDTH-1:0] blk_down_stream_chain_fst_seg_ram_addra, blk_down_stream_chain_fst_seg_ram_addrb;       
    logic [1:0] blk_down_stream_chain_fst_seg_ram_parity_ecc_err;

    logic virtio_used_irq_cnt_ram_wea, virtio_used_irq_cnt_ram_sw_wea, virtio_used_irq_cnt_ram_hw_wea;
    logic [15:0] virtio_used_irq_cnt_ram_dina, virtio_used_irq_cnt_ram_doutb;          
    logic [VQ_WIDTH-1:0] virtio_used_irq_cnt_ram_addra, virtio_used_irq_cnt_ram_addrb, virtio_used_irq_cnt_ram_addra_tmp;         
    logic [1:0] virtio_used_irq_cnt_ram_parity_ecc_err;    

    logic all_init_done, wr_used_irq_cnt_done, rd_used_irq_cnt_done; 
         
    logic [15:0] pi_ptr, ui_ptr, ci_ptr, used_ptr, blk_ds_ptr, blk_us_ptr;
    logic [6:0] rd_req_num, rd_rsp_num;

    logic [63:0] dfx_err_0, dfx_err_0_q, dfx_err_1, dfx_err_1_q, dfx_err_2, dfx_err_2_q, dfx_err_3, dfx_err_3_q;
    logic [42:0] dfx_status;

    logic [VQ_WIDTH-1:0] sw_vq_addr;
    logic [Q_WIDTH-1:0] sw_q_addr;
    logic [DEV_ID_WIDTH-1:0] sw_dev_addr;

    virtio_ctx_info_t virtio_ctx_info;

    virtio_vq_t soc_notify_qid;
    logic fatal, idx_engine_err;
    virtio_err_info_t err_info_ram_dout_tmp;
    logic [IRQ_MERGE_UINT_NUM*MSIX_TIME_WIDTH-1:0] msix_aggregation_time_value, msix_aggregation_time, rd_msix_aggregation_time_tmp;
    logic [MSIX_TIME_WIDTH-1:0] rd_msix_aggregation_time;
    logic used_dma_write_used_idx_irq_flag;

    enum logic [6:0] {
        ERR_IDLE            = 7'b0000001,
        USED_RD_ERR_INFO    = 7'b0000010,
        USED_ERR_NOP        = 7'b0000100,  //for timing
        USED_ERR_PROCESS    = 7'b0001000,
        IDX_ENG_RD_ERR_INFO = 7'b0010000,
        IDX_ENG_ERR_NOP     = 7'b0100000,  //for timing
        IDX_ENG_ERR_PROCESS = 7'b1000000
    } err_cstat, err_nstat;
 
    enum logic [3:0] {
        ERR_STOP_IDLE  = 4'b0001,
        ERR_STOP_NOP   = 4'b0010,  //for timing
        ERR_STOP_QUERY = 4'b0100,
        ERR_STOP_DOING = 4'b1000
    } err_stop_cstat, err_stop_nstat;
 
    enum logic [6:0] {
        IDLE       = 7'b0000001,
        CTX_RD_REQ = 7'b0000010,
        CTX_RD_PRO = 7'b0000100,
        CTX_RD     = 7'b0001000,
        CTX_EXEC   = 7'b0010000,
        CTX_WR     = 7'b0100000,
        CTX_RSP    = 7'b1000000
    } cstat, nstat;
 

    assign sw_vq_addr = {csr_if_addr[13:12], csr_if_addr[11+VQ_WIDTH:14]};
    assign sw_q_addr = csr_if_addr[11+VQ_WIDTH:14];
    assign sw_dev_addr = csr_if_addr[17:8];

    //==================ERR FSM=====================//
    always @(posedge clk) begin
        if(rst) begin
            err_cstat <= ERR_IDLE;
        end else begin
            err_cstat <= err_nstat;
        end
    end

    always @(*) begin
        err_nstat = err_cstat;
        case(err_cstat)
            ERR_IDLE: begin
                if(used_err_info_wr_vld) begin
                    err_nstat = USED_RD_ERR_INFO;
                end else if(idx_engine_err_info_wr_req_vld) begin
                    err_nstat = IDX_ENG_RD_ERR_INFO;
                end
            end
            USED_RD_ERR_INFO: begin
                err_nstat = USED_ERR_NOP;
            end
            USED_ERR_NOP: begin
                err_nstat = USED_ERR_PROCESS;
            end
            USED_ERR_PROCESS: begin
                if(used_err_process_finish) begin
                    if(idx_engine_err_info_wr_req_vld) begin
                        err_nstat = IDX_ENG_RD_ERR_INFO;
                    end else begin
                        err_nstat = ERR_IDLE;
                    end
                end
            end
            IDX_ENG_RD_ERR_INFO: begin
                err_nstat = IDX_ENG_ERR_NOP;
            end
            IDX_ENG_ERR_NOP: begin
                err_nstat = IDX_ENG_ERR_PROCESS;
            end
            IDX_ENG_ERR_PROCESS: begin
                if(idx_eng_err_process_finish) begin
                    err_nstat = ERR_IDLE;
                end
            end
            default: err_nstat = ERR_IDLE;
        endcase
    end

    //====================================signal===============================// 
    assign err_info_ram_dout_tmp = virtio_err_info_t'(err_info_ram_doutb);
    assign err_info_fatal        = err_info_ram_dout_tmp.fatal;
    assign idx_engine_err        = (err_info_ram_dout_tmp.err_code & VIRTIO_IDX_ENGINE_ERR_CODE_MASK) == VIRTIO_IDX_ENGINE_ERR_CODE_MASK;    //Flag that this is idx_engine_err

    //==========for timing===============//
    logic err_info_fatal_d1, idx_engine_err_d1;
    always @(posedge clk) begin
        err_info_fatal_d1 <= err_info_fatal;
        idx_engine_err_d1 <= idx_engine_err;
    end
    
    //=======================used_wr_used_info_ram_en = 1 || 2====================================//
    //1:When the fatal value read from the err_info RAM is 0, the used module can unconditionally write to the err_info RAM.
    //2:When the fatal value read from the err_info RAM is 1, the previous error originated from the idx_engine module, and the fatal value in the err_info that the used module intends to write is 1, the used module can write the err_info into the RAM.
    
    assign used_wr_used_info_ram_en = ~err_info_fatal_d1 || (err_info_fatal_d1 && idx_engine_err_d1 && used_err_info_wr_dat.fatal);

    //===========================used_err_process_finish = 1 || 2 || 3=====================================//
    //1:When the err_info sent by the used module is not written into the err_info RAM
    //2:When the err_info sent by the used module is to be written into the err_info RAM, the fatal value read from the err_info RAM is 0, and the fatal value in the err_info that the used module intends to write is 0
    //3:When the err_info sent by the used module is to be written into the err_info RAM and its fatal value is 1, the error handling for the used module can only be considered as completed after the actual assertion of hardware_stop_vld

    assign used_err_process_finish = ~used_wr_used_info_ram_en || (used_wr_used_info_ram_en && ~err_info_fatal_d1 && ~used_err_info_wr_dat.fatal) || (err_stop_rdy && used_wr_used_info_ram_en && used_err_info_wr_dat.fatal);
    
    //=============================idx_eng_err_process_finish = 1 || 2===================================//
    //1:When the fatal value read from the err_info RAM is 1, the err_info sent by the idx_engine module is not written into the err_info RAM.
    //2:When the fatal value read from the err_info RAM is 0, the error handling of the idx_engine module can only be considered as completed after the actual assertion of hardware_stop_vld.

    assign idx_eng_err_process_finish = err_info_fatal_d1 || (~err_info_fatal_d1 && err_stop_rdy);
    
    //=============================err_stop_vld = 1 || 2=================================//
    //1:When err_cstat is equal to USED_ERR_PROCESS, the used module writes to the err_info RAM, and the fatal value in the err_info being written is 1, then err_stop_vld will be asserted.
    //2:When err_cstat is equal to IDX_ENG_ERR_PROCESS, and the fatal value read from the err_info RAM is 0, then err_stop_vld will be asserted.

    assign err_stop_vld = ((err_cstat == USED_ERR_PROCESS) && used_wr_used_info_ram_en && used_err_info_wr_dat.fatal) || ((err_cstat == IDX_ENG_ERR_PROCESS) && ~err_info_fatal_d1);
    
    //===========idx_engine module and used module write err_info ram wren=============================//
    assign idx_eng_err_info_wen = (err_cstat == IDX_ENG_ERR_PROCESS) && idx_eng_err_process_finish && ~err_info_fatal_d1;
    assign used_err_info_wen = (err_cstat == USED_ERR_PROCESS) && used_err_process_finish && used_wr_used_info_ram_en;
    
    //When err_stop_vld is 1, cstat == IDLE, and the used module does not read ctrl_ram, hardware_stop_en is 1.
    assign hardware_stop_en = (cstat == IDLE) && err_stop_vld && (~used_ring_irq_rd_req_vld);

    //======for timing==========//
    logic [$bits(virtio_qstat_t)-1:0] ctrl_ram_q_status_d1;
    logic ctrl_ram_forced_shutdown_d1;

    always @(posedge clk) begin
        ctrl_ram_q_status_d1 <= ctrl_ram_doutb[$bits(virtio_qstat_t)-1:0];
        ctrl_ram_forced_shutdown_d1 <= ctrl_ram_doutb[$bits(virtio_qstat_t)];
    end

    //============================err_stop FSM=======================//
    always @(posedge clk) begin
        if(rst) begin
            err_stop_cstat <= ERR_STOP_IDLE;
        end else begin
            err_stop_cstat <= err_stop_nstat;
        end
    end

    always @(*) begin
        err_stop_nstat = err_stop_cstat;
        case(err_stop_cstat) 
            ERR_STOP_IDLE: begin
                if(hardware_stop_en) begin
                    err_stop_nstat = ERR_STOP_NOP;
                end
            end
            ERR_STOP_NOP: begin
                err_stop_nstat = ERR_STOP_QUERY;
            end
            ERR_STOP_QUERY: begin
                if((ctrl_ram_q_status_d1 == VIRTIO_Q_STATUS_DOING) || ((ctrl_ram_q_status_d1 == VIRTIO_Q_STATUS_STOPPING) && ~ctrl_ram_forced_shutdown_d1)) begin
                    err_stop_nstat = ERR_STOP_DOING;
                end else begin
                    err_stop_nstat = ERR_STOP_IDLE;
                end
            end
            ERR_STOP_DOING: begin
                err_stop_nstat = ERR_STOP_IDLE;
            end
            default: err_stop_nstat = ERR_STOP_IDLE;
        endcase
    end

    assign err_stop_rdy = ((err_stop_cstat == ERR_STOP_QUERY) && ~((ctrl_ram_q_status_d1 == VIRTIO_Q_STATUS_DOING) || ((ctrl_ram_q_status_d1 == VIRTIO_Q_STATUS_STOPPING) && ~ctrl_ram_forced_shutdown_d1))) || (err_stop_cstat == ERR_STOP_DOING);

    //=================err_info ram for idx_eng and used module write ctx module read=====================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( ERR_INFO_WIDTH         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( ERR_INFO_WIDTH         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_err_info(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (err_info_ram_dina            ),
        .addra          (err_info_ram_addra           ),
        .wea            (err_info_ram_wea             ),
        .addrb          (err_info_ram_addrb           ),
        .doutb          (err_info_ram_doutb           ),
        .parity_ecc_err (err_info_ram_parity_ecc_err  )
    );

    assign err_info_init_dat = {1'b0, VIRTIO_ERR_CODE_NONE};

    assign err_info_ram_dina  = used_err_info_wen ? used_err_info_wr_dat : idx_eng_err_info_wen ? idx_engine_err_info_wr_req_dat : err_info_init_dat;
    assign err_info_ram_addra = used_err_info_wen ? used_err_info_wr_qid : idx_eng_err_info_wen ? idx_engine_err_info_wr_req_qid : sw_vq_addr;
    assign err_info_ram_wea   = idx_eng_err_info_wen || used_err_info_wen || init_all_ram_idx;

    assign err_info_ram_addrb = (err_cstat == USED_RD_ERR_INFO) ? used_err_info_wr_qid : (err_cstat == IDX_ENG_RD_ERR_INFO) ? idx_engine_err_info_wr_req_qid : 'h0;

    //=================err_info_clone ram for software read=====================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( ERR_INFO_WIDTH         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( ERR_INFO_WIDTH         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_err_info_clone_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (err_info_clone_ram_dina            ),
        .addra          (err_info_clone_ram_addra           ),
        .wea            (err_info_clone_ram_wea             ),
        .addrb          (err_info_clone_ram_addrb           ),
        .doutb          (err_info_clone_ram_doutb           ),
        .parity_ecc_err (err_info_clone_ram_parity_ecc_err  )
    );

    assign err_info_clone_ram_dina  = err_info_ram_dina;
    assign err_info_clone_ram_addra = err_info_ram_addra;
    assign err_info_clone_ram_wea   = err_info_ram_wea;

    assign err_info_clone_ram_addrb = sw_vq_addr;
    
    //========================hardware_stop_vld and rdy to used/idx_engine=======================//
    assign hardware_stop_vld = (err_stop_cstat == ERR_STOP_DOING);
    
    always @(posedge clk) begin
        if(err_cstat == USED_ERR_NOP) begin
            hardware_stop_qid <= used_err_info_wr_qid;
        end else if(err_cstat == IDX_ENG_ERR_NOP) begin
            hardware_stop_qid <= idx_engine_err_info_wr_req_qid;
        end
    end

    //assign hardware_stop_qid = (err_cstat == USED_ERR_PROCESS) ? used_err_info_wr_qid : (err_cstat == IDX_ENG_ERR_PROCESS) ? idx_engine_err_info_wr_req_qid : 'h0;
    assign hardware_stop_dat.forced_shutdown = 1'b1;
    assign hardware_stop_dat.q_status = VIRTIO_Q_STATUS_STOPPING;

    assign idx_engine_err_info_wr_req_rdy = (err_cstat == IDX_ENG_ERR_PROCESS) && idx_eng_err_process_finish;
    assign used_err_info_wr_rdy = (err_cstat == USED_ERR_PROCESS) && used_err_process_finish;

    //===============================cstat FSM=============================//
    always @(posedge clk) begin
        if(rst) begin
            cstat <= IDLE;
        end else begin
            cstat <= nstat;
        end
    end

    always @(*) begin
        nstat = cstat;
        case(cstat) 
        IDLE: begin
            if(csr_if.valid && ~err_stop_vld) begin
                nstat = CTX_RD_REQ;
            end
        end
        CTX_RD_REQ: begin
            nstat = CTX_RD_PRO;
        end
        CTX_RD_PRO: begin
            nstat = CTX_RD;
        end
        CTX_RD: begin
            case(csr_if_addr[11:0])
                `VIRTIO_CTX_BDF: begin
                    if(rd_bdf_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_DEV_ID: begin
                    if(rd_dev_id_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_AVAIL_RING_ADDR: begin
                    if(rd_avail_ring_addr_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_USED_RING_ADDR: begin
                    if(rd_used_ring_addr_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_DESC_TBL_ADDR: begin
                    if(rd_desc_tbl_addr_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_QDEPTH: begin
                    if(rd_qdepth_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_INDIRCT_TSO_CSUM_EN: begin
                    if(rd_indirct_support_tso_en_csum_en_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_MAX_LEN: begin
                    if(rd_max_len_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_GENERATION: begin
                    if(rd_generation_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_CTRL: begin
                    if(rd_ctrl_done && (~software_initiated_start || (software_initiated_start && rd_avail_idx_blk_ds_ptr_blk_us_ptr_done))) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_AVAIL_IDX_BLK_DS_PTR_BLK_US_PTR: begin
                    if(rd_avail_idx_blk_ds_ptr_blk_us_ptr_done && rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_UI_PI_CI_USED_PTR: begin
                    if(rd_ui_pi_ci_used_ptr_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_SOC_NOTIFY: begin
                    if(rd_ctrl_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_IDX_ENG_NO_NOTIFY_RD_REQ_RSP_NUM: begin
                    if(rd_no_notify_req_rsp_num_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_USED_ELEM_PTR_ERR_FATAL_FLAG: begin
                    if(rd_used_elem_ptr_err_fatal_flag_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_ERR_INFO: begin
                    if(rd_err_info_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_MSIX_ADDR: begin
                    if(rd_msix_addr_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_MSIX_DATA: begin
                    if(rd_msix_data_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_MSIX_ENABLE: begin
                    if(rd_msix_enable_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_MSIX_MASK: begin
                    if(rd_msix_mask_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                 `VIRTIO_CTX_MSIX_PENDING: begin
                    if(rd_msix_pending_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_MSIX_AGGREGATION_TIME: begin
                    if(rd_msix_aggregation_time_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_MSIX_AGGREGATION_THRESHOLD: begin
                    if(rd_msix_aggregation_threshold_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_MSIX_AGGREGATION_INFO_LOW, `VIRTIO_CTX_MSIX_AGGREGATION_INFO_HIGH: begin
                    if(rd_msix_aggregation_info_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_QOS_ENABLE: begin
                    if(rd_qos_enable_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_QOS_L1_UNIT: begin
                    if(rd_qos_l1_unit_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_NET_IDX_LIMIT_PER_QUEUE: begin
                    if(rd_net_idx_limit_per_queue_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_BLK_DESC_ENG_DESC_TBL_ADDR: begin
                    if(rd_blk_desc_eng_desc_tbl_addr_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_BLK_DESC_ENG_DESC_TBL_SIZE: begin
                    if(rd_blk_desc_eng_desc_tbl_size_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_BLK_DESC_ENG_DESC_TBL_NEXT_ID_CNT: begin
                    if(rd_blk_desc_eng_desc_next_id_desc_cnt_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_BLK_DESC_ENG_IS_INDIRCT_RESUMER_CHAIN_FST_SEG_DATA_LEN: begin
                    if(rd_blk_desc_eng_is_indirct_resumer_data_len_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_NET_DESC_ENG_HEAD_TAIL_SLOT: begin
                    if(rd_net_desc_eng_tail_vld_head_slot_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_NET_TX_IDX_LIMIT_PER_DEV: begin
                    if(rd_net_tx_idx_limit_per_dev_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_NET_RX_IDX_LIMIT_PER_DEV: begin
                    if(rd_net_rx_idx_limit_per_dev_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                `VIRTIO_CTX_USED_IRQ_CNT: begin
                    if(rd_used_irq_cnt_done) begin
                        nstat = CTX_EXEC;
                    end
                end
                default: nstat = CTX_EXEC;                              
            endcase
        end
        CTX_EXEC: begin
            if(software_initiated_start) begin
                if(all_init_done) begin
                    nstat = CTX_WR;
                end 
            end else begin
                nstat = CTX_WR;
            end
        end
        CTX_WR: begin
            case(csr_if_addr[11:0])
                `VIRTIO_CTX_MSIX_MASK: begin
                    if(wr_msix_mask_done) begin
                        nstat = CTX_RSP;
                    end
                end
                `VIRTIO_CTX_AVAIL_IDX_BLK_DS_PTR_BLK_US_PTR: begin
                    if(wr_avail_idx_done) begin
                        nstat = CTX_RSP;
                    end
                end
                `VIRTIO_CTX_USED_IRQ_CNT: begin
                    if(wr_used_irq_cnt_done) begin
                        nstat = CTX_RSP;
                    end
                end
                default: nstat = CTX_RSP;
            endcase
        end
        CTX_RSP: begin
            if(csr_if.rready || ~csr_if_read) begin
                nstat = IDLE;
            end
        end 
        endcase
    end

    always @(posedge clk) begin
        if(cstat == IDLE) begin
            csr_if_addr  <= csr_if.addr;
            csr_if_wdata <= csr_if.wdata;
            csr_if_read  <= csr_if.read;
        end
    end

    assign csr_if.ready   = (cstat == CTX_RSP) && (csr_if.rready || ~csr_if_read);
    assign csr_if.rvalid  = (cstat == CTX_RSP) && csr_if_read;
    assign csr_if.rdata   = csr_if_rdata;

    always @(posedge clk) begin
        if(cstat == CTX_EXEC) begin
            case(csr_if_addr[11:0])
                `VIRTIO_CTX_BDF: begin
                    csr_if_rdata <= virtio_ctx_info.bdf;
                end
                `VIRTIO_CTX_DEV_ID: begin
                    csr_if_rdata <= virtio_ctx_info.dev_id;
                end
                `VIRTIO_CTX_AVAIL_RING_ADDR: begin
                    csr_if_rdata <= virtio_ctx_info.avail_ring_addr;
                end
                `VIRTIO_CTX_USED_RING_ADDR: begin
                    csr_if_rdata <= virtio_ctx_info.used_ring_addr;
                end
                `VIRTIO_CTX_DESC_TBL_ADDR: begin
                    csr_if_rdata <= virtio_ctx_info.desc_tbl_addr;
                end
                `VIRTIO_CTX_QDEPTH: begin
                    csr_if_rdata <= virtio_ctx_info.qdepth;
                end
                `VIRTIO_CTX_INDIRCT_TSO_CSUM_EN: begin
                    csr_if_rdata <= virtio_ctx_info.indirct_support_tso_en_csum_en;
                end
                `VIRTIO_CTX_MAX_LEN: begin
                    csr_if_rdata <= virtio_ctx_info.max_len;
                end
                `VIRTIO_CTX_GENERATION: begin
                    csr_if_rdata <= virtio_ctx_info.generation;
                end
                `VIRTIO_CTX_CTRL: begin
                    csr_if_rdata <= {virtio_ctx_info.forced_shutdown, virtio_ctx_info.q_status};
                end
                `VIRTIO_CTX_AVAIL_IDX_BLK_DS_PTR_BLK_US_PTR: begin
                    csr_if_rdata <= {virtio_ctx_info.blk_us_ptr, virtio_ctx_info.blk_ds_ptr, virtio_ctx_info.avail_idx};
                end
                `VIRTIO_CTX_UI_PI_CI_USED_PTR: begin
                    csr_if_rdata <= {virtio_ctx_info.used_ptr, virtio_ctx_info.ci_ptr, virtio_ctx_info.pi_ptr, virtio_ctx_info.ui_ptr};
                end
                `VIRTIO_CTX_IDX_ENG_NO_NOTIFY_RD_REQ_RSP_NUM: begin
                    csr_if_rdata <= {virtio_ctx_info.no_notify_flag, virtio_ctx_info.no_change_flag, 39'd0, virtio_ctx_info.idx_engine_rd_rsp_num, 9'd0, virtio_ctx_info.idx_engine_rd_req_num};
                end
                `VIRTIO_CTX_USED_ELEM_PTR_ERR_FATAL_FLAG: begin
                    csr_if_rdata <= {virtio_ctx_info.used_err_fatal_flag, 15'd0, virtio_ctx_info.used_elem_ptr};
                end
                `VIRTIO_CTX_ERR_INFO: begin
                    csr_if_rdata <= virtio_ctx_info.err_info;
                end
                `VIRTIO_CTX_MSIX_ADDR: begin
                    csr_if_rdata <= virtio_ctx_info.msix_addr;
                end
                `VIRTIO_CTX_MSIX_DATA: begin
                    csr_if_rdata <= virtio_ctx_info.msix_data;
                end
                `VIRTIO_CTX_MSIX_ENABLE: begin
                    csr_if_rdata <= virtio_ctx_info.msix_enable;
                end
                `VIRTIO_CTX_MSIX_MASK: begin
                    csr_if_rdata <= virtio_ctx_info.msix_mask;
                end
                `VIRTIO_CTX_MSIX_PENDING: begin
                    csr_if_rdata <= virtio_ctx_info.msix_pending;
                end
                `VIRTIO_CTX_MSIX_AGGREGATION_TIME: begin
                    csr_if_rdata <= rd_msix_aggregation_time;
                end
                `VIRTIO_CTX_MSIX_AGGREGATION_THRESHOLD: begin
                   csr_if_rdata <= virtio_ctx_info.msix_aggregation_threshold;
                end
                `VIRTIO_CTX_MSIX_AGGREGATION_INFO_LOW: begin
                    csr_if_rdata <= virtio_ctx_info.msix_aggregation_info_low;
                end
                `VIRTIO_CTX_MSIX_AGGREGATION_INFO_HIGH: begin
                    csr_if_rdata <= virtio_ctx_info.msix_aggregation_info_high;
                end
                `VIRTIO_CTX_QOS_ENABLE: begin
                    csr_if_rdata <= virtio_ctx_info.qos_enable;
                end
                `VIRTIO_CTX_QOS_L1_UNIT: begin
                    csr_if_rdata <= virtio_ctx_info.qos_l1_unit;
                end
                `VIRTIO_CTX_NET_IDX_LIMIT_PER_QUEUE: begin
                    csr_if_rdata <= virtio_ctx_info.net_idx_limit_per_queue;
                end               
                `VIRTIO_CTX_BLK_DESC_ENG_DESC_TBL_ADDR: begin
                    csr_if_rdata <= virtio_ctx_info.blk_desc_eng_desc_tbl_addr;
                end
                `VIRTIO_CTX_BLK_DESC_ENG_DESC_TBL_SIZE: begin
                     csr_if_rdata <= virtio_ctx_info.blk_desc_eng_desc_tbl_size;
                end
                `VIRTIO_CTX_BLK_DESC_ENG_DESC_TBL_NEXT_ID_CNT: begin
                     csr_if_rdata <= virtio_ctx_info.blk_desc_eng_desc_next_id_desc_cnt;
                end
                `VIRTIO_CTX_BLK_DESC_ENG_IS_INDIRCT_RESUMER_CHAIN_FST_SEG_DATA_LEN: begin
                    csr_if_rdata <= virtio_ctx_info.blk_desc_eng_is_indirct_resumer_data_len;
                end
                `VIRTIO_CTX_NET_DESC_ENG_HEAD_TAIL_SLOT: begin
                    csr_if_rdata <= virtio_ctx_info.net_desc_eng_tail_vld_head_slot;
                end
                `VIRTIO_CTX_NET_TX_IDX_LIMIT_PER_DEV: begin
                    csr_if_rdata <= virtio_ctx_info.net_tx_idx_limit_per_dev;
                end
                `VIRTIO_CTX_NET_RX_IDX_LIMIT_PER_DEV: begin
                    csr_if_rdata <= virtio_ctx_info.net_rx_idx_limit_per_dev;
                end
                `VIRTIO_CTX_USED_IRQ_CNT: begin
                    csr_if_rdata <= {virtio_ctx_info.used_dma_write_used_idx_irq_flag, 47'd0, virtio_ctx_info.virtio_used_send_irq_cnt};
                end
            endcase
        end
    end
    
    //========================================soc_notify==================================//
    assign soc_notify_vld = (cstat == CTX_EXEC) && (csr_if_addr[11:0] == `VIRTIO_CTX_SOC_NOTIFY) && ~csr_if_read && ((virtio_ctx_info.q_status == VIRTIO_Q_STATUS_STARTING) || (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_DOING));
    assign soc_notify_qid = virtio_vq_t'(sw_vq_addr);

    always @(posedge clk) begin
        if(rst) begin
            soc_notify_req_vld <= 1'b0;
        end else if(~soc_notify_req_vld || soc_notify_req_rdy) begin
            soc_notify_req_vld <= soc_notify_vld;
        end
    end

    always @(posedge clk) begin
        if(~soc_notify_req_vld || soc_notify_req_rdy) begin
            soc_notify_req_qid <= soc_notify_qid;
        end
    end

    assign vq_pending_chk_req_vld = cstat == CTX_RD_REQ;
    assign vq_pending_chk_req_vq  = sw_vq_addr;
    //assign vq_pending_chk_rsp_ok  = vq_pending_chk_rsp_vld && ~vq_pending_chk_rsp_busy;
    always @(posedge clk) begin
        if(rst) begin
            vq_pending_chk_rsp_ok <= 1'b0;
        end else if(vq_pending_chk_rsp_vld) begin
            vq_pending_chk_rsp_ok <= ~vq_pending_chk_rsp_busy;
        end
    end
    
    assign stop_ptr_equal = (pi_ptr == ui_ptr) && (ci_ptr == used_ptr) && (rd_req_num == rd_rsp_num);
    assign blk_forced_shutdown_stop_ptr_equal = (pi_ptr == ui_ptr) && (ci_ptr == blk_ds_ptr) && (rd_req_num == rd_rsp_num) && (blk_us_ptr == used_ptr);
    
    always @(posedge clk) begin
        if(rst) begin
            q_stop_en <= 1'b0;
        end else if(cstat == IDLE) begin
            q_stop_en <= 1'b0;
        end else if(cstat == CTX_RD_PRO) begin
            if(csr_if_addr[13:12] != VIRTIO_BLK_TYPE) begin //net
                q_stop_en <= stop_ptr_equal;
            end else begin  //blk
                if(forced_shutdown) begin //forced_shutdown stop queue
                    q_stop_en <= blk_forced_shutdown_stop_ptr_equal;
                end else begin
                    q_stop_en <= stop_ptr_equal;
                end
            end
        end
    end

    assign idx_eng_err_wait_process = idx_engine_err_info_wr_req_vld && (csr_if_addr[11+VQ_WIDTH:14] == idx_engine_err_info_wr_req_qid.qid);
    assign indirct_support = (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? desc_eng_net_rx_indirct_support_ram_doutb : (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? desc_eng_net_tx_indirct_support_ram_doutb : blk_desc_eng_indirct_support_ram_doutb;

    always @(posedge clk) begin
        if(cstat == CTX_RD) begin
            virtio_ctx_info.err_info <= err_info_clone_ram_doutb;  //only for software read
            
            if(~idx_engine_ctx_rd_rsp_vld) begin 
                virtio_ctx_info.bdf                   <= idx_engine_bdf_ram_doutb;
                virtio_ctx_info.qdepth                <= idx_engine_qdepth_ram_doutb;
                virtio_ctx_info.no_notify_flag        <= idx_engine_no_notify_rd_req_rsp_num_ram_doutb[15];
                virtio_ctx_info.no_change_flag        <= idx_engine_no_notify_rd_req_rsp_num_ram_doutb[14];
                virtio_ctx_info.idx_engine_rd_req_num <= idx_engine_no_notify_rd_req_rsp_num_ram_doutb[13:7];
                virtio_ctx_info.idx_engine_rd_rsp_num <= idx_engine_no_notify_rd_req_rsp_num_ram_doutb[6:0];
            end

            if((ctx_ctrl_ram_doutb[$bits(virtio_qstat_t)-1:0] == VIRTIO_Q_STATUS_STOPPING) && csr_if_read) begin
                virtio_ctx_info.q_status        <= (q_stop_en && (~idx_eng_err_wait_process) && vq_pending_chk_rsp_ok) ? VIRTIO_Q_STATUS_IDLE : VIRTIO_Q_STATUS_STOPPING;
                virtio_ctx_info.forced_shutdown <= (q_stop_en && (~idx_eng_err_wait_process) && vq_pending_chk_rsp_ok) ? 'b0 : ctx_ctrl_ram_doutb[$bits(virtio_qstat_t)];
            end else begin
                virtio_ctx_info.q_status        <= virtio_qstat_t'(ctx_ctrl_ram_doutb[$bits(virtio_qstat_t)-1:0]);
                virtio_ctx_info.forced_shutdown <= ctx_ctrl_ram_doutb[$bits(virtio_qstat_t)];
            end
            
            if(~idx_engine_ctx_rd_rsp_vld && ~blk_down_stream_ptr_rd_rsp_vld && ~blk_upstream_ptr_rd_rsp_vld) begin
                virtio_ctx_info.avail_idx  <= idx_engine_avail_idx_ram_doutb; 
                virtio_ctx_info.blk_ds_ptr <= blk_down_stream_ptr_ram_doutb;
                virtio_ctx_info.blk_us_ptr <= blk_upstream_ptr_ram_doutb;
            end
            if(~avail_ring_dma_ctx_info_rd_rsp_vld && ~avail_ring_desc_engine_ctx_info_rd_rsp_vld) begin
                virtio_ctx_info.ui_ptr   <= avail_ring_avail_ui_ptr_ram_doutb;
                virtio_ctx_info.pi_ptr   <= avail_ring_avail_pi_ptr_ram_doutb;
                virtio_ctx_info.ci_ptr   <= avail_ring_avail_ci_ptr_ram_doutb;
                virtio_ctx_info.used_ptr <= used_ptr_ram_doutb;
            end
            if(~used_elem_ptr_rd_rsp_vld && ~used_ring_irq_rd_rsp_vld) begin
                virtio_ctx_info.used_elem_ptr       <= used_elem_ptr_ram_doutb;
                virtio_ctx_info.used_err_fatal_flag <= used_err_fatal_flag_ram_doutb;
            end 
            if(~used_ring_irq_rd_rsp_vld) begin
                virtio_ctx_info.dev_id <= used_dev_id_ram_doutb;
                virtio_ctx_info.used_ring_addr <= used_ring_addr_ram_doutb;
                virtio_ctx_info.msix_addr <= used_msix_addr_ram_doutb;
                virtio_ctx_info.msix_data <= used_msix_data_ram_doutb;
                virtio_ctx_info.msix_enable <= used_msix_enable_mask_pending_ram_doutb[2];
                virtio_ctx_info.msix_mask <= used_msix_enable_mask_pending_ram_doutb[1];
                virtio_ctx_info.msix_pending <= used_msix_enable_mask_pending_ram_doutb[0];
            end
            if(~idx_engine_ctx_rd_rsp_vld) begin
                virtio_ctx_info.avail_ring_addr <= idx_engine_avail_ring_addr_ram_doutb;
            end
            if(~desc_engine_net_tx_ctx_info_rd_rsp_vld && ~desc_engine_net_rx_ctx_info_rd_rsp_vld && ~blk_desc_engine_global_info_rd_rsp_vld) begin
                virtio_ctx_info.desc_tbl_addr <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? desc_engine_net_rx_desc_tbl_addr_ram_doutb : (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? desc_engine_net_tx_desc_tbl_addr_ram_doutb : blk_desc_engine_desc_tbl_addr_ram_doutb;
                virtio_ctx_info.max_len <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? desc_eng_net_rx_max_len_ram_doutb : (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? desc_eng_net_tx_max_len_ram_doutb : blk_desc_eng_max_len_ram_doutb;
            end
            if(~msix_aggregation_time_rd_rsp_vld_net_tx && ~msix_aggregation_time_rd_rsp_vld_net_rx) begin
                virtio_ctx_info.msix_aggregation_time <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? used_msix_aggregation_time_net_rx_ram_doutb : (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? used_msix_aggregation_time_net_tx_ram_doutb : 'h0;
            end
            if(~msix_aggregation_threshold_rd_rsp_vld_net_tx && ~msix_aggregation_threshold_rd_rsp_vld_net_rx) begin
                virtio_ctx_info.msix_aggregation_threshold <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? used_msix_aggregation_threshold_net_rx_ram_doutb : (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? used_msix_aggregation_threshold_net_tx_ram_doutb : 'h0;
            end
            if(~msix_aggregation_info_rd_rsp_vld_net_tx && ~msix_aggregation_info_rd_rsp_vld_net_rx) begin
                virtio_ctx_info.msix_aggregation_info_low <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? {used_msix_aggregation_info_net_rx_ram_doutb[39:30], 6'd0, used_msix_aggregation_info_net_rx_ram_doutb[29:20], 6'd0, used_msix_aggregation_info_net_rx_ram_doutb[19:10], 6'd0, used_msix_aggregation_info_net_rx_ram_doutb[9:0]} : 
                (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? {used_msix_aggregation_info_net_tx_ram_doutb[39:30], 6'd0, used_msix_aggregation_info_net_tx_ram_doutb[29:20], 6'd0, used_msix_aggregation_info_net_tx_ram_doutb[19:10], 6'd0, used_msix_aggregation_info_net_tx_ram_doutb[9:0]} 
                : 'h0;
                virtio_ctx_info.msix_aggregation_info_high <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? {used_msix_aggregation_info_net_rx_ram_doutb[79:70], 6'd0, used_msix_aggregation_info_net_rx_ram_doutb[69:60], 6'd0, used_msix_aggregation_info_net_rx_ram_doutb[59:50], 6'd0, used_msix_aggregation_info_net_rx_ram_doutb[49:40]} : 
                (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? {used_msix_aggregation_info_net_tx_ram_doutb[79:70], 6'd0, used_msix_aggregation_info_net_tx_ram_doutb[69:60], 6'd0, used_msix_aggregation_info_net_tx_ram_doutb[59:50], 6'd0, used_msix_aggregation_info_net_tx_ram_doutb[49:40]} 
                : 'h0;
                msix_aggregation_info_net_tx_value <= used_msix_aggregation_info_net_tx_ram_doutb;
                msix_aggregation_info_net_rx_value <= used_msix_aggregation_info_net_rx_ram_doutb;
            end
            if(~net_tx_slot_ctrl_ctx_info_rd_rsp_vld && ~blk_down_stream_qos_info_rd_rsp_vld && ~net_rx_buf_drop_info_rd_rsp_vld) begin
                virtio_ctx_info.qos_enable <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? net_rx_buf_qos_enable_ram_doutb : (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? net_tx_qos_enable_ram_doutb : blk_down_stream_qos_enable_ram_doutb;
                virtio_ctx_info.qos_l1_unit <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? net_rx_buf_qos_unit_ram_doutb : (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? net_tx_qos_unit_ram_doutb : blk_down_stream_qos_unit_ram_doutb;
            end
            if(~blk_down_stream_dma_info_rd_rsp_vld && ~net_rx_buf_drop_info_rd_rsp_vld && ~net_tx_rd_data_ctx_info_rd_rsp_vld) begin
                virtio_ctx_info.generation <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? net_rx_buf_generation_ram_doutb : (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? net_tx_generation_ram_doutb : blk_down_stream_generation_ram_doutb;
            end
            if(~blk_desc_engine_local_info_rd_rsp_vld) begin
                virtio_ctx_info.blk_desc_eng_desc_tbl_addr <= blk_desc_eng_desc_tbl_addr_ram_doutb;
                virtio_ctx_info.blk_desc_eng_desc_tbl_size <= blk_desc_eng_desc_tbl_size_ram_doutb;
                virtio_ctx_info.blk_desc_eng_desc_next_id_desc_cnt <= {blk_desc_eng_desc_cnt_ram_doutb, blk_desc_eng_desc_tbl_next_id_ram_doutb[15:0], blk_desc_eng_desc_tbl_next_id_ram_doutb[31:16]};
            end
            if(~blk_desc_engine_local_info_rd_rsp_vld && ~blk_desc_engine_resumer_rd_rsp_vld && ~blk_down_stream_chain_fst_seg_rd_rsp_vld) begin
                virtio_ctx_info.blk_desc_eng_is_indirct_resumer_data_len <= {blk_desc_eng_data_len_ram_doutb, 29'b0, blk_down_stream_chain_fst_seg_ram_doutb, blk_desc_eng_resumer_ram_doutb, blk_desc_eng_is_indirct_ram_doutb};
            end
            if(~net_tx_rd_data_ctx_info_rd_rsp_vld && ~desc_engine_net_tx_ctx_info_rd_rsp_vld && ~desc_engine_net_rx_ctx_info_rd_rsp_vld && ~blk_desc_engine_global_info_rd_rsp_vld) begin
                virtio_ctx_info.indirct_support_tso_en_csum_en <= {net_tx_tso_en_csum_en_ram_doutb[0], net_tx_tso_en_csum_en_ram_doutb[1], indirct_support};
            end
            if(~net_rx_buf_req_idx_per_queue_rd_rsp_vld && ~desc_engine_net_tx_limit_per_queue_rd_rsp_vld) begin
                virtio_ctx_info.net_idx_limit_per_queue <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? net_rx_buf_idx_limit_per_queue_ram_doutb : (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ? desc_eng_net_tx_idx_limit_per_queue_ram_doutb : 'h0;
            end
            if(~desc_engine_net_tx_limit_per_dev_rd_rsp_vld) begin
                virtio_ctx_info.net_tx_idx_limit_per_dev <= desc_eng_net_tx_idx_limit_per_dev_ram_doutb;
            end
            if(~net_rx_buf_req_idx_per_dev_rd_rsp_vld) begin
                virtio_ctx_info.net_rx_idx_limit_per_dev <= net_rx_buf_idx_limit_per_dev_ram_doutb;
            end
            if(~desc_engine_net_tx_ctx_slot_chain_rd_rsp_vld && ~desc_engine_net_rx_ctx_slot_chain_rd_rsp_vld) begin
                virtio_ctx_info.net_desc_eng_tail_vld_head_slot <= (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) ? {desc_eng_net_rx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH*2:SLOT_WIDTH+1], desc_eng_net_rx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH], {(15-SLOT_WIDTH){1'b0}}, desc_eng_net_rx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH-1:0]} : 
                                                               (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) ?  {desc_eng_net_tx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH*2:SLOT_WIDTH+1], desc_eng_net_tx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH], {(15-SLOT_WIDTH){1'b0}}, desc_eng_net_tx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH-1:0]} : 
                                                               'h0;
            end
            if(~virtio_used_irq_cnt_ram_hw_wea) begin  //mon_send_a_irq_d1 is 0
                virtio_ctx_info.used_dma_write_used_idx_irq_flag <= used_dma_write_used_idx_irq_flag;
                virtio_ctx_info.virtio_used_send_irq_cnt <= virtio_used_irq_cnt_ram_doutb;
            end
        end else if((cstat == CTX_EXEC) && ~csr_if_read) begin
            case(csr_if_addr[9:0])
                `VIRTIO_CTX_CTRL: begin
                    if((virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE) && (csr_if_wdata[3:0] == VIRTIO_Q_STATUS_STARTING)) begin
                        virtio_ctx_info.q_status        <= VIRTIO_Q_STATUS_STARTING;
                        virtio_ctx_info.forced_shutdown <= 1'b0;
                    end else if(virtio_ctx_info.q_status == VIRTIO_Q_STATUS_STARTING) begin
                        if(csr_if_wdata[3:0] == VIRTIO_Q_STATUS_STOPPING) begin
                            virtio_ctx_info.q_status        <= VIRTIO_Q_STATUS_STOPPING;
                            virtio_ctx_info.forced_shutdown <= csr_if_wdata[4];
                        end else if(soc_notify_vld) begin
                            virtio_ctx_info.q_status        <= VIRTIO_Q_STATUS_DOING;
                            virtio_ctx_info.forced_shutdown <= 1'b0;
                        end
                    end else if((virtio_ctx_info.q_status == VIRTIO_Q_STATUS_DOING) && (csr_if_wdata[3:0] == VIRTIO_Q_STATUS_STOPPING)) begin
                        virtio_ctx_info.q_status        <= VIRTIO_Q_STATUS_STOPPING;
                        virtio_ctx_info.forced_shutdown <= csr_if_wdata[4];
                    end else if((virtio_ctx_info.q_status == VIRTIO_Q_STATUS_STOPPING) && (csr_if_wdata[3:0] == VIRTIO_Q_STATUS_DOING) && ~virtio_ctx_info.forced_shutdown) begin
                        virtio_ctx_info.q_status        <= VIRTIO_Q_STATUS_DOING;
                        virtio_ctx_info.forced_shutdown <= 1'b0;
                    end
                end
                `VIRTIO_CTX_DEV_ID: begin
                    virtio_ctx_info.dev_id <= csr_if_wdata;
                end
                `VIRTIO_CTX_BDF: begin
                    virtio_ctx_info.bdf <= csr_if_wdata;
                end
                `VIRTIO_CTX_AVAIL_RING_ADDR: begin
                    virtio_ctx_info.avail_ring_addr <= csr_if_wdata;
                end
                `VIRTIO_CTX_USED_RING_ADDR: begin
                    virtio_ctx_info.used_ring_addr <= csr_if_wdata;
                end
                `VIRTIO_CTX_DESC_TBL_ADDR: begin
                    virtio_ctx_info.desc_tbl_addr <= csr_if_wdata;
                end
                `VIRTIO_CTX_QDEPTH: begin
                    virtio_ctx_info.qdepth <= csr_if_wdata;
                end
                `VIRTIO_CTX_AVAIL_IDX_BLK_DS_PTR_BLK_US_PTR: begin
                    virtio_ctx_info.avail_idx  <= csr_if_wdata[15:0];
                end
                `VIRTIO_CTX_MSIX_ADDR: begin
                    virtio_ctx_info.msix_addr <= csr_if_wdata;
                end
                `VIRTIO_CTX_MSIX_DATA: begin
                    virtio_ctx_info.msix_data <= csr_if_wdata;
                end
                `VIRTIO_CTX_MSIX_ENABLE: begin
                    virtio_ctx_info.msix_enable <= csr_if_wdata;
                end
                `VIRTIO_CTX_MSIX_MASK: begin
                    virtio_ctx_info.msix_mask <= csr_if_wdata;
                end
                `VIRTIO_CTX_MSIX_AGGREGATION_TIME: begin
                    virtio_ctx_info.msix_aggregation_time <= csr_if_wdata;
                end
                `VIRTIO_CTX_MSIX_AGGREGATION_THRESHOLD: begin
                    virtio_ctx_info.msix_aggregation_threshold <= csr_if_wdata;
                end
                `VIRTIO_CTX_QOS_ENABLE: begin
                    virtio_ctx_info.qos_enable <= csr_if_wdata;
                end
                `VIRTIO_CTX_QOS_L1_UNIT: begin
                    virtio_ctx_info.qos_l1_unit <= csr_if_wdata;
                end
                `VIRTIO_CTX_GENERATION: begin
                    virtio_ctx_info.generation <= csr_if_wdata;
                end
                `VIRTIO_CTX_INDIRCT_TSO_CSUM_EN: begin
                    virtio_ctx_info.indirct_support_tso_en_csum_en <= csr_if_wdata;
                end
                `VIRTIO_CTX_MAX_LEN: begin
                    virtio_ctx_info.max_len <= csr_if_wdata;
                end
                `VIRTIO_CTX_NET_IDX_LIMIT_PER_QUEUE: begin
                    virtio_ctx_info.net_idx_limit_per_queue <= csr_if_wdata;
                end
                `VIRTIO_CTX_NET_RX_IDX_LIMIT_PER_DEV: begin
                    virtio_ctx_info.net_rx_idx_limit_per_dev <= csr_if_wdata;
                end
                `VIRTIO_CTX_NET_TX_IDX_LIMIT_PER_DEV: begin
                    virtio_ctx_info.net_tx_idx_limit_per_dev <= csr_if_wdata;
                end
                `VIRTIO_CTX_USED_IRQ_CNT: begin
                    virtio_ctx_info.virtio_used_send_irq_cnt <= csr_if_wdata;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if(cstat == CTX_RD) begin
            if(csr_if_read) begin
                rd_err_info_done <= 1'b1;
                rd_ctrl_done     <= 1'b1;
                if(~idx_engine_ctx_rd_rsp_vld) begin 
                    rd_bdf_done            <= 1'b1;
                    rd_qdepth_done         <= 1'b1;
                    rd_no_notify_req_rsp_num_done    <= 1'b1;
                end
                if(~idx_engine_ctx_rd_rsp_vld && ~blk_down_stream_ptr_rd_rsp_vld && ~blk_upstream_ptr_rd_rsp_vld) begin
                    rd_avail_idx_blk_ds_ptr_blk_us_ptr_done <= 1'b1;
                end
                if(~avail_ring_dma_ctx_info_rd_rsp_vld && ~avail_ring_desc_engine_ctx_info_rd_rsp_vld) begin
                    rd_ui_pi_ci_used_ptr_done <= 1'b1;
                end
                if(~used_elem_ptr_rd_rsp_vld && ~used_ring_irq_rd_rsp_vld) begin
                    rd_used_elem_ptr_err_fatal_flag_done <= 1'b1;
                end 
                if(~used_ring_irq_rd_rsp_vld) begin
                    rd_dev_id_done              <= 1'b1;
                    rd_used_ring_addr_done      <= 1'b1;
                    rd_used_err_fatal_flag_done <= 1'b1;
                    rd_msix_addr_done           <= 1'b1;
                    rd_msix_data_done           <= 1'b1;
                    rd_msix_enable_done         <= 1'b1;
                    rd_msix_mask_done           <= 1'b1;
                    rd_msix_pending_done        <= 1'b1;
                end
                if(~idx_engine_ctx_rd_rsp_vld) begin
                    rd_avail_ring_addr_done <= 1'b1;
                end
                if(~desc_engine_net_tx_ctx_info_rd_rsp_vld && ~desc_engine_net_rx_ctx_info_rd_rsp_vld && ~blk_desc_engine_global_info_rd_rsp_vld) begin
                    rd_desc_tbl_addr_done <= 1'b1;
                    rd_max_len_done       <= 1'b1;
                end
                if(~msix_aggregation_time_rd_rsp_vld_net_tx && ~msix_aggregation_time_rd_rsp_vld_net_rx) begin
                    rd_msix_aggregation_time_done <= 1'b1;
                end
                if(~msix_aggregation_threshold_rd_rsp_vld_net_tx && ~msix_aggregation_threshold_rd_rsp_vld_net_rx) begin
                    rd_msix_aggregation_threshold_done <= 1'b1;
                end
                if(~msix_aggregation_info_rd_rsp_vld_net_tx && ~msix_aggregation_info_rd_rsp_vld_net_rx) begin
                    rd_msix_aggregation_info_done <= 1'b1;
                end
                if(~net_tx_slot_ctrl_ctx_info_rd_rsp_vld && ~blk_down_stream_qos_info_rd_rsp_vld && ~net_rx_buf_drop_info_rd_rsp_vld) begin
                    rd_qos_enable_done  <= 1'b1;
                    rd_qos_l1_unit_done <= 1'b1;
                end
                if(~blk_down_stream_dma_info_rd_rsp_vld && ~net_rx_buf_drop_info_rd_rsp_vld && ~net_tx_rd_data_ctx_info_rd_rsp_vld) begin
                    rd_generation_done <= 1'b1;
                end
                if(~blk_desc_engine_local_info_rd_rsp_vld) begin
                    rd_blk_desc_eng_desc_tbl_addr_done                  <= 1'b1;
                    rd_blk_desc_eng_desc_tbl_size_done                  <= 1'b1;
                    rd_blk_desc_eng_desc_next_id_desc_cnt_done          <= 1'b1;
                end
                if(~blk_desc_engine_local_info_rd_rsp_vld && ~blk_desc_engine_resumer_rd_rsp_vld && ~blk_down_stream_chain_fst_seg_rd_rsp_vld) begin
                    rd_blk_desc_eng_is_indirct_resumer_data_len_done <= 1'b1;
                end
                if(~net_tx_rd_data_ctx_info_rd_rsp_vld && ~desc_engine_net_tx_ctx_info_rd_rsp_vld && ~desc_engine_net_rx_ctx_info_rd_rsp_vld && ~blk_desc_engine_global_info_rd_rsp_vld) begin
                    rd_indirct_support_tso_en_csum_en_done <= 1'b1;
                end
                if(~net_rx_buf_req_idx_per_queue_rd_rsp_vld && ~desc_engine_net_tx_limit_per_queue_rd_rsp_vld) begin
                    rd_net_idx_limit_per_queue_done <= 1'b1;
                end
                if(~desc_engine_net_tx_limit_per_dev_rd_rsp_vld) begin
                    rd_net_tx_idx_limit_per_dev_done <= 1'b1;
                end
                if(~net_rx_buf_req_idx_per_dev_rd_rsp_vld) begin
                    rd_net_rx_idx_limit_per_dev_done <= 1'b1;
                end
                if(~desc_engine_net_tx_ctx_slot_chain_rd_rsp_vld && ~desc_engine_net_rx_ctx_slot_chain_rd_rsp_vld) begin
                    rd_net_desc_eng_tail_vld_head_slot_done <= 1'b1;
                end
                if(~virtio_used_irq_cnt_ram_hw_wea) begin
                    rd_used_irq_cnt_done <= 1'b1;
                end
            end else begin
                rd_err_info_done                                    <= 1'b1; 
                rd_ctrl_done                                        <= 1'b1;
                rd_bdf_done                                         <= 1'b1;
                rd_qdepth_done                                      <= 1'b1;
                rd_no_notify_req_rsp_num_done                       <= 1'b1;
                if(software_initiated_start) begin   //init ptr 
                    if(~idx_engine_ctx_rd_rsp_vld && ~blk_down_stream_ptr_rd_rsp_vld && ~blk_upstream_ptr_rd_rsp_vld) begin
                        rd_avail_idx_blk_ds_ptr_blk_us_ptr_done     <= 1'b1;
                    end
                end else begin
                        rd_avail_idx_blk_ds_ptr_blk_us_ptr_done     <= 1'b1;
                end
                rd_ui_pi_ci_used_ptr_done                           <= 1'b1;
                rd_used_elem_ptr_err_fatal_flag_done                <= 1'b1;
                rd_dev_id_done                                      <= 1'b1;
                rd_used_ring_addr_done                              <= 1'b1;
                rd_used_err_fatal_flag_done                         <= 1'b1;
                rd_msix_addr_done                                   <= 1'b1;
                rd_msix_data_done                                   <= 1'b1;
                rd_msix_enable_done                                 <= 1'b1;
                rd_msix_mask_done                                   <= 1'b1;
                rd_msix_pending_done                                <= 1'b1;
                rd_avail_ring_addr_done                             <= 1'b1;
                rd_desc_tbl_addr_done                               <= 1'b1;
                rd_max_len_done                                     <= 1'b1;
                rd_msix_aggregation_time_done                       <= 1'b1;
                rd_msix_aggregation_threshold_done                  <= 1'b1;
                rd_msix_aggregation_info_done                       <= 1'b1;
                rd_qos_enable_done                                  <= 1'b1;
                rd_qos_l1_unit_done                                 <= 1'b1;
                rd_generation_done                                  <= 1'b1;
                rd_blk_desc_eng_desc_tbl_addr_done                  <= 1'b1;
                rd_blk_desc_eng_desc_tbl_size_done                  <= 1'b1;
                rd_blk_desc_eng_desc_next_id_desc_cnt_done          <= 1'b1;
                rd_blk_desc_eng_is_indirct_resumer_data_len_done    <= 1'b1;
                rd_indirct_support_tso_en_csum_en_done              <= 1'b1;
                rd_net_idx_limit_per_queue_done                     <= 1'b1;
                rd_net_tx_idx_limit_per_dev_done                    <= 1'b1;
                rd_net_rx_idx_limit_per_dev_done                    <= 1'b1;
                rd_net_desc_eng_tail_vld_head_slot_done             <= 1'b1;
                rd_used_irq_cnt_done                                <= 1'b1;
            end
        end else begin
            rd_err_info_done                                    <= 1'b0; 
            rd_ctrl_done                                        <= 1'b0;
            rd_bdf_done                                         <= 1'b0;
            rd_qdepth_done                                      <= 1'b0;
            rd_no_notify_req_rsp_num_done                       <= 1'b0;
            rd_avail_idx_blk_ds_ptr_blk_us_ptr_done             <= 1'b0;
            rd_ui_pi_ci_used_ptr_done                           <= 1'b0;
            rd_used_elem_ptr_err_fatal_flag_done                <= 1'b0;
            rd_dev_id_done                                      <= 1'b0;
            rd_used_ring_addr_done                              <= 1'b0;
            rd_used_err_fatal_flag_done                         <= 1'b0;
            rd_msix_addr_done                                   <= 1'b0;
            rd_msix_data_done                                   <= 1'b0;
            rd_msix_enable_done                                 <= 1'b0;
            rd_msix_mask_done                                   <= 1'b0;
            rd_msix_pending_done                                <= 1'b0;
            rd_avail_ring_addr_done                             <= 1'b0;
            rd_desc_tbl_addr_done                               <= 1'b0;
            rd_max_len_done                                     <= 1'b0;
            rd_msix_aggregation_time_done                       <= 1'b0;
            rd_msix_aggregation_threshold_done                  <= 1'b0;
            rd_msix_aggregation_info_done                       <= 1'b0;
            rd_qos_enable_done                                  <= 1'b0;
            rd_qos_l1_unit_done                                 <= 1'b0;
            rd_generation_done                                  <= 1'b0;
            rd_blk_desc_eng_desc_tbl_addr_done                  <= 1'b0;
            rd_blk_desc_eng_desc_tbl_size_done                  <= 1'b0;
            rd_blk_desc_eng_desc_next_id_desc_cnt_done          <= 1'b0;
            rd_blk_desc_eng_is_indirct_resumer_data_len_done    <= 1'b0;
            rd_indirct_support_tso_en_csum_en_done              <= 1'b0;
            rd_net_idx_limit_per_queue_done                     <= 1'b0;
            rd_net_tx_idx_limit_per_dev_done                    <= 1'b0;
            rd_net_rx_idx_limit_per_dev_done                    <= 1'b0;
            rd_net_desc_eng_tail_vld_head_slot_done             <= 1'b0;
            rd_used_irq_cnt_done                                <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if(cstat == CTX_WR) begin
            if(~csr_if_read) begin
                if(~used_msix_tbl_wr_vld) begin
                    wr_msix_mask_done <= 1'b1;
                end
                if(~idx_engine_ctx_wr_vld && ~blk_down_stream_ptr_wr_req_vld && ~blk_upstream_ptr_wr_req_vld) begin
                    wr_avail_idx_done <= 1'b1;
                end
                if(~virtio_used_irq_cnt_ram_hw_wea) begin
                    wr_used_irq_cnt_done <= 1'b1;
                end
            end
            else begin
                wr_msix_mask_done    <= 1'b1;
                wr_avail_idx_done    <= 1'b1;
                wr_used_irq_cnt_done <= 1'b1;
            end
        end
        else begin
            wr_msix_mask_done    <= 1'b0;
            wr_avail_idx_done    <= 1'b0;
            wr_used_irq_cnt_done <= 1'b0;
        end
    end

    always @(posedge clk) begin
        need_starting            <= (csr_if_addr[11:0] == `VIRTIO_CTX_CTRL) && (csr_if_wdata[3:0] == VIRTIO_Q_STATUS_STARTING) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);
        software_initiated_start <= (csr_if_addr[11:0] == `VIRTIO_CTX_CTRL) && (csr_if_wdata[3:0] == VIRTIO_Q_STATUS_STARTING) && ~csr_if_read;
    end

    assign init_all_ram_idx = (cstat == CTX_EXEC) && need_starting;

    always @(posedge clk) begin
        if(rst) begin
            init_pi_ptr                <= 1'b0;
            init_ui_ptr                <= 1'b0;
            init_ci_ptr                <= 1'b0;
            init_used_ptr              <= 1'b0;
            init_blk_ds_ptr            <= 1'b0;
            init_blk_us_ptr            <= 1'b0;
            init_used_elem_ptr         <= 1'b0;
            init_err_info              <= 1'b0;
            init_idx_eng_no_notify_rd_req_rsp_num <= 1'b0;
            init_msix_aggregation_info_net_rx     <= 1'b0;
            init_msix_aggregation_info_net_tx     <= 1'b0;
            init_blk_ds_chain_1st_seg_flag        <= 1'b0;
            init_used_dma_wr_used_idx_irq_flag    <= 1'b0;
        end else if(cstat == IDLE) begin
            init_pi_ptr                <= 1'b0;
            init_ui_ptr                <= 1'b0;
            init_ci_ptr                <= 1'b0;
            init_used_ptr              <= 1'b0;
            init_blk_ds_ptr            <= 1'b0;
            init_blk_us_ptr            <= 1'b0;
            init_used_elem_ptr         <= 1'b0;
            init_err_info              <= 1'b0;
            init_idx_eng_no_notify_rd_req_rsp_num <= 1'b0;
            init_msix_aggregation_info_net_rx     <= 1'b0;
            init_msix_aggregation_info_net_tx     <= 1'b0;
            init_blk_ds_chain_1st_seg_flag        <= 1'b0;
            init_used_dma_wr_used_idx_irq_flag    <= 1'b0;
        end else if(cstat == CTX_EXEC) begin
            init_pi_ptr                <= init_pi_ptr || ~avail_ring_avail_pi_wr_req_vld;              
            init_ui_ptr                <= init_ui_ptr || ~avail_ring_avail_ui_wr_req_vld;             
            init_ci_ptr                <= init_ci_ptr || ~avail_ring_avail_ci_wr_req_vld;             
            init_used_ptr              <= init_used_ptr || ~used_idx_wr_vld;          
            init_blk_ds_ptr            <= init_blk_ds_ptr || ~blk_down_stream_ptr_wr_req_vld;  
            init_blk_us_ptr            <= init_blk_us_ptr || ~blk_upstream_ptr_wr_req_vld; 
            init_used_elem_ptr         <= init_used_elem_ptr || ~used_elem_ptr_wr_vld;     
            init_err_info              <= init_err_info || (~idx_engine_err_info_wr_req_vld && ~used_err_info_wr_vld);           
            init_idx_eng_no_notify_rd_req_rsp_num <= init_idx_eng_no_notify_rd_req_rsp_num || ~idx_engine_ctx_wr_vld;
            init_msix_aggregation_info_net_rx     <= init_msix_aggregation_info_net_rx || ~msix_aggregation_info_wr_vld_net_rx;
            init_msix_aggregation_info_net_tx     <= init_msix_aggregation_info_net_tx || ~msix_aggregation_info_wr_vld_net_tx;
            init_blk_ds_chain_1st_seg_flag        <= init_blk_ds_chain_1st_seg_flag || ~blk_down_stream_chain_fst_seg_wr_vld;
            init_used_dma_wr_used_idx_irq_flag    <= init_used_dma_wr_used_idx_irq_flag || ~used_dma_write_used_idx_irq_flag_wr_vld;
        end
    end

    assign all_init_done = init_pi_ptr && init_ui_ptr && init_ci_ptr && init_used_ptr && init_blk_ds_ptr && init_idx_eng_no_notify_rd_req_rsp_num && init_msix_aggregation_info_net_tx && init_msix_aggregation_info_net_rx && init_blk_us_ptr && init_used_elem_ptr && init_blk_ds_chain_1st_seg_flag && init_used_dma_wr_used_idx_irq_flag;

    always @(posedge clk) begin
        if(rst) begin
            idx_engine_ctx_rd_rsp_vld                     <= 1'b0;
            avail_ring_dma_ctx_info_rd_rsp_vld            <= 1'b0;
            avail_ring_desc_engine_ctx_info_rd_rsp_vld    <= 1'b0;
            desc_engine_net_rx_ctx_info_rd_rsp_vld        <= 1'b0;
            desc_engine_net_rx_ctx_slot_chain_rd_rsp_vld  <= 1'b0;
            desc_engine_net_tx_ctx_info_rd_rsp_vld        <= 1'b0;
            desc_engine_net_tx_ctx_slot_chain_rd_rsp_vld  <= 1'b0;
            desc_engine_net_tx_limit_per_queue_rd_rsp_vld <= 1'b0;
            desc_engine_net_tx_limit_per_dev_rd_rsp_vld   <= 1'b0;
            blk_desc_engine_resumer_rd_rsp_vld            <= 1'b0;
            blk_desc_engine_global_info_rd_rsp_vld        <= 1'b0;
            blk_desc_engine_local_info_rd_rsp_vld         <= 1'b0;
            blk_down_stream_ptr_rd_rsp_vld                <= 1'b0;
            blk_down_stream_qos_info_rd_rsp_vld           <= 1'b0;
            blk_down_stream_dma_info_rd_rsp_vld           <= 1'b0;
            blk_down_stream_chain_fst_seg_rd_rsp_vld      <= 1'b0;
            blk_upstream_ctx_rsp_vld                      <= 1'b0;
            net_tx_slot_ctrl_ctx_info_rd_rsp_vld          <= 1'b0;
            net_tx_rd_data_ctx_info_rd_rsp_vld            <= 1'b0;
            net_rx_slot_ctrl_dev_id_rd_rsp_vld            <= 1'b0;
            net_rx_wr_data_ctx_rd_rsp_vld                 <= 1'b0;
            net_rx_buf_drop_info_rd_rsp_vld               <= 1'b0;
            net_rx_buf_req_idx_per_queue_rd_rsp_vld       <= 1'b0;
            net_rx_buf_req_idx_per_dev_rd_rsp_vld         <= 1'b0;
            used_ring_irq_rd_rsp_vld                      <= 1'b0;
            used_elem_ptr_rd_rsp_vld                      <= 1'b0;
            msix_aggregation_time_rd_rsp_vld_net_tx       <= 1'b0;
            msix_aggregation_threshold_rd_rsp_vld_net_tx  <= 1'b0;
            msix_aggregation_info_rd_rsp_vld_net_tx       <= 1'b0;
            msix_aggregation_time_rd_rsp_vld_net_rx       <= 1'b0;
            msix_aggregation_threshold_rd_rsp_vld_net_rx  <= 1'b0;
            msix_aggregation_info_rd_rsp_vld_net_rx       <= 1'b0;
            blk_upstream_ptr_rd_rsp_vld                   <= 1'b0;
            avail_ring_avail_addr_rd_rsp_vld              <= 1'b0;
            idx_engine_ctx_rd_rsp_vld                     <= 1'b0;
        end else begin
            avail_ring_dma_ctx_info_rd_rsp_vld            <= avail_ring_dma_ctx_info_rd_req_vld;
            avail_ring_desc_engine_ctx_info_rd_rsp_vld    <= avail_ring_desc_engine_ctx_info_rd_req_vld;
            desc_engine_net_rx_ctx_info_rd_rsp_vld        <= desc_engine_net_rx_ctx_info_rd_req_vld;
            desc_engine_net_rx_ctx_slot_chain_rd_rsp_vld  <= desc_engine_net_rx_ctx_slot_chain_rd_req_vld;
            desc_engine_net_tx_ctx_info_rd_rsp_vld        <= desc_engine_net_tx_ctx_info_rd_req_vld;
            desc_engine_net_tx_ctx_slot_chain_rd_rsp_vld  <= desc_engine_net_tx_ctx_slot_chain_rd_req_vld;
            desc_engine_net_tx_limit_per_queue_rd_rsp_vld <= desc_engine_net_tx_limit_per_queue_rd_req_vld;
            desc_engine_net_tx_limit_per_dev_rd_rsp_vld   <= desc_engine_net_tx_limit_per_dev_rd_req_vld;
            blk_desc_engine_resumer_rd_rsp_vld            <= blk_desc_engine_resumer_rd_req_vld;
            blk_desc_engine_global_info_rd_rsp_vld        <= blk_desc_engine_global_info_rd_req_vld;
            blk_desc_engine_local_info_rd_rsp_vld         <= blk_desc_engine_local_info_rd_req_vld;
            blk_down_stream_ptr_rd_rsp_vld                <= blk_down_stream_ptr_rd_req_vld;
            blk_down_stream_qos_info_rd_rsp_vld           <= blk_down_stream_qos_info_rd_req_vld;
            blk_down_stream_dma_info_rd_rsp_vld           <= blk_down_stream_dma_info_rd_req_vld;
            blk_down_stream_chain_fst_seg_rd_rsp_vld      <= blk_down_stream_chain_fst_seg_rd_req_vld;
            blk_upstream_ctx_rsp_vld                      <= blk_upstream_ctx_req_vld;
            net_tx_slot_ctrl_ctx_info_rd_rsp_vld          <= net_tx_slot_ctrl_ctx_info_rd_req_vld;
            net_tx_rd_data_ctx_info_rd_rsp_vld            <= net_tx_rd_data_ctx_info_rd_req_vld;
            net_rx_slot_ctrl_dev_id_rd_rsp_vld            <= net_rx_slot_ctrl_dev_id_rd_req_vld;
            net_rx_wr_data_ctx_rd_rsp_vld                 <= net_rx_wr_data_ctx_rd_req_vld;
            net_rx_buf_drop_info_rd_rsp_vld               <= net_rx_buf_drop_info_rd_req_vld;
            net_rx_buf_req_idx_per_queue_rd_rsp_vld       <= net_rx_buf_req_idx_per_queue_rd_req_vld;
            net_rx_buf_req_idx_per_dev_rd_rsp_vld         <= net_rx_buf_req_idx_per_dev_rd_req_vld;
            used_ring_irq_rd_rsp_vld                      <= used_ring_irq_rd_req_vld;
            used_elem_ptr_rd_rsp_vld                      <= used_elem_ptr_rd_req_vld;
            msix_aggregation_time_rd_rsp_vld_net_tx       <= msix_aggregation_time_rd_req_vld_net_tx;
            msix_aggregation_threshold_rd_rsp_vld_net_tx  <= msix_aggregation_threshold_rd_req_vld_net_tx;
            msix_aggregation_info_rd_rsp_vld_net_tx       <= msix_aggregation_info_rd_req_vld_net_tx;
            msix_aggregation_time_rd_rsp_vld_net_rx       <= msix_aggregation_time_rd_req_vld_net_rx; 
            msix_aggregation_threshold_rd_rsp_vld_net_rx  <= msix_aggregation_threshold_rd_req_vld_net_rx;
            msix_aggregation_info_rd_rsp_vld_net_rx       <= msix_aggregation_info_rd_req_vld_net_rx;
            blk_upstream_ptr_rd_rsp_vld                   <= blk_upstream_ptr_rd_req_vld;
            avail_ring_avail_addr_rd_rsp_vld              <= avail_ring_avail_addr_rd_req_vld;
            idx_engine_ctx_rd_rsp_vld                     <= idx_engine_ctx_rd_req_vld;
        end
    end

    //=========================ctrl ram for hardware_stop read and used read===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (ctrl_ram_dina            ),
        .addra          (ctrl_ram_addra           ),
        .wea            (ctrl_ram_wea             ),
        .addrb          (ctrl_ram_addrb           ),
        .doutb          (ctrl_ram_doutb           ),
        .parity_ecc_err (ctrl_ram_parity_ecc_err  )
    );

    always @(posedge clk) begin
      if(rst) begin
         ctrl_ram_flush <= 'h1;
      end else if(ctrl_ram_flush_id == {VQ_WIDTH{1'b1}}) begin
         ctrl_ram_flush <= 'h0;
      end
    end

    always @(posedge clk) begin
      if(rst) begin
         ctrl_ram_flush_id <= 'h0;
      end else if(ctrl_ram_flush) begin
         ctrl_ram_flush_id <= ctrl_ram_flush_id + 1'b1;
      end
    end

    assign software_wr_vld = ((virtio_ctx_info.q_status != ctx_ctrl_ram_doutb[$bits(virtio_qstat_t)-1:0]) || ~csr_if_read) && (cstat == CTX_WR) && ((csr_if_addr[11:0] == `VIRTIO_CTX_CTRL) || ((csr_if_addr[11:0] == `VIRTIO_CTX_SOC_NOTIFY) && ((virtio_ctx_info.q_status == VIRTIO_Q_STATUS_STARTING) || (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_DOING))));

    assign ctrl_ram_dina = ctrl_ram_flush ? {1'b0, VIRTIO_Q_STATUS_IDLE} : hardware_stop_vld ? hardware_stop_dat : (software_wr_vld && (csr_if_addr[11:0] == `VIRTIO_CTX_SOC_NOTIFY)) ? {1'b0, VIRTIO_Q_STATUS_DOING} : {virtio_ctx_info.forced_shutdown, virtio_ctx_info.q_status};
    assign ctrl_ram_addra = ctrl_ram_flush ? ctrl_ram_flush_id : hardware_stop_vld ? hardware_stop_qid : sw_vq_addr;
    assign ctrl_ram_wea = ctrl_ram_flush || software_wr_vld || hardware_stop_vld;

    //assign ctrl_ram_addrb = ((err_stop_cstat == ERR_STOP_IDLE) && hardware_stop_en) ? hardware_stop_qid : used_ring_irq_rd_req_qid; 

    assign ctrl_ram_addrb = used_ring_irq_rd_req_vld ? used_ring_irq_rd_req_qid : hardware_stop_qid;
    assign used_ring_irq_rd_rsp_q_status = virtio_qstat_t'(ctrl_ram_doutb[$bits(virtio_qstat_t)-1:0]);
    assign used_ring_irq_rd_rsp_forced_shutdown = ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for idx_engine read===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_idx_engine_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (idx_engine_ctrl_ram_dina            ),
        .addra          (idx_engine_ctrl_ram_addra           ),
        .wea            (idx_engine_ctrl_ram_wea             ),
        .addrb          (idx_engine_ctrl_ram_addrb           ),
        .doutb          (idx_engine_ctrl_ram_doutb           ),
        .parity_ecc_err (idx_engine_ctrl_ram_parity_ecc_err  )
    );

    assign idx_engine_ctrl_ram_dina = ctrl_ram_dina;
    assign idx_engine_ctrl_ram_addra = ctrl_ram_addra;
    assign idx_engine_ctrl_ram_wea = ctrl_ram_wea;

    assign idx_engine_ctrl_ram_addrb = idx_engine_ctx_rd_req_qid;
    assign idx_engine_ctx_rd_rsp_ctrl = virtio_qstat_t'(idx_engine_ctrl_ram_doutb[$bits(virtio_qstat_t)-1:0]);
    assign idx_engine_ctx_rd_rsp_force_shutdown = idx_engine_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for ctx module read===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_ctx_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (ctx_ctrl_ram_dina            ),
        .addra          (ctx_ctrl_ram_addra           ),
        .wea            (ctx_ctrl_ram_wea             ),
        .addrb          (ctx_ctrl_ram_addrb           ),
        .doutb          (ctx_ctrl_ram_doutb           ),
        .parity_ecc_err (ctx_ctrl_ram_parity_ecc_err  )
    );

    assign ctx_ctrl_ram_dina = ctrl_ram_dina;
    assign ctx_ctrl_ram_addra = ctrl_ram_addra;
    assign ctx_ctrl_ram_wea = ctrl_ram_wea;

    assign ctx_ctrl_ram_addrb = sw_vq_addr;
    assign forced_shutdown = ctx_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for avail_ring read===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_ctrl_ram_dina            ),
        .addra          (avail_ring_ctrl_ram_addra           ),
        .wea            (avail_ring_ctrl_ram_wea             ),
        .addrb          (avail_ring_ctrl_ram_addrb           ),
        .doutb          (avail_ring_ctrl_ram_doutb           ),
        .parity_ecc_err (avail_ring_ctrl_ram_parity_ecc_err  )
    );

    assign avail_ring_ctrl_ram_dina = ctrl_ram_dina;
    assign avail_ring_ctrl_ram_addra = ctrl_ram_addra;
    assign avail_ring_ctrl_ram_wea = ctrl_ram_wea;

    assign avail_ring_ctrl_ram_addrb = avail_ring_dma_ctx_info_rd_req_qid;
    assign avail_ring_dma_ctx_info_rd_rsp_ctrl = virtio_qstat_t'(avail_ring_ctrl_ram_doutb[$bits(virtio_qstat_t)-1:0]);
    assign avail_ring_dma_ctx_info_rd_rsp_forced_shutdown = avail_ring_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for avail_ring clone read===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_clone_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_clone_ctrl_ram_dina            ),
        .addra          (avail_ring_clone_ctrl_ram_addra           ),
        .wea            (avail_ring_clone_ctrl_ram_wea             ),
        .addrb          (avail_ring_clone_ctrl_ram_addrb           ),
        .doutb          (avail_ring_clone_ctrl_ram_doutb           ),
        .parity_ecc_err (avail_ring_clone_ctrl_ram_parity_ecc_err  )
    );

    assign avail_ring_clone_ctrl_ram_dina = ctrl_ram_dina;
    assign avail_ring_clone_ctrl_ram_addra = ctrl_ram_addra;
    assign avail_ring_clone_ctrl_ram_wea = ctrl_ram_wea;

    assign avail_ring_clone_ctrl_ram_addrb = avail_ring_desc_engine_ctx_info_rd_req_qid;
    assign avail_ring_desc_engine_ctx_info_rd_rsp_ctrl = virtio_qstat_t'(avail_ring_clone_ctrl_ram_doutb[$bits(virtio_qstat_t)-1:0]);
    assign avail_ring_desc_engine_ctx_info_rd_rsp_forced_shutdown = avail_ring_clone_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for virtio_desc_engine_net_tx read and csr_if read===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_engine_net_tx_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_engine_net_tx_ctrl_ram_dina            ),
        .addra          (desc_engine_net_tx_ctrl_ram_addra           ),
        .wea            (desc_engine_net_tx_ctrl_ram_wea             ),
        .addrb          (desc_engine_net_tx_ctrl_ram_addrb           ),
        .doutb          (desc_engine_net_tx_ctrl_ram_doutb           ),
        .parity_ecc_err (desc_engine_net_tx_ctrl_ram_parity_ecc_err  )
    );

    always @(posedge clk) begin
      if(rst) begin
         desc_engine_net_tx_ctrl_ram_flush <= 'h1;
      end else if(desc_engine_net_tx_ctrl_ram_flush_id == {Q_WIDTH{1'b1}}) begin
         desc_engine_net_tx_ctrl_ram_flush <= 'h0;
      end
    end

    always @(posedge clk) begin
      if(rst) begin
         desc_engine_net_tx_ctrl_ram_flush_id <= 'h0;
      end else if(desc_engine_net_tx_ctrl_ram_flush) begin
         desc_engine_net_tx_ctrl_ram_flush_id <= desc_engine_net_tx_ctrl_ram_flush_id + 1'b1;
      end
    end

    assign desc_engine_net_tx_software_wr_vld = software_wr_vld && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE);
    assign desc_engine_net_tx_hardware_stop_vld = hardware_stop_vld && (hardware_stop_qid.typ == VIRTIO_NET_TX_TYPE);

    assign desc_engine_net_tx_ctrl_ram_dina = desc_engine_net_tx_ctrl_ram_flush ? VIRTIO_Q_STATUS_IDLE : desc_engine_net_tx_hardware_stop_vld ? hardware_stop_dat : (desc_engine_net_tx_software_wr_vld && csr_if_addr[11:0] == `VIRTIO_CTX_SOC_NOTIFY) ? {1'b0, VIRTIO_Q_STATUS_DOING} : {virtio_ctx_info.forced_shutdown, virtio_ctx_info.q_status};
    assign desc_engine_net_tx_ctrl_ram_addra = desc_engine_net_tx_ctrl_ram_flush ? desc_engine_net_tx_ctrl_ram_flush_id : desc_engine_net_tx_hardware_stop_vld ? hardware_stop_qid : sw_q_addr;
    assign desc_engine_net_tx_ctrl_ram_wea = desc_engine_net_tx_ctrl_ram_flush || desc_engine_net_tx_software_wr_vld || desc_engine_net_tx_hardware_stop_vld;

    assign desc_engine_net_tx_ctrl_ram_addrb = desc_engine_net_tx_ctx_info_rd_req_vq.qid;
    assign desc_engine_net_tx_ctx_info_rd_rsp_forced_shutdown = desc_engine_net_tx_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for virtio_desc_engine_net_rx read ===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_engine_net_rx_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_engine_net_rx_ctrl_ram_dina            ),
        .addra          (desc_engine_net_rx_ctrl_ram_addra           ),
        .wea            (desc_engine_net_rx_ctrl_ram_wea             ),
        .addrb          (desc_engine_net_rx_ctrl_ram_addrb           ),
        .doutb          (desc_engine_net_rx_ctrl_ram_doutb           ),
        .parity_ecc_err (desc_engine_net_rx_ctrl_ram_parity_ecc_err  )
    );

    assign desc_engine_net_rx_software_wr_vld = software_wr_vld && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE);
    assign desc_engine_net_rx_hardware_stop_vld = hardware_stop_vld && (hardware_stop_qid.typ == VIRTIO_NET_RX_TYPE);

    assign desc_engine_net_rx_ctrl_ram_dina = desc_engine_net_tx_ctrl_ram_flush ? VIRTIO_Q_STATUS_IDLE : desc_engine_net_rx_hardware_stop_vld ? hardware_stop_dat : (desc_engine_net_rx_software_wr_vld && csr_if_addr[11:0] == `VIRTIO_CTX_SOC_NOTIFY) ? {1'b0, VIRTIO_Q_STATUS_DOING} : {virtio_ctx_info.forced_shutdown, virtio_ctx_info.q_status};
    assign desc_engine_net_rx_ctrl_ram_addra = desc_engine_net_tx_ctrl_ram_flush ? desc_engine_net_tx_ctrl_ram_flush_id : desc_engine_net_rx_hardware_stop_vld ? hardware_stop_qid : sw_q_addr;
    assign desc_engine_net_rx_ctrl_ram_wea = desc_engine_net_tx_ctrl_ram_flush || desc_engine_net_rx_software_wr_vld || desc_engine_net_rx_hardware_stop_vld;

    assign desc_engine_net_rx_ctrl_ram_addrb = desc_engine_net_rx_ctx_info_rd_req_vq.qid;
    assign desc_engine_net_rx_ctx_info_rd_rsp_forced_shutdown = desc_engine_net_rx_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for net_tx read ===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_tx_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_tx_ctrl_ram_dina            ),
        .addra          (net_tx_ctrl_ram_addra           ),
        .wea            (net_tx_ctrl_ram_wea             ),
        .addrb          (net_tx_ctrl_ram_addrb           ),
        .doutb          (net_tx_ctrl_ram_doutb           ),
        .parity_ecc_err (net_tx_ctrl_ram_parity_ecc_err  )
    );

    assign net_tx_ctrl_ram_dina = desc_engine_net_tx_ctrl_ram_dina;
    assign net_tx_ctrl_ram_addra = desc_engine_net_tx_ctrl_ram_addra;
    assign net_tx_ctrl_ram_wea = desc_engine_net_tx_ctrl_ram_wea;

    assign net_tx_ctrl_ram_addrb = net_tx_rd_data_ctx_info_rd_req_qid.qid;
    assign net_tx_rd_data_ctx_info_rd_rsp_forced_shutdown = net_tx_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for net_rx read ===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_rx_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_rx_ctrl_ram_dina            ),
        .addra          (net_rx_ctrl_ram_addra           ),
        .wea            (net_rx_ctrl_ram_wea             ),
        .addrb          (net_rx_ctrl_ram_addrb           ),
        .doutb          (net_rx_ctrl_ram_doutb           ),
        .parity_ecc_err (net_rx_ctrl_ram_parity_ecc_err  )
    );

    assign net_rx_ctrl_ram_dina = desc_engine_net_rx_ctrl_ram_dina;
    assign net_rx_ctrl_ram_addra = desc_engine_net_rx_ctrl_ram_addra;
    assign net_rx_ctrl_ram_wea = desc_engine_net_rx_ctrl_ram_wea;

    assign net_rx_ctrl_ram_addrb = net_rx_wr_data_ctx_rd_req_qid.qid;
    assign net_rx_wr_data_ctx_rd_rsp_forced_shutdown = net_rx_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for blk_desc_engine read ===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_engine_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_engine_ctrl_ram_dina            ),
        .addra          (blk_desc_engine_ctrl_ram_addra           ),
        .wea            (blk_desc_engine_ctrl_ram_wea             ),
        .addrb          (blk_desc_engine_ctrl_ram_addrb           ),
        .doutb          (blk_desc_engine_ctrl_ram_doutb           ),
        .parity_ecc_err (blk_desc_engine_ctrl_ram_parity_ecc_err  )
    );

    assign blk_software_wr_vld = software_wr_vld && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE);
    assign blk_hardware_stop_vld = hardware_stop_vld && (hardware_stop_qid.typ == VIRTIO_BLK_TYPE);

    assign blk_desc_engine_ctrl_ram_dina = desc_engine_net_tx_ctrl_ram_flush ? VIRTIO_Q_STATUS_IDLE : blk_hardware_stop_vld ? hardware_stop_dat : (blk_software_wr_vld && csr_if_addr[11:0] == `VIRTIO_CTX_SOC_NOTIFY) ? {1'b0, VIRTIO_Q_STATUS_DOING} : {virtio_ctx_info.forced_shutdown, virtio_ctx_info.q_status};
    assign blk_desc_engine_ctrl_ram_addra = desc_engine_net_tx_ctrl_ram_flush ? desc_engine_net_tx_ctrl_ram_flush_id : blk_hardware_stop_vld ? hardware_stop_qid : sw_q_addr;
    assign blk_desc_engine_ctrl_ram_wea = desc_engine_net_tx_ctrl_ram_flush || blk_software_wr_vld || blk_hardware_stop_vld;

    assign blk_desc_engine_ctrl_ram_addrb = blk_desc_engine_global_info_rd_req_qid;
    assign blk_desc_engine_global_info_rd_rsp_forced_shutdown = blk_desc_engine_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for blk_down_stream read ===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_down_stream_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_down_stream_ctrl_ram_dina            ),
        .addra          (blk_down_stream_ctrl_ram_addra           ),
        .wea            (blk_down_stream_ctrl_ram_wea             ),
        .addrb          (blk_down_stream_ctrl_ram_addrb           ),
        .doutb          (blk_down_stream_ctrl_ram_doutb           ),
        .parity_ecc_err (blk_down_stream_ctrl_ram_parity_ecc_err  )
    );

    assign blk_down_stream_ctrl_ram_dina = blk_desc_engine_ctrl_ram_dina;
    assign blk_down_stream_ctrl_ram_addra = blk_desc_engine_ctrl_ram_addra;
    assign blk_down_stream_ctrl_ram_wea = blk_desc_engine_ctrl_ram_wea;

    assign blk_down_stream_ctrl_ram_addrb = blk_down_stream_dma_info_rd_req_qid;
    assign blk_down_stream_dma_info_rd_rsp_forcedown = blk_down_stream_ctrl_ram_doutb[$bits(virtio_qstat_t)];

    //=========================ctrl ram for blk_upstream read ===========================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_ctrl_info_t)         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_upstream_ctrl_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_upstream_ctrl_ram_dina            ),
        .addra          (blk_upstream_ctrl_ram_addra           ),
        .wea            (blk_upstream_ctrl_ram_wea             ),
        .addrb          (blk_upstream_ctrl_ram_addrb           ),
        .doutb          (blk_upstream_ctrl_ram_doutb           ),
        .parity_ecc_err (blk_upstream_ctrl_ram_parity_ecc_err  )
    );

    assign blk_upstream_ctrl_ram_dina = blk_desc_engine_ctrl_ram_dina;
    assign blk_upstream_ctrl_ram_addra = blk_desc_engine_ctrl_ram_addra;
    assign blk_upstream_ctrl_ram_wea = blk_desc_engine_ctrl_ram_wea;

    assign blk_upstream_ctrl_ram_addrb = blk_upstream_ctx_req_qid;
    assign blk_upstream_ctx_rsp_forced_shutdown = blk_upstream_ctrl_ram_doutb[$bits(virtio_qstat_t)];
    assign blk_upstream_ctx_rsp_q_status    = virtio_qstat_t'(blk_upstream_ctrl_ram_doutb[$bits(virtio_qstat_t)-1:0]);
    //==========================dev_id ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( DEV_ID_WIDTH         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( DEV_ID_WIDTH         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_dev_id_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_dev_id_ram_dina            ),
        .addra          (used_dev_id_ram_addra           ),
        .wea            (used_dev_id_ram_wea             ),
        .addrb          (used_dev_id_ram_addrb           ),
        .doutb          (used_dev_id_ram_doutb           ),
        .parity_ecc_err (used_dev_id_ram_parity_ecc_err  )
    );

    assign used_dev_id_ram_dina = virtio_ctx_info.dev_id;
    assign used_dev_id_ram_addra = sw_vq_addr;
    assign used_dev_id_ram_wea = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_DEV_ID) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign used_dev_id_ram_addrb = used_ring_irq_rd_req_vld ? used_ring_irq_rd_req_qid : sw_vq_addr;
    assign used_ring_irq_rd_rsp_dev_id = used_dev_id_ram_doutb;

    //==========================dev_id ram for idx_engine module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( DEV_ID_WIDTH         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( DEV_ID_WIDTH         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_idx_engine_dev_id_ram(
        .rst            (rst                                   ), 
        .clk            (clk                                   ),
        .dina           (idx_engine_dev_id_ram_dina            ),
        .addra          (idx_engine_dev_id_ram_addra           ),
        .wea            (idx_engine_dev_id_ram_wea             ),
        .addrb          (idx_engine_dev_id_ram_addrb           ),
        .doutb          (idx_engine_dev_id_ram_doutb           ),
        .parity_ecc_err (idx_engine_dev_id_ram_parity_ecc_err  )
    );

    assign idx_engine_dev_id_ram_dina = used_dev_id_ram_dina;
    assign idx_engine_dev_id_ram_addra = sw_vq_addr;
    assign idx_engine_dev_id_ram_wea = used_dev_id_ram_wea;

    assign idx_engine_dev_id_ram_addrb =  idx_engine_ctx_rd_req_qid;
    assign idx_engine_ctx_rd_rsp_dev_id = idx_engine_dev_id_ram_doutb;

    //==========================dev_id ram for blk_upstream module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( DEV_ID_WIDTH         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( DEV_ID_WIDTH         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_upstream_dev_id_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_upstream_dev_id_ram_dina            ),
        .addra          (blk_upstream_dev_id_ram_addra           ),
        .wea            (blk_upstream_dev_id_ram_wea             ),
        .addrb          (blk_upstream_dev_id_ram_addrb           ),
        .doutb          (blk_upstream_dev_id_ram_doutb           ),
        .parity_ecc_err (blk_upstream_dev_id_ram_parity_ecc_err  )
    );

    assign blk_upstream_dev_id_ram_dina = used_dev_id_ram_dina;
    assign blk_upstream_dev_id_ram_addra = sw_q_addr;
    assign blk_upstream_dev_id_ram_wea = used_dev_id_ram_wea && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE);

    assign blk_upstream_dev_id_ram_addrb = blk_upstream_ctx_req_qid;
    assign blk_upstream_ctx_rsp_dev_id = blk_upstream_dev_id_ram_doutb;

    //==========================dev_id ram for net_tx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( DEV_ID_WIDTH         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( DEV_ID_WIDTH         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_tx_dev_id_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_tx_dev_id_ram_dina            ),
        .addra          (net_tx_dev_id_ram_addra           ),
        .wea            (net_tx_dev_id_ram_wea             ),
        .addrb          (net_tx_dev_id_ram_addrb           ),
        .doutb          (net_tx_dev_id_ram_doutb           ),
        .parity_ecc_err (net_tx_dev_id_ram_parity_ecc_err  )
    );

    assign net_tx_dev_id_ram_dina = used_dev_id_ram_dina;
    assign net_tx_dev_id_ram_addra = blk_upstream_dev_id_ram_addra;
    assign net_tx_dev_id_ram_wea = used_dev_id_ram_wea && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE);

    assign net_tx_dev_id_ram_addrb = net_tx_slot_ctrl_ctx_info_rd_req_qid.qid;
    assign net_tx_slot_ctrl_ctx_info_rd_rsp_dev_id = net_tx_dev_id_ram_doutb;

    //==========================dev_id ram for net_rx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( DEV_ID_WIDTH         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( DEV_ID_WIDTH         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_rx_dev_id_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_rx_dev_id_ram_dina            ),
        .addra          (net_rx_dev_id_ram_addra           ),
        .wea            (net_rx_dev_id_ram_wea             ),
        .addrb          (net_rx_dev_id_ram_addrb           ),
        .doutb          (net_rx_dev_id_ram_doutb           ),
        .parity_ecc_err (net_rx_dev_id_ram_parity_ecc_err  )
    );

    assign net_rx_dev_id_ram_dina = used_dev_id_ram_dina;
    assign net_rx_dev_id_ram_addra = blk_upstream_dev_id_ram_addra;
    assign net_rx_dev_id_ram_wea = used_dev_id_ram_wea && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE);

    assign net_rx_dev_id_ram_addrb = net_rx_slot_ctrl_dev_id_rd_req_qid.qid;
    assign net_rx_slot_ctrl_dev_id_rd_rsp_dat = net_rx_dev_id_ram_doutb;

    //==========================dev_id ram for rx_buf module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( DEV_ID_WIDTH         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( DEV_ID_WIDTH         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_rx_buf_dev_id_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_rx_buf_dev_id_ram_dina            ),
        .addra          (net_rx_buf_dev_id_ram_addra           ),
        .wea            (net_rx_buf_dev_id_ram_wea             ),
        .addrb          (net_rx_buf_dev_id_ram_addrb           ),
        .doutb          (net_rx_buf_dev_id_ram_doutb           ),
        .parity_ecc_err (net_rx_buf_dev_id_ram_parity_ecc_err  )
    );

    assign net_rx_buf_dev_id_ram_dina = used_dev_id_ram_dina;
    assign net_rx_buf_dev_id_ram_addra = blk_upstream_dev_id_ram_addra;
    assign net_rx_buf_dev_id_ram_wea = net_rx_dev_id_ram_wea;

    assign net_rx_buf_dev_id_ram_addrb = net_rx_buf_req_idx_per_queue_rd_req_qid;
    assign net_rx_buf_req_idx_per_queue_rd_rsp_dev_id = net_rx_buf_dev_id_ram_doutb;

    //==========================bdf ram for idx_engine module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_idx_engine_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (idx_engine_bdf_ram_dina            ),
        .addra          (idx_engine_bdf_ram_addra           ),
        .wea            (idx_engine_bdf_ram_wea             ),
        .addrb          (idx_engine_bdf_ram_addrb           ),
        .doutb          (idx_engine_bdf_ram_doutb           ),
        .parity_ecc_err (idx_engine_bdf_ram_parity_ecc_err  )
    );

    assign idx_engine_bdf_ram_dina = virtio_ctx_info.bdf;
    assign idx_engine_bdf_ram_addra = sw_vq_addr;
    assign idx_engine_bdf_ram_wea = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_BDF) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign idx_engine_bdf_ram_addrb = idx_engine_ctx_rd_req_vld ? idx_engine_ctx_rd_req_qid : sw_vq_addr;
    assign idx_engine_ctx_rd_rsp_bdf = idx_engine_bdf_ram_doutb;

    //==========================bdf ram for avail_ring module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_bdf_ram_dina            ),
        .addra          (avail_ring_bdf_ram_addra           ),
        .wea            (avail_ring_bdf_ram_wea             ),
        .addrb          (avail_ring_bdf_ram_addrb           ),
        .doutb          (avail_ring_bdf_ram_doutb           ),
        .parity_ecc_err (avail_ring_bdf_ram_parity_ecc_err  )
    );

    assign avail_ring_bdf_ram_dina = idx_engine_bdf_ram_dina;
    assign avail_ring_bdf_ram_addra = idx_engine_bdf_ram_addra;
    assign avail_ring_bdf_ram_wea = idx_engine_bdf_ram_wea;

    assign avail_ring_bdf_ram_addrb = avail_ring_dma_ctx_info_rd_req_qid;
    assign avail_ring_dma_ctx_info_rd_rsp_bdf = avail_ring_bdf_ram_doutb;

    //==========================bdf ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_bdf_ram_dina            ),
        .addra          (used_bdf_ram_addra           ),
        .wea            (used_bdf_ram_wea             ),
        .addrb          (used_bdf_ram_addrb           ),
        .doutb          (used_bdf_ram_doutb           ),
        .parity_ecc_err (used_bdf_ram_parity_ecc_err  )
    );

    assign used_bdf_ram_dina = idx_engine_bdf_ram_dina;
    assign used_bdf_ram_addra = idx_engine_bdf_ram_addra;
    assign used_bdf_ram_wea = idx_engine_bdf_ram_wea;

    assign used_bdf_ram_addrb = used_ring_irq_rd_req_qid;
    assign used_ring_irq_rd_rsp_bdf = used_bdf_ram_doutb;

    //==========================bdf ram for virtio_desc_engine_net_tx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_engine_net_tx_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_engine_net_tx_bdf_ram_dina            ),
        .addra          (desc_engine_net_tx_bdf_ram_addra           ),
        .wea            (desc_engine_net_tx_bdf_ram_wea             ),
        .addrb          (desc_engine_net_tx_bdf_ram_addrb           ),
        .doutb          (desc_engine_net_tx_bdf_ram_doutb           ),
        .parity_ecc_err (desc_engine_net_tx_bdf_ram_parity_ecc_err  )
    );

    assign desc_engine_net_tx_bdf_ram_dina = idx_engine_bdf_ram_dina;
    assign desc_engine_net_tx_bdf_ram_addra = sw_q_addr;
    assign desc_engine_net_tx_bdf_ram_wea = idx_engine_bdf_ram_wea && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE);

    assign desc_engine_net_tx_bdf_ram_addrb = desc_engine_net_tx_ctx_info_rd_req_vq.qid;
    assign desc_engine_net_tx_ctx_info_rd_rsp_bdf = desc_engine_net_tx_bdf_ram_doutb;

    //==========================bdf ram for virtio_desc_engine_net_rx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_engine_net_rx_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_engine_net_rx_bdf_ram_dina            ),
        .addra          (desc_engine_net_rx_bdf_ram_addra           ),
        .wea            (desc_engine_net_rx_bdf_ram_wea             ),
        .addrb          (desc_engine_net_rx_bdf_ram_addrb           ),
        .doutb          (desc_engine_net_rx_bdf_ram_doutb           ),
        .parity_ecc_err (desc_engine_net_rx_bdf_ram_parity_ecc_err  )
    );

    assign desc_engine_net_rx_bdf_ram_dina = idx_engine_bdf_ram_dina;
    assign desc_engine_net_rx_bdf_ram_addra = desc_engine_net_tx_bdf_ram_addra;
    assign desc_engine_net_rx_bdf_ram_wea = idx_engine_bdf_ram_wea && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE);

    assign desc_engine_net_rx_bdf_ram_addrb = desc_engine_net_rx_ctx_info_rd_req_vq.qid;
    assign desc_engine_net_rx_ctx_info_rd_rsp_bdf = desc_engine_net_rx_bdf_ram_doutb;

    //==========================bdf ram for net_tx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_tx_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_tx_bdf_ram_dina            ),
        .addra          (net_tx_bdf_ram_addra           ),
        .wea            (net_tx_bdf_ram_wea             ),
        .addrb          (net_tx_bdf_ram_addrb           ),
        .doutb          (net_tx_bdf_ram_doutb           ),
        .parity_ecc_err (net_tx_bdf_ram_parity_ecc_err  )
    );

    assign net_tx_bdf_ram_dina = idx_engine_bdf_ram_dina;
    assign net_tx_bdf_ram_addra = desc_engine_net_tx_bdf_ram_addra;
    assign net_tx_bdf_ram_wea = desc_engine_net_tx_bdf_ram_wea;

    assign net_tx_bdf_ram_addrb = net_tx_rd_data_ctx_info_rd_req_qid.qid;
    assign net_tx_rd_data_ctx_info_rd_rsp_bdf = net_tx_bdf_ram_doutb;

    //==========================bdf ram for net_rx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_rx_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_rx_bdf_ram_dina            ),
        .addra          (net_rx_bdf_ram_addra           ),
        .wea            (net_rx_bdf_ram_wea             ),
        .addrb          (net_rx_bdf_ram_addrb           ),
        .doutb          (net_rx_bdf_ram_doutb           ),
        .parity_ecc_err (net_rx_bdf_ram_parity_ecc_err  )
    );

    assign net_rx_bdf_ram_dina = idx_engine_bdf_ram_dina;
    assign net_rx_bdf_ram_addra = desc_engine_net_tx_bdf_ram_addra;
    assign net_rx_bdf_ram_wea = desc_engine_net_rx_bdf_ram_wea;

    assign net_rx_bdf_ram_addrb = net_rx_wr_data_ctx_rd_req_qid.qid;
    assign net_rx_wr_data_ctx_rd_rsp_bdf = net_rx_bdf_ram_doutb;

    //==========================bdf ram for blk_desc_engine module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_engine_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_engine_bdf_ram_dina            ),
        .addra          (blk_desc_engine_bdf_ram_addra           ),
        .wea            (blk_desc_engine_bdf_ram_wea             ),
        .addrb          (blk_desc_engine_bdf_ram_addrb           ),
        .doutb          (blk_desc_engine_bdf_ram_doutb           ),
        .parity_ecc_err (blk_desc_engine_bdf_ram_parity_ecc_err  )
    );

    assign blk_desc_engine_bdf_ram_dina = idx_engine_bdf_ram_dina;
    assign blk_desc_engine_bdf_ram_addra = desc_engine_net_tx_bdf_ram_addra;
    assign blk_desc_engine_bdf_ram_wea = idx_engine_bdf_ram_wea && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE);

    assign blk_desc_engine_bdf_ram_addrb = blk_desc_engine_global_info_rd_req_qid;
    assign blk_desc_engine_global_info_rd_rsp_bdf = blk_desc_engine_bdf_ram_doutb;

    //==========================bdf ram for blk_down_stream module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_down_stream_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_down_stream_bdf_ram_dina            ),
        .addra          (blk_down_stream_bdf_ram_addra           ),
        .wea            (blk_down_stream_bdf_ram_wea             ),
        .addrb          (blk_down_stream_bdf_ram_addrb           ),
        .doutb          (blk_down_stream_bdf_ram_doutb           ),
        .parity_ecc_err (blk_down_stream_bdf_ram_parity_ecc_err  )
    );

    assign blk_down_stream_bdf_ram_dina = idx_engine_bdf_ram_dina;
    assign blk_down_stream_bdf_ram_addra = desc_engine_net_tx_bdf_ram_addra;
    assign blk_down_stream_bdf_ram_wea = blk_desc_engine_bdf_ram_wea;

    assign blk_down_stream_bdf_ram_addrb = blk_down_stream_dma_info_rd_req_qid;
    assign blk_down_stream_dma_info_rd_rsp_bdf = blk_down_stream_bdf_ram_doutb;

    //==========================bdf ram for blk_upstream module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_upstream_bdf_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_upstream_bdf_ram_dina            ),
        .addra          (blk_upstream_bdf_ram_addra           ),
        .wea            (blk_upstream_bdf_ram_wea             ),
        .addrb          (blk_upstream_bdf_ram_addrb           ),
        .doutb          (blk_upstream_bdf_ram_doutb           ),
        .parity_ecc_err (blk_upstream_bdf_ram_parity_ecc_err  )
    );

    assign blk_upstream_bdf_ram_dina = idx_engine_bdf_ram_dina;
    assign blk_upstream_bdf_ram_addra = desc_engine_net_tx_bdf_ram_addra;
    assign blk_upstream_bdf_ram_wea = blk_desc_engine_bdf_ram_wea;

    assign blk_upstream_bdf_ram_addrb = blk_upstream_ctx_req_qid;
    assign blk_upstream_ctx_rsp_bdf = blk_upstream_bdf_ram_doutb;

     //==========================avail_ring_addr ram for idx_engine module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 64         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 64         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_idx_engine_avail_ring_addr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (idx_engine_avail_ring_addr_ram_dina            ),
        .addra          (idx_engine_avail_ring_addr_ram_addra           ),
        .wea            (idx_engine_avail_ring_addr_ram_wea             ),
        .addrb          (idx_engine_avail_ring_addr_ram_addrb           ),
        .doutb          (idx_engine_avail_ring_addr_ram_doutb           ),
        .parity_ecc_err (idx_engine_avail_ring_addr_ram_parity_ecc_err  )
    );

    assign idx_engine_avail_ring_addr_ram_dina = virtio_ctx_info.avail_ring_addr;
    assign idx_engine_avail_ring_addr_ram_addra = sw_vq_addr;
    assign idx_engine_avail_ring_addr_ram_wea = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_AVAIL_RING_ADDR) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign idx_engine_avail_ring_addr_ram_addrb = idx_engine_ctx_rd_req_vld ? idx_engine_ctx_rd_req_qid : sw_vq_addr;
    assign idx_engine_ctx_rd_rsp_avail_addr = idx_engine_avail_ring_addr_ram_doutb;

     //==========================avail_ring_addr ram for avail_ring module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 64         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 64         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_addr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_addr_ram_dina            ),
        .addra          (avail_ring_addr_ram_addra           ),
        .wea            (avail_ring_addr_ram_wea             ),
        .addrb          (avail_ring_addr_ram_addrb           ),
        .doutb          (avail_ring_addr_ram_doutb           ),
        .parity_ecc_err (avail_ring_addr_ram_parity_ecc_err  )
    );
    assign avail_ring_addr_ram_dina = idx_engine_avail_ring_addr_ram_dina;
    assign avail_ring_addr_ram_addra = sw_vq_addr;
    assign avail_ring_addr_ram_wea = idx_engine_avail_ring_addr_ram_wea;

    assign avail_ring_addr_ram_addrb = avail_ring_avail_addr_rd_req_qid;
    assign avail_ring_avail_addr_rd_rsp_dat = avail_ring_addr_ram_doutb;

    assign avail_ring_avail_addr_rd_req_rdy = 1'b1;

    //always @(posedge clk) begin
    //    if(rst) begin
    //      avail_addr_flag                <= 1'b0;
    //      avail_ring_avail_addr_rd_en_d1 <= 1'b0;
    //      idx_eng_avail_addr_rd_en_d1    <= 1'b0;
    //    end else begin
    //      avail_addr_flag                <= ~avail_addr_flag;
    //      avail_ring_avail_addr_rd_en_d1 <= avail_ring_avail_addr_rd_en;
    //      idx_eng_avail_addr_rd_en_d1    <= idx_eng_avail_addr_rd_en;
    //    end
    //end
//
    //assign idx_engine_avail_addr_rd_req_rdy = avail_addr_flag;
    //assign avail_ring_avail_addr_rd_req_rdy = ~avail_addr_flag;
    //
    //assign idx_eng_avail_addr_rd_en = idx_engine_avail_addr_rd_req_vld && avail_addr_flag;
    //assign avail_ring_avail_addr_rd_en = avail_ring_avail_addr_rd_req_vld && ~avail_addr_flag;
    //
    //assign avail_ring_addr_ram_addrb = idx_eng_avail_addr_rd_en ? idx_engine_avail_addr_rd_req_qid : avail_ring_avail_addr_rd_en ? avail_ring_avail_addr_rd_req_qid : sw_vq_addr;
    //
    //assign avail_ring_avail_addr_rd_rsp_vld = avail_ring_avail_addr_rd_en_d1;
    //assign idx_engine_avail_addr_rd_rsp_vld = idx_eng_avail_addr_rd_en_d1;
    //
    //assign avail_ring_avail_addr_rd_rsp_dat = avail_ring_addr_ram_doutb;
    //assign idx_engine_avail_addr_rd_rsp_dat = avail_ring_addr_ram_doutb;

    //==========================used_ring_addr ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 64         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 64         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_ring_addr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_ring_addr_ram_dina            ),
        .addra          (used_ring_addr_ram_addra           ),
        .wea            (used_ring_addr_ram_wea             ),
        .addrb          (used_ring_addr_ram_addrb           ),
        .doutb          (used_ring_addr_ram_doutb           ),
        .parity_ecc_err (used_ring_addr_ram_parity_ecc_err  )
    );

    assign used_ring_addr_ram_dina = virtio_ctx_info.used_ring_addr;
    assign used_ring_addr_ram_addra = sw_vq_addr;
    assign used_ring_addr_ram_wea = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_USED_RING_ADDR) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign used_ring_addr_ram_addrb = used_ring_irq_rd_req_vld ? used_ring_irq_rd_req_qid : sw_vq_addr;
    assign used_ring_irq_rd_rsp_used_ring_addr = used_ring_addr_ram_doutb;

    //==========================used_ring_addr ram for idx_engine module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 64         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 64         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_idx_engine_used_addr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (idx_engine_used_addr_ram_dina            ),
        .addra          (idx_engine_used_addr_ram_addra           ),
        .wea            (idx_engine_used_addr_ram_wea             ),
        .addrb          (idx_engine_used_addr_ram_addrb           ),
        .doutb          (idx_engine_used_addr_ram_doutb           ),
        .parity_ecc_err (idx_engine_used_addr_ram_parity_ecc_err  )
    );

    assign idx_engine_used_addr_ram_dina = used_ring_addr_ram_dina;
    assign idx_engine_used_addr_ram_addra = sw_vq_addr;
    assign idx_engine_used_addr_ram_wea = used_ring_addr_ram_wea;

    assign idx_engine_used_addr_ram_addrb = idx_engine_ctx_rd_req_qid;
    assign idx_engine_ctx_rd_rsp_used_addr = idx_engine_used_addr_ram_doutb;

    //==========================desc_tbl_addr ram for virtio_desc_engine_net_tx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 64         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 64         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_engine_net_tx_desc_tbl_addr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_engine_net_tx_desc_tbl_addr_ram_dina            ),
        .addra          (desc_engine_net_tx_desc_tbl_addr_ram_addra           ),
        .wea            (desc_engine_net_tx_desc_tbl_addr_ram_wea             ),
        .addrb          (desc_engine_net_tx_desc_tbl_addr_ram_addrb           ),
        .doutb          (desc_engine_net_tx_desc_tbl_addr_ram_doutb           ),
        .parity_ecc_err (desc_engine_net_tx_desc_tbl_addr_ram_parity_ecc_err  )
    );

    assign desc_engine_net_tx_desc_tbl_addr_ram_dina = virtio_ctx_info.desc_tbl_addr;
    assign desc_engine_net_tx_desc_tbl_addr_ram_addra = sw_q_addr;
    assign desc_engine_net_tx_desc_tbl_addr_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_DESC_TBL_ADDR) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign desc_engine_net_tx_desc_tbl_addr_ram_addrb = desc_engine_net_tx_ctx_info_rd_req_vld ? desc_engine_net_tx_ctx_info_rd_req_vq.qid : sw_q_addr;
    assign desc_engine_net_tx_ctx_info_rd_rsp_desc_tbl_addr = desc_engine_net_tx_desc_tbl_addr_ram_doutb;

    //==========================desc_tbl_addr ram for virtio_desc_engine_net_rx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 64         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 64         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_engine_net_rx_desc_tbl_addr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_engine_net_rx_desc_tbl_addr_ram_dina            ),
        .addra          (desc_engine_net_rx_desc_tbl_addr_ram_addra           ),
        .wea            (desc_engine_net_rx_desc_tbl_addr_ram_wea             ),
        .addrb          (desc_engine_net_rx_desc_tbl_addr_ram_addrb           ),
        .doutb          (desc_engine_net_rx_desc_tbl_addr_ram_doutb           ),
        .parity_ecc_err (desc_engine_net_rx_desc_tbl_addr_ram_parity_ecc_err  )
    );

    assign desc_engine_net_rx_desc_tbl_addr_ram_dina = desc_engine_net_tx_desc_tbl_addr_ram_dina;
    assign desc_engine_net_rx_desc_tbl_addr_ram_addra = desc_engine_net_tx_desc_tbl_addr_ram_addra;
    assign desc_engine_net_rx_desc_tbl_addr_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_DESC_TBL_ADDR) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign desc_engine_net_rx_desc_tbl_addr_ram_addrb = desc_engine_net_rx_ctx_info_rd_req_vld ? desc_engine_net_rx_ctx_info_rd_req_vq.qid : sw_q_addr;
    assign desc_engine_net_rx_ctx_info_rd_rsp_desc_tbl_addr = desc_engine_net_rx_desc_tbl_addr_ram_doutb;

    //==========================desc_tbl_addr ram for blk_desc_engine module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 64         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 64         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_engine_desc_tbl_addr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_engine_desc_tbl_addr_ram_dina            ),
        .addra          (blk_desc_engine_desc_tbl_addr_ram_addra           ),
        .wea            (blk_desc_engine_desc_tbl_addr_ram_wea             ),
        .addrb          (blk_desc_engine_desc_tbl_addr_ram_addrb           ),
        .doutb          (blk_desc_engine_desc_tbl_addr_ram_doutb           ),
        .parity_ecc_err (blk_desc_engine_desc_tbl_addr_ram_parity_ecc_err  )
    );

    assign blk_desc_engine_desc_tbl_addr_ram_dina = desc_engine_net_tx_desc_tbl_addr_ram_dina;
    assign blk_desc_engine_desc_tbl_addr_ram_addra = desc_engine_net_tx_desc_tbl_addr_ram_addra;
    assign blk_desc_engine_desc_tbl_addr_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_DESC_TBL_ADDR) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign blk_desc_engine_desc_tbl_addr_ram_addrb = blk_desc_engine_global_info_rd_req_vld ? blk_desc_engine_global_info_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_global_info_rd_rsp_desc_tbl_addr = blk_desc_engine_desc_tbl_addr_ram_doutb;

    //==========================qdepth ram for virtio_desc_engine_net_tx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 4         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 4         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_engine_net_tx_qdepth_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_engine_net_tx_qdepth_ram_dina            ),
        .addra          (desc_engine_net_tx_qdepth_ram_addra           ),
        .wea            (desc_engine_net_tx_qdepth_ram_wea             ),
        .addrb          (desc_engine_net_tx_qdepth_ram_addrb           ),
        .doutb          (desc_engine_net_tx_qdepth_ram_doutb           ),
        .parity_ecc_err (desc_engine_net_tx_qdepth_ram_parity_ecc_err  )
    );

    assign desc_engine_net_tx_qdepth_ram_dina = virtio_ctx_info.qdepth;
    assign desc_engine_net_tx_qdepth_ram_addra = sw_q_addr;
    assign desc_engine_net_tx_qdepth_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_QDEPTH) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign desc_engine_net_tx_qdepth_ram_addrb = desc_engine_net_tx_ctx_info_rd_req_vq.qid;
    assign desc_engine_net_tx_ctx_info_rd_rsp_qdepth = desc_engine_net_tx_qdepth_ram_doutb;

     //==========================qdepth ram for virtio_desc_engine_net_rx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 4         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 4         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_engine_net_rx_qdepth_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_engine_net_rx_qdepth_ram_dina            ),
        .addra          (desc_engine_net_rx_qdepth_ram_addra           ),
        .wea            (desc_engine_net_rx_qdepth_ram_wea             ),
        .addrb          (desc_engine_net_rx_qdepth_ram_addrb           ),
        .doutb          (desc_engine_net_rx_qdepth_ram_doutb           ),
        .parity_ecc_err (desc_engine_net_rx_qdepth_ram_parity_ecc_err  )
    );

    assign desc_engine_net_rx_qdepth_ram_dina = desc_engine_net_tx_qdepth_ram_dina;
    assign desc_engine_net_rx_qdepth_ram_addra = desc_engine_net_tx_qdepth_ram_addra;
    assign desc_engine_net_rx_qdepth_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_QDEPTH) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign desc_engine_net_rx_qdepth_ram_addrb = desc_engine_net_rx_ctx_info_rd_req_vq.qid;
    assign desc_engine_net_rx_ctx_info_rd_rsp_qdepth = desc_engine_net_rx_qdepth_ram_doutb;

     //==========================qdepth ram for blk_desc_engine module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 4         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 4         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_engine_qdepth_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_engine_qdepth_ram_dina            ),
        .addra          (blk_desc_engine_qdepth_ram_addra           ),
        .wea            (blk_desc_engine_qdepth_ram_wea             ),
        .addrb          (blk_desc_engine_qdepth_ram_addrb           ),
        .doutb          (blk_desc_engine_qdepth_ram_doutb           ),
        .parity_ecc_err (blk_desc_engine_qdepth_ram_parity_ecc_err  )
    );

    assign blk_desc_engine_qdepth_ram_dina = desc_engine_net_tx_qdepth_ram_dina;
    assign blk_desc_engine_qdepth_ram_addra = desc_engine_net_tx_qdepth_ram_addra;
    assign blk_desc_engine_qdepth_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_QDEPTH) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign blk_desc_engine_qdepth_ram_addrb = blk_desc_engine_global_info_rd_req_qid;
    assign blk_desc_engine_global_info_rd_rsp_qdepth = blk_desc_engine_qdepth_ram_doutb;

     //==========================qdepth ram for idx_engine module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 4         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 4         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_idx_engine_qdepth_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (idx_engine_qdepth_ram_dina            ),
        .addra          (idx_engine_qdepth_ram_addra           ),
        .wea            (idx_engine_qdepth_ram_wea             ),
        .addrb          (idx_engine_qdepth_ram_addrb           ),
        .doutb          (idx_engine_qdepth_ram_doutb           ),
        .parity_ecc_err (idx_engine_qdepth_ram_parity_ecc_err  )
    );

    assign idx_engine_qdepth_ram_dina = desc_engine_net_tx_qdepth_ram_dina;
    assign idx_engine_qdepth_ram_addra = sw_vq_addr;
    assign idx_engine_qdepth_ram_wea = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_QDEPTH) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign idx_engine_qdepth_ram_addrb = idx_engine_ctx_rd_req_vld ? idx_engine_ctx_rd_req_qid : sw_vq_addr;
    assign idx_engine_ctx_rd_rsp_qdepth = idx_engine_qdepth_ram_doutb;

     //==========================qdepth ram for avail_ring module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 4         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 4         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_qdepth_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_qdepth_ram_dina            ),
        .addra          (avail_ring_qdepth_ram_addra           ),
        .wea            (avail_ring_qdepth_ram_wea             ),
        .addrb          (avail_ring_qdepth_ram_addrb           ),
        .doutb          (avail_ring_qdepth_ram_doutb           ),
        .parity_ecc_err (avail_ring_qdepth_ram_parity_ecc_err  )
    );

    assign avail_ring_qdepth_ram_dina = idx_engine_qdepth_ram_dina;
    assign avail_ring_qdepth_ram_addra = idx_engine_qdepth_ram_addra;
    assign avail_ring_qdepth_ram_wea = idx_engine_qdepth_ram_wea;

    assign avail_ring_qdepth_ram_addrb = avail_ring_dma_ctx_info_rd_req_qid;
    assign avail_ring_dma_ctx_info_rd_rsp_qdepth = avail_ring_qdepth_ram_doutb;

     //==========================qdepth ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 4         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 4         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_qdepth_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_qdepth_ram_dina            ),
        .addra          (used_qdepth_ram_addra           ),
        .wea            (used_qdepth_ram_wea             ),
        .addrb          (used_qdepth_ram_addrb           ),
        .doutb          (used_qdepth_ram_doutb           ),
        .parity_ecc_err (used_qdepth_ram_parity_ecc_err  )
    );

    assign used_qdepth_ram_dina = idx_engine_qdepth_ram_dina;
    assign used_qdepth_ram_addra = idx_engine_qdepth_ram_addra;
    assign used_qdepth_ram_wea = idx_engine_qdepth_ram_wea;

    assign used_qdepth_ram_addrb = used_ring_irq_rd_req_qid;
    assign used_ring_irq_rd_rsp_qdepth = used_qdepth_ram_doutb;

     //==========================avail_idx ram for idx_engine module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_idx_engine_avail_idx_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (idx_engine_avail_idx_ram_dina            ),
        .addra          (idx_engine_avail_idx_ram_addra           ),
        .wea            (idx_engine_avail_idx_ram_wea             ),
        .addrb          (idx_engine_avail_idx_ram_addrb           ),
        .doutb          (idx_engine_avail_idx_ram_doutb           ),
        .parity_ecc_err (idx_engine_avail_idx_ram_parity_ecc_err  )
    );

    assign idx_engine_avail_idx_ram_dina = idx_engine_ctx_wr_vld ? idx_engine_ctx_wr_avail_idx : virtio_ctx_info.avail_idx;
    assign idx_engine_avail_idx_ram_addra = idx_engine_ctx_wr_vld ? idx_engine_ctx_wr_qid : sw_vq_addr;
    assign idx_engine_avail_idx_ram_wea_sw = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_AVAIL_IDX_BLK_DS_PTR_BLK_US_PTR) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);
    assign idx_engine_avail_idx_ram_wea = idx_engine_avail_idx_ram_wea_sw || idx_engine_ctx_wr_vld;

    assign idx_engine_avail_idx_ram_addrb = idx_engine_ctx_rd_req_vld ? idx_engine_ctx_rd_req_qid : sw_vq_addr;
    assign idx_engine_ctx_rd_rsp_avail_idx = idx_engine_avail_idx_ram_doutb;

     //==========================avail_idx ram for avail_ring module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_avail_idx_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_avail_idx_ram_dina            ),
        .addra          (avail_ring_avail_idx_ram_addra           ),
        .wea            (avail_ring_avail_idx_ram_wea             ),
        .addrb          (avail_ring_avail_idx_ram_addrb           ),
        .doutb          (avail_ring_avail_idx_ram_doutb           ),
        .parity_ecc_err (avail_ring_avail_idx_ram_parity_ecc_err  )
    );

    assign avail_ring_avail_idx_ram_dina = idx_engine_avail_idx_ram_dina;
    assign avail_ring_avail_idx_ram_addra = idx_engine_avail_idx_ram_addra;
    assign avail_ring_avail_idx_ram_wea = idx_engine_avail_idx_ram_wea;

    assign avail_ring_avail_idx_ram_addrb = avail_ring_dma_ctx_info_rd_req_qid;
    assign avail_ring_dma_ctx_info_rd_rsp_avail_idx = avail_ring_avail_idx_ram_doutb;

     //==========================avail_idx_clone ram for avail_ring module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_clone_avail_idx_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_clone_avail_idx_ram_dina            ),
        .addra          (avail_ring_clone_avail_idx_ram_addra           ),
        .wea            (avail_ring_clone_avail_idx_ram_wea             ),
        .addrb          (avail_ring_clone_avail_idx_ram_addrb           ),
        .doutb          (avail_ring_clone_avail_idx_ram_doutb           ),
        .parity_ecc_err (avail_ring_clone_avail_idx_ram_parity_ecc_err  )
    );

    assign avail_ring_clone_avail_idx_ram_dina = idx_engine_avail_idx_ram_dina;
    assign avail_ring_clone_avail_idx_ram_addra = idx_engine_avail_idx_ram_addra;
    assign avail_ring_clone_avail_idx_ram_wea = idx_engine_avail_idx_ram_wea;

    assign avail_ring_clone_avail_idx_ram_addrb = avail_ring_desc_engine_ctx_info_rd_req_qid;
    assign avail_ring_desc_engine_ctx_info_rd_rsp_avail_idx = avail_ring_clone_avail_idx_ram_doutb;

     //==========================avail_ui_ptr ram for avail_ring module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_avail_ui_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_avail_ui_ptr_ram_dina            ),
        .addra          (avail_ring_avail_ui_ptr_ram_addra           ),
        .wea            (avail_ring_avail_ui_ptr_ram_wea             ),
        .addrb          (avail_ring_avail_ui_ptr_ram_addrb           ),
        .doutb          (avail_ring_avail_ui_ptr_ram_doutb           ),
        .parity_ecc_err (avail_ring_avail_ui_ptr_ram_parity_ecc_err  )
    );

    assign avail_ring_avail_ui_ptr_ram_dina = avail_ring_avail_ui_wr_req_vld ? avail_ring_avail_ui_wr_req_dat : virtio_ctx_info.avail_idx;
    assign avail_ring_avail_ui_ptr_ram_addra = avail_ring_avail_ui_wr_req_vld ? avail_ring_avail_ui_wr_req_qid : sw_vq_addr;   
    assign avail_ring_avail_ui_ptr_ram_wea = avail_ring_avail_ui_wr_req_vld || init_all_ram_idx;

    assign avail_ring_avail_ui_ptr_ram_addrb = avail_ring_dma_ctx_info_rd_req_vld ? avail_ring_dma_ctx_info_rd_req_qid : sw_vq_addr;
    assign avail_ring_dma_ctx_info_rd_rsp_avail_ui = avail_ring_avail_ui_ptr_ram_doutb;

     //==========================avail_ui_ptr_clone ram for avail_ring module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_clone_avail_ui_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_clone_avail_ui_ptr_ram_dina            ),
        .addra          (avail_ring_clone_avail_ui_ptr_ram_addra           ),
        .wea            (avail_ring_clone_avail_ui_ptr_ram_wea             ),
        .addrb          (avail_ring_clone_avail_ui_ptr_ram_addrb           ),
        .doutb          (avail_ring_clone_avail_ui_ptr_ram_doutb           ),
        .parity_ecc_err (avail_ring_clone_avail_ui_ptr_ram_parity_ecc_err  )
    );

    assign avail_ring_clone_avail_ui_ptr_ram_dina = avail_ring_avail_ui_ptr_ram_dina;
    assign avail_ring_clone_avail_ui_ptr_ram_addra = avail_ring_avail_ui_ptr_ram_addra;   
    assign avail_ring_clone_avail_ui_ptr_ram_wea = avail_ring_avail_ui_ptr_ram_wea;

    assign avail_ring_clone_avail_ui_ptr_ram_addrb = avail_ring_desc_engine_ctx_info_rd_req_qid;
    assign avail_ring_desc_engine_ctx_info_rd_rsp_avail_ui = avail_ring_clone_avail_ui_ptr_ram_doutb;

    //==========================avail_ui_ptr ram for idx_engine module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_idx_engine_avail_ui_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (idx_engine_avail_ui_ptr_ram_dina            ),
        .addra          (idx_engine_avail_ui_ptr_ram_addra           ),
        .wea            (idx_engine_avail_ui_ptr_ram_wea             ),
        .addrb          (idx_engine_avail_ui_ptr_ram_addrb           ),
        .doutb          (idx_engine_avail_ui_ptr_ram_doutb           ),
        .parity_ecc_err (idx_engine_avail_ui_ptr_ram_parity_ecc_err  )
    );

    assign idx_engine_avail_ui_ptr_ram_dina = avail_ring_avail_ui_ptr_ram_dina;
    assign idx_engine_avail_ui_ptr_ram_addra = avail_ring_avail_ui_ptr_ram_addra;   
    assign idx_engine_avail_ui_ptr_ram_wea = avail_ring_avail_ui_ptr_ram_wea;

    assign idx_engine_avail_ui_ptr_ram_addrb = idx_engine_ctx_rd_req_qid;
    assign idx_engine_ctx_rd_rsp_avail_ui = idx_engine_avail_ui_ptr_ram_doutb;

    //==========================avail_ui_ptr ram for ctx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_ui_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (ui_ptr_ram_dina            ),
        .addra          (ui_ptr_ram_addra           ),
        .wea            (ui_ptr_ram_wea             ),
        .addrb          (ui_ptr_ram_addrb           ),
        .doutb          (ui_ptr_ram_doutb           ),
        .parity_ecc_err (ui_ptr_ram_parity_ecc_err  )
    );

    assign ui_ptr_ram_dina = avail_ring_avail_ui_ptr_ram_dina;
    assign ui_ptr_ram_addra = avail_ring_avail_ui_ptr_ram_addra;   
    assign ui_ptr_ram_wea = avail_ring_avail_ui_ptr_ram_wea;

    assign ui_ptr_ram_addrb = sw_vq_addr;
    assign ui_ptr = ui_ptr_ram_doutb;

    //==========================avail_pi_ptr ram for avail_ring module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_avail_pi_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_avail_pi_ptr_ram_dina            ),
        .addra          (avail_ring_avail_pi_ptr_ram_addra           ),
        .wea            (avail_ring_avail_pi_ptr_ram_wea             ),
        .addrb          (avail_ring_avail_pi_ptr_ram_addrb           ),
        .doutb          (avail_ring_avail_pi_ptr_ram_doutb           ),
        .parity_ecc_err (avail_ring_avail_pi_ptr_ram_parity_ecc_err  )
    );

    assign avail_ring_avail_pi_ptr_ram_dina = avail_ring_avail_pi_wr_req_vld ? avail_ring_avail_pi_wr_req_dat : virtio_ctx_info.avail_idx;
    assign avail_ring_avail_pi_ptr_ram_addra = avail_ring_avail_pi_wr_req_vld ? avail_ring_avail_pi_wr_req_qid : sw_vq_addr;   
    assign avail_ring_avail_pi_ptr_ram_wea = avail_ring_avail_pi_wr_req_vld || init_all_ram_idx;

    assign avail_ring_avail_pi_ptr_ram_addrb = avail_ring_desc_engine_ctx_info_rd_req_vld ? avail_ring_desc_engine_ctx_info_rd_req_qid : sw_vq_addr;
    assign avail_ring_desc_engine_ctx_info_rd_rsp_avail_pi = avail_ring_avail_pi_ptr_ram_doutb;

    //==========================avail_pi_ptr ram for ctx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_pi_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (pi_ptr_ram_dina            ),
        .addra          (pi_ptr_ram_addra           ),
        .wea            (pi_ptr_ram_wea             ),
        .addrb          (pi_ptr_ram_addrb           ),
        .doutb          (pi_ptr_ram_doutb           ),
        .parity_ecc_err (pi_ptr_ram_parity_ecc_err  )
    );

    assign pi_ptr_ram_dina = avail_ring_avail_pi_ptr_ram_dina;
    assign pi_ptr_ram_addra = avail_ring_avail_pi_ptr_ram_addra;   
    assign pi_ptr_ram_wea = avail_ring_avail_pi_ptr_ram_wea;

    assign pi_ptr_ram_addrb = sw_vq_addr;
    assign pi_ptr = pi_ptr_ram_doutb;
    
     //==========================avail_ci_ptr ram for avail_ring module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_avail_ci_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_avail_ci_ptr_ram_dina            ),
        .addra          (avail_ring_avail_ci_ptr_ram_addra           ),
        .wea            (avail_ring_avail_ci_ptr_ram_wea             ),
        .addrb          (avail_ring_avail_ci_ptr_ram_addrb           ),
        .doutb          (avail_ring_avail_ci_ptr_ram_doutb           ),
        .parity_ecc_err (avail_ring_avail_ci_ptr_ram_parity_ecc_err  )
    );

    assign avail_ring_avail_ci_ptr_ram_dina = avail_ring_avail_ci_wr_req_vld ? avail_ring_avail_ci_wr_req_dat : virtio_ctx_info.avail_idx;
    assign avail_ring_avail_ci_ptr_ram_addra = avail_ring_avail_ci_wr_req_vld ? avail_ring_avail_ci_wr_req_qid : sw_vq_addr;   
    assign avail_ring_avail_ci_ptr_ram_wea = avail_ring_avail_ci_wr_req_vld || init_all_ram_idx;

    assign avail_ring_avail_ci_ptr_ram_addrb = avail_ring_dma_ctx_info_rd_req_vld ? avail_ring_dma_ctx_info_rd_req_qid : sw_vq_addr;
    assign avail_ring_dma_ctx_info_rd_rsp_avail_ci = avail_ring_avail_ci_ptr_ram_doutb;

    //==========================avail_ci_ptr_clone ram for avail_ring module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_avail_ring_clone_avail_ci_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (avail_ring_clone_avail_ci_ptr_ram_dina            ),
        .addra          (avail_ring_clone_avail_ci_ptr_ram_addra           ),
        .wea            (avail_ring_clone_avail_ci_ptr_ram_wea             ),
        .addrb          (avail_ring_clone_avail_ci_ptr_ram_addrb           ),
        .doutb          (avail_ring_clone_avail_ci_ptr_ram_doutb           ),
        .parity_ecc_err (avail_ring_clone_avail_ci_ptr_ram_parity_ecc_err  )
    );

    assign avail_ring_clone_avail_ci_ptr_ram_dina = avail_ring_avail_ci_ptr_ram_dina;
    assign avail_ring_clone_avail_ci_ptr_ram_addra = avail_ring_avail_ci_ptr_ram_addra;   
    assign avail_ring_clone_avail_ci_ptr_ram_wea = avail_ring_avail_ci_ptr_ram_wea;

    assign avail_ring_clone_avail_ci_ptr_ram_addrb = avail_ring_desc_engine_ctx_info_rd_req_qid;
    assign avail_ring_desc_engine_ctx_info_rd_rsp_avail_ci = avail_ring_clone_avail_ci_ptr_ram_doutb;

    //==========================ci_ptr ram for ctx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_ci_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (ci_ptr_ram_dina            ),
        .addra          (ci_ptr_ram_addra           ),
        .wea            (ci_ptr_ram_wea             ),
        .addrb          (ci_ptr_ram_addrb           ),
        .doutb          (ci_ptr_ram_doutb           ),
        .parity_ecc_err (ci_ptr_ram_parity_ecc_err  )
    );

    assign ci_ptr_ram_dina = avail_ring_avail_ci_ptr_ram_dina;
    assign ci_ptr_ram_addra = avail_ring_avail_ci_ptr_ram_addra;   
    assign ci_ptr_ram_wea = avail_ring_avail_ci_ptr_ram_wea;

    assign ci_ptr_ram_addrb = sw_vq_addr;
    assign ci_ptr = ci_ptr_ram_doutb;

    //==========================no_notify_rd_req_rsp_num ram for idx_engine module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_idx_engine_no_notify_rd_req_rsp_num_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (idx_engine_no_notify_rd_req_rsp_num_ram_dina            ),
        .addra          (idx_engine_no_notify_rd_req_rsp_num_ram_addra           ),
        .wea            (idx_engine_no_notify_rd_req_rsp_num_ram_wea             ),
        .addrb          (idx_engine_no_notify_rd_req_rsp_num_ram_addrb           ),
        .doutb          (idx_engine_no_notify_rd_req_rsp_num_ram_doutb           ),
        .parity_ecc_err (idx_engine_no_notify_rd_req_rsp_num_ram_parity_ecc_err  )
    );

    assign idx_engine_no_notify_rd_req_rsp_num_ram_dina = idx_engine_ctx_wr_vld ? {idx_engine_ctx_wr_no_notify, idx_engine_ctx_wr_no_change, idx_engine_ctx_wr_dma_req_num, idx_engine_ctx_wr_dma_rsp_num} : 'h0;
    assign idx_engine_no_notify_rd_req_rsp_num_ram_addra = idx_engine_ctx_wr_vld ? idx_engine_ctx_wr_qid : sw_vq_addr;   
    assign idx_engine_no_notify_rd_req_rsp_num_ram_wea = idx_engine_ctx_wr_vld || init_all_ram_idx;

    assign idx_engine_no_notify_rd_req_rsp_num_ram_addrb = idx_engine_ctx_rd_req_vld ? idx_engine_ctx_rd_req_qid : sw_vq_addr;
    assign idx_engine_ctx_rd_rsp_no_notify = idx_engine_no_notify_rd_req_rsp_num_ram_doutb[15];
    assign idx_engine_ctx_rd_rsp_no_change = idx_engine_no_notify_rd_req_rsp_num_ram_doutb[14];
    assign idx_engine_ctx_rd_rsp_dma_req_num = idx_engine_no_notify_rd_req_rsp_num_ram_doutb[13:7];
    assign idx_engine_ctx_rd_rsp_dma_rsp_num = idx_engine_no_notify_rd_req_rsp_num_ram_doutb[6:0];

    //==========================no_notify_rd_req_rsp_num ram for ctx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_no_notify_rd_req_rsp_num_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (no_notify_rd_req_rsp_num_ram_dina            ),
        .addra          (no_notify_rd_req_rsp_num_ram_addra           ),
        .wea            (no_notify_rd_req_rsp_num_ram_wea             ),
        .addrb          (no_notify_rd_req_rsp_num_ram_addrb           ),
        .doutb          (no_notify_rd_req_rsp_num_ram_doutb           ),
        .parity_ecc_err (no_notify_rd_req_rsp_num_ram_parity_ecc_err  )
    );

    assign no_notify_rd_req_rsp_num_ram_dina = idx_engine_no_notify_rd_req_rsp_num_ram_dina;
    assign no_notify_rd_req_rsp_num_ram_addra = idx_engine_no_notify_rd_req_rsp_num_ram_addra;   
    assign no_notify_rd_req_rsp_num_ram_wea = idx_engine_no_notify_rd_req_rsp_num_ram_wea;

    assign no_notify_rd_req_rsp_num_ram_addrb = sw_vq_addr;
    assign rd_req_num = no_notify_rd_req_rsp_num_ram_doutb[13:7];
    assign rd_rsp_num = no_notify_rd_req_rsp_num_ram_doutb[6:0];

    //==========================blk_ds_ptr ram for blk_down_stream module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_down_stream_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_down_stream_ptr_ram_dina            ),
        .addra          (blk_down_stream_ptr_ram_addra           ),
        .wea            (blk_down_stream_ptr_ram_wea             ),
        .addrb          (blk_down_stream_ptr_ram_addrb           ),
        .doutb          (blk_down_stream_ptr_ram_doutb           ),
        .parity_ecc_err (blk_down_stream_ptr_ram_parity_ecc_err  )
    );

    assign blk_down_stream_ptr_ram_dina = blk_down_stream_ptr_wr_req_vld ? blk_down_stream_ptr_wr_req_dat : virtio_ctx_info.avail_idx;
    assign blk_down_stream_ptr_ram_addra = blk_down_stream_ptr_wr_req_vld ? blk_down_stream_ptr_wr_req_qid : sw_q_addr;   
    assign blk_down_stream_ptr_ram_wea = blk_down_stream_ptr_wr_req_vld || (init_all_ram_idx && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE));

    assign blk_down_stream_ptr_ram_addrb = blk_down_stream_ptr_rd_req_vld ? blk_down_stream_ptr_rd_req_qid : sw_q_addr;
    assign blk_down_stream_ptr_rd_rsp_dat = blk_down_stream_ptr_ram_doutb;

    //==========================blk_ds_ptr ram for ctx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_ds_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_ds_ptr_ram_dina            ),
        .addra          (blk_ds_ptr_ram_addra           ),
        .wea            (blk_ds_ptr_ram_wea             ),
        .addrb          (blk_ds_ptr_ram_addrb           ),
        .doutb          (blk_ds_ptr_ram_doutb           ),
        .parity_ecc_err (blk_ds_ptr_ram_parity_ecc_err  )
    );

    assign blk_ds_ptr_ram_dina = blk_down_stream_ptr_ram_dina;
    assign blk_ds_ptr_ram_addra = blk_down_stream_ptr_ram_addra;   
    assign blk_ds_ptr_ram_wea = blk_down_stream_ptr_ram_wea;

    assign blk_ds_ptr_ram_addrb = sw_q_addr;
    assign blk_ds_ptr = blk_ds_ptr_ram_doutb;

     //==========================used_ptr ram for used module write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_ptr_ram_dina            ),
        .addra          (used_ptr_ram_addra           ),
        .wea            (used_ptr_ram_wea             ),
        .addrb          (used_ptr_ram_addrb           ),
        .doutb          (used_ptr_ram_doutb           ),
        .parity_ecc_err (used_ptr_ram_parity_ecc_err  )
    );

    assign used_ptr_ram_dina = used_idx_wr_vld ? used_idx_wr_dat : virtio_ctx_info.avail_idx;
    assign used_ptr_ram_addra = used_idx_wr_vld ? used_idx_wr_qid : sw_vq_addr;   
    assign used_ptr_ram_wea = used_idx_wr_vld || init_all_ram_idx;

    assign used_ptr_ram_addrb = sw_vq_addr;
    assign used_ptr = used_ptr_ram_doutb;

    //==========================blk_upstream_ptr ram for blk_upstream module write and read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_upstream_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_upstream_ptr_ram_dina            ),
        .addra          (blk_upstream_ptr_ram_addra           ),
        .wea            (blk_upstream_ptr_ram_wea             ),
        .addrb          (blk_upstream_ptr_ram_addrb           ),
        .doutb          (blk_upstream_ptr_ram_doutb           ),
        .parity_ecc_err (blk_upstream_ptr_ram_parity_ecc_err  )
    );

    assign blk_upstream_ptr_ram_dina = blk_upstream_ptr_wr_req_vld ? blk_upstream_ptr_wr_req_dat : virtio_ctx_info.avail_idx;
    assign blk_upstream_ptr_ram_addra = blk_upstream_ptr_wr_req_vld ? blk_upstream_ptr_wr_req_qid : sw_q_addr;   
    assign blk_upstream_ptr_ram_wea = blk_upstream_ptr_wr_req_vld || (init_all_ram_idx && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE));

    assign blk_upstream_ptr_ram_addrb = blk_upstream_ptr_rd_req_vld ? blk_upstream_ptr_rd_req_qid : sw_q_addr;
    assign blk_upstream_ptr_rd_rsp_dat = blk_upstream_ptr_ram_doutb;

    //==========================blk_upstream_ptr ram for ctx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_us_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_us_ptr_ram_dina            ),
        .addra          (blk_us_ptr_ram_addra           ),
        .wea            (blk_us_ptr_ram_wea             ),
        .addrb          (blk_us_ptr_ram_addrb           ),
        .doutb          (blk_us_ptr_ram_doutb           ),
        .parity_ecc_err (blk_us_ptr_ram_parity_ecc_err  )
    );

    assign blk_us_ptr_ram_dina = blk_upstream_ptr_ram_dina;
    assign blk_us_ptr_ram_addra = blk_upstream_ptr_ram_addra;   
    assign blk_us_ptr_ram_wea = blk_upstream_ptr_ram_wea;

    assign blk_us_ptr_ram_addrb = sw_q_addr;
    assign blk_us_ptr = blk_us_ptr_ram_doutb;

     //==========================used_elem_ptr ram for used module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( $bits(virtio_used_elem_ptr_info_t)         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( $bits(virtio_used_elem_ptr_info_t)         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_elem_ptr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_elem_ptr_ram_dina            ),
        .addra          (used_elem_ptr_ram_addra           ),
        .wea            (used_elem_ptr_ram_wea             ),
        .addrb          (used_elem_ptr_ram_addrb           ),
        .doutb          (used_elem_ptr_ram_doutb           ),
        .parity_ecc_err (used_elem_ptr_ram_parity_ecc_err  )
    );

    assign used_elem_ptr_ram_dina  = used_elem_ptr_wr_vld ? used_elem_ptr_wr_dat : {1'b0, virtio_ctx_info.avail_idx};  //??? 
    assign used_elem_ptr_ram_addra = used_elem_ptr_wr_vld ? used_elem_ptr_wr_qid : sw_vq_addr;   
    assign used_elem_ptr_ram_wea = used_elem_ptr_wr_vld || init_all_ram_idx;

    assign used_elem_ptr_ram_addrb = used_elem_ptr_rd_req_vld ? used_elem_ptr_rd_req_qid : sw_vq_addr;
    assign used_elem_ptr_rd_rsp_dat = used_elem_ptr_ram_doutb;

     //==========================used_err_fatal_flag ram for used module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_err_fatal_flag_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_err_fatal_flag_ram_dina            ),
        .addra          (used_err_fatal_flag_ram_addra           ),
        .wea            (used_err_fatal_flag_ram_wea             ),
        .addrb          (used_err_fatal_flag_ram_addrb           ),
        .doutb          (used_err_fatal_flag_ram_doutb           ),
        .parity_ecc_err (used_err_fatal_flag_ram_parity_ecc_err  )
    );

    assign used_err_fatal_flag_ram_dina = used_err_fatal_wr_vld ? used_err_fatal_wr_dat : 'h0;  
    assign used_err_fatal_flag_ram_addra = used_err_fatal_wr_vld ? used_err_fatal_wr_qid : sw_vq_addr;   
    assign used_err_fatal_flag_ram_wea = used_err_fatal_wr_vld || init_all_ram_idx;

    assign used_err_fatal_flag_ram_addrb = used_ring_irq_rd_req_vld ? used_ring_irq_rd_req_qid : sw_vq_addr;
    assign used_ring_irq_rd_rsp_err_fatal = used_err_fatal_flag_ram_doutb;

     //==========================msix_addr ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 64         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 64         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_msix_addr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_msix_addr_ram_dina            ),
        .addra          (used_msix_addr_ram_addra           ),
        .wea            (used_msix_addr_ram_wea             ),
        .addrb          (used_msix_addr_ram_addrb           ),
        .doutb          (used_msix_addr_ram_doutb           ),
        .parity_ecc_err (used_msix_addr_ram_parity_ecc_err  )
    );

    assign used_msix_addr_ram_dina = virtio_ctx_info.msix_addr;  
    assign used_msix_addr_ram_addra = sw_vq_addr;   
    assign used_msix_addr_ram_wea = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_MSIX_ADDR) && ~csr_if_read;

    assign used_msix_addr_ram_addrb = used_ring_irq_rd_req_vld ? used_ring_irq_rd_req_qid : sw_vq_addr;
    assign used_ring_irq_rd_rsp_msix_addr = used_msix_addr_ram_doutb;

     //==========================msix_data ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 32         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 32         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_msix_data_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_msix_data_ram_dina            ),
        .addra          (used_msix_data_ram_addra           ),
        .wea            (used_msix_data_ram_wea             ),
        .addrb          (used_msix_data_ram_addrb           ),
        .doutb          (used_msix_data_ram_doutb           ),
        .parity_ecc_err (used_msix_data_ram_parity_ecc_err  )
    );

    assign used_msix_data_ram_dina = virtio_ctx_info.msix_data;  
    assign used_msix_data_ram_addra = sw_vq_addr;   
    assign used_msix_data_ram_wea = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_MSIX_DATA) && ~csr_if_read;

    assign used_msix_data_ram_addrb = used_ring_irq_rd_req_vld ? used_ring_irq_rd_req_qid : sw_vq_addr;
    assign used_ring_irq_rd_rsp_msix_data = used_msix_data_ram_doutb;

     //==========================msix_enable_mask_pending ram for used module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 3         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 3         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_msix_enable_mask_pending_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_msix_enable_mask_pending_ram_dina            ),
        .addra          (used_msix_enable_mask_pending_ram_addra           ),
        .wea            (used_msix_enable_mask_pending_ram_wea             ),
        .addrb          (used_msix_enable_mask_pending_ram_addrb           ),
        .doutb          (used_msix_enable_mask_pending_ram_doutb           ),
        .parity_ecc_err (used_msix_enable_mask_pending_ram_parity_ecc_err  )
    );

    assign used_msix_enable_mask_pending_ram_dina = used_msix_tbl_wr_vld ? {virtio_ctx_info.msix_enable, used_msix_tbl_wr_mask, used_msix_tbl_wr_pending} : {virtio_ctx_info.msix_enable, virtio_ctx_info.msix_mask, virtio_ctx_info.msix_pending};  
    assign used_msix_enable_mask_pending_ram_addra = used_msix_tbl_wr_vld ? used_msix_tbl_wr_qid : sw_vq_addr;
    assign used_msix_enable_mask_pending_ram_wea_sw = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_MSIX_ENABLE) && ~csr_if_read;
    assign used_msix_enable_mask_pending_ram_wea = used_msix_tbl_wr_vld || used_msix_enable_mask_pending_ram_wea_sw;

    assign used_msix_enable_mask_pending_ram_addrb = used_ring_irq_rd_req_vld ? used_ring_irq_rd_req_qid : sw_vq_addr;
    assign used_ring_irq_rd_rsp_msix_enable = used_msix_enable_mask_pending_ram_doutb[2];
    assign used_ring_irq_rd_rsp_msix_mask = used_msix_enable_mask_pending_ram_doutb[1];
    assign used_ring_irq_rd_rsp_msix_pending = used_msix_enable_mask_pending_ram_doutb[0];

    //=========================set_mask_pending interface==============================//
    always @(posedge clk) begin
        if(rst) begin
            used_set_mask_req_vld <= 1'b0;
        end else if(~used_set_mask_req_vld || used_set_mask_req_rdy) begin
            used_set_mask_req_vld <= (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_MSIX_MASK) && ~csr_if_read;
        end
    end

    always @(posedge clk) begin
        if(~used_set_mask_req_vld || used_set_mask_req_rdy) begin
            used_set_mask_req_qid <= virtio_vq_t'(sw_vq_addr);
            used_set_mask_req_dat <= csr_if_wdata[0];
        end
    end

     //==========================msix_aggregation_time_net_tx ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( IRQ_MERGE_UINT_NUM*3         ),
        .ADDRA_WIDTH( Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH ),
        .DATAB_WIDTH( IRQ_MERGE_UINT_NUM*3         ),
        .ADDRB_WIDTH( Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "WRITE_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "dist"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_msix_aggregation_time_net_tx_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_msix_aggregation_time_net_tx_ram_dina            ),
        .addra          (used_msix_aggregation_time_net_tx_ram_addra           ),
        .wea            (used_msix_aggregation_time_net_tx_ram_wea             ),
        .addrb          (used_msix_aggregation_time_net_tx_ram_addrb           ),
        .doutb          (used_msix_aggregation_time_net_tx_ram_doutb           ),
        .parity_ecc_err (used_msix_aggregation_time_net_tx_ram_parity_ecc_err  ) 
    );

    always @(posedge clk) begin
        if(cstat == CTX_EXEC) begin
            msix_aggregation_time <= virtio_ctx_info.msix_aggregation_time;
        end
    end

    genvar j;
    generate
    for (j = 0; j < IRQ_MERGE_UINT_NUM; j = j + 1) begin
        always @(*) begin
            if (j == sw_q_addr[IRQ_MERGE_UINT_NUM_WIDTH-1:0]) begin
                msix_aggregation_time_value[j*MSIX_TIME_WIDTH+:MSIX_TIME_WIDTH] = virtio_ctx_info.msix_aggregation_time[MSIX_TIME_WIDTH-1:0];
            end else begin
                msix_aggregation_time_value[j*MSIX_TIME_WIDTH+:MSIX_TIME_WIDTH] = msix_aggregation_time[j*MSIX_TIME_WIDTH+:MSIX_TIME_WIDTH];
            end
        end
    end
    endgenerate
    
    always @(*) begin
        rd_msix_aggregation_time_tmp = 'b0;
        rd_msix_aggregation_time = 'b0;
        if((cstat == CTX_EXEC) && csr_if_read && (csr_if_addr[11:0] == `VIRTIO_CTX_MSIX_AGGREGATION_TIME)) begin
            rd_msix_aggregation_time_tmp = virtio_ctx_info.msix_aggregation_time >> (sw_q_addr[IRQ_MERGE_UINT_NUM_WIDTH-1:0] * IRQ_MERGE_UINT_NUM_WIDTH);
            rd_msix_aggregation_time = rd_msix_aggregation_time_tmp[MSIX_TIME_WIDTH-1:0];
        end
    end
    

    assign used_msix_aggregation_time_net_tx_ram_dina = msix_aggregation_time_value;  
    assign used_msix_aggregation_time_net_tx_ram_addra = (sw_q_addr >> IRQ_MERGE_UINT_NUM_WIDTH);  
    assign used_msix_aggregation_time_net_tx_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_MSIX_AGGREGATION_TIME) && ~csr_if_read;

    assign used_msix_aggregation_time_net_tx_ram_addrb = msix_aggregation_time_rd_req_vld_net_tx ? msix_aggregation_time_rd_req_qid_net_tx : (sw_q_addr >> IRQ_MERGE_UINT_NUM_WIDTH);
    assign msix_aggregation_time_rd_rsp_dat_net_tx = used_msix_aggregation_time_net_tx_ram_doutb;

     //==========================msix_aggregation_time_net_rx ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( IRQ_MERGE_UINT_NUM*3         ),
        .ADDRA_WIDTH( Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH ),
        .DATAB_WIDTH( IRQ_MERGE_UINT_NUM*3         ),
        .ADDRB_WIDTH( Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "WRITE_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "dist"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_msix_aggregation_time_net_rx_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_msix_aggregation_time_net_rx_ram_dina            ),
        .addra          (used_msix_aggregation_time_net_rx_ram_addra           ),
        .wea            (used_msix_aggregation_time_net_rx_ram_wea             ),
        .addrb          (used_msix_aggregation_time_net_rx_ram_addrb           ),
        .doutb          (used_msix_aggregation_time_net_rx_ram_doutb           ),
        .parity_ecc_err (used_msix_aggregation_time_net_rx_ram_parity_ecc_err  )
    );

    assign used_msix_aggregation_time_net_rx_ram_dina = msix_aggregation_time_value;  
    assign used_msix_aggregation_time_net_rx_ram_addra = (sw_q_addr >> IRQ_MERGE_UINT_NUM_WIDTH);  
    assign used_msix_aggregation_time_net_rx_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_MSIX_AGGREGATION_TIME) && ~csr_if_read;

    assign used_msix_aggregation_time_net_rx_ram_addrb = msix_aggregation_time_rd_req_vld_net_rx ? msix_aggregation_time_rd_req_qid_net_rx : (sw_q_addr >> IRQ_MERGE_UINT_NUM_WIDTH);
    assign msix_aggregation_time_rd_rsp_dat_net_rx = used_msix_aggregation_time_net_rx_ram_doutb;

     //==========================msix_aggregation_threshold_net_tx ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 7         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 7         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_msix_aggregation_threshold_net_tx_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_msix_aggregation_threshold_net_tx_ram_dina            ),
        .addra          (used_msix_aggregation_threshold_net_tx_ram_addra           ),
        .wea            (used_msix_aggregation_threshold_net_tx_ram_wea             ),
        .addrb          (used_msix_aggregation_threshold_net_tx_ram_addrb           ),
        .doutb          (used_msix_aggregation_threshold_net_tx_ram_doutb           ),
        .parity_ecc_err (used_msix_aggregation_threshold_net_tx_ram_parity_ecc_err  )
    );

    assign used_msix_aggregation_threshold_net_tx_ram_dina = desc_engine_net_tx_ctrl_ram_flush ? 'h40 : virtio_ctx_info.msix_aggregation_threshold;  
    assign used_msix_aggregation_threshold_net_tx_ram_addra = desc_engine_net_tx_ctrl_ram_flush ? desc_engine_net_tx_ctrl_ram_flush_id : sw_q_addr;  
    assign used_msix_aggregation_threshold_net_tx_ram_wea = ((cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_MSIX_AGGREGATION_THRESHOLD) && ~csr_if_read) || desc_engine_net_tx_ctrl_ram_flush;

    assign used_msix_aggregation_threshold_net_tx_ram_addrb = msix_aggregation_threshold_rd_req_vld_net_tx ? msix_aggregation_threshold_rd_req_qid_net_tx : sw_q_addr;
    assign msix_aggregation_threshold_rd_rsp_dat_net_tx = used_msix_aggregation_threshold_net_tx_ram_doutb;

    //==========================msix_aggregation_threshold_net_rx ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 7         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 7         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_msix_aggregation_threshold_net_rx_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_msix_aggregation_threshold_net_rx_ram_dina            ),
        .addra          (used_msix_aggregation_threshold_net_rx_ram_addra           ),
        .wea            (used_msix_aggregation_threshold_net_rx_ram_wea             ),
        .addrb          (used_msix_aggregation_threshold_net_rx_ram_addrb           ),
        .doutb          (used_msix_aggregation_threshold_net_rx_ram_doutb           ),
        .parity_ecc_err (used_msix_aggregation_threshold_net_rx_ram_parity_ecc_err  )
    );

    assign used_msix_aggregation_threshold_net_rx_ram_dina = desc_engine_net_tx_ctrl_ram_flush ? 'h40 : virtio_ctx_info.msix_aggregation_threshold;  
    assign used_msix_aggregation_threshold_net_rx_ram_addra = desc_engine_net_tx_ctrl_ram_flush ? desc_engine_net_tx_ctrl_ram_flush_id : sw_q_addr;  
    assign used_msix_aggregation_threshold_net_rx_ram_wea = ((cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_MSIX_AGGREGATION_THRESHOLD) && ~csr_if_read) || desc_engine_net_tx_ctrl_ram_flush;

    assign used_msix_aggregation_threshold_net_rx_ram_addrb = msix_aggregation_threshold_rd_req_vld_net_rx ? msix_aggregation_threshold_rd_req_qid_net_rx : sw_q_addr;
    assign msix_aggregation_threshold_rd_rsp_dat_net_rx = used_msix_aggregation_threshold_net_rx_ram_doutb;

     //==========================msix_aggregation_info_net_tx ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)         ),
        .ADDRA_WIDTH( Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH ),
        .DATAB_WIDTH( IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)         ),
        .ADDRB_WIDTH( Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "WRITE_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "dist"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_msix_aggregation_info_net_tx_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_msix_aggregation_info_net_tx_ram_dina            ),
        .addra          (used_msix_aggregation_info_net_tx_ram_addra           ),
        .wea            (used_msix_aggregation_info_net_tx_ram_wea             ),
        .addrb          (used_msix_aggregation_info_net_tx_ram_addrb           ),
        .doutb          (used_msix_aggregation_info_net_tx_ram_doutb           ),
        .parity_ecc_err (used_msix_aggregation_info_net_tx_ram_parity_ecc_err  )
    );

    genvar i;
    generate
    for (i = 0; i < IRQ_MERGE_UINT_NUM; i = i + 1) begin
        always @(*) begin
            if (i == sw_q_addr[IRQ_MERGE_UINT_NUM_WIDTH-1:0]) begin
                init_msix_aggregation_info_value_mask[i*MSIX_BLK_WIDTH+:MSIX_BLK_WIDTH] = {MSIX_BLK_WIDTH{1'b0}};
            end else begin
                init_msix_aggregation_info_value_mask[i*MSIX_BLK_WIDTH+:MSIX_BLK_WIDTH] = {MSIX_BLK_WIDTH{1'b1}};
            end
        end
    end
    endgenerate

    assign init_msix_aggregation_info_net_tx_value = init_msix_aggregation_info_value_mask & msix_aggregation_info_net_tx_value;

    assign used_msix_aggregation_info_net_tx_ram_dina = msix_aggregation_info_wr_vld_net_tx ? msix_aggregation_info_wr_dat_net_tx : init_msix_aggregation_info_net_tx_value;  
    assign used_msix_aggregation_info_net_tx_ram_addra = msix_aggregation_info_wr_vld_net_tx ? msix_aggregation_info_wr_qid_net_tx : (sw_q_addr >> IRQ_MERGE_UINT_NUM_WIDTH);  
    assign used_msix_aggregation_info_net_tx_ram_wea = msix_aggregation_info_wr_vld_net_tx || (init_all_ram_idx && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE));

    assign used_msix_aggregation_info_net_tx_ram_addrb = msix_aggregation_info_rd_req_vld_net_tx ? msix_aggregation_info_rd_req_qid_net_tx : (sw_q_addr >> IRQ_MERGE_UINT_NUM_WIDTH);
    assign msix_aggregation_info_rd_rsp_dat_net_tx = used_msix_aggregation_info_net_tx_ram_doutb;

     //==========================msix_aggregation_info_net_rx ram for used module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)         ),
        .ADDRA_WIDTH( Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH ),
        .DATAB_WIDTH( IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)         ),
        .ADDRB_WIDTH( Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "WRITE_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "dist"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_msix_aggregation_info_net_rx_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_msix_aggregation_info_net_rx_ram_dina            ),
        .addra          (used_msix_aggregation_info_net_rx_ram_addra           ),
        .wea            (used_msix_aggregation_info_net_rx_ram_wea             ),
        .addrb          (used_msix_aggregation_info_net_rx_ram_addrb           ),
        .doutb          (used_msix_aggregation_info_net_rx_ram_doutb           ),
        .parity_ecc_err (used_msix_aggregation_info_net_rx_ram_parity_ecc_err  )
    );

    assign init_msix_aggregation_info_net_rx_value    = init_msix_aggregation_info_value_mask & msix_aggregation_info_net_rx_value;

    assign used_msix_aggregation_info_net_rx_ram_dina = msix_aggregation_info_wr_vld_net_rx ? msix_aggregation_info_wr_dat_net_rx : init_msix_aggregation_info_net_rx_value;  
    assign used_msix_aggregation_info_net_rx_ram_addra = msix_aggregation_info_wr_vld_net_rx ? msix_aggregation_info_wr_qid_net_rx : (sw_q_addr >> IRQ_MERGE_UINT_NUM_WIDTH);  
    assign used_msix_aggregation_info_net_rx_ram_wea = msix_aggregation_info_wr_vld_net_rx || (init_all_ram_idx && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE));

    assign used_msix_aggregation_info_net_rx_ram_addrb = msix_aggregation_info_rd_req_vld_net_rx ? msix_aggregation_info_rd_req_qid_net_rx : (sw_q_addr >> IRQ_MERGE_UINT_NUM_WIDTH);
    assign msix_aggregation_info_rd_rsp_dat_net_rx = used_msix_aggregation_info_net_rx_ram_doutb;

    //==========================qos_l1_unit ram for net_tx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_tx_qos_unit_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_tx_qos_unit_ram_dina            ),
        .addra          (net_tx_qos_unit_ram_addra           ),
        .wea            (net_tx_qos_unit_ram_wea             ),
        .addrb          (net_tx_qos_unit_ram_addrb           ),
        .doutb          (net_tx_qos_unit_ram_doutb           ),
        .parity_ecc_err (net_tx_qos_unit_ram_parity_ecc_err  )
    );

    assign net_tx_qos_unit_ram_dina = virtio_ctx_info.qos_l1_unit;  
    assign net_tx_qos_unit_ram_addra = sw_q_addr;  
    assign net_tx_qos_unit_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_QOS_L1_UNIT) && ~csr_if_read;

    assign net_tx_qos_unit_ram_addrb = net_tx_slot_ctrl_ctx_info_rd_req_vld ? net_tx_slot_ctrl_ctx_info_rd_req_qid : sw_q_addr;
    assign net_tx_slot_ctrl_ctx_info_rd_rsp_qos_unit = net_tx_qos_unit_ram_doutb;

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_tx_qos_enable_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_tx_qos_enable_ram_dina            ),
        .addra          (net_tx_qos_enable_ram_addra           ),
        .wea            (net_tx_qos_enable_ram_wea             ),
        .addrb          (net_tx_qos_enable_ram_addrb           ),
        .doutb          (net_tx_qos_enable_ram_doutb           ),
        .parity_ecc_err (net_tx_qos_enable_ram_parity_ecc_err  )
    );

    assign net_tx_qos_enable_ram_dina = virtio_ctx_info.qos_enable;  
    assign net_tx_qos_enable_ram_addra = sw_q_addr;  
    assign net_tx_qos_enable_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_QOS_ENABLE) && ~csr_if_read;

    assign net_tx_qos_enable_ram_addrb = net_tx_slot_ctrl_ctx_info_rd_req_vld ? net_tx_slot_ctrl_ctx_info_rd_req_qid : sw_q_addr;
    assign net_tx_slot_ctrl_ctx_info_rd_rsp_qos_enable = net_tx_qos_enable_ram_doutb;

    //==========================qos_l1_unit_clone ram for net_tx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_tx_qos_unit_clone_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_tx_qos_unit_clone_ram_dina            ),
        .addra          (net_tx_qos_unit_clone_ram_addra           ),
        .wea            (net_tx_qos_unit_clone_ram_wea             ),
        .addrb          (net_tx_qos_unit_clone_ram_addrb           ),
        .doutb          (net_tx_qos_unit_clone_ram_doutb           ),
        .parity_ecc_err (net_tx_qos_unit_clone_ram_parity_ecc_err  )
    );

    assign net_tx_qos_unit_clone_ram_dina = net_tx_qos_unit_ram_dina;  
    assign net_tx_qos_unit_clone_ram_addra = net_tx_qos_unit_ram_addra;  
    assign net_tx_qos_unit_clone_ram_wea = net_tx_qos_unit_ram_wea;

    assign net_tx_qos_unit_clone_ram_addrb = net_tx_rd_data_ctx_info_rd_req_qid;
    assign net_tx_rd_data_ctx_info_rd_rsp_qos_unit = net_tx_qos_unit_clone_ram_doutb;

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_tx_qos_enable_clone_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_tx_qos_enable_clone_ram_dina            ),
        .addra          (net_tx_qos_enable_clone_ram_addra           ),
        .wea            (net_tx_qos_enable_clone_ram_wea             ),
        .addrb          (net_tx_qos_enable_clone_ram_addrb           ),
        .doutb          (net_tx_qos_enable_clone_ram_doutb           ),
        .parity_ecc_err (net_tx_qos_enable_clone_ram_parity_ecc_err  )
    );

    assign net_tx_qos_enable_clone_ram_dina = net_tx_qos_enable_ram_dina;  
    assign net_tx_qos_enable_clone_ram_addra = net_tx_qos_enable_ram_addra;  
    assign net_tx_qos_enable_clone_ram_wea = net_tx_qos_enable_ram_wea;

    assign net_tx_qos_enable_clone_ram_addrb = net_tx_rd_data_ctx_info_rd_req_qid;
    assign net_tx_rd_data_ctx_info_rd_rsp_qos_enable = net_tx_qos_enable_clone_ram_doutb;

    //==========================qos_l1_unit ram for net_rx_buf module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_rx_buf_qos_unit_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_rx_buf_qos_unit_ram_dina            ),
        .addra          (net_rx_buf_qos_unit_ram_addra           ),
        .wea            (net_rx_buf_qos_unit_ram_wea             ),
        .addrb          (net_rx_buf_qos_unit_ram_addrb           ),
        .doutb          (net_rx_buf_qos_unit_ram_doutb           ),
        .parity_ecc_err (net_rx_buf_qos_unit_ram_parity_ecc_err  )
    );

    assign net_rx_buf_qos_unit_ram_dina = net_tx_qos_unit_ram_dina;  
    assign net_rx_buf_qos_unit_ram_addra = net_tx_qos_unit_ram_addra;  
    assign net_rx_buf_qos_unit_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_QOS_L1_UNIT) && ~csr_if_read;

    assign net_rx_buf_qos_unit_ram_addrb = net_rx_buf_drop_info_rd_req_vld ? net_rx_buf_drop_info_rd_req_qid : sw_q_addr;
    assign net_rx_buf_drop_info_rd_rsp_qos_unit = net_rx_buf_qos_unit_ram_doutb;

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_rx_buf_qos_enable_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_rx_buf_qos_enable_ram_dina            ),
        .addra          (net_rx_buf_qos_enable_ram_addra           ),
        .wea            (net_rx_buf_qos_enable_ram_wea             ),
        .addrb          (net_rx_buf_qos_enable_ram_addrb           ),
        .doutb          (net_rx_buf_qos_enable_ram_doutb           ),
        .parity_ecc_err (net_rx_buf_qos_enable_ram_parity_ecc_err  )
    );

    assign net_rx_buf_qos_enable_ram_dina = net_tx_qos_enable_ram_dina;  
    assign net_rx_buf_qos_enable_ram_addra = net_tx_qos_enable_ram_addra;  
    assign net_rx_buf_qos_enable_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_QOS_ENABLE) && ~csr_if_read;

    assign net_rx_buf_qos_enable_ram_addrb = net_rx_buf_drop_info_rd_req_vld ? net_rx_buf_drop_info_rd_req_qid : sw_q_addr;
    assign net_rx_buf_drop_info_rd_rsp_qos_enable = net_rx_buf_qos_enable_ram_doutb;

    //==========================qos_l1_unit ram for blk_down_stream module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_down_stream_qos_unit_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_down_stream_qos_unit_ram_dina            ),
        .addra          (blk_down_stream_qos_unit_ram_addra           ),
        .wea            (blk_down_stream_qos_unit_ram_wea             ),
        .addrb          (blk_down_stream_qos_unit_ram_addrb           ),
        .doutb          (blk_down_stream_qos_unit_ram_doutb           ),
        .parity_ecc_err (blk_down_stream_qos_unit_ram_parity_ecc_err  )
    );

    assign blk_down_stream_qos_unit_ram_dina = net_tx_qos_unit_ram_dina;  
    assign blk_down_stream_qos_unit_ram_addra = net_tx_qos_unit_ram_addra;  
    assign blk_down_stream_qos_unit_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_QOS_L1_UNIT) && ~csr_if_read;

    assign blk_down_stream_qos_unit_ram_addrb = blk_down_stream_qos_info_rd_req_vld ? blk_down_stream_qos_info_rd_req_qid : sw_q_addr;
    assign blk_down_stream_qos_info_rd_rsp_qos_unit = blk_down_stream_qos_unit_ram_doutb;

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_down_stream_qos_enable_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_down_stream_qos_enable_ram_dina            ),
        .addra          (blk_down_stream_qos_enable_ram_addra           ),
        .wea            (blk_down_stream_qos_enable_ram_wea             ),
        .addrb          (blk_down_stream_qos_enable_ram_addrb           ),
        .doutb          (blk_down_stream_qos_enable_ram_doutb           ),
        .parity_ecc_err (blk_down_stream_qos_enable_ram_parity_ecc_err  )
    );

    assign blk_down_stream_qos_enable_ram_dina = net_tx_qos_enable_ram_dina;  
    assign blk_down_stream_qos_enable_ram_addra = net_tx_qos_enable_ram_addra;  
    assign blk_down_stream_qos_enable_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_QOS_ENABLE) && ~csr_if_read;

    assign blk_down_stream_qos_enable_ram_addrb = blk_down_stream_qos_info_rd_req_vld ? blk_down_stream_qos_info_rd_req_qid : sw_q_addr;
    assign blk_down_stream_qos_info_rd_rsp_qos_enable = blk_down_stream_qos_enable_ram_doutb;

    //==========================generation ram for blk_down_stream module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 8         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 8         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_down_stream_generation_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_down_stream_generation_ram_dina            ),
        .addra          (blk_down_stream_generation_ram_addra           ),
        .wea            (blk_down_stream_generation_ram_wea             ),
        .addrb          (blk_down_stream_generation_ram_addrb           ),
        .doutb          (blk_down_stream_generation_ram_doutb           ),
        .parity_ecc_err (blk_down_stream_generation_ram_parity_ecc_err  )
    );

    assign blk_down_stream_generation_ram_dina = virtio_ctx_info.generation;  
    assign blk_down_stream_generation_ram_addra = sw_q_addr;  
    assign blk_down_stream_generation_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_GENERATION) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign blk_down_stream_generation_ram_addrb = blk_down_stream_dma_info_rd_req_vld ? blk_down_stream_dma_info_rd_req_qid : sw_q_addr;
    assign blk_down_stream_dma_info_rd_rsp_generation = blk_down_stream_generation_ram_doutb;

    //==========================generation ram for net_rx_buf module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 8         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 8         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_rx_buf_generation_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_rx_buf_generation_ram_dina            ),
        .addra          (net_rx_buf_generation_ram_addra           ),
        .wea            (net_rx_buf_generation_ram_wea             ),
        .addrb          (net_rx_buf_generation_ram_addrb           ),
        .doutb          (net_rx_buf_generation_ram_doutb           ),
        .parity_ecc_err (net_rx_buf_generation_ram_parity_ecc_err  )
    );

    assign net_rx_buf_generation_ram_dina = blk_down_stream_generation_ram_dina;  
    assign net_rx_buf_generation_ram_addra = blk_down_stream_generation_ram_addra;  
    assign net_rx_buf_generation_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_GENERATION) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign net_rx_buf_generation_ram_addrb = net_rx_buf_drop_info_rd_req_vld ? net_rx_buf_drop_info_rd_req_qid : sw_q_addr;
    assign net_rx_buf_drop_info_rd_rsp_generation = net_rx_buf_generation_ram_doutb;

    //==========================generation ram for blk_upstream module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 8         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 8         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_upstream_generation_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_upstream_generation_ram_dina            ),
        .addra          (blk_upstream_generation_ram_addra           ),
        .wea            (blk_upstream_generation_ram_wea             ),
        .addrb          (blk_upstream_generation_ram_addrb           ),
        .doutb          (blk_upstream_generation_ram_doutb           ),
        .parity_ecc_err (blk_upstream_generation_ram_parity_ecc_err  )
    );

    assign blk_upstream_generation_ram_dina = blk_down_stream_generation_ram_dina;  
    assign blk_upstream_generation_ram_addra = blk_down_stream_generation_ram_addra;  
    assign blk_upstream_generation_ram_wea = blk_down_stream_generation_ram_wea;

    assign blk_upstream_generation_ram_addrb = blk_upstream_ctx_req_qid;
    assign blk_upstream_ctx_rsp_generation = blk_upstream_generation_ram_doutb;

    //==========================generation ram for net_tx module read======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 8         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 8         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_tx_generation_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_tx_generation_ram_dina            ),
        .addra          (net_tx_generation_ram_addra           ),
        .wea            (net_tx_generation_ram_wea             ),
        .addrb          (net_tx_generation_ram_addrb           ),
        .doutb          (net_tx_generation_ram_doutb           ),
        .parity_ecc_err (net_tx_generation_ram_parity_ecc_err  )
    );

    assign net_tx_generation_ram_dina = blk_down_stream_generation_ram_dina;  
    assign net_tx_generation_ram_addra = blk_down_stream_generation_ram_addra;  
    assign net_tx_generation_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_GENERATION) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign net_tx_generation_ram_addrb = net_tx_rd_data_ctx_info_rd_req_vld ? net_tx_rd_data_ctx_info_rd_req_qid : sw_q_addr;
    assign net_tx_rd_data_ctx_info_rd_rsp_generation = net_tx_generation_ram_doutb;

    //==========================desc_tbl_addr ram for blk_desc_eng module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 64         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 64         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_eng_desc_tbl_addr_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_eng_desc_tbl_addr_ram_dina            ),
        .addra          (blk_desc_eng_desc_tbl_addr_ram_addra           ),
        .wea            (blk_desc_eng_desc_tbl_addr_ram_wea             ),
        .addrb          (blk_desc_eng_desc_tbl_addr_ram_addrb           ),
        .doutb          (blk_desc_eng_desc_tbl_addr_ram_doutb           ),
        .parity_ecc_err (blk_desc_eng_desc_tbl_addr_ram_parity_ecc_err  )
    );

    assign blk_desc_eng_desc_tbl_addr_ram_dina = blk_desc_engine_local_info_wr_desc_tbl_addr;  
    assign blk_desc_eng_desc_tbl_addr_ram_addra = blk_desc_engine_local_info_wr_qid;  
    assign blk_desc_eng_desc_tbl_addr_ram_wea = blk_desc_engine_local_info_wr_vld;

    assign blk_desc_eng_desc_tbl_addr_ram_addrb = blk_desc_engine_local_info_rd_req_vld ? blk_desc_engine_local_info_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_local_info_rd_rsp_desc_tbl_addr = blk_desc_eng_desc_tbl_addr_ram_doutb;

    //==========================desc_tbl_size ram for blk_desc_eng module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 32         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 32         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_eng_desc_tbl_size_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_eng_desc_tbl_size_ram_dina            ),
        .addra          (blk_desc_eng_desc_tbl_size_ram_addra           ),
        .wea            (blk_desc_eng_desc_tbl_size_ram_wea             ),
        .addrb          (blk_desc_eng_desc_tbl_size_ram_addrb           ),
        .doutb          (blk_desc_eng_desc_tbl_size_ram_doutb           ),
        .parity_ecc_err (blk_desc_eng_desc_tbl_size_ram_parity_ecc_err  )
    );

    assign blk_desc_eng_desc_tbl_size_ram_dina = blk_desc_engine_local_info_wr_desc_tbl_size;  
    assign blk_desc_eng_desc_tbl_size_ram_addra = blk_desc_engine_local_info_wr_qid;  
    assign blk_desc_eng_desc_tbl_size_ram_wea = blk_desc_engine_local_info_wr_vld;

    assign blk_desc_eng_desc_tbl_size_ram_addrb = blk_desc_engine_local_info_rd_req_vld ? blk_desc_engine_local_info_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_local_info_rd_rsp_desc_tbl_size = blk_desc_eng_desc_tbl_size_ram_doutb;

    //==========================desc_tbl_next_id ram for blk_desc_eng module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 32         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 32         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_eng_desc_tbl_next_id_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_eng_desc_tbl_next_id_ram_dina            ),
        .addra          (blk_desc_eng_desc_tbl_next_id_ram_addra           ),
        .wea            (blk_desc_eng_desc_tbl_next_id_ram_wea             ),
        .addrb          (blk_desc_eng_desc_tbl_next_id_ram_addrb           ),
        .doutb          (blk_desc_eng_desc_tbl_next_id_ram_doutb           ),
        .parity_ecc_err (blk_desc_eng_desc_tbl_next_id_ram_parity_ecc_err  )
    );

    assign blk_desc_eng_desc_tbl_next_id_ram_dina = {blk_desc_engine_local_info_wr_desc_tbl_next, blk_desc_engine_local_info_wr_desc_tbl_id};  
    assign blk_desc_eng_desc_tbl_next_id_ram_addra = blk_desc_engine_local_info_wr_qid;  
    assign blk_desc_eng_desc_tbl_next_id_ram_wea = blk_desc_engine_local_info_wr_vld;

    assign blk_desc_eng_desc_tbl_next_id_ram_addrb = blk_desc_engine_local_info_rd_req_vld ? blk_desc_engine_local_info_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_local_info_rd_rsp_desc_tbl_id = blk_desc_eng_desc_tbl_next_id_ram_doutb[15:0];
    assign blk_desc_engine_local_info_rd_rsp_desc_tbl_next = blk_desc_eng_desc_tbl_next_id_ram_doutb[31:16];

    //==========================desc_cnt ram for blk_desc_eng module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 20         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 20         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_eng_desc_cnt_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_eng_desc_cnt_ram_dina            ),
        .addra          (blk_desc_eng_desc_cnt_ram_addra           ),
        .wea            (blk_desc_eng_desc_cnt_ram_wea             ),
        .addrb          (blk_desc_eng_desc_cnt_ram_addrb           ),
        .doutb          (blk_desc_eng_desc_cnt_ram_doutb           ),
        .parity_ecc_err (blk_desc_eng_desc_cnt_ram_parity_ecc_err  )
    );

    assign blk_desc_eng_desc_cnt_ram_dina = blk_desc_engine_local_info_wr_desc_cnt;  
    assign blk_desc_eng_desc_cnt_ram_addra = blk_desc_engine_local_info_wr_qid;  
    assign blk_desc_eng_desc_cnt_ram_wea = blk_desc_engine_local_info_wr_vld;

    assign blk_desc_eng_desc_cnt_ram_addrb = blk_desc_engine_local_info_rd_req_vld ? blk_desc_engine_local_info_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_local_info_rd_rsp_desc_cnt = blk_desc_eng_desc_cnt_ram_doutb;

    //==========================data_len ram for blk_desc_eng module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 21         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 21         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_eng_data_len_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_eng_data_len_ram_dina            ),
        .addra          (blk_desc_eng_data_len_ram_addra           ),
        .wea            (blk_desc_eng_data_len_ram_wea             ),
        .addrb          (blk_desc_eng_data_len_ram_addrb           ),
        .doutb          (blk_desc_eng_data_len_ram_doutb           ),
        .parity_ecc_err (blk_desc_eng_data_len_ram_parity_ecc_err  )
    );

    assign blk_desc_eng_data_len_ram_dina = blk_desc_engine_local_info_wr_data_len;  
    assign blk_desc_eng_data_len_ram_addra = blk_desc_engine_local_info_wr_qid;  
    assign blk_desc_eng_data_len_ram_wea = blk_desc_engine_local_info_wr_vld;

    assign blk_desc_eng_data_len_ram_addrb = blk_desc_engine_local_info_rd_req_vld ? blk_desc_engine_local_info_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_local_info_rd_rsp_data_len = blk_desc_eng_data_len_ram_doutb;

    //==========================is_indirct ram for blk_desc_eng module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_eng_is_indirct_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_eng_is_indirct_ram_dina            ),
        .addra          (blk_desc_eng_is_indirct_ram_addra           ),
        .wea            (blk_desc_eng_is_indirct_ram_wea             ),
        .addrb          (blk_desc_eng_is_indirct_ram_addrb           ),
        .doutb          (blk_desc_eng_is_indirct_ram_doutb           ),
        .parity_ecc_err (blk_desc_eng_is_indirct_ram_parity_ecc_err  )
    );

    assign blk_desc_eng_is_indirct_ram_dina = blk_desc_engine_local_info_wr_is_indirct;  
    assign blk_desc_eng_is_indirct_ram_addra = blk_desc_engine_local_info_wr_qid;  
    assign blk_desc_eng_is_indirct_ram_wea = blk_desc_engine_local_info_wr_vld;

    assign blk_desc_eng_is_indirct_ram_addrb = blk_desc_engine_local_info_rd_req_vld ? blk_desc_engine_local_info_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_local_info_rd_rsp_is_indirct = blk_desc_eng_is_indirct_ram_doutb;

    //==========================resumer ram for blk_desc_eng module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_eng_resumer_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_eng_resumer_ram_dina            ),
        .addra          (blk_desc_eng_resumer_ram_addra           ),
        .wea            (blk_desc_eng_resumer_ram_wea             ),
        .addrb          (blk_desc_eng_resumer_ram_addrb           ),
        .doutb          (blk_desc_eng_resumer_ram_doutb           ),
        .parity_ecc_err (blk_desc_eng_resumer_ram_parity_ecc_err  )
    );

    assign blk_desc_eng_resumer_ram_dina = blk_desc_engine_resumer_wr_dat;  
    assign blk_desc_eng_resumer_ram_addra = blk_desc_engine_resumer_wr_qid;  
    assign blk_desc_eng_resumer_ram_wea = blk_desc_engine_resumer_wr_vld;

    assign blk_desc_eng_resumer_ram_addrb = blk_desc_engine_resumer_rd_req_vld ? blk_desc_engine_resumer_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_resumer_rd_rsp_dat = blk_desc_eng_resumer_ram_doutb;

    //==========================indirct_support ram for blk_desc_eng module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_eng_indirct_support_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_eng_indirct_support_ram_dina            ),
        .addra          (blk_desc_eng_indirct_support_ram_addra           ),
        .wea            (blk_desc_eng_indirct_support_ram_wea             ),
        .addrb          (blk_desc_eng_indirct_support_ram_addrb           ),
        .doutb          (blk_desc_eng_indirct_support_ram_doutb           ),
        .parity_ecc_err (blk_desc_eng_indirct_support_ram_parity_ecc_err  )
    );

    assign blk_desc_eng_indirct_support_ram_dina = virtio_ctx_info.indirct_support_tso_en_csum_en[0];  
    assign blk_desc_eng_indirct_support_ram_addra = sw_q_addr;  
    assign blk_desc_eng_indirct_support_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_INDIRCT_TSO_CSUM_EN) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign blk_desc_eng_indirct_support_ram_addrb = blk_desc_engine_global_info_rd_req_vld ? blk_desc_engine_global_info_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_global_info_rd_rsp_indirct_support = blk_desc_eng_indirct_support_ram_doutb;

     //==========================indirct_support ram for desc_eng_net_tx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_eng_net_tx_indirct_support_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_eng_net_tx_indirct_support_ram_dina            ),
        .addra          (desc_eng_net_tx_indirct_support_ram_addra           ),
        .wea            (desc_eng_net_tx_indirct_support_ram_wea             ),
        .addrb          (desc_eng_net_tx_indirct_support_ram_addrb           ),
        .doutb          (desc_eng_net_tx_indirct_support_ram_doutb           ),
        .parity_ecc_err (desc_eng_net_tx_indirct_support_ram_parity_ecc_err  )
    );

    assign desc_eng_net_tx_indirct_support_ram_dina = blk_desc_eng_indirct_support_ram_dina;  
    assign desc_eng_net_tx_indirct_support_ram_addra = blk_desc_eng_indirct_support_ram_addra;  
    assign desc_eng_net_tx_indirct_support_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_INDIRCT_TSO_CSUM_EN) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign desc_eng_net_tx_indirct_support_ram_addrb = desc_engine_net_tx_ctx_info_rd_req_vld ? desc_engine_net_tx_ctx_info_rd_req_vq.qid : sw_q_addr;
    assign desc_engine_net_tx_ctx_info_rd_rsp_indirct_support = desc_eng_net_tx_indirct_support_ram_doutb;

    //==========================indirct_support ram for desc_eng_net_rx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_eng_net_rx_indirct_support_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_eng_net_rx_indirct_support_ram_dina            ),
        .addra          (desc_eng_net_rx_indirct_support_ram_addra           ),
        .wea            (desc_eng_net_rx_indirct_support_ram_wea             ),
        .addrb          (desc_eng_net_rx_indirct_support_ram_addrb           ),
        .doutb          (desc_eng_net_rx_indirct_support_ram_doutb           ),
        .parity_ecc_err (desc_eng_net_rx_indirct_support_ram_parity_ecc_err  )
    );

    assign desc_eng_net_rx_indirct_support_ram_dina = blk_desc_eng_indirct_support_ram_dina;  
    assign desc_eng_net_rx_indirct_support_ram_addra = blk_desc_eng_indirct_support_ram_addra;  
    assign desc_eng_net_rx_indirct_support_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_INDIRCT_TSO_CSUM_EN) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign desc_eng_net_rx_indirct_support_ram_addrb = desc_engine_net_rx_ctx_info_rd_req_vld ? desc_engine_net_rx_ctx_info_rd_req_vq.qid : sw_q_addr;
    assign desc_engine_net_rx_ctx_info_rd_rsp_indirct_support = desc_eng_net_rx_indirct_support_ram_doutb;

    //==========================tso_en_csum_en ram for net_tx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 2         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 2         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_tx_tso_en_csum_en_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_tx_tso_en_csum_en_ram_dina            ),
        .addra          (net_tx_tso_en_csum_en_ram_addra           ),
        .wea            (net_tx_tso_en_csum_en_ram_wea             ),
        .addrb          (net_tx_tso_en_csum_en_ram_addrb           ),
        .doutb          (net_tx_tso_en_csum_en_ram_doutb           ),
        .parity_ecc_err (net_tx_tso_en_csum_en_ram_parity_ecc_err  )
    );

    assign net_tx_tso_en_csum_en_ram_dina = {virtio_ctx_info.indirct_support_tso_en_csum_en[1], virtio_ctx_info.indirct_support_tso_en_csum_en[2]};  
    assign net_tx_tso_en_csum_en_ram_addra = sw_q_addr;  
    assign net_tx_tso_en_csum_en_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_INDIRCT_TSO_CSUM_EN) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign net_tx_tso_en_csum_en_ram_addrb = net_tx_rd_data_ctx_info_rd_req_vld ? net_tx_rd_data_ctx_info_rd_req_qid.qid : sw_q_addr;
    assign net_tx_rd_data_ctx_info_rd_rsp_tso_en = net_tx_tso_en_csum_en_ram_doutb[1];
    assign net_tx_rd_data_ctx_info_rd_rsp_csum_en = net_tx_tso_en_csum_en_ram_doutb[0];

    //==========================max_len ram for desc_eng_net_tx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 20         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 20         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_eng_net_tx_max_len_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_eng_net_tx_max_len_ram_dina            ),
        .addra          (desc_eng_net_tx_max_len_ram_addra           ),
        .wea            (desc_eng_net_tx_max_len_ram_wea             ),
        .addrb          (desc_eng_net_tx_max_len_ram_addrb           ),
        .doutb          (desc_eng_net_tx_max_len_ram_doutb           ),
        .parity_ecc_err (desc_eng_net_tx_max_len_ram_parity_ecc_err  )
    );

    assign desc_eng_net_tx_max_len_ram_dina = virtio_ctx_info.max_len;  
    assign desc_eng_net_tx_max_len_ram_addra = sw_q_addr;  
    assign desc_eng_net_tx_max_len_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_MAX_LEN) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign desc_eng_net_tx_max_len_ram_addrb = desc_engine_net_tx_ctx_info_rd_req_vld ? desc_engine_net_tx_ctx_info_rd_req_vq.qid : sw_q_addr;
    assign desc_engine_net_tx_ctx_info_rd_rsp_max_len = desc_eng_net_tx_max_len_ram_doutb;

    //==========================max_len ram for desc_eng_net_rx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 20         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 20         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_eng_net_rx_max_len_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_eng_net_rx_max_len_ram_dina            ),
        .addra          (desc_eng_net_rx_max_len_ram_addra           ),
        .wea            (desc_eng_net_rx_max_len_ram_wea             ),
        .addrb          (desc_eng_net_rx_max_len_ram_addrb           ),
        .doutb          (desc_eng_net_rx_max_len_ram_doutb           ),
        .parity_ecc_err (desc_eng_net_rx_max_len_ram_parity_ecc_err  )
    );

    assign desc_eng_net_rx_max_len_ram_dina = desc_eng_net_tx_max_len_ram_dina;  
    assign desc_eng_net_rx_max_len_ram_addra = desc_eng_net_tx_max_len_ram_addra;  
    assign desc_eng_net_rx_max_len_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_MAX_LEN) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign desc_eng_net_rx_max_len_ram_addrb = desc_engine_net_rx_ctx_info_rd_req_vld ? desc_engine_net_rx_ctx_info_rd_req_vq.qid : sw_q_addr;
    assign desc_engine_net_rx_ctx_info_rd_rsp_max_len = desc_eng_net_rx_max_len_ram_doutb;

    //==========================max_len ram for blk_desc_eng module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 20         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 20         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_desc_eng_max_len_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_desc_eng_max_len_ram_dina            ),
        .addra          (blk_desc_eng_max_len_ram_addra           ),
        .wea            (blk_desc_eng_max_len_ram_wea             ),
        .addrb          (blk_desc_eng_max_len_ram_addrb           ),
        .doutb          (blk_desc_eng_max_len_ram_doutb           ),
        .parity_ecc_err (blk_desc_eng_max_len_ram_parity_ecc_err  )
    );

    assign blk_desc_eng_max_len_ram_dina = desc_eng_net_tx_max_len_ram_dina;  
    assign blk_desc_eng_max_len_ram_addra = desc_eng_net_tx_max_len_ram_addra;  
    assign blk_desc_eng_max_len_ram_wea = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_MAX_LEN) && ~csr_if_read && (virtio_ctx_info.q_status == VIRTIO_Q_STATUS_IDLE);

    assign blk_desc_eng_max_len_ram_addrb = blk_desc_engine_global_info_rd_req_vld ? blk_desc_engine_global_info_rd_req_qid : sw_q_addr;
    assign blk_desc_engine_global_info_rd_rsp_segment_size_blk = blk_desc_eng_max_len_ram_doutb;

    //==========================idx_limit_per_queue ram for net_rx_buf module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 8         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 8         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_rx_buf_idx_limit_per_queue_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_rx_buf_idx_limit_per_queue_ram_dina            ),
        .addra          (net_rx_buf_idx_limit_per_queue_ram_addra           ),
        .wea            (net_rx_buf_idx_limit_per_queue_ram_wea             ),
        .addrb          (net_rx_buf_idx_limit_per_queue_ram_addrb           ),
        .doutb          (net_rx_buf_idx_limit_per_queue_ram_doutb           ),
        .parity_ecc_err (net_rx_buf_idx_limit_per_queue_ram_parity_ecc_err  )
    );

    assign net_rx_buf_idx_limit_per_queue_ram_dina = desc_engine_net_tx_ctrl_ram_flush ? 8'd8 : virtio_ctx_info.net_idx_limit_per_queue;  
    assign net_rx_buf_idx_limit_per_queue_ram_addra = desc_engine_net_tx_ctrl_ram_flush ? desc_engine_net_tx_ctrl_ram_flush_id : sw_q_addr;  
    assign net_rx_buf_idx_limit_per_queue_ram_wea_sw = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_RX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_NET_IDX_LIMIT_PER_QUEUE) && ~csr_if_read;
    assign net_rx_buf_idx_limit_per_queue_ram_wea = net_rx_buf_idx_limit_per_queue_ram_wea_sw || desc_engine_net_tx_ctrl_ram_flush;

    assign net_rx_buf_idx_limit_per_queue_ram_addrb = net_rx_buf_req_idx_per_queue_rd_req_vld ? net_rx_buf_req_idx_per_queue_rd_req_qid : sw_q_addr;
    assign net_rx_buf_req_idx_per_queue_rd_rsp_limit = net_rx_buf_idx_limit_per_queue_ram_doutb;

    //==========================idx_limit_per_queue ram for desc_eng_net_tx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 8         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 8         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_eng_net_tx_idx_limit_per_queue_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_eng_net_tx_idx_limit_per_queue_ram_dina            ),
        .addra          (desc_eng_net_tx_idx_limit_per_queue_ram_addra           ),
        .wea            (desc_eng_net_tx_idx_limit_per_queue_ram_wea             ),
        .addrb          (desc_eng_net_tx_idx_limit_per_queue_ram_addrb           ),
        .doutb          (desc_eng_net_tx_idx_limit_per_queue_ram_doutb           ),
        .parity_ecc_err (desc_eng_net_tx_idx_limit_per_queue_ram_parity_ecc_err  )
    );

    assign desc_eng_net_tx_idx_limit_per_queue_ram_dina = net_rx_buf_idx_limit_per_queue_ram_dina;  
    assign desc_eng_net_tx_idx_limit_per_queue_ram_addra = net_rx_buf_idx_limit_per_queue_ram_addra;  
    assign desc_eng_net_tx_idx_limit_per_queue_ram_wea_sw = (cstat == CTX_WR) && (csr_if_addr[13:12] == VIRTIO_NET_TX_TYPE) && (csr_if_addr[11:0] == `VIRTIO_CTX_NET_IDX_LIMIT_PER_QUEUE) && ~csr_if_read;
    assign desc_eng_net_tx_idx_limit_per_queue_ram_wea = desc_eng_net_tx_idx_limit_per_queue_ram_wea_sw || desc_engine_net_tx_ctrl_ram_flush;

    assign desc_eng_net_tx_idx_limit_per_queue_ram_addrb = desc_engine_net_tx_limit_per_queue_rd_req_vld ? desc_engine_net_tx_limit_per_queue_rd_req_qid : sw_q_addr;
    assign desc_engine_net_tx_limit_per_queue_rd_rsp_dat = desc_eng_net_tx_idx_limit_per_queue_ram_doutb;

    //==========================idx_limit_per_dev ram for desc_eng_net_tx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 8         ),
        .ADDRA_WIDTH( DEV_ID_WIDTH ),
        .DATAB_WIDTH( 8         ),
        .ADDRB_WIDTH( DEV_ID_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_eng_net_tx_idx_limit_per_dev_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_eng_net_tx_idx_limit_per_dev_ram_dina            ),
        .addra          (desc_eng_net_tx_idx_limit_per_dev_ram_addra           ),
        .wea            (desc_eng_net_tx_idx_limit_per_dev_ram_wea             ),
        .addrb          (desc_eng_net_tx_idx_limit_per_dev_ram_addrb           ),
        .doutb          (desc_eng_net_tx_idx_limit_per_dev_ram_doutb           ),
        .parity_ecc_err (desc_eng_net_tx_idx_limit_per_dev_ram_parity_ecc_err  )
    );

    always @(posedge clk) begin
      if(rst) begin
         flush_idx_limit_per_dev <= 'h1;
      end else if(flush_idx_limit_per_dev_id == {DEV_ID_WIDTH{1'b1}}) begin
         flush_idx_limit_per_dev <= 'h0;
      end
    end

    always @(posedge clk) begin
      if(rst) begin
         flush_idx_limit_per_dev_id <= 'h0;
      end else if(flush_idx_limit_per_dev) begin
         flush_idx_limit_per_dev_id <= flush_idx_limit_per_dev_id + 1'b1;
      end
    end

    assign desc_eng_net_tx_idx_limit_per_dev_ram_dina = flush_idx_limit_per_dev ? 'd32 : virtio_ctx_info.net_tx_idx_limit_per_dev;  
    assign desc_eng_net_tx_idx_limit_per_dev_ram_addra = flush_idx_limit_per_dev ? flush_idx_limit_per_dev_id : sw_dev_addr;  
    assign desc_eng_net_tx_idx_limit_per_dev_ram_wea_sw = (cstat == CTX_WR) && (csr_if_addr[7:0] == `VIRTIO_CTX_NET_TX_IDX_LIMIT_PER_DEV) && ~csr_if_read;
    assign desc_eng_net_tx_idx_limit_per_dev_ram_wea = desc_eng_net_tx_idx_limit_per_dev_ram_wea_sw || flush_idx_limit_per_dev;

    assign desc_eng_net_tx_idx_limit_per_dev_ram_addrb = desc_engine_net_tx_limit_per_dev_rd_req_vld ? desc_engine_net_tx_limit_per_dev_rd_req_dev_id : sw_dev_addr;
    assign desc_engine_net_tx_limit_per_dev_rd_rsp_dat = desc_eng_net_tx_idx_limit_per_dev_ram_doutb;

    //==========================idx_limit_per_dev ram for net_rx_buf module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 8         ),
        .ADDRA_WIDTH( DEV_ID_WIDTH ),
        .DATAB_WIDTH( 8         ),
        .ADDRB_WIDTH( DEV_ID_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_net_rx_buf_idx_limit_per_dev_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (net_rx_buf_idx_limit_per_dev_ram_dina            ),
        .addra          (net_rx_buf_idx_limit_per_dev_ram_addra           ),
        .wea            (net_rx_buf_idx_limit_per_dev_ram_wea             ),
        .addrb          (net_rx_buf_idx_limit_per_dev_ram_addrb           ),
        .doutb          (net_rx_buf_idx_limit_per_dev_ram_doutb           ),
        .parity_ecc_err (net_rx_buf_idx_limit_per_dev_ram_parity_ecc_err  )
    );

    assign net_rx_buf_idx_limit_per_dev_ram_dina = flush_idx_limit_per_dev ? 'd32 : virtio_ctx_info.net_tx_idx_limit_per_dev;  
    assign net_rx_buf_idx_limit_per_dev_ram_addra = flush_idx_limit_per_dev ? flush_idx_limit_per_dev_id : sw_dev_addr;  
    assign net_rx_buf_idx_limit_per_dev_ram_wea_sw = (cstat == CTX_WR) && (csr_if_addr[7:0] == `VIRTIO_CTX_NET_RX_IDX_LIMIT_PER_DEV) && ~csr_if_read;
    assign net_rx_buf_idx_limit_per_dev_ram_wea = net_rx_buf_idx_limit_per_dev_ram_wea_sw || flush_idx_limit_per_dev;

    assign net_rx_buf_idx_limit_per_dev_ram_addrb = net_rx_buf_req_idx_per_dev_rd_req_vld ? net_rx_buf_req_idx_per_dev_rd_req_dev_id : sw_dev_addr;
    assign net_rx_buf_req_idx_per_dev_rd_rsp_limit = net_rx_buf_idx_limit_per_dev_ram_doutb;

    //==========================head_slot_tail_slot ram for desc_eng_net_tx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( SLOT_WIDTH*2+1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( SLOT_WIDTH*2+1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_eng_net_tx_tail_vld_head_slot_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_eng_net_tx_tail_vld_head_slot_ram_dina            ),
        .addra          (desc_eng_net_tx_tail_vld_head_slot_ram_addra           ),
        .wea            (desc_eng_net_tx_tail_vld_head_slot_ram_wea             ),
        .addrb          (desc_eng_net_tx_tail_vld_head_slot_ram_addrb           ),
        .doutb          (desc_eng_net_tx_tail_vld_head_slot_ram_doutb           ),
        .parity_ecc_err (desc_eng_net_tx_tail_vld_head_slot_ram_parity_ecc_err  )
    );

    assign desc_eng_net_tx_tail_vld_head_slot_ram_dina = desc_engine_net_tx_ctrl_ram_flush ? 'd0 : {desc_engine_net_tx_ctx_slot_chain_wr_tail_slot, desc_engine_net_tx_ctx_slot_chain_wr_head_slot_vld, desc_engine_net_tx_ctx_slot_chain_wr_head_slot};  
    assign desc_eng_net_tx_tail_vld_head_slot_ram_addra = desc_engine_net_tx_ctrl_ram_flush ? desc_engine_net_tx_ctrl_ram_flush_id : desc_engine_net_tx_ctx_slot_chain_wr_vq.qid;  
    assign desc_eng_net_tx_tail_vld_head_slot_ram_wea = desc_engine_net_tx_ctrl_ram_flush || desc_engine_net_tx_ctx_slot_chain_wr_vld;

    assign desc_eng_net_tx_tail_vld_head_slot_ram_addrb = desc_engine_net_tx_ctx_slot_chain_rd_req_vld ? desc_engine_net_tx_ctx_slot_chain_rd_req_vq.qid : sw_q_addr;
    assign desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot = desc_eng_net_tx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH-1:0];
    assign desc_engine_net_tx_ctx_slot_chain_rd_rsp_head_slot_vld = desc_eng_net_tx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH];
    assign desc_engine_net_tx_ctx_slot_chain_rd_rsp_tail_slot = desc_eng_net_tx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH*2:SLOT_WIDTH+1];

    //==========================head_slot_tail_slot ram for desc_eng_net_rx module read ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( SLOT_WIDTH*2+1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( SLOT_WIDTH*2+1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_desc_eng_net_rx_tail_vld_head_slot_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (desc_eng_net_rx_tail_vld_head_slot_ram_dina            ),
        .addra          (desc_eng_net_rx_tail_vld_head_slot_ram_addra           ),
        .wea            (desc_eng_net_rx_tail_vld_head_slot_ram_wea             ),
        .addrb          (desc_eng_net_rx_tail_vld_head_slot_ram_addrb           ),
        .doutb          (desc_eng_net_rx_tail_vld_head_slot_ram_doutb           ),
        .parity_ecc_err (desc_eng_net_rx_tail_vld_head_slot_ram_parity_ecc_err  )
    );

    assign desc_eng_net_rx_tail_vld_head_slot_ram_dina = desc_engine_net_tx_ctrl_ram_flush ? 'd0 : {desc_engine_net_rx_ctx_slot_chain_wr_tail_slot, desc_engine_net_rx_ctx_slot_chain_wr_head_slot_vld, desc_engine_net_rx_ctx_slot_chain_wr_head_slot};  
    assign desc_eng_net_rx_tail_vld_head_slot_ram_addra = desc_engine_net_tx_ctrl_ram_flush ? desc_engine_net_tx_ctrl_ram_flush_id : desc_engine_net_rx_ctx_slot_chain_wr_vq.qid;  
    assign desc_eng_net_rx_tail_vld_head_slot_ram_wea = desc_engine_net_tx_ctrl_ram_flush || desc_engine_net_rx_ctx_slot_chain_wr_vld;

    assign desc_eng_net_rx_tail_vld_head_slot_ram_addrb = desc_engine_net_rx_ctx_slot_chain_rd_req_vld ? desc_engine_net_rx_ctx_slot_chain_rd_req_vq.qid : sw_q_addr;
    assign desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot = desc_eng_net_rx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH-1:0];
    assign desc_engine_net_rx_ctx_slot_chain_rd_rsp_head_slot_vld = desc_eng_net_rx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH];
    assign desc_engine_net_rx_ctx_slot_chain_rd_rsp_tail_slot = desc_eng_net_rx_tail_vld_head_slot_ram_doutb[SLOT_WIDTH*2:SLOT_WIDTH+1];


    //==========================dma write used_idx and irq flag ======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_used_dma_write_used_idx_irq_flag_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (used_dma_write_used_idx_irq_flag_ram_dina            ),
        .addra          (used_dma_write_used_idx_irq_flag_ram_addra           ),
        .wea            (used_dma_write_used_idx_irq_flag_ram_wea             ),
        .addrb          (used_dma_write_used_idx_irq_flag_ram_addrb           ),
        .doutb          (used_dma_write_used_idx_irq_flag_ram_doutb           ),
        .parity_ecc_err (used_dma_write_used_idx_irq_flag_ram_parity_ecc_err  )
    );

    assign used_dma_write_used_idx_irq_flag_ram_dina = used_dma_write_used_idx_irq_flag_wr_vld ? used_dma_write_used_idx_irq_flag_wr_dat : 'h0;
    assign used_dma_write_used_idx_irq_flag_ram_addra = used_dma_write_used_idx_irq_flag_wr_vld ? used_dma_write_used_idx_irq_flag_wr_qid : sw_vq_addr;
    assign used_dma_write_used_idx_irq_flag_ram_wea = used_dma_write_used_idx_irq_flag_wr_vld || init_all_ram_idx; 

    assign used_dma_write_used_idx_irq_flag_ram_addrb = sw_vq_addr;
    assign used_dma_write_used_idx_irq_flag = used_dma_write_used_idx_irq_flag_ram_doutb;

//==========================blk_chain_fst_seg ram for blk_down_stream module read and write======================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 1         ),
        .ADDRA_WIDTH( Q_WIDTH ),
        .DATAB_WIDTH( 1         ),
        .ADDRB_WIDTH( Q_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_blk_down_stream_chain_fst_seg_ram(
        .rst            (rst                      ), 
        .clk            (clk                      ),
        .dina           (blk_down_stream_chain_fst_seg_ram_dina            ),
        .addra          (blk_down_stream_chain_fst_seg_ram_addra           ),
        .wea            (blk_down_stream_chain_fst_seg_ram_wea             ),
        .addrb          (blk_down_stream_chain_fst_seg_ram_addrb           ),
        .doutb          (blk_down_stream_chain_fst_seg_ram_doutb           ),
        .parity_ecc_err (blk_down_stream_chain_fst_seg_ram_parity_ecc_err  )
    );

    assign blk_down_stream_chain_fst_seg_ram_dina = blk_down_stream_chain_fst_seg_wr_vld ? blk_down_stream_chain_fst_seg_wr_dat : 1'b1;  
    assign blk_down_stream_chain_fst_seg_ram_addra = blk_down_stream_chain_fst_seg_wr_vld ? blk_down_stream_chain_fst_seg_wr_qid : sw_q_addr;  
    assign blk_down_stream_chain_fst_seg_ram_wea = (init_all_ram_idx && (csr_if_addr[13:12] == VIRTIO_BLK_TYPE)) || blk_down_stream_chain_fst_seg_wr_vld;

    assign blk_down_stream_chain_fst_seg_ram_addrb = blk_down_stream_chain_fst_seg_rd_req_vld ? blk_down_stream_chain_fst_seg_rd_req_qid : sw_q_addr;
    assign blk_down_stream_chain_fst_seg_rd_rsp_dat = blk_down_stream_chain_fst_seg_ram_doutb;

//=========================virtio_used module send irq cnt ================================//
    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 16         ),
        .ADDRA_WIDTH( VQ_WIDTH ),
        .DATAB_WIDTH( 16         ),
        .ADDRB_WIDTH( VQ_WIDTH ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,                 
    )u_virtio_used_irq_cnt_ram(
        .rst            (rst                    ), 
        .clk            (clk                    ),
        .dina           (virtio_used_irq_cnt_ram_dina            ),
        .addra          (virtio_used_irq_cnt_ram_addra           ),
        .wea            (virtio_used_irq_cnt_ram_wea             ),
        .addrb          (virtio_used_irq_cnt_ram_addrb           ),
        .doutb          (virtio_used_irq_cnt_ram_doutb           ),
        .parity_ecc_err (virtio_used_irq_cnt_ram_parity_ecc_err  )
    );

    always @(posedge clk) begin
        if(rst) begin
            virtio_used_irq_cnt_ram_hw_wea <= 1'b0;
        end else begin
            virtio_used_irq_cnt_ram_hw_wea <= mon_send_a_irq;
        end
        virtio_used_irq_cnt_ram_addra_tmp <= virtio_used_irq_cnt_ram_addrb;
    end

    //when STARTING queue,Clear the data of the corresponding queue to zero 
    assign virtio_used_irq_cnt_ram_addra = virtio_used_irq_cnt_ram_hw_wea ? virtio_used_irq_cnt_ram_addra_tmp : sw_vq_addr;    
    assign virtio_used_irq_cnt_ram_sw_wea = (cstat == CTX_WR) && (csr_if_addr[11:0] == `VIRTIO_CTX_USED_IRQ_CNT) && ~csr_if_read;
    assign virtio_used_irq_cnt_ram_wea = virtio_used_irq_cnt_ram_hw_wea || (init_all_ram_idx && all_init_done) || virtio_used_irq_cnt_ram_sw_wea;
    assign virtio_used_irq_cnt_ram_dina = virtio_used_irq_cnt_ram_hw_wea ? (virtio_used_irq_cnt_ram_doutb + 1'b1) : 'h0;
    assign virtio_used_irq_cnt_ram_addrb = mon_send_a_irq ? mon_send_irq_vq : sw_vq_addr;

    //========================================dfx_err========================================//
    // dfx_err_0: 64bit
    always @(posedge clk) begin
        if(rst)begin
            dfx_err_0 <= {$bits(dfx_err_0){1'h0}};
        end else begin
            dfx_err_0 <= {
                err_info_ram_parity_ecc_err,                  // 63-62
                err_info_clone_ram_parity_ecc_err,           // 61-60
                ctrl_ram_parity_ecc_err,                    // 59-58
                idx_engine_ctrl_ram_parity_ecc_err,          // 57-56
                ctx_ctrl_ram_parity_ecc_err,                // 55-54
                avail_ring_ctrl_ram_parity_ecc_err,          // 53-52
                avail_ring_clone_ctrl_ram_parity_ecc_err,   // 51-50
                desc_engine_net_tx_ctrl_ram_parity_ecc_err,  // 49-48
                desc_engine_net_rx_ctrl_ram_parity_ecc_err,  // 47-46
                net_tx_ctrl_ram_parity_ecc_err,             // 45-44
                net_rx_ctrl_ram_parity_ecc_err,             // 43-42
                blk_desc_engine_ctrl_ram_parity_ecc_err,    // 41-40
                blk_down_stream_ctrl_ram_parity_ecc_err,    // 39-38
                blk_upstream_ctrl_ram_parity_ecc_err,      // 37-36
                used_dev_id_ram_parity_ecc_err,             // 35-34
                blk_upstream_dev_id_ram_parity_ecc_err,     // 33-32
                net_tx_dev_id_ram_parity_ecc_err,           // 31-30
                net_rx_dev_id_ram_parity_ecc_err,           // 29-28
                net_rx_buf_dev_id_ram_parity_ecc_err,        // 27-26
                idx_engine_bdf_ram_parity_ecc_err,          // 25-24
                avail_ring_bdf_ram_parity_ecc_err,          // 23-22
                used_bdf_ram_parity_ecc_err,                // 21-20
                desc_engine_net_tx_bdf_ram_parity_ecc_err, // 19-18
                desc_engine_net_rx_bdf_ram_parity_ecc_err, // 17-16
                net_tx_bdf_ram_parity_ecc_err,             // 15-14
                net_rx_bdf_ram_parity_ecc_err,             // 13-12
                blk_desc_engine_bdf_ram_parity_ecc_err,    // 11-10
                blk_down_stream_bdf_ram_parity_ecc_err,    // 9-8
                blk_upstream_bdf_ram_parity_ecc_err,      // 7-6
                avail_ring_addr_ram_parity_ecc_err,        // 5-4
                used_ring_addr_ram_parity_ecc_err,          // 3-2
                desc_engine_net_tx_desc_tbl_addr_ram_parity_ecc_err // 1-0
            };
        end
    end

    // dfx_err_1: 64bit
    always @(posedge clk) begin
        if(rst)begin
            dfx_err_1 <= {$bits(dfx_err_1){1'h0}};
        end else begin
            dfx_err_1 <= {
                desc_engine_net_rx_desc_tbl_addr_ram_parity_ecc_err, // 63-62
                blk_desc_engine_desc_tbl_addr_ram_parity_ecc_err,  // 61-60
                desc_engine_net_tx_qdepth_ram_parity_ecc_err,      // 59-58
                desc_engine_net_rx_qdepth_ram_parity_ecc_err,      // 57-56
                blk_desc_engine_qdepth_ram_parity_ecc_err,         // 55-54
                idx_engine_qdepth_ram_parity_ecc_err,             // 53-52
                avail_ring_qdepth_ram_parity_ecc_err,             // 51-50
                used_qdepth_ram_parity_ecc_err,                   // 49-48
                idx_engine_avail_idx_ram_parity_ecc_err,          // 47-46
                avail_ring_avail_idx_ram_parity_ecc_err,          // 45-44
                avail_ring_clone_avail_idx_ram_parity_ecc_err,     // 43-42
                avail_ring_avail_ui_ptr_ram_parity_ecc_err,        // 41-40
                avail_ring_clone_avail_ui_ptr_ram_parity_ecc_err, // 39-38
                idx_engine_avail_ui_ptr_ram_parity_ecc_err,       // 37-36
                ui_ptr_ram_parity_ecc_err,                         // 35-34
                avail_ring_avail_pi_ptr_ram_parity_ecc_err,        // 33-32
                pi_ptr_ram_parity_ecc_err,                         // 31-30
                avail_ring_avail_ci_ptr_ram_parity_ecc_err,        // 29-28
                avail_ring_clone_avail_ci_ptr_ram_parity_ecc_err, // 27-26
                ci_ptr_ram_parity_ecc_err,                         // 25-24
                idx_engine_no_notify_rd_req_rsp_num_ram_parity_ecc_err,          // 23-22
                no_notify_rd_req_rsp_num_ram_parity_ecc_err,                     // 21-20
                idx_engine_used_addr_ram_parity_ecc_err,           // 19-18
                idx_engine_dev_id_ram_parity_ecc_err,              // 17-16
                blk_down_stream_ptr_ram_parity_ecc_err,            // 15-14
                blk_ds_ptr_ram_parity_ecc_err,                     // 13-12
                used_ptr_ram_parity_ecc_err,                       // 11-10
                blk_upstream_ptr_ram_parity_ecc_err,              // 9-8
                blk_us_ptr_ram_parity_ecc_err,                     // 7-6
                used_elem_ptr_ram_parity_ecc_err,                  // 5-4
                used_err_fatal_flag_ram_parity_ecc_err,            // 3-2
                used_msix_addr_ram_parity_ecc_err                  // 1-0
            };
        end
    end

    // dfx_err_2: 64bit
    always @(posedge clk) begin
        if(rst)begin
            dfx_err_2 <= {$bits(dfx_err_2){1'h0}};
        end else begin
            dfx_err_2 <= {
                used_msix_data_ram_parity_ecc_err,                  // 63-62
                used_msix_enable_mask_pending_ram_parity_ecc_err,    // 61-60
                used_msix_aggregation_time_net_tx_ram_parity_ecc_err,// 59-58
                used_msix_aggregation_time_net_rx_ram_parity_ecc_err,// 57-56
                used_msix_aggregation_threshold_net_tx_ram_parity_ecc_err,// 55-54
                used_msix_aggregation_threshold_net_rx_ram_parity_ecc_err,// 53-52
                used_msix_aggregation_info_net_tx_ram_parity_ecc_err,// 51-50
                used_msix_aggregation_info_net_rx_ram_parity_ecc_err,// 49-48
                net_tx_qos_unit_ram_parity_ecc_err,                 // 47-46
                net_tx_qos_enable_ram_parity_ecc_err,               // 45-44
                net_tx_qos_unit_clone_ram_parity_ecc_err,          // 43-42
                net_tx_qos_enable_clone_ram_parity_ecc_err,         // 41-40
                net_rx_buf_qos_unit_ram_parity_ecc_err,             // 39-38
                net_rx_buf_qos_enable_ram_parity_ecc_err,           // 37-36
                blk_down_stream_qos_unit_ram_parity_ecc_err,        // 35-34
                blk_down_stream_qos_enable_ram_parity_ecc_err,      // 33-32
                blk_down_stream_generation_ram_parity_ecc_err,      // 31-30
                net_rx_buf_generation_ram_parity_ecc_err,           // 29-28
                blk_upstream_generation_ram_parity_ecc_err,         // 27-26
                net_tx_generation_ram_parity_ecc_err,               // 25-24
                blk_desc_eng_desc_tbl_addr_ram_parity_ecc_err,     // 23-22
                blk_desc_eng_desc_tbl_size_ram_parity_ecc_err,      // 21-20
                blk_desc_eng_desc_tbl_next_id_ram_parity_ecc_err,  // 19-18
                blk_desc_eng_desc_cnt_ram_parity_ecc_err,           // 17-16
                blk_desc_eng_data_len_ram_parity_ecc_err,           // 15-14
                blk_desc_eng_is_indirct_ram_parity_ecc_err,         // 13-12
                blk_desc_eng_resumer_ram_parity_ecc_err,            // 11-10
                blk_desc_eng_indirct_support_ram_parity_ecc_err,    // 9-8
                desc_eng_net_tx_indirct_support_ram_parity_ecc_err, // 7-6
                desc_eng_net_rx_indirct_support_ram_parity_ecc_err, // 5-4
                net_tx_tso_en_csum_en_ram_parity_ecc_err,           // 3-2
                desc_eng_net_tx_max_len_ram_parity_ecc_err          // 1-0
            };
        end
    end
    
    // dfx_err_3: 64bit
    always @(posedge clk) begin
        if(rst)begin
            dfx_err_3 <= {$bits(dfx_err_3){1'h0}};
        end else begin
            dfx_err_3 <= {
                43'h0,
                idx_engine_err_info_wr_req_vld && ~idx_engine_err_info_wr_req_dat.fatal, //20
                desc_eng_net_rx_max_len_ram_parity_ecc_err,            // 19-18
                blk_desc_eng_max_len_ram_parity_ecc_err,               // 17-16
                net_rx_buf_idx_limit_per_queue_ram_parity_ecc_err,     // 15-14
                desc_eng_net_tx_idx_limit_per_queue_ram_parity_ecc_err,// 13-12
                desc_eng_net_tx_idx_limit_per_dev_ram_parity_ecc_err,  // 11-10
                net_rx_buf_idx_limit_per_dev_ram_parity_ecc_err,       // 9-8
                desc_eng_net_tx_tail_vld_head_slot_ram_parity_ecc_err, // 7-6
                desc_eng_net_rx_tail_vld_head_slot_ram_parity_ecc_err, // 5-4
                used_dma_write_used_idx_irq_flag_ram_parity_ecc_err,   // 3-2
                blk_down_stream_chain_fst_seg_ram_parity_ecc_err       // 1-0
            };
        end
    end
    
    genvar idx_0;
    generate
        for(idx_0=0;idx_0<$bits(dfx_err_0);idx_0++)begin :virtio_ctx_dfx_err_0
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err_0[idx_0]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err_0:%d, id:%d", $time, dfx_err_0[idx_0], idx_0));
        end
    endgenerate

    genvar idx_1;
    generate
        for(idx_1=0;idx_1<$bits(dfx_err_1);idx_1++)begin :virtio_ctx_dfx_err_1
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err_1[idx_1]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err_1:%d, id:%d", $time, dfx_err_1[idx_1], idx_1));
        end
    endgenerate

    genvar idx_2;
    generate
        for(idx_2=0;idx_2<$bits(dfx_err_2);idx_2++)begin :virtio_ctx_dfx_err_2
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err_2[idx_2]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err_2:%d, id:%d", $time, dfx_err_2[idx_2], idx_2));
        end
    endgenerate

    genvar idx_3;
    generate
        for(idx_3=0;idx_3<$bits(dfx_err_3);idx_3++)begin :virtio_ctx_dfx_err_3
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err_3[idx_3]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err_3:%d, id:%d", $time, dfx_err_3[idx_3], idx_3));
        end
    endgenerate

    assign dfx_status = {
        hardware_stop_qid,                 //42-33
        hardware_stop_vld,                 //32
        idx_engine_err_info_wr_req_vld,    //31
        idx_engine_err_info_wr_req_rdy,    //30
        used_err_info_wr_vld,              //29
        used_err_info_wr_rdy,              //28
        idx_eng_err_process_finish,        //27
        used_err_process_finish,           //26
        used_wr_used_info_ram_en,          //25
        idx_eng_err_info_wen,              //24
        used_err_info_wen,                 //23
        err_stop_rdy,                      //22
        err_stop_vld,                      //21
        hardware_stop_en,                  //20
        err_info_fatal_d1,                 //19
        idx_engine_err_d1,                 //18
        err_cstat,                         //17-11
        err_stop_cstat,                    //10-7
        cstat                              //6-0
    };

    virtio_ctx_dfx #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(64)
    )u_virtio_ctx_dfx(
    .clk                         (clk                        ),
    .rst                         (rst                        ),
    .dfx_err_0_dfx_err_0_we      (|dfx_err_0                 ),
    .dfx_err_0_dfx_err_0_wdata   (dfx_err_0|dfx_err_0_q      ),
    .dfx_err_0_dfx_err_0_q       (dfx_err_0_q                ),
    .dfx_err_1_dfx_err_1_we      (|dfx_err_1                 ),
    .dfx_err_1_dfx_err_1_wdata   (dfx_err_1|dfx_err_1_q      ),
    .dfx_err_1_dfx_err_1_q       (dfx_err_1_q                ),
    .dfx_err_2_dfx_err_2_we      (|dfx_err_2                 ),
    .dfx_err_2_dfx_err_2_wdata   (dfx_err_2|dfx_err_2_q      ),
    .dfx_err_2_dfx_err_2_q       (dfx_err_2_q                ),
    .dfx_err_3_dfx_err_3_we      (|dfx_err_3                 ),
    .dfx_err_3_dfx_err_3_wdata   (dfx_err_3|dfx_err_3_q      ),
    .dfx_err_3_dfx_err_3_q       (dfx_err_3_q                ),
    .dfx_status_dfx_status_wdata (dfx_status                 ),
    .csr_if                      (dfx_if                     )
    );
    
 endmodule
