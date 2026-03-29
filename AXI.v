`timescale 1ns / 1ps

// =====================================================================
// Module Name: axi4_full_master
// Description: 标准全功能 AXI4 主设备，支持突发传输 (Burst Transfer)
// =====================================================================
module axi4_full_master (
    input  wire        clk,
    input  wire        rst_n,

    // ---------------------------------------------------------
    // 1. 用户层接口 (供你的业务模块/FIFO调用)
    // ---------------------------------------------------------
    // --- 写用户接口 ---
    input  wire        user_wr_req,    // 触发突发写
    input  wire [31:0] user_wr_addr,   // 突发写的起始物理地址
    input  wire [7:0]  user_wr_len,    // 突发长度 (注意：AXI规定实际拍数是 len + 1)
    input  wire [31:0] user_wr_data,   // 用户源源不断提供的数据 (比如连着一个FIFO的dout)
    output wire        user_wr_ren,    // 告诉用户："我拿走了一个数据，请给下一个" (连FIFO的rd_en)
    output reg         user_wr_done,   // 整个Burst写完的脉冲

    // --- 读用户接口 ---
    input  wire        user_rd_req,    // 触发突发读
    input  wire [31:0] user_rd_addr,   // 突发读的起始物理地址
    input  wire [7:0]  user_rd_len,    // 突发读的长度 (实际拍数 = len + 1)
    output wire [31:0] user_rd_data,   // 读回来的一连串数据
    output wire        user_rd_wen,    // 告诉用户："这是一个有效数据，快存下来" (连FIFO的wr_en)
    output reg         user_rd_done,   // 整个Burst读完的脉冲

    // ---------------------------------------------------------
    // 2. 标准 AXI4 物理总线接口
    // ---------------------------------------------------------
    // AW 通道 (写地址)
    output reg  [31:0] m_axi_awaddr,
    output reg  [7:0]  m_axi_awlen,    // 新增：Burst 长度 (0代表传1拍，255代表传256拍)
    output wire [2:0]  m_axi_awsize,   // 新增：每拍几个字节 (3'b010 = 4 Bytes)
    output wire [1:0]  m_axi_awburst,  // 新增：Burst 类型 (2'b01 = INCR 递增地址)
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,

    // W 通道 (写数据)
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wlast,    // 新增：Burst 的最后一拍标志
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,

    // B 通道 (写响应)
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,

    // AR 通道 (读地址)
    output reg  [31:0] m_axi_araddr,
    output reg  [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,

    // R 通道 (读数据)
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,    // 新增：读 Burst 的最后一拍标志
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready
);

    // =========================================================
    // 全局静态 AXI 属性配置
    // =========================================================
    // 3'b010 表示每拍数据是 4 字节 (32-bit 总线)
    assign m_axi_awsize  = 3'b010; 
    assign m_axi_arsize  = 3'b010; 
    // 2'b01 表示 INCR (地址自动递增模式，每次加 4 字节)
    assign m_axi_awburst = 2'b01;  
    assign m_axi_arburst = 2'b01;  
    // 永远写满 4 个字节
    assign m_axi_wstrb   = 4'b1111;

    // =========================================================
    // 【模块 1】：突发写操作 (Burst Write) 控制逻辑
    // =========================================================
    localparam WR_IDLE   = 2'd0;
    localparam WR_ADDR   = 2'd1; // 发送地址
    localparam WR_DATA   = 2'd2; // 连续发送多拍数据
    localparam WR_RESP   = 2'd3; // 等待回执

    reg [1:0] wr_state;
    reg [7:0] w_beat_cnt; // 记录当前发到了第几拍数据

    // 用户层数据穿透连接：将用户的源数据直接接到 AXI WDATA 上
    assign m_axi_wdata = user_wr_data;
    
    // 生成 WLAST：当已发送拍数等于总长度时，就是最后一拍 (EOP)
    assign m_axi_wlast = (w_beat_cnt == m_axi_awlen);
    
    // W通道握手成功的标志：发出去了一拍有效数据
    wire w_handshake = m_axi_wvalid && m_axi_wready;
    
    // 告诉用户更新数据：当W通道握手成功时，让用户准备下一个数据
    assign user_wr_ren = w_handshake;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            user_wr_done  <= 1'b0;
            w_beat_cnt    <= 8'd0;
        end else begin
            user_wr_done <= 1'b0;

            case (wr_state)
                WR_IDLE: begin
                    if (user_wr_req) begin
                        m_axi_awaddr  <= user_wr_addr;
                        m_axi_awlen   <= user_wr_len; // 设定一共要连发多少拍
                        m_axi_awvalid <= 1'b1;        // 举起写地址的牌子
                        wr_state      <= WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0; // 地址交接成功
                        m_axi_wvalid  <= 1'b1; // 立刻举起写数据的牌子，开始 Burst
                        w_beat_cnt    <= 8'd0; // 拍数清零
                        wr_state      <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    // 只要握手成功，拍数就加1。数据会像流水一样流过去
                    if (w_handshake) begin
                        if (m_axi_wlast) begin
                            // 最后一拍也发完了！收起 Valid 牌子
                            m_axi_wvalid <= 1'b0;
                            m_axi_bready <= 1'b1; // 准备接听回执
                            wr_state     <= WR_RESP;
                        end else begin
                            // 还没发完，继续累加计数器。
                            // m_axi_wvalid 保持为 1，连续发送！
                            w_beat_cnt <= w_beat_cnt + 1'b1;
                        end
                    end
                end

                WR_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        user_wr_done <= 1'b1; // 整个连发过程彻底结束
                        wr_state     <= WR_IDLE;
                    end
                end
            endcase
        end
    end

    // =========================================================
    // 【模块 2】：突发读操作 (Burst Read) 控制逻辑
    // =========================================================
    localparam RD_IDLE   = 2'd0;
    localparam RD_ADDR   = 2'd1;
    localparam RD_DATA   = 2'd2;

    reg [1:0] rd_state;

    // R通道握手成功：收到了一拍有效数据
    wire r_handshake = m_axi_rvalid && m_axi_rready;

    // 将收到的数据和有效标志直接透传给用户层
    assign user_rd_data = m_axi_rdata;
    assign user_rd_wen  = r_handshake;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            user_rd_done  <= 1'b0;
        end else begin
            user_rd_done <= 1'b0;

            case (rd_state)
                RD_IDLE: begin
                    if (user_rd_req) begin
                        m_axi_araddr  <= user_rd_addr;
                        m_axi_arlen   <= user_rd_len; // 告诉Slave我要读多少拍
                        m_axi_arvalid <= 1'b1;
                        rd_state      <= RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0; // 地址交接成功
                        m_axi_rready  <= 1'b1; // 敞开大门，准备迎接一长串数据
                        rd_state      <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (r_handshake) begin
                        // 读操作非常省心，Slave 会通过 rlast 告诉我们是不是最后一个
                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0; // 关门
                            user_rd_done <= 1'b1; // 连读结束
                            rd_state     <= RD_IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule