/******************************************************************************
 * 文件名称 : virtio_netrx_slot_ctrl.sv
 * 作者名称 : Feilong Yun
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/23     Feilong Yun   初始化版本
******************************************************************************/
 `include "virtio_netrx_define.svh"
module virtio_netrx_slot_ctrl #(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM)
)
(
    input                          clk,
    input                          rst,

    input                          netrx_info_vld,
    input  virtio_rx_buf_req_info_t netrx_info_data,
    output     logic               netrx_info_rdy,

    output     logic               netrx_alloc_slot_req_vld,
    output     virtio_vq_t         netrx_alloc_slot_req_data,
    output     logic[9:0]          netrx_alloc_slot_req_dev_id,
    output     logic[`VIRTIO_RX_BUF_PKT_NUM_WIDTH-1:0]netrx_alloc_slot_req_pkt_id,
    input                          netrx_alloc_slot_req_rdy,

    input                          netrx_alloc_slot_rsp_vld,
    input    virtio_desc_eng_slot_rsp_t   netrx_alloc_slot_rsp_data,
    output    logic                netrx_alloc_slot_rsp_rdy,

    output    logic                slot_ctrl_dev_id_rd_req_vld,
    output    virtio_vq_t          slot_ctrl_dev_id_rd_req_qid,

    input                          slot_ctrl_dev_id_rd_rsp_vld,
    input     [9:0]                slot_ctrl_dev_id_rd_rsp_data,

    output   logic                 slot_id_empty_info_vld,
    output  virtio_desc_eng_slot_rsp_t slot_id_empty_info_data, 
    input                          slot_id_empty_info_rdy,

    output   logic[63:0]           dfx_status,
    output   logic[63:0]           dfx_err


);

    enum logic [7:0]  { 
        IDLE           = 8'b0000_0001,
        RD_CTX         = 8'b0000_0010,
        SLOT_REQ       = 8'b0000_0100

    } cstate, nstate,cstate_1d;


    logic                   wren_id_empty_fifo,rden_id_empty_fifo;
    virtio_desc_eng_slot_rsp_t   din_id_empty_fifo,dout_id_empty_fifo;
    logic                   id_empty_fifo_empty,id_empty_fifo_full,id_empty_fifo_overflow,id_empty_fifo_pfull,id_empty_fifo_underflow;
    logic [1:0]             id_empty_fifo_err;

    logic [9:0]             slot_ctrl_dev_id_rd_rsp_data_1d;
    virtio_rx_buf_req_info_t   netrx_info_data_1d;

    always @(posedge clk)begin
        if(slot_ctrl_dev_id_rd_rsp_vld)begin
            slot_ctrl_dev_id_rd_rsp_data_1d <= slot_ctrl_dev_id_rd_rsp_data;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            netrx_info_data_1d <= 0;
        end
        else if(netrx_info_vld && netrx_info_rdy)begin
            netrx_info_data_1d <= netrx_info_data;
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            cstate <= IDLE;
        end
        else begin
            cstate <= nstate;
        end
    end

    assign netrx_info_rdy = cstate == IDLE && netrx_info_vld;
    assign slot_ctrl_dev_id_rd_req_vld = cstate == IDLE && netrx_info_vld;
    assign slot_ctrl_dev_id_rd_req_qid = netrx_info_data.vq;

    always @(*)begin
        nstate = cstate;
        case(cstate)
        IDLE:
            begin
                if(netrx_info_vld)
                    nstate = RD_CTX;
            end
        RD_CTX:
            begin
                nstate = SLOT_REQ;
            end
        SLOT_REQ:
            begin
                if(netrx_alloc_slot_req_rdy)
                    nstate = IDLE;
            end
        default: nstate = cstate;
        endcase
    end

    assign netrx_alloc_slot_req_vld = (cstate == SLOT_REQ);
    assign netrx_alloc_slot_req_dev_id = slot_ctrl_dev_id_rd_rsp_data_1d;
    assign netrx_alloc_slot_req_data.qid = netrx_info_data_1d.vq.qid;
    assign netrx_alloc_slot_req_data.typ = VIRTIO_NET_RX_TYPE;
    assign netrx_alloc_slot_req_pkt_id = netrx_info_data_1d.pkt_id;

    assign netrx_alloc_slot_rsp_rdy = id_empty_fifo_pfull == 0;
    assign din_id_empty_fifo = netrx_alloc_slot_rsp_data;
    assign wren_id_empty_fifo = netrx_alloc_slot_rsp_rdy && netrx_alloc_slot_rsp_vld && (netrx_alloc_slot_rsp_data.local_ring_empty == 1 || netrx_alloc_slot_rsp_data.q_stat_doing == 0);

    always @(posedge clk)begin
        if(rst)begin
            slot_id_empty_info_vld <= 0;
        end
        else if(slot_id_empty_info_vld && slot_id_empty_info_rdy)begin
            slot_id_empty_info_vld <= 0;
        end
        else if(id_empty_fifo_empty == 0)begin
            slot_id_empty_info_vld <= 1;
        end
    end

    always @(posedge clk)begin
        slot_id_empty_info_data <= dout_id_empty_fifo;
    end

    assign rden_id_empty_fifo = slot_id_empty_info_vld && slot_id_empty_info_rdy;

    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_id_empty_fifo)),
        .FIFO_DEPTH (32),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (28),
        .DEPTH_PEMPTY (),
        .RAM_MODE ("dist"),
        .FIFO_MODE ("fwft")
    )u_id_empty_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_id_empty_fifo ),
        .din           ( din_id_empty_fifo ),
        .full          ( id_empty_fifo_full),
        .pfull         ( id_empty_fifo_pfull),
        .overflow      ( id_empty_fifo_overflow),
           
        .rden          ( rden_id_empty_fifo),
        .dout          ( dout_id_empty_fifo),
        .empty         ( id_empty_fifo_empty),
        .pempty        (),
        .underflow     ( id_empty_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( id_empty_fifo_err)
    
    );



    always @(posedge clk)begin
        dfx_status <= {id_empty_fifo_full,
                       id_empty_fifo_pfull,
                       id_empty_fifo_empty,
                       netrx_info_vld,
                       netrx_info_rdy,
                       netrx_alloc_slot_req_vld,
                       netrx_alloc_slot_req_rdy,
                       netrx_alloc_slot_rsp_vld,
                       netrx_alloc_slot_rsp_rdy,
                       slot_id_empty_info_vld,
                       slot_id_empty_info_rdy,
                       cstate};

        dfx_err <= {id_empty_fifo_overflow,
                    id_empty_fifo_underflow,
                    id_empty_fifo_err};
    end

    


endmodule