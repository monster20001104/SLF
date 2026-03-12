/******************************************************************************
 * 文件名称 : beq_rr_sch_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/11/18
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  11/18     Joe Jiang   初始化版本
 ******************************************************************************/
 `include "beq_define.svh"

 module beq_rr_sch_tb #(
    parameter Q_NUM         = 64,
    parameter WEIGHT_WIDTH  = 3,
    parameter Q_WIDTH       = $clog2(Q_NUM)
) (
    input                               clk,
    input                               rst,

    input                               doorbell_vld,
    output logic                        doorbell_sav,
    input  logic [Q_WIDTH:0]            doorbell_qid,// {qid, is_txq}

    output logic                        notify_req_vld,
    input                               notify_req_rdy,
    output logic [Q_WIDTH:0]            notify_req_qid,// {qid, is_txq}

    input                               notify_rsp_vld,
    output logic                        notify_rsp_rdy,
    input logic [$bits(beq_rr_sch_notify_rsp_t)-1:0]       notify_rsp_data,

    input logic [WEIGHT_WIDTH-1:0]      hot_weight,
    input logic [WEIGHT_WIDTH-1:0]      cold_weight
 );
    initial begin
        $fsdbDumpfile("top.fsdb");
        $fsdbDumpvars(0, beq_rr_sch_tb, "+all");
        $fsdbDumpMDA();
    end

    beq_rr_sch #(
        .Q_NUM        (Q_NUM        ),
        .WEIGHT_WIDTH (WEIGHT_WIDTH ),
        .Q_WIDTH      (Q_WIDTH      )
    ) u_beq_rr_sch (
        .clk            (clk            ),
        .rst            (rst            ),
        .doorbell_vld   (doorbell_vld   ),
        .doorbell_sav   (doorbell_sav   ),
        .doorbell_qid   (doorbell_qid   ),// {qid, is_txq}
        .notify_req_vld (notify_req_vld ),
        .notify_req_rdy (notify_req_rdy ),
        .notify_req_qid (notify_req_qid ),// {qid, is_txq}
        .notify_rsp_vld (notify_rsp_vld ),
        .notify_rsp_rdy (notify_rsp_rdy ),
        .notify_rsp_data(notify_rsp_data),
        .hot_weight     (hot_weight     ),
        .cold_weight    (cold_weight    ),
	.dfx_err        (),
	.dfx_status     (),
	.notify_req_cnt (),
	.notify_rsp_cnt ()
    );

 endmodule
