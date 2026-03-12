/******************************************************************************
 * 文件名称 : virtio_used_tb.sv
 * 作者名称 : cui naiwan
 * 创建日期 : 2025/07/25
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/25     cui naiwan   初始化版本
 ******************************************************************************/
`include "tlp_adap_dma_if.svh"
 `include "virtio_define.svh"
 
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


module virtio_used_tb
    import alt_tlp_adaptor_pkg::*;
#(
    parameter CSR_ADDR_WIDTH            = 64,
    parameter CSR_DATA_WIDTH            = 64,
    parameter IRQ_MERGE_UINT_NUM        = 8,
    parameter IRQ_MERGE_UINT_NUM_WIDTH  = $clog2(IRQ_MERGE_UINT_NUM),
    parameter Q_NUM                     = 256,
    parameter Q_WIDTH                   = $clog2(Q_NUM),
    parameter DATA_WIDTH                = 256,
    parameter EMPTH_WIDTH               = $clog2(DATA_WIDTH/8),
    parameter TIME_MAP_WIDTH            = 2,
    parameter CLOCK_FREQ_MHZ            = 200,
    parameter TIME_STAMP_UNIT_NS        = 500
)(
    input                                            clk,
    input                                            rst,
    //==============wr_used_info from or to blk_upstream/nettx/netrx======================//
    input  logic                                     wr_used_info_vld,
    input  [$bits(virtio_used_info_t)-1:0]           wr_used_info_dat,
    output logic                                     wr_used_info_rdy,
    //=============dma_data_wr_if======================================//
//=============dma_data_wr_if=================//
    input  logic                                     dma_data_wr_req_sav,    // wr_req_val_i must de-assert within 3 cycles after de-assertion of wr_req_rdy_o
    output logic                                     dma_data_wr_req_val,    // Request is taken when asserted
    output logic                                     dma_data_wr_req_sop,    // Indicates first dataword
    output logic                                     dma_data_wr_req_eop,    // Indicates last dataword
    output logic  [DATA_WIDTH-1:0]                   dma_data_wr_req_data,    // Data to write to host in big endian format
    output logic  [EMPTH_WIDTH-1:0]                  dma_data_wr_req_sty,    // Points to first valid payload byte. Valid when wr_req_sop_i=1
    output logic  [EMPTH_WIDTH-1:0]                  dma_data_wr_req_mty,    // Number of unused bytes in last dataword. Valid when wr_req_eop_i=1
    output logic  [$bits(desc_t)-1:0]                dma_data_wr_req_desc,    // Descriptor for write. Valid when wr_req_sop_i=1
    // Write response interface from DMA core
    input  logic [27:0]                              dma_data_wr_rsp_rd2rsp_loop,
    input  logic                                     dma_data_wr_rsp_val,
    //===============from or to err_handle==============================//
    output logic                                     err_handle_vld,
    output [$bits(virtio_vq_t)-1:0]                  err_handle_qid,
    output [$bits(virtio_err_info_t)-1:0]            err_handle_dat,
    input  logic                                     err_handle_rdy,
    //===================from or to ctx=================================//
    input  logic                                     set_mask_req_vld,
    input  [$bits(virtio_vq_t)-1:0]                  set_mask_req_qid,
    input  logic                                     set_mask_req_dat,
    output logic                                     set_mask_req_rdy,
    //======================ctx_req/rsp===========================//
    output logic                                     used_ring_irq_req_vld,
    output [$bits(virtio_vq_t)-1:0]                  used_ring_irq_req_qid,
    input  logic                                     used_ring_irq_rsp_vld,
    input  logic                                     used_ring_irq_rsp_forced_shutdown,
    input  logic [63:0]                              used_ring_irq_rsp_msix_addr,
    input  logic [31:0]                              used_ring_irq_rsp_msix_data,
    input  logic [15:0]                              used_ring_irq_rsp_bdf,
    input  logic [9:0]                               used_ring_irq_rsp_dev_id,
    input  logic                                     used_ring_irq_rsp_msix_mask,
    input  logic                                     used_ring_irq_rsp_msix_pending,
    input  logic [63:0]                              used_ring_irq_rsp_used_ring_addr,
    input  logic [3:0]                               used_ring_irq_rsp_qdepth,
    input  logic                                     used_ring_irq_rsp_msix_enable,
    input  [$bits(virtio_qstat_t)-1:0]               used_ring_irq_rsp_q_status,
    input  logic                                     used_ring_irq_rsp_err_fatal,
    //===========================ctx err fatal wr====================================//
    output logic                                     err_fatal_wr_vld,
    output [$bits(virtio_vq_t)-1:0]                  err_fatal_wr_qid,
    output logic                                     err_fatal_wr_dat,
    //=========================used_elem_ptr rd/wr==================================//
    output logic                                     used_elem_ptr_rd_req_vld,
    output [$bits(virtio_vq_t)-1:0]                  used_elem_ptr_rd_req_qid,
    input  logic                                     used_elem_ptr_rd_rsp_vld,
    input  logic [$bits(virtio_used_elem_ptr_info_t)-1:0] used_elem_ptr_rd_rsp_dat,

    output logic                                     used_elem_ptr_wr_vld,
    output [$bits(virtio_vq_t)-1:0]                  used_elem_ptr_wr_qid,
    output logic [$bits(virtio_used_elem_ptr_info_t)-1:0] used_elem_ptr_wr_dat,

    //==========================update ctx used_idx=====================//
    output logic                                     used_idx_wr_vld,
    output [$bits(virtio_vq_t)-1:0]                  used_idx_wr_qid,
    output logic [15:0]                              used_idx_wr_dat,
    
    output logic                                     msix_tbl_wr_vld,
    output [$bits(virtio_vq_t)-1:0]                  msix_tbl_wr_qid,
    output logic                                     msix_tbl_wr_mask,
    output logic                                     msix_tbl_wr_pending,

    //===========================when dma write used_idx and irq, update flag in ctx===================================//
    output logic                                     dma_write_used_idx_irq_flag_wr_vld,
    output [$bits(virtio_vq_t)-1:0]                  dma_write_used_idx_irq_flag_wr_qid,
    output logic                                     dma_write_used_idx_irq_flag_wr_dat,

//=================irq_merge_core_tx from or to ctx============================//
    // msix_aggregation_time_rd_req
    output logic                                             msix_aggregation_time_rd_req_vld_net_tx,
    output logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]    msix_aggregation_time_rd_req_qid_net_tx,
    // msix_aggregation_time_rd_rsp                    
    input  logic                                             msix_aggregation_time_rd_rsp_vld_net_tx,
    input  logic [IRQ_MERGE_UINT_NUM*3-1:0]                  msix_aggregation_time_rd_rsp_dat_net_tx,       
    // msix_aggregation_threshold_rd_req   
    output logic                                             msix_aggregation_threshold_rd_req_vld_net_tx,
    output logic [Q_WIDTH-1:0]                               msix_aggregation_threshold_rd_req_qid_net_tx,
    // msix_aggregation_threshold_rd_rsp        
    input  logic                                             msix_aggregation_threshold_rd_rsp_vld_net_tx,
    input  logic [6:0]                                       msix_aggregation_threshold_rd_rsp_dat_net_tx,
    // msix_aggregation_info_rd_req                        
    output logic                                             msix_aggregation_info_rd_req_vld_net_tx,
    output logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]    msix_aggregation_info_rd_req_qid_net_tx,
    // msix_aggregation_info_rd_rsp
    input  logic                                             msix_aggregation_info_rd_rsp_vld_net_tx,
    input  logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0] msix_aggregation_info_rd_rsp_dat_net_tx,
    // msix_aggregation_info_wr                
    output logic                                             msix_aggregation_info_wr_vld_net_tx,
    output logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]    msix_aggregation_info_wr_qid_net_tx,
    output logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0] msix_aggregation_info_wr_dat_net_tx,
    //=========================irq merge_core_rx from or to ctx=================================//
    // msix_aggregation_time_rd_req
    output logic                                             msix_aggregation_time_rd_req_vld_net_rx,
    output logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]    msix_aggregation_time_rd_req_qid_net_rx,
    // msix_aggregation_time_rd_rsp                 
    input  logic                                             msix_aggregation_time_rd_rsp_vld_net_rx,
    input  logic [IRQ_MERGE_UINT_NUM*3-1:0]                  msix_aggregation_time_rd_rsp_dat_net_rx,       
    // msix_aggregation_threshold_rd_req
    output logic                                             msix_aggregation_threshold_rd_req_vld_net_rx,
    output logic [Q_WIDTH-1:0]                               msix_aggregation_threshold_rd_req_qid_net_rx,
    // msix_aggregation_threshold_rd_rsp
    input  logic                                             msix_aggregation_threshold_rd_rsp_vld_net_rx,
    input  logic [6:0]                                       msix_aggregation_threshold_rd_rsp_dat_net_rx,
    // msix_aggregation_info_rd_req                        
    output logic                                             msix_aggregation_info_rd_req_vld_net_rx,
    output logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]    msix_aggregation_info_rd_req_qid_net_rx,
    // msix_aggregation_info_rd_rsp
    input  logic                                             msix_aggregation_info_rd_rsp_vld_net_rx,
    input  logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0] msix_aggregation_info_rd_rsp_dat_net_rx,
    // msix_aggregation_info_wr                
    output logic                                             msix_aggregation_info_wr_vld_net_rx,
    output logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]    msix_aggregation_info_wr_qid_net_rx,
    output logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0] msix_aggregation_info_wr_dat_net_rx,

    //================from or to blk_down_stream=====================//
    output logic                                             blk_ds_err_info_wr_rdy,
    input  logic                                             blk_ds_err_info_wr_vld,
    input  logic [$bits(virtio_vq_t)-1:0]                    blk_ds_err_info_wr_qid,
    input  logic [$bits(virtio_err_info_t)-1:0]              blk_ds_err_info_wr_dat,

    output logic                                     csr_if_ready,
    input  logic                                     csr_if_valid,
    input  logic                                     csr_if_read,
    input  logic [CSR_ADDR_WIDTH-1:0]                csr_if_addr,
    input  logic [CSR_DATA_WIDTH-1:0]                csr_if_wdata,
    input  logic [CSR_DATA_WIDTH/8-1:0]              csr_if_wmask,
    output logic [CSR_DATA_WIDTH-1:0]                csr_if_rdata,
    output logic                                     csr_if_rvalid,
    input  logic                                     csr_if_rready
);

    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, virtio_used_tb, "+all");
        $fsdbDumpMDA();
    end

    mlite_if #(.ADDR_WIDTH(CSR_ADDR_WIDTH), .DATA_WIDTH(CSR_DATA_WIDTH)) csr_if();

    assign csr_if_ready     = csr_if.ready;
    assign csr_if.valid     = csr_if_valid;
    assign csr_if.read      = csr_if_read;
    assign csr_if.addr      = csr_if_addr;
    assign csr_if.wdata     = csr_if_wdata;
    assign csr_if.wmask     = csr_if_wmask;
    assign csr_if_rdata     = csr_if.rdata;
    assign csr_if_rvalid    = csr_if.rvalid;
    assign csr_if.rready    = csr_if_rready;

    tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_data_wr_req_if();
    tlp_adap_dma_wr_rsp_if                               dma_data_wr_rsp_if();

    assign dma_data_wr_req_if.sav            = dma_data_wr_req_sav;
    assign dma_data_wr_req_sop               = dma_data_wr_req_if.sop;
    assign dma_data_wr_req_eop               = dma_data_wr_req_if.eop;
    assign dma_data_wr_req_val               = dma_data_wr_req_if.vld;
    assign dma_data_wr_req_data              = dma_data_wr_req_if.data;
    assign dma_data_wr_req_sty               = dma_data_wr_req_if.sty;
    assign dma_data_wr_req_mty               = dma_data_wr_req_if.mty;
    clear_x #(.DW($bits(desc_t))) u_dma_data_wr_req_desc_clearx (.in(dma_data_wr_req_if.desc), .out(dma_data_wr_req_desc));
    assign dma_data_wr_rsp_if.vld            = dma_data_wr_rsp_val;
    assign dma_data_wr_rsp_if.rd2rsp_loop    = dma_data_wr_rsp_rd2rsp_loop;

    virtio_used_top #(
        .IRQ_MERGE_UINT_NUM                (IRQ_MERGE_UINT_NUM               ),
        .IRQ_MERGE_UINT_NUM_WIDTH          (IRQ_MERGE_UINT_NUM_WIDTH         ),
        .Q_NUM                             (Q_NUM             ),
        .Q_WIDTH                           (Q_WIDTH           ),
        .DATA_WIDTH                        (DATA_WIDTH        ),
        .EMPTH_WIDTH                       (EMPTH_WIDTH       ),
        .TIME_MAP_WIDTH                    (TIME_MAP_WIDTH    ),
        .CLOCK_FREQ_MHZ                    (CLOCK_FREQ_MHZ    ),
        .TIME_STAMP_UNIT_NS                (TIME_STAMP_UNIT_NS)
    ) u_virtio_used_top( 
        .clk                                                 (clk                                         ),
        .rst                                                 (rst                                         ),
        .wr_used_info_vld                                    (wr_used_info_vld                            ),
        .wr_used_info_dat                                    (wr_used_info_dat                            ),
        .wr_used_info_rdy                                    (wr_used_info_rdy                            ),
        .dma_data_wr_req_if                                  (dma_data_wr_req_if                          ),
        .dma_data_wr_rsp_if                                  (dma_data_wr_rsp_if                          ),
        .err_handle_vld                                      (err_handle_vld                              ),
        .err_handle_qid                                      (err_handle_qid                              ),
        .err_handle_dat                                      (err_handle_dat                              ),
        .err_handle_rdy                                      (err_handle_rdy                              ),
        .set_mask_req_vld                                    (set_mask_req_vld                            ),
        .set_mask_req_qid                                    (set_mask_req_qid                            ),
        .set_mask_req_dat                                    (set_mask_req_dat                            ),
        .set_mask_req_rdy                                    (set_mask_req_rdy                            ),
        .used_ring_irq_req_vld                               (used_ring_irq_req_vld                       ),
        .used_ring_irq_req_qid                               (used_ring_irq_req_qid                       ),
        .used_ring_irq_rsp_vld                               (used_ring_irq_rsp_vld                       ),
        .used_ring_irq_rsp_forced_shutdown                   (used_ring_irq_rsp_forced_shutdown           ),                 
        .used_ring_irq_rsp_msix_addr                         (used_ring_irq_rsp_msix_addr                 ),
        .used_ring_irq_rsp_msix_data                         (used_ring_irq_rsp_msix_data                 ),
        .used_ring_irq_rsp_bdf                               (used_ring_irq_rsp_bdf                       ),
        .used_ring_irq_rsp_dev_id                            (used_ring_irq_rsp_dev_id                    ),
        .used_ring_irq_rsp_msix_mask                         (used_ring_irq_rsp_msix_mask                 ),
        .used_ring_irq_rsp_msix_pending                      (used_ring_irq_rsp_msix_pending              ),
        .used_ring_irq_rsp_used_ring_addr                    (used_ring_irq_rsp_used_ring_addr            ),
        .used_ring_irq_rsp_qdepth                            (used_ring_irq_rsp_qdepth                    ),
        .used_ring_irq_rsp_msix_enable                       (used_ring_irq_rsp_msix_enable               ),
        .used_ring_irq_rsp_q_status                          (used_ring_irq_rsp_q_status                  ),
        .used_ring_irq_rsp_err_fatal                         (used_ring_irq_rsp_err_fatal                 ),
        .err_fatal_wr_vld                                    (err_fatal_wr_vld                            ),
        .err_fatal_wr_qid                                    (err_fatal_wr_qid                            ),
        .err_fatal_wr_dat                                    (err_fatal_wr_dat                            ),
        .used_elem_ptr_rd_req_vld                            (used_elem_ptr_rd_req_vld                    ),
        .used_elem_ptr_rd_req_qid                            (used_elem_ptr_rd_req_qid                    ),
        .used_elem_ptr_rd_rsp_vld                            (used_elem_ptr_rd_rsp_vld                    ),
        .used_elem_ptr_rd_rsp_dat                            (used_elem_ptr_rd_rsp_dat                    ),
        .used_elem_ptr_wr_vld                                (used_elem_ptr_wr_vld                        ),
        .used_elem_ptr_wr_qid                                (used_elem_ptr_wr_qid                        ),
        .used_elem_ptr_wr_dat                                (used_elem_ptr_wr_dat                        ),
        .used_idx_wr_vld                                     (used_idx_wr_vld                             ),
        .used_idx_wr_qid                                     (used_idx_wr_qid                             ),
        .used_idx_wr_dat                                     (used_idx_wr_dat                             ),
        .msix_tbl_wr_vld                                     (msix_tbl_wr_vld                             ),
        .msix_tbl_wr_qid                                     (msix_tbl_wr_qid                             ),
        .msix_tbl_wr_mask                                    (msix_tbl_wr_mask                            ),
        .msix_tbl_wr_pending                                 (msix_tbl_wr_pending                         ),
        .dma_write_used_idx_irq_flag_wr_vld                  (dma_write_used_idx_irq_flag_wr_vld          ),
        .dma_write_used_idx_irq_flag_wr_qid                  (dma_write_used_idx_irq_flag_wr_qid          ),
        .dma_write_used_idx_irq_flag_wr_dat                  (dma_write_used_idx_irq_flag_wr_dat          ),
        .msix_aggregation_time_rd_req_vld_net_tx             (msix_aggregation_time_rd_req_vld_net_tx     ),
        .msix_aggregation_time_rd_req_qid_net_tx             (msix_aggregation_time_rd_req_qid_net_tx     ),
        .msix_aggregation_time_rd_rsp_vld_net_tx             (msix_aggregation_time_rd_rsp_vld_net_tx     ),
        .msix_aggregation_time_rd_rsp_dat_net_tx             (msix_aggregation_time_rd_rsp_dat_net_tx     ),
        .msix_aggregation_threshold_rd_req_vld_net_tx        (msix_aggregation_threshold_rd_req_vld_net_tx),
        .msix_aggregation_threshold_rd_req_qid_net_tx        (msix_aggregation_threshold_rd_req_qid_net_tx),
        .msix_aggregation_threshold_rd_rsp_vld_net_tx        (msix_aggregation_threshold_rd_rsp_vld_net_tx),
        .msix_aggregation_threshold_rd_rsp_dat_net_tx        (msix_aggregation_threshold_rd_rsp_dat_net_tx),
        .msix_aggregation_info_rd_req_vld_net_tx             (msix_aggregation_info_rd_req_vld_net_tx     ),
        .msix_aggregation_info_rd_req_qid_net_tx             (msix_aggregation_info_rd_req_qid_net_tx     ),
        .msix_aggregation_info_rd_rsp_vld_net_tx             (msix_aggregation_info_rd_rsp_vld_net_tx     ),
        .msix_aggregation_info_rd_rsp_dat_net_tx             (msix_aggregation_info_rd_rsp_dat_net_tx     ),
        .msix_aggregation_info_wr_vld_net_tx                 (msix_aggregation_info_wr_vld_net_tx         ),
        .msix_aggregation_info_wr_qid_net_tx                 (msix_aggregation_info_wr_qid_net_tx         ),
        .msix_aggregation_info_wr_dat_net_tx                 (msix_aggregation_info_wr_dat_net_tx         ),
        .msix_aggregation_time_rd_req_vld_net_rx             (msix_aggregation_time_rd_req_vld_net_rx     ),
        .msix_aggregation_time_rd_req_qid_net_rx             (msix_aggregation_time_rd_req_qid_net_rx     ),
        .msix_aggregation_time_rd_rsp_vld_net_rx             (msix_aggregation_time_rd_rsp_vld_net_rx     ),
        .msix_aggregation_time_rd_rsp_dat_net_rx             (msix_aggregation_time_rd_rsp_dat_net_rx     ),
        .msix_aggregation_threshold_rd_req_vld_net_rx        (msix_aggregation_threshold_rd_req_vld_net_rx),
        .msix_aggregation_threshold_rd_req_qid_net_rx        (msix_aggregation_threshold_rd_req_qid_net_rx),
        .msix_aggregation_threshold_rd_rsp_vld_net_rx        (msix_aggregation_threshold_rd_rsp_vld_net_rx),
        .msix_aggregation_threshold_rd_rsp_dat_net_rx        (msix_aggregation_threshold_rd_rsp_dat_net_rx),
        .msix_aggregation_info_rd_req_vld_net_rx             (msix_aggregation_info_rd_req_vld_net_rx     ),
        .msix_aggregation_info_rd_req_qid_net_rx             (msix_aggregation_info_rd_req_qid_net_rx     ),
        .msix_aggregation_info_rd_rsp_vld_net_rx             (msix_aggregation_info_rd_rsp_vld_net_rx     ),
        .msix_aggregation_info_rd_rsp_dat_net_rx             (msix_aggregation_info_rd_rsp_dat_net_rx     ),
        .msix_aggregation_info_wr_vld_net_rx                 (msix_aggregation_info_wr_vld_net_rx         ),
        .msix_aggregation_info_wr_qid_net_rx                 (msix_aggregation_info_wr_qid_net_rx         ),
        .msix_aggregation_info_wr_dat_net_rx                 (msix_aggregation_info_wr_dat_net_rx         ),
        .blk_ds_err_info_wr_rdy                              (blk_ds_err_info_wr_rdy                      ),                             
        .blk_ds_err_info_wr_vld                              (blk_ds_err_info_wr_vld                      ),
        .blk_ds_err_info_wr_qid                              (blk_ds_err_info_wr_qid                      ),
        .blk_ds_err_info_wr_dat                              (blk_ds_err_info_wr_dat                      ),
        .dfx_if                                              (csr_if                                      )
    );


endmodule