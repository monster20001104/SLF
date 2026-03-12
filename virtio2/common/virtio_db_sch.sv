/******************************************************************************
 * 文件名称 : virtio_db_sch.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/09/08
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  09/08     Joe Jiang   初始化版本
 ******************************************************************************/
 module virtio_db_sch #(
    parameter Q_WIDTH = 10
 ) (
    input                      clk,
    input                      rst,

    input  logic [Q_WIDTH-1:0] doorbell_req_vq,
    input  logic               doorbell_req_vld,
    output logic               doorbell_req_rdy,

    input  logic [Q_WIDTH-1:0] soc_notify_req_qid,
    input  logic               soc_notify_req_vld,
    output logic               soc_notify_req_rdy,

    output logic [Q_WIDTH-1:0] notify_req_qid,
    output logic               notify_req_vld,
    input  logic               notify_req_rdy

 );

    enum logic [1:0]  { 
        IDLE    = 2'b01,
        SCH     = 2'b10
    } cstat, nstat;

    logic [1:0] sch_req, sch_grant, sch_grant_d;
    logic sch_en, sch_grant_vld;

    assign sch_req = {doorbell_req_vld, soc_notify_req_vld};
    assign sch_en  = cstat == IDLE;

    rr_sch#(
        .SH_NUM(2)
    )u_rr_sch(
        .clk          (clk          ),
        .rst          (rst          ),
        .sch_req      (sch_req      ),
        .sch_en       (sch_en       ), 
        .sch_grant    (sch_grant    ), 
        .sch_grant_vld(sch_grant_vld)   
    );

    always @(posedge clk) begin
        if(rst)begin
            cstat <= IDLE;
        end else begin
            cstat <= nstat;
        end
    end

    always @(*) begin
        nstat = cstat;
        case (cstat)
            IDLE: begin
                if(sch_grant_vld)begin
                    nstat = SCH;
                end
            end
            SCH: begin
                if(notify_req_rdy || !notify_req_vld)begin
                    nstat = IDLE;
                end
            end
        endcase
    end

    assign soc_notify_req_rdy   = cstat == SCH && sch_grant_d[0] && (notify_req_rdy || !notify_req_vld);
    assign doorbell_req_rdy     = cstat == SCH && sch_grant_d[1] && (notify_req_rdy || !notify_req_vld);

    always @(posedge clk) begin
        if(cstat == IDLE)begin
            sch_grant_d <= sch_grant;
        end
    end

    always @(posedge clk) begin
        if(rst)begin
            notify_req_vld <= 1'b0;
        end if(notify_req_rdy || !notify_req_vld)begin
            notify_req_vld <= cstat == SCH;
        end
    end

    always @(posedge clk) begin
        if(notify_req_rdy || !notify_req_vld)begin
            if(sch_grant_d[0])begin
                notify_req_qid <= soc_notify_req_qid;
            end else if(sch_grant_d[1])begin
                notify_req_qid <= doorbell_req_vq;
            end
        end
    end
    
 endmodule