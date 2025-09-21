module axi_slave_simple #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH = 4
)(
    // Clock and Reset
    input  logic                    ACLK,
    input  logic                    ARESETn,
    
    // AXI4 Write Address Channel
    input  logic [ID_WIDTH-1:0]     AWID,
    input  logic [ADDR_WIDTH-1:0]   AWADDR,
    input  logic [7:0]              AWLEN,
    input  logic [2:0]              AWSIZE,
    input  logic [1:0]              AWBURST,
    input  logic                    AWVALID,
    output logic                    AWREADY,
    
    // AXI4 Write Data Channel
    input  logic [DATA_WIDTH-1:0]   WDATA,
    input  logic [DATA_WIDTH/8-1:0] WSTRB,
    input  logic                    WLAST,
    input  logic                    WVALID,
    output logic                    WREADY,
    
    // AXI4 Write Response Channel
    output logic [ID_WIDTH-1:0]     BID,
    output logic [1:0]              BRESP,
    output logic                    BVALID,
    input  logic                    BREADY,
    
    // AXI4 Read Address Channel
    input  logic [ID_WIDTH-1:0]     ARID,
    input  logic [ADDR_WIDTH-1:0]   ARADDR,
    input  logic [7:0]              ARLEN,
    input  logic [2:0]              ARSIZE,
    input  logic [1:0]              ARBURST,
    input  logic                    ARVALID,
    output logic                    ARREADY,
    
    // AXI4 Read Data Channel
    output logic [ID_WIDTH-1:0]     RID,
    output logic [DATA_WIDTH-1:0]   RDATA,
    output logic [1:0]              RRESP,
    output logic                    RLAST,
    output logic                    RVALID,
    input  logic                    RREADY
);

    // ================================================
    // Register File - Chỉ 4 thanh ghi đơn giản
    // ================================================
    logic [DATA_WIDTH-1:0] registers [0:3];
    
    // ================================================
    // Write Channel State Machine
    // ================================================
    typedef enum logic [2:0] {
        W_IDLE,
        W_ADDR,
        W_DATA, 
        W_RESP
    } write_state_t;
    
    write_state_t w_state, w_next_state;
    
    // Write transaction storage
    logic [ID_WIDTH-1:0]     stored_awid;
    logic [ADDR_WIDTH-1:0]   stored_awaddr;
    logic [7:0]              stored_awlen;
    logic [7:0]              w_beat_count;
    logic [ADDR_WIDTH-1:0]   w_current_addr;
    
    // Write state register
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            w_state <= W_IDLE;
            w_beat_count <= 0;
            w_current_addr <= 0;
            stored_awid <= 0;
            stored_awaddr <= 0;
            stored_awlen <= 0;
            for (int i = 0; i < 4; i++) begin
                registers[i] <= '0;
            end
        end else begin
            w_state <= w_next_state;
            
            case (w_state)
                W_IDLE: begin
                    // No action, just wait
                end
                
                W_ADDR: begin
                    if (AWVALID && AWREADY) begin
                        stored_awid <= AWID;
                        stored_awaddr <= AWADDR;
                        stored_awlen <= AWLEN;
                        w_beat_count <= AWLEN;
                        w_current_addr <= AWADDR;  // Initialize current address here
                    end
                end
                
                W_DATA: begin
                    if (WVALID && WREADY) begin
                        // Debug info
                        $display("[%0t] AXI Write: ADDR=0x%08h, REG_IDX=%0d, DATA=0x%08h", 
                                $time, w_current_addr, w_current_addr[3:2], WDATA);
                        
                        // Write to register file - handle each register separately
                        unique case (w_current_addr[3:2]) // Word address
                            2'b00: begin
                                if (WSTRB[0]) registers[0][7:0]   <= WDATA[7:0];
                                if (WSTRB[1]) registers[0][15:8]  <= WDATA[15:8];
                                if (WSTRB[2]) registers[0][23:16] <= WDATA[23:16];
                                if (WSTRB[3]) registers[0][31:24] <= WDATA[31:24];
                            end
                            2'b01: begin
                                if (WSTRB[0]) registers[1][7:0]   <= WDATA[7:0];
                                if (WSTRB[1]) registers[1][15:8]  <= WDATA[15:8];
                                if (WSTRB[2]) registers[1][23:16] <= WDATA[23:16];
                                if (WSTRB[3]) registers[1][31:24] <= WDATA[31:24];
                            end
                            2'b10: begin
                                if (WSTRB[0]) registers[2][7:0]   <= WDATA[7:0];
                                if (WSTRB[1]) registers[2][15:8]  <= WDATA[15:8];
                                if (WSTRB[2]) registers[2][23:16] <= WDATA[23:16];
                                if (WSTRB[3]) registers[2][31:24] <= WDATA[31:24];
                            end
                            2'b11: begin
                                if (WSTRB[0]) registers[3][7:0]   <= WDATA[7:0];
                                if (WSTRB[1]) registers[3][15:8]  <= WDATA[15:8];
                                if (WSTRB[2]) registers[3][23:16] <= WDATA[23:16];
                                if (WSTRB[3]) registers[3][31:24] <= WDATA[31:24];
                            end
                        endcase
                        
                        if (w_beat_count > 0) begin
                            w_beat_count <= w_beat_count - 1;
                            w_current_addr <= w_current_addr + 4; // Increment by 4 for word alignment
                        end
                    end
                end
            endcase
        end
    end
    
    // Write next state logic
    always_comb begin
        w_next_state = w_state;
        
        case (w_state)
            W_IDLE: begin
                if (AWVALID) 
                    w_next_state = W_ADDR;
            end
            
            W_ADDR: begin
                if (AWVALID && AWREADY) 
                    w_next_state = W_DATA;
            end
            
            W_DATA: begin
                if (WVALID && WREADY && WLAST) 
                    w_next_state = W_RESP;
            end
            
            W_RESP: begin
                if (BVALID && BREADY) 
                    w_next_state = W_IDLE;
            end
        endcase
    end
    
    // Write channel outputs
    always_comb begin
        AWREADY = (w_state == W_ADDR);
        WREADY  = (w_state == W_DATA);
        BVALID  = (w_state == W_RESP);
        BID     = stored_awid;
        BRESP   = 2'b00; // OKAY
    end
    
    // ================================================
    // Read Channel State Machine
    // ================================================
    typedef enum logic [2:0] {
        R_IDLE,
        R_ADDR,
        R_DATA
    } read_state_t;
    
    read_state_t r_state, r_next_state;
    
    // Read transaction storage
    logic [ID_WIDTH-1:0]     stored_arid;
    logic [ADDR_WIDTH-1:0]   stored_araddr;
    logic [7:0]              stored_arlen;
    logic [7:0]              r_beat_count;
    logic [ADDR_WIDTH-1:0]   r_current_addr;
    
    // Read state register
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            r_state <= R_IDLE;
            r_beat_count <= 0;
            r_current_addr <= 0;
            stored_arid <= 0;
            stored_araddr <= 0;
            stored_arlen <= 0;
        end else begin
            r_state <= r_next_state;
            
            case (r_state)
                R_IDLE: begin
                    // No action, just wait
                end
                
                R_ADDR: begin
                    if (ARVALID && ARREADY) begin
                        stored_arid <= ARID;
                        stored_araddr <= ARADDR;
                        stored_arlen <= ARLEN;
                        r_beat_count <= ARLEN;
                        r_current_addr <= ARADDR;  // Initialize current address here
                    end
                end
                
                R_DATA: begin
                    if (RVALID && RREADY) begin
                        if (r_beat_count > 0) begin
                            r_beat_count <= r_beat_count - 1;
                            r_current_addr <= r_current_addr + 4;
                        end
                    end
                end
            endcase
        end
    end
    
    // Read next state logic
    always_comb begin
        r_next_state = r_state;
        
        case (r_state)
            R_IDLE: begin
                if (ARVALID) 
                    r_next_state = R_ADDR;
            end
            
            R_ADDR: begin
                if (ARVALID && ARREADY) 
                    r_next_state = R_DATA;
            end
            
            R_DATA: begin
                if (RVALID && RREADY && RLAST) 
                    r_next_state = R_IDLE;
            end
        endcase
    end
    
    // Read channel outputs
    always_comb begin
        ARREADY = (r_state == R_ADDR);
        RVALID  = (r_state == R_DATA);
        RID     = stored_arid;
        RLAST   = (r_beat_count == 0);
        RRESP   = 2'b00; // OKAY
        
        // Read data from register file
        unique case (r_current_addr[3:2])
            2'b00:   RDATA = registers[0];
            2'b01:   RDATA = registers[1];
            2'b10:   RDATA = registers[2];
            2'b11:   RDATA = registers[3];
            default: RDATA = '0;
        endcase
    end

endmodule