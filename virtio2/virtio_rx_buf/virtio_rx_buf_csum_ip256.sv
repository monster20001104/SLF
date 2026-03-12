/******************************************************************************
 * 文件名称 : virtio_rx_buf_csum_ip256.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/07/16
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   07/16      Liuch       初始化版本
 ******************************************************************************/
module virtio_rx_buf_csum_ip256 #(
    parameter DATA_WIDTH = 256  //do not change 
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic [DATA_WIDTH-1:0] data,
    input  logic                  vld,
    input  logic                  sop,
    input  logic                  eop,
    input  logic                  vlan,
    output logic [15:0]           ip_csum,
    output logic                  ip_csum_vld,
    output logic [1:0]            rom_err
);

    logic [1:0]                         ip_csum_cnt;
    logic [1:0]                         ip_csum_cnt_old;
    logic [1:0]                         ip_csum_cnt_new;
    logic [(DATA_WIDTH/16)-1:0]         mask;
    logic [4:0]                         mask_rom_addr;
    logic [(DATA_WIDTH/16)-1:0]         mask_rom_data;
    logic [1:0]                         mask_rom_err;
    logic [(DATA_WIDTH/16)-1:0][16-1:0] unmask_data;
    logic [(DATA_WIDTH/16)-1:0][16-1:0] masked_data;

    logic [DATA_WIDTH-1:0]              adder_in_data;
    logic                               adder_in_vld;
    logic [16+4-1:0]                    adder_out_data;
    logic                               adder_out_vld;
    logic [15:0]                        sop_shift;

    assign rom_err       = mask_rom_err;
    assign mask_rom_addr = {2'b0, vlan, ip_csum_cnt};
    assign ip_csum_cnt   = vld ? ip_csum_cnt_new : ip_csum_cnt_old;
    assign unmask_data   = data;
    assign mask          = mask_rom_data;


    always @(posedge clk) begin
        if (rst || (eop && vld)) begin
            ip_csum_cnt_old <= 'b0;
            ip_csum_cnt_new <= 'b1;
        end else if (vld) begin
            ip_csum_cnt_old <= ip_csum_cnt_new;
            if (ip_csum_cnt_new != 'd3) begin
                ip_csum_cnt_new <= ip_csum_cnt_new + 'd1;
            end
        end
    end

    generate
        genvar i;
        begin : DATA_MASK
            for (i = 0; i < DATA_WIDTH / 16; i = i + 1) begin
                assign masked_data[i] = mask[i] ? unmask_data[i] : 'd0;
            end
        end
    endgenerate

    ////////////////////////////////////////////////////////////////////////////
    // stage
    logic         vld_stage1;
    logic         vld_stage5;
    logic         vld_stage6;
    logic         vld_stage7;
    logic         vld_stage8;
    logic         vld_stage9;
    logic [255:0] data_stage1;
    logic [19:0]  data_stage5;
    logic [19:0]  data_stage5_d;
    logic [20:0]  data_stage6;
    logic [16:0]  data_stage7;
    logic [15:0]  data_stage8;
    logic [15:0]  data_stage9;

    always @(posedge clk) begin
        vld_stage1 <= ip_csum_cnt_old[1] == 'd0 && vld;
        data_stage1 <= masked_data;
    end


    assign adder_in_data = data_stage1;
    assign adder_in_vld  = vld_stage1;  // 2 pai

    adder_tree #(
        .WIDTH(16),
        .DEPTH(4)    // depth = 4  stage1 -> stage5
    ) u_adder_tree (
        .clk     (clk),
        .rst     (rst),
        .in_data (adder_in_data),
        .in_vld  (adder_in_vld),
        .in_pause(1'b0),
        .out_sum (adder_out_data),
        .out_vld (adder_out_vld)
    );

    assign sop_shift[0] = sop && vld;
    always @(posedge clk) begin
        sop_shift[15:1] <= sop_shift[14:0];
    end
    // stage 5 -> 6
    assign vld_stage5  = adder_out_vld && !sop_shift[5];
    assign data_stage5 = adder_out_data;
    always @(posedge clk) begin
        if (adder_out_vld) begin
            if (sop_shift[5]) begin
                data_stage5_d <= data_stage5;
            end
        end
    end
    always @(posedge clk) begin
        if (vld_stage5) begin
            vld_stage6  <= 'd1;
            data_stage6 <= data_stage5 + data_stage5_d;
        end else begin
            vld_stage6 <= 'd0;
        end
    end

    always @(posedge clk) begin
        if (vld_stage6) begin
            vld_stage7  <= 'd1;
            data_stage7 <= data_stage6[15:0] + data_stage6[19:16];
        end else begin
            vld_stage7 <= 'd0;
        end
    end
    always @(posedge clk) begin
        if (vld_stage7) begin
            vld_stage8  <= 'd1;
            data_stage8 <= data_stage7[15:0] + data_stage7[16];
        end else begin
            vld_stage8 <= 'd0;
        end
    end
    always @(posedge clk) begin
        if (vld_stage8) begin
            vld_stage9  <= 'd1;
            data_stage9 <= data_stage8;
        end else begin
            vld_stage9 <= 'd0;
        end
    end


    assign ip_csum     = data_stage9;
    assign ip_csum_vld = vld_stage9;





    single_port_ram #(
        .DATA_WIDTH   (16),
        .ADDR_WIDTH   (5),
        .REG_EN       (0),
        .INIT         (0),
        .WRITE_MODE   ("NO_CHANGE"),
        .ADD_INIT_FILE("../../../src/virtio2/virtio_rx_buf/virtio_rx_buf_csum_ip256_converted.mif"),
        .RAM_MODE     ("dist"),
        .CHECK_ON     (1),
        .CHECK_MODE   ("parity")
    ) u_mask_rom (
        .clk           (clk),
        .rst           (rst),
        .dina          (16'b0),
        .addra         (mask_rom_addr),
        .wea           (1'b0),
        .douta         (mask_rom_data),
        .parity_ecc_err(mask_rom_err)
    );
endmodule : virtio_rx_buf_csum_ip256
