/******************************************************************************
 * 文件名称 : dwrr_sch_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/07/31
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/31     Joe Jiang   初始化版本
 ******************************************************************************/
module dwrr_sch_tb #(
  parameter SH_NUM      = 2,
  parameter LENGTH_WID  = 4,
  parameter WEIGHT_WID  = 8
)(
  input                             clk          ,
  input                             rst          ,
  input  [SH_NUM*WEIGHT_WID-1 : 0]  sch_weight   ,
  input                             sch_en       ,
  input  [SH_NUM-1 : 0]             sch_req      ,
  input  [SH_NUM*LENGTH_WID-1 : 0]  sch_len      ,
  output [SH_NUM-1 : 0]             sch_grant    ,
  output                            sch_grant_vld
);
    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, dwrr_sch_tb, "+all");
        $fsdbDumpMDA();
    end

dwrr_sch #(
    .SH_NUM(SH_NUM),
    .LENGTH_WID(LENGTH_WID),
    .WEIGHT_WID(WEIGHT_WID)
) u_dwrr_sch(
    .clk              (clk              ),
    .rst              (rst              ),
    .sch_weight   (sch_weight   ),
    .sch_en       (sch_en       ),
    .sch_req      (sch_req      ),
    .sch_len      (sch_len      ),
    .sch_grant    (sch_grant    ),
    .sch_grant_vld(sch_grant_vld)
);


endmodule
