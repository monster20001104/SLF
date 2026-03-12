/******************************************************************************
 * 文件名称 : beq_rxq_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/01/08
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  01/08     Joe Jiang   初始化版本
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

 module beq_rxq_tb 
 import alt_tlp_adaptor_pkg::*;
 #(
    parameter CSR_ADDR_WIDTH= 64,
    parameter CSR_DATA_WIDTH= 64,  
    parameter FEQ_NUM       = 256,
    parameter FEQ_NUM_WIDTH = $clog2(FEQ_NUM),
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
    /////////////
    output                                      emu2beq_sav ,
    input      logic                            emu2beq_vld ,
    input      logic  [DATA_WIDTH-1:0]          emu2beq_data,
    input      logic  [EMPTH_WIDTH-1:0]         emu2beq_sty ,
    input      logic  [EMPTH_WIDTH-1:0]         emu2beq_mty ,
    input      logic                            emu2beq_sop ,
    input      logic                            emu2beq_eop ,
    input      logic  [$bits(beq_rxq_sbd_t)-1:0]emu2beq_sbd ,

    output                                      net2beq_sav ,
    input      logic                            net2beq_vld ,
    input      logic  [DATA_WIDTH-1:0]          net2beq_data,
    input      logic  [EMPTH_WIDTH-1:0]         net2beq_sty ,
    input      logic  [EMPTH_WIDTH-1:0]         net2beq_mty ,
    input      logic                            net2beq_sop ,
    input      logic                            net2beq_eop ,
    input      logic  [$bits(beq_rxq_sbd_t)-1:0]net2beq_sbd ,

    output                                      blk2beq_sav ,
    input      logic                            blk2beq_vld ,
    input      logic  [DATA_WIDTH-1:0]          blk2beq_data,
    input      logic  [EMPTH_WIDTH-1:0]         blk2beq_sty ,
    input      logic  [EMPTH_WIDTH-1:0]         blk2beq_mty ,
    input      logic                            blk2beq_sop ,
    input      logic                            blk2beq_eop ,
    input      logic  [$bits(beq_rxq_sbd_t)-1:0]blk2beq_sbd ,

    output                                      sgdma2beq_sav ,
    input      logic                            sgdma2beq_vld ,
    input      logic  [DATA_WIDTH-1:0]          sgdma2beq_data,
    input      logic  [EMPTH_WIDTH-1:0]         sgdma2beq_sty ,
    input      logic  [EMPTH_WIDTH-1:0]         sgdma2beq_mty ,
    input      logic                            sgdma2beq_sop ,
    input      logic                            sgdma2beq_eop ,
    input      logic  [$bits(beq_rxq_sbd_t)-1:0]sgdma2beq_sbd ,

    output logic [FEQ_NUM_WIDTH-1:0]            net_qid2bid_req_idx,
    output logic                                net_qid2bid_req_vld,
    input  logic [Q_WIDTH-1:0]                  net_qid2bid_rsp_dat,
    input  logic                                net_qid2bid_rsp_vld,

    output logic [FEQ_NUM_WIDTH-1:0]            blk_qid2bid_req_idx,
    output logic                                blk_qid2bid_req_vld,
    input  logic [Q_WIDTH-1:0]                  blk_qid2bid_rsp_dat,
    input  logic                                blk_qid2bid_rsp_vld,

    output logic [Q_WIDTH-1:0]                  drop_mode_req_qid,
    output logic                                drop_mode_req_vld,
    input  logic                                drop_mode_rsp_vld,
    input  logic                                drop_mode_rsp_dat,

    output logic [Q_WIDTH-1:0]                  segment_size_req_qid,
    output logic                                segment_size_req_vld,
    input  logic [$bits(beq_rx_segment_t)-1:0]  segment_size_rsp_dat,
    input  logic                                segment_size_rsp_vld,

    output logic                                rd_ndesc_req_vld,
    input  logic                                rd_ndesc_req_rdy,
    output logic [$bits(beq_rd_ndesc_req_t)-1:0]rd_ndesc_req_dat,

    output logic                                rd_ndesc_rsp_rdy,
    input  logic                                rd_ndesc_rsp_vld,
    input  logic [$bits(beq_rd_ndesc_rsp_t)-1:0]rd_ndesc_rsp_sbd,
    input  logic                                rd_ndesc_rsp_sop,
    input  logic                                rd_ndesc_rsp_eop,
    input  logic [$bits(beq_avail_desc_t)-1:0]  rd_ndesc_rsp_dat,
    input  logic [3:0]                          rd_ndesc_rsp_tag,
    input  logic                                rd_ndesc_rsp_err,

    // Write request interface from DMA core
    input      logic                            dma_data_wr_req_sav          ,// wr_req_val_i must de-assert within 3 cycles after de-assertion of wr_req_rdy_o
    output     logic                            dma_data_wr_req_val          ,// Request is taken when asserted
    output     logic                            dma_data_wr_req_sop          ,// Indicates first dataword
    output     logic                            dma_data_wr_req_eop          ,// Indicates last dataword
    output     logic  [DATA_WIDTH-1:0]          dma_data_wr_req_data         ,// Data to write to host in big endian format
    output     logic  [EMPTH_WIDTH-1:0]         dma_data_wr_req_sty          ,// Points to first valid payload byte. Valid when wr_req_sop_i=1
    output     logic  [EMPTH_WIDTH-1:0]         dma_data_wr_req_mty          ,// Number of unused bytes in last dataword. Valid when wr_req_eop_i=1
    output     logic  [$bits(desc_t)-1:0]       dma_data_wr_req_desc         ,// Descriptor for write. Valid when wr_req_sop_i=1
    // Write response interface from DMA core
    input  logic [111:0]                        dma_data_wr_rsp_rd2rsp_loop  ,
    input  logic                                dma_data_wr_rsp_val          ,

    output logic [Q_WIDTH-1:0]                  ring_ci_rd_req_qid,
    output logic                                ring_ci_rd_req_vld,
    input  logic [15:0]                         ring_ci_rd_rsp_dat,
    input  logic                                ring_ci_rd_rsp_vld,

    output logic                                ring_ci_wr_vld,
    output logic [Q_WIDTH-1:0]                  ring_ci_wr_qid,
    output logic [15:0]                         ring_ci_wr_dat,

    output logic [Q_WIDTH-1:0]                  err_info_rd_req_qid,
    output logic                                err_info_rd_req_vld,
    input  beq_err_info                         err_info_rd_rsp_dat,
    input  logic                                err_info_rd_rsp_vld,

    output logic [Q_WIDTH-1:0]                  err_info_wr_qid,
    output logic                                err_info_wr_vld,
    output beq_err_info                         err_info_wr_dat,

    output logic [Q_WIDTH:0]                    ring_info_rd_req_qid,
    output logic                                ring_info_rd_req_vld,
    input  logic [63:0]                         ring_info_rd_rsp_base_addr,
    input  logic [2:0]                          ring_info_rd_rsp_qdepth, //1:1024,2:2028,3:4096,4:8192
    input  logic                                ring_info_rd_rsp_vld,

    

    // Register Bus for rxq
    output logic                                csr_if_ready,
    input  logic                                csr_if_valid,
    input  logic                                csr_if_read,
    input  logic [CSR_ADDR_WIDTH-1:0]           csr_if_addr,
    input  logic [CSR_DATA_WIDTH-1:0]           csr_if_wdata,
    input  logic [CSR_DATA_WIDTH/8-1:0]         csr_if_wmask,
    output logic [CSR_DATA_WIDTH-1:0]           csr_if_rdata,
    output logic                                csr_if_rvalid,
    input  logic                                csr_if_rready
   
    //Register Bus
    //mlite_if.slave                                csr_if
    
 );
    logic [Q_WIDTH-1:0]                  mon_rxq_qid;
    logic                                mon_rxq_recv_a_pkt;
    logic                                mon_rxq_drop_a_pkt;

    initial begin
        $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
        $fsdbDumpvars(0, beq_rxq_tb, "+all");
        $fsdbDumpMDA();
    end

    logic [1:0] m_br_enable;
    logic [23:0] chn_addr;

    mlite_if #(.ADDR_WIDTH(CSR_ADDR_WIDTH), .DATA_WIDTH(CSR_DATA_WIDTH)) csr_if();
    mlite_if #(.ADDR_WIDTH(21), .DATA_WIDTH(CSR_DATA_WIDTH)) m_br_if[2]();

    assign csr_if_ready     = csr_if.ready;
    assign csr_if.valid     = csr_if_valid;
    assign csr_if.read      = csr_if_read;
    assign csr_if.addr      = csr_if_addr;
    assign csr_if.wdata     = csr_if_wdata;
    assign csr_if.wmask     = csr_if_wmask;
    assign csr_if_rdata     = csr_if.rdata;
    assign csr_if_rvalid    = csr_if.rvalid;
    assign csr_if.rready    = csr_if_rready;

    beq_rxq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))   user2beq_if[3:0]();
    tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))   dma_data_wr_req_if();
    tlp_adap_dma_wr_rsp_if                               dma_data_wr_rsp_if();

    assign dma_data_wr_req_if.sav            = dma_data_wr_req_sav;
    assign dma_data_wr_req_sop               = dma_data_wr_req_if.sop;
    assign dma_data_wr_req_eop               = dma_data_wr_req_if.eop;
    assign dma_data_wr_req_val               = dma_data_wr_req_if.vld;
    assign dma_data_wr_req_data              = dma_data_wr_req_if.data;
    assign dma_data_wr_req_sty               = dma_data_wr_req_if.sty;
    assign dma_data_wr_req_mty               = dma_data_wr_req_if.mty;
    clear_x #(.DW($bits(desc_t))) u_dma_data_wr_req_desc_clearx (.in(dma_data_wr_req_if.desc), .out(dma_data_wr_req_desc));
    assign dma_data_wr_rsp_if.vld            = dma_data_wr_rsp_val;
    assign dma_data_wr_rsp_if.rd2rsp_loop    = dma_data_wr_rsp_rd2rsp_loop;

    assign emu2beq_sav          = user2beq_if[0].sav;
    assign user2beq_if[0].vld   = emu2beq_vld;
    assign user2beq_if[0].sop   = emu2beq_sop;
    assign user2beq_if[0].eop   = emu2beq_eop;
    assign user2beq_if[0].sbd   = emu2beq_sbd;
    assign user2beq_if[0].sty   = emu2beq_sty;
    assign user2beq_if[0].mty   = emu2beq_mty;
    assign user2beq_if[0].data  = emu2beq_data;

    assign net2beq_sav          = user2beq_if[1].sav;
    assign user2beq_if[1].vld   = net2beq_vld;
    assign user2beq_if[1].sop   = net2beq_sop;
    assign user2beq_if[1].eop   = net2beq_eop;
    assign user2beq_if[1].sbd   = net2beq_sbd;
    assign user2beq_if[1].sty   = net2beq_sty;
    assign user2beq_if[1].mty   = net2beq_mty;
    assign user2beq_if[1].data  = net2beq_data;

    assign blk2beq_sav          = user2beq_if[2].sav;
    assign user2beq_if[2].vld   = blk2beq_vld;
    assign user2beq_if[2].sop   = blk2beq_sop;
    assign user2beq_if[2].eop   = blk2beq_eop;
    assign user2beq_if[2].sbd   = blk2beq_sbd;
    assign user2beq_if[2].sty   = blk2beq_sty;
    assign user2beq_if[2].mty   = blk2beq_mty;
    assign user2beq_if[2].data  = blk2beq_data;

    assign sgdma2beq_sav        = user2beq_if[3].sav;
    assign user2beq_if[3].vld   = sgdma2beq_vld;
    assign user2beq_if[3].sop   = sgdma2beq_sop;
    assign user2beq_if[3].eop   = sgdma2beq_eop;
    assign user2beq_if[3].sbd   = sgdma2beq_sbd;
    assign user2beq_if[3].sty   = sgdma2beq_sty;
    assign user2beq_if[3].mty   = sgdma2beq_mty;
    assign user2beq_if[3].data  = sgdma2beq_data;

beq_rxq #(
    .FEQ_NUM             (FEQ_NUM             ),
    .FEQ_NUM_WIDTH       (FEQ_NUM_WIDTH       ),
    .Q_NUM               (Q_NUM               ),
    .Q_WIDTH             (Q_WIDTH             ),
    .DATA_WIDTH          (DATA_WIDTH          ),
    .EMPTH_WIDTH         (EMPTH_WIDTH         ),
    .MAX_DESC_SIZE       (MAX_DESC_SIZE       ),
    .DESC_BUF_PER_Q      (DESC_BUF_PER_Q      ),
    .DESC_BUF_PER_Q_WIDTH(DESC_BUF_PER_Q_WIDTH)
)u_beq_rxq(
    .clk                (clk                ),
    .rst                (rst                ),
    .user2beq_if        (user2beq_if        ),
    .net_qid2bid_req_idx(net_qid2bid_req_idx),
    .net_qid2bid_req_vld(net_qid2bid_req_vld),
    .net_qid2bid_rsp_dat(net_qid2bid_rsp_dat),
    .blk_qid2bid_req_idx(blk_qid2bid_req_idx),
    .blk_qid2bid_req_vld(blk_qid2bid_req_vld),
    .blk_qid2bid_rsp_dat(blk_qid2bid_rsp_dat),
    .drop_mode_req_qid(drop_mode_req_qid),
    .drop_mode_req_vld(drop_mode_req_vld),
    .drop_mode_rsp_vld(drop_mode_rsp_vld),
    .drop_mode_rsp_dat(drop_mode_rsp_dat),
    .segment_size_req_qid(segment_size_req_qid),
    .segment_size_req_vld(segment_size_req_vld),
    .segment_size_rsp_dat(segment_size_rsp_dat),
    .segment_size_rsp_vld(segment_size_rsp_vld),
    .rd_ndesc_req_vld(rd_ndesc_req_vld),
    .rd_ndesc_req_rdy(rd_ndesc_req_rdy),
    .rd_ndesc_req_dat(rd_ndesc_req_dat),
    .rd_ndesc_rsp_rdy(rd_ndesc_rsp_rdy),
    .rd_ndesc_rsp_vld(rd_ndesc_rsp_vld),
    .rd_ndesc_rsp_sbd(rd_ndesc_rsp_sbd),
    .rd_ndesc_rsp_sop(rd_ndesc_rsp_sop),
    .rd_ndesc_rsp_eop(rd_ndesc_rsp_eop),
    .rd_ndesc_rsp_dat(rd_ndesc_rsp_dat),
    .rd_ndesc_rsp_tag(rd_ndesc_rsp_tag),
    .rd_ndesc_rsp_err(1'b0),
    .dma_data_wr_req_if(dma_data_wr_req_if),
    .dma_data_wr_rsp_if(dma_data_wr_rsp_if),
    .ring_ci_rd_req_qid(ring_ci_rd_req_qid),
    .ring_ci_rd_req_vld(ring_ci_rd_req_vld),
    .ring_ci_rd_rsp_dat(ring_ci_rd_rsp_dat),
    .ring_ci_rd_rsp_vld(ring_ci_rd_rsp_vld),
    .ring_ci_wr_vld(ring_ci_wr_vld),
    .ring_ci_wr_qid(ring_ci_wr_qid),
    .ring_ci_wr_dat(ring_ci_wr_dat),
    .err_info_rd_req_qid(err_info_rd_req_qid),
    .err_info_rd_req_vld(err_info_rd_req_vld),
    .err_info_rd_rsp_dat(err_info_rd_rsp_dat),
    .err_info_rd_rsp_vld(err_info_rd_rsp_vld),
    .err_info_wr_qid(err_info_wr_qid),
    .err_info_wr_vld(err_info_wr_vld),
    .err_info_wr_dat(err_info_wr_dat),
    .ring_info_rd_req_qid      (ring_info_rd_req_qid      ),  
    .ring_info_rd_req_vld      (ring_info_rd_req_vld      ),  
    .ring_info_rd_rsp_base_addr(ring_info_rd_rsp_base_addr),  
    .ring_info_rd_rsp_qdepth   (ring_info_rd_rsp_qdepth   ),  
    .ring_info_rd_rsp_vld      (ring_info_rd_rsp_vld      ),
    .mon_qid(mon_rxq_qid),
    .mon_recv_a_pkt(mon_rxq_recv_a_pkt),
    .mon_drop_a_pkt(mon_rxq_drop_a_pkt),
    .dfx_if(m_br_if[0])

);

beq_mon #(
    .Q_NUM        (Q_NUM        ),
    .Q_WIDTH      (Q_WIDTH      ),
    .DESC_BUF_PER_Q      (DESC_BUF_PER_Q      ),
    .DESC_BUF_PER_Q_WIDTH(DESC_BUF_PER_Q_WIDTH) 
 ) u_beq_mon (
    .clk                    (clk),
    .rst                    (rst),
    .mon_txq_qid            (0       ),
    .mon_txq_send_a_pkt     (0),
    .mon_rxq_qid            (mon_rxq_qid       ),
    .mon_rxq_recv_a_pkt     (mon_rxq_recv_a_pkt),
    .mon_rxq_drop_a_pkt     (mon_rxq_drop_a_pkt),
    .internal_ctx_rd_req_qid(),
    .internal_ctx_rd_req_vld(),
    .internal_ctx_rd_req_rdy(0),
    .internal_ctx_rd_rsp_dat(0),
    .internal_ctx_rd_rsp_vld(0),
    .csr_if                 (m_br_if[1]),
    .dfx_err                ()
 );

assign m_br_enable[0] = chn_addr[9:8] == 2'h0;   //rxq_dfx
assign m_br_enable[1] = chn_addr[9:8] == 2'h1;   //beq_mon

mlite_crossbar#(
    .CHN_NUM   (2   ), 
    .ADDR_WIDTH(24  ), 
    .DATA_WIDTH(64  )
)u_mlite_crossbar(
    .clk            (clk),
    .rst            (rst),
    .chn_enable     (m_br_enable),
    .slave          (csr_if),             
    .master         (m_br_if),   
    .chn_addr       (chn_addr)
);

    
 endmodule