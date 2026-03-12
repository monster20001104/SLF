/******************************************************************************
 * 文件名称 : virtio_blk_desc_engine_core.sv
 * 作者名称 : Liuch
 * 创建日期 : 2025/07/08
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0   07/08      Liuch       初始化版本
 ******************************************************************************/
`include "virtio_blk_desc_engine_define.svh"
`include "virtio_desc_engine_define.svh"
module virtio_blk_desc_engine_core #(
    parameter DATA_WIDTH            = 256,
    parameter EMPTH_WIDTH           = $clog2(DATA_WIDTH / 8),
    parameter QID_NUM               = 256,
    parameter QID_WIDTH             = $clog2(QID_NUM),
    parameter SLOT_NUM              = 4,
    parameter SLOT_ID_WIDTH         = $clog2(SLOT_NUM),
    parameter SLOT_CPL_FF_WIDTH     = QID_WIDTH + SLOT_ID_WIDTH + 1 + 8 + 21 + 16 + 16,
    parameter SLOT_CPL_FF_DEPTH     = 32,
    parameter SLOT_CPL_FF_USEDW     = $clog2(SLOT_CPL_FF_DEPTH + 1),
    parameter DESC_DMA_FF_WIDTH     = QID_WIDTH + SLOT_ID_WIDTH,
    parameter DESC_DMA_FF_DEPTH     = 32,
    parameter DESC_DMA_FF_USEDW     = $clog2(DESC_DMA_FF_DEPTH + 1),
    parameter LINE_NUM              = 8,
    parameter DESC_PER_BUCKET_NUM   = LINE_NUM * DATA_WIDTH / $bits(virtq_desc_t),
    parameter DESC_PER_BUCKET_WIDTH = $clog2(DESC_PER_BUCKET_NUM)

) (
    input  logic                                                      clk,
    input  logic                                                      rst,
    // first_submit
    input  logic                                                      first_submit_vld,
    output logic                                                      first_submit_rdy,
    input  logic                                [QID_WIDTH-1:0]       first_submit_qid,
    input  logic                                [15:0]                first_submit_idx,
    input  logic                                [15:0]                first_submit_id,
    input  logic                                                      first_submit_resummer,
    input  logic                                [SLOT_ID_WIDTH-1:0]   first_submit_slot_id,
    input  logic                                                      first_submit_cycle_flag,
    // rsp_submit
    input  logic                                                      info_rd_vld,
    input  virtio_desc_eng_core_info_ff_t                             info_rd_dat,
    output logic                                                      info_rd_rdy,
    // desc_dma_rd_req
           tlp_adap_dma_rd_req_if                                     desc_dma_rd_req,
    // slot_cpl
    // input  logic                                                        slot_cpl_ff_rden,
    // output logic                                [SLOT_CPL_FF_WIDTH-1:0] slot_cpl_ff_dout,
    // output logic                                                        slot_cpl_ff_empty,
    input  logic                                [SLOT_ID_WIDTH-1:0]   slot_cpl_ram_raddr,
    output logic                                [SLOT_CPL_FF_WIDTH:0] slot_cpl_ram_rdata,
    // order_wr
    output logic                                                      order_wr_vld,
    output virtio_desc_eng_core_rd_desc_order_t                       order_wr_dat,
    // blk_desc_global_info_rd_req
    output logic                                                      blk_desc_global_info_rd_req_vld,
    output logic                                [QID_WIDTH-1:0]       blk_desc_global_info_rd_req_qid,
    // blk_desc_global_info_rd_rsp
    input  logic                                                      blk_desc_global_info_rd_rsp_vld,
    input  logic                                [15:0]                blk_desc_global_info_rd_rsp_bdf,
    input  logic                                                      blk_desc_global_info_rd_rsp_forced_shutdown,
    input  logic                                [63:0]                blk_desc_global_info_rd_rsp_desc_tbl_addr,
    input  logic                                [3:0]                 blk_desc_global_info_rd_rsp_qdepth,
    input  logic                                                      blk_desc_global_info_rd_rsp_indirct_support,
    input  logic                                [19:0]                blk_desc_global_info_rd_rsp_segment_size_blk,
    // blk_desc_local_info_rd_req
    output logic                                                      blk_desc_local_info_rd_req_vld,
    output logic                                [QID_WIDTH-1:0]       blk_desc_local_info_rd_req_qid,
    // blk_desc_local_info_rd_rsp
    input  logic                                                      blk_desc_local_info_rd_rsp_vld,
    input  logic                                [63:0]                blk_desc_local_info_rd_rsp_desc_tbl_addr_blk,
    input  logic                                [31:0]                blk_desc_local_info_rd_rsp_desc_tbl_size_blk,
    input  logic                                [15:0]                blk_desc_local_info_rd_rsp_desc_tbl_next_blk,
    input  logic                                [15:0]                blk_desc_local_info_rd_rsp_desc_tbl_id_blk,
    input  logic                                [19:0]                blk_desc_local_info_rd_rsp_desc_cnt,
    input  logic                                [20:0]                blk_desc_local_info_rd_rsp_data_len,
    input  logic                                                      blk_desc_local_info_rd_rsp_is_indirct,
    // blk_desc_local_info_wr
    output logic                                                      blk_desc_local_info_wr_vld,
    output logic                                [QID_WIDTH-1:0]       blk_desc_local_info_wr_qid,
    output logic                                [63:0]                blk_desc_local_info_wr_desc_tbl_addr_blk,
    output logic                                [31:0]                blk_desc_local_info_wr_desc_tbl_size_blk,
    output logic                                [15:0]                blk_desc_local_info_wr_desc_tbl_next_blk,
    output logic                                [15:0]                blk_desc_local_info_wr_desc_tbl_id_blk,
    output logic                                [19:0]                blk_desc_local_info_wr_desc_cnt,
    output logic                                [20:0]                blk_desc_local_info_wr_data_len,
    output logic                                                      blk_desc_local_info_wr_is_indirct,
    // blk_desc_resumer_wr
    output logic                                                      blk_desc_resumer_wr_vld,
    output logic                                [QID_WIDTH-1:0]       blk_desc_resumer_wr_qid,
    output logic                                                      blk_desc_resumer_wr_dat,
    output virtio_blk_desc_engine_core_status_t                       state,
    output virtio_blk_desc_engine_core_err_t                          err,
    output logic                                                      flush_resummer,
    input  logic                                [19:0]                virtio_blk_desc_engine_max_chain_len


);
    enum logic [8:0] {
        INIT       = 9'b000000001,
        CTX_RD_REQ = 9'b000000010,
        CTX_RD_RSP = 9'b000000100,
        ERR_CHECK  = 9'b000001000,
        ERR_INFO   = 9'b000010000,
        FIRST      = 9'b000100000,
        RESUMER    = 9'b001000000,
        RSP        = 9'b010000000,
        DELAY      = 9'b100000000
    }
        core_cstat, core_nstat;
    // core_cstat, core_nstat;



    logic                                                    submit_vld;
    logic                                                    submit_rdy;
    logic                                                    vld_flag;

    logic                                                    rsp_submit_vld;
    logic                                                    rsp_submit_rdy;
    virtio_desc_eng_core_info_ff_t                           rsp_submit_dat;

    // logic             [QID_WIDTH-1:0]         rsp_submit_qid;
    // logic             [15:0]                  rsp_submit_data_len;
    // logic             [15:0]                  rsp_submit_desc_cnt;
    // logic             [SLOT_ID_WIDTH-1:0]     rsp_submit_slot;
    // virtq_desc_t                              rsp_submit_desc;


    logic                              [QID_WIDTH-1:0]       submit_qid;
    logic                              [15:0]                submit_id;
    logic                              [15:0]                submit_idx;
    logic                              [SLOT_ID_WIDTH-1:0]   submit_slot_id;
    logic                                                    submit_resummer;
    logic                                                    submit_cycle_flag;

    logic                              [20:0]                submit_rsp_data_len;
    logic                              [7:0]                 submit_rsp_desc_cnt;
    logic                                                    submit_rsp_last;
    logic                              [63:0]                submit_rsp_addr;
    // logic                                  [63:0]                submit_rsp_addr_id;
    logic                              [16:0]                submit_rsp_len;
    logic                                                    submit_rsp_indirct;




    // CTX_RD_RSP
    logic                              [15:0]                global_info_bdf;
    logic                                                    global_info_forced_shutdown;
    logic                              [63:0]                global_info_desc_tbl_addr;
    logic                              [63:0]                global_info_desc_tbl_addr_id;
    logic                              [3:0]                 global_info_qdepth;
    logic                                                    global_info_indirct_support;
    logic                              [19:0]                global_info_segment_size_blk;

    logic                              [63:0]                local_info_desc_tbl_addr_blk;
    logic                              [63:0]                local_info_desc_tbl_addr_blk_id;
    logic                              [17:0]                local_info_desc_tbl_size_blk;
    logic                              [15:0]                local_info_desc_tbl_next_blk;
    logic                              [15:0]                local_info_desc_tbl_id_blk;
    logic                              [19:0]                local_info_desc_cnt;
    logic                              [19:0]                local_info_desc_cnt_add;
    logic                              [19:0]                global_info_qdepth_num;
    logic                              [20:0]                local_info_data_len;
    logic                              [20:0]                local_info_data_len_add;
    logic                                                    local_info_is_indirct;

    logic                              [16:0]                info_desc_bkt_remain;
    logic                              [16:0]                info_desc_buf_remain;

    logic                                                    desc_next_oversize_flag;  // 'h40
    logic                                                    desc_chain_len_oversize_flag;  // 'h41
    // logic                                                    desc_data_len_oversize_flag;  // 'h42
    logic                                                    desc_unsupport_indirct_flag;  // 'h43
    logic                                                    desc_next_must_zero_flag;  // 'h44
    logic                                                    desc_indirct_nested_flag;  // 'h45
    logic                                                    desc_data_len_zero_flag;  // 'h46
    logic                                                    desc_chain_len_one;  // 'h47
    logic                                                    desc_pcie_err;  // 'h48
    logic                                                    desc_next_oversize_indirect_flag;  // 'h49
    logic                                                    desc_buf_len_oversize;  // 'h4a

    virtio_err_code_t                                        err_code;
    // u_slot_cpl_ram
    logic                                                    slot_cpl_ram_wren;
    logic                              [SLOT_ID_WIDTH-1:0]   slot_cpl_ram_waddr;
    logic                              [SLOT_CPL_FF_WIDTH:0] slot_cpl_ram_wdata;

    // logic                              [SLOT_ID_WIDTH-1:0]   slot_cpl_ram_raddr;
    // logic                              [SLOT_CPL_FF_WIDTH:0] slot_cpl_ram_rdata;

    logic                              [1:0]                 slot_cpl_ram_err;

    // u_slot_cpl_ff
    // logic                                                      slot_cpl_ff_wren;
    // logic                              [SLOT_CPL_FF_WIDTH-1:0] slot_cpl_ff_din;
    // // logic                                                      slot_cpl_ff_full;
    // // logic                                                      slot_cpl_ff_pfull;
    // logic                                                      slot_cpl_ff_overflow;
    // // logic                                                      slot_cpl_ff_rden;
    // // logic                              [SLOT_CPL_FF_WIDTH-1:0] slot_cpl_ff_dout;
    // // logic                                                      slot_cpl_ff_empty;
    // // logic                                                      slot_cpl_ff_pempty;
    // logic                                                      slot_cpl_ff_underflow;
    // logic                              [SLOT_CPL_FF_USEDW-1:0] slot_cpl_ff_usedw;
    // logic                              [1:0]                   slot_cpl_ff_err;
    virtio_desc_eng_core_desc_rd2rsp_t                       rd2rsp_loop;
    // FIRST
    logic                              [SLOT_ID_WIDTH-1:0]   first_slot;
    logic                              [QID_WIDTH-1:0]       first_qid;
    logic                                                    first_forced_shutdown;
    virtio_err_info_t                                        first_err_info;
    logic                              [15:0]                first_desc_cnt;
    logic                              [20:0]                first_data_len;
    logic                              [15:0]                first_id;

    virtio_desc_eng_core_desc_rd2rsp_t                       rd2rsp_loop_first;

    // FIRST
    logic                              [SLOT_ID_WIDTH-1:0]   resumer_slot;
    logic                              [QID_WIDTH-1:0]       resumer_qid;
    logic                                                    resumer_forced_shutdown;
    virtio_err_info_t                                        resumer_err_info;
    logic                              [15:0]                resumer_desc_cnt;
    logic                              [20:0]                resumer_data_len;
    logic                              [15:0]                resumer_id;

    virtio_desc_eng_core_desc_rd2rsp_t                       rd2rsp_loop_resumer;

    // RSP

    logic                              [SLOT_ID_WIDTH-1:0]   rsp_slot;
    logic                              [QID_WIDTH-1:0]       rsp_qid;
    logic                                                    rsp_forced_shutdown;
    virtio_err_info_t                                        rsp_err_info;
    logic                              [15:0]                rsp_desc_cnt;
    logic                              [20:0]                rsp_data_len;
    logic                              [15:0]                rsp_id;

    virtio_desc_eng_core_desc_rd2rsp_t                       rd2rsp_loop_rsp;


    logic                                                    flush_slot;
    logic                              [SLOT_ID_WIDTH-1:0]   flush_slot_cnt;
    logic                              [QID_WIDTH-1:0]       flush_resummer_cnt;

    always @(posedge clk) begin
        if (rst) begin
            flush_slot <= 1'b1;
        end else if (flush_slot_cnt == (SLOT_NUM - 1) && slot_cpl_ram_wren) begin
            flush_slot <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            flush_slot_cnt <= 'b0;
        end else if (slot_cpl_ram_wren) begin
            flush_slot_cnt <= flush_slot_cnt + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            flush_resummer <= 1'b1;
        end else if (flush_resummer_cnt == (QID_NUM - 1) && blk_desc_resumer_wr_vld) begin
            flush_resummer <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            flush_resummer_cnt <= 'b0;
        end else if (blk_desc_resumer_wr_vld) begin
            flush_resummer_cnt <= flush_resummer_cnt + 1;
        end
    end







    // logic                              [1:0]               rd2rsp_loop_first_submit = 2'b00;
    // logic                              [SLOT_ID_WIDTH-1:0] rd2rsp_loop_first_slot_id;
    // logic                              [QID_WIDTH-1:0]     rd2rsp_loop_first_qid;
    // logic                              [15:0]              rd2rsp_loop_first_desc_id;
    // logic                              [15:0]              rd2rsp_loop_first_data_len;
    // logic                              [15:0]              rd2rsp_loop_first_desc_cnt;
    // logic                                                  rd2rsp_loop_first_is_indirct;


    assign submit_vld       = first_submit_vld || rsp_submit_vld;
    assign submit_rdy       = core_cstat == DELAY && desc_dma_rd_req.sav;
    assign first_submit_rdy = submit_rdy && vld_flag;

    assign rsp_submit_rdy   = submit_rdy && !vld_flag;

    assign info_rd_rdy      = rsp_submit_rdy;
    assign rsp_submit_vld   = info_rd_vld;
    assign rsp_submit_dat   = info_rd_dat;

    always @(posedge clk) begin
        if (core_cstat == CTX_RD_REQ && submit_vld && desc_dma_rd_req.sav) begin
            vld_flag <= first_submit_vld;
        end
    end


    always @(posedge clk) begin
        if (rst) begin
            core_cstat <= INIT;
        end else begin
            core_cstat <= core_nstat;
        end
    end

    always @(*) begin
        core_nstat = core_cstat;
        case (core_cstat)
            INIT: begin
                if (!flush_slot) begin
                    core_nstat = CTX_RD_REQ;
                end
            end
            CTX_RD_REQ: begin
                if (submit_vld && desc_dma_rd_req.sav) begin
                    core_nstat = CTX_RD_RSP;
                end
            end

            CTX_RD_RSP: begin
                core_nstat = ERR_CHECK;
            end
            ERR_CHECK: begin
                core_nstat = ERR_INFO;
            end
            ERR_INFO: begin
                if (vld_flag) begin
                    if (submit_resummer) begin
                        core_nstat = RESUMER;
                    end else begin
                        core_nstat = FIRST;
                    end
                end else begin
                    core_nstat = RSP;
                end
            end
            FIRST: begin
                core_nstat = DELAY;
            end
            RESUMER: begin
                core_nstat = DELAY;
            end
            RSP: begin
                core_nstat = DELAY;
            end
            DELAY: begin
                core_nstat = CTX_RD_REQ;
            end
            default: core_nstat = CTX_RD_REQ;
        endcase
    end
    // CTX_RD_REQ
    assign blk_desc_global_info_rd_req_vld = submit_vld && desc_dma_rd_req.sav && core_cstat == CTX_RD_REQ;
    assign blk_desc_global_info_rd_req_qid = first_submit_vld ? first_submit_qid : rsp_submit_dat.vq.qid;

    assign blk_desc_local_info_rd_req_vld  = submit_vld && desc_dma_rd_req.sav && core_cstat == CTX_RD_REQ;
    assign blk_desc_local_info_rd_req_qid  = first_submit_vld ? first_submit_qid : rsp_submit_dat.vq.qid;

    always @(*) begin
        submit_rsp_addr = rsp_submit_dat.indirct_addr;
        submit_rsp_len  = rsp_submit_dat.indirct_desc_size;
        submit_rsp_last = rsp_submit_dat.flag_last;
        submit_idx      = first_submit_id;  //to free
        if (vld_flag) begin
            submit_resummer     = first_submit_resummer;
            submit_cycle_flag   = first_submit_cycle_flag;
            submit_id           = first_submit_id;  // resummer  useless
            submit_qid          = first_submit_qid;
            submit_slot_id      = first_submit_slot_id;
            submit_rsp_data_len = 'd0;
            submit_rsp_desc_cnt = 'd0;
            submit_rsp_indirct  = 'd0;
        end else begin
            submit_resummer     = 'd0;
            submit_cycle_flag   = rsp_submit_dat.cycle_flag;
            submit_id           = rsp_submit_dat.next;
            submit_qid          = rsp_submit_dat.vq.qid;
            submit_slot_id      = rsp_submit_dat.slot_id[SLOT_ID_WIDTH-1:0];
            submit_rsp_data_len = rsp_submit_dat.total_buf_length;
            submit_rsp_desc_cnt = rsp_submit_dat.vld_cnt;
            submit_rsp_indirct  = rsp_submit_dat.flag_indirct;
        end
    end

    // CTX_RD_RSP

    always @(posedge clk) begin
        if (blk_desc_global_info_rd_rsp_vld) begin
            global_info_bdf              <= blk_desc_global_info_rd_rsp_bdf;
            global_info_forced_shutdown  <= blk_desc_global_info_rd_rsp_forced_shutdown;
            global_info_desc_tbl_addr    <= blk_desc_global_info_rd_rsp_desc_tbl_addr;
            global_info_qdepth           <= blk_desc_global_info_rd_rsp_qdepth;
            global_info_qdepth_num       <= 'b1 << blk_desc_global_info_rd_rsp_qdepth;
            global_info_indirct_support  <= blk_desc_global_info_rd_rsp_indirct_support;
            global_info_segment_size_blk <= blk_desc_global_info_rd_rsp_segment_size_blk;
            global_info_desc_tbl_addr_id <= blk_desc_global_info_rd_rsp_desc_tbl_addr + (submit_id << 4);
        end
    end
    always @(posedge clk) begin
        if (blk_desc_local_info_rd_rsp_vld) begin
            local_info_desc_tbl_addr_blk <= blk_desc_local_info_rd_rsp_desc_tbl_addr_blk;
            local_info_desc_tbl_size_blk <= blk_desc_local_info_rd_rsp_desc_tbl_size_blk;
            local_info_desc_tbl_next_blk <= blk_desc_local_info_rd_rsp_desc_tbl_next_blk;
            local_info_desc_tbl_id_blk   <= blk_desc_local_info_rd_rsp_desc_tbl_id_blk;
            local_info_desc_cnt          <= blk_desc_local_info_rd_rsp_desc_cnt;
            local_info_desc_cnt_add      <= blk_desc_local_info_rd_rsp_desc_cnt + submit_rsp_desc_cnt;
            local_info_data_len          <= blk_desc_local_info_rd_rsp_data_len;
            local_info_data_len_add      <= blk_desc_local_info_rd_rsp_data_len;
            local_info_is_indirct        <= blk_desc_local_info_rd_rsp_is_indirct;
            if (vld_flag && submit_resummer) begin
                local_info_desc_tbl_addr_blk_id <= blk_desc_local_info_rd_rsp_desc_tbl_addr_blk + (blk_desc_local_info_rd_rsp_desc_tbl_next_blk << 4);
            end else begin
                local_info_desc_tbl_addr_blk_id <= blk_desc_local_info_rd_rsp_desc_tbl_addr_blk + (submit_id << 4);
            end
        end
    end

    always @(posedge clk) begin  // remain for length
        if (blk_desc_global_info_rd_rsp_vld) begin
            info_desc_bkt_remain <= DESC_PER_BUCKET_NUM - submit_rsp_desc_cnt;  // 16- 
            if (vld_flag) begin
                if (submit_resummer) begin
                    info_desc_buf_remain <= blk_desc_local_info_rd_rsp_desc_tbl_size_blk - blk_desc_local_info_rd_rsp_desc_tbl_next_blk;
                end else begin
                    info_desc_buf_remain <= {17'b1 << blk_desc_global_info_rd_rsp_qdepth} - submit_id;
                end
            end else begin
                if (submit_rsp_indirct) begin
                    info_desc_buf_remain <= submit_rsp_len - submit_id;
                end else begin
                    info_desc_buf_remain <= blk_desc_local_info_rd_rsp_desc_tbl_size_blk - submit_id;
                end
            end
        end
    end
    // ERR_CHECK 
    always @(posedge clk) begin  // h'h1
        desc_next_oversize_flag          <= 1'b0;
        desc_next_oversize_indirect_flag <= 1'b0;
        if (!vld_flag) begin
            if (submit_rsp_indirct || local_info_is_indirct) begin
                if (submit_id >= submit_rsp_len && !submit_rsp_last) begin
                    desc_next_oversize_indirect_flag <= 1'b1;
                end
            end else begin
                if (submit_id >= local_info_desc_tbl_size_blk && !submit_rsp_last) begin
                    desc_next_oversize_flag <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        desc_chain_len_oversize_flag <= 1'b0;
        if (local_info_desc_cnt_add == global_info_qdepth_num && !(local_info_is_indirct || submit_rsp_indirct) && !submit_rsp_last) begin
            desc_chain_len_oversize_flag <= 1'b1;
        end else if (local_info_desc_cnt_add >= virtio_blk_desc_engine_max_chain_len && (local_info_is_indirct || submit_rsp_indirct) && !submit_rsp_last) begin
            desc_chain_len_oversize_flag <= 1'b1;
        end
    end


    assign desc_buf_len_oversize = rsp_submit_dat.desc_buf_len_oversize;
    // assign desc_data_len_oversize_flag = 0;

    always @(posedge clk) begin
        desc_unsupport_indirct_flag <= 1'b0;
        if (submit_rsp_indirct && !global_info_indirct_support) begin
            desc_unsupport_indirct_flag <= 1'b1;
        end
    end

    assign desc_next_must_zero_flag = rsp_submit_dat.indirct_desc_next_must_be_zero;
    assign desc_indirct_nested_flag = rsp_submit_dat.indirct_nexted_desc;
    assign desc_data_len_zero_flag  = rsp_submit_dat.desc_zero_len;

    always @(posedge clk) begin
        desc_chain_len_one <= 'b0;
        if (submit_rsp_last && local_info_desc_cnt_add == 20'b1) begin
            desc_chain_len_one <= 'b1;
        end
    end
    assign desc_pcie_err = rsp_submit_dat.pcie_err;


    always @(posedge clk) begin
        if (core_cstat == ERR_INFO) begin
            if (vld_flag) begin
                err_code <= VIRTIO_ERR_CODE_NONE;
            end else begin
                err_code <= VIRTIO_ERR_CODE_NONE;
                if (desc_pcie_err) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR;
                end else if (desc_next_oversize_flag) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE;
                end else if (desc_next_oversize_indirect_flag) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE;
                end else if (desc_chain_len_oversize_flag) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE;
                    // end else if (desc_data_len_oversize_flag) begin
                    //     err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE;
                end else if (desc_unsupport_indirct_flag) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT;
                end else if (desc_next_must_zero_flag) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO;
                end else if (desc_indirct_nested_flag) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC;
                end else if (desc_data_len_zero_flag) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO;
                end else if (desc_chain_len_one) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE;
                end else if (desc_buf_len_oversize) begin
                    err_code <= VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE;
                end
            end
        end
    end




    // local_INFO_WR

    assign blk_desc_local_info_wr_qid = submit_qid;
    always @(posedge clk) begin
        blk_desc_local_info_wr_vld <= 'b0;
        if (core_cstat == FIRST) begin
            blk_desc_local_info_wr_vld               <= 'b1;
            blk_desc_local_info_wr_desc_tbl_addr_blk <= global_info_desc_tbl_addr;
            blk_desc_local_info_wr_desc_tbl_size_blk <= {'b1 << blk_desc_global_info_rd_rsp_qdepth};  // error
            blk_desc_local_info_wr_desc_tbl_id_blk   <= submit_idx;
            blk_desc_local_info_wr_desc_tbl_next_blk <= submit_id;
            blk_desc_local_info_wr_desc_cnt          <= 'd0;
            blk_desc_local_info_wr_data_len          <= 'd0;
            blk_desc_local_info_wr_is_indirct        <= 'd0;
        end else if (core_cstat == RESUMER) begin
            blk_desc_local_info_wr_vld               <= 'b1;
            blk_desc_local_info_wr_desc_tbl_addr_blk <= local_info_desc_tbl_addr_blk;
            blk_desc_local_info_wr_desc_tbl_size_blk <= local_info_desc_tbl_size_blk;
            blk_desc_local_info_wr_desc_tbl_id_blk   <= local_info_desc_tbl_id_blk;
            blk_desc_local_info_wr_desc_tbl_next_blk <= local_info_desc_tbl_next_blk;
            blk_desc_local_info_wr_desc_cnt          <= local_info_desc_cnt;
            blk_desc_local_info_wr_data_len          <= local_info_data_len;
            blk_desc_local_info_wr_is_indirct        <= local_info_is_indirct;
        end else if (core_cstat == RSP) begin
            blk_desc_local_info_wr_vld               <= 'b1;
            blk_desc_local_info_wr_desc_tbl_addr_blk <= submit_rsp_indirct ? submit_rsp_addr : local_info_desc_tbl_addr_blk;
            blk_desc_local_info_wr_desc_tbl_size_blk <= submit_rsp_indirct ? submit_rsp_len : local_info_desc_tbl_size_blk;
            blk_desc_local_info_wr_desc_tbl_id_blk   <= local_info_desc_tbl_id_blk;
            blk_desc_local_info_wr_desc_tbl_next_blk <= submit_id;
            blk_desc_local_info_wr_desc_cnt          <= submit_rsp_desc_cnt == 8'd16 ? local_info_desc_cnt_add : local_info_desc_cnt;
            blk_desc_local_info_wr_data_len          <= submit_rsp_data_len;
            blk_desc_local_info_wr_is_indirct        <= local_info_is_indirct || submit_rsp_indirct;
        end
    end

    // BLK_DESC_RESUMMER
    assign blk_desc_resumer_wr_qid = flush_resummer ? flush_resummer_cnt : submit_qid;

    always @(posedge clk) begin
        blk_desc_resumer_wr_vld <= 1'b0;
        blk_desc_resumer_wr_dat <= 1'b0;
        if (flush_resummer) begin
            blk_desc_resumer_wr_vld <= 1'b1;
            blk_desc_resumer_wr_dat <= 1'b0;
        end else if (core_cstat == FIRST) begin
            blk_desc_resumer_wr_vld <= 1'b1;
            blk_desc_resumer_wr_dat <= 1'b0;
        end else if (core_cstat == RESUMER) begin
            blk_desc_resumer_wr_vld <= 1'b1;
            blk_desc_resumer_wr_dat <= 1'b0;
        end else if (core_cstat == RSP) begin
            blk_desc_resumer_wr_vld <= 1'b1;
            blk_desc_resumer_wr_dat <= submit_rsp_desc_cnt == 8'd16 && !submit_rsp_last && !global_info_forced_shutdown && err_code == VIRTIO_ERR_CODE_NONE;
        end
    end





    // SLOT_CPL_FF_WR
    always @(posedge clk) begin
        slot_cpl_ram_wren <= 1'b0;
        if (flush_slot) begin
            slot_cpl_ram_wren  <= 1'b1;
            slot_cpl_ram_waddr <= flush_slot_cnt;
            slot_cpl_ram_wdata <= 'b0;
        end else if (core_cstat == FIRST) begin
            if (global_info_forced_shutdown) begin
                slot_cpl_ram_wren <= 1'b1;
            end
            slot_cpl_ram_waddr <= first_slot;
            slot_cpl_ram_wdata <= {!submit_cycle_flag, first_slot, first_qid, first_forced_shutdown, first_err_info, first_desc_cnt, first_data_len, first_id};
        end else if (core_cstat == RESUMER) begin
            if (global_info_forced_shutdown) begin
                slot_cpl_ram_wren <= 1'b1;
            end
            slot_cpl_ram_waddr <= resumer_slot;
            slot_cpl_ram_wdata <= {!submit_cycle_flag, resumer_slot, resumer_qid, resumer_forced_shutdown, resumer_err_info, resumer_desc_cnt, resumer_data_len, resumer_id};
        end else if (core_cstat == RSP) begin
            if (global_info_forced_shutdown || submit_rsp_last || submit_rsp_desc_cnt == 8'd16 || err_code != VIRTIO_ERR_CODE_NONE) begin
                slot_cpl_ram_wren <= 1'b1;
            end
            slot_cpl_ram_waddr <= rsp_slot;
            slot_cpl_ram_wdata <= {!submit_cycle_flag, rsp_slot, rsp_qid, rsp_forced_shutdown, rsp_err_info, rsp_desc_cnt, rsp_data_len, rsp_id};
        end

    end

    assign first_slot                = submit_slot_id;
    assign first_qid                 = submit_qid;
    assign first_forced_shutdown     = global_info_forced_shutdown;
    assign first_err_info.fatal      = 1'b0;
    assign first_err_info.err_code   = VIRTIO_ERR_CODE_NONE;
    assign first_desc_cnt            = submit_rsp_desc_cnt;
    assign first_data_len            = submit_rsp_data_len;
    assign first_id                  = submit_id;

    assign resumer_slot              = submit_slot_id;
    assign resumer_qid               = submit_qid;
    assign resumer_forced_shutdown   = global_info_forced_shutdown;
    assign resumer_err_info.fatal    = 1'b0;
    assign resumer_err_info.err_code = VIRTIO_ERR_CODE_NONE;
    assign resumer_desc_cnt          = submit_rsp_desc_cnt;
    assign resumer_data_len          = submit_rsp_data_len;
    assign resumer_id                = local_info_desc_tbl_id_blk;

    assign rsp_slot                  = submit_slot_id;
    assign rsp_qid                   = submit_qid;
    assign rsp_forced_shutdown       = global_info_forced_shutdown;
    assign rsp_err_info.fatal        = err_code != VIRTIO_ERR_CODE_NONE;  //error
    assign rsp_err_info.err_code     = err_code;  //error
    assign rsp_desc_cnt              = submit_rsp_desc_cnt;
    assign rsp_data_len              = submit_rsp_data_len;
    assign rsp_id                    = local_info_desc_tbl_id_blk;

    // ORDER_FF
    always @(posedge clk) begin
        order_wr_vld         <= 1'b0;
        order_wr_dat.max_len <= global_info_segment_size_blk;
        if (core_cstat == FIRST) begin
            if (!global_info_forced_shutdown) begin
                order_wr_vld <= 1'b1;
            end
            order_wr_dat.vq.typ                <= VIRTIO_BLK_TYPE;
            order_wr_dat.vq.qid                <= submit_qid;
            order_wr_dat.slot_id               <= submit_slot_id;
            order_wr_dat.desc_buf_local_offset <= submit_slot_id << 3;
        end else if (core_cstat == RESUMER) begin
            if (!(global_info_forced_shutdown)) begin
                order_wr_vld <= 1'b1;
            end
            order_wr_dat.vq.typ                <= VIRTIO_BLK_TYPE;
            order_wr_dat.vq.qid                <= submit_qid;
            order_wr_dat.slot_id               <= submit_slot_id;
            order_wr_dat.desc_buf_local_offset <= submit_slot_id << 3;
        end else if (core_cstat == RSP) begin
            if (!(global_info_forced_shutdown || submit_rsp_last || submit_rsp_desc_cnt == 'd16 || err_code != VIRTIO_ERR_CODE_NONE)) begin
                order_wr_vld <= 1'b1;
            end
            order_wr_dat.vq.typ                <= VIRTIO_BLK_TYPE;
            order_wr_dat.vq.qid                <= submit_qid;
            order_wr_dat.slot_id               <= submit_slot_id;
            order_wr_dat.desc_buf_local_offset <= (submit_slot_id << 3) + submit_rsp_desc_cnt[4:1];
        end
    end




    // DMA_RD_REQ
    assign desc_dma_rd_req.desc.dev_id      = 0;
    assign desc_dma_rd_req.desc.bdf         = global_info_bdf;
    assign desc_dma_rd_req.desc.vf_active   = 0;
    assign desc_dma_rd_req.desc.tc          = 0;
    assign desc_dma_rd_req.desc.attr        = 0;
    assign desc_dma_rd_req.desc.th          = 0;
    assign desc_dma_rd_req.desc.td          = 0;
    assign desc_dma_rd_req.desc.ep          = 0;
    assign desc_dma_rd_req.desc.at          = 0;
    assign desc_dma_rd_req.desc.ph          = 0;
    assign desc_dma_rd_req.desc.rd2rsp_loop = rd2rsp_loop;
    always @(posedge clk) begin
        desc_dma_rd_req.vld <= 1'b0;
        if (core_cstat == FIRST) begin
            if (!global_info_forced_shutdown) begin
                desc_dma_rd_req.vld <= 1'b1;
            end
            desc_dma_rd_req.sty              <= 'd0;  // submit_rsp_desc_cnt[$clog2(DATA_WIDTH/128)-1:0] << 4
            desc_dma_rd_req.desc.pcie_addr   <= global_info_desc_tbl_addr_id;
            desc_dma_rd_req.desc.pcie_length <= 1 << 4;
            rd2rsp_loop                      <= rd2rsp_loop_first;
        end else if (core_cstat == RESUMER) begin
            if (!(global_info_forced_shutdown)) begin
                desc_dma_rd_req.vld <= 1'b1;
            end
            desc_dma_rd_req.sty            <= 'd0;
            desc_dma_rd_req.desc.pcie_addr <= local_info_desc_tbl_addr_blk_id;
            if (local_info_is_indirct) begin
                desc_dma_rd_req.desc.pcie_length <= (info_desc_bkt_remain > info_desc_buf_remain) ? (info_desc_buf_remain << 4) : (info_desc_bkt_remain << 4);
            end else begin
                desc_dma_rd_req.desc.pcie_length <= 1 << 4;
            end
            rd2rsp_loop <= rd2rsp_loop_resumer;
        end else if (core_cstat == RSP) begin
            if (!(global_info_forced_shutdown || submit_rsp_last || submit_rsp_desc_cnt == 'd16 || err_code != VIRTIO_ERR_CODE_NONE)) begin
                desc_dma_rd_req.vld <= 1'b1;
            end
            desc_dma_rd_req.sty <= submit_rsp_desc_cnt[$clog2(DATA_WIDTH/128)-1:0] << 4;
            if (submit_rsp_indirct) begin
                desc_dma_rd_req.desc.pcie_addr   <= submit_rsp_addr;
                desc_dma_rd_req.desc.pcie_length <= (info_desc_bkt_remain > info_desc_buf_remain) ? (info_desc_buf_remain << 4) : (info_desc_bkt_remain << 4);
            end else begin
                desc_dma_rd_req.desc.pcie_addr   <= local_info_desc_tbl_addr_blk_id;
                desc_dma_rd_req.desc.pcie_length <= 1 << 4;
            end
            rd2rsp_loop <= rd2rsp_loop_rsp;


        end
    end

    assign rd2rsp_loop_first.vq.typ                  = VIRTIO_BLK_TYPE;
    assign rd2rsp_loop_first.vq.qid                  = submit_qid;
    assign rd2rsp_loop_first.idx                     = submit_id;
    assign rd2rsp_loop_first.cycle_flag              = submit_cycle_flag;
    assign rd2rsp_loop_first.slot_id                 = submit_slot_id;
    assign rd2rsp_loop_first.desc_buf_local_offset   = submit_slot_id << 3 + submit_rsp_desc_cnt[3:1];
    assign rd2rsp_loop_first.valid_desc_cnt          = submit_rsp_desc_cnt;
    assign rd2rsp_loop_first.total_buf_length        = submit_rsp_data_len;

    assign rd2rsp_loop_first.indirct_processing      = 0;
    assign rd2rsp_loop_first.qdepth                  = global_info_qdepth;
    assign rd2rsp_loop_first.indirct_support         = global_info_indirct_support;
    assign rd2rsp_loop_first.indirct_desc_size       = local_info_desc_tbl_size_blk;
    assign rd2rsp_loop_first.dirct_desc_bitmap       = 'b0;


    assign rd2rsp_loop_resumer.vq.typ                = VIRTIO_BLK_TYPE;
    assign rd2rsp_loop_resumer.vq.qid                = submit_qid;
    assign rd2rsp_loop_resumer.idx                   = local_info_desc_tbl_next_blk;
    assign rd2rsp_loop_resumer.cycle_flag            = submit_cycle_flag;
    assign rd2rsp_loop_resumer.slot_id               = submit_slot_id;
    assign rd2rsp_loop_resumer.desc_buf_local_offset = (submit_slot_id << 3) + submit_rsp_desc_cnt[3:1];
    assign rd2rsp_loop_resumer.valid_desc_cnt        = submit_rsp_desc_cnt;
    assign rd2rsp_loop_resumer.total_buf_length      = submit_rsp_data_len;

    assign rd2rsp_loop_resumer.indirct_processing    = local_info_is_indirct;
    assign rd2rsp_loop_resumer.qdepth                = global_info_qdepth;
    assign rd2rsp_loop_resumer.indirct_support       = global_info_indirct_support;
    assign rd2rsp_loop_resumer.indirct_desc_size     = local_info_desc_tbl_size_blk;
    assign rd2rsp_loop_resumer.dirct_desc_bitmap     = 'b0;

    assign rd2rsp_loop_rsp.vq.typ                    = VIRTIO_BLK_TYPE;
    assign rd2rsp_loop_rsp.vq.qid                    = submit_qid;
    assign rd2rsp_loop_rsp.idx                       = submit_id;
    assign rd2rsp_loop_rsp.cycle_flag                = submit_cycle_flag;
    assign rd2rsp_loop_rsp.slot_id                   = submit_slot_id;
    assign rd2rsp_loop_rsp.desc_buf_local_offset     = (submit_slot_id << 3) + submit_rsp_desc_cnt[3:1];
    assign rd2rsp_loop_rsp.valid_desc_cnt            = submit_rsp_desc_cnt;
    assign rd2rsp_loop_rsp.total_buf_length          = submit_rsp_data_len;

    assign rd2rsp_loop_rsp.indirct_processing        = local_info_is_indirct || submit_rsp_indirct;
    assign rd2rsp_loop_rsp.qdepth                    = global_info_qdepth;
    assign rd2rsp_loop_rsp.indirct_support           = global_info_indirct_support;
    assign rd2rsp_loop_rsp.indirct_desc_size         = submit_rsp_indirct ? submit_rsp_len : local_info_desc_tbl_size_blk;
    assign rd2rsp_loop_rsp.dirct_desc_bitmap         = 'b0;



    // RSP



    sync_simple_dual_port_ram #(
        .DATAA_WIDTH(SLOT_CPL_FF_WIDTH + 1),
        .ADDRA_WIDTH(SLOT_ID_WIDTH),
        .DATAB_WIDTH(SLOT_CPL_FF_WIDTH + 1),
        .ADDRB_WIDTH(SLOT_ID_WIDTH),
        .WRITE_MODE ("WRITE_FIRST"),
        .RAM_MODE   ("dist"),                 // blk dist
        .INIT       (0),
        .CHECK_ON   (1),
        .CHECK_MODE ("parity")
    ) u_slot_cpl_ram (
        .clk           (clk),
        .rst           (rst),
        //
        .addra         (slot_cpl_ram_waddr),
        .dina          (slot_cpl_ram_wdata),
        .wea           (slot_cpl_ram_wren),
        //
        .addrb         (slot_cpl_ram_raddr),
        .doutb         (slot_cpl_ram_rdata),
        //
        .parity_ecc_err(slot_cpl_ram_err)
    );




    // yucca_sync_fifo #(
    //     .DATA_WIDTH(SLOT_CPL_FF_WIDTH),
    //     .FIFO_DEPTH(SLOT_CPL_FF_DEPTH),
    //     .CHECK_ON  (1),
    //     .CHECK_MODE("parity"),
    //     // .DEPTH_PFULL(),
    //     .RAM_MODE  ("dist"),
    //     .FIFO_MODE ("fwft")
    // ) u_slot_cpl_ff (
    //     .clk           (clk),
    //     .rst           (rst),
    //     .wren          (slot_cpl_ff_wren),
    //     .din           (slot_cpl_ff_din),
    //     .full          (slot_cpl_ff_full),
    //     .pfull         (slot_cpl_ff_pfull),
    //     .overflow      (slot_cpl_ff_overflow),
    //     .rden          (slot_cpl_ff_rden),
    //     .dout          (slot_cpl_ff_dout),
    //     .empty         (slot_cpl_ff_empty),
    //     .pempty        (),
    //     .underflow     (slot_cpl_ff_underflow),
    //     .usedw         (slot_cpl_ff_usedw),
    //     .parity_ecc_err(slot_cpl_ff_err)
    // );
    // assign state = {core_cstat};
    // assign err   = {2'b0, slot_cpl_ram_err};

    logic blk_desc_global_info_rd_req_vld_d;
    logic blk_desc_global_info_rd_req_err;
    logic blk_desc_local_info_rd_req_vld_d;
    logic blk_desc_local_info_rd_req_err;

    always @(posedge clk) begin
        blk_desc_global_info_rd_req_vld_d <= blk_desc_global_info_rd_req_vld;
        blk_desc_local_info_rd_req_vld_d  <= blk_desc_local_info_rd_req_vld;
    end
    assign blk_desc_global_info_rd_req_err = blk_desc_global_info_rd_req_vld_d ^ blk_desc_global_info_rd_rsp_vld;
    assign blk_desc_local_info_rd_req_err  = blk_desc_local_info_rd_req_vld_d ^ blk_desc_local_info_rd_rsp_vld;

    always @(posedge clk) begin
        state.info_rd_vld         <= info_rd_vld;
        state.info_rd_rdy         <= info_rd_rdy;
        state.desc_dma_rd_req_vld <= desc_dma_rd_req.vld;
        state.desc_dma_rd_req_sav <= desc_dma_rd_req.sav;
        state.core_cstat          <= core_cstat;
    end

    always @(posedge clk) begin
        err.slot_cpl_ram_err <= slot_cpl_ram_err;
    end


    genvar err_idx;
    generate
        for (err_idx = 0; err_idx < $bits(err); err_idx++) begin : db_err_i
            assert property (@(posedge clk) disable iff (rst) (~(err[err_idx] === 1'b1)))
            else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, err[err_idx], err_idx));
        end
    endgenerate

endmodule : virtio_blk_desc_engine_core
