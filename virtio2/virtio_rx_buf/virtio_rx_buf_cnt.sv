/******************************************************************************
 * 文件名称 : virtio_rx_buf_cnt.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/12/02
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   12/02      Liuch       初始化版本
 ******************************************************************************/
module virtio_rx_buf_cnt #(
    parameter CNT_WIDTH = 16,
    parameter QID_NUM   = 256,

    localparam QID_WIDTH = $clog2(QID_NUM)
) (
    input  logic                 clk,
    input  logic                 rst,
    //
    input  logic                 update_vld,
    input  logic [QID_WIDTH-1:0] update_addr,
    //
    input  logic                 rd_req_vld,
    output logic                 rd_req_rdy,
    input  logic [QID_WIDTH-1:0] rd_req_addr,
    input  logic                 cnt_clr_en,
    //
    output logic                 rd_rsp_vld,
    output logic [CNT_WIDTH-1:0] rd_rsp_data,
    //
    output logic                 flush,
    output logic [1:0]           ram_err
);

    logic                 rx_buf_cnt_ram_wren;
    logic [QID_WIDTH-1:0] rx_buf_cnt_ram_waddr;
    logic [CNT_WIDTH-1:0] rx_buf_cnt_ram_wdata;
    logic [QID_WIDTH-1:0] rx_buf_cnt_ram_raddr;
    logic [CNT_WIDTH-1:0] rx_buf_cnt_ram_rdata;
    logic [1:0]           rx_buf_cnt_ram_err;


    logic                 ram_rden_up;
    logic [QID_WIDTH-1:0] flush_ram_addr;


    sync_simple_dual_port_ram_blk_write_first_ppl #(
        .DATAA_WIDTH(CNT_WIDTH),
        .ADDRA_WIDTH(QID_WIDTH),
        .DATAB_WIDTH(CNT_WIDTH),
        .ADDRB_WIDTH(QID_WIDTH),
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u_rx_buf_cnt_ram (
        .clk           (clk),
        .rst           (rst),
        .wea           (rx_buf_cnt_ram_wren),
        .addra         (rx_buf_cnt_ram_waddr),
        .dina          (rx_buf_cnt_ram_wdata),
        .addrb         (rx_buf_cnt_ram_raddr),
        .doutb         (rx_buf_cnt_ram_rdata),
        .parity_ecc_err(rx_buf_cnt_ram_err)
    );


    always @(posedge clk) begin
        if (rst) begin
            flush          <= 1'b1;
            flush_ram_addr <= {QID_WIDTH{1'b0}};
        end else if (flush) begin
            flush_ram_addr <= flush_ram_addr + 1'b1;

            if (flush_ram_addr == QID_NUM - 1) begin
                flush <= 1'b0;
            end
        end
    end


    always @(*) begin
        if (flush) begin
            rx_buf_cnt_ram_raddr = flush_ram_addr;
        end else if (update_vld) begin
            rx_buf_cnt_ram_raddr = update_addr;
        end else begin
            rx_buf_cnt_ram_raddr = rd_req_addr;
        end
    end

    assign rd_req_rdy = !flush & !update_vld;

    // assign ram_rden_up = !flush && (update_vld || (rd_req_vld && cnt_clr_en));

    always @(posedge clk) begin
        ram_rden_up <= 1'b0;
        if (!flush) begin
            if (update_vld) begin
                ram_rden_up <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (flush) begin
            rx_buf_cnt_ram_wren  <= 1'b1;
            rx_buf_cnt_ram_waddr <= flush_ram_addr;
        end else if (update_vld || (rd_req_vld && cnt_clr_en)) begin
            rx_buf_cnt_ram_wren  <= 1'b1;
            rx_buf_cnt_ram_waddr <= update_vld ? update_addr : rd_req_addr;
        end else begin
            rx_buf_cnt_ram_wren <= 1'b0;
        end
    end

    assign rx_buf_cnt_ram_wdata = ram_rden_up ? (rx_buf_cnt_ram_rdata + 1'b1) : {CNT_WIDTH{1'b0}};


    always @(posedge clk) begin
        rd_rsp_vld <= rd_req_vld && rd_req_rdy && !cnt_clr_en;
    end
    assign rd_rsp_data = rx_buf_cnt_ram_rdata;

    assign ram_err     = rx_buf_cnt_ram_err;

endmodule : virtio_rx_buf_cnt
