/******************************************************************************
 *              : virtio_idx_engine_tb.sv
 *              : Feilong Yun
 *              : 2025/06/23
 *              : 
 *
 *              : 
 *
 *                                                     
 * v1.0  06/23     Feilong Yun                  
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

module virtio_idx_engine_tb 
    import alt_tlp_adaptor_pkg::*;
    #(
    parameter DATA_WIDTH = 256,
    parameter EMPTH_WIDTH = $clog2(DATA_WIDTH/8)
 )(
    input                                       clk,
    input                                       rst,

    input                                       sch_req_vld,
    output                                      sch_req_rdy,
    input     [$bits(virtio_vq_t)-1:0]          sch_req_vq,

    output logic                                idx_eng_dma_rd_req_val,
    output logic  [EMPTH_WIDTH-1:0]             idx_eng_dma_rd_req_sty,
    output logic  [$bits(desc_t)-1:0]           idx_eng_dma_rd_req_desc,
    input  logic                                idx_eng_dma_rd_req_sav,

    input  logic                                idx_eng_dma_rd_rsp_val,
    input  logic                                idx_eng_dma_rd_rsp_sop,
    input  logic                                idx_eng_dma_rd_rsp_eop,
    input  logic                                idx_eng_dma_rd_rsp_err,
    input  logic [DATA_WIDTH-1:0]               idx_eng_dma_rd_rsp_data,
    input  logic [EMPTH_WIDTH-1:0]              idx_eng_dma_rd_rsp_sty,
    input  logic [EMPTH_WIDTH-1:0]              idx_eng_dma_rd_rsp_mty,
    input  logic [$bits(desc_t)-1:0]            idx_eng_dma_rd_rsp_desc,

    input  logic                                idx_eng_dma_wr_req_sav          ,// wr_req_val_i must de-assert within 3 cycles after de-assertion of wr_req_rdy_o
    output logic                                idx_eng_dma_wr_req_val          ,// Request is taken when asserted
    output logic                                idx_eng_dma_wr_req_sop          ,// Indicates first dataword
    output logic                                idx_eng_dma_wr_req_eop          ,// Indicates last dataword
    output logic  [DATA_WIDTH-1:0]              idx_eng_dma_wr_req_data         ,// Data to write to host in big endian format
    output logic  [EMPTH_WIDTH-1:0]             idx_eng_dma_wr_req_sty          ,// Points to first valid payload byte. Valid when wr_req_sop_i=1
    output logic  [EMPTH_WIDTH-1:0]             idx_eng_dma_wr_req_mty          ,// Number of unused bytes in last dataword. Valid when wr_req_eop_i=1
    output logic  [$bits(desc_t)-1:0]           idx_eng_dma_wr_req_desc         ,// Descriptor for write. Valid when wr_req_sop_i=1
    
    input  logic [103:0]                        idx_eng_dma_wr_rsp_rd2rsp_loop  ,
    input  logic                                idx_eng_dma_wr_rsp_val          ,

    output logic                                idx_notify_vld,
    output logic [$bits(virtio_vq_t)-1:0]       idx_notify_vq,
    input  logic                                idx_notify_rdy,

    output logic                                err_code_wr_req_vld,
    output logic [$bits(virtio_vq_t)-1:0]       err_code_wr_req_vq,
    output logic [$bits(virtio_err_info_t)-1:0] err_code_wr_req_data,
    input  logic                                err_code_wr_req_rdy,

    output logic                             idx_engine_ctx_rd_req_vld,
    output logic [$bits(virtio_vq_t)-1:0]    idx_engine_ctx_rd_req_vq,
    input  logic                             idx_engine_ctx_rd_rsp_vld,
    input  logic [9:0]                       idx_engine_ctx_rd_rsp_dev_id,
    input  logic [15:0]                      idx_engine_ctx_rd_rsp_bdf,
    input  logic [63:0]                      idx_engine_ctx_rd_rsp_avail_addr,
    input  logic [63:0]                      idx_engine_ctx_rd_rsp_used_addr,
    input  logic [3:0]                       idx_engine_ctx_rd_rsp_qdepth,
    input  logic [$bits(virtio_qstat_t)-1:0] idx_engine_ctx_rd_rsp_ctrl,
    input  logic                             idx_engine_ctx_rd_rsp_force_shutdown,
    input  logic [15:0]                      idx_engine_ctx_rd_rsp_avail_idx,
    input  logic [15:0]                      idx_engine_ctx_rd_rsp_avail_ui,
    input  logic                             idx_engine_ctx_rd_rsp_no_notify,
    input  logic [6:0]                       idx_engine_ctx_rd_rsp_dma_req_num,
    input  logic [6:0]                       idx_engine_ctx_rd_rsp_dma_rsp_num,

    output logic                             idx_engine_ctx_wr_vld,
    output logic [$bits(virtio_vq_t)-1:0]    idx_engine_ctx_wr_vq,
    output logic [15:0]                      idx_engine_ctx_wr_avail_idx,
    output logic                             idx_engine_ctx_wr_no_notify,
    output logic [6:0]                       idx_engine_ctx_wr_dma_req_num,
    output logic [6:0]                       idx_engine_ctx_wr_dma_rsp_num
 );


   logic                        notify_req_vld;
   logic                        notify_req_rdy;
   logic [$bits(virtio_vq_t)-1:0] notify_req_vq;

   logic                        notify_rsp_vld;
   logic                        notify_rsp_rdy;
   logic                        notify_rsp_cold;
   logic                        notify_rsp_done;
   logic [$bits(virtio_vq_t)-1:0]notify_rsp_vq;

mlite_if #(.ADDR_WIDTH (12), .DATA_WIDTH (64), .CHANNEL_NUM(1))   mlite_master();
tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))   idx_eng_dma_wr_req();
tlp_adap_dma_wr_rsp_if                               idx_eng_dma_wr_rsp();
tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))   idx_eng_dma_rd_req();
tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))   idx_eng_dma_rd_rsp();


assign idx_eng_dma_wr_req.sav               = idx_eng_dma_wr_req_sav;
assign idx_eng_dma_wr_req_sop               = idx_eng_dma_wr_req.sop;
assign idx_eng_dma_wr_req_eop               = idx_eng_dma_wr_req.eop;
assign idx_eng_dma_wr_req_val               = idx_eng_dma_wr_req.vld;
assign idx_eng_dma_wr_req_data              = idx_eng_dma_wr_req.data;
assign idx_eng_dma_wr_req_sty               = idx_eng_dma_wr_req.sty;
assign idx_eng_dma_wr_req_mty               = idx_eng_dma_wr_req.mty;
clear_x #(.DW($bits(desc_t))) u_idx_eng_dma_wr_req_desc_clearx (.in(idx_eng_dma_wr_req.desc), .out(idx_eng_dma_wr_req_desc));

assign idx_eng_dma_wr_rsp.vld               = idx_eng_dma_wr_rsp_val;
assign idx_eng_dma_wr_rsp.rd2rsp_loop       = idx_eng_dma_wr_rsp_rd2rsp_loop;

assign idx_eng_dma_rd_req.sav               = idx_eng_dma_rd_req_sav;
assign idx_eng_dma_rd_req_val               = idx_eng_dma_rd_req.vld;
assign idx_eng_dma_rd_req_sty               = idx_eng_dma_rd_req.sty;
clear_x #(.DW($bits(desc_t))) u_idx_eng_dma_rd_req_desc_clearx (.in(idx_eng_dma_rd_req.desc), .out(idx_eng_dma_rd_req_desc));
assign idx_eng_dma_rd_rsp.vld               = idx_eng_dma_rd_rsp_val;
assign idx_eng_dma_rd_rsp.sop               = idx_eng_dma_rd_rsp_sop;
assign idx_eng_dma_rd_rsp.eop               = idx_eng_dma_rd_rsp_eop;
assign idx_eng_dma_rd_rsp.sty               = idx_eng_dma_rd_rsp_sty;
assign idx_eng_dma_rd_rsp.mty               = idx_eng_dma_rd_rsp_mty;
assign idx_eng_dma_rd_rsp.data              = idx_eng_dma_rd_rsp_data;
assign idx_eng_dma_rd_rsp.err               = idx_eng_dma_rd_rsp_err;
assign idx_eng_dma_rd_rsp.desc              = idx_eng_dma_rd_rsp_desc;

  virtio_sch #(
    .WEIGHT_WIDTH(4                     ),
    .VQ_WIDTH    ($bits(virtio_vq_t)    )
) u_virtio_avail_sch (
    .clk            (clk            ),
    .rst            (rst            ),
    .sch_req_vld    (sch_req_vld    ),
    .sch_req_rdy    (sch_req_rdy    ),
    .sch_req_qid    (sch_req_vq     ),
    .notify_req_vld (notify_req_vld ),
    .notify_req_rdy (notify_req_rdy ),
    .notify_req_qid (notify_req_vq ),
    .notify_rsp_vld (notify_rsp_vld ),
    .notify_rsp_rdy (notify_rsp_rdy ),
    .notify_rsp_qid (notify_rsp_vq ),
    .notify_rsp_done(notify_rsp_done),
    .notify_rsp_cold(notify_rsp_cold),
    .hot_weight     (4'h5),
    .cold_weight    (4'h2),
    .dfx_err        (),
    .dfx_status     (),
    .notify_req_cnt (),
    .notify_rsp_cnt ()
);


virtio_idx_engine_top #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .EMPTH_WIDTH ( EMPTH_WIDTH )
)u_virtio_idx_engine_top(   
    .clk                                    ( clk                                 ),
    .rst                                    ( rst                                 ),
    .notify_req_vld                         ( notify_req_vld                      ),
    .notify_req_rdy                         ( notify_req_rdy                      ),
    .notify_req_vq                          ( notify_req_vq                       ),
    .notify_rsp_vld                         ( notify_rsp_vld                      ),
    .notify_rsp_rdy                         ( notify_rsp_rdy                      ),
    .notify_rsp_cold                        ( notify_rsp_cold                     ),
    .notify_rsp_done                        ( notify_rsp_done                     ),
    .notify_rsp_vq                          ( notify_rsp_vq                       ),
    .idx_eng_dma_rd_req                     ( idx_eng_dma_rd_req                  ),
    .idx_eng_dma_rd_rsp                     ( idx_eng_dma_rd_rsp                  ),
    .idx_eng_dma_wr_req                     ( idx_eng_dma_wr_req                  ),
    .idx_eng_dma_wr_rsp                     ( idx_eng_dma_wr_rsp                  ),
    .idx_notify_vld                         ( idx_notify_vld                      ),
    .idx_notify_vq                          ( idx_notify_vq                       ),
    .idx_notify_rdy                         ( idx_notify_rdy                      ),
    .err_code_wr_req_vld                    ( err_code_wr_req_vld                 ),
    .err_code_wr_req_data                   ( err_code_wr_req_data                ),
    .err_code_wr_req_vq                     ( err_code_wr_req_vq                  ),
    .err_code_wr_req_rdy                    ( err_code_wr_req_rdy                 ),
    .idx_engine_ctx_rd_req_vld              ( idx_engine_ctx_rd_req_vld           ),
    .idx_engine_ctx_rd_req_vq               ( idx_engine_ctx_rd_req_vq            ),
    .idx_engine_ctx_rd_rsp_vld              ( idx_engine_ctx_rd_rsp_vld           ),
    .idx_engine_ctx_rd_rsp_dev_id           ( idx_engine_ctx_rd_rsp_dev_id        ),
    .idx_engine_ctx_rd_rsp_bdf              ( idx_engine_ctx_rd_rsp_bdf           ),
    .idx_engine_ctx_rd_rsp_avail_addr       ( idx_engine_ctx_rd_rsp_avail_addr    ),
    .idx_engine_ctx_rd_rsp_used_addr        ( idx_engine_ctx_rd_rsp_used_addr     ),
    .idx_engine_ctx_rd_rsp_qdepth           ( idx_engine_ctx_rd_rsp_qdepth        ),
    .idx_engine_ctx_rd_rsp_ctrl             ( idx_engine_ctx_rd_rsp_ctrl          ),
    .idx_engine_ctx_rd_rsp_force_shutdown   ( idx_engine_ctx_rd_rsp_force_shutdown),
    .idx_engine_ctx_rd_rsp_avail_idx        ( idx_engine_ctx_rd_rsp_avail_idx     ),
    .idx_engine_ctx_rd_rsp_avail_ui         ( idx_engine_ctx_rd_rsp_avail_ui      ),
    .idx_engine_ctx_rd_rsp_no_notify        ( idx_engine_ctx_rd_rsp_no_notify     ),
    .idx_engine_ctx_rd_rsp_no_change        ( idx_engine_ctx_rd_rsp_no_change     ),
    .idx_engine_ctx_rd_rsp_dma_req_num      ( idx_engine_ctx_rd_rsp_dma_req_num   ),
    .idx_engine_ctx_rd_rsp_dma_rsp_num      ( idx_engine_ctx_rd_rsp_dma_rsp_num   ),
    .idx_engine_ctx_wr_vld                  ( idx_engine_ctx_wr_vld               ),
    .idx_engine_ctx_wr_vq                   ( idx_engine_ctx_wr_vq                ),
    .idx_engine_ctx_wr_avail_idx            ( idx_engine_ctx_wr_avail_idx         ),
    .idx_engine_ctx_wr_no_notify            ( idx_engine_ctx_wr_no_notify         ),
    .idx_engine_ctx_wr_no_change            ( idx_engine_ctx_wr_no_change         ),
    .idx_engine_ctx_wr_dma_req_num          ( idx_engine_ctx_wr_dma_req_num       ),
    .idx_engine_ctx_wr_dma_rsp_num          ( idx_engine_ctx_wr_dma_rsp_num       ),
    .dfx_slave                              ( mlite_master                        )
 );


    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, virtio_idx_engine_tb, "+all");
        $fsdbDumpMDA();
    end

endmodule
