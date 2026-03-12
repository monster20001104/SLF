/******************************************************************************
 * 文件名称 : virtio_rx_buf_linklist.sv
 * 作者名称 : lch
 * 创建日期 : 2025/06/25
 * 功能描述 : 双向链表
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   06/25       lch         初始化版本
 ******************************************************************************/
`include "virtio_rx_buf_define.svh"
module virtio_rx_buf_linklist #(
    parameter WEIGHT_WIDTH   = 4,
    parameter DATA_WIDTH     = 256,
    parameter EMPTH_WIDTH    = $clog2(DATA_WIDTH / 8),
    parameter BKT_FF_DEPTH   = 1024,
    parameter BKT_FF_WIDTH   = $clog2(BKT_FF_DEPTH),
    parameter QID_NUM        = 256,
    parameter QID_WIDTH      = $clog2(QID_NUM),
    parameter DEV_NUM        = 1024,
    parameter DEV_WIDTH      = $clog2(DEV_NUM),
    parameter REG_ADDR_WIDTH = 32,                       //! Width of SW address bus
    parameter REG_DATA_WIDTH = 64,                       //! Width of SW data bus
    // BKT_FF local
    // parameter BKT_FF_WIDTH   = 10,
    // parameter BKT_FF_DEPTH   = 1024,
    parameter BKT_FF_USEDW   = $clog2(BKT_FF_DEPTH + 1)
) (
    input  logic                                              clk,
    input  logic                                              rst,
    //
    output logic                                              drop_data_ff_rden,
    input  logic                                              drop_data_ff_sop,
    input  logic                                              drop_data_ff_eop,
    input  logic                           [EMPTH_WIDTH-1:0]  drop_data_ff_mty,
    input  logic                                              drop_data_proto_csum_pass,
    input  logic                           [QID_WIDTH-1:0]    drop_data_ff_gid,
    input  logic                           [18-1:0]           drop_data_ff_len,
    input  logic                           [DATA_WIDTH-1:0]   drop_data_ff_data,
    input  logic                                              drop_data_ff_empty,
    //
    input  logic                           [QID_WIDTH-1:0]    idx_per_queue_raddr,
    output logic                           [15:0]             idx_per_queue_rdata,
    //
    output logic                                              idx_per_queue_rd_req_vld,
    output logic                           [QID_WIDTH-1:0]    idx_per_queue_rd_req_qid,
    //
    input  logic                                              idx_per_queue_rd_rsp_vld,
    input  logic                           [DEV_WIDTH-1:0]    idx_per_queue_rd_rsp_dev_id,
    input  logic                           [7:0]              idx_per_queue_rd_rsp_idx_limit_per_queue,
    output logic                                              idx_per_queue_rd_rsp_err,
    //
    output logic                                              idx_per_dev_rd_req_vld,
    output logic                           [DEV_WIDTH-1:0]    idx_per_dev_rd_req_dev_id,
    //
    input  logic                                              idx_per_dev_rd_rsp_vld,
    input  logic                           [7:0]              idx_per_dev_rd_rsp_idx_limit_per_dev,
    output logic                                              idx_per_dev_rd_rsp_err,
    //
    output virtio_rx_buf_req_info_t                           info_out_data,
    output logic                                              info_out_vld,
    input  logic                                              info_out_rdy,
    // rd_data_req
    input  logic                                              rd_data_req_vld,
    output logic                                              rd_data_req_rdy,
    input  virtio_rx_buf_rd_data_req_t                        rd_data_req_data,
    // rd_data_rsp
    output logic                           [255:0]            rd_data_rsp_data,
    output logic                           [EMPTH_WIDTH-1:0]  rd_data_rsp_sty,
    output logic                           [EMPTH_WIDTH-1:0]  rd_data_rsp_mty,
    output logic                                              rd_data_rsp_sop,
    output logic                                              rd_data_rsp_eop,
    output virtio_rx_buf_rd_data_rsp_sbd_t                    rd_data_rsp_sbd,
    output logic                                              rd_data_rsp_vld,
    input  logic                                              rd_data_rsp_rdy,
    // time_stamp
    output logic                           [15:0]             send_time_rdata_drop,
    input  logic                           [QID_WIDTH-1:0]    send_time_raddr_drop,
    input  logic                                              send_time_rden_drop,
    //
    input  logic                           [15:0]             time_stamp,
    input  logic                                              time_stamp_up,
    //
    output logic                           [BKT_FF_USEDW-1:0] bkt_ff_usedw,
    output logic                                              bkt_ff_pempty,
    // rr_sch
    input  logic                           [WEIGHT_WIDTH-1:0] hot_weight,
    input  logic                           [WEIGHT_WIDTH-1:0] cold_weight,
    output virtio_rx_buf_link_stat_t                          link_stat,
    output virtio_rx_buf_link_err_t                           link_err,
    //
    // input  logic                                              csum_drop_ram_rden_up,
    // input  logic                                              qos_drop_ram_rden_up,
    // input  logic                                              pfull_drop_ram_rden_up,
    // output logic                           [QID_WIDTH-1:0]    csum_drop_ram_raddr_ctx,
    // output logic                           [QID_WIDTH-1:0]    qos_drop_ram_raddr_ctx,
    // output logic                           [QID_WIDTH-1:0]    pfull_drop_ram_raddr_ctx,
    // input  logic                           [15:0]             csum_drop_ram_rdata,
    // input  logic                           [15:0]             qos_drop_ram_rdata,
    // input  logic                           [15:0]             pfull_drop_ram_rdata,
    //
    output logic                                              recv_pkt_num_ram_rd_req_vld,
    input  logic                                              recv_pkt_num_ram_rd_req_rdy,
    output logic                           [QID_WIDTH-1:0]    recv_pkt_num_ram_rd_req_addr,
    output logic                                              recv_pkt_num_ram_cnt_clr_en,
    input  logic                                              recv_pkt_num_ram_rd_rsp_vld,
    input  logic                           [16-1:0]           recv_pkt_num_ram_rd_rsp_data,
    //
    output logic                                              csum_drop_pkt_ram_rd_req_vld,
    input  logic                                              csum_drop_pkt_ram_rd_req_rdy,
    output logic                           [QID_WIDTH-1:0]    csum_drop_pkt_ram_rd_req_addr,
    output logic                                              csum_drop_pkt_ram_cnt_clr_en,
    input  logic                                              csum_drop_pkt_ram_rd_rsp_vld,
    input  logic                           [16-1:0]           csum_drop_pkt_ram_rd_rsp_data,
    //
    output logic                                              qos_drop_pkt_ram_rd_req_vld,
    input  logic                                              qos_drop_pkt_ram_rd_req_rdy,
    output logic                           [QID_WIDTH-1:0]    qos_drop_pkt_ram_rd_req_addr,
    output logic                                              qos_drop_pkt_ram_cnt_clr_en,
    input  logic                                              qos_drop_pkt_ram_rd_rsp_vld,
    input  logic                           [16-1:0]           qos_drop_pkt_ram_rd_rsp_data,
    //
    output logic                                              buf_full_drop_pkt_ram_rd_req_vld,
    input  logic                                              buf_full_drop_pkt_ram_rd_req_rdy,
    output logic                           [QID_WIDTH-1:0]    buf_full_drop_pkt_ram_rd_req_addr,
    output logic                                              buf_full_drop_pkt_ram_cnt_clr_en,
    input  logic                                              buf_full_drop_pkt_ram_rd_rsp_vld,
    input  logic                           [16-1:0]           buf_full_drop_pkt_ram_rd_rsp_data,
    //
    output logic                           [19:0]             not_ready_drop_pkt_total,
    //
    output logic                           [19:0]             info_out_pkt_total,
    output logic                           [19:0]             rd_req_pkt_total,
    output logic                           [19:0]             rd_rsp_pkt_total,
    //
    output logic                                              flush,
    // rd_ram
           mlite_if.slave                                     ctx_if

);
    localparam NOTIFY_FF_WIDTH = 10;
    localparam NOTIFY_FF_DEPTH = 32;
    localparam NOTIFY_FF_USEDW = $clog2(NOTIFY_FF_DEPTH + 1);
    localparam FRAME_DATA_WIDTH = DATA_WIDTH + EMPTH_WIDTH + 2;
    localparam FRAME_DATA_DEPTH = BKT_FF_DEPTH * 4;
    localparam FRAME_DATA_DEPTH_WIDTH = $clog2(FRAME_DATA_DEPTH);
    localparam LINK_INFO_WIDTH = BKT_FF_WIDTH + 18 + 1;  // 添加一些信息 . 附带length信息
    localparam LINK_INFO_DEPTH = BKT_FF_DEPTH;
    localparam LINK_INFO_DEPTH_WIDTH = $clog2(FRAME_DATA_DEPTH);
    localparam PC_FSM_INFO_WIDTH = 1 + BKT_FF_WIDTH + BKT_FF_WIDTH;
    localparam PC_FSM_INFO_DEPTH = QID_NUM;
    localparam PC_FSM_INFO_DEPTH_WIDTH = $clog2(FRAME_DATA_DEPTH);
    localparam S_FSM_INFO_WIDTH = 1 + BKT_FF_WIDTH;
    localparam S_FSM_INFO_DEPTH = QID_NUM;
    localparam S_FSM_INFO_DEPTH_WIDTH = $clog2(S_FSM_INFO_DEPTH);
    localparam NEXT_INFO_WIDTH = BKT_FF_WIDTH;
    localparam NEXT_INFO_DEPTH = BKT_FF_DEPTH;
    localparam NEXT_INFO_DEPTH_WIDTH = $clog2(NEXT_INFO_DEPTH);
    localparam IDX_QUE_WIDTH = 16;
    localparam IDX_QUE_DEPTH = QID_NUM;
    localparam IDX_QUE_DEPTH_WIDTH = $clog2(IDX_QUE_DEPTH);
    localparam IDX_DEV_WIDTH = 16;
    localparam IDX_DEV_NUM = DEV_NUM;
    localparam IDX_DEV_NUM_WIDTH = $clog2(IDX_DEV_NUM);
    localparam IDX_MAX_NUM = IDX_DEV_NUM > IDX_QUE_DEPTH ? IDX_DEV_NUM : IDX_QUE_DEPTH;
    localparam IDX_MAX_NUM_WIDTH = $clog2(IDX_MAX_NUM);
    localparam FRAME_INFO_WIDTH = 2;
    localparam FRAME_INFO_DEPTH = BKT_FF_DEPTH;
    localparam FRAME_INFO_DEPTH_WIDTH = $clog2(FRAME_INFO_DEPTH);
    localparam RD_DATA_FF_WIDTH = QID_WIDTH + BKT_FF_WIDTH + 1 + DEV_WIDTH;
    localparam RD_DATA_FF_DEPTH = 32;
    localparam RD_DATA_FF_DEPTH_WIDTH = $clog2(RD_DATA_FF_DEPTH + 1);


    logic [FRAME_DATA_WIDTH-1:0]                                     frame_data_wdata;
    logic [FRAME_DATA_DEPTH_WIDTH-1:0]                               frame_data_waddr;
    logic                                                            frame_data_wren;
    logic [FRAME_DATA_WIDTH-1:0]                                     frame_data_rdata;
    logic [FRAME_DATA_DEPTH_WIDTH-1:0]                               frame_data_raddr;
    // logic [FRAME_DATA_DEPTH_WIDTH-1:0]                               frame_data_raddr_curr;
    // logic [FRAME_DATA_DEPTH_WIDTH-1:0]                               frame_data_raddr_next;
    logic [1:0]                                                      frame_data_err;
    //
    logic [LINK_INFO_WIDTH-1:0]                                      link_info_wdata;
    logic [18-1:0]                                                   link_info_wdata_length;
    logic                                                            link_info_wdata_proto_csum_pass;
    logic [LINK_INFO_DEPTH_WIDTH-1:0]                                link_info_waddr;
    logic                                                            link_info_wren;
    logic [LINK_INFO_WIDTH-1:0]                                      link_info_rdata;
    logic [LINK_INFO_DEPTH_WIDTH-1:0]                                link_info_raddr;
    logic [1:0]                                                      link_info_err;

    logic [PC_FSM_INFO_WIDTH-1:0]                                    pc_fsm_info_wdata;
    logic [PC_FSM_INFO_DEPTH_WIDTH-1:0]                              pc_fsm_info_waddr;
    logic                                                            pc_fsm_info_wren;
    logic [1:0]                        [PC_FSM_INFO_WIDTH-1:0]       pc_fsm_info_rdata;
    logic [1:0]                        [PC_FSM_INFO_DEPTH_WIDTH-1:0] pc_fsm_info_raddr;
    logic [1:0]                        [1:0]                         pc_fsm_info_err;

    logic [S_FSM_INFO_WIDTH-1:0]                                     s_fsm_info_wdata;
    logic [S_FSM_INFO_DEPTH_WIDTH-1:0]                               s_fsm_info_waddr;
    logic                                                            s_fsm_info_wren;
    logic [S_FSM_INFO_WIDTH-1:0]                                     s_fsm_info_rdata;
    logic [S_FSM_INFO_DEPTH_WIDTH-1:0]                               s_fsm_info_raddr;
    logic [1:0]                                                      s_fsm_info_err;

    logic [NEXT_INFO_WIDTH-1:0]                                      next_info_wdata;
    logic [NEXT_INFO_DEPTH_WIDTH-1:0]                                next_info_waddr;
    logic                                                            next_info_wren;
    logic [NEXT_INFO_WIDTH-1:0]                                      next_info_rdata;
    logic [NEXT_INFO_DEPTH_WIDTH-1:0]                                next_info_raddr;
    logic [1:0]                                                      next_info_err;

    logic [IDX_QUE_WIDTH-1:0]                                        idx_que_proc_wdata;
    logic [IDX_QUE_DEPTH_WIDTH-1:0]                                  idx_que_proc_waddr;
    logic                                                            idx_que_proc_wren;
    logic [IDX_QUE_WIDTH-1:0]                                        idx_que_proc_rdata;
    logic [IDX_QUE_DEPTH_WIDTH-1:0]                                  idx_que_proc_raddr;
    logic [1:0]                        [1:0]                         idx_que_proc_err;

    logic [IDX_QUE_WIDTH-1:0]                                        idx_que_comp_wdata;
    logic [IDX_QUE_DEPTH_WIDTH-1:0]                                  idx_que_comp_waddr;
    logic                                                            idx_que_comp_wren;
    logic [1:0]                        [IDX_QUE_WIDTH-1:0]           idx_que_comp_rdata;
    logic [1:0]                        [IDX_QUE_DEPTH_WIDTH-1:0]     idx_que_comp_raddr;
    logic [2:0]                        [1:0]                         idx_que_comp_err;

    logic [IDX_DEV_WIDTH-1:0]                                        idx_dev_proc_wdata;
    logic [IDX_DEV_NUM_WIDTH-1:0]                                    idx_dev_proc_waddr;
    logic                                                            idx_dev_proc_wren;
    logic [IDX_DEV_WIDTH-1:0]                                        idx_dev_proc_rdata;
    logic [IDX_DEV_NUM_WIDTH-1:0]                                    idx_dev_proc_raddr;
    logic [1:0]                                                      idx_dev_proc_err;

    logic [IDX_DEV_WIDTH-1:0]                                        idx_dev_comp_wdata;
    logic [IDX_DEV_NUM_WIDTH-1:0]                                    idx_dev_comp_waddr;
    logic                                                            idx_dev_comp_wren;
    logic [1:0]                        [IDX_DEV_WIDTH-1:0]           idx_dev_comp_rdata;
    logic [1:0]                        [IDX_DEV_NUM_WIDTH-1:0]       idx_dev_comp_raddr;
    logic [1:0]                        [1:0]                         idx_dev_comp_err;


    logic [FRAME_INFO_WIDTH-1:0]                                     frame_info_wdata;
    logic [FRAME_INFO_DEPTH_WIDTH-1:0]                               frame_info_waddr;
    logic                                                            frame_info_wren;
    logic [FRAME_INFO_WIDTH-1:0]                                     frame_info_rdata;
    logic [FRAME_INFO_DEPTH_WIDTH-1:0]                               frame_info_raddr;
    logic [1:0]                                                      frame_info_err;


    //
    logic                                                            bkt_ff_wren;
    logic [BKT_FF_WIDTH-1:0]                                         bkt_ff_din;
    // logic                                                                  bkt_ff_full;
    // logic                                                                  bkt_ff_pfull;
    logic                                                            bkt_ff_overflow;
    logic                                                            bkt_ff_rden;
    logic [BKT_FF_WIDTH-1:0]                                         bkt_ff_dout;
    logic                                                            bkt_ff_empty;
    // logic                                                            bkt_ff_pempty;
    logic                                                            bkt_ff_underflow;
    // logic [BKT_FF_USEDW-1:0]                                         bkt_ff_usedw;
    logic [1:0]                                                      bkt_ff_err;
    //
    logic                                                            notify_rsp_ff_wren;
    logic [NOTIFY_FF_WIDTH-1:0]                                      notify_rsp_ff_din;
    logic                                                            notify_rsp_ff_pfull;
    logic                                                            notify_rsp_ff_overflow;
    logic                                                            notify_rsp_ff_rden;
    logic [NOTIFY_FF_WIDTH-1:0]                                      notify_rsp_ff_dout;
    logic                                                            notify_rsp_ff_empty;
    // logic                                                                  notify_rsp_ff_pempty;
    logic                                                            notify_rsp_ff_underflow;
    logic [NOTIFY_FF_USEDW-1:0]                                      notify_rsp_ff_usedw;
    logic [1:0]                                                      notify_rsp_ff_err;
    logic [QID_WIDTH-1:0]                                            notify_rsp_ff_din_qid;
    logic                                                            notify_rsp_ff_din_cold;
    logic                                                            notify_rsp_ff_din_done;
    //

    logic                                                            rd_data_ff_wren;
    logic [RD_DATA_FF_WIDTH-1:0]                                     rd_data_ff_din;
    // logic                                                            rd_data_ff_full;
    logic                                                            rd_data_ff_pfull;
    // logic                                                            rd_data_ff_overflow;
    logic                                                            rd_data_ff_rden;
    logic [RD_DATA_FF_WIDTH-1:0]                                     rd_data_ff_dout;
    logic                                                            rd_data_ff_empty;
    // logic                                                            rd_data_ff_pempty;
    // logic                                                            rd_data_ff_underflow;
    // logic [RD_DATA_FF_DEPTH_WIDTH-1:0]                                         rd_data_ff_usedw;
    logic [1:0]                                                      rd_data_ff_err;

    logic [7:0]                                                      ctx_que_rom_raddr;
    logic [9:0]                                                      ctx_dev_rom_raddr;
    logic [7:0]                                                      ctx_pc_fsm_rom_raddr;
    logic [7:0]                                                      ctx_s_fsm_rom_raddr;
    logic [7:0]                                                      ctx_next_rom_raddr;
    logic [9:0]                                                      ctx_link_rom_raddr;
    logic [7:0]                                                      ctx_time_rom_raddr;

    ////////////////////////////////////////////////////////////////////////////
    // ram_wr
    logic                                                            drop_data_ff_vld;
    logic [1:0]                                                      ram_wr_offs;


    logic [BKT_FF_WIDTH-1:0]                                         ram_wr_done_bkt_id;
    logic                                                            ram_wr_done_proto_csum_pass;
    logic [QID_WIDTH-1:0]                                            ram_wr_done_vq_gid;
    logic [17:0]                                                     ram_wr_done_length;

    logic                                                            frame_ram_wr_vld;
    logic                                                            frame_ram_wr_rdy;

    enum logic [1:0] {
        RAM_WR_RUN  = 2'b01,
        RAM_WR_DONE = 2'b10
    }
        ram_wr_cstat, ram_wr_nstat;

    assign drop_data_ff_vld  = !drop_data_ff_empty && !bkt_ff_empty && ram_wr_cstat == RAM_WR_RUN;
    assign drop_data_ff_rden = drop_data_ff_vld;

    always @(posedge clk) begin
        frame_data_wdata <= {drop_data_ff_sop, drop_data_ff_eop, drop_data_ff_mty, drop_data_ff_data};
        frame_data_waddr <= {bkt_ff_dout, ram_wr_offs};
        frame_data_wren  <= drop_data_ff_vld;
    end

    assign bkt_ff_rden     = drop_data_ff_vld && (ram_wr_offs == 'b11 || drop_data_ff_eop);

    assign link_info_wdata = {link_info_wdata_proto_csum_pass, link_info_wdata_length, bkt_ff_dout};
    always @(posedge clk) begin
        link_info_wdata_length          <= drop_data_ff_len;
        link_info_wdata_proto_csum_pass <= drop_data_proto_csum_pass;
        link_info_waddr                 <= bkt_ff_dout;
        link_info_wren                  <= drop_data_ff_vld && (ram_wr_offs == 'b11 || drop_data_ff_eop);
    end


    always @(posedge clk) begin
        if (rst) begin
            ram_wr_cstat <= RAM_WR_RUN;
        end else begin
            ram_wr_cstat <= ram_wr_nstat;
        end
    end

    always @(*) begin
        ram_wr_nstat = ram_wr_cstat;
        case (ram_wr_cstat)
            RAM_WR_RUN: begin
                if (drop_data_ff_vld && drop_data_ff_eop) begin
                    ram_wr_nstat = RAM_WR_DONE;
                end
            end
            RAM_WR_DONE: begin
                if (frame_ram_wr_vld && frame_ram_wr_rdy) begin
                    ram_wr_nstat = RAM_WR_RUN;
                end
            end
            default: ram_wr_nstat = RAM_WR_RUN;
        endcase

    end


    always @(posedge clk) begin
        if (rst) begin
            ram_wr_offs <= 'b0;
        end else if (drop_data_ff_vld) begin
            if (drop_data_ff_eop) begin
                ram_wr_offs <= 'b0;
            end else begin
                ram_wr_offs <= ram_wr_offs + 'd1;
            end
        end
    end

    always @(posedge clk) begin
        if (drop_data_ff_sop && drop_data_ff_vld) begin
            ram_wr_done_bkt_id          <= bkt_ff_dout;
            ram_wr_done_proto_csum_pass <= drop_data_proto_csum_pass;
            ram_wr_done_vq_gid          <= drop_data_ff_gid;
            ram_wr_done_length          <= drop_data_ff_len;
        end
    end


    assign frame_ram_wr_vld = ram_wr_cstat == RAM_WR_DONE;
    ////////////////////////////////////////////////////////////////////////////
    // glb cfg

    logic [2:0] odd;
    always @(posedge clk) begin
        if (rst) begin
            odd <= 'b0;
        end else if (odd < 'd5) begin
            odd <= odd + 1'b1;
        end else begin
            odd <= 'b0;
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // P_FSM

    enum logic [3:0] {
        P_FSM_ODD_0 = 4'b0001,
        P_FSM_ODD_1 = 4'b0010,
        P_FSM_ODD_2 = 4'b0100,
        P_FSM_WAIT  = 4'b1000
    }
        p_fsm_cstat, p_fsm_nstat;

    logic [BKT_FF_WIDTH-1:0]            p_fsm_bkt_id;
    logic [QID_WIDTH-1:0]               p_fsm_vq_gid;

    logic                               pc_info_rden_p_fsm;
    logic [PC_FSM_INFO_WIDTH-1:0]       pc_info_rdata_p_fsm;
    logic [PC_FSM_INFO_DEPTH_WIDTH-1:0] pc_info_raddr_p_fsm;

    logic                               pc_info_wren_p_fsm;
    logic [PC_FSM_INFO_WIDTH-1:0]       pc_info_wdata_p_fsm;
    logic [PC_FSM_INFO_DEPTH_WIDTH-1:0] pc_info_waddr_p_fsm;

    logic                               p_fsm_vld;
    logic                               p_fsm_rdy;

    assign frame_ram_wr_rdy = p_fsm_cstat == P_FSM_ODD_0 && odd == 0;


    always @(posedge clk) begin
        if (rst) begin
            p_fsm_cstat <= P_FSM_ODD_0;
        end else begin
            p_fsm_cstat <= p_fsm_nstat;
        end
    end

    always @(*) begin
        p_fsm_nstat = p_fsm_cstat;
        case (p_fsm_cstat)
            P_FSM_ODD_0: begin
                if (frame_ram_wr_vld && frame_ram_wr_rdy) begin  // odd == 0
                    p_fsm_nstat = P_FSM_ODD_1;
                end
            end
            P_FSM_ODD_1: begin  // odd == 1
                p_fsm_nstat = P_FSM_ODD_2;
            end
            P_FSM_ODD_2: begin  // odd == 2
                p_fsm_nstat = P_FSM_WAIT;
            end
            P_FSM_WAIT: begin
                if (p_fsm_vld && p_fsm_rdy) begin
                    p_fsm_nstat = P_FSM_ODD_0;
                end
            end
            default: p_fsm_nstat = P_FSM_ODD_0;
        endcase
    end

    always @(posedge clk) begin
        if (frame_ram_wr_vld && frame_ram_wr_rdy) begin
            p_fsm_bkt_id <= ram_wr_done_bkt_id;
            p_fsm_vq_gid <= ram_wr_done_vq_gid;
        end
    end

    assign pc_info_rden_p_fsm  = frame_ram_wr_vld && frame_ram_wr_rdy;  // odd_0
    assign pc_info_raddr_p_fsm = ram_wr_done_vq_gid;
    always @(posedge clk) begin
        if (p_fsm_cstat == P_FSM_ODD_1) begin
            pc_info_rdata_p_fsm <= pc_fsm_info_rdata[0];
        end
    end

    assign next_info_wren      = p_fsm_cstat == P_FSM_ODD_1 || (p_fsm_cstat == P_FSM_ODD_2 && pc_info_rdata_p_fsm[BKT_FF_WIDTH+BKT_FF_WIDTH+:1]);  // odd_1_2
    assign next_info_waddr     = p_fsm_cstat == P_FSM_ODD_1 ? p_fsm_bkt_id : pc_info_rdata_p_fsm[0+:BKT_FF_WIDTH];
    assign next_info_wdata     = p_fsm_bkt_id;

    assign pc_info_wren_p_fsm  = p_fsm_cstat == P_FSM_ODD_2;  //odd_2
    assign pc_info_waddr_p_fsm = p_fsm_vq_gid;
    assign pc_info_wdata_p_fsm = pc_info_rdata_p_fsm[BKT_FF_WIDTH+BKT_FF_WIDTH+:1] ? {pc_info_rdata_p_fsm[BKT_FF_WIDTH+:BKT_FF_WIDTH+1], p_fsm_bkt_id} : {1'b1, p_fsm_bkt_id, p_fsm_bkt_id};

    // assign pc_info_raddr_p_fsm_1 = p_fsm_vq_gid;
    // assign pc_info_raddr_p_fsm   = p_fsm_cstat == P_FSM_ODD_0 ? ram_wr_done_vq_gid : p_fsm_vq_gid;
    assign p_fsm_vld           = p_fsm_cstat == P_FSM_WAIT;


    ////////////////////////////////////////////////////////////////////////////
    // rr_sch
    logic                 sch_req_vld;
    logic                 sch_req_rdy;
    logic [QID_WIDTH-1:0] sch_req_qid;
    //
    logic                 notify_req_vld;
    logic                 notify_req_rdy;
    logic [QID_WIDTH-1:0] notify_req_qid;
    logic                 notify_req_vld_d;
    logic                 notify_req_rdy_d;
    logic [QID_WIDTH-1:0] notify_req_qid_d;
    //
    logic                 notify_rsp_vld;
    logic                 notify_rsp_rdy;
    logic [QID_WIDTH-1:0] notify_rsp_qid;
    logic                 notify_rsp_cold;
    logic                 notify_rsp_done;

    logic [13:0]          sch_err;
    logic [11:0]          sch_status;

    logic                 notify_rsp_sim_stop = 1;

    assign sch_req_vld = p_fsm_vld && sch_req_rdy;
    assign sch_req_qid = p_fsm_vq_gid;
    assign p_fsm_rdy   = sch_req_rdy;

    virtio_sch #(
        .VQ_WIDTH    (QID_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH)
    ) u0_virtio_sch (
        .clk            (clk),
        .rst            (rst),
        //
        .sch_req_vld    (sch_req_vld),
        .sch_req_rdy    (sch_req_rdy),
        .sch_req_qid    (sch_req_qid),
        //
        // .notify_req_vld (notify_req_vld),
        // .notify_req_rdy (notify_req_rdy),
        // .notify_req_qid (notify_req_qid),
        .notify_req_vld (notify_req_vld_d),
        .notify_req_rdy (notify_req_rdy_d),
        .notify_req_qid (notify_req_qid_d),
        //
        .notify_rsp_vld (notify_rsp_vld && notify_rsp_sim_stop),
        .notify_rsp_rdy (notify_rsp_rdy),
        .notify_rsp_qid (notify_rsp_qid),
        .notify_rsp_cold(notify_rsp_cold),
        .notify_rsp_done(notify_rsp_done),
        //
        .hot_weight     (hot_weight),
        .cold_weight    (cold_weight),
        .dfx_err        (sch_err),
        .dfx_status     (sch_status),
        .notify_req_cnt (),
        .notify_rsp_cnt ()


    );

    always @(posedge clk) begin
        if (rst) begin
            notify_req_vld <= 'b0;
        end else if (!notify_req_vld || notify_req_rdy) begin
            notify_req_vld <= notify_req_vld_d;
        end
    end

    always @(posedge clk) begin
        if (!notify_req_vld || notify_req_rdy) begin
            notify_req_qid <= notify_req_qid_d;
        end
    end

    assign notify_req_rdy_d = !notify_req_vld || notify_req_rdy;

    ////////////////////////////////////////////////////////////////////////////
    // S_FSM


    enum logic [7:0] {
        S_FSM_FLUSH     = 8'b00000001,
        S_FSM_ODD_0     = 8'b00000010,
        S_FSM_ODD_1     = 8'b00000100,
        S_FSM_ODD_2     = 8'b00001000,
        S_FSM_ODD_3     = 8'b00010000,
        S_FSM_ODD_5     = 8'b00100000,
        S_FSM_WAIT_SEND = 8'b01000000,
        S_FSM_RERUN     = 8'b10000000
    }
        s_fsm_cstat, s_fsm_nstat;

    logic                               s_fsm_flush;
    logic [IDX_MAX_NUM_WIDTH-1:0]       s_fsm_flush_wr_addr;


    logic                               s_fsm_vld;
    logic                               s_fsm_rdy;
    logic [QID_WIDTH-1:0]               s_fsm_vq_gid;
    logic [BKT_FF_WIDTH-1:0]            s_fsm_pkt_id;

    logic                               pc_info_rden_s_fsm;
    logic [PC_FSM_INFO_WIDTH-1:0]       pc_info_rdata_s_fsm;
    logic [PC_FSM_INFO_DEPTH_WIDTH-1:0] pc_info_raddr_s_fsm;

    logic                               idx_ctx_que_rd_en_s_fsm;
    logic [DEV_WIDTH-1:0]               idx_ctx_que_rdata_dev_s_fsm;
    logic [7:0]                         idx_ctx_que_rdata_limit_s_fsm;
    logic [IDX_QUE_DEPTH_WIDTH-1:0]     idx_ctx_que_raddr_s_fsm;

    logic                               idx_que_rden;
    logic [IDX_QUE_WIDTH-1:0]           idx_que_rdata_send_s_fsm;
    logic [IDX_QUE_WIDTH-1:0]           idx_que_rdata_send_s_fsm_inc;
    logic [IDX_QUE_WIDTH-1:0]           idx_que_rdata_comp_s_fsm;
    logic [IDX_QUE_DEPTH_WIDTH-1:0]     idx_que_raddr_s_fsm;

    logic                               s_info_rden_s_fsm;
    logic [S_FSM_INFO_WIDTH-1:0]        s_info_rdata_s_fsm;
    logic [S_FSM_INFO_DEPTH_WIDTH-1:0]  s_info_raddr_s_fsm;

    logic                               idx_dev_rden;
    logic [IDX_DEV_WIDTH-1:0]           idx_dev_rdata_send_s_fsm;
    logic [IDX_DEV_WIDTH-1:0]           idx_dev_rdata_send_s_fsm_inc;
    logic [IDX_DEV_WIDTH-1:0]           idx_dev_rdata_comp_s_fsm;
    logic [IDX_DEV_NUM_WIDTH-1:0]       idx_dev_raddr_s_fsm;

    logic                               idx_ctx_dev_rd_en_s_fsm;
    logic [8-1:0]                       idx_ctx_dev_rdata_limit_s_fsm;
    logic [IDX_DEV_NUM_WIDTH-1:0]       idx_ctx_dev_raddr_s_fsm;

    logic                               next_info_rden_s_fsm;
    logic [NEXT_INFO_WIDTH-1:0]         next_info_rdata_s_fsm;
    logic                               next_info_rdata_s_fsm_equal;
    logic [NEXT_INFO_WIDTH-1:0]         next_info_rdata_s_fsm_r;
    logic [NEXT_INFO_DEPTH_WIDTH-1:0]   next_info_raddr_s_fsm;
    logic                               s_fsm_end_flag;
    logic [1:0]                         s_fsm_continue_cnt;

    logic                               s_info_wren_s_fsm;
    logic [S_FSM_INFO_WIDTH-1:0]        s_info_wdata_s_fsm;
    logic [S_FSM_INFO_DEPTH_WIDTH-1:0]  s_info_waddr_s_fsm;

    logic                               frame_info_wren_s_fsm;
    logic [FRAME_INFO_WIDTH-1:0]        frame_info_wdata_s_fsm;
    logic [FRAME_INFO_DEPTH_WIDTH-1:0]  frame_info_waddr_s_fsm;


    logic                               s_fsm_limit_flag;
    logic                               s_fsm_per_que_limit_flag;
    logic                               s_fsm_per_dev_limit_flag;

    logic                               s_fsm_vld_en;

    logic                               s_fsm_wr_status0_flag_pre;  // in doc
    logic                               s_fsm_wr_status1_flag_pre;
    logic                               s_fsm_wr_status2_flag_pre;
    logic                               s_fsm_wr_status3_flag_pre;
    logic                               s_fsm_wr_status0_flag;  // in doc
    logic                               s_fsm_wr_status1_flag;
    logic                               s_fsm_wr_status2_flag;
    logic                               s_fsm_wr_status3_flag;
    logic                               s_fsm_wr_status0_flag_r;
    logic                               s_fsm_wr_status1_flag_r;
    logic                               s_fsm_wr_status2_flag_r;
    logic                               s_fsm_wr_status3_flag_r;


    always @(posedge clk) begin
        if (rst) begin
            s_fsm_continue_cnt <= 'b0;
        end else if (s_fsm_cstat == S_FSM_WAIT_SEND) begin
            if (s_fsm_vld_en) begin
                if (s_fsm_rdy) begin
                    s_fsm_continue_cnt <= s_fsm_continue_cnt + 1;
                end
            end else begin
                s_fsm_continue_cnt <= 0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            s_fsm_cstat <= S_FSM_FLUSH;
        end else begin
            s_fsm_cstat <= s_fsm_nstat;
        end
    end

    always @(*) begin
        s_fsm_nstat = s_fsm_cstat;
        case (s_fsm_cstat)
            S_FSM_FLUSH: begin
                if (s_fsm_flush_wr_addr == IDX_MAX_NUM - 1) begin
                    s_fsm_nstat = S_FSM_ODD_5;
                end
            end
            S_FSM_ODD_5: begin
                if (notify_req_vld && !notify_rsp_ff_pfull && odd == 'd5) begin
                    s_fsm_nstat = S_FSM_ODD_0;
                end
            end
            S_FSM_ODD_0: begin
                s_fsm_nstat = S_FSM_ODD_1;
            end
            S_FSM_ODD_1: begin  // odd == 1
                s_fsm_nstat = S_FSM_ODD_2;
            end
            S_FSM_ODD_2: begin  // odd == 2
                s_fsm_nstat = S_FSM_ODD_3;
            end
            S_FSM_ODD_3: begin  // odd == 3
                s_fsm_nstat = S_FSM_WAIT_SEND;
            end
            S_FSM_WAIT_SEND: begin
                if (s_fsm_vld_en) begin
                    if (s_fsm_rdy) begin
                        if (s_fsm_end_flag || s_fsm_continue_cnt == 'd3) begin
                            s_fsm_nstat = S_FSM_ODD_5;
                        end else begin
                            s_fsm_nstat = S_FSM_RERUN;
                        end
                    end
                end else begin
                    s_fsm_nstat = S_FSM_ODD_5;
                end


            end
            S_FSM_RERUN: begin
                if (odd == 'd5) begin
                    s_fsm_nstat = S_FSM_ODD_0;
                end
            end
            default: s_fsm_nstat = S_FSM_ODD_5;
        endcase
    end

    // S_FSM_FLUSH

    always @(posedge clk) begin
        if (rst) begin
            s_fsm_flush <= 1'b1;
        end else if (s_fsm_flush_wr_addr == IDX_MAX_NUM - 1) begin
            s_fsm_flush <= 1'b0;
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            s_fsm_flush_wr_addr <= 1'b0;
        end else begin
            s_fsm_flush_wr_addr <= s_fsm_flush_wr_addr + 1;
        end
    end



    // S_FSM_ODD_5

    logic idx_ctx_que_rd_en_s_fsm_r;
    logic idx_per_queue_rd_rsp_vld_s_fsm;

    assign notify_req_rdy = (odd == 'd5) && (s_fsm_cstat == S_FSM_ODD_5) && (!notify_rsp_ff_pfull);

    always @(posedge clk) begin
        if (notify_req_vld && notify_req_rdy) begin
            s_fsm_vq_gid <= notify_req_qid;
        end
    end

    assign idx_ctx_que_rd_en_s_fsm = (s_fsm_cstat == S_FSM_ODD_5 && s_fsm_nstat == S_FSM_ODD_0);  // odd_5
    assign idx_ctx_que_raddr_s_fsm = notify_req_qid;

    always @(posedge clk) begin
        idx_ctx_que_rd_en_s_fsm_r <= idx_ctx_que_rd_en_s_fsm;
    end

    assign idx_per_queue_rd_rsp_vld_s_fsm = idx_ctx_que_rd_en_s_fsm_r;  // odd_0

    always @(posedge clk) begin
        if (idx_per_queue_rd_rsp_vld_s_fsm) begin
            idx_ctx_que_rdata_dev_s_fsm   <= idx_per_queue_rd_rsp_dev_id;  // odd_1
            idx_ctx_que_rdata_limit_s_fsm <= idx_per_queue_rd_rsp_idx_limit_per_queue;
        end
    end


    // S_FSM_ODD_0

    // for head.v
    assign pc_info_rden_s_fsm    = s_fsm_cstat == S_FSM_ODD_0;
    assign pc_info_raddr_s_fsm   = s_fsm_vq_gid;

    assign idx_que_rden          = s_fsm_cstat == S_FSM_ODD_0;
    assign idx_que_proc_raddr    = idx_que_rden ? s_fsm_vq_gid : ctx_que_rom_raddr;
    assign idx_que_comp_raddr[0] = idx_que_rden ? s_fsm_vq_gid : ctx_que_rom_raddr;

    // for s_end.v
    assign s_info_rden_s_fsm     = s_fsm_cstat == S_FSM_ODD_0;
    assign s_info_raddr_s_fsm    = s_fsm_vq_gid;





    always @(posedge clk) begin
        if (s_fsm_cstat == S_FSM_ODD_1) begin
            pc_info_rdata_s_fsm          <= pc_fsm_info_rdata[1];  // odd_2
            idx_que_rdata_send_s_fsm     <= idx_que_proc_rdata[15:0];
            idx_que_rdata_send_s_fsm_inc <= idx_que_proc_rdata[15:0] + 1;
            idx_que_rdata_comp_s_fsm     <= idx_que_comp_rdata[0][15:0];
            s_info_rdata_s_fsm           <= s_fsm_info_rdata;

            s_fsm_wr_status0_flag_pre    <= pc_fsm_info_rdata[1][BKT_FF_WIDTH+BKT_FF_WIDTH+:1] == 'h0;
            s_fsm_wr_status1_flag_pre    <= pc_fsm_info_rdata[1][BKT_FF_WIDTH+BKT_FF_WIDTH+:1] == 'h1 && s_fsm_info_rdata[BKT_FF_WIDTH+:1] == 'h0;
            s_fsm_wr_status2_flag_pre    <= pc_fsm_info_rdata[1][BKT_FF_WIDTH+BKT_FF_WIDTH+:1] == 'h1 && s_fsm_info_rdata[BKT_FF_WIDTH+:1] == 'h1;
            s_fsm_wr_status3_flag_pre    <= pc_fsm_info_rdata[1][BKT_FF_WIDTH+BKT_FF_WIDTH+:1] == 'h1 && s_fsm_info_rdata[BKT_FF_WIDTH+:1] == 'h1;
        end







    end


    // S_FSM_ODD_1

    assign idx_dev_rden            = s_fsm_cstat == S_FSM_ODD_1;
    assign idx_dev_proc_raddr      = idx_dev_rden ? idx_ctx_que_rdata_dev_s_fsm : ctx_dev_rom_raddr;
    assign idx_dev_comp_raddr[0]   = idx_dev_rden ? idx_ctx_que_rdata_dev_s_fsm : ctx_dev_rom_raddr;

    assign idx_ctx_dev_rd_en_s_fsm = s_fsm_cstat == S_FSM_ODD_1;
    assign idx_ctx_dev_raddr_s_fsm = idx_ctx_que_rdata_dev_s_fsm;

    assign next_info_rden_s_fsm    = s_fsm_cstat == S_FSM_ODD_1;
    assign next_info_raddr_s_fsm   = s_fsm_info_rdata;

    always @(posedge clk) begin
        if (s_fsm_cstat == S_FSM_ODD_2) begin
            idx_dev_rdata_send_s_fsm      <= idx_dev_proc_rdata[15:0];  // odd_3
            idx_dev_rdata_send_s_fsm_inc  <= idx_dev_proc_rdata[15:0] + 1;
            idx_dev_rdata_comp_s_fsm      <= idx_dev_comp_rdata[0][15:0];
            idx_ctx_dev_rdata_limit_s_fsm <= idx_per_dev_rd_rsp_idx_limit_per_dev;

            s_fsm_per_que_limit_flag      <= ((idx_que_rdata_send_s_fsm - idx_que_rdata_comp_s_fsm) == idx_ctx_que_rdata_limit_s_fsm);
            s_fsm_per_dev_limit_flag      <= ((idx_dev_proc_rdata[15:0] - idx_dev_comp_rdata[0][15:0]) == idx_per_dev_rd_rsp_idx_limit_per_dev);
            s_fsm_limit_flag              <= ((idx_que_rdata_send_s_fsm - idx_que_rdata_comp_s_fsm) == idx_ctx_que_rdata_limit_s_fsm) || ((idx_dev_proc_rdata[15:0] - idx_dev_comp_rdata[0][15:0]) == idx_per_dev_rd_rsp_idx_limit_per_dev);

            next_info_rdata_s_fsm         <= next_info_rdata;  // odd_3
            next_info_rdata_s_fsm_equal   <= next_info_rdata == s_info_rdata_s_fsm[0+:BKT_FF_WIDTH];
            s_fsm_end_flag                <= s_fsm_wr_status1_flag_pre ? pc_info_rdata_s_fsm[BKT_FF_WIDTH+:BKT_FF_WIDTH] == pc_info_rdata_s_fsm[0+:BKT_FF_WIDTH] : next_info_rdata == pc_info_rdata_s_fsm[0+:BKT_FF_WIDTH];


        end
    end

    // S_FSM_ODD_2


    // S_FSM_ODD_3

    assign s_fsm_wr_status0_flag = s_fsm_wr_status0_flag_pre;
    assign s_fsm_wr_status1_flag = s_fsm_wr_status1_flag_pre;
    assign s_fsm_wr_status2_flag = s_fsm_wr_status2_flag_pre && next_info_rdata_s_fsm_equal;
    assign s_fsm_wr_status3_flag = s_fsm_wr_status3_flag_pre && !next_info_rdata_s_fsm_equal;

    logic s_fsm_wr_en;
    assign s_fsm_wr_en            = s_fsm_cstat == S_FSM_ODD_3 && !s_fsm_limit_flag && (s_fsm_wr_status1_flag || s_fsm_wr_status3_flag);

    assign s_info_wren_s_fsm      = s_fsm_wr_en;
    assign s_info_waddr_s_fsm     = s_fsm_vq_gid;
    assign s_info_wdata_s_fsm     = s_fsm_wr_status1_flag ? {1'b1, pc_info_rdata_s_fsm[BKT_FF_WIDTH+:BKT_FF_WIDTH]} : {1'b1, next_info_rdata_s_fsm};

    assign frame_info_wren_s_fsm  = s_fsm_wr_en;
    assign frame_info_waddr_s_fsm = s_fsm_wr_status1_flag ? pc_info_rdata_s_fsm[BKT_FF_WIDTH+:BKT_FF_WIDTH] : next_info_rdata_s_fsm;  // pkt_id
    assign frame_info_wdata_s_fsm = 2'b00;

    always @(posedge clk) begin
        if (s_fsm_cstat == S_FSM_ODD_3) begin
            s_fsm_vld_en            <= !s_fsm_limit_flag && (s_fsm_wr_status1_flag || s_fsm_wr_status3_flag);
            s_fsm_wr_status0_flag_r <= s_fsm_wr_status0_flag;  // odd_4
            s_fsm_wr_status1_flag_r <= s_fsm_wr_status1_flag;
            s_fsm_wr_status2_flag_r <= s_fsm_wr_status2_flag;
            s_fsm_wr_status3_flag_r <= s_fsm_wr_status3_flag;

            s_fsm_pkt_id            <= s_fsm_wr_status1_flag ? {1'b1, pc_info_rdata_s_fsm[BKT_FF_WIDTH+:BKT_FF_WIDTH]} : {1'b1, next_info_rdata_s_fsm};
            // next_info_rdata_s_fsm_r <= next_info_rdata_s_fsm;
            // s_fsm_end_flag          <= next_info_rdata_s_fsm == pc_info_rdata_s_fsm[0+:BKT_FF_WIDTH];
        end
    end

    assign idx_dev_proc_wren    = s_fsm_flush || s_fsm_wr_en;
    assign idx_dev_proc_waddr   = s_fsm_flush ? s_fsm_flush_wr_addr : idx_ctx_que_rdata_dev_s_fsm;
    assign idx_dev_proc_wdata   = s_fsm_flush ? 0 : idx_dev_rdata_send_s_fsm_inc;

    assign idx_que_proc_wren    = s_fsm_flush || s_fsm_wr_en;
    assign idx_que_proc_waddr   = s_fsm_flush ? s_fsm_flush_wr_addr : s_fsm_vq_gid;
    assign idx_que_proc_wdata   = s_fsm_flush ? 0 : idx_que_rdata_send_s_fsm_inc;



    // S_FSM_WAIT_SEND

    assign s_fsm_vld            = s_fsm_cstat == S_FSM_WAIT_SEND && s_fsm_vld_en;
    assign s_fsm_rdy            = info_out_rdy;

    assign info_out_vld         = s_fsm_vld;
    assign info_out_data.pkt_id = s_fsm_pkt_id;
    assign info_out_data.vq.qid = s_fsm_vq_gid;
    assign info_out_data.vq.typ = VIRTIO_NET_RX_TYPE;

    // always @(posedge clk) begin
    //     if (s_fsm_cstat == S_FSM_ODD_3) begin
    //         s_fsm_pkt_id <= s_fsm_wr_status1_flag ? {1'b1, pc_info_rdata_s_fsm[BKT_FF_WIDTH+:BKT_FF_WIDTH]} : {1'b1, next_info_rdata_s_fsm};
    //     end
    // end

    always @(posedge clk) begin
        if (rst) begin
            info_out_pkt_total <= 'b0;
        end else if (info_out_vld & info_out_rdy) begin
            info_out_pkt_total <= info_out_pkt_total + 1'b1;
        end
    end

    // S_FSM_WAIT_RSP


    yucca_sync_fifo #(
        .DATA_WIDTH (NOTIFY_FF_WIDTH),
        .FIFO_DEPTH (NOTIFY_FF_DEPTH),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL(24),
        .RAM_MODE   ("dist"),
        .FIFO_MODE  ("fwft")
    ) u_notify_rsp_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (notify_rsp_ff_wren),
        .din           (notify_rsp_ff_din),
        .full          (),
        .pfull         (notify_rsp_ff_pfull),
        .overflow      (notify_rsp_ff_overflow),
        .rden          (notify_rsp_ff_rden),
        .dout          (notify_rsp_ff_dout),
        .empty         (notify_rsp_ff_empty),
        .pempty        (),
        .underflow     (notify_rsp_ff_underflow),
        .usedw         (notify_rsp_ff_usedw),
        .parity_ecc_err(notify_rsp_ff_err)
    );

    assign notify_rsp_ff_wren     = s_fsm_cstat != S_FSM_ODD_5 && s_fsm_nstat == S_FSM_ODD_5;
    assign notify_rsp_ff_din_qid  = s_fsm_vq_gid;
    assign notify_rsp_ff_din_cold = s_fsm_limit_flag;
    assign notify_rsp_ff_din_done = s_fsm_wr_status0_flag_r || s_fsm_wr_status2_flag_r || (s_fsm_vld_en && s_fsm_end_flag);
    assign notify_rsp_ff_din      = {notify_rsp_ff_din_qid, notify_rsp_ff_din_cold, notify_rsp_ff_din_done};

    assign notify_rsp_ff_rden     = notify_rsp_vld && notify_rsp_rdy && notify_rsp_sim_stop;
    assign notify_rsp_vld         = !notify_rsp_ff_empty;
    assign notify_rsp_qid         = notify_rsp_ff_dout[2+:QID_WIDTH];
    assign notify_rsp_cold        = notify_rsp_ff_dout[1];
    assign notify_rsp_done        = notify_rsp_ff_dout[0];



    // ERR CHECK
    always @(posedge clk) begin
        if (rst) begin
            idx_per_queue_rd_rsp_err <= 1'b0;
        end else if (s_fsm_cstat == S_FSM_ODD_0 && !idx_per_queue_rd_rsp_vld) begin
            idx_per_queue_rd_rsp_err <= 1'b1;
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            idx_per_dev_rd_rsp_err <= 1'b0;
        end else if (s_fsm_cstat == S_FSM_ODD_2 && !idx_per_dev_rd_rsp_vld) begin
            idx_per_dev_rd_rsp_err <= 1'b1;
        end
    end


    ////////////////////////////////////////////////////////////////////////////
    // C_FSM
    // input  logic                                          rd_data_req_vld,
    // output logic                                          rd_data_req_rdy,
    // output virtio_rx_buf_rd_data_req_t                    rd_data_req_data,
    enum logic [7:0] {
        C_FSM_FLUSH = 8'b00000001,
        C_FSM_ODD_2 = 8'b00000010,
        C_FSM_ODD_3 = 8'b00000100,
        C_FSM_ODD_4 = 8'b00001000,
        C_FSM_ODD_5 = 8'b00010000,
        C_FSM_ODD_0 = 8'b00100000,
        C_FSM_WAIT  = 8'b01000000,
        C_FSM_RERUN = 8'b10000000

    }
        c_fsm_cstat, c_fsm_nstat;
    logic                               c_fsm_flush;
    logic [IDX_MAX_NUM_WIDTH-1:0]       c_fsm_flush_wr_addr;

    // logic                           c_fsm_rerun_flag;
    logic                               c_fsm_vld;
    logic                               c_fsm_rdy;

    // C_FSM_ODD_2
    logic [QID_WIDTH-1:0]               c_fsm_vq_gid;
    logic [BKT_FF_WIDTH-1:0]            c_fsm_pkt_id;
    logic                               c_fsm_drop;

    logic                               idx_ctx_que_rd_en_c_fsm;
    logic [IDX_QUE_DEPTH_WIDTH-1:0]     idx_ctx_que_raddr_c_fsm;

    logic [DEV_WIDTH-1:0]               idx_ctx_que_rdata_dev_c_fsm;

    // C_FSM_ODD_3

    logic                               pc_info_rden_c_fsm;
    logic [PC_FSM_INFO_WIDTH-1:0]       pc_info_rdata_c_fsm;
    logic [PC_FSM_INFO_DEPTH_WIDTH-1:0] pc_info_raddr_c_fsm;

    logic                               s_info_rden_c_fsm;
    logic [S_FSM_INFO_WIDTH-1:0]        s_info_rdata_c_fsm;
    logic [S_FSM_INFO_DEPTH_WIDTH-1:0]  s_info_raddr_c_fsm;

    logic                               next_info_rden_c_fsm;
    logic [NEXT_INFO_WIDTH-1:0]         next_info_rdata_c_fsm;
    logic [NEXT_INFO_DEPTH_WIDTH-1:0]   next_info_raddr_c_fsm;

    logic                               frame_info_rden_c_fsm;
    logic [FRAME_INFO_WIDTH-1:0]        frame_info_rdata_c_fsm;
    logic [FRAME_INFO_DEPTH_WIDTH-1:0]  frame_info_raddr_c_fsm;

    logic                               c_fsm_head_v;
    logic [BKT_FF_WIDTH-1:0]            c_fsm_head;
    logic [BKT_FF_WIDTH-1:0]            c_fsm_end;
    logic                               c_fsm_s_end_v;
    logic [BKT_FF_WIDTH-1:0]            c_fsm_s_end;
    logic [BKT_FF_WIDTH-1:0]            c_fsm_next;
    logic [FRAME_INFO_WIDTH-1:0]        c_fsm_frame_info_curr;

    logic                               c_fsm_first_flag;
    logic                               c_fsm_s_end_flag;
    logic                               c_fsm_end_flag;

    // C_FSM_ODD_4

    logic                               c_fsm_next_drop;
    logic                               c_fsm_next_vld;

    // C_FSM_ODD_0

    logic                               frame_info_wren_c_fsm;
    logic [FRAME_INFO_WIDTH-1:0]        frame_info_wdata_c_fsm;
    logic [FRAME_INFO_DEPTH_WIDTH-1:0]  frame_info_waddr_c_fsm;

    logic                               s_info_wren_c_fsm;
    logic [S_FSM_INFO_WIDTH-1:0]        s_info_wdata_c_fsm;
    logic [S_FSM_INFO_DEPTH_WIDTH-1:0]  s_info_waddr_c_fsm;

    logic                               pc_info_wren_c_fsm;
    logic [PC_FSM_INFO_WIDTH-1:0]       pc_info_wdata_c_fsm;
    logic [PC_FSM_INFO_DEPTH_WIDTH-1:0] pc_info_waddr_c_fsm;


    logic                               c_fsm_done_vld;
    logic                               c_fsm_done_rdy;
    logic [QID_WIDTH-1:0]               c_fsm_done_vq_gid;
    logic [DEV_WIDTH-1:0]               c_fsm_done_dev_id;
    logic [BKT_FF_WIDTH-1:0]            c_fsm_done_pkt_id;
    logic                               c_fsm_done_drop;





    always @(posedge clk) begin
        if (rst) begin
            c_fsm_cstat <= C_FSM_FLUSH;
        end else begin
            c_fsm_cstat <= c_fsm_nstat;
        end
    end

    always @(*) begin
        c_fsm_nstat = c_fsm_cstat;
        case (c_fsm_cstat)
            C_FSM_FLUSH: begin
                if (c_fsm_flush_wr_addr == IDX_MAX_NUM - 1) begin
                    c_fsm_nstat = C_FSM_ODD_2;
                end
            end
            C_FSM_ODD_2: begin
                if (c_fsm_vld && c_fsm_rdy) begin  // odd == 10
                    c_fsm_nstat = C_FSM_ODD_3;
                end
            end
            C_FSM_ODD_3: begin
                c_fsm_nstat = C_FSM_ODD_4;
            end
            C_FSM_ODD_4: begin
                c_fsm_nstat = C_FSM_ODD_5;
            end
            C_FSM_ODD_5: begin
                c_fsm_nstat = C_FSM_ODD_0;
            end
            C_FSM_ODD_0: begin  // odd == 00
                c_fsm_nstat = C_FSM_WAIT;
            end
            C_FSM_WAIT: begin
                if (c_fsm_next_vld && !c_fsm_s_end_flag) begin
                    if (c_fsm_done_rdy) begin
                        c_fsm_nstat = C_FSM_RERUN;
                    end
                end else begin
                    if (c_fsm_done_rdy) begin
                        c_fsm_nstat = C_FSM_ODD_2;
                    end
                end
            end
            C_FSM_RERUN: begin
                if (odd == 'd2) begin
                    c_fsm_nstat = C_FSM_ODD_3;
                end
            end



            default: c_fsm_nstat = C_FSM_ODD_2;
        endcase
    end

    // C_FSM_FLUSH

    always @(posedge clk) begin
        if (rst) begin
            c_fsm_flush <= 1'b1;
        end else if (c_fsm_flush_wr_addr == IDX_MAX_NUM - 1) begin
            c_fsm_flush <= 1'b0;
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            c_fsm_flush_wr_addr <= 1'b0;
        end else begin
            c_fsm_flush_wr_addr <= c_fsm_flush_wr_addr + 1;
        end
    end


    // C_FSM_ODD_2

    assign c_fsm_rdy = c_fsm_cstat == C_FSM_ODD_2 && odd == 'd2;

    always @(posedge clk) begin
        if (c_fsm_cstat == C_FSM_ODD_2 && c_fsm_vld && c_fsm_rdy) begin
            c_fsm_vq_gid <= rd_data_req_data.vq.qid;
            c_fsm_pkt_id <= rd_data_req_data.pkt_id;
            c_fsm_drop   <= rd_data_req_data.drop;
        end else if (c_fsm_cstat == C_FSM_RERUN && odd == 'd2) begin
            c_fsm_pkt_id <= c_fsm_next;
            c_fsm_drop   <= c_fsm_next_drop;
        end
    end

    assign idx_ctx_que_rd_en_c_fsm = c_fsm_vld && c_fsm_rdy;  // odd_2
    assign idx_ctx_que_raddr_c_fsm = rd_data_req_data.vq.qid;

    always @(posedge clk) begin
        if (c_fsm_cstat == C_FSM_ODD_3) begin
            idx_ctx_que_rdata_dev_c_fsm <= idx_per_queue_rd_rsp_dev_id;  //odd_4
        end
    end


    // C_FSM_ODD_3

    assign pc_info_rden_c_fsm     = c_fsm_cstat == C_FSM_ODD_3;
    assign pc_info_raddr_c_fsm    = c_fsm_vq_gid;
    assign pc_info_rdata_c_fsm    = pc_fsm_info_rdata[0];

    assign s_info_rden_c_fsm      = c_fsm_cstat == C_FSM_ODD_3;
    assign s_info_raddr_c_fsm     = c_fsm_vq_gid;
    assign s_info_rdata_c_fsm     = s_fsm_info_rdata;

    assign next_info_rden_c_fsm   = c_fsm_cstat == C_FSM_ODD_3;
    assign next_info_raddr_c_fsm  = c_fsm_pkt_id;
    assign next_info_rdata_c_fsm  = next_info_rdata;

    assign frame_info_rden_c_fsm  = c_fsm_cstat == C_FSM_ODD_3 || c_fsm_cstat == C_FSM_ODD_4;
    assign frame_info_raddr_c_fsm = c_fsm_cstat == C_FSM_ODD_3 ? c_fsm_pkt_id : next_info_rdata;  // 在第二拍读取下一包的数据的vld
    assign frame_info_rdata_c_fsm = frame_info_rdata;


    always @(posedge clk) begin
        if (c_fsm_cstat == C_FSM_ODD_4) begin
            c_fsm_head_v          <= pc_info_rdata_c_fsm[BKT_FF_WIDTH+BKT_FF_WIDTH+:1];  // odd_5
            c_fsm_head            <= pc_info_rdata_c_fsm[BKT_FF_WIDTH+:BKT_FF_WIDTH];
            c_fsm_end             <= pc_info_rdata_c_fsm[0+:BKT_FF_WIDTH];

            c_fsm_s_end_v         <= s_info_rdata_c_fsm[BKT_FF_WIDTH+:1];
            c_fsm_s_end           <= s_info_rdata_c_fsm[0+:BKT_FF_WIDTH];

            c_fsm_next            <= next_info_rdata_c_fsm;
            c_fsm_frame_info_curr <= frame_info_rdata_c_fsm;

            c_fsm_first_flag      <= c_fsm_pkt_id == pc_info_rdata_c_fsm[BKT_FF_WIDTH+:BKT_FF_WIDTH];
            c_fsm_s_end_flag      <= c_fsm_pkt_id == s_info_rdata_c_fsm[0+:BKT_FF_WIDTH];
            c_fsm_end_flag        <= c_fsm_pkt_id == next_info_rdata_c_fsm;
        end
    end

    // C_FSM_ODD_4
    always @(posedge clk) begin
        if (c_fsm_cstat == C_FSM_ODD_5) begin
            c_fsm_next_drop <= frame_info_rdata_c_fsm[1];  // odd_0
            c_fsm_next_vld  <= frame_info_rdata_c_fsm[0];  // odd_0
        end
    end
    // C_FSM_ODD_0

    assign frame_info_wren_c_fsm  = c_fsm_cstat == C_FSM_ODD_0;
    assign frame_info_wdata_c_fsm = c_fsm_first_flag ? 2'b0 : {c_fsm_drop, 1'b1};
    assign frame_info_waddr_c_fsm = c_fsm_pkt_id;


    assign s_info_wren_c_fsm      = c_fsm_cstat == C_FSM_ODD_0 && c_fsm_first_flag && c_fsm_s_end_flag;
    assign s_info_wdata_c_fsm     = {1'b0, c_fsm_s_end};
    assign s_info_waddr_c_fsm     = c_fsm_vq_gid;

    assign pc_info_wren_c_fsm     = c_fsm_cstat == C_FSM_ODD_0 && c_fsm_first_flag;
    assign pc_info_wdata_c_fsm    = c_fsm_end_flag ? {1'b0, c_fsm_head, c_fsm_end} : {c_fsm_head_v, c_fsm_next, c_fsm_end};
    assign pc_info_waddr_c_fsm    = c_fsm_vq_gid;

    assign c_fsm_vld              = rd_data_req_vld;
    assign rd_data_req_rdy        = c_fsm_rdy;

    always @(posedge clk) begin
        if (rst) begin
            rd_req_pkt_total <= 'b0;
        end else if (rd_data_req_vld & rd_data_req_rdy) begin
            rd_req_pkt_total <= rd_req_pkt_total + 1'b1;
        end
    end


    always @(posedge clk) begin
        if (rst) begin
            c_fsm_done_vld <= 'b0;
        end else if (c_fsm_cstat == C_FSM_ODD_0 && c_fsm_first_flag) begin
            c_fsm_done_vld <= 'b1;
        end else if (c_fsm_done_rdy && c_fsm_done_vld) begin
            c_fsm_done_vld <= 'b0;
        end
    end

    assign c_fsm_done_drop   = c_fsm_drop;
    assign c_fsm_done_vq_gid = c_fsm_vq_gid;
    assign c_fsm_done_pkt_id = c_fsm_pkt_id;
    assign c_fsm_done_dev_id = idx_ctx_que_rdata_dev_c_fsm;
    assign c_fsm_done_rdy    = !rd_data_ff_pfull;



    ////////////////////////////////////////////////////////////////////////////
    // ram_rd
    enum logic [1:0] {
        BKT_RD_RST = 2'b01,
        BKT_RD_RUN = 2'b10
    }
        bkt_rd_cstat, bkt_rd_nstat;



    enum logic [6:0] {
        RAM_RD_IDLE      = 7'b0000001,
        RAM_RD_INIT      = 7'b0000010,
        RAM_RD_DELAY     = 7'b0000100,
        RAM_RD_DROP      = 7'b0001000,
        RAM_RD_SEND_HEAD = 7'b0010000,
        RAM_RD_SEND      = 7'b0100000,
        RAM_RD_DELAY2    = 7'b1000000

    }
        ram_rd_cstat, ram_rd_cstat_d, ram_rd_nstat;

    logic [BKT_FF_WIDTH+1:0]  ram_rd_addr_test;
    logic [1:0]               ram_rd_offs;
    logic [1:0]               ram_rd_offs_curr;
    logic [1:0]               ram_rd_offs_next;
    logic                     ram_rd_en;
    logic [BKT_FF_WIDTH-1:0]  ram_rd_addr;
    logic [BKT_FF_WIDTH-1:0]  ram_rd_addr_curr;
    logic [BKT_FF_WIDTH-1:0]  ram_rd_addr_next;
    logic                     ram_rd_info_drop;
    logic [BKT_FF_WIDTH-1:0]  ram_rd_info_pkt_id;
    logic [DEV_WIDTH-1:0]     ram_rd_info_dev_id;
    logic [QID_WIDTH-1:0]     ram_rd_info_vq_gid;
    logic                     ram_rd_info_proto_csum_pass;
    logic                     ram_rd_info_proto_csum_pass_r;
    logic [17:0]              ram_rd_info_length;
    logic [BKT_FF_WIDTH-1:0]  ram_rd_next;

    logic                     ram_rd_vld;
    logic                     ram_rd_rdy;

    logic [IDX_QUE_WIDTH-1:0] idx_que_rdata_comp_c_fsm_inc;
    logic [IDX_DEV_WIDTH-1:0] idx_dev_rdata_comp_c_fsm_inc;

    // logic [FRAME_DATA_WIDTH-1:0] ram_rd_data_old;
    // logic [FRAME_DATA_WIDTH-1:0] ram_rd_data_new;

    // assign ram_rd_addr_test            = {ram_rd_addr, ram_rd_offs};

    assign ram_rd_info_vq_gid          = rd_data_ff_dout[0+:QID_WIDTH];
    assign ram_rd_info_pkt_id          = rd_data_ff_dout[QID_WIDTH+:BKT_FF_WIDTH];
    assign ram_rd_info_drop            = rd_data_ff_dout[QID_WIDTH+BKT_FF_WIDTH+:1];
    assign ram_rd_info_dev_id          = rd_data_ff_dout[QID_WIDTH+BKT_FF_WIDTH+1+:DEV_WIDTH];
    assign ram_rd_info_proto_csum_pass = link_info_rdata[BKT_FF_WIDTH+18+:1];
    assign ram_rd_info_length          = link_info_rdata[BKT_FF_WIDTH+:18];


    always @(posedge clk) begin
        if (rst) begin
            ram_rd_cstat <= RAM_RD_IDLE;
        end else begin
            ram_rd_cstat <= ram_rd_nstat;
        end
        ram_rd_cstat_d <= ram_rd_cstat;
    end

    always @(*) begin
        ram_rd_nstat = ram_rd_cstat;
        case (ram_rd_cstat)
            RAM_RD_IDLE: begin
                if (!rd_data_ff_empty && bkt_rd_cstat == BKT_RD_RUN) begin
                    ram_rd_nstat = RAM_RD_INIT;
                end
            end
            RAM_RD_INIT: begin
                ram_rd_nstat = RAM_RD_DELAY;
            end
            RAM_RD_DELAY: begin

                if (ram_rd_info_drop) begin
                    ram_rd_nstat = RAM_RD_DROP;
                end else begin
                    ram_rd_nstat = RAM_RD_SEND_HEAD;
                end

            end
            RAM_RD_DROP: begin
                if (ram_rd_vld && ram_rd_rdy && frame_data_rdata[DATA_WIDTH+EMPTH_WIDTH+:1]) begin
                    ram_rd_nstat = RAM_RD_DELAY2;
                end
            end
            RAM_RD_SEND_HEAD: begin
                if (ram_rd_rdy) begin
                    ram_rd_nstat = RAM_RD_SEND;
                end
            end
            RAM_RD_SEND: begin
                if (ram_rd_vld && ram_rd_rdy && frame_data_rdata[DATA_WIDTH+EMPTH_WIDTH+:1]) begin
                    ram_rd_nstat = RAM_RD_DELAY2;
                end
            end
            RAM_RD_DELAY2: begin
                ram_rd_nstat = RAM_RD_IDLE;
            end
            default: ram_rd_nstat = RAM_RD_IDLE;
        endcase

    end

    assign ram_rd_next = link_info_rdata[0+:BKT_FF_WIDTH];
    logic ram_vld0;
    logic ram_vld1;
    logic ram_vld2;
    assign ram_vld0 = (ram_rd_vld && ram_rd_rdy) || ram_rd_cstat == RAM_RD_INIT;
    assign ram_vld1 = (ram_rd_vld && ram_rd_rdy) || ram_rd_cstat == RAM_RD_INIT;
    assign ram_vld2 = (ram_rd_vld && ram_rd_rdy) || ram_rd_cstat == RAM_RD_INIT;
    always @(posedge clk) begin
        if (ram_rd_cstat == RAM_RD_IDLE) begin
            ram_rd_addr_next <= ram_rd_info_pkt_id;
        end else if (ram_rd_offs == 'b11 && ram_rd_vld && ram_rd_rdy) begin
            ram_rd_addr_next <= ram_rd_next;
        end
    end

    always @(posedge clk) begin
        if (ram_vld0) begin
            ram_rd_addr_curr <= ram_rd_addr_next;
        end
    end

    assign ram_rd_addr = ram_vld0 ? ram_rd_addr_next : ram_rd_addr_curr;

    always @(posedge clk) begin
        if (ram_rd_cstat == RAM_RD_IDLE) begin
            ram_rd_offs_next <= 0;
        end else if (ram_vld1) begin
            // if (rd_data_rsp_eop) begin
            //     ram_rd_offs_next <= 0;
            // end else begin
            ram_rd_offs_next <= ram_rd_offs_next + 1;
            // end
        end
    end

    always @(posedge clk) begin
        if (ram_vld1) begin
            ram_rd_offs_curr <= ram_rd_offs_next;
        end
    end

    assign ram_rd_offs = ram_vld2 ? ram_rd_offs_next : ram_rd_offs_curr;

    assign ram_rd_en   = ram_rd_cstat != RAM_RD_IDLE && ram_rd_cstat != RAM_RD_DELAY2;

    virtio_rx_buf_rd_data_rsp_sbd_t rd_data_rsp_sbd_inside;
    // // sbd
    always @(posedge clk) begin
        if (ram_rd_cstat == RAM_RD_DELAY) begin

            ram_rd_info_proto_csum_pass_r  <= ram_rd_info_proto_csum_pass;  // virtio_head
            rd_data_rsp_sbd_inside.pkt_len <= ram_rd_info_length + 'd12;  // virtio_head
            rd_data_rsp_sbd_inside.vq.typ  <= VIRTIO_NET_RX_TYPE;
            rd_data_rsp_sbd_inside.vq.qid  <= ram_rd_info_vq_gid;
        end
    end


    // assign frame_data_raddr_curr = {ram_rd_addr_curr, ram_rd_offs_curr};
    // assign frame_data_raddr_next = {ram_rd_addr_next, ram_rd_offs_next};


    assign ram_rd_rdy = ram_rd_cstat == RAM_RD_DROP || (rd_data_rsp_rdy || !rd_data_rsp_vld);


    always @(posedge clk) begin
        rd_data_ff_rden <= ram_rd_vld && ram_rd_rdy && (ram_rd_cstat == RAM_RD_SEND_HEAD ? 0 : frame_data_rdata[DATA_WIDTH+EMPTH_WIDTH+:1]);
    end
    // assign idx_que_comp_raddr[1] = ram_rd_info_vq_gid;
    // assign idx_dev_comp_raddr[1] = ram_rd_info_dev_id;
    always @(posedge clk) begin
        idx_que_comp_raddr[1]        <= ram_rd_info_vq_gid;
        idx_dev_comp_raddr[1]        <= ram_rd_info_dev_id;
        idx_que_rdata_comp_c_fsm_inc <= idx_que_comp_rdata[1] + 1;
        idx_dev_rdata_comp_c_fsm_inc <= idx_dev_comp_rdata[1] + 1;
    end

    assign idx_que_comp_wren  = c_fsm_flush || rd_data_ff_rden;
    assign idx_que_comp_wdata = c_fsm_flush ? 0 : idx_que_rdata_comp_c_fsm_inc;
    assign idx_que_comp_waddr = c_fsm_flush ? c_fsm_flush_wr_addr : ram_rd_info_vq_gid;

    assign idx_dev_comp_wren  = c_fsm_flush || rd_data_ff_rden;
    assign idx_dev_comp_wdata = c_fsm_flush ? 0 : idx_dev_rdata_comp_c_fsm_inc;
    assign idx_dev_comp_waddr = c_fsm_flush ? c_fsm_flush_wr_addr : ram_rd_info_dev_id;


    always @(posedge clk) begin
        if (rst) begin
            rd_data_rsp_vld <= 'b0;
        end else if (rd_data_rsp_rdy || !rd_data_rsp_vld) begin
            rd_data_rsp_vld <= (ram_rd_vld && ram_rd_cstat == RAM_RD_SEND) || ram_rd_cstat == RAM_RD_SEND_HEAD;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rd_rsp_pkt_total <= 'b0;
        end else if (rd_data_rsp_vld & rd_data_rsp_rdy & rd_data_rsp_eop) begin
            rd_rsp_pkt_total <= rd_rsp_pkt_total + 1'b1;
        end
    end


    always @(posedge clk) begin
        if (rd_data_rsp_rdy || !rd_data_rsp_vld) begin
            rd_data_rsp_data <= ram_rd_cstat == RAM_RD_SEND_HEAD ? {160'd0, {6'b0, ram_rd_info_proto_csum_pass_r, 1'b0}, 88'b0} : frame_data_rdata[0+:DATA_WIDTH];
            rd_data_rsp_sty  <= ram_rd_cstat == RAM_RD_SEND_HEAD ? (DATA_WIDTH / 8) - 12 : {EMPTH_WIDTH{1'b0}};
            rd_data_rsp_mty  <= ram_rd_cstat == RAM_RD_SEND_HEAD ? 0 : frame_data_rdata[DATA_WIDTH+:EMPTH_WIDTH];
            rd_data_rsp_sop  <= ram_rd_cstat == RAM_RD_SEND_HEAD;
            rd_data_rsp_eop  <= ram_rd_cstat == RAM_RD_SEND_HEAD ? 0 : frame_data_rdata[DATA_WIDTH+EMPTH_WIDTH+:1];
            rd_data_rsp_sbd  <= rd_data_rsp_sbd_inside;
        end
    end


    ////////////////////////////////////////////////////////////////////////////
    // BKT CTRL

    logic [BKT_FF_WIDTH-1:0] bkt_rd_rst_cnt;

    always @(posedge clk) begin
        if (rst) begin
            bkt_rd_cstat <= BKT_RD_RST;
        end else begin
            bkt_rd_cstat <= bkt_rd_nstat;
        end
    end

    always @(*) begin
        bkt_rd_nstat = bkt_rd_cstat;
        case (bkt_rd_cstat)
            BKT_RD_RST: begin
                if (bkt_rd_rst_cnt == BKT_FF_DEPTH - 1) begin
                    bkt_rd_nstat = BKT_RD_RUN;
                end
            end
            BKT_RD_RUN: ;
            default: bkt_rd_nstat = BKT_RD_RST;
        endcase

    end

    always @(posedge clk) begin
        if (rst) begin
            bkt_rd_rst_cnt <= 'b0;
        end else if (bkt_rd_cstat == BKT_RD_RST) begin
            bkt_rd_rst_cnt <= bkt_rd_rst_cnt + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            bkt_ff_wren <= 1'b0;
        end else begin
            bkt_ff_wren <= bkt_rd_cstat == BKT_RD_RST ? 1'b1 : ram_rd_vld && ram_rd_rdy && (ram_rd_offs_curr == 'b11 || (ram_rd_cstat == RAM_RD_SEND_HEAD ? 0 : frame_data_rdata[DATA_WIDTH+EMPTH_WIDTH+:1]));
        end
        bkt_ff_din <= bkt_rd_cstat == BKT_RD_RST ? bkt_rd_rst_cnt : ram_rd_addr_curr;
    end

    // assign 
    // assign 


    assign ram_rd_vld = (ram_rd_cstat == RAM_RD_DROP || ram_rd_cstat == RAM_RD_SEND) && bkt_rd_cstat == BKT_RD_RUN;

    logic                 not_ready_drop_pkt_ram_update_vld;
    logic [QID_WIDTH-1:0] not_ready_drop_pkt_ram_update_addr;
    logic                 not_ready_drop_pkt_ram_rd_req_vld;
    logic                 not_ready_drop_pkt_ram_rd_req_rdy;
    logic [QID_WIDTH-1:0] not_ready_drop_pkt_ram_rd_req_addr;
    logic                 not_ready_drop_pkt_ram_cnt_clr_en;
    logic                 not_ready_drop_pkt_ram_rd_rsp_vld;
    logic [16-1:0]        not_ready_drop_pkt_ram_rd_rsp_data;
    logic                 not_ready_drop_pkt_ram_flush;
    logic [1:0]           not_ready_drop_pkt_ram_err;

    virtio_rx_buf_cnt #(
        .CNT_WIDTH(16),
        .QID_NUM  (QID_NUM)
    ) u_not_ready_drop_pkt_ramm (
        .clk        (clk),
        .rst        (rst),
        .update_vld (not_ready_drop_pkt_ram_update_vld),
        .update_addr(not_ready_drop_pkt_ram_update_addr),
        .rd_req_vld (not_ready_drop_pkt_ram_rd_req_vld),
        .rd_req_rdy (not_ready_drop_pkt_ram_rd_req_rdy),
        .rd_req_addr(not_ready_drop_pkt_ram_rd_req_addr),
        .cnt_clr_en (not_ready_drop_pkt_ram_cnt_clr_en),
        .rd_rsp_vld (not_ready_drop_pkt_ram_rd_rsp_vld),
        .rd_rsp_data(not_ready_drop_pkt_ram_rd_rsp_data),
        .flush      (not_ready_drop_pkt_ram_flush),
        .ram_err    (not_ready_drop_pkt_ram_err)
    );

    always @(posedge clk) begin
        not_ready_drop_pkt_ram_update_vld <= 'b0;
        if (ram_rd_cstat_d == RAM_RD_DROP && ram_rd_cstat == RAM_RD_DELAY2) begin
            not_ready_drop_pkt_ram_update_vld <= 'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            not_ready_drop_pkt_total <= 'b0;
        end else if (ram_rd_cstat_d == RAM_RD_DROP && ram_rd_cstat == RAM_RD_DELAY2) begin
            not_ready_drop_pkt_total <= not_ready_drop_pkt_total + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (ram_rd_cstat_d == RAM_RD_DROP && ram_rd_cstat == RAM_RD_DELAY2) begin
            not_ready_drop_pkt_ram_update_addr <= rd_data_rsp_sbd_inside.vq.qid;
        end
    end


    // logic                 ram_rd_drop_ram_wren;
    // logic [QID_WIDTH-1:0] ram_rd_drop_ram_waddr;
    // logic [15:0]          ram_rd_drop_ram_wdata;

    // logic                 ram_rd_drop_ram_rden;
    // logic                 ram_rd_drop_ram_rden_up;
    // logic [QID_WIDTH-1:0] ram_rd_drop_ram_raddr;
    // logic [QID_WIDTH-1:0] ram_rd_drop_ram_raddr_ctx;
    // logic [15:0]          ram_rd_drop_ram_rdata;

    // logic [1:0]           ram_rd_drop_ram_err;
    // logic [QID_WIDTH-1:0] drop_ram_addr;
    // logic                 ram_rd_drop_flush;
    // logic                 ram_rd_drop_flush_r;
    // sync_simple_dual_port_ram #(
    //     .DATAA_WIDTH(16),
    //     .ADDRA_WIDTH(QID_WIDTH),
    //     .DATAB_WIDTH(16),
    //     .ADDRB_WIDTH(QID_WIDTH),
    //     .RAM_MODE   ("blk"),      // blk dist
    //     .INIT       (0),
    //     .CHECK_ON   (1),
    //     .CHECK_MODE ("parity")
    // ) u_ram_rd_drop_ram (
    //     .clk           (clk),
    //     .rst           (rst),
    //     //
    //     .wea           (ram_rd_drop_ram_wren),
    //     .addra         (ram_rd_drop_ram_waddr),
    //     .dina          (ram_rd_drop_ram_wdata),
    //     //
    //     .addrb         (ram_rd_drop_ram_raddr),
    //     .doutb         (ram_rd_drop_ram_rdata),
    //     //
    //     .parity_ecc_err(ram_rd_drop_ram_err)
    // );

    // always @(posedge clk) begin
    //     ram_rd_drop_flush_r   <= ram_rd_drop_flush;
    //     ram_rd_drop_ram_waddr <= drop_ram_addr;
    //     if (ram_rd_drop_flush) begin
    //         ram_rd_drop_ram_wren <= 1'b1;
    //     end else begin
    //         ram_rd_drop_ram_wren <= ram_rd_drop_ram_rden_up;
    //     end
    // end
    // assign ram_rd_drop_ram_wdata = ram_rd_drop_flush_r ? 16'b0 : ram_rd_drop_ram_rdata + 1;

    // always @(posedge clk) begin
    //     if (rst) begin
    //         ram_rd_drop_flush <= 1'b1;
    //     end else if (ram_rd_drop_flush && drop_ram_addr == QID_NUM - 1) begin
    //         ram_rd_drop_flush <= 1'b0;
    //     end
    // end

    // always @(posedge clk) begin
    //     ram_rd_drop_ram_rden_up <= 1'b0;
    //     if (ram_rd_cstat_d == RAM_RD_DROP && ram_rd_cstat == RAM_RD_DELAY2) begin
    //         ram_rd_drop_ram_rden_up <= 1'b1;
    //     end
    // end

    // assign ram_rd_drop_ram_raddr = ram_rd_drop_ram_rden_up ? drop_ram_addr : ram_rd_drop_ram_raddr_ctx;

    // always @(posedge clk) begin
    //     if (rst) begin
    //         drop_ram_addr <= 1'b0;
    //     end else if (ram_rd_drop_flush) begin
    //         drop_ram_addr <= drop_ram_addr + 1;
    //     end else if (ram_rd_cstat_d == RAM_RD_DROP && ram_rd_cstat == RAM_RD_DELAY2) begin
    //         drop_ram_addr <= rd_data_rsp_sbd_inside.vq.qid;
    //     end
    // end

    ////////////////////////////////////////////////////////////////////////////
    // ram 


    sync_simple_dual_port_ram #(
        .DATAA_WIDTH(FRAME_DATA_WIDTH),
        .ADDRA_WIDTH(FRAME_DATA_DEPTH_WIDTH),
        .DATAB_WIDTH(FRAME_DATA_WIDTH),
        .ADDRB_WIDTH(FRAME_DATA_DEPTH_WIDTH),
        .RAM_MODE   ("blk"),                   // blk dist
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_frame_data_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (frame_data_wdata),
        .addra         (frame_data_waddr),
        .wea           (frame_data_wren),
        //
        .doutb         (frame_data_rdata),
        .addrb         (frame_data_raddr),
        //
        .parity_ecc_err(frame_data_err)
    );
    assign frame_data_raddr = {ram_rd_addr, ram_rd_offs};


    sync_simple_dual_port_ram #(
        .DATAA_WIDTH(LINK_INFO_WIDTH),
        .ADDRA_WIDTH(LINK_INFO_DEPTH_WIDTH),
        .DATAB_WIDTH(LINK_INFO_WIDTH),
        .ADDRB_WIDTH(LINK_INFO_DEPTH_WIDTH),
        .RAM_MODE   ("blk"),                  // blk dist
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_link_info_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (link_info_wdata),
        .addra         (link_info_waddr),
        .wea           (link_info_wren),
        //
        .doutb         (link_info_rdata),
        .addrb         (link_info_raddr),
        //
        .parity_ecc_err(link_info_err)
    );

    assign link_info_raddr = ram_rd_en ? ram_rd_addr : ctx_link_rom_raddr;

    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(PC_FSM_INFO_WIDTH),
        .ADDRA_WIDTH(PC_FSM_INFO_DEPTH_WIDTH),
        .DATAB_WIDTH(PC_FSM_INFO_WIDTH),
        .ADDRB_WIDTH(PC_FSM_INFO_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_pc_fsm_info_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (pc_fsm_info_wdata),
        .addra         (pc_fsm_info_waddr),
        .wea           (pc_fsm_info_wren),
        //
        .doutb         (pc_fsm_info_rdata[0]),
        .addrb         (pc_fsm_info_raddr[0]),
        //
        .parity_ecc_err(pc_fsm_info_err[0])
    );
    assign pc_fsm_info_wren     = pc_info_wren_p_fsm ? pc_info_wren_p_fsm : pc_info_wren_c_fsm;
    assign pc_fsm_info_waddr    = pc_info_wren_p_fsm ? pc_info_waddr_p_fsm : pc_info_waddr_c_fsm;
    assign pc_fsm_info_wdata    = pc_info_wren_p_fsm ? pc_info_wdata_p_fsm : pc_info_wdata_c_fsm;

    assign pc_fsm_info_raddr[0] = pc_info_rden_p_fsm ? pc_info_raddr_p_fsm : pc_info_raddr_c_fsm;

    assert property (@(posedge clk) disable iff (rst) ((pc_info_rden_p_fsm && pc_info_rden_c_fsm) !== 1))
    else $fatal(0, "pc_info_rden err");


    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(PC_FSM_INFO_WIDTH),
        .ADDRA_WIDTH(PC_FSM_INFO_DEPTH_WIDTH),
        .DATAB_WIDTH(PC_FSM_INFO_WIDTH),
        .ADDRB_WIDTH(PC_FSM_INFO_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u1_pc_fsm_info_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (pc_fsm_info_wdata),
        .addra         (pc_fsm_info_waddr),
        .wea           (pc_fsm_info_wren),
        //
        .doutb         (pc_fsm_info_rdata[1]),
        .addrb         (pc_fsm_info_raddr[1]),
        //
        .parity_ecc_err(pc_fsm_info_err[1])
    );

    assign pc_fsm_info_raddr[1] = pc_info_rden_s_fsm ? pc_info_raddr_s_fsm : ctx_pc_fsm_rom_raddr;

    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(S_FSM_INFO_WIDTH),
        .ADDRA_WIDTH(S_FSM_INFO_DEPTH_WIDTH),
        .DATAB_WIDTH(S_FSM_INFO_WIDTH),
        .ADDRB_WIDTH(S_FSM_INFO_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_s_fsm_info_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (s_fsm_info_wdata),
        .addra         (s_fsm_info_waddr),
        .wea           (s_fsm_info_wren),
        //
        .doutb         (s_fsm_info_rdata),
        .addrb         (s_fsm_info_raddr),
        //
        .parity_ecc_err(s_fsm_info_err)
    );
    assign s_fsm_info_wren  = s_info_wren_c_fsm ? s_info_wren_c_fsm : s_info_wren_s_fsm;
    assign s_fsm_info_wdata = s_info_wren_c_fsm ? s_info_wdata_c_fsm : s_info_wdata_s_fsm;
    assign s_fsm_info_waddr = s_info_wren_c_fsm ? s_info_waddr_c_fsm : s_info_waddr_s_fsm;

    assign s_fsm_info_raddr = s_info_rden_s_fsm ? s_info_raddr_s_fsm : s_info_rden_c_fsm ? s_info_raddr_c_fsm : ctx_s_fsm_rom_raddr;

    assert property (@(posedge clk) disable iff (rst) ((s_info_rden_s_fsm && s_info_rden_c_fsm) !== 1))
    else $fatal(0, "s_info_rden err");


    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(NEXT_INFO_WIDTH),
        .ADDRA_WIDTH(NEXT_INFO_DEPTH_WIDTH),
        .DATAB_WIDTH(NEXT_INFO_WIDTH),
        .ADDRB_WIDTH(NEXT_INFO_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_next_info_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (next_info_wdata),
        .addra         (next_info_waddr),
        .wea           (next_info_wren),
        //
        .doutb         (next_info_rdata),
        .addrb         (next_info_raddr),
        //
        .parity_ecc_err(next_info_err)
    );

    assert property (@(posedge clk) disable iff (rst) ((next_info_rden_s_fsm && next_info_rden_c_fsm) !== 1))
    else $fatal(0, "next_info_rd_en err");

    assign next_info_raddr = next_info_rden_s_fsm ? next_info_raddr_s_fsm : next_info_rden_c_fsm ? next_info_raddr_c_fsm : ctx_next_rom_raddr;

    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(IDX_QUE_WIDTH),
        .ADDRA_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .DATAB_WIDTH(IDX_QUE_WIDTH),
        .ADDRB_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_idx_que_proc_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (idx_que_proc_wdata),
        .addra         (idx_que_proc_waddr),
        .wea           (idx_que_proc_wren),
        //
        .doutb         (idx_que_proc_rdata),
        .addrb         (idx_que_proc_raddr),
        //
        .parity_ecc_err(idx_que_proc_err[0])
    );


    logic [IDX_QUE_WIDTH-1:0]       idx_que_proc_rdata_time_drop;
    logic [IDX_QUE_DEPTH_WIDTH-1:0] idx_que_proc_raddr_time_drop;

    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(IDX_QUE_WIDTH),
        .ADDRA_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .DATAB_WIDTH(IDX_QUE_WIDTH),
        .ADDRB_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u1_idx_que_proc_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (idx_que_proc_wdata),
        .addra         (idx_que_proc_waddr),
        .wea           (idx_que_proc_wren),
        //
        .doutb         (idx_que_proc_rdata_time_drop),
        .addrb         (idx_que_proc_raddr_time_drop),
        //
        .parity_ecc_err(idx_que_proc_err[1])
    );
    assign idx_que_proc_raddr_time_drop = idx_per_queue_raddr;


    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(IDX_QUE_WIDTH),
        .ADDRA_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .DATAB_WIDTH(IDX_QUE_WIDTH),
        .ADDRB_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_idx_que_comp_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (idx_que_comp_wdata),
        .addra         (idx_que_comp_waddr),
        .wea           (idx_que_comp_wren),
        //
        .doutb         (idx_que_comp_rdata[0]),
        .addrb         (idx_que_comp_raddr[0]),
        //
        .parity_ecc_err(idx_que_comp_err[0])
    );


    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(IDX_QUE_WIDTH),
        .ADDRA_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .DATAB_WIDTH(IDX_QUE_WIDTH),
        .ADDRB_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u1_idx_que_comp_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (idx_que_comp_wdata),
        .addra         (idx_que_comp_waddr),
        .wea           (idx_que_comp_wren),
        //
        .doutb         (idx_que_comp_rdata[1]),
        .addrb         (idx_que_comp_raddr[1]),
        //
        .parity_ecc_err(idx_que_comp_err[1])
    );

    logic [IDX_QUE_WIDTH-1:0]       idx_que_comp_rdata_time_drop;
    logic [IDX_QUE_DEPTH_WIDTH-1:0] idx_que_comp_raddr_time_drop;

    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(IDX_QUE_WIDTH),
        .ADDRA_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .DATAB_WIDTH(IDX_QUE_WIDTH),
        .ADDRB_WIDTH(IDX_QUE_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u2_idx_que_comp_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (idx_que_comp_wdata),
        .addra         (idx_que_comp_waddr),
        .wea           (idx_que_comp_wren),
        //
        .doutb         (idx_que_comp_rdata_time_drop),
        .addrb         (idx_que_comp_raddr_time_drop),
        //
        .parity_ecc_err(idx_que_comp_err[2])
    );
    assign idx_que_comp_raddr_time_drop = idx_per_queue_raddr;
    assign idx_per_queue_rdata          = {idx_que_proc_rdata_time_drop[7:0], idx_que_comp_rdata_time_drop[7:0]};


    assign idx_per_queue_rd_req_vld     = idx_ctx_que_rd_en_s_fsm ? idx_ctx_que_rd_en_s_fsm : idx_ctx_que_rd_en_c_fsm;
    assign idx_per_queue_rd_req_qid     = idx_ctx_que_rd_en_s_fsm ? idx_ctx_que_raddr_s_fsm : idx_ctx_que_raddr_c_fsm;

    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(IDX_DEV_WIDTH),
        .ADDRA_WIDTH(IDX_DEV_NUM_WIDTH),
        .DATAB_WIDTH(IDX_DEV_WIDTH),
        .ADDRB_WIDTH(IDX_DEV_NUM_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_idx_dev_proc_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (idx_dev_proc_wdata),
        .addra         (idx_dev_proc_waddr),
        .wea           (idx_dev_proc_wren),
        //
        .doutb         (idx_dev_proc_rdata),
        .addrb         (idx_dev_proc_raddr),
        //
        .parity_ecc_err(idx_dev_proc_err)
    );

    // assign idx_dev_proc_wren  = idx_dev_wr_en_s_fsm;
    // assign idx_dev_proc_waddr = idx_dev_waddr_s_fsm;
    // assign idx_dev_proc_wdata = idx_dev_wdata_s_fsm;


    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(IDX_DEV_WIDTH),
        .ADDRA_WIDTH(IDX_DEV_NUM_WIDTH),
        .DATAB_WIDTH(IDX_DEV_WIDTH),
        .ADDRB_WIDTH(IDX_DEV_NUM_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_idx_dev_comp_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (idx_dev_comp_wdata),
        .addra         (idx_dev_comp_waddr),
        .wea           (idx_dev_comp_wren),
        //
        .doutb         (idx_dev_comp_rdata[0]),
        .addrb         (idx_dev_comp_raddr[0]),
        //
        .parity_ecc_err(idx_dev_comp_err[0])
    );

    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(IDX_DEV_WIDTH),
        .ADDRA_WIDTH(IDX_DEV_NUM_WIDTH),
        .DATAB_WIDTH(IDX_DEV_WIDTH),
        .ADDRB_WIDTH(IDX_DEV_NUM_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u1_idx_dev_comp_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (idx_dev_comp_wdata),
        .addra         (idx_dev_comp_waddr),
        .wea           (idx_dev_comp_wren),
        //
        .doutb         (idx_dev_comp_rdata[1]),
        .addrb         (idx_dev_comp_raddr[1]),
        //
        .parity_ecc_err(idx_dev_comp_err[1])
    );



    // assign idx_dev_raddr             = idx_dev_rden_s_fsm ? idx_dev_raddr_s_fsm : idx_dev_rden_c_fsm ? idx_dev_raddr_c_fsm : ctx_dev_rom_raddr;

    assign idx_per_dev_rd_req_vld    = idx_ctx_dev_rd_en_s_fsm;
    assign idx_per_dev_rd_req_dev_id = idx_ctx_dev_raddr_s_fsm;


    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(FRAME_INFO_WIDTH),
        .ADDRA_WIDTH(FRAME_INFO_DEPTH_WIDTH),
        .DATAB_WIDTH(FRAME_INFO_WIDTH),
        .ADDRB_WIDTH(FRAME_INFO_DEPTH_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_frame_info_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (frame_info_wdata),
        .addra         (frame_info_waddr),
        .wea           (frame_info_wren),
        //
        .doutb         (frame_info_rdata),
        .addrb         (frame_info_raddr),
        //
        .parity_ecc_err(frame_info_err)
    );
    assign frame_info_wren  = frame_info_wren_c_fsm ? frame_info_wren_c_fsm : frame_info_wren_s_fsm;
    assign frame_info_waddr = frame_info_wren_c_fsm ? frame_info_waddr_c_fsm : frame_info_waddr_s_fsm;
    assign frame_info_wdata = frame_info_wren_c_fsm ? frame_info_wdata_c_fsm : frame_info_wdata_s_fsm;

    assign frame_info_raddr = frame_info_raddr_c_fsm;

    assert property (@(posedge clk) disable iff (rst) ((frame_info_wren_s_fsm && frame_info_wren_c_fsm) !== 1))
    else $fatal(0, "frame_info_wren err");

    yucca_sync_fifo #(
        .DATA_WIDTH  (BKT_FF_WIDTH),
        .FIFO_DEPTH  (BKT_FF_DEPTH),
        .CHECK_ON    (1),
        .CHECK_MODE  ("parity"),
        .DEPTH_PEMPTY(24),
        .RAM_MODE    ("blk"),
        .FIFO_MODE   ("fwft")
    ) u0_bkt_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (bkt_ff_wren),
        .din           (bkt_ff_din),
        .full          (),
        // .full          (bkt_ff_full),
        .pfull         (),
        // .pfull         (bkt_ff_pfull),
        .overflow      (bkt_ff_overflow),
        .rden          (bkt_ff_rden),
        .dout          (bkt_ff_dout),
        // .empty         (),
        .empty         (bkt_ff_empty),
        .pempty        (bkt_ff_pempty),
        .underflow     (bkt_ff_underflow),
        .usedw         (bkt_ff_usedw),
        .parity_ecc_err(bkt_ff_err)
    );


    yucca_sync_fifo #(
        .DATA_WIDTH  (RD_DATA_FF_WIDTH),
        .FIFO_DEPTH  (RD_DATA_FF_DEPTH),
        .CHECK_ON    (1),
        .CHECK_MODE  ("parity"),
        .DEPTH_PEMPTY(16),
        .RAM_MODE    ("dist"),
        .FIFO_MODE   ("fwft")
    ) u0_rd_data_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (rd_data_ff_wren),
        .din           (rd_data_ff_din),
        .full          (),
        // .full          (rd_data_ff_full),
        // .pfull         (),
        .pfull         (rd_data_ff_pfull),
        .overflow      (rd_data_ff_overflow),
        .rden          (rd_data_ff_rden),
        .dout          (rd_data_ff_dout),
        // .empty         (),
        .empty         (rd_data_ff_empty),
        .pempty        (),
        // .pempty        (rd_data_ff_pempty),
        .underflow     (rd_data_ff_underflow),
        .usedw         (),
        // .usedw         (rd_data_ff_usedw),
        .parity_ecc_err(rd_data_ff_err)
    );
    assign rd_data_ff_din  = {c_fsm_done_dev_id, c_fsm_done_drop, c_fsm_done_pkt_id, c_fsm_done_vq_gid};
    assign rd_data_ff_wren = c_fsm_done_vld && c_fsm_done_rdy;


    ////////////////////////////////////////////////////////////////////////////
    // SEND_TIME FOR DROP
    localparam SEND_TIME_WIDTH = 16;
    localparam SEND_TIME_DEPTH = QID_NUM;
    localparam SEND_TIME_DEPTH_WIDTH = $clog2(SEND_TIME_DEPTH);
    logic [SEND_TIME_WIDTH-1:0]       send_time_wdata;
    logic [SEND_TIME_DEPTH_WIDTH-1:0] send_time_waddr;
    logic                             send_time_wren;
    logic [SEND_TIME_WIDTH-1:0]       send_time_rdata;
    logic [SEND_TIME_DEPTH_WIDTH-1:0] send_time_raddr;
    logic [1:0]                       send_time_err;


    logic [SEND_TIME_WIDTH-1:0]       send_time_wdata_s_fsm;
    logic [SEND_TIME_DEPTH_WIDTH-1:0] send_time_waddr_s_fsm;
    logic                             send_time_wren_s_fsm;

    logic [SEND_TIME_WIDTH-1:0]       send_time_wdata_up;
    logic [SEND_TIME_DEPTH_WIDTH-1:0] send_time_waddr_up;
    logic                             send_time_wren_up;

    logic [SEND_TIME_WIDTH-1:0]       send_time_rdata_up;
    logic [SEND_TIME_DEPTH_WIDTH-1:0] send_time_raddr_up;
    logic                             send_time_rden_up;

    logic                             send_time_rden_up_r;
    logic [SEND_TIME_WIDTH-1:0]       send_time_rdata_up_r;


    // logic [SEND_TIME_WIDTH-1:0]       send_time_rdata_drop;
    // logic [SEND_TIME_DEPTH_WIDTH-1:0] send_time_raddr_drop;
    // logic                             send_time_rden_drop;
    logic [SEND_TIME_WIDTH-1:0]       send_time_rdata_drop_r;
    logic                             send_time_rden_drop_r;

    // lock  rdata_drop
    always @(posedge clk) begin
        send_time_rden_drop_r <= send_time_rden_drop;
        send_time_rden_up_r   <= send_time_rden_up;
    end
    always @(posedge clk) begin
        if (send_time_rden_drop_r) begin
            send_time_rdata_drop_r <= send_time_rdata;
        end
    end
    always @(posedge clk) begin
        if (send_time_rden_up_r) begin
            send_time_rdata_up_r <= send_time_rdata;
        end
    end
    assign send_time_rdata_drop = send_time_rden_drop_r ? send_time_rdata : send_time_rdata_drop_r;
    assign send_time_rdata_up   = send_time_rden_up_r ? send_time_rdata : send_time_rdata_up_r;

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH(SEND_TIME_WIDTH),
        .ADDRA_WIDTH(SEND_TIME_DEPTH_WIDTH),
        .DATAB_WIDTH(SEND_TIME_WIDTH),
        .ADDRB_WIDTH(SEND_TIME_DEPTH_WIDTH),
        .RAM_MODE   ("blk"),                  // blk dist
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u0_send_time_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (send_time_wdata),
        .addra         (send_time_waddr),
        .wea           (send_time_wren),
        //
        .doutb         (send_time_rdata),
        .addrb         (send_time_raddr),
        //
        .parity_ecc_err(send_time_err)
    );

    assign send_time_wren  = send_time_wren_s_fsm ? send_time_wren_s_fsm : send_time_wren_up;
    assign send_time_waddr = send_time_wren_s_fsm ? send_time_waddr_s_fsm : send_time_waddr_up;
    assign send_time_wdata = send_time_wren_s_fsm ? send_time_wdata_s_fsm : send_time_wdata_up;

    assign send_time_raddr = send_time_rden_drop ? send_time_raddr_drop : send_time_rden_up ? send_time_raddr_up : ctx_time_rom_raddr;


    always @(posedge clk) begin
        send_time_wren_s_fsm  <= s_fsm_wr_en;
        send_time_waddr_s_fsm <= s_fsm_vq_gid;
        send_time_wdata_s_fsm <= time_stamp;
    end



    logic [QID_WIDTH:0] time_up_qid;


    enum logic [2:0] {
        TIME_UP_RD   = 3'b001,
        TIME_UP_CALC = 3'b010,
        TIME_UP_WR   = 3'b100
    }
        time_up_cstat, time_up_nstat;


    always @(posedge clk) begin
        if (rst) begin
            time_up_cstat <= TIME_UP_RD;
        end else begin
            time_up_cstat <= time_up_nstat;
        end
    end

    always @(*) begin
        time_up_nstat = time_up_cstat;
        case (time_up_cstat)
            TIME_UP_RD: begin
                if (send_time_rden_up) begin
                    time_up_nstat = TIME_UP_CALC;
                end
            end
            TIME_UP_CALC: begin
                if (send_time_wren && send_time_waddr == send_time_waddr_up) begin
                    time_up_nstat = TIME_UP_RD;
                end else begin
                    time_up_nstat = TIME_UP_WR;
                end
            end
            TIME_UP_WR: begin
                if (send_time_wren && send_time_waddr == send_time_waddr_up) begin
                    time_up_nstat = TIME_UP_RD;
                end
            end
            default: time_up_nstat = TIME_UP_RD;
        endcase

    end

    assign send_time_rden_up  = time_up_cstat == TIME_UP_RD && ~send_time_rden_drop && time_up_qid != QID_NUM;
    assign send_time_raddr_up = time_up_qid[QID_WIDTH-1:0];

    assign send_time_wren_up  = time_up_cstat == TIME_UP_WR;
    assign send_time_waddr_up = time_up_qid[QID_WIDTH-1:0];
    // assign send_time_wdata_up = time_stamp - send_time_rdata_up > 16'h8000 ? {~time_stamp[15], time_stamp[14:0]} : send_time_rdata_up;
    logic [SEND_TIME_WIDTH-1:0] send_time_diff;
    assign send_time_diff = (time_stamp - send_time_rdata_up);
    always @(posedge clk) begin
        send_time_wdata_up <= send_time_diff[15] != 0 ? {~time_stamp[15], time_stamp[14:0]} : send_time_rdata_up;
    end

    always @(posedge clk) begin
        if (rst) begin
            time_up_qid <= 'b0;
        end else if (time_up_qid == QID_NUM && time_stamp_up) begin
            time_up_qid <= 'b0;
        end else if (time_up_nstat == TIME_UP_RD && time_up_cstat != TIME_UP_RD) begin
            if (time_up_qid != QID_NUM) begin
                time_up_qid <= time_up_qid + 1;
            end
        end
    end


    ////////////////////////////////////////////////////////////////////////////
    // mlite_if
    enum logic [4:0] {
        IDLE     = 5'b00001,
        WRITE    = 5'b00010,
        READ     = 5'b00100,
        READ_RAM = 5'b01000,
        READ_RSP = 5'b10000
    }
        rom_cstat, rom_nstat;

    logic [REG_ADDR_WIDTH-1:0] ctx_if_raddr;
    logic [REG_DATA_WIDTH-1:0] ctx_if_rdata;

    // logic [9:0]                   ctx_rom_addr;
    // logic [REG_ADDR_WIDTH-1-16:0] ctx_rom_addr_dead;
    logic [5:0]                ctx_rom_sel;

    logic                      ctx_que_rom_rd_en;
    logic                      ctx_dev_rom_rd_en;
    logic                      ctx_pc_fsm_rom_rd_en;
    logic                      ctx_s_fsm_rom_rd_en;
    logic                      ctx_next_rom_rd_en;
    logic                      ctx_link_rom_rd_en;
    logic                      ctx_time_rom_rd_en;

    logic                      recv_pkt_num_ram_rd_en;
    logic                      csum_drop_pkt_ram_rd_en;
    logic                      qos_drop_pkt_ram_rd_en;
    logic                      buf_full_drop_pkt_ram_rd_en;
    logic                      not_ready_drop_pkt_ram_rd_en;

    logic                      ram_rd_ok;
    assign ram_rd_ok                          = (csum_drop_pkt_ram_rd_req_vld && csum_drop_pkt_ram_rd_req_rdy) || (qos_drop_pkt_ram_rd_req_vld && qos_drop_pkt_ram_rd_req_rdy) || (buf_full_drop_pkt_ram_rd_req_vld && buf_full_drop_pkt_ram_rd_req_rdy) || (not_ready_drop_pkt_ram_rd_req_vld && not_ready_drop_pkt_ram_rd_req_rdy);

    // assign ctx_rom_addr         = ctx_if_raddr[9:0];
    // assign ctx_rom_addr_dead    = ctx_if_raddr[REG_ADDR_WIDTH-1:16];
    // always @(posedge clk) begin
    //     if (rom_cstat == IDLE) begin
    //         ctx_rom_sel <= ctx_if.addr[16:11];
    //     end
    // end
    assign ctx_rom_sel                        = ctx_if_raddr[16:11];

    assign ctx_que_rom_rd_en                  = ctx_rom_sel[5:2] == 4'b1000 && !idx_que_rden;
    assign ctx_dev_rom_rd_en                  = ctx_rom_sel[5:2] == 4'b1001 && !idx_dev_rden;
    assign ctx_pc_fsm_rom_rd_en               = ctx_rom_sel[5:2] == 4'b1010 && !pc_info_rden_s_fsm;
    assign ctx_s_fsm_rom_rd_en                = ctx_rom_sel[5:2] == 4'b1011 && !s_info_rden_s_fsm && !s_info_rden_c_fsm;
    assign ctx_next_rom_rd_en                 = ctx_rom_sel[5:2] == 4'b1100 && !next_info_rden_s_fsm && !next_info_rden_c_fsm;
    assign ctx_link_rom_rd_en                 = ctx_rom_sel[5:2] == 4'b1101 && !ram_rd_en;
    assign ctx_time_rom_rd_en                 = ctx_rom_sel[5:2] == 4'b1110 && !send_time_rden_drop && !send_time_rden_up;

    assign recv_pkt_num_ram_rd_en             = ctx_rom_sel[5:2] == 4'b0100;
    assign csum_drop_pkt_ram_rd_en            = ctx_rom_sel[5:2] == 4'b1111 && ctx_rom_sel[1:0] == 2'b00;
    assign qos_drop_pkt_ram_rd_en             = ctx_rom_sel[5:2] == 4'b1111 && ctx_rom_sel[1:0] == 2'b01;
    assign buf_full_drop_pkt_ram_rd_en        = ctx_rom_sel[5:2] == 4'b1111 && ctx_rom_sel[1:0] == 2'b10;
    assign not_ready_drop_pkt_ram_rd_en       = ctx_rom_sel[5:2] == 4'b1111 && ctx_rom_sel[1:0] == 2'b11;




    assign ctx_que_rom_raddr                  = ctx_if_raddr[10:3];
    assign ctx_dev_rom_raddr                  = ctx_if_raddr[12:3];
    assign ctx_pc_fsm_rom_raddr               = ctx_if_raddr[10:3];
    assign ctx_s_fsm_rom_raddr                = ctx_if_raddr[10:3];
    assign ctx_next_rom_raddr                 = ctx_if_raddr[10:3];
    assign ctx_link_rom_raddr                 = ctx_if_raddr[12:3];
    assign ctx_time_rom_raddr                 = ctx_if_raddr[10:3];

    // assign csum_drop_ram_raddr_ctx           = ctx_if_raddr[10:3];
    // assign qos_drop_ram_raddr_ctx            = ctx_if_raddr[10:3];
    // assign pfull_drop_ram_raddr_ctx          = ctx_if_raddr[10:3];

    assign recv_pkt_num_ram_rd_req_addr       = ctx_if_raddr[10:3];
    assign csum_drop_pkt_ram_rd_req_addr      = ctx_if_raddr[10:3];
    assign qos_drop_pkt_ram_rd_req_addr       = ctx_if_raddr[10:3];
    assign buf_full_drop_pkt_ram_rd_req_addr  = ctx_if_raddr[10:3];
    assign not_ready_drop_pkt_ram_rd_req_addr = ctx_if_raddr[10:3];



    assign recv_pkt_num_ram_rd_req_vld        = recv_pkt_num_ram_rd_en && (rom_cstat == READ || rom_cstat == WRITE);
    assign csum_drop_pkt_ram_rd_req_vld       = csum_drop_pkt_ram_rd_en && (rom_cstat == READ || rom_cstat == WRITE);
    assign qos_drop_pkt_ram_rd_req_vld        = qos_drop_pkt_ram_rd_en && (rom_cstat == READ || rom_cstat == WRITE);
    assign buf_full_drop_pkt_ram_rd_req_vld   = buf_full_drop_pkt_ram_rd_en && (rom_cstat == READ || rom_cstat == WRITE);
    assign not_ready_drop_pkt_ram_rd_req_vld  = not_ready_drop_pkt_ram_rd_en && (rom_cstat == READ || rom_cstat == WRITE);

    assign recv_pkt_num_ram_cnt_clr_en        = rom_cstat == WRITE;
    assign csum_drop_pkt_ram_cnt_clr_en       = rom_cstat == WRITE;
    assign qos_drop_pkt_ram_cnt_clr_en        = rom_cstat == WRITE;
    assign buf_full_drop_pkt_ram_cnt_clr_en   = rom_cstat == WRITE;
    assign not_ready_drop_pkt_ram_cnt_clr_en  = rom_cstat == WRITE;

    // assign 
    always @(posedge clk) begin
        if (rom_cstat == READ_RAM) begin
            case (ctx_rom_sel)
                6'b010000: ctx_if_rdata <= {48'b0, recv_pkt_num_ram_rd_rsp_data};
                6'b100000: ctx_if_rdata <= {32'b0, idx_que_proc_rdata, idx_que_comp_rdata[0]};
                6'b100100, 6'b00101, 6'b00110, 6'b00111: ctx_if_rdata <= {32'b0, idx_dev_proc_rdata, idx_dev_comp_rdata[0]};
                6'b101000: ctx_if_rdata <= {43'b0, pc_fsm_info_rdata[1]};
                6'b101100: ctx_if_rdata <= {53'b0, s_fsm_info_rdata};
                6'b110000: ctx_if_rdata <= {54'b0, next_info_rdata};
                6'b110100, 6'b10101, 6'b10110, 6'b10111: ctx_if_rdata <= {35'b0, link_info_rdata};
                6'b111000: ctx_if_rdata <= {48'b0, send_time_rdata};
                6'b111100: ctx_if_rdata <= {48'b0, csum_drop_pkt_ram_rd_rsp_data};
                6'b111101: ctx_if_rdata <= {48'b0, qos_drop_pkt_ram_rd_rsp_data};
                6'b111110: ctx_if_rdata <= {48'b0, buf_full_drop_pkt_ram_rd_rsp_data};
                6'b111111: ctx_if_rdata <= {48'b0, not_ready_drop_pkt_ram_rd_rsp_data};
                default: ctx_if_rdata <= 64'hdeadbeefdeadc0de;
            endcase
        end
    end


    always @(posedge clk) begin
        if (rst) begin
            rom_cstat <= IDLE;
        end else begin
            rom_cstat <= rom_nstat;
        end
    end

    always @(*) begin
        rom_nstat = rom_cstat;
        case (rom_cstat)
            IDLE: begin
                if (ctx_if.ready && ctx_if.valid) begin
                    if (!ctx_if.read) begin
                        rom_nstat = WRITE;
                    end else begin
                        rom_nstat = READ;
                    end
                end
            end
            WRITE: begin
                case (ctx_rom_sel[5:2])
                    4'b0100: rom_nstat = recv_pkt_num_ram_rd_req_vld && recv_pkt_num_ram_rd_req_rdy ? IDLE : rom_cstat;
                    4'b1000: rom_nstat = ctx_que_rom_rd_en ? IDLE : rom_cstat;
                    4'b1001: rom_nstat = ctx_dev_rom_rd_en ? IDLE : rom_cstat;
                    4'b1010: rom_nstat = ctx_pc_fsm_rom_rd_en ? IDLE : rom_cstat;
                    4'b1011: rom_nstat = ctx_s_fsm_rom_rd_en ? IDLE : rom_cstat;
                    4'b1100: rom_nstat = ctx_next_rom_rd_en ? IDLE : rom_cstat;
                    4'b1101: rom_nstat = ctx_link_rom_rd_en ? IDLE : rom_cstat;
                    4'b1110: rom_nstat = ctx_time_rom_rd_en ? IDLE : rom_cstat;
                    4'b1111: rom_nstat = ram_rd_ok ? IDLE : rom_cstat;
                    default: rom_nstat = IDLE;
                endcase
            end
            READ: begin
                case (ctx_rom_sel[5:2])
                    4'b0100: rom_nstat = recv_pkt_num_ram_rd_req_vld && recv_pkt_num_ram_rd_req_rdy ? READ_RAM : rom_cstat;
                    4'b1000: rom_nstat = ctx_que_rom_rd_en ? READ_RAM : rom_cstat;
                    4'b1001: rom_nstat = ctx_dev_rom_rd_en ? READ_RAM : rom_cstat;
                    4'b1010: rom_nstat = ctx_pc_fsm_rom_rd_en ? READ_RAM : rom_cstat;
                    4'b1011: rom_nstat = ctx_s_fsm_rom_rd_en ? READ_RAM : rom_cstat;
                    4'b1100: rom_nstat = ctx_next_rom_rd_en ? READ_RAM : rom_cstat;
                    4'b1101: rom_nstat = ctx_link_rom_rd_en ? READ_RAM : rom_cstat;
                    4'b1110: rom_nstat = ctx_time_rom_rd_en ? READ_RAM : rom_cstat;
                    4'b1111: rom_nstat = ram_rd_ok ? READ_RAM : rom_cstat;
                    default: rom_nstat = READ_RAM;
                endcase
            end
            READ_RAM: begin
                rom_nstat = READ_RSP;
            end
            READ_RSP: begin
                if (ctx_if.rready) begin
                    rom_nstat = IDLE;
                end
            end
            default: begin
                rom_nstat = IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rom_cstat == IDLE) begin
            ctx_if_raddr <= ctx_if.addr;
        end
    end

    assign ctx_if.rdata  = ctx_if_rdata;
    assign ctx_if.ready  = rom_cstat == IDLE;
    assign ctx_if.rvalid = rom_cstat == READ_RSP;

    // always @(posedge clk) begin
    //     if (rst)begin
    //         C_FSM_FLUSH <= 1'b1;
    //     end else if () begin

    //     end
    // end

    ////////////////////////////////////////////////////////////////////////////
    // link_dfx
    always @(posedge clk) begin
        link_stat.drop_data_ff_rdy    <= drop_data_ff_rden;
        link_stat.drop_data_ff_vld    <= !drop_data_ff_empty;
        link_stat.info_out_rdy        <= info_out_rdy;
        link_stat.info_out_vld        <= info_out_vld;
        link_stat.rd_data_req_vld     <= rd_data_req_vld;
        link_stat.rd_data_req_rdy     <= rd_data_req_rdy;
        link_stat.rd_data_rsp_vld     <= rd_data_rsp_vld;
        link_stat.rd_data_rsp_rdy     <= rd_data_rsp_rdy;
        link_stat.sch_status          <= sch_status;
        link_stat.rom_cstat           <= rom_cstat;
        link_stat.time_up_cstat       <= time_up_cstat;
        link_stat.ram_rd_cstat        <= ram_rd_cstat;
        link_stat.bkt_rd_cstat        <= bkt_rd_cstat;
        link_stat.c_fsm_cstat         <= c_fsm_cstat;
        link_stat.s_fsm_cstat         <= s_fsm_cstat;
        link_stat.p_fsm_cstat         <= p_fsm_cstat;
        link_stat.ram_wr_cstat        <= ram_wr_cstat;

        link_err.sch_err              <= sch_err;
        link_err.frame_data_err       <= frame_data_err;
        link_err.link_info_err        <= link_info_err;
        link_err.pc_fsm_info_err_0    <= pc_fsm_info_err[0];
        link_err.pc_fsm_info_err_1    <= pc_fsm_info_err[1];
        link_err.s_fsm_info_err       <= s_fsm_info_err;
        link_err.next_info_err        <= next_info_err;
        // link_err.idx_que_err_0        <= idx_que_err[0];
        // link_err.idx_que_err_1        <= idx_que_err[1];
        // link_err.idx_dev_err          <= idx_dev_err;
        link_err.frame_info_err       <= frame_info_err;
        link_err.bkt_ff_overflow      <= bkt_ff_overflow;
        link_err.bkt_ff_underflow     <= bkt_ff_underflow;
        link_err.bkt_ff_err           <= bkt_ff_err;
        link_err.rd_data_ff_overflow  <= rd_data_ff_overflow;
        link_err.rd_data_ff_underflow <= rd_data_ff_underflow;
        link_err.rd_data_ff_err       <= rd_data_ff_err;
        link_err.send_time_err        <= send_time_err;
    end


endmodule : virtio_rx_buf_linklist
