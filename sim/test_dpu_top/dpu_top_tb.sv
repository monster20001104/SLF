/******************************************************************************
 * 文件名称 : dpu_top_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/02/07
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  02/07     Joe Jiang   初始化版本
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

module dpu_top_tb 
  import alt_tlp_adaptor_pkg::*;
#(
    parameter int   REG_ADDR_WIDTH = 30                  ,
    parameter int   REG_DATA_WIDTH = 64                  ,
    parameter int   DW             = 256                 , // DW=512 for gen3x16. DW=256 for all other configurations.
    parameter int   DATASEG_WIDTH  = 128                 , // DATASEG_WIDTH=256, except for r-tile, x4
    parameter int   NUM_DATASEGS   = DW/DATASEG_WIDTH    ,
    parameter int   NUM_VF         = 128                 ,
    parameter int   NUM_PF         = 1
)(
    input  wire                                               soc_pcie_clk             ,
    input  wire                                               soc_pcie_rst             ,
    input  wire                                               host_pcie_clk            ,
    input  wire                                               host_pcie_rst            ,
    input  wire                                               fpga_user_reset          ,
    input  wire                                               clk_200m         ,
    input  wire                                               rst_200m         ,
    input  wire                                               clk_50m         ,
    input  wire                                               rst_50m         ,
    input  wire                                               clk_11m         ,
    input  wire                                               rst_11m         ,

    input  wire [NUM_DATASEGS*DATASEG_WIDTH-1:0]              host_rx_st_data      ,
    input  wire [NUM_DATASEGS*$clog2(DATASEG_WIDTH/64)-1:0]   host_rx_st_empty     ,
    input  wire [NUM_DATASEGS-1:0]                            host_rx_st_sop       ,
    input  wire [NUM_DATASEGS-1:0]                            host_rx_st_eop       ,
    input  wire [NUM_DATASEGS-1:0]                            host_rx_st_valid     ,
    output wire                                               host_rx_st_ready     ,
    input  wire [NUM_DATASEGS*3-1:0]                          host_rx_st_bar_range ,

    output logic [NUM_DATASEGS*DATASEG_WIDTH-1:0]             host_tx_st_data      ,
    output  wire [NUM_DATASEGS*$clog2(DATASEG_WIDTH/64)-1:0]  host_tx_st_empty     ,
    output logic [NUM_DATASEGS-1:0]                           host_tx_st_sop       ,
    output logic [NUM_DATASEGS-1:0]                           host_tx_st_eop       ,
    output logic [NUM_DATASEGS-1:0]                           host_tx_st_valid     ,
    input  logic                                              host_tx_st_ready     ,
    output logic [NUM_DATASEGS-1:0]                           host_tx_st_err       ,


    input  wire [NUM_DATASEGS*DATASEG_WIDTH-1:0]              soc_rx_st_data      ,
    input  wire [NUM_DATASEGS*$clog2(DATASEG_WIDTH/64)-1:0]   soc_rx_st_empty     ,
    input  wire [NUM_DATASEGS-1:0]                            soc_rx_st_sop       ,
    input  wire [NUM_DATASEGS-1:0]                            soc_rx_st_eop       ,
    input  wire [NUM_DATASEGS-1:0]                            soc_rx_st_valid     ,
    output wire                                               soc_rx_st_ready     ,
    input  wire [NUM_DATASEGS*3-1:0]                          soc_rx_st_bar_range ,

    output logic [NUM_DATASEGS*DATASEG_WIDTH-1:0]             soc_tx_st_data      ,
    output  wire [NUM_DATASEGS*$clog2(DATASEG_WIDTH/64)-1:0]  soc_tx_st_empty     ,
    output logic [NUM_DATASEGS-1:0]                           soc_tx_st_sop       ,
    output logic [NUM_DATASEGS-1:0]                           soc_tx_st_eop       ,
    output logic [NUM_DATASEGS-1:0]                           soc_tx_st_valid     ,
    input  logic                                              soc_tx_st_ready     ,
    output logic [NUM_DATASEGS-1:0]                           soc_tx_st_err       ,

    input  wire [3:0]                                         soc_tl_cfg_add      ,
    input  wire [31:0]                                        soc_tl_cfg_ctl      ,

    input  wire                                               i2c_data_in     ,
    input  wire                                               i2c_clk_in      , 
    output wire                                               i2c_data_o      , 
    output wire                                               i2c_clk_o   
);

initial begin
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 20);
    $fsdbDumpvars(0, dpu_top_tb, "+all");
    $fsdbDumpMDA();
end

alt_pcie_if #(
    .NUM_PF (NUM_PF),
    .NUM_VF (NUM_VF)
) soc_pcie_if (soc_pcie_clk, soc_pcie_rst);

alt_pcie_if #(
    .NUM_PF (NUM_PF),
    .NUM_VF (NUM_VF)
) host_pcie_if (host_pcie_clk, host_pcie_rst);

logic [7:0]      soc_bus_num         ;
logic [4:0]      soc_device_num      ;
logic [2:0]      soc_max_payload_size;
logic [2:0]      soc_max_rd_req_size ;

assign soc_pcie_if.rx_st_data = soc_rx_st_data;
assign soc_pcie_if.rx_st_empty = soc_rx_st_empty;
assign soc_pcie_if.rx_st_sop = soc_rx_st_sop;
assign soc_pcie_if.rx_st_eop = soc_rx_st_eop;
assign soc_pcie_if.rx_st_valid = soc_rx_st_valid;
assign soc_rx_st_ready = soc_pcie_if.rx_st_ready;
assign soc_pcie_if.rx_st_bar_range = soc_rx_st_bar_range;

clear_x #(.DW(NUM_DATASEGS*DATASEG_WIDTH)) u_tx_st_data_clearx (.in(soc_pcie_if.tx_st_data), .out(soc_tx_st_data));
clear_x #(.DW(NUM_DATASEGS*$clog2(DATASEG_WIDTH/64))) u_tx_st_empty_clearx (.in(soc_pcie_if.tx_st_empty), .out(soc_tx_st_empty));
clear_x #(.DW(NUM_DATASEGS)) u_tx_st_sop_clearx (.in(soc_pcie_if.tx_st_sop), .out(soc_tx_st_sop));
clear_x #(.DW(NUM_DATASEGS)) u_tx_st_eop_clearx (.in(soc_pcie_if.tx_st_eop), .out(soc_tx_st_eop));
clear_x #(.DW(NUM_DATASEGS)) u_tx_st_valid_clearx (.in(soc_pcie_if.tx_st_valid), .out(soc_tx_st_valid));
clear_x #(.DW(NUM_DATASEGS)) u_tx_st_err_clearx (.in(soc_pcie_if.tx_st_err), .out(soc_tx_st_err));
assign soc_pcie_if.tx_st_ready = soc_tx_st_ready;

//todo
assign soc_pcie_if.tx_cred_fc_infinite = 6'b111111;
assign soc_pcie_if.tx_cred_fc_hip_cons = 'h0;
assign soc_pcie_if.tx_cred_hdr_fc = 'h40;
assign soc_pcie_if.tx_cred_data_fc = 'h80;


//set the cfg (these should come from decoding the hip tl_cfg/cii)
//assign soc_pcie_if.currentspeed          = '0;
assign soc_pcie_if.ltssmstate           = 'h11;  //L1
//assign soc_pcie_if.dl_up                 = '1;
//assign soc_pcie_if.link_up               = '1;
//assign soc_pcie_if.timer_update          = '0;

assign soc_pcie_if.msix_ack                = 0;
assign soc_pcie_if.msix_err                = '0;
assign soc_pcie_if.msix_en_pf              = '0;
assign soc_pcie_if.msix_fn_mask_pf         = '0;
assign soc_pcie_if.ko_cpl_spc_header       = 0;
assign soc_pcie_if.ko_cpl_spc_data         = '0;
assign soc_pcie_if.pf0_num_vfs             = '0;
assign soc_pcie_if.pf1_num_vfs             = '0;
assign soc_pcie_if.mem_space_en_pf         = '1;
assign soc_pcie_if.bus_master_en_pf        = '1;
assign soc_pcie_if.mem_space_en_vf         = '0;
assign soc_pcie_if.ctl_shdw_update         = '0;
assign soc_pcie_if.ctl_shdw_pf_num         = '0;
assign soc_pcie_if.ctl_shdw_vf_num         = '0;
assign soc_pcie_if.ctl_shdw_vf_active      = '0;
assign soc_pcie_if.ctl_shdw_cfg            = '0;

//todo
assign soc_pcie_if.bus_num_f0           = soc_bus_num;
assign soc_pcie_if.bus_num_f1           = 'h0;
assign soc_pcie_if.device_num_f0        = soc_device_num;
assign soc_pcie_if.device_num_f1        = 'h0;
assign soc_pcie_if.pf_max_payload_size  = soc_max_payload_size;
assign soc_pcie_if.pf_rd_req_size       = soc_max_rd_req_size;

//tie off signals that the model does not handle
assign soc_pcie_if.flr_active_pf   = '1;
assign soc_pcie_if.flr_rcvd_vf     = '0;
assign soc_pcie_if.flr_rcvd_pf_num = '0;
assign soc_pcie_if.flr_rcvd_vf_num = '0;


assign host_pcie_if.rx_st_data = host_rx_st_data;
assign host_pcie_if.rx_st_empty = host_rx_st_empty;
assign host_pcie_if.rx_st_sop = host_rx_st_sop;
assign host_pcie_if.rx_st_eop = host_rx_st_eop;
assign host_pcie_if.rx_st_valid = host_rx_st_valid;
assign host_rx_st_ready = host_pcie_if.rx_st_ready;
assign host_pcie_if.rx_st_bar_range = host_rx_st_bar_range;

clear_x #(.DW(NUM_DATASEGS*DATASEG_WIDTH))u_host_tx_st_data_clearx (.in(host_pcie_if.tx_st_data), .out(host_tx_st_data));
clear_x #(.DW(NUM_DATASEGS*$clog2(DATASEG_WIDTH/64)))            u_host_tx_st_empty_clearx (.in(host_pcie_if.tx_st_empty), .out(host_tx_st_empty));
clear_x #(.DW(NUM_DATASEGS))              u_host_tx_st_sop_clearx (.in(host_pcie_if.tx_st_sop), .out(host_tx_st_sop));
clear_x #(.DW(NUM_DATASEGS))              u_host_tx_st_eop_clearx (.in(host_pcie_if.tx_st_eop), .out(host_tx_st_eop));
clear_x #(.DW(NUM_DATASEGS))              u_host_tx_st_valid_clearx (.in(host_pcie_if.tx_st_valid), .out(host_tx_st_valid));
clear_x #(.DW(NUM_DATASEGS))              u_host_tx_st_err_clearx (.in(host_pcie_if.tx_st_err), .out(host_tx_st_err));
assign host_pcie_if.tx_st_ready = host_tx_st_ready;

//todo
assign host_pcie_if.tx_cred_fc_infinite = 6'b111111;
assign host_pcie_if.tx_cred_fc_hip_cons = 'h0;
assign host_pcie_if.tx_cred_hdr_fc = 'h40;
assign host_pcie_if.tx_cred_data_fc = 'h80;


//set the cfg (these should come from decoding the hip tl_cfg/cii)
//assign soc_pcie_if.currentspeed          = '0;
assign host_pcie_if.ltssmstate           = 'h11;  //L1
//assign soc_pcie_if.dl_up                 = '1;
//assign soc_pcie_if.link_up               = '1;
//assign soc_pcie_if.timer_update          = '0;

assign host_pcie_if.msix_ack                = 0;
assign host_pcie_if.msix_err                = '0;
assign host_pcie_if.msix_en_pf              = '0;
assign host_pcie_if.msix_fn_mask_pf         = '0;
assign host_pcie_if.ko_cpl_spc_header       = 0;
assign host_pcie_if.ko_cpl_spc_data         = '0;
assign host_pcie_if.pf0_num_vfs             = '0;
assign host_pcie_if.pf1_num_vfs             = '0;
assign host_pcie_if.mem_space_en_pf         = '1;
assign host_pcie_if.bus_master_en_pf        = '1;
assign host_pcie_if.mem_space_en_vf         = '0;
assign host_pcie_if.ctl_shdw_update         = '0;
assign host_pcie_if.ctl_shdw_pf_num         = '0;
assign host_pcie_if.ctl_shdw_vf_num         = '0;
assign host_pcie_if.ctl_shdw_vf_active      = '0;
assign host_pcie_if.ctl_shdw_cfg            = '0;

//todo
assign host_pcie_if.bus_num_f0           = 'h0;
assign host_pcie_if.bus_num_f1           = 'h0;
assign host_pcie_if.device_num_f0        = 'h0;
assign host_pcie_if.device_num_f1        = 'h0;
assign host_pcie_if.pf_max_payload_size  = 'h0;
assign host_pcie_if.pf_rd_req_size       = 'h0;

//tie off signals that the model does not handle
assign host_pcie_if.flr_active_pf   = '1;
assign host_pcie_if.flr_rcvd_vf     = '0;
assign host_pcie_if.flr_rcvd_pf_num = '0;
assign host_pcie_if.flr_rcvd_vf_num = '0;

dpu_top #(
  .REG_ADDR_WIDTH(REG_ADDR_WIDTH),
  .REG_DATA_WIDTH(REG_DATA_WIDTH),
  .DW            (DW            ),
  .NUM_DATASEGS  (NUM_DATASEGS  ),
  .NUM_VF        (NUM_VF        ),
  .NUM_PF        (NUM_PF        )
) u_dpu_top (
  .soc_pcie_clk    (soc_pcie_clk        ),
  .soc_pcie_rst    (soc_pcie_rst        ),
  .host_pcie_clk    (host_pcie_clk      ),
  .host_pcie_rst    (host_pcie_rst      ),
  .fpga_user_reset  (fpga_user_reset    ), 
  .clk_200m    (clk_200m   ),
  .rst_200m    ({10{rst_200m}}   ),
  .clk_50m     (clk_50m    ),
  .rst_50m     (rst_50m    ),
  .clk_11m     (clk_11m    ),
  .rst_11m     (rst_11m    ),
  .alt_pcie_soc(soc_pcie_if),
  .alt_pcie_host(host_pcie_if),
  .soc_bus_num         (soc_bus_num          ),
  .soc_device_num      (soc_device_num       ),
  .soc_max_payload_size(soc_max_payload_size ),
  .soc_max_rd_req_size (soc_max_rd_req_size  ),
  .soc_tl_cfg_add(soc_tl_cfg_add),
  .soc_tl_cfg_ctl(soc_tl_cfg_ctl),
  .i2c_data_in (i2c_data_in),
  .i2c_clk_in  (i2c_clk_in ),
  .i2c_data_o  (i2c_data_o ),
  .i2c_clk_o   (i2c_clk_o  )
);
    
endmodule
