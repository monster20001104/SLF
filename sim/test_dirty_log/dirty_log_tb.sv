/***************************************************
* 文件名称 : dirty_log_tb
* 作者名称 : 崔飞翔
* 创建日期 : 2025/08/07
* 功能描述 : 
* 
* 修改记录 : 
* 
* 修改日期 : 2025/08/07
* 版本号    修改人    修改内容
* v1.0     崔飞翔     初始化版本
***************************************************/

module dirty_log_tb     
    import alt_tlp_adaptor_pkg::*;
#(
    parameter   REG_ADDR_WIDTH  	= 23    ,
    parameter   REG_DATA_WIDTH  	= 64    ,
    parameter   LOOP_WIDTH          = 104   ,
    parameter   DATA_WIDTH          = 256   ,
    parameter   TY_WIDTH            = DATA_WIDTH==512 ? 6 : 5
)(

    input  wire                                 clk                 ,
    input  wire                                 rst                 ,  

    output	logic                               cdc_wr_req_sav		,             
    input 	logic                               cdc_wr_req_val		,             
    input 	logic                               cdc_wr_req_sop		,             
    input 	logic                               cdc_wr_req_eop		,             
    input 	logic	[DATA_WIDTH-1:0]            cdc_wr_req_data		,            
    input 	logic	[TY_WIDTH-1:0]              cdc_wr_req_sty		,             
    input 	logic	[TY_WIDTH-1:0]              cdc_wr_req_mty		,             
    input  	logic   [$bits(desc_t)-1:0]         cdc_wr_req_desc		,            

    input	logic                               pcie_wr_req_sav		,             
    output 	logic                               pcie_wr_req_val		,             
    output 	logic                               pcie_wr_req_sop		,             
    output 	logic                               pcie_wr_req_eop		,             
    output 	logic	[DATA_WIDTH-1:0]            pcie_wr_req_data	,            
    output 	logic	[TY_WIDTH-1:0]              pcie_wr_req_sty		,             
    output 	logic	[TY_WIDTH-1:0]              pcie_wr_req_mty		,             
    output  logic   [$bits(desc_t)-1:0]         pcie_wr_req_desc	,  

    input	logic	[LOOP_WIDTH-1:0]            pcie_wr_rsp_rd2rsp_loop ,
    input   logic                               pcie_wr_rsp_dirty_log   ,
    input	logic                               pcie_wr_rsp_val		    , 
    output	logic                               pcie_wr_rsp_sav		    ,

    output	logic	[LOOP_WIDTH-1:0]            cdc_wr_rsp_rd2rsp_loop  ,
    output	logic                               cdc_wr_rsp_val		    , 
    input	logic                               cdc_wr_rsp_sav		    ,


    output logic                                csr_if_ready               ,
    input  logic                                csr_if_valid               ,
    input  logic                                csr_if_read                ,
    input  logic  [REG_ADDR_WIDTH-1:0]          csr_if_addr                ,
    input  logic  [REG_DATA_WIDTH-1:0]          csr_if_wdata               ,
    input  logic  [REG_DATA_WIDTH/8-1:0]        csr_if_wmask               ,
    output logic  [REG_DATA_WIDTH-1:0]          csr_if_rdata               ,
    output logic                                csr_if_rvalid              ,
    input  logic                                csr_if_rready              
);
initial begin
    $fsdbAutoSwitchDumpfile(1000, "top.fsdb", 100);
    $fsdbDumpvars(0, dirty_log_tb, "+all");
    $fsdbDumpMDA();//sim_top.u_happy_digital_top.AFE_DSP_DATA);//存储所有的memeory值
end

mlite_if                #(.DATA_WIDTH(REG_DATA_WIDTH))    csr_if();

assign csr_if_ready                = csr_if.ready;
assign csr_if.valid                = csr_if_valid;
assign csr_if.read                 = csr_if_read;
assign csr_if.addr                 = csr_if_addr;
assign csr_if.wdata                = csr_if_wdata;
assign csr_if.wmask                = csr_if_wmask;
assign csr_if_rdata                = csr_if.rdata;
assign csr_if_rvalid               = csr_if.rvalid;
assign csr_if.rready               = csr_if_rready;


dirty_log_top#(
    .REG_ADDR_WIDTH           ( REG_ADDR_WIDTH ),
    .REG_DATA_WIDTH           ( REG_DATA_WIDTH ),
    .LOOP_WIDTH               ( LOOP_WIDTH     ),
    .DATA_WIDTH               ( DATA_WIDTH     ),
    .TY_WIDTH                 ( TY_WIDTH       )
)u_dirty_log_top(
    .clk_i                    ( clk                      ),
    .srst_i                   ( rst                      ),
    .cdc_wr_req_sav           ( cdc_wr_req_sav           ),
    .cdc_wr_req_val           ( cdc_wr_req_val           ),
    .cdc_wr_req_sop           ( cdc_wr_req_sop           ),
    .cdc_wr_req_eop           ( cdc_wr_req_eop           ),
    .cdc_wr_req_data          ( cdc_wr_req_data          ),
    .cdc_wr_req_sty           ( cdc_wr_req_sty           ),
    .cdc_wr_req_mty           ( cdc_wr_req_mty           ),
    .cdc_wr_req_desc          ( cdc_wr_req_desc          ),
    .pcie_wr_req_sav          ( pcie_wr_req_sav          ),
    .pcie_wr_req_val          ( pcie_wr_req_val          ),
    .pcie_wr_req_sop          ( pcie_wr_req_sop          ),
    .pcie_wr_req_eop          ( pcie_wr_req_eop          ),
    .pcie_wr_req_data         ( pcie_wr_req_data         ),
    .pcie_wr_req_sty          ( pcie_wr_req_sty          ),
    .pcie_wr_req_mty          ( pcie_wr_req_mty          ),
    .pcie_wr_req_desc         ( pcie_wr_req_desc         ),
    .pcie_wr_rsp_rd2rsp_loop  ( pcie_wr_rsp_rd2rsp_loop  ),
    .pcie_wr_rsp_dirty_log    ( pcie_wr_rsp_dirty_log    ),
    .pcie_wr_rsp_val          ( pcie_wr_rsp_val          ),
    .pcie_wr_rsp_sav          ( pcie_wr_rsp_sav          ),
    .cdc_wr_rsp_rd2rsp_loop   ( cdc_wr_rsp_rd2rsp_loop   ),
    .cdc_wr_rsp_val           ( cdc_wr_rsp_val           ),
    .cdc_wr_rsp_sav           ( cdc_wr_rsp_sav           ),
    .csr_if                   ( csr_if                   )
);



endmodule