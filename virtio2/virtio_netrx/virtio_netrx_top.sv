/******************************************************************************
 * 文件名称 : virtio_netrx_top.sv
 * 作者名称 : Feilong Yun
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/23     Feilong Yun   初始化版本
******************************************************************************/
 `include "virtio_netrx_define.svh"
 `include "tlp_adap_dma_if.svh"
module virtio_netrx_top #(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM),
    parameter DFX_ADDR_OFFSET = 0
)
(
    input                          clk,
    input                          rst,

    input                          netrx_info_vld,
    input  virtio_rx_buf_req_info_t   netrx_info_data,
    output                         netrx_info_rdy,

    output                         netrx_alloc_slot_req_vld,
    output     virtio_vq_t         netrx_alloc_slot_req_data,
    output     [9:0]               netrx_alloc_slot_req_dev_id,
    output     [`VIRTIO_RX_BUF_PKT_NUM_WIDTH-1:0] netrx_alloc_slot_req_pkt_id,
    input                          netrx_alloc_slot_req_rdy,

    input                          netrx_alloc_slot_rsp_vld,
    input    virtio_desc_eng_slot_rsp_t   netrx_alloc_slot_rsp_data,
    output                         netrx_alloc_slot_rsp_rdy,

    output                         slot_ctrl_dev_id_rd_req_vld,
    output    virtio_vq_t          slot_ctrl_dev_id_rd_req_qid,

    input                          slot_ctrl_dev_id_rd_rsp_vld,
    input     [9:0]                slot_ctrl_dev_id_rd_rsp_data,

    output                          netrx_desc_rsp_rdy,
    input                           netrx_desc_rsp_vld,
    input                           netrx_desc_rsp_sop,
    input                           netrx_desc_rsp_eop,
    input  virtio_desc_eng_desc_rsp_sbd_t  netrx_desc_rsp_sbd,
    input  virtq_desc_t             netrx_desc_rsp_data,

    output                          rd_data_req_vld,
    output  virtio_rx_buf_rd_data_req_t rd_data_req_data,
    input                           rd_data_req_rdy,

    input                           rd_data_rsp_vld,
    input                           rd_data_rsp_sop,
    input                           rd_data_rsp_eop,
    input  [DATA_EMPTY-1:0]    rd_data_rsp_sty,
    input  [DATA_EMPTY-1:0]    rd_data_rsp_mty,
    input  [DATA_WIDTH-1:0]    rd_data_rsp_data,
    output                          rd_data_rsp_rdy,
    input virtio_rx_buf_rd_data_rsp_sbd_t rd_data_rsp_sbd,

    tlp_adap_dma_wr_req_if.src      dma_wr_req,
    tlp_adap_dma_wr_rsp_if.snk      dma_wr_rsp,


    output                          wr_data_ctx_rd_req_vld,
    output      virtio_vq_t         wr_data_ctx_rd_req_qid,

    input                           wr_data_ctx_rd_rsp_vld,
    input        [15:0]             wr_data_ctx_rd_rsp_bdf,
    input                           wr_data_ctx_rd_rsp_forced_shutdown,

    output                          used_info_vld,
    output virtio_used_info_t       used_info_data,
    input                           used_info_rdy,

    mlite_if.slave                  dfx_slave

);


    logic                        order_fifo_vld;
    virtio_netrx_order_t         order_fifo_data;
    logic                        order_fifo_sav;

    logic                        slot_id_empty_info_vld;
    virtio_desc_eng_slot_rsp_t   slot_id_empty_info_data;
    logic                        slot_id_empty_info_rdy;


    logic [63:0]  dfx_status[2:0];
    logic [63:0]  dfx_err[2:0];

    logic [63:0]  cnt_drop_rcv_len_err;
    logic [63:0]  cnt_drop_desc_err;
    logic [63:0]  cnt_drop_empty;

    logic [63:0]  wr_issued_cnt;
    logic [63:0]  wr_rsp_cnt;


virtio_netrx_slot_ctrl #(
    .DATA_WIDTH (DATA_WIDTH),
    .DATA_EMPTY (DATA_EMPTY),
    .VIRTIO_Q_NUM (VIRTIO_Q_NUM ),
    .VIRTIO_Q_WIDTH (VIRTIO_Q_WIDTH)
)u_virtio_netrx_slot_ctrl
(
    .clk                              ( clk ),
    .rst                              ( rst ),

    .netrx_info_vld                   ( netrx_info_vld ),
    .netrx_info_data                  ( netrx_info_data ),
    .netrx_info_rdy                   ( netrx_info_rdy ),

    .netrx_alloc_slot_req_vld         ( netrx_alloc_slot_req_vld ),
    .netrx_alloc_slot_req_data        ( netrx_alloc_slot_req_data ),
    .netrx_alloc_slot_req_dev_id      ( netrx_alloc_slot_req_dev_id ),
    .netrx_alloc_slot_req_pkt_id      ( netrx_alloc_slot_req_pkt_id ),
    .netrx_alloc_slot_req_rdy         ( netrx_alloc_slot_req_rdy ),

    .netrx_alloc_slot_rsp_vld         ( netrx_alloc_slot_rsp_vld ),
    .netrx_alloc_slot_rsp_data        ( netrx_alloc_slot_rsp_data ),
    .netrx_alloc_slot_rsp_rdy         ( netrx_alloc_slot_rsp_rdy ),

    .slot_ctrl_dev_id_rd_req_vld      ( slot_ctrl_dev_id_rd_req_vld ),
    .slot_ctrl_dev_id_rd_req_qid      ( slot_ctrl_dev_id_rd_req_qid ),

    .slot_ctrl_dev_id_rd_rsp_vld      ( slot_ctrl_dev_id_rd_rsp_vld ),
    .slot_ctrl_dev_id_rd_rsp_data     ( slot_ctrl_dev_id_rd_rsp_data ),

    .slot_id_empty_info_vld           ( slot_id_empty_info_vld ),
    .slot_id_empty_info_data          ( slot_id_empty_info_data ), 
    .slot_id_empty_info_rdy           ( slot_id_empty_info_rdy ),

    .dfx_err                          ( dfx_err[0] ),
    .dfx_status                       ( dfx_status[0])


);

 virtio_netrx_dma_wr_req_ctrl #(
    .DATA_WIDTH (DATA_WIDTH),
    .DATA_EMPTY (DATA_EMPTY),
    .VIRTIO_Q_NUM (VIRTIO_Q_NUM ),
    .VIRTIO_Q_WIDTH (VIRTIO_Q_WIDTH)
)u_virtio_netrx_dma_wr_req_ctrl
(
    .clk                          ( clk ),
    .rst                          ( rst ),

    .slot_id_empty_info_vld       ( slot_id_empty_info_vld ),
    .slot_id_empty_info_data      ( slot_id_empty_info_data ), 
    .slot_id_empty_info_rdy       ( slot_id_empty_info_rdy ),
 
    .netrx_desc_rsp_rdy           ( netrx_desc_rsp_rdy ),
    .netrx_desc_rsp_vld           ( netrx_desc_rsp_vld ),
    .netrx_desc_rsp_sop           ( netrx_desc_rsp_sop ),
    .netrx_desc_rsp_eop           ( netrx_desc_rsp_eop ),
    .netrx_desc_rsp_sbd           ( netrx_desc_rsp_sbd ),
    .netrx_desc_rsp_data          ( netrx_desc_rsp_data ),

    .rd_data_req_vld              ( rd_data_req_vld ),
    .rd_data_req_data             ( rd_data_req_data ),
    .rd_data_req_rdy              ( rd_data_req_rdy ),

    .rd_data_rsp_vld              ( rd_data_rsp_vld ),
    .rd_data_rsp_sop              ( rd_data_rsp_sop ),
    .rd_data_rsp_eop              ( rd_data_rsp_eop ),
    .rd_data_rsp_sty              ( rd_data_rsp_sty ),
    .rd_data_rsp_mty              ( rd_data_rsp_mty ),
    .rd_data_rsp_data             ( rd_data_rsp_data ),
    .rd_data_rsp_rdy              ( rd_data_rsp_rdy ),
    .rd_data_rsp_sbd              ( rd_data_rsp_sbd ),

    .dma_wr_req                   ( dma_wr_req ),

    .order_fifo_vld               ( order_fifo_vld ),
    .order_fifo_data              ( order_fifo_data ),
    .order_fifo_sav               ( order_fifo_sav ),

    .wr_data_ctx_rd_req_vld         ( wr_data_ctx_rd_req_vld ),
    .wr_data_ctx_rd_req_qid         ( wr_data_ctx_rd_req_qid ),

    .wr_data_ctx_rd_rsp_vld         ( wr_data_ctx_rd_rsp_vld ),
    .wr_data_ctx_rd_rsp_bdf         ( wr_data_ctx_rd_rsp_bdf),
    .wr_data_ctx_rd_rsp_forced_shutdown(wr_data_ctx_rd_rsp_forced_shutdown),

    .cnt_drop_rcv_len_err        ( cnt_drop_rcv_len_err ),
    .cnt_drop_desc_err           ( cnt_drop_desc_err ),
    .cnt_drop_empty              ( cnt_drop_empty ),

    .wr_issued_cnt               ( wr_issued_cnt ),

    .dfx_err                          ( dfx_err[1] ),
    .dfx_status                       ( dfx_status[1])
);


virtio_netrx_wrrsp_sbd_ctrl #(
    .DATA_WIDTH (DATA_WIDTH),
    .DATA_EMPTY (DATA_EMPTY),
    .VIRTIO_Q_NUM (VIRTIO_Q_NUM ),
    .VIRTIO_Q_WIDTH (VIRTIO_Q_WIDTH)

 ) u_virtio_netrx_wrrsp_sbd_ctrl(
    .clk                           ( clk ),
    .rst                           ( rst ),

    .dma_wr_rsp                    ( dma_wr_rsp ),

    .order_fifo_vld                ( order_fifo_vld ),
    .order_fifo_data               ( order_fifo_data ),
    .order_fifo_sav                ( order_fifo_sav ),

    .used_info_vld                 ( used_info_vld ),
    .used_info_data                ( used_info_data ),
    .used_info_rdy                 ( used_info_rdy ),

    .wr_rsp_cnt                    ( wr_rsp_cnt ),

    .dfx_err                       ( dfx_err[2] ),
    .dfx_status                    ( dfx_status[2])

 );

 logic [25:0]dma_wr_req_block_cnt,dma_wr_req_vdata_cnt;
 logic [25:0]rd_data_rsp_block_cnt,rd_data_rsp_vdata_cnt;

 `ifdef PMON_EN

logic [25:0]  mon_tick_interval;

localparam MS_100_CLEAN_CNT = `MS_100_CLEAN_CNT_AT_USER_CLK;
assign mon_tick_interval = MS_100_CLEAN_CNT;

  performance_probe #(
    .PP_IF_NUM (1),
    .CNT_WIDTH (26)
) u_performance_probe(
    .clk                        ( clk ),
    .rst                        ( rst ),

    .backpressure_vld           (dma_wr_req.vld),
    .backpressure_sav           (dma_wr_req.sav),

    .handshake_vld              (rd_data_rsp_vld),
    .handshake_rdy              (rd_data_rsp_rdy),
    
    .mon_tick_interval          (mon_tick_interval),

    .backpressure_block_cnt     (dma_wr_req_block_cnt),
    .backpressure_vdata_cnt     (dma_wr_req_vdata_cnt),

    .handshake_block_cnt        (rd_data_rsp_block_cnt),
    .handshake_vdata_cnt        (rd_data_rsp_vdata_cnt) 
);
`endif 

 


 logic [63:0]dfx_err0_dfx_err_q,dfx_err1_dfx_err_q,dfx_err2_dfx_err_q;
    virtio_netrx_reg_dfx #(
        .ADDR_OFFSET (0),  //! Module's offset in the main address map
        .ADDR_WIDTH (16),   //! Width of SW address bus
        .DATA_WIDTH (64)    //! Width of SW data bus
    )u_virtio_netrx_reg_dfx
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
    
        .dma_wr_rate_dfx_cnt_wdata              ( {6'b0,dma_wr_req_vdata_cnt,6'b0,dma_wr_req_block_cnt}  ),  // offset_addr= 0x200
        .rx_buf_rate_dfx_cnt_wdata              ( {6'b0,rd_data_rsp_vdata_cnt,6'b0,rd_data_rsp_block_cnt}  ),
        .cnt_drop_rcv_len_err_dfx_cnt_wdata     ( cnt_drop_rcv_len_err ),
        .cnt_drop_desc_err_dfx_cnt_wdata        ( cnt_drop_desc_err ),
        .wr_issued_cnt_dfx_cnt_wdata            ( wr_issued_cnt ),
        .wr_rsp_cnt_dfx_cnt_wdata               ( wr_rsp_cnt ),
        
      
    
        .dfx_threshold0_dfx_threshold_swmod      (  ),          //! Indicates SW has modified this field  offset_addr = 0x400
        .dfx_threshold0_dfx_threshold_q          (  ),              //! Current field value    
    
    
    
        .csr_if                                 ( dfx_slave )
    
    );

endmodule