/******************************************************************************
 * 文件名称 : rr_sch.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/07/26
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/26     Joe Jiang   初始化版本
 ******************************************************************************/
module rr_sch#(
  parameter SH_NUM = 8             
)(
  input                     clk           ,
  input                     rst           ,
  input [SH_NUM - 1 : 0]    sch_req       ,
  input                     sch_en        , 
  output[SH_NUM - 1 : 0]    sch_grant     , 
  output                    sch_grant_vld    
);
    wire  [SH_NUM - 1 : 0]   right_grant        ;
    wire  [SH_NUM - 1 : 0]   rr_req             ;
    wire  [SH_NUM - 1 : 0]   next_mask_ptr      ;
    reg   [SH_NUM - 1 : 0]   next_mask_ptr_ff1  ;
    wire  [SH_NUM - 1 : 0]   left_req           ;
    wire  [SH_NUM - 1 : 0]   left_grant         ;
    wire  [SH_NUM - 1 : 0]   right_mask         ;
    wire  [SH_NUM - 1 : 0]   left_mask          ;
 
assign sch_grant_vld        = sch_en == 1'b1 ? |sch_req : 1'b0         ;
assign rr_req        = sch_en == 1'b0 ? {SH_NUM{1'b0}} : sch_req;
assign left_req      = (next_mask_ptr_ff1) & rr_req           ; 
assign right_grant   = rr_req & (~(rr_req - 1'b1))            ;//找首1
assign left_grant    = left_req & (~(left_req - 1'b1))        ;//找首1
assign right_mask[0] = 1'b0                                   ;
assign left_mask[0]  = 1'b0                                   ;
 
genvar i;
generate
  for(i=1;i<SH_NUM;i=i+1)begin:MASK_GEN
    assign right_mask[i] = |rr_req[i-1:0]  ;
    assign left_mask[i]  = |left_req[i-1:0];
  end
endgenerate
 
assign sch_grant      = left_req == {SH_NUM{1'b0}} ? right_grant : left_grant;
assign next_mask_ptr = left_req == {SH_NUM{1'b0}} ? right_mask : left_mask  ;
 
always @(posedge clk)begin
  if(rst)begin
    next_mask_ptr_ff1 <= {SH_NUM{1'b0}};
  end else if(sch_grant_vld == 1'b1) begin
    next_mask_ptr_ff1 <= next_mask_ptr;
  end
end

endmodule