
/*
 * Author       : Yunfeilong
 * Date         : 2024-08-21
 * Description  : mlite_crossbar_tb.sv
*/



module mlite_crossbar_tb #(
    parameter CHN_NUM = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64
)
(

    input                          clk,
    input                          rst,

    //input      [CHN_NUM-1:0]       chn_enable,
    
    input                          mlite_slave_valid,
    input                          mlite_slave_read,
    input      [ADDR_WIDTH-1:0]    mlite_slave_addr,
    input      [DATA_WIDTH-1:0]    mlite_slave_wdata,
    input      [DATA_WIDTH/8-1:0]  mlite_slave_wmask,
    input                          mlite_slave_rready,
    output                         mlite_slave_ready,
    output                         mlite_slave_rvalid,
    output     [DATA_WIDTH-1:0]    mlite_slave_rdata,


    output                         mlite_master0_valid,
    output                         mlite_master0_read,
    output     [ADDR_WIDTH-1:0]    mlite_master0_addr  ,
    output     [DATA_WIDTH-1:0]    mlite_master0_wdata ,
    output     [DATA_WIDTH/8-1:0]  mlite_master0_wmask  ,
    output                         mlite_master0_rready  ,
    input                          mlite_master0_ready,
    input                          mlite_master0_rvalid,
    input      [DATA_WIDTH-1:0]    mlite_master0_rdata  ,


    output                         mlite_master1_valid,
    output                         mlite_master1_read,
    output     [ADDR_WIDTH-1:0]    mlite_master1_addr  ,
    output     [DATA_WIDTH-1:0]    mlite_master1_wdata ,
    output     [DATA_WIDTH/8-1:0]  mlite_master1_wmask  ,
    output                         mlite_master1_rready  ,
    input                          mlite_master1_ready,
    input                          mlite_master1_rvalid,
    input      [DATA_WIDTH-1:0]    mlite_master1_rdata  ,


    output                         mlite_master2_valid,
    output                         mlite_master2_read,
    output     [ADDR_WIDTH-1:0]    mlite_master2_addr  ,
    output     [DATA_WIDTH-1:0]    mlite_master2_wdata ,
    output     [DATA_WIDTH/8-1:0]  mlite_master2_wmask  ,
    output                         mlite_master2_rready  ,
    input                          mlite_master2_ready,
    input                          mlite_master2_rvalid,
    input      [DATA_WIDTH-1:0]    mlite_master2_rdata  ,


    output                         mlite_master3_valid,
    output                         mlite_master3_read,
    output     [ADDR_WIDTH-1:0]    mlite_master3_addr  ,
    output     [DATA_WIDTH-1:0]    mlite_master3_wdata ,
    output     [DATA_WIDTH/8-1:0]  mlite_master3_wmask  ,
    output                         mlite_master3_rready  ,
    input                          mlite_master3_ready,
    input                          mlite_master3_rvalid,
    input      [DATA_WIDTH-1:0]    mlite_master3_rdata  

    
   /* 
    output     [CHN_NUM-1:0]       mlite_master_valid,
    output     [CHN_NUM-1:0]       mlite_master_read,
    output     [ADDR_WIDTH-1:0]    mlite_master_addr [CHN_NUM-1:0],
    output     [DATA_WIDTH-1:0]    mlite_master_wdata [CHN_NUM-1:0],
    output     [DATA_WIDTH/8-1:0]  mlite_master_wmask [CHN_NUM-1:0],
    output     [CHN_NUM-1:0]       mlite_master_rready [CHN_NUM-1:0],
    input      [CHN_NUM-1:0]       mlite_master_ready,
    input      [CHN_NUM-1:0]       mlite_master_rvalid,
    input      [DATA_WIDTH-1:0]    mlite_master_rdata [CHN_NUM-1:0],
*/
    //output reg [ADDR_WIDTH-1 :0]   chn_addr


);

logic [CHN_NUM-1:0]       chn_enable;
logic [ADDR_WIDTH-1 :0]   chn_addr;

assign chn_enable = chn_addr[15:14] == 0 ? 4'b0001 :
                    chn_addr[15:14] == 1 ? 4'b0010 : 
                    chn_addr[15:14] == 2 ? 4'b0100 :
                                           4'b1000 ;
                        

initial begin
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, mlite_crossbar_tb, "+all");
    $fsdbDumpMDA();
end


mlite_if #(.ADDR_WIDTH (ADDR_WIDTH), .DATA_WIDTH (DATA_WIDTH), .CHANNEL_NUM(1))   mlite_slave();
mlite_if #(.ADDR_WIDTH (ADDR_WIDTH), .DATA_WIDTH (DATA_WIDTH), .CHANNEL_NUM(1))   mlite_master[CHN_NUM]();

assign mlite_slave.valid = mlite_slave_valid;
assign mlite_slave.read = mlite_slave_read;
assign mlite_slave.addr = mlite_slave_addr;
assign mlite_slave.wdata = mlite_slave_wdata;
assign mlite_slave.wmask = mlite_slave_wmask;
assign mlite_slave.rready = mlite_slave_rready;

assign mlite_slave_ready = mlite_slave.ready;
assign mlite_slave_rvalid = mlite_slave.rvalid;
assign mlite_slave_rdata = mlite_slave.rdata;


assign mlite_master0_valid = mlite_master[0].valid;
assign mlite_master0_read = mlite_master[0].read;
assign mlite_master0_addr = mlite_master[0].addr;
assign mlite_master0_wdata = mlite_master[0].wdata;
assign mlite_master0_wmask = mlite_master[0].wmask;
assign mlite_master0_rready = mlite_master[0].rready;
assign mlite_master[0].ready = mlite_master0_ready;
assign mlite_master[0].rvalid = mlite_master0_rvalid;
assign mlite_master[0].rdata = mlite_master0_rdata;

assign mlite_master1_valid = mlite_master[1].valid;
assign mlite_master1_read = mlite_master[1].read;
assign mlite_master1_addr = mlite_master[1].addr;
assign mlite_master1_wdata = mlite_master[1].wdata;
assign mlite_master1_wmask = mlite_master[1].wmask;
assign mlite_master1_rready = mlite_master[1].rready;
assign mlite_master[1].ready = mlite_master1_ready;
assign mlite_master[1].rvalid = mlite_master1_rvalid;
assign mlite_master[1].rdata = mlite_master1_rdata;

assign mlite_master2_valid = mlite_master[2].valid;
assign mlite_master2_read = mlite_master[2].read;
assign mlite_master2_addr = mlite_master[2].addr;
assign mlite_master2_wdata = mlite_master[2].wdata;
assign mlite_master2_wmask = mlite_master[2].wmask;
assign mlite_master2_rready = mlite_master[2].rready;
assign mlite_master[2].ready = mlite_master2_ready;
assign mlite_master[2].rvalid = mlite_master2_rvalid;
assign mlite_master[2].rdata = mlite_master2_rdata;

assign mlite_master3_valid = mlite_master[3].valid;
assign mlite_master3_read = mlite_master[3].read;
assign mlite_master3_addr = mlite_master[3].addr;
assign mlite_master3_wdata = mlite_master[3].wdata;
assign mlite_master3_wmask = mlite_master[3].wmask;
assign mlite_master3_rready = mlite_master[3].rready;
assign mlite_master[3].ready = mlite_master3_ready;
assign mlite_master[3].rvalid = mlite_master3_rvalid;
assign mlite_master[3].rdata = mlite_master3_rdata;


mlite_crossbar#(
    .CHN_NUM (CHN_NUM),
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
)u_mlite_crossbar
(
    .clk          (clk),
    .rst          (rst),

    .chn_enable   (chn_enable),
    
    .slave        (mlite_slave),             
    .master       (mlite_master),   

    .chn_addr     (chn_addr)

);




endmodule