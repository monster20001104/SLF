/******************************************************************************
 *              : virtio_netrx_wrrsp_sbd.sv
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
module virtio_netrx_wrrsp_sbd_ctrl #(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM)

 ) (
    input                        clk,
    input                        rst,

    tlp_adap_dma_wr_rsp_if.snk      dma_wr_rsp,

    input                        order_fifo_vld,
    input  virtio_netrx_order_t  order_fifo_data,
    output logic                 order_fifo_sav,

    output logic                 used_info_vld,
    output virtio_used_info_t    used_info_data,
    input                        used_info_rdy,
    
    output logic [63:0]          dfx_err,
    output logic [63:0]          dfx_status,
    output logic [63:0]          wr_rsp_cnt

 );

    enum logic [7:0]  { 
        IDLE            = 8'b0000_0001,
        GEN_ERR_USED    = 8'b0000_0010,
        GEN_USED        = 8'b0000_0100,
        FATAL_ERR       = 8'b0000_1000,
        RD_FIFO_NO_USED = 8'b0001_0000
    } cstate, nstate,cstate_1d;

    logic         wren_order_fifo,rden_order_fifo,order_fifo_full,order_fifo_pfull,order_fifo_empty,order_fifo_overflow,order_fifo_underflow;
    virtio_netrx_order_t din_order_fifo,dout_order_fifo;
    logic [1:0]   order_fifo_err;

    logic         wren_sbd_fifo,rden_sbd_fifo,sbd_fifo_full,sbd_fifo_pfull,sbd_fifo_empty,sbd_fifo_overflow,sbd_fifo_underflow;
    virtio_netrx_sbd_t din_sbd_fifo,dout_sbd_fifo;
    logic [1:0]   sbd_fifo_err;

    assign wren_order_fifo = order_fifo_vld;
    assign din_order_fifo = order_fifo_data;
    assign order_fifo_sav = ~order_fifo_pfull;

    always @(posedge clk)begin
        wren_sbd_fifo <= dma_wr_rsp.vld;
        din_sbd_fifo.tail <= dma_wr_rsp.rd2rsp_loop[0];
        din_sbd_fifo.qid <= dma_wr_rsp.rd2rsp_loop[VIRTIO_Q_WIDTH:1];
    end

    //assign wren_sbd_fifo = dma_wr_rsp.vld;
    //assign din_sbd_fifo.tail = dma_wr_rsp.rd2rsp_loop[0];
    //assign din_sbd_fifo.qid = dma_wr_rsp.rd2rsp_loop[VIRTIO_Q_WIDTH:1];

    always @(posedge clk)begin
        if(rst)begin
            cstate <= IDLE;
        end
        else begin
            cstate <= nstate;
        end
    end

    always @(*)begin
        nstate = cstate;
        case(cstate)
        IDLE:
            begin
                if(order_fifo_empty == 0 && dout_order_fifo.enable_wr == 0)
                    nstate = GEN_ERR_USED;
                else if( order_fifo_empty == 0 && dout_order_fifo.enable_wr == 1 && sbd_fifo_empty == 0)begin
                    if(dout_order_fifo.qid == dout_sbd_fifo.qid && dout_sbd_fifo.tail == 1)
                        nstate = GEN_USED;
                    else if(dout_order_fifo.qid == dout_sbd_fifo.qid && dout_sbd_fifo.tail == 0)
                        nstate = RD_FIFO_NO_USED;
                    else
                        nstate = FATAL_ERR;
                end
            end
        GEN_USED:
            begin
                if(used_info_rdy)
                    nstate = IDLE;
            end
        GEN_ERR_USED:
            begin
                if(used_info_rdy)
                    nstate = IDLE;
            end
        FATAL_ERR:
            begin
                nstate = IDLE;
            end
        RD_FIFO_NO_USED:
            begin
                nstate = IDLE;
            end
        default: nstate = IDLE;
        endcase
    end

    assign rden_order_fifo = ((cstate == GEN_USED || cstate == GEN_ERR_USED) && used_info_rdy) || cstate == RD_FIFO_NO_USED || cstate == FATAL_ERR;
    assign rden_sbd_fifo = (cstate == GEN_USED  && used_info_rdy) || cstate == RD_FIFO_NO_USED || cstate == FATAL_ERR;

    assign used_info_vld = cstate == GEN_USED || cstate == GEN_ERR_USED ;
    assign used_info_data.elem.len = dout_order_fifo.len;
    assign used_info_data.elem.id = dout_order_fifo.ring_id;
    assign used_info_data.used_idx = dout_order_fifo.avail_idx;
    assign used_info_data.err_info = dout_order_fifo.err_info;
    assign used_info_data.vq.qid = dout_order_fifo.qid;
    assign used_info_data.vq.typ = VIRTIO_NET_RX_TYPE;
    assign used_info_data.forced_shutdown = dout_order_fifo.force_down;


yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_order_fifo)),
        .FIFO_DEPTH (64),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (58),
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


    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_sbd_fifo)),
        .FIFO_DEPTH (64),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (58),
        .DEPTH_PEMPTY (),
        .RAM_MODE  ("dist"),
        .FIFO_MODE  ("fwft")
    )u_sbd_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_sbd_fifo ),
        .din           ( din_sbd_fifo ),
        .full          ( sbd_fifo_full),
        .pfull         ( sbd_fifo_pfull),
        .overflow      ( sbd_fifo_overflow),
           
        .rden          ( rden_sbd_fifo),
        .dout          ( dout_sbd_fifo),
        .empty         ( sbd_fifo_empty),
        .pempty        (),
        .underflow     ( sbd_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( sbd_fifo_err)
    
    );


        always @(posedge clk)begin
        dfx_status <= {sbd_fifo_full,
                       sbd_fifo_pfull,
                       sbd_fifo_empty,
                       order_fifo_full,
                       order_fifo_pfull,
                       order_fifo_empty,
                       used_info_vld,
                       used_info_rdy,
                       cstate};

        dfx_err <= {order_fifo_overflow,
                    order_fifo_underflow,
                    order_fifo_err,
                    sbd_fifo_overflow,
                    sbd_fifo_underflow,
                    sbd_fifo_err,
                    (cstate == FATAL_ERR)};
    end

    always @(posedge clk)begin
        if(rst)
            wr_rsp_cnt <= 0;
        else if(dma_wr_rsp.vld )
            wr_rsp_cnt <= wr_rsp_cnt + 1;
    end




endmodule
