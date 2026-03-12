/******************************************************************************
 * 文件名称 : beq_desc_eng_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/11/29
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  11/29     Joe Jiang   初始化版本
 ******************************************************************************/
`include "tlp_adap_dma_if.svh"

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

module beq_desc_eng_tb 
import alt_tlp_adaptor_pkg::*;
#(
    parameter REG_ADDR_WIDTH    = 12,
    parameter REG_DATA_WIDTH    = 64,
    parameter Q_NUM         = 64,
    parameter Q_WIDTH       = $clog2(Q_NUM),
    parameter DATA_WIDTH    = 512,
    parameter EMPTH_WIDTH   = $clog2(DATA_WIDTH/8),
    parameter MAX_DESC_SIZE = 8192,
    parameter DESC_BUF_PER_Q = 32,
    parameter DESC_BUF_PER_Q_WIDTH = $clog2(DESC_BUF_PER_Q)
) (
    input                                       clk,
    input                                       rst,
    //db_notify         
    input  logic                                db_notify_req_vld,
    output logic                                db_notify_req_rdy,
    input  logic [Q_WIDTH:0]                    db_notify_req_dat, //{qid, is_txq}

    output logic                                db_notify_rsp_vld,
    input  logic                                db_notify_rsp_rdy,
    output logic [$bits(beq_rr_sch_notify_rsp_t)-1:0] db_notify_rsp_dat,
    //rd_ndesc from txq&rxq //0 rxq 1 txq
    input  logic                                rxq_rd_ndesc_req_vld ,
    output logic                                rxq_rd_ndesc_req_rdy ,
    input  logic [$bits(beq_rd_ndesc_req_t)-1:0]                    rxq_rd_ndesc_req_dat ,

    input  logic                                txq_rd_ndesc_req_vld ,
    output logic                                txq_rd_ndesc_req_rdy ,
    input  logic [$bits(beq_rd_ndesc_req_t)-1:0]                    txq_rd_ndesc_req_dat ,

    input  logic                                rxq_rd_ndesc_rsp_rdy ,
    output logic                                rxq_rd_ndesc_rsp_vld ,
    output logic [$bits(beq_rd_ndesc_rsp_t)-1:0]                   rxq_rd_ndesc_rsp_sbd ,
    output logic                                rxq_rd_ndesc_rsp_sop ,
    output logic                                rxq_rd_ndesc_rsp_eop ,
    output logic [$bits(beq_avail_desc_t)-1:0]                     rxq_rd_ndesc_rsp_dat ,

    input  logic                                txq_rd_ndesc_rsp_rdy    ,
    output logic                                txq_rd_ndesc_rsp_vld    ,
    output logic [$bits(beq_rd_ndesc_rsp_t)-1:0]                   txq_rd_ndesc_rsp_sbd    ,
    output logic                                txq_rd_ndesc_rsp_sop    ,
    output logic                                txq_rd_ndesc_rsp_eop    ,
    output logic [$bits(beq_avail_desc_t)-1:0]                     txq_rd_ndesc_rsp_dat    ,

    output logic                                new_chain_notify_vld,
    input  logic                                new_chain_notify_rdy,
    output logic [$bits(beq_wrr_sch_notify_t)-1:0]                 new_chain_notify_dat,

    // Read request interface from DMA core
    input      logic                            dma_desc_rd_req_sav  ,
    output     logic                            dma_desc_rd_req_val  ,
    output     logic  [EMPTH_WIDTH-1:0]         dma_desc_rd_req_sty  ,
    output     logic  [$bits(desc_t)-1:0]       dma_desc_rd_req_desc ,
    // Read response interface back to DMA core
    input      logic                            dma_desc_rd_rsp_val  ,
    input      logic                            dma_desc_rd_rsp_sop  ,
    input      logic                            dma_desc_rd_rsp_eop  ,
    input      logic                            dma_desc_rd_rsp_err  ,
    input      logic  [DATA_WIDTH-1:0]          dma_desc_rd_rsp_data ,
    input      logic  [EMPTH_WIDTH-1:0]         dma_desc_rd_rsp_sty  ,
    input      logic  [EMPTH_WIDTH-1:0]         dma_desc_rd_rsp_mty  ,
    input      logic  [$bits(desc_t)-1:0]       dma_desc_rd_rsp_desc ,

    output logic [Q_WIDTH:0]                    ring_info_rd_req_qid,
    output logic                                ring_info_rd_req_vld,

    input  logic [63:0]                         ring_info_rd_rsp_base_addr,
    input  logic [2:0]                          ring_info_rd_rsp_qdepth, //1:1024,2:2028,3:4096,4:8192
    input  logic                                ring_info_rd_rsp_vld,

    output logic                                txq_transfer_type_rd_req_vld,
    output logic [Q_WIDTH-1:0]                  txq_transfer_type_rd_req_qid,
    input  [$bits(beq_transfer_type_t)-1:0]     txq_transfer_type_rd_rsp_dat,
    input  logic                                txq_transfer_type_rd_rsp_vld,

    output logic                                rxq_transfer_type_rd_req_vld,
    output logic [Q_WIDTH-1:0]                  rxq_transfer_type_rd_req_qid,
    input  [$bits(beq_transfer_type_t)-1:0]     rxq_transfer_type_rd_rsp_dat,
    input  logic                                rxq_transfer_type_rd_rsp_vld,

    output logic                                ring_db_idx_rd_req_vld,
    output logic [Q_WIDTH:0]                    ring_db_idx_rd_req_qid,
    input  logic [15:0]                         ring_db_idx_rd_rsp_dat,
    input  logic                                ring_db_idx_rd_rsp_vld,

    output logic                                ring_pi_rd_req_vld,
    output logic [Q_WIDTH:0]                    ring_pi_rd_req_qid,
    input  logic [15:0]                         ring_pi_rd_rsp_dat,
    input  logic                                ring_pi_rd_rsp_vld,

    output logic                                ring_pi_wr_vld,
    output logic [Q_WIDTH:0]                    ring_pi_wr_qid,
    output logic [15:0]                         ring_pi_wr_dat,


    output logic                                ring_ci_rd_req_vld,
    output logic [Q_WIDTH:0]                    ring_ci_rd_req_qid,
    input  logic [15:0]                         ring_ci_rd_rsp_dat,
    input  logic                                ring_ci_rd_rsp_vld,

    input                                       qstatus_wr_vld,
    input  logic [Q_WIDTH:0]                    qstatus_wr_qid,
    input  logic [$bits(beq_status_type_t)-1:0] qstatus_wr_dat,
    output logic                                qstatus_wr_rdy,

    input  logic  [Q_WIDTH:0]                   q_stop_req_qid,
    input  logic                                q_stop_req_vld,
    output logic                                q_stop_req_rdy,
    output logic                                q_stop_rsp_dat,
    output logic                                q_stop_rsp_vld,

            // Register Bus
    output logic                                dfx_if_ready,
    input  logic                                dfx_if_valid,
    input  logic                                dfx_if_read,
    input  logic [REG_ADDR_WIDTH-1:0]               dfx_if_addr,
    input  logic [REG_DATA_WIDTH-1:0]               dfx_if_wdata,
    input  logic [REG_DATA_WIDTH/8-1:0]             dfx_if_wmask,
    output logic [REG_DATA_WIDTH-1:0]               dfx_if_rdata,
    output logic                                dfx_if_rvalid,
    input  logic                                dfx_if_rready
);

initial begin
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
    $fsdbDumpvars(0, beq_desc_eng_tb, "+all");
    $fsdbDumpMDA();
end

tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_desc_rd_req_if();
tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_desc_rd_rsp_if();

logic                                rd_ndesc_req_vld_tmp [1:0];
logic                                rd_ndesc_req_rdy_tmp [1:0];
beq_rd_ndesc_req_t                   rd_ndesc_req_dat_tmp [1:0];
logic                                rd_ndesc_rsp_rdy_tmp [1:0];
logic                                rd_ndesc_rsp_vld_tmp [1:0];
beq_rd_ndesc_rsp_t                   rd_ndesc_rsp_sbd_tmp [1:0];
logic                                rd_ndesc_rsp_sop_tmp [1:0];
logic                                rd_ndesc_rsp_eop_tmp [1:0];
beq_avail_desc_t                     rd_ndesc_rsp_dat_tmp [1:0];

logic                                   transfer_type_rd_req_vld_tmp[1:0];
logic [Q_WIDTH-1:0]                     transfer_type_rd_req_qid_tmp[1:0];
logic [$bits(beq_transfer_type_t)-1:0]  transfer_type_rd_rsp_dat_tmp[1:0];
logic                                   transfer_type_rd_rsp_vld_tmp[1:0];

   mlite_if #(.ADDR_WIDTH(REG_ADDR_WIDTH), .DATA_WIDTH(REG_DATA_WIDTH)) dfx_if();


  assign rxq_transfer_type_rd_req_vld = transfer_type_rd_req_vld_tmp[0];
  assign rxq_transfer_type_rd_req_qid = transfer_type_rd_req_qid_tmp[0];
  assign transfer_type_rd_rsp_dat_tmp[0] = rxq_transfer_type_rd_rsp_dat;
  assign transfer_type_rd_rsp_vld_tmp[0] = rxq_transfer_type_rd_rsp_vld;

  assign txq_transfer_type_rd_req_vld = transfer_type_rd_req_vld_tmp[1];
  assign txq_transfer_type_rd_req_qid = transfer_type_rd_req_qid_tmp[1];
  assign transfer_type_rd_rsp_dat_tmp[1] = txq_transfer_type_rd_rsp_dat;
  assign transfer_type_rd_rsp_vld_tmp[1] = txq_transfer_type_rd_rsp_vld;


   assign dfx_if_ready     = dfx_if.ready;
   assign dfx_if.valid     = dfx_if_valid;
   assign dfx_if.read      = dfx_if_read;
   assign dfx_if.addr      = dfx_if_addr;
   assign dfx_if.wdata     = dfx_if_wdata;
   assign dfx_if.wmask     = dfx_if_wmask;
   assign dfx_if_rdata     = dfx_if.rdata;
   assign dfx_if_rvalid    = dfx_if.rvalid;
   assign dfx_if.rready    = dfx_if_rready;

assign dma_desc_rd_req_if.sav            = dma_desc_rd_req_sav;
assign dma_desc_rd_req_val               = dma_desc_rd_req_if.vld;
assign dma_desc_rd_req_sty               = dma_desc_rd_req_if.sty;
assign dma_desc_rd_req_desc              = dma_desc_rd_req_if.desc;

assign dma_desc_rd_rsp_if.vld            = dma_desc_rd_rsp_val;
assign dma_desc_rd_rsp_if.sop            = dma_desc_rd_rsp_sop;
assign dma_desc_rd_rsp_if.eop            = dma_desc_rd_rsp_eop;
assign dma_desc_rd_rsp_if.sty            = dma_desc_rd_rsp_sty;
assign dma_desc_rd_rsp_if.mty            = dma_desc_rd_rsp_mty;
assign dma_desc_rd_rsp_if.data           = dma_desc_rd_rsp_data;
assign dma_desc_rd_rsp_if.err            = dma_desc_rd_rsp_err;
assign dma_desc_rd_rsp_if.desc           = dma_desc_rd_rsp_desc;

assign rd_ndesc_req_vld_tmp[0] = rxq_rd_ndesc_req_vld;
assign rd_ndesc_req_vld_tmp[1] = txq_rd_ndesc_req_vld;

assign rxq_rd_ndesc_req_rdy = rd_ndesc_req_rdy_tmp[0];
assign txq_rd_ndesc_req_rdy = rd_ndesc_req_rdy_tmp[1];

assign rd_ndesc_req_dat_tmp[0] = rxq_rd_ndesc_req_dat;
assign rd_ndesc_req_dat_tmp[1] = txq_rd_ndesc_req_dat;

assign  rd_ndesc_rsp_rdy_tmp[0] = rxq_rd_ndesc_rsp_rdy;
assign  rd_ndesc_rsp_rdy_tmp[1] = txq_rd_ndesc_rsp_rdy;

clear_x #(.DW($bits(beq_avail_desc_t))) u_rxq_rd_ndesc_rsp_dat_clearx (.in(rd_ndesc_rsp_dat_tmp[0]), .out(rxq_rd_ndesc_rsp_dat));
clear_x #(.DW($bits(beq_avail_desc_t))) u_txq_rd_ndesc_rsp_dat_clearx (.in(rd_ndesc_rsp_dat_tmp[1]), .out(txq_rd_ndesc_rsp_dat));


assign  rxq_rd_ndesc_rsp_vld= rd_ndesc_rsp_vld_tmp[0];
assign  txq_rd_ndesc_rsp_vld= rd_ndesc_rsp_vld_tmp[1];
assign  rxq_rd_ndesc_rsp_sbd= rd_ndesc_rsp_sbd_tmp[0];
assign  txq_rd_ndesc_rsp_sbd= rd_ndesc_rsp_sbd_tmp[1];
assign  rxq_rd_ndesc_rsp_sop= rd_ndesc_rsp_sop_tmp[0];
assign  txq_rd_ndesc_rsp_sop= rd_ndesc_rsp_sop_tmp[1];
assign  rxq_rd_ndesc_rsp_eop= rd_ndesc_rsp_eop_tmp[0];
assign  txq_rd_ndesc_rsp_eop= rd_ndesc_rsp_eop_tmp[1];
//assign  rxq_rd_ndesc_rsp_dat= rd_ndesc_rsp_dat_tmp[0];
//assign  txq_rd_ndesc_rsp_dat= rd_ndesc_rsp_dat_tmp[1];

beq_desc_engine #(
    .Q_NUM               (Q_NUM               ),
    .Q_WIDTH             (Q_WIDTH             ),
    .DATA_WIDTH          (DATA_WIDTH          ),
    .EMPTH_WIDTH         (EMPTH_WIDTH         ),
    .MAX_DESC_SIZE       (MAX_DESC_SIZE       ),
    .DESC_BUF_PER_Q      (DESC_BUF_PER_Q      ),
    .DESC_BUF_PER_Q_WIDTH(DESC_BUF_PER_Q_WIDTH)
) u_beq_desc_engine (
        .clk                        (clk                        ),
        .rst                        (rst                        ),
        .db_notify_req_vld          (db_notify_req_vld          ),
        .db_notify_req_rdy          (db_notify_req_rdy          ),
        .db_notify_req_dat          (db_notify_req_dat          ), //{qid, is_txq}
        .db_notify_rsp_vld          (db_notify_rsp_vld          ),
        .db_notify_rsp_rdy          (db_notify_rsp_rdy          ),
        .db_notify_rsp_dat          (db_notify_rsp_dat          ),
        .rd_ndesc_req_vld           (rd_ndesc_req_vld_tmp       ),
        .rd_ndesc_req_rdy           (rd_ndesc_req_rdy_tmp       ),
        .rd_ndesc_req_dat           (rd_ndesc_req_dat_tmp       ),
        .rd_ndesc_rsp_rdy           (rd_ndesc_rsp_rdy_tmp       ),
        .rd_ndesc_rsp_vld           (rd_ndesc_rsp_vld_tmp       ),
        .rd_ndesc_rsp_sbd           (rd_ndesc_rsp_sbd_tmp       ),
        .rd_ndesc_rsp_sop           (rd_ndesc_rsp_sop_tmp       ),
        .rd_ndesc_rsp_eop           (rd_ndesc_rsp_eop_tmp       ),
        .rd_ndesc_rsp_dat           (rd_ndesc_rsp_dat_tmp       ),
        .new_chain_notify_vld       (new_chain_notify_vld       ),
        .new_chain_notify_rdy       (new_chain_notify_rdy       ),
        .new_chain_notify_dat       (new_chain_notify_dat       ),
        .dma_desc_rd_req_if         (dma_desc_rd_req_if         ),
        .dma_desc_rd_rsp_if         (dma_desc_rd_rsp_if         ),
        .ring_info_rd_req_qid       (ring_info_rd_req_qid       ),
        .ring_info_rd_req_vld       (ring_info_rd_req_vld       ),
        .ring_info_rd_rsp_base_addr (ring_info_rd_rsp_base_addr ),
        .ring_info_rd_rsp_qdepth    (ring_info_rd_rsp_qdepth    ), 
        .ring_info_rd_rsp_vld       (ring_info_rd_rsp_vld       ),
        .transfer_type_rd_req_vld   (transfer_type_rd_req_vld_tmp   ),
        .transfer_type_rd_req_qid   (transfer_type_rd_req_qid_tmp   ),
        .transfer_type_rd_rsp_dat   (transfer_type_rd_rsp_dat_tmp   ),
        .transfer_type_rd_rsp_vld   (transfer_type_rd_rsp_vld_tmp   ),
        .ring_db_idx_rd_req_vld     (ring_db_idx_rd_req_vld     ),
        .ring_db_idx_rd_req_qid     (ring_db_idx_rd_req_qid     ),
        .ring_db_idx_rd_rsp_dat     (ring_db_idx_rd_rsp_dat     ),
        .ring_db_idx_rd_rsp_vld     (ring_db_idx_rd_rsp_vld     ),
        .ring_pi_rd_req_vld         (ring_pi_rd_req_vld         ),
        .ring_pi_rd_req_qid         (ring_pi_rd_req_qid         ),
        .ring_pi_rd_rsp_dat         (ring_pi_rd_rsp_dat         ),
        .ring_pi_rd_rsp_vld         (ring_pi_rd_rsp_vld         ),
        .ring_pi_wr_vld             (ring_pi_wr_vld             ),
        .ring_pi_wr_qid             (ring_pi_wr_qid             ),
        .ring_pi_wr_dat             (ring_pi_wr_dat             ),
        .ring_ci_rd_req_vld         (ring_ci_rd_req_vld         ),
        .ring_ci_rd_req_qid         (ring_ci_rd_req_qid         ),
        .ring_ci_rd_rsp_dat         (ring_ci_rd_rsp_dat         ),
        .ring_ci_rd_rsp_vld         (ring_ci_rd_rsp_vld         ),
        .qstatus_wr_vld             (qstatus_wr_vld             ),
        .qstatus_wr_qid             (qstatus_wr_qid             ),
        .qstatus_wr_dat             (qstatus_wr_dat             ),
        .internal_ctx_rd_req_qid    ('h0),
        .internal_ctx_rd_req_vld    ('h0),
        .internal_ctx_rd_req_rdy    (),
        .internal_ctx_rd_rsp_dat    (),
        .internal_ctx_rd_rsp_vld    (),
        .qstatus_wr_rdy             (qstatus_wr_rdy             ),
        .q_stop_req_qid             (q_stop_req_qid             ),
        .q_stop_req_vld             (q_stop_req_vld             ),
        .q_stop_req_rdy             (q_stop_req_rdy             ),
        .q_stop_rsp_dat             (q_stop_rsp_dat             ),
        .q_stop_rsp_vld             (q_stop_rsp_vld             ),
        .dfx_if                     (dfx_if                     )
 );
    
endmodule