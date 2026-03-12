/******************************************************************************
 * 文件名称 : beq_feq2bid_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/11/20
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  11/20     Joe Jiang   初始化版本
 ******************************************************************************/
 module beq_feq2bid_tb #(
    parameter ADDR_WIDTH    = 21,
    parameter DATA_WIDTH    = 64,
    parameter FEQ_NUM       = 256,
    parameter FEQ_NUM_WIDTH = $clog2(FEQ_NUM),
    parameter Q_NUM         = 64,
    parameter Q_WIDTH       = $clog2(Q_NUM)
 )(
    input                                       clk,
    input                                       rst,

    input  logic [FEQ_NUM_WIDTH-1:0]            net_qid2bid_req_idx,
    input  logic                                net_qid2bid_req_vld,
    output logic [Q_WIDTH-1:0]                  net_qid2bid_rsp_dat,
    output logic                                net_qid2bid_rsp_vld,
    input  logic [FEQ_NUM_WIDTH-1:0]            blk_qid2bid_req_idx,
    input  logic                                blk_qid2bid_req_vld,
    output logic [Q_WIDTH-1:0]                  blk_qid2bid_rsp_dat,
    output logic                                blk_qid2bid_rsp_vld,

        // Register Bus
    output logic                                csr_if_ready,
    input  logic                                csr_if_valid,
    input  logic                                csr_if_read,
    input  logic [ADDR_WIDTH-1:0]               csr_if_addr,
    input  logic [DATA_WIDTH-1:0]               csr_if_wdata,
    input  logic [DATA_WIDTH/8-1:0]             csr_if_wmask,
    output logic [DATA_WIDTH-1:0]               csr_if_rdata,
    output logic                                csr_if_rvalid,
    input  logic                                csr_if_rready
    
 );

   initial begin
        $fsdbDumpfile("top.fsdb");
        $fsdbDumpvars(0, beq_feq2bid_tb, "+all");
        $fsdbDumpMDA();
   end

   mlite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) csr_if();

   assign csr_if_ready     = csr_if.ready;
   assign csr_if.valid     = csr_if_valid;
   assign csr_if.read      = csr_if_read;
   assign csr_if.addr      = csr_if_addr;
   assign csr_if.wdata     = csr_if_wdata;
   assign csr_if.wmask     = csr_if_wmask;
   assign csr_if_rdata     = csr_if.rdata;
   assign csr_if_rvalid    = csr_if.rvalid;
   assign csr_if.rready    = csr_if_rready;

beq_feq2bid #(
    .FEQ_NUM      (FEQ_NUM      ),
    .FEQ_NUM_WIDTH(FEQ_NUM_WIDTH),
    .Q_NUM        (Q_NUM        ),
    .Q_WIDTH      (Q_WIDTH      )
) u_beq_feq2bid (
    .clk                (clk                ),
    .rst                (rst                ),
    .net_qid2bid_req_idx(net_qid2bid_req_idx),
    .net_qid2bid_req_vld(net_qid2bid_req_vld),
    .net_qid2bid_rsp_dat(net_qid2bid_rsp_dat),
    .net_qid2bid_rsp_vld(net_qid2bid_rsp_vld),
    .blk_qid2bid_req_idx(blk_qid2bid_req_idx),
    .blk_qid2bid_req_vld(blk_qid2bid_req_vld),
    .blk_qid2bid_rsp_dat(blk_qid2bid_rsp_dat),
    .blk_qid2bid_rsp_vld(blk_qid2bid_rsp_vld),
    .csr_if             (csr_if             )
);
    
 endmodule