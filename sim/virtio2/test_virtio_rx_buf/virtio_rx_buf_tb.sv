/******************************************************************************
 * 文件名称 : virtio_rx_buf_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/12/28
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  12/28     Joe Jiang   初始化版本
 ******************************************************************************/
`timescale 1ns / 1ns
`include "beq_data_if.svh"
`include "virtio_rx_buf_define.svh"
`include "../../../common/interfaces/mlite_if.svh"
module virtio_rx_buf_tb #(
    parameter DATA_WIDTH           = 256,
    parameter GEN_WIDTH            = 8,
    parameter QID_NUM              = 256,
    parameter DEV_NUM              = 1024,
    parameter UID_NUM              = 1024,
    parameter WEIGHT_WIDTH         = 4,
    // local
    parameter EMPTH_WIDTH          = $clog2(DATA_WIDTH / 8),
    parameter QID_WIDTH            = $clog2(QID_NUM),
    parameter UID_WIDTH            = $clog2(UID_NUM),
    parameter DEV_WIDTH            = $clog2(DEV_NUM),
    parameter PARSER_DATA_FF_WIDTH = DATA_WIDTH + EMPTH_WIDTH + 2,
    parameter PARSER_DATA_FF_DEPTH = 32,
    parameter PARSER_DATA_FF_USEDW = $clog2(PARSER_DATA_FF_DEPTH + 1),
    parameter PARSER_INFO_FF_WIDTH = 16 + 8 + 8 + 18 + 7 + 16,
    parameter PARSER_INFO_FF_DEPTH = 32,
    parameter PARSER_INFO_FF_USEDW = $clog2(PARSER_INFO_FF_DEPTH + 1),
    parameter CSUM_DATA_FF_WIDTH   = DATA_WIDTH + EMPTH_WIDTH + 2,
    parameter CSUM_DATA_FF_DEPTH   = 512,
    parameter CSUM_DATA_FF_USEDW   = $clog2(CSUM_DATA_FF_DEPTH + 1),
    parameter CSUM_INFO_FF_WIDTH   = 1 + 1 + 8 + 8 + 18,
    parameter CSUM_INFO_FF_DEPTH   = 32,
    parameter CSUM_INFO_FF_USEDW   = $clog2(CSUM_INFO_FF_DEPTH + 1),
    parameter BKT_FF_DEPTH         = `VIRTIO_RX_BUF_PKT_NUM,
    parameter BKT_FF_WIDTH         = $clog2(BKT_FF_DEPTH),
    parameter BKT_FF_USEDW         = $clog2(BKT_FF_DEPTH + 1)
) (

    input  logic                                              clk,
    input  logic                                              rst,
    //
    input  logic [                            DATA_WIDTH-1:0] beq2net_data,
    input  logic [                           EMPTH_WIDTH-1:0] beq2net_sty,
    input  logic [                           EMPTH_WIDTH-1:0] beq2net_mty,
    input  logic [                                   129 : 0] beq2net_sbd,
    input  logic                                              beq2net_sop,
    input  logic                                              beq2net_eop,
    // input  logic                   beq2net_err,
    output logic                                              beq2net_sav,
    input  logic                                              beq2net_vld,
    // drop_info_rd_req
    output logic                                              drop_info_rd_req_vld,
    input  logic                                              drop_info_rd_req_rdy,
    output logic [                                       7:0] drop_info_rd_req_qid,
    // drop_info_rd_rsp
    input  logic                                              drop_info_rd_rsp_vld,
    input  logic [                                       7:0] drop_info_rd_rsp_generation,
    input  logic [                             DEV_WIDTH-1:0] drop_info_rd_rsp_qos_unit,
    input  logic                                              drop_info_rd_rsp_qos_enable,
    // cfg
    // input  logic [                                       7:0] drop_time_sel,
    // input  logic [                                       7:0] drop_random_sel,
    // input  logic                                              csum_flag,
    // qos_query_req
    output logic                                              qos_query_req_vld,
    input  logic                                              qos_query_req_rdy,
    output logic [                             DEV_WIDTH-1:0] qos_query_req_uid,
    // qos_query_rsp
    input  logic                                              qos_query_rsp_vld,
    input  logic                                              qos_query_rsp_ok,
    output logic                                              qos_query_rsp_rdy,
    // qos_query_update
    output logic                                              qos_update_vld,
    output logic [                             UID_WIDTH-1:0] qos_update_uid,
    input  logic                                              qos_update_rdy,
    output logic [                                      19:0] qos_update_len,
    output logic [                                       7:0] qos_update_pkt_num,
    //
    output logic                                              req_idx_per_queue_rd_req_vld,
    output logic [                             QID_WIDTH-1:0] req_idx_per_queue_rd_req_qid,
    //
    input  logic                                              req_idx_per_queue_rd_rsp_vld,
    input  logic [                             DEV_WIDTH-1:0] req_idx_per_queue_rd_rsp_dev_id,
    input  logic [                                       7:0] req_idx_per_queue_rd_rsp_idx_limit_per_queue,
    //
    output logic                                              req_idx_per_dev_rd_req_vld,
    output logic [                             DEV_WIDTH-1:0] req_idx_per_dev_rd_req_dev_id,
    //
    input  logic                                              req_idx_per_dev_rd_rsp_vld,
    input  logic [                                       7:0] req_idx_per_dev_rd_rsp_idx_limit_per_dev,
    // output virtio_rx_buf_req_info_t                          info_out_data,
    output logic [                          BKT_FF_WIDTH-1:0] info_out_data_pkt_id,
    output logic [                                       7:0] info_out_data_vq_gid,
    output logic                                              info_out_vld,
    input  logic                                              info_out_rdy,
    // rd_data_req
    input  logic                                              rd_data_req_vld,
    output logic                                              rd_data_req_rdy,
    // input  virtio_rx_buf_rd_data_req_t                       rd_data_req_data,
    input  logic [                          BKT_FF_WIDTH-1:0] rd_data_req_data_pkt_id,
    input  logic [                                       7:0] rd_data_req_data_vq_gid,
    input  logic [                                       1:0] rd_data_req_data_vq_typ,
    input  logic                                              rd_data_req_data_drop,
    // rd_data_rsp
    output logic [                                     255:0] rd_data_rsp_data,
    output logic [                           EMPTH_WIDTH-1:0] rd_data_rsp_sty,
    output logic [                           EMPTH_WIDTH-1:0] rd_data_rsp_mty,
    output logic                                              rd_data_rsp_sop,
    output logic                                              rd_data_rsp_eop,
    output logic [$bits(virtio_rx_buf_rd_data_rsp_sbd_t)-1:0] rd_data_rsp_sbd,
    output logic                                              rd_data_rsp_vld,
    input  logic                                              rd_data_rsp_rdy,
    //
    input                                                     dfx_if_valid,
    input                                                     dfx_if_read,
    input        [                                    32-1:0] dfx_if_addr,
    input        [                                    64-1:0] dfx_if_wdata,
    input        [                                  64/8-1:0] dfx_if_wmask,
    input                                                     dfx_if_rready,
    output                                                    dfx_if_ready,
    output                                                    dfx_if_rvalid,
    output       [                                    64-1:0] dfx_if_rdata,

    input logic [WEIGHT_WIDTH-1:0] hot_weight,
    input logic [WEIGHT_WIDTH-1:0] cold_weight
    // input  logic                                             rd_data_rsp_rdy


);
    // logic [DATA_WIDTH-1:0] beq2net_data;
    beq_txq_bus_if #(.DATA_WIDTH(DATA_WIDTH)) beq2net ();

    assign beq2net.data = beq2net_data;
    assign beq2net.sty  = beq2net_sty;
    assign beq2net.mty  = beq2net_mty;
    assign beq2net.sbd  = beq2net_sbd;
    assign beq2net.sop  = beq2net_sop;
    assign beq2net.eop  = beq2net_eop;
    assign beq2net.vld  = beq2net_vld;
    assign beq2net_sav  = beq2net.sav;

    mlite_if #(.DATA_WIDTH(64)) dfx_if ();
    assign dfx_if.valid  = dfx_if_valid;
    assign dfx_if.read   = dfx_if_read;
    assign dfx_if.addr   = dfx_if_addr;
    assign dfx_if.wdata  = dfx_if_wdata;
    assign dfx_if.wmask  = dfx_if_wmask;
    assign dfx_if.rready = dfx_if_rready;

    assign dfx_if_ready  = dfx_if.ready;
    assign dfx_if_rvalid = dfx_if.rvalid;
    assign dfx_if_rdata  = dfx_if.rdata;

    virtio_rx_buf_req_info_t info_out_data;
    assign info_out_data_pkt_id = info_out_data.pkt_id;
    assign info_out_data_vq_gid = info_out_data.vq.qid;
    virtio_rx_buf_rd_data_req_t rd_data_req_data;
    assign rd_data_req_data.pkt_id = rd_data_req_data_pkt_id;
    assign rd_data_req_data.vq.qid = rd_data_req_data_vq_gid;
    assign rd_data_req_data.vq.typ = rd_data_req_data_vq_typ;
    assign rd_data_req_data.drop   = rd_data_req_data_drop;
    // mlite_if.slave ctx_if
    virtio_rx_buf_top #(
        .BKT_FF_DEPTH(BKT_FF_DEPTH)
    ) u_virtio_rx_buf_top (
        .clk                                         (clk),
        .rst                                         (rst),
        .beq2net                                     (beq2net),
        .dfx_if                                      (dfx_if),
        // drop_info_ctx
        .drop_info_rd_req_vld                        (drop_info_rd_req_vld),
        .drop_info_rd_req_qid                        (drop_info_rd_req_qid),
        .drop_info_rd_rsp_vld                        (drop_info_rd_rsp_vld),
        .drop_info_rd_rsp_generation                 (drop_info_rd_rsp_generation),
        .drop_info_rd_rsp_qos_unit                   (drop_info_rd_rsp_qos_unit),
        .drop_info_rd_rsp_qos_enable                 (drop_info_rd_rsp_qos_enable),
        //sel
        // .drop_time_sel                           (drop_time_sel),
        // .drop_random_sel                         (drop_random_sel),
        // qos_query
        .qos_query_req_vld                           (qos_query_req_vld),
        .qos_query_req_rdy                           (qos_query_req_rdy),
        .qos_query_req_uid                           (qos_query_req_uid),
        .qos_query_rsp_vld                           (qos_query_rsp_vld),
        .qos_query_rsp_ok                            (qos_query_rsp_ok),
        .qos_query_rsp_rdy                           (qos_query_rsp_rdy),
        .qos_update_vld                              (qos_update_vld),
        .qos_update_uid                              (qos_update_uid),
        .qos_update_rdy                              (qos_update_rdy),
        .qos_update_len                              (qos_update_len),
        .qos_update_pkt_num                          (qos_update_pkt_num),
        //
        // .csum_flag                               (csum_flag),
        //
        .req_idx_per_queue_rd_req_vld                (req_idx_per_queue_rd_req_vld),
        .req_idx_per_queue_rd_req_qid                (req_idx_per_queue_rd_req_qid),
        .req_idx_per_queue_rd_rsp_vld                (req_idx_per_queue_rd_rsp_vld),
        .req_idx_per_queue_rd_rsp_dev_id             (req_idx_per_queue_rd_rsp_dev_id),
        .req_idx_per_queue_rd_rsp_idx_limit_per_queue(req_idx_per_queue_rd_rsp_idx_limit_per_queue),
        // .req_idx_per_queue_rd_rsp_err                       (req_idx_per_queue_rd_rsp_err)
        //
        .req_idx_per_dev_rd_req_vld                  (req_idx_per_dev_rd_req_vld),
        .req_idx_per_dev_rd_req_dev_id               (req_idx_per_dev_rd_req_dev_id),
        .req_idx_per_dev_rd_rsp_vld                  (req_idx_per_dev_rd_rsp_vld),
        .req_idx_per_dev_rd_rsp_idx_limit_per_dev    (req_idx_per_dev_rd_rsp_idx_limit_per_dev),
        .info_out_data                               (info_out_data),
        .info_out_vld                                (info_out_vld),
        .info_out_rdy                                (info_out_rdy),
        // rd_data_req
        .rd_data_req_vld                             (rd_data_req_vld),
        .rd_data_req_rdy                             (rd_data_req_rdy),
        .rd_data_req_data                            (rd_data_req_data),
        // rd_data_rsp
        .rd_data_rsp_data                            (rd_data_rsp_data),
        .rd_data_rsp_sty                             (rd_data_rsp_sty),
        .rd_data_rsp_mty                             (rd_data_rsp_mty),
        .rd_data_rsp_sop                             (rd_data_rsp_sop),
        .rd_data_rsp_eop                             (rd_data_rsp_eop),
        .rd_data_rsp_sbd                             (rd_data_rsp_sbd),
        .rd_data_rsp_vld                             (rd_data_rsp_vld),
        .rd_data_rsp_rdy                             (rd_data_rsp_rdy)
        // .rd_data_rsp_rdy                                           (1),
        // .hot_weight                                  (1),
        // .cold_weight                                 (1)
        // .hot_weight                                                (hot_weight),
        // .cold_weight                                               (cold_weight)
        // .req_idx_per_dev_rd_rsp_err                         (req_idx_per_dev_rd_rsp_err)
    );

    // initial begin
    //     rd_data_rsp_rdy = 0;
    //     forever begin
    //         @(posedge clk) rd_data_rsp_rdy = ~rd_data_rsp_rdy;
    //     end
    // end
    logic [63:0] bps_cnt;
    logic [63:0] bps_cnt_r;
    logic [63:0] bps_cnt_sub;
    logic [31:0] bps;

    logic [63:0] pps_cnt;
    logic [63:0] pps_cnt_r;
    logic [63:0] pps_cnt_sub;
    logic [63:0] pps_cnt_sub_r;
    logic [31:0] pps;

    logic [63:0] time_cnt;
    always @(posedge clk) begin
        if (rst | time_cnt == 'd100_000) begin  // ns -> ms
            time_cnt <= 0;
        end else begin
            time_cnt <= time_cnt + 'd5;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            bps_cnt <= 'b0;
        end else if (rd_data_rsp_vld & !rd_data_rsp_sop) begin
            bps_cnt <= bps_cnt + 'd32 - rd_data_rsp_mty;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            bps_cnt_r <= 'b0;
        end else if (time_cnt >= 'd1_00_000) begin
            bps_cnt_r <= bps_cnt;
        end
    end

    assign bps_cnt_sub = (bps_cnt - bps_cnt_r) * 8 / 'd100_000;

    always @(posedge clk) begin
        if (rst) begin
            bps <= 0;
        end
        if (time_cnt >= 'd1_00_000) begin
            if (bps_cnt_r != 0) begin
                if (bps == 0) begin
                    bps <= bps_cnt_sub;
                end else begin
                    bps <= (bps + bps_cnt_sub) / 2;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            pps_cnt <= 'b0;
        end else if (rd_data_rsp_vld & rd_data_rsp_eop) begin
            pps_cnt <= pps_cnt + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            pps_cnt_r <= 'b0;
        end else if (time_cnt >= 'd1_00_000) begin
            pps_cnt_r <= pps_cnt;
        end
    end

    assign pps_cnt_sub = (pps_cnt - pps_cnt_r);

    // always @(posedge clk) begin
    //     if (time_cnt >= 'd1_000_000) begin
    //         pps_cnt_r <= pps_cnt_sub;
    //     end
    // end

    always @(posedge clk) begin
        if (rst) begin
            pps <= 0;
        end
        if (time_cnt >= 'd1_00_000) begin
            if (pps_cnt_r != 0) begin
                if (pps == 0) begin
                    pps <= pps_cnt_sub;
                end else begin
                    pps <= (pps + pps_cnt_sub) / 2;
                end
            end
        end
    end


    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, virtio_rx_buf_tb, "+all");
        $fsdbDumpMDA();
    end

endmodule
