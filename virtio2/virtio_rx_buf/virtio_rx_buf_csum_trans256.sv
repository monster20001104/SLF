/******************************************************************************
 * 文件名称 : virtio_rx_buf_csum_trans256.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/07/16
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   07/16      Liuch       初始化版本
 ******************************************************************************/
module virtio_rx_buf_csum_trans256 #(
    parameter DATA_WIDTH  = 256,                    //do not change 
    parameter EMPTH_WIDTH = $clog2(DATA_WIDTH / 8)
) (
    input  logic                   clk,
    input  logic                   rst,
    input  logic [DATA_WIDTH-1:0]  data,
    input  logic                   vld,
    input  logic                   sop,
    input  logic                   eop,
    input  logic [EMPTH_WIDTH-1:0] mty,
    input  logic                   vlan,
    input  logic                   ipv4,
    input  logic [15:0]            ipv4_pkt_len,
    output logic [15:0]            trans_csum,
    output logic                   trans_csum_vld,
    output logic [1:0]             rom_err
);

    logic [1:0]                         trans_csum_cnt;
    logic [1:0]                         trans_csum_cnt_old;
    logic [1:0]                         trans_csum_cnt_new;
    logic [(DATA_WIDTH/8)-1:0]          mask;
    logic [(DATA_WIDTH/8)-1:0]          mask_eop;
    logic [4:0]                         mask_rom_addr;
    logic [(DATA_WIDTH/16)-1:0]         mask_rom_data;
    logic [(DATA_WIDTH/8)-1:0]          mask_rom_data_r;
    logic [1:0]                         mask_rom_err;

    logic [(DATA_WIDTH/8)-1:0][8-1:0]   unmask_data;
    logic [(DATA_WIDTH/8)-1:0][8-1:0]   masked_data;

    logic [DATA_WIDTH-1:0]              adder_in_data;
    logic                               adder_in_vld;
    logic [16+4-1:0]                    adder_out_data;
    logic                               adder_out_vld;

    assign rom_err        = mask_rom_err;
    assign mask_rom_addr  = {1'b0, vlan, ipv4, trans_csum_cnt};
    assign trans_csum_cnt = vld ? trans_csum_cnt_new : trans_csum_cnt_old;
    assign mask_eop       = eop ? {(DATA_WIDTH / 8) {1'b1}} << mty : {(DATA_WIDTH / 8) {1'b1}};
    assign mask           = mask_eop & mask_rom_data_r;

    generate
        genvar i0;
        begin : MASK_ROM
            for (i0 = 0; i0 < DATA_WIDTH / 16; i0 = i0 + 1) begin
                assign mask_rom_data_r[i0*2+:2] = mask_rom_data[i0] ? 2'b11 : 2'b00;
            end
        end
    endgenerate


    always @(*) begin
        unmask_data = data;
        if (trans_csum_cnt_old == 'd0) begin
            case ({
                vlan, ipv4
            })
                'b00: unmask_data = {data[06*16+:10*16], 8'b0, data[05*16+08+:08], data[00+:05*16]};
                'b01: unmask_data = {data[08*16+:08*16], ipv4_pkt_len, data[05*16+:2*16], 8'b0, data[04*16+:08], data[00+:04*16]};
                'b10: unmask_data = {data[04*16+:10*16], 8'b0, data[03*16+08+:08], data[00+:03*16]};
                'b11: unmask_data = {data[06*16+:08*16], ipv4_pkt_len, data[03*16+:2*16], 8'b0, data[02*16+:08], data[00+:02*16]};
                default: unmask_data = data;
            endcase
        end
    end


    always @(posedge clk) begin
        if (rst || (eop && vld)) begin
            trans_csum_cnt_old <= 'b0;
            trans_csum_cnt_new <= 'b1;
        end else if (vld) begin
            trans_csum_cnt_old <= trans_csum_cnt_new;
            if (trans_csum_cnt_new != 'd3) begin
                trans_csum_cnt_new <= trans_csum_cnt_new + 'd1;
            end
        end
    end


    generate
        genvar i1;
        begin : DATA_MASK
            for (i1 = 0; i1 < DATA_WIDTH / 8; i1 = i1 + 1) begin
                assign masked_data[i1] = mask[i1] ? unmask_data[i1] : 'd0;
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

    logic         sop_stage1;
    logic [4:0]   sop_shift1_5;
    logic         sop_stage5;
    logic         sop_stage6;
    logic         sop_stage7;

    logic         eop_stage1;
    logic [4:0]   eop_shift1_5;
    logic         eop_stage5;
    logic         eop_stage6;
    logic         eop_stage7;

    logic [255:0] data_stage1;
    logic [19:0]  data_stage5;
    logic [16:0]  data_stage6;
    logic [15:0]  data_stage7;
    logic [16:0]  data_stage7_d;
    logic [16:0]  data_stage8;
    logic [15:0]  data_stage9;

    always @(posedge clk) begin
        vld_stage1 <= vld;
        sop_stage1 <= vld && sop;
        eop_stage1 <= vld && eop;
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

    assign sop_shift1_5[0] = sop_stage1;
    assign eop_shift1_5[0] = eop_stage1;
    always @(posedge clk) begin
        sop_shift1_5[4:1] <= sop_shift1_5[3:0];
        eop_shift1_5[4:1] <= eop_shift1_5[3:0];
    end
    // stage 4 -> 5
    assign vld_stage5  = adder_out_vld;
    assign sop_stage5  = sop_shift1_5[4];
    assign eop_stage5  = eop_shift1_5[4];
    assign data_stage5 = adder_out_data;


    always @(posedge clk) begin
        if (vld_stage5) begin
            vld_stage6  <= 'd1;
            sop_stage6  <= sop_stage5;
            eop_stage6  <= eop_stage5;
            data_stage6 <= data_stage5[15:0] + data_stage5[19:16];
        end else begin
            vld_stage6 <= 'd0;
        end
    end
    always @(posedge clk) begin
        if (vld_stage6) begin
            vld_stage7  <= 'd1;
            sop_stage7  <= sop_stage6;
            eop_stage7  <= eop_stage6;
            data_stage7 <= data_stage6[15:0] + data_stage6[16];
        end else begin
            vld_stage7 <= 'd0;
        end
    end

    always @(posedge clk) begin
        if (vld_stage7) begin
            if (sop_stage7) begin
                data_stage7_d <= {1'b0, data_stage7};
            end else begin
                data_stage7_d <= data_stage7 + data_stage7_d[15:0] + data_stage7_d[16];
            end
        end
    end

    always @(posedge clk) begin
        if (vld_stage7 && eop_stage7) begin
            vld_stage8 <= 1'b1;
            if (sop_stage7) begin
                data_stage8 <= {1'b0, data_stage7};
            end else begin
                data_stage8 <= data_stage7 + data_stage7_d[15:0] + data_stage7_d[16];
            end
        end else begin
            vld_stage8 <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (vld_stage8) begin
            vld_stage9  <= 'd1;
            data_stage9 <= data_stage8[16] + data_stage8[15:0];
        end else begin
            vld_stage9 <= 'd0;
        end
    end


    assign trans_csum     = data_stage9;
    assign trans_csum_vld = vld_stage9;





    single_port_ram #(
        .DATA_WIDTH   (16),
        .ADDR_WIDTH   (5),
        .REG_EN       (0),
        .INIT         (0),
        .WRITE_MODE   ("NO_CHANGE"),
        .ADD_INIT_FILE("../../../src/virtio2/virtio_rx_buf/virtio_rx_buf_csum_trans256_converted.mif"),
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
endmodule : virtio_rx_buf_csum_trans256
