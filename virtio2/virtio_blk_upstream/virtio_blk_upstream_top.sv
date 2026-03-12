/******************************************************************************
 * 文件名称 : virtio_blk_upstream.sv
 * 作者名称 : cui naiwan
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/23     cui naiwan   初始化版本
 ******************************************************************************/
 `include "virtio_define.svh"
 `include "beq_data_if.svh"
 `include "tlp_adap_dma_if.svh"
 module virtio_blk_upstream_top 
 import alt_tlp_adaptor_pkg::*;
 #(
    parameter Q_NUM =256,
    parameter Q_WIDTH = $clog2(Q_NUM),
    parameter DATA_WIDTH = 256,
    parameter EMPTH_WIDTH = $clog2(DATA_WIDTH/8)
)(
    input                                       clk,
    input                                       rst,
    //===========from or to beq=======================//
    beq_txq_bus_if.snk                          beq2blk_if,
    //=============dma_data_wr_if=================//
    tlp_adap_dma_wr_req_if.src                  dma_data_wr_req_if,
    tlp_adap_dma_wr_rsp_if.snk                  dma_data_wr_rsp_if,
    //=========from or to virtio_used==============//
    output logic                                wr_used_info_vld,
    output virtio_used_info_t                   wr_used_info_dat,
    input  logic                                wr_used_info_rdy,
    //===========from or to ctx================//
    output logic                                blk_upstream_ctx_req_vld,
    output logic [Q_WIDTH-1:0]                  blk_upstream_ctx_req_qid, 
    
    input  logic                                blk_upstream_ctx_rsp_vld, 
    input  logic                                blk_upstream_ctx_rsp_forced_shutdown,
    input  logic [$bits(virtio_qstat_t)-1:0]    blk_upstream_ctx_rsp_q_status,
    input  logic [7:0]                          blk_upstream_ctx_rsp_generation,                 
    input  logic [9:0]                          blk_upstream_ctx_rsp_dev_id, 
    input  logic [15:0]                         blk_upstream_ctx_rsp_bdf, 

    output logic                                blk_upstream_ptr_rd_req_vld,
    output logic [Q_WIDTH-1:0]                  blk_upstream_ptr_rd_req_qid,
    input  logic                                blk_upstream_ptr_rd_rsp_vld,
    input  logic [15:0]                         blk_upstream_ptr_rd_rsp_dat,

    output logic                                blk_upstream_ptr_wr_req_vld,
    output logic [Q_WIDTH-1:0]                  blk_upstream_ptr_wr_req_qid,
    output logic [15:0]                         blk_upstream_ptr_wr_req_dat,

    //===========to beq===================//
    output logic                                blk_to_beq_cred_fc,                              
    //===========to mon===================//
    output virtio_vq_t                          mon_send_io_qid,
    output logic                                mon_send_io,

    mlite_if.slave                              dfx_if
);

    enum logic [5:0] {
        IDLE        = 6'b000001,
        RD_HEADER   = 6'b000100,
        WR_DATA_REQ = 6'b001000,
        DROP        = 6'b010000,
        WR_ORDER    = 6'b100000
    } wr_cstat, wr_nstat;

    enum logic [2:0] {
        USED_IDLE    = 3'b001,
        RD_RSP       = 3'b010,
        WR_USED_INFO = 3'b100
    } used_cstat, used_nstat;

    localparam DATA_FF_WIDTH = DATA_WIDTH + EMPTH_WIDTH*2 + 2;
    localparam INFO_FF_WIDTH = $bits(beq2blk_if.sbd.length);
    localparam WR_RSP_FF_WIDTH = $bits(dma_data_wr_rsp_if.rd2rsp_loop);
    
    typedef struct packed {
    virtio_vq_t             qid;
    logic                   dummy;
    logic                   flag;
    logic [15:0]            desc_index;
    logic [31:0]            used_length;
    logic [15:0]            used_idx;
    } virtio_blk_upstream_order_info_t;

    
    logic data_ff_empty, data_ff_wren, data_ff_pfull, data_ff_rden;
    logic [DATA_FF_WIDTH-1:0] data_ff_din, data_ff_dout;
    logic data_ff_dout_eop, data_ff_dout_sop;
    logic [EMPTH_WIDTH-1:0] data_ff_dout_sty, data_ff_dout_mty;
    logic [DATA_WIDTH-1:0] data_ff_dout_data;
    logic data_ff_overflow, data_ff_underflow;
    logic [1:0] data_ff_parity_ecc_err;
    logic info_ff_empty, info_ff_wren, info_ff_pfull, info_ff_rden;
    logic [INFO_FF_WIDTH-1:0] info_ff_din, info_ff_dout, info_ff_dout_length;
    logic info_ff_overflow, info_ff_underflow;
    logic [1:0] info_ff_parity_ecc_err;
    logic order_ff_empty, order_ff_wren, order_ff_pfull, order_ff_rden;
    virtio_blk_upstream_order_info_t order_ff_din, order_ff_dout, order_ff_dout_reg;
    logic order_ff_overflow, order_ff_underflow;
    logic [1:0] order_ff_parity_ecc_err;
    logic [3:0] order_used_idx, rsp_used_idx;
    logic wr_rsp_ff_empty, wr_rsp_ff_wren, wr_rsp_ff_pfull, wr_rsp_ff_rden;
    logic [WR_RSP_FF_WIDTH-1:0] wr_rsp_ff_din, wr_rsp_ff_dout, wr_rsp_ff_dout_reg;
    logic wr_rsp_ff_overflow, wr_rsp_ff_underflow;
    logic [1:0] wr_rsp_ff_parity_ecc_err;
    logic [7:0] data_ff_rd_cnt;
    logic [Q_WIDTH-1:0] buffer_header_qid;
    logic [7:0] buffer_header_vq_gen;
    logic [15:0] buffer_header_flags;
    logic [15:0] buffer_header_desc_index;
    logic [63:0] buffer_header_host_buf_addr;
    logic [15:0] buffer_header_magic_num;
    logic [15:0] buffer_header_used_idx;
    logic [31:0] buffer_header_used_length;
    logic [16:0] dfx_err, dfx_err_q;
    logic [20:0] dfx_status;
    logic [7:0] dma_data_wr_req_cnt, dma_data_wr_rsp_cnt;
    logic [9:0] dev_id;
    logic [15:0] bdf;
    logic forced_shutdown;
    logic [7:0] generation;
    logic [$bits(virtio_qstat_t)-1:0] q_status;
    logic [15:0] generation_not_match_drop_pkt_cnt, magic_num_not_match_drop_pkt_cnt, q_status_not_match_drop_pkt_cnt, forced_shutdown_drop_pkt_cnt, beq2blk_pkt_cnt, blk_upstream_tran_pkt_cnt, blk_upstream_drop_pkt_cnt;
    logic dma_wr_req_en;
    logic [31:0] dma_wr_req_cnt, rsp_ff_rd_cnt;
    logic [15:0] blk_upstream_ptr;    

//==============WR FSM==================//
    always @(posedge clk) begin
        if(rst) begin
            wr_cstat <= IDLE;
        end else begin
            wr_cstat <= wr_nstat;
        end          
    end

    always @(*) begin
        wr_nstat = wr_cstat;
        case(wr_cstat)
            IDLE: begin
                if(~data_ff_empty && ~order_ff_pfull) begin
                    wr_nstat = RD_HEADER;
                end
            end
            RD_HEADER: begin
                if((data_ff_rd_cnt == 8'd1) && data_ff_rden) begin
                    if((buffer_header_magic_num != 16'hc0de) || (buffer_header_vq_gen != generation) || forced_shutdown || (q_status == VIRTIO_Q_STATUS_IDLE) || (q_status == VIRTIO_Q_STATUS_STARTING)) begin
                        wr_nstat = DROP;
                    end else begin
                        wr_nstat = WR_DATA_REQ;
                    end
                end
            end
            DROP: begin
                if(data_ff_dout_eop && data_ff_rden) begin
                    wr_nstat = IDLE;
                end
            end
            WR_DATA_REQ: begin
                if(data_ff_dout_eop && data_ff_rden) begin
                    wr_nstat = WR_ORDER;
                end
            end
            WR_ORDER: begin
                wr_nstat = IDLE;
            end
            default: wr_nstat = IDLE;
        endcase
    end

    yucca_sync_fifo #(
        .DATA_WIDTH ( DATA_FF_WIDTH                                                 ),
        .FIFO_DEPTH ( 512                                                           ),
        .CHECK_ON   ( 1                                                             ),
        .CHECK_MODE ( "parity"                                                      ),
        .DEPTH_PFULL( 500                                                           ),
        .RAM_MODE   ( "blk"                                                         ),
        .FIFO_MODE  ( "fwft"                                                        )
    ) u_data_ff (
        .clk             (clk                      ),
        .rst             (rst                      ),
        .wren            (data_ff_wren             ),
        .din             (data_ff_din              ),
        .full            (data_ff_full             ),
        .pfull           (data_ff_pfull            ),
        .overflow        (data_ff_overflow         ),
        .rden            (data_ff_rden             ),
        .dout            (data_ff_dout             ),
        .empty           (data_ff_empty            ),
        .pempty          (                         ),
        .underflow       (data_ff_underflow        ),
        .usedw           (                         ),
        .parity_ecc_err  (data_ff_parity_ecc_err   )
    );

    assign data_ff_wren = beq2blk_if.vld;
    assign data_ff_din  = {beq2blk_if.eop, beq2blk_if.sop, beq2blk_if.mty, beq2blk_if.sty, beq2blk_if.data};
    assign data_ff_rden = ((wr_cstat == RD_HEADER) || (wr_cstat == DROP) || ((wr_cstat == WR_DATA_REQ) && dma_data_wr_req_if.sav && dma_wr_req_en)) && ~data_ff_empty;
    assign {data_ff_dout_eop, data_ff_dout_sop, data_ff_dout_mty, data_ff_dout_sty, data_ff_dout_data} = data_ff_dout;
    assign blk_to_beq_cred_fc = data_ff_rden;

    always @(posedge clk) begin
        if(wr_cstat == IDLE) begin
            data_ff_rd_cnt <= 8'd0;
        end else if(data_ff_rden) begin
            data_ff_rd_cnt <= data_ff_rd_cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        if((wr_cstat == RD_HEADER) && data_ff_rden && (data_ff_rd_cnt == 8'd0)) begin
            buffer_header_qid           <= data_ff_dout[Q_WIDTH-1:0];
            buffer_header_vq_gen        <= data_ff_dout[23:16];
            buffer_header_desc_index    <= data_ff_dout[47:32];
            buffer_header_flags         <= data_ff_dout[63:48];
            buffer_header_host_buf_addr <= data_ff_dout[127:64];
            buffer_header_used_length   <= data_ff_dout[159:128];
            buffer_header_used_idx      <= data_ff_dout[175:160];
            buffer_header_magic_num     <= data_ff_dout[191:176];
        end
    end
    
//=======================ctx req and rsp===================================//
    //assign blk_upstream_ctx_req_vld = (wr_cstat == RD_HEADER) && data_ff_rden && (data_ff_rd_cnt == 8'd0);
    assign blk_upstream_ctx_req_vld = (wr_cstat == IDLE) && ~data_ff_empty && ~order_ff_pfull;
    assign blk_upstream_ctx_req_qid = data_ff_dout_data[Q_WIDTH-1:0];

    always @(posedge clk) begin
        if(blk_upstream_ctx_rsp_vld) begin
            forced_shutdown <= blk_upstream_ctx_rsp_forced_shutdown;
            q_status        <= blk_upstream_ctx_rsp_q_status;
            dev_id          <= blk_upstream_ctx_rsp_dev_id;
            bdf             <= blk_upstream_ctx_rsp_bdf;
            generation      <= blk_upstream_ctx_rsp_generation;
        end
    end

    yucca_sync_fifo #(
        .DATA_WIDTH ( INFO_FF_WIDTH                                    ),
        .FIFO_DEPTH ( 32                                               ),
        .CHECK_ON   ( 1                                                ),
        .CHECK_MODE ( "parity"                                         ),
        .DEPTH_PFULL( 24                                               ),
        .RAM_MODE   ( "dist"                                           ),
        .FIFO_MODE  ( "fwft"                                           )
    ) u_info_ff (
        .clk             (clk                      ),
        .rst             (rst                      ),
        .wren            (info_ff_wren             ),
        .din             (info_ff_din              ),
        .full            (info_ff_full             ),
        .pfull           (info_ff_pfull            ),
        .overflow        (info_ff_overflow         ),
        .rden            (info_ff_rden             ),
        .dout            (info_ff_dout             ),
        .empty           (info_ff_empty            ),
        .pempty          (                         ),
        .underflow       (info_ff_underflow        ),
        .usedw           (                         ),
        .parity_ecc_err  (info_ff_parity_ecc_err   )
    );

    assign info_ff_wren = beq2blk_if.vld && beq2blk_if.sop;
    assign info_ff_din  = beq2blk_if.sbd.length;
    assign info_ff_rden = data_ff_rden && data_ff_dout_eop;
    assign info_ff_dout_length = info_ff_dout;

    assign beq2blk_if.sav = ~(data_ff_pfull || info_ff_pfull);

//================WR used_info FSM==================//
    always @(posedge clk) begin
        if(rst) begin
            used_cstat <= USED_IDLE;
        end else begin
            used_cstat <= used_nstat;
        end      
    end

    always @(*) begin
    used_nstat = used_cstat;
    case(used_cstat)
        USED_IDLE: begin
            if((~wr_rsp_ff_empty) && (~order_ff_empty)) begin
                used_nstat = RD_RSP;
            end
        end
        RD_RSP: begin
            used_nstat = WR_USED_INFO;
        end
        WR_USED_INFO: begin
            if((order_ff_dout_reg.used_idx[3:0] == wr_rsp_ff_dout_reg[3:0]) && ~order_ff_dout_reg.flag) begin  //one io finish
                if(wr_used_info_rdy) begin
                    used_nstat = USED_IDLE;
                end
            end else begin
                used_nstat = USED_IDLE;
            end
        end
        default: used_nstat = USED_IDLE;
    endcase
    end


   //=============update blk_upstream_ptr==================//
    assign blk_upstream_ptr_rd_req_vld = (used_cstat == USED_IDLE) && (~wr_rsp_ff_empty) && (~order_ff_empty);
    assign blk_upstream_ptr_rd_req_qid = order_ff_dout.qid;
    
    always @(posedge clk) begin
        if(blk_upstream_ptr_rd_rsp_vld) begin
            blk_upstream_ptr <= blk_upstream_ptr_rd_rsp_dat;
        end
    end

    assign blk_upstream_ptr_wr_req_vld = (used_cstat == WR_USED_INFO) && (order_ff_dout_reg.used_idx[3:0] == wr_rsp_ff_dout_reg[3:0]) && ~order_ff_dout_reg.flag && wr_used_info_rdy;
    assign blk_upstream_ptr_wr_req_qid = order_ff_dout_reg.qid;
    assign blk_upstream_ptr_wr_req_dat = blk_upstream_ptr + 1'b1;

//=============order_ff and rsp_ff=======================//
    yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(virtio_blk_upstream_order_info_t) ),
        .FIFO_DEPTH ( 32                          ),
        .CHECK_ON   ( 1                           ),
        .CHECK_MODE ( "parity"                    ),
        .DEPTH_PFULL( 24                          ),
        .RAM_MODE   ( "dist"                      ),
        .FIFO_MODE  ( "fwft"                      )
    ) u_order_ff (
        .clk             (clk                      ),
        .rst             (rst                      ),
        .wren            (order_ff_wren            ),
        .din             (order_ff_din             ),
        .full            (                         ),
        .pfull           (order_ff_pfull           ),
        .overflow        (order_ff_overflow        ),
        .rden            (order_ff_rden            ),
        .dout            (order_ff_dout            ),
        .empty           (order_ff_empty           ),
        .pempty          (                         ),
        .underflow       (order_ff_underflow       ),
        .usedw           (                         ),
        .parity_ecc_err  (order_ff_parity_ecc_err  )
    );

    assign order_ff_wren            = (wr_cstat == WR_ORDER);
    assign order_ff_din.qid         = {VIRTIO_BLK_TYPE, buffer_header_qid};
    assign order_ff_din.dummy       = forced_shutdown;
    assign order_ff_din.flag        = buffer_header_flags[0];
    assign order_ff_din.desc_index  = buffer_header_desc_index;
    assign order_ff_din.used_length = buffer_header_used_length;
    assign order_ff_din.used_idx    = buffer_header_used_idx;
    assign order_ff_rden            = (used_cstat == RD_RSP);
    assign order_used_idx           = order_ff_dout.used_idx[3:0];
    

    always @(posedge clk) begin
        if(order_ff_rden) begin
            order_ff_dout_reg <= order_ff_dout;
        end
    end

    //================wr used info===================//
    assign wr_used_info_vld = (used_cstat == WR_USED_INFO) && (order_ff_dout_reg.used_idx[3:0] == wr_rsp_ff_dout_reg[3:0]) && ~order_ff_dout_reg.flag;

    assign wr_used_info_dat.vq              = order_ff_dout_reg.qid;
    assign wr_used_info_dat.elem.len        = order_ff_dout_reg.used_length;
    assign wr_used_info_dat.elem.id         = order_ff_dout_reg.desc_index;
    assign wr_used_info_dat.used_idx        = order_ff_dout_reg.used_idx;
    assign wr_used_info_dat.forced_shutdown = order_ff_dout_reg.dummy;
    assign wr_used_info_dat.err_info        = 'h0;

    yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(dma_data_wr_rsp_if.rd2rsp_loop)),
        .FIFO_DEPTH ( 32                          ),
        .CHECK_ON   ( 1                           ),
        .CHECK_MODE ( "parity"                    ),
        .DEPTH_PFULL( 24                          ),
        .RAM_MODE   ( "dist"                      ),
        .FIFO_MODE  ( "fwft"                      )
    ) u_wr_rsp_ff (
        .clk             (clk                      ),
        .rst             (rst                      ),
        .wren            (wr_rsp_ff_wren           ),
        .din             (wr_rsp_ff_din            ),
        .full            (                         ),
        .pfull           (wr_rsp_ff_pfull          ),
        .overflow        (wr_rsp_ff_overflow       ),
        .rden            (wr_rsp_ff_rden           ),
        .dout            (wr_rsp_ff_dout           ),
        .empty           (wr_rsp_ff_empty          ),
        .pempty          (                         ),
        .underflow       (wr_rsp_ff_underflow      ),
        .usedw           (                         ),
        .parity_ecc_err  (wr_rsp_ff_parity_ecc_err )
    );

    always @(posedge clk) begin
        if(wr_rsp_ff_rden) begin
            wr_rsp_ff_dout_reg <= wr_rsp_ff_dout;
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            dma_wr_req_cnt <= 32'd0;
        end else if(dma_data_wr_req_if.vld && dma_data_wr_req_if.eop) begin
            dma_wr_req_cnt <= dma_wr_req_cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            rsp_ff_rd_cnt <= 32'd0;
        end else if(wr_rsp_ff_rden) begin
            rsp_ff_rd_cnt <= rsp_ff_rd_cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        dma_wr_req_en <= (dma_wr_req_cnt - rsp_ff_rd_cnt) < (32'd32 - 32'd8);
    end

    assign wr_rsp_ff_wren = dma_data_wr_rsp_if.vld;
    assign wr_rsp_ff_din  = dma_data_wr_rsp_if.rd2rsp_loop;
    assign wr_rsp_ff_rden = (used_cstat == RD_RSP);
    assign rsp_used_idx   = wr_rsp_ff_dout[3:0];

    //===========dma_data_wr_if=================//
    always @(posedge clk) begin
        if(rst) begin
            dma_data_wr_req_if.vld <= 'h0;
        end else begin
            dma_data_wr_req_if.vld <= (wr_cstat == WR_DATA_REQ) && data_ff_rden && ~forced_shutdown;
        end
    end

    always @(posedge clk) begin
        dma_data_wr_req_if.desc.dev_id          <= dev_id;
        dma_data_wr_req_if.desc.bdf             <= bdf;
        dma_data_wr_req_if.desc.vf_active       <= '0;
        dma_data_wr_req_if.desc.tc              <= '0;
        dma_data_wr_req_if.desc.attr            <= '0;
        dma_data_wr_req_if.desc.th              <= '0;
        dma_data_wr_req_if.desc.td              <= '0;
        dma_data_wr_req_if.desc.ep              <= '0;
        dma_data_wr_req_if.desc.at              <= '0;
        dma_data_wr_req_if.desc.ph              <= '0;
        dma_data_wr_req_if.desc.rd2rsp_loop     <= {buffer_header_qid, buffer_header_used_idx[3:0]};
        dma_data_wr_req_if.data                 <= data_ff_dout_data;
        dma_data_wr_req_if.sty                  <= data_ff_dout_sty;
        dma_data_wr_req_if.mty                  <= data_ff_dout_mty;
        dma_data_wr_req_if.sop                  <= data_ff_rd_cnt == 8'd2;
        dma_data_wr_req_if.eop                  <= data_ff_dout_eop;
        dma_data_wr_req_if.desc.pcie_addr       <= buffer_header_host_buf_addr;
        dma_data_wr_req_if.desc.pcie_length     <= info_ff_dout_length - 'd64; 
    end



//==============dfx=========================//
    always @(posedge clk) begin
        if(rst) begin
            dfx_err <= {$bits(dfx_err){1'b0}};
        end else begin
            dfx_err = {
                 (used_cstat == RD_RSP) && (order_used_idx != rsp_used_idx),  //16
                 data_ff_overflow,         //15
                 data_ff_underflow,        //14
                 data_ff_parity_ecc_err,   //13-12
                 info_ff_overflow,         //11
                 info_ff_underflow,        //10
                 info_ff_parity_ecc_err,   //9-8
                 order_ff_overflow,        //7
                 order_ff_underflow,       //6
                 order_ff_parity_ecc_err,  //5-4
                 wr_rsp_ff_overflow,       //3
                 wr_rsp_ff_underflow,      //2
                 wr_rsp_ff_parity_ecc_err  //1-0
            };
        end
    end

    genvar idx;
    generate
        for(idx=0;idx<$bits(dfx_err);idx++)begin :db_err_i
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err[idx]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, dfx_err[idx], idx));
        end
    endgenerate

    assign dfx_status = {
        beq2blk_if.sav,           //20
        dma_data_wr_req_if.sav,   //19
        wr_used_info_vld,         //18
        wr_used_info_rdy,         //17
        data_ff_pfull,            //16
        data_ff_empty,            //15
        info_ff_pfull,            //14
        info_ff_empty,            //13
        order_ff_pfull,           //12
        order_ff_empty,           //11
        wr_rsp_ff_pfull,          //10
        wr_rsp_ff_empty,          //9
        wr_cstat,                 //8-4
        used_cstat                //3-0     
    };

    always @(posedge clk) begin
        if(rst) begin
            beq2blk_pkt_cnt                   <= 16'd0;
            blk_upstream_tran_pkt_cnt         <= 16'd0;
            blk_upstream_drop_pkt_cnt         <= 16'd0;
            dma_data_wr_req_cnt               <= 8'd0;
            dma_data_wr_rsp_cnt               <= 8'd0;
            magic_num_not_match_drop_pkt_cnt  <= 16'd0;
            generation_not_match_drop_pkt_cnt <= 16'd0;
            q_status_not_match_drop_pkt_cnt   <= 16'd0;
            forced_shutdown_drop_pkt_cnt      <= 16'd0;
        end else begin
            if(beq2blk_if.vld && beq2blk_if.eop) begin
                beq2blk_pkt_cnt <= beq2blk_pkt_cnt + 1'b1;
            end
            if((wr_cstat == WR_DATA_REQ) && data_ff_dout_eop && data_ff_rden) begin
                blk_upstream_tran_pkt_cnt <= blk_upstream_tran_pkt_cnt + 1'b1;
            end
            if((wr_cstat == DROP) && data_ff_rden && data_ff_dout_eop) begin
                blk_upstream_drop_pkt_cnt <= blk_upstream_drop_pkt_cnt + 1'b1;
            end
            if(dma_data_wr_req_if.vld && dma_data_wr_req_if.eop) begin
                dma_data_wr_req_cnt <= dma_data_wr_req_cnt + 1'b1;
            end
            if(dma_data_wr_rsp_if.vld) begin
                dma_data_wr_rsp_cnt <= dma_data_wr_rsp_cnt + 1'b1;
            end
            if((wr_cstat == DROP) && (buffer_header_magic_num != 16'hc0de) && data_ff_rden && data_ff_dout_eop) begin
                magic_num_not_match_drop_pkt_cnt <= magic_num_not_match_drop_pkt_cnt + 1'b1;
            end
            if((wr_cstat == DROP) && (buffer_header_vq_gen != generation) && data_ff_rden && data_ff_dout_eop) begin
                generation_not_match_drop_pkt_cnt <= generation_not_match_drop_pkt_cnt + 1'b1;
            end
            if((wr_cstat == DROP) && (q_status == VIRTIO_Q_STATUS_IDLE || q_status == VIRTIO_Q_STATUS_STARTING) && data_ff_rden && data_ff_dout_eop) begin
                q_status_not_match_drop_pkt_cnt <= q_status_not_match_drop_pkt_cnt + 1'b1;
            end
            if((wr_cstat == DROP) && forced_shutdown && data_ff_rden && data_ff_dout_eop) begin
                forced_shutdown_drop_pkt_cnt <= forced_shutdown_drop_pkt_cnt + 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            mon_send_io <= 1'b0;
        end else begin   
            mon_send_io <= order_ff_rden && (~order_ff_dout.dummy) && ~order_ff_dout.flag;
        end
        mon_send_io_qid <= order_ff_dout.qid;
    end


    `ifdef PMON_EN
    localparam PP_IF_NUM = 1;
    localparam CNT_WIDTH = 26;
    localparam MS_100_CLEAN_CNT = `MS_100_CLEAN_CNT_AT_USER_CLK;
    
    logic   [PP_IF_NUM-1:0]             backpressure_vld;
    logic   [PP_IF_NUM-1:0]             backpressure_sav;
    logic   [PP_IF_NUM-1:0]             handshake_vld;
    logic   [PP_IF_NUM-1:0]             handshake_rdy;
    logic   [CNT_WIDTH-1:0]             mon_tick_interval;
    logic   [PP_IF_NUM*CNT_WIDTH-1:0]   backpressure_block_cnt;
    logic   [PP_IF_NUM*CNT_WIDTH-1:0]   backpressure_vdata_cnt;

    
    assign mon_tick_interval = MS_100_CLEAN_CNT;
    assign backpressure_vld = dma_data_wr_req_if.vld;
    assign backpressure_sav = dma_data_wr_req_if.sav;
    assign handshake_vld = '0;
    assign handshake_rdy = '0;
    
    performance_probe #(
        .PP_IF_NUM  (PP_IF_NUM),
        .CNT_WIDTH  (CNT_WIDTH)
    ) u_blk_upstream_performance_probe(
        .clk                       (clk),  
        .rst                       (rst),
        .backpressure_vld          (backpressure_vld      ),
        .backpressure_sav          (backpressure_sav      ),
        .handshake_vld             (handshake_vld         ),
        .handshake_rdy             (handshake_rdy         ),
        .mon_tick_interval         (mon_tick_interval     ),
        .backpressure_block_cnt    (backpressure_block_cnt),
        .backpressure_vdata_cnt    (backpressure_vdata_cnt),
        .handshake_block_cnt       (),
        .handshake_vdata_cnt       ()
    );
    `endif

    virtio_blk_upstream_dfx #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(64)
    )u_virtio_blk_upstream_dfx(
        .clk(clk),
        .rst(rst),

        .dfx_err_dfx_err_we     (|dfx_err),             //! Control HW write (active high)
        .dfx_err_dfx_err_wdata  (dfx_err|dfx_err_q),          //! HW write data
        .dfx_err_dfx_err_q      (dfx_err_q),              //! Current field value        

        .dfx_status_dfx_status_wdata(dfx_status),          //! HW write data
        .beq2blk_pkt_blk_upstream_tran_drop_pkt_cnt_beq2blk_pkt_blk_upstream_tran_drop_pkt_cnt_wdata({blk_upstream_drop_pkt_cnt, blk_upstream_tran_pkt_cnt, beq2blk_pkt_cnt}),          //! HW write data
        .dma_cnt_dma_cnt_wdata({dma_data_wr_req_cnt, dma_data_wr_rsp_cnt}),          //! HW write data
        .magic_num_generation_q_status_not_match_pkt_cnt_magic_num_generation_q_status_not_match_pkt_cnt_wdata({magic_num_not_match_drop_pkt_cnt, generation_not_match_drop_pkt_cnt, q_status_not_match_drop_pkt_cnt, forced_shutdown_drop_pkt_cnt}),          //! HW write data
        `ifdef PMON_EN
        .dma_data_wr_req_if_backpressure_block_vdata_cnt_dma_data_wr_req_if_backpressure_block_vdata_cnt_wdata({backpressure_block_cnt[CNT_WIDTH-1:0], 6'd0, backpressure_vdata_cnt[CNT_WIDTH-1:0]}),
        `endif
        .csr_if(dfx_if)
    );

 endmodule
