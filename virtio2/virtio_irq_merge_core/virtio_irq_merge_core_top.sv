/******************************************************************************
 * 文件名称 : virtio_irq_merge_core_top.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/7/3
 * 功能描述 : 并行转串行.
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  07/03       Liuch       初始化版本
 ******************************************************************************/
module virtio_irq_merge_core_top #(
    parameter IRQ_MERGE_UINT_NUM       = 8,
    parameter IRQ_MERGE_UINT_NUM_WIDTH = $clog2(IRQ_MERGE_UINT_NUM),
    parameter QID_NUM                  = 256,
    parameter QID_WIDTH                = $clog2(QID_NUM),
    parameter TIME_MAP_WIDTH           = 2,
    parameter CLK_FREQ_M               = 200,
    parameter TIME_STAMP_UNIT_NS       = 500
) (
    input  logic                                             clk,
    input  logic                                             rst,
    // irq_in
    input  logic [QID_WIDTH-1:0]                             irq_in_qid,
    input  logic                                             irq_in_vld,
    output logic                                             irq_in_rdy,
    // irq_out
    output logic [QID_WIDTH-1:0]                             irq_out_qid,
    output logic                                             irq_out_vld,
    input  logic                                             irq_out_rdy,
    // msix_aggregation_time_rd_req
    output logic                                             msix_aggregation_time_rd_req_vld,
    output logic [(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]  msix_aggregation_time_rd_req_idx,
    // msix_aggregation_time_rd_rsp 
    input  logic                                             msix_aggregation_time_rd_rsp_vld,
    input  logic [IRQ_MERGE_UINT_NUM*3-1:0]                  msix_aggregation_time_rd_rsp_dat,       // list_len = 8
    // msix_aggregation_threshold_rd_req
    output logic                                             msix_aggregation_threshold_rd_req_vld,
    output logic [QID_WIDTH-1:0]                             msix_aggregation_threshold_rd_req_idx,
    // msix_aggregation_threshold_rd_rsp
    input  logic                                             msix_aggregation_threshold_rd_rsp_vld,
    input  logic [6:0]                                       msix_aggregation_threshold_rd_rsp_dat,
    // msix_aggregation_info_rd_req
    output logic                                             msix_aggregation_info_rd_req_vld,
    output logic [(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]  msix_aggregation_info_rd_req_idx,
    // msix_aggregation_info_rd_rsp
    input  logic                                             msix_aggregation_info_rd_rsp_vld,
    input  logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0] msix_aggregation_info_rd_rsp_dat,
    // msix_aggregation_info_wr
    output logic                                             msix_aggregation_info_wr_vld,
    output logic [(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0]  msix_aggregation_info_wr_idx,
    output logic [IRQ_MERGE_UINT_NUM*(TIME_MAP_WIDTH+8)-1:0] msix_aggregation_info_wr_dat,
    // dfx
    output logic [3:0]                                       dfx_irq_merge_core_err
);
    localparam ENG_OUT_FF_WIDTH = QID_WIDTH - IRQ_MERGE_UINT_NUM_WIDTH + IRQ_MERGE_UINT_NUM;
    localparam ENG_OUT_FF_DEPTH = 256 * 2 / IRQ_MERGE_UINT_NUM;
    localparam ENG_OUT_FF_PFULL = (256 / IRQ_MERGE_UINT_NUM) - 4;
    localparam ENG_OUT_FF_USEDW = $clog2(ENG_OUT_FF_DEPTH + 1);


    logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0]                      scan_out_qid;
    logic                                                               scan_out_vld;
    logic                                                               scan_out_rdy;


    logic [15:0]                                                        time_stamp;
    logic                                                               time_stamp_imp;


    logic [QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH-1:0]                      eng_in_qid;
    logic [IRQ_MERGE_UINT_NUM-1:0]                                      eng_in_vld;
    logic                                                               eng_in_rdy;
    logic                                                               eng_in_flag;


    logic [IRQ_MERGE_UINT_NUM*(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] eng_out_qid;
    logic [IRQ_MERGE_UINT_NUM-1:0]                                      eng_out_vld;


    logic [IRQ_MERGE_UINT_NUM-1:0]                                      msix_aggregation_time_rd_req_vld_eng;
    logic [IRQ_MERGE_UINT_NUM*(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] msix_aggregation_time_rd_req_idx_eng;
    logic [IRQ_MERGE_UINT_NUM-1:0]                                      msix_aggregation_threshold_rd_req_vld_eng;
    logic [IRQ_MERGE_UINT_NUM*QID_WIDTH-1:0]                            msix_aggregation_threshold_rd_req_idx_eng;
    logic [IRQ_MERGE_UINT_NUM-1:0]                                      msix_aggregation_info_rd_req_vld_eng;
    logic [IRQ_MERGE_UINT_NUM*(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] msix_aggregation_info_rd_req_idx_eng;
    logic [IRQ_MERGE_UINT_NUM-1:0]                                      msix_aggregation_info_wr_vld_eng;
    logic [IRQ_MERGE_UINT_NUM*(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)-1:0] msix_aggregation_info_wr_idx_eng;

    // eng_out_ff
    logic                                                               eng_out_ff_wren;
    logic [ENG_OUT_FF_WIDTH-1:0]                                        eng_out_ff_din;
    // logic                        eng_out_ff_full;
    logic                                                               eng_out_ff_pfull;
    logic                                                               eng_out_ff_overflow;
    logic                                                               eng_out_ff_rden;
    logic [ENG_OUT_FF_WIDTH-1:0]                                        eng_out_ff_dout;
    logic                                                               eng_out_ff_empty;
    // logic                        eng_out_ff_pempty;
    logic                                                               eng_out_ff_underflow;
    // logic [ENG_OUT_FF_USEDW-1:0] eng_out_ff_usedw;
    logic [1:0]                                                         eng_out_ff_err;


    // mux_nto1
    logic [IRQ_MERGE_UINT_NUM-1:0]                                      mux_in_dat;
    logic                                                               mux_in_vld;
    logic                                                               mux_in_rdy;
    logic [IRQ_MERGE_UINT_NUM-1:0]                                      mux_out_dat;
    logic                                                               mux_out_vld;
    logic                                                               mux_out_rdy;
    logic                                                               rst_logic;

    assign eng_in_rdy   = (irq_in_rdy || scan_out_rdy) && rst_logic;
    assign irq_in_rdy   = !eng_out_ff_pfull && eng_in_flag == 1 && rst_logic;
    assign scan_out_rdy = eng_in_flag == 0;
    assign eng_in_qid   = eng_in_flag ? irq_in_qid[QID_WIDTH-1:IRQ_MERGE_UINT_NUM_WIDTH] : scan_out_qid;

    always @(posedge clk) begin
        if (rst) begin
            eng_in_flag <= 'b0;
            rst_logic   <= 1'b0;
        end else begin
            eng_in_flag <= ~eng_in_flag;
            rst_logic   <= 1'b1;
        end
    end


    virtio_irq_merge_core_scan #(
        .IRQ_MERGE_UINT_NUM(IRQ_MERGE_UINT_NUM),
        .QID_NUM           (QID_NUM)
    ) u_virtio_irq_merge_core_scan (
        .clk           (clk),
        .rst           (rst),
        .scan_out_qid  (scan_out_qid),
        .scan_out_vld  (scan_out_vld),
        .scan_out_rdy  (scan_out_rdy),
        .time_stamp_imp(time_stamp_imp)
    );



    generate
        genvar i;
        for (i = 0; i < IRQ_MERGE_UINT_NUM; i = i + 1) begin : CORE_ENG
            assign eng_in_vld[i] = eng_in_flag ? irq_in_vld && irq_in_qid[IRQ_MERGE_UINT_NUM_WIDTH-1:0] == i : scan_out_vld;

            virtio_irq_merge_core_eng #(
                .IRQ_MERGE_UINT_NUM(IRQ_MERGE_UINT_NUM),
                .QID_NUM           (QID_NUM),
                .TIME_MAP_WIDTH    (TIME_MAP_WIDTH)
            ) u_virtio_irq_merge_core_eng (
                .clk                                  (clk),
                .rst                                  (rst),
                .eng_id                               (i),
                .time_stamp                           (time_stamp),
                // eng_in
                .eng_in_qid                           (eng_in_qid),
                .eng_in_vld                           (eng_in_vld[i]),
                .eng_in_rdy                           (eng_in_rdy),
                .eng_in_flag                          (eng_in_flag),
                // eng_out
                .eng_out_qid                          (eng_out_qid[i*(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)+:QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH]),
                .eng_out_vld                          (eng_out_vld[i]),
                // msix_aggregation_time_rd_req
                .msix_aggregation_time_rd_req_vld     (msix_aggregation_time_rd_req_vld_eng[i]),
                .msix_aggregation_time_rd_req_idx     (msix_aggregation_time_rd_req_idx_eng[i*(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)+:QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH]),
                // msix_aggregation_time_rd_rsp
                .msix_aggregation_time_rd_rsp_vld     (msix_aggregation_time_rd_rsp_vld),
                .msix_aggregation_time_rd_rsp_dat     (msix_aggregation_time_rd_rsp_dat[i*IRQ_MERGE_UINT_NUM_WIDTH+:IRQ_MERGE_UINT_NUM_WIDTH]),
                // msix_aggregation_threshold_rd_req
                .msix_aggregation_threshold_rd_req_vld(msix_aggregation_threshold_rd_req_vld_eng[i]),
                .msix_aggregation_threshold_rd_req_idx(msix_aggregation_threshold_rd_req_idx_eng[i*QID_WIDTH+:QID_WIDTH]),
                // msix_aggregation_threshold_rd_rsp
                .msix_aggregation_threshold_rd_rsp_vld(msix_aggregation_threshold_rd_rsp_vld),
                .msix_aggregation_threshold_rd_rsp_dat(msix_aggregation_threshold_rd_rsp_dat),
                // msix_aggregation_info_rd_req
                .msix_aggregation_info_rd_req_vld     (msix_aggregation_info_rd_req_vld_eng[i]),
                .msix_aggregation_info_rd_req_idx     (msix_aggregation_info_rd_req_idx_eng[i*(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)+:QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH]),
                // msix_aggregation_info_rd_rsp
                .msix_aggregation_info_rd_rsp_vld     (msix_aggregation_info_rd_rsp_vld),
                .msix_aggregation_info_rd_rsp_dat     (msix_aggregation_info_rd_rsp_dat[i*(TIME_MAP_WIDTH+8)+:(TIME_MAP_WIDTH+8)]),
                // msix_aggregation_info_wr
                .msix_aggregation_info_wr_vld         (msix_aggregation_info_wr_vld_eng[i]),
                .msix_aggregation_info_wr_idx         (msix_aggregation_info_wr_idx_eng[i*(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)+:QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH]),
                .msix_aggregation_info_wr_dat         (msix_aggregation_info_wr_dat[i*(TIME_MAP_WIDTH+8)+:(TIME_MAP_WIDTH+8)])
            );

        end
    endgenerate

    assign msix_aggregation_time_rd_req_vld      = |msix_aggregation_time_rd_req_vld_eng;
    assign msix_aggregation_time_rd_req_idx      = msix_aggregation_time_rd_req_idx_eng[0+:QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH];


    assign msix_aggregation_threshold_rd_req_vld = |msix_aggregation_threshold_rd_req_vld_eng;

    integer j;

    always @(*) begin
        msix_aggregation_threshold_rd_req_idx = 0;
        for (j = 0; j < IRQ_MERGE_UINT_NUM; j = j + 1) begin
            if (msix_aggregation_threshold_rd_req_vld_eng[j]) begin
                msix_aggregation_threshold_rd_req_idx = msix_aggregation_threshold_rd_req_idx_eng[QID_WIDTH*j+:QID_WIDTH];
            end
        end
    end


    assign msix_aggregation_info_rd_req_vld = |msix_aggregation_info_rd_req_vld_eng;
    assign msix_aggregation_info_rd_req_idx = msix_aggregation_info_rd_req_idx_eng[0+:QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH];

    assign msix_aggregation_info_wr_vld     = |msix_aggregation_info_wr_vld_eng;
    assign msix_aggregation_info_wr_idx     = msix_aggregation_info_wr_idx_eng[0+:QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH];


    virtio_irq_merge_core_time #(
        .CLK_FREQ_M        (CLK_FREQ_M),
        .TIME_STAMP_UNIT_NS(TIME_STAMP_UNIT_NS)
    ) u_virtio_irq_merge_core_time (
        .clk           (clk),
        .rst           (rst),
        .time_stamp    (time_stamp),
        .time_stamp_imp(time_stamp_imp)
    );



    yucca_sync_fifo #(
        .DATA_WIDTH (ENG_OUT_FF_WIDTH),
        .FIFO_DEPTH (ENG_OUT_FF_DEPTH),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL(ENG_OUT_FF_PFULL),
        .RAM_MODE   ("dist"),
        .FIFO_MODE  ("fwft")
    ) u_eng_out_ff (
        .clk           (clk),
        .rst           (rst),
        .wren          (eng_out_ff_wren),
        .din           (eng_out_ff_din),
        .full          (),
        // .full          (eng_out_ff_full),
        .pfull         (eng_out_ff_pfull),
        .overflow      (eng_out_ff_overflow),
        .rden          (eng_out_ff_rden),
        .dout          (eng_out_ff_dout),
        .empty         (eng_out_ff_empty),
        .pempty        (),
        // .pempty        (eng_out_ff_pempty),
        .underflow     (eng_out_ff_underflow),
        .usedw         (),
        // .usedw         (eng_out_ff_usedw),
        .parity_ecc_err(eng_out_ff_err)
    );
    assign eng_out_ff_wren             = |eng_out_vld;
    assign eng_out_ff_din              = {eng_out_qid[0+:(QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH)], eng_out_vld};

    assign eng_out_ff_rden             = mux_in_vld && mux_in_rdy;

    assign dfx_irq_merge_core_err[3]   = eng_out_ff_overflow;
    assign dfx_irq_merge_core_err[2]   = eng_out_ff_underflow;
    assign dfx_irq_merge_core_err[1:0] = eng_out_ff_err;

    mux_nto1 #(
        .N(IRQ_MERGE_UINT_NUM)
    ) u_mux_nto1 (
        .clk        (clk),
        .rst        (rst),
        .mux_in_dat (mux_in_dat),
        .mux_in_vld (mux_in_vld),
        .mux_in_rdy (mux_in_rdy),
        .mux_out_dat(mux_out_dat),
        .mux_out_vld(mux_out_vld),
        .mux_out_rdy(mux_out_rdy)
    );

    assign mux_in_dat  = eng_out_ff_dout[0+:IRQ_MERGE_UINT_NUM];
    assign mux_in_vld  = !eng_out_ff_empty;
    assign mux_out_rdy = irq_out_rdy;



    logic [IRQ_MERGE_UINT_NUM_WIDTH-1:0] irq_out_hot;

    assign irq_out_vld = mux_out_vld;
    integer k;
    always @(*) begin
        irq_out_hot = 0;
        irq_out_qid = 0;
        for (k = 0; k < IRQ_MERGE_UINT_NUM; k = k + 1) begin
            if (mux_out_dat[k]) begin
                irq_out_hot = k;
                irq_out_qid = {eng_out_ff_dout[IRQ_MERGE_UINT_NUM+:QID_WIDTH-IRQ_MERGE_UINT_NUM_WIDTH], irq_out_hot};
            end
        end
    end

    // ERR_INFO
    logic msix_aggregation_threshold_rd_req_vld_eng_err;
    assign msix_aggregation_threshold_rd_req_vld_eng_err = (msix_aggregation_threshold_rd_req_vld_eng & (msix_aggregation_threshold_rd_req_vld_eng - 1)) != 0;
    assert property (@(posedge clk) msix_aggregation_threshold_rd_req_vld_eng_err !== 1)
    else $fatal(0, "msix_aggregation_threshold_rd_req_vld_eng  error  has two vld");



endmodule : virtio_irq_merge_core_top
