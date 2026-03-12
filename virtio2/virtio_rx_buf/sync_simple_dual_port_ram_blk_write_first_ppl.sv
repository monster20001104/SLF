module sync_simple_dual_port_ram_blk_write_first_ppl #(
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

    logic                   wea_flag;
    logic                   wea_d;
    logic [DATAA_WIDTH-1:0] dina_d;
    logic [ADDRA_WIDTH-1:0] addra_d;


    logic [DATAA_WIDTH-1:0] ram_dina;
    logic [ADDRA_WIDTH-1:0] ram_addra;
    logic                   ram_wea;
    logic [DATAB_WIDTH-1:0] ram_doutb;
    logic [ADDRB_WIDTH-1:0] ram_addrb;

    always @(posedge clk) begin
        if (wea && addra == addrb) begin
            wea_flag <= 'b1;
        end else begin
            wea_flag <= 'b0;
        end
    end

    always @(posedge clk) begin
        wea_d   <= wea;
        addra_d <= addra;
        dina_d  <= dina;
    end

    sync_simple_dual_port_ram_blk_write_first #(
        .DATAA_WIDTH(DATAA_WIDTH),
        .ADDRA_WIDTH(ADDRA_WIDTH),
        .DATAB_WIDTH(DATAB_WIDTH),
        .ADDRB_WIDTH(ADDRB_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) write_first_blk_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .dina          (ram_dina),
        .addra         (ram_addra),
        .wea           (ram_wea),
        //
        .doutb         (ram_doutb),
        .addrb         (ram_addrb),
        //
        .parity_ecc_err(parity_ecc_err)
    );

    assign ram_dina  = dina_d;
    assign ram_addra = addra_d;
    assign ram_wea   = wea_d;

    assign ram_addrb = addrb;
    assign doutb     = wea_flag ? dina_d : ram_doutb;

endmodule
