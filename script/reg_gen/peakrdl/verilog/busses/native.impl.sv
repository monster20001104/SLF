logic [ADDR_WIDTH-1:0]      csr_if_addr;
logic [DATA_WIDTH-1:0]      csr_if_wdata;
logic [DATA_WIDTH-1:0]      csr_if_rdata;
logic [DATA_WIDTH/8-1:0]    csr_if_wmask;


logic [ADDR_WIDTH-1:0]      addr;
logic [DATA_WIDTH-1:0]      rdata;
logic [DATA_WIDTH/8-1:0]    wmask;

// convert byte mask to bit mask
always @(*) begin
    int byte_idx;
    for (byte_idx = 0; byte_idx < DATA_WIDTH/8; byte_idx+=1) begin
        sw_mask[8*(byte_idx+1)-1 -: 8] = {8{wmask[byte_idx]}};
    end
end

enum logic [3:0]  { 
    IDLE     = 4'b0001,
    WRITE    = 4'b0010,
    READ     = 4'b0100,
    READ_RSP = 4'b1000
} cstat, nstat;

always @(posedge clk) begin
    if(rst)begin
        cstat <= IDLE;
    end else begin
        cstat <= nstat;
    end
end

always @(*)begin
    nstat = cstat;
    case (cstat)
        IDLE: begin
            if(csr_if.ready && csr_if.valid)begin
                if(!csr_if.read)begin
                    nstat = WRITE;
                end else begin
                    nstat = READ;
                end
            end
        end
        WRITE:begin
            nstat = IDLE;
        end
        READ:begin
            nstat = READ_RSP;
        end
        READ_RSP:begin
            if(csr_if.rready)begin
                nstat = IDLE;
            end
        end
        default:begin
            nstat = cstat;
        end
    endcase
end

always @(posedge clk) begin
    if(cstat == IDLE)begin
        csr_if_addr   <= csr_if.addr;
        csr_if_wdata  <= csr_if.wdata;
        csr_if_wmask  <= csr_if.wmask;
    end
end


assign addr     = csr_if_addr;
assign sw_wr    = cstat == WRITE;
assign sw_rd    = cstat == READ;
assign sw_wdata = csr_if_wdata;
assign wmask    = csr_if_wmask;
assign rdata    = sw_rdata;

always @(posedge clk) begin
    if(cstat == READ)begin
        csr_if_rdata <= rdata;
    end
end

assign csr_if.ready   = cstat == IDLE;
assign csr_if.rvalid  = cstat == READ_RSP;
assign csr_if.rdata   = csr_if_rdata;