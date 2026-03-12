/******************************************************************************
 * 文件名称 : virtio_blk_desc_engine_alloc.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/07/07
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   07/07      Liuch       初始化版本
 ******************************************************************************/
`include "../virtio_define.svh"
`include "virtio_blk_desc_engine_define.svh"
module virtio_blk_desc_engine_alloc #(
    parameter QID_NUM = 256,
    parameter QID_WIDTH = $clog2(QID_NUM),
    parameter SLOT_NUM = 4,
    parameter SLOT_ID_WIDTH = $clog2(SLOT_NUM),
    parameter SLOT_ID_FF_WIDTH = SLOT_ID_WIDTH,
    parameter SLOT_ID_FF_DEPTH = SLOT_NUM,
    parameter SLOT_ID_FF_USEDW = $clog2(SLOT_ID_FF_DEPTH + 1)
) (
    input  logic                                                        clk,
    input  logic                                                        rst,
    // alloc_slot_req
    input  logic                                                        alloc_slot_req_vld,
    output logic                                                        alloc_slot_req_rdy,
    input  virtio_vq_t                                                  alloc_slot_req_vq,
    // alloc_slot_rsp
    output logic                                                        alloc_slot_rsp_vld,
    input  logic                                                        alloc_slot_rsp_rdy,
    output virtio_desc_eng_slot_rsp_t                                   alloc_slot_rsp_dat,
    // avail_id_req
    output logic                                                        avail_id_req_vld,
    input  logic                                                        avail_id_req_rdy,
    output logic                                 [QID_WIDTH-1:0]        avail_id_req_vq,
    // avail_id_rsp
    input  logic                                                        avail_id_rsp_vld,
    output logic                                                        avail_id_rsp_rdy,
    input  virtio_avail_id_rsp_dat_t                                    avail_id_rsp_dat,
    // slot_id_ff_rd
    output logic                                                        slot_id_ff_rden,
    input  logic                                 [SLOT_ID_FF_WIDTH-1:0] slot_id_ff_dout,
    input  logic                                                        slot_id_ff_cycle_flag,
    input  logic                                                        slot_id_ff_empty,
    // first_submit
    output logic                                                        first_submit_vld,
    input  logic                                                        first_submit_rdy,
    output logic                                 [QID_WIDTH-1:0]        first_submit_qid,
    output logic                                 [15:0]                 first_submit_idx,
    output logic                                 [15:0]                 first_submit_id,
    output logic                                                        first_submit_resummer,
    output logic                                 [SLOT_ID_WIDTH-1:0]    first_submit_slot_id,
    output logic                                                        first_submit_cycle_flag,
    // slot_order_ff_rd
    input  logic                                                        slot_order_ff_rden,
    output logic                                 [SLOT_ID_FF_WIDTH-1:0] slot_order_ff_dout,
    output logic                                                        slot_order_ff_empty,
    // blk_desc_resummer_rd_req
    output logic                                                        blk_desc_resummer_rd_req_vld,
    output logic                                 [QID_WIDTH-1:0]        blk_desc_resummer_rd_req_qid,
    // blk_desc_resummer_rd_rsp
    input  logic                                                        blk_desc_resummer_rd_rsp_vld,
    input  logic                                                        blk_desc_resummer_rd_rsp_dat,
    output virtio_blk_desc_engine_alloc_status_t                        state,
    output virtio_blk_desc_engine_alloc_err_t                           err,
    input  logic                                                        flush_resummer
);
    // 如果不ok  直接返回cold 不能获取id. id是在获取之后再获取


    localparam AVAIL_ID_FF_WIDTH = QID_WIDTH + 1;
    localparam AVAIL_ID_FF_DEPTH = 32;
    localparam AVAIL_ID_FF_USEDW = $clog2(AVAIL_ID_FF_DEPTH + 1);

    logic [QID_WIDTH-1:0]         qid;
    logic                         resumer_flag;


    // avail_id_ff
    logic                         avail_id_ff_wren;
    logic [AVAIL_ID_FF_WIDTH-1:0] avail_id_ff_din;
    logic                         avail_id_ff_full;
    // logic                         avail_id_ff_pfull;
    logic                         avail_id_ff_overflow;
    logic                         avail_id_ff_rden;
    logic [AVAIL_ID_FF_WIDTH-1:0] avail_id_ff_dout;
    logic                         avail_id_ff_empty;
    // logic                         avail_id_ff_pempty;
    logic                         avail_id_ff_underflow;
    logic [AVAIL_ID_FF_USEDW-1:0] avail_id_ff_usedw;
    logic [1:0]                   avail_id_ff_err;

    logic [QID_WIDTH-1:0]         avail_id_ff_out_qid;
    logic                         avail_id_ff_out_resumer_flag;


    // u_slot_order_ff
    logic                         slot_order_ff_wren;
    logic [SLOT_ID_FF_WIDTH-1:0]  slot_order_ff_din;
    // logic                         slot_order_ff_full;
    // logic                         slot_order_ff_pfull;
    logic                         slot_order_ff_overflow;
    // logic                         slot_order_ff_rden;
    // logic [SLOT_ID_FF_WIDTH-1:0]  slot_order_ff_dout;
    // logic                         slot_order_ff_empty;
    // logic                         slot_order_ff_pempty;
    logic                         slot_order_ff_underflow;
    logic [SLOT_ID_FF_USEDW-1:0]  slot_order_ff_usedw;
    logic [1:0]                   slot_order_ff_err;

    enum logic [2:0] {
        RESUMMER_RDCTXREQ = 3'b001,
        RESUMMER_RDCTXRSP = 3'b010,
        RESUMMER_SENDREQ  = 3'b100
    }
        resumer_cstat, resumer_nstat;

    enum logic [2:0] {
        AVAIL_RSP = 3'b001,
        ALLOC_RSP = 3'b010,
        SUBMIT    = 3'b100
    }
        alloc_rsp_cstat, alloc_rsp_nstat;


    assign alloc_slot_req_rdy = !avail_id_ff_full && resumer_cstat == RESUMMER_RDCTXREQ && !flush_resummer;


    always @(posedge clk) begin
        if (alloc_slot_req_vld && alloc_slot_req_rdy && !flush_resummer) begin
            qid <= alloc_slot_req_vq.qid;
        end
    end

    assign blk_desc_resummer_rd_req_vld = alloc_slot_req_vld && alloc_slot_req_rdy && !flush_resummer;
    assign blk_desc_resummer_rd_req_qid = alloc_slot_req_vq.qid;

    always @(posedge clk) begin
        if (rst) begin
            resumer_cstat <= RESUMMER_RDCTXREQ;
        end else begin
            resumer_cstat <= resumer_nstat;
        end
    end

    always @(*) begin
        resumer_nstat = resumer_cstat;
        case (resumer_cstat)
            RESUMMER_RDCTXREQ: begin
                if (alloc_slot_req_vld && alloc_slot_req_rdy && !flush_resummer) begin
                    resumer_nstat = RESUMMER_RDCTXRSP;
                end
            end
            RESUMMER_RDCTXRSP: begin
                if (blk_desc_resummer_rd_rsp_vld) begin
                    resumer_nstat = RESUMMER_SENDREQ;
                end
            end
            RESUMMER_SENDREQ: begin
                if (avail_id_req_rdy || resumer_flag) begin
                    resumer_nstat = RESUMMER_RDCTXREQ;
                end
            end
            default: resumer_nstat = RESUMMER_RDCTXREQ;
        endcase
    end

    always @(posedge clk) begin
        if (blk_desc_resummer_rd_rsp_vld) begin
            resumer_flag <= blk_desc_resummer_rd_rsp_dat;
        end
    end

    assign avail_id_req_vld = resumer_cstat == RESUMMER_SENDREQ && !resumer_flag;
    // assign avail_id_req_vq.typ = VIRTIO_BLK_TYPE;
    assign avail_id_req_vq  = qid;

    yucca_sync_fifo #(
        .DATA_WIDTH(AVAIL_ID_FF_WIDTH),
        .FIFO_DEPTH(AVAIL_ID_FF_DEPTH),
        .CHECK_ON  (1),
        .CHECK_MODE("parity"),
        // .DEPTH_PFULL(),
        .RAM_MODE  ("dist"),
        .FIFO_MODE ("fwft")
    ) u_avail_id_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (avail_id_ff_wren),
        .din           (avail_id_ff_din),
        .full          (avail_id_ff_full),
        .pfull         (),
        // .pfull         (avail_id_ff_pfull),
        .overflow      (avail_id_ff_overflow),
        .rden          (avail_id_ff_rden),
        .dout          (avail_id_ff_dout),
        .empty         (avail_id_ff_empty),
        .pempty        (),
        // .pempty        (avail_id_ff_pempty),
        .underflow     (avail_id_ff_underflow),
        .usedw         (avail_id_ff_usedw),
        .parity_ecc_err(avail_id_ff_err)
    );

    assign avail_id_ff_wren             = resumer_cstat == RESUMMER_SENDREQ && (avail_id_req_rdy || resumer_flag);
    assign avail_id_ff_din              = {resumer_flag, qid};

    assign avail_id_ff_rden             = alloc_rsp_cstat == AVAIL_RSP && !avail_id_ff_empty && (avail_id_ff_out_resumer_flag || avail_id_rsp_vld);
    assign avail_id_ff_out_qid          = avail_id_ff_dout[0+:QID_WIDTH];
    assign avail_id_ff_out_resumer_flag = avail_id_ff_dout[QID_WIDTH+:1];


    assign avail_id_rsp_rdy             = alloc_rsp_cstat == AVAIL_RSP && !avail_id_ff_empty && !avail_id_ff_out_resumer_flag;


    always @(posedge clk) begin
        if (rst) begin
            alloc_rsp_cstat <= AVAIL_RSP;
        end else begin
            alloc_rsp_cstat <= alloc_rsp_nstat;
        end
    end

    always @(*) begin
        alloc_rsp_nstat = alloc_rsp_cstat;
        case (alloc_rsp_cstat)
            AVAIL_RSP: begin
                if (avail_id_ff_rden) begin
                    alloc_rsp_nstat = ALLOC_RSP;
                end
            end
            ALLOC_RSP: begin
                if (alloc_slot_rsp_vld && alloc_slot_rsp_rdy) begin
                    alloc_rsp_nstat = SUBMIT;
                end
            end
            SUBMIT: begin
                if ((first_submit_rdy && !slot_id_ff_empty) || !first_submit_vld) begin
                    alloc_rsp_nstat = AVAIL_RSP;
                end
            end

            default: alloc_rsp_nstat = AVAIL_RSP;
        endcase
    end


    assign alloc_slot_rsp_vld                   = alloc_rsp_cstat == ALLOC_RSP && !slot_id_ff_empty;

    assign slot_id_ff_rden                      = alloc_rsp_cstat == SUBMIT && alloc_slot_rsp_dat.ok && first_submit_rdy && !slot_id_ff_empty;
    assign alloc_slot_rsp_dat.pkt_id            = 0;
    assign alloc_slot_rsp_dat.ok                = alloc_slot_rsp_dat.q_stat_doing && alloc_slot_rsp_dat.err_info.err_code == VIRTIO_ERR_CODE_NONE && !alloc_slot_rsp_dat.local_ring_empty && !alloc_slot_rsp_dat.avail_ring_empty;
    assign alloc_slot_rsp_dat.desc_engine_limit = 0;


    always @(posedge clk) begin
        if (avail_id_ff_rden) begin
            alloc_slot_rsp_dat.vq.typ <= VIRTIO_BLK_TYPE;
            alloc_slot_rsp_dat.vq.qid <= avail_id_ff_out_qid;
            if (avail_id_ff_out_resumer_flag) begin
                alloc_slot_rsp_dat.local_ring_empty  <= 0;
                alloc_slot_rsp_dat.avail_ring_empty  <= 0;
                alloc_slot_rsp_dat.q_stat_doing      <= 1;
                alloc_slot_rsp_dat.q_stat_stopping   <= 0;
                alloc_slot_rsp_dat.err_info.fatal    <= 0;
                alloc_slot_rsp_dat.err_info.err_code <= VIRTIO_ERR_CODE_NONE;
            end else begin
                alloc_slot_rsp_dat.local_ring_empty  <= avail_id_rsp_dat.local_ring_empty;
                alloc_slot_rsp_dat.avail_ring_empty  <= avail_id_rsp_dat.avail_ring_empty;
                alloc_slot_rsp_dat.q_stat_doing      <= avail_id_rsp_dat.q_stat_doing;
                alloc_slot_rsp_dat.q_stat_stopping   <= avail_id_rsp_dat.q_stat_stopping;
                alloc_slot_rsp_dat.err_info.fatal    <= avail_id_rsp_dat.err_info.fatal;
                alloc_slot_rsp_dat.err_info.err_code <= avail_id_rsp_dat.err_info.err_code;
            end
        end
    end



    assign first_submit_vld        = alloc_rsp_cstat == SUBMIT && alloc_slot_rsp_dat.ok;
    assign first_submit_slot_id    = slot_id_ff_dout;
    assign first_submit_cycle_flag = slot_id_ff_cycle_flag;

    always @(posedge clk) begin
        if (avail_id_ff_rden) begin
            first_submit_qid      <= avail_id_ff_out_qid;
            first_submit_resummer <= avail_id_ff_out_resumer_flag;
            first_submit_idx      <= avail_id_rsp_dat.avail_idx;
            first_submit_id       <= avail_id_rsp_dat.id;
        end
    end

    yucca_sync_fifo #(
        .DATA_WIDTH(SLOT_ID_FF_WIDTH),
        .FIFO_DEPTH(SLOT_ID_FF_DEPTH),
        .CHECK_ON  (1),
        .CHECK_MODE("parity"),
        // .DEPTH_PFULL(),
        .RAM_MODE  ("dist"),
        .FIFO_MODE ("fwft")
    ) u_slot_order_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (slot_order_ff_wren),
        .din           (slot_order_ff_din),
        .full          (),
        // .full          (slot_order_ff_full),
        .pfull         (),
        // .pfull         (slot_order_ff_pfull),
        .overflow      (slot_order_ff_overflow),
        .rden          (slot_order_ff_rden),
        .dout          (slot_order_ff_dout),
        .empty         (slot_order_ff_empty),
        .pempty        (),
        // .pempty        (slot_order_ff_pempty),
        .underflow     (slot_order_ff_underflow),
        .usedw         (slot_order_ff_usedw),
        .parity_ecc_err(slot_order_ff_err)
    );

    assign slot_order_ff_wren = slot_id_ff_rden;
    assign slot_order_ff_din  = slot_id_ff_dout;


    logic avail_id_err;
    assign avail_id_err = avail_id_ff_rden && !avail_id_ff_out_resumer_flag && avail_id_ff_out_qid != avail_id_rsp_dat.vq.qid;

    always @(posedge clk) begin
        state.alloc_slot_req_vld    <= alloc_slot_req_vld;
        state.alloc_slot_req_rdy    <= alloc_slot_req_rdy;
        state.alloc_slot_rsp_vld    <= alloc_slot_rsp_vld;
        state.alloc_slot_rsp_rdy    <= alloc_slot_rsp_rdy;
        state.avail_id_req_vld      <= avail_id_req_vld;
        state.avail_id_req_rdy      <= avail_id_req_rdy;
        state.avail_id_rsp_vld      <= avail_id_rsp_vld;
        state.avail_id_rsp_rdy      <= avail_id_rsp_rdy;
        state.first_submit_vld      <= first_submit_vld;
        state.first_submit_rdy      <= first_submit_rdy;
        state.avail_id_ff_full      <= avail_id_ff_full;
        state.avail_id_ff_empty     <= avail_id_ff_empty;
        state.slot_order_ff_usedw   <= slot_order_ff_usedw;
        state.alloc_rsp_cstat       <= alloc_rsp_cstat;
        state.resumer_cstat         <= resumer_cstat;

        err.avail_id_err            <= avail_id_err;
        err.slot_order_ff_overflow  <= slot_order_ff_overflow;
        err.slot_order_ff_underflow <= slot_order_ff_underflow;
        err.slot_order_ff_err       <= slot_order_ff_err;
        err.avail_id_ff_overflow    <= avail_id_ff_overflow;
        err.avail_id_ff_underflow   <= avail_id_ff_underflow;
        err.avail_id_ff_err         <= avail_id_ff_err;
    end


    genvar err_idx;
    generate
        for (err_idx = 0; err_idx < $bits(err); err_idx++) begin : db_err_i
            assert property (@(posedge clk) disable iff (rst) (~(err[err_idx] === 1'b1)))
            else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, err[err_idx], err_idx));
        end
    endgenerate

endmodule : virtio_blk_desc_engine_alloc
