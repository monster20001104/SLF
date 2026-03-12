/******************************************************************************
 *              : virtio_desc_req_ctrl.sv
 *              : Feilong Yun
 *              : 2025/06/23
 *              : 
 *
 *              : 
 *
 *                                                     
 * v1.0  06/23     Feilong Yun                  
******************************************************************************/
 `include "virtio_avail_ring_define.svh"
module virtio_desc_req_ctrl #(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM),
    parameter NETTX_PERQ_RING_ID_NUM = 32,
    parameter NETRX_PERQ_RING_ID_NUM = 32,
    parameter BLK_PERQ_RING_ID_NUM = 8,
    parameter NETTX_PERQ_RING_ID_WIDTH = $clog2(NETTX_PERQ_RING_ID_NUM),
    parameter NETRX_PERQ_RING_ID_WIDTH = $clog2(NETRX_PERQ_RING_ID_NUM),
    parameter BLK_PERQ_RING_ID_WIDTH = $clog2(BLK_PERQ_RING_ID_NUM)

 )
 (

    input                        clk,
    input                        rst,

    input                        netrx_avail_id_req_vld,
    input   [VIRTIO_Q_WIDTH-1:0] netrx_avail_id_req_data,
    input    [3:0]               netrx_avail_id_req_nid,
    output  logic                netrx_avail_id_req_rdy,

    output logic                 netrx_avail_id_rsp_vld,
    output virtio_avail_id_rsp_dat_t netrx_avail_id_rsp_data,
    output   logic               netrx_avail_id_rsp_eop,
    input                        netrx_avail_id_rsp_rdy,

    output   logic               rd_ring_id_netrx_req_vld,
    output   logic[VIRTIO_Q_WIDTH + NETRX_PERQ_RING_ID_WIDTH - 1:0]rd_ring_id_netrx_req_addr,
    input                        rd_ring_id_netrx_rsp_vld,
    input    [17:0]              rd_ring_id_netrx_rsp_data,

    input                        nettx_avail_id_req_vld,
    input    [VIRTIO_Q_WIDTH-1:0]nettx_avail_id_req_data,
    input    [3:0]               nettx_avail_id_req_nid,
    output    logic              nettx_avail_id_req_rdy,

    output   logic               nettx_avail_id_rsp_vld,
    output   logic               nettx_avail_id_rsp_eop,
    output virtio_avail_id_rsp_dat_t nettx_avail_id_rsp_data,
    input                        nettx_avail_id_rsp_rdy,

    output   logic               rd_ring_id_nettx_req_vld,
    output   logic[VIRTIO_Q_WIDTH + NETTX_PERQ_RING_ID_WIDTH - 1:0]rd_ring_id_nettx_req_addr,
    input                        rd_ring_id_nettx_rsp_vld,
    input    [17:0]              rd_ring_id_nettx_rsp_data,

    input                        blk_avail_id_req_vld,
    input    [VIRTIO_Q_WIDTH-1:0]blk_avail_id_req_data,
    input    [3:0]               blk_avail_id_req_nid,
    output   logic               blk_avail_id_req_rdy,

    output   logic               blk_avail_id_rsp_vld,
    output virtio_avail_id_rsp_dat_t blk_avail_id_rsp_data,
    output   logic               blk_avail_id_rsp_eop,
    input                        blk_avail_id_rsp_rdy,

    output   logic               rd_ring_id_blk_req_vld,
    output   logic[VIRTIO_Q_WIDTH + BLK_PERQ_RING_ID_WIDTH - 1:0]rd_ring_id_blk_req_addr,
    input                        rd_ring_id_blk_rsp_vld,
    input    [17:0]              rd_ring_id_blk_rsp_data,

    output    logic              avail_ci_wr_req_vld,
    output    logic[15:0]        avail_ci_wr_req_data,
    output    virtio_vq_t        avail_ci_wr_req_qid,

    output   logic               desc_engine_ctx_info_rd_req_vld,
    output   virtio_vq_t         desc_engine_ctx_info_rd_req_qid,

    input                        desc_engine_ctx_info_rd_rsp_vld,
    input                        desc_engine_ctx_info_rd_rsp_force_shutdown,
    input     [$bits(virtio_qstat_t)-1:0]desc_engine_ctx_info_rd_rsp_ctrl,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_pi,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_idx,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_ui,
    input     [15:0]             desc_engine_ctx_info_rd_rsp_avail_ci,

    input                        vq_pending_chk_req_vld,
    input    virtio_vq_t         vq_pending_chk_req_vq,
    output   logic               vq_pending_chk_rsp_vld,
    output   logic               vq_pending_chk_rsp_busy,


    output   logic [63:0]        dfx_err,
    output   logic [63:0]        dfx_status

 );


    enum logic [7:0]  { 
        REQ_IDLE    = 8'b0000_0001,
        RD_CTX      = 8'b0000_0010,
        RD_ID_RAM   = 8'b0000_0100,
        RSP_ID      = 8'b0000_1000,
        UPDATA_CI   = 8'b0001_0000,
        FINISH      = 8'b0010_0000,
        FINISH_1D   = 8'b0100_0000
    } nettx_cstate, nettx_nstate,nettx_cstate_1d,
    netrx_cstate, netrx_nstate,netrx_cstate_1d,
    blk_cstate, blk_nstate,blk_cstate_1d;

    logic        mark_clk;

    logic        nettx_desc_engine_ctx_info_rd_rsp_force_shutdown_1d;
    logic [$bits(virtio_qstat_t)-1:0]   nettx_desc_engine_ctx_info_rd_rsp_ctrl_1d,nettx_desc_engine_ctx_info_rd_rsp_ctrl_reg;
    logic [15:0] nettx_desc_engine_ctx_info_rd_rsp_avail_pi_1d;
    logic [15:0] nettx_desc_engine_ctx_info_rd_rsp_avail_idx_1d;
    logic [15:0] nettx_desc_engine_ctx_info_rd_rsp_avail_ui_1d;
    logic [15:0] nettx_desc_engine_ctx_info_rd_rsp_avail_ci_1d;


    logic        netrx_desc_engine_ctx_info_rd_rsp_force_shutdown_1d;
    logic [$bits(virtio_qstat_t)-1:0]   netrx_desc_engine_ctx_info_rd_rsp_ctrl_1d,netrx_desc_engine_ctx_info_rd_rsp_ctrl_reg;
    logic [15:0] netrx_desc_engine_ctx_info_rd_rsp_avail_pi_1d;
    logic [15:0] netrx_desc_engine_ctx_info_rd_rsp_avail_idx_1d;
    logic [15:0] netrx_desc_engine_ctx_info_rd_rsp_avail_ui_1d;
    logic [15:0] netrx_desc_engine_ctx_info_rd_rsp_avail_ci_1d;


    logic        blk_desc_engine_ctx_info_rd_rsp_force_shutdown_1d;
    logic [$bits(virtio_qstat_t)-1:0]   blk_desc_engine_ctx_info_rd_rsp_ctrl_1d,blk_desc_engine_ctx_info_rd_rsp_ctrl_reg;
    logic [15:0] blk_desc_engine_ctx_info_rd_rsp_avail_pi_1d;
    logic [15:0] blk_desc_engine_ctx_info_rd_rsp_avail_idx_1d;
    logic [15:0] blk_desc_engine_ctx_info_rd_rsp_avail_ui_1d;
    logic [15:0] blk_desc_engine_ctx_info_rd_rsp_avail_ci_1d;

    logic [VIRTIO_Q_WIDTH-1:0] nettx_avail_id_req_data_1d,netrx_avail_id_req_data_1d,blk_avail_id_req_data_1d;
    logic [VIRTIO_Q_WIDTH-1:0] nettx_avail_id_req_data_reg,netrx_avail_id_req_data_reg,blk_avail_id_req_data_reg;

    logic [17:0] rd_ring_id_nettx_rsp_data_1d,rd_ring_id_netrx_rsp_data_1d,rd_ring_id_blk_rsp_data_1d;
    logic [17:0] rd_ring_id_nettx_rsp_data_reg,rd_ring_id_netrx_rsp_data_reg,rd_ring_id_blk_rsp_data_reg;

    logic [3:0]  nettx_avail_id_req_nid_1d,netrx_avail_id_req_nid_1d,blk_avail_id_req_nid_1d;
    logic [5:0]  local_id_num;
    logic [5:0]  rd_id_num_nettx,cnt_id_num_nettx,cnt_id_num_nettx_1d;
    logic [5:0]  rd_id_num_netrx,cnt_id_num_netrx,cnt_id_num_netrx_1d;
    logic [5:0]  rd_id_num_blk,cnt_id_num_blk,cnt_id_num_blk_1d;

    virtio_vq_t  nettx_busy_qid,netrx_busy_qid,blk_busy_qid;

    always @(posedge clk)begin
        if(rst)begin
            nettx_avail_id_req_data_1d <= 0;
        end
        else if(nettx_avail_id_req_vld && nettx_avail_id_req_rdy)begin
            nettx_avail_id_req_data_1d <= nettx_avail_id_req_data;
        end
    end

    assign nettx_avail_id_req_data_reg = (nettx_avail_id_req_vld && nettx_avail_id_req_rdy) ? nettx_avail_id_req_data : nettx_avail_id_req_data_1d;

    always @(posedge clk)begin
        if(rst)begin
            netrx_avail_id_req_data_1d <= 0;
        end
        else if(netrx_avail_id_req_vld && netrx_avail_id_req_rdy)begin
            netrx_avail_id_req_data_1d <= netrx_avail_id_req_data;
        end
    end

    assign netrx_avail_id_req_data_reg = (netrx_avail_id_req_vld && netrx_avail_id_req_rdy) ? netrx_avail_id_req_data : netrx_avail_id_req_data_1d;

    always @(posedge clk)begin
        if(rst)begin
            blk_avail_id_req_data_1d <= 0;
        end
        else if(blk_avail_id_req_vld && blk_avail_id_req_rdy)begin
            blk_avail_id_req_data_1d <= blk_avail_id_req_data;
        end
    end

    assign blk_avail_id_req_data_reg = (blk_avail_id_req_vld && blk_avail_id_req_rdy) ? blk_avail_id_req_data : blk_avail_id_req_data_1d;

    always @(posedge clk)begin
        if(rst)begin
            mark_clk <= 0;
        end
        else begin
            mark_clk <= ~mark_clk;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            nettx_cstate <= REQ_IDLE;
        end
        else begin
            nettx_cstate <= nettx_nstate;
        end
    end

    always @(*)begin
        nettx_nstate = nettx_cstate;
        case(nettx_cstate)
        REQ_IDLE:
            begin
                if(nettx_avail_id_req_vld && mark_clk == 0)
                    nettx_nstate = RD_CTX;
            end
        RD_CTX:
            begin
                nettx_nstate = RD_ID_RAM;
            end
        RD_ID_RAM:
            begin
                nettx_nstate = RSP_ID;
            end
        RSP_ID:
            begin
                if(nettx_avail_id_rsp_rdy && nettx_avail_id_rsp_vld && (cnt_id_num_nettx  ==  rd_id_num_nettx))
                    nettx_nstate = UPDATA_CI;
            end
        UPDATA_CI:
            begin
                if(mark_clk == 0)
                    nettx_nstate = FINISH;
            end
        FINISH:
            begin
                nettx_nstate = FINISH_1D;
            end
        FINISH_1D:
            begin
                nettx_nstate = REQ_IDLE;
            end
        default: nettx_nstate = nettx_cstate;
        endcase
    end


    always @(posedge clk)begin
        if(rst)begin
            netrx_cstate <= REQ_IDLE;
        end
        else begin
            netrx_cstate <= netrx_nstate;
        end
    end

    always @(*)begin
        netrx_nstate = netrx_cstate;
        case(netrx_cstate)
        REQ_IDLE:
            begin
                if(netrx_avail_id_req_vld && mark_clk == 1)
                    netrx_nstate = RD_CTX;
            end
        RD_CTX:
            begin
                netrx_nstate = RD_ID_RAM;
            end
        RD_ID_RAM:
            begin
                netrx_nstate = RSP_ID;
            end
        RSP_ID:
            begin
                if(netrx_avail_id_rsp_rdy && netrx_avail_id_rsp_vld && (cnt_id_num_netrx  ==  rd_id_num_netrx))
                    netrx_nstate = UPDATA_CI;
            end
        UPDATA_CI:
            begin
                if(mark_clk == 1)
                    netrx_nstate = FINISH;
            end
        FINISH:
            begin
                netrx_nstate = FINISH_1D;
            end
        FINISH_1D:
            begin
                netrx_nstate = REQ_IDLE;
            end
        default: netrx_nstate = netrx_cstate;
        endcase
    end


    always @(posedge clk)begin
        if(rst) begin
            blk_cstate <= REQ_IDLE;
        end
        else begin
            blk_cstate <= blk_nstate;
        end
    end

    always @(*)begin
        blk_nstate = blk_cstate;
        case(blk_cstate)
        REQ_IDLE:
            begin
                if(blk_avail_id_req_vld == 1 && (nettx_avail_id_req_vld == 0 || nettx_cstate != REQ_IDLE) && (netrx_avail_id_req_vld == 0 || netrx_cstate != REQ_IDLE))
                    blk_nstate = RD_CTX;
            end
        RD_CTX:
            begin
                blk_nstate = RD_ID_RAM;
            end
        RD_ID_RAM:
            begin
                blk_nstate = RSP_ID;
            end
        RSP_ID:
            begin
                if(blk_avail_id_rsp_rdy && blk_avail_id_rsp_vld && (cnt_id_num_blk  ==  rd_id_num_blk))
                    blk_nstate = UPDATA_CI;
            end
        UPDATA_CI:
            begin
                if(netrx_cstate != UPDATA_CI  && nettx_cstate != UPDATA_CI)
                    blk_nstate = FINISH;
            end
        FINISH:
            begin
                blk_nstate = FINISH_1D;
            end
        FINISH_1D:
            begin
                blk_nstate = REQ_IDLE;
            end
        default: blk_nstate = blk_cstate;
        endcase
    end

    always @(posedge clk)begin
        if(nettx_cstate == RD_CTX)begin
            nettx_desc_engine_ctx_info_rd_rsp_force_shutdown_1d <= desc_engine_ctx_info_rd_rsp_force_shutdown;
            nettx_desc_engine_ctx_info_rd_rsp_ctrl_1d <= desc_engine_ctx_info_rd_rsp_ctrl;
            nettx_desc_engine_ctx_info_rd_rsp_avail_pi_1d <= desc_engine_ctx_info_rd_rsp_avail_pi;
            nettx_desc_engine_ctx_info_rd_rsp_avail_idx_1d <= desc_engine_ctx_info_rd_rsp_avail_idx;
            nettx_desc_engine_ctx_info_rd_rsp_avail_ui_1d <= desc_engine_ctx_info_rd_rsp_avail_ui;
            nettx_desc_engine_ctx_info_rd_rsp_avail_ci_1d <= desc_engine_ctx_info_rd_rsp_avail_ci;
        end
    end

    always @(posedge clk)begin
        if(netrx_cstate == RD_CTX)begin
            netrx_desc_engine_ctx_info_rd_rsp_force_shutdown_1d <= desc_engine_ctx_info_rd_rsp_force_shutdown;
            netrx_desc_engine_ctx_info_rd_rsp_ctrl_1d <= desc_engine_ctx_info_rd_rsp_ctrl;
            netrx_desc_engine_ctx_info_rd_rsp_avail_pi_1d <= desc_engine_ctx_info_rd_rsp_avail_pi;
            netrx_desc_engine_ctx_info_rd_rsp_avail_idx_1d <= desc_engine_ctx_info_rd_rsp_avail_idx;
            netrx_desc_engine_ctx_info_rd_rsp_avail_ui_1d <= desc_engine_ctx_info_rd_rsp_avail_ui;
            netrx_desc_engine_ctx_info_rd_rsp_avail_ci_1d <= desc_engine_ctx_info_rd_rsp_avail_ci;
        end
    end

    always @(posedge clk)begin
        if(blk_cstate == RD_CTX)begin
            blk_desc_engine_ctx_info_rd_rsp_force_shutdown_1d <= desc_engine_ctx_info_rd_rsp_force_shutdown;
            blk_desc_engine_ctx_info_rd_rsp_ctrl_1d <= desc_engine_ctx_info_rd_rsp_ctrl;
            blk_desc_engine_ctx_info_rd_rsp_avail_pi_1d <= desc_engine_ctx_info_rd_rsp_avail_pi;
            blk_desc_engine_ctx_info_rd_rsp_avail_idx_1d <= desc_engine_ctx_info_rd_rsp_avail_idx;
            blk_desc_engine_ctx_info_rd_rsp_avail_ui_1d <= desc_engine_ctx_info_rd_rsp_avail_ui;
            blk_desc_engine_ctx_info_rd_rsp_avail_ci_1d <= desc_engine_ctx_info_rd_rsp_avail_ci;
        end
    end

    always @(posedge clk)begin
        if(rd_ring_id_blk_rsp_vld)begin
            rd_ring_id_blk_rsp_data_1d <= rd_ring_id_blk_rsp_data;
        end
    end

    assign rd_ring_id_blk_rsp_data_reg = rd_ring_id_blk_rsp_vld ? rd_ring_id_blk_rsp_data : rd_ring_id_blk_rsp_data_1d;

    always @(posedge clk)begin
        if(rd_ring_id_nettx_rsp_vld)begin
            rd_ring_id_nettx_rsp_data_1d <= rd_ring_id_nettx_rsp_data;
        end
    end

    assign rd_ring_id_nettx_rsp_data_reg = rd_ring_id_nettx_rsp_vld ? rd_ring_id_nettx_rsp_data : rd_ring_id_nettx_rsp_data_1d;

    always @(posedge clk)begin
        if(rd_ring_id_netrx_rsp_vld)begin
            rd_ring_id_netrx_rsp_data_1d <= rd_ring_id_netrx_rsp_data;
        end
    end

    assign rd_ring_id_netrx_rsp_data_reg = rd_ring_id_netrx_rsp_vld ? rd_ring_id_netrx_rsp_data : rd_ring_id_netrx_rsp_data_1d;
    

    assign nettx_avail_id_req_rdy = nettx_cstate == RD_ID_RAM;
    assign netrx_avail_id_req_rdy = netrx_cstate == RD_ID_RAM;
    assign blk_avail_id_req_rdy = blk_cstate == RD_ID_RAM;

    assign desc_engine_ctx_info_rd_req_vld = (nettx_cstate == REQ_IDLE && nettx_nstate == RD_CTX) 
                                           ||(netrx_cstate == REQ_IDLE && netrx_nstate == RD_CTX)
                                           ||(blk_cstate == REQ_IDLE && blk_nstate == RD_CTX);

    assign desc_engine_ctx_info_rd_req_qid = (nettx_cstate == REQ_IDLE && nettx_nstate == RD_CTX) ? {VIRTIO_NET_TX_TYPE,nettx_avail_id_req_data} :
                                             (netrx_cstate == REQ_IDLE && netrx_nstate == RD_CTX) ? {VIRTIO_NET_RX_TYPE,netrx_avail_id_req_data} :
                                                                                                    {VIRTIO_BLK_TYPE,blk_avail_id_req_data} ; 


    assign local_id_num = desc_engine_ctx_info_rd_rsp_avail_pi - desc_engine_ctx_info_rd_rsp_avail_ci;

    always @(posedge clk)begin
        nettx_avail_id_req_nid_1d <= nettx_avail_id_req_nid;
        netrx_avail_id_req_nid_1d <= netrx_avail_id_req_nid;
        blk_avail_id_req_nid_1d <= blk_avail_id_req_nid;
    end

    always @(posedge clk)begin
        if(rst)begin
            rd_id_num_nettx <= 0;
        end
        else if(desc_engine_ctx_info_rd_rsp_vld && nettx_cstate == RD_CTX)begin
            rd_id_num_nettx <= (local_id_num > nettx_avail_id_req_nid_1d) ? nettx_avail_id_req_nid_1d : local_id_num;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            rd_id_num_netrx <= 0;
        end
        else if(desc_engine_ctx_info_rd_rsp_vld && netrx_cstate == RD_CTX)begin
            rd_id_num_netrx <= (local_id_num > netrx_avail_id_req_nid_1d) ? netrx_avail_id_req_nid_1d : local_id_num;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            rd_id_num_blk <= 0;
        end
        else if(desc_engine_ctx_info_rd_rsp_vld && blk_cstate == RD_CTX)begin
            rd_id_num_blk <= (local_id_num > blk_avail_id_req_nid_1d) ? blk_avail_id_req_nid_1d : local_id_num;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            cnt_id_num_nettx <= 0;
        end
        else if(nettx_cstate == REQ_IDLE)begin
            cnt_id_num_nettx <= 0;
        end
        else if(rd_ring_id_nettx_req_vld && rd_id_num_nettx > 0)begin
            cnt_id_num_nettx <= cnt_id_num_nettx + 1;
        end
    end 

    always @(posedge clk)begin
        if(rst)begin
            cnt_id_num_netrx <= 0;
        end
        else if(netrx_cstate == REQ_IDLE)begin
            cnt_id_num_netrx <= 0;
        end
        else if(rd_ring_id_netrx_req_vld && rd_id_num_netrx > 0)begin
            cnt_id_num_netrx <= cnt_id_num_netrx + 1;
        end
    end 

    always @(posedge clk)begin
        if(rst)begin
            cnt_id_num_blk <= 0;
        end
        else if(blk_cstate == REQ_IDLE)begin
            cnt_id_num_blk <= 0;
        end
        else if(rd_ring_id_blk_req_vld && rd_id_num_blk > 0)begin
            cnt_id_num_blk <= cnt_id_num_blk + 1;
        end
    end 

    always @(posedge clk)begin
        if(rd_ring_id_nettx_req_vld)begin
            cnt_id_num_nettx_1d <= cnt_id_num_nettx;
        end
    end

    always @(posedge clk)begin
        if(rd_ring_id_netrx_req_vld)begin
            cnt_id_num_netrx_1d <= cnt_id_num_netrx;
        end
    end

    always @(posedge clk)begin
        if(rd_ring_id_blk_req_vld)begin
            cnt_id_num_blk_1d <= cnt_id_num_blk;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            rd_ring_id_nettx_req_vld <= 0;
        end
        else if(rd_ring_id_nettx_req_vld)begin
            rd_ring_id_nettx_req_vld <= 0;
        end
        else if(nettx_cstate == RD_CTX || (nettx_avail_id_rsp_rdy && nettx_avail_id_rsp_vld && (cnt_id_num_nettx  <  rd_id_num_nettx)))begin
            rd_ring_id_nettx_req_vld <= 1;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            rd_ring_id_netrx_req_vld <= 0;
        end
        else if(rd_ring_id_netrx_req_vld)begin
            rd_ring_id_netrx_req_vld <= 0;
        end
        else if(netrx_cstate == RD_CTX || (netrx_avail_id_rsp_rdy && netrx_avail_id_rsp_vld && (cnt_id_num_netrx  <  rd_id_num_netrx)))begin
            rd_ring_id_netrx_req_vld <= 1;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            rd_ring_id_blk_req_vld <= 0;
        end
        else if(rd_ring_id_blk_req_vld)begin
            rd_ring_id_blk_req_vld <= 0;
        end
        else if(blk_cstate == RD_CTX || (blk_avail_id_rsp_rdy && blk_avail_id_rsp_vld && (cnt_id_num_blk  <  rd_id_num_blk)))begin
            rd_ring_id_blk_req_vld <= 1;
        end
    end
    logic [NETTX_PERQ_RING_ID_WIDTH-1:0] nettx_offset_addr;
    logic [NETRX_PERQ_RING_ID_WIDTH-1:0] netrx_offset_addr;
    logic [BLK_PERQ_RING_ID_WIDTH-1:0] blk_offset_addr;
    assign nettx_offset_addr = nettx_desc_engine_ctx_info_rd_rsp_avail_ci_1d[NETTX_PERQ_RING_ID_WIDTH-1:0] + cnt_id_num_nettx;
    assign netrx_offset_addr = netrx_desc_engine_ctx_info_rd_rsp_avail_ci_1d[NETRX_PERQ_RING_ID_WIDTH-1:0] + cnt_id_num_netrx;
    assign blk_offset_addr = blk_desc_engine_ctx_info_rd_rsp_avail_ci_1d[BLK_PERQ_RING_ID_WIDTH-1:0] + cnt_id_num_blk;

    assign rd_ring_id_nettx_req_addr = (nettx_avail_id_req_data_reg << NETTX_PERQ_RING_ID_WIDTH) + nettx_offset_addr;
    assign rd_ring_id_netrx_req_addr = (netrx_avail_id_req_data_reg << NETRX_PERQ_RING_ID_WIDTH) + netrx_offset_addr;
    assign rd_ring_id_blk_req_addr = (blk_avail_id_req_data_reg << BLK_PERQ_RING_ID_WIDTH) + blk_offset_addr;

    always @(posedge clk)begin
        if(rst)begin
            nettx_avail_id_rsp_vld <= 0;
        end
        else if(nettx_avail_id_rsp_rdy || !nettx_avail_id_rsp_vld)begin
            nettx_avail_id_rsp_vld <= rd_ring_id_nettx_req_vld;
        end
    end

    //assign nettx_avail_id_rsp_vld = rd_ring_id_nettx_rsp_vld;
    assign nettx_avail_id_rsp_data.vq.qid = nettx_avail_id_req_data_1d;
    assign nettx_avail_id_rsp_data.vq.typ = VIRTIO_NET_TX_TYPE;
    assign nettx_avail_id_rsp_data.id = rd_ring_id_nettx_rsp_data_reg[15:0];
    assign nettx_avail_id_rsp_data.avail_ring_empty = nettx_desc_engine_ctx_info_rd_rsp_avail_idx_1d == nettx_desc_engine_ctx_info_rd_rsp_avail_ci_1d;
    assign nettx_avail_id_rsp_data.local_ring_empty = nettx_desc_engine_ctx_info_rd_rsp_avail_pi_1d == nettx_desc_engine_ctx_info_rd_rsp_avail_ci_1d;
    assign nettx_avail_id_rsp_data.q_stat_doing =  nettx_desc_engine_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_DOING;
    assign nettx_avail_id_rsp_data.q_stat_stopping = nettx_desc_engine_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_STOPPING ;
    assign nettx_avail_id_rsp_data.avail_idx = nettx_desc_engine_ctx_info_rd_rsp_avail_ci_1d + cnt_id_num_nettx_1d;
    assign nettx_avail_id_rsp_eop = (rd_id_num_nettx >0) ? (cnt_id_num_nettx  ==  rd_id_num_nettx) : 1 ;
    assign nettx_avail_id_rsp_data.err_info.fatal = rd_ring_id_nettx_rsp_data_reg[17:16] > 0;
    assign nettx_avail_id_rsp_data.err_info.err_code = rd_ring_id_nettx_rsp_data_reg[17] ? VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR :
                                                       rd_ring_id_nettx_rsp_data_reg[16] ? VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE :
                                                                                           VIRTIO_ERR_CODE_NONE ;

    always @(posedge clk)begin
        if(rst)begin
            netrx_avail_id_rsp_vld <= 0;
        end
        else if(netrx_avail_id_rsp_rdy || !netrx_avail_id_rsp_vld)begin
            netrx_avail_id_rsp_vld <= rd_ring_id_netrx_req_vld;
        end
    end

    assign netrx_avail_id_rsp_data.vq.qid = netrx_avail_id_req_data_1d;
    assign netrx_avail_id_rsp_data.vq.typ = VIRTIO_NET_RX_TYPE;
    assign netrx_avail_id_rsp_data.id = rd_ring_id_netrx_rsp_data_reg[15:0];
    assign netrx_avail_id_rsp_data.avail_ring_empty = netrx_desc_engine_ctx_info_rd_rsp_avail_idx_1d == netrx_desc_engine_ctx_info_rd_rsp_avail_ci_1d;
    assign netrx_avail_id_rsp_data.local_ring_empty = netrx_desc_engine_ctx_info_rd_rsp_avail_pi_1d == netrx_desc_engine_ctx_info_rd_rsp_avail_ci_1d;
    assign netrx_avail_id_rsp_data.q_stat_doing = netrx_desc_engine_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_DOING;
    assign netrx_avail_id_rsp_data.q_stat_stopping = netrx_desc_engine_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_STOPPING ;
    assign netrx_avail_id_rsp_data.avail_idx = netrx_desc_engine_ctx_info_rd_rsp_avail_ci_1d + cnt_id_num_netrx_1d;
    assign netrx_avail_id_rsp_eop = (rd_id_num_netrx >0) ? (cnt_id_num_netrx  ==  rd_id_num_netrx) : 1 ;
    assign netrx_avail_id_rsp_data.err_info.fatal = rd_ring_id_netrx_rsp_data_reg[17:16] > 0;
    assign netrx_avail_id_rsp_data.err_info.err_code = rd_ring_id_netrx_rsp_data_reg[17] ? VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR :
                                                       rd_ring_id_netrx_rsp_data_reg[16] ? VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE :
                                                                                           VIRTIO_ERR_CODE_NONE ;

    always @(posedge clk)begin
        if(rst)begin
            blk_avail_id_rsp_vld <= 0;
        end
        else if(blk_avail_id_rsp_rdy || !blk_avail_id_rsp_vld)begin
            blk_avail_id_rsp_vld <= rd_ring_id_blk_req_vld;
        end
    end

    assign blk_avail_id_rsp_data.vq.qid = blk_avail_id_req_data_1d;
    assign blk_avail_id_rsp_data.vq.typ = VIRTIO_BLK_TYPE;
    assign blk_avail_id_rsp_data.id = rd_ring_id_blk_rsp_data_reg[15:0];
    assign blk_avail_id_rsp_data.avail_ring_empty = blk_desc_engine_ctx_info_rd_rsp_avail_idx_1d == blk_desc_engine_ctx_info_rd_rsp_avail_ci_1d;
    assign blk_avail_id_rsp_data.local_ring_empty = blk_desc_engine_ctx_info_rd_rsp_avail_pi_1d == blk_desc_engine_ctx_info_rd_rsp_avail_ci_1d;
    assign blk_avail_id_rsp_data.q_stat_doing =  blk_desc_engine_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_DOING;
    assign blk_avail_id_rsp_data.q_stat_stopping = blk_desc_engine_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_STOPPING ;
    assign blk_avail_id_rsp_data.avail_idx = blk_desc_engine_ctx_info_rd_rsp_avail_ci_1d + cnt_id_num_blk_1d;
    assign blk_avail_id_rsp_eop = (rd_id_num_blk >0) ? (cnt_id_num_blk  ==  rd_id_num_blk) : 1 ;
    assign blk_avail_id_rsp_data.err_info.fatal = rd_ring_id_blk_rsp_data_reg[17:16] > 0;
    assign blk_avail_id_rsp_data.err_info.err_code = rd_ring_id_blk_rsp_data_reg[17] ? VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR :
                                                     rd_ring_id_blk_rsp_data_reg[16] ? VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE :
                                                                                       VIRTIO_ERR_CODE_NONE ;

    always @(posedge clk)begin
        if(rst)begin
            avail_ci_wr_req_vld <= 0;
            avail_ci_wr_req_data <= 0;
            avail_ci_wr_req_qid <= 0;
        end
        else if(nettx_cstate == UPDATA_CI && nettx_avail_id_rsp_data.local_ring_empty == 0 && nettx_avail_id_rsp_data.q_stat_doing == 1 && mark_clk == 0)begin
            avail_ci_wr_req_vld <= 1;
            avail_ci_wr_req_data <= nettx_desc_engine_ctx_info_rd_rsp_avail_ci_1d + rd_id_num_nettx;
            avail_ci_wr_req_qid <= {VIRTIO_NET_TX_TYPE,nettx_avail_id_req_data_1d} ;
        end
        else if(netrx_cstate ==  UPDATA_CI && netrx_avail_id_rsp_data.local_ring_empty == 0 && netrx_avail_id_rsp_data.q_stat_doing == 1 && mark_clk == 1)begin
            avail_ci_wr_req_vld <= 1;
            avail_ci_wr_req_data <= netrx_desc_engine_ctx_info_rd_rsp_avail_ci_1d + rd_id_num_netrx;
            avail_ci_wr_req_qid <= {VIRTIO_NET_RX_TYPE,netrx_avail_id_req_data_1d};
        end
        else if(blk_cstate == UPDATA_CI && blk_avail_id_rsp_data.local_ring_empty == 0 && blk_avail_id_rsp_data.q_stat_doing == 1 && (nettx_cstate != UPDATA_CI && netrx_cstate != UPDATA_CI))begin
            avail_ci_wr_req_vld <= 1;
            avail_ci_wr_req_data <= blk_desc_engine_ctx_info_rd_rsp_avail_ci_1d + rd_id_num_blk;
            avail_ci_wr_req_qid <= {VIRTIO_BLK_TYPE,blk_avail_id_req_data_1d} ;
        end
        else begin
            avail_ci_wr_req_vld <= 0;
        end
    end


    always @(posedge clk)begin
        vq_pending_chk_rsp_vld <= vq_pending_chk_req_vld;
    end

    assign nettx_desc_engine_ctx_info_rd_rsp_ctrl_reg = nettx_cstate == RD_CTX ? desc_engine_ctx_info_rd_rsp_ctrl : nettx_desc_engine_ctx_info_rd_rsp_ctrl_1d;
    assign netrx_desc_engine_ctx_info_rd_rsp_ctrl_reg = netrx_cstate == RD_CTX ? desc_engine_ctx_info_rd_rsp_ctrl : netrx_desc_engine_ctx_info_rd_rsp_ctrl_1d;
    assign blk_desc_engine_ctx_info_rd_rsp_ctrl_reg = blk_cstate == RD_CTX ? desc_engine_ctx_info_rd_rsp_ctrl : blk_desc_engine_ctx_info_rd_rsp_ctrl_1d;

    always @(posedge clk)begin
        if(rst)begin
            nettx_busy_qid <= 0;
        end
        else if(nettx_avail_id_req_vld && nettx_cstate == REQ_IDLE)begin
            nettx_busy_qid <= nettx_avail_id_req_data;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            netrx_busy_qid <= 0;
        end
        else if(netrx_avail_id_req_vld && netrx_cstate == REQ_IDLE)begin
            netrx_busy_qid <= netrx_avail_id_req_data;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            blk_busy_qid <= 0;
        end
        else if(blk_avail_id_req_vld && blk_cstate == REQ_IDLE)begin
            blk_busy_qid <= blk_avail_id_req_data;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            vq_pending_chk_rsp_busy <= 0;
        end
        else if(vq_pending_chk_req_vld)begin
            case(vq_pending_chk_req_vq.typ)
                VIRTIO_NET_TX_TYPE:
                    begin
                        if(vq_pending_chk_req_vq.qid == nettx_busy_qid.qid && nettx_cstate != REQ_IDLE && nettx_desc_engine_ctx_info_rd_rsp_ctrl_reg == VIRTIO_Q_STATUS_DOING)
                            vq_pending_chk_rsp_busy <= 1;
                        else 
                            vq_pending_chk_rsp_busy <= 0;
                    end
                VIRTIO_NET_RX_TYPE:
                    begin
                        if(vq_pending_chk_req_vq.qid == netrx_busy_qid.qid && netrx_cstate != REQ_IDLE && netrx_desc_engine_ctx_info_rd_rsp_ctrl_reg == VIRTIO_Q_STATUS_DOING)
                            vq_pending_chk_rsp_busy <= 1;
                        else 
                            vq_pending_chk_rsp_busy <= 0;
                    end
                VIRTIO_BLK_TYPE :
                    begin
                        if(vq_pending_chk_req_vq.qid == blk_busy_qid.qid && blk_cstate != REQ_IDLE && blk_desc_engine_ctx_info_rd_rsp_ctrl_reg == VIRTIO_Q_STATUS_DOING)
                            vq_pending_chk_rsp_busy <= 1;
                        else 
                            vq_pending_chk_rsp_busy <= 0;
                    end
                default: vq_pending_chk_rsp_busy <= 0;
            endcase
        end
    end


    always @(posedge clk)begin
        dfx_status <= {netrx_avail_id_req_vld,
                       netrx_avail_id_req_rdy,
                       nettx_avail_id_req_vld,
                       nettx_avail_id_req_rdy,
                       blk_avail_id_req_vld,
                       blk_avail_id_req_rdy,
                       netrx_avail_id_rsp_vld,
                       netrx_avail_id_rsp_rdy,
                       nettx_avail_id_rsp_vld,
                       nettx_avail_id_rsp_rdy,
                       blk_avail_id_rsp_vld,
                       blk_avail_id_rsp_rdy,
                       nettx_cstate,
                       netrx_cstate,
                       blk_cstate};

        dfx_err <= { 0 };

    end

endmodule
