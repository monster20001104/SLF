/******************************************************************************
 * 文件名称 : virtio_rx_buf_parser_256.sv
 * 作者名称 : lch
 * 创建日期 : 2025/06/17
 * 功能描述 : parser 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   06/17       lch         初始化版本
 * v1.1   07/15       lch         去掉virtio_head
 ******************************************************************************/
`include "virtio_rx_buf_define.svh"
module virtio_rx_buf_parser_256 #(
    parameter DATA_WIDTH  = 256,
    parameter GEN_WIDTH   = 8,
    parameter QID_NUM     = 256,
    //local
    parameter EMPTH_WIDTH = $clog2(DATA_WIDTH / 8),
    parameter QID_WIDTH   = $clog2(QID_NUM)          //should less than 17
) (
    input logic clk,
    input logic rst,

           beq_txq_bus_if.snk                              beq2net,
    input  logic                                           csum_flag,
    //
    input  logic                                           parser_data_ff_rden,
    output logic                                           parser_data_ff_sop,
    output logic                                           parser_data_ff_eop,
    output logic                         [EMPTH_WIDTH-1:0] parser_data_ff_mty,
    output logic                         [DATA_WIDTH-1:0]  parser_data_ff_data,
    output logic                                           parser_data_ff_empty,
    //
    input  logic                                           parser_info_ff_rden,
    output logic                         [15:0]            parser_info_ff_ipv4_pkt_len,
    output logic                         [QID_WIDTH-1:0]   parser_info_ff_vq_gid,
    output logic                         [GEN_WIDTH-1:0]   parser_info_ff_vq_gen,
    output logic                         [17:0]            parser_info_ff_length,
    output logic                                           parser_info_ff_vlan_en,
    output logic                                           parser_info_ff_ipv4_flag,
    output logic                                           parser_info_ff_ipv4_tcp_flag,
    output logic                                           parser_info_ff_ipv4_udp_flag,
    output logic                                           parser_info_ff_ipv6_tcp_flag,
    output logic                                           parser_info_ff_ipv6_udp_flag,
    output logic                                           parser_info_ff_net_trans_flag,
    output logic                         [15:0]            parser_info_ff_ipv4_udp_csum,
    output logic                                           parser_info_ff_empty,
    //
    input  logic                                           recv_pkt_num_ram_rd_req_vld,
    output logic                                           recv_pkt_num_ram_rd_req_rdy,
    input  logic                         [QID_WIDTH-1:0]   recv_pkt_num_ram_rd_req_addr,
    input  logic                                           recv_pkt_num_ram_cnt_clr_en,
    output logic                                           recv_pkt_num_ram_rd_rsp_vld,
    output logic                         [16-1:0]          recv_pkt_num_ram_rd_rsp_data,
    //
    output virtio_rx_buf_parser_status_t                   parser_status,
    output virtio_rx_buf_parser_err_t                      parser_err

);

    localparam PARSER_DATA_FF_WIDTH = DATA_WIDTH + EMPTH_WIDTH + 2;
    localparam PARSER_DATA_FF_DEPTH = 32;
    localparam PARSER_INFO_FF_WIDTH = 16 + QID_WIDTH + GEN_WIDTH + 18 + 7 + 16;
    localparam PARSER_INFO_FF_DEPTH = 32;
    ////////////////////////////////////////////////////////////////////////////
    // parser_data_ff
    logic                            parser_data_ff_wren;
    logic [PARSER_DATA_FF_WIDTH-1:0] parser_data_ff_din;
    logic                            parser_data_ff_pfull;
    logic                            parser_data_ff_overflow;

    logic [PARSER_DATA_FF_WIDTH-1:0] parser_data_ff_dout;
    logic                            parser_data_ff_underflow;

    logic [1:0]                      parser_data_ff_err;


    ////////////////////////////////////////////////////////////////////////////
    // parser_info_ff
    logic                            parser_info_ff_wren;
    logic [PARSER_INFO_FF_WIDTH-1:0] parser_info_ff_din;
    logic                            parser_info_ff_pfull;
    logic                            parser_info_ff_overflow;
    logic [PARSER_INFO_FF_WIDTH-1:0] parser_info_ff_dout;
    logic                            parser_info_ff_underflow;
    logic [1:0]                      parser_info_ff_err;
    logic [15:0]                     sop_shift;
    logic                            eop_shift;
    logic                            beq2net_vlan_en;
    logic                            beq2net_vlan_en_stage0;
    logic [15:0]                     beq2net_net_type;
    logic [15:0]                     beq2net_net_type_stage0;
    logic [5:0]                      beq2net_ipv4_ihl;
    logic [5:0]                      beq2net_ipv4_ihl_stage0;
    logic [2:0]                      beq2net_ipv4_flags;
    logic [2:0]                      beq2net_ipv4_flags_stage0;
    logic [12:0]                     beq2net_ipv4_frag;
    logic [12:0]                     beq2net_ipv4_frag_stage0;
    logic [7:0]                      beq2net_ipv4_trans;
    logic [7:0]                      beq2net_ipv4_trans_vlan;
    logic [7:0]                      beq2net_ipv4_trans_stage0;
    logic [7:0]                      beq2net_ipv6_trans;
    logic [7:0]                      beq2net_ipv6_trans_vlan;
    logic [7:0]                      beq2net_ipv6_trans_stage0;
    logic [15:0]                     beq2net_ipv4_udp_csum;
    logic [15:0]                     beq2net_ipv4_udp_csum_vlan;
    logic [15:0]                     beq2net_ipv4_udp_csum_stage0;
    logic [15:0]                     beq2net_ipv4_pkt_len;
    logic [15:0]                     beq2net_ipv4_pkt_len_vlan;
    logic [15:0]                     beq2net_ipv4_pkt_len_stage0;
    logic [QID_WIDTH-1:0]            beq2net_vq_gid;
    logic [GEN_WIDTH-1:0]            beq2net_vq_gen;
    logic [17:0]                     beq2net_length;
    logic                            beq2net_need_vld;
    logic [QID_WIDTH-1:0]            beq2net_vq_gid_stage0;
    logic [GEN_WIDTH-1:0]            beq2net_vq_gen_stage0;
    logic [17:0]                     beq2net_length_stage0;
    logic                            beq2net_need_vld_stage0;

    logic                            beq2net_ipv4_flag_stage0;
    logic                            beq2net_ipv6_flag_stage0;
    logic                            beq2net_ipv4_tcp_flag_stage0;
    logic                            beq2net_ipv4_udp_flag_stage0;
    logic                            beq2net_ipv6_tcp_flag_stage0;
    logic                            beq2net_ipv6_udp_flag_stage0;

    logic                            stage0_vld;
    logic                            stage0_vld_submit;
    logic                            stage0_vld_used;

    logic                            stage1_vld;


    logic [QID_WIDTH-1:0]            beq2net_vq_gid_stage1;
    logic [GEN_WIDTH-1:0]            beq2net_vq_gen_stage1;
    logic [17:0]                     beq2net_length_stage1;
    logic                            beq2net_need_vld_stage1;
    logic                            beq2net_vlan_en_stage1;
    logic                            beq2net_ipv4_flag_stage1;
    logic                            beq2net_ipv6_flag_stage1;
    logic                            beq2net_ipv4_tcp_flag_stage1;
    logic                            beq2net_ipv4_udp_flag_stage1;
    logic                            beq2net_ipv6_tcp_flag_stage1;
    logic                            beq2net_ipv6_udp_flag_stage1;
    logic                            beq2net_net_trans_flag_stage1;
    logic [15:0]                     beq2net_ipv4_udp_csum_stage1;
    logic [15:0]                     beq2net_ipv4_pkt_len_stage1;

    logic                            recv_cnt_ram_wren;
    logic [QID_WIDTH-1:0]            recv_cnt_ram_waddr;
    logic [15:0]                     recv_cnt_ram_wdata;

    logic [QID_WIDTH-1:0]            recv_cnt_ram_addr;
    logic                            recv_cnt_ram_rden;
    // logic                 recv_cnt_ram_rden_up;
    logic [QID_WIDTH-1:0]            recv_cnt_ram_raddr;
    // logic [QID_WIDTH-1:0] recv_cnt_ram_raddr_ctx;
    // logic [15:0]          recv_cnt_ram_rdata;
    logic                            flush;
    logic                            flush_r;


    assign sop_shift[0]                  = beq2net.sop;
    assign eop_shift                     = beq2net.eop;
    assign beq2net_vlan_en               = beq2net.data[9*16+:16] == 'h8100;
    assign beq2net_net_type              = beq2net_vlan_en ? beq2net.data[07*16+:16] : beq2net.data[09*16+:16];
    assign beq2net_ipv4_ihl              = beq2net_vlan_en ? {beq2net.data[06*16+8+:4], 2'b0} : {beq2net.data[08*16+8+:4], 2'b0};
    assign beq2net_ipv4_flags            = beq2net_vlan_en ? beq2net.data[03*16+13+:3] : beq2net.data[05*16+13+:3];
    assign beq2net_ipv4_frag             = beq2net_vlan_en ? beq2net.data[03*16+:13] : beq2net.data[05*16+:13];
    assign beq2net_ipv4_trans            = beq2net.data[04*16+:8];
    assign beq2net_ipv4_trans_vlan       = beq2net.data[02*16+:8];
    assign beq2net_ipv6_trans            = beq2net.data[05*16+8+:8];
    assign beq2net_ipv6_trans_vlan       = beq2net.data[03*16+8+:8];
    assign beq2net_ipv4_udp_csum         = beq2net.data[11*16+:16];
    assign beq2net_ipv4_udp_csum_vlan    = beq2net.data[09*16+:16];
    assign beq2net_ipv4_pkt_len          = beq2net.data[07*16+:16] - 'd20;
    assign beq2net_ipv4_pkt_len_vlan     = beq2net.data[05*16+:16] - 'd20;

    assign beq2net_ipv4_flag_stage0      = beq2net_net_type_stage0 == 'h0800 && beq2net_ipv4_ihl_stage0 == 'd20 && beq2net_ipv4_flags_stage0[0] == 0 && beq2net_ipv4_frag_stage0 == 0;
    assign beq2net_ipv6_flag_stage0      = beq2net_net_type_stage0 == 'h86dd;
    assign beq2net_ipv4_tcp_flag_stage0  = beq2net_ipv4_flag_stage0 && beq2net_ipv4_trans_stage0 == 'd6;
    assign beq2net_ipv4_udp_flag_stage0  = beq2net_ipv4_flag_stage0 && beq2net_ipv4_trans_stage0 == 'd17;
    assign beq2net_ipv6_tcp_flag_stage0  = beq2net_ipv6_flag_stage0 && beq2net_ipv6_trans_stage0 == 'd6;
    assign beq2net_ipv6_udp_flag_stage0  = beq2net_ipv6_flag_stage0 && beq2net_ipv6_trans_stage0 == 'd17;


    assign beq2net_vq_gid                = beq2net.sbd.user0[00+:QID_WIDTH];
    assign beq2net_vq_gen                = beq2net.sbd.user0[32+:GEN_WIDTH];
    assign beq2net_length                = beq2net.sbd.length;
    assign beq2net_need_vld              = beq2net.sbd.user0[16];

    assign stage0_vld                    = stage0_vld_submit && !stage0_vld_used;

    assign parser_info_ff_ipv4_pkt_len   = parser_info_ff_dout[41+GEN_WIDTH+QID_WIDTH+:16];
    assign parser_info_ff_vq_gid         = parser_info_ff_dout[41+GEN_WIDTH+:QID_WIDTH];
    assign parser_info_ff_vq_gen         = parser_info_ff_dout[41+:GEN_WIDTH];
    assign parser_info_ff_length         = parser_info_ff_dout[23+:18];
    assign parser_info_ff_vlan_en        = parser_info_ff_dout[22+:1];
    assign parser_info_ff_ipv4_flag      = parser_info_ff_dout[21+:1];
    assign parser_info_ff_ipv4_tcp_flag  = parser_info_ff_dout[20+:1];
    assign parser_info_ff_ipv4_udp_flag  = parser_info_ff_dout[19+:1];
    assign parser_info_ff_ipv6_tcp_flag  = parser_info_ff_dout[18+:1];
    assign parser_info_ff_ipv6_udp_flag  = parser_info_ff_dout[17+:1];
    assign parser_info_ff_net_trans_flag = parser_info_ff_dout[16+:1];
    assign parser_info_ff_ipv4_udp_csum  = parser_info_ff_dout[0+:16];


    ////////////////////////////////////////////////////////////////////////////
    // stage control
    always @(posedge clk) begin
        if (rst) begin
            sop_shift[15:1] <= 0;
        end else if (beq2net.vld) begin
            if (beq2net.eop) begin
                sop_shift[15:1] <= 0;
            end else begin
                sop_shift[15:1] <= {sop_shift[14:1], sop_shift[0]};
            end
        end
    end
    ////////////////////////////////////////////////////////////////////////////
    // stage0


    always @(posedge clk) begin
        if (sop_shift[0] && beq2net.vld) begin
            beq2net_vlan_en_stage0    <= beq2net_vlan_en;
            beq2net_net_type_stage0   <= beq2net_net_type;
            beq2net_ipv4_ihl_stage0   <= beq2net_ipv4_ihl;
            beq2net_ipv4_flags_stage0 <= beq2net_ipv4_flags;
            beq2net_ipv4_frag_stage0  <= beq2net_ipv4_frag;
            beq2net_vq_gid_stage0     <= beq2net_vq_gid;
            beq2net_vq_gen_stage0     <= beq2net_vq_gen;
            beq2net_length_stage0     <= beq2net_length;
            beq2net_need_vld_stage0   <= beq2net_need_vld;
            if (beq2net_vlan_en) begin
                beq2net_ipv4_trans_stage0   <= beq2net_ipv4_trans_vlan;
                beq2net_ipv6_trans_stage0   <= beq2net_ipv6_trans_vlan;
                beq2net_ipv4_pkt_len_stage0 <= beq2net_ipv4_pkt_len_vlan;
            end else begin
                beq2net_ipv4_trans_stage0   <= beq2net_ipv4_trans;
                beq2net_ipv6_trans_stage0   <= beq2net_ipv6_trans;
                beq2net_ipv4_pkt_len_stage0 <= beq2net_ipv4_pkt_len;
            end
        end
    end

    always @(posedge clk) begin
        if (sop_shift[1] && beq2net.vld) begin
            if (beq2net_vlan_en_stage0) begin
                beq2net_ipv4_udp_csum_stage0 <= beq2net_ipv4_udp_csum_vlan;
            end else begin
                beq2net_ipv4_udp_csum_stage0 <= beq2net_ipv4_udp_csum;
            end
        end
    end


    always @(posedge clk) begin
        if (sop_shift[0] && beq2net.vld) begin
            stage0_vld_used <= 'b0;
        end else if (stage0_vld) begin
            stage0_vld_used <= 'b1;
        end
    end


    always @(posedge clk) begin
        if (eop_shift && beq2net.vld) begin
            stage0_vld_submit <= 'b1;
        end else if (sop_shift[1] && beq2net.vld) begin
            stage0_vld_submit <= 'b1;
        end else begin
            stage0_vld_submit <= 'b0;
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // stage 1


    always @(posedge clk) begin
        stage1_vld <= stage0_vld;
    end

    always @(posedge clk) begin
        if (stage0_vld) begin
            beq2net_vq_gid_stage1        <= beq2net_vq_gid_stage0;
            beq2net_vq_gen_stage1        <= beq2net_vq_gen_stage0;
            beq2net_length_stage1        <= beq2net_length_stage0;
            beq2net_need_vld_stage1      <= beq2net_need_vld_stage0;
            beq2net_vlan_en_stage1       <= beq2net_vlan_en_stage0;
            beq2net_ipv4_pkt_len_stage1  <= beq2net_ipv4_pkt_len_stage0;
            beq2net_ipv4_udp_csum_stage1 <= beq2net_ipv4_udp_csum_stage0;
            if (!beq2net_need_vld_stage0 || !csum_flag) begin
                beq2net_ipv4_flag_stage1      <= 0;
                beq2net_ipv6_flag_stage1      <= 0;
                beq2net_ipv4_tcp_flag_stage1  <= 0;
                beq2net_ipv4_udp_flag_stage1  <= 0;
                beq2net_ipv6_tcp_flag_stage1  <= 0;
                beq2net_ipv6_udp_flag_stage1  <= 0;
                beq2net_net_trans_flag_stage1 <= 0;
            end else begin
                beq2net_ipv4_flag_stage1      <= beq2net_ipv4_flag_stage0;
                beq2net_ipv6_flag_stage1      <= beq2net_ipv6_flag_stage0;
                beq2net_ipv4_tcp_flag_stage1  <= beq2net_ipv4_tcp_flag_stage0;
                beq2net_ipv4_udp_flag_stage1  <= beq2net_ipv4_udp_flag_stage0;
                beq2net_ipv6_tcp_flag_stage1  <= beq2net_ipv6_tcp_flag_stage0;
                beq2net_ipv6_udp_flag_stage1  <= beq2net_ipv6_udp_flag_stage0;
                beq2net_net_trans_flag_stage1 <= beq2net_ipv4_tcp_flag_stage0 || beq2net_ipv4_udp_flag_stage0 || beq2net_ipv6_tcp_flag_stage0 || beq2net_ipv6_udp_flag_stage0;
            end
        end
    end


    ////////////////////////////////////////////////////////////////////////////
    // parser_data_ff


    assign parser_data_ff_wren = beq2net.vld;
    assign parser_data_ff_din  = {beq2net.sop, beq2net.eop, beq2net.mty, beq2net.data};
    assign beq2net.sav         = !parser_data_ff_pfull && !flush;

    assign parser_data_ff_sop  = parser_data_ff_dout[DATA_WIDTH+EMPTH_WIDTH+1+:1];
    assign parser_data_ff_eop  = parser_data_ff_dout[DATA_WIDTH+EMPTH_WIDTH+:1];
    assign parser_data_ff_mty  = parser_data_ff_dout[DATA_WIDTH+:EMPTH_WIDTH];
    assign parser_data_ff_data = parser_data_ff_dout[0+:DATA_WIDTH];

    yucca_sync_fifo #(
        .DATA_WIDTH (PARSER_DATA_FF_WIDTH),
        .FIFO_DEPTH (PARSER_DATA_FF_DEPTH),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL(24),
        .RAM_MODE   ("dist"),
        .FIFO_MODE  ("fwft")
    ) u0_parser_data_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (parser_data_ff_wren),
        .din           (parser_data_ff_din),
        .full          (),
        .pfull         (parser_data_ff_pfull),
        .overflow      (parser_data_ff_overflow),
        .rden          (parser_data_ff_rden),
        .dout          (parser_data_ff_dout),
        .empty         (parser_data_ff_empty),
        .pempty        (),
        .underflow     (parser_data_ff_underflow),
        .usedw         (),
        .parity_ecc_err(parser_data_ff_err)
    );
    ////////////////////////////////////////////////////////////////////////////
    // parser_info_ff

    always @(posedge clk) begin
        parser_info_ff_wren <= stage1_vld;
    end

    always @(posedge clk) begin
        if (stage1_vld) begin
            parser_info_ff_din <= {beq2net_ipv4_pkt_len_stage1, beq2net_vq_gid_stage1, beq2net_vq_gen_stage1, beq2net_length_stage1, beq2net_vlan_en_stage1, beq2net_ipv4_flag_stage1, beq2net_ipv4_tcp_flag_stage1, beq2net_ipv4_udp_flag_stage1, beq2net_ipv6_tcp_flag_stage1, beq2net_ipv6_udp_flag_stage1, beq2net_net_trans_flag_stage1, beq2net_ipv4_udp_csum_stage1};

        end
    end


    yucca_sync_fifo #(
        .DATA_WIDTH (PARSER_INFO_FF_WIDTH),
        .FIFO_DEPTH (PARSER_INFO_FF_DEPTH),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL(24),
        .RAM_MODE   ("dist"),
        .FIFO_MODE  ("fwft")
    ) u0_parser_info_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (parser_info_ff_wren),
        .din           (parser_info_ff_din),
        .full          (),
        .pfull         (parser_info_ff_pfull),
        .overflow      (parser_info_ff_overflow),
        .rden          (parser_info_ff_rden),
        .dout          (parser_info_ff_dout),
        .empty         (parser_info_ff_empty),
        .pempty        (),
        .underflow     (parser_info_ff_underflow),
        .usedw         (),
        .parity_ecc_err(parser_info_ff_err)
    );


    logic                 recv_pkt_num_ram_update_vld;
    logic [QID_WIDTH-1:0] recv_pkt_num_ram_update_addr;
    // logic                 recv_pkt_num_ram_rd_req_vld;
    // logic                 recv_pkt_num_ram_rd_req_rdy;
    // logic [QID_WIDTH-1:0] recv_pkt_num_ram_rd_req_addr;
    // logic                 recv_pkt_num_ram_cnt_clr_en;
    // logic                 recv_pkt_num_ram_rd_rsp_vld;
    // logic [16-1:0]        recv_pkt_num_ram_rd_rsp_data;
    logic                 recv_pkt_num_ram_flush;
    logic [1:0]           recv_pkt_num_ram_err;

    virtio_rx_buf_cnt #(
        .CNT_WIDTH(16),
        .QID_NUM  (QID_NUM)
    ) u_recv_pkt_num_ram (
        .clk        (clk),
        .rst        (rst),
        .update_vld (recv_pkt_num_ram_update_vld),
        .update_addr(recv_pkt_num_ram_update_addr),

        .rd_req_vld (recv_pkt_num_ram_rd_req_vld),
        .rd_req_rdy (recv_pkt_num_ram_rd_req_rdy),
        .rd_req_addr(recv_pkt_num_ram_rd_req_addr),
        .cnt_clr_en (recv_pkt_num_ram_cnt_clr_en),

        .rd_rsp_vld (recv_pkt_num_ram_rd_rsp_vld),
        .rd_rsp_data(recv_pkt_num_ram_rd_rsp_data),
        // .flush      (flush),
        .flush      (recv_pkt_num_ram_flush),
        .ram_err    (recv_pkt_num_ram_err)
    );

    assign recv_pkt_num_ram_update_vld  = beq2net.eop && beq2net.vld;
    assign recv_pkt_num_ram_update_addr = beq2net_vq_gid;

    ////////////////////////////////////////////////////////////////////////////
    // err
    always @(posedge clk) begin  // 8bit
        parser_status.beq2net_vld          <= beq2net.vld;
        parser_status.beq2net_sav          <= beq2net.sav;
        parser_status.parser_data_ff_pfull <= parser_data_ff_pfull;
        parser_status.parser_data_ff_empty <= parser_data_ff_empty;
        parser_status.parser_info_ff_pfull <= parser_info_ff_pfull;
        parser_status.parser_info_ff_empty <= parser_info_ff_empty;
    end

    always @(posedge clk) begin  // 10bit
        parser_err.recv_pkt_num_ram_err     <= recv_pkt_num_ram_err;
        parser_err.parser_data_ff_overflow  <= parser_data_ff_overflow;
        parser_err.parser_data_ff_underflow <= parser_data_ff_underflow;
        parser_err.parser_data_ff_err       <= parser_data_ff_err;
        parser_err.parser_info_ff_overflow  <= parser_info_ff_overflow;
        parser_err.parser_info_ff_underflow <= parser_info_ff_underflow;
        parser_err.parser_info_ff_err       <= parser_info_ff_err;
    end

    assign flush = recv_pkt_num_ram_flush;

endmodule : virtio_rx_buf_parser_256
