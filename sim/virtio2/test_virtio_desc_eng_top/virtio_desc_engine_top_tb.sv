/******************************************************************************
 * 文件名称 : virtio_desc_engine_top_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/07/17
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/17     Joe Jiang   初始化版本
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

module virtio_desc_engine_top_tb 
import alt_tlp_adaptor_pkg::*;
#(
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

    // Read request interface from DMA core
    input      logic                                           net_rx_dma_desc_rd_req_sav  ,
    output     logic                                           net_rx_dma_desc_rd_req_val  ,
    output     logic  [EMPTH_WIDTH-1:0]                        net_rx_dma_desc_rd_req_sty  ,
    output     logic  [$bits(desc_t)-1:0]                      net_rx_dma_desc_rd_req_desc ,
    // Read response interface back to DMA core             
    input      logic                                           net_rx_dma_desc_rd_rsp_val  ,
    input      logic                                           net_rx_dma_desc_rd_rsp_sop  ,
    input      logic                                           net_rx_dma_desc_rd_rsp_eop  ,
    input      logic                                           net_rx_dma_desc_rd_rsp_err  ,
    input      logic  [DATA_WIDTH-1:0]                         net_rx_dma_desc_rd_rsp_data ,
    input      logic  [EMPTH_WIDTH-1:0]                        net_rx_dma_desc_rd_rsp_sty  ,
    input      logic  [EMPTH_WIDTH-1:0]                        net_rx_dma_desc_rd_rsp_mty  ,
    input      logic  [$bits(desc_t)-1:0]                      net_rx_dma_desc_rd_rsp_desc ,

    // Read request interface from DMA core
    input      logic                                           net_tx_dma_desc_rd_req_sav  ,
    output     logic                                           net_tx_dma_desc_rd_req_val  ,
    output     logic  [EMPTH_WIDTH-1:0]                        net_tx_dma_desc_rd_req_sty  ,
    output     logic  [$bits(desc_t)-1:0]                      net_tx_dma_desc_rd_req_desc ,
    // Read response interface back to DMA core             
    input      logic                                           net_tx_dma_desc_rd_rsp_val  ,
    input      logic                                           net_tx_dma_desc_rd_rsp_sop  ,
    input      logic                                           net_tx_dma_desc_rd_rsp_eop  ,
    input      logic                                           net_tx_dma_desc_rd_rsp_err  ,
    input      logic  [DATA_WIDTH-1:0]                         net_tx_dma_desc_rd_rsp_data ,
    input      logic  [EMPTH_WIDTH-1:0]                        net_tx_dma_desc_rd_rsp_sty  ,
    input      logic  [EMPTH_WIDTH-1:0]                        net_tx_dma_desc_rd_rsp_mty  ,
    input      logic  [$bits(desc_t)-1:0]                      net_tx_dma_desc_rd_rsp_desc ,

    input  logic                                                net_rx_alloc_slot_req_vld,
    output logic                                                net_rx_alloc_slot_req_rdy,
    input  logic [9:0]                                          net_rx_alloc_slot_req_dev_id,
    input  logic [9:0]                                          net_rx_alloc_slot_req_pkt_id,
    input  logic [$bits(virtio_vq_t)-1:0]                       net_rx_alloc_slot_req_vq,
    output logic                                                net_rx_alloc_slot_rsp_vld,
    output logic [$bits(virtio_desc_eng_slot_rsp_t)-1:0]        net_rx_alloc_slot_rsp_dat,
    input  logic                                                net_rx_alloc_slot_rsp_rdy,

    input  logic                                                net_tx_alloc_slot_req_vld,
    output logic                                                net_tx_alloc_slot_req_rdy,
    input  logic [9:0]                                          net_tx_alloc_slot_req_dev_id,
    input  logic [9:0]                                          net_tx_alloc_slot_req_pkt_id,
    input  logic [$bits(virtio_vq_t)-1:0]                       net_tx_alloc_slot_req_vq,
    output logic                                                net_tx_alloc_slot_rsp_vld,
    output logic [$bits(virtio_desc_eng_slot_rsp_t)-1:0]        net_tx_alloc_slot_rsp_dat,
    input  logic                                                net_tx_alloc_slot_rsp_rdy,

    output logic                                                net_rx_avail_id_req_vld,
    output logic [2:0]                                          net_rx_avail_id_req_nid,
    input  logic                                                net_rx_avail_id_req_rdy,
    output logic [$bits(virtio_vq_t)-1:0]                       net_rx_avail_id_req_vq,
    input  logic                                                net_rx_avail_id_rsp_vld,
    input  logic                                                net_rx_avail_id_rsp_eop,
    output logic                                                net_rx_avail_id_rsp_rdy,
    input  logic [$bits(virtio_avail_id_rsp_dat_t)-1:0]         net_rx_avail_id_rsp_dat,

    output logic                                                net_tx_avail_id_req_vld,
    output logic [2:0]                                          net_tx_avail_id_req_nid,
    input  logic                                                net_tx_avail_id_req_rdy,
    output logic [$bits(virtio_vq_t)-1:0]                       net_tx_avail_id_req_vq,
    input  logic                                                net_tx_avail_id_rsp_vld,
    input  logic                                                net_tx_avail_id_rsp_eop,
    output logic                                                net_tx_avail_id_rsp_rdy,
    input  logic [$bits(virtio_avail_id_rsp_dat_t)-1:0]         net_tx_avail_id_rsp_dat,

    output logic                                                net_rx_desc_rsp_vld,
    output logic [$bits(virtio_desc_eng_desc_rsp_sbd_t)-1:0]    net_rx_desc_rsp_sbd,
    output logic                                                net_rx_desc_rsp_sop,
    output logic                                                net_rx_desc_rsp_eop,
    output logic [$bits(virtq_desc_t)-1:0]                      net_rx_desc_rsp_dat,
    input  logic                                                net_rx_desc_rsp_rdy, 

    output logic                                                net_tx_desc_rsp_vld,
    output logic [$bits(virtio_desc_eng_desc_rsp_sbd_t)-1:0]    net_tx_desc_rsp_sbd,
    output logic                                                net_tx_desc_rsp_sop,
    output logic                                                net_tx_desc_rsp_eop,
    output logic [$bits(virtq_desc_t)-1:0]                      net_tx_desc_rsp_dat,
    input  logic                                                net_tx_desc_rsp_rdy, 

    output logic                                                net_rx_ctx_info_rd_req_vld,
    output [$bits(virtio_vq_t)-1:0]                             net_rx_ctx_info_rd_req_vq,
    input  logic                                                net_rx_ctx_info_rd_rsp_vld,
    input  logic [63:0]                                         net_rx_ctx_info_rd_rsp_desc_tbl_addr,
    input  logic [3:0]                                          net_rx_ctx_info_rd_rsp_qdepth,
    input  logic                                                net_rx_ctx_info_rd_rsp_forced_shutdown,
    input  logic                                                net_rx_ctx_info_rd_rsp_indirct_support,
    input  logic [15:0]                                         net_rx_ctx_info_rd_rsp_bdf,
    input  logic [19:0]                                         net_rx_ctx_info_rd_rsp_max_len,
    output logic                                                net_rx_ctx_slot_chain_rd_req_vld,
    output [$bits(virtio_vq_t)-1:0]                             net_rx_ctx_slot_chain_rd_req_vq,
    input  logic                                                net_rx_ctx_slot_chain_rd_rsp_vld,
    input  logic [SLOT_WIDTH-1:0]                               net_rx_ctx_slot_chain_rd_rsp_head_slot,
    input  logic [SLOT_WIDTH-1:0]                               net_rx_ctx_slot_chain_rd_rsp_head_slot_vld,
    input  logic [SLOT_WIDTH-1:0]                               net_rx_ctx_slot_chain_rd_rsp_tail_slot,
    output logic                                                net_rx_ctx_slot_chain_wr_vld,
    output [$bits(virtio_vq_t)-1:0]                             net_rx_ctx_slot_chain_wr_vq,
    output logic [SLOT_WIDTH-1:0]                               net_rx_ctx_slot_chain_wr_head_slot,
    output logic                                                net_rx_ctx_slot_chain_wr_head_slot_vld,
    output logic [SLOT_WIDTH-1:0]                               net_rx_ctx_slot_chain_wr_tail_slot,
    output logic                                                net_tx_ctx_info_rd_req_vld,
    output [$bits(virtio_vq_t)-1:0]                             net_tx_ctx_info_rd_req_vq,
    input  logic                                                net_tx_ctx_info_rd_rsp_vld,
    input  logic [63:0]                                         net_tx_ctx_info_rd_rsp_desc_tbl_addr,
    input  logic [3:0]                                          net_tx_ctx_info_rd_rsp_qdepth,
    input  logic                                                net_tx_ctx_info_rd_rsp_forced_shutdown,
    input  logic                                                net_tx_ctx_info_rd_rsp_indirct_support,
    input  logic [15:0]                                         net_tx_ctx_info_rd_rsp_bdf,
    input  logic [19:0]                                         net_tx_ctx_info_rd_rsp_max_len,
    output logic                                                net_tx_ctx_slot_chain_rd_req_vld,
    output [$bits(virtio_vq_t)-1:0]                             net_tx_ctx_slot_chain_rd_req_vq,
    input  logic                                                net_tx_ctx_slot_chain_rd_rsp_vld,
    input  logic [SLOT_WIDTH-1:0]                               net_tx_ctx_slot_chain_rd_rsp_head_slot,
    input  logic [SLOT_WIDTH-1:0]                               net_tx_ctx_slot_chain_rd_rsp_head_slot_vld,
    input  logic [SLOT_WIDTH-1:0]                               net_tx_ctx_slot_chain_rd_rsp_tail_slot,
    output logic                                                net_tx_ctx_slot_chain_wr_vld,
    output [$bits(virtio_vq_t)-1:0]                             net_tx_ctx_slot_chain_wr_vq,
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
    input                                                       dfx_if_valid,
    input                                                       dfx_if_read,
    input        [                                   32-1:0]    dfx_if_addr,
    input        [                                   64-1:0]    dfx_if_wdata,
    input        [                                 64/8-1:0]    dfx_if_wmask,
    input                                                       dfx_if_rready,
    output                                                      dfx_if_ready,
    output                                                      dfx_if_rvalid,
    output       [                                   64-1:0]    dfx_if_rdata
);
    initial begin
      $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
      $fsdbDumpvars(0, virtio_desc_engine_top_tb, "+all");
      $fsdbDumpMDA();
    end

    tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))   net_rx_dma_desc_rd_req_if();
    tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))   net_rx_dma_desc_rd_rsp_if();
    tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))   net_tx_dma_desc_rd_req_if();
    tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))   net_tx_dma_desc_rd_rsp_if();

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

    assign net_rx_dma_desc_rd_req_if.sav            = net_rx_dma_desc_rd_req_sav;
    assign net_rx_dma_desc_rd_req_val               = net_rx_dma_desc_rd_req_if.vld;
    assign net_rx_dma_desc_rd_req_sty               = net_rx_dma_desc_rd_req_if.sty;
    assign net_rx_dma_desc_rd_req_desc              = net_rx_dma_desc_rd_req_if.desc;
    assign net_rx_dma_desc_rd_rsp_if.vld            = net_rx_dma_desc_rd_rsp_val;
    assign net_rx_dma_desc_rd_rsp_if.sop            = net_rx_dma_desc_rd_rsp_sop;
    assign net_rx_dma_desc_rd_rsp_if.eop            = net_rx_dma_desc_rd_rsp_eop;
    assign net_rx_dma_desc_rd_rsp_if.sty            = net_rx_dma_desc_rd_rsp_sty;
    assign net_rx_dma_desc_rd_rsp_if.mty            = net_rx_dma_desc_rd_rsp_mty;
    assign net_rx_dma_desc_rd_rsp_if.data           = net_rx_dma_desc_rd_rsp_data;
    assign net_rx_dma_desc_rd_rsp_if.err            = net_rx_dma_desc_rd_rsp_err;
    assign net_rx_dma_desc_rd_rsp_if.desc           = net_rx_dma_desc_rd_rsp_desc;

    assign net_tx_dma_desc_rd_req_if.sav            = net_tx_dma_desc_rd_req_sav;
    assign net_tx_dma_desc_rd_req_val               = net_tx_dma_desc_rd_req_if.vld;
    assign net_tx_dma_desc_rd_req_sty               = net_tx_dma_desc_rd_req_if.sty;
    assign net_tx_dma_desc_rd_req_desc              = net_tx_dma_desc_rd_req_if.desc;
    assign net_tx_dma_desc_rd_rsp_if.vld            = net_tx_dma_desc_rd_rsp_val;
    assign net_tx_dma_desc_rd_rsp_if.sop            = net_tx_dma_desc_rd_rsp_sop;
    assign net_tx_dma_desc_rd_rsp_if.eop            = net_tx_dma_desc_rd_rsp_eop;
    assign net_tx_dma_desc_rd_rsp_if.sty            = net_tx_dma_desc_rd_rsp_sty;
    assign net_tx_dma_desc_rd_rsp_if.mty            = net_tx_dma_desc_rd_rsp_mty;
    assign net_tx_dma_desc_rd_rsp_if.data           = net_tx_dma_desc_rd_rsp_data;
    assign net_tx_dma_desc_rd_rsp_if.err            = net_tx_dma_desc_rd_rsp_err;
    assign net_tx_dma_desc_rd_rsp_if.desc           = net_tx_dma_desc_rd_rsp_desc;

    virtio_desc_engine_top #(
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
    ) u_desc_engine_top (
        .clk                                            (clk                                            ),
        .rst                                            (rst                                            ),
        .net_rx_dma_desc_rd_req_if                      (net_rx_dma_desc_rd_req_if                      ),
        .net_rx_dma_desc_rd_rsp_if                      (net_rx_dma_desc_rd_rsp_if                      ),
        .net_tx_dma_desc_rd_req_if                      (net_tx_dma_desc_rd_req_if                      ),
        .net_tx_dma_desc_rd_rsp_if                      (net_tx_dma_desc_rd_rsp_if                      ),
        .net_rx_alloc_slot_req_vld                      (net_rx_alloc_slot_req_vld                      ),
        .net_rx_alloc_slot_req_rdy                      (net_rx_alloc_slot_req_rdy                      ),
        .net_rx_alloc_slot_req_dev_id                   (net_rx_alloc_slot_req_dev_id                   ),
        .net_rx_alloc_slot_req_pkt_id                   (net_rx_alloc_slot_req_pkt_id                   ),
        .net_rx_alloc_slot_req_vq                       (net_rx_alloc_slot_req_vq                       ),
        .net_rx_alloc_slot_rsp_vld                      (net_rx_alloc_slot_rsp_vld                      ),
        .net_rx_alloc_slot_rsp_dat                      (net_rx_alloc_slot_rsp_dat                      ),
        .net_rx_alloc_slot_rsp_rdy                      (net_rx_alloc_slot_rsp_rdy                      ),
        .net_tx_alloc_slot_req_vld                      (net_tx_alloc_slot_req_vld                      ),
        .net_tx_alloc_slot_req_rdy                      (net_tx_alloc_slot_req_rdy                      ),
        .net_tx_alloc_slot_req_dev_id                   (net_tx_alloc_slot_req_dev_id                   ),
        .net_tx_alloc_slot_req_pkt_id                   (net_tx_alloc_slot_req_pkt_id                   ),
        .net_tx_alloc_slot_req_vq                       (net_tx_alloc_slot_req_vq                       ),
        .net_tx_alloc_slot_rsp_vld                      (net_tx_alloc_slot_rsp_vld                      ),
        .net_tx_alloc_slot_rsp_dat                      (net_tx_alloc_slot_rsp_dat                      ),
        .net_tx_alloc_slot_rsp_rdy                      (net_tx_alloc_slot_rsp_rdy                      ),
        .net_rx_avail_id_req_vld                        (net_rx_avail_id_req_vld                        ),
        .net_rx_avail_id_req_nid                        (net_rx_avail_id_req_nid                        ),
        .net_rx_avail_id_req_rdy                        (net_rx_avail_id_req_rdy                        ),
        .net_rx_avail_id_req_vq                         (net_rx_avail_id_req_vq                         ),
        .net_rx_avail_id_rsp_vld                        (net_rx_avail_id_rsp_vld                        ),
        .net_rx_avail_id_rsp_eop                        (net_rx_avail_id_rsp_eop                        ),
        .net_rx_avail_id_rsp_rdy                        (net_rx_avail_id_rsp_rdy                        ),
        .net_rx_avail_id_rsp_dat                        (net_rx_avail_id_rsp_dat                        ),
        .net_tx_avail_id_req_vld                        (net_tx_avail_id_req_vld                        ),
        .net_tx_avail_id_req_nid                        (net_tx_avail_id_req_nid                        ),
        .net_tx_avail_id_req_rdy                        (net_tx_avail_id_req_rdy                        ),
        .net_tx_avail_id_req_vq                         (net_tx_avail_id_req_vq                         ),
        .net_tx_avail_id_rsp_vld                        (net_tx_avail_id_rsp_vld                        ),
        .net_tx_avail_id_rsp_eop                        (net_tx_avail_id_rsp_eop                        ),
        .net_tx_avail_id_rsp_rdy                        (net_tx_avail_id_rsp_rdy                        ),
        .net_tx_avail_id_rsp_dat                        (net_tx_avail_id_rsp_dat                        ),
        .net_rx_desc_rsp_vld                            (net_rx_desc_rsp_vld                            ),
        .net_rx_desc_rsp_sbd                            (net_rx_desc_rsp_sbd                            ),
        .net_rx_desc_rsp_sop                            (net_rx_desc_rsp_sop                            ),
        .net_rx_desc_rsp_eop                            (net_rx_desc_rsp_eop                            ),
        .net_rx_desc_rsp_dat                            (net_rx_desc_rsp_dat                            ),
        .net_rx_desc_rsp_rdy                            (net_rx_desc_rsp_rdy                            ), 
        .net_tx_desc_rsp_vld                            (net_tx_desc_rsp_vld                            ),
        .net_tx_desc_rsp_sbd                            (net_tx_desc_rsp_sbd                            ),
        .net_tx_desc_rsp_sop                            (net_tx_desc_rsp_sop                            ),
        .net_tx_desc_rsp_eop                            (net_tx_desc_rsp_eop                            ),
        .net_tx_desc_rsp_dat                            (net_tx_desc_rsp_dat                            ),
        .net_tx_desc_rsp_rdy                            (net_tx_desc_rsp_rdy                            ),     
        .net_rx_ctx_info_rd_req_vld                     (net_rx_ctx_info_rd_req_vld                     ),
        .net_rx_ctx_info_rd_req_vq                      (net_rx_ctx_info_rd_req_vq                      ),
        .net_rx_ctx_info_rd_rsp_vld                     (net_rx_ctx_info_rd_rsp_vld                     ),
        .net_rx_ctx_info_rd_rsp_desc_tbl_addr           (net_rx_ctx_info_rd_rsp_desc_tbl_addr           ),
        .net_rx_ctx_info_rd_rsp_qdepth                  (net_rx_ctx_info_rd_rsp_qdepth                  ),
        .net_rx_ctx_info_rd_rsp_forced_shutdown         (net_rx_ctx_info_rd_rsp_forced_shutdown         ),
        .net_rx_ctx_info_rd_rsp_indirct_support         (net_rx_ctx_info_rd_rsp_indirct_support         ),
        .net_rx_ctx_info_rd_rsp_bdf                     (net_rx_ctx_info_rd_rsp_bdf                     ),
        .net_rx_ctx_info_rd_rsp_max_len                 (net_rx_ctx_info_rd_rsp_max_len                 ),
        .net_rx_ctx_slot_chain_rd_req_vld               (net_rx_ctx_slot_chain_rd_req_vld               ),
        .net_rx_ctx_slot_chain_rd_req_vq                (net_rx_ctx_slot_chain_rd_req_vq                ),
        .net_rx_ctx_slot_chain_rd_rsp_vld               (net_rx_ctx_slot_chain_rd_rsp_vld               ),
        .net_rx_ctx_slot_chain_rd_rsp_head_slot         (net_rx_ctx_slot_chain_rd_rsp_head_slot         ),
        .net_rx_ctx_slot_chain_rd_rsp_head_slot_vld     (net_rx_ctx_slot_chain_rd_rsp_head_slot_vld     ),
        .net_rx_ctx_slot_chain_rd_rsp_tail_slot         (net_rx_ctx_slot_chain_rd_rsp_tail_slot         ),
        .net_rx_ctx_slot_chain_wr_vld                   (net_rx_ctx_slot_chain_wr_vld                   ),
        .net_rx_ctx_slot_chain_wr_vq                    (net_rx_ctx_slot_chain_wr_vq                    ),
        .net_rx_ctx_slot_chain_wr_head_slot             (net_rx_ctx_slot_chain_wr_head_slot             ),
        .net_rx_ctx_slot_chain_wr_head_slot_vld         (net_rx_ctx_slot_chain_wr_head_slot_vld         ),
        .net_rx_ctx_slot_chain_wr_tail_slot             (net_rx_ctx_slot_chain_wr_tail_slot             ),
        .net_tx_ctx_info_rd_req_vld                     (net_tx_ctx_info_rd_req_vld                     ),
        .net_tx_ctx_info_rd_req_vq                      (net_tx_ctx_info_rd_req_vq                      ),
        .net_tx_ctx_info_rd_rsp_vld                     (net_tx_ctx_info_rd_rsp_vld                     ),
        .net_tx_ctx_info_rd_rsp_desc_tbl_addr           (net_tx_ctx_info_rd_rsp_desc_tbl_addr           ),
        .net_tx_ctx_info_rd_rsp_qdepth                  (net_tx_ctx_info_rd_rsp_qdepth                  ),
        .net_tx_ctx_info_rd_rsp_forced_shutdown         (net_tx_ctx_info_rd_rsp_forced_shutdown         ),
        .net_tx_ctx_info_rd_rsp_indirct_support         (net_tx_ctx_info_rd_rsp_indirct_support         ),
        .net_tx_ctx_info_rd_rsp_bdf                     (net_tx_ctx_info_rd_rsp_bdf                     ),
        .net_tx_ctx_info_rd_rsp_max_len                 (net_tx_ctx_info_rd_rsp_max_len                 ),
        .net_tx_ctx_slot_chain_rd_req_vld               (net_tx_ctx_slot_chain_rd_req_vld               ),
        .net_tx_ctx_slot_chain_rd_req_vq                (net_tx_ctx_slot_chain_rd_req_vq                ),
        .net_tx_ctx_slot_chain_rd_rsp_vld               (net_tx_ctx_slot_chain_rd_rsp_vld               ),
        .net_tx_ctx_slot_chain_rd_rsp_head_slot         (net_tx_ctx_slot_chain_rd_rsp_head_slot         ),
        .net_tx_ctx_slot_chain_rd_rsp_head_slot_vld     (net_tx_ctx_slot_chain_rd_rsp_head_slot_vld     ),
        .net_tx_ctx_slot_chain_rd_rsp_tail_slot         (net_tx_ctx_slot_chain_rd_rsp_tail_slot         ),
        .net_tx_ctx_slot_chain_wr_vld                   (net_tx_ctx_slot_chain_wr_vld                   ),
        .net_tx_ctx_slot_chain_wr_vq                    (net_tx_ctx_slot_chain_wr_vq                    ),
        .net_tx_ctx_slot_chain_wr_head_slot             (net_tx_ctx_slot_chain_wr_head_slot             ),
        .net_tx_ctx_slot_chain_wr_head_slot_vld         (net_tx_ctx_slot_chain_wr_head_slot_vld         ),
        .net_tx_ctx_slot_chain_wr_tail_slot             (net_tx_ctx_slot_chain_wr_tail_slot             ),
        .net_tx_limit_per_queue_rd_req_vld              (net_tx_limit_per_queue_rd_req_vld              ),
        .net_tx_limit_per_queue_rd_req_qid              (net_tx_limit_per_queue_rd_req_qid              ),
        .net_tx_limit_per_queue_rd_rsp_vld              (net_tx_limit_per_queue_rd_rsp_vld              ),
        .net_tx_limit_per_queue_rd_rsp_dat              (net_tx_limit_per_queue_rd_rsp_dat              ),
        .net_tx_limit_per_dev_rd_req_vld                (net_tx_limit_per_dev_rd_req_vld                ),
        .net_tx_limit_per_dev_rd_req_dev_id             (net_tx_limit_per_dev_rd_req_dev_id             ),
        .net_tx_limit_per_dev_rd_rsp_vld                (net_tx_limit_per_dev_rd_rsp_vld                ),
        .net_tx_limit_per_dev_rd_rsp_dat                (net_tx_limit_per_dev_rd_rsp_dat                ),
        .dfx_if                                         (dfx_if                                         )
    );


    
endmodule
