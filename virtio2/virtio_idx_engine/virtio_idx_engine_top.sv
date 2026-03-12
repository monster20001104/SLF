/******************************************************************************
 * 文件名称 : virtio_idx_engine_top.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/12/18
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v2.0  12/18     Joe Jiang   新增kick notify抑制
 ******************************************************************************/
 `include "virtio_define.svh"
module virtio_idx_engine_top 
    import alt_tlp_adaptor_pkg::*;
#(
   parameter DATA_WIDTH                = 256,
   parameter EMPTH_WIDTH               = $clog2(DATA_WIDTH/8)
)
(
        
    input                                    clk,
    input                                    rst,

    input  logic                             notify_req_vld,
    output logic                             notify_req_rdy,
    input  virtio_vq_t                       notify_req_vq,
    
    output logic                             notify_rsp_vld,
    input  logic                             notify_rsp_rdy,
    output logic                             notify_rsp_cold,
    output logic                             notify_rsp_done,
    output virtio_vq_t                       notify_rsp_vq,

    tlp_adap_dma_rd_req_if.src               idx_eng_dma_rd_req,
    tlp_adap_dma_rd_rsp_if.snk               idx_eng_dma_rd_rsp,

    tlp_adap_dma_wr_req_if.src               idx_eng_dma_wr_req,
    tlp_adap_dma_wr_rsp_if.snk               idx_eng_dma_wr_rsp,

    output logic                             idx_notify_vld,
    output virtio_vq_t                       idx_notify_vq,
    input  logic                             idx_notify_rdy,

    output logic                             idx_engine_ctx_rd_req_vld,
    output virtio_vq_t                       idx_engine_ctx_rd_req_vq,
    input  logic                             idx_engine_ctx_rd_rsp_vld,
    input  logic [9:0]                       idx_engine_ctx_rd_rsp_dev_id,
    input  logic [15:0]                      idx_engine_ctx_rd_rsp_bdf,
    input  logic [63:0]                      idx_engine_ctx_rd_rsp_avail_addr,
    input  logic [63:0]                      idx_engine_ctx_rd_rsp_used_addr,
    input  logic [3:0]                       idx_engine_ctx_rd_rsp_qdepth,
    input  logic [$bits(virtio_qstat_t)-1:0] idx_engine_ctx_rd_rsp_ctrl,
    input  logic                             idx_engine_ctx_rd_rsp_force_shutdown,
    input  logic [15:0]                      idx_engine_ctx_rd_rsp_avail_idx,
    input  logic [15:0]                      idx_engine_ctx_rd_rsp_avail_ui,
    input  logic                             idx_engine_ctx_rd_rsp_no_notify,
    input  logic                             idx_engine_ctx_rd_rsp_no_change,
    input  logic [6:0]                       idx_engine_ctx_rd_rsp_dma_req_num,
    input  logic [6:0]                       idx_engine_ctx_rd_rsp_dma_rsp_num,

    output logic                             idx_engine_ctx_wr_vld,
    output virtio_vq_t                       idx_engine_ctx_wr_vq,
    output logic [15:0]                      idx_engine_ctx_wr_avail_idx,
    output logic                             idx_engine_ctx_wr_no_notify,
    output logic                             idx_engine_ctx_wr_no_change,
    output logic [6:0]                       idx_engine_ctx_wr_dma_req_num,
    output logic [6:0]                       idx_engine_ctx_wr_dma_rsp_num,

    output logic                             err_code_wr_req_vld,
    output virtio_vq_t                       err_code_wr_req_vq,
    output virtio_err_info_t                 err_code_wr_req_data,
    input  logic                             err_code_wr_req_rdy,

    mlite_if.slave                           dfx_slave
 );
   localparam FIFO_DEPTH      = 32;

   typedef enum logic [3:0] { 
        KICK_NOTIFY      = 4'b0001,
        WR_NOTIFY_RSP    = 4'b0010,
        RD_NOTIFY_RSP    = 4'b0100,
        RD_IDX_RSP       = 4'b1000
   } process_type_t;

   enum logic [4:0] { 
        IDLE      = 5'b00001,
        SCH       = 5'b00010,
        RD_CTX    = 5'b00100,
        EXEC      = 5'b01000,
        WR_CTX    = 5'b10000
   } cstate, nstate;

   logic [63:0]   dfx_status;
   logic [63:0]   dfx_err, dfx_err_q;
 
   logic [7:0]    rd_rsp_err_cnt;   
   logic [15:0]   idx_threshold;

   logic [15:0]   idx_diff;
   logic [63:0]   used_flags_addr;
   logic [63:0]   avail_idx_addr;
   logic [9:0]    dev_id;
   logic [15:0]   bdf;        
   logic [15:0]    qszie;          
   virtio_qstat_t q_status;    
   logic          force_shutdown;
   logic [15:0]   avail_idx;    
   logic [15:0]   avail_ui;
   logic          no_notify; 
   logic          no_change;  
   logic [6:0]    dma_req_num;   
   logic [6:0]    dma_rsp_num;

   logic [7:0]    rd_idx_req_cnt;
   logic [7:0]    rd_idx_rsp_cnt;
   logic [7:0]    rd_idx_inflight_cnt;
   logic [7:0]    rd_flags_req_cnt;
   logic [7:0]    rd_flags_rsp_cnt;
   logic [7:0]    rd_flags_inflight_cnt;
   logic [7:0]    wr_req_cnt;
   logic [7:0]    wr_rsp_cnt;
   logic [7:0]    wr_inflight_cnt;
   logic [7:0]    rd_flags_rsp_err_cnt;
   logic [7:0]    rd_idx_rsp_err_cnt;
   logic          dma_wr_inflight_ready;
   logic          dma_rd_idx_inflight_ready;
   logic          dma_rd_flags_inflight_ready;

   process_type_t    process_type;
   virtio_vq_t       process_vq;
   logic [15:0]      process_avail_idx;
   logic             process_pcie_err;
   virtio_err_code_t err_code;

   typedef struct packed{
      virtio_vq_t    vq;
      logic [15:0]   avail_idx;
      logic          err;
   } virtio_idx_rsp_t;

   logic[$bits(virtio_vq_t):0] rd_flags_rsp_ff_din, rd_flags_rsp_ff_dout;
   logic rd_flags_rsp_ff_wren, rd_flags_rsp_ff_rden, rd_flags_rsp_ff_empty;
   logic rd_flags_rsp_ff_overflow, rd_flags_rsp_ff_underflow;
   logic [1:0] rd_flags_rsp_ff_parity_ecc_err;

   virtio_idx_rsp_t rd_idx_rsp_ff_din, rd_idx_rsp_ff_dout;
   logic rd_idx_rsp_ff_wren, rd_idx_rsp_ff_rden, rd_idx_rsp_ff_empty;
   logic rd_idx_rsp_ff_overflow, rd_idx_rsp_ff_underflow;
   logic [1:0] rd_idx_rsp_ff_parity_ecc_err;

   virtio_vq_t wr_rsp_ff_din, wr_rsp_ff_dout;
   logic wr_rsp_ff_wren, wr_rsp_ff_rden, wr_rsp_ff_empty;
   logic wr_rsp_ff_overflow, wr_rsp_ff_underflow;
   logic [1:0] wr_rsp_ff_parity_ecc_err;

   logic wr_flags, rd_flags, rd_idx;

   yucca_sync_fifo #(
        .DATA_WIDTH  ($bits(virtio_vq_t)+1),
        .FIFO_DEPTH  (FIFO_DEPTH             ),
        .CHECK_ON    (1                      ),
        .CHECK_MODE  ("parity"               ),
        .RAM_MODE    ("dist"                 ),
        .FIFO_MODE   ("fwft"                 )
   )u_rd_rsp_ff(
        .clk           ( clk                       ),
        .rst           ( rst                       ),
        .wren          ( rd_flags_rsp_ff_wren          ),
        .din           ( rd_flags_rsp_ff_din           ),
        .full          (                           ),
        .pfull         (                           ),
        .overflow      ( rd_flags_rsp_ff_overflow      ),
        .rden          ( rd_flags_rsp_ff_rden          ),
        .dout          ( rd_flags_rsp_ff_dout          ),
        .empty         ( rd_flags_rsp_ff_empty         ),
        .pempty        (                           ),
        .underflow     ( rd_flags_rsp_ff_underflow     ),
        .usedw         (                           ),  
        .parity_ecc_err( rd_flags_rsp_ff_parity_ecc_err)
   );

   assign rd_flags_rsp_ff_wren = idx_eng_dma_rd_rsp.vld && idx_eng_dma_rd_rsp.eop && idx_eng_dma_rd_rsp.sop && ~idx_eng_dma_rd_rsp.desc.rd2rsp_loop[$bits(virtio_vq_t)];
   assign rd_flags_rsp_ff_din = {idx_eng_dma_rd_rsp.err, idx_eng_dma_rd_rsp.desc.rd2rsp_loop[$bits(virtio_vq_t)-1:0]};
   assign rd_flags_rsp_ff_rden = cstate == WR_CTX && process_type == RD_NOTIFY_RSP;


   yucca_sync_fifo #(
        .DATA_WIDTH  ($bits(virtio_idx_rsp_t)),
        .FIFO_DEPTH  (FIFO_DEPTH             ),
        .CHECK_ON    (1                      ),
        .CHECK_MODE  ("parity"               ),
        .RAM_MODE    ("dist"                 ),
        .FIFO_MODE   ("fwft"                 )
   )u_rd_idx_rsp_ff(
        .clk           ( clk                       ),
        .rst           ( rst                       ),
        .wren          ( rd_idx_rsp_ff_wren          ),
        .din           ( rd_idx_rsp_ff_din           ),
        .full          (                           ),
        .pfull         (                           ),
        .overflow      ( rd_idx_rsp_ff_overflow      ),
        .rden          ( rd_idx_rsp_ff_rden          ),
        .dout          ( rd_idx_rsp_ff_dout          ),
        .empty         ( rd_idx_rsp_ff_empty         ),
        .pempty        (                           ),
        .underflow     ( rd_idx_rsp_ff_underflow     ),
        .usedw         (                           ),  
        .parity_ecc_err( rd_idx_rsp_ff_parity_ecc_err)
   );

   assign rd_idx_rsp_ff_wren = idx_eng_dma_rd_rsp.vld && idx_eng_dma_rd_rsp.eop && idx_eng_dma_rd_rsp.sop && idx_eng_dma_rd_rsp.desc.rd2rsp_loop[$bits(virtio_vq_t)];
   assign rd_idx_rsp_ff_din.avail_idx = idx_eng_dma_rd_rsp.data[15:0];
   assign rd_idx_rsp_ff_din.vq = idx_eng_dma_rd_rsp.desc.rd2rsp_loop[$bits(virtio_vq_t)-1:0];
   assign rd_idx_rsp_ff_din.err = idx_eng_dma_rd_rsp.err;
   assign rd_idx_rsp_ff_rden = cstate == WR_CTX && process_type == RD_IDX_RSP;

   yucca_sync_fifo #(
        .DATA_WIDTH  ($bits(virtio_vq_t)),
        .FIFO_DEPTH  (FIFO_DEPTH             ),
        .CHECK_ON    (1                      ),
        .CHECK_MODE  ("parity"               ),
        .RAM_MODE    ("dist"                 ),
        .FIFO_MODE   ("fwft"                 )
   )u_wr_rsp_ff(
        .clk           ( clk                       ),
        .rst           ( rst                       ),
        .wren          ( wr_rsp_ff_wren          ),
        .din           ( wr_rsp_ff_din           ),
        .full          (                           ),
        .pfull         (                           ),
        .overflow      ( wr_rsp_ff_overflow      ),
        .rden          ( wr_rsp_ff_rden          ),
        .dout          ( wr_rsp_ff_dout          ),
        .empty         ( wr_rsp_ff_empty         ),
        .pempty        (                           ),
        .underflow     ( wr_rsp_ff_underflow     ),
        .usedw         (                           ),  
        .parity_ecc_err( wr_rsp_ff_parity_ecc_err)
   );

   assign wr_rsp_ff_wren = idx_eng_dma_wr_rsp.vld;
   assign wr_rsp_ff_din  = idx_eng_dma_wr_rsp.rd2rsp_loop;
   assign wr_rsp_ff_rden = cstate == WR_CTX && process_type == WR_NOTIFY_RSP;
   
   assign notify_req_rdy = cstate == WR_CTX && process_type == KICK_NOTIFY;

   always @(posedge clk) begin
      if(rst)begin
         cstate <= IDLE;
      end else begin
         cstate <= nstate;
      end
   end

   always @(*) begin
      nstate = cstate;
      case (cstate)
         IDLE: begin
            if(((!rd_idx_rsp_ff_empty) || (!rd_flags_rsp_ff_empty && dma_rd_idx_inflight_ready) || (!wr_rsp_ff_empty && dma_rd_idx_inflight_ready && dma_wr_inflight_ready)  || (notify_req_vld && dma_rd_idx_inflight_ready && dma_rd_flags_inflight_ready && dma_wr_inflight_ready))
                  && !idx_notify_vld && !err_code_wr_req_vld && !notify_rsp_vld //Ensure the handshake always succeeds
                  && idx_eng_dma_rd_req.sav && idx_eng_dma_wr_req.sav)begin
               nstate = SCH;
            end
         end
         SCH: begin
            nstate = RD_CTX;
         end
         RD_CTX: begin
            nstate = EXEC;
         end
         EXEC: begin
            nstate = WR_CTX;
         end
         WR_CTX: begin
            nstate = IDLE;
         end
      endcase
   end

   always @(posedge clk) begin
      if(rst)begin
            process_pcie_err     <= 1'b0; 
      end else if(cstate == IDLE)begin
         if(!rd_idx_rsp_ff_empty)begin
            process_avail_idx    <= rd_idx_rsp_ff_dout.avail_idx; //avail_idx from host memory
            process_type         <= RD_IDX_RSP;
            process_pcie_err     <= rd_idx_rsp_ff_dout.err;
            process_vq           <= rd_idx_rsp_ff_dout.vq;
         end else if(!rd_flags_rsp_ff_empty && dma_rd_idx_inflight_ready)begin
            process_avail_idx    <= 16'h0;
            process_type         <= RD_NOTIFY_RSP;
            process_pcie_err     <= rd_flags_rsp_ff_dout[$bits(virtio_vq_t)];
            process_vq           <= rd_flags_rsp_ff_dout[$bits(virtio_vq_t)-1:0];
         end else if(!wr_rsp_ff_empty)begin
            process_avail_idx    <= 16'h0;
            process_pcie_err     <= 1'b0;
            process_type         <= WR_NOTIFY_RSP;
            process_vq           <= wr_rsp_ff_dout;
         end else begin
            process_avail_idx    <= 16'h0;
            process_pcie_err     <= 1'b0;
            process_type         <= KICK_NOTIFY;
            process_vq           <= notify_req_vq;
         end
      end
   end

   assign idx_engine_ctx_rd_req_vld = cstate == SCH;
   assign idx_engine_ctx_rd_req_vq  = process_vq;

   always @(posedge clk) begin
      if(idx_engine_ctx_rd_rsp_vld)begin
         used_flags_addr   <= idx_engine_ctx_rd_rsp_used_addr;
         avail_idx_addr    <= idx_engine_ctx_rd_rsp_avail_addr + 2;
         dev_id            <= idx_engine_ctx_rd_rsp_dev_id;
         bdf               <= idx_engine_ctx_rd_rsp_bdf;
         qszie             <= 'h1 << idx_engine_ctx_rd_rsp_qdepth;
         q_status          <= virtio_qstat_t'(idx_engine_ctx_rd_rsp_ctrl);
         force_shutdown    <= idx_engine_ctx_rd_rsp_force_shutdown;
         avail_idx         <= idx_engine_ctx_rd_rsp_avail_idx; // avail_idx in ctx
         avail_ui          <= idx_engine_ctx_rd_rsp_avail_ui;
         no_notify         <= idx_engine_ctx_rd_rsp_no_notify;
         no_change         <= idx_engine_ctx_rd_rsp_no_change;
         dma_req_num       <= idx_engine_ctx_rd_rsp_dma_req_num;
         dma_rsp_num       <= idx_engine_ctx_rd_rsp_dma_rsp_num;
      end
   end

   assign idx_diff = avail_idx - avail_ui;

   always @(*) begin
      if(process_type == KICK_NOTIFY)begin
         if(idx_diff <= idx_threshold)begin
            if(no_change)begin
               if(no_notify)begin
                  wr_flags = 1'b1;
                  rd_flags = 1'b0;
                  rd_idx   = 1'b0;
               end else begin
                  wr_flags = 1'b0;
                  rd_flags = 1'b0;
                  rd_idx   = 1'b1;
               end
            end else begin
               if(no_notify)begin
                  wr_flags = 1'b0;
                  rd_flags = 1'b0;
                  rd_idx   = 1'b1;
               end else begin
                  wr_flags = 1'b1;
                  rd_flags = 1'b0;
                  rd_idx   = 1'b0;
               end
            end
         end else begin //idx_diff > idx_threshold
            if(no_notify)begin
               wr_flags = 1'b0;
               rd_flags = 1'b0;
               rd_idx   = 1'b0;
            end else begin
               wr_flags = 1'b1;
               rd_flags = 1'b0;
               rd_idx   = 1'b0;
            end
         end
      end else if(process_type == WR_NOTIFY_RSP)begin
         wr_flags = 1'b0;
         rd_flags = 1'b1;
         rd_idx   = 1'b0;
      end else if(process_type == RD_NOTIFY_RSP)begin
         if(idx_diff > idx_threshold)begin
            wr_flags = 1'b0;
            rd_flags = 1'b0;
            rd_idx   = 1'b0;
         end else begin //idx_diff <= idx_threshold
            wr_flags = 1'b0;
            rd_flags = 1'b0;
            rd_idx   = 1'b1;
         end
      end else begin //process_type == RD_IDX_RSP
         wr_flags = 1'b0;
         rd_flags = 1'b0;
         rd_idx   = 1'b0;
      end
   end


   always @(posedge clk) begin
      if(rst)begin
         idx_eng_dma_wr_req.vld <= 1'b0;
      end else if(cstate == EXEC && q_status == VIRTIO_Q_STATUS_DOING)begin
         idx_eng_dma_wr_req.vld <= wr_flags;
      end else begin
         idx_eng_dma_wr_req.vld <= 1'b0;
      end
   end

   always @(posedge clk)begin
      idx_eng_dma_wr_req.sop              <= 1'b1;
      idx_eng_dma_wr_req.sty              <= {EMPTH_WIDTH{1'h0}};    
      idx_eng_dma_wr_req.eop              <= 1'b1;                                                        
      idx_eng_dma_wr_req.mty              <= DATA_WIDTH/8 - 2;
      idx_eng_dma_wr_req.data             <= {{DATA_WIDTH-1{1'h0}}, !no_notify};    
      idx_eng_dma_wr_req.desc.pcie_addr   <= used_flags_addr;
      idx_eng_dma_wr_req.desc.bdf         <= bdf;
      idx_eng_dma_wr_req.desc.rd2rsp_loop <= process_vq;
      idx_eng_dma_wr_req.desc.pcie_length <= 2;
      idx_eng_dma_wr_req.desc.dev_id      <= dev_id;
   end  

   always @(posedge clk) begin
      if(rst)begin
         idx_eng_dma_rd_req.vld <= 1'b0;
      end else if(cstate == EXEC && q_status == VIRTIO_Q_STATUS_DOING)begin
         idx_eng_dma_rd_req.vld <= rd_flags || rd_idx; 
      end else begin
         idx_eng_dma_rd_req.vld <= 1'b0;
      end
   end

   always @(posedge clk) begin
      idx_eng_dma_rd_req.desc             <= 'h0;
      idx_eng_dma_rd_req.sty              <= {EMPTH_WIDTH{1'h0}};
      idx_eng_dma_rd_req.desc.bdf         <= bdf;
      idx_eng_dma_rd_req.desc.pcie_addr   <= process_type != WR_NOTIFY_RSP ? avail_idx_addr : used_flags_addr;
      idx_eng_dma_rd_req.desc.pcie_length <= 'h2;
      idx_eng_dma_rd_req.desc.rd2rsp_loop <= {process_type != WR_NOTIFY_RSP, process_vq};
      idx_eng_dma_rd_req.desc.dev_id      <= dev_id;
   end
   //err handle
   always @(posedge clk) begin
      if(rst)begin
         err_code <= VIRTIO_ERR_CODE_NONE;
      end else begin
         if(cstate == EXEC)begin
            if(process_pcie_err)begin
               err_code <= VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR;
            end else if(process_type == RD_IDX_RSP && process_avail_idx - avail_idx > qszie)begin
               err_code <= VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX;
            end else begin
               err_code <= VIRTIO_ERR_CODE_NONE;
            end
         end
      end
   end

   always @(posedge clk) begin
      if(rst)begin
         idx_engine_ctx_wr_vld <= 1'b0;
      end else begin
         idx_engine_ctx_wr_vld <= cstate == WR_CTX && (q_status == VIRTIO_Q_STATUS_DOING || q_status == VIRTIO_Q_STATUS_STOPPING); 
         idx_engine_ctx_wr_vq  <= process_vq;
      end
   end

   always @(posedge clk) begin
      if(process_type == RD_IDX_RSP && err_code == VIRTIO_ERR_CODE_NONE)begin
         idx_engine_ctx_wr_avail_idx <= process_avail_idx;
         idx_engine_ctx_wr_no_change <= process_avail_idx == avail_idx;
      end else begin
         idx_engine_ctx_wr_avail_idx <= avail_idx;
         idx_engine_ctx_wr_no_change <= no_change;
      end

      if(process_type == KICK_NOTIFY && wr_flags)begin
         idx_engine_ctx_wr_no_notify <= !no_notify;
      end else begin
         idx_engine_ctx_wr_no_notify <= no_notify;
      end

      if(idx_eng_dma_rd_req.vld || (idx_eng_dma_wr_req.vld && idx_eng_dma_wr_req.eop))begin
         idx_engine_ctx_wr_dma_req_num <= dma_req_num + 1'b1;
      end else begin
         idx_engine_ctx_wr_dma_req_num <= dma_req_num;
      end

      if(rd_flags_rsp_ff_rden || rd_idx_rsp_ff_rden || wr_rsp_ff_rden)begin
         idx_engine_ctx_wr_dma_rsp_num <= dma_rsp_num + 1'b1;
      end else begin
         idx_engine_ctx_wr_dma_rsp_num <= dma_rsp_num;
      end
   end

   always @(posedge clk) begin
      if(rst)begin
         idx_notify_vld    <= 1'b0;
      end if(!idx_notify_vld || idx_notify_rdy)begin
         idx_notify_vld    <= cstate == WR_CTX && process_type == RD_IDX_RSP && err_code == VIRTIO_ERR_CODE_NONE && avail_idx != process_avail_idx;
         idx_notify_vq     <= process_vq;
      end
   end

   always @(posedge clk) begin
      if(rst)begin
         err_code_wr_req_vld              <= 1'b0;
      end if(!err_code_wr_req_vld || err_code_wr_req_rdy)begin
         err_code_wr_req_vld              <= cstate == WR_CTX && err_code != VIRTIO_ERR_CODE_NONE;
         err_code_wr_req_vq               <= process_vq;
         err_code_wr_req_data.err_code    <= err_code;
         err_code_wr_req_data.fatal       <= 1'b1;
      end
   end

   always @(posedge clk) begin
      if(rst)begin
         notify_rsp_vld    <= 1'b0;
      end else if(!notify_rsp_vld || notify_rsp_rdy)begin
         notify_rsp_vld    <= cstate == WR_CTX && ((process_type == KICK_NOTIFY && idx_diff > idx_threshold && no_notify) || (process_type == RD_NOTIFY_RSP && idx_diff > idx_threshold)  || process_type == RD_IDX_RSP || q_status != VIRTIO_Q_STATUS_DOING);
         notify_rsp_vq     <= process_vq;
         notify_rsp_cold   <= (q_status == VIRTIO_Q_STATUS_STOPPING  || idx_diff > idx_threshold) && !force_shutdown;
         notify_rsp_done   <= force_shutdown || (q_status == VIRTIO_Q_STATUS_IDLE) || (process_type == RD_IDX_RSP && process_avail_idx == avail_idx && !no_notify);
      end
   end


   always @(posedge clk) begin
      if(rst)begin
         rd_idx_req_cnt                <= 8'h0;
         rd_idx_rsp_cnt                <= 8'h0;
         rd_idx_inflight_cnt           <= 8'h0;
         rd_idx_rsp_err_cnt            <= 8'h0;
         dma_rd_idx_inflight_ready     <= 1'b0;
         rd_flags_req_cnt              <= 8'h0;
         rd_flags_rsp_cnt              <= 8'h0;
         rd_flags_inflight_cnt         <= 8'h0;
         rd_flags_rsp_err_cnt          <= 8'h0;
         dma_rd_flags_inflight_ready   <= 1'b0;
         wr_req_cnt                    <= 8'h0;
         wr_rsp_cnt                    <= 8'h0;
         wr_inflight_cnt               <= 8'h0;
         dma_wr_inflight_ready         <= 1'b0;
      end else begin

         rd_idx_req_cnt                <= rd_idx_req_cnt + (idx_eng_dma_rd_req.vld && idx_eng_dma_rd_req.desc.rd2rsp_loop[$bits(virtio_vq_t)]);
         rd_idx_rsp_cnt                <= rd_idx_rsp_cnt + rd_idx_rsp_ff_rden;
         rd_idx_rsp_err_cnt            <= rd_idx_rsp_err_cnt + (idx_eng_dma_rd_rsp.vld && idx_eng_dma_rd_rsp.eop && idx_eng_dma_rd_rsp.err && idx_eng_dma_rd_rsp.desc.rd2rsp_loop[$bits(virtio_vq_t)]);

         rd_flags_req_cnt              <= rd_flags_req_cnt + (idx_eng_dma_rd_req.vld && ~idx_eng_dma_rd_req.desc.rd2rsp_loop[$bits(virtio_vq_t)]);
         rd_flags_rsp_cnt              <= rd_flags_rsp_cnt + rd_flags_rsp_ff_rden;
         rd_flags_rsp_err_cnt          <= rd_flags_rsp_err_cnt + (idx_eng_dma_rd_rsp.vld && idx_eng_dma_rd_rsp.eop && idx_eng_dma_rd_rsp.err && ~idx_eng_dma_rd_rsp.desc.rd2rsp_loop[$bits(virtio_vq_t)]);
         
         wr_req_cnt                    <= wr_req_cnt + (idx_eng_dma_wr_req.vld && idx_eng_dma_wr_req.eop);
         wr_rsp_cnt                    <= wr_rsp_cnt + wr_rsp_ff_rden;

         rd_idx_inflight_cnt           <= rd_idx_req_cnt - rd_idx_rsp_cnt;
         rd_flags_inflight_cnt         <= rd_flags_req_cnt - rd_flags_rsp_cnt;
         wr_inflight_cnt               <= wr_req_cnt - wr_rsp_cnt;

         dma_rd_idx_inflight_ready     <= rd_idx_inflight_cnt < FIFO_DEPTH-4;
         dma_rd_flags_inflight_ready   <= rd_flags_inflight_cnt < FIFO_DEPTH-4;
         dma_wr_inflight_ready         <= wr_inflight_cnt < FIFO_DEPTH-4;

      end
   end

   always @(posedge clk) begin
      dfx_err <= {
         idx_eng_dma_rd_rsp.vld && (!idx_eng_dma_rd_rsp.sop || !idx_eng_dma_rd_rsp.eop),
         rd_idx_rsp_ff_overflow,
         rd_idx_rsp_ff_underflow,
         rd_idx_rsp_ff_parity_ecc_err,
         rd_flags_rsp_ff_overflow,
         rd_flags_rsp_ff_underflow,
         rd_flags_rsp_ff_parity_ecc_err,
         wr_rsp_ff_overflow,
         wr_rsp_ff_underflow,
         wr_rsp_ff_parity_ecc_err
      };
      dfx_status <= {
         idx_eng_dma_rd_req.sav,
         idx_eng_dma_wr_req.sav,
         err_code_wr_req_vld,
         err_code_wr_req_rdy,
         idx_notify_vld,
         idx_notify_rdy,
         notify_rsp_vld,
         notify_rsp_rdy,
         notify_req_vld,
         notify_req_rdy,
         cstate, //5bits
         dma_rd_idx_inflight_ready,
         dma_rd_flags_inflight_ready,
         dma_wr_inflight_ready,
         rd_flags_rsp_ff_empty,
         rd_idx_rsp_ff_empty,
         wr_rsp_ff_empty
      };
   end

   virtio_idx_engine_reg_dfx #(
      .ADDR_WIDTH(12),
      .DATA_WIDTH(64)
   )u_virtio_idx_engine_reg_dfx(
      .clk                                (clk                       ),
      .rst                                (rst                       ),
      .dfx_err0_dfx_err_we                (|dfx_err                  ),
      .dfx_err0_dfx_err_wdata             (dfx_err|dfx_err_q         ),
      .dfx_err0_dfx_err_q                 (dfx_err_q                 ),
      .dfx_status0_dfx_status_wdata       (dfx_status                ),
      .rd_idx_req_cnt_dfx_cnt_wdata       (rd_idx_req_cnt            ),
      .rd_idx_rsp_cnt_dfx_cnt_wdata       (rd_idx_rsp_cnt            ),
      .rd_idx_rsp_err_cnt_dfx_cnt_wdata   (rd_idx_rsp_err_cnt        ),
      .rd_flags_req_cnt_dfx_cnt_wdata     (rd_flags_req_cnt          ),
      .rd_flags_rsp_cnt_dfx_cnt_wdata     (rd_flags_rsp_cnt          ),
      .rd_flags_rsp_err_cnt_dfx_cnt_wdata (rd_flags_rsp_err_cnt      ),
      .wr_req_cnt_dfx_cnt_wdata           (wr_req_cnt                ),
      .wr_rsp_cnt_dfx_cnt_wdata           (wr_rsp_cnt                ),
      .dfx_threshold0_dfx_threshold_q     (idx_threshold             ),
      .csr_if                             (dfx_slave                 )
   );

   genvar idx;
   generate
      for(idx=0;idx<$bits(dfx_err);idx++)begin :db_err_i
         assert property (@(posedge clk) disable iff (rst) (~(dfx_err[idx]===1'b1)))
         else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, dfx_err[idx], idx));
      end
   endgenerate

endmodule