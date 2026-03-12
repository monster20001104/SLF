/******************************************************************************
 * 文件名称 : virtio_rx_buf_time_stamp.sv
 * 作者名称 : lch
 * 创建日期 : 2025/06/17
 * 功能描述 : csum_check 
 *
 * 修改记录 : 
 *
 * 版本号  日期        修改人       修改内容
 * v1.0   06/17       lch         初始化版本
 ******************************************************************************/
module virtio_rx_buf_time_stamp #(
    // parameter CLK_FRQ = 20
    parameter CLK_FRQ = 200
) (
    input  logic        clk,
    input  logic        rst,
    output logic [15:0] time_stamp,
    output logic        time_stamp_up
);
    localparam CLK_CNT_WIDTH = $clog2(CLK_FRQ - 1);

    logic [CLK_CNT_WIDTH-1:0] time_cnt;
    always @(posedge clk) begin
        if (rst) begin
            time_cnt <= 'b0;
        end else if (time_cnt == CLK_FRQ - 1) begin
            time_cnt <= 'b0;
        end else begin
            time_cnt <= time_cnt + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            time_stamp <= 'b0;
        end else if (time_cnt == CLK_FRQ - 1) begin
            time_stamp <= time_stamp + 1;
        end
    end
    always @(posedge clk) begin
        if (time_cnt == CLK_FRQ - 1) begin
            time_stamp_up <= 'b1;
        end else begin
            time_stamp_up <= 'b0;
        end
    end


endmodule : virtio_rx_buf_time_stamp
