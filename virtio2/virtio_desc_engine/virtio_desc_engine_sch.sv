/******************************************************************************
 * 文件名称 : virtio_desc_engine_sch.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/07/02
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/02     Joe Jiang   初始化版本
 ******************************************************************************/
 `include "virtio_desc_engine_define.svh"
module virtio_desc_engine_sch #(
    parameter SLOT_NUM       = 32,
    parameter SLOT_WIDTH     = $clog2(SLOT_NUM)
) (
    input                                   clk,
    input                                   rst,

    input  virtio_desc_eng_core_wakeup_info forced_shutdown_ff_dout, 
    input  logic                            forced_shutdown_ff_empty, 
    output logic                            forced_shutdown_ff_rden,

    input  virtio_desc_eng_core_info_ff_t   info_rd_dat,
    input  logic                            info_rd_vld,
    output logic                            info_rd_rdy,   

    input  virtio_desc_eng_core_wakeup_info wake_up_ff_dout,
    input  logic                            wake_up_ff_empty,
    output logic                            wake_up_ff_rden,

    output virtio_vq_t                      sch_vq,
    output req_type_t                       sch_type,
    output logic [SLOT_WIDTH-1:0]           sch_slot_id,
    output logic                            sch_vld,
    input  logic                            sch_ack,

    input  logic                            standby,
    input  logic [SLOT_WIDTH:0]           angry_cnt
);

    enum logic [1:0] { 
        SCH_IDLE = 2'b01,
        SCH_WAIT_ACK  = 2'b10
    } sch_cstat, sch_nstat;

    logic [2*4-1:0] sch_weight;
    logic sch_en;
    logic [1:0] sch_req, sch_grant;
    logic sch_grant_vld;

    wrr_sch #(
        .SH_NUM(2),
        .WEIGHT_WID(4)
    ) u_wrr_sch(
        .clk          (clk          ),
        .rst          (rst          ),
        .sch_weight   (sch_weight   ),
        .sch_en       (sch_en       ),
        .sch_req      (sch_req      ),
        .sch_grant    (sch_grant    ),
        .sch_grant_vld(sch_grant_vld)
    );

    assign sch_weight = {4'h8, 4'h8};
    assign sch_en = forced_shutdown_ff_empty && sch_cstat == SCH_IDLE;
    assign sch_req = {!wake_up_ff_empty && (angry_cnt < SLOT_NUM/4 || !standby), info_rd_vld};

    always @(posedge clk) begin
        if(rst)begin
            sch_cstat <= SCH_IDLE;
        end else begin
            sch_cstat <= sch_nstat;
        end
    end

    always @(*) begin
        sch_nstat = sch_cstat;
        case (sch_cstat)
            SCH_IDLE: begin
                if(!forced_shutdown_ff_empty)begin
                    sch_nstat = SCH_WAIT_ACK;
                end else if(sch_grant_vld)begin
                    sch_nstat = SCH_WAIT_ACK;
                end
            end
            SCH_WAIT_ACK:begin
                if(sch_ack)begin
                    sch_nstat = SCH_IDLE;
                end
            end
        endcase
    end
    assign sch_vld = sch_cstat == SCH_WAIT_ACK;

    always @(posedge clk) begin
        if(sch_cstat == SCH_IDLE)begin
            if(!forced_shutdown_ff_empty)begin
                sch_type            <= SHUTDOWN;
                sch_vq              <= forced_shutdown_ff_dout.vq;
                sch_slot_id         <= forced_shutdown_ff_dout.slot_id;
            end else if(sch_grant[1])begin
                sch_type            <= WAKE_UP;
                sch_vq              <= wake_up_ff_dout.vq;
                sch_slot_id         <= wake_up_ff_dout.slot_id;
            end else if(sch_grant[0])begin
                sch_type            <= DESC_RSP;
                sch_vq              <= info_rd_dat.vq;
                sch_slot_id         <= info_rd_dat.slot_id;
            end
        end
    end

    assign forced_shutdown_ff_rden  = sch_type == SHUTDOWN      && sch_ack;
    assign info_rd_rdy              = sch_type == DESC_RSP      && sch_ack;
    assign wake_up_ff_rden          = sch_type == WAKE_UP       && sch_ack;
endmodule