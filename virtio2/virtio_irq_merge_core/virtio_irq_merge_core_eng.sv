/******************************************************************************
 * 文件名称 : virtio_irq_merge_core_eng.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/07/03
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   07/03      Liuch       初始化版本
 ******************************************************************************/
module virtio_irq_merge_core_eng #(
    parameter IRQ_MERGE_UINT_NUM       = 4,
    parameter IRQ_MERGE_UINT_NUM_WIDTH = $clog2(IRQ_MERGE_UINT_NUM),
    parameter QID_NUM                  = 256,
    parameter QID_WIDTH                = $clog2(QID_NUM),
    parameter TIME_MAP_WIDTH           = 2
) (
    input  logic                                          clk,
    input  logic                                          rst,
    // eng_id
    input  logic [IRQ_MERGE_UINT_NUM_WIDTH-1:0]           eng_id,
    // time_stamp
    input  logic [15:0]                                   time_stamp,
    // eng_in
    input  logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] eng_in_qid,
    input  logic                                          eng_in_vld,
    input  logic                                          eng_in_rdy,
    input  logic                                          eng_in_flag,
    // eng_out
    output logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] eng_out_qid,
    output logic                                          eng_out_vld,
    // msix_aggregation_time_rd_req
    output logic                                          msix_aggregation_time_rd_req_vld,
    output logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] msix_aggregation_time_rd_req_idx,
    // msix_aggregation_time_rd_rsp 
    input  logic                                          msix_aggregation_time_rd_rsp_vld,
    input  logic [2:0]                                    msix_aggregation_time_rd_rsp_dat,
    // msix_aggregation_threshold_rd_req
    output logic                                          msix_aggregation_threshold_rd_req_vld,
    output logic [QID_WIDTH-1:0]                          msix_aggregation_threshold_rd_req_idx,
    // msix_aggregation_threshold_rd_rsp
    input  logic                                          msix_aggregation_threshold_rd_rsp_vld,
    input  logic [6:0]                                    msix_aggregation_threshold_rd_rsp_dat,
    // msix_aggregation_info_rd_req
    output logic                                          msix_aggregation_info_rd_req_vld,
    output logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] msix_aggregation_info_rd_req_idx,
    // msix_aggregation_info_rd_rsp
    input  logic                                          msix_aggregation_info_rd_rsp_vld,
    input  logic [8+TIME_MAP_WIDTH-1:0]                   msix_aggregation_info_rd_rsp_dat,
    // msix_aggregation_info_wr
    output logic                                          msix_aggregation_info_wr_vld,
    output logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] msix_aggregation_info_wr_idx,
    output logic [8+TIME_MAP_WIDTH-1:0]                   msix_aggregation_info_wr_dat


);
    // STAGE0
    logic                                          vld_stage0;
    logic                                          eng_in_flag0;
    logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] eng_in_qid_stage0;

    //STAGE1
    logic                                          vld_stage1;
    logic                                          eng_in_flag1;
    logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] eng_in_qid_stage1;
    logic [TIME_MAP_WIDTH-1:0]                     time_map_curr_stage1;
    logic [TIME_MAP_WIDTH-1:0]                     time_map_next_stage1;
    logic [2:0]                                    msix_aggregation_time_stage1;
    logic [6:0]                                    msix_aggregation_threshold_stage1;

    //STAGE2
    logic                                          vld_stage2;
    logic                                          vld_d_stage2;
    logic                                          eng_in_flag2;
    logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] eng_in_qid_stage2;
    logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] eng_in_qid_d_stage2;
    logic [TIME_MAP_WIDTH-1:0]                     time_map_curr_stage2;
    logic [TIME_MAP_WIDTH-1:0]                     time_map_next_stage2;
    logic [6:0]                                    msix_aggregation_threshold_stage2;

    logic                                          msix_aggregation_info_en_stage2;
    logic [TIME_MAP_WIDTH-1:0]                     msix_aggregation_info_time_map_stage2;
    logic [6:0]                                    msix_aggregation_info_irq_cnt_stage2;
    logic [6:0]                                    msix_aggregation_info_irq_cnt_add_stage2;

    logic                                          msix_aggregation_info_wr_en_stage2;
    logic [TIME_MAP_WIDTH-1:0]                     msix_aggregation_info_wr_time_map_stage2;
    logic [6:0]                                    msix_aggregation_info_wr_irq_cnt_stage2;





    //STAGE3
    logic                                          vld_stage3;
    logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0] eng_in_qid_stage3;

    logic                                          msix_aggregation_info_wr_en;
    logic [TIME_MAP_WIDTH-1:0]                     msix_aggregation_info_wr_time_map;
    logic [6:0]                                    msix_aggregation_info_wr_irq_cnt;



    // STAGE0
    assign msix_aggregation_time_rd_req_vld      = eng_in_vld && eng_in_rdy;
    assign msix_aggregation_time_rd_req_idx      = eng_in_qid;
    assign msix_aggregation_threshold_rd_req_vld = eng_in_flag && eng_in_vld && eng_in_rdy;
    assign msix_aggregation_threshold_rd_req_idx = {eng_in_qid, eng_id};
    assign vld_stage0                            = eng_in_vld && eng_in_rdy;
    assign eng_in_qid_stage0                     = eng_in_qid;
    assign eng_in_flag0                          = eng_in_flag;

    // STAGE1
    assign msix_aggregation_info_rd_req_vld      = vld_stage1;
    assign msix_aggregation_threshold_stage1     = msix_aggregation_threshold_rd_rsp_dat;
    assign msix_aggregation_time_stage1          = msix_aggregation_time_rd_rsp_dat;
    assign time_map_curr_stage1                  = time_stamp >> msix_aggregation_time_stage1;
    assign time_map_next_stage1                  = (time_stamp >> msix_aggregation_time_stage1) - 1;

    always @(posedge clk) begin
        vld_stage1                       <= vld_stage0;
        msix_aggregation_info_rd_req_idx <= eng_in_qid_stage0;
        eng_in_flag1                     <= eng_in_flag0;
        eng_in_qid_stage1                <= eng_in_qid_stage0;
    end

    // STAGE2
    assign msix_aggregation_info_en_stage2          = vld_d_stage2 && eng_in_qid_stage2 == eng_in_qid_d_stage2 ? msix_aggregation_info_wr_en_stage2 : msix_aggregation_info_rd_rsp_dat[7+TIME_MAP_WIDTH+:1];
    assign msix_aggregation_info_time_map_stage2    = vld_d_stage2 && eng_in_qid_stage2 == eng_in_qid_d_stage2 ? msix_aggregation_info_wr_time_map_stage2 : msix_aggregation_info_rd_rsp_dat[7+:TIME_MAP_WIDTH];
    assign msix_aggregation_info_irq_cnt_stage2     = vld_d_stage2 && eng_in_qid_stage2 == eng_in_qid_d_stage2 ? msix_aggregation_info_wr_irq_cnt_stage2 : msix_aggregation_info_rd_rsp_dat[0+:7];
    assign msix_aggregation_info_irq_cnt_add_stage2 = msix_aggregation_info_irq_cnt_stage2 + 1;

    always @(posedge clk) begin
        vld_stage2                        <= vld_stage1;
        vld_d_stage2                      <= vld_stage2;

        eng_in_flag2                      <= eng_in_flag1;

        eng_in_qid_stage2                 <= eng_in_qid_stage1;
        eng_in_qid_d_stage2               <= eng_in_qid_stage2;

        time_map_curr_stage2              <= time_map_curr_stage1;
        time_map_next_stage2              <= time_map_next_stage1;
        msix_aggregation_threshold_stage2 <= msix_aggregation_threshold_stage1;
    end

    always @(posedge clk) begin
        msix_aggregation_info_wr_en_stage2       <= msix_aggregation_info_en_stage2;
        msix_aggregation_info_wr_time_map_stage2 <= msix_aggregation_info_time_map_stage2;
        msix_aggregation_info_wr_irq_cnt_stage2  <= msix_aggregation_info_irq_cnt_stage2;
        if (vld_stage2) begin
            if (eng_in_flag2) begin
                if (msix_aggregation_threshold_stage2 == msix_aggregation_info_irq_cnt_add_stage2 && msix_aggregation_threshold_stage2 != 'd0) begin
                    msix_aggregation_info_wr_en_stage2       <= 'b0;
                    msix_aggregation_info_wr_time_map_stage2 <= msix_aggregation_info_time_map_stage2;
                    msix_aggregation_info_wr_irq_cnt_stage2  <= 'b0;
                end else begin
                    if (msix_aggregation_info_en_stage2) begin
                        msix_aggregation_info_wr_en_stage2       <= msix_aggregation_info_en_stage2;
                        msix_aggregation_info_wr_time_map_stage2 <= msix_aggregation_info_time_map_stage2;
                        msix_aggregation_info_wr_irq_cnt_stage2  <= msix_aggregation_info_irq_cnt_add_stage2;
                    end else begin
                        msix_aggregation_info_wr_en_stage2       <= 'b1;
                        msix_aggregation_info_wr_time_map_stage2 <= time_map_next_stage2;
                        msix_aggregation_info_wr_irq_cnt_stage2  <= 'b1;
                    end
                end
            end else begin
                if (msix_aggregation_info_en_stage2 && time_map_curr_stage2 == msix_aggregation_info_time_map_stage2) begin
                    msix_aggregation_info_wr_en_stage2       <= 'b0;
                    msix_aggregation_info_wr_time_map_stage2 <= msix_aggregation_info_time_map_stage2;
                    msix_aggregation_info_wr_irq_cnt_stage2  <= 'b0;
                end
            end
        end
    end





    // STAGE3
    assign msix_aggregation_info_wr_vld      = vld_stage3;
    assign msix_aggregation_info_wr_idx      = eng_in_qid_stage3;
    assign msix_aggregation_info_wr_dat      = {msix_aggregation_info_wr_en, msix_aggregation_info_wr_time_map, msix_aggregation_info_wr_irq_cnt};

    assign msix_aggregation_info_wr_en       = msix_aggregation_info_wr_en_stage2;
    assign msix_aggregation_info_wr_time_map = msix_aggregation_info_wr_time_map_stage2;
    assign msix_aggregation_info_wr_irq_cnt  = msix_aggregation_info_wr_irq_cnt_stage2;

    always @(posedge clk) begin
        vld_stage3           <= vld_stage2;
        eng_in_qid_stage3    <= eng_in_qid_stage2;
    end

    always @(posedge clk) begin
        eng_out_vld <= 'b0;
        eng_out_qid <= eng_in_qid_stage2;
        if (vld_stage2) begin
            if (eng_in_flag2 && (msix_aggregation_threshold_stage2 == msix_aggregation_info_irq_cnt_add_stage2) && msix_aggregation_threshold_stage2 != 0) begin
                eng_out_vld <= 'b1;
            end else if (!eng_in_flag2 && msix_aggregation_info_en_stage2 && time_map_curr_stage2 == msix_aggregation_info_time_map_stage2) begin
                eng_out_vld <= 'b1;
            end
        end
    end
    // STAGE2 --> eng_out


    // EER_INFO
    // logic msix_aggregation_time_rd_err;
    // logic msix_aggregation_time_rd_req_vld_r;
    // always @(posedge clk) begin
    //     msix_aggregation_time_rd_req_vld_r <= msix_aggregation_time_rd_req_vld;
    // end
    // assign msix_aggregation_time_rd_err = msix_aggregation_time_rd_req_vld_r ^ msix_aggregation_time_rd_rsp_vld;
    // assert property (@(posedge clk) !msix_aggregation_time_rd_err !== 1)
    // else $fatal(0, "msix_aggregation_time_rd_rsp_vld err");

    // logic msix_aggregation_threshold_rd_err;
    // logic msix_aggregation_threshold_rd_req_vld_r;
    // always @(posedge clk) begin
    //     msix_aggregation_threshold_rd_req_vld_r <= msix_aggregation_threshold_rd_req_vld;
    // end
    // assign msix_aggregation_threshold_rd_err = msix_aggregation_threshold_rd_req_vld_r ? !msix_aggregation_threshold_rd_rsp_vld : 1'b0;
    // assert property (@(posedge clk) !msix_aggregation_threshold_rd_err !== 1)
    // else $fatal(0, "msix_aggregation_threshold_rd_rsp_vld err");

    // logic msix_aggregation_info_rd_req_err;
    // logic msix_aggregation_info_rd_req_vld_r;
    // always @(posedge clk) begin
    //     msix_aggregation_info_rd_req_vld_r <= msix_aggregation_info_rd_req_vld;
    // end
    // assign msix_aggregation_info_rd_req_err = msix_aggregation_info_rd_req_vld_r ^ msix_aggregation_info_rd_rsp_vld;
    // assert property (@(posedge clk) !msix_aggregation_info_rd_req_err !== 1)
    // else $fatal(0, "msix_aggregation_info_rd_req err");



endmodule : virtio_irq_merge_core_eng
