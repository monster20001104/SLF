/******************************************************************************
 * 文件名称 : virtio_rx_buf_drop.sv
 * 作者名称 : lch
 * 创建日期 : 2025/06/23
 * 功能描述 : frame_drop
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   06/23       lch         初始化版本
 ******************************************************************************/
`include "virtio_rx_buf_define.svh"
module virtio_rx_buf_drop #(
    parameter DATA_WIDTH   = 256,
    parameter GEN_WIDTH    = 8,
    parameter QID_NUM      = 256,
    parameter UID_NUM      = 1024,
    parameter DEV_NUM      = 1024,
    parameter BKT_FF_DEPTH = 1024,
    // local
    parameter EMPTH_WIDTH  = $clog2(DATA_WIDTH / 8),
    parameter QID_WIDTH    = $clog2(QID_NUM),
    parameter UID_WIDTH    = $clog2(UID_NUM),
    parameter DEV_WIDTH    = $clog2(DEV_NUM),
    parameter BKT_FF_WIDTH = $clog2(BKT_FF_DEPTH),
    parameter BKT_FF_USEDW = $clog2(BKT_FF_DEPTH + 1)
) (
    input  logic                                        clk,
    input  logic                                        rst,
    //
    output logic                                        csum_data_ff_rden,
    input  logic                                        csum_data_ff_sop,
    input  logic                                        csum_data_ff_eop,
    input  logic                     [EMPTH_WIDTH-1:0]  csum_data_ff_mty,
    input  logic                     [DATA_WIDTH-1:0]   csum_data_ff_data,
    input  logic                                        csum_data_ff_empty,
    //
    output logic                                        csum_info_ff_rden,
    input  logic                                        csum_info_ff_csum_pass,
    input  logic                                        csum_info_ff_trans_csum_pass,
    input  logic                     [QID_WIDTH-1:0]    csum_info_ff_vq_gid,
    input  logic                     [GEN_WIDTH-1:0]    csum_info_ff_vq_gen,
    input  logic                     [18-1:0]           csum_info_ff_length,
    input  logic                                        csum_info_ff_empty,
    // drop_info_rd_req
    output logic                                        drop_info_rd_req_vld,
    output logic                     [8-1:0]            drop_info_rd_req_qid,
    // drop_info_rd_rsp
    input  logic                                        drop_info_rd_rsp_vld,
    input  logic                     [7:0]              drop_info_rd_rsp_generation,
    input  logic                     [UID_WIDTH-1:0]    drop_info_rd_rsp_qos_unit,
    input  logic                                        drop_info_rd_rsp_qos_enable,
    // qos_query_req
    output logic                                        qos_query_req_vld,
    input  logic                                        qos_query_req_rdy,
    output logic                     [UID_WIDTH-1:0]    qos_query_req_uid,
    // qos_query_rsp
    input  logic                                        qos_query_rsp_vld,
    input  logic                                        qos_query_rsp_ok,
    output logic                                        qos_query_rsp_rdy,
    // qos_query_update
    output logic                                        qos_update_vld,
    output logic                     [UID_WIDTH-1:0]    qos_update_uid,
    input  logic                                        qos_update_rdy,
    output logic                     [19:0]             qos_update_len,
    output logic                     [7:0]              qos_update_pkt_num,
    // drop_time_ram
    input  logic                     [15:0]             time_stamp,
    input  logic                     [7:0]              drop_time_sel,
    output logic                                        drop_time_ram_rd_en,
    output logic                     [8-1:0]            drop_time_ram_raddr,
    input  logic                     [15:0]             drop_time_ram_rdata,
    output logic                     [8-1:0]            idx_per_queue_raddr,
    input  logic                     [15:0]             idx_per_queue_rdata,
    // drop_random
    input  logic                     [7:0]              drop_random_sel,
    input  logic                     [BKT_FF_USEDW-1:0] bkt_ff_usedw,
    input  logic                                        bkt_ff_pempty,
    // csum_flag
    input  logic                                        rx_buf_csum_flag,
    // drop_data
    input  logic                                        drop_data_ff_rden,
    output logic                                        drop_data_ff_sop,
    output logic                                        drop_data_ff_eop,
    output logic                     [EMPTH_WIDTH-1:0]  drop_data_ff_mty,
    output logic                                        drop_data_proto_csum_pass,
    output logic                     [QID_WIDTH-1:0]    drop_data_ff_gid,
    output logic                     [18-1:0]           drop_data_ff_len,
    output logic                     [DATA_WIDTH-1:0]   drop_data_ff_data,
    output logic                                        drop_data_ff_empty,
    output logic                                        flush,
    // 
    input  logic                                        csum_drop_pkt_ram_rd_req_vld,
    output logic                                        csum_drop_pkt_ram_rd_req_rdy,
    input  logic                     [QID_WIDTH-1:0]    csum_drop_pkt_ram_rd_req_addr,
    input  logic                                        csum_drop_pkt_ram_cnt_clr_en,
    output logic                                        csum_drop_pkt_ram_rd_rsp_vld,
    output logic                     [16-1:0]           csum_drop_pkt_ram_rd_rsp_data,
    //
    input  logic                                        qos_drop_pkt_ram_rd_req_vld,
    output logic                                        qos_drop_pkt_ram_rd_req_rdy,
    input  logic                     [QID_WIDTH-1:0]    qos_drop_pkt_ram_rd_req_addr,
    input  logic                                        qos_drop_pkt_ram_cnt_clr_en,
    output logic                                        qos_drop_pkt_ram_rd_rsp_vld,
    output logic                     [16-1:0]           qos_drop_pkt_ram_rd_rsp_data,
    //
    input  logic                                        buf_full_drop_pkt_ram_rd_req_vld,
    output logic                                        buf_full_drop_pkt_ram_rd_req_rdy,
    input  logic                     [QID_WIDTH-1:0]    buf_full_drop_pkt_ram_rd_req_addr,
    input  logic                                        buf_full_drop_pkt_ram_cnt_clr_en,
    output logic                                        buf_full_drop_pkt_ram_rd_rsp_vld,
    output logic                     [16-1:0]           buf_full_drop_pkt_ram_rd_rsp_data,
    //
    output logic                     [19:0]             csum_drop_pkt_total,
    output logic                     [19:0]             qos_drop_pkt_total,
    output logic                     [19:0]             buf_full_drop_pkt_total,
    //
    output virtio_rx_buf_drop_err_t                     drop_err,
    output virtio_rx_buf_drop_stat_t                    drop_stat
);
    localparam QOS_INFO_FF_WIDTH = 25 + QID_WIDTH + UID_WIDTH;
    localparam QOS_INFO_FF_DEPTH = 32;
    localparam QOS_INFO_FF_USEDW = $clog2(QOS_INFO_FF_DEPTH + 1);

    ////////////////////////////////////////////////////////////////////////////
    // ctx_req_stage
    enum logic [3:0] {
        DROP_CTX_REQ  = 4'b0001,
        DROP_CTX_RSP  = 4'b0010,
        DROP_CTX_CALC = 4'b0100,
        DROP_CTX_VLD  = 4'b1000
    }
        drop_ctx_cstat, drop_ctx_nstat;



    logic                 drop_ctx_vld;
    logic                 drop_ctx_rdy;

    logic                 drop_ctx_gen_flag;  // 1:drop
    logic [UID_WIDTH-1:0] drop_ctx_qos_unit;
    logic                 drop_ctx_qos_enable;
    logic                 drop_ctx_csum_pass;
    logic                 drop_ctx_proto_csum_pass;
    logic [QID_WIDTH-1:0] drop_ctx_vq_gid;
    logic [GEN_WIDTH-1:0] drop_ctx_vq_gen;
    logic [18-1:0]        drop_ctx_length;
    logic                 drop_ctx_time_flag;  // 1:drop
    logic                 drop_ctx_random_flag;  // 1:drop
    logic                 drop_ctx_pfull_flag;  // 1:drop


    assign drop_ctx_csum_pass       = csum_info_ff_csum_pass;
    assign drop_ctx_proto_csum_pass = csum_info_ff_trans_csum_pass;
    assign drop_ctx_vq_gid          = csum_info_ff_vq_gid;
    assign drop_ctx_vq_gen          = csum_info_ff_vq_gen;
    assign drop_ctx_length          = csum_info_ff_length;

    always @(posedge clk) begin
        if (rst) begin
            drop_ctx_cstat <= DROP_CTX_REQ;
        end else begin
            drop_ctx_cstat <= drop_ctx_nstat;
        end
    end

    always @(*) begin
        drop_ctx_nstat = drop_ctx_cstat;
        case (drop_ctx_cstat)
            DROP_CTX_REQ: begin
                if (drop_info_rd_req_vld) begin
                    drop_ctx_nstat = DROP_CTX_RSP;
                end
            end
            DROP_CTX_RSP: begin
                if (drop_info_rd_rsp_vld) begin
                    drop_ctx_nstat = DROP_CTX_CALC;
                end
            end
            DROP_CTX_CALC: begin
                drop_ctx_nstat = DROP_CTX_VLD;
            end
            DROP_CTX_VLD: begin
                if (drop_ctx_vld && drop_ctx_rdy) begin
                    drop_ctx_nstat = DROP_CTX_REQ;
                end
            end
            default: drop_ctx_nstat = DROP_CTX_REQ;
        endcase

    end

    assign drop_info_rd_req_vld = drop_ctx_cstat == DROP_CTX_REQ && !csum_info_ff_empty;
    assign drop_info_rd_req_qid = drop_ctx_vq_gid;
    assign drop_ctx_vld         = drop_ctx_cstat == DROP_CTX_VLD;

    always @(posedge clk) begin
        if (drop_info_rd_rsp_vld) begin
            drop_ctx_gen_flag   <= drop_info_rd_rsp_generation != drop_ctx_vq_gen;
            drop_ctx_qos_unit   <= drop_info_rd_rsp_qos_unit;
            drop_ctx_qos_enable <= drop_info_rd_rsp_qos_enable;
        end
    end

    assign csum_info_ff_rden = drop_ctx_vld && drop_ctx_rdy;

    ////////////////////////////////////////////////////////////////////////////
    // drop_time
    logic [15:0] time_diff;
    logic        idx_per_queue_diff;
    logic        drop_time_pfull;

    assign drop_time_ram_rd_en = drop_info_rd_req_vld;
    assign drop_time_ram_raddr = drop_ctx_vq_gid;
    assign idx_per_queue_raddr = drop_ctx_vq_gid;



    always @(posedge clk) begin
        if (drop_info_rd_rsp_vld) begin
            time_diff          <= time_stamp - drop_time_ram_rdata;
            idx_per_queue_diff <= idx_per_queue_rdata[0+:8] != idx_per_queue_rdata[8+:8];
            drop_time_pfull    <= bkt_ff_usedw[BKT_FF_USEDW-1:BKT_FF_USEDW-2] == 'd0;
        end

    end
    always @(posedge clk) begin
        if (drop_ctx_cstat == DROP_CTX_CALC) begin
            drop_ctx_time_flag <= 0;
            if (idx_per_queue_diff && drop_time_pfull) begin
                case (drop_time_sel)
                    'd0: drop_ctx_time_flag <= 0;
                    'd1: drop_ctx_time_flag <= time_diff > 16'd2;
                    'd2: drop_ctx_time_flag <= time_diff > 16'd4;
                    'd3: drop_ctx_time_flag <= time_diff > 16'd8;
                    'd4: drop_ctx_time_flag <= time_diff > 16'd16;
                    'd5: drop_ctx_time_flag <= time_diff > 16'd32;
                    'd6: drop_ctx_time_flag <= time_diff > 16'd64;
                    'd7: drop_ctx_time_flag <= time_diff > 16'd128;
                    default: drop_ctx_time_flag <= 0;
                endcase
            end
        end
    end


    ////////////////////////////////////////////////////////////////////////////
    // random_seed
    logic [31:0] drop_random;
    lfrs_32_noload u0_lfrs_32_noload (
        .clk_i (clk),
        .rst_i (rst),
        .en_i  (1'b1),
        .seed_i(32'b1),
        .data_o(drop_random)
    );

    always @(posedge clk) begin
        if (drop_info_rd_rsp_vld) begin
            drop_ctx_random_flag <= 0;
            if (bkt_ff_usedw[BKT_FF_USEDW-1:BKT_FF_USEDW-3] == 'd0) begin  // top == 0
                case (drop_random_sel)
                    'd0: drop_ctx_random_flag <= 0;
                    'd1: drop_ctx_random_flag <= drop_random[0+:2] == 'd0;
                    'd2: drop_ctx_random_flag <= drop_random[0+:3] == 'd0;
                    'd3: drop_ctx_random_flag <= drop_random[0+:4] == 'd0;
                    'd4: drop_ctx_random_flag <= drop_random[0+:5] == 'd0;
                    'd5: drop_ctx_random_flag <= drop_random[0+:6] == 'd0;
                    'd6: drop_ctx_random_flag <= drop_random[0+:7] == 'd0;
                    'd7: drop_ctx_random_flag <= drop_random[0+:8] == 'd0;
                    default: drop_ctx_random_flag <= 0;
                endcase
            end
        end
    end
    ////////////////////////////////////////////////////////////////////////////
    // random_pfull
    // always @(posedge clk) begin
    //     if (drop_info_rd_rsp_vld) begin
    //         drop_ctx_pfull_flag <= 0;
    //         if (bkt_ff_pempty) begin
    //             drop_ctx_pfull_flag <= 1;
    //         end
    //     end
    // end

    assign drop_ctx_pfull_flag = 0;

    ////////////////////////////////////////////////////////////////////////////
    // qos_req_stage

    logic                         qos_info_ff_wren;
    logic [QOS_INFO_FF_WIDTH-1:0] qos_info_ff_din;
    logic                         qos_info_ff_full;
    logic                         qos_info_ff_pfull;
    logic                         qos_info_ff_overflow;
    logic                         qos_info_ff_rden;
    logic [QOS_INFO_FF_WIDTH-1:0] qos_info_ff_dout;
    logic                         qos_info_ff_empty;
    logic                         qos_info_ff_pempty;
    logic                         qos_info_ff_underflow;
    logic [QOS_INFO_FF_USEDW-1:0] qos_info_ff_usedw;
    logic [1:0]                   qos_info_ff_err;

    // enum logic [1:0] {
    //     DROP_QOS_REQ = 2'b01,
    //     DROP_QOS_RSP = 2'b10
    // }
    //     drop_qos_cstat, drop_qos_nstat;

    logic                         drop_qos_vld;
    logic                         drop_qos_rdy;

    logic                         drop_qos_qos_enable;

    logic                         drop_qos_gen_flag;  // 1:drop
    logic [DEV_WIDTH-1:0]         drop_qos_qos_unit;  // 1:drop
    logic                         drop_qos_qos_flag;  // 1:drop
    logic                         drop_qos_csum_pass;  // 0:drop
    logic                         drop_qos_time_flag;  // 1:drop
    logic                         drop_qos_random_flag;  // 1:drop
    logic                         drop_qos_pfull_flag;  // 1:drop

    logic                         drop_qos_proto_csum_pass;
    logic [18-1:0]                drop_qos_length;
    logic [8-1:0]                 drop_qos_vq_gid;

    yucca_sync_fifo #(
        .DATA_WIDTH  (QOS_INFO_FF_WIDTH),
        .FIFO_DEPTH  (QOS_INFO_FF_DEPTH),
        .CHECK_ON    (1),
        .CHECK_MODE  ("parity"),
        .DEPTH_PEMPTY(24),
        .RAM_MODE    ("dist"),
        .FIFO_MODE   ("fwft")
    ) u_drop_info_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (qos_info_ff_wren),
        .din           (qos_info_ff_din),
        .full          (qos_info_ff_full),
        // .pfull         (),
        .pfull         (qos_info_ff_pfull),
        .overflow      (qos_info_ff_overflow),
        .rden          (qos_info_ff_rden),
        .dout          (qos_info_ff_dout),
        // .empty         (),
        .empty         (qos_info_ff_empty),
        .pempty        (qos_info_ff_pempty),
        .underflow     (qos_info_ff_underflow),
        .usedw         (qos_info_ff_usedw),
        .parity_ecc_err(qos_info_ff_err)
    );

    // assign drop_info_ff_wren            = drop_info_rd_rsp_vld;
    // assign drop_info_ff_din             = {csum_info_ff_csum_pass, csum_info_ff_trans_csum_pass, csum_info_ff_vq_gid, csum_info_ff_length, (drop_info_rd_rsp_generation != drop_ctx_vq_gen), drop_info_rd_rsp_qos_unit, drop_info_rd_rsp_qos_enable};

    // assign drop_info_ff_csum_pass       = drop_info_ff_dout[21+GEN_WIDTH+QID_WIDTH+:1];
    // assign drop_info_ff_trans_csum_pass = drop_info_ff_dout[20+UID_WIDTH+QID_WIDTH+:1];
    // assign drop_info_ff_vq_gid          = drop_info_ff_dout[20+UID_WIDTH+:QID_WIDTH];
    // assign drop_info_ff_length          = drop_info_ff_dout[2+UID_WIDTH+:18];
    // assign drop_info_ff_gen_flag        = drop_info_ff_dout[1+UID_WIDTH+:1];
    // assign drop_info_ff_qos_unit        = drop_info_ff_dout[1+:UID_WIDTH];
    // assign drop_info_ff_qos_en          = drop_info_ff_dout[0+:1];

    // assign csum_info_ff_rden            = drop_info_ff_wren;
    // // assign drop_info_rd_req_vld  = !drop_info_ff_full && !csum_info_ff_empty;
    // // assign drop_info_rd_req_qid  = csum_info_ff_vq_gid;





    // always @(posedge clk) begin
    //     if (rst) begin
    //         drop_qos_cstat <= DROP_QOS_REQ;
    //     end else begin
    //         drop_qos_cstat <= drop_qos_nstat;
    //     end
    // end

    // always @(*) begin
    //     drop_qos_nstat = drop_qos_cstat;
    //     case (drop_qos_cstat)
    //         DROP_QOS_REQ: begin
    //             if (qos_query_req_vld && qos_query_req_rdy) begin
    //                 drop_qos_nstat = DROP_QOS_RSP;
    //             end
    //         end
    //         DROP_QOS_RSP: begin
    //             if (drop_qos_vld && drop_qos_rdy) begin
    //                 drop_qos_nstat = DROP_QOS_REQ;
    //             end
    //         end
    //         default: drop_qos_nstat = DROP_QOS_REQ;
    //     endcase

    // end







    // assign drop_ctx_rdy      = qos_query_req_rdy;
    assign drop_ctx_rdy             = (qos_query_req_rdy || !drop_ctx_qos_enable) && !qos_info_ff_full;
    assign qos_query_req_vld        = drop_ctx_vld && !qos_info_ff_full && drop_ctx_qos_enable;
    assign qos_query_req_uid        = drop_ctx_qos_unit;

    assign qos_query_rsp_rdy        = drop_qos_rdy && !qos_info_ff_empty && drop_qos_qos_enable;

    assign drop_qos_vld             = (qos_query_rsp_vld && drop_qos_rdy || !drop_qos_qos_enable) && !qos_info_ff_empty;

    assign qos_info_ff_wren         = drop_ctx_vld && drop_ctx_rdy;
    assign qos_info_ff_din          = {drop_ctx_gen_flag, drop_ctx_qos_enable, drop_ctx_csum_pass, drop_ctx_proto_csum_pass, drop_ctx_qos_unit, drop_ctx_vq_gid, drop_ctx_length, drop_ctx_time_flag, drop_ctx_random_flag, drop_ctx_pfull_flag};
    assign qos_info_ff_rden         = drop_qos_vld && drop_qos_rdy;

    assign drop_qos_gen_flag        = qos_info_ff_dout[24+QID_WIDTH+UID_WIDTH+:1];
    assign drop_qos_qos_enable      = qos_info_ff_dout[23+QID_WIDTH+UID_WIDTH+:1];
    assign drop_qos_csum_pass       = qos_info_ff_dout[22+QID_WIDTH+UID_WIDTH+:1];
    assign drop_qos_proto_csum_pass = qos_info_ff_dout[21+QID_WIDTH+UID_WIDTH+:1];
    assign drop_qos_qos_unit        = qos_info_ff_dout[21+QID_WIDTH+:UID_WIDTH];
    assign drop_qos_vq_gid          = qos_info_ff_dout[21+:QID_WIDTH];
    assign drop_qos_length          = qos_info_ff_dout[3+:18];
    assign drop_qos_time_flag       = qos_info_ff_dout[2+:1];
    assign drop_qos_random_flag     = qos_info_ff_dout[1+:1];
    // assign drop_qos_pfull_flag      = qos_info_ff_dout[0+:1];
    assign drop_qos_pfull_flag      = bkt_ff_pempty;
    assign drop_qos_qos_flag        = !qos_query_rsp_ok && drop_qos_qos_enable;

    // always @(posedge clk) begin
    //     if (qos_query_rsp_vld) begin
    //         drop_qos_qos_flag <= 'b0;
    //         if (!qos_query_rsp_ok && drop_qos_qos_enable) begin
    //             drop_qos_qos_flag <= 'b1;
    //         end
    //     end
    // end

    ////////////////////////////////////////////////////////////////////////////
    // drop_stage

    enum logic [3:0] {
        DROP_IDLE = 4'b0001,
        DROP_DROP = 4'b0010,
        DROP_SEND = 4'b0100,
        DROP_QOS  = 4'b1000
    }
        drop_cstat, drop_nstat;
    logic                 drop_flag;
    // logic                 drop_data_proto_csum_pass;
    logic [DEV_WIDTH-1:0] drop_data_qos_uid;
    logic                 drop_data_qos_enable;
    logic                 qos_update_vld_delay;
    logic [UID_WIDTH-1:0] qos_update_uid_delay;
    logic [19:0]          qos_update_len_delay;

    assign drop_flag = (!drop_qos_csum_pass) || drop_qos_gen_flag || drop_qos_qos_flag || drop_qos_time_flag || drop_qos_random_flag || drop_qos_pfull_flag;


    always @(posedge clk) begin
        if (rst) begin
            drop_cstat <= DROP_IDLE;
        end else begin
            drop_cstat <= drop_nstat;
        end
    end

    always @(*) begin
        drop_nstat = drop_cstat;
        case (drop_cstat)
            DROP_IDLE: begin
                if (drop_qos_vld && drop_qos_rdy) begin
                    if (drop_flag) begin
                        drop_nstat = DROP_DROP;
                    end else begin
                        drop_nstat = DROP_SEND;
                    end
                end
            end
            DROP_DROP: begin
                if (csum_data_ff_rden && drop_data_ff_eop) begin
                    drop_nstat = DROP_IDLE;
                end
            end
            DROP_SEND: begin
                if (csum_data_ff_rden && drop_data_ff_eop) begin
                    drop_nstat = DROP_QOS;
                end
            end
            DROP_QOS: begin
                if ((qos_update_rdy || !qos_update_vld) || !qos_update_vld_delay) begin
                    drop_nstat = DROP_IDLE;
                end
            end
            default: drop_nstat = DROP_IDLE;
        endcase

    end

    assign drop_qos_rdy       = drop_cstat == DROP_IDLE;

    assign csum_data_ff_rden  = drop_data_ff_rden || drop_cstat == DROP_DROP;
    assign drop_data_ff_sop   = csum_data_ff_sop;
    assign drop_data_ff_eop   = csum_data_ff_eop;
    assign drop_data_ff_mty   = csum_data_ff_mty;
    assign drop_data_ff_data  = csum_data_ff_data;
    // assign drop_data_ff_data  = drop_data_ff_sop && drop_data_proto_csum_pass ? {csum_data_ff_data[255:161], 1'b1, csum_data_ff_data[159:0]} : csum_data_ff_data;  // 改头部信息
    assign drop_data_ff_empty = drop_cstat == DROP_SEND ? csum_data_ff_empty : 1'b1;


    always @(posedge clk) begin
        if (drop_qos_vld && drop_qos_rdy) begin
            drop_data_proto_csum_pass <= drop_qos_proto_csum_pass;
            drop_data_ff_gid          <= drop_qos_vq_gid;
            drop_data_qos_uid         <= drop_qos_qos_unit;
            drop_data_ff_len          <= drop_qos_length;
            drop_data_qos_enable      <= drop_qos_qos_enable;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            qos_update_vld <= 'b0;
        end else if (qos_update_rdy || !qos_update_vld) begin
            qos_update_vld <= qos_update_vld_delay;
        end
    end

    always @(posedge clk) begin
        if (qos_update_rdy || !qos_update_vld) begin
            qos_update_uid <= qos_update_uid_delay;
            qos_update_len <= qos_update_len_delay;
        end
    end


    assign qos_update_uid_delay = drop_data_qos_uid;
    assign qos_update_vld_delay = drop_cstat == DROP_QOS && drop_data_qos_enable;
    assign qos_update_len_delay = drop_data_ff_len;
    assign qos_update_pkt_num   = 8'b1;
    ///////////////////////////////////////////////////////////////////////////////


    logic                 csum_drop_pkt_ram_update_vld;
    logic [QID_WIDTH-1:0] csum_drop_pkt_ram_update_addr;
    // logic                 csum_drop_pkt_ram_rd_req_vld;
    // logic                 csum_drop_pkt_ram_rd_req_rdy;
    // logic [QID_WIDTH-1:0] csum_drop_pkt_ram_rd_req_addr;
    // logic                 csum_drop_pkt_ram_cnt_clr_en;
    // logic                 csum_drop_pkt_ram_rd_rsp_vld;
    // logic [16-1:0]        csum_drop_pkt_ram_rd_rsp_data;
    logic                 csum_drop_pkt_ram_flush;
    logic [1:0]           csum_drop_pkt_ram_err;

    logic                 qos_drop_pkt_ram_update_vld;
    logic [QID_WIDTH-1:0] qos_drop_pkt_ram_update_addr;
    // logic                 qos_drop_pkt_ram_rd_req_vld;
    // logic                 qos_drop_pkt_ram_rd_req_rdy;
    // logic [QID_WIDTH-1:0] qos_drop_pkt_ram_rd_req_addr;
    // logic                 qos_drop_pkt_ram_cnt_clr_en;
    // logic                 qos_drop_pkt_ram_rd_rsp_vld;
    // logic [16-1:0]        qos_drop_pkt_ram_rd_rsp_data;
    logic                 qos_drop_pkt_ram_flush;
    logic [1:0]           qos_drop_pkt_ram_err;

    logic                 buf_full_drop_pkt_ram_update_vld;
    logic [QID_WIDTH-1:0] buf_full_drop_pkt_ram_update_addr;
    // logic                 buf_full_drop_pkt_ram_rd_req_vld;
    // logic                 buf_full_drop_pkt_ram_rd_req_rdy;
    // logic [QID_WIDTH-1:0] buf_full_drop_pkt_ram_rd_req_addr;
    // logic                 buf_full_drop_pkt_ram_cnt_clr_en;
    // logic                 buf_full_drop_pkt_ram_rd_rsp_vld;
    // logic [16-1:0]        buf_full_drop_pkt_ram_rd_rsp_data;
    logic                 buf_full_drop_pkt_ram_flush;
    logic [1:0]           buf_full_drop_pkt_ram_err;

    virtio_rx_buf_cnt #(
        .CNT_WIDTH(16),
        .QID_NUM  (QID_NUM)
    ) u_csum_drop_pkt_ram (
        .clk        (clk),
        .rst        (rst),
        .update_vld (csum_drop_pkt_ram_update_vld),
        .update_addr(csum_drop_pkt_ram_update_addr),
        .rd_req_vld (csum_drop_pkt_ram_rd_req_vld),
        .rd_req_rdy (csum_drop_pkt_ram_rd_req_rdy),
        .rd_req_addr(csum_drop_pkt_ram_rd_req_addr),
        .cnt_clr_en (csum_drop_pkt_ram_cnt_clr_en),
        .rd_rsp_vld (csum_drop_pkt_ram_rd_rsp_vld),
        .rd_rsp_data(csum_drop_pkt_ram_rd_rsp_data),
        .flush      (csum_drop_pkt_ram_flush),
        .ram_err    (csum_drop_pkt_ram_err)
    );
    virtio_rx_buf_cnt #(
        .CNT_WIDTH(16),
        .QID_NUM  (QID_NUM)
    ) u_qos_drop_pkt_ram (
        .clk        (clk),
        .rst        (rst),
        .update_vld (qos_drop_pkt_ram_update_vld),
        .update_addr(qos_drop_pkt_ram_update_addr),
        .rd_req_vld (qos_drop_pkt_ram_rd_req_vld),
        .rd_req_rdy (qos_drop_pkt_ram_rd_req_rdy),
        .rd_req_addr(qos_drop_pkt_ram_rd_req_addr),
        .cnt_clr_en (qos_drop_pkt_ram_cnt_clr_en),
        .rd_rsp_vld (qos_drop_pkt_ram_rd_rsp_vld),
        .rd_rsp_data(qos_drop_pkt_ram_rd_rsp_data),
        .flush      (qos_drop_pkt_ram_flush),
        .ram_err    (qos_drop_pkt_ram_err)
    );
    virtio_rx_buf_cnt #(
        .CNT_WIDTH(16),
        .QID_NUM  (QID_NUM)
    ) u_buf_full_drop_pkt_ram (
        .clk        (clk),
        .rst        (rst),
        .update_vld (buf_full_drop_pkt_ram_update_vld),
        .update_addr(buf_full_drop_pkt_ram_update_addr),
        .rd_req_vld (buf_full_drop_pkt_ram_rd_req_vld),
        .rd_req_rdy (buf_full_drop_pkt_ram_rd_req_rdy),
        .rd_req_addr(buf_full_drop_pkt_ram_rd_req_addr),
        .cnt_clr_en (buf_full_drop_pkt_ram_cnt_clr_en),
        .rd_rsp_vld (buf_full_drop_pkt_ram_rd_rsp_vld),
        .rd_rsp_data(buf_full_drop_pkt_ram_rd_rsp_data),
        .flush      (buf_full_drop_pkt_ram_flush),
        .ram_err    (buf_full_drop_pkt_ram_err)
    );

    always @(posedge clk) begin
        csum_drop_pkt_ram_update_vld     <= 1'b0;
        qos_drop_pkt_ram_update_vld      <= 1'b0;
        buf_full_drop_pkt_ram_update_vld <= 1'b0;
        if (drop_cstat == DROP_IDLE && drop_qos_vld && drop_qos_rdy) begin
            if (drop_qos_gen_flag) begin
            end else if ((!drop_qos_csum_pass)) begin
                csum_drop_pkt_ram_update_vld <= 1'b1;
            end else if (drop_qos_qos_flag) begin
                qos_drop_pkt_ram_update_vld <= 1'b1;
            end else if (drop_qos_time_flag || drop_qos_random_flag || drop_qos_pfull_flag) begin
                buf_full_drop_pkt_ram_update_vld <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            csum_drop_pkt_total     <= 'b0;
            qos_drop_pkt_total      <= 'b0;
            buf_full_drop_pkt_total <= 'b0;
        end else if (drop_cstat == DROP_IDLE && drop_qos_vld && drop_qos_rdy) begin
            if (drop_qos_gen_flag) begin
            end else if ((!drop_qos_csum_pass)) begin
                csum_drop_pkt_total <= csum_drop_pkt_total + 1'b1;
            end else if (drop_qos_qos_flag) begin
                qos_drop_pkt_total <= qos_drop_pkt_total + 1'b1;
            end else if (drop_qos_time_flag || drop_qos_random_flag || drop_qos_pfull_flag) begin
                buf_full_drop_pkt_total <= buf_full_drop_pkt_total + 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (drop_cstat == DROP_IDLE && drop_qos_vld && drop_qos_rdy) begin
            csum_drop_pkt_ram_update_addr     <= drop_qos_vq_gid;
            qos_drop_pkt_ram_update_addr      <= drop_qos_vq_gid;
            buf_full_drop_pkt_ram_update_addr <= drop_qos_vq_gid;
        end
    end
    ////////////////////////////////////////////////////////////////////////////
    // STAT

    always @(posedge clk) begin
        drop_err.csum_drop_ram_err     <= 0;
        drop_err.qos_drop_ram_err      <= 0;
        drop_err.pfull_drop_ram_err    <= 0;
        drop_err.qos_info_ff_overflow  <= qos_info_ff_overflow;
        drop_err.qos_info_ff_underflow <= qos_info_ff_underflow;
        drop_err.qos_info_ff_err       <= qos_info_ff_err;
        drop_stat.drop_cstat           <= drop_cstat;
        drop_stat.drop_ctx_cstat       <= drop_ctx_cstat;
    end


endmodule : virtio_rx_buf_drop
