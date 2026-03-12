/******************************************************************************
 * 文件名称 : virtio_blk_downstream_tb.sv
 * 作者名称 : matao
 * 创建日期 : 2025/07/09
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   07/09       matao       初始化版本
 ******************************************************************************/
`include "mlite_if.svh"
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
module virtio_blk_downstream_tb 
    import alt_tlp_adaptor_pkg::*;
    #(
    parameter QOS_QUERY_UID_WIDTH   = 10    ,
    parameter REG_ADDR_WIDTH        = 23    ,
    parameter REG_DATA_WIDTH        = 64    ,
    parameter DATA_WIDTH            = 256   ,
    parameter EMPTH_WIDTH           = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_WIDTH        = 8     ,
    parameter WEIGHT_WIDTH          = 4     ,
    parameter VQ_WIDTH              = 8

)
(
    input                                                       clk                         ,
    input                                                       rst                         ,

    //notify 
    input  logic                                                sch_req_vld                 ,
    input  logic  [VIRTIO_Q_WIDTH-1:0]                          sch_req_qid                 ,
    output logic                                                sch_req_rdy                 ,

    //qos query update
    input  logic                                                qos_query_req_rdy           ,
    output logic  [QOS_QUERY_UID_WIDTH-1:0]                     qos_query_req_uid           ,
    output logic                                                qos_query_req_vld           ,

    input  logic                                                qos_query_rsp_vld           ,
    input  logic                                                qos_query_rsp_ok            ,
    output logic                                                qos_query_rsp_rdy           ,

    input  logic                                                qos_update_rdy              ,
    output logic                                                qos_update_vld              ,
    output logic [QOS_QUERY_UID_WIDTH-1:0]                      qos_update_uid              ,
    output logic [19:0]                                         qos_update_len              ,
    output logic [7:0]                                          qos_update_pkt_num          ,

    //alloc slot
    input  logic                                                alloc_slot_req_rdy          ,
    output logic                                                alloc_slot_req_vld          ,
    output logic [$bits(virtio_vq_t)-1:0]                       alloc_slot_req_dat          ,

    input  logic                                                alloc_slot_rsp_vld          ,
    input  logic [$bits(virtio_desc_eng_slot_rsp_t)-1:0]        alloc_slot_rsp_dat          ,
    output logic                                                alloc_slot_rsp_rdy          ,

    //blk desc
    input  logic                                                blk_desc_vld                ,
    input  logic                                                blk_desc_sop                ,
    input  logic                                                blk_desc_eop                ,
    input  logic [$bits(virtio_desc_eng_desc_rsp_sbd_t)-1:0]    blk_desc_sbd                ,
    input  logic [$bits(virtq_desc_t)-1:0]                      blk_desc_dat                ,
    output logic                                                blk_desc_rdy                ,

    // Read request interface from DMA core
    input  logic                                                dma_rd_req_sav              ,
    output logic                                                dma_rd_req_val              ,
    output logic [EMPTH_WIDTH-1:0]                              dma_rd_req_sty              ,
    output logic [$bits(desc_t)-1:0]                            dma_rd_req_desc             ,
    // Read response interface back to DMA core
    input  logic                                                dma_rd_rsp_val              ,
    input  logic                                                dma_rd_rsp_sop              ,
    input  logic                                                dma_rd_rsp_eop              ,
    input  logic                                                dma_rd_rsp_err              ,
    input  logic [DATA_WIDTH-1:0]                               dma_rd_rsp_data             ,
    input  logic [EMPTH_WIDTH-1:0]                              dma_rd_rsp_sty              ,
    input  logic [EMPTH_WIDTH-1:0]                              dma_rd_rsp_mty              ,
    input  logic [$bits(desc_t)-1:0]                            dma_rd_rsp_desc             ,

    input  logic                                                blk2beq_sav                 ,
    output logic                                                blk2beq_vld                 ,
    output logic [DATA_WIDTH-1:0]                               blk2beq_data                ,
    output logic [EMPTH_WIDTH-1:0]                              blk2beq_sty                 ,
    output logic [EMPTH_WIDTH-1:0]                              blk2beq_mty                 ,
    output logic                                                blk2beq_sop                 ,
    output logic                                                blk2beq_eop                 ,
    output logic [$bits(beq_rxq_sbd_t)-1:0]                     blk2beq_sbd                 ,

    //context info
    output logic                                                qos_info_rd_req_vld         ,
    output logic [VIRTIO_Q_WIDTH-1:0]                           qos_info_rd_req_qid         ,

    input  logic                                                qos_info_rd_rsp_vld         ,
    input  logic                                                qos_info_rd_rsp_qos_enable  ,
    input  logic [QOS_QUERY_UID_WIDTH-1:0]                      qos_info_rd_rsp_qos_unit    ,

    output logic                                                dma_info_rd_req_vld         ,
    output logic [VIRTIO_Q_WIDTH-1:0]                           dma_info_rd_req_qid         ,

    input  logic                                                dma_info_rd_rsp_vld         ,
    input  logic [15:0]                                         dma_info_rd_rsp_bdf         ,
    input  logic                                                dma_info_rd_rsp_forcedown   ,
    input  logic [7:0]                                          dma_info_rd_rsp_generation  ,

    output logic                                                blk_ds_ptr_rd_req_vld       ,
    output logic [VIRTIO_Q_WIDTH-1:0]                           blk_ds_ptr_rd_req_qid       ,
    input  logic                                                blk_ds_ptr_rd_rsp_vld       ,
    input  logic [15:0]                                         blk_ds_ptr_rd_rsp_dat       ,
    output logic                                                blk_ds_ptr_wr_vld           ,
    output logic [VIRTIO_Q_WIDTH-1:0]                           blk_ds_ptr_wr_qid           ,
    output logic [15:0]                                         blk_ds_ptr_wr_dat           ,

    output logic                                                blk_chain_fst_seg_rd_req_vld,
    output logic [VIRTIO_Q_WIDTH-1:0]                           blk_chain_fst_seg_rd_req_qid,
    input  logic                                                blk_chain_fst_seg_rd_rsp_vld,
    input  logic                                                blk_chain_fst_seg_rd_rsp_dat,
    output logic                                                blk_chain_fst_seg_wr_vld    ,
    output logic [VIRTIO_Q_WIDTH-1:0]                           blk_chain_fst_seg_wr_qid    ,
    output logic                                                blk_chain_fst_seg_wr_dat    ,
    
    input  logic                                                blk_ds_err_info_wr_rdy      ,
    output logic                                                blk_ds_err_info_wr_vld      ,
    output [$bits(virtio_vq_t)-1:0]                             blk_ds_err_info_wr_qid      ,
    output [$bits(virtio_err_info_t)-1:0]                       blk_ds_err_info_wr_dat      ,

    // Register Bus
    output logic                                                csr_if_ready                ,
    input  logic                                                csr_if_valid                ,
    input  logic                                                csr_if_read                 ,
    input  logic [REG_ADDR_WIDTH-1:0]                           csr_if_addr                 ,
    input  logic [REG_DATA_WIDTH-1:0]                           csr_if_wdata                ,
    input  logic [REG_DATA_WIDTH/8-1:0]                         csr_if_wmask                ,
    output logic [REG_DATA_WIDTH-1:0]                           csr_if_rdata                ,
    output logic                                                csr_if_rvalid               ,
    input  logic                                                csr_if_rready               
);
tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))   desc_rd_data_req_if();
tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))   desc_rd_data_rsp_if();

beq_rxq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   blk2beq_if();
mlite_if #(.ADDR_WIDTH(16), .DATA_WIDTH(REG_DATA_WIDTH)) csr_if();

logic [DATA_WIDTH-1:0]              blk_beq_data_tmp  ;
logic [$bits(beq_rxq_sbd_t)-1:0]    blk_beq_sbd_tmp   ;
logic                               notify_req_vld    ;
logic                               notify_req_rdy    ;
logic [VQ_WIDTH-1:0]                notify_req_qid    ;
logic                               notify_rsp_rdy    ;
logic                               notify_rsp_vld    ;
logic [VIRTIO_Q_WIDTH-1:0]          notify_rsp_qid    ;
logic                               notify_rsp_cold   ;
logic                               notify_rsp_done   ;

assign desc_rd_data_req_if.sav      = dma_rd_req_sav            ;
assign dma_rd_req_val               = desc_rd_data_req_if.vld   ;
assign dma_rd_req_sty               = desc_rd_data_req_if.sty   ;
assign dma_rd_req_desc              = desc_rd_data_req_if.desc  ;

assign desc_rd_data_rsp_if.vld      = dma_rd_rsp_val    ;
assign desc_rd_data_rsp_if.sop      = dma_rd_rsp_sop    ;
assign desc_rd_data_rsp_if.eop      = dma_rd_rsp_eop    ;
assign desc_rd_data_rsp_if.sty      = dma_rd_rsp_sty    ;
assign desc_rd_data_rsp_if.mty      = dma_rd_rsp_mty    ;
assign desc_rd_data_rsp_if.data     = dma_rd_rsp_data   ;
assign desc_rd_data_rsp_if.err      = dma_rd_rsp_err    ;
assign desc_rd_data_rsp_if.desc     = dma_rd_rsp_desc   ;

assign blk2beq_if.sav               = blk2beq_sav       ;
assign blk2beq_vld                  = blk2beq_if.vld    ;
assign blk2beq_sop                  = blk2beq_if.sop    ;
assign blk2beq_eop                  = blk2beq_if.eop    ;
assign blk_beq_sbd_tmp              = blk2beq_if.sbd    ;
assign blk2beq_sty                  = blk2beq_if.sty    ;
assign blk2beq_mty                  = blk2beq_if.mty    ;
assign blk_beq_data_tmp             = blk2beq_if.data   ;

assign csr_if_ready                 = csr_if.ready      ;
assign csr_if.valid                 = csr_if_valid      ;
assign csr_if.read                  = csr_if_read       ;
assign csr_if.addr                  = csr_if_addr       ;
assign csr_if.wdata                 = csr_if_wdata      ;
assign csr_if.wmask                 = csr_if_wmask      ;
assign csr_if_rdata                 = csr_if.rdata      ;
assign csr_if_rvalid                = csr_if.rvalid     ;
assign csr_if.rready                = csr_if_rready     ;

initial begin
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, virtio_blk_downstream_tb, "+all");
    $fsdbDumpMDA();
end

clear_x #(.DW(DATA_WIDTH)) u_beq_data_clearx (.in(blk_beq_data_tmp), .out(blk2beq_data));
clear_x #(.DW($bits(beq_rxq_sbd_t))) u_beq_sbd_clearx (.in(blk_beq_sbd_tmp), .out(blk2beq_sbd));
virtio_blk_downstream #(
    .QOS_QUERY_UID_WIDTH    (QOS_QUERY_UID_WIDTH),
    .VIRTIO_Q_WIDTH         (VIRTIO_Q_WIDTH     ),
    .DATA_WIDTH             (DATA_WIDTH         ),
    .REG_ADDR_WIDTH         (REG_ADDR_WIDTH     ),
    .REG_DATA_WIDTH         (REG_DATA_WIDTH     )
) u_virtio_blk_downstream(
    .clk                             (clk                         ),
    .rst                             (rst                         ),
    .notify_req_vld                  (notify_req_vld              ),
    .notify_req_qid                  (notify_req_qid              ),
    .notify_req_rdy                  (notify_req_rdy              ),
    .notify_rsp_rdy                  (notify_rsp_rdy              ),
    .notify_rsp_vld                  (notify_rsp_vld              ),
    .notify_rsp_qid                  (notify_rsp_qid              ),
    .notify_rsp_cold                 (notify_rsp_cold             ),
    .notify_rsp_done                 (notify_rsp_done             ),
    .qos_query_req_rdy               (qos_query_req_rdy           ),
    .qos_query_req_uid               (qos_query_req_uid           ),
    .qos_query_req_vld               (qos_query_req_vld           ),
    .qos_query_rsp_vld               (qos_query_rsp_vld           ),
    .qos_query_rsp_ok                (qos_query_rsp_ok            ),
    .qos_query_rsp_rdy               (qos_query_rsp_rdy           ),
    .qos_update_rdy                  (qos_update_rdy              ),
    .qos_update_vld                  (qos_update_vld              ),
    .qos_update_uid                  (qos_update_uid              ),
    .qos_update_len                  (qos_update_len              ),
    .qos_update_pkt_num              (qos_update_pkt_num          ),
    .alloc_slot_req_rdy              (alloc_slot_req_rdy          ),
    .alloc_slot_req_vld              (alloc_slot_req_vld          ),
    .alloc_slot_req_dat              (alloc_slot_req_dat          ),
    .alloc_slot_rsp_vld              (alloc_slot_rsp_vld          ),
    .alloc_slot_rsp_dat              (alloc_slot_rsp_dat          ),
    .alloc_slot_rsp_rdy              (alloc_slot_rsp_rdy          ),
    .blk_desc_vld                    (blk_desc_vld                ),
    .blk_desc_sop                    (blk_desc_sop                ),
    .blk_desc_eop                    (blk_desc_eop                ),
    .blk_desc_sbd                    (blk_desc_sbd                ),
    .blk_desc_dat                    (blk_desc_dat                ),
    .blk_desc_rdy                    (blk_desc_rdy                ),
    .desc_rd_data_req_if             (desc_rd_data_req_if         ),
    .desc_rd_data_rsp_if             (desc_rd_data_rsp_if         ),
    .blk2beq_if                      (blk2beq_if                  ),
    .qos_info_rd_req_vld             (qos_info_rd_req_vld         ),
    .qos_info_rd_req_qid             (qos_info_rd_req_qid         ),
    .qos_info_rd_rsp_vld             (qos_info_rd_rsp_vld         ),
    .qos_info_rd_rsp_qos_enable      (qos_info_rd_rsp_qos_enable  ),
    .qos_info_rd_rsp_qos_unit        (qos_info_rd_rsp_qos_unit    ),
    .dma_info_rd_req_vld             (dma_info_rd_req_vld         ),
    .dma_info_rd_req_qid             (dma_info_rd_req_qid         ),
    .dma_info_rd_rsp_vld             (dma_info_rd_rsp_vld         ),
    .dma_info_rd_rsp_bdf             (dma_info_rd_rsp_bdf         ),
    .dma_info_rd_rsp_forcedown       (dma_info_rd_rsp_forcedown   ),
    .dma_info_rd_rsp_generation      (dma_info_rd_rsp_generation  ),
    .blk_ds_ptr_rd_req_vld           (blk_ds_ptr_rd_req_vld       ),
    .blk_ds_ptr_rd_req_qid           (blk_ds_ptr_rd_req_qid       ),
    .blk_ds_ptr_rd_rsp_vld           (blk_ds_ptr_rd_rsp_vld       ),
    .blk_ds_ptr_rd_rsp_dat           (blk_ds_ptr_rd_rsp_dat       ),
    .blk_ds_ptr_wr_vld               (blk_ds_ptr_wr_vld           ),
    .blk_ds_ptr_wr_qid               (blk_ds_ptr_wr_qid           ),
    .blk_ds_ptr_wr_dat               (blk_ds_ptr_wr_dat           ),
    .blk_chain_fst_seg_rd_req_vld    (blk_chain_fst_seg_rd_req_vld),
    .blk_chain_fst_seg_rd_req_qid    (blk_chain_fst_seg_rd_req_qid),
    .blk_chain_fst_seg_rd_rsp_vld    (blk_chain_fst_seg_rd_rsp_vld),
    .blk_chain_fst_seg_rd_rsp_dat    (blk_chain_fst_seg_rd_rsp_dat),
    .blk_chain_fst_seg_wr_vld        (blk_chain_fst_seg_wr_vld    ),
    .blk_chain_fst_seg_wr_qid        (blk_chain_fst_seg_wr_qid    ),
    .blk_chain_fst_seg_wr_dat        (blk_chain_fst_seg_wr_dat    ),
    .blk_ds_err_info_wr_rdy          (blk_ds_err_info_wr_rdy      ),
    .blk_ds_err_info_wr_vld          (blk_ds_err_info_wr_vld      ),
    .blk_ds_err_info_wr_qid          (blk_ds_err_info_wr_qid      ),
    .blk_ds_err_info_wr_dat          (blk_ds_err_info_wr_dat      ),
    .csr_if                          (csr_if                      )
);
virtio_sch #(
    .WEIGHT_WIDTH   (WEIGHT_WIDTH ),
    .VQ_WIDTH       (VQ_WIDTH     )
) u_virtio_sch (
    .clk                            (clk                   ),
    .rst                            (rst                   ),
    .sch_req_vld                    (sch_req_vld           ),
    .sch_req_rdy                    (sch_req_rdy           ),
    .sch_req_qid                    (sch_req_qid           ),
    .notify_req_vld                 (notify_req_vld        ),
    .notify_req_rdy                 (notify_req_rdy        ),
    .notify_req_qid                 (notify_req_qid        ),
    .notify_rsp_vld                 (notify_rsp_vld        ),
    .notify_rsp_rdy                 (notify_rsp_rdy        ),
    .notify_rsp_qid                 (notify_rsp_qid        ),
    .notify_rsp_done                (notify_rsp_done       ),
    .notify_rsp_cold                (notify_rsp_cold       ),
    .hot_weight                     (4'd2                  ),
    .cold_weight                    (4'd1                  )
);
endmodule