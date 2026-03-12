/******************************************************************************
 * 文件名称 : virtio_irq_merge_core_time.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/07/03
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   07/03      Liuch       初始化版本
 ******************************************************************************/
module virtio_irq_merge_core_time #(
    parameter CLK_FREQ_M         = 200,
    parameter TIME_STAMP_UNIT_NS = 500

) (
    input  logic        clk,
    input  logic        rst,
    output logic [15:0] time_stamp,
    output logic        time_stamp_imp
);
    localparam CLK_CYCLE = TIME_STAMP_UNIT_NS / (1000 / CLK_FREQ_M);
    localparam CLK_CYCLE_WIDTH = $clog2(CLK_CYCLE - 1);
    logic [CLK_CYCLE_WIDTH-1:0] time_cycle_cnt;

    always @(posedge clk) begin
        if (rst) begin
            time_cycle_cnt <= 'b0;
        end else begin
            if (time_cycle_cnt == CLK_CYCLE - 1) begin
                time_cycle_cnt <= 'b0;
            end else begin
                time_cycle_cnt <= time_cycle_cnt + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            time_stamp <= 'b0;
        end else if (time_cycle_cnt == CLK_CYCLE - 1) begin
            time_stamp <= time_stamp + 1;
        end
    end

    always @(posedge clk) begin
        if (time_cycle_cnt == CLK_CYCLE - 1) begin
            time_stamp_imp <= 1'b1;
        end else begin
            time_stamp_imp <= 1'b0;
        end
    end

endmodule : virtio_irq_merge_core_time
