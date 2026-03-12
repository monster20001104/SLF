/******************************************************************************
 *              : virtio_nettx_rd_data_ctrl.sv
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
  `include "tlp_adap_dma_if.svh"
module virtio_nettx_rd_data_ctrl 
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
    input                           clk,
    input                           rst,
    // Descriptor Engine
    output logic                    nettx_desc_rsp_rdy, // 表示cmdfifo有空位
    input                           nettx_desc_rsp_vld,
    input                           nettx_desc_rsp_sop,
    input                           nettx_desc_rsp_eop,
    input  virtio_desc_eng_desc_rsp_sbd_t  nettx_desc_rsp_sbd,  // dev_id在这里
    input  virtq_desc_t             nettx_desc_rsp_data, // 标准的描述符格式 

    input                           qos_update_rdy,
    output  logic                   qos_update_vld,
    output  logic[VIRTIO_Q_WIDTH+1:0]    qos_update_uid,
    output  logic[19:0]             qos_update_len,
    output  logic[9:0]              qos_update_pkt_num,


    tlp_adap_dma_rd_req_if.src      dma_rd_req,

    input                           dma_rd_rsp_val,
    input                           dma_rd_rsp_eop,
    input                           dma_rd_rsp_sop,
    input  [DATA_EMPTY-1:0]         dma_rd_rsp_sty,
    input  desc_t                   dma_rd_rsp_desc,

    output  logic                   order_fifo_vld,
    output  virtio_nettx_order_t    order_fifo_data,
    input                           order_fifo_sav,

    input   logic                   data_fifo_rd,
    input   logic                   ctrl_fifo_rd,

    output  logic                   rd_data_ctx_info_rd_req_vld,
    output  virtio_vq_t             rd_data_ctx_info_rd_req_qid,

    input                           rd_data_ctx_info_rd_rsp_vld,
    input   [15:0]                  rd_data_ctx_info_rd_rsp_bdf,
    input                           rd_data_ctx_info_rd_rsp_forced_shutdown,    // 驱动正在reset设备该位为1
    input                           rd_data_ctx_info_rd_rsp_qos_enable,
    input   [VIRTIO_Q_WIDTH+1:0]    rd_data_ctx_info_rd_rsp_qos_unit,
    input                           rd_data_ctx_info_rd_rsp_tso_en,
    input                           rd_data_ctx_info_rd_rsp_csum_en,
    input   [7:0]                   rd_data_ctx_info_rd_rsp_gen,                // 一致性检查，确保在读取配置期间，主机端没有修改设备状态，保证读到的元数据是成套且同步的

    input                           dfx_vld,
    input   [31:0]                  dfx_data,

    output  logic[63:0]             rd_issued_cnt,

    output  logic[63:0]             dfx_status,
    output  logic[63:0]             dfx_err


);
    // 负责从描述符引擎接收原始信息
    enum logic [7:0]  { 
        DESC_IDLE      = 8'b0000_0001,
        JUDGE          = 8'b0000_0010,
        RD_DESC        = 8'b0000_0100,      // 读描述符数据
        WR_CMD         = 8'b0000_1000,      // 
        RD_DESC_DROP   = 8'b0001_0000,
        WR_CMD_DROP    = 8'b0010_0000
    } proc_desc_cstate, proc_desc_nstate,proc_desc_cstate_1d;
    // 负责执行真正的 PCIe DMA 数据搬运
    enum logic [8:0]  { 
        RD_IDLE        = 9'b0_0000_0001,    // 空闲侦听状态
        RD_CMD_FIFO    = 9'b0_0000_0010,    // 指令提取与路径分支
        CUT_PACKET     = 9'b0_0000_0100,    // 切片计算 长度超过4KB就会执行
        RD_DATA        = 9'b0_0000_1000,    // 资源预检查
        NO_RD          = 9'b0_0001_0000,    // 静默清理状态
        FINISH         = 9'b0_0010_0000,    // 检查当前描述符或描述符链的处理进度
        RD_DROP        = 9'b0_0100_0000,    // 异常强制清理
        QOS_UPDATE     = 9'b0_1000_0000,    // 带宽实报实销结算
        TX_DMA_RD      = 9'b1_0000_0000     // DMA 发起与 Context 二次确认
    } rd_data_cstate, rd_data_nstate,rd_data_cstate_1d;

    logic [15:0]            rd_data_ctx_info_rd_rsp_bdf_1d;
    logic                   rd_data_ctx_info_rd_rsp_forced_shutdown_1d;
    logic                   rd_data_ctx_info_rd_rsp_qos_enable_1d;
    logic [VIRTIO_Q_WIDTH+1:0]   rd_data_ctx_info_rd_rsp_qos_unit_1d;
    logic                   rd_data_ctx_info_rd_rsp_tso_en_1d;
    logic                   rd_data_ctx_info_rd_rsp_csum_en_1d;
    logic  [7:0]            rd_data_ctx_info_rd_rsp_gen_1d;

    virtio_desc_eng_desc_rsp_sbd_t  nettx_desc_rsp_sbd_1d;
    virtq_desc_t            nettx_desc_rsp_data_1d;
    logic                   nettx_desc_rsp_sop_1d;
    logic                   nettx_desc_rsp_eop_1d;
    
    logic                   wren_cmd_fifo,rden_cmd_fifo;
    virtio_nettx_cmd_t      din_cmd_fifo,dout_cmd_fifo,dout_cmd_fifo_1d,dout_cmd_fifo_qos,dout_cmd_fifo_qos_reg;
    logic                   cmd_fifo_empty,cmd_fifo_full,cmd_fifo_overflow,cmd_fifo_pfull,cmd_fifo_underflow;
    logic [1:0]             cmd_fifo_err;

    logic [19:0]            rd_data_len_padding;
    logic [19:0]            inflight_data_space,inflight_ctrl_space;

    logic [8:0]             valid_desc_cnt;
    logic [8:0]             cnt_chain;
    logic [8:0]             cnt_desc;

    logic [19:0]            desc_total_len,rd_tx_len,rest_len,rd_data_len,rd_data_len_total,rd_chain_data_len_total;
    logic [63:0]            rd_data_addr,rd_desc_addr;

    logic                   rd_data_vld,rd_data_vld_1d;
    logic[DATA_EMPTY-1:0]   rd_data_sty;
    logic                   qos_update_vld_pre,qos_finish;

    logic                   dma_rd_rsp_val_1d;
    logic                   dma_rd_rsp_eop_1d;
    logic                   dma_rd_rsp_sop_1d;
    logic  [DATA_EMPTY-1:0] dma_rd_rsp_sty_1d;
    desc_t                  dma_rd_rsp_desc_1d;

    logic [31:0]            inflight_data_parameter;

    // inflight_data_parameter发出DMA请求但数据还没返回FIFO的最大数据量
    always @(posedge clk)begin
        if(rst) begin
            inflight_data_parameter <= DATA_FIFO_DEPTH-129;     // 4KB空间
        end
        else if(dfx_vld) begin
            inflight_data_parameter <= dfx_data;
        end
    end
    // rd_data_ctrl
    always @(posedge clk)begin
        if(rst)begin
            rd_data_ctx_info_rd_rsp_qos_unit_1d <= 0;
            rd_data_ctx_info_rd_rsp_qos_enable_1d <= 0;
            rd_data_ctx_info_rd_rsp_forced_shutdown_1d <= 0;
            rd_data_ctx_info_rd_rsp_bdf_1d <= 0;
            rd_data_ctx_info_rd_rsp_tso_en_1d <= 0;
            rd_data_ctx_info_rd_rsp_csum_en_1d <= 0;
            rd_data_ctx_info_rd_rsp_gen_1d <= 0;
        end
        else if(rd_data_ctx_info_rd_rsp_vld)begin
            rd_data_ctx_info_rd_rsp_qos_unit_1d <= rd_data_ctx_info_rd_rsp_qos_unit;
            rd_data_ctx_info_rd_rsp_qos_enable_1d <= rd_data_ctx_info_rd_rsp_qos_enable;
            rd_data_ctx_info_rd_rsp_forced_shutdown_1d <= rd_data_ctx_info_rd_rsp_forced_shutdown;
            rd_data_ctx_info_rd_rsp_bdf_1d <= rd_data_ctx_info_rd_rsp_bdf;
            rd_data_ctx_info_rd_rsp_tso_en_1d <= rd_data_ctx_info_rd_rsp_tso_en;
            rd_data_ctx_info_rd_rsp_csum_en_1d <= rd_data_ctx_info_rd_rsp_csum_en;
            rd_data_ctx_info_rd_rsp_gen_1d <= rd_data_ctx_info_rd_rsp_gen;
        end
    end


    always @(posedge clk)begin
        if(nettx_desc_rsp_rdy && nettx_desc_rsp_vld)begin
            nettx_desc_rsp_sbd_1d <= nettx_desc_rsp_sbd;
            nettx_desc_rsp_data_1d <= nettx_desc_rsp_data;
            nettx_desc_rsp_sop_1d <= nettx_desc_rsp_sop;
            nettx_desc_rsp_eop_1d <= nettx_desc_rsp_eop;
        end
    end

    //assign rd_data_ctx_info_rd_req_vld = rd_data_cstate == RD_IDLE && cmd_fifo_empty == 0 && dout_cmd_fifo.sop == 1 && dout_cmd_fifo.drop == 0;
    // 确保发起读DMA前 ctx模块拿到的是最新的BDF
    // 防止一直卡在该状态，从而对ctx发起几次重复请求
    assign rd_data_ctx_info_rd_req_vld = rd_data_cstate == TX_DMA_RD && rd_data_cstate_1d != TX_DMA_RD;
    assign rd_data_ctx_info_rd_req_qid = {VIRTIO_NET_TX_TYPE,dout_cmd_fifo.qid};
    //告诉此模块 有多少个有效的描述符
    always @(posedge clk)begin
        if(rst)begin
            valid_desc_cnt <= 0;
        end
        else if(nettx_desc_rsp_vld && nettx_desc_rsp_sop && nettx_desc_rsp_rdy)begin
            valid_desc_cnt <= nettx_desc_rsp_sbd.valid_desc_cnt;
        end
    end

    always @(posedge clk)begin
        if(rst) begin
            proc_desc_cstate <= DESC_IDLE;
        end
        else begin
            proc_desc_cstate <= proc_desc_nstate;
        end
    end

    always @(*)begin
        proc_desc_nstate = proc_desc_cstate;
        case(proc_desc_cstate)
        DESC_IDLE:
            begin
                if(nettx_desc_rsp_vld)
                    proc_desc_nstate = JUDGE;
            end
        JUDGE:
            begin //  高位表示程度 低位表示错误类型
                if(nettx_desc_rsp_sbd.err_info >0 || nettx_desc_rsp_sbd.forced_shutdown == 1)
                    proc_desc_nstate = RD_DESC_DROP ;
                else  
                    proc_desc_nstate = RD_DESC;
            end
        RD_DESC:
            begin
                if(nettx_desc_rsp_vld)
                    proc_desc_nstate = WR_CMD;
            end
        WR_CMD: 
            begin
                if(cmd_fifo_pfull == 0)begin
                    if(cnt_desc < valid_desc_cnt )
                        proc_desc_nstate = RD_DESC;
                    else if(cnt_desc == valid_desc_cnt )
                        proc_desc_nstate = DESC_IDLE;
                end
            end
        RD_DESC_DROP: // 当任务被判定为无效时，硬件不能直接罢工，必须把残余信号处理干净
            begin
                if(nettx_desc_rsp_vld && nettx_desc_rsp_eop)
                    proc_desc_nstate = WR_CMD_DROP;
            end      
        WR_CMD_DROP:
            begin
                if(cmd_fifo_pfull == 0)
                    proc_desc_nstate = DESC_IDLE;
            end
        default: proc_desc_nstate = proc_desc_cstate;
        endcase
    end

    always @(posedge clk)begin
        if(rst)begin
            cnt_desc <= 0;
        end
        else if (proc_desc_cstate == DESC_IDLE)begin
            cnt_desc <= 0;
        end
        else if(proc_desc_cstate == RD_DESC && nettx_desc_rsp_vld)begin
            cnt_desc <= cnt_desc + 1;
        end
    end
    // 统计当前传输任务中包含多少个完整的包
    always @(posedge clk)begin
        if(rst)begin
            cnt_chain <= 0;
        end
        else if (proc_desc_cstate == DESC_IDLE)begin
            cnt_chain <= 0;
        end
        else if(proc_desc_cstate == RD_DESC && nettx_desc_rsp_data.flags.next == 0 && nettx_desc_rsp_vld)begin
            cnt_chain <= cnt_chain + 1;
        end
    end

    assign nettx_desc_rsp_rdy = ((proc_desc_cstate == RD_DESC) || (proc_desc_cstate == RD_DESC_DROP)) && nettx_desc_rsp_vld;


    always @(posedge clk)begin
        if(rst)begin
            rd_data_cstate <= RD_IDLE;
        end
        else begin
            rd_data_cstate <= rd_data_nstate;
        end
    end

    always @(posedge clk)begin
        rd_data_cstate_1d <= rd_data_cstate;
    end

    always @(*)begin
        rd_data_nstate = rd_data_cstate;
        case(rd_data_cstate)
        RD_IDLE:
            begin
                if(cmd_fifo_empty == 0)
                    rd_data_nstate = RD_CMD_FIFO;
            end
        RD_CMD_FIFO:
            begin
                if(dout_cmd_fifo.drop == 1)
                    rd_data_nstate = NO_RD;
                else
                    rd_data_nstate = CUT_PACKET;
            end
        NO_RD:
            begin
                if(order_fifo_sav == 1)
                    rd_data_nstate = RD_IDLE;
            end
        CUT_PACKET:
            begin
                rd_data_nstate = RD_DATA;
            end
        RD_DATA:
            begin
                if(dma_rd_req.sav == 1 && order_fifo_sav == 1 && (inflight_ctrl_space < CTRL_FIFO_DEPTH-8 && inflight_data_space < inflight_data_parameter))begin
                    rd_data_nstate = TX_DMA_RD;  
                end          
            end
        TX_DMA_RD:
            begin
                if(rd_data_ctx_info_rd_rsp_vld)begin
                    if(rd_data_ctx_info_rd_rsp_forced_shutdown == 0)
                        rd_data_nstate = FINISH;
                    else
                        rd_data_nstate = RD_DROP;
                end
            end
        RD_DROP:
            begin
                if(rden_cmd_fifo && dout_cmd_fifo.eop && cmd_fifo_empty == 0)
                    rd_data_nstate = RD_IDLE;
            end
        FINISH:
            begin
                if(rd_data_len_total < desc_total_len)
                    rd_data_nstate = CUT_PACKET;
                else if(dout_cmd_fifo.eop == 0 )
                    rd_data_nstate = RD_IDLE;
                else begin
                    if(rd_data_ctx_info_rd_rsp_qos_enable_1d == 0)
                        rd_data_nstate = RD_IDLE;
                    else if(rd_data_ctx_info_rd_rsp_qos_enable_1d == 1 && qos_update_vld && qos_update_rdy)
                        rd_data_nstate = RD_IDLE;
                    else
                        rd_data_nstate = QOS_UPDATE;
                    end
                    
            end    
        QOS_UPDATE:
            begin
                if(qos_finish == 1)
                    rd_data_nstate = RD_IDLE;
            end 
        default: rd_data_nstate = rd_data_cstate;
        endcase
    end


    always @(posedge clk)begin
        if(rst)begin
            din_cmd_fifo.sop <= 1;
        end
        else if(wren_cmd_fifo && din_cmd_fifo.eop)begin
            din_cmd_fifo.sop <= 1; 
        end   
        else if(wren_cmd_fifo)begin    
            din_cmd_fifo.sop <= 0;
        end
    end

    assign wren_cmd_fifo = (proc_desc_cstate == WR_CMD && cmd_fifo_pfull == 0) || (proc_desc_cstate == WR_CMD_DROP && cmd_fifo_pfull == 0);
    assign din_cmd_fifo.desc = nettx_desc_rsp_data_1d;
    //assign din_cmd_fifo.sop = proc_desc_cstate == WR_CMD_DROP ? 1 : nettx_desc_rsp_sop_1d;
    assign din_cmd_fifo.eop = proc_desc_cstate == WR_CMD_DROP ? 1 : nettx_desc_rsp_eop_1d;
    assign din_cmd_fifo.drop = proc_desc_cstate == WR_CMD_DROP;
    assign din_cmd_fifo.ring_id = nettx_desc_rsp_sbd_1d.ring_id;
    assign din_cmd_fifo.forced_shutdown = nettx_desc_rsp_sbd_1d.forced_shutdown;
    assign din_cmd_fifo.avail_idx = nettx_desc_rsp_sbd_1d.avail_idx;
    assign din_cmd_fifo.dev_id = nettx_desc_rsp_sbd_1d.dev_id;
    assign din_cmd_fifo.qid = nettx_desc_rsp_sbd_1d.vq.qid;
    assign din_cmd_fifo.chain_tail = din_cmd_fifo.eop;
    assign din_cmd_fifo.err_info = nettx_desc_rsp_sbd_1d.err_info;
    assign din_cmd_fifo.total_buf_len = nettx_desc_rsp_sbd_1d.total_buf_length;
    assign din_cmd_fifo.cnt_chain = cnt_chain;

    assign order_fifo_data.qid = dout_cmd_fifo_1d.qid;
    assign order_fifo_data.enable_rd = rd_data_cstate == FINISH;
    assign order_fifo_data.forced_shutdown = dout_cmd_fifo_1d.forced_shutdown || (rd_data_cstate == RD_DROP && rd_data_ctx_info_rd_rsp_forced_shutdown_1d);
    assign order_fifo_data.ring_id = dout_cmd_fifo_1d.ring_id;
    assign order_fifo_data.avail_idx = dout_cmd_fifo_1d.avail_idx;
    assign order_fifo_data.err_info = dout_cmd_fifo_1d.err_info;
    assign order_fifo_data.chain_tail = (rd_data_cstate == FINISH) ? (dout_cmd_fifo_1d.chain_tail && rd_data_len_total >= desc_total_len) : 1;
    assign order_fifo_data.chain_stop = rd_data_cstate == RD_DROP && (dout_cmd_fifo_1d.sop == 0  || (dout_cmd_fifo_1d.sop == 1 && rd_data_len_total > 0));
    assign order_fifo_data.tso_en = rd_data_ctx_info_rd_rsp_tso_en_1d;
    assign order_fifo_data.csum_en = rd_data_ctx_info_rd_rsp_csum_en_1d;
    assign order_fifo_data.gen = rd_data_ctx_info_rd_rsp_gen_1d;
    assign order_fifo_data.total_buf_len = dout_cmd_fifo.total_buf_len;
    assign order_fifo_vld = (rd_data_cstate == NO_RD && order_fifo_sav == 1) 
                         || (rd_data_cstate == FINISH)
                         || (rd_data_cstate == RD_DROP && rd_data_cstate_1d != RD_DROP );

    always @(posedge clk)begin
        dout_cmd_fifo_1d <= dout_cmd_fifo;
    end

    assign desc_total_len = dout_cmd_fifo_1d.desc.len; // 当前描述符的总长度
    assign rd_desc_addr = dout_cmd_fifo_1d.desc.addr;
    assign rest_len = desc_total_len - rd_tx_len;      // 当前描述符还剩下多少没处理
    // 当前描述符已经计算好准备发的长度
    always @(posedge clk)begin
        if(rst)begin
            rd_tx_len <= 0;
        end
        else if ((rd_data_cstate == FINISH && rd_data_len_total >= desc_total_len) || rd_data_cstate == RD_DROP)begin
            rd_tx_len <= 0;
        end
        else if(rd_data_cstate == CUT_PACKET )begin
            if(rest_len[19:12] > 0) begin
                rd_tx_len[19:12] <= rd_tx_len[19:12] + 1;
            end
            else  begin
                rd_tx_len[11:0] <= rest_len;
            end
        end
    end

    always @(posedge clk)begin
        if(rst)begin
            rd_data_addr <= 0;
        end    
        else if(rd_data_cstate == CUT_PACKET)begin
            rd_data_addr <= rd_desc_addr + rd_tx_len;
        end
    end

    always @(posedge clk)begin
        if(rst) begin
            rd_data_len <= 0;
        end
        else if(rd_data_cstate == CUT_PACKET )begin
            if(rest_len[19:12] > 0) begin
                rd_data_len <= 4096;
            end
            else  begin
                rd_data_len <= rest_len;
            end
        end
    end
    // 当前描述符中已经握手发出的长度
    always @(posedge clk)begin
        if(rst)begin
            rd_data_len_total <= 0;
        end
        else if(rd_data_cstate == RD_IDLE)begin
            rd_data_len_total <= 0;
        end
        else if(rd_data_vld)begin
            rd_data_len_total <= rd_data_len_total + rd_data_len;
        end
    end
    // 当前整条描述符链（Packet）已发出的总长度
    always @(posedge clk)begin
        if(rst)begin
            rd_chain_data_len_total <= 0;
        end
        else if(rd_data_cstate == RD_DROP)begin
            rd_chain_data_len_total <= 0;
        end
        else if(rden_cmd_fifo && dout_cmd_fifo_1d.chain_tail == 1)begin
            rd_chain_data_len_total <= 0;
        end
        else if(rd_data_vld)begin
            rd_chain_data_len_total <= rd_chain_data_len_total + rd_data_len;
        end
    end

    always @(posedge clk)begin
        dma_rd_rsp_val_1d <=  dma_rd_rsp_val;
        dma_rd_rsp_eop_1d <=  dma_rd_rsp_eop;
        dma_rd_rsp_sop_1d <=  dma_rd_rsp_sop;
        dma_rd_rsp_sty_1d <= dma_rd_rsp_sty;
        dma_rd_rsp_desc_1d <= dma_rd_rsp_desc;
    end


    assign rd_data_sty = rd_chain_data_len_total[DATA_EMPTY-1:0];
    always @(posedge clk) begin
        if(rst)begin
            rd_data_vld_1d <= 1'b0;
        end else begin
            rd_data_vld_1d <= rd_data_vld;
            rd_data_len_padding <= rd_data_sty + rd_data_len;
        end
    end
    // 记录已经在路上即将占用仓库的数据量  单位是行数
    // data_fifo_rd表示rsp_data_fifo的读使能信号表示读出32字节数据 也就是一行
    always @(posedge clk)begin
        if(rst)begin
            inflight_data_space <= 0;
        end else if(rd_data_vld_1d && data_fifo_rd)begin
            inflight_data_space <= inflight_data_space + rd_data_len_padding[19:5] + |rd_data_len_padding[4:0] - 1'b1;
        end else if(rd_data_vld_1d && !data_fifo_rd)begin
            inflight_data_space <= inflight_data_space + rd_data_len_padding[19:5] + |rd_data_len_padding[4:0];
        end else if(!rd_data_vld_1d &&  data_fifo_rd)begin
            inflight_data_space <= inflight_data_space - 1'b1;
        end
    end
    //  放进order FIFO里的
    always @(posedge clk)begin
        if(rst)begin
            inflight_ctrl_space <= 0;
        end
        else if(rd_data_vld_1d && !ctrl_fifo_rd)begin
            inflight_ctrl_space <= inflight_ctrl_space + 1;
        end
        else if(!rd_data_vld_1d && ctrl_fifo_rd)begin
            inflight_ctrl_space <= inflight_ctrl_space - 1;
        end
    end

    assign rd_data_vld = rd_data_ctx_info_rd_rsp_vld && rd_data_ctx_info_rd_rsp_forced_shutdown == 0;
    assign dma_rd_req.vld = rd_data_vld;
    assign dma_rd_req.sty = rd_data_sty;
    assign dma_rd_req.desc.bdf = rd_data_ctx_info_rd_rsp_bdf;
    assign dma_rd_req.desc.vf_active = 0;
    assign dma_rd_req.desc.tc = 0;
    assign dma_rd_req.desc.attr = 0;
    assign dma_rd_req.desc.th = 0;
    assign dma_rd_req.desc.td = 0;
    assign dma_rd_req.desc.ep = 0;
    assign dma_rd_req.desc.at = 0;
    assign dma_rd_req.desc.ph = 0;
    assign dma_rd_req.desc.pcie_addr = rd_data_addr;
    assign dma_rd_req.desc.pcie_length = rd_data_len;
    assign dma_rd_req.desc.rd2rsp_loop = {dout_cmd_fifo_1d.qid,dout_cmd_fifo_1d.ring_id};
    assign dma_rd_req.desc.dev_id = dout_cmd_fifo_1d.dev_id;

    assign rden_cmd_fifo = (rd_data_cstate == FINISH && rd_data_len_total >= desc_total_len) || (rd_data_cstate == RD_DROP && cmd_fifo_empty == 0 ) || (rd_data_cstate == NO_RD && order_fifo_sav == 1);
    
    always @(posedge clk)begin
        if(rst)
            dout_cmd_fifo_qos <= 0;
        else if(rd_data_cstate == FINISH)
            dout_cmd_fifo_qos <= dout_cmd_fifo;
    end

    assign dout_cmd_fifo_qos_reg = (rd_data_cstate == FINISH) ? dout_cmd_fifo : dout_cmd_fifo_qos;

    assign qos_update_pkt_num = dout_cmd_fifo_qos_reg.cnt_chain;
    assign qos_update_uid = rd_data_ctx_info_rd_rsp_qos_unit_1d;
    // 在 Virtio-Net 协议中，每个包都有一个 12 字节的 Virtio Header。
    assign qos_update_len = (dout_cmd_fifo_qos_reg.total_buf_len > 12 ) ? (dout_cmd_fifo_qos_reg.total_buf_len - 12) : dout_cmd_fifo_qos_reg.total_buf_len ;

    always @(posedge clk)begin
        if(rst)begin
            qos_update_vld <= 0;
        end
        else if(qos_update_vld && qos_update_rdy)begin
            qos_update_vld <= 0;
        end
        else if(rd_data_ctx_info_rd_rsp_vld && rd_data_ctx_info_rd_rsp_qos_enable && dout_cmd_fifo_1d.eop && (rd_data_len_total + rd_data_len == desc_total_len))begin
            qos_update_vld <= 1;
        end
    end
    /*
    always @(posedge clk)begin
        if(rst)begin
            qos_update_vld <= 0;
        end
        else if(qos_update_vld && qos_update_rdy)begin
            qos_update_vld <= 0;
        end
        else if(qos_update_vld_pre && dout_cmd_fifo_qos.eop)begin
            qos_update_vld <= 1;
        end
    end
    */

    always @(posedge clk)begin
        if(rst)begin
            qos_finish <= 0;
        end
        else if(qos_finish && rd_data_cstate == RD_IDLE)begin
            qos_finish <= 0;
        end
        else if(qos_update_vld && qos_update_rdy)begin
            qos_finish <= 1;
        end
    end
    yucca_sync_fifo #(
        .DATA_WIDTH ($size(din_cmd_fifo)),
        .FIFO_DEPTH (16),
        .CHECK_ON (1),
        .CHECK_MODE ("parity"),
        .DEPTH_PFULL (2),
        .DEPTH_PEMPTY (),
        .RAM_MODE ("dist"),
        .FIFO_MODE ("fwft")
    )u_cmd_fifo(
    
        .clk           ( clk ),
        .rst           ( rst ),
    
        .wren          ( wren_cmd_fifo ),
        .din           ( din_cmd_fifo ),
        .full          ( cmd_fifo_full),
        .pfull         ( cmd_fifo_pfull),
        .overflow      ( cmd_fifo_overflow),
           
        .rden          ( rden_cmd_fifo),
        .dout          ( dout_cmd_fifo),
        .empty         ( cmd_fifo_empty),
        .pempty        (),
        .underflow     ( cmd_fifo_underflow),
    
        .usedw         (),  
    
        .parity_ecc_err( cmd_fifo_err)
    
    );


    always @(posedge clk)begin
        dfx_status <= {cmd_fifo_full,
                       cmd_fifo_pfull,
                       cmd_fifo_empty,
                       dma_rd_req.sav,
                       order_fifo_sav,
                       nettx_desc_rsp_rdy,
                       nettx_desc_rsp_vld,
                       qos_update_rdy,
                       qos_update_vld,
                       inflight_ctrl_space[7:0],
                       8'h0,
                       inflight_data_space[9:0],
                       10'h0,
                       rd_data_cstate,
                       proc_desc_cstate};

        dfx_err <= {cmd_fifo_underflow,
                    cmd_fifo_overflow,
                    cmd_fifo_err
                    //(nettx_desc_rsp_sbd.err_info >0)
                    };
    end


    always @(posedge clk)begin
        if(rst)begin
            rd_issued_cnt <= 0;
        end
        else if(dma_rd_req.vld)begin
            rd_issued_cnt <= rd_issued_cnt + 1;
        end
    end

    


endmodule
