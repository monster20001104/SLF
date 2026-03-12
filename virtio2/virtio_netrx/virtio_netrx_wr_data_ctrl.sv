  /******************************************************************************
 *              : virtio_netrx_dma_wr_req_ctrl.sv
 *              : Feilong Yun
 *              : 2025/06/23
 *              : 
 *
 *              : 
 *
 *                                                     
 * v1.0  06/23     Feilong Yun                  
******************************************************************************/
 `include "virtio_netrx_define.svh"
 `include "tlp_adap_dma_if.svh"
module virtio_netrx_dma_wr_req_ctrl #(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM)
)
(
    input                           clk,
    input                           rst,

    input                           slot_id_empty_info_vld,
    input  virtio_desc_eng_slot_rsp_t slot_id_empty_info_data, 
    output logic                    slot_id_empty_info_rdy,

    output logic                    netrx_desc_rsp_rdy,
    input                           netrx_desc_rsp_vld,
    input                           netrx_desc_rsp_sop,
    input                           netrx_desc_rsp_eop,
    input  virtio_desc_eng_desc_rsp_sbd_t  netrx_desc_rsp_sbd,
    input  virtq_desc_t             netrx_desc_rsp_data,

    output  logic                   rd_data_req_vld,
    output  virtio_rx_buf_rd_data_req_t rd_data_req_data,  // 里面包含drop信号
    input                           rd_data_req_rdy,

    input                           rd_data_rsp_vld,
    input                           rd_data_rsp_sop,
    input                           rd_data_rsp_eop,
    input  [DATA_EMPTY-1:0]    rd_data_rsp_sty,
    input  [DATA_EMPTY-1:0]    rd_data_rsp_mty,
    input  [DATA_WIDTH-1:0]    rd_data_rsp_data,
    output  logic                   rd_data_rsp_rdy,
    input virtio_rx_buf_rd_data_rsp_sbd_t rd_data_rsp_sbd,

    tlp_adap_dma_wr_req_if.src      dma_wr_req,

    output  logic                   order_fifo_vld,
    output  virtio_netrx_order_t    order_fifo_data,
    input                           order_fifo_sav,

    output  logic                   wr_data_ctx_rd_req_vld,
    output           virtio_vq_t    wr_data_ctx_rd_req_qid,

    input                           wr_data_ctx_rd_rsp_vld,
    input        [15:0]             wr_data_ctx_rd_rsp_bdf,
    input                           wr_data_ctx_rd_rsp_forced_shutdown,

    output  logic [63:0]            cnt_drop_rcv_len_err,
    output  logic [63:0]            cnt_drop_desc_err,
    output  logic [63:0]            cnt_drop_empty,

    output  logic [63:0]            wr_issued_cnt,

    output  logic [63:0]            dfx_err,
    output  logic [63:0]            dfx_status
);


    enum logic [7:0]  { 
        DESC_IDLE      = 8'b0000_0001,
        DESC_JUDGE     = 8'b0000_0010,
        DATA_VALID     = 8'b0000_0100,
        DROP           = 8'b0000_1000,
        RD_DATA        = 8'b0001_0000,
        PASS           = 8'b0010_0000
    } proc_desc_cstate, proc_desc_nstate,proc_desc_cstate_1d;

    enum logic [7:0]  { 
        SCH_IDLE       = 8'b0000_0001,
        SCH_0          = 8'b0000_0010,
        SCH_1          = 8'b0000_0100
    } sch_cstate, sch_nstate,sch_cstate_1d;

    enum logic [7:0]  { 
        WR_IDLE           = 8'b0000_0001,
        WR_JUDGE          = 8'b0000_0010,
        DROP_DATA         = 8'b0000_0100,
        WR_DATA           = 8'b0000_1000,
        RD_CMD            = 8'b0001_0000,
        RD_NEXT_DESC_CMD  = 8'b0010_0000,
        DESC_CMD_VLD      = 8'b0100_0000
    } dma_wr_req_cstate, dma_wr_req_nstate,dma_wr_req_cstate_1d;

   
    virtio_netrx_sch_cmd_t  sch_cmd_info_data,sch_cmd_info_data_1d;
    logic                   sch_cmd_info_vld,sch_cmd_info_rdy,sch_cmd_info_vld_pre;

    logic                   wren_cmd_fifo,rden_cmd_fifo;
    virtio_netrx_wr_cmd_t   din_cmd_fifo,dout_cmd_fifo,dout_cmd_fifo_1d;
    logic                   cmd_fifo_empty,cmd_fifo_full,cmd_fifo_overflow,cmd_fifo_pfull,cmd_fifo_underflow;
    logic [1:0]             cmd_fifo_err;

    logic                   wren_data_buf_fifo,rden_data_buf_fifo;
    virtio_netrx_data_buf_t din_data_buf_fifo,dout_data_buf_fifo,dout_data_buf_fifo_1d;
    logic                   data_buf_fifo_empty,data_buf_fifo_full,data_buf_fifo_overflow,data_buf_fifo_pfull,data_buf_fifo_underflow;
    logic [1:0]             data_buf_fifo_err;

    logic                   wren_sbd_buf_fifo,rden_sbd_buf_fifo;
    virtio_rx_buf_rd_data_rsp_sbd_t din_sbd_buf_fifo,dout_sbd_buf_fifo;
    logic                   sbd_buf_fifo_empty,sbd_buf_fifo_full,sbd_buf_fifo_overflow,sbd_buf_fifo_pfull,sbd_buf_fifo_underflow;
    logic [1:0]             sbd_buf_fifo_err;

    logic [15:0]            wr_data_ctx_rd_rsp_bdf_1d;
    logic                   wr_data_ctx_rd_rsp_forced_shutdown_1d;

    logic  [1:0]            sch_req,sch_grant,sch_grant_1d;
    logic                   sch_en,sch_grant_vld,sch_grant_vld_1d;

    logic  [19:0]           len_desc_add,wr_fe_len_total_later,wr_fe_len_total_pre,len_rd_fifo,len_desc_add_now,wr_fe_len_total_sty_pre;
    logic  [19:0]           wr_fe_len,wr_fe_len_now;
    logic  [DATA_EMPTY-1:0]dma_wr_req_sty,dma_wr_req_mty,dma_wr_req_sty_pre_hold;
    logic                   rd_move_data,rd_drop_data,dma_wr_req_en;


    logic                  dma_wr_req_val_pre,dma_wr_req_val_pre_1d;
    logic                  dma_wr_req_sop_pre;
    logic                  dma_wr_req_eop_pre,dma_wr_req_eop_pre_1d;
    logic  [DATA_WIDTH-1:0] dma_wr_req_data_pre;
    logic  [DATA_EMPTY-1:0] dma_wr_req_sty_pre,dma_wr_req_sty_pre_copy;
    logic  [DATA_EMPTY-1:0] dma_wr_req_mty_pre;
    logic  [63:0]          dma_wr_req_addr_pre;
    logic  [31:0]          dma_wr_req_len_pre;
    logic  [63:0]          dma_wr_req_sbd_pre;
    logic  [15:0]          dma_wr_req_bdf_pre;
    logic                  dma_wr_req_sav_pre;
    logic                  wr_chain_data_en;

    logic                  netrx_desc_rsp_sop_1d;
    logic                  netrx_desc_rsp_eop_1d;
    virtio_desc_eng_desc_rsp_sbd_t  netrx_desc_rsp_sbd_1d;
    virtq_desc_t           netrx_desc_rsp_data_1d;
    logic                  slot_id_empty_info_rdy_1d;

    virtio_desc_eng_slot_rsp_t slot_id_empty_info_data_1d; 
    
    logic                  drop;

    logic [DATA_EMPTY-1:0] dout_data_buf_fifo_sty_reg;
    logic mark_packet_first_sop;

    logic                  checkout_pkt_order_err;
    virtio_netrx_pktet_order_t  pkt_order_info_data_1d;

    
    /*
    assign rd_data_rsp_rdy = data_buf_fifo_pfull == 0;
    assign wren_data_buf_fifo = rd_data_rsp_vld && rd_data_rsp_rdy;
    assign din_data_buf_fifo.sop = rd_data_rsp_sop;
    assign din_data_buf_fifo.eop = rd_data_rsp_eop;
    assign din_data_buf_fifo.sty = rd_data_rsp_sop ? rd_data_rsp_sty : 0;
    assign din_data_buf_fifo.mty = rd_data_rsp_eop ? rd_data_rsp_mty : 0;
    assign din_data_buf_fifo.data = rd_data_rsp_data;

    assign wren_sbd_buf_fifo = wren_data_buf_fifo && rd_data_rsp_sop;
    assign din_sbd_buf_fifo = rd_data_rsp_sbd;*/


    always @(posedge clk)begin
        rd_data_rsp_rdy <= data_buf_fifo_pfull == 0;

        wren_data_buf_fifo <= rd_data_rsp_vld && rd_data_rsp_rdy;
        din_data_buf_fifo.sop <= rd_data_rsp_sop;
        din_data_buf_fifo.eop <= rd_data_rsp_eop;
        din_data_buf_fifo.sty <= rd_data_rsp_sop ? rd_data_rsp_sty : 0;
        din_data_buf_fifo.mty <= rd_data_rsp_eop ? rd_data_rsp_mty : 0;
        din_data_buf_fifo.data <= rd_data_rsp_data;

        wren_sbd_buf_fifo <= rd_data_rsp_vld && rd_data_rsp_rdy && rd_data_rsp_sop;
        din_sbd_buf_fifo <= rd_data_rsp_sbd;
    end


    always @(posedge clk)begin
        if(wr_data_ctx_rd_rsp_vld)begin
            wr_data_ctx_rd_rsp_bdf_1d <= wr_data_ctx_rd_rsp_bdf;
            wr_data_ctx_rd_rsp_forced_shutdown_1d <= wr_data_ctx_rd_rsp_forced_shutdown;
        end
    end

    
    assign sch_req = {slot_id_empty_info_vld,(netrx_desc_rsp_vld && netrx_desc_rsp_sop)};
    assign sch_en = sch_cstate == SCH_IDLE && sch_req > 0;

    always @(posedge clk)begin
        if(rst)begin
            sch_cstate <= SCH_IDLE;
        end
        else begin
            sch_cstate <= sch_nstate;
        end
    end

    always @(*)begin
        sch_nstate = sch_cstate;
        case(sch_cstate)
        SCH_IDLE:
            begin
                if(sch_req > 0)begin
                    if(sch_grant[0])
                        sch_nstate = SCH_0;
                    else if(sch_grant[1])
                        sch_nstate = SCH_1;
                end
            end
        SCH_0:
            begin
                if(netrx_desc_rsp_vld && netrx_desc_rsp_rdy && netrx_desc_rsp_eop)
                    sch_nstate = SCH_IDLE;
            end
        SCH_1:
            begin
                if(slot_id_empty_info_vld && slot_id_empty_info_rdy)
                    sch_nstate = SCH_IDLE;
            end
        default:
            sch_nstate = sch_cstate;  
        endcase
    end

    assign sch_cmd_info_vld = (sch_cstate == SCH_0 && netrx_desc_rsp_vld) || (sch_cstate == SCH_1 && slot_id_empty_info_vld);


    rr_sch#(
        .SH_NUM (2)            
    )u_rr_sch(
       .clk              ( clk ),
       .rst              ( rst ),
       .sch_req          ( sch_req ),
       .sch_en           ( sch_en ), 
       .sch_grant        ( sch_grant ), 
       .sch_grant_vld    ( sch_grant_vld )   
    );

    assign netrx_desc_rsp_rdy = proc_desc_cstate == DESC_IDLE && sch_cstate == SCH_0 && netrx_desc_rsp_vld && cmd_fifo_pfull == 0;
    assign slot_id_empty_info_rdy = proc_desc_cstate == DESC_IDLE && sch_cstate == SCH_1 && slot_id_empty_info_vld && cmd_fifo_pfull == 0 ;

    always @(posedge clk)begin
        if(netrx_desc_rsp_rdy && netrx_desc_rsp_vld)begin
            netrx_desc_rsp_sop_1d <= netrx_desc_rsp_sop;
            netrx_desc_rsp_eop_1d <= netrx_desc_rsp_eop;
            netrx_desc_rsp_sbd_1d <= netrx_desc_rsp_sbd;
            netrx_desc_rsp_data_1d <= netrx_desc_rsp_data;
        end
    end


    always @(posedge clk)begin
        if(rst)begin
            slot_id_empty_info_data_1d <= 0;
        end
        else if(slot_id_empty_info_vld && slot_id_empty_info_rdy)begin
            slot_id_empty_info_data_1d <= slot_id_empty_info_data;
        end
    end
    
    
    always @(posedge clk)begin
        slot_id_empty_info_rdy_1d <= slot_id_empty_info_rdy;
    end

    always @(posedge clk)begin
        if(rst)begin
            proc_desc_cstate <= DESC_IDLE;
        end
        else begin
            proc_desc_cstate <= proc_desc_nstate;
        end
    end
    
    always @(posedge clk)begin
        proc_desc_cstate_1d <= proc_desc_cstate;
    end

    always @(*)begin
        proc_desc_nstate = proc_desc_cstate;
        case(proc_desc_cstate)
        DESC_IDLE:
            begin
                if(sch_cmd_info_vld && cmd_fifo_pfull == 0)
                    proc_desc_nstate = DESC_JUDGE;
            end
        DESC_JUDGE:
            begin
                if(slot_id_empty_info_rdy_1d)
                    proc_desc_nstate = DROP  ;
                else  
                    proc_desc_nstate = DATA_VALID;
            end
        DROP :
            begin
                proc_desc_nstate = RD_DATA;
            end
        DATA_VALID:
            begin
                if(netrx_desc_rsp_sop_1d)
                    proc_desc_nstate = RD_DATA;
                else
                    proc_desc_nstate = PASS;
            end
        RD_DATA:
            begin
                if(rd_data_req_rdy)
                    proc_desc_nstate = DESC_IDLE;
            end
        PASS:
            begin
                proc_desc_nstate = DESC_IDLE;
            end
        default: proc_desc_nstate = proc_desc_cstate;
        endcase
    end

    always @(posedge clk)begin
        if(rst)begin
            drop <= 0;
        end
        else if(proc_desc_cstate == DESC_IDLE)begin
            drop <= 0;
        end
        else if(proc_desc_cstate == DROP )begin
            drop <= 1;
        end
    end

    assign rd_data_req_vld = (proc_desc_cstate == RD_DATA) ;
    assign rd_data_req_data.drop = drop;

    always @(posedge clk)begin
        if(rst)begin
            rd_data_req_data.pkt_id <= 0;
            rd_data_req_data.vq <= 0;
        end
        else if(proc_desc_cstate == DROP)begin
            rd_data_req_data.pkt_id <= slot_id_empty_info_data_1d.pkt_id;
            rd_data_req_data.vq <= slot_id_empty_info_data_1d.vq;
        end
        else if(proc_desc_cstate == DATA_VALID)begin
            rd_data_req_data.pkt_id <= netrx_desc_rsp_sbd_1d.pkt_id;
            rd_data_req_data.vq <= netrx_desc_rsp_sbd_1d.vq;
        end
    end

    assign wren_cmd_fifo = proc_desc_cstate == DATA_VALID ;
    assign din_cmd_fifo.sop = netrx_desc_rsp_sop_1d;
    assign din_cmd_fifo.eop = netrx_desc_rsp_eop_1d;
    assign din_cmd_fifo.netrx_desc_rsp_sbd = netrx_desc_rsp_sbd_1d;
    assign din_cmd_fifo.netrx_desc_rsp_data = netrx_desc_rsp_data_1d;


    assign wr_data_ctx_rd_req_vld = dma_wr_req_cstate == WR_IDLE && dma_wr_req_nstate == WR_JUDGE ;
    assign wr_data_ctx_rd_req_qid = dout_cmd_fifo.netrx_desc_rsp_sbd.vq;


    always @(posedge clk)begin
        if(rst)
            dma_wr_req_cstate <= WR_IDLE;
        else
            dma_wr_req_cstate <= dma_wr_req_nstate;
    end

    always @(posedge clk)begin
        dma_wr_req_cstate_1d <= dma_wr_req_cstate;
    end

    always @(*)begin
        dma_wr_req_nstate = dma_wr_req_cstate;
        case(dma_wr_req_cstate)
        WR_IDLE:
            begin
                if(cmd_fifo_empty == 0 && data_buf_fifo_empty == 0 && sbd_buf_fifo_empty == 0 && order_fifo_sav == 1)
                    dma_wr_req_nstate = WR_JUDGE;
            end
        WR_JUDGE:
            begin
                if(wr_data_ctx_rd_rsp_forced_shutdown == 1 
                || dout_cmd_fifo.netrx_desc_rsp_sbd.forced_shutdown == 1 
                || dout_sbd_buf_fifo.pkt_len > dout_cmd_fifo.netrx_desc_rsp_sbd.total_buf_length
                || dout_cmd_fifo.netrx_desc_rsp_sbd.err_info > 0)
                    dma_wr_req_nstate = DROP_DATA;
                else
                    dma_wr_req_nstate = WR_DATA;
            end
        DROP_DATA:
            begin
                if(rden_data_buf_fifo && dout_data_buf_fifo.eop)
                    dma_wr_req_nstate = RD_CMD;
            end
        WR_DATA:
            begin
                if(dma_wr_req_eop_pre && dma_wr_req_val_pre )begin
                    if(len_desc_add < dout_sbd_buf_fifo.pkt_len)
                        dma_wr_req_nstate = RD_NEXT_DESC_CMD;
                    else
                        dma_wr_req_nstate = RD_CMD;
                end
            end
        RD_CMD:
            begin
                if(rden_cmd_fifo && dout_cmd_fifo.eop)
                    dma_wr_req_nstate = WR_IDLE;
            end
        RD_NEXT_DESC_CMD:
            begin
                dma_wr_req_nstate = DESC_CMD_VLD;
            end
        DESC_CMD_VLD:
            begin
                if(cmd_fifo_empty == 0)
                    dma_wr_req_nstate = WR_DATA;
            end

        default: dma_wr_req_nstate = dma_wr_req_cstate;
        endcase
    end

    always @(posedge clk)begin
        dma_wr_req_sav_pre <= dma_wr_req.sav;
    end

    assign rden_data_buf_fifo = ((dma_wr_req_cstate == DROP_DATA ) || (rd_move_data  && dma_wr_req_sav_pre  && (dma_wr_req_sty_pre_copy == 0 || mark_packet_first_sop == 0 ))) && data_buf_fifo_empty == 0;
    assign rden_cmd_fifo = (dma_wr_req_cstate == RD_CMD || dma_wr_req_cstate == RD_NEXT_DESC_CMD) && cmd_fifo_empty == 0;
    assign rden_sbd_buf_fifo =  rden_cmd_fifo && dout_cmd_fifo.eop;

    always @(posedge clk)begin
        if(rst)begin
            len_desc_add <= 0;
        end
        else if(dma_wr_req_cstate == WR_IDLE)begin
            len_desc_add <= 0;
        end
        else if(dma_wr_req_cstate == WR_JUDGE || (dma_wr_req_cstate == DESC_CMD_VLD && cmd_fifo_empty == 0) )begin
            len_desc_add <= len_desc_add + dout_cmd_fifo.netrx_desc_rsp_data.len;
        end
    end

    assign len_desc_add_now = len_desc_add + dout_cmd_fifo.netrx_desc_rsp_data.len;

    always @(posedge clk)begin
        if(rst)begin
            wr_fe_len_total_later <= 0;
        end
        else if(rden_cmd_fifo && dout_cmd_fifo.eop)begin
            wr_fe_len_total_later <= 0;
        end
        else if(dma_wr_req_val_pre && dma_wr_req_eop_pre)begin 
            if(len_desc_add >=  dout_sbd_buf_fifo.pkt_len)begin
                wr_fe_len_total_later <= dout_sbd_buf_fifo.pkt_len;
            end
            else begin
                wr_fe_len_total_later <= len_desc_add;
            end
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            wr_fe_len_total_pre <= 0;
        end
        else if(dma_wr_req_cstate == WR_IDLE)begin
            wr_fe_len_total_pre <= 0;
        end
        else if(dma_wr_req_cstate == WR_JUDGE || (dma_wr_req_cstate == DESC_CMD_VLD && cmd_fifo_empty == 0))begin 
            if(len_desc_add + dout_cmd_fifo.netrx_desc_rsp_data.len >=  dout_sbd_buf_fifo.pkt_len)begin
                wr_fe_len_total_pre <= dout_sbd_buf_fifo.pkt_len;
            end
            else begin
                wr_fe_len_total_pre <= len_desc_add + dout_cmd_fifo.netrx_desc_rsp_data.len;
            end
        end
    end


    always @(posedge clk)begin
        if(rst)begin
            dma_wr_req_sty_pre <= 0;
        end
        else if(dma_wr_req_cstate == WR_JUDGE)begin
            dma_wr_req_sty_pre <= dout_data_buf_fifo.sty;
        end
        else if(dma_wr_req_val_pre && dma_wr_req_eop_pre)begin
            dma_wr_req_sty_pre <= len_desc_add[DATA_EMPTY-1:0] + dout_data_buf_fifo_sty_reg;
        end
        else if(dma_wr_req_val_pre && dma_wr_req_sop_pre)begin
            dma_wr_req_sty_pre <= 0;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            dma_wr_req_sty_pre_copy <= 0;
        end
        else if(dma_wr_req_cstate == WR_JUDGE)begin
            dma_wr_req_sty_pre_copy <= dout_data_buf_fifo.sty;
        end
        else if(dma_wr_req_val_pre && dma_wr_req_eop_pre)begin
            dma_wr_req_sty_pre_copy <= len_desc_add[DATA_EMPTY-1:0] + dout_data_buf_fifo_sty_reg;
        end
        else if(dma_wr_req_val_pre && dma_wr_req_sop_pre)begin
            dma_wr_req_sty_pre_copy <= 0;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            mark_packet_first_sop <= 0;
        end
        else if(dma_wr_req_cstate == WR_IDLE)begin
            mark_packet_first_sop <= 0;
        end
        else if(dma_wr_req_val_pre && dma_wr_req_sop_pre)begin
            mark_packet_first_sop <= 1;
        end
    end
    
    
    always @(posedge clk)begin
        if(dma_wr_req_cstate == WR_JUDGE)
            dout_data_buf_fifo_sty_reg <= dout_data_buf_fifo.sty;
    end

    always @(posedge clk)begin
        if(rst)begin
            dma_wr_req_sty_pre_hold <= 0;
        end
        else if(dma_wr_req_cstate == WR_IDLE)begin
            dma_wr_req_sty_pre_hold <= dout_data_buf_fifo.sty;
        end
        else if(dma_wr_req_val_pre && dma_wr_req_eop_pre)begin
            dma_wr_req_sty_pre_hold <= len_desc_add[DATA_EMPTY-1:0] + dout_data_buf_fifo_sty_reg;
        end
    end

    
    assign wr_fe_len_total_sty_pre = wr_fe_len_total_pre + dout_data_buf_fifo_sty_reg;
    assign dma_wr_req_mty_pre = DATA_WIDTH/8 - wr_fe_len_total_sty_pre[DATA_EMPTY-1:0];

    always @(posedge clk)begin
        if(rst)begin
            len_rd_fifo <= 0;
        end
        else if(dma_wr_req_cstate == WR_IDLE)begin
            len_rd_fifo <= 0;
        end
        else if(rden_data_buf_fifo) begin
            len_rd_fifo <= len_rd_fifo + DATA_WIDTH/8 - dout_data_buf_fifo.sty - dout_data_buf_fifo.mty;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            rd_move_data <= 0;
        end
        else if(dma_wr_req_eop_pre && dma_wr_req_val_pre )begin
            rd_move_data <= 0;
        end
        else if((dma_wr_req_cstate == WR_JUDGE || dma_wr_req_cstate == DESC_CMD_VLD) && len_rd_fifo < dout_sbd_buf_fifo.pkt_len  && len_rd_fifo < len_desc_add_now && dma_wr_req_nstate == WR_DATA )begin
            rd_move_data <= 1;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            dma_wr_req_en <= 0;
        end
        else if(dma_wr_req_val_pre && dma_wr_req_eop_pre)begin
            dma_wr_req_en <= 0;
        end
        else if((dma_wr_req_cstate == WR_JUDGE || dma_wr_req_cstate == DESC_CMD_VLD)&& dma_wr_req_nstate == WR_DATA)begin
            dma_wr_req_en <= 1;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            wr_chain_data_en <= 0;
        end
        else if(rden_cmd_fifo && dout_cmd_fifo.eop)begin
            wr_chain_data_en <= 0;
        end
        else if(dma_wr_req_cstate == WR_JUDGE && dma_wr_req_nstate == WR_DATA)begin
            wr_chain_data_en <= 1;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            wr_fe_len <= 0;
        end
        else if(dma_wr_req_val_pre && dma_wr_req_eop_pre)begin
            wr_fe_len <= 0;
        end
        else if(dma_wr_req_val_pre)begin
            wr_fe_len <= DATA_WIDTH/8 + wr_fe_len ;
        end
    end

    assign wr_fe_len_now = dma_wr_req_val_pre ? (DATA_WIDTH/8 + wr_fe_len ) : wr_fe_len ; 
                                                                
    assign dma_wr_req_val_pre = dma_wr_req_en && dma_wr_req_sav_pre && ((data_buf_fifo_empty == 0 && dma_wr_req_sty_pre == 0)  || dma_wr_req_sty_pre >0);
    //assign dma_wr_req_val_pre = dma_wr_req_en && dma_wr_req_sav_pre && (data_buf_fifo_empty == 0 || dma_wr_req_sty_pre >0)

    always @(posedge clk)begin
        if(rst)begin
            dma_wr_req_sop_pre <= 1;
        end
        else if(dma_wr_req_eop_pre && dma_wr_req_val_pre)begin
            dma_wr_req_sop_pre <= 1;
        end
        else if(dma_wr_req_val_pre)begin
            dma_wr_req_sop_pre <= 0;
        end
    end

    logic [17:0] dout_sbd_buf_fifo_pkt_len_1d ,netrx_desc_rsp_data_len;
    always @(posedge clk)begin
        dout_sbd_buf_fifo_pkt_len_1d <= dout_sbd_buf_fifo.pkt_len - wr_fe_len_total_later;
        netrx_desc_rsp_data_len <= dout_cmd_fifo.netrx_desc_rsp_data.len;
    end


    always @(posedge clk)begin
        if(rst) begin
            dma_wr_req_eop_pre <= 0;
        end
        else if(dma_wr_req_cstate == RD_NEXT_DESC_CMD || dma_wr_req_cstate == RD_CMD)begin
            dma_wr_req_eop_pre <= 0;
        end
        else if(dout_cmd_fifo.netrx_desc_rsp_data.len <=  wr_fe_len_now + DATA_WIDTH/8 - dma_wr_req_sty_pre_hold) begin
            dma_wr_req_eop_pre <= 1;
        end
        else if(dout_sbd_buf_fifo_pkt_len_1d <= wr_fe_len_now + DATA_WIDTH/8 -  dma_wr_req_sty_pre_hold)begin
            dma_wr_req_eop_pre <= 1;
        end
        else begin
            dma_wr_req_eop_pre <= 0;
        end
    end

    always @(posedge clk)begin
        if(rden_data_buf_fifo )begin
            dout_data_buf_fifo_1d <= dout_data_buf_fifo;
        end
    end

    always @(posedge clk)begin
        dma_wr_req.sop <= dma_wr_req_sop_pre;
        dma_wr_req.sty <= dma_wr_req_sty_pre;    
        dma_wr_req.vld <= dma_wr_req_val_pre;
        dma_wr_req.eop <= dma_wr_req_eop_pre;                                                          
        dma_wr_req.mty <= dma_wr_req_mty_pre;
        dma_wr_req.data <= (dma_wr_req_sty_pre > 0 &&  mark_packet_first_sop == 1) ? dout_data_buf_fifo_1d.data :  dout_data_buf_fifo.data;    
        dma_wr_req.desc.pcie_addr <= dout_cmd_fifo.netrx_desc_rsp_data.addr;
        dma_wr_req.desc.bdf <=  wr_data_ctx_rd_rsp_bdf_1d ;
        dma_wr_req.desc.rd2rsp_loop[0] <= len_desc_add >= dout_sbd_buf_fifo.pkt_len;
        dma_wr_req.desc.rd2rsp_loop[11:1] <= dout_cmd_fifo.netrx_desc_rsp_sbd.vq.qid;
        dma_wr_req.desc.rd2rsp_loop[103:12] <= 0;
        dma_wr_req.desc.pcie_length <= wr_fe_len_total_pre - wr_fe_len_total_later ;
        dma_wr_req.desc.dev_id <= dout_cmd_fifo.netrx_desc_rsp_sbd.dev_id;
    end    

    assign dma_wr_req.desc.vf_active = 0;
    assign dma_wr_req.desc.tc = 0;
    assign dma_wr_req.desc.attr = 0;
    assign dma_wr_req.desc.th = 0;
    assign dma_wr_req.desc.td = 0;
    assign dma_wr_req.desc.ep = 0;
    assign dma_wr_req.desc.at = 0;
    assign dma_wr_req.desc.ph = 0;

    assign   order_fifo_vld = (dma_wr_req_cstate == DROP_DATA &&  dma_wr_req_cstate_1d == WR_JUDGE)
                              || (dma_wr_req_sop_pre && dma_wr_req_val_pre);                          
    assign   order_fifo_data.qid = dout_cmd_fifo.netrx_desc_rsp_sbd.vq.qid;
    assign   order_fifo_data.ring_id = dout_cmd_fifo.netrx_desc_rsp_sbd.ring_id;
    assign   order_fifo_data.avail_idx = dout_cmd_fifo.netrx_desc_rsp_sbd.avail_idx;
    assign   order_fifo_data.len = (order_fifo_data.err_info.fatal == 1'b0 && order_fifo_data.err_info.err_code != VIRTIO_ERR_CODE_NONE) ? 0 :  dout_sbd_buf_fifo.pkt_len;
    assign   order_fifo_data.enable_wr = dma_wr_req_cstate == WR_DATA;
    assign   order_fifo_data.force_down = wr_data_ctx_rd_rsp_forced_shutdown_1d == 1 || dout_cmd_fifo.netrx_desc_rsp_sbd.forced_shutdown == 1;
    assign   order_fifo_data.err_info = (dout_cmd_fifo.netrx_desc_rsp_sbd.err_info > 0 || dout_cmd_fifo.netrx_desc_rsp_sbd.forced_shutdown == 1) ? dout_cmd_fifo.netrx_desc_rsp_sbd.err_info :
                                        (dout_sbd_buf_fifo.pkt_len > dout_cmd_fifo.netrx_desc_rsp_sbd.total_buf_length) ? {1'b0,VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR} :
                                                                                                                          0 ;



    logic err_sop,err_eop;
    check_sop_eop u_check_sop_eop(
    .clk     ( clk),
    .rst     ( rst ),

    .vld     ( rd_data_rsp_vld && rd_data_rsp_rdy) ,
    .sop     ( rd_data_rsp_sop ),
    .eop     ( rd_data_rsp_eop ),

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

    .vld    ( rd_data_rsp_vld && rd_data_rsp_rdy ),
    .sop    ( rd_data_rsp_sop),
    .eop    ( rd_data_rsp_eop),
    .sty    ( rd_data_rsp_sty),
    .mty    ( rd_data_rsp_mty),

    .exp_len ( rd_data_rsp_sbd.pkt_len),

    .checkout_len_err (checkout_len_err)
);

    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_cmd_fifo)),
        .FIFO_DEPTH (16),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (10),
        .DEPTH_PEMPTY (),
        .RAM_MODE ("dist"),
        .FIFO_MODE ("fwft")
    )u_cmd_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_cmd_fifo ),
        .din           ( din_cmd_fifo ),
        .full          ( cmd_fifo_full),
        .pfull         ( cmd_fifo_pfull),
        .overflow      ( cmd_fifo_overflow),
           
        .rden          ( rden_cmd_fifo),
        .dout          ( dout_cmd_fifo),
        .empty         ( cmd_fifo_empty),
        .pempty        (),
        .underflow     ( cmd_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( cmd_fifo_err)
    
    );


    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_data_buf_fifo)),
        .FIFO_DEPTH (32),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (24),
        .DEPTH_PEMPTY (),
        .RAM_MODE ("dist"),
        .FIFO_MODE ("fwft")
    )u_data_buf_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_data_buf_fifo ),
        .din           ( din_data_buf_fifo ),
        .full          ( data_buf_fifo_full),
        .pfull         ( data_buf_fifo_pfull),
        .overflow      ( data_buf_fifo_overflow),
           
        .rden          ( rden_data_buf_fifo),
        .dout          ( dout_data_buf_fifo),
        .empty         ( data_buf_fifo_empty),
        .pempty        (),
        .underflow     ( data_buf_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( data_buf_fifo_err)
    
    );

    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_sbd_buf_fifo)),
        .FIFO_DEPTH (32),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (24),
        .DEPTH_PEMPTY (),
        .RAM_MODE ("dist"),
        .FIFO_MODE ("fwft")
    )u_sbd_buf_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_sbd_buf_fifo ),
        .din           ( din_sbd_buf_fifo ),
        .full          ( sbd_buf_fifo_full),
        .pfull         ( sbd_buf_fifo_pfull),
        .overflow      ( sbd_buf_fifo_overflow),
           
        .rden          ( rden_sbd_buf_fifo),
        .dout          ( dout_sbd_buf_fifo),
        .empty         ( sbd_buf_fifo_empty),
        .pempty        (),
        .underflow     ( sbd_buf_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( sbd_buf_fifo_err)
    
    );
    logic data_buf_fifo_full_dfx,data_buf_fifo_pfull_dfx,data_buf_fifo_empty_dfx;
    always @(posedge clk)begin
        data_buf_fifo_pfull_dfx <= data_buf_fifo_pfull;
        data_buf_fifo_full_dfx <= data_buf_fifo_full;
        data_buf_fifo_empty_dfx <= data_buf_fifo_empty;
    end

    always @(posedge clk)begin
        dfx_status <= {sch_cstate,
                       cmd_fifo_full,
                       cmd_fifo_pfull,
                       cmd_fifo_empty,
                       data_buf_fifo_full_dfx,
                       data_buf_fifo_pfull_dfx,
                       data_buf_fifo_empty_dfx,
                       sbd_buf_fifo_full,
                       sbd_buf_fifo_pfull,
                       sbd_buf_fifo_empty,
                       netrx_desc_rsp_rdy,
                       netrx_desc_rsp_vld,
                       rd_data_req_vld,
                       rd_data_req_rdy,
                       rd_data_rsp_vld,
                       rd_data_rsp_rdy,
                       dma_wr_req.sav,
                       order_fifo_sav,
                       proc_desc_cstate,
                       dma_wr_req_cstate};

        dfx_err <= {
                    err_sop,
                    err_eop,
                    checkout_len_err,
                    cmd_fifo_overflow,
                    cmd_fifo_underflow,
                    cmd_fifo_err,
                    data_buf_fifo_overflow,
                    data_buf_fifo_underflow,
                    data_buf_fifo_err,
                    sbd_buf_fifo_overflow,
                    sbd_buf_fifo_underflow,
                    sbd_buf_fifo_err};
    end
     
    always @(posedge clk)begin
        if(rst)
            cnt_drop_rcv_len_err <= 0;
        else if(dma_wr_req_cstate == WR_JUDGE && dout_sbd_buf_fifo.pkt_len > dout_cmd_fifo.netrx_desc_rsp_sbd.total_buf_length)
            cnt_drop_rcv_len_err <= cnt_drop_rcv_len_err + 1;
    end

    always @(posedge clk)begin
        if(rst)
            cnt_drop_desc_err <= 0;
        else if(dma_wr_req_cstate == WR_JUDGE && dout_cmd_fifo.netrx_desc_rsp_sbd.err_info > 0)
            cnt_drop_desc_err <= cnt_drop_desc_err + 1;
    end

    always @(posedge clk)begin
        if(rst)
            cnt_drop_empty <= 0;
        else if(slot_id_empty_info_vld && slot_id_empty_info_rdy)
            cnt_drop_empty <= cnt_drop_empty + 1;
    end

    always @(posedge clk)begin
        if(rst)
            wr_issued_cnt <= 0;
        else if(dma_wr_req.vld && dma_wr_req.sop)
            wr_issued_cnt <= wr_issued_cnt + 1;
    end




endmodule
