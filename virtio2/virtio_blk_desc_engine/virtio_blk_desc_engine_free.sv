/******************************************************************************
 * 文件名称 : virtio_blk_desc_engine_free.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/07/07
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   07/07      Liuch       初始化版本
 ******************************************************************************/
`include "virtio_define.svh"
`include "virtio_blk_desc_engine_define.svh"
module virtio_blk_desc_engine_free #(
    parameter DATA_WIDTH        = 256,
    parameter QID_NUM           = 256,
    parameter QID_WIDTH         = $clog2(QID_NUM),
    parameter SLOT_NUM          = 4,
    parameter SLOT_ID_WIDTH     = $clog2(SLOT_NUM),
    parameter SLOT_ID_FF_WIDTH  = $clog2(SLOT_NUM),
    parameter SLOT_ID_FF_DEPTH  = SLOT_NUM,
    parameter SLOT_ID_FF_USEDW  = $clog2(SLOT_ID_FF_DEPTH + 1),
    parameter SLOT_CPL_FF_WIDTH = QID_WIDTH + SLOT_ID_WIDTH + 1 + 8 + 21 + 16 + 16,
    parameter SLOT_CPL_FF_DEPTH = 32,
    parameter SLOT_CPL_FF_USEDW = $clog2(SLOT_CPL_FF_DEPTH + 1),
    parameter LINE_NUM          = 8,
    parameter LINE_WIDTH        = $clog2(LINE_NUM),
    parameter BUCKET_NUM        = 4,
    parameter BUCKET_WIDTH      = $clog2(BUCKET_NUM),
    parameter DESC_BUF_DEPTH    = (BUCKET_NUM * LINE_NUM)
) (
    input  logic                                                                                                    clk,
    input  logic                                                                                                    rst,
    // slot_id_ff_rd
    input  logic                                                                                                    slot_id_ff_rden,
    output logic                                [SLOT_ID_FF_WIDTH-1:0]                                              slot_id_ff_dout,
    output logic                                                                                                    slot_id_ff_empty,
    output logic                                                                                                    slot_id_ff_cycle_flag,
    // slot_order_ff_rd
    output logic                                                                                                    slot_order_ff_rden,
    input  logic                                [SLOT_ID_FF_WIDTH-1:0]                                              slot_order_ff_dout,
    input  logic                                                                                                    slot_order_ff_empty,
    // slot_cpl_ff_rd
    // output logic                                                                                              slot_cpl_ff_rden,
    // input  logic                          [SLOT_CPL_FF_WIDTH-1:0]                                             slot_cpl_ff_dout,
    // input  logic                                                                                              slot_cpl_ff_empty,
    output logic                                [SLOT_ID_WIDTH-1:0]                                                 slot_cpl_ram_raddr,
    input  logic                                [SLOT_CPL_FF_WIDTH:0]                                               slot_cpl_ram_rdata,
    // desc_ram_rd
    output logic                                [$clog2(DESC_BUF_DEPTH)+$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:0] desc_buf_rd_req_addr,
    output logic                                                                                                    desc_buf_rd_req_vld,
    input  virtq_desc_t                                                                                             desc_buf_rd_rsp_dat,
    input  logic                                                                                                    desc_buf_rd_rsp_vld,
    // blk_desc
    output logic                                                                                                    blk_desc_vld,
    input  logic                                                                                                    blk_desc_rdy,
    output logic                                                                                                    blk_desc_sop,
    output logic                                                                                                    blk_desc_eop,
    output virtio_desc_eng_desc_rsp_sbd_t                                                                           blk_desc_sbd,
    output virtq_desc_t                                                                                             blk_desc_dat,
    output virtio_blk_desc_engine_free_status_t                                                                     state,
    output virtio_blk_desc_engine_free_err_t                                                                        err

);

    enum logic [1:0] {
        SLOT_FF_INIT = 2'b01,
        SLOT_FF_RUN  = 2'b10
    }
        slot_ff_cstat, slot_ff_nstat;

    enum logic [4:0] {
        BLK_DESC_IDLE    = 5'b00001,
        BLK_DESC_ERR     = 5'b00010,
        BLK_DESC_OUT     = 5'b00100,
        BLK_DESC_DELAY   = 5'b01000,
        BLK_DESC_RD_FIFO = 5'b10000
    }
        blk_desc_cstat, blk_desc_nstat;

    logic                          [SLOT_ID_WIDTH-1:0]                                                 cpl_slot;
    logic                          [QID_WIDTH-1:0]                                                     cpl_qid;
    logic                                                                                              cpl_forced_shutdown;
    virtio_err_info_t                                                                                  cpl_err_info;
    logic                          [15:0]                                                              cpl_desc_cnt;
    logic                          [20:0]                                                              cpl_data_len;
    logic                          [15:0]                                                              cpl_id;

    logic                          [15:0]                                                              vld_cnt;

    logic                          [$clog2(DESC_BUF_DEPTH)+$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:0] desc_buf_rd_req_addr_old;
    logic                          [$clog2(DESC_BUF_DEPTH)+$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:0] desc_buf_rd_req_addr_new;

    // u_slot_id_ff
    logic                                                                                              slot_id_ff_wren;
    logic                          [SLOT_ID_FF_WIDTH-1:0]                                              slot_id_ff_din;
    logic                                                                                              slot_id_ff_full;
    logic                                                                                              slot_id_ff_pfull;
    logic                                                                                              slot_id_ff_overflow;
    // logic                        slot_id_ff_rden;
    // logic [SLOT_ID_FF_WIDTH-1:0] slot_id_ff_dout;
    // logic                        slot_id_ff_empty;
    logic                                                                                              slot_id_ff_empty_init;
    logic                                                                                              slot_id_ff_pempty;
    logic                                                                                              slot_id_ff_underflow;
    logic                          [SLOT_ID_FF_USEDW-1:0]                                              slot_id_ff_usedw;
    logic                          [1:0]                                                               slot_id_ff_err;

    logic                          [SLOT_ID_FF_WIDTH-1:0]                                              slot_id_init_cnt;

    logic                                                                                              slot_cpl_ff_rden;
    logic                          [SLOT_CPL_FF_WIDTH-1:0]                                             slot_cpl_ff_dout;
    logic                                                                                              slot_cpl_ff_empty;
    logic                                                                                              cycle_flag;


    logic                                                                                              blk_desc_vld_d;
    logic                                                                                              blk_desc_rdy_d;
    logic                                                                                              blk_desc_sop_d;
    logic                                                                                              blk_desc_eop_d;
    virtio_desc_eng_desc_rsp_sbd_t                                                                     blk_desc_sbd_d;
    virtq_desc_t                                                                                       blk_desc_dat_d;


    always @(posedge clk) begin
        if (rst) begin
            cycle_flag <= 1'b1;
        end else if (slot_cpl_ff_rden && slot_cpl_ram_raddr == SLOT_NUM - 1) begin
            cycle_flag <= ~cycle_flag;
        end
    end

    assign slot_cpl_ram_raddr  = slot_order_ff_dout;
    assign slot_cpl_ff_empty   = slot_cpl_ram_rdata[SLOT_CPL_FF_WIDTH] != cycle_flag || slot_order_ff_empty;
    assign slot_cpl_ff_dout    = slot_cpl_ram_rdata[SLOT_CPL_FF_WIDTH-1:0];

    assign cpl_slot            = slot_cpl_ff_dout[70+:SLOT_ID_WIDTH];
    assign cpl_qid             = slot_cpl_ff_dout[62+:8];
    assign cpl_forced_shutdown = slot_cpl_ff_dout[61+:1];
    assign cpl_err_info        = slot_cpl_ff_dout[53+:8];
    assign cpl_desc_cnt        = slot_cpl_ff_dout[37+:16];
    assign cpl_data_len        = slot_cpl_ff_dout[16+:21];
    assign cpl_id              = slot_cpl_ff_dout[0+:16];


    assign slot_cpl_ff_rden    = blk_desc_cstat == BLK_DESC_RD_FIFO;
    assign slot_order_ff_rden  = blk_desc_cstat == BLK_DESC_RD_FIFO;


    always @(posedge clk) begin
        if (rst) begin
            blk_desc_cstat <= BLK_DESC_IDLE;
        end else begin
            blk_desc_cstat <= blk_desc_nstat;
        end
    end

    always @(*) begin
        blk_desc_nstat = blk_desc_cstat;
        case (blk_desc_cstat)
            BLK_DESC_DELAY: begin
                if (!slot_order_ff_empty) begin
                    blk_desc_nstat = BLK_DESC_IDLE;
                end
            end
            BLK_DESC_IDLE: begin
                if (!slot_cpl_ff_empty) begin
                    if (!cpl_forced_shutdown && cpl_err_info.err_code == VIRTIO_ERR_CODE_NONE) begin
                        blk_desc_nstat = BLK_DESC_OUT;
                    end else begin
                        blk_desc_nstat = BLK_DESC_ERR;
                    end
                end
            end
            BLK_DESC_ERR: begin
                if (blk_desc_vld_d && blk_desc_rdy_d && blk_desc_eop_d) begin
                    blk_desc_nstat = BLK_DESC_RD_FIFO;
                end
            end
            BLK_DESC_OUT: begin
                if (blk_desc_vld_d && blk_desc_rdy_d && blk_desc_eop_d) begin
                    blk_desc_nstat = BLK_DESC_RD_FIFO;
                end
            end
            BLK_DESC_RD_FIFO: begin
                blk_desc_nstat = BLK_DESC_DELAY;
            end

            default: blk_desc_nstat = BLK_DESC_DELAY;
        endcase
    end
    assign blk_desc_vld_d = blk_desc_cstat == BLK_DESC_ERR || blk_desc_cstat == BLK_DESC_OUT;
    assign blk_desc_rdy_d = blk_desc_rdy || !blk_desc_vld;

    always @(posedge clk) begin
        if (rst) begin
            blk_desc_vld <= 1'b0;
        end else if (blk_desc_rdy || !blk_desc_vld) begin
            blk_desc_vld <= blk_desc_vld_d;
        end
    end

    always @(posedge clk) begin
        if (blk_desc_rdy || !blk_desc_vld) begin
            blk_desc_sop <= blk_desc_sop_d;
            blk_desc_eop <= blk_desc_eop_d;
            blk_desc_sbd <= blk_desc_sbd_d;
            blk_desc_dat <= blk_desc_dat_d;
        end
    end

    assign desc_buf_rd_req_vld = 1'b1;
    assign blk_desc_dat_d      = desc_buf_rd_rsp_dat;
    always @(*) begin
        if (blk_desc_cstat == BLK_DESC_IDLE) begin
            desc_buf_rd_req_addr = cpl_slot << 4;
        end else begin
            if (blk_desc_rdy_d) begin
                desc_buf_rd_req_addr = desc_buf_rd_req_addr_new;
            end else begin
                desc_buf_rd_req_addr = desc_buf_rd_req_addr_old;
            end
        end
    end

    always @(posedge clk) begin
        if (blk_desc_cstat == BLK_DESC_IDLE) begin
            desc_buf_rd_req_addr_old <= cpl_slot << 4;
            desc_buf_rd_req_addr_new <= (cpl_slot << 4) + 'd1;
        end else begin
            if (blk_desc_rdy_d) begin
                desc_buf_rd_req_addr_old <= desc_buf_rd_req_addr_new;
                desc_buf_rd_req_addr_new <= desc_buf_rd_req_addr_new + 'd1;
            end
        end
    end

    assign blk_desc_sop_d = desc_buf_rd_req_addr_old == cpl_slot << 4;

    always @(posedge clk) begin
        if (blk_desc_cstat == BLK_DESC_IDLE) begin
            vld_cnt <= 1'b1;
        end else begin
            if (blk_desc_rdy_d) begin
                vld_cnt <= vld_cnt + 'd1;
            end
        end
    end

    always @(*) begin
        if (blk_desc_cstat == BLK_DESC_ERR) begin
            blk_desc_eop_d = 1'b1;
        end else begin
            blk_desc_eop_d = vld_cnt == cpl_desc_cnt;
        end
    end


    always @(posedge clk) begin
        if (blk_desc_cstat == BLK_DESC_IDLE) begin
            blk_desc_sbd_d.vq.typ           <= VIRTIO_BLK_TYPE;  // no use?
            blk_desc_sbd_d.vq.qid           <= cpl_qid;
            blk_desc_sbd_d.dev_id           <= 0;  // no use?
            blk_desc_sbd_d.pkt_id           <= 0;  // no use?
            blk_desc_sbd_d.total_buf_length <= cpl_data_len;
            blk_desc_sbd_d.valid_desc_cnt   <= cpl_desc_cnt;  // no use?
            blk_desc_sbd_d.ring_id          <= cpl_id;
            blk_desc_sbd_d.avail_idx        <= 0;  // no use?
            blk_desc_sbd_d.forced_shutdown  <= cpl_forced_shutdown;
            blk_desc_sbd_d.err_info         <= cpl_err_info;
        end
    end










    yucca_sync_fifo #(
        .DATA_WIDTH(SLOT_ID_FF_WIDTH),
        .FIFO_DEPTH(SLOT_ID_FF_DEPTH),
        .CHECK_ON  (1),
        .CHECK_MODE("parity"),
        .RAM_MODE  ("dist"),
        .FIFO_MODE ("fwft")
    ) u_slot_id_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (slot_id_ff_wren),
        .din           (slot_id_ff_din),
        .full          (slot_id_ff_full),
        .pfull         (slot_id_ff_pfull),
        .overflow      (slot_id_ff_overflow),
        .rden          (slot_id_ff_rden),
        .dout          (slot_id_ff_dout),
        .empty         (slot_id_ff_empty_init),
        .pempty        (slot_id_ff_pempty),
        .underflow     (slot_id_ff_underflow),
        .usedw         (slot_id_ff_usedw),
        .parity_ecc_err(slot_id_ff_err)
    );
    always @(posedge clk) begin
        if (rst) begin
            slot_id_ff_cycle_flag <= 'b0;
        end else if (slot_id_ff_dout == SLOT_NUM - 1 && slot_id_ff_rden) begin
            slot_id_ff_cycle_flag <= ~slot_id_ff_cycle_flag;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            slot_ff_cstat <= SLOT_FF_INIT;
        end else begin
            slot_ff_cstat <= slot_ff_nstat;
        end
    end

    always @(*) begin
        slot_ff_nstat = slot_ff_cstat;
        case (slot_ff_cstat)
            SLOT_FF_INIT:
            if (slot_id_init_cnt == SLOT_NUM - 1) begin
                slot_ff_nstat = SLOT_FF_RUN;
            end
            SLOT_FF_RUN: ;
            default: slot_ff_nstat = SLOT_FF_INIT;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            slot_id_init_cnt <= 'b0;
        end else begin
            slot_id_init_cnt <= slot_id_init_cnt + 1;
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            slot_id_ff_wren <= 1'b0;
        end else begin
            slot_id_ff_wren <= slot_ff_cstat == SLOT_FF_INIT || (blk_desc_vld_d && blk_desc_rdy_d && blk_desc_eop_d);
        end
        slot_id_ff_din <= slot_ff_cstat == SLOT_FF_INIT ? slot_id_init_cnt : slot_order_ff_dout;
    end

    assign slot_id_ff_empty = slot_id_ff_empty_init || slot_ff_cstat != SLOT_FF_RUN;



    // assign state            = {blk_desc_cstat, slot_ff_cstat};
    // assign err              = {4'b0, slot_id_ff_underflow, slot_id_ff_overflow, slot_id_ff_err};


    always @(posedge clk) begin
        state.blk_desc_vld      <= blk_desc_vld;
        state.blk_desc_rdy      <= blk_desc_rdy;
        state.slot_cpl_ff_empty <= slot_cpl_ff_empty;
        state.slot_id_ff_usedw  <= slot_id_ff_usedw;
        state.blk_desc_cstat    <= blk_desc_cstat;
        state.slot_ff_cstat     <= slot_ff_cstat;
    end


    always @(posedge clk) begin
        err.slot_id_ff_underflow <= slot_id_ff_underflow;
        err.slot_id_ff_overflow  <= slot_id_ff_overflow;
        err.slot_id_ff_err       <= slot_id_ff_err;
    end

    genvar err_idx;
    generate
        for (err_idx = 0; err_idx < $bits(err); err_idx++) begin : db_err_i
            assert property (@(posedge clk) disable iff (rst) (~(err[err_idx] === 1'b1)))
            else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, err[err_idx], err_idx));
        end
    endgenerate

endmodule : virtio_blk_desc_engine_free
