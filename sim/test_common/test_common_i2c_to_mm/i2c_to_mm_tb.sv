/******************************************************************************
 * 文件名称 : i2c_to_mm_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/10/22
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  10/22     Joe Jiang   初始化版本
 ******************************************************************************/
 `include "fpga_define.svh"
 
 module clear_x #(
    parameter DW = 512
)(
    input  logic [DW-1:0] in,
    output logic [DW-1:0] out
);
    generate
    genvar i;
    for(i=0;i<DW;i++)begin
      always_comb begin
        case(in[i])
          1'b1: out[i] = 1'b1;
          1'b0: out[i] = 1'b0;
          default: out[i] = 1'b0;
        endcase
      end
    end
  endgenerate
    
endmodule
 
 module i2c_to_mm_tb(
    input  wire        clk,          
    input  wire        rst,    
    

    output     logic                               avmm_write,             // Asserted for writes access
    output     logic                               avmm_read,              // Asserted for read access
    output     logic [31:0]                        avmm_address,              // Target address //avmm_addr[26:24] = bar_num
    output     logic [3:0]                         avmm_byteenable,        // Byte enables
    output     logic [31:0]                      avmm_writedata,        // Write data. Valid for writes - little endian format
    input  var logic                               avmm_waitrequest,      // Asserted by slave when it is unable to process request
    input  var logic [31:0]                      avmm_readdata,         // Read data response from slave
    input  var logic                               avmm_readdatavalid,     // Asserted to indicate that avmm_read_data_i contains valid read data

    input  wire        i2c_data_in,   //   conduit_end.conduit_data_in
    input  wire        i2c_clk_in,    //              .conduit_clk_in
    output wire        i2c_data_o,   //              .conduit_data_oe
    output wire        i2c_clk_o     //              .conduit_clk_oe
 );

 

 logic i2c_data_oe, i2c_clk_oe;

 //assign i2c_data_o = ~i2c_data_oe;
 //assign i2c_clk_o = ~i2c_clk_oe;

clear_x #(.DW(1)) u_clear_x_i2c_data_o (.in(~i2c_data_oe), .out(i2c_data_o));
clear_x #(.DW(1)) u_clear_x_i2c_clk_o (.in(~i2c_clk_oe), .out(i2c_clk_o));


 initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, i2c_to_mm_tb, "+all");
    $fsdbDumpMDA();//sim_top.u_happy_digital_top.AFE_DSP_DATA);//存储所有的memeory值
end

i2c_slave_to_avalon_mm u_i2c_slave_to_avalon_mm (
		.clk           (clk                ),
		.address       (avmm_address       ),
		.read          (avmm_read          ),
		.readdata      (avmm_readdata      ),
		.readdatavalid (avmm_readdatavalid ),
		.waitrequest   (avmm_waitrequest   ),
		.write         (avmm_write         ),
		.byteenable    (avmm_byteenable    ),
		.writedata     (avmm_writedata     ),
		.rst_n         (~rst               ),
		.i2c_data_in   (i2c_data_in        ),
		.i2c_clk_in    (i2c_clk_in         ),
		.i2c_data_oe   (i2c_data_oe        ),
		.i2c_clk_oe    (i2c_clk_oe         )
	);

endmodule