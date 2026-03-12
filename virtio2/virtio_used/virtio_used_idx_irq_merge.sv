/******************************************************************************
 * 文件名称 : virtio_used_irq_merge.sv
 * 作者名称 : cui naiwan
 * 创建日期 : 2025/06/24
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/24     cui naiwan   初始化版本
 ******************************************************************************/
 `include "virtio_define.svh"
 `include "virtio_used_define.svh"
 module virtio_used_idx_irq_merge #(
    parameter IRQ_MERGE_UINT_NUM       = 8,
    parameter IRQ_MERGE_UINT_NUM_WIDTH = $clog2(IRQ_MERGE_UINT_NUM),
    parameter Q_NUM                    = 256,
    parameter Q_WIDTH                  = $clog2(Q_NUM),
    parameter TIME_MAP_WIDTH           = 2,
    parameter CLOCK_FREQ_MHZ           = 200,
    parameter TIME_STAMP_UNIT_NS       = 500
)(
    input                                                    clk,
    input                                                    rst,
    //==================from or to blk_upstream/nettx/netrx======================//
    input  logic                                             wr_used_info_vld,
    input  virtio_used_info_t                                wr_used_info_dat,
    output logic                                             wr_used_info_rdy,
    //==================from or to virtio_used_top=============================//
    output logic                                             used_info_irq_vld,
    output used_irq_ff_entry_t                               used_info_irq_dat,
    input  logic                                             used_info_irq_rdy,
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
    //====================dfx====================================================//
    output logic [19:0]                                      dfx_err,
    output logic [14:0]                                      dfx_status,
    output logic [3:0]                                       dfx_irq_merge_core_net_tx_err,
    output logic [3:0]                                       dfx_irq_merge_core_net_rx_err

);

    enum logic [4:0] {
        IDLE                                = 5'b00001,
        ARBITER                             = 5'b00010,
        WR_USED_INFO_BLK_FF                 = 5'b00100,
        WR_USED_INFO_NET_USED_IDX_IRQ_MERGE = 5'b01000,
        WR_USED_IDX_IRQ                     = 5'b10000
    } irq_cstat, irq_nstat;

    localparam EMPTY_WIDTH = $bits(virtio_used_info_t) - $bits(virtio_vq_t);

    logic [3:0] req_sch_req, req_sch_grant;
    logic blk_used_idx_irq_vld, net_tx_used_idx_irq_vld, net_rx_used_idx_irq_vld;
    logic req_sch_en, req_sch_grant_vld, is_net_rx_used_idx_irq, is_net_tx_used_idx_irq, is_blk_used_idx_irq, is_used_info;
        
    virtio_vq_t blk_used_idx_irq_qid, net_used_idx_irq_qid, irq_merge_core_rx_irq_in_qid, irq_merge_core_tx_irq_in_qid, irq_merge_core_rx_irq_out_qid, irq_merge_core_tx_irq_out_qid;
    logic [Q_WIDTH-1:0] irq_out_qid_tx, irq_out_qid_rx;
    logic blk_used_idx_irq_ff_empty, blk_used_idx_irq_ff_wren, blk_used_idx_irq_ff_pfull, blk_used_idx_irq_ff_rden;
    virtio_vq_t blk_used_idx_irq_ff_din, blk_used_idx_irq_ff_dout;
    logic blk_used_idx_irq_ff_overflow, blk_used_idx_irq_ff_underflow;
    logic [1:0] blk_used_idx_irq_ff_parity_ecc_err;
    logic net_tx_used_idx_irq_merge_in_ff_empty, net_tx_used_idx_irq_merge_in_ff_wren, net_tx_used_idx_irq_merge_in_ff_pfull, net_tx_used_idx_irq_merge_in_ff_rden;
    logic [Q_WIDTH-1:0] net_tx_used_idx_irq_merge_in_ff_din, net_tx_used_idx_irq_merge_in_ff_dout;
    logic net_tx_used_idx_irq_merge_in_ff_overflow, net_tx_used_idx_irq_merge_in_ff_underflow;
    logic [1:0] net_tx_used_idx_irq_merge_in_ff_parity_ecc_err;
    logic net_rx_used_idx_irq_merge_in_ff_empty, net_rx_used_idx_irq_merge_in_ff_wren, net_rx_used_idx_irq_merge_in_ff_pfull, net_rx_used_idx_irq_merge_in_ff_rden;
    logic [Q_WIDTH-1:0] net_rx_used_idx_irq_merge_in_ff_din, net_rx_used_idx_irq_merge_in_ff_dout;
    logic net_rx_used_idx_irq_merge_in_ff_overflow, net_rx_used_idx_irq_merge_in_ff_underflow;
    logic [1:0] net_rx_used_idx_irq_merge_in_ff_parity_ecc_err;
    logic used_irq_ff_wren, used_irq_ff_pfull, used_irq_ff_rden;
    used_irq_ff_entry_t used_irq_ff_din, used_irq_ff_dout;
    logic used_irq_ff_overflow, used_irq_ff_underflow;
    logic [1:0] used_irq_ff_parity_ecc_err;
    logic irq_merge_core_tx_irq_in_vld, irq_merge_core_rx_irq_in_vld, irq_merge_core_tx_irq_in_rdy, irq_merge_core_rx_irq_in_rdy;
    logic blk_rdy, net_tx_rdy, net_rx_rdy;    
    logic [1:0] net_used_idx_irq_sch_req, net_used_idx_irq_sch_grant;
    logic net_used_idx_irq_sch_en, net_used_idx_irq_sch_grant_vld;
    logic net_used_idx_irq_ff_empty, net_used_idx_irq_ff_wren, net_used_idx_irq_ff_pfull, net_used_idx_irq_ff_rden;
    net_used_idx_irq_ff_entry_t net_used_idx_irq_ff_din, net_used_idx_irq_ff_dout, net_used_idx_irq;
    logic net_used_idx_irq_ff_overflow, net_used_idx_irq_ff_underflow;
    logic [1:0] net_used_idx_irq_ff_parity_ecc_err;
    logic irq_merge_core_tx_irq_out_vld, irq_merge_core_tx_irq_out_rdy, irq_merge_core_rx_irq_out_vld, irq_merge_core_rx_irq_out_rdy;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] msix_aggregation_time_rd_req_idx_net_tx, msix_aggregation_info_rd_req_idx_net_tx, msix_aggregation_info_wr_idx_net_tx;
    logic [Q_WIDTH-1:0] msix_aggregation_threshold_rd_req_idx_net_tx;
    logic [(Q_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] msix_aggregation_time_rd_req_idx_net_rx, msix_aggregation_info_rd_req_idx_net_rx, msix_aggregation_info_wr_idx_net_rx;
    logic [Q_WIDTH-1:0] msix_aggregation_threshold_rd_req_idx_net_rx;

    //===============rr_sch=======================//
    assign blk_used_idx_irq_vld    = ~blk_used_idx_irq_ff_empty;
    assign net_tx_used_idx_irq_vld = (~net_used_idx_irq_ff_empty) && (net_used_idx_irq_ff_dout.typ == NET_TX_USED_IDX_IRQ);
    assign net_rx_used_idx_irq_vld = (~net_used_idx_irq_ff_empty) && (net_used_idx_irq_ff_dout.typ == NET_RX_USED_IDX_IRQ);

    assign req_sch_req = {net_rx_used_idx_irq_vld, net_tx_used_idx_irq_vld, blk_used_idx_irq_vld, wr_used_info_vld};
    assign req_sch_en = (irq_cstat == IDLE) && (blk_rdy || net_tx_rdy || net_rx_rdy);

    rr_sch#(
        .SH_NUM(4)         
    )u_irq_rr_sch(
        .clk           (clk),
        .rst           (rst),
        .sch_req       (req_sch_req      ),
        .sch_en        (req_sch_en       ), 
        .sch_grant     (req_sch_grant    ), 
        .sch_grant_vld (req_sch_grant_vld)   
    );

    always @(posedge clk) begin
        if((irq_cstat == IDLE) && req_sch_grant_vld) begin
            {is_net_rx_used_idx_irq, is_net_tx_used_idx_irq, is_blk_used_idx_irq, is_used_info} <= req_sch_grant;
        end
    end

    assign blk_rdy    = (wr_used_info_vld && (wr_used_info_dat.vq.typ == VIRTIO_BLK_TYPE)) ? (~blk_used_idx_irq_ff_pfull) : 1'b1;
    assign net_tx_rdy = (wr_used_info_vld && (wr_used_info_dat.vq.typ == VIRTIO_NET_TX_TYPE)) ? (~net_tx_used_idx_irq_merge_in_ff_pfull) : 1'b1;
    assign net_rx_rdy = (wr_used_info_vld && (wr_used_info_dat.vq.typ == VIRTIO_NET_RX_TYPE)) ? (~net_rx_used_idx_irq_merge_in_ff_pfull) : 1'b1;

    //===============irq_merge=================//
    always @(posedge clk) begin
        if(rst) begin
            irq_cstat <= IDLE;
        end else begin
            irq_cstat <= irq_nstat;
        end
    end

    always @(*) begin
        irq_nstat = irq_cstat;
        case(irq_cstat)
            IDLE: begin
                if(req_sch_grant_vld && (blk_rdy || net_tx_rdy || net_rx_rdy)) begin
                    irq_nstat = ARBITER;
                end
            end
            ARBITER: begin
                if(~used_irq_ff_pfull) begin
                    if(is_used_info) begin 
                        if(wr_used_info_dat.vq.typ == VIRTIO_BLK_TYPE) begin
                            irq_nstat = WR_USED_INFO_BLK_FF;
                        end else begin  //typ == NET_TX or NET_RX
                            irq_nstat = WR_USED_INFO_NET_USED_IDX_IRQ_MERGE;
                        end
                    end
                    else if(is_blk_used_idx_irq || is_net_tx_used_idx_irq || is_net_rx_used_idx_irq) begin
                        irq_nstat = WR_USED_IDX_IRQ;
                    end
                end
            end 
            WR_USED_INFO_NET_USED_IDX_IRQ_MERGE, WR_USED_INFO_BLK_FF, WR_USED_IDX_IRQ: begin
                irq_nstat = IDLE;
            end
            default: irq_nstat = IDLE;
        endcase      
    end

    assign wr_used_info_rdy = (irq_cstat == WR_USED_INFO_NET_USED_IDX_IRQ_MERGE) || (irq_cstat == WR_USED_INFO_BLK_FF);  //to virtio_used external used_sch

    //========================blk_used_idx_irq_ff=============================//
    yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(virtio_vq_t)                             ),
        .FIFO_DEPTH ( 32                                                            ),
        .CHECK_ON   ( 1                                                             ),
        .CHECK_MODE ( "parity"                                                      ),
        .DEPTH_PFULL( 24                                                            ),
        .RAM_MODE   ( "dist"                                                        ),
        .FIFO_MODE  ( "fwft"                                                        )
    ) u_blk_used_idx_irq_ff (
        .clk             (clk                                  ),
        .rst             (rst                                  ),
        .wren            (blk_used_idx_irq_ff_wren             ),
        .din             (blk_used_idx_irq_ff_din              ),
        .full            (                                     ),
        .pfull           (blk_used_idx_irq_ff_pfull            ),
        .overflow        (blk_used_idx_irq_ff_overflow         ),
        .rden            (blk_used_idx_irq_ff_rden             ),
        .dout            (blk_used_idx_irq_ff_dout             ),
        .empty           (blk_used_idx_irq_ff_empty            ),
        .pempty          (                                     ),
        .underflow       (blk_used_idx_irq_ff_underflow        ),
        .usedw           (                                     ),
        .parity_ecc_err  (blk_used_idx_irq_ff_parity_ecc_err   )
    );

    assign blk_used_idx_irq_ff_wren = (irq_cstat == WR_USED_INFO_BLK_FF);
    assign blk_used_idx_irq_ff_din  = wr_used_info_dat.vq;
    assign blk_used_idx_irq_ff_rden = (irq_cstat == WR_USED_IDX_IRQ) && is_blk_used_idx_irq;
    assign blk_used_idx_irq_qid     = blk_used_idx_irq_ff_dout;

    //========================net_tx_used_idx_irq_merge_in_ff=============================//
    yucca_sync_fifo #(
        .DATA_WIDTH ( Q_WIDTH                             ),
        .FIFO_DEPTH ( 32                                                            ),
        .CHECK_ON   ( 1                                                             ),
        .CHECK_MODE ( "parity"                                                      ),
        .DEPTH_PFULL( 24                                                            ),
        .RAM_MODE   ( "dist"                                                        ),
        .FIFO_MODE  ( "fwft"                                                        )
    ) u_net_tx_used_idx_irq_merge_in_ff (
        .clk             (clk                                           ),
        .rst             (rst                                           ),
        .wren            (net_tx_used_idx_irq_merge_in_ff_wren          ),
        .din             (net_tx_used_idx_irq_merge_in_ff_din           ),
        .full            (                                              ),
        .pfull           (net_tx_used_idx_irq_merge_in_ff_pfull         ),
        .overflow        (net_tx_used_idx_irq_merge_in_ff_overflow      ),
        .rden            (net_tx_used_idx_irq_merge_in_ff_rden          ),
        .dout            (net_tx_used_idx_irq_merge_in_ff_dout          ),
        .empty           (net_tx_used_idx_irq_merge_in_ff_empty         ),
        .pempty          (                                              ),
        .underflow       (net_tx_used_idx_irq_merge_in_ff_underflow     ),
        .usedw           (                                              ),
        .parity_ecc_err  (net_tx_used_idx_irq_merge_in_ff_parity_ecc_err)
    );

    assign net_tx_used_idx_irq_merge_in_ff_wren = (irq_cstat == WR_USED_INFO_NET_USED_IDX_IRQ_MERGE) && (wr_used_info_dat.vq.typ == VIRTIO_NET_TX_TYPE);
    assign net_tx_used_idx_irq_merge_in_ff_din  = wr_used_info_dat.vq.qid;
    
    assign irq_merge_core_tx_irq_in_qid         = net_tx_used_idx_irq_merge_in_ff_dout;
    assign irq_merge_core_tx_irq_in_vld         = ~net_tx_used_idx_irq_merge_in_ff_empty;
    assign net_tx_used_idx_irq_merge_in_ff_rden = irq_merge_core_tx_irq_in_vld && irq_merge_core_tx_irq_in_rdy;

    //========================net_rx_used_idx_irq_merge_in_ff=============================//
    yucca_sync_fifo #(
        .DATA_WIDTH ( Q_WIDTH                             ),
        .FIFO_DEPTH ( 32                                                            ),
        .CHECK_ON   ( 1                                                             ),
        .CHECK_MODE ( "parity"                                                      ),
        .DEPTH_PFULL( 24                                                            ),
        .RAM_MODE   ( "dist"                                                        ),
        .FIFO_MODE  ( "fwft"                                                        )
    ) u_net_rx_used_idx_irq_merge_in_ff (
        .clk             (clk                                           ),
        .rst             (rst                                           ),
        .wren            (net_rx_used_idx_irq_merge_in_ff_wren          ),
        .din             (net_rx_used_idx_irq_merge_in_ff_din           ),
        .full            (                                              ),
        .pfull           (net_rx_used_idx_irq_merge_in_ff_pfull         ),
        .overflow        (net_rx_used_idx_irq_merge_in_ff_overflow      ),
        .rden            (net_rx_used_idx_irq_merge_in_ff_rden          ),
        .dout            (net_rx_used_idx_irq_merge_in_ff_dout          ),
        .empty           (net_rx_used_idx_irq_merge_in_ff_empty         ),
        .pempty          (                                              ),
        .underflow       (net_rx_used_idx_irq_merge_in_ff_underflow     ),
        .usedw           (                                              ),
        .parity_ecc_err  (net_rx_used_idx_irq_merge_in_ff_parity_ecc_err)
    );

    assign net_rx_used_idx_irq_merge_in_ff_wren = (irq_cstat == WR_USED_INFO_NET_USED_IDX_IRQ_MERGE) && (wr_used_info_dat.vq.typ == VIRTIO_NET_RX_TYPE);
    assign net_rx_used_idx_irq_merge_in_ff_din  = wr_used_info_dat.vq.qid;
    
    assign irq_merge_core_rx_irq_in_qid         = net_rx_used_idx_irq_merge_in_ff_dout;
    assign irq_merge_core_rx_irq_in_vld         = ~net_rx_used_idx_irq_merge_in_ff_empty;
    assign net_rx_used_idx_irq_merge_in_ff_rden = irq_merge_core_rx_irq_in_vld && irq_merge_core_rx_irq_in_rdy;
    
    //=======================used_irq_ff======================================//
    yucca_sync_fifo #( 
        .DATA_WIDTH ( $bits(used_irq_ff_entry_t)                                    ),
        .FIFO_DEPTH ( 32                                                            ),
        .CHECK_ON   ( 1                                                             ),
        .CHECK_MODE ( "parity"                                                      ),
        .DEPTH_PFULL( 24                                                            ),
        .RAM_MODE   ( "dist"                                                        ),
        .FIFO_MODE  ( "fwft"                                                        )
    ) u_used_irq_ff (
        .clk             (clk                          ),
        .rst             (rst                          ),
        .wren            (used_irq_ff_wren             ),
        .din             (used_irq_ff_din              ),
        .full            (                             ),
        .pfull           (used_irq_ff_pfull            ),
        .overflow        (used_irq_ff_overflow         ),
        .rden            (used_irq_ff_rden             ),
        .dout            (used_irq_ff_dout             ),
        .empty           (used_irq_ff_empty            ),
        .pempty          (                             ),
        .underflow       (used_irq_ff_underflow        ),
        .usedw           (                             ),
        .parity_ecc_err  (used_irq_ff_parity_ecc_err   )
    );

    assign used_irq_ff_wren = (irq_cstat == WR_USED_INFO_NET_USED_IDX_IRQ_MERGE) || (irq_cstat == WR_USED_INFO_BLK_FF) || (irq_cstat == WR_USED_IDX_IRQ);
    
    always @(*) begin
        if(is_used_info) begin
            used_irq_ff_din.used_info      = wr_used_info_dat;
            used_irq_ff_din.typ            = USED_INFO;
        end else if(is_net_tx_used_idx_irq || is_net_rx_used_idx_irq) begin
            used_irq_ff_din.used_info      = {net_used_idx_irq_qid,{EMPTY_WIDTH{1'b0}}};
            used_irq_ff_din.typ            = USED_IDX_IRQ;
        end else begin//is_blk_used_idx_irq
            used_irq_ff_din.used_info      = {blk_used_idx_irq_qid,{EMPTY_WIDTH{1'b0}}};
            used_irq_ff_din.typ            = USED_IDX_IRQ;
        end
    end

    assign used_info_irq_vld = ~used_irq_ff_empty;
    assign used_irq_ff_rden  = used_info_irq_vld && used_info_irq_rdy;

    assign used_info_irq_dat.typ = used_irq_ff_dout.typ;
    assign used_info_irq_dat.used_info = used_irq_ff_dout.used_info;

    //==================irq_merge_core_tx and irq_merge_core_rx rr_sch=================//
    rr_sch#(
        .SH_NUM(2)         
    )u_merge_core_rr_sch(
        .clk           (clk),
        .rst           (rst),
        .sch_req       (net_used_idx_irq_sch_req      ),
        .sch_en        (net_used_idx_irq_sch_en       ), 
        .sch_grant     (net_used_idx_irq_sch_grant    ), 
        .sch_grant_vld (net_used_idx_irq_sch_grant_vld)   
    );

    assign net_used_idx_irq_sch_en = ~net_used_idx_irq_ff_pfull;
    assign net_used_idx_irq_sch_req = {irq_merge_core_tx_irq_out_vld, irq_merge_core_rx_irq_out_vld};

    assign net_used_idx_irq.qid = net_used_idx_irq_sch_grant[0] ? irq_merge_core_rx_irq_out_qid : irq_merge_core_tx_irq_out_qid;
    assign net_used_idx_irq.typ = net_used_idx_irq_sch_grant[0] ? NET_RX_USED_IDX_IRQ : NET_TX_USED_IDX_IRQ;

    //========================net_used_idx_irq_ff=============================//
    yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(net_used_idx_irq_ff_entry_t)                             ),
        .FIFO_DEPTH ( 32                                                            ),
        .CHECK_ON   ( 1                                                             ),
        .CHECK_MODE ( "parity"                                                      ),
        .DEPTH_PFULL( 24                                                            ),
        .RAM_MODE   ( "dist"                                                        ),
        .FIFO_MODE  ( "fwft"                                                        )
    ) u_net_used_idx_irq_ff (
        .clk             (clk                                  ),
        .rst             (rst                                  ),
        .wren            (net_used_idx_irq_ff_wren             ),
        .din             (net_used_idx_irq_ff_din              ),
        .full            (                                     ),
        .pfull           (net_used_idx_irq_ff_pfull            ),
        .overflow        (net_used_idx_irq_ff_overflow         ),
        .rden            (net_used_idx_irq_ff_rden             ),
        .dout            (net_used_idx_irq_ff_dout             ),
        .empty           (net_used_idx_irq_ff_empty            ),
        .pempty          (                                     ),
        .underflow       (net_used_idx_irq_ff_underflow        ),
        .usedw           (                                     ),
        .parity_ecc_err  (net_used_idx_irq_ff_parity_ecc_err   )
    );

    assign net_used_idx_irq_ff_wren = net_used_idx_irq_sch_grant_vld;
    assign net_used_idx_irq_ff_din.qid  = net_used_idx_irq.qid;
    assign net_used_idx_irq_ff_din.typ  = net_used_idx_irq.typ;  //1'b0:NET_TX_USED_IDX_IRQ 1'b1:NET_RX_USED_IDX_IRQ 
    assign net_used_idx_irq_ff_rden = (irq_cstat == WR_USED_IDX_IRQ) && (is_net_tx_used_idx_irq || is_net_rx_used_idx_irq);
    assign net_used_idx_irq_qid  = net_used_idx_irq_ff_dout.qid;

    //===============irq_merge_core_tx==========================//
    assign irq_merge_core_tx_irq_out_qid = {VIRTIO_NET_TX_TYPE, irq_out_qid_tx};
    assign irq_merge_core_rx_irq_out_qid = {VIRTIO_NET_RX_TYPE, irq_out_qid_rx};

    assign msix_aggregation_time_rd_req_qid_net_tx = msix_aggregation_time_rd_req_idx_net_tx;
    assign msix_aggregation_threshold_rd_req_qid_net_tx = msix_aggregation_threshold_rd_req_idx_net_tx;
    assign msix_aggregation_info_rd_req_qid_net_tx = msix_aggregation_info_rd_req_idx_net_tx;
    assign msix_aggregation_info_wr_qid_net_tx = msix_aggregation_info_wr_idx_net_tx;

    assign msix_aggregation_time_rd_req_qid_net_rx = msix_aggregation_time_rd_req_idx_net_rx;
    assign msix_aggregation_threshold_rd_req_qid_net_rx = msix_aggregation_threshold_rd_req_idx_net_rx;
    assign msix_aggregation_info_rd_req_qid_net_rx = msix_aggregation_info_rd_req_idx_net_rx;
    assign msix_aggregation_info_wr_qid_net_rx = msix_aggregation_info_wr_idx_net_rx;

    assign irq_merge_core_tx_irq_out_rdy = net_used_idx_irq_sch_grant[1] && net_used_idx_irq_sch_grant_vld;
    assign irq_merge_core_rx_irq_out_rdy = net_used_idx_irq_sch_grant[0] && net_used_idx_irq_sch_grant_vld;


    virtio_irq_merge_core_top #(
        .IRQ_MERGE_UINT_NUM(IRQ_MERGE_UINT_NUM),
        .IRQ_MERGE_UINT_NUM_WIDTH(IRQ_MERGE_UINT_NUM_WIDTH),
        .QID_NUM(Q_NUM),
        .QID_WIDTH(Q_WIDTH),
        .TIME_MAP_WIDTH(TIME_MAP_WIDTH),
        .CLK_FREQ_M(CLOCK_FREQ_MHZ),
        .TIME_STAMP_UNIT_NS(TIME_STAMP_UNIT_NS)
    ) u_irq_merge_core_tx(
        .clk                                    (clk),
        .rst                                    (rst),
        .irq_in_qid                             (irq_merge_core_tx_irq_in_qid),
        .irq_in_vld                             (irq_merge_core_tx_irq_in_vld),
        .irq_in_rdy                             (irq_merge_core_tx_irq_in_rdy),
        .irq_out_qid                            (irq_out_qid_tx),
        .irq_out_vld                            (irq_merge_core_tx_irq_out_vld),
        .irq_out_rdy                            (irq_merge_core_tx_irq_out_rdy),
        .msix_aggregation_time_rd_req_vld       (msix_aggregation_time_rd_req_vld_net_tx),
        .msix_aggregation_time_rd_req_idx       (msix_aggregation_time_rd_req_idx_net_tx),
        .msix_aggregation_time_rd_rsp_vld       (msix_aggregation_time_rd_rsp_vld_net_tx),
        .msix_aggregation_time_rd_rsp_dat       (msix_aggregation_time_rd_rsp_dat_net_tx),
        .msix_aggregation_threshold_rd_req_vld  (msix_aggregation_threshold_rd_req_vld_net_tx),
        .msix_aggregation_threshold_rd_req_idx  (msix_aggregation_threshold_rd_req_idx_net_tx),
        .msix_aggregation_threshold_rd_rsp_vld  (msix_aggregation_threshold_rd_rsp_vld_net_tx),
        .msix_aggregation_threshold_rd_rsp_dat  (msix_aggregation_threshold_rd_rsp_dat_net_tx),
        .msix_aggregation_info_rd_req_vld       (msix_aggregation_info_rd_req_vld_net_tx),
        .msix_aggregation_info_rd_req_idx       (msix_aggregation_info_rd_req_idx_net_tx),
        .msix_aggregation_info_rd_rsp_vld       (msix_aggregation_info_rd_rsp_vld_net_tx),
        .msix_aggregation_info_rd_rsp_dat       (msix_aggregation_info_rd_rsp_dat_net_tx),
        .msix_aggregation_info_wr_vld           (msix_aggregation_info_wr_vld_net_tx),
        .msix_aggregation_info_wr_idx           (msix_aggregation_info_wr_idx_net_tx),
        .msix_aggregation_info_wr_dat           (msix_aggregation_info_wr_dat_net_tx),
        .dfx_irq_merge_core_err                 (dfx_irq_merge_core_net_tx_err)
    );

    //===============irq_merge_core_rx==========================//
    virtio_irq_merge_core_top #(
        .IRQ_MERGE_UINT_NUM(IRQ_MERGE_UINT_NUM),
        .IRQ_MERGE_UINT_NUM_WIDTH(IRQ_MERGE_UINT_NUM_WIDTH),
        .QID_NUM(Q_NUM),
        .QID_WIDTH(Q_WIDTH),
        .TIME_MAP_WIDTH(TIME_MAP_WIDTH),
        .CLK_FREQ_M(CLOCK_FREQ_MHZ),
        .TIME_STAMP_UNIT_NS(TIME_STAMP_UNIT_NS)
    ) u_irq_merge_core_rx(
        .clk                                    (clk),
        .rst                                    (rst),
        .irq_in_qid                             (irq_merge_core_rx_irq_in_qid),
        .irq_in_vld                             (irq_merge_core_rx_irq_in_vld),
        .irq_in_rdy                             (irq_merge_core_rx_irq_in_rdy),
        .irq_out_qid                            (irq_out_qid_rx),
        .irq_out_vld                            (irq_merge_core_rx_irq_out_vld),
        .irq_out_rdy                            (irq_merge_core_rx_irq_out_rdy),   
        .msix_aggregation_time_rd_req_vld       (msix_aggregation_time_rd_req_vld_net_rx),
        .msix_aggregation_time_rd_req_idx       (msix_aggregation_time_rd_req_idx_net_rx),
        .msix_aggregation_time_rd_rsp_vld       (msix_aggregation_time_rd_rsp_vld_net_rx),
        .msix_aggregation_time_rd_rsp_dat       (msix_aggregation_time_rd_rsp_dat_net_rx),
        .msix_aggregation_threshold_rd_req_vld  (msix_aggregation_threshold_rd_req_vld_net_rx),
        .msix_aggregation_threshold_rd_req_idx  (msix_aggregation_threshold_rd_req_idx_net_rx),
        .msix_aggregation_threshold_rd_rsp_vld  (msix_aggregation_threshold_rd_rsp_vld_net_rx),
        .msix_aggregation_threshold_rd_rsp_dat  (msix_aggregation_threshold_rd_rsp_dat_net_rx),
        .msix_aggregation_info_rd_req_vld       (msix_aggregation_info_rd_req_vld_net_rx),
        .msix_aggregation_info_rd_req_idx       (msix_aggregation_info_rd_req_idx_net_rx),
        .msix_aggregation_info_rd_rsp_vld       (msix_aggregation_info_rd_rsp_vld_net_rx),
        .msix_aggregation_info_rd_rsp_dat       (msix_aggregation_info_rd_rsp_dat_net_rx),
        .msix_aggregation_info_wr_vld           (msix_aggregation_info_wr_vld_net_rx),
        .msix_aggregation_info_wr_idx           (msix_aggregation_info_wr_idx_net_rx),
        .msix_aggregation_info_wr_dat           (msix_aggregation_info_wr_dat_net_rx),
        .dfx_irq_merge_core_err                 (dfx_irq_merge_core_net_rx_err)
    );
    
//==============dfx=========================//
    always @(posedge clk) begin
        if(rst) begin
            dfx_err <= {$bits(dfx_err){1'b0}};
        end else begin
            dfx_err = {
                net_used_idx_irq_ff_overflow,         //19
                net_used_idx_irq_ff_underflow,        //18
                net_used_idx_irq_ff_parity_ecc_err,   //17-16
                used_irq_ff_overflow,                 //15
                used_irq_ff_underflow,                //14
                used_irq_ff_parity_ecc_err,           //13-12
                net_rx_used_idx_irq_merge_in_ff_overflow,         //11
                net_rx_used_idx_irq_merge_in_ff_underflow,        //10
                net_rx_used_idx_irq_merge_in_ff_parity_ecc_err,   //9-8
                net_tx_used_idx_irq_merge_in_ff_overflow,         //7
                net_tx_used_idx_irq_merge_in_ff_underflow,        //6
                net_tx_used_idx_irq_merge_in_ff_parity_ecc_err,   //5-4
                blk_used_idx_irq_ff_overflow,         //3
                blk_used_idx_irq_ff_underflow,        //2
                blk_used_idx_irq_ff_parity_ecc_err    //1-0
            };  
        end
    end

    genvar idx;
    generate
        for(idx=0;idx<$bits(dfx_err);idx++)begin :used_idx_irq_merge_err_i
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err[idx]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, dfx_err[idx], idx));
        end
    endgenerate

    assign dfx_status = {
        net_used_idx_irq_ff_pfull,   //14
        net_used_idx_irq_ff_empty,   //13
        used_irq_ff_pfull,           //12
        used_irq_ff_empty,           //11
        net_rx_used_idx_irq_merge_in_ff_pfull,   //10
        net_rx_used_idx_irq_merge_in_ff_empty,   //9
        net_tx_used_idx_irq_merge_in_ff_pfull,   //8
        net_tx_used_idx_irq_merge_in_ff_empty,   //7
        blk_used_idx_irq_ff_pfull,               //6
        blk_used_idx_irq_ff_empty,               //5
        irq_cstat                                //4-0
    };

    




 endmodule


