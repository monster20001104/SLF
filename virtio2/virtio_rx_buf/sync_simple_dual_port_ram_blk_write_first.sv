module sync_simple_dual_port_ram_blk_write_first #(
    parameter DATAA_WIDTH   = 32,
    parameter ADDRA_WIDTH   = 10,
    parameter DATAB_WIDTH   = 32,
    parameter ADDRB_WIDTH   = 10,
    parameter INIT          = 1,
    parameter ADD_INIT_FILE = "",
    parameter CHECK_ON      = 0,
    parameter CHECK_MODE    = "ecc",
    parameter CHECK_BIT     = 8
) (
    input  logic                   rst,
    input  logic                   clk,
    input  logic [DATAA_WIDTH-1:0] dina,
    input  logic [ADDRA_WIDTH-1:0] addra,
    input  logic                   wea,
    input  logic [ADDRB_WIDTH-1:0] addrb,
    output logic [DATAB_WIDTH-1:0] doutb,
    output logic [1:0]             parity_ecc_err
);

    logic [DATAB_WIDTH-1:0] doutb_raw;
    logic [DATAA_WIDTH-1:0] dina_sync;
    logic                   wr_rd_conflict;

    always @(posedge clk) begin
        if (rst) begin
            wr_rd_conflict <= '0;
            dina_sync      <= '0;
        end else begin
            wr_rd_conflict <= addra === addrb && wea;
            dina_sync      <= dina;
        end
    end


    assign doutb          = wr_rd_conflict ? dina_sync : doutb_raw;

    sync_simple_dual_port_ram #(
        .RAM_MODE  ("blk"),
        .REG_EN    (0),
        .WRITE_MODE("READ_FIRST"),

        .DATAA_WIDTH  (DATAA_WIDTH),
        .ADDRA_WIDTH  (ADDRA_WIDTH),
        .DATAB_WIDTH  (DATAB_WIDTH),
        .ADDRB_WIDTH  (ADDRB_WIDTH),
        .INIT         (INIT),
        .ADD_INIT_FILE(ADD_INIT_FILE),
        .CHECK_ON     (CHECK_ON),
        .CHECK_MODE   (CHECK_MODE),
        .CHECK_BIT    (CHECK_BIT)
    ) u_underlying_blk_ram (
        .rst           (rst),
        .clk           (clk),
        .dina          (dina),
        .addra         (addra),
        .wea           (wea),
        .addrb         (addrb),
        .doutb         (doutb_raw),
        .parity_ecc_err(parity_ecc_err)
    );

endmodule
