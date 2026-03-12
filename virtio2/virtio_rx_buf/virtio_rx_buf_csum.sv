/******************************************************************************
 * 文件名称 : virtio_rx_buf_csum.sv
 * 作者名称 : lch
 * 创建日期 : 2025/06/17
 * 功能描述 : csum_check 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   06/17       lch         初始化版本
 ******************************************************************************/
`include "virtio_rx_buf_define.svh"
module virtio_rx_buf_csum #(
    parameter DATA_WIDTH  = 256,
    parameter GEN_WIDTH   = 8,
    parameter QID_NUM     = 256,
    //local
    parameter EMPTH_WIDTH = $clog2(DATA_WIDTH / 8),
    parameter QID_WIDTH   = $clog2(QID_NUM)
) (
    input  logic                                      clk,
    input  logic                                      rst,
    // parser_data_ff
    output logic                                      parser_data_ff_rden,
    input  logic                                      parser_data_ff_sop,
    input  logic                                      parser_data_ff_eop,
    input  logic                    [EMPTH_WIDTH-1:0] parser_data_ff_mty,
    input  logic                    [DATA_WIDTH-1:0]  parser_data_ff_data,
    input  logic                                      parser_data_ff_empty,
    // parser_info_ff
    output logic                                      parser_info_ff_rden,
    input  logic                    [15:0]            parser_info_ff_ipv4_pkt_len,
    input  logic                    [7:0]             parser_info_ff_vq_gid,
    input  logic                    [7:0]             parser_info_ff_vq_gen,
    input  logic                    [17:0]            parser_info_ff_length,
    input  logic                                      parser_info_ff_vlan_en,
    input  logic                                      parser_info_ff_ipv4_flag,
    input  logic                                      parser_info_ff_ipv4_tcp_flag,
    input  logic                                      parser_info_ff_ipv4_udp_flag,
    input  logic                                      parser_info_ff_ipv6_tcp_flag,
    input  logic                                      parser_info_ff_ipv6_udp_flag,
    input  logic                                      parser_info_ff_net_trans_flag,
    input  logic                    [15:0]            parser_info_ff_ipv4_udp_csum,
    input  logic                                      parser_info_ff_empty,
    // csum_data_ff
    input  logic                                      csum_data_ff_rden,
    output logic                                      csum_data_ff_sop,
    output logic                                      csum_data_ff_eop,
    output logic                    [EMPTH_WIDTH-1:0] csum_data_ff_mty,
    output logic                    [DATA_WIDTH-1:0]  csum_data_ff_data,
    output logic                                      csum_data_ff_empty,
    // csum_info_ff
    input  logic                                      csum_info_ff_rden,
    output logic                                      csum_info_ff_csum_pass,
    output logic                                      csum_info_ff_trans_csum_pass,
    output logic                    [QID_WIDTH-1:0]   csum_info_ff_vq_gid,
    output logic                    [GEN_WIDTH-1:0]   csum_info_ff_vq_gen,
    output logic                    [18-1:0]          csum_info_ff_length,
    output logic                                      csum_info_ff_empty,
    output virtio_rx_buf_csum_err_t                   csum_err
);
    parameter CSUM_DATA_FF_WIDTH = DATA_WIDTH + EMPTH_WIDTH + 2;
    parameter CSUM_DATA_FF_DEPTH = 512;
    localparam CSUM_INFO_FF_WIDTH = 1 + 1 + 8 + 8 + 18;
    localparam CSUM_INFO_FF_DEPTH = 32;
    ////////////////////////////////////////////////////////////////////////////
    // data_bypass
    enum logic [1:0] {
        PARSER_WAIT = 2'b01,
        PARSER_RUN  = 2'b10
    }
        parser_cstat, parser_nstat;

    logic                          parser_data_ff_vld;
    logic                          csum_data_ff_wren;
    logic [CSUM_DATA_FF_WIDTH-1:0] csum_data_ff_din;
    logic                          csum_data_ff_wr_end;
    logic                          csum_data_ff_pfull;
    logic                          csum_info_ff_pfull;
    logic                          csum_data_ff_overflow;
    logic [CSUM_DATA_FF_WIDTH-1:0] csum_data_ff_dout;
    logic                          csum_data_ff_underflow;
    logic [1:0]                    csum_data_ff_err;

    always @(posedge clk) begin
        if (rst) begin
            parser_cstat <= PARSER_WAIT;
        end else begin
            parser_cstat <= parser_nstat;
        end
    end

    always @(*) begin
        parser_nstat = parser_cstat;
        case (parser_cstat)
            PARSER_WAIT:
            if (!parser_info_ff_empty && !parser_data_ff_empty) begin
                parser_nstat = PARSER_RUN;
            end
            PARSER_RUN: begin
                if (parser_data_ff_eop && parser_data_ff_vld) begin
                    parser_nstat = PARSER_WAIT;
                end
            end
            default: parser_nstat = PARSER_WAIT;
        endcase
    end


    assign parser_data_ff_vld  = parser_cstat == PARSER_RUN && !csum_data_ff_pfull && !parser_data_ff_empty && !csum_info_ff_pfull;
    assign csum_data_ff_wren   = parser_data_ff_vld;
    assign csum_data_ff_din    = {parser_data_ff_sop, parser_data_ff_eop, parser_data_ff_mty, parser_data_ff_data};
    assign csum_data_ff_wr_end = parser_data_ff_eop;
    assign parser_data_ff_rden = parser_data_ff_vld;
    assign parser_info_ff_rden = parser_data_ff_eop && parser_data_ff_vld;

    assign csum_data_ff_sop    = csum_data_ff_dout[DATA_WIDTH+EMPTH_WIDTH+1+:1];
    assign csum_data_ff_eop    = csum_data_ff_dout[DATA_WIDTH+EMPTH_WIDTH+:1];
    assign csum_data_ff_mty    = csum_data_ff_dout[DATA_WIDTH+:EMPTH_WIDTH];
    assign csum_data_ff_data   = csum_data_ff_dout[0+:DATA_WIDTH];

    logic                           csum_data_ff_rden_d;
    logic                           csum_data_ff_empty_d;
    logic  [CSUM_DATA_FF_WIDTH-1:0] csum_data_ff_dout_d;

    pkt_fifo #(
        .DATA_WIDTH (CSUM_DATA_FF_WIDTH),
        .FIFO_DEPTH (CSUM_DATA_FF_DEPTH),
        .DEPTH_PFULL(CSUM_DATA_FF_DEPTH - 12),
        .CHECK_ON   (1)
    ) u0_csum_data_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (csum_data_ff_wren),
        .din           (csum_data_ff_din),
        .wr_end        (csum_data_ff_wr_end),
        .wr_drop       (1'b0),
        .full          (),
        .pfull         (csum_data_ff_pfull),
        .overflow      (csum_data_ff_overflow),
        //
        .rden          (csum_data_ff_rden_d),
        .dout          (csum_data_ff_dout_d),
        .empty         (csum_data_ff_empty_d),
        .pempty        (),
        .underflow     (csum_data_ff_underflow),
        .usedw         (),
        .parity_ecc_err(csum_data_ff_err)
    );

    always @(posedge clk ) begin
        if (rst) begin
            csum_data_ff_empty <= 'b1;
        end else if (csum_data_ff_empty || csum_data_ff_rden) begin
            csum_data_ff_empty <= csum_data_ff_empty_d;
        end
    end

    always @(posedge clk) begin
        if (csum_data_ff_empty || csum_data_ff_rden) begin
            csum_data_ff_dout <= csum_data_ff_dout_d;
        end
    end

    assign csum_data_ff_rden_d = (csum_data_ff_empty || csum_data_ff_rden) && !csum_data_ff_empty_d;


    // ////////////////////////////////////////////////////////////////////////////
    // // sop eop shift
    // // begin : op_shift
    logic [15:0] sop_shift;
    logic [15:0] eop_shift;


    assign sop_shift[0] = parser_data_ff_sop;
    always @(posedge clk) begin  // 后续可以判断是否可以删去rst.
        if (rst) begin
            sop_shift[15:1] <= 0;
        end else if (parser_data_ff_vld) begin
            if (parser_data_ff_eop) begin
                sop_shift[15:1] <= 0;
            end else begin
                sop_shift[15:1] <= {sop_shift[14:1], sop_shift[0]};
            end
        end
    end

    assign eop_shift[0] = parser_data_ff_eop;
    always @(posedge clk) begin  // 后续可以判断是否可以删去rst.
        if (rst) begin
            eop_shift[15:1] <= 0;
        end else if (parser_data_ff_vld) begin
            eop_shift[15:1] <= {eop_shift[14:1], eop_shift[0]};
        end
    end


    ////////////////////////////////////////////////////////////////////////////
    // ip_csum
    // begin : ip_csum
    logic [15:0] ip_csum_data_stage9;
    logic        ip_csum_vld_stage9;
    logic [1:0]  ip_csum_err;
    logic [15:0] trans_csum_data_stage9;
    logic        trans_csum_vld_stage9;
    logic [1:0]  trans_csum_err;

    generate
        if (DATA_WIDTH == 256) begin : DATA_WIDTH_256_IPCSUM
            virtio_rx_buf_csum_ip256 u_virtio_rx_buf_csum_ip256 (
                .clk        (clk),
                .rst        (rst),
                .data       (parser_data_ff_data),
                .vld        (parser_data_ff_vld),
                .sop        (parser_data_ff_sop),
                .eop        (parser_data_ff_eop),
                .vlan       (parser_info_ff_vlan_en),
                .ip_csum    (ip_csum_data_stage9),
                .ip_csum_vld(ip_csum_vld_stage9),
                .rom_err    (ip_csum_err)
            );
            virtio_rx_buf_csum_trans256 u_virtio_rx_buf_csum_trans256 (
                .clk           (clk),
                .rst           (rst),
                .data          (parser_data_ff_data),
                .vld           (parser_data_ff_vld),
                .sop           (parser_data_ff_sop),
                .eop           (parser_data_ff_eop),
                .mty           (parser_data_ff_mty),
                .vlan          (parser_info_ff_vlan_en),
                .ipv4          (parser_info_ff_ipv4_flag),
                .ipv4_pkt_len  (parser_info_ff_ipv4_pkt_len),
                .trans_csum    (trans_csum_data_stage9),
                .trans_csum_vld(trans_csum_vld_stage9),
                .rom_err       (trans_csum_err)
            );
        end
    endgenerate

    ////////////////////////////////////////////////////////////////////////////
    // frame_info_1

    logic [15:0]       frame_info_vld;


    (* ramstyle = "logic" *) logic [10:0]       beq2net_ip_flag_stage;
    logic [10:0]       beq2net_trans_flag_stage;
    logic [10:0]       beq2net_proto_pass_stage;

    logic              beq2net_ip_pass_stage10;
    logic              beq2net_ip_csum_pass_stage10;
    logic              beq2net_trans_csum_pass_stage10;
    logic              beq2net_csum_pass_stage10;


    logic [10:0][7:0]  beq2net_vq_gid_stage;
    logic [10:0][7:0]  beq2net_vq_gen_stage;
    logic [10:0][17:0] beq2net_length_stage;


    assign frame_info_vld[0]               = eop_shift[0] && parser_data_ff_vld;
    assign beq2net_ip_flag_stage[0]        = parser_info_ff_ipv4_flag;
    assign beq2net_trans_flag_stage[0]     = parser_info_ff_net_trans_flag;
    assign beq2net_proto_pass_stage[0]     = parser_info_ff_ipv4_udp_flag && parser_info_ff_ipv4_udp_csum == 16'h0000;
    assign beq2net_vq_gid_stage[0]         = parser_info_ff_vq_gid;
    assign beq2net_vq_gen_stage[0]         = parser_info_ff_vq_gen;
    assign beq2net_length_stage[0]         = parser_info_ff_length;
    assign beq2net_ip_csum_pass_stage10    = beq2net_ip_flag_stage[10] && beq2net_ip_pass_stage10;
    assign beq2net_trans_csum_pass_stage10 = beq2net_trans_flag_stage[10] && beq2net_proto_pass_stage[10];

    assign beq2net_csum_pass_stage10       = (beq2net_ip_csum_pass_stage10 || !beq2net_ip_flag_stage[10]) && (beq2net_trans_csum_pass_stage10 || !beq2net_trans_flag_stage[10]);

    always @(posedge clk) begin
        frame_info_vld[15:1] <= {frame_info_vld[14:0]};
    end

    always @(posedge clk) begin
        if (frame_info_vld[0]) begin
            beq2net_ip_flag_stage[1]    <= beq2net_ip_flag_stage[0];
            beq2net_trans_flag_stage[1] <= beq2net_trans_flag_stage[0];
            beq2net_proto_pass_stage[1] <= beq2net_proto_pass_stage[0];
            beq2net_vq_gid_stage[1]     <= beq2net_vq_gid_stage[0];
            beq2net_vq_gen_stage[1]     <= beq2net_vq_gen_stage[0];
            beq2net_length_stage[1]     <= beq2net_length_stage[0];
        end
    end
    always @(posedge clk) begin
        beq2net_ip_flag_stage[10:2]    <= beq2net_ip_flag_stage[9:1];
        beq2net_trans_flag_stage[10:2] <= beq2net_trans_flag_stage[9:1];
        beq2net_proto_pass_stage[9:2]  <= beq2net_proto_pass_stage[8:1];
        beq2net_vq_gid_stage[10:2]     <= beq2net_vq_gid_stage[9:1];
        beq2net_vq_gen_stage[10:2]     <= beq2net_vq_gen_stage[9:1];
        beq2net_length_stage[10:2]     <= beq2net_length_stage[9:1];
    end

    always @(posedge clk) begin
        if (frame_info_vld[9]) begin
            beq2net_ip_pass_stage10 <= ip_csum_data_stage9 == 'hffff;
        end
    end

    always @(posedge clk) begin
        if (frame_info_vld[9]) begin
            beq2net_proto_pass_stage[10] <= beq2net_proto_pass_stage[9] || trans_csum_data_stage9 == 'hffff;
        end
    end



    logic                          csum_info_ff_wren;
    logic [CSUM_INFO_FF_WIDTH-1:0] csum_info_ff_din;
    logic                          csum_info_ff_overflow;

    logic [CSUM_INFO_FF_WIDTH-1:0] csum_info_ff_dout;
    logic                          csum_info_ff_underflow;
    logic [1:0]                    csum_info_ff_err;

    assign csum_info_ff_wren            = frame_info_vld[10];
    assign csum_info_ff_din             = {beq2net_csum_pass_stage10, beq2net_trans_csum_pass_stage10, beq2net_vq_gid_stage[10], beq2net_vq_gen_stage[10], beq2net_length_stage[10]};

    assign csum_info_ff_csum_pass       = csum_info_ff_dout[18+GEN_WIDTH+QID_WIDTH+1+:1];
    assign csum_info_ff_trans_csum_pass = csum_info_ff_dout[18+GEN_WIDTH+QID_WIDTH+:1];
    assign csum_info_ff_vq_gid          = csum_info_ff_dout[18+GEN_WIDTH+:QID_WIDTH];
    assign csum_info_ff_vq_gen          = csum_info_ff_dout[18+:GEN_WIDTH];
    assign csum_info_ff_length          = csum_info_ff_dout[0+:18];


    yucca_sync_fifo #(
        .DATA_WIDTH (CSUM_INFO_FF_WIDTH),
        .FIFO_DEPTH (CSUM_INFO_FF_DEPTH),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL(24),
        .RAM_MODE   ("dist"),
        .FIFO_MODE  ("fwft")
    ) u_csum_info_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (csum_info_ff_wren),
        .din           (csum_info_ff_din),
        .full          (),
        .pfull         (csum_info_ff_pfull),
        .overflow      (csum_info_ff_overflow),
        .rden          (csum_info_ff_rden),
        .dout          (csum_info_ff_dout),
        .empty         (csum_info_ff_empty),
        .pempty        (),
        .underflow     (csum_info_ff_underflow),
        .usedw         (),
        .parity_ecc_err(csum_info_ff_err)
    );


    // ERROR INFO
    always @(posedge clk) begin
        csum_err.ip_csum_err            <= ip_csum_err;
        csum_err.trans_csum_err         <= trans_csum_err;
        csum_err.csum_info_ff_overflow  <= csum_info_ff_overflow;
        csum_err.csum_info_ff_underflow <= csum_info_ff_underflow;
        csum_err.csum_info_ff_err       <= csum_info_ff_err;
        csum_err.csum_data_ff_overflow  <= csum_data_ff_overflow;
        csum_err.csum_data_ff_underflow <= csum_data_ff_underflow;
        csum_err.csum_data_ff_err       <= csum_data_ff_err;
    end

endmodule : virtio_rx_buf_csum
