/******************************************************************************
 * 文件名称 : mgmt_tb.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2024/10/24
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  10/24     Joe Jiang   初始化版本
 ******************************************************************************/

module mgmt_tb #(
    parameter                                ADDR_WIDTH  = 22,   //! Width of SW address bus
    parameter                                DATA_WIDTH  = 64    //! Width of SW data bus
)(
    input                               clk          ,
    input                               rst          ,

    input                               clk_50m      ,
    input                               rst_50m      ,

    input                               clk_11m      ,
    input                               rst_11m      ,

    output logic                        csr_if_ready ,
    input  logic                        csr_if_valid ,
    input  logic                        csr_if_read  ,
    input  logic [ADDR_WIDTH-1:0]       csr_if_addr  ,
    input  logic [DATA_WIDTH-1:0]       csr_if_wdata ,
    input  logic [DATA_WIDTH/8-1:0]     csr_if_wmask ,
    output logic [DATA_WIDTH-1:0]       csr_if_rdata ,
    output logic                        csr_if_rvalid,
    input  logic                        csr_if_rready,

    input  wire                         i2c_data_in  ,
    input  wire                         i2c_clk_in   , 
    output wire                         i2c_data_o   , 
    output wire                         i2c_clk_o    ,
    input  wire                         bmc_i2c_data_in  ,
    input  wire                         bmc_i2c_clk_in   , 
    output wire                         bmc_i2c_data_o   , 
    output wire                         bmc_i2c_clk_o   
);

 initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, mgmt_tb, "+all");
    $fsdbDumpMDA();//sim_top.u_happy_digital_top.AFE_DSP_DATA);//存储所有的memeory值
end

mlite_if #(.ADDR_WIDTH(64), .DATA_WIDTH(DATA_WIDTH)) csr_if();

    logic pll_rst;
    logic [4:0] pll_rst_cnt = 'h0;

    always @(posedge clk) begin
        if (~&pll_rst_cnt) begin
            pll_rst_cnt <= pll_rst_cnt + 5'd1;
        end
    end

    assign pll_rst = ~&pll_rst_cnt;

assign csr_if_ready     = csr_if.ready;
assign csr_if.valid     = csr_if_valid;
assign csr_if.read      = csr_if_read;
assign csr_if.addr      = csr_if_addr;
assign csr_if.wdata     = csr_if_wdata;
assign csr_if.wmask     = csr_if_wmask;
assign csr_if_rdata     = csr_if.rdata;
assign csr_if_rvalid    = csr_if.rvalid;
assign csr_if.rready    = csr_if_rready;

mgmt #(
    .ADDR_WIDTH(ADDR_WIDTH),   
    .DATA_WIDTH(DATA_WIDTH)
)u_mgmt(
    .clk        (clk        ),
    .rst        (rst        ),
    .clk_50m    (clk_50m    ),
    .rst_50m    (rst_50m    ),
    .clk_11m    (clk_11m    ),
    .rst_11m    (rst_11m    ),
    .csr_if     (csr_if     ),
    .i2c_data_in(i2c_data_in),
    .i2c_clk_in (i2c_clk_in ), 
    .i2c_data_o (i2c_data_o ), 
    .i2c_clk_o  (i2c_clk_o  ),
    .bmc_i2c_data_in(bmc_i2c_data_in),
    .bmc_i2c_clk_in (bmc_i2c_clk_in ), 
    .bmc_i2c_data_o (bmc_i2c_data_o ), 
    .bmc_i2c_clk_o  (bmc_i2c_clk_o  )
);
    
endmodule