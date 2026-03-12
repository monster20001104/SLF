/******************************************************************************
 *              : virtio_nettx_top.sv
 *              : Feilong Yun
 *              : 2025/06/23
 *              : 
 *
 *              : 
 *
 *                                                     
 * v1.0  06/23     Feilong Yun                  
******************************************************************************/
 `include "virtio_nettx_define.svh"
 `include "tlp_adap_dma_if.svh"
module virtio_nettx_top
   import alt_tlp_adaptor_pkg::*;
 #(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM),
    parameter CTRL_FIFO_DEPTH = 64,
    parameter DATA_FIFO_DEPTH = 1024,
    parameter DFX_ADDR_OFFSET = 0
)
(

    input                          clk,
    input                          rst,

    input                          notify_req_vld,
    input      [VIRTIO_Q_WIDTH-1:0]     notify_req_qid,
    output                         notify_req_rdy,

    output                         notify_rsp_vld,
    output     [VIRTIO_Q_WIDTH-1:0 ]    notify_rsp_qid,
    output                         notify_rsp_cold,
    output                         notify_rsp_done,
    input                          notify_rsp_rdy,

    output                         nettx_alloc_slot_req_vld,
    output     virtio_vq_t         nettx_alloc_slot_req_data,
    output     [9:0]               nettx_alloc_slot_req_dev_id,
    input                          nettx_alloc_slot_req_rdy,

    input                          nettx_alloc_slot_rsp_vld,
    input    virtio_desc_eng_slot_rsp_t   nettx_alloc_slot_rsp_data,
    output                         nettx_alloc_slot_rsp_rdy,

    output                         slot_ctrl_ctx_info_rd_req_vld,
    output    virtio_vq_t          slot_ctrl_ctx_info_rd_req_qid,

    input                          slot_ctrl_ctx_info_rd_rsp_vld,
    input     [VIRTIO_Q_WIDTH+1:0]      slot_ctrl_ctx_info_rd_rsp_qos_unit,
    input                          slot_ctrl_ctx_info_rd_rsp_qos_enable,
    input     [9:0]                slot_ctrl_ctx_info_rd_rsp_dev_id,

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
    input  virtio_desc_eng_desc_rsp_sbd_t  nettx_desc_rsp_sbd,
    input  virtq_desc_t             nettx_desc_rsp_data,

    input                           qos_update_rdy,
    output                          qos_update_vld,
    output  [VIRTIO_Q_WIDTH+1:0]         qos_update_uid,
    output  [19:0]                  qos_update_len,
    output  [9:0]                   qos_update_pkt_num,

    tlp_adap_dma_rd_req_if.src      dma_rd_req,
    tlp_adap_dma_rd_rsp_if.snk      dma_rd_rsp,

    output                          rd_data_ctx_info_rd_req_vld,
    output  virtio_vq_t             rd_data_ctx_info_rd_req_qid,

    input                           rd_data_ctx_info_rd_rsp_vld,
    input   [15:0]                  rd_data_ctx_info_rd_rsp_bdf,
    input                           rd_data_ctx_info_rd_rsp_forced_shutdown,
    input                           rd_data_ctx_info_rd_rsp_qos_enable,
    input   [VIRTIO_Q_WIDTH+1:0]         rd_data_ctx_info_rd_rsp_qos_unit,
    input                           rd_data_ctx_info_rd_rsp_tso_en,
    input                           rd_data_ctx_info_rd_rsp_csum_en,
    input   [7:0]                   rd_data_ctx_info_rd_rsp_gen,

    input                           net2tso_sav,
    output                          net2tso_vld,
    output                          net2tso_sop,
    output                          net2tso_eop,
    output   [DATA_EMPTY-1:0]  net2tso_sty,
    output   [DATA_EMPTY-1:0]  net2tso_mty,
    output                          net2tso_err,
    output   [DATA_WIDTH-1:0]  net2tso_data,
    output   [VIRTIO_Q_WIDTH-1:0]        net2tso_qid,
    output   [17:0]                 net2tso_len,
    output   [7:0]                  net2tso_gen,
    output                          net2tso_tso_en,
    output                          net2tso_csum_en,

    output                          used_info_vld,
    input                           used_info_rdy,
    output   virtio_used_info_t     used_info_data,

    mlite_if.slave                  dfx_slave


);

    logic                   data_fifo_rd;
    logic                   ctrl_fifo_rd;
    
    logic         order_fifo_vld;
    virtio_nettx_order_t    order_fifo_data;
    logic        order_fifo_sav;

    logic [63:0]  dfx_status[2:0];
    logic [63:0]  dfx_err[2:0];

    logic         dfx_vld;
    logic [31:0]  dfx_data;

    logic [63:0]  rd_issued_cnt,rd_rsp_cnt;


virtio_nettx_slot_ctrl #(
    .DATA_WIDTH (DATA_WIDTH),
    .DATA_EMPTY (DATA_EMPTY),
    .VIRTIO_Q_NUM (VIRTIO_Q_NUM ),
    .VIRTIO_Q_WIDTH (VIRTIO_Q_WIDTH)
)u_virtio_nettx_slot_ctrl
(
    .clk                            ( clk ),
    .rst                            ( rst ),

    .notify_req_vld                 ( notify_req_vld ),
    .notify_req_qid                 ( notify_req_qid ),
    .notify_req_rdy                 ( notify_req_rdy ),

    .notify_rsp_vld                 ( notify_rsp_vld ),
    .notify_rsp_qid                 ( notify_rsp_qid ),
    .notify_rsp_cold                ( notify_rsp_cold ),
    .notify_rsp_done                ( notify_rsp_done ),
    .notify_rsp_rdy                 ( notify_rsp_rdy ),

    .nettx_alloc_slot_req_vld       ( nettx_alloc_slot_req_vld ),
    .nettx_alloc_slot_req_data      ( nettx_alloc_slot_req_data ),
    .nettx_alloc_slot_req_dev_id    ( nettx_alloc_slot_req_dev_id ),
    .nettx_alloc_slot_req_rdy       ( nettx_alloc_slot_req_rdy ),

    .nettx_alloc_slot_rsp_vld       ( nettx_alloc_slot_rsp_vld ),
    .nettx_alloc_slot_rsp_data      ( nettx_alloc_slot_rsp_data ),
    .nettx_alloc_slot_rsp_rdy       ( nettx_alloc_slot_rsp_rdy ),

    .slot_ctrl_ctx_info_rd_req_vld  ( slot_ctrl_ctx_info_rd_req_vld ),
    .slot_ctrl_ctx_info_rd_req_qid  ( slot_ctrl_ctx_info_rd_req_qid ),

    .slot_ctrl_ctx_info_rd_rsp_vld  ( slot_ctrl_ctx_info_rd_rsp_vld ),
    .slot_ctrl_ctx_info_rd_rsp_qos_unit ( slot_ctrl_ctx_info_rd_rsp_qos_unit ),
    .slot_ctrl_ctx_info_rd_rsp_qos_enable ( slot_ctrl_ctx_info_rd_rsp_qos_enable ),
    .slot_ctrl_ctx_info_rd_rsp_dev_id ( slot_ctrl_ctx_info_rd_rsp_dev_id ),

    .qos_query_req_vld              ( qos_query_req_vld ),
    .qos_query_req_uid              ( qos_query_req_uid ),
    .qos_query_req_rdy              ( qos_query_req_rdy ) ,

    .qos_query_rsp_vld              ( qos_query_rsp_vld ),
    .qos_query_rsp_data             ( qos_query_rsp_data ),
    .qos_query_rsp_rdy              ( qos_query_rsp_rdy),

    .dfx_status                     ( dfx_status[0]),
    .dfx_err                        ( dfx_err[0])

);



 virtio_nettx_rd_data_ctrl #(
    .DATA_WIDTH ( DATA_WIDTH),
    .DATA_EMPTY  (DATA_EMPTY),
    .VIRTIO_Q_NUM  (VIRTIO_Q_NUM),
    .VIRTIO_Q_WIDTH  (VIRTIO_Q_WIDTH),
    .CTRL_FIFO_DEPTH (CTRL_FIFO_DEPTH),
    .DATA_FIFO_DEPTH (DATA_FIFO_DEPTH)
 )u_virtio_nettx_rd_data_ctrl
(
    .clk                      ( clk ),
    .rst                      ( rst ),

    .nettx_desc_rsp_rdy       ( nettx_desc_rsp_rdy ),
    .nettx_desc_rsp_vld       ( nettx_desc_rsp_vld ),
    .nettx_desc_rsp_sop       ( nettx_desc_rsp_sop ),
    .nettx_desc_rsp_eop       ( nettx_desc_rsp_eop ),
    .nettx_desc_rsp_sbd       ( nettx_desc_rsp_sbd ),
    .nettx_desc_rsp_data      ( nettx_desc_rsp_data ),

    .qos_update_rdy           ( qos_update_rdy ),
    .qos_update_vld           ( qos_update_vld ),
    .qos_update_uid           ( qos_update_uid ),
    .qos_update_len           ( qos_update_len ),
    .qos_update_pkt_num       ( qos_update_pkt_num),

    .dma_rd_req               ( dma_rd_req ),

    .dma_rd_rsp_val          ( dma_rd_rsp.vld ),
    .dma_rd_rsp_eop          ( dma_rd_rsp.eop ),
    .dma_rd_rsp_sop          ( dma_rd_rsp.sop ),
    .dma_rd_rsp_sty          ( dma_rd_rsp.sty ),
    .dma_rd_rsp_desc         ( dma_rd_rsp.desc ),

    .order_fifo_vld           ( order_fifo_vld ),
    .order_fifo_data          ( order_fifo_data ),
    .order_fifo_sav           ( order_fifo_sav ),

    .data_fifo_rd         ( data_fifo_rd ),
    .ctrl_fifo_rd         ( ctrl_fifo_rd ),

    .rd_data_ctx_info_rd_req_vld ( rd_data_ctx_info_rd_req_vld ),
    .rd_data_ctx_info_rd_req_qid ( rd_data_ctx_info_rd_req_qid ),

    .rd_data_ctx_info_rd_rsp_vld ( rd_data_ctx_info_rd_rsp_vld ),
    .rd_data_ctx_info_rd_rsp_bdf ( rd_data_ctx_info_rd_rsp_bdf ),
    .rd_data_ctx_info_rd_rsp_forced_shutdown ( rd_data_ctx_info_rd_rsp_forced_shutdown),
    .rd_data_ctx_info_rd_rsp_qos_enable ( rd_data_ctx_info_rd_rsp_qos_enable),
    .rd_data_ctx_info_rd_rsp_qos_unit ( rd_data_ctx_info_rd_rsp_qos_unit),
    .rd_data_ctx_info_rd_rsp_tso_en ( rd_data_ctx_info_rd_rsp_tso_en ),
    .rd_data_ctx_info_rd_rsp_csum_en ( rd_data_ctx_info_rd_rsp_csum_en ),
    .rd_data_ctx_info_rd_rsp_gen ( rd_data_ctx_info_rd_rsp_gen ),

    .dfx_vld                  ( dfx_vld ),
    .dfx_data                 ( dfx_data ),

    .rd_issued_cnt            ( rd_issued_cnt ),

    .dfx_status               ( dfx_status[1]),
    .dfx_err                  ( dfx_err[1] )


);


virtio_nettx_rsp_data_ctrl #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .DATA_EMPTY ( DATA_EMPTY ),
    .VIRTIO_Q_NUM ( VIRTIO_Q_NUM ),
    .VIRTIO_Q_WIDTH ( VIRTIO_Q_WIDTH),
    .CTRL_FIFO_DEPTH (CTRL_FIFO_DEPTH),
    .DATA_FIFO_DEPTH (DATA_FIFO_DEPTH)
)u_virtio_nettx_rsp_data_ctrl
(
    .clk                         ( clk ),
    .rst                         ( rst ),

    .dma_rd_rsp                  ( dma_rd_rsp ),

    .net2tso_sav                 ( net2tso_sav ),
    .net2tso_vld                 ( net2tso_vld ),
    .net2tso_sop                 ( net2tso_sop ),
    .net2tso_eop                 ( net2tso_eop ),
    .net2tso_sty                 ( net2tso_sty ),
    .net2tso_mty                 ( net2tso_mty ),
    .net2tso_err                 ( net2tso_err ),
    .net2tso_data                ( net2tso_data ),
    .net2tso_qid                 ( net2tso_qid ),
    .net2tso_len                 ( net2tso_len ),
    .net2tso_gen                 ( net2tso_gen ),
    .net2tso_tso_en              ( net2tso_tso_en ),
    .net2tso_csum_en             ( net2tso_csum_en ),

    .used_info_vld               ( used_info_vld ),
    .used_info_rdy               ( used_info_rdy ),
    .used_info_data              ( used_info_data ),

    .order_fifo_vld              ( order_fifo_vld ),
    .order_fifo_data             ( order_fifo_data ),
    .order_fifo_sav              ( order_fifo_sav ),

    .data_fifo_rd         ( data_fifo_rd ),
    .ctrl_fifo_rd         ( ctrl_fifo_rd ),

    .rd_rsp_cnt                  ( rd_rsp_cnt ),
            
    .dfx_err                     ( dfx_err[2] ),
    .dfx_status                  ( dfx_status[2] )


);
 logic [25:0]dma_rd_req_block_cnt,dma_rd_req_vdata_cnt,dma_rd_rsp_vdata_cnt;
 logic [25:0]net2tso_block_cnt,net2tso_vdata_cnt;

  `ifdef PMON_EN

    logic [25:0]  mon_tick_interval;

    localparam MS_100_CLEAN_CNT = `MS_100_CLEAN_CNT_AT_USER_CLK;
    assign mon_tick_interval = MS_100_CLEAN_CNT;

  performance_probe #(
    .PP_IF_NUM (3),
    .CNT_WIDTH (26)
) u_performance_probe(
    .clk                        ( clk ),
    .rst                        ( rst ),

    .backpressure_vld           ({dma_rd_rsp.vld,dma_rd_req.vld,net2tso_vld}),
    .backpressure_sav           ({1'b0,dma_rd_req.sav,net2tso_sav}),

    .handshake_vld              (),
    .handshake_rdy              (),
    
    .mon_tick_interval          (mon_tick_interval),

    .backpressure_block_cnt     ({dma_rd_req_block_cnt,net2tso_block_cnt}),
    .backpressure_vdata_cnt     ({dma_rd_rsp_vdata_cnt,dma_rd_req_vdata_cnt,net2tso_vdata_cnt}),

    .handshake_block_cnt        (),
    .handshake_vdata_cnt        () 
);
`endif 


logic [63:0]dfx_err0_dfx_err_q,dfx_err1_dfx_err_q,dfx_err2_dfx_err_q;
    virtio_nettx_reg_dfx #(
        .ADDR_OFFSET (0),  //! Module's offset in the main address map
        .ADDR_WIDTH (16),   //! Width of SW address bus
        .DATA_WIDTH (64)    //! Width of SW data bus
    )u_virtio_nettx_reg_dfx
    (
        .clk                                    ( clk ),     //! Default clock
        .rst                                    ( rst ),  //! Default reset
    
        .dfx_err0_dfx_err_we                    ( | dfx_err[0] ),             //! Control HW write (active high)     offset_addr= 0x00
        .dfx_err0_dfx_err_wdata                 ( dfx_err[0] | dfx_err0_dfx_err_q),          //! HW write data
        .dfx_err0_dfx_err_q                     ( dfx_err0_dfx_err_q ) ,
    
        .dfx_err1_dfx_err_we                    ( | dfx_err[1] ),             //! Control HW write (active high)
        .dfx_err1_dfx_err_wdata                 ( dfx_err[1] | dfx_err1_dfx_err_q),          //! HW write data
        .dfx_err1_dfx_err_q                     ( dfx_err1_dfx_err_q),
    
        .dfx_err2_dfx_err_we                    ( | dfx_err[2] ),             //! Control HW write (active high)
        .dfx_err2_dfx_err_wdata                 ( dfx_err[2] | dfx_err2_dfx_err_q),          //! HW write data
        .dfx_err2_dfx_err_q                     ( dfx_err2_dfx_err_q ),
    
        .dfx_status0_dfx_status_wdata           ( dfx_status[0] ),          //! HW write data  offset_addr= 0x100
        .dfx_status1_dfx_status_wdata           ( dfx_status[1]),           //! HW write data
        .dfx_status2_dfx_status_wdata           ( dfx_status[2]),          //! HW write data
    
        .dma_req_rate_dfx_cnt_wdata             ({6'b0,dma_rd_req_block_cnt,6'b0,dma_rd_req_vdata_cnt}   ),  // offset_addr= 0x200
        .dma_rsp_rate_dfx_cnt_wdata             ( dma_rd_rsp_vdata_cnt  ),
        .tso_rate_dfx_cnt_wdata                 ( {6'b0,net2tso_block_cnt,6'b0,net2tso_vdata_cnt}  ),
        .rd_issued_cnt_dfx_cnt_wdata            ( rd_issued_cnt ),
        .rd_rsp_cnt_dfx_cnt_wdata               ( rd_rsp_cnt ),

    
        .dfx_threshold0_dfx_threshold_swmod      ( dfx_vld  ),          //! Indicates SW has modified this field  offset_addr = 0x400
        .dfx_threshold0_dfx_threshold_q          ( dfx_data  ),              //! Current field value
        
    
        .csr_if                                 ( dfx_slave )
    
    );



endmodule
