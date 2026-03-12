`include "mlite_if.svh"
module basic_warp #(
    parameter                                ADDR_OFFSET = 0,  //! Module's offset in the main address map
    parameter                                ADDR_WIDTH  = 32,   //! Width of SW address bus
    parameter                                DATA_WIDTH  = 32    //! Width of SW data bus
)(
    // Clocks and resets
    input logic                              clk,     //! Default clock
    input logic                              rst,  //! Default reset

    output logic                     [31: 0] test1_test1_q,              //! Current field value
    output logic                             test2_test2_swmod,          //! Indicates SW has modified this field
    output logic                     [31: 0] test2_test2_q,              //! Current field value
    input  logic                             test3_test2_hwclr,          //! Set all bits low
    output logic                     [31: 0] test3_test2_q,              //! Current field value
    input  logic                     [31: 0] test4_test3_wdata,          //! HW write data
    input  logic                             test5_test3_we,             //! Control HW write (active high)
    input  logic                     [31: 0] test5_test3_wdata,          //! HW write data

    // Register Bus
    output logic                             csr_if_ready,
    input  logic                             csr_if_valid,
    input  logic                             csr_if_read,
    input  logic [ADDR_WIDTH-1:0]            csr_if_addr,
    input  logic [DATA_WIDTH-1:0]            csr_if_wdata,
    input  logic [DATA_WIDTH/8-1:0]          csr_if_wmask,
    output logic [DATA_WIDTH-1:0]            csr_if_rdata,
    output logic                             csr_if_rvalid,
    input  logic                             csr_if_rready

);

 initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, basic_warp, "+all");
    $fsdbDumpMDA();//sim_top.u_happy_digital_top.AFE_DSP_DATA);//存储所有的memeory值
end

mlite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) csr_if();

test #(
    .ADDR_OFFSET(ADDR_OFFSET),
    .ADDR_WIDTH (ADDR_WIDTH ),
    .DATA_WIDTH (DATA_WIDTH )
)u_basic(
    .clk                        (clk                      ),     //! Default clock
    .rst                        (rst                      ),  //! Default reset
    .test1_test1_q              (test1_test1_q            ),    
    .test2_test2_swmod          (test2_test2_swmod        ),
    .test2_test2_q              (test2_test2_q            ),    
    .test3_test2_hwclr          (test3_test2_hwclr        ),
    .test3_test2_q              (test3_test2_q            ),    
    .test4_test3_wdata          (test4_test3_wdata        ),
    .test5_test3_we             (test5_test3_we           ),   
    .test5_test3_wdata          (test5_test3_wdata        ),
    .csr_if                     (csr_if                   )
);

assign csr_if_ready     = csr_if.ready;
assign csr_if.valid     = csr_if_valid;
assign csr_if.read      = csr_if_read;
assign csr_if.addr      = csr_if_addr;
assign csr_if.wdata     = csr_if_wdata;
assign csr_if.wmask     = csr_if_wmask;
assign csr_if_rdata     = csr_if.rdata;
assign csr_if_rvalid    = csr_if.rvalid;
assign csr_if.rready    = csr_if_rready;
    
endmodule