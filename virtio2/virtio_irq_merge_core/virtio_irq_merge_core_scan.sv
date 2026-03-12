/******************************************************************************
 * 文件名称 : virtio_irq_merge_core_scan.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/07/03
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   07/03      Liuch       初始化版本
 ******************************************************************************/
module virtio_irq_merge_core_scan #(
    parameter IRQ_MERGE_UINT_NUM       = 4,
    parameter IRQ_MERGE_UINT_NUM_WIDTH = $clog2(IRQ_MERGE_UINT_NUM),
    parameter QID_NUM                  = 256,
    parameter SCAN_QID_NUM             = QID_NUM / IRQ_MERGE_UINT_NUM,
    parameter SCAN_CNT_WIDTH           = $clog2(SCAN_QID_NUM + 1),
    parameter SCAN_WIDTH               = $clog2(SCAN_QID_NUM)
) (
    input  logic                  clk,
    input  logic                  rst,
    output logic [SCAN_WIDTH-1:0] scan_out_qid,
    output logic                  scan_out_vld,
    input  logic                  scan_out_rdy,
    input  logic                  time_stamp_imp
);
    logic [SCAN_CNT_WIDTH-1:0] scan_out_cnt;
    logic                      rst_logic;

    assign scan_out_vld = scan_out_cnt != SCAN_QID_NUM && rst_logic;
    assign scan_out_qid = scan_out_cnt[SCAN_WIDTH-1:0];
    always @(posedge clk) begin
        if (rst || time_stamp_imp) begin
            scan_out_cnt <= 0;
        end else if (scan_out_vld && scan_out_rdy) begin
            scan_out_cnt <= scan_out_cnt + 1;
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            rst_logic <= 1'b0;
        end else begin
            rst_logic <= 1'b1;
        end
    end

endmodule : virtio_irq_merge_core_scan
