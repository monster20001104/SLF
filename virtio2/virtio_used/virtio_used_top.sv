/******************************************************************************
 * 文件名称 : virtio_used.sv
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
 module virtio_used_top #(
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
    input                                                    clk,
    input                                                    rst,
    //==============wr_used_info from or to blk_upstream/nettx/netrx======================//
    input  logic                                             wr_used_info_vld,
    input  virtio_used_info_t                                wr_used_info_dat,
    output logic                                             wr_used_info_rdy,
    //=============dma_data_wr_if======================================//
    tlp_adap_dma_wr_req_if.src                               dma_data_wr_req_if,
    tlp_adap_dma_wr_rsp_if.snk                               dma_data_wr_rsp_if,
    //===============from or to err_handle==============================//
    output logic                                             err_handle_vld,
    output virtio_vq_t                                       err_handle_qid,
    output virtio_err_info_t                                 err_handle_dat,
    input  logic                                             err_handle_rdy,
    //===================from or to ctx=================================//
    input  logic                                             set_mask_req_vld,
    input  virtio_vq_t                                       set_mask_req_qid,
    input  logic                                             set_mask_req_dat,
    output logic                                             set_mask_req_rdy,
    //======================ctx_req/rsp===========================//
    output logic                                             used_ring_irq_req_vld,
    output virtio_vq_t                                       used_ring_irq_req_qid,
    input  logic                                             used_ring_irq_rsp_vld,
    input  logic                                             used_ring_irq_rsp_forced_shutdown,
    input  logic [63:0]                                      used_ring_irq_rsp_msix_addr,
    input  logic [31:0]                                      used_ring_irq_rsp_msix_data,
    input  logic [15:0]                                      used_ring_irq_rsp_bdf,
    input  logic [9:0]                                       used_ring_irq_rsp_dev_id,
    input  logic                                             used_ring_irq_rsp_msix_mask,
    input  logic                                             used_ring_irq_rsp_msix_pending,
    input  logic [63:0]                                      used_ring_irq_rsp_used_ring_addr,
    input  logic [3:0]                                       used_ring_irq_rsp_qdepth,
    input  logic                                             used_ring_irq_rsp_msix_enable,
    input  logic [$bits(virtio_qstat_t)-1:0]                 used_ring_irq_rsp_q_status,
    input  logic                                             used_ring_irq_rsp_err_fatal,
    //===========================ctx err fatal wr====================================//
    output logic                                             err_fatal_wr_vld,
    output virtio_vq_t                                       err_fatal_wr_qid,
    output logic                                             err_fatal_wr_dat,
    //=========================ctx used_elem_ptr rd/wr==================================//
    output logic                                             used_elem_ptr_rd_req_vld,
    output virtio_vq_t                                       used_elem_ptr_rd_req_qid,
    input  logic                                             used_elem_ptr_rd_rsp_vld,
    input  virtio_used_elem_ptr_info_t                       used_elem_ptr_rd_rsp_dat,
        
    output logic                                             used_elem_ptr_wr_vld,
    output virtio_vq_t                                       used_elem_ptr_wr_qid,
    output virtio_used_elem_ptr_info_t                       used_elem_ptr_wr_dat,

    //==========================update ctx used_idx=====================//
    output logic                                             used_idx_wr_vld,
    output virtio_vq_t                                       used_idx_wr_qid,
    output logic [15:0]                                      used_idx_wr_dat,
            
    output logic                                             msix_tbl_wr_vld,
    output virtio_vq_t                                       msix_tbl_wr_qid,
    output logic                                             msix_tbl_wr_mask,
    output logic                                             msix_tbl_wr_pending,

    //===========================when dma write used_idx and irq, update flag in ctx===================================//
    output logic                                             dma_write_used_idx_irq_flag_wr_vld,
    output virtio_vq_t                                       dma_write_used_idx_irq_flag_wr_qid,
    output logic                                             dma_write_used_idx_irq_flag_wr_dat,

    //============================ctx cal send irq num===================================//
    output virtio_vq_t                                       mon_send_irq_vq,
    output logic                                             mon_send_a_irq,     

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
    input  virtio_vq_t                                       blk_ds_err_info_wr_qid,
    input  virtio_err_info_t                                 blk_ds_err_info_wr_dat,                                      

    mlite_if.slave                                           dfx_if
);

    typedef enum logic [1:0] { 
        USED_INFO    = 2'b00,
        USED_IDX     = 2'b01,
        IRQ          = 2'b10
    } virtio_used_irq_wr_type_t;

    typedef struct packed {
        virtio_vq_t                  qid;
        logic                        dummy;
        logic                        fatal;
        logic                        update_ctx_used_ptr;
        virtio_used_irq_wr_type_t    wr_type;
        logic [15:0]                 used_idx;  
    } virtio_used_irq_order_info_t;

    typedef struct packed {
        virtio_vq_t                  qid;
        virtio_used_irq_wr_type_t    wr_type;
        logic [15:0]                 used_idx;  
    } virtio_wr_rsp_info_t;

    

    logic used_info_irq_rdy;
    used_irq_ff_entry_t used_info_irq_dat;
    logic [$bits(virtio_used_irq_ff_wr_type_t)-1:0] used_info_irq_typ;
    logic [7:0] dfx_used_irq_merge_err;
    logic [9:0] dfx_used_irq_merge_status;
    logic [7:0] dfx_irq_merge_core_err;
    logic forced_shutdown;
    logic [9:0] dev_id; 
    logic [15:0] bdf;
    logic [63:0] msix_addr, used_ring_addr;
    logic [31:0] msix_data;
    logic [3:0] qdepth;
    logic mask, pending;
    logic [2:0] used_req_sch_req;
    logic used_req_sch_en, used_req_sch_grant_vld;
    logic [2:0] used_req_sch_grant;
    logic is_used_info_irq, is_sel_used_info_irq, is_set_mask, is_sel_set_mask, is_blk_ds_err_info, is_sel_blk_ds_err_info;
    logic err_fatal, send_irq, set_unmask_send_irq, wr_used_elem, wr_used_idx, set_pending, set_unmask, set_mask, set_dfx_err;
    logic wr_order_condition;
    logic order_ff_empty, order_ff_wren, order_ff_pfull, order_ff_rden;
    virtio_used_irq_order_info_t order_ff_din_wire, order_ff_din, order_ff_dout, order_ff_dout_reg;
    logic order_ff_overflow, order_ff_underflow;
    logic [1:0] order_ff_parity_ecc_err;
    logic [3:0] order_used_idx, rsp_used_idx;
    logic wr_rsp_ff_empty, wr_rsp_ff_wren, wr_rsp_ff_pfull, wr_rsp_ff_rden;
    virtio_wr_rsp_info_t wr_rsp_ff_din, wr_rsp_ff_dout;
    logic wr_rsp_ff_overflow, wr_rsp_ff_underflow;
    logic [1:0] wr_rsp_ff_parity_ecc_err;
    logic [$bits(virtio_qstat_t)-1:0] q_status;
    logic msix_enable, used_info_irq_vld;
    logic [11:0] dfx_err, dfx_err_q;
    logic [25:0] dfx_status;
    logic [7:0] wr_used_info_cnt, dma_data_wr_req_cnt, dma_data_wr_rsp_cnt, dfx_err_cnt;
    logic [19:0] dfx_used_idx_irq_merge_err, dfx_used_idx_irq_merge_err_q;
    logic [14:0] dfx_used_idx_irq_merge_status;
    logic [3:0] dfx_irq_merge_core_net_tx_err, dfx_irq_merge_core_net_tx_err_q, dfx_irq_merge_core_net_rx_err, dfx_irq_merge_core_net_rx_err_q;
    logic q_status_en, first_err_flag, fatal_err_flag;
    logic [15:0] used_idx_plus_one, used_idx_reduce_one;
    logic dma_wr_req_en;
    logic [31:0] dma_wr_req_cnt, rsp_ff_rd_cnt;
    logic no_err_used_elem_used_idx_irq_wen, no_err_irq_wen, err_used_elem_wen, err_used_idx_wen, err_irq_wen, update_ctx_used_ptr;                  
    logic handshake_to_sch_rdy; 
    logic sch_to_handshake_vld; 
    virtio_used_handshake_reg_info_t sch_to_handshake_dat, handshake_to_used_dat, used_processing_dat; 
    logic used_to_handshake_rdy;
    logic handshake_to_used_vld;
    logic used_process_used_info_irq_rdy, used_process_set_mask_req_rdy, used_process_blk_ds_err_info_wr_rdy;

    enum logic [12:0] {
        IDLE                     = 13'b0000000000001,
        NOP_WAIT                 = 13'b0000000000010,   //for timing
        PROCESS                  = 13'b0000000000100,
        SET_PENDING              = 13'b0000000001000,
        SET_MASK_UNMASK          = 13'b0000000010000,
        DFX_ERR                  = 13'b0000000100000,
        ERR_HANDLE               = 13'b0000001000000,
        RD_USED_ELEM_PTR         = 13'b0000010000000,
        WR_ERR_FATAL_USED_IDX    = 13'b0000100000000,
        WR_ERR_FATAL_IRQ         = 13'b0001000000000,
        WR_USED_ELEM_IDX         = 13'b0010000000000,
        WR_IRQ                   = 13'b0100000000000,
        EXIT                     = 13'b1000000000000
    } cstat, nstat;

    enum logic [2:0] {
        USED_IDX_IDLE        = 3'b001,
        RD_RSP               = 3'b010,
        WR_CTX_USED_IDX      = 3'b100
    } used_idx_cstat, used_idx_nstat;

    enum logic [1:0] {
        USED_SCH = 2'b01,
        USED_EXE = 2'b10
    } used_sch_cstat, used_sch_nstat;


//===================virtio_used_irq_merge_inst==============//

    virtio_used_idx_irq_merge #(
        .IRQ_MERGE_UINT_NUM(IRQ_MERGE_UINT_NUM),
        .IRQ_MERGE_UINT_NUM_WIDTH(IRQ_MERGE_UINT_NUM_WIDTH),
        .Q_NUM(Q_NUM),
        .Q_WIDTH(Q_WIDTH),
        .TIME_MAP_WIDTH(TIME_MAP_WIDTH),
        .CLOCK_FREQ_MHZ(CLOCK_FREQ_MHZ),
        .TIME_STAMP_UNIT_NS(TIME_STAMP_UNIT_NS)
    )u_virtio_used_idx_irq_merge(
        .clk                                            (clk                      ),
        .rst                                            (rst                      ),
        .wr_used_info_vld                               (wr_used_info_vld         ),
        .wr_used_info_dat                               (wr_used_info_dat         ),
        .wr_used_info_rdy                               (wr_used_info_rdy         ),
        .used_info_irq_vld                              (used_info_irq_vld        ),
        .used_info_irq_dat                              (used_info_irq_dat        ),
        .used_info_irq_rdy                              (used_info_irq_rdy        ),
        .msix_aggregation_time_rd_req_vld_net_tx        (msix_aggregation_time_rd_req_vld_net_tx),
        .msix_aggregation_time_rd_req_qid_net_tx        (msix_aggregation_time_rd_req_qid_net_tx),
        .msix_aggregation_time_rd_rsp_vld_net_tx        (msix_aggregation_time_rd_rsp_vld_net_tx),
        .msix_aggregation_time_rd_rsp_dat_net_tx        (msix_aggregation_time_rd_rsp_dat_net_tx),       
        .msix_aggregation_threshold_rd_req_vld_net_tx   (msix_aggregation_threshold_rd_req_vld_net_tx),
        .msix_aggregation_threshold_rd_req_qid_net_tx   (msix_aggregation_threshold_rd_req_qid_net_tx),
        .msix_aggregation_threshold_rd_rsp_vld_net_tx   (msix_aggregation_threshold_rd_rsp_vld_net_tx),
        .msix_aggregation_threshold_rd_rsp_dat_net_tx   (msix_aggregation_threshold_rd_rsp_dat_net_tx),
        .msix_aggregation_info_rd_req_vld_net_tx        (msix_aggregation_info_rd_req_vld_net_tx),
        .msix_aggregation_info_rd_req_qid_net_tx        (msix_aggregation_info_rd_req_qid_net_tx),
        .msix_aggregation_info_rd_rsp_vld_net_tx        (msix_aggregation_info_rd_rsp_vld_net_tx),
        .msix_aggregation_info_rd_rsp_dat_net_tx        (msix_aggregation_info_rd_rsp_dat_net_tx),
        .msix_aggregation_info_wr_vld_net_tx            (msix_aggregation_info_wr_vld_net_tx),
        .msix_aggregation_info_wr_qid_net_tx            (msix_aggregation_info_wr_qid_net_tx),
        .msix_aggregation_info_wr_dat_net_tx            (msix_aggregation_info_wr_dat_net_tx),
        .msix_aggregation_time_rd_req_vld_net_rx        (msix_aggregation_time_rd_req_vld_net_rx),
        .msix_aggregation_time_rd_req_qid_net_rx        (msix_aggregation_time_rd_req_qid_net_rx),
        .msix_aggregation_time_rd_rsp_vld_net_rx        (msix_aggregation_time_rd_rsp_vld_net_rx),
        .msix_aggregation_time_rd_rsp_dat_net_rx        (msix_aggregation_time_rd_rsp_dat_net_rx),       
        .msix_aggregation_threshold_rd_req_vld_net_rx   (msix_aggregation_threshold_rd_req_vld_net_rx),
        .msix_aggregation_threshold_rd_req_qid_net_rx   (msix_aggregation_threshold_rd_req_qid_net_rx),
        .msix_aggregation_threshold_rd_rsp_vld_net_rx   (msix_aggregation_threshold_rd_rsp_vld_net_rx),
        .msix_aggregation_threshold_rd_rsp_dat_net_rx   (msix_aggregation_threshold_rd_rsp_dat_net_rx),
        .msix_aggregation_info_rd_req_vld_net_rx        (msix_aggregation_info_rd_req_vld_net_rx),
        .msix_aggregation_info_rd_req_qid_net_rx        (msix_aggregation_info_rd_req_qid_net_rx),
        .msix_aggregation_info_rd_rsp_vld_net_rx        (msix_aggregation_info_rd_rsp_vld_net_rx),
        .msix_aggregation_info_rd_rsp_dat_net_rx        (msix_aggregation_info_rd_rsp_dat_net_rx),
        .msix_aggregation_info_wr_vld_net_rx            (msix_aggregation_info_wr_vld_net_rx),
        .msix_aggregation_info_wr_qid_net_rx            (msix_aggregation_info_wr_qid_net_rx),
        .msix_aggregation_info_wr_dat_net_rx            (msix_aggregation_info_wr_dat_net_rx),
        .dfx_err                                        (dfx_used_idx_irq_merge_err),
        .dfx_status                                     (dfx_used_idx_irq_merge_status),
        .dfx_irq_merge_core_net_tx_err                  (dfx_irq_merge_core_net_tx_err),
        .dfx_irq_merge_core_net_rx_err                  (dfx_irq_merge_core_net_rx_err)
    );

//====================read ctx========================//
    assign used_ring_irq_req_vld = (cstat == IDLE) && handshake_to_used_vld && dma_data_wr_req_if.sav && dma_wr_req_en;
    assign used_ring_irq_req_qid = handshake_to_used_dat.vq;

    always @(posedge clk) begin
        if(used_ring_irq_rsp_vld) begin
            forced_shutdown <= used_ring_irq_rsp_forced_shutdown;
            dev_id          <= used_ring_irq_rsp_dev_id;
            bdf             <= used_ring_irq_rsp_bdf;
            msix_addr       <= used_ring_irq_rsp_msix_addr;
            msix_data       <= used_ring_irq_rsp_msix_data;
            used_ring_addr  <= used_ring_irq_rsp_used_ring_addr;
            qdepth          <= used_ring_irq_rsp_qdepth;
            mask            <= used_ring_irq_rsp_msix_mask;
            pending         <= used_ring_irq_rsp_msix_pending;
            msix_enable     <= used_ring_irq_rsp_msix_enable;
            q_status        <= used_ring_irq_rsp_q_status;
            fatal_err_flag  <= used_ring_irq_rsp_err_fatal;
        end
    end

//===============rr_sch=======================//
    
    assign used_req_sch_req = {blk_ds_err_info_wr_vld, used_info_irq_vld, set_mask_req_vld};
    assign used_req_sch_en  = USED_SCH;

    //============SCH FSM============//
    always @(posedge clk) begin
        if(rst) begin
            used_sch_cstat <= USED_SCH;
        end else begin
            used_sch_cstat <= used_sch_nstat;
        end
    end

    always @(*) begin
        used_sch_nstat = used_sch_cstat;
        case(used_sch_cstat)
            USED_SCH: begin
                if(used_req_sch_grant_vld) begin
                    used_sch_nstat = USED_EXE;
                end
            end
            USED_EXE: begin
                if(handshake_to_sch_rdy) begin
                    used_sch_nstat = USED_SCH;
                end
            end
            default: used_sch_nstat = USED_SCH;
        endcase
    end

    rr_sch#(
        .SH_NUM(3)         
    )u_irq_rr_sch(
        .clk           (clk),
        .rst           (rst),
        .sch_req       (used_req_sch_req      ),
        .sch_en        (used_req_sch_en       ), 
        .sch_grant     (used_req_sch_grant    ), 
        .sch_grant_vld (used_req_sch_grant_vld)   
    );

    always @(posedge clk) begin
        if((used_sch_cstat == USED_SCH) && used_req_sch_grant_vld) begin
            {is_sel_blk_ds_err_info, is_sel_used_info_irq, is_sel_set_mask} <= used_req_sch_grant;
        end
    end

    assign sch_to_handshake_vld     = (used_sch_cstat == USED_EXE);
    assign sch_to_handshake_dat.vq  = is_sel_blk_ds_err_info ? blk_ds_err_info_wr_qid : is_sel_used_info_irq ? used_info_irq_dat.used_info.vq : set_mask_req_qid;
    assign sch_to_handshake_dat.typ = is_sel_blk_ds_err_info ? IS_BLK_DS_ERR_INFO : is_sel_used_info_irq ? IS_USED_INFO_IRQ : IS_SET_MASK;
    assign sch_to_handshake_dat.used_dat.used_info = is_sel_blk_ds_err_info ? blk_ds_err_info_wr_dat : is_sel_used_info_irq ? used_info_irq_dat.used_info : set_mask_req_dat;
    assign sch_to_handshake_dat.used_dat.typ = used_info_irq_dat.typ;
    
    assign used_info_irq_rdy      = (used_sch_cstat == USED_EXE) && is_sel_used_info_irq && handshake_to_sch_rdy;
    assign set_mask_req_rdy       = (used_sch_cstat == USED_EXE) && is_sel_set_mask && handshake_to_sch_rdy;
    assign blk_ds_err_info_wr_rdy = (used_sch_cstat == USED_EXE) && is_sel_blk_ds_err_info && handshake_to_sch_rdy;

    handshake_reg #(
        .WIDTH ($bits(virtio_used_handshake_reg_info_t))
    )u_used_handshake_reg(
        .clk           (clk),  
        .rst           (rst),
        .s_ready       (handshake_to_sch_rdy ),
        .s_valid       (sch_to_handshake_vld ),
        .s_data        (sch_to_handshake_dat ),
        .m_ready       (used_to_handshake_rdy),
        .m_valid       (handshake_to_used_vld),
        .m_data        (handshake_to_used_dat)
    ); 

    always @(posedge clk) begin
        if(cstat == NOP_WAIT) begin
            used_processing_dat <= handshake_to_used_dat;
        end
    end

    always @(posedge clk) begin
        if(cstat == NOP_WAIT) begin
            is_blk_ds_err_info <= handshake_to_used_vld && (handshake_to_used_dat.typ == IS_BLK_DS_ERR_INFO);
            is_set_mask        <= handshake_to_used_vld && (handshake_to_used_dat.typ == IS_SET_MASK);
            is_used_info_irq   <= handshake_to_used_vld && (handshake_to_used_dat.typ == IS_USED_INFO_IRQ);
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            used_to_handshake_rdy <= 1'b0;
        end else begin
            used_to_handshake_rdy <= cstat == PROCESS;
        end
    end

    assign q_status_en = (q_status == VIRTIO_Q_STATUS_DOING) || (q_status == VIRTIO_Q_STATUS_STOPPING);

//======================FSM===========================//
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
                if(handshake_to_used_vld && dma_data_wr_req_if.sav && dma_wr_req_en) begin
                    nstat = NOP_WAIT;
                end
            end
            NOP_WAIT: begin
                nstat = PROCESS;
            end
            PROCESS: begin
                if(q_status_en) begin
                    if(is_used_info_irq) begin
                        if((used_processing_dat.used_dat.typ == USED_INFO) && (used_processing_dat.used_dat.used_info.err_info.err_code != VIRTIO_ERR_CODE_NONE) && ~fatal_err_flag) begin
                            nstat = ERR_HANDLE;
                        end else begin
                            nstat = WR_USED_ELEM_IDX;
                        end
                    end else if(is_set_mask) begin
                        if(msix_enable) begin
                            nstat = SET_MASK_UNMASK;
                        end else begin
                            nstat = EXIT;
                        end
                    end else begin  //is_blk_ds_err_info
                        if(~fatal_err_flag) begin
                            nstat = ERR_HANDLE;
                        end else begin
                            nstat = EXIT;
                        end
                    end
                end else begin
                    nstat = EXIT;
                end
            end
            EXIT, SET_PENDING, DFX_ERR, WR_IRQ, WR_ERR_FATAL_IRQ: begin
                nstat = IDLE;
            end
            WR_USED_ELEM_IDX: begin
                if(used_processing_dat.used_dat.typ == USED_IDX_IRQ) begin
                    if(msix_enable) begin
                        if(~mask && ~pending) begin
                            nstat = WR_IRQ;
                        end else if (mask && ~pending) begin
                            nstat = SET_PENDING;
                        end else if(~mask && pending) begin
                            nstat = DFX_ERR;
                        end else begin
                            nstat = IDLE;
                        end
                    end else begin
                        nstat = IDLE;
                    end
                end else begin   //wr_used_elem
                    nstat = IDLE;                
                end
            end
            SET_MASK_UNMASK: begin
                if(~used_processing_dat.used_dat.used_info[0] && mask && pending) begin
                    nstat = WR_IRQ;
                end else if(~mask && pending) begin
                    nstat = DFX_ERR;
                end else begin
                    nstat = IDLE;
                end
            end
            ERR_HANDLE: begin
                if(err_handle_rdy) begin
                    if(~is_blk_ds_err_info && used_processing_dat.used_dat.used_info.err_info.fatal) begin
                        nstat = RD_USED_ELEM_PTR;
                    end else begin
                        nstat = IDLE;
                    end
                end
            end
            RD_USED_ELEM_PTR: begin
                nstat = WR_ERR_FATAL_USED_IDX;
            end
            WR_ERR_FATAL_USED_IDX: begin
                if(msix_enable && ~mask && ~pending) begin
                    nstat = WR_ERR_FATAL_IRQ;
                end else begin
                    nstat = IDLE;
                end
            end
        endcase
    end

//=====================wr err fatal=============================//
    assign err_fatal_wr_vld = (cstat == ERR_HANDLE);
    assign err_fatal_wr_qid = used_processing_dat.vq;
    assign err_fatal_wr_dat = used_processing_dat.used_dat.used_info.err_info.fatal;

//====================rd/wr_used_elem_ptr======================//
    assign wr_used_elem = is_used_info_irq && (used_processing_dat.used_dat.typ == USED_INFO);
    assign wr_used_idx  = is_used_info_irq && (used_processing_dat.used_dat.typ == USED_IDX_IRQ);
    assign send_irq     = is_used_info_irq && (used_processing_dat.used_dat.typ == USED_IDX_IRQ) && ~mask && ~pending && msix_enable;
    //for timing
    always @(posedge clk) begin
        if((cstat == PROCESS) && wr_used_elem) begin
            used_idx_plus_one <= used_processing_dat.used_dat.used_info.used_idx + 1'b1;
        end
    end
    assign used_elem_ptr_wr_vld = (((cstat == WR_USED_ELEM_IDX) || ((cstat == ERR_HANDLE) && err_handle_rdy)) && wr_used_elem) || ((cstat == WR_USED_ELEM_IDX) && wr_used_idx && ~send_irq) || (cstat == WR_IRQ) || (cstat == WR_ERR_FATAL_USED_IDX);
    assign used_elem_ptr_wr_qid = used_processing_dat.vq;
    assign used_elem_ptr_wr_dat.wr_flag  = (((cstat == WR_USED_ELEM_IDX) || ((cstat == ERR_HANDLE) && err_handle_rdy)) && wr_used_elem) ? 1'b0 : 1'b1;
    assign used_elem_ptr_wr_dat.used_idx = (((cstat == WR_USED_ELEM_IDX) || ((cstat == ERR_HANDLE) && err_handle_rdy)) && wr_used_elem) ? used_idx_plus_one : used_elem_ptr_rd_rsp_dat.used_idx;

    assign used_elem_ptr_rd_req_qid = used_processing_dat.vq;
    //===========used_elem_ptr_rd_req_vld = 1 || 2 || 3 ===========================//
    //1 : dma wr used_idx and when (wr_used_idx && ~send_irq) == 1 update ctx used_ptr //
    //2 : when (wr_used_idx && send_irq) == 1 update ctx used_ptr                      //
    //3 : when err,dma wr used_idx and update ctx used_ptr                                                    //
    //=================================================================================//
    assign used_elem_ptr_rd_req_vld = ((cstat == PROCESS) && wr_used_idx) || ((cstat == WR_USED_ELEM_IDX) && wr_used_idx && send_irq) || (cstat == RD_USED_ELEM_PTR);   
    
//===============order_ff===============================//
     yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(virtio_used_irq_order_info_t)),
        .FIFO_DEPTH ( 32                          ),
        .CHECK_ON   ( 1                           ),
        .CHECK_MODE ( "parity"                    ),
        .DEPTH_PFULL( 24                          ),
        .RAM_MODE   ( "dist"                      ),
        .FIFO_MODE  ( "fwft"                      )
    ) u_order_ff (
        .clk             (clk                      ),
        .rst             (rst                      ),
        .wren            (order_ff_wren            ),
        .din             (order_ff_din             ),
        .full            (                         ),
        .pfull           (order_ff_pfull           ),
        .overflow        (order_ff_overflow        ),
        .rden            (order_ff_rden            ),
        .dout            (order_ff_dout            ),
        .empty           (order_ff_empty           ),
        .pempty          (                         ),
        .underflow       (order_ff_underflow       ),
        .usedw           (                         ),
        .parity_ecc_err  (order_ff_parity_ecc_err  )
    );

//=================================================================//
//when cstat == ERR_HANDLE and not blk_ds_err_info and used_info.err_info.fatal = 0 -> err dma wr_used_elem -> forced_shudown
//when cstat == WR_ERR_FATAL_IRQ -> err dma wr_used_idx -> forced_shudown
//when cstat == WR_ERR_FATAL_USED_IDX -> err, when forced_shutdown=1:only update ctx used_ptr; when forced_shutdown=0:wr_used_idx and update ctx used_ptr
//when cstat == WR_USED_ELEM_IDX -> normal wr_used_idx -> no err and forced_shutdown -> ~used_elem_ptr_rd_rsp_dat.wr_flag
//when cstat == WR_USED_ELEM_IDX -> normal dma wr_used_elem -> no err and forced_shutdown -> 1
//when cstat == WR_USED_ELEM_IDX -> have err or forced_shutdown -> wr_used_idx and ~send_irq -> 1 (update ctx used_idx)
//when cstat == WR_IRQ -> ~used_elem_ptr_rd_rsp_dat.wr_flag
//=====================generate order_ff_wren=====================//
    always @(*) begin
        if(((cstat == ERR_HANDLE) && err_handle_rdy && is_used_info_irq && ~used_processing_dat.used_dat.used_info.err_info.fatal) || (cstat == WR_ERR_FATAL_IRQ)) begin
            wr_order_condition = ~forced_shutdown;  //err_fatal wr_used_elem or wr_irq
        end else if(cstat == WR_ERR_FATAL_USED_IDX) begin
            wr_order_condition = 1'b1;  //err_fatal, when forced_shutdown=1:only update ctx used_ptr; when forced_shutdown=0:wr_used_idx and update ctx used_ptr
        end else if(cstat == WR_USED_ELEM_IDX) begin
            if(~fatal_err_flag && ~forced_shutdown) begin  //normal write
                if(wr_used_idx && used_elem_ptr_rd_rsp_dat.wr_flag)
                    wr_order_condition = 1'b0;  //when wr_flag is 1,not write
                else begin
                    wr_order_condition = 1'b1;
                end
            end else begin
                wr_order_condition = wr_used_idx && ~send_irq;  //(fatal_err_flag || forced_shutdown) for update ctx used_ptr
            end
        end else if(cstat == WR_IRQ) begin
            wr_order_condition = ~used_elem_ptr_rd_rsp_dat.wr_flag;      //wr irq and update ctx_used_ptr
        end else begin
            wr_order_condition = 1'b0;
        end
    end

//==================================================================//       
    assign used_idx_reduce_one              = used_elem_ptr_rd_rsp_dat.used_idx - 1'b1;

    //=============order_ff_used_idx value==========================//
    //cstat == WR_USED_ELEM_IDX and set_unmask_send_irq：1'b0                      //
    //cstat == WR_USED_ELEM_IDX and wr_used_elem：used_idx_plus_one                // 
    //cstat == WR_USED_ELEM_IDX and wr_used_idx：used_elem_ptr_rd_rsp_dat.used_idx //
    //cstat == WR_IRQ：used_elem_ptr_rd_rsp_dat.used_idx                               //
    //cstat == ERR_HANDLE and wr_used_elem：used_idx_plus_one                          // 
    //cstat == WR_ERR_FATAL_USED_IDX：used_elem_ptr_rd_rsp_dat.used_idx - 1'b1         //
    //cstat == WR_ERR_FATAL_IRQ：used_elem_ptr_rd_rsp_dat.used_idx                     //
    //=================================================================================//
    always @(posedge clk) begin
        if(rst)begin
            order_ff_wren                    <= 1'b0;
        end else begin
            order_ff_wren                    <= wr_order_condition;
        end
    end
    always @(posedge clk) begin
        order_ff_din <= order_ff_din_wire;
    end
    assign order_ff_din_wire.qid                 = used_processing_dat.vq;
    assign order_ff_din_wire.dummy               = forced_shutdown;
    assign order_ff_din_wire.fatal               = fatal_err_flag;  
    //1 || 2; 2 = (cstat == WR_ERR_FATAL_USED_IDX) || (cstat == WR_ERR_FATAL_IRQ):when err,at WR_ERR_FATAL_USED_IDX update ctx used_idx;Whether or not interrupts can be issued;
    assign order_ff_din_wire.update_ctx_used_ptr = (((cstat == WR_USED_ELEM_IDX) && wr_used_idx && ~send_irq) || ((cstat == WR_ERR_FATAL_USED_IDX) || (cstat == WR_ERR_FATAL_IRQ))) ? 1'b1 : 1'b0; //when wr used_idx update ctx used_ptr is 1,wr irq update ctx used_ptr is 0; 
    assign order_ff_din_wire.wr_type             = ((cstat == WR_IRQ) || (cstat == WR_ERR_FATAL_IRQ)) ? IRQ : (((cstat == WR_USED_ELEM_IDX) || (cstat == ERR_HANDLE)) && wr_used_elem) ? USED_INFO : USED_IDX;
    assign order_ff_din_wire.used_idx            = (((cstat == WR_USED_ELEM_IDX) || (cstat == ERR_HANDLE)) && wr_used_elem) ? used_idx_plus_one : used_elem_ptr_rd_rsp_dat.used_idx;
    

    assign order_ff_rden                    = ((order_ff_dout.dummy || order_ff_dout.fatal) && update_ctx_used_ptr && (~order_ff_empty) && (used_idx_cstat == USED_IDX_IDLE)) || (used_idx_cstat == RD_RSP);
    assign order_used_idx                   = order_ff_dout.used_idx[3:0];

    always @(posedge clk) begin
        if(order_ff_rden) begin
            order_ff_dout_reg <= order_ff_dout;
        end
    end 

//==================wr_rsp_ff============================//
    yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(virtio_wr_rsp_info_t) ),
        .FIFO_DEPTH ( 32                          ),
        .CHECK_ON   ( 1                           ),
        .CHECK_MODE ( "parity"                    ),
        .DEPTH_PFULL( 24                          ),
        .RAM_MODE   ( "dist"                      ),
        .FIFO_MODE  ( "fwft"                      )
    ) u_wr_rsp_ff (
        .clk             (clk                      ),
        .rst             (rst                      ),
        .wren            (wr_rsp_ff_wren           ),
        .din             (wr_rsp_ff_din            ),
        .full            (                         ),
        .pfull           (wr_rsp_ff_pfull          ),
        .overflow        (wr_rsp_ff_overflow       ),
        .rden            (wr_rsp_ff_rden           ),
        .dout            (wr_rsp_ff_dout           ),
        .empty           (wr_rsp_ff_empty          ),
        .pempty          (                         ),
        .underflow       (wr_rsp_ff_underflow      ),
        .usedw           (                         ),
        .parity_ecc_err  (wr_rsp_ff_parity_ecc_err )
    );

    assign wr_rsp_ff_wren = dma_data_wr_rsp_if.vld;
    assign wr_rsp_ff_din  = dma_data_wr_rsp_if.rd2rsp_loop;
    assign wr_rsp_ff_rden = (used_idx_cstat == RD_RSP);
    assign rsp_used_idx   = wr_rsp_ff_dout[3:0];

//===================update used_idx FSM===========================//
    assign update_ctx_used_ptr = ((order_ff_dout.wr_type == USED_IDX) && order_ff_dout.update_ctx_used_ptr) || ((order_ff_dout.wr_type == IRQ) && (~order_ff_dout.update_ctx_used_ptr));

    always @(posedge clk) begin
        if(rst) begin
            used_idx_cstat <= USED_IDX_IDLE;
        end else begin
            used_idx_cstat <= used_idx_nstat;        
        end
    end

    always @(*) begin
        used_idx_nstat = used_idx_cstat;
        case(used_idx_cstat) 
            USED_IDX_IDLE: begin
                if((order_ff_dout.dummy || order_ff_dout.fatal) && update_ctx_used_ptr && (~order_ff_empty)) begin
                    used_idx_nstat = WR_CTX_USED_IDX;
                end else if(~wr_rsp_ff_empty && ~order_ff_empty) begin
                    used_idx_nstat = RD_RSP;
                end
            end
            RD_RSP: begin
                if(order_used_idx == rsp_used_idx) begin 
                    if(update_ctx_used_ptr) begin  
                        used_idx_nstat = WR_CTX_USED_IDX;
                    end else begin
                        used_idx_nstat = USED_IDX_IDLE;
                    end
                end else begin
                    used_idx_nstat = USED_IDX_IDLE;
                end
            end
            WR_CTX_USED_IDX: begin
                used_idx_nstat = USED_IDX_IDLE;
            end
            default: used_idx_nstat = USED_IDX_IDLE;
        endcase
    end

//==========================dma wirte used_idx and irq==================================//
    always @(posedge clk) begin
        if(rst) begin
            dma_wr_req_cnt <= 32'd0;
        end else if(dma_data_wr_req_if.vld && dma_data_wr_req_if.eop) begin
            dma_wr_req_cnt <= dma_wr_req_cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            rsp_ff_rd_cnt <= 32'd0;
        end else if(wr_rsp_ff_rden) begin
            rsp_ff_rd_cnt <= rsp_ff_rd_cnt + 1'b1;
        end
    end

    //assign dma_wr_req_en = (dma_wr_req_cnt - rsp_ff_rd_cnt) < (32'd32 - 32'd8);

    always @(posedge clk) begin
        dma_wr_req_en <= (dma_wr_req_cnt - rsp_ff_rd_cnt) < (32'd32 - 32'd8);
    end

//=====================dma_data_wr_if========================//
    assign no_err_used_elem_used_idx_wen     = (cstat == WR_USED_ELEM_IDX) && ((wr_used_idx && ~used_elem_ptr_rd_rsp_dat.wr_flag) || wr_used_elem) && ~fatal_err_flag;
    assign no_err_irq_wen                    = (cstat == WR_IRQ) && ~used_elem_ptr_rd_rsp_dat.wr_flag && ~fatal_err_flag;
    assign err_used_elem_wen                 = (cstat == ERR_HANDLE) && err_handle_rdy && ~is_blk_ds_err_info && ~used_processing_dat.used_dat.used_info.err_info.fatal;
    assign err_used_idx_wen                  = cstat == WR_ERR_FATAL_USED_IDX;
    assign err_irq_wen                       = cstat == WR_ERR_FATAL_IRQ;

    assign dma_write_used_idx_irq_flag_wr_vld = (((cstat == WR_USED_ELEM_IDX) && wr_used_idx && send_irq && ~used_elem_ptr_rd_rsp_dat.wr_flag && ~fatal_err_flag) || no_err_irq_wen || (err_used_idx_wen && msix_enable && ~mask && ~pending) || err_irq_wen) && (~forced_shutdown);
    assign dma_write_used_idx_irq_flag_wr_qid = used_processing_dat.vq;
    assign dma_write_used_idx_irq_flag_wr_dat = (((cstat == WR_USED_ELEM_IDX) && wr_used_idx && send_irq && ~used_elem_ptr_rd_rsp_dat.wr_flag && ~fatal_err_flag) || err_used_idx_wen) ? 1'b1 : 1'b0;

    always @(posedge clk) begin
        if(rst) begin
            dma_data_wr_req_if.vld <= 'h0;
        end else begin
            dma_data_wr_req_if.vld <= (no_err_used_elem_used_idx_wen || no_err_irq_wen || err_used_elem_wen || err_used_idx_wen || err_irq_wen) && (~forced_shutdown);
        end
    end

    always @(posedge clk) begin
        dma_data_wr_req_if.desc.dev_id          <= dev_id;
        dma_data_wr_req_if.desc.rd2rsp_loop     <= {order_ff_din_wire.qid, order_ff_din_wire.wr_type, order_ff_din_wire.used_idx};
        dma_data_wr_req_if.desc.bdf             <= bdf;
        dma_data_wr_req_if.desc.vf_active       <= '0;
        dma_data_wr_req_if.desc.tc              <= '0;
        dma_data_wr_req_if.desc.attr            <= '0;
        dma_data_wr_req_if.desc.th              <= '0;
        dma_data_wr_req_if.desc.td              <= '0;
        dma_data_wr_req_if.desc.ep              <= '0;
        dma_data_wr_req_if.desc.at              <= '0;
        dma_data_wr_req_if.desc.ph              <= '0;
        dma_data_wr_req_if.sty                  <= '0;
        dma_data_wr_req_if.sop                  <= '1;
        dma_data_wr_req_if.eop                  <= '1;      
    end

//=================dma_data_wr_req_if.data/mty================//
    always @(posedge clk) begin
        if(cstat == WR_USED_ELEM_IDX) begin  
            if(wr_used_elem) begin
                dma_data_wr_req_if.data             <= used_processing_dat.used_dat.used_info.elem;   
                dma_data_wr_req_if.mty              <= (DATA_WIDTH - $bits(virtq_used_elem_t))/8;
                dma_data_wr_req_if.desc.pcie_length <= $bits(virtq_used_elem_t)/8;
            end else if(wr_used_idx) begin
                dma_data_wr_req_if.data             <= used_elem_ptr_rd_rsp_dat.used_idx;
                dma_data_wr_req_if.mty              <= (DATA_WIDTH - $bits(used_processing_dat.used_dat.used_info.used_idx))/8;
                dma_data_wr_req_if.desc.pcie_length <= $bits(used_processing_dat.used_dat.used_info.used_idx)/8;
            end
        end else if(cstat == ERR_HANDLE) begin  //ERR_HANDLE is wr_used_elem
            dma_data_wr_req_if.data             <= {32'd0, used_processing_dat.used_dat.used_info.elem.id};  
            dma_data_wr_req_if.mty              <= (DATA_WIDTH - $bits(virtq_used_elem_t))/8;
            dma_data_wr_req_if.desc.pcie_length <= $bits(virtq_used_elem_t)/8;
        end else if(cstat == WR_ERR_FATAL_USED_IDX) begin
            dma_data_wr_req_if.data             <= used_idx_reduce_one;
            dma_data_wr_req_if.mty              <= (DATA_WIDTH - $bits(used_processing_dat.used_dat.used_info.used_idx))/8;
            dma_data_wr_req_if.desc.pcie_length <= $bits(used_processing_dat.used_dat.used_info.used_idx)/8;
        end else if((cstat == WR_ERR_FATAL_IRQ) || (cstat == WR_IRQ)) begin
            dma_data_wr_req_if.data             <= msix_data;
            dma_data_wr_req_if.mty              <= (DATA_WIDTH - 32)/8;
            dma_data_wr_req_if.desc.pcie_length <= 'h4;
        end
    end

//================dma_data_wr_req_if.addr=======================//
    always @(posedge clk) begin
        if((cstat == WR_USED_ELEM_IDX) || (cstat == ERR_HANDLE)) begin
            if(wr_used_elem) begin   //used_elem
                case(qdepth)
                    4'd0: begin   //1
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + 3'b100;  //base_addr + 4
                    end
                    4'd1: begin   //2
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[0],3'b100};
                    end
                    4'd2: begin   //4
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[1:0],3'b100};
                    end
                    4'd3: begin   //8
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[2:0],3'b100};
                    end
                    4'd4: begin   //16
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[3:0],3'b100};
                    end
                    4'd5: begin   //32
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[4:0],3'b100};
                    end
                    4'd6: begin   //64
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[5:0],3'b100};
                    end
                    4'd7: begin   //128
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[6:0],3'b100};
                    end
                    4'd8: begin   //256
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[7:0],3'b100};
                    end
                    4'd9: begin   //512
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[8:0],3'b100};
                    end
                    4'd10: begin   //1024
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[9:0],3'b100};
                    end
                    4'd11: begin   //2048
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[10:0],3'b100};
                    end
                    4'd12: begin   //4096
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[11:0],3'b100};
                    end
                    4'd13: begin   //8192
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[12:0],3'b100};
                    end
                    4'd14: begin   //16384
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[13:0],3'b100};
                    end
                    4'd15: begin   //32768
                        dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + {used_processing_dat.used_dat.used_info.used_idx[14:0],3'b100};
                    end                
                endcase
            end else if(wr_used_idx) begin
                 dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + 'h2;
            end
        end else if(cstat == WR_ERR_FATAL_USED_IDX) begin
            dma_data_wr_req_if.desc.pcie_addr <= used_ring_addr + 'h2;
        end else if((cstat == WR_ERR_FATAL_IRQ) || (cstat == WR_IRQ)) begin
            dma_data_wr_req_if.desc.pcie_addr <= msix_addr;    //irq
        end
    end

//==================wr ctx mask/pending table============================//
    assign msix_tbl_wr_vld     = (cstat == SET_PENDING) || (cstat == SET_MASK_UNMASK);
    assign msix_tbl_wr_qid     = used_processing_dat.vq;
    assign msix_tbl_wr_mask    = (cstat == SET_MASK_UNMASK) ? ((used_processing_dat.used_dat.used_info[0] && ~mask && ~pending) ? 1'b1 : (~used_processing_dat.used_dat.used_info[0] && mask) ? 1'b0 : mask) : mask;
    assign msix_tbl_wr_pending = (cstat == SET_PENDING) ? 1'b1 : ((cstat == SET_MASK_UNMASK) && ~used_processing_dat.used_dat.used_info[0] && mask && pending) ? 1'b0 : pending;

//======================update ctx used_idx================================//    
    assign used_idx_wr_vld = (used_idx_cstat == WR_CTX_USED_IDX);
    assign used_idx_wr_qid = order_ff_dout_reg.qid;
    assign used_idx_wr_dat = order_ff_dout_reg.used_idx;

//=======================to err_handle=============================//
    assign err_handle_vld = (cstat == ERR_HANDLE);
    assign err_handle_qid = used_processing_dat.vq;
    assign err_handle_dat = is_blk_ds_err_info ? used_processing_dat.used_dat.used_info : used_processing_dat.used_dat.used_info.err_info;

//======================mon send irq==============================//
    always @(posedge clk) begin
        if(rst) begin
            mon_send_a_irq <= 1'b0;
        end else begin
            mon_send_a_irq <= (no_err_irq_wen || err_irq_wen) && (~forced_shutdown);
        end
        mon_send_irq_vq <= used_processing_dat.vq;
    end

    `ifdef PMON_EN
    localparam PP_IF_NUM = 3;
    localparam CNT_WIDTH = 26;
    localparam MS_100_CLEAN_CNT = `MS_100_CLEAN_CNT_AT_USER_CLK;
    
    
    logic   [PP_IF_NUM-1:0]             backpressure_vld;
    logic   [PP_IF_NUM-1:0]             backpressure_sav;
    logic   [PP_IF_NUM-1:0]             handshake_vld;
    logic   [PP_IF_NUM-1:0]             handshake_rdy;
    logic   [CNT_WIDTH-1:0]             mon_tick_interval;
    logic   [PP_IF_NUM*CNT_WIDTH-1:0]   backpressure_block_cnt;
    logic   [PP_IF_NUM*CNT_WIDTH-1:0]   backpressure_vdata_cnt;
    logic   [PP_IF_NUM*CNT_WIDTH-1:0]   handshake_block_cnt;
    logic   [PP_IF_NUM*CNT_WIDTH-1:0]   handshake_vdata_cnt;

    
    assign mon_tick_interval = MS_100_CLEAN_CNT;
    assign backpressure_vld = {2'b0, dma_data_wr_req_if.vld};
    assign backpressure_sav = {2'b0, dma_data_wr_req_if.sav};
    assign handshake_vld = {wr_used_info_vld && (wr_used_info_dat.vq.typ == VIRTIO_BLK_TYPE), wr_used_info_vld && (wr_used_info_dat.vq.typ == VIRTIO_NET_RX_TYPE), wr_used_info_vld && (wr_used_info_dat.vq.typ == VIRTIO_NET_TX_TYPE)};
    assign handshake_rdy = {wr_used_info_rdy, wr_used_info_rdy, wr_used_info_rdy};
    
    
    performance_probe#(
        .PP_IF_NUM          ( PP_IF_NUM ),
        .CNT_WIDTH          ( CNT_WIDTH )
    )u_used_performance_probe(
        .clk                       ( clk                   ),
        .rst                       ( rst                   ),
        .backpressure_vld          ( backpressure_vld      ),
        .backpressure_sav          ( backpressure_sav      ),
        .handshake_vld             ( handshake_vld         ),
        .handshake_rdy             ( handshake_rdy         ),
        .mon_tick_interval         ( mon_tick_interval     ),
        .backpressure_block_cnt    ( backpressure_block_cnt),
        .backpressure_vdata_cnt    ( backpressure_vdata_cnt),
        .handshake_block_cnt       ( handshake_block_cnt   ),
        .handshake_vdata_cnt       ( handshake_vdata_cnt   )
    );
    `endif 

//==============dfx=========================//
    always @(posedge clk) begin
        if(rst) begin
            dfx_err <= {$bits(dfx_err){1'b0}};
        end else begin
            dfx_err <= {
                (cstat == PROCESS) && ~q_status_en && (wr_used_elem || is_blk_ds_err_info),    //11
                (cstat == PROCESS) && ~forced_shutdown && (is_used_info_irq && (used_processing_dat.used_dat.typ == USED_INFO) && used_processing_dat.used_dat.used_info.forced_shutdown),    //10
                (cstat == PROCESS) && is_used_info_irq && (used_processing_dat.used_dat.typ == USED_INFO) && (used_processing_dat.used_dat.used_info.err_info.err_code == VIRTIO_ERR_CODE_NONE) && used_processing_dat.used_dat.used_info.err_info.fatal,       //9                 
                (used_idx_cstat == RD_RSP) && (order_used_idx != rsp_used_idx),                                                                                             //8
                order_ff_overflow,                                                                                                                                          //7
                order_ff_underflow,                                                                                                                                         //6
                order_ff_parity_ecc_err,                                                                                                                                    //5-4
                wr_rsp_ff_overflow,                                                                                                                                         //3
                wr_rsp_ff_underflow,                                                                                                                                        //2
                wr_rsp_ff_parity_ecc_err                                                                                                                                    //1-0
                };
        end
    end

    genvar idx;
    generate
        for(idx=0;idx<$bits(dfx_err);idx++)begin :virtio_used_err_i
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err[idx]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, dfx_err[idx], idx));
        end
    endgenerate

    assign dfx_status = {
        forced_shutdown,          //25
        dma_data_wr_req_if.sav,   //24
        wr_used_info_vld,         //23
        wr_used_info_rdy,         //22
        err_handle_rdy,           //21
        err_handle_vld,           //20
        order_ff_pfull,           //19
        order_ff_empty,           //18
        wr_rsp_ff_pfull,          //17
        wr_rsp_ff_empty,          //16
        used_idx_cstat,           //15-13
        cstat                     //12-0     
    };

    always @(posedge clk) begin
        if(rst) begin
            wr_used_info_cnt             <= 8'd0;
            dma_data_wr_req_cnt          <= 8'd0;
            dma_data_wr_rsp_cnt          <= 8'd0;
            dfx_err_cnt                  <= 8'd0;
        end else begin
            if(wr_used_info_vld && wr_used_info_rdy) begin
                wr_used_info_cnt <= wr_used_info_cnt + 1'b1;
            end
            if(dma_data_wr_req_if.vld && dma_data_wr_req_if.eop) begin
                dma_data_wr_req_cnt <= dma_data_wr_req_cnt + 1'b1;
            end
            if(dma_data_wr_rsp_if.vld) begin
                dma_data_wr_rsp_cnt <= dma_data_wr_rsp_cnt + 1'b1;
            end
            if(cstat == DFX_ERR) begin
                dfx_err_cnt <= dfx_err_cnt + 1'b1;
            end
        end
    end
      

    virtio_used_dfx #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(64)
    )u_virtio_used_dfx(
        .clk(clk),
        .rst(rst),

        .dfx_err_dfx_err_we     (|dfx_err),             
        .dfx_err_dfx_err_wdata  (dfx_err|dfx_err_q),    
        .dfx_err_dfx_err_q      (dfx_err_q),            

        .dfx_used_idx_irq_merge_err_dfx_used_idx_irq_merge_err_we(|dfx_used_idx_irq_merge_err),            
        .dfx_used_idx_irq_merge_err_dfx_used_idx_irq_merge_err_wdata(dfx_used_idx_irq_merge_err|dfx_used_idx_irq_merge_err_q),        
        .dfx_used_idx_irq_merge_err_dfx_used_idx_irq_merge_err_q(dfx_used_idx_irq_merge_err_q),             

        .dfx_irq_merge_core_net_tx_err_dfx_irq_merge_core_net_tx_err_we(|dfx_irq_merge_core_net_tx_err),            
        .dfx_irq_merge_core_net_tx_err_dfx_irq_merge_core_net_tx_err_wdata(dfx_irq_merge_core_net_tx_err|dfx_irq_merge_core_net_tx_err_q),         
        .dfx_irq_merge_core_net_tx_err_dfx_irq_merge_core_net_tx_err_q(dfx_irq_merge_core_net_tx_err_q),   

        .dfx_irq_merge_core_net_rx_err_dfx_irq_merge_core_net_rx_err_we(|dfx_irq_merge_core_net_rx_err),            
        .dfx_irq_merge_core_net_rx_err_dfx_irq_merge_core_net_rx_err_wdata(dfx_irq_merge_core_net_rx_err|dfx_irq_merge_core_net_rx_err_q),         
        .dfx_irq_merge_core_net_rx_err_dfx_irq_merge_core_net_rx_err_q(dfx_irq_merge_core_net_rx_err_q),   

        .dfx_status_dfx_status_wdata(dfx_status),               
        .dfx_used_idx_irq_merge_status_dfx_used_idx_irq_merge_status_wdata(dfx_used_idx_irq_merge_status),  
        .used_dfx_err_cnt_used_dfx_err_cnt_wdata(dfx_err_cnt),
        .dma_cnt_dma_cnt_wdata({dma_data_wr_req_cnt, dma_data_wr_rsp_cnt}),
        `ifdef PMON_EN
        .dma_data_wr_req_if_backpressure_block_vdata_cnt_dma_data_wr_req_if_backpressure_block_vdata_cnt_wdata({backpressure_block_cnt[1*CNT_WIDTH-1:0], 6'd0, backpressure_vdata_cnt[1*CNT_WIDTH-1:0]}),
        .net_tx_used_info_handshake_block_vdata_cnt_net_tx_used_info_handshake_block_vdata_cnt_wdata({handshake_block_cnt[1*CNT_WIDTH-1:0], 6'd0, handshake_vdata_cnt[1*CNT_WIDTH-1:0]}),
        .net_rx_used_info_handshake_block_vdata_cnt_net_rx_used_info_handshake_block_vdata_cnt_wdata({handshake_block_cnt[2*CNT_WIDTH-1:1*CNT_WIDTH], 6'd0, handshake_vdata_cnt[2*CNT_WIDTH-1:1*CNT_WIDTH]}),
        .blk_used_info_handshake_block_vdata_cnt_blk_used_info_handshake_block_vdata_cnt_wdata({handshake_block_cnt[3*CNT_WIDTH-1:2*CNT_WIDTH], 6'd0, handshake_vdata_cnt[3*CNT_WIDTH-1:2*CNT_WIDTH]}),
        `endif
        .csr_if(dfx_if)
    );





 endmodule


