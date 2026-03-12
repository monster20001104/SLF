/******************************************************************************
 * 文件名称 : beq_wrr_sch_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/11/19
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  11/19     Joe Jiang   初始化版本
 ******************************************************************************/
module beq_wrr_sch_tb #(
    parameter Q_NUM         = 64,
    parameter WEIGHT_WIDTH  = 3,
    parameter Q_WIDTH       = $clog2(Q_NUM)
) (
    input                                       clk,
    input                                       rst,

    input                                       new_chain_notify_vld,
    output logic                                new_chain_notify_rdy,
    input  [$bits(beq_wrr_sch_notify_t)-1:0]    new_chain_notify_dat,

    output logic                                notify_req_vld,
    input                                       notify_req_rdy,
    output [$bits(beq_wrr_sch_notify_t)-1:0]    notify_req_dat,

    input                                       notify_rsp_vld,
    output logic                                notify_rsp_rdy,
    input [$bits(beq_wrr_sch_notify_t)-1:0]     notify_rsp_dat,

    input logic [WEIGHT_WIDTH-1:0]              emu_weight,
    input logic [WEIGHT_WIDTH-1:0]              net_weight,
    input logic [WEIGHT_WIDTH-1:0]              blk_weight,
    input logic [WEIGHT_WIDTH-1:0]              sgdma_weight
);
    initial begin
        $fsdbDumpfile("top.fsdb");
        $fsdbDumpvars(0, beq_wrr_sch_tb, "+all");
        $fsdbDumpMDA();
    end

    beq_wrr_sch #(
        .Q_NUM       (Q_NUM       ),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .Q_WIDTH     (Q_WIDTH     )
    ) u_beq_wrr_sch (
        .clk                    (clk                 ),
        .rst                    (rst                 ),
        .new_chain_notify_vld   (new_chain_notify_vld),
        .new_chain_notify_rdy   (new_chain_notify_rdy),
        .new_chain_notify_dat   (new_chain_notify_dat),
        .notify_req_vld         (notify_req_vld      ),
        .notify_req_rdy         (notify_req_rdy      ),
        .notify_req_dat         (notify_req_dat      ),
        .notify_rsp_vld         (notify_rsp_vld      ),
        .notify_rsp_rdy         (notify_rsp_rdy      ),
        .notify_rsp_dat         (notify_rsp_dat      ),
        .emu_weight             (emu_weight          ),
        .net_weight             (net_weight          ),
        .blk_weight             (blk_weight          ),
        .sgdma_weight           (sgdma_weight        ),
	.dfx_err                (),
	.dfx_status             (),
	.notify_req_cnt         (),
	.notify_rsp_cnt         ()
    );

endmodule
