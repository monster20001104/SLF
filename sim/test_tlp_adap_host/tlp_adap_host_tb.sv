/******************************************************************************
 * 文件名称 : tlp_adap_soc.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/07/31
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/31     Joe Jiang   初始化版本
 ******************************************************************************/
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

module tlp_adap_host_tb 
  import alt_tlp_adaptor_pkg::*;
#(
    parameter int   DW = 256,                 // DW=512 for gen3x16. DW=256 for all other configurations.
    parameter int   DATASEG_WIDTH = 128,      // DATASEG_WIDTH=256, except for r-tile, x4
    parameter int   NUM_DATASEGS = DW/DATASEG_WIDTH,
    parameter int   BAW = DW==1024 ? 7 : DW==512 ? 6 : 5,          // log2(DW/8)
    parameter int   NUM_VF = 128,
    parameter int   NUM_PF = 1
)(
    output logic                                    linkdown_rst,
    input  wire                                     clk,
    input  wire                                     rst,
    input  wire                                     pciehip_srst,
    input  wire                                     linkdown,
    input  wire [NUM_DATASEGS*DATASEG_WIDTH-1:0]    rx_st_data,
    input  wire [NUM_DATASEGS*$clog2(DATASEG_WIDTH/64)-1:0]                  rx_st_empty,
    input  wire [NUM_DATASEGS-1:0]                  rx_st_sop,
    input  wire [NUM_DATASEGS-1:0]                  rx_st_eop,
    input  wire [NUM_DATASEGS-1:0]                  rx_st_valid,
    output wire                                     rx_st_ready,
    input  wire [NUM_DATASEGS*3-1:0]                rx_st_bar_range,

    output logic [NUM_DATASEGS*DATASEG_WIDTH-1:0]    tx_st_data,
    output  wire [NUM_DATASEGS*$clog2(DATASEG_WIDTH/64)-1:0]                  tx_st_empty,

    output logic [NUM_DATASEGS-1:0]                  tx_st_sop,
    output logic [NUM_DATASEGS-1:0]                  tx_st_eop,
    output logic [NUM_DATASEGS-1:0]                  tx_st_valid,
    input  logic                                     tx_st_ready,
    output logic [NUM_DATASEGS-1:0]                  tx_st_err,


    input  wire [3:0]                               tl_cfg_add,
    input  wire [31:0]                              tl_cfg_ctl,


    output logic [$bits(tlp_bypass_hdr_t)-1:0]      tlp_bypass_req_hdr ,
    output  logic                                   tlp_bypass_req_linkdown,
    output logic [7:0]                              tlp_bypass_req_gen ,
    input   logic                                   tlp_bypass_req_sav , //backpressure
    output  logic                                   tlp_bypass_req_vld ,
    output  logic                                   tlp_bypass_req_sop ,
    output  logic                                   tlp_bypass_req_eop ,
    output  logic [DW-1:0]                          tlp_bypass_req_data,

    input  logic [$bits(tlp_bypass_hdr_t)-1:0]      tlp_bypass_cpl_hdr ,
    input  logic [7:0]                              tlp_bypass_cpl_gen ,
    input  logic                                    tlp_bypass_cpl_sop ,
    input  logic                                    tlp_bypass_cpl_eop ,
    input  logic  [DW-1:0]                          tlp_bypass_cpl_data,
    input  logic                                    tlp_bypass_cpl_vld ,
    output logic                                    tlp_bypass_cpl_rdy , //handshake

    // Write request interface from DMA core
    output     logic                            dma_wr_req_sav                           ,// wr_req_val_i must de-assert within 3 cycles after de-assertion of wr_req_sav_o
    input      logic                            dma_wr_req_val                            ,// Request is taken when asserted
    input      logic                            dma_wr_req_sop                            ,// Indicates first dataword
    input      logic                            dma_wr_req_eop                            ,// Indicates last dataword
    input      logic  [DW-1:0]                  dma_wr_req_data                           ,// Data to write to host in big endian format
    input      logic  [BAW-1:0]                 dma_wr_req_sty                            ,// Points to first valid payload byte. Valid when wr_req_sop_i=1
    input      logic  [BAW-1:0]                 dma_wr_req_mty                            ,// Number of unused bytes in last dataword. Valid when wr_req_eop_i=1
    input      logic  [$bits(desc_t)-1:0]       dma_wr_req_desc                           ,// Descriptor for write. Valid when wr_req_sop_i=1
    //
    // Write response interface from DMA core
    //
    output logic [103:0]                        dma_wr_rsp_rd2rsp_loop,
    output logic                                dma_wr_rsp_val,
    input  logic                                dma_wr_rsp_sav,
    
    // Read request interface from DMA core
    output     logic                            dma_rd_req_sav                            ,// rd_req_val_i must de-assert within 3 cycles after de-assertion of rd_req_sav_o
    input      logic                            dma_rd_req_val                            ,// Request is taken when asserted
    input      logic  [BAW-1:0]                 dma_rd_req_sty                            ,// Determines where first valid payload byte is placed in rd_rsp_data_o
    input      logic  [$bits(desc_t)-1:0]       dma_rd_req_desc                           ,// Descriptor for read
    // Read response interface back to DMA core
    output     logic                            dma_rd_rsp_val                            ,// Asserted when response is valid
    output     logic                            dma_rd_rsp_sop                            ,// Indicates first dataword
    output     logic                            dma_rd_rsp_eop                            ,// Indicates last dataword
    output     logic                            dma_rd_rsp_err                            ,// Asserted if completion from host has non-succesfull status or poison bit set
    output     logic  [DW-1:0]                  dma_rd_rsp_data                           ,// Response data
    output     logic  [BAW-1:0]                 dma_rd_rsp_sty                            ,// Points to first valid payload byte. Valid when rd_rsp_sop_o=1
    output     logic  [BAW-1:0]                 dma_rd_rsp_mty                            ,// Number of unused bytes in last dataword. Valid when rd_rsp_eop_o=1
    output     logic  [$bits(desc_t)-1:0]       dma_rd_rsp_desc                           ,// Descriptor for response. Valid when rd_rsp_sop_o=1
    input      logic                            dma_rd_rsp_sav                            ,
    output     logic                            csr_if_ready                              ,
    input      logic                            csr_if_valid                              ,
    input      logic                            csr_if_read                               ,
    input      logic  [31:0]                    csr_if_addr                               ,
    input      logic  [63:0]                    csr_if_wdata                              ,
    input      logic  [7:0]                     csr_if_wmask                              ,
    output     logic  [63:0]                    csr_if_rdata                              ,
    output     logic                            csr_if_rvalid                             ,
    input      logic                            csr_if_rready              

);

logic [$bits(tlp_bypass_hdr_t)-1:0]      tlp_bypass_req_hdr_tmp;
logic [DW-1:0]                          tlp_bypass_req_data_tmp;

initial begin
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 100);
    $fsdbDumpvars(0, tlp_adap_host_tb, "+all");
    $fsdbDumpMDA();
end

alt_pcie_if #(
    .NUM_PF (NUM_PF),
    .NUM_VF (NUM_VF)
) pcie_if (clk,pciehip_srst);

//assign pcie_if.tl_cfg_add               = tl_cfg_add;
//assign pcie_if.tl_cfg_ctl               = tl_cfg_ctl;

//assign pcie_if.tx_cdts_limit_tdm_idx    = tx_cdts_limit_tdm_idx;
//assign pcie_if.tx_cdts_limit            = tx_cdts_limit;

//assign rx_buffer_limit                  = pcie_if.rx_buffer_limit;
//assign rx_buffer_limit_tdm_idx          = pcie_if.rx_buffer_limit_tdm_idx;

assign linkdown_rst = 1'b1;

assign csr_if_ready                = csr_if.ready;
assign csr_if.valid                = csr_if_valid;
assign csr_if.read                 = csr_if_read;
assign csr_if.addr                 = csr_if_addr;
assign csr_if.wdata                = csr_if_wdata;
assign csr_if.wmask                = csr_if_wmask;
assign csr_if_rdata                = csr_if.rdata;
assign csr_if_rvalid               = csr_if.rvalid;
assign csr_if.rready               = csr_if_rready;

assign pcie_if.rx_st_data = rx_st_data;
assign pcie_if.rx_st_empty = rx_st_empty;
assign pcie_if.rx_st_sop = rx_st_sop;
assign pcie_if.rx_st_eop = rx_st_eop;
assign pcie_if.rx_st_valid = rx_st_valid;
assign rx_st_ready = pcie_if.rx_st_ready;
assign pcie_if.rx_st_bar_range = rx_st_bar_range;
//assign pcie_if.rx_st_tlp_abort = rx_st_tlp_abort;

// assign tx_st_data = pcie_if.tx_st_data;
// assign tx_st_sop = pcie_if.tx_st_sop;
// assign tx_st_eop = pcie_if.tx_st_eop;
// assign tx_st_valid = pcie_if.tx_st_valid;
// assign tx_st_err = pcie_if.tx_st_err;
// assign tx_st_hdr = pcie_if.tx_st_hdr;
// assign tx_st_tlp_prfx = pcie_if.tx_st_tlp_prfx;

clear_x #(.DW(NUM_DATASEGS*DATASEG_WIDTH)) u_tx_st_data_clearx (.in(pcie_if.tx_st_data), .out(tx_st_data));
clear_x #(.DW(NUM_DATASEGS*$clog2(DATASEG_WIDTH/64))) u_tx_st_empty_clearx (.in(pcie_if.tx_st_empty), .out(tx_st_empty));
clear_x #(.DW(NUM_DATASEGS)) u_tx_st_sop_clearx (.in(pcie_if.tx_st_sop), .out(tx_st_sop));
clear_x #(.DW(NUM_DATASEGS)) u_tx_st_eop_clearx (.in(pcie_if.tx_st_eop), .out(tx_st_eop));
clear_x #(.DW(NUM_DATASEGS)) u_tx_st_valid_clearx (.in(pcie_if.tx_st_valid), .out(tx_st_valid));
clear_x #(.DW(NUM_DATASEGS)) u_tx_st_err_clearx (.in(pcie_if.tx_st_err), .out(tx_st_err));


logic [$bits(dma_rd_rsp_data)-1:0] dma_rd_rsp_data_tmp;
logic [$bits(dma_rd_rsp_desc)-1:0] dma_rd_rsp_desc_tmp;

clear_x #(.DW($bits(dma_rd_rsp_data))) u_dma_rd_rsp_data_clearx (.in(dma_rd_rsp_data_tmp), .out(dma_rd_rsp_data));
clear_x #(.DW($bits(dma_rd_rsp_desc))) u_dma_rd_rsp_desc_clearx (.in(dma_rd_rsp_desc_tmp), .out(dma_rd_rsp_desc));

clear_x #(.DW($bits(tlp_bypass_hdr_t))) u_tlp_bypass_req_hdr_clearx (.in(tlp_bypass_req_hdr_tmp), .out(tlp_bypass_req_hdr));
clear_x #(.DW(DW)) u_tlp_bypass_req_data_clearx (.in(tlp_bypass_req_data_tmp), .out(tlp_bypass_req_data));

assign pcie_if.tx_st_ready = tx_st_ready;

//todo
assign pcie_if.tx_cred_fc_infinite = 6'b111111;
assign pcie_if.tx_cred_fc_hip_cons = 'h0;
assign pcie_if.tx_cred_hdr_fc = 'h40;
assign pcie_if.tx_cred_data_fc = 'h80;

//alt_avmm_if #(.AW(32),.DW(32),.BW(4),.SW(0)) debug_csr_if(.clk(clk), .srst(pciehip_srst));;
mlite_if                #(.DATA_WIDTH(64))    csr_if();

alt_tlp_adaptor_host u_host_alt_tlp_adaptor (
    .clk_i                  (clk                    ),
    .srst_i                 (rst                    ),
    .pciehip_srst_i         (pciehip_srst           ),
    .linkdown_i             (linkdown               ),
    .dlup_i                 (0                      ),
    .pcie_hip_if            (pcie_if                ),
    // Write request interface from DMA core
    .wr_req_sav_o           (dma_wr_req_sav             ), 
    .wr_req_val_i           (dma_wr_req_val             ), 
    .wr_req_sop_i           (dma_wr_req_sop             ), 
    .wr_req_eop_i           (dma_wr_req_eop             ), 
    .wr_req_data_i          (dma_wr_req_data            ),
    .wr_req_sty_i           (dma_wr_req_sty             ), 
    .wr_req_mty_i           (dma_wr_req_mty             ), 
    .wr_req_desc_i          (dma_wr_req_desc            ),
    // Write response interface from DMA core
    .wr_rsp_rd2rsp_loop_o   (dma_wr_rsp_rd2rsp_loop     ),
    .wr_rsp_val_o           (dma_wr_rsp_val             ),
    .wr_rsp_sav_i           (dma_wr_rsp_sav             ),
    // Read request interface from DMA core
    .rd_req_sav_o           (dma_rd_req_sav             ), 
    .rd_req_val_i           (dma_rd_req_val             ), 
    .rd_req_sty_i           (dma_rd_req_sty             ), 
    .rd_req_desc_i          (dma_rd_req_desc            ),
    // Read response interface back to DMA core     
    .rd_rsp_val_o           (dma_rd_rsp_val             ), 
    .rd_rsp_sop_o           (dma_rd_rsp_sop             ), 
    .rd_rsp_eop_o           (dma_rd_rsp_eop             ), 
    .rd_rsp_err_o           (dma_rd_rsp_err             ), 
    .rd_rsp_data_o          (dma_rd_rsp_data_tmp        ),
    .rd_rsp_sty_o           (dma_rd_rsp_sty             ), 
    .rd_rsp_mty_o           (dma_rd_rsp_mty             ), 
    .rd_rsp_desc_o          (dma_rd_rsp_desc_tmp        ),
    .rd_rsp_sav_i           (dma_rd_rsp_sav             ),

    .tlp_bypass_req_hdr_o (tlp_bypass_req_hdr_tmp ),
    .tlp_bypass_req_sav_i (tlp_bypass_req_sav ),
    .tlp_bypass_req_gen_o (tlp_bypass_req_gen ),
    .tlp_bypass_req_linkdown_o (tlp_bypass_req_linkdown),
    .tlp_bypass_req_vld_o (tlp_bypass_req_vld ),
    .tlp_bypass_req_sop_o (tlp_bypass_req_sop ),
    .tlp_bypass_req_eop_o (tlp_bypass_req_eop ),
    .tlp_bypass_req_data_o(tlp_bypass_req_data_tmp),
    .tlp_bypass_cpl_hdr_i (tlp_bypass_cpl_hdr ),
    .tlp_bypass_cpl_gen_i (tlp_bypass_cpl_gen ),
    .tlp_bypass_cpl_sop_i (tlp_bypass_cpl_sop ),
    .tlp_bypass_cpl_eop_i (tlp_bypass_cpl_eop ),
    .tlp_bypass_cpl_data_i(tlp_bypass_cpl_data),
    .tlp_bypass_cpl_vld_i (tlp_bypass_cpl_vld ),
    .tlp_bypass_cpl_rdy_o (tlp_bypass_cpl_rdy ),
    
    .csr_if                 (csr_if                 )
); 

//set the cfg (these should come from decoding the hip tl_cfg/cii)
//assign pcie_if.currentspeed          = '0;
assign pcie_if.ltssmstate           = 'h11;  //L1
//assign pcie_if.dl_up                 = '1;
//assign pcie_if.link_up               = '1;
//assign pcie_if.timer_update          = '0;

assign pcie_if.msix_ack                = 0;
assign pcie_if.msix_err                = '0;
assign pcie_if.msix_en_pf              = '0;
assign pcie_if.msix_fn_mask_pf         = '0;
assign pcie_if.ko_cpl_spc_header       = 0;
assign pcie_if.ko_cpl_spc_data         = '0;
assign pcie_if.pf0_num_vfs             = '0;
assign pcie_if.pf1_num_vfs             = '0;
assign pcie_if.mem_space_en_pf         = '1;
assign pcie_if.bus_master_en_pf        = '1;
assign pcie_if.mem_space_en_vf         = '0;
assign pcie_if.ctl_shdw_update         = '0;
assign pcie_if.ctl_shdw_pf_num         = '0;
assign pcie_if.ctl_shdw_vf_num         = '0;
assign pcie_if.ctl_shdw_vf_active      = '0;
assign pcie_if.ctl_shdw_cfg            = '0;

//todo
assign pcie_if.bus_num_f0 = 'h1;
assign pcie_if.bus_num_f1 = 'h0;
assign pcie_if.device_num_f0 = 'h0;
assign pcie_if.device_num_f1 = 'h0;
assign pcie_if.pf_max_payload_size = 2;
assign pcie_if.pf_rd_req_size = 5;

//tie off signals that the model does not handle
assign pcie_if.flr_active_pf   = '1;
assign pcie_if.flr_rcvd_vf     = '0;
assign pcie_if.flr_rcvd_pf_num = '0;
assign pcie_if.flr_rcvd_vf_num = '0;

//ssign debug_csr_if.sideband = 'h0;
//ssign debug_csr_if.address = 'h0;
//ssign debug_csr_if.write = 'h0;
//ssign debug_csr_if.byteenable = 'h0;
//ssign debug_csr_if.writedata = 'h0;
//ssign debug_csr_if.read = 'h0;

    
endmodule