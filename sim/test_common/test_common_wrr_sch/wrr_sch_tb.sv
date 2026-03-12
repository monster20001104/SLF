/******************************************************************************
 * 文件名称 : wrr_sch_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/07/31
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/31     Joe Jiang   初始化版本
 ******************************************************************************/
module wrr_sch_tb #(
  parameter SH_NUM      = 2,
  parameter WEIGHT_WID  = 8
)(
  input                             clk          ,
  input                             rst          ,
  input  [SH_NUM*WEIGHT_WID-1 : 0]  sch_weight   ,
  input                             sch_en       ,
  input  [SH_NUM-1 : 0]             sch_req      ,
  output [SH_NUM-1 : 0]             sch_grant    ,
  output                            sch_grant_vld
);

initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0);
    $fsdbDumpMDA();//sim_top.u_happy_digital_top.AFE_DSP_DATA);//存储所有的memeory值
end

wrr_sch #(
    .SH_NUM(SH_NUM),
    .WEIGHT_WID(WEIGHT_WID)
) u_wrr_sch(
    .clk              (clk              ),
    .rst              (rst              ),
    .sch_weight   (sch_weight   ),
    .sch_en       (sch_en       ),
    .sch_req      (sch_req      ),
    .sch_grant    (sch_grant    ),
    .sch_grant_vld(sch_grant_vld)
);


endmodule