/******************************************************************************
 * 文件名称 : virtio_desc_engine_slot_mgmt.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/07/14
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/14     Joe Jiang   初始化版本
 ******************************************************************************/
 `include "virtio_define.svh"
module virtio_desc_engine_slot_mgmt #(
    parameter TXQ                            = 1,
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

    input  logic                                                alloc_slot_req_vld,
    output logic                                                alloc_slot_req_rdy,
    input  logic [9:0]                                          alloc_slot_req_dev_id,
    input  logic [PKT_ID_WIDTH-1:0]                                          alloc_slot_req_pkt_id,
    input  virtio_vq_t                                          alloc_slot_req_vq,

    output logic                                                alloc_slot_rsp_vld,
    output virtio_desc_eng_slot_rsp_t                           alloc_slot_rsp_dat,
    input  logic                                                alloc_slot_rsp_rdy,

    output logic                                                avail_id_req_vld,
    input  logic                                                avail_id_req_rdy,
    output logic [3:0]                                          avail_id_req_nid,
    output virtio_vq_t                                          avail_id_req_vq,

    input  logic                                                avail_id_rsp_vld,
    output logic                                                avail_id_rsp_rdy,
    input  logic                                                avail_id_rsp_eop,
    input  virtio_avail_id_rsp_dat_t                            avail_id_rsp_dat,

    output logic                                                slot_submit_vld,
    output logic [SLOT_WIDTH-1:0]                               slot_submit_slot_id,
    output virtio_vq_t                                          slot_submit_vq,
    output logic [DEV_ID_WIDTH-1:0]                             slot_submit_dev_id,
    output logic [PKT_ID_WIDTH-1:0]                             slot_submit_pkt_id,
    output logic [15:0]                                         slot_submit_ring_id,
    output logic [15:0]                                         slot_submit_avail_idx,
    output virtio_err_info_t                                    slot_submit_err,
    input  logic                                                slot_submit_rdy,

    input  logic                                                slot_cpl_vld,
    input  logic [SLOT_WIDTH-1:0]                               slot_cpl_slot_id,
    input  virtio_vq_t                                          slot_cpl_vq,
    output logic                                                slot_cpl_sav,

    output logic                                                rd_desc_req_vld,
    output logic [SLOT_WIDTH-1:0]                               rd_desc_req_slot_id,
    input  logic                                                rd_desc_req_rdy,

    input  logic                                                rd_desc_rsp_vld,
    input  virtio_desc_eng_desc_rsp_sbd_t                       rd_desc_rsp_sbd,
    input  logic                                                rd_desc_rsp_sop,
    input  logic                                                rd_desc_rsp_eop,
    input  virtq_desc_t                                         rd_desc_rsp_dat,
    output logic                                                rd_desc_rsp_rdy,

    output logic                                                desc_rsp_vld,
    output virtio_desc_eng_desc_rsp_sbd_t                       desc_rsp_sbd,
    output logic                                                desc_rsp_sop,
    output logic                                                desc_rsp_eop,
    output virtq_desc_t                                         desc_rsp_dat,
    input  logic                                                desc_rsp_rdy, 

    output logic                                                limit_per_queue_rd_req_vld,
    output logic [7:0]                                          limit_per_queue_rd_req_qid,
    input  logic                                                limit_per_queue_rd_rsp_vld,
    input  logic [7:0]                                          limit_per_queue_rd_rsp_dat,

    output logic                                                limit_per_dev_rd_req_vld,
    output logic [9:0]                                          limit_per_dev_rd_req_dev_id,
    input  logic                                                limit_per_dev_rd_rsp_vld,
    input  logic [7:0]                                          limit_per_dev_rd_rsp_dat,
    output logic [27:0]                                         dfx_err,
    output logic [19:0]                                         dfx_status,
    output logic [7:0]                                          alloc_slot_req_cnt, 
    output logic [7:0]                                          alloc_slot_rsp_cnt, 
    output logic [7:0]                                          alloc_slot_limit_cnt, 
    output logic [7:0]                                          alloc_slot_ok_cnt,
    output logic [7:0]                                          avail_id_req_cnt, 
    output logic [7:0]                                          avail_id_rsp_cnt, 
    output logic [7:0]                                          avail_id_rsp_pkt_cnt, 
    output logic [7:0]                                          avail_id_got_id_cnt, 
    output logic [7:0]                                          avail_id_err_cnt,
    output logic [7:0]                                          slot_submit_cnt, 
    output logic [7:0]                                          slot_cpl_cnt,
    output logic [7:0]                                          rd_desc_req_cnt, 
    output logic [7:0]                                          rd_desc_rsp_cnt, 
    output logic [7:0]                                          rd_desc_rsp_pkt_cnt, 
    output logic [7:0]                                          slot_err_cnt,
    output logic [7:0]                                          desc_rsp_cnt, 
    output logic [7:0]                                          desc_rsp_pkt_cnt,
    output logic [15:0]                                         used_slot_num
);
    typedef struct packed{
        logic                       limit;
        logic  [3:0]                nid;
        logic [DEV_ID_WIDTH-1:0]    dev_id;
        logic [PKT_ID_WIDTH-1:0]    pkt_id;
        virtio_vq_t                 vq;
    }order_t;

    typedef struct packed{
        logic [DEV_ID_WIDTH-1:0]  dev_id;
        logic [Q_WIDTH-1:0]       qid;
        logic [3:0]               nid;
    }not_submit_t;

    enum logic [4:0]  { 
        PRE_PROCESS_IDLE    = 5'b00001,
        PRE_PROCESS_CTX     = 5'b00010,
        PRE_PROCESS_CALC1   = 5'b00100,
        PRE_PROCESS_CALC2   = 5'b01000,
        PRE_PROCESS_WR      = 5'b10000
    } pre_process_cstat, pre_process_cstat_d, pre_process_nstat;

    enum logic [3:0]  { 
        SUBMIT_IDLE             = 4'b0001,
        SUBMIT_SLOT             = 4'b0010,
        SUBMIT_WAIT_ALLOC_RSP   = 4'b0100,
        SUBMIT_WAIT_SUBMIT_RSP  = 4'b1000
    } submit_cstat, submit_cstat_d, submit_nstat;

    enum logic [2:0]  { 
        FREE_IDLE     = 3'b001,
        FREE_RD_REQ   = 3'b010,
        FREE_RD_RSP   = 3'b100
    } free_cstat, free_nstat;

    logic not_submit_ff_wren, not_submit_ff_rden, not_submit_ff_full, not_submit_ff_pfull, not_submit_ff_empty;
    not_submit_t  not_submit_ff_din, not_submit_ff_dout;
    logic not_submit_ff_overflow, not_submit_ff_underflow;
    logic [1:0] not_submit_ff_parity_ecc_err;

    logic avail_id_rsp_sop;
    virtio_err_info_t err_info2net;

    virtio_avail_id_rsp_dat_t avail_id_rsp_dat_d;
    logic avail_id_rsp_eop_d;
    logic avail_id_rsp_ok;
    logic rsp_cnt_with_not_submit;
    logic [SLOT_WIDTH-1:0] free_slot_id, submit_slot_id, cpl_slot_id;
    virtio_vq_t free_vq, cpl_vq;
    logic rd_desc_rsp_fire_d;
    logic [Q_WIDTH-1:0]      rsp_cnt_qid_d; 
    logic [DEV_ID_WIDTH-1:0] rsp_cnt_dev_id_d;

    logic tag_ff_wren, tag_ff_full, tag_ff_pfull, tag_ff_rden, tag_ff_empty;
    logic tag_ff_overflow, tag_ff_underflow;
    logic [$clog2(SLOT_NUM):0] tag_ff_usedw;
    logic [SLOT_WIDTH-1:0] tag_ff_din, tag_ff_dout;
    logic [1:0] tag_ff_parity_ecc_err;

    logic order_ff_wren, order_ff_pfull, order_ff_rden, order_ff_empty;
    order_t order_ff_din, order_ff_dout, order_info;
    logic order_ff_overflow, order_ff_underflow;
    logic [1:0] order_ff_parity_ecc_err;

    logic [7:0] hold_req_cnt_per_q, hold_req_cnt_per_dev;

    logic flush, tag_flush;
    logic [DEV_ID_WIDTH-1:0] flush_id;

    logic [PKT_ID_WIDTH-1:0] req_pkt_id;
    logic [DEV_ID_WIDTH-1:0] req_dev_id;
    virtio_vq_t req_vq;

    logic limit;
    logic [7:0] limit_per_queue, limit_per_dev, credit_per_q, credit_per_dev, inflight_per_dev, inflight_per_q, rsp_cnt_credit;
    logic [3:0] req_nid, rsp_nid;


    logic cpl_slot_ff_wren, cpl_slot_ff_full, cpl_slot_ff_pfull, cpl_slot_ff_rden, cpl_slot_ff_empty;
    logic [SLOT_WIDTH + $bits(virtio_vq_t)-1:0] cpl_slot_ff_din, cpl_slot_ff_dout;
    logic cpl_slot_ff_overflow, cpl_slot_underflow;
    logic [1:0] cpl_slot_parity_ecc_err;

    logic req_cnt_per_q_ram_wen;
    logic [7:0] req_cnt_per_q_ram_wdata, req_cnt_per_q_ram_rdata;
    logic [Q_WIDTH-1:0] req_cnt_per_q_ram_waddr, req_cnt_per_q_ram_raddr;
    logic [1:0] req_cnt_per_q_ram_parity_ecc_err;

    logic rsp_cnt_per_q_ram_wen;
    logic [7:0] rsp_cnt_per_q_ram_wdata, rsp_cnt_per_q_ram_rdata;
    logic [Q_WIDTH-1:0] rsp_cnt_per_q_ram_waddr, rsp_cnt_per_q_ram_raddr;
    logic [1:0] rsp_cnt_per_q_ram_parity_ecc_err;

    logic rsp_cnt_per_q_clone_ram_wen;
    logic [7:0] rsp_cnt_per_q_clone_ram_wdata, rsp_cnt_per_q_clone_ram_rdata;
    logic [Q_WIDTH-1:0] rsp_cnt_per_q_clone_ram_waddr, rsp_cnt_per_q_clone_ram_raddr;
    logic [1:0] rsp_cnt_per_q_clone_ram_parity_ecc_err;

    logic req_cnt_per_dev_ram_wen;
    logic [7:0] req_cnt_per_dev_ram_wdata, req_cnt_per_dev_ram_rdata;
    logic [DEV_ID_WIDTH-1:0] req_cnt_per_dev_ram_waddr, req_cnt_per_dev_ram_raddr;
    logic [1:0] req_cnt_per_dev_ram_parity_ecc_err;

    logic rsp_cnt_per_dev_ram_wen;
    logic [7:0] rsp_cnt_per_dev_ram_wdata, rsp_cnt_per_dev_ram_rdata;
    logic [DEV_ID_WIDTH-1:0] rsp_cnt_per_dev_ram_waddr, rsp_cnt_per_dev_ram_raddr;
    logic [1:0] rsp_cnt_per_dev_ram_parity_ecc_err;

    logic rsp_cnt_per_dev_clone_ram_wen;
    logic [7:0] rsp_cnt_per_dev_clone_ram_wdata, rsp_cnt_per_dev_clone_ram_rdata;
    logic [DEV_ID_WIDTH-1:0] rsp_cnt_per_dev_clone_ram_waddr, rsp_cnt_per_dev_clone_ram_raddr;
    logic [1:0] rsp_cnt_per_dev_clone_ram_parity_ecc_err;

    logic goto_submit_wait_alloc_rsp;
    logic goto_submit_slot;

    always @(posedge clk) begin
        if(rst)begin
            flush <= 'h1;
        end else if((flush_id == {DEV_ID_WIDTH{1'b1}}))begin
            flush <= 'h0;
        end
    end

    always @(posedge clk) begin
        if(rst)begin
            tag_flush <= 'h1;
        end else if(flush_id == {SLOT_WIDTH{1'b1}}) begin
            tag_flush <= 'h0;
        end
    end
    
    always @(posedge clk) begin
        if(rst)begin
            flush_id <= 'h0;
        end else if(flush)begin
            flush_id <= flush_id + 1'b1;
        end
    end


    always @(posedge clk) begin
        if(rst)begin
            pre_process_cstat   <= PRE_PROCESS_IDLE;
            pre_process_cstat_d <= PRE_PROCESS_IDLE;
        end else begin
            pre_process_cstat   <= pre_process_nstat;
            pre_process_cstat_d <= pre_process_cstat;
        end
    end

    always @(*) begin
        pre_process_nstat = pre_process_cstat;
        case (pre_process_cstat)
            PRE_PROCESS_IDLE: begin
                if(alloc_slot_req_vld && !order_ff_pfull && !flush)begin
                    pre_process_nstat = PRE_PROCESS_CTX;
                end
            end
            PRE_PROCESS_CTX: begin
                pre_process_nstat = PRE_PROCESS_CALC1;
            end
            PRE_PROCESS_CALC1: begin
                pre_process_nstat = PRE_PROCESS_CALC2;
            end
            PRE_PROCESS_CALC2: begin
                pre_process_nstat = PRE_PROCESS_WR;
            end
            PRE_PROCESS_WR: begin
                if(avail_id_req_rdy || !avail_id_req_vld)begin
                    pre_process_nstat = PRE_PROCESS_IDLE;
                end
            end
        endcase
    end

    assign limit_per_queue_rd_req_vld   = pre_process_cstat == PRE_PROCESS_IDLE && alloc_slot_req_vld && !order_ff_pfull && !flush;
    assign limit_per_queue_rd_req_qid   = alloc_slot_req_vq.qid;
    assign limit_per_dev_rd_req_vld     = pre_process_cstat == PRE_PROCESS_IDLE && alloc_slot_req_vld && !order_ff_pfull && !flush;
    assign limit_per_dev_rd_req_dev_id  = alloc_slot_req_dev_id;
    assign alloc_slot_req_rdy           = pre_process_cstat == PRE_PROCESS_CTX;
    
    assign req_cnt_per_q_ram_raddr      = alloc_slot_req_vq.qid;
    assign rsp_cnt_per_q_ram_raddr      = alloc_slot_req_vq.qid;
    assign req_cnt_per_dev_ram_raddr      = alloc_slot_req_dev_id;
    assign rsp_cnt_per_dev_ram_raddr     = alloc_slot_req_dev_id;

    always @(posedge clk) begin
        if(rst)begin
            req_vq                  <= 'h0;
            req_dev_id              <= 'h0;
            req_pkt_id              <= 'h0;
            limit                   <= 1'b0;
            req_nid                 <= 4'h0;
            inflight_per_q          <= 'h0;
            inflight_per_dev        <= 'h0;
            hold_req_cnt_per_q      <= 'h0;
            hold_req_cnt_per_dev    <= 'h0;
            credit_per_q            <= 'h0;
            credit_per_dev          <= 'h0;
        end else if(pre_process_cstat == PRE_PROCESS_CTX)begin
            req_vq                  <= alloc_slot_req_vq;
            req_dev_id              <= alloc_slot_req_dev_id;
            req_pkt_id              <= alloc_slot_req_pkt_id;
            limit_per_queue         <= limit_per_queue_rd_rsp_dat;
            limit_per_dev           <= limit_per_dev_rd_rsp_dat;
            inflight_per_q          <= req_cnt_per_q_ram_rdata - rsp_cnt_per_q_ram_rdata;
            inflight_per_dev        <= req_cnt_per_dev_ram_rdata - rsp_cnt_per_dev_ram_rdata;
            hold_req_cnt_per_q      <= req_cnt_per_q_ram_rdata;
            hold_req_cnt_per_dev    <= req_cnt_per_dev_ram_rdata;
        end else if(pre_process_cstat == PRE_PROCESS_CALC1)begin
            credit_per_q            <= limit_per_queue - inflight_per_q;
            credit_per_dev          <= limit_per_dev - inflight_per_dev;
        end else if(pre_process_cstat == PRE_PROCESS_CALC2)begin
            if(TXQ)begin
                limit               <= (inflight_per_q >= limit_per_queue) || (inflight_per_dev >= limit_per_dev);
                casex ({credit_per_q>credit_per_dev, credit_per_q>3'h4, credit_per_dev>3'h4})
                    3'b00x: begin
                        req_nid         <= credit_per_q;
                    end
                    3'b1x0: begin
                        req_nid         <= credit_per_dev;
                    end
                    default: begin
                        req_nid         <= 3'h4;
                    end
                endcase
            end else begin
                req_nid             <= 3'h1;
                limit               <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if(rst)begin
            avail_id_req_vld <= 1'b0;
        end else if(avail_id_req_rdy || !avail_id_req_vld)begin
            avail_id_req_vld <= pre_process_cstat == PRE_PROCESS_WR && !limit;
        end
    end

    always @(posedge clk) begin
        if(avail_id_req_rdy || !avail_id_req_vld)begin
            avail_id_req_vq             <= req_vq; 
            avail_id_req_nid            <= req_nid;
        end
    end

    always @(posedge clk) begin
        if(rst)begin
            submit_cstat    <= SUBMIT_IDLE;
            submit_cstat_d  <= SUBMIT_IDLE;
        end else begin
            submit_cstat    <= submit_nstat;
            submit_cstat_d  <= submit_cstat;
        end
    end

    assign goto_submit_wait_alloc_rsp = !order_ff_empty && order_ff_dout.limit;
    assign goto_submit_slot = avail_id_rsp_vld && !order_ff_empty && !tag_ff_empty && !not_submit_ff_full;

    always @(*) begin
        submit_nstat = submit_cstat;
        case (submit_cstat)
            SUBMIT_IDLE: begin
                if(goto_submit_wait_alloc_rsp)begin
                    submit_nstat = SUBMIT_WAIT_ALLOC_RSP;
                end else if(goto_submit_slot)begin
                    submit_nstat = SUBMIT_SLOT;
                end
            end
            SUBMIT_SLOT:begin
                if(!avail_id_rsp_dat_d.local_ring_empty && avail_id_rsp_dat_d.q_stat_doing)begin
                    if(slot_submit_rdy && (alloc_slot_rsp_rdy || !alloc_slot_rsp_vld))begin
                        submit_nstat = SUBMIT_IDLE;
                    end else if(slot_submit_rdy)begin
                        submit_nstat = SUBMIT_WAIT_ALLOC_RSP;
                    end else if(alloc_slot_rsp_rdy || !alloc_slot_rsp_vld)begin
                        submit_nstat = SUBMIT_WAIT_SUBMIT_RSP;
                    end
                end else begin
                    if(alloc_slot_rsp_rdy || !alloc_slot_rsp_vld)begin
                        submit_nstat = SUBMIT_IDLE;
                    end else begin
                        submit_nstat = SUBMIT_WAIT_ALLOC_RSP;
                    end
                end                
            end
            SUBMIT_WAIT_SUBMIT_RSP:begin
                if(slot_submit_rdy)begin
                    submit_nstat = SUBMIT_IDLE;
                end
            end
            SUBMIT_WAIT_ALLOC_RSP:begin
                if(alloc_slot_rsp_rdy || !alloc_slot_rsp_vld)begin
                    submit_nstat = SUBMIT_IDLE;
                end
            end
            
        endcase
    end

    assign avail_id_rsp_rdy = submit_cstat == SUBMIT_SLOT && submit_cstat_d == SUBMIT_IDLE;

    always  @(posedge clk)begin
        if(rst)begin
            avail_id_rsp_sop <= 1'b1;
        end else if(avail_id_rsp_vld && avail_id_rsp_rdy && avail_id_rsp_eop)begin
            avail_id_rsp_sop <= 1'b1;
        end else if(avail_id_rsp_vld && avail_id_rsp_rdy)begin
            avail_id_rsp_sop <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if(submit_cstat == SUBMIT_IDLE)begin
            submit_slot_id      <= tag_ff_dout;
            avail_id_rsp_dat_d  <= avail_id_rsp_dat;
            avail_id_rsp_eop_d  <= avail_id_rsp_eop;
            order_info          <= order_ff_dout;
            avail_id_rsp_ok     <= !avail_id_rsp_dat.local_ring_empty && avail_id_rsp_dat.q_stat_doing && 
                                    avail_id_rsp_dat.err_info.err_code == VIRTIO_ERR_CODE_NONE && 
                                    !order_ff_dout.limit;

            if(avail_id_rsp_vld && avail_id_rsp_sop) begin
                err_info2net.err_code    <= avail_id_rsp_dat.err_info.err_code;
                err_info2net.fatal       <= avail_id_rsp_dat.err_info.fatal;
            end else if(!err_info2net.fatal && avail_id_rsp_vld)begin
                err_info2net.err_code    <= avail_id_rsp_dat.err_info.err_code;
                err_info2net.fatal       <= avail_id_rsp_dat.err_info.fatal;
            end
        end
    end 

    always @(posedge clk) begin
        if(rst)begin
            alloc_slot_rsp_vld <= 1'b0;
        end else if(alloc_slot_rsp_rdy || !alloc_slot_rsp_vld)begin
            alloc_slot_rsp_vld <= (submit_cstat == SUBMIT_SLOT && avail_id_rsp_eop_d) || (submit_cstat == SUBMIT_WAIT_ALLOC_RSP && (avail_id_rsp_eop_d || order_info.limit));
        end
    end 

    always @(posedge clk) begin
        if(alloc_slot_rsp_rdy || !alloc_slot_rsp_vld)begin
            if(submit_cstat == SUBMIT_SLOT || submit_cstat == SUBMIT_WAIT_ALLOC_RSP)begin
                alloc_slot_rsp_dat.vq                   <= order_info.vq;
                alloc_slot_rsp_dat.pkt_id               <= order_info.pkt_id;
                
                alloc_slot_rsp_dat.desc_engine_limit    <= order_info.limit;
                if(order_info.limit)begin
                    alloc_slot_rsp_dat.err_info         <= 'h0;
                    alloc_slot_rsp_dat.ok               <= 'h0;
                    alloc_slot_rsp_dat.local_ring_empty <= 1'h0;
                    alloc_slot_rsp_dat.avail_ring_empty <= 1'h0;
                    alloc_slot_rsp_dat.q_stat_doing     <= 1'h1;
                    alloc_slot_rsp_dat.q_stat_stopping  <= 1'h0;
                end else begin
                    alloc_slot_rsp_dat.err_info         <= err_info2net;
                    alloc_slot_rsp_dat.ok               <= avail_id_rsp_ok;
                    alloc_slot_rsp_dat.local_ring_empty <= avail_id_rsp_dat_d.local_ring_empty;
                    alloc_slot_rsp_dat.avail_ring_empty <= avail_id_rsp_dat_d.avail_ring_empty;
                    alloc_slot_rsp_dat.q_stat_doing     <= avail_id_rsp_dat_d.q_stat_doing;
                    alloc_slot_rsp_dat.q_stat_stopping  <= avail_id_rsp_dat_d.q_stat_stopping;
                end
            end
        end
    end

    assign slot_submit_vld         = (submit_cstat == SUBMIT_SLOT || submit_cstat == SUBMIT_WAIT_SUBMIT_RSP) && !avail_id_rsp_dat_d.local_ring_empty && avail_id_rsp_dat_d.q_stat_doing;
    assign slot_submit_slot_id     = submit_slot_id;
    assign slot_submit_vq          = order_info.vq;
    assign slot_submit_dev_id      = order_info.dev_id;
    assign slot_submit_pkt_id      = order_info.pkt_id;
    assign slot_submit_ring_id     = avail_id_rsp_dat_d.id;
    assign slot_submit_avail_idx   = avail_id_rsp_dat_d.avail_idx;
    assign slot_submit_err         = avail_id_rsp_dat_d.err_info;

    always @(posedge clk) begin
        if(rst)begin
            free_cstat <= FREE_IDLE;
        end else begin
            free_cstat <= free_nstat;
        end
    end

    always @(*) begin
        free_nstat = free_cstat;
        case (free_cstat)
            FREE_IDLE: begin
                if(!cpl_slot_ff_empty)begin
                    free_nstat = FREE_RD_REQ;
                end
            end
            FREE_RD_REQ:begin
                if(rd_desc_req_vld && rd_desc_req_rdy)begin
                    free_nstat = FREE_RD_RSP;
                end
            end
            FREE_RD_RSP: begin
                if(rd_desc_rsp_vld && rd_desc_rsp_rdy && rd_desc_rsp_eop)begin
                    free_nstat = FREE_IDLE;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        if(free_cstat == FREE_IDLE)begin
            free_slot_id <= cpl_slot_id;
            free_vq      <= cpl_vq;
        end
    end

    always @(posedge clk) begin
        if(rst)begin
            rd_desc_rsp_fire_d      <= 1'b0;
        end else begin
            rd_desc_rsp_fire_d      <= rd_desc_rsp_vld && rd_desc_rsp_rdy && rd_desc_rsp_eop && TXQ == 1;
        end
    end

    assign rd_desc_req_vld = free_cstat == FREE_RD_REQ;
    assign rd_desc_req_slot_id = free_slot_id;
    
    assign rd_desc_rsp_rdy = (desc_rsp_rdy || !desc_rsp_vld) && free_cstat == FREE_RD_RSP;
    always @(posedge clk) begin
        if(rst)begin
            desc_rsp_vld <= 1'b0;
        end else if(desc_rsp_rdy || !desc_rsp_vld)begin
            desc_rsp_vld <= rd_desc_rsp_vld;
        end
    end

    always  @(posedge clk)begin
        if(rst)begin
            desc_rsp_sop <= 1'b1;
        end else if(desc_rsp_vld && desc_rsp_rdy && desc_rsp_eop)begin
            desc_rsp_sop <= 1'b1;
        end else if(desc_rsp_vld && desc_rsp_rdy)begin
            desc_rsp_sop <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if(desc_rsp_rdy || !desc_rsp_vld)begin
            desc_rsp_eop <= rd_desc_rsp_eop;
            desc_rsp_sbd <= rd_desc_rsp_sbd;
            desc_rsp_dat <= rd_desc_rsp_dat;
        end
    end
    
    yucca_sync_fifo #(
        .DATA_WIDTH ( SLOT_WIDTH + $bits(virtio_vq_t)   ),
        .FIFO_DEPTH ( 32                                ),
        .CHECK_ON   ( 1                                 ),
        .CHECK_MODE ( "parity"                          ),
        .DEPTH_PFULL( 32-8                              ),
        .RAM_MODE   ( "dist"                            ),
        .FIFO_MODE  ( "fwft"                            )
    ) u_cpl_slot_ff (
        .clk             (clk                       ),
        .rst             (rst                       ),
        .wren            (cpl_slot_ff_wren             ),
        .din             (cpl_slot_ff_din              ),
        .full            (cpl_slot_ff_full             ),
        .pfull           (cpl_slot_ff_pfull            ),
        .overflow        (cpl_slot_ff_overflow         ),
        .rden            (cpl_slot_ff_rden             ),
        .dout            (cpl_slot_ff_dout             ),
        .empty           (cpl_slot_ff_empty            ),
        .pempty          (                          ),
        .underflow       (cpl_slot_underflow        ),
        .usedw           (                          ),
        .parity_ecc_err  (cpl_slot_parity_ecc_err   )
    );

    assign cpl_slot_ff_wren = slot_cpl_vld;
    assign cpl_slot_ff_din  = {slot_cpl_vq, slot_cpl_slot_id};
    assign slot_cpl_sav = !cpl_slot_ff_pfull;
    assign cpl_slot_ff_rden = rd_desc_req_vld && rd_desc_req_rdy;
    assign {cpl_vq, cpl_slot_id} = cpl_slot_ff_dout;
    
    yucca_sync_fifo #(
        .DATA_WIDTH ( SLOT_WIDTH                  ),
        .FIFO_DEPTH ( SLOT_NUM                    ),
        .CHECK_ON   ( 1                           ),
        .CHECK_MODE ( "parity"                    ),
        .DEPTH_PFULL( SLOT_NUM-8                  ),
        .RAM_MODE   ( "dist"                      ),
        .FIFO_MODE  ( "fwft"                      )
    ) u_tag_ff (
        .clk             (clk                     ),
        .rst             (rst                     ),
        .wren            (tag_ff_wren             ),
        .din             (tag_ff_din              ),
        .full            (tag_ff_full             ),
        .pfull           (tag_ff_pfull            ),
        .overflow        (tag_ff_overflow         ),
        .rden            (tag_ff_rden             ),
        .dout            (tag_ff_dout             ),
        .empty           (tag_ff_empty            ),
        .pempty          (                        ),
        .underflow       (tag_ff_underflow        ),
        .usedw           (tag_ff_usedw            ),
        .parity_ecc_err  (tag_ff_parity_ecc_err   )
    );

    assign tag_ff_wren = tag_flush || (rd_desc_rsp_vld && rd_desc_rsp_rdy && rd_desc_rsp_eop);
    assign tag_ff_din = tag_flush ? flush_id : free_slot_id;
    assign tag_ff_rden = slot_submit_vld && slot_submit_rdy;

    assign used_slot_num = tag_ff_usedw;

    yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(order_t)              ),
        .FIFO_DEPTH ( 32                          ),
        .CHECK_ON   ( 1                           ),
        .CHECK_MODE ( "parity"                    ),
        .DEPTH_PFULL( 32-8                        ),
        .RAM_MODE   ( "dist"                      ),
        .FIFO_MODE  ( "fwft"                      )
    ) u_order_ff (
        .clk             (clk                       ),
        .rst             (rst                       ),
        .wren            (order_ff_wren             ),
        .din             (order_ff_din              ),
        .full            (order_ff_full             ),
        .pfull           (order_ff_pfull            ),
        .overflow        (order_ff_overflow         ),
        .rden            (order_ff_rden             ),
        .dout            (order_ff_dout             ),
        .empty           (order_ff_empty            ),
        .pempty          (                          ),
        .underflow       (order_ff_underflow        ),
        .usedw           (                          ),
        .parity_ecc_err  (order_ff_parity_ecc_err   )
    );
    

    assign order_ff_wren        = pre_process_cstat == PRE_PROCESS_WR && pre_process_cstat_d == PRE_PROCESS_CALC2;
    assign order_ff_din.vq      = req_vq;
    assign order_ff_din.dev_id  = req_dev_id;
    assign order_ff_din.pkt_id  = req_pkt_id;
    assign order_ff_din.limit   = limit;
    assign order_ff_din.nid     = req_nid;
    assign order_ff_rden = avail_id_rsp_rdy && avail_id_rsp_vld && avail_id_rsp_eop || (submit_cstat == SUBMIT_WAIT_ALLOC_RSP && submit_cstat_d == SUBMIT_IDLE);

    generate
        if(TXQ == 1)begin
            yucca_sync_fifo #(
                .DATA_WIDTH ( $bits(not_submit_t)        ),
                .FIFO_DEPTH ( 32                          ),
                .CHECK_ON   ( 1                           ),
                .CHECK_MODE ( "parity"                    ),
                .DEPTH_PFULL( 32-8                        ),
                .RAM_MODE   ( "dist"                      ),
                .FIFO_MODE  ( "fwft"                      )
            ) u_not_submit_ff (
                .clk             (clk                            ),
                .rst             (rst                            ),
                .wren            (not_submit_ff_wren             ),
                .din             (not_submit_ff_din              ),
                .full            (not_submit_ff_full             ),
                .pfull           (not_submit_ff_pfull            ),
                .overflow        (not_submit_ff_overflow         ),
                .rden            (not_submit_ff_rden             ),
                .dout            (not_submit_ff_dout             ),
                .empty           (not_submit_ff_empty            ),
                .pempty          (                               ),
                .underflow       (not_submit_ff_underflow        ),
                .usedw           (                               ),
                .parity_ecc_err  (not_submit_ff_parity_ecc_err   )
            );
            always @(posedge clk) begin
                if(rst)begin
                    rsp_nid <= 4'h0;
                end else if(submit_cstat == SUBMIT_IDLE)begin
                    if(goto_submit_wait_alloc_rsp)begin
                        rsp_nid <= rsp_nid;
                    end else if(goto_submit_slot)begin
                        if(!avail_id_rsp_dat.local_ring_empty && avail_id_rsp_dat.q_stat_doing)begin
                            rsp_nid <= rsp_nid + 1'b1;
                        end
                    end
                end else if(avail_id_rsp_vld && avail_id_rsp_rdy && avail_id_rsp_eop)begin
                    rsp_nid <= 4'h0;
                end
            end

            always @(posedge clk) begin
                if(rst)begin
                    not_submit_ff_wren       <= 1'b0;
                end else begin
                    not_submit_ff_wren       <= avail_id_rsp_rdy && avail_id_rsp_vld && avail_id_rsp_eop  && (order_info.nid != rsp_nid);
                end
                not_submit_ff_din.qid    <= order_info.vq.qid;
                not_submit_ff_din.dev_id <= order_info.dev_id;
                not_submit_ff_din.nid    <= order_info.nid - rsp_nid;
            end

            assign not_submit_ff_rden       = rsp_cnt_with_not_submit;

            always @(posedge clk) begin
                if(rst)begin
                    rsp_cnt_with_not_submit <= 1'b0;
                end else begin
                    rsp_cnt_with_not_submit <= !not_submit_ff_empty && free_cstat == FREE_IDLE && !rd_desc_rsp_fire_d && !rsp_cnt_with_not_submit;
                end

                if(free_cstat == FREE_IDLE && !rd_desc_rsp_fire_d)begin
                    rsp_cnt_qid_d  <= not_submit_ff_dout.qid;
                    rsp_cnt_dev_id_d <= not_submit_ff_dout.dev_id;
                    rsp_cnt_credit <= not_submit_ff_dout.nid;
                end else begin
                    rsp_cnt_qid_d  <= rd_desc_rsp_sbd.vq.qid;
                    rsp_cnt_dev_id_d <= rd_desc_rsp_sbd.dev_id;
                    rsp_cnt_credit <= 1'b1;
                end
            end

            sync_simple_dual_port_ram #(
                .DATAA_WIDTH   ( 8                                          ),
                .ADDRA_WIDTH   ( Q_WIDTH                                    ),
                .DATAB_WIDTH   ( 8                                          ),
                .ADDRB_WIDTH   ( Q_WIDTH                                    ),
                .REG_EN        ( 0                                          ),
                .INIT          ( 0                                          ),
                .WRITE_MODE    ( "READ_FIRST"                               ),
                .RAM_MODE      ( "blk"                                      ),
                .CHECK_ON      ( 1                                          ),
                .CHECK_MODE    ( "parity"                                   )
            )u_req_cnt_per_q_ram(
                .rst            ( rst                                ),
                .clk            ( clk                                ),
                .dina           ( req_cnt_per_q_ram_wdata            ),
                .addra          ( req_cnt_per_q_ram_waddr            ),
                .wea            ( req_cnt_per_q_ram_wen              ),
                .addrb          ( req_cnt_per_q_ram_raddr            ),
                .doutb          ( req_cnt_per_q_ram_rdata            ),
                .parity_ecc_err ( req_cnt_per_q_ram_parity_ecc_err   )
            );

            assign req_cnt_per_q_ram_wen    = flush || (pre_process_cstat == PRE_PROCESS_WR && pre_process_cstat_d == PRE_PROCESS_CALC2 && !limit);
            assign req_cnt_per_q_ram_waddr  = flush ? flush_id : req_vq.qid;
            assign req_cnt_per_q_ram_wdata  = flush ? 'h0 : hold_req_cnt_per_q + req_nid;

            sync_simple_dual_port_ram #(
                .DATAA_WIDTH   ( 8                                          ),
                .ADDRA_WIDTH   ( Q_WIDTH                                    ),
                .DATAB_WIDTH   ( 8                                          ),
                .ADDRB_WIDTH   ( Q_WIDTH                                    ),
                .REG_EN        ( 0                                          ),
                .INIT          ( 0                                          ),
                .WRITE_MODE    ( "READ_FIRST"                               ),
                .RAM_MODE      ( "blk"                                      ),
                .CHECK_ON      ( 1                                          ),
                .CHECK_MODE    ( "parity"                                   )
            )u_rsp_cnt_per_q_ram(
                .rst            ( rst                                ),
                .clk            ( clk                                ),
                .dina           ( rsp_cnt_per_q_ram_wdata            ),
                .addra          ( rsp_cnt_per_q_ram_waddr            ),
                .wea            ( rsp_cnt_per_q_ram_wen              ),
                .addrb          ( rsp_cnt_per_q_ram_raddr            ),
                .doutb          ( rsp_cnt_per_q_ram_rdata            ),
                .parity_ecc_err ( rsp_cnt_per_q_ram_parity_ecc_err   )
            );

            assign rsp_cnt_per_q_ram_wen    = flush || rd_desc_rsp_fire_d || rsp_cnt_with_not_submit;
            assign rsp_cnt_per_q_ram_waddr  = flush ? flush_id : rsp_cnt_qid_d;
            assign rsp_cnt_per_q_ram_wdata  = flush ? 'h0 : rsp_cnt_per_q_clone_ram_rdata + rsp_cnt_credit;

            sync_simple_dual_port_ram #(
                .DATAA_WIDTH   ( 8                                          ),
                .ADDRA_WIDTH   ( Q_WIDTH                                    ),
                .DATAB_WIDTH   ( 8                                          ),
                .ADDRB_WIDTH   ( Q_WIDTH                                    ),
                .REG_EN        ( 0                                          ),
                .INIT          ( 0                                          ),
                .WRITE_MODE    ( "READ_FIRST"                               ),
                .RAM_MODE      ( "blk"                                      ),
                .CHECK_ON      ( 1                                          ),
                .CHECK_MODE    ( "parity"                                   )
            )u_rsp_cnt_per_q_clone_ram(
                .rst            ( rst                                      ),
                .clk            ( clk                                      ),
                .dina           ( rsp_cnt_per_q_clone_ram_wdata            ),
                .addra          ( rsp_cnt_per_q_clone_ram_waddr            ),
                .wea            ( rsp_cnt_per_q_clone_ram_wen              ),
                .addrb          ( rsp_cnt_per_q_clone_ram_raddr            ),
                .doutb          ( rsp_cnt_per_q_clone_ram_rdata            ),
                .parity_ecc_err ( rsp_cnt_per_q_clone_ram_parity_ecc_err   )
            );

            assign rsp_cnt_per_q_clone_ram_wen = rsp_cnt_per_q_ram_wen;
            assign rsp_cnt_per_q_clone_ram_waddr = rsp_cnt_per_q_ram_waddr;
            assign rsp_cnt_per_q_clone_ram_wdata = rsp_cnt_per_q_ram_wdata;
            assign rsp_cnt_per_q_clone_ram_raddr = free_cstat == FREE_IDLE ? not_submit_ff_dout.qid : rd_desc_rsp_sbd.vq.qid;

            sync_simple_dual_port_ram #(
                .DATAA_WIDTH   ( 8                                          ),
                .ADDRA_WIDTH   ( DEV_ID_WIDTH                               ),
                .DATAB_WIDTH   ( 8                                          ),
                .ADDRB_WIDTH   ( DEV_ID_WIDTH                               ),
                .REG_EN        ( 0                                          ),
                .INIT          ( 0                                          ),
                .WRITE_MODE    ( "READ_FIRST"                               ),
                .RAM_MODE      ( "blk"                                      ),
                .CHECK_ON      ( 1                                          ),
                .CHECK_MODE    ( "parity"                                   )
            )u_req_cnt_per_dev_ram(
                .rst            ( rst                                  ),
                .clk            ( clk                                  ),
                .dina           ( req_cnt_per_dev_ram_wdata            ),
                .addra          ( req_cnt_per_dev_ram_waddr            ),
                .wea            ( req_cnt_per_dev_ram_wen              ),
                .addrb          ( req_cnt_per_dev_ram_raddr            ),
                .doutb          ( req_cnt_per_dev_ram_rdata            ),
                .parity_ecc_err ( req_cnt_per_dev_ram_parity_ecc_err   )
            );

            assign req_cnt_per_dev_ram_wen    = flush || (pre_process_cstat == PRE_PROCESS_WR && pre_process_cstat_d == PRE_PROCESS_CALC2 && !limit);
            assign req_cnt_per_dev_ram_waddr  = flush ? flush_id : req_dev_id;
            assign req_cnt_per_dev_ram_wdata  = flush ? 'h0 : hold_req_cnt_per_dev + req_nid;

            sync_simple_dual_port_ram #(
                .DATAA_WIDTH   ( 8                                          ),
                .ADDRA_WIDTH   ( DEV_ID_WIDTH                               ),
                .DATAB_WIDTH   ( 8                                          ),
                .ADDRB_WIDTH   ( DEV_ID_WIDTH                               ),
                .REG_EN        ( 0                                          ),
                .INIT          ( 0                                          ),
                .WRITE_MODE    ( "READ_FIRST"                               ),
                .RAM_MODE      ( "blk"                                      ),
                .CHECK_ON      ( 1                                          ),
                .CHECK_MODE    ( "parity"                                   )
            )u_rsp_cnt_per_dev_ram(
                .rst            ( rst                                  ),
                .clk            ( clk                                  ),
                .dina           ( rsp_cnt_per_dev_ram_wdata            ),
                .addra          ( rsp_cnt_per_dev_ram_waddr            ),
                .wea            ( rsp_cnt_per_dev_ram_wen              ),
                .addrb          ( rsp_cnt_per_dev_ram_raddr            ),
                .doutb          ( rsp_cnt_per_dev_ram_rdata            ),
                .parity_ecc_err ( rsp_cnt_per_dev_ram_parity_ecc_err   )
            );

            assign rsp_cnt_per_dev_ram_wen    = flush || rd_desc_rsp_fire_d || rsp_cnt_with_not_submit;
            assign rsp_cnt_per_dev_ram_waddr  = flush ? flush_id : rsp_cnt_dev_id_d;
            assign rsp_cnt_per_dev_ram_wdata  = flush ? 'h0 : rsp_cnt_per_dev_clone_ram_rdata + rsp_cnt_credit;

            sync_simple_dual_port_ram #(
                .DATAA_WIDTH   ( 8                                          ),
                .ADDRA_WIDTH   ( DEV_ID_WIDTH                                    ),
                .DATAB_WIDTH   ( 8                                          ),
                .ADDRB_WIDTH   ( DEV_ID_WIDTH                                    ),
                .REG_EN        ( 0                                          ),
                .INIT          ( 0                                          ),
                .WRITE_MODE    ( "READ_FIRST"                               ),
                .RAM_MODE      ( "blk"                                      ),
                .CHECK_ON      ( 1                                          ),
                .CHECK_MODE    ( "parity"                                   )
            )u_rsp_cnt_per_dev_clone_ram(
                .rst            ( rst                                        ),
                .clk            ( clk                                        ),
                .dina           ( rsp_cnt_per_dev_clone_ram_wdata            ),
                .addra          ( rsp_cnt_per_dev_clone_ram_waddr            ),
                .wea            ( rsp_cnt_per_dev_clone_ram_wen              ),
                .addrb          ( rsp_cnt_per_dev_clone_ram_raddr            ),
                .doutb          ( rsp_cnt_per_dev_clone_ram_rdata            ),
                .parity_ecc_err ( rsp_cnt_per_dev_clone_ram_parity_ecc_err   )
            );

            assign rsp_cnt_per_dev_clone_ram_wen = rsp_cnt_per_dev_ram_wen;
            assign rsp_cnt_per_dev_clone_ram_waddr = rsp_cnt_per_dev_ram_waddr;
            assign rsp_cnt_per_dev_clone_ram_wdata = rsp_cnt_per_dev_ram_wdata;

            assign rsp_cnt_per_dev_clone_ram_raddr = free_cstat == FREE_IDLE ? not_submit_ff_dout.dev_id : rd_desc_rsp_sbd.dev_id;
        end else begin
            assign not_submit_ff_full = 1'b0;
        end
    endgenerate

    always @(posedge clk) begin
        if(rst)begin
            alloc_slot_req_cnt          <= 8'h0;
            alloc_slot_rsp_cnt          <= 8'h0;
            alloc_slot_limit_cnt        <= 8'h0;
            alloc_slot_ok_cnt           <= 8'h0;
            avail_id_req_cnt            <= 8'h0;
            avail_id_rsp_cnt            <= 8'h0;
            avail_id_rsp_pkt_cnt        <= 8'h0;
            avail_id_got_id_cnt         <= 8'h0;
            avail_id_err_cnt            <= 8'h0;
            slot_submit_cnt             <= 8'h0;
            slot_cpl_cnt                <= 8'h0;
            rd_desc_req_cnt             <= 8'h0;
            rd_desc_rsp_cnt             <= 8'h0;
            rd_desc_rsp_pkt_cnt         <= 8'h0;
            slot_err_cnt                <= 8'h0;
            desc_rsp_cnt                <= 8'h0;
            desc_rsp_pkt_cnt            <= 8'h0;
        end else begin
            if(alloc_slot_req_vld && alloc_slot_req_rdy)begin
                alloc_slot_req_cnt      <= alloc_slot_req_cnt + 1'b1;
            end
            if(alloc_slot_rsp_vld && alloc_slot_rsp_rdy)begin
                alloc_slot_rsp_cnt      <= alloc_slot_rsp_cnt + 1'b1;
            end
            if(alloc_slot_rsp_vld && alloc_slot_rsp_rdy && alloc_slot_rsp_dat.desc_engine_limit)begin
                alloc_slot_limit_cnt    <= alloc_slot_limit_cnt + 1'b1;
            end
            if(alloc_slot_rsp_vld && alloc_slot_rsp_rdy && alloc_slot_rsp_dat.ok)begin
                alloc_slot_ok_cnt      <= alloc_slot_ok_cnt + 1'b1;
            end
            if(avail_id_req_vld && avail_id_req_rdy)begin
                avail_id_req_cnt        <= avail_id_req_cnt + 1'b1;
            end
            if(avail_id_rsp_vld && avail_id_rsp_rdy)begin
                avail_id_rsp_cnt        <= avail_id_rsp_cnt + 1'b1;
            end
            if(avail_id_rsp_vld && avail_id_rsp_rdy && avail_id_rsp_eop)begin
                avail_id_rsp_pkt_cnt    <= avail_id_rsp_pkt_cnt + 1'b1;
            end
            if(avail_id_rsp_vld && avail_id_rsp_rdy && 
                                    !avail_id_rsp_dat.local_ring_empty && avail_id_rsp_dat.q_stat_doing && 
                                    avail_id_rsp_dat.err_info.err_code == VIRTIO_ERR_CODE_NONE)begin
                avail_id_got_id_cnt     <= avail_id_got_id_cnt + 1'b1;
            end
            if(avail_id_rsp_vld && avail_id_rsp_rdy && avail_id_rsp_dat.err_info.err_code != VIRTIO_ERR_CODE_NONE)begin
                avail_id_err_cnt        <= avail_id_err_cnt + 1'b1;
            end
            if(slot_submit_vld && slot_submit_rdy)begin
                slot_submit_cnt         <= slot_submit_cnt + 1'b1;
            end 
            if(slot_cpl_vld)begin
                slot_cpl_cnt            <= slot_cpl_cnt + 1'b1;
            end
            if(rd_desc_req_vld && rd_desc_req_rdy)begin
                rd_desc_req_cnt         <= rd_desc_req_cnt + 1'b1;
            end
            if(rd_desc_rsp_vld && rd_desc_rsp_rdy && rd_desc_rsp_eop)begin
                rd_desc_rsp_cnt         <= rd_desc_rsp_cnt + 1'b1;
            end
            if(rd_desc_rsp_vld && rd_desc_rsp_rdy)begin
                rd_desc_rsp_pkt_cnt     <= rd_desc_rsp_pkt_cnt + 1'b1;
            end
            if(rd_desc_rsp_vld && rd_desc_rsp_rdy && rd_desc_rsp_eop && rd_desc_rsp_sbd.err_info.err_code != VIRTIO_ERR_CODE_NONE)begin
                slot_err_cnt            <= slot_err_cnt + 1'b1;
            end
            if(desc_rsp_vld && desc_rsp_rdy)begin
                desc_rsp_cnt            <= desc_rsp_cnt + 1'b1;
            end
            if(desc_rsp_vld && desc_rsp_rdy && desc_rsp_eop)begin
                desc_rsp_pkt_cnt        <= desc_rsp_pkt_cnt + 1'b1;
            end
        end
    end

    assign dfx_status = { //20bits
        not_submit_ff_empty,
        not_submit_ff_full,
        order_ff_empty,
        order_ff_pfull,
        tag_ff_empty,
        tag_ff_full,
        cpl_slot_ff_empty,
        cpl_slot_ff_pfull,
        free_cstat,          //3bits
        submit_cstat,        //4bits
        pre_process_cstat    //5bits
    };

    assign dfx_err = {   //28bits
        rsp_cnt_per_dev_clone_ram_parity_ecc_err,
        rsp_cnt_per_dev_ram_parity_ecc_err,
        req_cnt_per_dev_ram_parity_ecc_err,
        rsp_cnt_per_q_clone_ram_parity_ecc_err,
        rsp_cnt_per_q_ram_parity_ecc_err,
        req_cnt_per_q_ram_parity_ecc_err,
        not_submit_ff_parity_ecc_err,
        not_submit_ff_underflow,
        not_submit_ff_overflow,
        order_ff_parity_ecc_err,
        order_ff_underflow,
        order_ff_overflow,
        tag_ff_parity_ecc_err,
        tag_ff_underflow,
        tag_ff_overflow,
        cpl_slot_parity_ecc_err,
        cpl_slot_underflow,
        cpl_slot_ff_overflow
    };

    genvar idx;
    generate
        for(idx=0;idx<$bits(dfx_err);idx++)begin :db_err_i
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err[idx]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, dfx_err[idx], idx));
        end
    endgenerate

endmodule