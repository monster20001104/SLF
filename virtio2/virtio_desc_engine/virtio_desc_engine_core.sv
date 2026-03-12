/******************************************************************************
 * 文件名称 : virtio_desc_engine_core.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/06/27
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/27     Joe Jiang   初始化版本
 ******************************************************************************/
 `include "tlp_adap_dma_if.svh"
 `include "virtio_desc_engine_define.svh"

module virtio_desc_engine_core #(
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
    parameter MAX_BUCKET_PER_SLOT_WIDTH      = $clog2(MAX_BUCKET_PER_SLOT),
    parameter NET_RX                         = 1
) (
    input                                                       clk,
    input                                                       rst,

    tlp_adap_dma_rd_req_if.src                                  dma_desc_rd_req_if,
    tlp_adap_dma_rd_rsp_if.snk                                  dma_desc_rd_rsp_if,

    input  logic                                                slot_submit_vld,
    input  logic [SLOT_WIDTH-1:0]                               slot_submit_slot_id,
    input  virtio_vq_t                                          slot_submit_vq,
    input  logic [DEV_ID_WIDTH-1:0]                             slot_submit_dev_id,
    input  logic [PKT_ID_WIDTH-1:0]                             slot_submit_pkt_id,
    input  logic [15:0]                                         slot_submit_ring_id,
    input  logic [15:0]                                         slot_submit_avail_idx,
    input  virtio_err_info_t                                    slot_submit_err,
    output logic                                                slot_submit_rdy,

    output logic                                                slot_cpl_vld,
    output logic [SLOT_WIDTH-1:0]                               slot_cpl_slot_id,
    output virtio_vq_t                                          slot_cpl_vq,
    input  logic                                                slot_cpl_sav,

    input  logic                                                rd_desc_req_vld,
    input  logic [SLOT_WIDTH-1:0]                               rd_desc_req_slot_id,
    output logic                                                rd_desc_req_rdy,

    output logic                                                rd_desc_rsp_vld,
    output virtio_desc_eng_desc_rsp_sbd_t                       rd_desc_rsp_sbd,
    output logic                                                rd_desc_rsp_sop,
    output logic                                                rd_desc_rsp_eop,
    output virtq_desc_t                                         rd_desc_rsp_dat,
    input  logic                                                rd_desc_rsp_rdy,

    output logic                                                ctx_info_rd_req_vld,
    output virtio_vq_t                                          ctx_info_rd_req_vq,
    input  logic                                                ctx_info_rd_rsp_vld,
    input  logic [63:0]                                         ctx_info_rd_rsp_desc_tbl_addr,
    input  logic [3:0]                                          ctx_info_rd_rsp_qdepth,
    input  logic                                                ctx_info_rd_rsp_forced_shutdown,
    input  logic                                                ctx_info_rd_rsp_indirct_support,
    input  logic [19:0]                                         ctx_info_rd_rsp_max_len,
    input  logic [15:0]                                         ctx_info_rd_rsp_bdf,

    output logic                                                ctx_slot_chain_rd_req_vld,
    output virtio_vq_t                                          ctx_slot_chain_rd_req_vq,
    input  logic                                                ctx_slot_chain_rd_rsp_vld,
    input  logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_rd_rsp_head_slot,
    input  logic                                                ctx_slot_chain_rd_rsp_head_slot_vld,
    input  logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_rd_rsp_tail_slot,

    output logic                                                ctx_slot_chain_wr_vld,
    output virtio_vq_t                                          ctx_slot_chain_wr_vq,
    output logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_wr_head_slot,
    output logic                                                ctx_slot_chain_wr_head_slot_vld,
    output logic [SLOT_WIDTH-1:0]                               ctx_slot_chain_wr_tail_slot,
    output logic [44:0]                                         dfx_err,
    output logic [62:0]                                         dfx_status,
    output logic [7:0]                                          dma_req_cnt,
    output logic [7:0]                                          dma_rsp_cnt,
    output logic [7:0]                                          sch_out_forced_shutdown_cnt, 
    output logic [7:0]                                          sch_out_wake_up_cnt, 
    output logic [7:0]                                          sch_out_desc_rsp_cnt,
    output logic [7:0]                                          desc_buf_order_wr_cnt, 
    output logic [7:0]                                          desc_buf_info_rd_cnt, 
    output logic [7:0]                                          wake_up_cnt
);

    enum logic [3:0]  { 
        SUBMIT_IDLE                 = 4'b0001,
        SUBMIT_RD_PREV_LOCAL_CTX    = 4'b0010,
        SUBMIT_WR_PREV_LOCAL_CTX    = 4'b0100,
        SUBMIT_WR_CTX               = 4'b1000
    } submit_cstat, submit_nstat;

    enum logic [3:0]  { 
        REQ_DESC_IDLE                = 4'b0001,
        REQ_DESC_RD_PREV_LOCAL_CTX   = 4'b0010,
        REQ_DESC_WR_CTX              = 4'b0100,
        REQ_DESC_WR_PREV_LOCAL_CTX   = 4'b1000
    } cstat, cstat_d, nstat;

    enum logic [4:0]  { 
        CPL_IDLE                = 5'b00001,
        CPL_RD_LOCAL_CTX        = 5'b00010,
        CPL_RD_NXT_LOCAL_CTX    = 5'b00100,
        CPL_EXE                 = 5'b01000,
        CPL_NXT                 = 5'b10000
    } cpl_cstat, cpl_nstat, cpl_cstat_d;

    enum logic [4:0]  { 
        RSP_DESC_IDLE           = 5'b00001,
        RSP_DESC_INFO           = 5'b00010,
        RSP_BUCKET_INFO         = 5'b00100,
        RSP_DESC_RD_REQ         = 5'b01000,
        RSP_DESC_RD_DESC        = 5'b10000
    } rsp_desc_cstat, rsp_desc_nstat;

    logic                   standby;
    logic [SLOT_WIDTH:0]    angry_cnt;

    logic [1:0]             pingpong_cnt;


    virtio_desc_eng_core_info_ff_t   info_rd_dat;
    logic                            info_rd_vld;
    logic                            info_rd_rdy;

    logic                               sch_ack;
    logic [$bits(req_type_t)-1:0]       sch_type;
    virtio_vq_t                         sch_vq;
    logic [SLOT_WIDTH-1:0]              sch_slot_id;
    logic                               sch_vld;
    req_type_t                  process_typ;
    virtio_vq_t                 process_vq;
    logic [SLOT_WIDTH-1:0]      process_slot_id;
    virtio_desc_eng_core_info_ff_t      process_desc_rsp_info;

    logic wake_up_ff_wren, wake_up_ff_rden, wake_up_ff_pfull, wake_up_ff_empty;
    logic [$clog2(SLOT_NUM):0] wake_up_ff_usedw;
    virtio_desc_eng_core_wakeup_info wake_up_ff_din, wake_up_ff_dout;
    logic wake_up_ff_overflow, wake_up_ff_underflow;
    logic [1:0] wake_up_ff_parity_ecc_err;

    virtio_desc_eng_core_slot_ctx_t slot_ctx_ram_wdata, slot_ctx_ram_rdata;
    logic [SLOT_WIDTH-1:0] slot_ctx_ram_waddr, slot_ctx_ram_raddr;
    logic slot_ctx_ram_wen;
    logic [1:0] slot_ctx_ram_parity_ecc_err;

    logic bucket_id_ff_wren, bucket_id_ff_rden, bucket_id_ff_empty, bucket_id_ff_pfull;
    logic [BUCKET_WIDTH-1:0]     bucket_id_ff_din, bucket_id_ff_dout;
    logic [$clog2(BUCKET_NUM):0] bucket_id_ff_usedw;
    logic bucket_id_ff_overflow, bucket_id_ff_underflow;
    logic [1:0] bucket_id_ff_parity_ecc_err;

    logic slot_cpl_ff_wren, slot_cpl_ff_pfull, slot_cpl_ff_rden, slot_cpl_ff_empty;
    logic [SLOT_WIDTH + $bits(virtio_vq_t)-1 : 0] slot_cpl_ff_din, slot_cpl_ff_dout;
    logic slot_cpl_ff_overflow, slot_cpl_ff_underflow;
    logic [1:0] slot_cpl_ff_parity_ecc_err;

    logic forced_shutdown_ff_wren, forced_shutdown_ff_pfull, forced_shutdown_ff_rden, forced_shutdown_ff_empty;
    virtio_desc_eng_core_wakeup_info forced_shutdown_ff_din, forced_shutdown_ff_dout;
    logic forced_shutdown_ff_overflow, forced_shutdown_ff_underflow;
    logic [SLOT_WIDTH:0] forced_shutdown_ff_usedw;
    logic [1:0] forced_shutdown_ff_parity_ecc_err;

    logic slot_status_ram_wen;
    logic [SLOT_WIDTH-1:0] slot_status_ram_waddr, slot_status_ram_raddr;
    logic [$bits(virtio_slot_status_t)-1:0] slot_status_ram_wdata, slot_status_ram_rdata;
    logic [1:0] slot_status_ram_parity_ecc_err;

    logic slot_ctx_en_ram_wen;
    logic [SLOT_WIDTH-1:0] slot_ctx_en_ram_waddr, slot_ctx_en_ram_raddr;
    logic slot_ctx_en_ram_wdata, slot_ctx_en_ram_rdata;
    logic [1:0] slot_ctx_en_ram_parity_ecc_err;

    logic slot_ctx_clone_ram_wen;
    logic [SLOT_WIDTH-1:0] slot_ctx_clone_ram_waddr, slot_ctx_clone_ram_raddr;
    virtio_desc_eng_core_slot_ctx_t slot_ctx_clone_ram_wdata, slot_ctx_clone_ram_rdata;
    logic [1:0] slot_ctx_clone_ram_parity_ecc_err;

    logic buckets_ram_wen;
    logic [SLOT_WIDTH + MAX_BUCKET_PER_SLOT_WIDTH - 1:0] buckets_ram_waddr, buckets_ram_raddr;
    logic [BUCKET_WIDTH-1:0] buckets_ram_wdata, buckets_ram_rdata;
    logic [1:0] buckets_ram_parity_ecc_err;

    logic buckets_clone_ram_wen;
    logic [SLOT_WIDTH + MAX_BUCKET_PER_SLOT_WIDTH - 1 : 0] buckets_clone_ram_waddr, buckets_clone_ram_raddr;
    logic [BUCKET_WIDTH-1:0] buckets_clone_ram_wdata, buckets_clone_ram_rdata;
    logic [1:0] buckets_clone_ram_parity_ecc_err;

    logic [16:0] indirct_buf_remaining;
    logic [16:0] bucket_remaining;

    logic [SLOT_WIDTH-1:0] do_cpl_slot_id; 
    virtio_vq_t do_cpl_vq;
    logic [7:0] rsp_desc_addr, rsp_desc_cnt;
    virtio_desc_eng_core_slot_ctx_t rsp_desc_ctx_info;
    virtio_slot_status_t rsp_desc_ctx_status;

    logic cpl_nxt_vld, cpl_not_nxt_req; 

    logic [SLOT_NUM-1:0] cpl_bitmap;
    logic [SLOT_NUM-1:0] dbg_bitmap;
    logic [SLOT_NUM-1:0] dbg_err_flag;

    virtio_desc_eng_core_slot_ctx_t submit_cur_slot_ctx, submit_prev_slot_ctx;
    virtio_desc_eng_core_desc_rd2rsp_t submit_rd_desc_rd2rsp;

    virtio_desc_eng_core_slot_ctx_t cur_slot_ctx;
    virtio_slot_status_t cur_slot_status;

    virtio_desc_eng_core_desc_rd2rsp_t process_rd_desc_rd2rsp;

    logic alloc_new_bucket;

    logic [$clog2(DESC_BUF_DEPTH)+$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:0] desc_buf_rd_req_addr;
    logic                                                                     desc_buf_rd_req_vld;
    virtq_desc_t                                                              desc_buf_rd_rsp_dat, desc_buf_rd_rsp_dat_d;
    logic                                                                     desc_buf_rd_rsp_vld;
    logic [12:0]                                                              desc_buf_dfx_err;
    logic [3:0]                                                               desc_buf_dfx_status;

    logic                   req_desc_ctx_slot_head_slot_ram_wen;
    logic [Q_WIDTH-1:0]     req_desc_ctx_slot_head_slot_ram_waddr, req_desc_ctx_slot_head_slot_ram_raddr;
    logic [SLOT_WIDTH-1:0]  req_desc_ctx_slot_head_slot_ram_wdata, req_desc_ctx_slot_head_slot_ram_rdata;
    logic [1:0]             req_desc_ctx_slot_head_slot_ram_parity_ecc_err;

    logic                                                                     order_wr_vld;
    virtio_desc_eng_core_rd_desc_order_t                                      order_wr_dat;

    logic flush;
    logic [BUCKET_WIDTH-1:0] flush_id;

    logic desc_buf_err_flag, chain_data_len_oversize, chain_len_oversize, next_oversize, indirct_next_oversize;


    logic angry_up, angry_down;

    assign angry_up = cstat == REQ_DESC_WR_CTX && slot_status_ram_wdata == SLOT_STATUS_ANGRY && cur_slot_status != SLOT_STATUS_ANGRY;
    assign angry_down = rsp_desc_ctx_status == SLOT_STATUS_ANGRY && rd_desc_rsp_eop && rd_desc_rsp_vld && rd_desc_rsp_rdy;

    always @(posedge clk) begin
        if(rst)begin
            angry_cnt <= 'h0;
        end else if(angry_up && angry_down)begin
            angry_cnt <= angry_cnt;
        end else if(angry_up)begin
            angry_cnt <= angry_cnt + 1'b1;
        end else if(angry_down)begin
            angry_cnt <= angry_cnt - 1'b1;
        end
    end


    always @(posedge clk) begin
        if(rst)begin
            flush <= 'h1;
        end else if((flush_id == {BUCKET_WIDTH{1'b1}}))begin
            flush <= 'h0;
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
            standby <= 1'b0;
        end else if(bucket_id_ff_usedw < BUCKET_NUM/2)begin
            standby <= 1'b1;
        end else if(bucket_id_ff_pfull)begin
            standby <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if(rst)begin
            pingpong_cnt <= 2'h0;
        end else begin
            pingpong_cnt <= pingpong_cnt + 2'h1;
        end
    end

    assign slot_submit_rdy = submit_cstat == SUBMIT_WR_CTX;

    always @(posedge clk) begin
        if(rst)begin
            submit_cstat <= SUBMIT_IDLE;
        end else begin
            submit_cstat <= submit_nstat;
        end
    end

    always @(*) begin
        submit_nstat = submit_cstat;
        case (submit_cstat)
            SUBMIT_IDLE: begin
                if(pingpong_cnt == 2'b00 && slot_submit_vld && dma_desc_rd_req_if.sav && !standby)begin
                    submit_nstat = SUBMIT_RD_PREV_LOCAL_CTX;
                end
            end
            SUBMIT_RD_PREV_LOCAL_CTX: begin
                submit_nstat = SUBMIT_WR_PREV_LOCAL_CTX;
            end
            SUBMIT_WR_PREV_LOCAL_CTX: begin
                submit_nstat = SUBMIT_WR_CTX;
            end
            SUBMIT_WR_CTX:begin
                submit_nstat = SUBMIT_IDLE;
            end           
        endcase
    end

    always @(posedge clk) begin
        if(submit_cstat == SUBMIT_RD_PREV_LOCAL_CTX)begin
            submit_cur_slot_ctx.vq                 <= slot_submit_vq;
            submit_cur_slot_ctx.pkt_id             <= slot_submit_pkt_id;
            submit_cur_slot_ctx.dev_id             <= slot_submit_dev_id;
            submit_cur_slot_ctx.cpl                <= 'h0;
            submit_cur_slot_ctx.forced_shutdown    <= ctx_info_rd_rsp_forced_shutdown;
            submit_cur_slot_ctx.nxt_vld            <= 1'b0;
            submit_cur_slot_ctx.nxt_slot           <= 'h0;
            submit_cur_slot_ctx.prev_vld           <= ctx_slot_chain_rd_rsp_head_slot_vld;
            submit_cur_slot_ctx.prev_slot          <= ctx_slot_chain_rd_rsp_tail_slot;
            submit_cur_slot_ctx.valid_desc_cnt     <= 'h0;
            submit_cur_slot_ctx.total_buf_length   <= 'h0;
            submit_cur_slot_ctx.desc_base_addr     <= ctx_info_rd_rsp_desc_tbl_addr;
            submit_cur_slot_ctx.bdf                <= ctx_info_rd_rsp_bdf;
            submit_cur_slot_ctx.max_len            <= ctx_info_rd_rsp_max_len;
            submit_cur_slot_ctx.qdepth             <= ctx_info_rd_rsp_qdepth;
            submit_cur_slot_ctx.next_desc          <= 1'b0;
            submit_cur_slot_ctx.indirct_desc_size  <= 'h0;
            submit_cur_slot_ctx.indirct_processing <= 1'b0;
            submit_cur_slot_ctx.is_indirct         <= 1'b0;
            submit_cur_slot_ctx.indirct_support    <= ctx_info_rd_rsp_indirct_support;
            submit_cur_slot_ctx.avail_idx          <= slot_submit_avail_idx;
            submit_cur_slot_ctx.ring_id            <= slot_submit_ring_id;
            submit_cur_slot_ctx.err_info           <= slot_submit_err;
        end
    end 

    assign forced_shutdown_ff_wren          = submit_cstat == SUBMIT_WR_CTX && (submit_cur_slot_ctx.forced_shutdown || submit_cur_slot_ctx.err_info.err_code != VIRTIO_ERR_CODE_NONE);
    assign forced_shutdown_ff_din.vq        = slot_submit_vq;
    assign forced_shutdown_ff_din.slot_id   = slot_submit_slot_id;

    virtio_desc_engine_sch #(
        .SLOT_NUM  (SLOT_NUM  ),
        .SLOT_WIDTH(SLOT_WIDTH)
    ) u_virtio_desc_engine_sch (
        .clk             (clk             ),
        .rst             (rst             ),
        .forced_shutdown_ff_dout    (forced_shutdown_ff_dout), 
        .forced_shutdown_ff_empty   (forced_shutdown_ff_empty), 
        .forced_shutdown_ff_rden    (forced_shutdown_ff_rden),
        .info_rd_dat     (info_rd_dat     ),
        .info_rd_vld     (info_rd_vld     ),
        .info_rd_rdy     (info_rd_rdy     ),   
        .wake_up_ff_dout (wake_up_ff_dout ),
        .wake_up_ff_empty(wake_up_ff_empty),
        .wake_up_ff_rden (wake_up_ff_rden ),
        .sch_vq          (sch_vq          ),
        .sch_type        (sch_type        ),
        .sch_slot_id     (sch_slot_id     ),
        .sch_vld         (sch_vld         ),
        .sch_ack         (sch_ack         ),
        .standby         (standby         ),
        .angry_cnt       (angry_cnt       )
    );

    assign sch_ack = cstat == REQ_DESC_WR_CTX;

    always @(posedge clk) begin
        if(rst)begin
            cstat   <= REQ_DESC_IDLE;
            cstat_d <= REQ_DESC_IDLE;
        end else begin
            cstat   <= nstat;
            cstat_d <= cstat;
        end
    end

    always @(*) begin
        nstat = cstat;
        case (cstat)
            REQ_DESC_IDLE: begin
                if(pingpong_cnt == 2'b10 && sch_vld && dma_desc_rd_req_if.sav)begin
                    nstat = REQ_DESC_RD_PREV_LOCAL_CTX;
                end
            end
            REQ_DESC_RD_PREV_LOCAL_CTX: begin //3
                nstat = REQ_DESC_WR_CTX;
            end
            REQ_DESC_WR_CTX: begin //0
                    nstat = REQ_DESC_WR_PREV_LOCAL_CTX;
            end
            REQ_DESC_WR_PREV_LOCAL_CTX:begin //1
                nstat = REQ_DESC_IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        if(cstat == REQ_DESC_IDLE)begin
            process_typ             <= req_type_t'(sch_type);
            process_vq              <= sch_vq;
            process_slot_id         <= sch_slot_id;
            process_desc_rsp_info   <= info_rd_dat;
            chain_data_len_oversize <= info_rd_dat.total_buf_length > info_rd_dat.max_len;
            chain_len_oversize      <= info_rd_dat.vld_cnt > MAX_CHAIN_SIZE || (info_rd_dat.vld_cnt == MAX_CHAIN_SIZE && !info_rd_dat.flag_last);
            
            if(info_rd_dat.flag_indirct || info_rd_dat.indirct_processing)begin
                indirct_next_oversize   <= (info_rd_dat.next >= info_rd_dat.indirct_desc_size) && !info_rd_dat.flag_last;
                next_oversize           <= 1'h0;
            end else begin
                indirct_next_oversize   <= 1'h0;
                next_oversize           <= (info_rd_dat.next >= (16'h1 << info_rd_dat.qdepth)) && !info_rd_dat.flag_last;
            end
        end
    end

    assign desc_buf_err_flag = process_desc_rsp_info.pcie_err || process_desc_rsp_info.indirct_desc_next_must_be_zero || 
                               process_desc_rsp_info.desc_zero_len || process_desc_rsp_info.indirct_nexted_desc || 
                               process_desc_rsp_info.write_only_invalid || process_desc_rsp_info.unsupport_indirct || 
                               chain_len_oversize || next_oversize || indirct_next_oversize;

    always @(posedge clk) begin
        if(process_typ == DESC_RSP)begin
            if(cstat == REQ_DESC_RD_PREV_LOCAL_CTX)begin
                cur_slot_status                     <= virtio_slot_status_t'(slot_status_ram_rdata);
                cur_slot_ctx                        <= slot_ctx_ram_rdata;
                cur_slot_ctx.total_buf_length       <= process_desc_rsp_info.total_buf_length;
                cur_slot_ctx.next_desc              <= process_desc_rsp_info.next;
                cur_slot_ctx.cpl                    <= process_desc_rsp_info.flag_last || ctx_info_rd_rsp_forced_shutdown || desc_buf_err_flag || chain_data_len_oversize || process_desc_rsp_info.desc_buf_len_oversize;
                                                        
                cur_slot_ctx.forced_shutdown        <= ctx_info_rd_rsp_forced_shutdown;
                cur_slot_ctx.is_indirct             <= ctx_info_rd_rsp_indirct_support && process_desc_rsp_info.flag_indirct;
                cur_slot_ctx.indirct_processing         <= process_desc_rsp_info.indirct_processing;
                if(ctx_info_rd_rsp_indirct_support && process_desc_rsp_info.flag_indirct)begin
                    cur_slot_ctx.desc_base_addr     <= process_desc_rsp_info.indirct_addr;
                    cur_slot_ctx.indirct_desc_size  <= process_desc_rsp_info.indirct_desc_size;
                end
                cur_slot_ctx.valid_desc_cnt         <= process_desc_rsp_info.vld_cnt;
                cur_slot_ctx.err_info.fatal         <= desc_buf_err_flag;
                if(process_desc_rsp_info.pcie_err)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR;
                end else if(process_desc_rsp_info.indirct_desc_next_must_be_zero)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO;
                end else if(process_desc_rsp_info.desc_zero_len)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN;
                end else if(process_desc_rsp_info.desc_buf_len_oversize)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE;
                end else if(process_desc_rsp_info.indirct_nexted_desc)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC;
                end else if(process_desc_rsp_info.write_only_invalid && NET_RX)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE;
                end else if(process_desc_rsp_info.write_only_invalid && !NET_RX)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO;
                end else if(process_desc_rsp_info.unsupport_indirct)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT;
                end else if(chain_data_len_oversize)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE;
                end else if(chain_len_oversize)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE;
                end else if(next_oversize)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE;
                end else if(indirct_next_oversize)begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE;
                end else begin
                    cur_slot_ctx.err_info.err_code  <= VIRTIO_ERR_CODE_NONE;
                end
            end
        end else if(process_typ == SHUTDOWN)begin
            if(cstat == REQ_DESC_RD_PREV_LOCAL_CTX)begin
                cur_slot_status                     <= virtio_slot_status_t'(slot_status_ram_rdata);
                cur_slot_ctx                        <= slot_ctx_ram_rdata;
                cur_slot_ctx.cpl                    <= 1'b1;
            end
        end else if(process_typ == WAKE_UP)begin
            if(cstat == REQ_DESC_RD_PREV_LOCAL_CTX)begin
                cur_slot_status                     <= virtio_slot_status_t'(slot_status_ram_rdata);
                cur_slot_ctx                        <= slot_ctx_ram_rdata;
                cur_slot_ctx.cpl                    <= ctx_info_rd_rsp_forced_shutdown;
                cur_slot_ctx.forced_shutdown        <= ctx_info_rd_rsp_forced_shutdown;
            end
        end
    end  

//    status==angry     standby    angry_cnt<SLOT_NUM/4-1      is_first      prev_status==angry        alloc_new_bucket
//        0                 1                0                     x                   x                 0
//        0                 1                1                     0                   0                 0
//        1                 x                x                     x                   x                 1
//        0                 0                x                     x                   x                 1
//        0                 1                1                     1                   x                 1
//        0                 1                1                     0                   1                 1
    always @(*) begin //REQ_DESC_WR_CTX
        casex ({cur_slot_status == SLOT_STATUS_ANGRY, standby, angry_cnt < SLOT_NUM/4, req_desc_ctx_slot_head_slot_ram_rdata == process_slot_id, slot_status_ram_rdata == SLOT_STATUS_ANGRY})
            5'b010xx, 5'b01100:begin
                alloc_new_bucket = 1'b0;
            end
            default: begin
                alloc_new_bucket = 1'b1;
            end
        endcase
    end

    //slot_ctx_ram
    always @(*) begin
        if(pingpong_cnt == 2'b10 && cstat == REQ_DESC_IDLE)begin //desc rsp & wake up
            slot_ctx_ram_raddr = sch_slot_id;
        end else if(cstat == REQ_DESC_RD_PREV_LOCAL_CTX)begin //REQ_DESC_RD_PREV_LOCAL_CTX desc rsp & wake up
            slot_ctx_ram_raddr = slot_ctx_ram_rdata.prev_slot;
        end else if(pingpong_cnt == 2'b00 && submit_cstat == SUBMIT_IDLE)begin //slot_submit SUBMIT_IDLE
            slot_ctx_ram_raddr = slot_submit_slot_id;
        end else begin //slot_submit SUBMIT_RD_PREV_LOCAL_CTX
            slot_ctx_ram_raddr = ctx_slot_chain_rd_rsp_tail_slot;
        end
    end

    always @(*) begin
        if(cstat == REQ_DESC_WR_CTX)begin
            slot_ctx_ram_wen = 1'b1;
        end else if(submit_cstat == SUBMIT_WR_PREV_LOCAL_CTX)begin
            slot_ctx_ram_wen = submit_cur_slot_ctx.prev_vld;
        end else if(submit_cstat == SUBMIT_WR_CTX)begin
            slot_ctx_ram_wen = 1'b1;
        end else begin
            slot_ctx_ram_wen = 1'b0;
        end
    end

    always @(*) begin
        if(cstat == REQ_DESC_WR_CTX)begin
            slot_ctx_ram_waddr = process_slot_id;
        end else if(submit_cstat == SUBMIT_WR_CTX)begin
            slot_ctx_ram_waddr = slot_submit_slot_id;
        end else begin
            slot_ctx_ram_waddr = submit_cur_slot_ctx.prev_slot;
        end
    end

    always @(*) begin
        if(submit_cstat == SUBMIT_WR_PREV_LOCAL_CTX)begin
            slot_ctx_ram_wdata = slot_ctx_ram_rdata;
            slot_ctx_ram_wdata.nxt_vld = 1'b1;
            slot_ctx_ram_wdata.nxt_slot = slot_submit_slot_id;
        end else if(submit_cstat == SUBMIT_WR_CTX)begin
            slot_ctx_ram_wdata = submit_cur_slot_ctx;
        end else begin //cstat == REQ_DESC_WR_CTX
            slot_ctx_ram_wdata = cur_slot_ctx;
        end
    end

    assign slot_ctx_en_ram_wen = cpl_cstat == CPL_EXE || submit_cstat == SUBMIT_WR_CTX;
    assign slot_ctx_en_ram_waddr = cpl_cstat == CPL_EXE ? slot_cpl_slot_id : slot_submit_slot_id;
    assign slot_ctx_en_ram_wdata = submit_cstat == SUBMIT_WR_CTX;
    assign slot_ctx_en_ram_raddr = do_cpl_slot_id;

    assign slot_ctx_clone_ram_wdata = slot_ctx_ram_wdata;
    assign slot_ctx_clone_ram_waddr = slot_ctx_ram_waddr;
    assign slot_ctx_clone_ram_wen   = slot_ctx_ram_wen;

    //slot_status_ram
    always @(*) begin
        if(cstat == REQ_DESC_IDLE && pingpong_cnt == 2'b10)begin
            slot_status_ram_raddr = sch_slot_id;
        end else if(cstat == REQ_DESC_RD_PREV_LOCAL_CTX)begin
            slot_status_ram_raddr = slot_ctx_ram_rdata.prev_slot;
        end else begin
            slot_status_ram_raddr = rd_desc_req_slot_id;
        end
    end
    assign slot_status_ram_waddr = cstat == REQ_DESC_WR_CTX ? process_slot_id : slot_submit_slot_id;
    always @(*) begin
        if(submit_cstat == SUBMIT_WR_CTX)begin
            slot_status_ram_wdata = SLOT_STATUS_NOMAL;
        end else if(cur_slot_ctx.valid_desc_cnt[3:0] == 'h0 && !cur_slot_ctx.is_indirct && standby && !cur_slot_ctx.cpl)begin
            if(alloc_new_bucket)begin
                slot_status_ram_wdata = SLOT_STATUS_ANGRY;
            end else begin
                slot_status_ram_wdata = SLOT_STATUS_DORMANT;
            end
        end else begin
            if(cur_slot_status == SLOT_STATUS_DORMANT)begin
                slot_status_ram_wdata = SLOT_STATUS_NOMAL;
            end else begin
                slot_status_ram_wdata = cur_slot_status;
            end
        end
    end
    assign slot_status_ram_wen = submit_cstat == SUBMIT_WR_CTX || cstat == REQ_DESC_WR_CTX;

    //buckets_ram
    assign buckets_ram_raddr            = {process_slot_id, slot_ctx_ram_rdata.valid_desc_cnt[6:4]};
    assign buckets_ram_waddr            = submit_cstat == SUBMIT_WR_CTX ? {slot_submit_slot_id, 3'h0} : {process_slot_id, cur_slot_ctx.valid_desc_cnt[6:4]};
    always @(*) begin
        if(submit_cstat == SUBMIT_WR_CTX)begin
            buckets_ram_wen = 1'b1;
        end else if(process_typ != SHUTDOWN && cstat == REQ_DESC_WR_CTX && cur_slot_ctx.valid_desc_cnt[3:0] == 'h0 && !cur_slot_ctx.is_indirct)begin
            buckets_ram_wen = alloc_new_bucket && !cur_slot_ctx.cpl;
        end else begin
            buckets_ram_wen = 1'b0;
        end
    end
    assign buckets_ram_wdata    = bucket_id_ff_dout;
    assign buckets_clone_ram_wen = buckets_ram_wen;
    assign buckets_clone_ram_waddr = buckets_ram_waddr;
    assign buckets_clone_ram_wdata = buckets_ram_wdata;

    assign bucket_id_ff_rden    = buckets_ram_wen;

    assign submit_rd_desc_rd2rsp.vq                    = slot_submit_vq;
    assign submit_rd_desc_rd2rsp.slot_id               = slot_submit_slot_id;
    assign submit_rd_desc_rd2rsp.desc_buf_local_offset = {bucket_id_ff_dout, 3'h0};
    assign submit_rd_desc_rd2rsp.indirct_processing    = 1'h0;
    assign submit_rd_desc_rd2rsp.idx                   = submit_cur_slot_ctx.next_desc;
    assign submit_rd_desc_rd2rsp.valid_desc_cnt        = submit_cur_slot_ctx.valid_desc_cnt;
    assign submit_rd_desc_rd2rsp.total_buf_length      = submit_cur_slot_ctx.total_buf_length;
    assign submit_rd_desc_rd2rsp.qdepth                = submit_cur_slot_ctx.qdepth;
    assign submit_rd_desc_rd2rsp.indirct_support       = submit_cur_slot_ctx.indirct_support;
    assign submit_rd_desc_rd2rsp.cycle_flag            = 1'h0;
    assign submit_rd_desc_rd2rsp.indirct_desc_size     = 'h0;
    always @(*) begin
        if(submit_cur_slot_ctx.ring_id[1:0] == 2'h0)begin
            submit_rd_desc_rd2rsp.dirct_desc_bitmap     = 2'h1;
        end else if(submit_cur_slot_ctx.ring_id[1:0] == 2'h3)begin
            submit_rd_desc_rd2rsp.dirct_desc_bitmap     = 2'h3;
        end else begin
            submit_rd_desc_rd2rsp.dirct_desc_bitmap     = 2'h2;
        end
    end

    assign process_rd_desc_rd2rsp.vq                    = process_vq;
    assign process_rd_desc_rd2rsp.slot_id               = process_slot_id;
    assign process_rd_desc_rd2rsp.desc_buf_local_offset = {{cur_slot_ctx.valid_desc_cnt[3:0] == 'h0  && !cur_slot_ctx.is_indirct ? bucket_id_ff_dout : buckets_ram_rdata}, cur_slot_ctx.valid_desc_cnt[3:1]};
    assign process_rd_desc_rd2rsp.indirct_processing    = cur_slot_ctx.is_indirct || cur_slot_ctx.indirct_processing;
    assign process_rd_desc_rd2rsp.idx                   = cur_slot_ctx.next_desc;
    assign process_rd_desc_rd2rsp.valid_desc_cnt        = cur_slot_ctx.valid_desc_cnt;
    assign process_rd_desc_rd2rsp.total_buf_length      = cur_slot_ctx.total_buf_length;
    assign process_rd_desc_rd2rsp.qdepth                = cur_slot_ctx.qdepth;
    assign process_rd_desc_rd2rsp.indirct_support       = cur_slot_ctx.indirct_support;
    assign process_rd_desc_rd2rsp.cycle_flag            = 1'h0;
    assign process_rd_desc_rd2rsp.indirct_desc_size     = cur_slot_ctx.indirct_desc_size;
    assign process_rd_desc_rd2rsp.dirct_desc_bitmap     = 2'h0;

    always @(posedge clk) begin
        if(rst)begin
            dma_desc_rd_req_if.vld          <= 1'b0;
        end else if(cstat == REQ_DESC_WR_CTX)begin
            if(cur_slot_ctx.valid_desc_cnt[3:0] == 'h0 && !cur_slot_ctx.is_indirct)begin
                dma_desc_rd_req_if.vld          <= alloc_new_bucket && !cur_slot_ctx.cpl && cur_slot_ctx.err_info.err_code == VIRTIO_ERR_CODE_NONE;
            end else begin
                dma_desc_rd_req_if.vld          <= !cur_slot_ctx.cpl && cur_slot_ctx.err_info.err_code == VIRTIO_ERR_CODE_NONE;
            end
        end else if(submit_cstat == SUBMIT_WR_PREV_LOCAL_CTX)begin
            dma_desc_rd_req_if.vld          <= !submit_cur_slot_ctx.forced_shutdown && submit_cur_slot_ctx.err_info.err_code == VIRTIO_ERR_CODE_NONE;
        end else begin
            dma_desc_rd_req_if.vld          <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if(process_typ == DESC_RSP)begin
            bucket_remaining                <= DESC_PER_BUCKET_NUM - process_desc_rsp_info.vld_cnt[3:0];
            indirct_buf_remaining           <= process_desc_rsp_info.indirct_desc_size - process_desc_rsp_info.next;
        end else begin
            bucket_remaining                <= DESC_PER_BUCKET_NUM - slot_ctx_ram_rdata.valid_desc_cnt[3:0];
            indirct_buf_remaining           <= slot_ctx_ram_rdata.indirct_desc_size - slot_ctx_ram_rdata.next_desc;
        end
    end

    always @(posedge clk) begin
        dma_desc_rd_req_if.desc <= 'h0;
        if(submit_cstat == SUBMIT_WR_PREV_LOCAL_CTX)begin
            dma_desc_rd_req_if.sty                      <= submit_cur_slot_ctx.ring_id[0]* $bits(virtq_desc_t)/8;
            dma_desc_rd_req_if.desc.bdf                 <= submit_cur_slot_ctx.bdf;
            dma_desc_rd_req_if.desc.pcie_addr           <= submit_cur_slot_ctx.desc_base_addr + submit_cur_slot_ctx.ring_id[15:2] * 4 * $bits(virtq_desc_t)/8;
            dma_desc_rd_req_if.desc.pcie_length         <= 'd64;//$bits(virtq_desc_t)/8;
            dma_desc_rd_req_if.desc.rd2rsp_loop         <= submit_rd_desc_rd2rsp;
        end else if(cstat == REQ_DESC_WR_CTX)begin
            dma_desc_rd_req_if.sty                      <= cur_slot_ctx.valid_desc_cnt[0]*$bits(virtq_desc_t)/8;
            dma_desc_rd_req_if.desc.bdf                 <= cur_slot_ctx.bdf;
            dma_desc_rd_req_if.desc.pcie_addr           <= cur_slot_ctx.desc_base_addr + cur_slot_ctx.next_desc*$bits(virtq_desc_t)/8;
            if(cur_slot_ctx.is_indirct || cur_slot_ctx.indirct_processing)begin
                if(bucket_remaining > indirct_buf_remaining)begin
                    dma_desc_rd_req_if.desc.pcie_length <= indirct_buf_remaining * $bits(virtq_desc_t)/8;
                end else begin
                    dma_desc_rd_req_if.desc.pcie_length <= bucket_remaining * $bits(virtq_desc_t)/8;
                end
            end else begin
                dma_desc_rd_req_if.desc.pcie_length     <= $bits(virtq_desc_t)/8;
            end
            dma_desc_rd_req_if.desc.rd2rsp_loop         <= process_rd_desc_rd2rsp;
        end
    end  

    assign order_wr_vld = dma_desc_rd_req_if.vld;
    always @(posedge clk) begin
        if(submit_cstat == SUBMIT_WR_PREV_LOCAL_CTX)begin
            order_wr_dat.vq                     <= submit_rd_desc_rd2rsp.vq;
            order_wr_dat.slot_id                <= submit_rd_desc_rd2rsp.slot_id;
            order_wr_dat.max_len                <= submit_cur_slot_ctx.max_len;
            order_wr_dat.desc_buf_local_offset  <= submit_rd_desc_rd2rsp.desc_buf_local_offset;
        end else if(cstat == REQ_DESC_WR_CTX)begin
            order_wr_dat.vq                     <= process_rd_desc_rd2rsp.vq;
            order_wr_dat.slot_id                <= process_rd_desc_rd2rsp.slot_id;
            order_wr_dat.max_len                <= cur_slot_ctx.max_len;
            order_wr_dat.desc_buf_local_offset  <= process_rd_desc_rd2rsp.desc_buf_local_offset;
        end
    end 

    always @(posedge clk) begin
        if(rst)begin
            cpl_cstat   <= CPL_IDLE;
            cpl_cstat_d <= CPL_IDLE;
        end else begin
            cpl_cstat   <= cpl_nstat;
            cpl_cstat_d <= cpl_cstat;
        end
    end

    always @(*) begin
        cpl_nstat = cpl_cstat;
        case (cpl_cstat)
            CPL_IDLE: begin
                if(!slot_cpl_ff_empty && pingpong_cnt == 2'b01 && slot_cpl_sav)begin
                    cpl_nstat = CPL_RD_LOCAL_CTX;
                end
            end
            CPL_RD_LOCAL_CTX: begin //rd cur
                if(cpl_cstat_d == CPL_IDLE && !cpl_bitmap[do_cpl_slot_id])begin
                    cpl_nstat = CPL_IDLE;
                end else begin
                    cpl_nstat = CPL_RD_NXT_LOCAL_CTX;
                end
            end
            CPL_RD_NXT_LOCAL_CTX:begin // rd nxt
                if(!slot_ctx_en_ram_rdata)begin
                    cpl_nstat = CPL_IDLE;
                end else if(cpl_not_nxt_req)begin
                    if(ctx_slot_chain_rd_rsp_head_slot_vld && (ctx_slot_chain_rd_rsp_head_slot == do_cpl_slot_id))begin
                        cpl_nstat = CPL_EXE; 
                    end else  begin //the slot id is been cpl
                        cpl_nstat = CPL_IDLE;
                    end
                end else  begin //is not frist
                    cpl_nstat = CPL_EXE; 
                end
            end
            CPL_EXE: begin
                if(slot_ctx_clone_ram_rdata.cpl && cpl_nxt_vld)begin
                    cpl_nstat = CPL_NXT;
                end else begin
                    cpl_nstat = CPL_IDLE;
                end
            end 
            CPL_NXT: begin
                if(slot_cpl_sav && pingpong_cnt == 2'b01)begin
                    cpl_nstat = CPL_RD_LOCAL_CTX;
                end
            end
        endcase
    end

    assign slot_cpl_vld     = cpl_cstat == CPL_EXE;
    always @(posedge clk) begin
        slot_cpl_vq         <= do_cpl_vq;
        slot_cpl_slot_id    <= do_cpl_slot_id;
    end

    assign slot_cpl_ff_rden = cpl_cstat_d == CPL_IDLE && cpl_cstat == CPL_RD_LOCAL_CTX;

    always @(posedge clk) begin
        if(cpl_cstat == CPL_RD_NXT_LOCAL_CTX)begin
            cpl_nxt_vld <= slot_ctx_clone_ram_rdata.nxt_vld;
        end
    end

    always @(posedge clk) begin
        if(cpl_cstat == CPL_IDLE)begin
            {do_cpl_vq, do_cpl_slot_id}  <= slot_cpl_ff_dout;
        end else if(cpl_cstat == CPL_RD_NXT_LOCAL_CTX)begin
            do_cpl_slot_id  <= slot_ctx_clone_ram_rdata.nxt_slot;
            do_cpl_vq       <= do_cpl_vq;
        end
    end     
    
    always @(*) begin
        if(cpl_cstat == CPL_RD_LOCAL_CTX)begin
            slot_ctx_clone_ram_raddr = do_cpl_slot_id;
        end else if(cpl_cstat == CPL_RD_NXT_LOCAL_CTX)begin
            slot_ctx_clone_ram_raddr = slot_ctx_clone_ram_rdata.nxt_slot;
        end else begin //RSP_DESC_IDLE
            slot_ctx_clone_ram_raddr = rd_desc_req_slot_id;
        end
    end                                                                                //  2'                  2'b00 2'b10

    always @(posedge clk) begin
        if(rst)begin
            rsp_desc_cstat <= RSP_DESC_IDLE;
        end else begin
            rsp_desc_cstat <= rsp_desc_nstat;
        end
    end

    always @(*) begin
        rsp_desc_nstat = rsp_desc_cstat;
        case (rsp_desc_cstat)
            RSP_DESC_IDLE: begin
                if(rd_desc_req_vld && (pingpong_cnt == 2'b00 || pingpong_cnt == 2'b01))begin
                    rsp_desc_nstat = RSP_DESC_INFO;
                end
            end
            RSP_DESC_INFO: begin
                rsp_desc_nstat = RSP_BUCKET_INFO;
            end
            RSP_BUCKET_INFO: begin
                rsp_desc_nstat = RSP_DESC_RD_REQ;
            end
            RSP_DESC_RD_REQ: begin
                rsp_desc_nstat = RSP_DESC_RD_DESC;
            end
            RSP_DESC_RD_DESC: begin
                if(rd_desc_rsp_rdy && rd_desc_rsp_vld && rd_desc_rsp_eop)begin
                    rsp_desc_nstat = RSP_DESC_IDLE;
                end else if(rd_desc_rsp_rdy && rd_desc_rsp_vld && rsp_desc_addr[DESC_PER_BUCKET_WIDTH-1:0] == DESC_PER_BUCKET_NUM - 1)begin
                    rsp_desc_nstat = RSP_BUCKET_INFO;
                end else if(rd_desc_rsp_rdy && rd_desc_rsp_vld)begin
                    rsp_desc_nstat = RSP_DESC_RD_REQ;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        if(rst)begin
            bucket_id_ff_wren <= 1'b0;
        end else begin
            bucket_id_ff_wren <= flush || (rd_desc_rsp_rdy && rd_desc_rsp_vld && (rd_desc_rsp_eop || rsp_desc_addr[DESC_PER_BUCKET_WIDTH-1:0] == DESC_PER_BUCKET_NUM - 1));
        end

        bucket_id_ff_din <= flush ? flush_id : buckets_clone_ram_rdata;
    end

    always @(posedge clk) begin
        if(rsp_desc_cstat == RSP_DESC_INFO)begin
            rsp_desc_ctx_info <= slot_ctx_clone_ram_rdata;
            rsp_desc_ctx_status <= virtio_slot_status_t'(slot_status_ram_rdata);
        end
    end

    always @(posedge clk) begin
        if(rsp_desc_cstat == RSP_DESC_IDLE)begin
            rsp_desc_cnt <= 'h1;
            rsp_desc_addr <= 'h0;
        end else if(rd_desc_rsp_rdy && rd_desc_rsp_vld)begin
            rsp_desc_cnt <= rsp_desc_cnt + 1'b1;
            rsp_desc_addr <= rsp_desc_addr + 1'b1;
        end
    end

    always @(posedge clk) begin
        if(rst)begin
            rd_desc_rsp_sop <= 1'b1;
        end else if(rd_desc_rsp_vld && rd_desc_rsp_rdy)begin
            rd_desc_rsp_sop <= rd_desc_rsp_eop;
        end
    end

    assign rd_desc_rsp_eop = rsp_desc_cnt == rsp_desc_ctx_info.valid_desc_cnt || rsp_desc_ctx_info.valid_desc_cnt == 'h0;

    assign rd_desc_rsp_sbd.vq               = rsp_desc_ctx_info.vq;
    assign rd_desc_rsp_sbd.dev_id           = rsp_desc_ctx_info.dev_id;
    assign rd_desc_rsp_sbd.pkt_id           = rsp_desc_ctx_info.pkt_id;
    assign rd_desc_rsp_sbd.total_buf_length = rsp_desc_ctx_info.total_buf_length;
    assign rd_desc_rsp_sbd.valid_desc_cnt   = rsp_desc_ctx_info.valid_desc_cnt;
    assign rd_desc_rsp_sbd.ring_id          = rsp_desc_ctx_info.ring_id;
    assign rd_desc_rsp_sbd.avail_idx        = rsp_desc_ctx_info.avail_idx;
    assign rd_desc_rsp_sbd.forced_shutdown  = rsp_desc_ctx_info.forced_shutdown;
    assign rd_desc_rsp_sbd.err_info         = rsp_desc_ctx_info.err_info;

    assign rd_desc_rsp_dat                  = desc_buf_rd_rsp_dat;
    assign rd_desc_rsp_vld                  = rsp_desc_cstat == RSP_DESC_RD_DESC;


    assign rd_desc_req_rdy = rsp_desc_cstat == RSP_DESC_INFO;

    assign desc_buf_rd_req_vld = rsp_desc_cstat == RSP_DESC_RD_REQ || rsp_desc_cstat == RSP_DESC_RD_DESC;

    assign buckets_clone_ram_raddr = {rd_desc_req_slot_id, rsp_desc_addr[6:DESC_PER_BUCKET_WIDTH]};
    assign desc_buf_rd_req_addr = {buckets_clone_ram_rdata, rsp_desc_addr[DESC_PER_BUCKET_WIDTH-1:0]};

    assign slot_cpl_ff_wren = cstat_d == REQ_DESC_WR_PREV_LOCAL_CTX && cur_slot_ctx.cpl;
    assign slot_cpl_ff_din = {process_vq, process_slot_id};

    assign wake_up_ff_wren = slot_status_ram_wen && slot_status_ram_wdata == SLOT_STATUS_DORMANT && !cur_slot_ctx.cpl;
    assign wake_up_ff_din.slot_id = process_slot_id;
    assign wake_up_ff_din.vq = process_vq;

    //desc eng ctx 
    assign ctx_info_rd_req_vld          = (submit_cstat == SUBMIT_IDLE && pingpong_cnt == 2'b00 && slot_submit_vld) || (pingpong_cnt == 2'b10 && cstat == REQ_DESC_IDLE && sch_vld);
    assign ctx_info_rd_req_vq           = submit_cstat == SUBMIT_IDLE && pingpong_cnt == 2'b00 ? slot_submit_vq : sch_vq;

    assign ctx_slot_chain_rd_req_vld    = (submit_cstat == SUBMIT_IDLE && pingpong_cnt == 2'b00 && slot_submit_vld) || (cpl_cstat == CPL_RD_LOCAL_CTX);
    assign ctx_slot_chain_rd_req_vq     = cpl_cstat == CPL_RD_LOCAL_CTX ? do_cpl_vq : slot_submit_vq;

    assign req_desc_ctx_slot_head_slot_ram_raddr    = sch_vq.qid;
    assign req_desc_ctx_slot_head_slot_ram_wen      = ctx_slot_chain_wr_vld;
    assign req_desc_ctx_slot_head_slot_ram_waddr    = ctx_slot_chain_wr_vq.qid;
    assign req_desc_ctx_slot_head_slot_ram_wdata    = ctx_slot_chain_wr_head_slot;

    always @(posedge clk) begin
        cpl_not_nxt_req <= cpl_cstat == CPL_RD_LOCAL_CTX && cpl_cstat_d == CPL_IDLE;
    end

    //assign ctx_slot_chain_wr_vld            = submit_cstat == SUBMIT_RD_PREV_LOCAL_CTX || (cpl_cstat == CPL_RD_NXT_LOCAL_CTX);
    always @(*) begin
        if(cpl_cstat == CPL_RD_NXT_LOCAL_CTX && slot_ctx_en_ram_rdata)begin
            if(cpl_not_nxt_req)begin
                ctx_slot_chain_wr_vld = ctx_slot_chain_rd_rsp_head_slot_vld && (ctx_slot_chain_rd_rsp_head_slot == do_cpl_slot_id);
            end else begin
                ctx_slot_chain_wr_vld = 1'b1;
            end
        end else begin
            ctx_slot_chain_wr_vld = submit_cstat == SUBMIT_RD_PREV_LOCAL_CTX;
        end
    end
    assign ctx_slot_chain_wr_vq             = submit_cstat == SUBMIT_RD_PREV_LOCAL_CTX ? slot_submit_vq : do_cpl_vq;
    assign ctx_slot_chain_wr_head_slot_vld  = submit_cstat == SUBMIT_RD_PREV_LOCAL_CTX ? 1'b1 : slot_ctx_clone_ram_rdata.nxt_vld;
    assign ctx_slot_chain_wr_tail_slot      = submit_cstat == SUBMIT_RD_PREV_LOCAL_CTX ? slot_submit_slot_id : ctx_slot_chain_rd_rsp_tail_slot;
    always @(*) begin
        if(submit_cstat == SUBMIT_RD_PREV_LOCAL_CTX)begin
            if(ctx_slot_chain_rd_rsp_head_slot_vld)begin
                ctx_slot_chain_wr_head_slot = ctx_slot_chain_rd_rsp_head_slot;
            end else begin
                ctx_slot_chain_wr_head_slot = slot_submit_slot_id;
            end
        end else begin
            ctx_slot_chain_wr_head_slot = slot_ctx_clone_ram_rdata.nxt_slot;
        end
    end

    genvar i;
// synthesis translate_off
    generate
        for (i = 0; i<32; i++) begin
            always @(posedge clk) begin
                if(rst)begin
                    dbg_bitmap[i] <= 1'h0;
                    dbg_err_flag[i] <= 1'h0;
                end else if(order_wr_vld && i == order_wr_dat.slot_id)begin
                    dbg_bitmap[i] <= 1'h1;
                    dbg_err_flag[i] <= dbg_bitmap[i];
                end else if(info_rd_vld && info_rd_rdy && i == info_rd_dat.slot_id)begin
                    dbg_bitmap[i] <= 1'h0;
                end
            end
        end        
    endgenerate
// synthesis translate_on
    generate
        for (i = 0; i<32; i++) begin
            always @(posedge clk) begin
                if(rst)begin
                    cpl_bitmap[i] <= 1'h0;
                end else if(cstat == REQ_DESC_WR_CTX && cur_slot_ctx.cpl && process_slot_id == i)begin
                    cpl_bitmap[i] <= 1'h1;
                end else if(slot_cpl_vld && slot_cpl_slot_id == i)begin
                    cpl_bitmap[i] <= 1'h0;
                end
            end
        end        
    endgenerate

    virtio_desc_engine_desc_buf #(
        .DATA_WIDTH         (DATA_WIDTH         ), 
        .EMPTH_WIDTH        (EMPTH_WIDTH        ), 
        .SLOT_NUM           (SLOT_NUM           ), 
        .SLOT_WIDTH         (SLOT_WIDTH         ), 
        .LINE_NUM           (LINE_NUM           ), 
        .LINE_WIDTH         (LINE_WIDTH         ), 
        .BUCKET_NUM         (BUCKET_NUM         ), 
        .BUCKET_WIDTH       (BUCKET_WIDTH       ), 
        .DESC_BUF_DEPTH     (DESC_BUF_DEPTH     ),
        .IS_WRITE_ONLY      (NET_RX             ),
        .WRITE_ONLY_CHECK_ON(1                  )
    ) u_virtio_desc_engine_desc_buf(
        .clk                    (clk                    ),
        .rst                    (rst                    ),
        .dma_desc_rd_rsp_if     (dma_desc_rd_rsp_if     ),
        .order_wr_vld           (order_wr_vld           ),
        .order_wr_dat           (order_wr_dat           ),
        .info_rd_vld            (info_rd_vld            ),
        .info_rd_dat            (info_rd_dat            ),
        .info_rd_rdy            (info_rd_rdy            ),
        .desc_buf_rd_req_addr   (desc_buf_rd_req_addr   ),
        .desc_buf_rd_req_vld    (desc_buf_rd_req_vld    ),
        .desc_buf_rd_rsp_dat    (desc_buf_rd_rsp_dat    ),
        .desc_buf_rd_rsp_vld    (desc_buf_rd_rsp_vld    ),
        .dfx_err                (desc_buf_dfx_err       ),
        .dfx_status             (desc_buf_dfx_status    )
    );

    yucca_sync_fifo #(
        .DATA_WIDTH ( SLOT_WIDTH + $bits(virtio_vq_t)           ),
        .FIFO_DEPTH ( SLOT_NUM                                  ),
        .CHECK_ON   ( 1                                         ),
        .CHECK_MODE ( "parity"                                  ),
        .DEPTH_PFULL( SLOT_NUM-8                                ),
        .RAM_MODE   ( "dist"                                    ),
        .FIFO_MODE  ( "fwft"                                    )
    ) u_slot_cpl_ff (
        .clk             (clk                           ),
        .rst             (rst                           ),
        .wren            (slot_cpl_ff_wren              ),
        .din             (slot_cpl_ff_din               ),
        .full            (                              ),
        .pfull           (slot_cpl_ff_pfull             ),
        .overflow        (slot_cpl_ff_overflow          ),
        .rden            (slot_cpl_ff_rden              ),
        .dout            (slot_cpl_ff_dout              ),
        .empty           (slot_cpl_ff_empty             ),
        .pempty          (                              ),
        .underflow       (slot_cpl_ff_underflow         ),
        .usedw           (                              ),
        .parity_ecc_err  (slot_cpl_ff_parity_ecc_err    )
    );

    yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(virtio_desc_eng_core_wakeup_info)   ),
        .FIFO_DEPTH ( SLOT_NUM                                  ),
        .CHECK_ON   ( 1                                         ),
        .CHECK_MODE ( "parity"                                  ),
        .DEPTH_PFULL( SLOT_NUM/4*3                              ),
        .RAM_MODE   ( "dist"                                    ),
        .FIFO_MODE  ( "fwft"                                    )
    ) u_wake_up_ff (
        .clk             (clk                         ),
        .rst             (rst                         ),
        .wren            (wake_up_ff_wren             ),
        .din             (wake_up_ff_din              ),
        .full            (                            ),
        .pfull           (wake_up_ff_pfull            ),
        .overflow        (wake_up_ff_overflow         ),
        .rden            (wake_up_ff_rden             ),
        .dout            (wake_up_ff_dout             ),
        .empty           (wake_up_ff_empty            ),
        .pempty          (                            ),
        .underflow       (wake_up_ff_underflow        ),
        .usedw           (wake_up_ff_usedw            ),
        .parity_ecc_err  (wake_up_ff_parity_ecc_err   )
    );

    yucca_sync_fifo #(
        .DATA_WIDTH ( BUCKET_WIDTH              ),
        .FIFO_DEPTH ( BUCKET_NUM                ),
        .CHECK_ON   ( 1                                         ),
        .CHECK_MODE ( "parity"                                  ),
        .DEPTH_PFULL( BUCKET_NUM/8*5            ),
        .RAM_MODE   ( "blk"                                     ),
        .FIFO_MODE  ( "fwft"                                    )
    ) u_bucket_id_ff (
        .clk             (clk                           ),
        .rst             (rst                           ),
        .wren            (bucket_id_ff_wren             ),
        .din             (bucket_id_ff_din              ),
        .full            (                              ),
        .pfull           (bucket_id_ff_pfull            ),
        .overflow        (bucket_id_ff_overflow         ),
        .rden            (bucket_id_ff_rden             ),
        .dout            (bucket_id_ff_dout             ),
        .empty           (bucket_id_ff_empty            ),
        .pempty          (                              ),
        .underflow       (bucket_id_ff_underflow        ),
        .usedw           (bucket_id_ff_usedw            ),
        .parity_ecc_err  (bucket_id_ff_parity_ecc_err   )
    );

    yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(virtio_desc_eng_core_wakeup_info)   ),
        .FIFO_DEPTH ( SLOT_NUM                                  ),
        .CHECK_ON   ( 1                                         ),
        .CHECK_MODE ( "parity"                                  ),
        .DEPTH_PFULL( SLOT_NUM/8*5                              ),
        .RAM_MODE   ( "blk"                                     ),
        .FIFO_MODE  ( "fwft"                                    )
    ) u_forced_shutdown_ff (
        .clk             (clk                                 ),
        .rst             (rst                                 ),
        .wren            (forced_shutdown_ff_wren             ),
        .din             (forced_shutdown_ff_din              ),
        .full            (                                    ),
        .pfull           (forced_shutdown_ff_pfull            ),
        .overflow        (forced_shutdown_ff_overflow         ),
        .rden            (forced_shutdown_ff_rden             ),
        .dout            (forced_shutdown_ff_dout             ),
        .empty           (forced_shutdown_ff_empty            ),
        .pempty          (                                    ),
        .underflow       (forced_shutdown_ff_underflow        ),
        .usedw           (forced_shutdown_ff_usedw            ),
        .parity_ecc_err  (forced_shutdown_ff_parity_ecc_err   )
    );

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH   ( 1                               ),
        .ADDRA_WIDTH   ( SLOT_WIDTH                      ),
        .DATAB_WIDTH   ( 1                               ),
        .ADDRB_WIDTH   ( SLOT_WIDTH                      ),
        .REG_EN        ( 0                               ),
        .INIT          ( 0                               ),
        .WRITE_MODE    ( "WRITE_FIRST"                   ),
        .RAM_MODE      ( "dist"                          ),
        .CHECK_ON      ( 1                               ),
        .CHECK_MODE    ( "parity"                        )
    )u_slot_ctx_en_ram(
        .rst            ( rst                               ),
        .clk            ( clk                               ),
        .dina           ( slot_ctx_en_ram_wdata             ),
        .addra          ( slot_ctx_en_ram_waddr             ),
        .wea            ( slot_ctx_en_ram_wen               ),
        .addrb          ( slot_ctx_en_ram_raddr             ),
        .doutb          ( slot_ctx_en_ram_rdata             ),
        .parity_ecc_err ( slot_ctx_en_ram_parity_ecc_err    )
    ); 

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH   ( $bits(virtio_slot_status_t)     ),
        .ADDRA_WIDTH   ( SLOT_WIDTH                      ),
        .DATAB_WIDTH   ( $bits(virtio_slot_status_t)     ),
        .ADDRB_WIDTH   ( SLOT_WIDTH                      ),
        .REG_EN        ( 0                               ),
        .INIT          ( 0                               ),
        .WRITE_MODE    ( "WRITE_FIRST"                   ),
        .RAM_MODE      ( "dist"                          ),
        .CHECK_ON      ( 1                               ),
        .CHECK_MODE    ( "parity"                        )
    )u_slot_status_ram(
        .rst            ( rst                               ),
        .clk            ( clk                               ),
        .dina           ( slot_status_ram_wdata             ),
        .addra          ( slot_status_ram_waddr             ),
        .wea            ( slot_status_ram_wen               ),
        .addrb          ( slot_status_ram_raddr             ),
        .doutb          ( slot_status_ram_rdata             ),
        .parity_ecc_err ( slot_status_ram_parity_ecc_err    )
    ); 

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH   ( $bits(virtio_desc_eng_core_slot_ctx_t)     ),
        .ADDRA_WIDTH   ( SLOT_WIDTH                                 ),
        .DATAB_WIDTH   ( $bits(virtio_desc_eng_core_slot_ctx_t)     ),
        .ADDRB_WIDTH   ( SLOT_WIDTH                                 ),
        .REG_EN        ( 0                                          ),
        .INIT          ( 0                                          ),
        .WRITE_MODE    ( "WRITE_FIRST"                              ),
        .RAM_MODE      ( "dist"                                     ),
        .CHECK_ON      ( 1                                          ),
        .CHECK_MODE    ( "parity"                                   )
    )u_slot_ctx_ram(
        .rst            ( rst                           ),
        .clk            ( clk                           ),
        .dina           ( slot_ctx_ram_wdata            ),
        .addra          ( slot_ctx_ram_waddr            ),
        .wea            ( slot_ctx_ram_wen              ),
        .addrb          ( slot_ctx_ram_raddr            ),
        .doutb          ( slot_ctx_ram_rdata            ),
        .parity_ecc_err ( slot_ctx_ram_parity_ecc_err   )
    );

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH   ( $bits(virtio_desc_eng_core_slot_ctx_t)     ),
        .ADDRA_WIDTH   ( SLOT_WIDTH                                 ),
        .DATAB_WIDTH   ( $bits(virtio_desc_eng_core_slot_ctx_t)     ),
        .ADDRB_WIDTH   ( SLOT_WIDTH                                 ),
        .REG_EN        ( 0                                          ),
        .INIT          ( 0                                          ),
        .WRITE_MODE    ( "WRITE_FIRST"                              ),
        .RAM_MODE      ( "dist"                                     ),
        .CHECK_ON      ( 1                                          ),
        .CHECK_MODE    ( "parity"                                   )
    )u_slot_ctx_clone_ram(
        .rst            ( rst                           ),
        .clk            ( clk                           ),
        .dina           ( slot_ctx_clone_ram_wdata            ),
        .addra          ( slot_ctx_clone_ram_waddr            ),
        .wea            ( slot_ctx_clone_ram_wen              ),
        .addrb          ( slot_ctx_clone_ram_raddr            ),
        .doutb          ( slot_ctx_clone_ram_rdata            ),
        .parity_ecc_err ( slot_ctx_clone_ram_parity_ecc_err   )
    );

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH   ( BUCKET_WIDTH                               ),
        .ADDRA_WIDTH   ( SLOT_WIDTH + MAX_BUCKET_PER_SLOT_WIDTH     ),
        .DATAB_WIDTH   ( BUCKET_WIDTH                               ),
        .ADDRB_WIDTH   ( SLOT_WIDTH + MAX_BUCKET_PER_SLOT_WIDTH     ),
        .REG_EN        ( 0                                          ),
        .INIT          ( 0                                          ),
        .WRITE_MODE    ( "WRITE_FIRST"                              ),
        .RAM_MODE      ( "dist"                                     ),
        .CHECK_ON      ( 1                                          ),
        .CHECK_MODE    ( "parity"                                   )
    )u_buckets_ram(
        .rst            ( rst                           ),
        .clk            ( clk                           ),
        .dina           ( buckets_ram_wdata            ),
        .addra          ( buckets_ram_waddr            ),
        .wea            ( buckets_ram_wen              ),
        .addrb          ( buckets_ram_raddr            ),
        .doutb          ( buckets_ram_rdata            ),
        .parity_ecc_err ( buckets_ram_parity_ecc_err   )
    );

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH   ( BUCKET_WIDTH                               ),
        .ADDRA_WIDTH   ( SLOT_WIDTH + MAX_BUCKET_PER_SLOT_WIDTH     ),
        .DATAB_WIDTH   ( BUCKET_WIDTH                               ),
        .ADDRB_WIDTH   ( SLOT_WIDTH + MAX_BUCKET_PER_SLOT_WIDTH     ),
        .REG_EN        ( 0                                          ),
        .INIT          ( 0                                          ),
        .WRITE_MODE    ( "WRITE_FIRST"                              ),
        .RAM_MODE      ( "dist"                                     ),
        .CHECK_ON      ( 1                                          ),
        .CHECK_MODE    ( "parity"                                   )
    )u_buckets_clone_ram(
        .rst            ( rst                           ),
        .clk            ( clk                           ),
        .dina           ( buckets_clone_ram_wdata            ),
        .addra          ( buckets_clone_ram_waddr            ),
        .wea            ( buckets_clone_ram_wen              ),
        .addrb          ( buckets_clone_ram_raddr            ),
        .doutb          ( buckets_clone_ram_rdata            ),
        .parity_ecc_err ( buckets_clone_ram_parity_ecc_err   )
    );

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( SLOT_WIDTH),
        .ADDRA_WIDTH( Q_WIDTH   ),
        .DATAB_WIDTH( SLOT_WIDTH),
        .ADDRB_WIDTH( Q_WIDTH   ),
        .INIT       ( 0         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 1         ),
        .RAM_MODE   ( "blk"     ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,  
    )u_req_desc_ctx_slot_head_slot_ram(
        .rst            ( rst                                               ),
        .clk            ( clk                                               ),
        .dina           ( req_desc_ctx_slot_head_slot_ram_wdata             ),
        .addra          ( req_desc_ctx_slot_head_slot_ram_waddr             ),
        .wea            ( req_desc_ctx_slot_head_slot_ram_wen               ),
        .addrb          ( req_desc_ctx_slot_head_slot_ram_raddr             ),
        .doutb          ( req_desc_ctx_slot_head_slot_ram_rdata             ),
        .parity_ecc_err ( req_desc_ctx_slot_head_slot_ram_parity_ecc_err    )
    );

    always @(posedge clk) begin
        if(rst)begin
            dma_req_cnt                 <= 'h0;
            dma_rsp_cnt                 <= 'h0;
            sch_out_forced_shutdown_cnt <= 'h0;
            sch_out_wake_up_cnt         <= 'h0;
            sch_out_desc_rsp_cnt        <= 'h0;
            desc_buf_order_wr_cnt       <= 'h0;
            desc_buf_info_rd_cnt        <= 'h0;
            wake_up_cnt                 <= 'h0;
        end else begin
            if(dma_desc_rd_req_if.vld)begin
                dma_req_cnt             <= dma_req_cnt + 1'b1;
            end
            if(dma_desc_rd_rsp_if.vld && dma_desc_rd_rsp_if.eop)begin
                dma_rsp_cnt             <= dma_rsp_cnt + 1'b1;
            end
            if(sch_ack && sch_type == SHUTDOWN)begin
                sch_out_forced_shutdown_cnt <= sch_out_forced_shutdown_cnt + 1'b1;
            end
            if(sch_ack && sch_type == WAKE_UP)begin
                sch_out_wake_up_cnt <= sch_out_wake_up_cnt + 1'b1;
            end
            if(sch_ack && sch_type == DESC_RSP)begin
                sch_out_desc_rsp_cnt <= sch_out_desc_rsp_cnt + 1'b1;
            end
            if(order_wr_vld)begin
                desc_buf_order_wr_cnt <= desc_buf_order_wr_cnt + 1'b1;
            end

            if(info_rd_vld && info_rd_rdy)begin
                desc_buf_info_rd_cnt <= desc_buf_info_rd_cnt + 1'b1;
            end

            if(wake_up_ff_wren)begin
                wake_up_cnt <= wake_up_cnt + 1'b1;
            end
        end
    end

//    assign dfx_err = {
always @(posedge clk) begin
    dfx_err <= {
        desc_buf_dfx_err, // 13bits + 3bits + 29bits
        1'h0,
        req_desc_ctx_slot_head_slot_ram_parity_ecc_err,
        slot_ctx_en_ram_parity_ecc_err,
        slot_cpl_ff_overflow, 
        slot_cpl_ff_underflow, 
        slot_cpl_ff_parity_ecc_err, 
        wake_up_ff_overflow, 
        wake_up_ff_underflow, 
        wake_up_ff_parity_ecc_err, 
        bucket_id_ff_overflow, 
        bucket_id_ff_underflow, 
        bucket_id_ff_parity_ecc_err, 
        forced_shutdown_ff_overflow, 
        forced_shutdown_ff_underflow, 
        forced_shutdown_ff_parity_ecc_err, 
        slot_status_ram_parity_ecc_err, 
        slot_ctx_ram_parity_ecc_err, 
        slot_ctx_clone_ram_parity_ecc_err, 
        buckets_ram_parity_ecc_err, 
        buckets_clone_ram_parity_ecc_err,
        angry_cnt > SLOT_NUM/4
    };
end

    genvar idx;
    generate
        for(idx=0;idx<$bits(dfx_err);idx++)begin :db_err_i
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err[idx]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, dfx_err[idx], idx));
        end
    endgenerate
    generate
        for(idx=0;idx<$bits(dbg_err_flag);idx++)begin :dbg_err_flag_i
                assert property (@(posedge clk) disable iff (rst) (~(dbg_err_flag[idx]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, err_flag:%d, id:%d", $time, dbg_err_flag[idx], idx));
        end
    endgenerate

    assign dfx_status= {
        desc_buf_dfx_status,//4bits
        submit_cstat,  //4bits
        cstat,  //4bits
        cpl_cstat,  //5bits
        rsp_desc_cstat,  //5bits
        dma_desc_rd_req_if.sav, 
        slot_submit_rdy, 
        slot_cpl_sav, 
        rd_desc_req_rdy, 
        rd_desc_rsp_rdy, 
        info_rd_rdy, 
        angry_cnt, //6bits
        standby, 
        slot_cpl_ff_pfull, 
        slot_cpl_ff_empty, 
        wake_up_ff_pfull, 
        wake_up_ff_empty, 
        wake_up_ff_usedw, //6bits
        bucket_id_ff_pfull, 
        bucket_id_ff_empty, 
        bucket_id_ff_usedw, //8bits
        forced_shutdown_ff_pfull, 
        forced_shutdown_ff_empty, 
        forced_shutdown_ff_usedw //6bits
    };

endmodule
