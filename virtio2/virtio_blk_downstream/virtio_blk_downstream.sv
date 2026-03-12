/******************************************************************************
 * 文件名称 : virtio_blk_downstream.sv
 * 作者名称 : matao
 * 创建日期 : 2025/07/04
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   07/04       matao       初始化版本
 ******************************************************************************/
`include "virtio_define.svh"
`include "virtio_blk_downstream_define.svh"
`include "beq_data_if.svh"
`include "tlp_adap_dma_if.svh"
module virtio_blk_downstream 
    import alt_tlp_adaptor_pkg::*;
    #(
    parameter  QOS_QUERY_UID_WIDTH   = 10   ,
    parameter  VIRTIO_Q_WIDTH        = 8    ,
    parameter  DATA_WIDTH            = 256  ,
    parameter  REG_ADDR_WIDTH        = 16   ,
    parameter  REG_DATA_WIDTH        = 64
)(
    input                                           clk                         ,
    input                                           rst                         ,

    //notify 
    input  logic                                    notify_req_vld              ,
    input  logic  [VIRTIO_Q_WIDTH-1:0]              notify_req_qid              ,
    output logic                                    notify_req_rdy              ,

    input  logic                                    notify_rsp_rdy              ,
    output logic                                    notify_rsp_vld              ,
    output logic  [VIRTIO_Q_WIDTH-1:0]              notify_rsp_qid              ,
    output logic                                    notify_rsp_cold             ,
    output logic                                    notify_rsp_done             ,

    //qos query update
    input  logic                                    qos_query_req_rdy           ,
    output logic  [QOS_QUERY_UID_WIDTH-1:0]         qos_query_req_uid           ,
    output logic                                    qos_query_req_vld           ,

    input  logic                                    qos_query_rsp_vld           ,
    input  logic                                    qos_query_rsp_ok            ,
    output logic                                    qos_query_rsp_rdy           ,

    input  logic                                    qos_update_rdy              ,
    output logic                                    qos_update_vld              ,
    output logic [QOS_QUERY_UID_WIDTH-1:0]          qos_update_uid              ,
    output logic [19:0]                             qos_update_len              ,
    output logic [7:0]                              qos_update_pkt_num          ,

    //alloc slot
    input  logic                                    alloc_slot_req_rdy          ,
    output logic                                    alloc_slot_req_vld          ,
    output virtio_vq_t                              alloc_slot_req_dat          ,

    input  logic                                    alloc_slot_rsp_vld          ,
    input  virtio_desc_eng_slot_rsp_t               alloc_slot_rsp_dat          ,
    output logic                                    alloc_slot_rsp_rdy          ,

    //blk desc
    input  logic                                    blk_desc_vld                ,
    input  logic                                    blk_desc_sop                ,
    input  logic                                    blk_desc_eop                ,
    input  virtio_desc_eng_desc_rsp_sbd_t           blk_desc_sbd                ,
    input  virtq_desc_t                             blk_desc_dat                ,
    output logic                                    blk_desc_rdy                ,

    //desc rd data
    tlp_adap_dma_rd_req_if.src                      desc_rd_data_req_if         ,
    tlp_adap_dma_rd_rsp_if.snk                      desc_rd_data_rsp_if         ,

    //blk2beq
    beq_rxq_bus_if.src                              blk2beq_if                  ,

    //context info
    output logic                                    qos_info_rd_req_vld         ,
    output logic  [VIRTIO_Q_WIDTH-1:0]              qos_info_rd_req_qid         ,

    input  logic                                    qos_info_rd_rsp_vld         ,
    input  logic                                    qos_info_rd_rsp_qos_enable  ,
    input  logic  [QOS_QUERY_UID_WIDTH-1:0]         qos_info_rd_rsp_qos_unit    ,

    output logic                                    dma_info_rd_req_vld         ,
    output logic  [VIRTIO_Q_WIDTH-1:0]              dma_info_rd_req_qid         ,

    input  logic                                    dma_info_rd_rsp_vld         ,
    input  logic  [15:0]                            dma_info_rd_rsp_bdf         ,
    input  logic                                    dma_info_rd_rsp_forcedown   ,
    input  logic  [7:0]                             dma_info_rd_rsp_generation  ,

    output logic                                    blk_ds_ptr_rd_req_vld       ,
    output logic  [VIRTIO_Q_WIDTH-1:0]              blk_ds_ptr_rd_req_qid       ,
    input  logic                                    blk_ds_ptr_rd_rsp_vld       ,
    input  logic  [15:0]                            blk_ds_ptr_rd_rsp_dat       ,
    output logic                                    blk_ds_ptr_wr_vld           ,
    output logic  [VIRTIO_Q_WIDTH-1:0]              blk_ds_ptr_wr_qid           ,
    output logic  [15:0]                            blk_ds_ptr_wr_dat           ,

    output logic                                    blk_chain_fst_seg_rd_req_vld,
    output logic  [VIRTIO_Q_WIDTH-1:0]              blk_chain_fst_seg_rd_req_qid,
    input  logic                                    blk_chain_fst_seg_rd_rsp_vld,
    input  logic                                    blk_chain_fst_seg_rd_rsp_dat,
    output logic                                    blk_chain_fst_seg_wr_vld    ,
    output logic  [VIRTIO_Q_WIDTH-1:0]              blk_chain_fst_seg_wr_qid    ,
    output logic                                    blk_chain_fst_seg_wr_dat    ,

    input  logic                                    blk_ds_err_info_wr_rdy      ,
    output logic                                    blk_ds_err_info_wr_vld      ,
    output virtio_vq_t                              blk_ds_err_info_wr_qid      ,
    output virtio_err_info_t                        blk_ds_err_info_wr_dat      ,

    //register_if 
    mlite_if.slave                                  csr_if
);

localparam  VIRTIO_ERR_INFO_WIDTH     = $bits(virtio_err_info_t)                                                                        ;
localparam  SLOT_INFO_FF_DATA_WIDTH   = VIRTIO_Q_WIDTH + QOS_QUERY_UID_WIDTH + VIRTIO_ERR_INFO_WIDTH + 3                                ;
localparam  DESC_INFO_FF_DATA_WIDTH   = $bits(virtio_blk_downstream_desc_info_t)                                                        ;
localparam  DMA_RD_REQ_RSP_LOOP_WIDTH = VIRTIO_Q_WIDTH + 16                                                                             ;
localparam  BLK_BUFFER_HDR_MAGIC_NUM  = 16'hC0DE                                                                                        ;
localparam  BUFFER_HDR_SIZE           = 64                                                                                              ;
localparam  BUFFER_HDR_CYCLES         = (DATA_WIDTH/8 > BUFFER_HDR_SIZE) ? 1 : BUFFER_HDR_SIZE/(DATA_WIDTH/8)                           ;
localparam  EMPTH_WIDTH               = $clog2(DATA_WIDTH/8)                                                                            ;
localparam  DMA_RSP_DESC_PCIE_LENGTH  = $bits(desc_rd_data_rsp_if.desc.pcie_length)                                                     ;
localparam  PKT_FF_WIDTH              = 3 + DATA_WIDTH + EMPTH_WIDTH * 2 + DMA_RD_REQ_RSP_LOOP_WIDTH + DMA_RSP_DESC_PCIE_LENGTH         ;
localparam  PKT_FF_DEPTH              = 512                                                                                             ;
localparam  INTRANSIT_NUM             = PKT_FF_DEPTH                                                                                    ;
localparam  DMA_MAX_SIZE              = 4096                                                                                            ;
localparam  DMA_RD_ADDR_WIDTH         = $bits(blk_desc_dat.addr)                                                                        ;

//dfx
logic                                   blk_downstream_err_we           ;
logic  [REG_DATA_WIDTH-1:0]             blk_downstream_err_wdata        ;
logic  [REG_DATA_WIDTH-1:0]             blk_downstream_err_q            ;
logic  [REG_DATA_WIDTH-1:0]             blk_downstream_ff_stat_wdata    ;
logic  [REG_DATA_WIDTH-1:0]             blk_downstream_fsm_stat_wdata   ;
logic                                   blk_downstream_err_cnt_we       ;
logic  [REG_DATA_WIDTH-1:0]             blk_downstream_err_cnt_wdata    ;
logic  [REG_DATA_WIDTH-1:0]             blk_downstream_err_cnt_q        ;
logic                                   blk_downstream_if_cnt_we        ;
logic  [REG_DATA_WIDTH-1:0]             blk_downstream_if_cnt_wdata     ;
logic  [REG_DATA_WIDTH-1:0]             blk_downstream_if_cnt_q         ;
logic  [REG_DATA_WIDTH-1:0]             blk_desc_hs_related_cnt_wdata   ;
logic  [REG_DATA_WIDTH-1:0]             dma_rd_req_bp_related_cnt_wdata ;
logic  [REG_DATA_WIDTH-1:0]             dma_rd_rsp_bp_vdata_cnt_wdata   ;
logic  [9:0]                            blk_downstream_dma_infligth_q   ;
logic  [2:0]                            blk_downstream_err_cnt_en       ;
logic  [3:0]                            blk_downstream_if_cnt_en        ;

//Signal Segment1:qos fsm
enum logic [5:0]  { 
    QOS_IDLE    = 6'b000001,
    QOS_CTX_REQ = 6'b000010,
    QOS_CTX_RSP = 6'b000100,
    QOS_REQ     = 6'b001000,
    QOS_RSP     = 6'b010000,
    QOS_NO_EN   = 6'b100000
} qos_cstat, qos_nstat;

logic  [VIRTIO_Q_WIDTH-1:0]             qos_qid_d                       ;
logic  [QOS_QUERY_UID_WIDTH-1:0]        qos_uid_d                       ;
logic                                   qos_info_rd_rsp_qos_enable_d    ;

logic                                   qos2alloc_slot_rdy              ;
logic                                   qos2alloc_slot_vld              ;
logic                                   qos2alloc_slot_ok               ;
logic  [VIRTIO_Q_WIDTH-1:0]             qos2alloc_slot_qid              ;
logic  [QOS_QUERY_UID_WIDTH-1:0]        qos2alloc_slot_uid              ;
logic                                   qos2alloc_slot_qos_en           ;

//Signal Segment2:alloc slot fsm
enum logic [3:0]  { 
    ALLOC_SLOT_IDLE   = 4'b0001,
    ALLOC_SLOT_REQ    = 4'b0010,
    ALLOC_SLOT_RSP    = 4'b0100,
    ALLOC_SLOT_WR     = 4'b1000
} alloc_slot_cstat, alloc_slot_nstat;

logic  [VIRTIO_Q_WIDTH-1:0]             alloc_slot_qid_d                ;
logic  [QOS_QUERY_UID_WIDTH-1:0]        alloc_slot_uid_d                ;
logic                                   alloc_slot_cold                 ;
logic                                   alloc_slot_done                 ;
logic                                   alloc_slot_qid_match_err        ;
logic                                   alloc_slot_local_ring_empty_err ;
virtio_vq_t                             alloc_slot_req_dat_d            ;
logic  [VIRTIO_ERR_INFO_WIDTH-1:0]      alloc_slot_err                  ;
logic                                   alloc_slot_qos_en_d             ;


//Signal Segment3:slot info fifo - slot_info_ff
logic                                   slot_info_ff_wren      , slot_info_ff_pfull    , slot_info_ff_rden, slot_info_ff_empty, slot_info_ff_full   ;
logic  [SLOT_INFO_FF_DATA_WIDTH-1:0]    slot_info_ff_din       , slot_info_ff_dout                                                                  ;
logic                                   slot_info_ff_overflow  , slot_info_ff_underflow                                                             ;
logic  [1:0]                            slot_info_ff_parity_ecc_err                                                                                 ;

//Signal Segment4:desc_arbiteration fsm
enum logic [10:0]  { 
    ARB_IDLE        = 11'b00000000001,
    ARB_CTX_REQ     = 11'b00000000010,
    ARB_CTX_RSP     = 11'b00000000100,
    ARB_DESC_WAIT   = 11'b00000001000,
    ARB_INFO_WR     = 11'b00000010000,
    ARB_DESC_PRO    = 11'b00000100000,
    ARB_DMA_CHK     = 11'b00001000000,
    ARB_DMA_RD      = 11'b00010000000,
    ARB_QOS_UPDATE  = 11'b00100000000,
    ARB_DESC_RD     = 11'b01000000000,
    ARB_NOTIFY_RSP  = 11'b10000000000
} arbitration_cstat, arbitration_nstat;

logic  [VIRTIO_Q_WIDTH-1:0]             arbiteration_slot_ff_qid        ;
logic  [QOS_QUERY_UID_WIDTH-1:0]        arbiteration_slot_ff_uid        ;
logic                                   arbiteration_slot_ff_cold       ;
logic                                   arbiteration_slot_ff_done       ;
logic  [VIRTIO_ERR_INFO_WIDTH-1:0]      arbiteration_slot_ff_err        ;
logic                                   arbiteration_slot_ff_qos_en     ;

logic  [VIRTIO_Q_WIDTH-1:0]             arbiteration_slot_ff_qid_d      ;
logic  [QOS_QUERY_UID_WIDTH-1:0]        arbiteration_slot_ff_uid_d      ;
logic                                   arbiteration_slot_ff_cold_d     ;
logic                                   arbiteration_slot_ff_done_d     ;
logic  [VIRTIO_ERR_INFO_WIDTH-1:0]      arbiteration_slot_ff_err_d      ;
logic                                   arbiteration_slot_ff_qos_en_d   ;

//from dma info req
logic  [15:0]                           dma_info_rd_rsp_bdf_d           ;
logic                                   dma_info_rd_rsp_forcedown_d     ;
logic  [7:0]                            dma_info_rd_rsp_generation_d    ;
logic                                   arbiteration_err_shutdown       ;

//from desc_data
logic                                   arbiteration_next               ;
//to desc_info_ff
logic  [VIRTIO_ERR_INFO_WIDTH-1:0]      arbiteration_err_info           ;
logic  [7:0]                            arbiteration_gen                ;
logic                                   arbiteration_ext_shutdown       ;
logic                                   arbiteration_int_shutdown       ;
logic                                   arbiteration_sop                ;

logic                                   inflight_rd_fifo_rdy            ;
logic                                   inflight_rd_dma_rdy             ;
//blk_desc d
logic                                   blk_desc_vld_d                  ;
logic                                   blk_desc_eop_d                  ;
virtio_desc_eng_desc_rsp_sbd_t          blk_desc_sbd_d                  ;
virtq_desc_t                            blk_desc_dat_d                  ;

//dma req 4k cut 
logic                                   dma_rd_req_last                 ;
logic  [DMA_RSP_DESC_PCIE_LENGTH-1:0]   dma_rd_req_current_len          ;
logic  [DMA_RD_ADDR_WIDTH-1:0]          dma_rd_req_current_addr         ;

//Signal Segment5:desc info fifo - desc_info_ff 
logic                                   desc_info_ff_wren      , desc_info_ff_pfull    , desc_info_ff_rden, desc_info_ff_empty, desc_info_ff_full   ;
virtio_blk_downstream_desc_info_t       desc_info_ff_din       , desc_info_ff_dout                                                                  ;
logic                                   desc_info_ff_overflow  , desc_info_ff_underflow                                                             ;
logic  [1:0]                            desc_info_ff_parity_ecc_err                                                                                 ;

logic  [VIRTIO_Q_WIDTH-1:0]             desc_info_ff_out_qid_d ;

//Signal Segment7:pkt fifo
logic                                   data_pkt_ff_wren    , data_pkt_ff_rden     , data_pkt_ff_wr_end ; 
//logic                                   data_pkt_ff_wren    , data_pkt_ff_rden                          ; 
logic                                   data_pkt_ff_empty   , data_pkt_ff_pfull    , data_pkt_ff_full   ;
logic  [PKT_FF_WIDTH-1:0]               data_pkt_ff_din     , data_pkt_ff_dout                          ;
logic                                   data_pkt_ff_overflow, data_pkt_ff_underflow                     ;
logic  [1:0]                            data_pkt_ff_parity_ecc_err                                      ;
logic                                   data_pkt_ff_rden_d                                              ;

logic                                   pkt_ff2rsp_sop, pkt_ff2rsp_eop, pkt_ff2rsp_err                  ;
logic  [DATA_WIDTH-1:0]                 pkt_ff2rsp_data                                                 ;
logic  [EMPTH_WIDTH-1:0]                pkt_ff2rsp_sty, pkt_ff2rsp_mty                                  ;
logic  [DMA_RD_REQ_RSP_LOOP_WIDTH-1:0]  desc_rd_rsp_desc_rsp_loop                                       ;
logic  [DMA_RSP_DESC_PCIE_LENGTH-1:0]   desc_rd_rsp_desc_pcie_length                                    ;

logic                                   dma_rd_rsp_loop_match_err                                       ;

//Signal Segment8:desc rsp fsm
enum logic [8:0]  { 
    RSP_IDLE         = 9'b0_0000_0001,
    RSP_HDR          = 9'b0_0000_0010,
    RSP_WAIT         = 9'b0_0000_0100,
    RSP_RD           = 9'b0_0000_1000,
    RSP_ARB          = 9'b0_0001_0000,
    RSP_CTX_RD       = 9'b0_0010_0000,
    RSP_CTX_RSP      = 9'b0_0100_0000,
    RSP_ERR_CTX      = 9'b0_1000_0000,
    RSP_DMA_SHUTDOWN = 9'b1_0000_0000
} rsp_cstat, rsp_nstat;

logic  [$clog2(BUFFER_HDR_CYCLES)-1:0]  rsp_hdr_cnt                             ; 
virtio_err_info_t                       dma_rd_rsp_err_info                     ;
beq_rxq_sbd_t                           blk2beq_sbd                             ;
virtio_blk_downstream_buffer_header_t   buffer_hdr                              ;
logic  [11:0]                           inflight_rd_fifo                        ;
logic  [11:0]                           remaining_infligth                      ;
logic  [11:0]                           current_req_credit                      ;
//logic  [11:0]                           inflight_rd_dma                         ;
logic  [VIRTIO_ERR_INFO_WIDTH-1:0]      buffer_hdr_err_d                        ;
logic  [VIRTIO_ERR_INFO_WIDTH-1:0]      dma_rd_rsp_err_d                        ;
logic  [VIRTIO_ERR_INFO_WIDTH-1:0]      slot_desc_err_d                         ;
logic                                   blk2beq_shutdown                        ;
logic                                   beq_sbd_end_of_pkt                      ;
logic                                   dma_pkt_ff_rdy                          ;

//Signal Segment9:PMON_EN
`ifdef PMON_EN
localparam PP_IF_NUM = 2 ;
localparam CNT_WIDTH = 26;
localparam MS_100_CLEAN_CNT = `MS_100_CLEAN_CNT_AT_USER_CLK;

logic   [PP_IF_NUM-1:0]             backpressure_vld        ;
logic   [PP_IF_NUM-1:0]             backpressure_sav        ;
logic   [PP_IF_NUM-1:0]             handshake_vld           ;
logic   [PP_IF_NUM-1:0]             handshake_rdy           ;
logic   [CNT_WIDTH-1:0]             mon_tick_interval       ;
logic   [PP_IF_NUM*CNT_WIDTH-1:0]   backpressure_block_cnt  ;
logic   [PP_IF_NUM*CNT_WIDTH-1:0]   backpressure_vdata_cnt  ;
logic   [PP_IF_NUM*CNT_WIDTH-1:0]   handshake_block_cnt     ;
logic   [PP_IF_NUM*CNT_WIDTH-1:0]   handshake_vdata_cnt     ;
`endif

//Logic Segment1: qos fsm
always @(posedge clk) begin
    if(rst)begin
        qos_cstat <= QOS_IDLE;
    end else begin
        qos_cstat <= qos_nstat;
    end
end

always @(*)begin
    qos_nstat = qos_cstat;
    case (qos_cstat)
        QOS_IDLE: begin
            if(notify_req_vld)begin
                qos_nstat = QOS_CTX_REQ;
            end
        end
        QOS_CTX_REQ: begin
            qos_nstat = QOS_CTX_RSP;
        end
        QOS_CTX_RSP: begin
            if(qos_info_rd_rsp_vld && ((qos_info_rd_rsp_qos_enable && blk_chain_fst_seg_rd_rsp_dat) == 0))begin
                qos_nstat = QOS_NO_EN;
            end else if(qos_info_rd_rsp_vld && qos_info_rd_rsp_qos_enable && blk_chain_fst_seg_rd_rsp_dat)begin
                qos_nstat = QOS_REQ;
            end
        end
        QOS_REQ: begin
            if(qos_query_req_rdy)begin
                qos_nstat = QOS_RSP;
            end
        end
        QOS_RSP: begin
            if(qos_query_rsp_vld && qos2alloc_slot_rdy)begin
                qos_nstat = QOS_IDLE;
            end
        end
        QOS_NO_EN: begin
            if(qos2alloc_slot_rdy)begin
                qos_nstat = QOS_IDLE;
            end
        end
        default:begin
            qos_nstat = qos_cstat;
        end
    endcase
end

always@(posedge clk) begin
    if(qos_cstat == QOS_IDLE) begin
        qos_qid_d <= notify_req_qid;
    end
end

always@(posedge clk) begin
    if(qos_info_rd_rsp_vld) begin
        qos_uid_d <= qos_info_rd_rsp_qos_unit;
    end
end

always@(posedge clk) begin
    if(qos_info_rd_rsp_vld) begin
        qos_info_rd_rsp_qos_enable_d <= qos_info_rd_rsp_qos_enable;
    end
end

//notify req rdy
assign notify_req_rdy = (qos_cstat == QOS_CTX_REQ);
//qos info rd req
assign qos_info_rd_req_qid = qos_qid_d                                                                  ;
assign qos_info_rd_req_vld = (qos_cstat == QOS_CTX_REQ)                                                 ;
assign blk_chain_fst_seg_rd_req_qid = qos_qid_d                                                         ;
assign blk_chain_fst_seg_rd_req_vld = (qos_cstat == QOS_CTX_REQ)                                        ;
//qos query req rsp
assign qos_query_req_uid = qos_uid_d                                                                    ;
assign qos_query_req_vld = (qos_cstat == QOS_REQ)                                                       ;

assign qos_query_rsp_rdy = (qos_cstat == QOS_RSP) && qos_query_rsp_vld && qos2alloc_slot_rdy            ;
//qos fsm to alloc slot fsm
assign qos2alloc_slot_vld = ((qos_cstat == QOS_RSP) && qos_query_rsp_vld) || (qos_cstat == QOS_NO_EN)   ;
assign qos2alloc_slot_ok  = (qos_cstat == QOS_NO_EN) ? 1 : qos_query_rsp_ok                             ;
assign qos2alloc_slot_qid = qos_qid_d                                                                   ;
assign qos2alloc_slot_uid = qos_uid_d                                                                   ;
assign qos2alloc_slot_qos_en = qos_info_rd_rsp_qos_enable_d                                             ;

//Logic Segment2: alloc slot fsm
always @(posedge clk) begin
    if(rst)begin
        alloc_slot_cstat <= ALLOC_SLOT_IDLE;
    end else begin
        alloc_slot_cstat <= alloc_slot_nstat;
    end
end

always @(*)begin
    alloc_slot_nstat = alloc_slot_cstat;
    case (alloc_slot_cstat)
        ALLOC_SLOT_IDLE: begin
            if(qos2alloc_slot_vld && (!slot_info_ff_pfull))begin
                if(qos2alloc_slot_ok)begin
                    alloc_slot_nstat = ALLOC_SLOT_REQ;
                end else begin
                    alloc_slot_nstat = ALLOC_SLOT_WR;
                end
            end
        end
        ALLOC_SLOT_REQ: begin
            if(alloc_slot_req_rdy)begin
                alloc_slot_nstat = ALLOC_SLOT_RSP;
            end
        end
        ALLOC_SLOT_RSP: begin
            if(alloc_slot_rsp_vld)begin
                alloc_slot_nstat = ALLOC_SLOT_WR;
            end
        end
        ALLOC_SLOT_WR: begin
            alloc_slot_nstat = ALLOC_SLOT_IDLE;
        end
        default:begin
            alloc_slot_nstat = alloc_slot_cstat;
        end
    endcase
end

always@(posedge clk) begin
    if(alloc_slot_cstat == ALLOC_SLOT_IDLE) begin
        alloc_slot_qid_d <= qos2alloc_slot_qid;
    end
end

always@(posedge clk) begin
    if(alloc_slot_cstat == ALLOC_SLOT_IDLE) begin
        alloc_slot_uid_d <= qos2alloc_slot_uid;
    end
end

always@(posedge clk) begin
    if(alloc_slot_cstat == ALLOC_SLOT_IDLE) begin
        alloc_slot_qos_en_d <= qos2alloc_slot_qos_en;
    end
end

always@(posedge clk) begin
    if(alloc_slot_req_vld) begin
        alloc_slot_req_dat_d <= alloc_slot_req_dat;
    end
end

//qos2alloc_slot rdy
assign qos2alloc_slot_rdy = (alloc_slot_cstat == ALLOC_SLOT_IDLE) && qos2alloc_slot_vld && (!slot_info_ff_pfull);
//alloc_slot_req rsp
assign alloc_slot_req_vld = (alloc_slot_cstat == ALLOC_SLOT_REQ)                                        ;
assign alloc_slot_req_dat.qid = alloc_slot_qid_d                                                        ;
assign alloc_slot_req_dat.typ = VIRTIO_BLK_TYPE                                                         ;

assign alloc_slot_rsp_rdy = (alloc_slot_cstat == ALLOC_SLOT_RSP) && alloc_slot_rsp_vld                  ;
assign alloc_slot_qid_match_err = alloc_slot_rsp_vld && (alloc_slot_req_dat_d != alloc_slot_rsp_dat.vq) ;

//cold done
always @(posedge clk) begin
    if((alloc_slot_cstat == ALLOC_SLOT_IDLE) && (!qos2alloc_slot_ok))begin
        alloc_slot_cold <= 1;
    end else if(alloc_slot_cstat == ALLOC_SLOT_RSP)begin
        casex ({alloc_slot_rsp_dat.q_stat_doing, alloc_slot_rsp_dat.q_stat_stopping, alloc_slot_rsp_dat.avail_ring_empty, alloc_slot_rsp_dat.local_ring_empty})
            4'b01xx, 4'b1001:begin
                alloc_slot_cold <= 1'b1;
            end
            default:begin
                alloc_slot_cold <= 1'b0;
            end
        endcase 
    end
end

always @(posedge clk) begin
    if((alloc_slot_cstat == ALLOC_SLOT_IDLE) && (!qos2alloc_slot_ok))begin
        alloc_slot_done <= 0;
    end else if(alloc_slot_cstat == ALLOC_SLOT_RSP)begin
        casex ({alloc_slot_rsp_dat.q_stat_doing, alloc_slot_rsp_dat.q_stat_stopping, alloc_slot_rsp_dat.avail_ring_empty, alloc_slot_rsp_dat.local_ring_empty})
            4'b00xx, 4'b1011:begin
                alloc_slot_done <= 1'b1;
            end
            default:begin
                alloc_slot_done <= 1'b0;
            end
        endcase 
    end
end

always @(posedge clk) begin
    if(alloc_slot_rsp_vld)begin
        alloc_slot_err <= alloc_slot_rsp_dat.err_info;
    end
end

assign alloc_slot_local_ring_empty_err = alloc_slot_rsp_vld && ({alloc_slot_rsp_dat.q_stat_doing, alloc_slot_rsp_dat.q_stat_stopping, alloc_slot_rsp_dat.avail_ring_empty, alloc_slot_rsp_dat.local_ring_empty} == 4'b1010);

//Logic Segment3:slot info fifo - slot_info_ff  
yucca_sync_fifo #(
    .DATA_WIDTH (SLOT_INFO_FF_DATA_WIDTH ),
    .FIFO_DEPTH (32                      ),
    .CHECK_ON   (1                       ),
    .CHECK_MODE ("parity"                ),
    .DEPTH_PFULL(24                      ),
    .RAM_MODE   ("dist"                  ),
    .FIFO_MODE  ("fwft"                  )
) u_slot_info_ff(
    .clk             (clk                           ),
    .rst             (rst                           ),
    .wren            (slot_info_ff_wren             ),
    .din             (slot_info_ff_din              ),
    .full            (slot_info_ff_full             ),
    .pfull           (slot_info_ff_pfull            ),
    .overflow        (slot_info_ff_overflow         ),
    .rden            (slot_info_ff_rden             ),
    .dout            (slot_info_ff_dout             ),
    .empty           (slot_info_ff_empty            ),
    .pempty          (                              ),
    .underflow       (slot_info_ff_underflow        ),
    .usedw           (                              ), 
    .parity_ecc_err  (slot_info_ff_parity_ecc_err   )
);
assign slot_info_ff_wren = (alloc_slot_cstat == ALLOC_SLOT_WR) ;
assign slot_info_ff_din  = {alloc_slot_qid_d, alloc_slot_uid_d, alloc_slot_err, alloc_slot_cold, alloc_slot_done, alloc_slot_qos_en_d};
assign slot_info_ff_rden = (arbitration_cstat == ARB_NOTIFY_RSP) && notify_rsp_rdy                               ;
assign {arbiteration_slot_ff_qid, arbiteration_slot_ff_uid, arbiteration_slot_ff_err, arbiteration_slot_ff_cold, arbiteration_slot_ff_done, arbiteration_slot_ff_qos_en} = slot_info_ff_dout ;

//Logic Segment4: arbiteration fsm
always @(posedge clk) begin
    if(rst)begin
        arbitration_cstat <= ARB_IDLE;
    end else begin
        arbitration_cstat <= arbitration_nstat;
    end
end

always @(*)begin
    arbitration_nstat = arbitration_cstat;
    case (arbitration_cstat)
        ARB_IDLE: begin
            if((!slot_info_ff_empty) && ((arbiteration_slot_ff_cold || arbiteration_slot_ff_done) == 1'b1))begin
                arbitration_nstat = ARB_NOTIFY_RSP;
            end else if((!slot_info_ff_empty))begin
                arbitration_nstat = ARB_CTX_REQ;
            end
        end
        ARB_CTX_REQ: begin
            if(!desc_info_ff_pfull)begin
                arbitration_nstat = ARB_CTX_RSP;
            end
        end
        ARB_CTX_RSP: begin
            if(arbiteration_slot_ff_err_d != 0)begin
                arbitration_nstat = ARB_INFO_WR;
            end else if(blk_desc_vld)begin
                arbitration_nstat = ARB_DESC_WAIT;
            end 
        end
        ARB_DESC_WAIT: begin
            if(blk_desc_sbd_d.forced_shutdown || (blk_desc_sbd_d.err_info != 0))begin
                arbitration_nstat = ARB_DESC_RD;
            end else begin
                arbitration_nstat = ARB_DESC_PRO;
            end 
        end
        ARB_INFO_WR: begin
            if(arbiteration_slot_ff_err_d != 0)begin
                arbitration_nstat = ARB_NOTIFY_RSP;
            end else if(blk_desc_eop_d && dma_rd_req_last)begin
                arbitration_nstat = ARB_NOTIFY_RSP;
            end else begin
                arbitration_nstat = ARB_CTX_REQ;
            end
        end
        ARB_DESC_PRO: begin
            if(!blk_desc_dat_d.flags.write && !dma_info_rd_rsp_forcedown_d)begin
                arbitration_nstat = ARB_DMA_CHK;
            end else if((blk_desc_dat_d.flags.write || (!blk_desc_dat_d.flags.write && dma_info_rd_rsp_forcedown_d)) && blk_desc_eop_d)begin
                arbitration_nstat = ARB_QOS_UPDATE;
            end else begin
                arbitration_nstat = ARB_DESC_RD;
            end
        end
        ARB_DMA_CHK: begin
            arbitration_nstat = ARB_DMA_RD;
        end
        ARB_DMA_RD: begin
            //if(desc_rd_data_req_if.sav && inflight_rd_fifo_rdy && inflight_rd_dma_rdy)begin
            if(desc_rd_data_req_if.sav && inflight_rd_fifo_rdy)begin
                if(blk_desc_eop_d && dma_rd_req_last)begin
                    arbitration_nstat = ARB_QOS_UPDATE;
                end else if(!blk_desc_eop_d && dma_rd_req_last)begin
                    arbitration_nstat = ARB_DESC_RD;
                end else begin
                    arbitration_nstat = ARB_INFO_WR;
                end
            end 
        end
        ARB_QOS_UPDATE: begin
            if(qos_update_rdy || (!arbiteration_slot_ff_qos_en_d))begin
                arbitration_nstat = ARB_DESC_RD;
            end 
        end
        ARB_DESC_RD: begin
            arbitration_nstat = ARB_INFO_WR;
        end
        ARB_NOTIFY_RSP: begin
            if(notify_rsp_rdy)begin
                arbitration_nstat = ARB_IDLE;
            end
        end
        default:begin
            arbitration_nstat = ARB_IDLE;
        end
    endcase
end

//err reg
always@(posedge clk) begin
    arbiteration_slot_ff_uid_d    <= arbiteration_slot_ff_uid   ;
    arbiteration_slot_ff_qid_d    <= arbiteration_slot_ff_qid   ;
    arbiteration_slot_ff_cold_d   <= arbiteration_slot_ff_cold  ;
    arbiteration_slot_ff_done_d   <= arbiteration_slot_ff_done  ;
    arbiteration_slot_ff_err_d    <= arbiteration_slot_ff_err   ;
    arbiteration_slot_ff_qos_en_d <= arbiteration_slot_ff_qos_en;
end


//from dma info rsp
always@(posedge clk) begin
    if(rst)begin
        dma_info_rd_rsp_forcedown_d <= 0;
    end else if(arbitration_cstat == ARB_IDLE) begin //slot_err_info no shutdown
        dma_info_rd_rsp_forcedown_d <= 0;
    end else if(dma_info_rd_rsp_vld) begin
        dma_info_rd_rsp_forcedown_d <= dma_info_rd_rsp_forcedown;
    end
end

always@(posedge clk) begin 
    if(rst)begin
        dma_info_rd_rsp_generation_d <= 0 ;
    end else if(dma_info_rd_rsp_vld) begin
        dma_info_rd_rsp_generation_d <= dma_info_rd_rsp_generation;
    end
end

always@(posedge clk) begin
    if(rst)begin
        dma_info_rd_rsp_bdf_d <= 0;
    end else if(dma_info_rd_rsp_vld) begin
        dma_info_rd_rsp_bdf_d <= dma_info_rd_rsp_bdf;
    end
end

//blk_Desc_d
always@(posedge clk) begin
    if(rst)begin
        blk_desc_vld_d <= 0;
    end else if(arbitration_cstat == ARB_CTX_RSP)begin
        blk_desc_vld_d <= blk_desc_vld;
    end
end

always@(posedge clk) begin
    if(arbitration_cstat == ARB_CTX_RSP)begin
        blk_desc_eop_d <= blk_desc_eop;
        blk_desc_dat_d <= blk_desc_dat;
        blk_desc_sbd_d <= blk_desc_sbd;
    end
end

always@(posedge clk) begin
    if(arbitration_cstat == ARB_IDLE)begin
        arbiteration_sop <= 1'b1;
    end else if(arbitration_cstat == ARB_INFO_WR)begin
        if(dma_rd_req_last)begin
            arbiteration_sop <= 1'b1;
        end else begin
            arbiteration_sop <= 1'b0;
        end
    end 
end

always@(posedge clk) begin
    if(arbitration_cstat == ARB_IDLE)begin
        dma_rd_req_current_len <= 'b0;
    end else if((arbitration_cstat == ARB_DESC_PRO) && dma_rd_req_last)begin
        dma_rd_req_current_len <= blk_desc_dat_d.len;
    end else if ((arbitration_cstat == ARB_DESC_PRO) && (!dma_rd_req_last)) begin
        dma_rd_req_current_len <= dma_rd_req_current_len - DMA_MAX_SIZE;
    end
end

always@(posedge clk) begin
    if((arbitration_cstat == ARB_DESC_WAIT) && arbiteration_sop)begin
        dma_rd_req_current_addr <= blk_desc_dat_d.addr;
    end else if(desc_rd_data_req_if.vld)begin
        dma_rd_req_current_addr <= dma_rd_req_current_addr + DMA_MAX_SIZE;
    end
end

always@(posedge clk) begin
    if((arbitration_cstat == ARB_IDLE))begin
        dma_rd_req_last <= 1'b1;
    end else if ((arbitration_cstat == ARB_DESC_WAIT) && arbiteration_err_shutdown) begin
        dma_rd_req_last <= 1'b1;
    end else if(arbitration_cstat == ARB_DMA_CHK)begin // len<=4096
        dma_rd_req_last <= (dma_rd_req_current_len == DMA_MAX_SIZE) || ((dma_rd_req_current_len[DMA_RSP_DESC_PCIE_LENGTH-1:12] == 'd0) && (|dma_rd_req_current_len[11:0]));
    end
end

always@(posedge clk) begin
    if((arbitration_cstat == ARB_IDLE))begin
        current_req_credit <= 'b0;
    end else if(arbitration_cstat == ARB_DMA_CHK)begin
        if((dma_rd_req_current_len == DMA_MAX_SIZE) || ((dma_rd_req_current_len[DMA_RSP_DESC_PCIE_LENGTH-1:12] == 'd0) && (|dma_rd_req_current_len[11:0])))begin
            current_req_credit <= dma_rd_req_current_len[15:EMPTH_WIDTH] + |dma_rd_req_current_len[EMPTH_WIDTH-1:0];
        end else begin
            current_req_credit <= DMA_MAX_SIZE / 32;
        end
    end
end
//in transit
always@(posedge clk) begin
    remaining_infligth <= INTRANSIT_NUM - inflight_rd_fifo;
end
assign inflight_rd_fifo_rdy = (current_req_credit <=  remaining_infligth);
//assign inflight_rd_dma_rdy = inflight_rd_dma < blk_downstream_dma_infligth_q;
//dma info rd req
assign dma_info_rd_req_vld = (arbitration_cstat == ARB_CTX_REQ) && (!desc_info_ff_pfull) && (arbiteration_slot_ff_err_d == 0)       ;
assign dma_info_rd_req_qid = arbiteration_slot_ff_qid_d                                                                             ;
assign arbiteration_err_shutdown = dma_info_rd_rsp_forcedown_d || blk_desc_sbd_d.forced_shutdown || (blk_desc_sbd_d.err_info != 0)  ;

//from blk_desc data
always@(posedge clk) begin
    if(arbitration_cstat == ARB_DESC_WAIT) begin
        arbiteration_next <= arbiteration_next && blk_desc_dat_d.flags.next ;
    end else if(arbitration_cstat == ARB_IDLE)begin
        arbiteration_next <= 1;
    end
end
//desc_info ff wr
assign arbiteration_gen      = dma_info_rd_rsp_generation_d                                                             ;
assign arbiteration_err_info = (arbiteration_slot_ff_err_d != 0) ? arbiteration_slot_ff_err_d : blk_desc_sbd_d.err_info ;
assign arbiteration_ext_shutdown = blk_desc_sbd_d.forced_shutdown                                                       ;
assign arbiteration_int_shutdown = dma_info_rd_rsp_forcedown_d                                                          ;
//dma rd req
always@(posedge clk) begin
    if(arbitration_cstat == ARB_DMA_RD) begin
        //desc_rd_data_req_if.vld <= desc_rd_data_req_if.sav && inflight_rd_fifo_rdy && inflight_rd_dma_rdy;
        desc_rd_data_req_if.vld <= desc_rd_data_req_if.sav && inflight_rd_fifo_rdy ;
    end else begin
        desc_rd_data_req_if.vld <= 0;
    end
end 

always@(posedge clk) begin
    desc_rd_data_req_if.sty                 <= 0                        ;
    desc_rd_data_req_if.desc                <= 0                        ;
    desc_rd_data_req_if.desc.bdf            <= dma_info_rd_rsp_bdf_d    ;
    desc_rd_data_req_if.desc.pcie_addr      <= dma_rd_req_current_addr  ;
    desc_rd_data_req_if.desc.pcie_length    <= dma_rd_req_last ? dma_rd_req_current_len : DMA_MAX_SIZE                       ;
    desc_rd_data_req_if.desc.rd2rsp_loop[DMA_RD_REQ_RSP_LOOP_WIDTH-1:0] <= {arbiteration_slot_ff_qid_d, blk_desc_sbd_d.ring_id};
end 
//desc data rd
assign blk_desc_rdy = (arbitration_cstat == ARB_DESC_RD);
//blk_chain_fst_seg_wr  ext_err!=0 || ext_shutdown || netx==0
assign blk_chain_fst_seg_wr_vld = (arbitration_cstat == ARB_DESC_RD)                                                                ;
assign blk_chain_fst_seg_wr_qid = arbiteration_slot_ff_qid_d                                                                        ;
assign blk_chain_fst_seg_wr_dat = (!blk_desc_dat_d.flags.next) || blk_desc_sbd_d.forced_shutdown || (blk_desc_sbd_d.err_info != 0)  ;
//qos update
assign qos_update_vld = (arbitration_cstat == ARB_QOS_UPDATE) && arbiteration_slot_ff_qos_en_d ;
assign qos_update_uid = arbiteration_slot_ff_uid_d                    ;
assign qos_update_len = blk_desc_sbd_d.total_buf_length               ;
assign qos_update_pkt_num = arbiteration_next ? 0 : 1                 ;
//notify rsp
assign notify_rsp_vld  = (arbitration_cstat == ARB_NOTIFY_RSP)        ;
assign notify_rsp_qid  = arbiteration_slot_ff_qid_d                   ;
assign notify_rsp_cold = arbiteration_slot_ff_cold_d                  ;
assign notify_rsp_done = arbiteration_slot_ff_done_d                  ;
//Logic Segment5:desc info fifo - desc_info_ff  
yucca_sync_fifo #(
    .DATA_WIDTH (DESC_INFO_FF_DATA_WIDTH ),
    .FIFO_DEPTH (32                      ),
    .CHECK_ON   (1                       ),
    .CHECK_MODE ("parity"                ),
    .DEPTH_PFULL(24                      ),
    .RAM_MODE   ("dist"                  ),
    .FIFO_MODE  ("fwft"                  )
) u_desc_info_ff(
    .clk             (clk                           ),
    .rst             (rst                           ),
    .wren            (desc_info_ff_wren             ),
    .din             (desc_info_ff_din              ),
    .full            (desc_info_ff_full             ),
    .pfull           (desc_info_ff_pfull            ),
    .overflow        (desc_info_ff_overflow         ),
    .rden            (desc_info_ff_rden             ),
    .dout            (desc_info_ff_dout             ),
    .empty           (desc_info_ff_empty            ),
    .pempty          (                              ),
    .underflow       (desc_info_ff_underflow        ),
    .usedw           (                              ), 
    .parity_ecc_err  (desc_info_ff_parity_ecc_err   )
);
assign desc_info_ff_wren = (arbitration_cstat == ARB_INFO_WR)               ;
assign desc_info_ff_din.desc_info_qid          = arbiteration_slot_ff_qid_d ;
assign desc_info_ff_din.desc_info_gen          = arbiteration_gen           ;
assign desc_info_ff_din.desc_info_err_info     = arbiteration_err_info      ;
assign desc_info_ff_din.desc_info_ring_id      = blk_desc_sbd_d.ring_id     ;
assign desc_info_ff_din.desc_info_flags        = blk_desc_dat_d.flags       ;
assign desc_info_ff_din.desc_info_addr         = blk_desc_dat_d.addr        ;
assign desc_info_ff_din.desc_info_length       = blk_desc_dat_d.len         ;
assign desc_info_ff_din.desc_info_ext_shutdown = arbiteration_ext_shutdown  ;
assign desc_info_ff_din.desc_info_int_shutdown = arbiteration_int_shutdown  ;
assign desc_info_ff_din.desc_info_eop          = dma_rd_req_last            ;
assign desc_info_ff_rden = (rsp_cstat == RSP_ARB)                           ;

//Logic Segment7:pkt fifo
//yucca_sync_fifo #(
//    .DATA_WIDTH (PKT_FF_WIDTH           ),
//    .FIFO_DEPTH (PKT_FF_DEPTH           ),
//    .CHECK_ON   (1                      ),
//    .CHECK_MODE ("parity"               ),
//    //.DEPTH_PFULL(24                     ),
//    .RAM_MODE   ("blk"                  ),
//    .FIFO_MODE  ("fwft"                 )
//) u_data_pkt_ff(
//    .clk             (clk                         ),
//    .rst             (rst                         ),
//    .wren            (data_pkt_ff_wren            ),
//    .din             (data_pkt_ff_din             ),
//    .full            (data_pkt_ff_full            ),
//    .pfull           (data_pkt_ff_pfull           ),
//    .overflow        (data_pkt_ff_overflow        ),
//    .rden            (data_pkt_ff_rden            ),
//    .dout            (data_pkt_ff_dout            ),
//    .empty           (data_pkt_ff_empty           ),
//    .pempty          (                            ),
//    .underflow       (data_pkt_ff_underflow       ),
//    .usedw           (                            ), 
//    .parity_ecc_err  (data_pkt_ff_parity_ecc_err  )
//);
pkt_fifo #(
    .DATA_WIDTH  (PKT_FF_WIDTH    ),
    .FIFO_DEPTH  (PKT_FF_DEPTH    ),
    .CHECK_ON    (1               )
) u_data_pkt_ff (
    .clk            (clk                        ),
    .rst            (rst                        ),   
    .wren           (data_pkt_ff_wren           ),
    .din            (data_pkt_ff_din            ),
    .wr_end         (data_pkt_ff_wr_end         ),
    .wr_drop        (1'b0                       ),
    .full           (data_pkt_ff_full           ),
    .pfull          (data_pkt_ff_pfull          ),
    .overflow       (data_pkt_ff_overflow       ),
    .rden           (data_pkt_ff_rden           ),
    .dout           (data_pkt_ff_dout           ),
    .empty          (data_pkt_ff_empty          ),
    .pempty         (                           ),
    .underflow      (data_pkt_ff_underflow      ),
    .usedw          (                           ),
    .parity_ecc_err (data_pkt_ff_parity_ecc_err )
);
assign data_pkt_ff_din    = {desc_rd_data_rsp_if.sop, desc_rd_data_rsp_if.eop, desc_rd_data_rsp_if.err, desc_rd_data_rsp_if.data, desc_rd_data_rsp_if.sty, 
                        desc_rd_data_rsp_if.mty, desc_rd_data_rsp_if.desc.rd2rsp_loop[DMA_RD_REQ_RSP_LOOP_WIDTH-1:0], desc_rd_data_rsp_if.desc.pcie_length};

assign data_pkt_ff_wren   = desc_rd_data_rsp_if.vld;
assign data_pkt_ff_wr_end = desc_rd_data_rsp_if.eop;

assign {pkt_ff2rsp_sop, pkt_ff2rsp_eop, pkt_ff2rsp_err, pkt_ff2rsp_data, pkt_ff2rsp_sty, 
        pkt_ff2rsp_mty, desc_rd_rsp_desc_rsp_loop, desc_rd_rsp_desc_pcie_length} = data_pkt_ff_dout ;
assign data_pkt_ff_rden   = (!data_pkt_ff_empty) && (rsp_cstat == RSP_RD) && blk2beq_if.sav         ;
//sim for pkt_fifo_pfull
assign dma_pkt_ff_rdy = 1'b1;

always @(posedge clk) begin
    if(rst)begin
        dma_rd_rsp_loop_match_err <= 0;
    end else begin
        dma_rd_rsp_loop_match_err <= (rsp_cstat == RSP_RD) && (desc_rd_rsp_desc_rsp_loop != {desc_info_ff_dout.desc_info_qid, desc_info_ff_dout.desc_info_ring_id});
    end
end
//Logic Segment8:desc rsp fsm
always @(posedge clk) begin
    if(rst)begin
        rsp_cstat <= RSP_IDLE;
    end else begin
        rsp_cstat <= rsp_nstat;
    end
end

always @(*)begin
    rsp_nstat = rsp_cstat;
    case (rsp_cstat)
        RSP_IDLE: begin
            if((!desc_info_ff_empty) && blk2beq_if.sav)begin
                rsp_nstat = RSP_HDR;
            end
        end
        RSP_HDR: begin
            if(rsp_hdr_cnt == BUFFER_HDR_CYCLES - 1)begin
                if((desc_info_ff_dout.desc_info_err_info != 0) || desc_info_ff_dout.desc_info_ext_shutdown || desc_info_ff_dout.desc_info_int_shutdown || desc_info_ff_dout.desc_info_flags.write)begin
                    rsp_nstat = RSP_ARB;
                end else begin
                    rsp_nstat = RSP_WAIT;
                end
            end
        end
        RSP_WAIT: begin
            if(desc_info_ff_dout.desc_info_int_shutdown && blk2beq_if.sav)begin
                rsp_nstat = RSP_DMA_SHUTDOWN;
            end else if(!data_pkt_ff_empty && !desc_info_ff_dout.desc_info_int_shutdown && dma_pkt_ff_rdy)begin
                rsp_nstat = RSP_RD;
            end
        end
        RSP_RD: begin
            if(data_pkt_ff_rden && pkt_ff2rsp_eop)begin
                if (dma_rd_rsp_err_d) begin
                    rsp_nstat = RSP_ERR_CTX;
                end else begin
                    rsp_nstat = RSP_ARB;
                end
            end
        end
        RSP_ARB: begin
            if((desc_info_ff_dout.desc_info_err_info != 0) || desc_info_ff_dout.desc_info_ext_shutdown || (desc_info_ff_dout.desc_info_eop && (!desc_info_ff_dout.desc_info_flags.next)))begin
                rsp_nstat = RSP_CTX_RD;
            end else if(!desc_info_ff_dout.desc_info_eop) begin
                rsp_nstat = RSP_WAIT;
            end else begin 
                rsp_nstat = RSP_IDLE;
            end
        end
        RSP_CTX_RD: begin
            rsp_nstat = RSP_CTX_RSP;
        end
        RSP_CTX_RSP: begin
            if(blk_ds_ptr_rd_rsp_vld)begin
                if(slot_desc_err_d != 0)begin
                    rsp_nstat = RSP_ERR_CTX;
                end else begin
                    rsp_nstat = RSP_IDLE;
                end
            end
        end
        RSP_ERR_CTX: begin
            if(blk_ds_err_info_wr_rdy)begin
                if(dma_rd_rsp_err_d != 0)begin
                    rsp_nstat = RSP_ARB;
                end else begin
                    rsp_nstat = RSP_IDLE;
                end
            end
        end
        RSP_DMA_SHUTDOWN: begin
            if((rsp_hdr_cnt == BUFFER_HDR_CYCLES - 1))begin
                rsp_nstat = RSP_ARB;
            end
        end
        default:begin
            rsp_nstat = rsp_cstat;
        end
    endcase
end

always @(posedge clk) begin
    if(rst)begin
        rsp_hdr_cnt <= 'h0;
    end else if((rsp_cstat == RSP_IDLE) || (rsp_cstat == RSP_WAIT))begin
        rsp_hdr_cnt <= 'h0;
    end else if((rsp_cstat == RSP_HDR) || (rsp_cstat == RSP_DMA_SHUTDOWN))begin
        rsp_hdr_cnt <= rsp_hdr_cnt + 1'b1;
    end 
end

//inflight_rd_fifo 500
always @(posedge clk) begin
    if(rst)begin
        data_pkt_ff_rden_d <= 1'b0;
    end else begin
        data_pkt_ff_rden_d <= data_pkt_ff_rden;
    end
end

always @(posedge clk) begin
    if(rst)begin
        inflight_rd_fifo <= 'h0;
    end else if(desc_rd_data_req_if.vld && (!data_pkt_ff_rden_d))begin
        inflight_rd_fifo <= inflight_rd_fifo + desc_rd_data_req_if.desc.pcie_length[15:EMPTH_WIDTH] + |desc_rd_data_req_if.desc.pcie_length[EMPTH_WIDTH-1:0];
    end else if(!(desc_rd_data_req_if.vld) && data_pkt_ff_rden_d)begin
        inflight_rd_fifo <= inflight_rd_fifo - 1'b1;
    end else if(desc_rd_data_req_if.vld && data_pkt_ff_rden_d)begin
        inflight_rd_fifo <= inflight_rd_fifo + desc_rd_data_req_if.desc.pcie_length[15:EMPTH_WIDTH] + |desc_rd_data_req_if.desc.pcie_length[EMPTH_WIDTH-1:0] - 1;
    end
end
//inflight_rd_dma 
//always @(posedge clk) begin
//    if(rst)begin
//        inflight_rd_dma <= 'h0;
//    end else if(desc_rd_data_req_if.vld && (!data_pkt_ff_wren))begin
//        inflight_rd_dma <= inflight_rd_dma + desc_rd_data_req_if.desc.pcie_length[15:EMPTH_WIDTH] + |desc_rd_data_req_if.desc.pcie_length[EMPTH_WIDTH-1:0];
//    end else if(!(desc_rd_data_req_if.vld) && data_pkt_ff_wren)begin
//        inflight_rd_dma <= inflight_rd_dma - 1'b1;
//    end else if(desc_rd_data_req_if.vld && data_pkt_ff_wren)begin
//        inflight_rd_dma <= inflight_rd_dma + desc_rd_data_req_if.desc.pcie_length[15:EMPTH_WIDTH] + |desc_rd_data_req_if.desc.pcie_length[EMPTH_WIDTH-1:0] - 1;
//    end
//end
//dma_rd_rsp_err
assign dma_rd_rsp_err_info.fatal      = 1'b1                                ;
assign dma_rd_rsp_err_info.err_code   = VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR   ;
//buffer hdr err
always @(posedge clk) begin
    if(rsp_cstat == RSP_IDLE)begin
        buffer_hdr_err_d <= desc_info_ff_dout.desc_info_err_info;
    end else if(rsp_cstat == RSP_WAIT)begin
        if(pkt_ff2rsp_err)begin
            buffer_hdr_err_d <= dma_rd_rsp_err_info;
        end else begin
            buffer_hdr_err_d <= desc_info_ff_dout.desc_info_err_info;
        end
    end
end

always @(posedge clk) begin
    if(rsp_cstat == RSP_IDLE)begin
        slot_desc_err_d <= desc_info_ff_dout.desc_info_err_info;
    end
end
always @(posedge clk) begin
    if(rsp_cstat == RSP_IDLE)begin
        dma_rd_rsp_err_d <=  'b0;
    end else if((rsp_cstat == RSP_WAIT) && !desc_info_ff_dout.desc_info_int_shutdown)begin
        if(pkt_ff2rsp_err)begin
            dma_rd_rsp_err_d <= dma_rd_rsp_err_info;
        end else begin
            dma_rd_rsp_err_d <=  'b0;
        end
    end
end


always @(posedge clk) begin
    if(rst)begin
        beq_sbd_end_of_pkt <= 1'b0;
    end else if((rsp_cstat == RSP_IDLE))begin
        if((desc_info_ff_dout.desc_info_err_info == 0) && !desc_info_ff_dout.desc_info_ext_shutdown && !desc_info_ff_dout.desc_info_int_shutdown && !desc_info_ff_dout.desc_info_flags.write)begin
            beq_sbd_end_of_pkt <= 1'b0;
        end else begin
            beq_sbd_end_of_pkt <= desc_info_ff_dout.desc_info_eop;
        end
    end else if((rsp_cstat == RSP_WAIT))begin
        beq_sbd_end_of_pkt <= desc_info_ff_dout.desc_info_eop;
    end
end


//buffer hdr
assign buffer_hdr.resv0               =  'b0                                ;
assign buffer_hdr.reserved            =  'b0                                ;
assign buffer_hdr.magic_num           = BLK_BUFFER_HDR_MAGIC_NUM            ;
assign buffer_hdr.host_buffer_length  = desc_info_ff_dout.desc_info_length  ;
assign buffer_hdr.host_buffer_addr    = desc_info_ff_dout.desc_info_addr    ;
assign buffer_hdr.virtio_flags        = desc_info_ff_dout.desc_info_flags   ;
assign buffer_hdr.virtio_desc_index   = desc_info_ff_dout.desc_info_ring_id ;
assign buffer_hdr.vq_gen              = desc_info_ff_dout.desc_info_gen     ;
assign buffer_hdr.vq_qid              = desc_info_ff_dout.desc_info_qid     ;
assign buffer_hdr.resv1               =  'b0                                ;

assign blk2beq_shutdown = desc_info_ff_dout.desc_info_ext_shutdown || desc_info_ff_dout.desc_info_int_shutdown;
//beq sbd
assign blk2beq_sbd.user1        =  'b0                             ;
assign blk2beq_sbd.user0[39:32] = buffer_hdr_err_d                 ;   //err_code
assign blk2beq_sbd.user0[31:27] =  'b0                             ;   //reserved
assign blk2beq_sbd.user0[26]    = blk2beq_shutdown                 ;   // forced_shutdown
assign blk2beq_sbd.user0[25]    = beq_sbd_end_of_pkt               ;   // end of io
assign blk2beq_sbd.user0[24]    = (rsp_cstat == RSP_HDR)           ;  //start of io
assign blk2beq_sbd.user0[23:16] = desc_info_ff_dout.desc_info_gen  ;
assign blk2beq_sbd.user0[15:0]  = desc_info_ff_dout.desc_info_qid  ;
assign blk2beq_sbd.qid          = desc_info_ff_dout.desc_info_qid  ;
assign blk2beq_sbd.length       = (rsp_cstat == RSP_RD) ? desc_rd_rsp_desc_pcie_length : BUFFER_HDR_SIZE;

//beq if
always @(posedge clk) begin
    if(rst)begin
        blk2beq_if.vld <= 0;
    end else begin
        blk2beq_if.vld <= (rsp_cstat == RSP_HDR) || ((!data_pkt_ff_empty) && (rsp_cstat == RSP_RD) && blk2beq_if.sav ) || (rsp_cstat == RSP_DMA_SHUTDOWN);
    end
end
always @(posedge clk) begin
    blk2beq_if.sbd  <= blk2beq_sbd                                                                              ;
    blk2beq_if.sop  <= ((rsp_hdr_cnt == 0) &&( (rsp_cstat == RSP_HDR) || (rsp_cstat == RSP_DMA_SHUTDOWN))) || (pkt_ff2rsp_sop && data_pkt_ff_rden)   ;
    blk2beq_if.sty  <= ((rsp_cstat == RSP_HDR) || (rsp_cstat == RSP_DMA_SHUTDOWN)) ? 0 : pkt_ff2rsp_sty                                              ;                                                                                    ;
    blk2beq_if.eop  <= ((rsp_cstat == RSP_HDR) || (rsp_cstat == RSP_DMA_SHUTDOWN)) ? (rsp_hdr_cnt == BUFFER_HDR_CYCLES - 1) : pkt_ff2rsp_eop         ;
    blk2beq_if.mty  <= ((rsp_cstat == RSP_HDR) || (rsp_cstat == RSP_DMA_SHUTDOWN)) ? BUFFER_HDR_SIZE % (DATA_WIDTH/8) : pkt_ff2rsp_mty               ;
    blk2beq_if.data <= (rsp_hdr_cnt == 0) && (rsp_cstat == RSP_HDR) ? (buffer_hdr | {DATA_WIDTH{1'b0}}) : (rsp_cstat == RSP_RD) ? pkt_ff2rsp_data : {DATA_WIDTH{1'b0}};
end

//blk ds ptr
always @(posedge clk) begin
    if(rsp_cstat == RSP_IDLE)begin
        desc_info_ff_out_qid_d <= 0;
    end else if((rsp_cstat == RSP_ARB) || (rsp_cstat == RSP_RD))begin
        desc_info_ff_out_qid_d <= desc_info_ff_dout.desc_info_qid;
    end
end

assign blk_ds_ptr_rd_req_vld = (rsp_cstat == RSP_CTX_RD);
assign blk_ds_ptr_rd_req_qid = desc_info_ff_out_qid_d   ;
always @(posedge clk) begin
    if(rst)begin
        blk_ds_ptr_wr_vld <= 0;
    end else begin
        blk_ds_ptr_wr_vld <= blk_ds_ptr_rd_rsp_vld;
    end
end
always @(posedge clk) begin
    blk_ds_ptr_wr_qid <= desc_info_ff_out_qid_d     ;
    blk_ds_ptr_wr_dat <= blk_ds_ptr_rd_rsp_dat + 1  ;
end
//ctx err wr
assign blk_ds_err_info_wr_vld = (rsp_cstat == RSP_ERR_CTX)                  ;
assign blk_ds_err_info_wr_qid = {VIRTIO_BLK_TYPE, desc_info_ff_out_qid_d}   ;
assign blk_ds_err_info_wr_dat = buffer_hdr_err_d                            ;

//dfx
virtio_blk_downstream_dfx #(
    .ADDR_WIDTH  (REG_ADDR_WIDTH    ),
    .DATA_WIDTH  (REG_DATA_WIDTH    )
) u_virtio_blk_downstream_dfx(
    .clk                                                                            (clk                            ),
    .rst                                                                            (rst                            ),
    .blk_downstream_err_blk_downstream_err_we                                       (blk_downstream_err_we          ),
    .blk_downstream_err_blk_downstream_err_wdata                                    (blk_downstream_err_wdata       ),
    .blk_downstream_err_blk_downstream_err_q                                        (blk_downstream_err_q           ),
    .blk_downstream_ff_stat_blk_downstream_ff_stat_wdata                            (blk_downstream_ff_stat_wdata   ),
    .blk_downstream_fsm_stat_blk_downstream_fsm_stat_wdata                          (blk_downstream_fsm_stat_wdata  ),
    .blk_downstream_err_cnt_blk_downstream_err_cnt_we                               (blk_downstream_err_cnt_we      ),
    .blk_downstream_err_cnt_blk_downstream_err_cnt_wdata                            (blk_downstream_err_cnt_wdata   ),
    .blk_downstream_err_cnt_blk_downstream_err_cnt_q                                (blk_downstream_err_cnt_q       ),
    .blk_downstream_if_cnt_blk_downstream_if_cnt_we                                 (blk_downstream_if_cnt_we       ),
    .blk_downstream_if_cnt_blk_downstream_if_cnt_wdata                              (blk_downstream_if_cnt_wdata    ),
    .blk_downstream_if_cnt_blk_downstream_if_cnt_q                                  (blk_downstream_if_cnt_q        ),
    .blk_desc_hs_related_cnt_blk_desc_hs_related_cnt_wdata                          (blk_desc_hs_related_cnt_wdata  ),
    .dma_rd_req_bp_related_cnt_dma_rd_req_bp_related_cnt_wdata                      (dma_rd_req_bp_related_cnt_wdata),
    .dma_rd_rsp_bp_vdata_cnt_dma_rd_rsp_bp_vdata_cnt_wdata                          (dma_rd_rsp_bp_vdata_cnt_wdata  ),
    .blk_downstream_dma_inflight_threshold_blk_downstream_dma_inflight_threshold_q  (blk_downstream_dma_infligth_q  ),
    .csr_if                                                                         (csr_if                         )
);
genvar idx;
generate
    for(idx=0;idx<14;idx++)begin
            assert property (@(posedge clk) disable iff (rst) (~(blk_downstream_err_wdata[idx]===1'b1)))
                else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, err:%d, id:%d", $time, blk_downstream_err_wdata[idx], idx));
    end
endgenerate
//err
always @(posedge clk) begin
    blk_downstream_err_we <= | ({alloc_slot_local_ring_empty_err, dma_rd_rsp_loop_match_err, alloc_slot_qid_match_err, 
                                data_pkt_ff_underflow, data_pkt_ff_overflow, data_pkt_ff_parity_ecc_err,
                                desc_info_ff_underflow, desc_info_ff_overflow, desc_info_ff_parity_ecc_err,
                                slot_info_ff_underflow, slot_info_ff_overflow, slot_info_ff_parity_ecc_err});
end
always @(posedge clk) begin
    blk_downstream_err_wdata  <= {dma_rd_rsp_loop_match_err, alloc_slot_qid_match_err, 
                                data_pkt_ff_underflow, data_pkt_ff_overflow, data_pkt_ff_parity_ecc_err,
                                desc_info_ff_underflow, desc_info_ff_overflow, desc_info_ff_parity_ecc_err,
                                slot_info_ff_underflow, slot_info_ff_overflow, slot_info_ff_parity_ecc_err} | blk_downstream_err_q  ;
end
//status
always @(posedge clk) begin
    blk_downstream_ff_stat_wdata  <= {blk2beq_if.sav, 
                                    data_pkt_ff_pfull, data_pkt_ff_empty, data_pkt_ff_full,
                                    desc_info_ff_pfull, desc_info_ff_empty, desc_info_ff_full,
                                    slot_info_ff_pfull, slot_info_ff_empty, slot_info_ff_full} ;
end

always @(posedge clk) begin
    blk_downstream_fsm_stat_wdata  <= {rsp_cstat, rsp_nstat, arbitration_cstat, arbitration_nstat,
                                    alloc_slot_cstat, alloc_slot_nstat, qos_cstat, qos_nstat} ;
end
//Logic Segment8:Performance probes
`ifdef PMON_EN
assign mon_tick_interval = MS_100_CLEAN_CNT;
assign backpressure_vld  = {desc_rd_data_rsp_if.vld, desc_rd_data_req_if.vld};
assign backpressure_sav  = {1'b1, desc_rd_data_req_if.sav};
assign handshake_vld     = {1'b0, blk_desc_vld};
assign handshake_rdy     = {1'b0, blk_desc_rdy};

performance_probe #(
    .PP_IF_NUM   (PP_IF_NUM ),
    .CNT_WIDTH   (CNT_WIDTH )
) u_blk_ds_performance_probe(
    .clk                    (clk                    ),
    .rst                    (rst                    ),
    .backpressure_vld       (backpressure_vld       ),
    .backpressure_sav       (backpressure_sav       ),
    .handshake_vld          (handshake_vld          ),
    .handshake_rdy          (handshake_rdy          ),
    .mon_tick_interval      (mon_tick_interval      ),
    .backpressure_block_cnt (backpressure_block_cnt ),
    .backpressure_vdata_cnt (backpressure_vdata_cnt ),
    .handshake_block_cnt    (handshake_block_cnt    ),
    .handshake_vdata_cnt    (handshake_vdata_cnt    )
);
`endif
//err cnt
always @(posedge clk) begin
    blk_downstream_err_cnt_en[0] <= alloc_slot_rsp_vld && alloc_slot_rsp_rdy && alloc_slot_rsp_dat.err_info != 0;
    blk_downstream_err_cnt_en[1] <= (arbitration_cstat == ARB_DESC_RD) && (blk_desc_sbd_d.err_info != 0);
    blk_downstream_err_cnt_en[2] <= desc_rd_data_rsp_if.vld && desc_rd_data_rsp_if.eop && desc_rd_data_rsp_if.err;
end
//if cnt
always @(posedge clk) begin
    blk_downstream_if_cnt_en[0] <= blk2beq_if.vld && blk2beq_if.eop;
    blk_downstream_if_cnt_en[1] <= blk_desc_rdy && blk_desc_vld;
    blk_downstream_if_cnt_en[2] <= (rsp_hdr_cnt == 0) && (rsp_cstat == RSP_HDR);
    blk_downstream_if_cnt_en[3] <= data_pkt_ff_rden && pkt_ff2rsp_eop;
end

assign blk_downstream_err_cnt_we           = |blk_downstream_err_cnt_en;
assign blk_downstream_err_cnt_wdata[15:0]  = blk_downstream_err_cnt_en[0] ? blk_downstream_err_cnt_q[15:0]  + 1 : blk_downstream_err_cnt_q[15:0]  ;
assign blk_downstream_err_cnt_wdata[31:16] = blk_downstream_err_cnt_en[1] ? blk_downstream_err_cnt_q[31:16] + 1 : blk_downstream_err_cnt_q[31:16] ;
assign blk_downstream_err_cnt_wdata[47:32] = blk_downstream_err_cnt_en[2] ? blk_downstream_err_cnt_q[47:32] + 1 : blk_downstream_err_cnt_q[47:32] ;
assign blk_downstream_err_cnt_wdata[REG_DATA_WIDTH-1:48] = 'b0;

assign blk_downstream_if_cnt_we           = |blk_downstream_if_cnt_en;
assign blk_downstream_if_cnt_wdata[7:0]   = blk_downstream_if_cnt_en[0] ? blk_downstream_if_cnt_q[7:0]   + 1 : blk_downstream_if_cnt_q[7:0]   ;
assign blk_downstream_if_cnt_wdata[15:8]  = blk_downstream_if_cnt_en[1] ? blk_downstream_if_cnt_q[15:8]  + 1 : blk_downstream_if_cnt_q[15:8]  ;
assign blk_downstream_if_cnt_wdata[23:16] = blk_downstream_if_cnt_en[2] ? blk_downstream_if_cnt_q[23:16] + 1 : blk_downstream_if_cnt_q[23:16] ;
assign blk_downstream_if_cnt_wdata[31:24] = blk_downstream_if_cnt_en[3] ? blk_downstream_if_cnt_q[31:24] + 1 : blk_downstream_if_cnt_q[31:24] ;
assign blk_downstream_if_cnt_wdata[REG_DATA_WIDTH-1:32] = 'b0;

`ifdef PMON_EN
assign blk_desc_hs_related_cnt_wdata   = {'h0, handshake_vdata_cnt[0 * CNT_WIDTH +: CNT_WIDTH],{(32-CNT_WIDTH){1'h0}}, handshake_block_cnt[0 * CNT_WIDTH +: CNT_WIDTH]} ;
assign dma_rd_req_bp_related_cnt_wdata = {'h0, backpressure_vdata_cnt[0 * CNT_WIDTH +: CNT_WIDTH],{(32-CNT_WIDTH){1'h0}}, backpressure_block_cnt[0 * CNT_WIDTH +: CNT_WIDTH]} ;
assign dma_rd_rsp_bp_vdata_cnt_wdata   = {'h0, backpressure_vdata_cnt[1 * CNT_WIDTH +: CNT_WIDTH]} ;
`else
assign blk_desc_hs_related_cnt_wdata   = 'b0 ;
assign dma_rd_req_bp_related_cnt_wdata = 'b0 ;
assign dma_rd_rsp_bp_vdata_cnt_wdata   = 'b0 ;
`endif

// synthesis translate_off
logic  [3:0]        dbg_dma_rd_req_cnt;
logic               dbg_dma_rd_req_err;
always @(posedge clk) begin
    if(rst) begin
        dbg_dma_rd_req_cnt  <= 4'd0;
        dbg_dma_rd_req_err  <= 1'b0;
    end else begin
        if(desc_rd_data_req_if.vld) begin
            dbg_dma_rd_req_cnt <= 4'd0;
            dbg_dma_rd_req_err <= (dbg_dma_rd_req_cnt <= 4'd4) ? 1'b1 : 1'b0;
        end else if(dbg_dma_rd_req_cnt < 4'd8) begin
            dbg_dma_rd_req_cnt <= dbg_dma_rd_req_cnt + 4'd1;
            dbg_dma_rd_req_err <= 1'b0; 
        end
        else begin
            dbg_dma_rd_req_cnt <= dbg_dma_rd_req_cnt;
            dbg_dma_rd_req_err <= 1'b0;
        end
    end
end

assert property (@(posedge clk) disable iff(rst) not (dbg_dma_rd_req_err)) 
    else begin
    $fatal(1, "[DMA Read Request Error] Adjacent requests interval ≤4 clock cycles! Current counter value: %0d", dbg_dma_rd_req_cnt);
end
// synthesis translate_on

endmodule