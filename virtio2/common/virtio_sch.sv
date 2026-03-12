/******************************************************************************
 * 文件名称 : virtio_sch.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/10/08
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.1  2025/08/08   cui naiwan   初始化版本
 ******************************************************************************/
`include "../virtio_define.svh"
module virtio_sch #(
    parameter WEIGHT_WIDTH  = 4,
    parameter VQ_WIDTH      = 8
) (
    input                               clk,
    input                               rst,

    input                               sch_req_vld,
    output logic                        sch_req_rdy,
    input  logic [VQ_WIDTH-1:0]         sch_req_qid,

    output logic                        notify_req_vld,
    input                               notify_req_rdy,
    output logic [VQ_WIDTH-1:0]         notify_req_qid,

    input                               notify_rsp_vld,
    output logic                        notify_rsp_rdy,
    input  logic [VQ_WIDTH-1:0]         notify_rsp_qid,
    input                               notify_rsp_done,
    input                               notify_rsp_cold,

    input logic [WEIGHT_WIDTH-1:0]      hot_weight,
    input logic [WEIGHT_WIDTH-1:0]      cold_weight,

    output logic [13:0]                 dfx_err,
    output logic [11:0]                 dfx_status,

    output logic [7:0]                  notify_req_cnt,
    output logic [7:0]                  notify_rsp_cnt
);
    
    localparam VQ_NUM = 2**VQ_WIDTH;

    enum logic [2:0]  { 
        IDLE            = 3'b001,
        READ_BITMAP     = 3'b010,
        WRITE_BITMAP    = 3'b100
    } req_cstat, req_nstat;
    
    logic [1:0] req_sch_req, req_sch_grant;
    logic       req_sch_en, req_sch_grant_vld;

    logic is_sch_req, is_notify_rsp;

    typedef enum logic [1:0]  { 
        ZERO            = 2'b00,
        ONCE            = 2'b01,
        MORE            = 2'b10
    } sch_bitmap_t;

    logic                bitmap_wea;
    logic [1:0]          bitmap_parity_ecc_err;
    logic [VQ_WIDTH-1:0] bitmap_addra, bitmap_addrb;
    logic [$bits(sch_bitmap_t)-1:0]        bitmap_dina, bitmap_doutb;

    logic                hot_ff_wren, hot_ff_pfull, hot_ff_rden, hot_ff_empty;
    logic [VQ_WIDTH-1:0] hot_ff_din, hot_ff_dout;
    logic                hot_ff_overflow, hot_ff_underflow;
    logic [1:0]          hot_ff_parity_ecc_err;

    logic                cold_ff_wren, cold_ff_pfull, cold_ff_rden, cold_ff_empty;
    logic [VQ_WIDTH-1:0] cold_ff_din, cold_ff_dout;
    logic                cold_ff_overflow, cold_ff_underflow;
    logic [1:0]          cold_ff_parity_ecc_err;

    logic               push_fifo;
    logic               zero_when_notify_rsp;

    logic [1:0]                 req_wrr_sch_req, req_wrr_sch_grant;
    logic                       req_wrr_sch_en, req_wrr_sch_grant_vld;
    logic [WEIGHT_WIDTH*2-1:0]  hot_cold_weight;

    logic sch_hot;

    enum logic [1:0]  { 
        SCH            = 2'b01,
        EXE            = 2'b10
    } sch_cstat, sch_nstat;

    logic sch_req_ff_wren, sch_req_ff_pfull, sch_req_ff_full, sch_req_ff_rden, sch_req_ff_empty;
    logic [VQ_WIDTH-1:0] sch_req_ff_din, sch_req_ff_dout;
    logic sch_req_ff_overflow, sch_req_ff_underflow;
    logic [1:0] sch_req_ff_parity_ecc_err;

    yucca_sync_fifo #(
        .DATA_WIDTH (VQ_WIDTH       ),
        .FIFO_DEPTH (32             ),
        .CHECK_ON   (1              ),
        .CHECK_MODE ("parity"       ),
        .DEPTH_PFULL(24             ),
        .RAM_MODE   ("dist"         ),
        .FIFO_MODE  ("fwft"         )
    ) u_sch_req_ff (
        .clk             (clk                     ),
        .rst             (rst                     ),
        .wren            (sch_req_ff_wren             ),
        .din             (sch_req_ff_din              ),
        .full            (sch_req_ff_full                        ),
        .pfull           (sch_req_ff_pfull            ),
        .overflow        (sch_req_ff_overflow         ),
        .rden            (sch_req_ff_rden             ),
        .dout            (sch_req_ff_dout             ),
        .empty           (sch_req_ff_empty            ),
        .pempty          (                        ),
        .underflow       (sch_req_ff_underflow        ),
        .usedw           (                        ),
        .parity_ecc_err  (sch_req_ff_parity_ecc_err   )
    );

    assign sch_req_ff_wren = sch_req_vld && sch_req_rdy;
    assign sch_req_ff_din = sch_req_qid;
    assign sch_req_rdy = !sch_req_ff_full;
    
    assign req_sch_req = {!sch_req_ff_empty, notify_rsp_vld};
    assign req_sch_en = req_cstat == IDLE;

    rr_sch#(
        .SH_NUM(2)         
    )u_req_rr_sch(
        .clk           (clk),
        .rst           (rst),
        .sch_req       (req_sch_req      ),
        .sch_en        (req_sch_en       ), 
        .sch_grant     (req_sch_grant    ), 
        .sch_grant_vld (req_sch_grant_vld)   
    );

    always @(posedge clk) begin
        if(rst)begin
            req_cstat <= IDLE;
        end else begin
            req_cstat <= req_nstat;
        end
    end

    always @(*)begin
        req_nstat = req_cstat;
        case (req_cstat)
            IDLE: begin
                if(req_sch_grant_vld)begin
                    req_nstat = READ_BITMAP;
                end
            end
            READ_BITMAP: begin
                req_nstat = WRITE_BITMAP;
            end
            WRITE_BITMAP:begin
                req_nstat = IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        if(req_cstat == IDLE && req_sch_grant_vld)begin
            {is_sch_req, is_notify_rsp} <= req_sch_grant;
        end
    end

    assign sch_req_ff_rden  = req_cstat == WRITE_BITMAP && is_sch_req;
    assign notify_rsp_rdy   = req_cstat == WRITE_BITMAP && is_notify_rsp;

    sync_simple_dual_port_ram #(
        .DATAA_WIDTH( 2         ),
        .ADDRA_WIDTH( VQ_WIDTH  ),
        .DATAB_WIDTH( 2         ),
        .ADDRB_WIDTH( VQ_WIDTH  ),
        .INIT       ( 1         ),
        .WRITE_MODE ( "READ_FIRST"),
        .REG_EN     ( 0         ),
        .RAM_MODE   ( "blk"    ),//(   auto   ,   blk   ,   dist")
        .CHECK_ON   ( 1         ),
        .CHECK_MODE ( "parity"  ) //("ecc","parity"   ECC_ON=0,            
    )u_bitmap(
        .rst            (rst                    ), 
        .clk            (clk                    ),
        .dina           (bitmap_dina            ),
        .addra          (bitmap_addra           ),
        .wea            (bitmap_wea             ),
        .addrb          (bitmap_addrb           ),
        .doutb          (bitmap_doutb           ),
        .parity_ecc_err (bitmap_parity_ecc_err  )
    );

    assign bitmap_addrb = req_cstat == READ_BITMAP ? is_sch_req ? sch_req_ff_dout : notify_rsp_qid : 'h0;

    assign bitmap_wea   = req_cstat == WRITE_BITMAP;
    assign bitmap_addra = req_cstat == WRITE_BITMAP ? is_sch_req ? sch_req_ff_dout : notify_rsp_qid : 'h0;

    always @(*) begin
        if(is_sch_req)begin
            if(bitmap_doutb == ZERO)begin
                bitmap_dina = ONCE;
            //end else if(bitmap_doutb == ONCE)begin
            //    bitmap_dina = MORE;
            end else begin //bitmap_doutb == MORE
                bitmap_dina = MORE;
            end
        end else if(is_notify_rsp && notify_rsp_done)begin
            if(bitmap_doutb == MORE)begin
                bitmap_dina = ONCE;
            //end else if(bitmap_dina == ONCE)begin
            //    bitmap_dina = ZERO;
            end else begin //bitmap_doutb == ZERO
                bitmap_dina = ZERO;
            end
        end else if(is_notify_rsp && !notify_rsp_done)begin
            bitmap_dina = MORE;
        end else begin
            bitmap_dina = 2'h0;
        end
    end 

    always @(*) begin
        push_fifo = 1'b0;
        if(req_cstat == WRITE_BITMAP)begin
            if(is_sch_req)begin
                if(bitmap_doutb == ZERO)begin
                    push_fifo = 1'b1;
                end
            end else if(is_notify_rsp && notify_rsp_done)begin
                if(bitmap_doutb == MORE)begin
                    push_fifo = 1'b1;
                end
            end else if(is_notify_rsp && !notify_rsp_done)begin
                push_fifo = 1'b1;
            end
        end
    end

    //error check
    assign zero_when_notify_rsp = req_cstat == WRITE_BITMAP && is_notify_rsp && bitmap_doutb == ZERO;

    yucca_sync_fifo #(
        .DATA_WIDTH (VQ_WIDTH       ),
        .FIFO_DEPTH (VQ_NUM         ),
        .CHECK_ON   (1              ),
        .CHECK_MODE ("parity"       ),
        .DEPTH_PFULL(248            ),
        .RAM_MODE   ("blk"         ),
        .FIFO_MODE  ("fwft"         )
    ) u_hot_ff (
        .clk             (clk                     ),
        .rst             (rst                     ),
        .wren            (hot_ff_wren             ),
        .din             (hot_ff_din              ),
        .full            (                        ),
        .pfull           (hot_ff_pfull            ),
        .overflow        (hot_ff_overflow         ),
        .rden            (hot_ff_rden             ),
        .dout            (hot_ff_dout             ),
        .empty           (hot_ff_empty            ),
        .pempty          (                        ),
        .underflow       (hot_ff_underflow        ),
        .usedw           (                        ),
        .parity_ecc_err  (hot_ff_parity_ecc_err   )
    );

    assign hot_ff_wren = push_fifo &&  !(is_notify_rsp && notify_rsp_cold);
    assign hot_ff_din  = is_sch_req ? sch_req_ff_dout : notify_rsp_qid;
    assign hot_ff_rden = notify_req_vld && notify_req_rdy && sch_hot;

    yucca_sync_fifo #(
        .DATA_WIDTH (VQ_WIDTH       ),
        .FIFO_DEPTH (VQ_NUM         ),
        .CHECK_ON   (1              ),
        .CHECK_MODE ("parity"       ),
        .DEPTH_PFULL(248            ),
        .RAM_MODE   ("blk"         ),
        .FIFO_MODE  ("fwft"         )
    ) u_cold_ff (
        .clk             (clk                      ),
        .rst             (rst                      ),
        .wren            (cold_ff_wren             ),
        .din             (cold_ff_din              ),
        .full            (                         ),
        .pfull           (cold_ff_pfull            ),
        .overflow        (cold_ff_overflow         ),
        .rden            (cold_ff_rden             ),
        .dout            (cold_ff_dout             ),
        .empty           (cold_ff_empty            ),
        .pempty          (                         ),
        .underflow       (cold_ff_underflow        ),
        .usedw           (                         ),
        .parity_ecc_err  (cold_ff_parity_ecc_err   )
    );

    assign cold_ff_wren = push_fifo &&  (is_notify_rsp && notify_rsp_cold);
    assign cold_ff_din  = is_sch_req ? sch_req_ff_dout : notify_rsp_qid;

    assign cold_ff_rden = notify_req_vld && notify_req_rdy && !sch_hot;

    wrr_sch#(
        .SH_NUM     (2              ),
        .WEIGHT_WID (WEIGHT_WIDTH   )      
    )u_req_wrr_sch(
        .clk           (clk                     ),
        .rst           (rst                     ),
        .sch_weight    (hot_cold_weight         ),
        .sch_req       (req_wrr_sch_req         ),
        .sch_en        (req_wrr_sch_en          ), 
        .sch_grant     (req_wrr_sch_grant       ), 
        .sch_grant_vld (req_wrr_sch_grant_vld   )   
    );

    assign hot_cold_weight = {hot_weight, cold_weight};
    assign req_wrr_sch_en = sch_cstat == SCH;
    assign req_wrr_sch_req = {!hot_ff_empty, !cold_ff_empty};


    always @(posedge clk) begin
        if(rst)begin
            sch_cstat <= SCH;
        end else begin
            sch_cstat <= sch_nstat;
        end
    end

    always @(*) begin
        sch_nstat = sch_cstat;
        case (sch_cstat)
            SCH: begin
                if(req_wrr_sch_grant_vld)begin
                    sch_nstat = EXE;
                end
            end
            EXE: begin
                if(notify_req_vld && notify_req_rdy)begin
                    sch_nstat = SCH;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        if(req_wrr_sch_grant_vld)begin
            sch_hot <= req_wrr_sch_grant[1];
        end
    end

    assign notify_req_qid = sch_hot ? hot_ff_dout : cold_ff_dout;
    assign notify_req_vld = sch_cstat == EXE;

    assign dfx_err = {
        sch_req_ff_overflow,
        sch_req_ff_underflow,
        sch_req_ff_parity_ecc_err,
        bitmap_parity_ecc_err,
        hot_ff_overflow,
        hot_ff_underflow,
        hot_ff_parity_ecc_err,
        cold_ff_overflow,
        cold_ff_underflow,
        cold_ff_parity_ecc_err
    };

    genvar idx;
    generate
        for(idx=0;idx<$bits(dfx_err);idx++)begin :sch_req_err_i
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err[idx]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, dfx_err[idx], idx));
        end
    endgenerate

    assign dfx_status = {
        notify_req_vld,
        notify_req_rdy,
        notify_rsp_vld,
        notify_rsp_rdy,
        sch_req_ff_full,
        sch_req_ff_empty,
        hot_ff_pfull,
        hot_ff_empty,
        cold_ff_pfull,
        cold_ff_empty,
        sch_cstat
    };

    always @(posedge clk) begin
        if(rst)begin
            notify_req_cnt <= 8'h0;
            notify_rsp_cnt <= 8'h0;
        end begin
            if(notify_req_vld && notify_req_rdy)begin
                notify_req_cnt <= notify_req_cnt + 1'b1;
            end
            if(notify_rsp_vld && notify_rsp_rdy)begin
                notify_rsp_cnt <= notify_rsp_cnt + 1'b1;
            end
        end
    end

endmodule
