module common_multi_bit_ctrl_signal_cdc_tb #(
    parameter DATA_WIDTH = 8,
    parameter SYNC_STAGES = 2
    )(
    // 系统信号
    input wire din_rst,
    input wire dout_rst,   
     
    // 域A接口
    input wire din_clk,
    input wire [DATA_WIDTH-1:0] din_data,
    input wire din_valid,
    output wire din_ready,
    
    // 域B接口
    input wire dout_clk,
    output wire [DATA_WIDTH-1:0] dout_data,
    output wire dout_valid,
    input wire dout_ready 
);

multi_bit_ctrl_signal_cdc #(
    .DATA_WIDTH  (DATA_WIDTH),
    .SYNC_STAGES (SYNC_STAGES)
)u_multi_bit_ctrl_signal_cdc(
    .din_rst    (din_rst   ),
    .dout_rst   (dout_rst  ),
    .din_clk    (din_clk   ),
    .din_data   (din_data  ),
    .din_valid  (din_valid ),
    .din_ready  (din_ready ),
    .dout_clk   (dout_clk  ),
    .dout_data  (dout_data ),
    .dout_valid (dout_valid),
    .dout_ready (dout_ready)
);


initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, common_multi_bit_ctrl_signal_cdc_tb, "+all");
    $fsdbDumpMDA();
end

endmodule