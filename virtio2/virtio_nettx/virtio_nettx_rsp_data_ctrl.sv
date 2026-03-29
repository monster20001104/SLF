/******************************************************************************
 * 文件名称 : virtio_nettx_slot_ctrl.sv
 * 作者名称 : Feilong Yun
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/23     Feilong Yun   初始化版本
******************************************************************************/
 `include "virtio_nettx_define.svh"
  `include "tlp_adap_dma_if.svh"
module virtio_nettx_rsp_data_ctrl 
   import alt_tlp_adaptor_pkg::*;
#(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM),
    parameter CTRL_FIFO_DEPTH = 64,
    parameter DATA_FIFO_DEPTH = 512
)
(
    input                         clk,
    input                         rst,

    tlp_adap_dma_rd_rsp_if.snk   dma_rd_rsp,

    output   logic                data_fifo_rd, // 按拍算
    output   logic                ctrl_fifo_rd, // 按单算 结算order FIFO的位置

    input                         net2tso_sav,
    output   logic                net2tso_sop,
    output   logic                net2tso_eop,
    output   logic                net2tso_vld,
    output   logic[DATA_EMPTY-1:0]net2tso_sty,
    output   logic[DATA_EMPTY-1:0]net2tso_mty,
    output   logic                net2tso_err,
    output   logic[DATA_WIDTH-1:0]net2tso_data,
    output   logic[VIRTIO_Q_WIDTH-1:0] net2tso_qid,
    output   logic[17:0]          net2tso_len,
    output   logic[7:0]           net2tso_gen,
    output   logic                net2tso_tso_en,
    output   logic                net2tso_csum_en, // 告诉下游模块是否需要重新计算校验和

    output   logic                used_info_vld,
    input                         used_info_rdy,
    output   virtio_used_info_t   used_info_data,

    input                         order_fifo_vld,
    input   virtio_nettx_order_t  order_fifo_data,
    output   logic                order_fifo_sav,

    output   logic[63:0]          rd_rsp_cnt,
            
    output   logic[63:0]          dfx_err,
    output   logic[63:0]          dfx_status


);


    logic [19:0] rcv_data_len,fe2tso_data_len,data_len_rcv_sbd;
    genvar i;
    logic [DATA_WIDTH-1 :0] bit_enable;

    enum logic [7:0]  { 
        IDLE                 = 8'b0000_0001,
        GEN_USED_INFO_ERR    = 8'b0000_0010,
        TX_DATA_ERR          = 8'b0000_0100,
        TX_DATA              = 8'b0000_1000,
        GEN_USED             = 8'b0001_0000,
        FINISH               = 8'b0010_0000,
        GEN_USED_STOP_NO_RD  = 8'b0100_0000,
        ADD_CHAIN_ERR        = 8'b1000_0000
    } cstate, nstate,cstate_1d;


    logic                   wren_order_fifo,rden_order_fifo;
    virtio_nettx_order_t    din_order_fifo,dout_order_fifo,dout_order_fifo_1d;
    logic                   order_fifo_empty,order_fifo_full,order_fifo_overflow,order_fifo_pfull,order_fifo_underflow;
    logic [1:0]             order_fifo_err;

    logic                   wren_rsp_sbd_fifo,rden_rsp_sbd_fifo;
    virtio_nettx_rsp_sbd_t  din_rsp_sbd_fifo,dout_rsp_sbd_fifo;
    logic                   rsp_sbd_fifo_empty,rsp_sbd_fifo_full,rsp_sbd_fifo_overflow,rsp_sbd_fifo_pfull,rsp_sbd_fifo_underflow;
    logic [1:0]             rsp_sbd_fifo_err;

    logic                   wren_rsp_data_fifo,rden_rsp_data_fifo,rden_rsp_data_fifo_copy;
    virtio_nettx_rsp_data_t din_rsp_data_fifo,dout_rsp_data_fifo;
    logic                   rsp_data_fifo_empty,rsp_data_fifo_full,rsp_data_fifo_overflow,rsp_data_fifo_pfull,rsp_data_fifo_underflow;
    logic [1:0]             rsp_data_fifo_err;



    logic                   feq2tso_sav;
    logic                   feq2tso_vld;
    logic                   feq2tso_sop;
    logic                   feq2tso_eop;
    logic   [DATA_EMPTY-1:0]feq2tso_sty;
    logic   [DATA_EMPTY-1:0]feq2tso_mty;
    logic                   feq2tso_err;
    logic   [DATA_WIDTH-1:0]feq2tso_data;

    logic                   err_reg;
    logic                   net2tso_sav_1d;


    /*assign wren_rsp_sbd_fifo = dma_rd_rsp.vld && dma_rd_rsp.eop;
    assign din_rsp_sbd_fifo.ring_id = dma_rd_rsp.desc.rd2rsp_loop[15:0];
    assign din_rsp_sbd_fifo.qid = dma_rd_rsp.desc.rd2rsp_loop[15+VIRTIO_Q_WIDTH:16];
    assign din_rsp_sbd_fifo.len = dma_rd_rsp.desc.pcie_length;
    assign din_rsp_sbd_fifo.tlp_err = dma_rd_rsp.err;
    
    assign wren_rsp_data_fifo = dma_rd_rsp.vld;
    assign din_rsp_data_fifo.data = dma_rd_rsp.data;
    assign din_rsp_data_fifo.sop = dma_rd_rsp.sop;
    assign din_rsp_data_fifo.eop = dma_rd_rsp.eop;
    assign din_rsp_data_fifo.sty = (dma_rd_rsp.vld && dma_rd_rsp.sop) ? dma_rd_rsp.sty:0;
    assign din_rsp_data_fifo.mty = dma_rd_rsp.eop ? dma_rd_rsp.mty : 0 ;
    assign din_rsp_data_fifo.err = dma_rd_rsp.err;
    */
    always @(posedge clk)begin
        wren_rsp_sbd_fifo <= dma_rd_rsp.vld && dma_rd_rsp.eop;
        din_rsp_sbd_fifo.ring_id <= dma_rd_rsp.desc.rd2rsp_loop[15:0];
        din_rsp_sbd_fifo.qid <= dma_rd_rsp.desc.rd2rsp_loop[15+VIRTIO_Q_WIDTH:16];
        din_rsp_sbd_fifo.len <= dma_rd_rsp.desc.pcie_length;
        din_rsp_sbd_fifo.tlp_err <= dma_rd_rsp.err;
    
        wren_rsp_data_fifo <= dma_rd_rsp.vld;
        din_rsp_data_fifo.data <= dma_rd_rsp.data;
        din_rsp_data_fifo.sop <= dma_rd_rsp.sop;
        din_rsp_data_fifo.eop <= dma_rd_rsp.eop;
        din_rsp_data_fifo.sty <= (dma_rd_rsp.vld && dma_rd_rsp.sop) ? dma_rd_rsp.sty:0;
        din_rsp_data_fifo.mty <= dma_rd_rsp.eop ? dma_rd_rsp.mty : 0 ;
        din_rsp_data_fifo.err <= dma_rd_rsp.err;
    end

    assign wren_order_fifo = order_fifo_vld;
    assign din_order_fifo = order_fifo_data;
    assign order_fifo_sav = order_fifo_pfull == 0;

    always @(posedge clk)begin
        dout_order_fifo_1d <= dout_order_fifo;
    end


    always @(posedge clk)begin
        if(rst)begin
            cstate <= IDLE;
        end
        else begin
            cstate <= nstate;
        end
    end

    always @(posedge clk)begin
        cstate_1d <= cstate;
    end

    always @(*)begin
        nstate = cstate;
        case(cstate)
        IDLE:
            begin   //有一个待处理的任务，前端已经拦截了数据读取，原因是因为系统正在强制关机，且目前链条本身还没出协议错误
                if( order_fifo_empty == 0 && dout_order_fifo.enable_rd == 0 && (dout_order_fifo.chain_stop == 0 && dout_order_fifo.forced_shutdown == 1))
                    nstate = GEN_USED_STOP_NO_RD;
                    // 系统既要强制关机，而且当前正在处理的这个描述符链条本身也发生了协议错误
                else if(order_fifo_empty == 0 && dout_order_fifo.enable_rd == 0 && dout_order_fifo.chain_stop == 1 && dout_order_fifo.forced_shutdown == 1)
                    nstate = ADD_CHAIN_ERR;  
                    // 描述符错误  没发 DMA 请求   告诉主机报错
                else if(order_fifo_empty == 0 && dout_order_fifo.enable_rd == 0 && dout_order_fifo.err_info > 0)
                    nstate = GEN_USED_INFO_ERR;           
                else if( rsp_sbd_fifo_empty == 0  && order_fifo_empty == 0 && dout_order_fifo.enable_rd == 1)begin
                    if(dout_rsp_sbd_fifo.tlp_err || dout_rsp_sbd_fifo.qid != dout_order_fifo.qid || dout_order_fifo.ring_id != dout_rsp_sbd_fifo.ring_id)
                        nstate = TX_DATA_ERR; // 搬运数据但是标记错误
                    else
                        nstate = TX_DATA;   
                end
            end
        TX_DATA:
            begin
                if(rden_rsp_data_fifo && dout_rsp_data_fifo.eop)begin
                    if(dout_order_fifo.chain_tail)
                        nstate = GEN_USED;
                    else
                        nstate = FINISH; // 表示结束这次切片的处理
                end
            end
        TX_DATA_ERR:
            begin
                if(rden_rsp_data_fifo && dout_rsp_data_fifo.eop)begin
                    if(dout_order_fifo.chain_tail)
                        nstate = GEN_USED_INFO_ERR;
                    else
                        nstate = FINISH;
                end
            end
        GEN_USED:
            begin
                if(used_info_rdy)
                    nstate = FINISH;
            end
        GEN_USED_INFO_ERR:
            begin
                if(used_info_rdy)
                    nstate = FINISH;
            end
        ADD_CHAIN_ERR:
            begin
                if(used_info_rdy)
                    nstate = FINISH;
            end
        GEN_USED_STOP_NO_RD:
            begin
                if(used_info_rdy)
                    nstate = FINISH;
            end
        FINISH :
            begin
                nstate = IDLE;
            end

        default: nstate = cstate;
        endcase
    end

    always @(posedge clk )begin
        net2tso_sav_1d <= net2tso_sav;
    end
    // sav属于外部信号，有效沿和本模块的clk上升沿可能有时序偏差 打一拍可以同步并且滤除毛刺
    assign rden_rsp_data_fifo = (cstate == TX_DATA_ERR ||  cstate == TX_DATA) && net2tso_sav_1d == 1;
    assign rden_rsp_data_fifo_copy = (cstate == TX_DATA_ERR ||  cstate == TX_DATA) && net2tso_sav_1d == 1;
    assign rden_rsp_sbd_fifo = (cstate == FINISH && dout_order_fifo_1d.enable_rd == 1 && (cstate_1d == TX_DATA || cstate_1d == GEN_USED || cstate_1d == TX_DATA_ERR || cstate_1d == GEN_USED_INFO_ERR )) ;
    assign rden_order_fifo = (cstate == FINISH);

    assign data_fifo_rd = rden_rsp_data_fifo;
    assign ctrl_fifo_rd = rden_rsp_sbd_fifo;
    
    generate
    for(i=0;i<(DATA_WIDTH/8);i++)
    assign bit_enable[8*i+7:8*i]=(i<dout_rsp_data_fifo.sty )?8'b0000_0000 : 8'b1111_1111;
    endgenerate

    always @(posedge clk )begin
        if(rden_rsp_data_fifo_copy )begin
            feq2tso_data <= (dout_rsp_data_fifo.data & bit_enable) | (feq2tso_data & (~bit_enable));
        end
    end

    always @(posedge clk )begin               
        if(rst)begin
            rcv_data_len <= 0;
        end
        else if(cstate == GEN_USED || cstate == ADD_CHAIN_ERR || cstate == GEN_USED_INFO_ERR)begin
            rcv_data_len <= 0; 
        end
        else if(rden_rsp_data_fifo && (cstate == TX_DATA || cstate == TX_DATA_ERR))begin
            rcv_data_len <= rcv_data_len + DATA_WIDTH/8 - dout_rsp_data_fifo.sty- dout_rsp_data_fifo.mty;
        end
    end

    always @(posedge clk )begin //                       
        if(rst)begin
            fe2tso_data_len <= 0;
        end
        else if(cstate == GEN_USED || cstate == ADD_CHAIN_ERR || cstate == GEN_USED_INFO_ERR)begin
            fe2tso_data_len <= 0;
        end
        else if(feq2tso_vld)begin
            fe2tso_data_len <= fe2tso_data_len + DATA_WIDTH/8;
        end
    end

    always @(posedge clk )begin //                        
        if(rst)begin
            feq2tso_sop <= 1;
        end
        else if((feq2tso_vld && feq2tso_eop) || (cstate == ADD_CHAIN_ERR && used_info_rdy))begin
            feq2tso_sop <= 1;
        end
        else if(feq2tso_vld )begin
            feq2tso_sop <= 0;
        end    
    end

    assign feq2tso_sty = 0;

    assign feq2tso_vld  = ((rcv_data_len - fe2tso_data_len >= DATA_WIDTH/8)
                        ||((rcv_data_len - fe2tso_data_len <= DATA_WIDTH/8) && (rcv_data_len == dout_order_fifo_1d.total_buf_len) && dout_order_fifo_1d.chain_tail)
                        ) && (cstate_1d == TX_DATA || cstate_1d == TX_DATA_ERR);

    assign feq2tso_mty =  DATA_WIDTH/8 - dout_order_fifo_1d.total_buf_len[DATA_EMPTY-1:0] ;

    assign feq2tso_eop = (feq2tso_vld && (dout_order_fifo_1d.total_buf_len - fe2tso_data_len <= DATA_WIDTH/8));

    always @(posedge clk )begin
        if(rst)begin
            feq2tso_err <= 0;
        end
        else if(cstate_1d == GEN_USED || cstate_1d == GEN_USED_INFO_ERR)begin
            feq2tso_err <= 0;
        end
        else if(dout_rsp_data_fifo.err && rden_rsp_data_fifo)begin
            feq2tso_err <= 1 ;
        end
    end

    always @(posedge clk )begin
        net2tso_vld <= feq2tso_vld || (cstate == ADD_CHAIN_ERR && used_info_rdy);
        net2tso_data <= feq2tso_data;
        net2tso_sop <= feq2tso_sop;
        net2tso_eop <= feq2tso_eop || (cstate == ADD_CHAIN_ERR && used_info_rdy);
        net2tso_mty <= feq2tso_mty;
        net2tso_sty <= feq2tso_sty;
        net2tso_err <= feq2tso_err || (cstate == ADD_CHAIN_ERR && used_info_rdy) ;
        net2tso_qid <= dout_order_fifo_1d.qid;
        net2tso_len <= dout_order_fifo_1d.total_buf_len;
        net2tso_gen <= dout_order_fifo_1d.gen;
        net2tso_tso_en <= dout_order_fifo_1d.tso_en;
        net2tso_csum_en <= dout_order_fifo_1d.csum_en;

    end

    always @(posedge clk)begin
        if(rst)begin
            err_reg <= 0;
        end
        else if(cstate == GEN_USED_INFO_ERR && nstate == FINISH)begin
            err_reg <= 0;
        end    
        else if(cstate == GEN_USED && nstate == FINISH)begin
            err_reg <= 0;
        end
        else if(cstate == TX_DATA_ERR)begin
            err_reg <= 1;
        end
    end
    
    assign used_info_vld = cstate == GEN_USED || cstate == GEN_USED_INFO_ERR || cstate == GEN_USED_STOP_NO_RD || cstate == ADD_CHAIN_ERR ;
    assign used_info_data.vq.qid = dout_order_fifo_1d.qid;
    assign used_info_data.vq.typ = VIRTIO_NET_TX_TYPE;
    assign used_info_data.elem.len = cstate == GEN_USED_STOP_NO_RD ? 0 : dout_order_fifo_1d.total_buf_len;
    assign used_info_data.elem.id = dout_order_fifo_1d.ring_id;
    assign used_info_data.used_idx = dout_order_fifo_1d.avail_idx;
    assign used_info_data.err_info = dout_order_fifo_1d.enable_rd == 0    ? dout_order_fifo_1d.err_info : 
                                     err_reg                              ? {1'b1,VIRTIO_ERR_CODE_NETTX_PCIE_ERR} :
                                                                            0;
    assign used_info_data.forced_shutdown = dout_order_fifo_1d.forced_shutdown;
                                                             


    logic err_sop,err_eop;
    check_sop_eop u_check_sop_eop(
    .clk     ( clk),
    .rst     ( rst ),

    .vld     ( dma_rd_rsp.vld) ,
    .sop     ( dma_rd_rsp.sop ),
    .eop     ( dma_rd_rsp.eop ),

    .err_sop ( err_sop),
    .err_eop ( err_eop)
);

logic checkout_len_err;
 check_pkt_len #(
    .HOST_DATA_WIDTH ( DATA_WIDTH),
    .HOST_SMTY_WIDTH ( DATA_EMPTY )
)u_check_pkt_len(
    .clk   ( clk ),
    .rst   ( rst ),

    .vld    ( dma_rd_rsp.vld ),
    .sop    ( dma_rd_rsp.sop),
    .eop    ( dma_rd_rsp.eop),
    .sty    ( dma_rd_rsp.sty),
    .mty    ( dma_rd_rsp.mty),

    .exp_len ( dma_rd_rsp.desc.pcie_length ),

    .checkout_len_err (checkout_len_err)
);

    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_order_fifo)),
        .FIFO_DEPTH (CTRL_FIFO_DEPTH),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (CTRL_FIFO_DEPTH-8),
        .DEPTH_PEMPTY (),
        .RAM_MODE ("dist"),
        .FIFO_MODE ("fwft")
    )u_order_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_order_fifo ),
        .din           ( din_order_fifo ),
        .full          ( order_fifo_full),
        .pfull         ( order_fifo_pfull),
        .overflow      ( order_fifo_overflow),
           
        .rden          ( rden_order_fifo),
        .dout          ( dout_order_fifo),
        .empty         ( order_fifo_empty),
        .pempty        (),
        .underflow     ( order_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( order_fifo_err)
    
    );


    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_rsp_sbd_fifo)),
        .FIFO_DEPTH (CTRL_FIFO_DEPTH),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (CTRL_FIFO_DEPTH-8),
        .DEPTH_PEMPTY (),
        .RAM_MODE ("dist"),
        .FIFO_MODE ("fwft")
    )u_rsp_sbd_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_rsp_sbd_fifo ),
        .din           ( din_rsp_sbd_fifo ),
        .full          ( rsp_sbd_fifo_full),
        .pfull         ( rsp_sbd_fifo_pfull),
        .overflow      ( rsp_sbd_fifo_overflow),
           
        .rden          ( rden_rsp_sbd_fifo),
        .dout          ( dout_rsp_sbd_fifo),
        .empty         ( rsp_sbd_fifo_empty),
        .pempty        (),
        .underflow     ( rsp_sbd_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( rsp_sbd_fifo_err)
    
    );


        yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_rsp_data_fifo)),
        .FIFO_DEPTH (DATA_FIFO_DEPTH),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (DATA_FIFO_DEPTH-16),
        .DEPTH_PEMPTY (),
        .RAM_MODE ("blk"),
        .FIFO_MODE ("fwft")
    )u_rsp_data_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_rsp_data_fifo ),
        .din           ( din_rsp_data_fifo ),
        .full          ( rsp_data_fifo_full),
        .pfull         ( rsp_data_fifo_pfull),
        .overflow      ( rsp_data_fifo_overflow),
           
        .rden          ( rden_rsp_data_fifo),
        .dout          ( dout_rsp_data_fifo),
        .empty         ( rsp_data_fifo_empty),
        .pempty        (),
        .underflow     ( rsp_data_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( rsp_data_fifo_err)
    
    );



    always @(posedge clk)begin
        dfx_status <= {(dout_rsp_data_fifo.err >0),
                       (cstate == TX_DATA_ERR),
                       rsp_data_fifo_full,
                       rsp_data_fifo_pfull,
                       rsp_data_fifo_empty,
                       rsp_sbd_fifo_full,
                       rsp_sbd_fifo_pfull,
                       rsp_sbd_fifo_empty,
                       order_fifo_full,
                       order_fifo_pfull,
                       order_fifo_empty,
                       used_info_vld,
                       used_info_rdy,
                       net2tso_sav,
                       cstate};

        dfx_err <= {err_sop,
                    err_eop,
                    checkout_len_err,
                    rsp_data_fifo_overflow,
                    rsp_data_fifo_underflow,
                    rsp_data_fifo_err,
                    rsp_sbd_fifo_overflow,
                    rsp_sbd_fifo_underflow,
                    rsp_sbd_fifo_err,
                    order_fifo_overflow,
                    order_fifo_underflow,
                    order_fifo_err
                    //(dout_rsp_data_fifo.err >0),
                    //(cstate == TX_DATA_ERR)
                    };
    end

        always @(posedge clk)begin
        if(rst)begin
            rd_rsp_cnt <= 0;
        end
        else if(dma_rd_rsp.vld && dma_rd_rsp.eop)begin
            rd_rsp_cnt <= rd_rsp_cnt + 1;
        end
    end

    genvar idx;
    generate
        for(idx=0;idx<$bits(dfx_err);idx++)begin :db_err_i
                assert property (@(posedge clk) disable iff (rst) (~(dfx_err[idx]===1'b1)))
                    else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, dfx_err[idx], idx));
        end
    endgenerate

endmodule