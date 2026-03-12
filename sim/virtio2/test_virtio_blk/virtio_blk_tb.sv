/******************************************************************************
 * 文件名称 : virtio_net_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/09/09
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  09/09     Joe Jiang   初始化版本
 ******************************************************************************/
 `include "tlp_adap_dma_if.svh"
 `include "virtio_define.svh"
 `include "virtio_desc_engine_define.svh"
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
 
 module virtio_blk_tb 
 import alt_tlp_adaptor_pkg::*;
 #(
    parameter UID_WIDTH             = 10,
    parameter REG_DATA_WIDTH        = 64,
    parameter REG_ADDR_WIDTH        = 32,
    parameter QOS_QUERY_UID_WIDTH   = 10,
    parameter DATA_WIDTH            = 256,
    parameter EMPTH_WIDTH           = $clog2(DATA_WIDTH/8),
    parameter HOST_INTERFACE_NUM_WR = 3,
    parameter HOST_INTERFACE_NUM_RD = 7
 )(
    input                                                       clk                         ,
    input                                                       rst                         ,

    input      logic                                            dma_rd_req_sav              ,
    output     logic                                            dma_rd_req_val              ,
    output     logic  [EMPTH_WIDTH-1:0]                         dma_rd_req_sty              ,
    output     logic  [$bits(desc_t)-1:0]                       dma_rd_req_desc             ,
    input      logic                                            dma_rd_rsp_val              ,
    input      logic                                            dma_rd_rsp_sop              ,
    input      logic                                            dma_rd_rsp_eop              ,
    input      logic                                            dma_rd_rsp_err              ,
    input      logic  [DATA_WIDTH-1:0]                          dma_rd_rsp_data             ,
    input      logic  [EMPTH_WIDTH-1:0]                         dma_rd_rsp_sty              ,
    input      logic  [EMPTH_WIDTH-1:0]                         dma_rd_rsp_mty              ,
    input      logic  [$bits(desc_t)-1:0]                       dma_rd_rsp_desc             ,
    input      logic                                            dma_wr_req_sav              ,
    output     logic                                            dma_wr_req_val              ,
    output     logic                                            dma_wr_req_sop              ,
    output     logic                                            dma_wr_req_eop              ,
    output     logic  [DATA_WIDTH-1:0]                          dma_wr_req_data             ,
    output     logic  [EMPTH_WIDTH-1:0]                         dma_wr_req_sty              ,
    output     logic  [EMPTH_WIDTH-1:0]                         dma_wr_req_mty              ,
    output     logic  [$bits(desc_t)-1:0]                       dma_wr_req_desc             ,
    input      logic  [103:0]                                   dma_wr_rsp_rd2rsp_loop      ,
    input      logic                                            dma_wr_rsp_val              ,

    input logic                                                doorbell_req_vld            ,
    input [$bits(virtio_vq_t)-1:0]                             doorbell_req_vq            ,
    output logic                                               doorbell_req_rdy            ,
    input                                                       net2tso_sav                 ,
    output logic                                                net2tso_vld                 ,
    output logic  [DATA_WIDTH-1:0]                              net2tso_data                ,
    output logic  [EMPTH_WIDTH-1:0]                             net2tso_sty                 ,
    output logic  [EMPTH_WIDTH-1:0]                             net2tso_mty                 ,
    output logic                                                net2tso_sop                 ,
    output logic                                                net2tso_eop                 ,
    output logic                                                net2tso_err                 ,
    output logic  [7:0]                                         net2tso_qid                 ,
    output logic  [17:0]                                        net2tso_length              ,
    output logic  [7:0]                                         net2tso_gen                 ,
    output logic                                                net2tso_tso_en              ,
    output logic                                                net2tso_csum_en             ,
    output     logic                                            beq2net_sav                 ,
    input      logic                                            beq2net_vld                 ,
    input      logic  [DATA_WIDTH-1:0]                          beq2net_data                ,
    input      logic  [EMPTH_WIDTH-1:0]                         beq2net_sty                 ,
    input      logic  [EMPTH_WIDTH-1:0]                         beq2net_mty                 ,
    input      logic                                            beq2net_sop                 ,
    input      logic                                            beq2net_eop                 ,
    input      logic  [$bits(beq_txq_sbd_t)-1:0]                beq2net_sbd                 ,
    output     logic                                            beq2blk_sav                 ,
    input      logic                                            beq2blk_vld                 ,
    input      logic  [DATA_WIDTH-1:0]                          beq2blk_data                ,
    input      logic  [EMPTH_WIDTH-1:0]                         beq2blk_sty                 ,
    input      logic  [EMPTH_WIDTH-1:0]                         beq2blk_mty                 ,
    input      logic                                            beq2blk_sop                 ,
    input      logic                                            beq2blk_eop                 ,
    input      logic  [$bits(beq_txq_sbd_t)-1:0]                beq2blk_sbd                 ,
    input      logic                                            blk2beq_sav                 ,
    output     logic                                            blk2beq_vld                 ,
    output     logic  [DATA_WIDTH-1:0]                          blk2beq_data                ,
    output     logic  [EMPTH_WIDTH-1:0]                         blk2beq_sty                 ,
    output     logic  [EMPTH_WIDTH-1:0]                         blk2beq_mty                 ,
    output     logic                                            blk2beq_sop                 ,
    output     logic                                            blk2beq_eop                 ,
    output     logic  [$bits(beq_rxq_sbd_t)-1:0]                blk2beq_sbd                 ,
    output logic                                                blk_to_beq_cred_fc          ,
    output logic                                                net_rx_qos_query_req_vld    ,
    input  logic                                                net_rx_qos_query_req_rdy    ,
    output logic                           [UID_WIDTH-1:0]      net_rx_qos_query_req_uid    ,
    input  logic                                                net_rx_qos_query_rsp_vld    ,
    input  logic                                                net_rx_qos_query_rsp_ok     ,
    output logic                                                net_rx_qos_query_rsp_rdy    ,
    output logic                                                net_rx_qos_update_vld       ,
    output logic                           [UID_WIDTH-1:0]      net_rx_qos_update_uid       ,
    input  logic                                                net_rx_qos_update_rdy       ,
    output logic                           [19:0]               net_rx_qos_update_len       ,
    output logic                           [7:0]                net_rx_qos_update_pkt_num   , 
    output logic                                                net_tx_qos_query_req_vld    ,
    output logic [UID_WIDTH-1:0]                                net_tx_qos_query_req_uid    ,
    input  logic                                                net_tx_qos_query_req_rdy    ,
    input  logic                                                net_tx_qos_query_rsp_vld    ,
    input  logic                                                net_tx_qos_query_rsp_ok     ,
    output logic                                                net_tx_qos_query_rsp_rdy    ,
    input  logic                                                net_tx_qos_update_rdy       ,
    output logic                                                net_tx_qos_update_vld       ,
    output logic [UID_WIDTH-1:0]                                net_tx_qos_update_uid       ,
    output logic [19:0]                                         net_tx_qos_update_len       ,
    output logic [9:0]                                          net_tx_qos_update_pkt_num   ,
    input  logic                                                blk_qos_query_req_rdy       ,
    output logic  [QOS_QUERY_UID_WIDTH-1:0]                     blk_qos_query_req_uid       ,
    output logic                                                blk_qos_query_req_vld       ,
    input  logic                                                blk_qos_query_rsp_vld       ,
    input  logic                                                blk_qos_query_rsp_ok        ,
    output logic                                                blk_qos_query_rsp_rdy       ,
    input  logic                                                blk_qos_update_rdy          ,
    output logic                                                blk_qos_update_vld          ,
    output logic [QOS_QUERY_UID_WIDTH-1:0]                      blk_qos_update_uid          ,
    output logic [19:0]                                         blk_qos_update_len          ,
    output logic [7:0]                                          blk_qos_update_pkt_num      ,

    output     logic                                            csr_if_ready                ,
    input      logic                                            csr_if_valid                ,
    input      logic                                            csr_if_read                 ,
    input      logic  [REG_ADDR_WIDTH-1:0]                      csr_if_addr                 ,
    input      logic  [REG_DATA_WIDTH-1:0]                      csr_if_wdata                ,
    input      logic  [REG_DATA_WIDTH/8-1:0]                    csr_if_wmask                ,
    output     logic  [REG_DATA_WIDTH-1:0]                      csr_if_rdata                ,
    output     logic                                            csr_if_rvalid               ,
    input      logic                                            csr_if_rready             
 );

    tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))      dma_wr_req_if()	;
    tlp_adap_dma_wr_rsp_if                                  dma_wr_rsp_if()	;
    tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))      dma_rd_req_if()	;
    tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))      dma_rd_rsp_if()	;

    tlp_adap_dma_wr_req_if  #(.DATA_WIDTH(DATA_WIDTH))      host_arbt_slave_wr_req_if[HOST_INTERFACE_NUM_WR-1:0]()	;
    tlp_adap_dma_wr_rsp_if                                  host_arbt_slave_wr_rsp_if[HOST_INTERFACE_NUM_WR-1:0]()	;
    tlp_adap_dma_rd_req_if  #(.DATA_WIDTH(DATA_WIDTH))      host_arbt_slave_rd_req_if[HOST_INTERFACE_NUM_RD-1:0]()	;
    tlp_adap_dma_rd_rsp_if  #(.DATA_WIDTH(DATA_WIDTH))      host_arbt_slave_rd_rsp_if[HOST_INTERFACE_NUM_RD-1:0]()	;
    mlite_if                #(.DATA_WIDTH(REG_DATA_WIDTH))  csr_if();
    mlite_if                #(.DATA_WIDTH(REG_DATA_WIDTH))  host_tlp_adap_arbiter_csr_if();
    beq_txq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))      beq2net_if();
    beq_txq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))      beq2blk_if();
    beq_rxq_bus_if          #(.DATA_WIDTH(DATA_WIDTH))      blk2beq_if();

    logic [HOST_INTERFACE_NUM_WR-1:0] wr_dma_vld;
    logic [HOST_INTERFACE_NUM_WR-1:0] wr_dma_sop;
    logic [16*HOST_INTERFACE_NUM_WR-1:0] wr_dma_bdf;

    logic [HOST_INTERFACE_NUM_RD-1:0] rd_dma_vld;
    logic [16*HOST_INTERFACE_NUM_RD-1:0] rd_dma_bdf;

    //////////////////////////逻辑/////////////////////////////
    initial begin
        $fsdbAutoSwitchDumpfile(512, "top.fsdb", 40);
        $fsdbDumpvars(0, virtio_blk_tb, "+all");
        $fsdbDumpMDA();
    end

    assign csr_if_ready                         = csr_if.ready;
    assign csr_if.valid                         = csr_if_valid;
    assign csr_if.read                          = csr_if_read;
    assign csr_if.addr                          = csr_if_addr;
    assign csr_if.wdata                         = csr_if_wdata;
    assign csr_if.wmask                         = csr_if_wmask;
    assign csr_if_rdata                         = csr_if.rdata;
    assign csr_if_rvalid                        = csr_if.rvalid;
    assign csr_if.rready                        = csr_if_rready;
    assign beq2net_sav                          = beq2net_if.sav;
    assign beq2net_if.vld                       = beq2net_vld;
    assign beq2net_if.sop                       = beq2net_sop;
    assign beq2net_if.eop                       = beq2net_eop;
    assign beq2net_if.sbd                       = beq2net_sbd;
    assign beq2net_if.sty                       = beq2net_sty;
    assign beq2net_if.mty                       = beq2net_mty;
    assign beq2net_if.data                      = beq2net_data;
    assign beq2blk_sav                          = beq2blk_if.sav;
    assign beq2blk_if.vld                       = beq2blk_vld;
    assign beq2blk_if.sop                       = beq2blk_sop;
    assign beq2blk_if.eop                       = beq2blk_eop;
    assign beq2blk_if.sbd                       = beq2blk_sbd;
    assign beq2blk_if.sty                       = beq2blk_sty;
    assign beq2blk_if.mty                       = beq2blk_mty;
    assign beq2blk_if.data                      = beq2blk_data;
    assign blk2beq_if.sav                       = blk2beq_sav;
    assign blk2beq_vld                          = blk2beq_if.vld;
    assign blk2beq_sop                          = blk2beq_if.sop;
    assign blk2beq_eop                          = blk2beq_if.eop;
    assign blk2beq_sbd                          = blk2beq_if.sbd;
    assign blk2beq_sty                          = blk2beq_if.sty;
    assign blk2beq_mty                          = blk2beq_if.mty;
    assign blk2beq_data                         = blk2beq_if.data;
    assign host_tlp_adap_arbiter_csr_if.valid   = 1'b0;
    assign host_tlp_adap_arbiter_csr_if.read    = '0;
    assign host_tlp_adap_arbiter_csr_if.addr    = '0;
    assign host_tlp_adap_arbiter_csr_if.wdata   = '0;
    assign host_tlp_adap_arbiter_csr_if.wmask   = '0;
    assign host_tlp_adap_arbiter_csr_if.rready  = 1'b1;

    assign dma_rd_req_if.sav               = dma_rd_req_sav;
    assign dma_rd_req_val                  = dma_rd_req_if.vld;
    assign dma_rd_req_sty                  = dma_rd_req_if.sty;
    clear_x #(.DW($bits(desc_t))) u_dma_rd_req_desc_clearx (.in(dma_rd_req_if.desc), .out(dma_rd_req_desc));
    assign dma_rd_rsp_if.vld               = dma_rd_rsp_val;
    assign dma_rd_rsp_if.sop               = dma_rd_rsp_sop;
    assign dma_rd_rsp_if.eop               = dma_rd_rsp_eop;
    assign dma_rd_rsp_if.sty               = dma_rd_rsp_sty;
    assign dma_rd_rsp_if.mty               = dma_rd_rsp_mty;
    assign dma_rd_rsp_if.data              = dma_rd_rsp_data;
    assign dma_rd_rsp_if.err               = dma_rd_rsp_err;
    assign dma_rd_rsp_if.desc              = dma_rd_rsp_desc;

    assign dma_wr_req_if.sav            = dma_wr_req_sav;
    assign dma_wr_req_sop               = dma_wr_req_if.sop;
    assign dma_wr_req_eop               = dma_wr_req_if.eop;
    assign dma_wr_req_val               = dma_wr_req_if.vld;
    assign dma_wr_req_data              = dma_wr_req_if.data;
    assign dma_wr_req_sty               = dma_wr_req_if.sty;
    assign dma_wr_req_mty               = dma_wr_req_if.mty;
    clear_x #(.DW($bits(desc_t))) u_dma_wr_req_desc_clearx (.in(dma_wr_req_if.desc), .out(dma_wr_req_desc));
    assign dma_wr_rsp_if.vld            = dma_wr_rsp_val;
    assign dma_wr_rsp_if.rd2rsp_loop    = dma_wr_rsp_rd2rsp_loop;

    tlp_adaptor_arbiter #(
        .INTERFACE_NUM_WR(HOST_INTERFACE_NUM_WR     ),
        .INTERFACE_NUM_RD(HOST_INTERFACE_NUM_RD     ),
        .DATA_WIDTH      (DATA_WIDTH                        ),
        .EMPTH_WIDTH     ($clog2(DATA_WIDTH/8)              ),
        .DWRR_WEIGHT_WID (4                         )
    )u_host_tlp_adaptor_arbiter(
        .clk                    (  clk                          ),
        .rst                    (  rst                          ),
        .master_wr_req_if       (  dma_wr_req_if                ),
        .master_wr_rsp_if       (  dma_wr_rsp_if                ),
        .master_rd_req_if       (  dma_rd_req_if                ),
        .master_rd_rsp_if       (  dma_rd_rsp_if                ),
        .slave_wr_req_if        (  host_arbt_slave_wr_req_if    ),
        .slave_wr_rsp_if        (  host_arbt_slave_wr_rsp_if    ),
        .slave_rd_req_if        (  host_arbt_slave_rd_req_if    ),
        .slave_rd_rsp_if        (  host_arbt_slave_rd_rsp_if    ),
        .rd_chn_shaping_en      ('h50),
        .csr_if                 (  host_tlp_adap_arbiter_csr_if )
    );
    generate
      genvar i;
      for (i = 0; i < HOST_INTERFACE_NUM_WR; i ++) begin
        clear_x #(.DW(1)) (.in(host_arbt_slave_wr_req_if[i].vld), .out(wr_dma_vld[i]));
        clear_x #(.DW(1)) (.in(host_arbt_slave_wr_req_if[i].sop), .out(wr_dma_sop[i]));
        clear_x #(.DW(16)) (.in(host_arbt_slave_wr_req_if[i].desc.bdf), .out(wr_dma_bdf[i*16+15:i*16]));
      end

      for (i = 0; i < HOST_INTERFACE_NUM_RD; i ++) begin
        clear_x #(.DW(1)) (.in(host_arbt_slave_rd_req_if[i].vld), .out(rd_dma_vld[i]));
        clear_x #(.DW(16)) (.in(host_arbt_slave_rd_req_if[i].desc.bdf), .out(rd_dma_bdf[i*16+15:i*16]));
      end
    endgenerate


    virtio_top u_virtio_top (
        .clk(clk),
        .rst({4{rst}}),
        .idx_eng_dma_rd_req_if               (host_arbt_slave_rd_req_if[0]),
        .idx_eng_dma_rd_rsp_if               (host_arbt_slave_rd_rsp_if[0]),
        .avail_ring_dma_rd_req_if            (host_arbt_slave_rd_req_if[1]),
        .avail_ring_dma_rd_rsp_if            (host_arbt_slave_rd_rsp_if[1]),
        .net_tx_desc_dma_rd_req_if           (host_arbt_slave_rd_req_if[2]),
        .net_tx_desc_dma_rd_rsp_if           (host_arbt_slave_rd_rsp_if[2]),
        .net_rx_desc_dma_rd_req_if           (host_arbt_slave_rd_req_if[3]),
        .net_rx_desc_dma_rd_rsp_if           (host_arbt_slave_rd_rsp_if[3]),
        .net_tx_data_dma_rd_req_if           (host_arbt_slave_rd_req_if[4]),
        .net_tx_data_dma_rd_rsp_if           (host_arbt_slave_rd_rsp_if[4]),
        .net_rx_data_dma_wr_req_if           (host_arbt_slave_wr_req_if[2]),
        .net_rx_data_dma_wr_rsp_if           (host_arbt_slave_wr_rsp_if[2]),
        .blk_desc_dma_rd_req_if              (host_arbt_slave_rd_req_if[5]),
        .blk_desc_dma_rd_rsp_if              (host_arbt_slave_rd_rsp_if[5]),
        .blk_downstream_data_dma_rd_req_if   (host_arbt_slave_rd_req_if[6]),
        .blk_downstream_data_dma_rd_rsp_if   (host_arbt_slave_rd_rsp_if[6]),
        .blk_upstream_data_dma_wr_req_if     (host_arbt_slave_wr_req_if[1]),
        .blk_upstream_data_dma_wr_rsp_if     (host_arbt_slave_wr_rsp_if[1]),
        .used_dma_wr_req_if                  (host_arbt_slave_wr_req_if[0]),
        .used_dma_wr_rsp_if                  (host_arbt_slave_wr_rsp_if[0]),

        .doorbell_req_vld            (doorbell_req_vld            ),
        .doorbell_req_vq             (doorbell_req_vq              ),
        .doorbell_req_rdy            (doorbell_req_rdy            ),
        .net2tso_sav                 (net2tso_sav                 ),
        .net2tso_vld                 (net2tso_vld                 ),
        .net2tso_data                (net2tso_data                ),
        .net2tso_sty                 (net2tso_sty                 ),
        .net2tso_mty                 (net2tso_mty                 ),
        .net2tso_sop                 (net2tso_sop                 ),
        .net2tso_eop                 (net2tso_eop                 ),
        .net2tso_err                 (net2tso_err                 ),
        .net2tso_qid                 (net2tso_qid                 ),
        .net2tso_length              (net2tso_length              ),
        .net2tso_gen                 (net2tso_gen                 ),
        .net2tso_tso_en              (net2tso_tso_en              ),
        .net2tso_csum_en             (net2tso_csum_en             ),
        .beq2net_if                  (beq2net_if                  ),
        .beq2blk_if                  (beq2blk_if                  ),
        .blk_to_beq_cred_fc          (blk_to_beq_cred_fc          ),
        .blk2beq_if                  (blk2beq_if                  ),
        .net_rx_qos_query_req_vld    (net_rx_qos_query_req_vld    ),
        .net_rx_qos_query_req_rdy    (net_rx_qos_query_req_rdy    ),
        .net_rx_qos_query_req_uid    (net_rx_qos_query_req_uid    ),
        .net_rx_qos_query_rsp_vld    (net_rx_qos_query_rsp_vld    ),
        .net_rx_qos_query_rsp_ok     (net_rx_qos_query_rsp_ok     ),
        .net_rx_qos_query_rsp_rdy    (net_rx_qos_query_rsp_rdy    ),
        .net_rx_qos_update_vld       (net_rx_qos_update_vld       ),
        .net_rx_qos_update_uid       (net_rx_qos_update_uid       ),
        .net_rx_qos_update_rdy       (net_rx_qos_update_rdy       ),
        .net_rx_qos_update_len       (net_rx_qos_update_len       ),
        .net_rx_qos_update_pkt_num   (net_rx_qos_update_pkt_num   ),
        .net_tx_qos_query_req_vld    (net_tx_qos_query_req_vld    ),
        .net_tx_qos_query_req_uid    (net_tx_qos_query_req_uid    ),
        .net_tx_qos_query_req_rdy    (net_tx_qos_query_req_rdy    ),
        .net_tx_qos_query_rsp_vld    (net_tx_qos_query_rsp_vld    ),
        .net_tx_qos_query_rsp_ok     (net_tx_qos_query_rsp_ok     ),
        .net_tx_qos_query_rsp_rdy    (net_tx_qos_query_rsp_rdy    ),
        .net_tx_qos_update_rdy       (net_tx_qos_update_rdy       ),
        .net_tx_qos_update_vld       (net_tx_qos_update_vld       ),
        .net_tx_qos_update_uid       (net_tx_qos_update_uid       ),
        .net_tx_qos_update_len       (net_tx_qos_update_len       ),
        .net_tx_qos_update_pkt_num   (net_tx_qos_update_pkt_num   ),
        .blk_qos_query_req_rdy       (blk_qos_query_req_rdy       ),
        .blk_qos_query_req_uid       (blk_qos_query_req_uid       ),
        .blk_qos_query_req_vld       (blk_qos_query_req_vld       ),
        .blk_qos_query_rsp_vld       (blk_qos_query_rsp_vld       ),
        .blk_qos_query_rsp_ok        (blk_qos_query_rsp_ok        ),
        .blk_qos_query_rsp_rdy       (blk_qos_query_rsp_rdy       ),
        .blk_qos_update_rdy          (blk_qos_update_rdy          ),
        .blk_qos_update_vld          (blk_qos_update_vld          ),
        .blk_qos_update_uid          (blk_qos_update_uid          ),
        .blk_qos_update_len          (blk_qos_update_len          ),
        .blk_qos_update_pkt_num      (blk_qos_update_pkt_num      ),
        .csr_if                      (csr_if                      )
    );

 endmodule
