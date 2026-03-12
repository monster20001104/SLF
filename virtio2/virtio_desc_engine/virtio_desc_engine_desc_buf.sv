/******************************************************************************
 * 文件名称 : virtio_desc_engine_desc_buf.sv
 * 作者名称 : Joe Jiang
 * 创建日期 : 2025/06/23
 * 功能描述 : 
 *
 * 修改记录 : 
 *
 * 版本号  日期       修改人       修改内容
 * v1.0  06/23     Joe Jiang   初始化版本
 ******************************************************************************/
  `include "virtio_desc_engine_define.svh"
 module virtio_desc_engine_desc_buf #(
    parameter DATA_WIDTH                     = 256,
    parameter EMPTH_WIDTH                    = $clog2(DATA_WIDTH/8),
    parameter SLOT_NUM                       = 32,
    parameter SLOT_WIDTH                     = $clog2(SLOT_NUM),
    parameter LINE_NUM                       = 8,
    parameter LINE_WIDTH                     = $clog2(LINE_NUM),
    parameter BUCKET_NUM                     = 128,
    parameter BUCKET_WIDTH                   = $clog2(BUCKET_NUM),
    parameter DESC_BUF_DEPTH                 = (BUCKET_NUM*LINE_NUM),
    parameter IS_WRITE_ONLY                  = 1,                         
    parameter WRITE_ONLY_CHECK_ON            = 0                                          
 ) (
   input                                                                            clk,
   input                                                                            rst,

   tlp_adap_dma_rd_rsp_if.snk                                                       dma_desc_rd_rsp_if,

   input                                                                            order_wr_vld,
   input  virtio_desc_eng_core_rd_desc_order_t                                      order_wr_dat,

   output                                                                           info_rd_vld,
   output virtio_desc_eng_core_info_ff_t                                            info_rd_dat,
   input                                                                            info_rd_rdy,

   input  logic [$clog2(DESC_BUF_DEPTH)+$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:0] desc_buf_rd_req_addr ,
   input  logic                                                                     desc_buf_rd_req_vld  ,
   output virtq_desc_t                                                              desc_buf_rd_rsp_dat  ,
   output logic                                                                     desc_buf_rd_rsp_vld  ,
   output logic [12:0]                                                              dfx_err              ,
   output logic [3:0]                                                               dfx_status
 );
 
   logic [3:0]                                              rsp_data_vld_cnt;
   logic [DATA_WIDTH/$bits(virtq_desc_t)-1:0]               keep_left, keep_right, match_nxt, vld_desc;
   logic [DATA_WIDTH/$bits(virtq_desc_t)-1:0]               keep_d, keep_dd;
   logic                                                    vld_d, sop_d, eop_d;
   logic                                                    vld_dd, sop_dd, eop_dd;
   logic                                                    vld_ddd, sop_ddd, eop_ddd;
   (* ramstyle = "logic" *) logic                           pcie_err, pcie_err_d, pcie_err_dd, pcie_err_ddd, pcie_err_dddd;
   logic [15:0]                                             idx, next_last_dd;
   virtio_desc_eng_core_desc_rd2rsp_t                       desc_rd2rsp, desc_rd2rsp_d, desc_rd2rsp_dd, desc_rd2rsp_ddd;
   virtq_desc_t [DATA_WIDTH/$bits(virtq_desc_t)-1:0]        desc;
   virtq_desc_t [DATA_WIDTH/$bits(virtq_desc_t)-1:0]        desc_d;
   virtq_desc_t [DATA_WIDTH/$bits(virtq_desc_t)-1:0]        desc_dd;
   virtq_desc_t [DATA_WIDTH/$bits(virtq_desc_t)-1:0]        desc_ddd;
   logic same_chain, same_chain_d;
   logic cycle_flag;

   logic [DATA_WIDTH/$bits(virtq_desc_t)-1:0] desc_buf_ram_wren;
   logic [$bits(virtq_desc_t)-1:0] desc_buf_ram_dina [DATA_WIDTH/$bits(virtq_desc_t)-1:0];
   logic [$bits(virtq_desc_t)-1:0] desc_buf_ram_doutb [DATA_WIDTH/$bits(virtq_desc_t)-1:0];
   logic [$clog2(DESC_BUF_DEPTH)-1:0] desc_buf_ram_addra, desc_buf_ram_addrb;
   logic [1:0] desc_buf_ram_parity_ecc_err [DATA_WIDTH/$bits(virtq_desc_t)-1:0];

   logic [$clog2(DESC_BUF_DEPTH)+$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:0] desc_buf_rd_req_addr_d;

   logic [DATA_WIDTH/$bits(virtq_desc_t)-1:0] desc_nxts;
   logic [DATA_WIDTH/$bits(virtq_desc_t)-1:0] desc_indircts;
   logic [DATA_WIDTH/$bits(virtq_desc_t)-1:0] desc_buf_ram_parity_ecc_err_w;

   logic flag_last_w, flag_last;
   logic flag_indirct_w, flag_indirct;
   logic indirct_processing;

   logic info_ff_wren, info_ff_full, info_ff_pfull, info_ff_rden, info_ff_empty;
   virtio_desc_eng_core_info_ff_t info_ff_din, info_ff_dout;
   logic info_ff_overflow, info_ff_underflow;
   logic [1:0] info_ff_parity_ecc_err;

   logic order_ff_wren, order_ff_pfull, order_ff_rden, order_ff_empty;
   virtio_desc_eng_core_rd_desc_order_t order_ff_din, order_ff_dout;
   logic order_ff_overflow, order_ff_underflow;
   logic [1:0] order_ff_parity_ecc_err;

   logic [20:0]                                                               total_buf_length;
   logic [16:0]                                                               indirct_desc_size;
   logic [DATA_WIDTH/$bits(virtq_desc_t)-1:0][31:0]                           desc_len_ddd;
   logic [15:0]                                                               vld_cnt;

   
   logic [3:0] qdepth;
   virtio_vq_t vq_d, vq_dd;
   logic [SLOT_WIDTH-1:0] slot_id_d, slot_id_dd;

   logic [63:0]                                                        indirct_addr;
   logic [15:0] last_next;

   logic last_flag_next_d;
   logic [DATA_WIDTH/$bits(virtq_desc_t)-1:0][DATA_WIDTH/$bits(virtq_desc_t)-1:0] last_desc_mask_v;

   logic [DATA_WIDTH/$bits(virtq_desc_t)-1:0] indirct_desc_next_must_be_zero, desc_zero_len, desc_buf_len_oversize, write_only_invalid, indirct_nexted_desc, unsupport_indirct;
   logic [16:0] indirct_desc_size_old;
   logic [19:0] max_len;
   //stage1 keep---------------------------------------------
   assign desc_rd2rsp   = dma_desc_rd_rsp_if.desc.rd2rsp_loop;
   assign desc          = dma_desc_rd_rsp_if.data;
   assign pcie_err      = dma_desc_rd_rsp_if.err;

   initial begin
      if ($bits(desc_rd2rsp) > $bits(dma_desc_rd_rsp_if.desc.rd2rsp_loop)) begin
         $error("Width error: signal desc_rd2rsp (%0d bits) > signal dma_desc_rd_rsp_if.desc.rd2rsp_loop (%0d bits)",
                  $bits(desc_rd2rsp), $bits(dma_desc_rd_rsp_if.desc.rd2rsp_loop));
      end
   end

   genvar i, j;
   generate
      for (j = 0; j < DATA_WIDTH/$bits(virtq_desc_t);j++ ) begin
         for (i = 0; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
            if(i == j) begin
               assign last_desc_mask_v[j][j] = dma_desc_rd_rsp_if.sop ? 1'b1 : last_flag_next_d;
            end else if(i > j) begin
               assign last_desc_mask_v[j][i] = desc[i-1].flags.next;
            end else begin
               assign last_desc_mask_v[j][i] = 1'b0;
            end
         end
      end
   endgenerate
   
   
   always @(*) begin
      if(dma_desc_rd_rsp_if.sop)begin
         keep_left  = {DATA_WIDTH/$bits(virtq_desc_t){1'b1}} << dma_desc_rd_rsp_if.sty[EMPTH_WIDTH-1:$clog2($bits(virtq_desc_t)/8)];
      end else begin
         keep_left  = {DATA_WIDTH/$bits(virtq_desc_t){1'b1}};
      end
      if(dma_desc_rd_rsp_if.eop)begin
         keep_right = {DATA_WIDTH/$bits(virtq_desc_t){1'b1}} >> dma_desc_rd_rsp_if.mty[EMPTH_WIDTH-1:$clog2($bits(virtq_desc_t)/8)];
      end else begin
         keep_right = {DATA_WIDTH/$bits(virtq_desc_t){1'b1}};
      end
   end

   always @(posedge clk) begin
      if(rst)begin
         sop_d       <= 1'b0;
         eop_d       <= 1'b0;
         vld_d       <= 1'b0;
      end else begin
         if(dma_desc_rd_rsp_if.vld)begin
            if(desc_rd2rsp.dirct_desc_bitmap == 2'h2)begin
               sop_d    <= rsp_data_vld_cnt == 4'h1;
               vld_d    <= rsp_data_vld_cnt == 4'h1;
               eop_d    <= rsp_data_vld_cnt == 4'h1;
            end else if(desc_rd2rsp.dirct_desc_bitmap == 2'h3)begin
               sop_d    <= rsp_data_vld_cnt == 4'h2;
               vld_d    <= rsp_data_vld_cnt == 4'h2;
               eop_d    <= rsp_data_vld_cnt == 4'h2;
            end else if(desc_rd2rsp.dirct_desc_bitmap == 2'h1)begin
               sop_d    <= rsp_data_vld_cnt == 4'h0;
               vld_d    <= rsp_data_vld_cnt == 4'h0;
               eop_d    <= rsp_data_vld_cnt == 4'h0;
            end else begin
               vld_d    <= 1'b1;
               sop_d    <= dma_desc_rd_rsp_if.sop;
               eop_d    <= dma_desc_rd_rsp_if.eop;
            end
         end else begin
            vld_d       <= 1'b0;
            sop_d       <= 1'b0;
            eop_d       <= 1'b0;
         end         
      end
      pcie_err_d     <= pcie_err;
      desc_d         <= dma_desc_rd_rsp_if.data;
      desc_rd2rsp_d  <= desc_rd2rsp;
      if(dma_desc_rd_rsp_if.sop)begin
         idx         <= desc_rd2rsp.idx - dma_desc_rd_rsp_if.sty[EMPTH_WIDTH-1:$clog2($bits(virtq_desc_t)/8)];
      end else if(dma_desc_rd_rsp_if.vld) begin
         idx         <= idx + DATA_WIDTH/$bits(virtq_desc_t);
      end
   end

   always @(posedge clk) begin
      if(rst)begin
         rsp_data_vld_cnt <= 'h0;
      end else if(dma_desc_rd_rsp_if.vld)begin
         if(dma_desc_rd_rsp_if.eop)begin
            rsp_data_vld_cnt <= 'h0;
         end else begin
            rsp_data_vld_cnt <= rsp_data_vld_cnt + 1'b1;
         end
      end 
   end

   always @(posedge clk) begin
      if(rst)begin
         keep_d <= {DATA_WIDTH/$bits(virtq_desc_t){1'b0}};
      end else if(dma_desc_rd_rsp_if.vld)begin 
         if(desc_rd2rsp.dirct_desc_bitmap == 6'h0)begin
            keep_d <= keep_left & keep_right & last_desc_mask_v[dma_desc_rd_rsp_if.sty[EMPTH_WIDTH-1:$clog2($bits(virtq_desc_t)/8)]];
         end else if(desc_rd2rsp.dirct_desc_bitmap == 2'h1)begin
            keep_d <= rsp_data_vld_cnt == 4'h0 ? 'h1 : 'h0;
         end else if(desc_rd2rsp.dirct_desc_bitmap == 2'h2)begin
            keep_d <= rsp_data_vld_cnt == 4'h1 ? 'h1 : 'h0;
         end else begin
            keep_d <= rsp_data_vld_cnt == 4'h2 ? 'h1 : 'h0;
         end
         last_flag_next_d <= desc[DATA_WIDTH/$bits(virtq_desc_t)-1].flags.next;
      end else begin
         keep_d <= {DATA_WIDTH/$bits(virtq_desc_t){1'b0}};
      end
   end
   //stage2 match next-------------------------------------
   always @(posedge clk) begin
      if(rst)begin
         match_nxt[0] <= 1'b0;
      end else begin
         match_nxt[0] <= keep_d[0] && ((sop_d && (keep_d[0] == 'h1)) || next_last_dd == idx);
      end
   end

   generate
      for (i = 1; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
         always @(posedge clk) begin
            if(rst)begin
               match_nxt[i]      <= 1'b0;
            end else begin
               match_nxt[i]   <= keep_d[i] && ((sop_d && (keep_d[i:0] == ('h1 << i))) || ((desc_d[i-1].next == idx + i) && desc_d[i-1].flags.next));
            end
         end
      end
   endgenerate

   always @(posedge clk) begin
      if(rst)begin
         eop_dd                 <= 1'b0;
         sop_dd                 <= 1'b0;
         vld_dd                 <= 1'b0;
         keep_dd                <= 'h0;
      end else begin
         eop_dd                 <= eop_d;
         sop_dd                 <= sop_d;
         vld_dd                 <= vld_d;
         keep_dd                <= keep_d;
      end
      pcie_err_dd       <= pcie_err_d;
      desc_dd           <= desc_d;
      if (desc_d[DATA_WIDTH/$bits(virtq_desc_t)-1].flags.next)begin
         next_last_dd   <= desc_d[DATA_WIDTH/$bits(virtq_desc_t)-1].next;
      end else begin
         next_last_dd   <= 'h0;
      end
      desc_rd2rsp_dd    <= desc_rd2rsp_d;
   end
   //stage3 wren-------------------------------------------
   always @(*) begin
      for (int i = 0; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
         if(i == 0)begin
            vld_desc[0]       = match_nxt[0];
            same_chain        = match_nxt[0] || sop_dd;
         end else if(match_nxt[i-:2] == 2'b01)begin
            vld_desc[i]       = 0;
            same_chain        = 0;
         end else if(same_chain)begin
            vld_desc[i]       = match_nxt[i];
            same_chain        = 1;
         end else begin
            vld_desc[i]       = 0;
            same_chain        = 0;
         end
      end
   end

   always @(posedge clk) begin
      if(rst)begin
         eop_ddd                 <= 1'b0;
         sop_ddd                 <= 1'b0;
         vld_ddd                 <= 1'b0;
      end else begin
         eop_ddd                 <= eop_dd;
         sop_ddd                 <= sop_dd;
         vld_ddd                 <= vld_dd;
      end
      pcie_err_ddd               <= pcie_err_dd;
      desc_ddd                   <= desc_dd;
      desc_rd2rsp_ddd            <= desc_rd2rsp_dd;
   end

   always @(posedge clk) begin
      if (rst)begin
         desc_buf_ram_wren    <= {DATA_WIDTH/$bits(virtq_desc_t){1'b0}};
      end else if(sop_dd)begin
         desc_buf_ram_wren    <= vld_desc;
      end  else if(same_chain_d)begin
         desc_buf_ram_wren    <= vld_desc;
      end else begin
         desc_buf_ram_wren    <= {DATA_WIDTH/$bits(virtq_desc_t){1'b0}};
      end
   end

   generate
      for (i = 0; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
         always @(posedge clk) begin
            if(rst)begin
               indirct_desc_next_must_be_zero[i]      <= 1'b0;
            end else if(desc_buf_ram_wren[i] && desc_ddd[i].flags.indirect && desc_rd2rsp_ddd.indirct_support && !desc_rd2rsp_ddd.indirct_processing)begin
               if(desc_ddd[i].flags.next)begin
                  indirct_desc_next_must_be_zero[i]   <= 1'b1;
               end else if(sop_ddd) begin
                  indirct_desc_next_must_be_zero[i]   <= 1'b0;
               end
            end else if(sop_ddd)begin
               indirct_desc_next_must_be_zero[i]      <= 1'b0;
            end

            if(rst)begin
               desc_zero_len[i]              <= 1'b0;
               desc_buf_len_oversize[i]      <= 1'b0;
            end else if(desc_buf_ram_wren[i])begin
               if(desc_ddd[i].len == 'h0)begin
                  desc_zero_len[i]           <= 1'b1;
               end else if(sop_ddd) begin
                  desc_zero_len[i]           <= 1'b0;
               end
               if(desc_ddd[i].len > order_ff_dout.max_len && !desc_ddd[i].flags.indirect)begin
                  desc_buf_len_oversize[i]   <= 1'b1;
               end else if(sop_ddd) begin
                  desc_buf_len_oversize[i]   <= 1'b0;
               end
            end else if(sop_ddd)begin
               desc_zero_len[i]              <= 1'b0;
               desc_buf_len_oversize[i]      <= 1'b0;
            end

            if(rst)begin
               indirct_nexted_desc[i]     <= 1'b0;
            end else if(desc_buf_ram_wren[i] && desc_rd2rsp_ddd.indirct_processing)begin
               if(desc_ddd[i].flags.indirect)begin
                  indirct_nexted_desc[i]  <= 1'b1;
               end else if(sop_ddd)begin
                  indirct_nexted_desc[i]  <= 1'b0;
               end
            end else if(sop_ddd)begin
                  indirct_nexted_desc[i]  <= 1'b0;
            end

            if(rst)begin
               write_only_invalid[i]      <= 1'b0;
            end else if(desc_buf_ram_wren[i] && !desc_ddd[i].flags.indirect && WRITE_ONLY_CHECK_ON)begin
               if(IS_WRITE_ONLY != desc_ddd[i].flags.write)begin
                  write_only_invalid[i]   <= 1'b1;
               end else if(sop_ddd)begin
                  write_only_invalid[i]   <= 1'b0;
               end
            end else if(sop_ddd) begin
               write_only_invalid[i]      <= 1'b0;
            end

            if(rst)begin
               unsupport_indirct[i]    <= 1'b0;
            end else if(desc_buf_ram_wren[i])begin
               if(desc_ddd[i].flags.indirect && !desc_rd2rsp_ddd.indirct_support)begin
                  unsupport_indirct[i] <= 1'b1;
               end else if(sop_ddd)begin
                  unsupport_indirct[i] <= 1'b0;
               end
            end else if(sop_ddd)begin
               unsupport_indirct[i]    <= 1'b0;
            end
         end
      end
   endgenerate

   always @(posedge clk) begin
      if(rst)begin
         same_chain_d         <= 1'b1;
      end else if(eop_dd)begin
         same_chain_d         <= 1'b1;
      end else if(vld_dd)begin
         same_chain_d         <= same_chain_d && same_chain;
      end
   end

   always @(posedge clk) begin
      if(sop_dd)begin
         desc_buf_ram_addra <= desc_rd2rsp_dd.desc_buf_local_offset;
      end else if(vld_desc)begin
         desc_buf_ram_addra <= desc_buf_ram_addra + 1'b1;
      end
   end

   generate
      for (i = 0; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
         localparam RAM_MODE = DESC_BUF_DEPTH <= 32 ? "dist" : "blk";
         localparam WRITE_MODE = RAM_MODE == "blk" ? "READ_FIRST" : "WRITE_FIRST";
         sync_simple_dual_port_ram #(
            .DATAA_WIDTH( $bits(virtq_desc_t)     ),
            .ADDRA_WIDTH( $clog2(DESC_BUF_DEPTH)  ),
            .DATAB_WIDTH( $bits(virtq_desc_t)     ),
            .ADDRB_WIDTH( $clog2(DESC_BUF_DEPTH)  ),
            .INIT       ( 0                       ),
            .REG_EN     ( 0                       ),
            .RAM_MODE   ( RAM_MODE                ),//(   auto   ,   blk   ,   dist")
            .WRITE_MODE ( WRITE_MODE              ),
            .CHECK_ON   ( 1                       ),
            .CHECK_MODE ( "parity"                ) //("ecc","parity"   ECC_ON=0,            
         )u_desc_buf_ram(
            .rst            (rst                               ), 
            .clk            (clk                               ),
            .dina           (desc_buf_ram_dina[i]              ),
            .addra          (desc_buf_ram_addra                ),
            .wea            (desc_buf_ram_wren[i]              ),
            .addrb          (desc_buf_ram_addrb                ),
            .doutb          (desc_buf_ram_doutb[i]             ),
            .parity_ecc_err (desc_buf_ram_parity_ecc_err[i]    )
         );

         assign desc_buf_ram_dina[i] = desc_ddd[i];
      end
   endgenerate

   generate
      always @(*) begin
         for (int i = 0; i < DATA_WIDTH/$bits(virtq_desc_t); i++) begin
            if(i == 0)begin
               desc_buf_ram_parity_ecc_err_w = desc_buf_ram_parity_ecc_err[0];
            end else begin
               desc_buf_ram_parity_ecc_err_w = desc_buf_ram_parity_ecc_err_w | desc_buf_ram_parity_ecc_err[i];
            end
         end
      end
   endgenerate


   always @(posedge clk) begin
      if(rst)begin
         desc_buf_rd_rsp_vld <= 1'b0;
      end else begin
         desc_buf_rd_rsp_vld <= desc_buf_rd_req_vld;
         desc_buf_rd_req_addr_d <= desc_buf_rd_req_addr;
      end
   end

   assign desc_buf_ram_addrb = desc_buf_rd_req_addr[$clog2(DESC_BUF_DEPTH)+$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:$clog2(DATA_WIDTH/$bits(virtq_desc_t))];

   always @(*) begin
      for (int i = 0; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
         if(i == desc_buf_rd_req_addr_d[$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:0])begin
            desc_buf_rd_rsp_dat = desc_buf_ram_doutb[i];
         end
      end
   end

   //assign desc_buf_rd_rsp_dat = desc_buf_rd_req_addr_d[$clog2(DATA_WIDTH/$bits(virtq_desc_t))-1:0] desc_buf_ram_doutb[i];

   //flag_next, last_next-------------------------------------------
   generate
      for (i = 0; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
         assign desc_nxts[i]  = desc_ddd[i].flags.next;
         assign desc_indircts[i]  = desc_ddd[i].flags.indirect;
      end
   endgenerate

   assign flag_last_w = |(desc_buf_ram_wren & ~desc_nxts);//有chain尾巴
   assign flag_indirct_w = |(desc_buf_ram_wren & desc_indircts);

   always @(posedge clk) begin
      if(sop_ddd)begin
         flag_last            <= flag_last_w;
         flag_indirct         <= flag_indirct_w;
      end else begin
         flag_last            <= flag_last || flag_last_w;
         flag_indirct         <= flag_indirct || flag_indirct_w;
      end
   end

   always @(posedge clk) begin
      for (int i = 0; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
         if(i == DATA_WIDTH/$bits(virtq_desc_t) - 1)begin
            if(desc_buf_ram_wren[i])begin
               last_next <= desc_ddd[i].next;
            end
         end else begin
            if(desc_buf_ram_wren[i+:2] == 2'b01)begin
               last_next <= desc_ddd[i].next;
            end
         end
      end
   end

   always @(posedge clk) begin
      for (int i = 0; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
         if(desc_buf_ram_wren == (1 << i))begin
            indirct_addr <= desc_ddd[i].addr;
         end
      end
   end

   //vld_cnt
   always @(posedge clk) begin
      if(DATA_WIDTH/$bits(virtq_desc_t) == 2)begin
         if(sop_ddd)begin
            if(flag_indirct_w)begin
               vld_cnt <= desc_rd2rsp_ddd.valid_desc_cnt;
            end else begin
               vld_cnt <= desc_rd2rsp_ddd.valid_desc_cnt + desc_buf_ram_wren[0] + desc_buf_ram_wren[1];
            end
         end else begin
            vld_cnt <= vld_cnt + desc_buf_ram_wren[0] + desc_buf_ram_wren[1];
         end
      end else if(DATA_WIDTH/$bits(virtq_desc_t) == 4)begin
         case (desc_buf_ram_wren)
               4'b0001, 4'b0010, 4'b0100, 4'b1000:begin
                  if(sop_ddd)begin
                     if(flag_indirct_w)begin
                        vld_cnt <= desc_rd2rsp_ddd.valid_desc_cnt + 'h1;
                     end else begin
                        vld_cnt <= desc_rd2rsp_ddd.valid_desc_cnt;
                     end
                  end else begin
                     vld_cnt <= vld_cnt + 'h1;
                  end
               end
               4'b0011, 4'b0110, 4'b1100:begin
                  if(sop_ddd)begin
                     vld_cnt <= desc_rd2rsp_ddd.valid_desc_cnt + 'h2;
                  end else begin
                     vld_cnt <= vld_cnt + 'h2;
                  end
               end
               4'b0111, 4'b1110:begin
                  if(sop_ddd)begin
                     vld_cnt <= desc_rd2rsp_ddd.valid_desc_cnt + 'h3;
                  end else begin
                     vld_cnt <= vld_cnt + 'h3;
                  end
               end
               4'b1111:begin
                  if(sop_ddd)begin
                     vld_cnt <= desc_rd2rsp_ddd.valid_desc_cnt + 'h4;
                  end else begin
                     vld_cnt <= vld_cnt + 'h4;
                  end
               end
               default: begin
                  vld_cnt <= vld_cnt;
               end
         endcase
      end
   end

   //total_buf_length
   generate
      for (i = 0; i < DATA_WIDTH/$bits(virtq_desc_t);i++ ) begin
         always @(posedge clk) begin
            if(sop_dd)begin
               desc_len_ddd[i]    <= vld_desc[i] ? desc_dd[i].len : 'h0;
            end  else if(same_chain_d)begin
               desc_len_ddd[i]    <= vld_desc[i] ? desc_dd[i].len : 'h0;
            end else begin
               desc_len_ddd[i]    <= 'h0;
            end
         end
      end
   endgenerate



   always @(posedge clk) begin
      if(DATA_WIDTH/$bits(virtq_desc_t) == 2)begin
         indirct_desc_size <= desc_len_ddd[0][31:4] | desc_len_ddd[1][31:4];
         if(sop_ddd)begin
            if(flag_indirct_w)begin
               total_buf_length <= desc_rd2rsp_ddd.total_buf_length;
            end else begin
               total_buf_length <= desc_rd2rsp_ddd.total_buf_length + desc_len_ddd[0] + desc_len_ddd[1];
            end
         end else begin
            total_buf_length <= total_buf_length + desc_len_ddd[0] + desc_len_ddd[1];
         end
      end else if(DATA_WIDTH/$bits(virtq_desc_t) == 4)begin
         indirct_desc_size <= desc_len_ddd[0][31:4] | desc_len_ddd[1][31:4] | desc_len_ddd[2][31:4] | desc_len_ddd[3][31:4];
         if(sop_ddd)begin
            if(flag_indirct_w)begin
               total_buf_length <= desc_rd2rsp_ddd.total_buf_length;
            end else begin
               total_buf_length <= desc_rd2rsp_ddd.total_buf_length + desc_len_ddd[0] + desc_len_ddd[1] + desc_len_ddd[2] + desc_len_ddd[3];
            end
         end else begin
            total_buf_length <= total_buf_length + desc_len_ddd[0] + desc_len_ddd[1] + desc_len_ddd[2] + desc_len_ddd[3];
         end
      end
   end

   always_comb assert (DATA_WIDTH == 512 || DATA_WIDTH == 256) else
    $fatal(0,"The DATA_WIDTH parameter must be set to 256, 512.");

   always @(posedge clk) begin
      if(rst)begin
         info_ff_wren <= 1'b0;
      end else begin
         info_ff_wren <= eop_ddd;
      end
   end

   always @(posedge clk) begin
      vq_d           <= order_ff_dout.vq;
      vq_dd          <= vq_d;
      slot_id_d      <= order_ff_dout.slot_id;
      slot_id_dd     <= slot_id_d;
   end

   always @(posedge clk) begin
      pcie_err_dddd           <= pcie_err_ddd;
      cycle_flag              <= desc_rd2rsp_ddd.cycle_flag;
      qdepth                  <= desc_rd2rsp_ddd.qdepth;
      indirct_processing      <= desc_rd2rsp_ddd.indirct_processing;
      indirct_desc_size_old   <= desc_rd2rsp_ddd.indirct_desc_size;
      max_len                 <= order_ff_dout.max_len;
   end
   assign info_ff_din.vq = vq_d; 
   assign info_ff_din.slot_id = slot_id_d;
   assign info_ff_din.total_buf_length = total_buf_length;
   assign info_ff_din.next = flag_indirct ? 'h0 : last_next;
   assign info_ff_din.flag_last = flag_last && !flag_indirct;
   assign info_ff_din.indirct_addr = indirct_addr;
   assign info_ff_din.indirct_desc_size = indirct_processing ? indirct_desc_size_old : indirct_desc_size;
   assign info_ff_din.flag_indirct = flag_indirct;
   assign info_ff_din.indirct_processing = indirct_processing;
   assign info_ff_din.vld_cnt = vld_cnt;
   assign info_ff_din.cycle_flag = cycle_flag;
   assign info_ff_din.qdepth = qdepth;
   assign info_ff_din.max_len = max_len;

   assign info_ff_din.pcie_err = pcie_err_dddd;
   assign info_ff_din.indirct_desc_next_must_be_zero  = |indirct_desc_next_must_be_zero;
   assign info_ff_din.desc_zero_len                   = |desc_zero_len;
   assign info_ff_din.desc_buf_len_oversize           = |desc_buf_len_oversize;
   assign info_ff_din.indirct_nexted_desc             = |indirct_nexted_desc;
   assign info_ff_din.write_only_invalid              = |write_only_invalid;
   assign info_ff_din.unsupport_indirct               = |unsupport_indirct;
   yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(virtio_desc_eng_core_info_ff_t) ),
        .FIFO_DEPTH ( SLOT_NUM                    ),
        .CHECK_ON   ( 1                           ),
        .CHECK_MODE ( "parity"                    ),
        .DEPTH_PFULL( SLOT_NUM-8                  ),
        .RAM_MODE   ( "dist"                      ),
        .FIFO_MODE  ( "fwft"                      )
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

    assign info_rd_vld = !info_ff_empty;
    assign info_ff_rden = info_rd_vld && info_rd_rdy;
    assign info_rd_dat = info_ff_dout;

    yucca_sync_fifo #(
        .DATA_WIDTH ( $bits(virtio_desc_eng_core_rd_desc_order_t) ),
        .FIFO_DEPTH ( SLOT_NUM                    ),
        .CHECK_ON   ( 1                           ),
        .CHECK_MODE ( "parity"                    ),
        .DEPTH_PFULL( SLOT_NUM-8                  ),
        .RAM_MODE   ( "dist"                      ),
        .FIFO_MODE  ( "fwft"                      )
    ) u_order_ff (
        .clk             (clk                      ),
        .rst             (rst                      ),
        .wren            (order_ff_wren             ),
        .din             (order_ff_din              ),
        .full            (order_ff_full             ),
        .pfull           (order_ff_pfull            ),
        .overflow        (order_ff_overflow         ),
        .rden            (order_ff_rden             ),
        .dout            (order_ff_dout             ),
        .empty           (order_ff_empty            ),
        .pempty          (                          ),
        .underflow       (order_ff_underflow        ),
        .usedw           (                          ),
        .parity_ecc_err  (order_ff_parity_ecc_err   )
    );

   assign order_ff_wren = order_wr_vld;
   assign order_ff_din = order_wr_dat;

   assign order_ff_rden = eop_ddd;

   assign dfx_err = {
               desc_buf_ram_parity_ecc_err_w,
               info_ff_overflow,
               info_ff_underflow,
               info_ff_parity_ecc_err,
               order_ff_overflow,
               order_ff_underflow,
               order_ff_parity_ecc_err,
               order_ff_rden && order_ff_dout.vq                     != desc_rd2rsp_ddd.vq,
               order_ff_rden && order_ff_dout.slot_id                != desc_rd2rsp_ddd.slot_id,
               order_ff_rden && order_ff_dout.desc_buf_local_offset  != desc_rd2rsp_ddd.desc_buf_local_offset
            };
   generate
      for(i=0;i<$bits(dfx_err);i++)begin :db_err_i
               assert property (@(posedge clk) disable iff (rst) (~(dfx_err[i]===1'b1)))
                  else $fatal(0, $sformatf("%8t: %m ASSERTION_ERROR, dfx_err:%d, id:%d", $time, dfx_err[i], i));
      end
   endgenerate

   assign dfx_status = {
      order_ff_full,
      order_ff_empty,
      info_ff_full,
      info_ff_empty
   };


 endmodule