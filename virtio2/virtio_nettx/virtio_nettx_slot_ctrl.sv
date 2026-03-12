/******************************************************************************
 *              : virtio_nettx_slot_ctrl.sv
 *              : Feilong Yun
 *              : 2025/06/23
 *              : 
 *
 *              : 
 *
 *                                                     
 * v1.0  06/23     Feilong Yun                  
******************************************************************************/
 `include "virtio_nettx_define.svh"
module virtio_nettx_slot_ctrl #(
    parameter DATA_WIDTH = 256,
    parameter DATA_EMPTY = $clog2(DATA_WIDTH/8),
    parameter VIRTIO_Q_NUM = 256,
    parameter VIRTIO_Q_WIDTH = $clog2(VIRTIO_Q_NUM)
)
(
    input                          clk,
    input                          rst,

    input                          notify_req_vld,
    input      logic[VIRTIO_Q_WIDTH-1:0]notify_req_qid,
    output     logic               notify_req_rdy, 

    output     logic               notify_rsp_vld,
    output     logic[VIRTIO_Q_WIDTH-1:0 ]notify_rsp_qid,
    output     logic               notify_rsp_cold,
    output     logic               notify_rsp_done,
    input                          notify_rsp_rdy,
    // 申请硬件槽位 驱动描述符引擎开始去Host内存抓取描述符
    output     logic               nettx_alloc_slot_req_vld,
    output     virtio_vq_t         nettx_alloc_slot_req_data,
    output     logic[9:0]          nettx_alloc_slot_req_dev_id,
    input                          nettx_alloc_slot_req_rdy,

    input                          nettx_alloc_slot_rsp_vld,
    input    virtio_desc_eng_slot_rsp_t   nettx_alloc_slot_rsp_data,
    output    logic                nettx_alloc_slot_rsp_rdy,
    // 读取虚拟队列的上下文：是否开启QoS 对应的device id
    output    logic                slot_ctrl_ctx_info_rd_req_vld,
    output    virtio_vq_t          slot_ctrl_ctx_info_rd_req_qid,

    input                          slot_ctrl_ctx_info_rd_rsp_vld,
    input     [VIRTIO_Q_WIDTH+1:0]      slot_ctrl_ctx_info_rd_rsp_qos_unit,
    input                          slot_ctrl_ctx_info_rd_rsp_qos_enable,
    input     [9:0]                slot_ctrl_ctx_info_rd_rsp_dev_id,
    // 令牌桶查询
    output    logic                qos_query_req_vld, 
    output    logic[VIRTIO_Q_WIDTH+1:0] qos_query_req_uid,
    input     logic                qos_query_req_rdy,

    input                          qos_query_rsp_vld,
    input                          qos_query_rsp_data,
    output    logic                qos_query_rsp_rdy,

    output    logic[63:0]          dfx_status,
    output    logic[63:0]          dfx_err

);

    enum logic [7:0]  { 
        IDLE           = 8'b0000_0001,
        RD_CTX         = 8'b0000_0010,
        QOS_DISABLE    = 8'b0000_0100,
        QOS_REQ        = 8'b0000_1000,
        QOS_RSP        = 8'b0001_0000
    } cstate, nstate,cstate_1d;


    enum logic [7:0]  { 
        RR_IDLE        = 8'b0001,
        SCH_PROC       = 8'b0010
    } rr_cstate, rr_nstate,rr_cstate_1d;

    logic [VIRTIO_Q_WIDTH+1:0]  slot_ctrl_ctx_info_rd_rsp_qos_unit_1d;
    logic                  slot_ctrl_ctx_info_rd_rsp_qos_enable_1d;
    logic [9:0]            slot_ctrl_ctx_info_rd_rsp_dev_id_1d;

    logic [VIRTIO_Q_WIDTH-1:0]  notify_req_qid_1d;

    logic                  nettx_alloc_slot_no_req_vld,nettx_alloc_slot_no_req_rdy;

    logic [1:0]            sch_req,sch_grant;
    logic                  sch_en,sch_grant_vld;

    always @(posedge clk)begin
        if(rst)begin
            notify_req_qid_1d <= 0;
        end
        else if(notify_req_vld && notify_req_rdy)begin
            notify_req_qid_1d <= notify_req_qid;
        end
    end

    always @(posedge clk)begin
        if(slot_ctrl_ctx_info_rd_rsp_vld)begin
            slot_ctrl_ctx_info_rd_rsp_qos_unit_1d <= slot_ctrl_ctx_info_rd_rsp_qos_unit;
            slot_ctrl_ctx_info_rd_rsp_qos_enable_1d <= slot_ctrl_ctx_info_rd_rsp_qos_enable;
            slot_ctrl_ctx_info_rd_rsp_dev_id_1d <= slot_ctrl_ctx_info_rd_rsp_dev_id;
        end
    end


    always @(posedge clk)begin
        if(rst)begin
            cstate <= IDLE;
        end
        else begin
            cstate <= nstate;
        end
    end

    always @(*)begin
        nstate = cstate;
        case(cstate)
        IDLE:
            begin
                if(notify_req_vld)
                    nstate = RD_CTX;                   
            end
        RD_CTX:
            begin // 检测是否开启限速
                if(slot_ctrl_ctx_info_rd_rsp_qos_enable == 0)
                    nstate = QOS_DISABLE;
                else  
                    nstate = QOS_REQ; 
            end
        QOS_DISABLE: // 无流控处理
            begin
                if(nettx_alloc_slot_req_rdy)
                    nstate = IDLE;
            end
        QOS_REQ: // 令牌查询
            begin
                if(qos_query_req_rdy)
                    nstate = QOS_RSP;
            end
        QOS_RSP: // 等待令牌查询结果
            begin
                if(qos_query_rsp_vld && qos_query_rsp_data == 0 && nettx_alloc_slot_no_req_rdy)
                    nstate = IDLE;
                else if(qos_query_rsp_vld && qos_query_rsp_data == 1 && nettx_alloc_slot_req_rdy)
                    nstate = IDLE;    
            end

        default: nstate = cstate;
        endcase
    end

    assign notify_req_rdy = cstate == RD_CTX; // 只有处理完一个描述符后才会回到IDLE 然后检测req_vld
    //assign qos_query_rsp_rdy = cstate == QOS_RSP && nstate == IDLE;
    always @(posedge clk)begin // 限速查询指令处理完毕
        qos_query_rsp_rdy <= (cstate == QOS_RSP && nstate == IDLE);
    end

    assign qos_query_req_vld = cstate == QOS_REQ;
    assign qos_query_req_uid = slot_ctrl_ctx_info_rd_rsp_qos_unit_1d;
    // 上下文读取请求
    assign slot_ctrl_ctx_info_rd_req_vld = cstate == IDLE && notify_req_vld;
    assign slot_ctrl_ctx_info_rd_req_qid.qid = notify_req_qid;
    assign slot_ctrl_ctx_info_rd_req_qid.typ = VIRTIO_NET_TX_TYPE; //指定类型为发送队列
    // 描述符槽位申请
    assign nettx_alloc_slot_req_vld = (cstate == QOS_DISABLE) 
                                    ||(cstate == QOS_RSP && qos_query_rsp_vld && qos_query_rsp_data == 1 ) ;
    assign nettx_alloc_slot_req_dev_id = slot_ctrl_ctx_info_rd_rsp_dev_id_1d;
    assign nettx_alloc_slot_req_data.qid = notify_req_qid_1d;
    assign nettx_alloc_slot_req_data.typ = VIRTIO_NET_TX_TYPE;
    // 内部仲裁请求
    assign sch_req = {nettx_alloc_slot_no_req_vld,nettx_alloc_slot_rsp_vld};
    // nettx_alloc_slot_no_req_vld:QoS拦截 
    // nettx_alloc_slot_rsp_vld：成功被分配槽位
    assign sch_en = rr_cstate == RR_IDLE && sch_req > 0;
    // 循环仲裁器 上一拍谁优先这一拍不优先 起点为低位优先
    rr_sch#(
        .SH_NUM (2)                             // 仲裁源的数量           
    )u_rr_sch(
       .clk              ( clk ),
       .rst              ( rst ),
       .sch_req          ( sch_req ),           // 每一位代表一个请求源
       .sch_en           ( sch_en ), 
       .sch_grant        ( sch_grant ),         // 结果-独热码形式-为1代表胜出
       .sch_grant_vld    ( sch_grant_vld )      // 仲裁结果有效标志  
     );


     always @(posedge clk)begin
        if(rst)begin
            rr_cstate <= RR_IDLE;
        end
        else begin
            rr_cstate <= rr_nstate;
        end
    end
    // 管理响应阶段的握手逻辑
    always @(*)begin
        rr_nstate = rr_cstate;
        case(rr_cstate)
        RR_IDLE:
            begin
                if(sch_req > 0)
                    rr_nstate = SCH_PROC;              
            end
        SCH_PROC: // 锁死胜出的响应信号
            begin
                if(notify_rsp_vld && notify_rsp_rdy)
                    rr_nstate = RR_IDLE;
            end

        default: rr_nstate = rr_cstate;
        endcase
    end

    assign nettx_alloc_slot_no_req_vld = cstate == QOS_RSP && qos_query_rsp_vld && qos_query_rsp_data == 0;
    assign nettx_alloc_slot_no_req_rdy = sch_grant_vld && sch_grant[1] == 1;

    assign nettx_alloc_slot_rsp_rdy = sch_grant_vld && sch_grant[0] == 1;

    always @(posedge clk)begin
        if(rst)begin
            notify_rsp_vld <= 0;
            notify_rsp_qid <= 0;
            notify_rsp_cold <= 0;
            notify_rsp_done <= 0;
        end
        else if(notify_rsp_vld && notify_rsp_rdy)begin
            notify_rsp_vld <= 0;
        end
        else if(sch_grant_vld &&  sch_grant[1] == 1)begin
            notify_rsp_vld <= 1;
            notify_rsp_qid <= notify_req_qid_1d;
            notify_rsp_cold <= 1;
            notify_rsp_done <= 0;
        end
        else if(sch_grant_vld &&  sch_grant[0] == 1)begin
            notify_rsp_vld <= 1;
            notify_rsp_qid <= nettx_alloc_slot_rsp_data.vq.qid;
            notify_rsp_cold <= nettx_alloc_slot_rsp_data.q_stat_stopping == 1 
                            || (nettx_alloc_slot_rsp_data.local_ring_empty == 1 && nettx_alloc_slot_rsp_data.q_stat_doing == 1)
                            || nettx_alloc_slot_rsp_data.desc_engine_limit;
            notify_rsp_done <= (nettx_alloc_slot_rsp_data.local_ring_empty == 1 && nettx_alloc_slot_rsp_data.avail_ring_empty == 1 && nettx_alloc_slot_rsp_data.q_stat_doing == 1) 
                            || (nettx_alloc_slot_rsp_data.q_stat_doing == 0 && nettx_alloc_slot_rsp_data.q_stat_stopping == 0);
        end

    end


    always @(posedge clk)begin
        dfx_status <= {notify_req_vld,
                       notify_req_rdy,
                       notify_rsp_vld,
                       notify_rsp_rdy,
                       nettx_alloc_slot_req_vld,
                       nettx_alloc_slot_req_rdy,
                       nettx_alloc_slot_rsp_vld,
                       nettx_alloc_slot_rsp_rdy,
                       qos_query_req_vld,
                       qos_query_req_rdy,
                       qos_query_rsp_vld,
                       qos_query_rsp_rdy,
                       cstate,
                       rr_cstate};

        // 如果分配失败且不是因为空，也不是因为限速，且 err_info 有值，则认为是错误
        // 注意：这里假设 err_info 在 ok=0 时有效
        dfx_err <= {56'd0, nettx_alloc_slot_rsp_data.err_info}; 
    end



endmodule
