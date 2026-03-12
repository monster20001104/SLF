/******************************************************************************
 *              : virtio_ring_id_engine.sv
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
 `include "tlp_adap_dma_if.svh"
module virtio_ring_id_engine 
    import alt_tlp_adaptor_pkg::*;
#(
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

 )(
    input                        clk,
    input                        rst,

    input                        notify_req_vld,
    input     virtio_vq_t        notify_req_qid,
    output    logic              notify_req_rdy,

    output    logic              notify_rsp_vld,
    output    virtio_vq_t        notify_rsp_qid,
    output    logic              notify_rsp_cold,
    output    logic              notify_rsp_done,
    input                        notify_rsp_rdy,

    tlp_adap_dma_rd_req_if.src   dma_ring_id_rd_req,
    tlp_adap_dma_rd_rsp_if.snk   dma_ring_id_rd_rsp,

    /*output   logic               dma_ring_id_rd_req.val,
    output   logic               dma_ring_id_rd_req.sty,
    output   desc_t              dma_ring_id_rd_req.desc,
    input                        dma_ring_id_rd_req.sav,

    input                        dma_ring_id_rd_rsp.val,
    input                        dma_ring_id_rd_rsp.sop,
    input                        dma_ring_id_rd_rsp.eop,
    input                        dma_ring_id_rd_rsp.err,
    input   [DATA_WIDTH-1:0]dma_ring_id_rd_rsp.data,
    input   [DATA_EMPTY-1:0]dma_ring_id_rd_rsp.sty,
    input   [DATA_EMPTY-1:0]dma_ring_id_rd_rsp.mty,
    input    desc_t              dma_ring_id_rd_rsp.desc,*/

    output   logic               avail_addr_rd_req_vld,
    output   virtio_vq_t         avail_addr_rd_req_qid,
    input                        avail_addr_rd_req_rdy,

    input                        avail_addr_rd_rsp_vld,
    input     [63:0]             avail_addr_rd_rsp_data,

    output    logic              avail_ui_wr_req_vld,
    output    logic[15:0]        avail_ui_wr_req_data,
    output    virtio_vq_t        avail_ui_wr_req_qid,

    output    logic              avail_pi_wr_req_vld,
    output    logic[15:0]        avail_pi_wr_req_data,
    output    virtio_vq_t        avail_pi_wr_req_qid,

    output   logic               nettx_notify_req_vld,
    output   logic[VIRTIO_Q_WIDTH-1:0]nettx_notify_req_qid,
    input                        nettx_notify_req_rdy,

    output   logic               blk_notify_req_vld,
    output   logic[VIRTIO_Q_WIDTH-1:0]blk_notify_req_qid,
    input                        blk_notify_req_rdy,

    output   logic               dma_ctx_info_rd_req_vld,
    output   virtio_vq_t         dma_ctx_info_rd_req_qid,

    input                        dma_ctx_info_rd_rsp_vld,
    input                        dma_ctx_info_rd_rsp_force_shutdown,
    input     [$bits(virtio_qstat_t)-1:0]dma_ctx_info_rd_rsp_ctrl,
    input     [15:0]             dma_ctx_info_rd_rsp_bdf,
    input     [3:0]              dma_ctx_info_rd_rsp_qdepth,
    input     [15:0]             dma_ctx_info_rd_rsp_avail_idx,
    input     [15:0]             dma_ctx_info_rd_rsp_avail_ui,
    input     [15:0]             dma_ctx_info_rd_rsp_avail_ci,

    input                        rd_ring_id_nettx_req_vld,
    input     [VIRTIO_Q_WIDTH + NETTX_PERQ_RING_ID_WIDTH - 1:0]rd_ring_id_nettx_req_addr,
    output    logic              rd_ring_id_nettx_rsp_vld,
    output    logic[17:0]        rd_ring_id_nettx_rsp_data,

    input                        rd_ring_id_netrx_req_vld,
    input     [VIRTIO_Q_WIDTH + NETRX_PERQ_RING_ID_WIDTH - 1:0]rd_ring_id_netrx_req_addr,
    output    logic              rd_ring_id_netrx_rsp_vld,
    output    logic[17:0]        rd_ring_id_netrx_rsp_data,

    input                        rd_ring_id_blk_req_vld,
    input     [VIRTIO_Q_WIDTH + BLK_PERQ_RING_ID_WIDTH - 1:0]rd_ring_id_blk_req_addr,
    output    logic              rd_ring_id_blk_rsp_vld,
    output    logic[17:0]        rd_ring_id_blk_rsp_data,

    output    logic [7:0]        rd_issued_cnt,
    output    logic [7:0]        rd_rsp_cnt,

    output    logic [63:0]       dfx_err,
    output    logic [63:0]       dfx_status

 );

    enum logic [7:0]  { 
        RD_IDLE     = 8'b0000_0001,
        RD_CTX      = 8'b0000_0010,
        JUDGE       = 8'b0000_0100,
        RD_RING_ID  = 8'b0000_1000,
        NO_RD       = 8'b0001_0000
    } rd_cstate, rd_nstate,rd_cstate_1d;

    enum logic [7:0]  { 
        RSP_IDLE     = 8'b0000_0001,
        PROC_RING_ID = 8'b0000_0010,
        WR_RAM       = 8'b0000_0100,
        FATAL_ERR    = 8'b0000_1000,
        NOTIFY       = 8'b0001_0000
    } rsp_cstate, rsp_nstate,rsp_cstate_1d;

    logic [4:0] ram_offset;
    logic [5:0] total_num,cnt_ring_id;

    virtio_vq_t   notify_req_qid_1d,notify_req_qid_reg;

    logic  [15:0] dma_ctx_info_rd_rsp_bdf_1d;
    logic  [15:0] dma_ctx_info_rd_rsp_qdepth_1d;
    logic  [15:0] dma_ctx_info_rd_rsp_avail_idx_1d;
    logic  [15:0] dma_ctx_info_rd_rsp_avail_ui_1d,dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d,dma_ctx_info_rd_rsp_avail_ui_1d_copy,dma_ctx_info_rd_rsp_avail_ui_1d_copy1;
    logic  [15:0] dma_ctx_info_rd_rsp_avail_ci_1d;
    logic  [$bits(virtio_qstat_t)-1:0]   dma_ctx_info_rd_rsp_ctrl_1d;
    logic         dma_ctx_info_rd_rsp_force_shutdown_1d;

    logic         wren_rsp_fifo,rden_rsp_fifo,rsp_fifo_full,rsp_fifo_pfull,rsp_fifo_empty,rsp_fifo_overflow,rsp_fifo_underflow;
    virtio_ring_id_rsp din_rsp_fifo,dout_rsp_fifo,dout_rsp_fifo_1d;
    logic [1:0]   rsp_fifo_err;

    logic         wren_order_fifo,rden_order_fifo,order_fifo_full,order_fifo_pfull,order_fifo_empty,order_fifo_overflow,order_fifo_underflow;
    virtio_vq_t din_order_fifo,dout_order_fifo;
    logic [1:0]   order_fifo_err;

    logic [5:0]   rd_num,rd_num_pre,ram_rest_num;
    logic [15:0]  max_num_host;

    logic         wea_ring_id_nettx;
    logic [VIRTIO_Q_WIDTH-1 + NETTX_PERQ_RING_ID_WIDTH:0] addra_ring_id_nettx,addrb_ring_id_nettx;
    logic [17:0]  dina_ring_id_nettx,doutb_ring_id_nettx;
    logic [1:0]   err_ring_id_nettx;

    logic         wea_ring_id_netrx;
    logic [VIRTIO_Q_WIDTH-1 + NETRX_PERQ_RING_ID_WIDTH:0] addra_ring_id_netrx,addrb_ring_id_netrx;
    logic [17:0]  dina_ring_id_netrx,doutb_ring_id_netrx;
    logic [1:0]   err_ring_id_netrx;

    logic         wea_ring_id_blk;
    logic [VIRTIO_Q_WIDTH-1 + BLK_PERQ_RING_ID_WIDTH:0] addra_ring_id_blk,addrb_ring_id_blk;
    logic [17:0]  dina_ring_id_blk,doutb_ring_id_blk;
    logic [1:0]   err_ring_id_blk;

    logic         wr_ring_id_ram_nettx_vld;
    logic [17:0]  wr_ring_id_ram_nettx_data;
    logic [VIRTIO_Q_WIDTH-1 + NETTX_PERQ_RING_ID_WIDTH:0]wr_ring_id_ram_nettx_addr;
    logic         wr_ring_id_ram_netrx_vld;
    logic [17:0]  wr_ring_id_ram_netrx_data;
    logic [VIRTIO_Q_WIDTH-1 + NETRX_PERQ_RING_ID_WIDTH:0]wr_ring_id_ram_netrx_addr;
    logic         wr_ring_id_ram_blk_vld;
    logic [17:0]  wr_ring_id_ram_blk_data;
    logic [VIRTIO_Q_WIDTH-1 + BLK_PERQ_RING_ID_WIDTH:0]wr_ring_id_ram_blk_addr;

    logic [15:0]  ring_id;  
    logic [5:0]   avail_num_id_ram;


    assign avail_num_id_ram = notify_req_qid_reg.typ == VIRTIO_NET_RX_TYPE ?  NETRX_PERQ_RING_ID_NUM :
                              notify_req_qid_reg.typ == VIRTIO_NET_TX_TYPE ?  NETTX_PERQ_RING_ID_NUM :
                                                                              BLK_PERQ_RING_ID_NUM  ;
    
    always @(posedge clk)begin
        if(rst)begin
            notify_req_qid_1d <= 0;
        end
        else if(notify_req_vld && notify_req_rdy)begin
            notify_req_qid_1d <= notify_req_qid;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            notify_req_qid_reg <= 0;
        end
        else if(notify_req_vld && rd_cstate == RD_IDLE)begin
            notify_req_qid_reg <= notify_req_qid;
        end
    end

    //assign notify_req_qid_reg = (notify_req_vld && notify_req_rdy) ? notify_req_qid : notify_req_qid_1d;

    assign notify_req_rdy = rd_cstate == RD_CTX && avail_addr_rd_req_vld && avail_addr_rd_req_rdy;

    always @(posedge clk)begin
        if(rst)begin
            avail_addr_rd_req_vld <= 0;
            avail_addr_rd_req_qid <= 0;
        end
        else if(avail_addr_rd_req_rdy || !avail_addr_rd_req_vld)begin
            avail_addr_rd_req_vld <= (rd_cstate == RD_IDLE && notify_req_vld && order_fifo_pfull == 0 && dma_ring_id_rd_req.sav == 1);
            avail_addr_rd_req_qid <= notify_req_qid;
        end
    end

    assign dma_ctx_info_rd_req_vld = rd_cstate == RD_IDLE && notify_req_vld && order_fifo_pfull == 0 && dma_ring_id_rd_req.sav == 1;
    assign dma_ctx_info_rd_req_qid = notify_req_qid;

    always @(posedge clk)begin
        if(dma_ctx_info_rd_rsp_vld)begin
            dma_ctx_info_rd_rsp_bdf_1d <= dma_ctx_info_rd_rsp_bdf;
            dma_ctx_info_rd_rsp_avail_idx_1d <= dma_ctx_info_rd_rsp_avail_idx;
            dma_ctx_info_rd_rsp_avail_ui_1d <= dma_ctx_info_rd_rsp_avail_ui;
            dma_ctx_info_rd_rsp_ctrl_1d <= dma_ctx_info_rd_rsp_ctrl;
            dma_ctx_info_rd_rsp_force_shutdown_1d <= dma_ctx_info_rd_rsp_force_shutdown;   
            dma_ctx_info_rd_rsp_avail_ui_1d_copy <= dma_ctx_info_rd_rsp_avail_ui;
            dma_ctx_info_rd_rsp_avail_ui_1d_copy1 <= dma_ctx_info_rd_rsp_avail_ui;
            dma_ctx_info_rd_rsp_avail_ci_1d <= dma_ctx_info_rd_rsp_avail_ci;       
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            dma_ctx_info_rd_rsp_qdepth_1d <= 0;
        end
        else if(dma_ctx_info_rd_rsp_vld)begin
              case (dma_ctx_info_rd_rsp_qdepth[3:0]) 
                4'd0:begin dma_ctx_info_rd_rsp_qdepth_1d <= 1;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= 0;end
                4'd1:begin dma_ctx_info_rd_rsp_qdepth_1d <= 2;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[0];end
                4'd2:begin dma_ctx_info_rd_rsp_qdepth_1d <= 4;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[1:0];end
                4'd3:begin dma_ctx_info_rd_rsp_qdepth_1d <= 8;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[2:0];end
                4'd4:begin dma_ctx_info_rd_rsp_qdepth_1d <= 16;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[3:0];end
                4'd5:begin dma_ctx_info_rd_rsp_qdepth_1d <= 32;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[4:0];end
                4'd6:begin dma_ctx_info_rd_rsp_qdepth_1d <= 64;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[5:0];end
                4'd7:begin dma_ctx_info_rd_rsp_qdepth_1d <= 128;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[6:0];end
                4'd8:begin dma_ctx_info_rd_rsp_qdepth_1d <= 256;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[7:0];end
                4'd9:begin dma_ctx_info_rd_rsp_qdepth_1d <= 512;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[8:0];end
                4'd10:begin dma_ctx_info_rd_rsp_qdepth_1d <= 1024;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[9:0];end
                4'd11:begin dma_ctx_info_rd_rsp_qdepth_1d <= 2048;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[10:0];end
                4'd12:begin dma_ctx_info_rd_rsp_qdepth_1d <= 4096;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[11:0];end
                4'd13:begin dma_ctx_info_rd_rsp_qdepth_1d <= 8192;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[12:0];end
                4'd14:begin dma_ctx_info_rd_rsp_qdepth_1d <= 16384;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[13:0];end
                4'd15:begin dma_ctx_info_rd_rsp_qdepth_1d <= 32768;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= dma_ctx_info_rd_rsp_avail_ui[14:0];end
                default : begin dma_ctx_info_rd_rsp_qdepth_1d <= 0;dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d <= 0 ;end
            endcase
        end
    end

    always @(posedge clk)begin
        if(rst) begin
            rd_cstate <= RD_IDLE;
        end
        else begin
            rd_cstate <= rd_nstate;
        end
    end

    always @(posedge clk)begin
        rd_cstate_1d <= rd_cstate;
    end

    always @(*)begin
        rd_nstate = rd_cstate;
        case(rd_cstate)
        RD_IDLE:
            begin
                if(notify_req_vld && order_fifo_pfull == 0 && dma_ring_id_rd_req.sav == 1)
                    rd_nstate = RD_CTX;
            end
        RD_CTX:
            begin
                if(avail_addr_rd_req_vld && avail_addr_rd_req_rdy)
                    rd_nstate = JUDGE;
            end
        JUDGE:
            begin
                if ( (dma_ctx_info_rd_rsp_avail_idx_1d == dma_ctx_info_rd_rsp_avail_ui_1d)
                    || (dma_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_STOPPING)
                    || (dma_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_IDLE)
                    || (dma_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_STARTING)
                    || (dma_ctx_info_rd_rsp_avail_ui_1d - dma_ctx_info_rd_rsp_avail_ci_1d) > avail_num_id_ram[5:1] )
                    rd_nstate = NO_RD;
                else
                    rd_nstate = RD_RING_ID;                
            end
        RD_RING_ID:
            begin
                if(notify_rsp_rdy)
                    rd_nstate = RD_IDLE;
            end
        NO_RD:
            begin
                if(notify_rsp_rdy)
                    rd_nstate = RD_IDLE;
            end

        default: rd_nstate = rd_cstate;
        endcase
    end
 
    always @(posedge clk)begin
        if(rst) begin
            ram_rest_num <= 0;
        end
        else if(rd_cstate == RD_CTX && rd_cstate_1d != RD_CTX && notify_req_qid_reg.typ != VIRTIO_BLK_TYPE)begin
            if(dma_ctx_info_rd_rsp_avail_ui - dma_ctx_info_rd_rsp_avail_ci < avail_num_id_ram[5:1])begin
                ram_rest_num <= avail_num_id_ram[5:1];
            end
            else begin
                ram_rest_num <= avail_num_id_ram - (dma_ctx_info_rd_rsp_avail_ui - dma_ctx_info_rd_rsp_avail_ci);
            end

        end
        else if(rd_cstate == RD_CTX && rd_cstate_1d != RD_CTX && notify_req_qid_reg.typ == VIRTIO_BLK_TYPE)begin
            ram_rest_num <= avail_num_id_ram - (dma_ctx_info_rd_rsp_avail_ui - dma_ctx_info_rd_rsp_avail_ci);
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            max_num_host <= 0;
        end
        else if(rd_cstate == RD_CTX && rd_cstate_1d != RD_CTX)begin
            max_num_host <= dma_ctx_info_rd_rsp_avail_idx - dma_ctx_info_rd_rsp_avail_ui;
        end
    end

    assign rd_num_pre = max_num_host > ram_rest_num ? ram_rest_num : max_num_host;

    always @(posedge clk)begin
        if(rst)begin
            rd_num <= 0;
        end
        else if(rd_cstate == JUDGE)begin
            if(dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d + rd_num_pre > dma_ctx_info_rd_rsp_qdepth_1d)begin
                rd_num <= dma_ctx_info_rd_rsp_qdepth_1d - dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d  ;
            end
            else begin
                rd_num <= rd_num_pre;
            end
        end
    end

    assign dma_ring_id_rd_req.desc.pcie_length = {rd_num,1'b0};
    always @(posedge clk)begin
        if(rd_cstate == JUDGE)begin
            dma_ring_id_rd_req.desc.pcie_addr <= avail_addr_rd_rsp_data + 4 + {dma_ctx_info_rd_rsp_avail_ui_in_qdepth_1d,1'b0};
            dma_ring_id_rd_req.desc.bdf <= dma_ctx_info_rd_rsp_bdf_1d;
            dma_ring_id_rd_req.desc.rd2rsp_loop[47:0] <= {notify_req_qid_1d.qid,notify_req_qid_1d.typ,dma_ctx_info_rd_rsp_avail_ui_1d,dma_ctx_info_rd_rsp_qdepth_1d};
        end
    end
    assign dma_ring_id_rd_req.desc.dev_id = 0;
    assign dma_ring_id_rd_req.desc.vf_active = 0;
    assign dma_ring_id_rd_req.desc.tc = 0;
    assign dma_ring_id_rd_req.desc.attr = 0;
    assign dma_ring_id_rd_req.desc.th = 0 ;
    assign dma_ring_id_rd_req.desc.td = 0;
    assign dma_ring_id_rd_req.desc.ep = 0;
    assign dma_ring_id_rd_req.desc.at = 0;
    assign dma_ring_id_rd_req.desc.ph = 0;

    assign dma_ring_id_rd_req.desc.rd2rsp_loop[63:48] = rd_num;
    assign dma_ring_id_rd_req.desc.rd2rsp_loop[103:64] = 0;

    assign dma_ring_id_rd_req.vld = (rd_cstate == RD_RING_ID && notify_rsp_rdy);
    assign dma_ring_id_rd_req.sty = 0;

    assign avail_ui_wr_req_vld = rd_cstate == RD_RING_ID && rd_cstate_1d != RD_RING_ID;
    assign avail_ui_wr_req_qid = notify_req_qid_1d;
    assign avail_ui_wr_req_data = dma_ctx_info_rd_rsp_avail_ui_1d + rd_num;

    assign notify_rsp_vld = rd_cstate == RD_RING_ID || rd_cstate == NO_RD;
    assign notify_rsp_qid = notify_req_qid_1d;
    assign notify_rsp_done = (dma_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_IDLE) || (dma_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_DOING && dma_ctx_info_rd_rsp_avail_idx_1d == dma_ctx_info_rd_rsp_avail_ui_1d_copy);
    assign notify_rsp_cold = (dma_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_STOPPING) ||  (dma_ctx_info_rd_rsp_ctrl_1d == VIRTIO_Q_STATUS_DOING && dma_ctx_info_rd_rsp_avail_ui_1d_copy1 - dma_ctx_info_rd_rsp_avail_ci_1d >= 16);

    assign wren_order_fifo = rd_cstate == RD_RING_ID && notify_rsp_rdy;
    assign din_order_fifo = notify_req_qid_1d;

    assign wren_rsp_fifo = dma_ring_id_rd_rsp.vld;
    assign din_rsp_fifo.ring_id_data = dma_ring_id_rd_rsp.data[255:0];
    assign din_rsp_fifo.typ = dma_ring_id_rd_rsp.desc.rd2rsp_loop[33:32] == VIRTIO_NET_RX_TYPE ? VIRTIO_NET_RX_TYPE :
                              dma_ring_id_rd_rsp.desc.rd2rsp_loop[33:32] == VIRTIO_NET_TX_TYPE ? VIRTIO_NET_TX_TYPE :
                                                                                                 VIRTIO_BLK_TYPE;
    assign din_rsp_fifo.qid = dma_ring_id_rd_rsp.desc.rd2rsp_loop[VIRTIO_Q_WIDTH+33:34];
    assign din_rsp_fifo.qdepth = dma_ring_id_rd_rsp.desc.rd2rsp_loop[15:0];
    assign din_rsp_fifo.avail_ui = dma_ring_id_rd_rsp.desc.rd2rsp_loop[31:16];
    assign din_rsp_fifo.rd_num = dma_ring_id_rd_rsp.desc.rd2rsp_loop[63:48];
    assign din_rsp_fifo.tlp_err = dma_ring_id_rd_rsp.err > 0;

    assign rden_rsp_fifo = rsp_cstate == NOTIFY && rsp_nstate == RSP_IDLE;
    assign rden_order_fifo = rsp_cstate == NOTIFY && rsp_nstate == RSP_IDLE;

    always @(posedge clk)begin
        if(rst)begin
            cnt_ring_id <= 0;
        end
        else if (rsp_cstate == RSP_IDLE)begin
            cnt_ring_id <= 0;
        end
        else if(rsp_cstate == PROC_RING_ID)begin
            cnt_ring_id <=  cnt_ring_id + 1;
        end
    end

    always@(posedge clk)begin
        if(rsp_cstate == PROC_RING_ID)begin
            case (cnt_ring_id[3:0])
                4'b0000: ring_id <= dout_rsp_fifo.ring_id_data[15:0];
                4'b0001: ring_id <= dout_rsp_fifo.ring_id_data[31:16];
                4'b0010: ring_id <= dout_rsp_fifo.ring_id_data[47:32];
                4'b0011: ring_id <= dout_rsp_fifo.ring_id_data[63:48];
                4'b0100: ring_id <= dout_rsp_fifo.ring_id_data[79:64];
                4'b0101: ring_id <= dout_rsp_fifo.ring_id_data[95:80];
                4'b0110: ring_id <= dout_rsp_fifo.ring_id_data[111:96];
                4'b0111: ring_id <= dout_rsp_fifo.ring_id_data[127:112];
                4'b1000: ring_id <= dout_rsp_fifo.ring_id_data[143:128];
                4'b1001: ring_id <= dout_rsp_fifo.ring_id_data[159:144];
                4'b1010: ring_id <= dout_rsp_fifo.ring_id_data[175:160];
                4'b1011: ring_id <= dout_rsp_fifo.ring_id_data[191:176];
                4'b1100: ring_id <= dout_rsp_fifo.ring_id_data[207:192];
                4'b1101: ring_id <= dout_rsp_fifo.ring_id_data[223:208];
                4'b1110: ring_id <= dout_rsp_fifo.ring_id_data[239:224];
                4'b1111: ring_id <= dout_rsp_fifo.ring_id_data[255:240];
            default:ring_id <= 0;
            endcase
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            ram_offset <= 0;
        end
        else if(rsp_cstate == PROC_RING_ID)begin
            ram_offset <= cnt_ring_id + dout_rsp_fifo.avail_ui;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            rsp_cstate <= RSP_IDLE;
        end
        else begin
            rsp_cstate <= rsp_nstate;
        end
    end

    always @(posedge clk)begin
        total_num <= dout_rsp_fifo.rd_num;
        dout_rsp_fifo_1d <= dout_rsp_fifo;
    end

    always @(posedge clk)begin
        rsp_cstate_1d <= rsp_cstate;
    end

    always @(*)begin
        rsp_nstate = rsp_cstate;
        case(rsp_cstate)
        RSP_IDLE:
            begin
                if(order_fifo_empty == 0 && rsp_fifo_empty == 0 )begin
                    if(dout_order_fifo.qid == dout_rsp_fifo.qid && dout_order_fifo.typ == dout_rsp_fifo.typ)
                        rsp_nstate = PROC_RING_ID;
                    else
                        rsp_nstate = FATAL_ERR;
                end
            end
        PROC_RING_ID:
            begin
                rsp_nstate = WR_RAM;
            end
        WR_RAM:
            begin
                if(cnt_ring_id < total_num)                    
                    rsp_nstate = PROC_RING_ID;
                else
                    rsp_nstate = NOTIFY;
            end
        NOTIFY:
            begin
                if( (nettx_notify_req_rdy && dout_rsp_fifo_1d.typ == VIRTIO_NET_TX_TYPE) 
                  ||(blk_notify_req_rdy && dout_rsp_fifo_1d.typ == VIRTIO_BLK_TYPE)
                  ||(dout_rsp_fifo_1d.typ == VIRTIO_NET_RX_TYPE))
                    rsp_nstate = RSP_IDLE;
            end
        FATAL_ERR:
            begin
                rsp_nstate = RSP_IDLE;
            end
        default: rsp_nstate = rsp_cstate;
        endcase
    end

    assign avail_pi_wr_req_vld = rsp_cstate == NOTIFY && rsp_cstate_1d == WR_RAM;
    assign avail_pi_wr_req_qid.qid = dout_rsp_fifo_1d.qid;
    assign avail_pi_wr_req_qid.typ = dout_rsp_fifo_1d.typ;
    assign avail_pi_wr_req_data = dout_rsp_fifo_1d.avail_ui + total_num;

    assign ring_id_err = ring_id >= dout_rsp_fifo.qdepth;

    always @(posedge clk)begin
        wr_ring_id_ram_nettx_vld <= rsp_cstate == WR_RAM && dout_rsp_fifo_1d.typ == VIRTIO_NET_TX_TYPE;
        wr_ring_id_ram_nettx_addr <= {dout_rsp_fifo_1d.qid,ram_offset[NETTX_PERQ_RING_ID_WIDTH-1:0]} ;
        wr_ring_id_ram_nettx_data <= {dout_rsp_fifo_1d.tlp_err,ring_id_err,ring_id};

        wr_ring_id_ram_netrx_vld <= rsp_cstate == WR_RAM && dout_rsp_fifo_1d.typ == VIRTIO_NET_RX_TYPE;
        wr_ring_id_ram_netrx_addr <= {dout_rsp_fifo_1d.qid,ram_offset[NETRX_PERQ_RING_ID_WIDTH-1:0]} ;
        wr_ring_id_ram_netrx_data <= {dout_rsp_fifo_1d.tlp_err,ring_id_err,ring_id};

        wr_ring_id_ram_blk_vld <= rsp_cstate == WR_RAM && dout_rsp_fifo_1d.typ == VIRTIO_BLK_TYPE;
        wr_ring_id_ram_blk_addr <= {dout_rsp_fifo_1d.qid,ram_offset[BLK_PERQ_RING_ID_WIDTH-1:0]} ;
        wr_ring_id_ram_blk_data <= {dout_rsp_fifo_1d.tlp_err,ring_id_err,ring_id};
    end

    assign wea_ring_id_nettx = wr_ring_id_ram_nettx_vld;
    assign addra_ring_id_nettx = wr_ring_id_ram_nettx_addr;
    assign dina_ring_id_nettx = wr_ring_id_ram_nettx_data;

    assign wea_ring_id_netrx = wr_ring_id_ram_netrx_vld;
    assign addra_ring_id_netrx = wr_ring_id_ram_netrx_addr;
    assign dina_ring_id_netrx = wr_ring_id_ram_netrx_data;

    assign wea_ring_id_blk = wr_ring_id_ram_blk_vld;
    assign addra_ring_id_blk = wr_ring_id_ram_blk_addr;
    assign dina_ring_id_blk = wr_ring_id_ram_blk_data;

    assign addrb_ring_id_nettx = rd_ring_id_nettx_req_addr;
    assign addrb_ring_id_netrx = rd_ring_id_netrx_req_addr;
    assign addrb_ring_id_blk = rd_ring_id_blk_req_addr;

    assign rd_ring_id_nettx_rsp_data = doutb_ring_id_nettx;
    assign rd_ring_id_netrx_rsp_data = doutb_ring_id_netrx;
    assign rd_ring_id_blk_rsp_data = doutb_ring_id_blk;

    always @(posedge clk)begin
        rd_ring_id_nettx_rsp_vld <= rd_ring_id_nettx_req_vld;
        rd_ring_id_netrx_rsp_vld <= rd_ring_id_netrx_req_vld;
        rd_ring_id_blk_rsp_vld <= rd_ring_id_blk_req_vld;
    end

    assign nettx_notify_req_vld = rsp_cstate == NOTIFY && dout_rsp_fifo_1d.typ == VIRTIO_NET_TX_TYPE;
    assign nettx_notify_req_qid = dout_rsp_fifo_1d.qid;

    assign blk_notify_req_vld = rsp_cstate == NOTIFY && dout_rsp_fifo_1d.typ == VIRTIO_BLK_TYPE;
    assign blk_notify_req_qid = dout_rsp_fifo_1d.qid;


    logic err_sop,err_eop;
    check_sop_eop u_check_sop_eop(
    .clk     ( clk),
    .rst     ( rst ),

    .vld     ( dma_ring_id_rd_rsp.vld) ,
    .sop     ( dma_ring_id_rd_rsp.sop ),
    .eop     ( dma_ring_id_rd_rsp.eop ),

    .err_sop ( err_sop),
    .err_eop ( err_eop)
);

logic checkout_len_err;
 check_pkt_len #(
    .HOST_DATA_WIDTH ( DATA_WIDTH),
    .HOST_SMTY_WIDTH ( DATA_EMPTY )
)u_check_pkt_len(
    .clk   ( clk ),
    .rst   ( rst ),

    .vld    ( dma_ring_id_rd_rsp.vld ),
    .sop    ( dma_ring_id_rd_rsp.sop),
    .eop    ( dma_ring_id_rd_rsp.eop),
    .sty    ( dma_ring_id_rd_rsp.sty),
    .mty    ( dma_ring_id_rd_rsp.mty),

    .exp_len ( dma_ring_id_rd_rsp.desc.pcie_length ),

    .checkout_len_err (checkout_len_err)
);

    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_rsp_fifo)),
        .FIFO_DEPTH (32),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (28),
        .DEPTH_PEMPTY (),
        .RAM_MODE  ("dist"),
        .FIFO_MODE  ("fwft")
    )u_rsp_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_rsp_fifo ),
        .din           ( din_rsp_fifo ),
        .full          ( rsp_fifo_full),
        .pfull         ( rsp_fifo_pfull),
        .overflow      ( rsp_fifo_overflow),
           
        .rden          ( rden_rsp_fifo),
        .dout          ( dout_rsp_fifo),
        .empty         ( rsp_fifo_empty),
        .pempty        (),
        .underflow     ( rsp_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( rsp_fifo_err)
    
    );

    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_order_fifo)),
        .FIFO_DEPTH (32),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (28),
        .DEPTH_PEMPTY (),
        .RAM_MODE  ("dist"),
        .FIFO_MODE  ("fwft")
    )u_order_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_order_fifo ),
        .din           ( din_order_fifo ),
        .full          ( order_fifo_full),
        .pfull         ( order_fifo_pfull),
        .overflow      ( order_fifo_overflow),
           
        .rden          ( rden_order_fifo),
        .dout          ( dout_order_fifo),
        .empty         ( order_fifo_empty),
        .pempty        (),
        .underflow     ( order_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( order_fifo_err)
    
    );

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH (18),
        .ADDRA_WIDTH (VIRTIO_Q_WIDTH + NETTX_PERQ_RING_ID_WIDTH ),
        .DATAB_WIDTH (18),
        .ADDRB_WIDTH (VIRTIO_Q_WIDTH + NETTX_PERQ_RING_ID_WIDTH ),
        .INIT (1), 
        .WRITE_MODE ("READ_FIRST"), 
        .RAM_MODE("blk"),
        .CHECK_ON (1),
        .CHECK_BIT(16),
        .CHECK_MODE ("parity")
    ) u_ring_id_nettx_ram(
         .rst                  ( rst ),  
         .clk                  ( clk ),
       
         .dina                 ( dina_ring_id_nettx ),
         .addra                ( addra_ring_id_nettx ),
         .wea                  ( wea_ring_id_nettx ),

         .addrb                ( addrb_ring_id_nettx),
         .doutb                ( doutb_ring_id_nettx ),   
         .parity_ecc_err       ( err_ring_id_nettx )
     
     );

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH (18),
        .ADDRA_WIDTH (VIRTIO_Q_WIDTH + NETRX_PERQ_RING_ID_WIDTH ),
        .DATAB_WIDTH (18),
        .ADDRB_WIDTH (VIRTIO_Q_WIDTH + NETRX_PERQ_RING_ID_WIDTH ),
        .INIT (1), 
        .WRITE_MODE ("READ_FIRST"), 
        .REG_EN (0),
        .RAM_MODE("blk"),
        .CHECK_ON (1),
        .CHECK_BIT(16),
        .CHECK_MODE ("parity")
    ) u_ring_id_netrx_ram(
         .rst                  ( rst ),  
         .clk                  ( clk ),
       
         .dina                 ( dina_ring_id_netrx ),
         .addra                ( addra_ring_id_netrx ),
         .wea                  ( wea_ring_id_netrx ),

         .addrb                ( addrb_ring_id_netrx),
         .doutb                ( doutb_ring_id_netrx ),   
         .parity_ecc_err       ( err_ring_id_netrx )
     
     );

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH (18),
        .ADDRA_WIDTH (VIRTIO_Q_WIDTH + BLK_PERQ_RING_ID_WIDTH ),
        .DATAB_WIDTH (18),
        .ADDRB_WIDTH (VIRTIO_Q_WIDTH + BLK_PERQ_RING_ID_WIDTH ),
        .INIT (1), 
        .WRITE_MODE ("READ_FIRST"), 
        .REG_EN (0),
        .RAM_MODE("blk"),
        .CHECK_ON (1),
        .CHECK_BIT(16),
        .CHECK_MODE ("parity")
    ) u_ring_id_blk_ram(
         .rst                  ( rst ),  
         .clk                  ( clk ),
       
         .dina                 ( dina_ring_id_blk ),
         .addra                ( addra_ring_id_blk ),
         .wea                  ( wea_ring_id_blk ),

         .addrb                ( addrb_ring_id_blk),
         .doutb                ( doutb_ring_id_blk ),   
         .parity_ecc_err       ( err_ring_id_blk )
     
     );


    always @(posedge clk)begin
        dfx_status <= {order_fifo_full,
                       order_fifo_pfull,
                       order_fifo_empty,
                       rsp_fifo_full,
                       rsp_fifo_pfull,
                       rsp_fifo_empty,
                       notify_req_vld,
                       notify_req_rdy,
                       notify_rsp_vld,
                       notify_rsp_rdy,
                       dma_ring_id_rd_req.sav,
                       nettx_notify_req_vld,
                       nettx_notify_req_rdy,
                       blk_notify_req_vld,
                       blk_notify_req_rdy,
                       avail_addr_rd_req_vld,
                       avail_addr_rd_req_rdy,
                       rd_cstate,
                       rsp_cstate};

        dfx_err <= {   checkout_len_err,
                       err_sop,
                       err_eop,
                       rsp_fifo_overflow,
                       rsp_fifo_underflow,
                       rsp_fifo_err,
                       order_fifo_overflow,
                       order_fifo_underflow,
                       order_fifo_err,
                       err_ring_id_nettx,
                       err_ring_id_netrx,
                       err_ring_id_blk,
                       (rsp_cstate == FATAL_ERR)};

    end


    always @(posedge clk)begin
        if(rst)begin
            rd_issued_cnt <= 0;
        end
        else if(dma_ring_id_rd_req.vld)begin
            rd_issued_cnt <= rd_issued_cnt + 1;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            rd_rsp_cnt <= 0;
        end
        else if(dma_ring_id_rd_rsp.vld && dma_ring_id_rd_rsp.eop)begin
            rd_rsp_cnt <= rd_rsp_cnt + 1;
        end
    end

endmodule
