/******************************************************************************
 * 文件名称 : virtio_rx_buf_top.sv
 * 作者名称 : lch
 * 创建日期 : 2025/06/17
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   06/17       lch         初始化版本
 ******************************************************************************/
`include "beq_data_if.svh"
`include "virtio_rx_buf_define.svh"
`include "../../../common/interfaces/mlite_if.svh"
module virtio_rx_buf_top #(
    parameter DATA_WIDTH   = 256,
    parameter GEN_WIDTH    = 8,
    parameter QID_NUM      = 256,
    parameter UID_NUM      = 1024,
    parameter DEV_NUM      = 1024,
    parameter BKT_FF_DEPTH = 2048,
    // local
    parameter EMPTH_WIDTH  = $clog2(DATA_WIDTH / 8),
    parameter QID_WIDTH    = $clog2(QID_NUM),
    parameter UID_WIDTH    = $clog2(UID_NUM),
    parameter DEV_WIDTH    = $clog2(DEV_NUM)
) (
    input  logic                                             clk,
    input  logic                                             rst,
    ////////////////////////////////////////////////////////////////////////////
    // csum
           beq_txq_bus_if.snk                                beq2net,
           mlite_if.slave                                    dfx_if,
    //    mlite_if.slave                                    dfx_if,
    ////////////////////////////////////////////////////////////////////////////
    // drop
    // drop_info_rd_req
    output logic                                             drop_info_rd_req_vld,
    output logic                           [QID_WIDTH-1:0]   drop_info_rd_req_qid,
    // drop_info_rd_rsp
    input  logic                                             drop_info_rd_rsp_vld,
    input  logic                           [GEN_WIDTH-1:0]   drop_info_rd_rsp_generation,
    input  logic                           [UID_WIDTH-1:0]   drop_info_rd_rsp_qos_unit,
    input  logic                                             drop_info_rd_rsp_qos_enable,
    // cfg
    // input  logic                           [7:0]             drop_time_sel,
    // input  logic                           [7:0]             drop_random_sel,
    // qos_query_req
    output logic                                             qos_query_req_vld,
    input  logic                                             qos_query_req_rdy,
    output logic                           [UID_WIDTH-1:0]   qos_query_req_uid,
    // qos_query_rsp
    input  logic                                             qos_query_rsp_vld,
    input  logic                                             qos_query_rsp_ok,
    output logic                                             qos_query_rsp_rdy,
    // qos_query_update
    output logic                                             qos_update_vld,
    output logic                           [UID_WIDTH-1:0]   qos_update_uid,
    input  logic                                             qos_update_rdy,
    output logic                           [19:0]            qos_update_len,
    output logic                           [7:0]             qos_update_pkt_num,
    // rx_buf_csum_flag
    // input  logic                                             csum_flag,
    // req_idx_per_queue_rd_req
    output logic                                             req_idx_per_queue_rd_req_vld,
    output logic                           [QID_WIDTH-1:0]   req_idx_per_queue_rd_req_qid,
    // req_idx_per_queue_rd_rsp
    input  logic                                             req_idx_per_queue_rd_rsp_vld,
    input  logic                           [DEV_WIDTH-1:0]   req_idx_per_queue_rd_rsp_dev_id,
    input  logic                           [7:0]             req_idx_per_queue_rd_rsp_idx_limit_per_queue,
    // req_idx_per_dev_rd_req
    output logic                                             req_idx_per_dev_rd_req_vld,
    output logic                           [DEV_WIDTH-1:0]   req_idx_per_dev_rd_req_dev_id,
    // req_idx_per_dev_rd_rsp
    input  logic                                             req_idx_per_dev_rd_rsp_vld,
    input  logic                           [7:0]             req_idx_per_dev_rd_rsp_idx_limit_per_dev,
    //
    output virtio_rx_buf_req_info_t                          info_out_data,
    output logic                                             info_out_vld,
    input  logic                                             info_out_rdy,
    // rd_data_req
    input  logic                                             rd_data_req_vld,
    output logic                                             rd_data_req_rdy,
    input  virtio_rx_buf_rd_data_req_t                       rd_data_req_data,
    // rd_data_rsp
    output logic                           [DATA_WIDTH-1:0]  rd_data_rsp_data,
    output logic                           [EMPTH_WIDTH-1:0] rd_data_rsp_sty,
    output logic                           [EMPTH_WIDTH-1:0] rd_data_rsp_mty,
    output logic                                             rd_data_rsp_sop,
    output logic                                             rd_data_rsp_eop,
    output virtio_rx_buf_rd_data_rsp_sbd_t                   rd_data_rsp_sbd,
    output logic                                             rd_data_rsp_vld,
    input  logic                                             rd_data_rsp_rdy


);
    localparam PARSER_DATA_FF_WIDTH = DATA_WIDTH + EMPTH_WIDTH + 2;
    localparam PARSER_DATA_FF_DEPTH = 32;
    localparam PARSER_DATA_FF_USEDW = $clog2(PARSER_DATA_FF_DEPTH + 1);
    localparam PARSER_INFO_FF_WIDTH = 16 + 8 + 8 + 18 + 7 + 16;
    localparam PARSER_INFO_FF_DEPTH = 32;
    localparam PARSER_INFO_FF_USEDW = $clog2(PARSER_INFO_FF_DEPTH + 1);
    // localparam BKT_FF_DEPTH = 2048;
    localparam BKT_FF_WIDTH = $clog2(BKT_FF_DEPTH);
    localparam BKT_FF_USEDW = $clog2(BKT_FF_DEPTH + 1);


    ////////////////////////////////////////////////////////////////////////////
    // err
    logic                         [63:0] virtio_rx_buf_dfx_err;
    logic                         [63:0] virtio_rx_buf_dfx_link_err;
    logic                         [63:0] virtio_rx_buf_dfx_drop_stat;
    logic                         [63:0] virtio_rx_buf_dfx_link_stat;
    logic                                drop_flush;

    virtio_rx_buf_drop_stat_t            drop_stat;  // 8
    virtio_rx_buf_link_stat_t            link_stat;  // 59

    virtio_rx_buf_parser_status_t        parser_status;  // 8
    virtio_rx_buf_parser_err_t           parser_err;  // 8

    virtio_rx_buf_csum_err_t             csum_err;  // 12
    virtio_rx_buf_drop_err_t             drop_err;  // 4
    virtio_rx_buf_link_err_t             link_err;  // 44

    always @(posedge clk) begin
        virtio_rx_buf_dfx_err       <= {drop_err, csum_err, parser_err};
        virtio_rx_buf_dfx_link_err  <= {link_err};
        virtio_rx_buf_dfx_drop_stat <= {beq2net.vld, beq2net.sav, drop_stat};
        virtio_rx_buf_dfx_link_stat <= {link_stat};
    end

    ////////////////////////////////////////////////////////////////////////////
    //
    beq_txq_bus_if #(.DATA_WIDTH(DATA_WIDTH)) beq2net_i ();
    assign beq2net_i.data = bytes_swap(beq2net.data);
    assign beq2net_i.sty  = beq2net.sty;
    assign beq2net_i.mty  = beq2net.mty;
    assign beq2net_i.sbd  = beq2net.sbd;
    assign beq2net_i.sop  = beq2net.sop;
    assign beq2net_i.eop  = beq2net.eop;
    assign beq2net_i.vld  = beq2net.vld;
    assign beq2net.sav    = beq2net_i.sav;

    logic [DATA_WIDTH-1:0] rd_data_rsp_data_o;
    assign rd_data_rsp_data = bytes_swap(rd_data_rsp_data_o);

    // parser
    logic                    parser_data_ff_rden;
    logic                    parser_data_ff_sop;
    logic                    parser_data_ff_eop;
    logic [EMPTH_WIDTH-1:0]  parser_data_ff_mty;
    logic [DATA_WIDTH-1:0]   parser_data_ff_data;
    logic                    parser_data_ff_empty;

    logic                    parser_info_ff_rden;
    logic [15:0]             parser_info_ff_ipv4_pkt_len;
    logic [7:0]              parser_info_ff_vq_gid;
    logic [7:0]              parser_info_ff_vq_gen;
    logic [17:0]             parser_info_ff_length;
    logic                    parser_info_ff_vlan_en;
    logic                    parser_info_ff_ipv4_flag;
    logic                    parser_info_ff_ipv4_tcp_flag;
    logic                    parser_info_ff_ipv4_udp_flag;
    logic                    parser_info_ff_ipv6_tcp_flag;
    logic                    parser_info_ff_ipv6_udp_flag;
    logic                    parser_info_ff_net_trans_flag;
    logic [15:0]             parser_info_ff_ipv4_udp_csum;
    logic                    parser_info_ff_empty;

    logic                    recv_pkt_num_ram_rd_req_vld;
    logic                    recv_pkt_num_ram_rd_req_rdy;
    logic [QID_WIDTH-1:0]    recv_pkt_num_ram_rd_req_addr;
    logic                    recv_pkt_num_ram_cnt_clr_en;
    logic                    recv_pkt_num_ram_rd_rsp_vld;
    logic [16-1:0]           recv_pkt_num_ram_rd_rsp_data;
    // csum
    logic                    csum_data_ff_rden;
    logic                    csum_data_ff_sop;
    logic                    csum_data_ff_eop;
    logic [EMPTH_WIDTH-1:0]  csum_data_ff_mty;
    logic [DATA_WIDTH-1:0]   csum_data_ff_data;
    logic                    csum_data_ff_empty;

    logic                    csum_info_ff_rden;
    logic                    csum_info_ff_csum_pass;
    logic                    csum_info_ff_trans_csum_pass;
    logic [8-1:0]            csum_info_ff_vq_gid;
    logic [8-1:0]            csum_info_ff_vq_gen;
    logic [18-1:0]           csum_info_ff_length;
    logic                    csum_info_ff_empty;
    // drop
    logic                    send_time_rden_drop;
    logic [QID_WIDTH-1:0]    send_time_raddr_drop;
    logic [15:0]             send_time_rdata_drop;
    logic [QID_WIDTH-1:0]    req_idx_per_queue_raddr;
    logic [15:0]             req_idx_per_queue_rdata;

    logic                    drop_data_ff_rden;
    logic                    drop_data_ff_sop;
    logic                    drop_data_ff_eop;
    logic [EMPTH_WIDTH-1:0]  drop_data_ff_mty;
    logic                    drop_data_proto_csum_pass;
    logic [8-1:0]            drop_data_ff_gid;
    logic [18-1:0]           drop_data_ff_len;
    logic [DATA_WIDTH-1:0]   drop_data_ff_data;
    logic                    drop_data_ff_empty;
    //
    logic [15:0]             time_stamp;
    logic                    time_stamp_up;
    logic [BKT_FF_USEDW-1:0] bkt_ff_usedw;
    logic                    bkt_ff_pempty;
    //
    logic                    virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_we;
    logic [63:0]             virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_wdata;
    logic [63:0]             virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_q;
    logic                    virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_we;
    logic [63:0]             virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_wdata;
    logic [63:0]             virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_q;
    logic [63:0]             virtio_rx_buf_dfx_link_stat_virtio_rx_buf_dfx_link_stat_wdata;
    logic [63:0]             virtio_rx_buf_dfx_drop_stat_virtio_rx_buf_dfx_drop_stat_wdata;

    logic [7:0]              sch_weight;
    logic                    csum_flag;
    logic [7:0]              drop_time_sel;
    logic [7:0]              drop_random_sel;

    logic                    csum_drop_pkt_ram_rd_req_vld;
    logic                    csum_drop_pkt_ram_rd_req_rdy;
    logic [QID_WIDTH-1:0]    csum_drop_pkt_ram_rd_req_addr;
    logic                    csum_drop_pkt_ram_cnt_clr_en;
    logic                    csum_drop_pkt_ram_rd_rsp_vld;
    logic [16-1:0]           csum_drop_pkt_ram_rd_rsp_data;
    //
    logic                    qos_drop_pkt_ram_rd_req_vld;
    logic                    qos_drop_pkt_ram_rd_req_rdy;
    logic [QID_WIDTH-1:0]    qos_drop_pkt_ram_rd_req_addr;
    logic                    qos_drop_pkt_ram_cnt_clr_en;
    logic                    qos_drop_pkt_ram_rd_rsp_vld;
    logic [16-1:0]           qos_drop_pkt_ram_rd_rsp_data;
    //
    logic                    buf_full_drop_pkt_ram_rd_req_vld;
    logic                    buf_full_drop_pkt_ram_rd_req_rdy;
    logic [QID_WIDTH-1:0]    buf_full_drop_pkt_ram_rd_req_addr;
    logic                    buf_full_drop_pkt_ram_cnt_clr_en;
    logic                    buf_full_drop_pkt_ram_rd_rsp_vld;
    logic [16-1:0]           buf_full_drop_pkt_ram_rd_rsp_data;

    logic [19:0]             csum_drop_pkt_total;
    logic [19:0]             qos_drop_pkt_total;
    logic [19:0]             buf_full_drop_pkt_total;
    logic [19:0]             not_ready_drop_pkt_total;

    logic [19:0]             info_out_pkt_total;
    logic [19:0]             rd_req_pkt_total;
    logic [19:0]             rd_rsp_pkt_total;
    logic [63:0]             netrx_if_pkt_cnt;
    mlite_if #(
        .ADDR_WIDTH(17),
        .DATA_WIDTH(64)
    ) m_br_if[2] ();

    generate
        if (DATA_WIDTH == 256) begin : DATA_WIDTH_256

            virtio_rx_buf_parser_256 #(
                .DATA_WIDTH(DATA_WIDTH),
                .GEN_WIDTH (GEN_WIDTH),
                .QID_NUM   (QID_NUM)
            ) u_virtio_rx_buf_parser (
                .clk                          (clk),
                .rst                          (rst),
                .beq2net                      (beq2net_i),
                //
                .csum_flag                    (csum_flag),
                //
                .parser_data_ff_rden          (parser_data_ff_rden),
                .parser_data_ff_sop           (parser_data_ff_sop),
                .parser_data_ff_eop           (parser_data_ff_eop),
                .parser_data_ff_mty           (parser_data_ff_mty),
                .parser_data_ff_data          (parser_data_ff_data),
                .parser_data_ff_empty         (parser_data_ff_empty),
                //
                .parser_info_ff_rden          (parser_info_ff_rden),
                .parser_info_ff_ipv4_pkt_len  (parser_info_ff_ipv4_pkt_len),
                .parser_info_ff_vq_gid        (parser_info_ff_vq_gid),
                .parser_info_ff_vq_gen        (parser_info_ff_vq_gen),
                .parser_info_ff_length        (parser_info_ff_length),
                .parser_info_ff_vlan_en       (parser_info_ff_vlan_en),
                .parser_info_ff_ipv4_flag     (parser_info_ff_ipv4_flag),
                .parser_info_ff_ipv4_tcp_flag (parser_info_ff_ipv4_tcp_flag),
                .parser_info_ff_ipv4_udp_flag (parser_info_ff_ipv4_udp_flag),
                .parser_info_ff_ipv6_tcp_flag (parser_info_ff_ipv6_tcp_flag),
                .parser_info_ff_ipv6_udp_flag (parser_info_ff_ipv6_udp_flag),
                .parser_info_ff_net_trans_flag(parser_info_ff_net_trans_flag),
                .parser_info_ff_ipv4_udp_csum (parser_info_ff_ipv4_udp_csum),
                .parser_info_ff_empty         (parser_info_ff_empty),
                .recv_pkt_num_ram_rd_req_vld  (recv_pkt_num_ram_rd_req_vld),
                .recv_pkt_num_ram_rd_req_rdy  (recv_pkt_num_ram_rd_req_rdy),
                .recv_pkt_num_ram_rd_req_addr (recv_pkt_num_ram_rd_req_addr),
                .recv_pkt_num_ram_cnt_clr_en  (recv_pkt_num_ram_cnt_clr_en),
                .recv_pkt_num_ram_rd_rsp_vld  (recv_pkt_num_ram_rd_rsp_vld),
                .recv_pkt_num_ram_rd_rsp_data (recv_pkt_num_ram_rd_rsp_data),
                .parser_status                (parser_status),
                .parser_err                   (parser_err)
            );
        end else begin : DATA_WIDTH_ELSE
            $fatal(0, "DATA_WIDTH is unsupported");
        end
    endgenerate

    virtio_rx_buf_csum #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_virtio_rx_buf_csum (
        .clk                          (clk),
        .rst                          (rst),
        //
        .parser_data_ff_rden          (parser_data_ff_rden),
        .parser_data_ff_sop           (parser_data_ff_sop),
        .parser_data_ff_eop           (parser_data_ff_eop),
        .parser_data_ff_mty           (parser_data_ff_mty),
        .parser_data_ff_data          (parser_data_ff_data),
        .parser_data_ff_empty         (parser_data_ff_empty),
        //
        .parser_info_ff_rden          (parser_info_ff_rden),
        .parser_info_ff_ipv4_pkt_len  (parser_info_ff_ipv4_pkt_len),
        .parser_info_ff_vq_gid        (parser_info_ff_vq_gid),
        .parser_info_ff_vq_gen        (parser_info_ff_vq_gen),
        .parser_info_ff_length        (parser_info_ff_length),
        .parser_info_ff_vlan_en       (parser_info_ff_vlan_en),
        .parser_info_ff_ipv4_flag     (parser_info_ff_ipv4_flag),
        .parser_info_ff_ipv4_tcp_flag (parser_info_ff_ipv4_tcp_flag),
        .parser_info_ff_ipv4_udp_flag (parser_info_ff_ipv4_udp_flag),
        .parser_info_ff_ipv6_tcp_flag (parser_info_ff_ipv6_tcp_flag),
        .parser_info_ff_ipv6_udp_flag (parser_info_ff_ipv6_udp_flag),
        .parser_info_ff_net_trans_flag(parser_info_ff_net_trans_flag),
        .parser_info_ff_ipv4_udp_csum (parser_info_ff_ipv4_udp_csum),
        .parser_info_ff_empty         (parser_info_ff_empty),
        // csum_data_ff
        .csum_data_ff_rden            (csum_data_ff_rden),
        .csum_data_ff_sop             (csum_data_ff_sop),
        .csum_data_ff_eop             (csum_data_ff_eop),
        .csum_data_ff_mty             (csum_data_ff_mty),
        .csum_data_ff_data            (csum_data_ff_data),
        .csum_data_ff_empty           (csum_data_ff_empty),
        // csum_info_ff
        .csum_info_ff_rden            (csum_info_ff_rden),
        .csum_info_ff_csum_pass       (csum_info_ff_csum_pass),
        .csum_info_ff_trans_csum_pass (csum_info_ff_trans_csum_pass),
        .csum_info_ff_vq_gid          (csum_info_ff_vq_gid),
        .csum_info_ff_vq_gen          (csum_info_ff_vq_gen),
        .csum_info_ff_length          (csum_info_ff_length),
        .csum_info_ff_empty           (csum_info_ff_empty),
        .csum_err                     (csum_err)
    );


    virtio_rx_buf_drop #(
        .DATA_WIDTH  (DATA_WIDTH),
        .DEV_NUM   (DEV_NUM),
        .BKT_FF_DEPTH(BKT_FF_DEPTH)
    ) u_virtio_rx_buf_drop (
        .clk                              (clk),
        .rst                              (rst),
        // csum_data_ff
        .csum_data_ff_rden                (csum_data_ff_rden),
        .csum_data_ff_sop                 (csum_data_ff_sop),
        .csum_data_ff_eop                 (csum_data_ff_eop),
        .csum_data_ff_mty                 (csum_data_ff_mty),
        .csum_data_ff_data                (csum_data_ff_data),
        .csum_data_ff_empty               (csum_data_ff_empty),
        // csum_info_ff
        .csum_info_ff_rden                (csum_info_ff_rden),
        .csum_info_ff_csum_pass           (csum_info_ff_csum_pass),
        .csum_info_ff_trans_csum_pass     (csum_info_ff_trans_csum_pass),
        .csum_info_ff_vq_gid              (csum_info_ff_vq_gid),
        .csum_info_ff_vq_gen              (csum_info_ff_vq_gen),
        .csum_info_ff_length              (csum_info_ff_length),
        .csum_info_ff_empty               (csum_info_ff_empty),
        //drop_info_rd_req
        .drop_info_rd_req_vld             (drop_info_rd_req_vld),
        .drop_info_rd_req_qid             (drop_info_rd_req_qid),
        //drop_info_rd_rsp
        .drop_info_rd_rsp_vld             (drop_info_rd_rsp_vld),
        .drop_info_rd_rsp_generation      (drop_info_rd_rsp_generation),
        .drop_info_rd_rsp_qos_unit        (drop_info_rd_rsp_qos_unit),
        .drop_info_rd_rsp_qos_enable      (drop_info_rd_rsp_qos_enable),
        //qos_query
        .qos_query_req_vld                (qos_query_req_vld),
        .qos_query_req_rdy                (qos_query_req_rdy),
        .qos_query_req_uid                (qos_query_req_uid),
        .qos_query_rsp_vld                (qos_query_rsp_vld),
        .qos_query_rsp_ok                 (qos_query_rsp_ok),
        .qos_query_rsp_rdy                (qos_query_rsp_rdy),
        .qos_update_vld                   (qos_update_vld),
        .qos_update_uid                   (qos_update_uid),
        .qos_update_rdy                   (qos_update_rdy),
        .qos_update_len                   (qos_update_len),
        .qos_update_pkt_num               (qos_update_pkt_num),
        // drop_time_ram
        .time_stamp                       (time_stamp),
        .drop_time_sel                    (drop_time_sel),
        .drop_time_ram_rd_en              (send_time_rden_drop),
        .drop_time_ram_raddr              (send_time_raddr_drop),
        .drop_time_ram_rdata              (send_time_rdata_drop),
        .idx_per_queue_raddr              (req_idx_per_queue_raddr),
        .idx_per_queue_rdata              (req_idx_per_queue_rdata),
        // drop_random
        .drop_random_sel                  (drop_random_sel),
        .rx_buf_csum_flag                 (csum_flag),
        // bkt_ff
        .bkt_ff_usedw                     (bkt_ff_usedw),
        .bkt_ff_pempty                    (bkt_ff_pempty),
        // drop_data_out
        .drop_data_ff_rden                (drop_data_ff_rden),
        .drop_data_ff_sop                 (drop_data_ff_sop),
        .drop_data_ff_eop                 (drop_data_ff_eop),
        .drop_data_ff_mty                 (drop_data_ff_mty),
        .drop_data_proto_csum_pass        (drop_data_proto_csum_pass),
        .drop_data_ff_gid                 (drop_data_ff_gid),
        .drop_data_ff_len                 (drop_data_ff_len),
        .drop_data_ff_data                (drop_data_ff_data),
        .drop_data_ff_empty               (drop_data_ff_empty),
        //
        .flush                            (drop_flush),
        //
        .csum_drop_pkt_ram_rd_req_vld     (csum_drop_pkt_ram_rd_req_vld),
        .csum_drop_pkt_ram_rd_req_rdy     (csum_drop_pkt_ram_rd_req_rdy),
        .csum_drop_pkt_ram_rd_req_addr    (csum_drop_pkt_ram_rd_req_addr),
        .csum_drop_pkt_ram_cnt_clr_en     (csum_drop_pkt_ram_cnt_clr_en),
        .csum_drop_pkt_ram_rd_rsp_vld     (csum_drop_pkt_ram_rd_rsp_vld),
        .csum_drop_pkt_ram_rd_rsp_data    (csum_drop_pkt_ram_rd_rsp_data),
        //
        .qos_drop_pkt_ram_rd_req_vld      (qos_drop_pkt_ram_rd_req_vld),
        .qos_drop_pkt_ram_rd_req_rdy      (qos_drop_pkt_ram_rd_req_rdy),
        .qos_drop_pkt_ram_rd_req_addr     (qos_drop_pkt_ram_rd_req_addr),
        .qos_drop_pkt_ram_cnt_clr_en      (qos_drop_pkt_ram_cnt_clr_en),
        .qos_drop_pkt_ram_rd_rsp_vld      (qos_drop_pkt_ram_rd_rsp_vld),
        .qos_drop_pkt_ram_rd_rsp_data     (qos_drop_pkt_ram_rd_rsp_data),
        //
        .buf_full_drop_pkt_ram_rd_req_vld (buf_full_drop_pkt_ram_rd_req_vld),
        .buf_full_drop_pkt_ram_rd_req_rdy (buf_full_drop_pkt_ram_rd_req_rdy),
        .buf_full_drop_pkt_ram_rd_req_addr(buf_full_drop_pkt_ram_rd_req_addr),
        .buf_full_drop_pkt_ram_cnt_clr_en (buf_full_drop_pkt_ram_cnt_clr_en),
        .buf_full_drop_pkt_ram_rd_rsp_vld (buf_full_drop_pkt_ram_rd_rsp_vld),
        .buf_full_drop_pkt_ram_rd_rsp_data(buf_full_drop_pkt_ram_rd_rsp_data),
        //
        .csum_drop_pkt_total              (csum_drop_pkt_total),
        .qos_drop_pkt_total               (qos_drop_pkt_total),
        .buf_full_drop_pkt_total          (buf_full_drop_pkt_total),
        //
        .drop_err                         (drop_err),
        .drop_stat                        (drop_stat)
    );


    virtio_rx_buf_linklist #(
        .DATA_WIDTH    (DATA_WIDTH),
        .QID_NUM       (QID_NUM),
        .DEV_NUM       (DEV_NUM),
        .BKT_FF_DEPTH  (BKT_FF_DEPTH),
        .REG_ADDR_WIDTH(17),
        .WEIGHT_WIDTH  (4)
    ) u_virtio_rx_buf_linklist (
        .clk                                     (clk),
        .rst                                     (rst),
        //
        .drop_data_ff_rden                       (drop_data_ff_rden),
        .drop_data_ff_sop                        (drop_data_ff_sop),
        .drop_data_ff_eop                        (drop_data_ff_eop),
        .drop_data_ff_mty                        (drop_data_ff_mty),
        .drop_data_proto_csum_pass               (drop_data_proto_csum_pass),
        .drop_data_ff_gid                        (drop_data_ff_gid),
        .drop_data_ff_len                        (drop_data_ff_len),
        .drop_data_ff_data                       (drop_data_ff_data),
        .drop_data_ff_empty                      (drop_data_ff_empty),
        //
        .idx_per_queue_raddr                     (req_idx_per_queue_raddr),
        .idx_per_queue_rdata                     (req_idx_per_queue_rdata),
        //
        .idx_per_queue_rd_req_vld                (req_idx_per_queue_rd_req_vld),
        .idx_per_queue_rd_req_qid                (req_idx_per_queue_rd_req_qid),
        .idx_per_queue_rd_rsp_vld                (req_idx_per_queue_rd_rsp_vld),
        .idx_per_queue_rd_rsp_dev_id             (req_idx_per_queue_rd_rsp_dev_id),
        .idx_per_queue_rd_rsp_idx_limit_per_queue(req_idx_per_queue_rd_rsp_idx_limit_per_queue),
        .idx_per_queue_rd_rsp_err                (req_idx_per_queue_rd_rsp_err),
        //
        .idx_per_dev_rd_req_vld                  (req_idx_per_dev_rd_req_vld),
        .idx_per_dev_rd_req_dev_id               (req_idx_per_dev_rd_req_dev_id),
        .idx_per_dev_rd_rsp_vld                  (req_idx_per_dev_rd_rsp_vld),
        .idx_per_dev_rd_rsp_idx_limit_per_dev    (req_idx_per_dev_rd_rsp_idx_limit_per_dev),
        .idx_per_dev_rd_rsp_err                  (req_idx_per_dev_rd_rsp_err),
        //
        .info_out_data                           (info_out_data),
        .info_out_vld                            (info_out_vld),
        .info_out_rdy                            (info_out_rdy),
        // rd_data_req
        .rd_data_req_vld                         (rd_data_req_vld),
        .rd_data_req_rdy                         (rd_data_req_rdy),
        .rd_data_req_data                        (rd_data_req_data),
        // rd_data_rsp
        .rd_data_rsp_data                        (rd_data_rsp_data_o),
        .rd_data_rsp_sty                         (rd_data_rsp_sty),
        .rd_data_rsp_mty                         (rd_data_rsp_mty),
        .rd_data_rsp_sop                         (rd_data_rsp_sop),
        .rd_data_rsp_eop                         (rd_data_rsp_eop),
        .rd_data_rsp_sbd                         (rd_data_rsp_sbd),
        .rd_data_rsp_vld                         (rd_data_rsp_vld),
        .rd_data_rsp_rdy                         (rd_data_rsp_rdy),
        //
        .send_time_rdata_drop                    (send_time_rdata_drop),
        .send_time_raddr_drop                    (send_time_raddr_drop),
        .send_time_rden_drop                     (send_time_rden_drop),
        .time_stamp                              (time_stamp),
        .time_stamp_up                           (time_stamp_up),
        .bkt_ff_usedw                            (bkt_ff_usedw),
        .bkt_ff_pempty                           (bkt_ff_pempty),
        .hot_weight                              (sch_weight[7:4]),
        .cold_weight                             (sch_weight[3:0]),
        .link_stat                               (link_stat),
        .link_err                                (link_err),
        //
        .recv_pkt_num_ram_rd_req_vld             (recv_pkt_num_ram_rd_req_vld),
        .recv_pkt_num_ram_rd_req_rdy             (recv_pkt_num_ram_rd_req_rdy),
        .recv_pkt_num_ram_rd_req_addr            (recv_pkt_num_ram_rd_req_addr),
        .recv_pkt_num_ram_cnt_clr_en             (recv_pkt_num_ram_cnt_clr_en),
        .recv_pkt_num_ram_rd_rsp_vld             (recv_pkt_num_ram_rd_rsp_vld),
        .recv_pkt_num_ram_rd_rsp_data            (recv_pkt_num_ram_rd_rsp_data),
        //
        .csum_drop_pkt_ram_rd_req_vld            (csum_drop_pkt_ram_rd_req_vld),
        .csum_drop_pkt_ram_rd_req_rdy            (csum_drop_pkt_ram_rd_req_rdy),
        .csum_drop_pkt_ram_rd_req_addr           (csum_drop_pkt_ram_rd_req_addr),
        .csum_drop_pkt_ram_cnt_clr_en            (csum_drop_pkt_ram_cnt_clr_en),
        .csum_drop_pkt_ram_rd_rsp_vld            (csum_drop_pkt_ram_rd_rsp_vld),
        .csum_drop_pkt_ram_rd_rsp_data           (csum_drop_pkt_ram_rd_rsp_data),
        //
        .qos_drop_pkt_ram_rd_req_vld             (qos_drop_pkt_ram_rd_req_vld),
        .qos_drop_pkt_ram_rd_req_rdy             (qos_drop_pkt_ram_rd_req_rdy),
        .qos_drop_pkt_ram_rd_req_addr            (qos_drop_pkt_ram_rd_req_addr),
        .qos_drop_pkt_ram_cnt_clr_en             (qos_drop_pkt_ram_cnt_clr_en),
        .qos_drop_pkt_ram_rd_rsp_vld             (qos_drop_pkt_ram_rd_rsp_vld),
        .qos_drop_pkt_ram_rd_rsp_data            (qos_drop_pkt_ram_rd_rsp_data),
        //
        .buf_full_drop_pkt_ram_rd_req_vld        (buf_full_drop_pkt_ram_rd_req_vld),
        .buf_full_drop_pkt_ram_rd_req_rdy        (buf_full_drop_pkt_ram_rd_req_rdy),
        .buf_full_drop_pkt_ram_rd_req_addr       (buf_full_drop_pkt_ram_rd_req_addr),
        .buf_full_drop_pkt_ram_cnt_clr_en        (buf_full_drop_pkt_ram_cnt_clr_en),
        .buf_full_drop_pkt_ram_rd_rsp_vld        (buf_full_drop_pkt_ram_rd_rsp_vld),
        .buf_full_drop_pkt_ram_rd_rsp_data       (buf_full_drop_pkt_ram_rd_rsp_data),
        //
        .info_out_pkt_total                      (info_out_pkt_total),
        .rd_req_pkt_total                        (rd_req_pkt_total),
        .rd_rsp_pkt_total                        (rd_rsp_pkt_total),
        //
        .not_ready_drop_pkt_total                (not_ready_drop_pkt_total),
        //
        .ctx_if                                  (m_br_if[1])
    );

    virtio_rx_buf_time_stamp u_virtio_rx_buf_time_stamp (
        .clk          (clk),
        .rst          (rst),
        .time_stamp   (time_stamp),
        .time_stamp_up(time_stamp_up)
    );

    virtio_rx_buf_dfx #(
        .ADDR_OFFSET(0),
        .ADDR_WIDTH (17),
        .DATA_WIDTH (64)
    ) u_virtio_rx_buf_dfx (
        .clk                                                          (clk),
        .rst                                                          (rst),
        .rx_buf_chksum_enable_rx_buf_chksum_enable_q                  (csum_flag),
        .rx_buf_sch_weight_rx_buf_sch_weight_q                        (sch_weight),                                                     // hot7-4 cold 3-0
        .rx_buf_time_drop_mode_rx_buf_time_drop_mode_q                (drop_time_sel),
        .rx_buf_random_drop_mode_rx_buf_random_drop_mode_q            (drop_random_sel),
        .virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_we               (virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_we),
        .virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_wdata            (virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_wdata),
        .virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_q                (virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_q),
        .virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_we     (virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_we),
        .virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_wdata  (virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_wdata),
        .virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_q      (virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_q),
        .virtio_rx_buf_dfx_drop_stat_virtio_rx_buf_dfx_drop_stat_wdata(virtio_rx_buf_dfx_drop_stat_virtio_rx_buf_dfx_drop_stat_wdata),
        .virtio_rx_buf_dfx_link_stat_virtio_rx_buf_dfx_link_stat_wdata(virtio_rx_buf_dfx_link_stat_virtio_rx_buf_dfx_link_stat_wdata),
        .csum_drop_pkt_total_csum_drop_pkt_total_wdata                (csum_drop_pkt_total),
        .qos_drop_pkt_total_qos_drop_pkt_total_wdata                  (qos_drop_pkt_total),
        .buf_full_drop_pkt_total_buf_full_drop_pkt_total_wdata        (buf_full_drop_pkt_total),
        .not_ready_drop_pkt_total_not_ready_drop_pkt_total_wdata      (not_ready_drop_pkt_total),
        .netrx_if_pkt_cnt_netrx_if_pkt_cnt_wdata                      (netrx_if_pkt_cnt),
        // .rd_req_pkt_total_rd_req_pkt_total_wdata                    (rd_req_pkt_total),
        // .rd_rsp_pkt_total_rd_rsp_pkt_total_wdata                    (rd_rsp_pkt_total),
        .csr_if                                                       (m_br_if[0])
    );
    assign netrx_if_pkt_cnt                                              = {4'b0, info_out_pkt_total, rd_req_pkt_total, rd_rsp_pkt_total};

    assign virtio_rx_buf_dfx_drop_stat_virtio_rx_buf_dfx_drop_stat_wdata = virtio_rx_buf_dfx_drop_stat;
    assign virtio_rx_buf_dfx_link_stat_virtio_rx_buf_dfx_link_stat_wdata = virtio_rx_buf_dfx_link_stat;

    assign virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_we                = |virtio_rx_buf_dfx_err;
    assign virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_wdata             = virtio_rx_buf_dfx_err_virtio_rx_buf_dfx_err_q | virtio_rx_buf_dfx_err;

    assign virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_we      = |virtio_rx_buf_dfx_link_err;
    assign virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_wdata   = virtio_rx_buf_dfx_link_err_virtio_rx_buf_dfx_link_err_q | virtio_rx_buf_dfx_link_err;




    logic [1:0]  chn_enable;
    logic [31:0] chn_addr;
    mlite_crossbar #(
        .CHN_NUM(2),
        .ADDR_WIDTH(32),
        .DATA_WIDTH(64)
    ) u_mlite_crossbar (
        .clk       (clk),
        .rst       (rst),
        .chn_enable(chn_enable),
        .slave     (dfx_if),
        .master    (m_br_if),
        .chn_addr  (chn_addr)
    );

    assign chn_enable[0] = chn_addr[16:15] == 2'd00;
    assign chn_enable[1] = chn_addr[16:15] != 2'd00;



    function [DATA_WIDTH-1:0] bytes_swap;
        input [DATA_WIDTH-1:0] data_in;
        integer i;
        begin
            for (i = 0; i < DATA_WIDTH / 8; i = i + 1) begin
                bytes_swap[i*8+:8] = data_in[(DATA_WIDTH/8-1-i)*8+:8];
            end
        end
    endfunction


endmodule
