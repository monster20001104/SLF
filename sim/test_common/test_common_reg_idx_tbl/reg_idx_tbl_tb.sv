


module reg_idx_tbl_tb #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64
) (

    input clk,
    input rst,

    input                     mlite_slave_valid,
    input                     mlite_slave_read,
    input  [  ADDR_WIDTH-1:0] mlite_slave_addr,
    input  [  DATA_WIDTH-1:0] mlite_slave_wdata,
    input  [DATA_WIDTH/8-1:0] mlite_slave_wmask,
    input                     mlite_slave_rready,
    output                    mlite_slave_ready,
    output                    mlite_slave_rvalid,
    output [  DATA_WIDTH-1:0] mlite_slave_rdata


);


    initial begin
        $fsdbDumpfile("top.fsdb");
        $fsdbDumpvars(0, reg_idx_tbl_tb, "+all");
        $fsdbDumpMDA();
    end


    mlite_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .CHANNEL_NUM(1)
    ) mlite_slave ();


    assign mlite_slave.valid  = mlite_slave_valid;
    assign mlite_slave.read   = mlite_slave_read;
    assign mlite_slave.addr   = mlite_slave_addr;
    assign mlite_slave.wdata  = mlite_slave_wdata;
    assign mlite_slave.wmask  = mlite_slave_wmask;
    assign mlite_slave.rready = mlite_slave_rready;

    assign mlite_slave_ready  = mlite_slave.ready;
    assign mlite_slave_rvalid = mlite_slave.rvalid;
    assign mlite_slave_rdata  = mlite_slave.rdata;


    reg_idx_tbl #(
        .REG_ADDR_WIDTH(ADDR_WIDTH),
        .REG_DATA_WIDTH(DATA_WIDTH)
    ) u_reg_idx_tbl (
        .clk   (clk),
        .rst   (rst),
        .csr_if(mlite_slave)
    );




endmodule
