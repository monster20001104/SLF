/******************************************************************************
 * 文件名称 : virtio_used_sch.sv
 * 作者名称 : cui naiwan
 * 创建日期 : 2025/07/01
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/01     cui naiwan   初始化版本
 ******************************************************************************/
 `include "virtio_define.svh"
 module virtio_used_sch(
    input                                            clk,
    input                                            rst,
    //===============from or to blk_upstream================//
    input logic                                      blk_upstream_wr_used_info_vld,
    input virtio_used_info_t                         blk_upstream_wr_used_info_dat,
    output logic                                     blk_upstream_wr_used_info_rdy,
    //===============from or to net_tx=======================//
    input logic                                      net_tx_wr_used_info_vld,
    input virtio_used_info_t                         net_tx_wr_used_info_dat,
    output logic                                     net_tx_wr_used_info_rdy, 
    //===============from or to net_rx=======================//
    input logic                                      net_rx_wr_used_info_vld,
    input virtio_used_info_t                         net_rx_wr_used_info_dat,
    output logic                                     net_rx_wr_used_info_rdy, 
    //================from or to virtio_used=================//
    output logic                                     wr_used_info_vld,
    output virtio_used_info_t                        wr_used_info_dat,
    input  logic                                     wr_used_info_rdy
 );

    logic is_blk_upstream_wr_used_info, is_net_rx_wr_used_info, is_net_tx_wr_used_info;
    logic req_sch_en, req_sch_grant_vld;
    logic [2:0] req_sch_req, req_sch_grant;
    
    enum logic [1:0] {
        SCH = 2'b01,
        EXE = 2'b10
    } sch_cstat, sch_nstat;

    //============SCH FSM============//
    always @(posedge clk) begin
        if(rst) begin
            sch_cstat <= SCH;
        end else begin
            sch_cstat <= sch_nstat;
        end
    end

    always @(*) begin
        sch_nstat = sch_cstat;
        case(sch_cstat)
            SCH: begin
                if(req_sch_grant_vld) begin
                    sch_nstat = EXE;
                end
            end
            EXE: begin
                if(wr_used_info_rdy) begin
                    sch_nstat = SCH;
                end
            end
            default: sch_nstat = SCH;
        endcase
    end

     //===============rr_sch=======================//
    assign req_sch_req = {blk_upstream_wr_used_info_vld, net_rx_wr_used_info_vld, net_tx_wr_used_info_vld};
    assign req_sch_en = sch_cstat == SCH;

    rr_sch#(
        .SH_NUM(3)         
    )u_rr_sch_used(
        .clk           (clk),
        .rst           (rst),
        .sch_req       (req_sch_req      ),
        .sch_en        (req_sch_en       ), 
        .sch_grant     (req_sch_grant    ), 
        .sch_grant_vld (req_sch_grant_vld)   
    );

    always @(posedge clk) begin
        if((sch_cstat == SCH) && req_sch_grant_vld) begin
            {is_blk_upstream_wr_used_info, is_net_rx_wr_used_info, is_net_tx_wr_used_info} <= req_sch_grant;
        end
    end

    assign wr_used_info_vld = (sch_cstat == EXE);
    assign wr_used_info_dat = is_blk_upstream_wr_used_info ? blk_upstream_wr_used_info_dat : is_net_rx_wr_used_info ? net_rx_wr_used_info_dat : net_tx_wr_used_info_dat;

    assign blk_upstream_wr_used_info_rdy = (sch_cstat == EXE) && is_blk_upstream_wr_used_info && wr_used_info_vld && wr_used_info_rdy;
    assign net_tx_wr_used_info_rdy = (sch_cstat == EXE) && is_net_tx_wr_used_info && wr_used_info_vld && wr_used_info_rdy;
    assign net_rx_wr_used_info_rdy = (sch_cstat == EXE) && is_net_rx_wr_used_info && wr_used_info_vld && wr_used_info_rdy;

 endmodule