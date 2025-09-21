module tb_axi_slave_simple;

    // Parameters
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter ID_WIDTH = 4;
    parameter CLK_PERIOD = 10;

    // Clock and Reset
    logic ACLK;
    logic ARESETn;
    
    // AXI4 Write Address Channel
    logic [ID_WIDTH-1:0]     AWID;
    logic [ADDR_WIDTH-1:0]   AWADDR;
    logic [7:0]              AWLEN;
    logic [2:0]              AWSIZE;
    logic [1:0]              AWBURST;
    logic                    AWVALID;
    logic                    AWREADY;
    
    // AXI4 Write Data Channel
    logic [DATA_WIDTH-1:0]   WDATA;
    logic [DATA_WIDTH/8-1:0] WSTRB;
    logic                    WLAST;
    logic                    WVALID;
    logic                    WREADY;
    
    // AXI4 Write Response Channel
    logic [ID_WIDTH-1:0]     BID;
    logic [1:0]              BRESP;
    logic                    BVALID;
    logic                    BREADY;
    
    // AXI4 Read Address Channel
    logic [ID_WIDTH-1:0]     ARID;
    logic [ADDR_WIDTH-1:0]   ARADDR;
    logic [7:0]              ARLEN;
    logic [2:0]              ARSIZE;
    logic [1:0]              ARBURST;
    logic                    ARVALID;
    logic                    ARREADY;
    
    // AXI4 Read Data Channel
    logic [ID_WIDTH-1:0]     RID;
    logic [DATA_WIDTH-1:0]   RDATA;
    logic [1:0]              RRESP;
    logic                    RLAST;
    logic                    RVALID;
    logic                    RREADY;

    // Test variables
    int error_count = 0;
    int test_count = 0;

    // ================================================
    // DUT Instantiation
    // ================================================
    axi_slave_simple #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .AWID(AWID),
        .AWADDR(AWADDR),
        .AWLEN(AWLEN),
        .AWSIZE(AWSIZE),
        .AWBURST(AWBURST),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        .WDATA(WDATA),
        .WSTRB(WSTRB),
        .WLAST(WLAST),
        .WVALID(WVALID),
        .WREADY(WREADY),
        .BID(BID),
        .BRESP(BRESP),
        .BVALID(BVALID),
        .BREADY(BREADY),
        .ARID(ARID),
        .ARADDR(ARADDR),
        .ARLEN(ARLEN),
        .ARSIZE(ARSIZE),
        .ARBURST(ARBURST),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        .RID(RID),
        .RDATA(RDATA),
        .RRESP(RRESP),
        .RLAST(RLAST),
        .RVALID(RVALID),
        .RREADY(RREADY)
    );

    // ================================================
    // Clock Generation
    // ================================================
    initial begin
        ACLK = 0;
        forever #(CLK_PERIOD/2) ACLK = ~ACLK;
    end

    // ================================================
    // Reset Generation
    // ================================================
    initial begin
        ARESETn = 0;
        #(CLK_PERIOD * 5);
        ARESETn = 1;
        $display("[%0t] Reset deasserted", $time);
    end

    // ================================================
    // Initialize Signals
    // ================================================
    initial begin
        // Initialize write address channel
        AWID = 0;
        AWADDR = 0;
        AWLEN = 0;
        AWSIZE = 3'b010; // 4 bytes
        AWBURST = 2'b01; // INCR
        AWVALID = 0;
        
        // Initialize write data channel
        WDATA = 0;
        WSTRB = 4'b1111;
        WLAST = 0;
        WVALID = 0;
        
        // Initialize write response channel
        BREADY = 0;
        
        // Initialize read address channel
        ARID = 0;
        ARADDR = 0;
        ARLEN = 0;
        ARSIZE = 3'b010; // 4 bytes
        ARBURST = 2'b01; // INCR
        ARVALID = 0;
        
        // Initialize read data channel
        RREADY = 0;
    end

    // ================================================
    // Test Tasks
    // ================================================
    
    // AXI Write Task
    task automatic axi_write(
        input logic [ID_WIDTH-1:0]     id,
        input logic [ADDR_WIDTH-1:0]   addr,
        input logic [7:0]              len,
        input logic [DATA_WIDTH-1:0]   data[$]
    );
        int beat;
        
        $display("[%0t] Starting AXI Write: ID=%0d, ADDR=0x%08h, LEN=%0d", 
                 $time, id, addr, len);
        
        // Write Address Phase
        @(posedge ACLK);
        AWID <= id;
        AWADDR <= addr;
        AWLEN <= len;
        AWVALID <= 1;
        
        // Wait for AWREADY
        wait(AWREADY);
        @(posedge ACLK);
        AWVALID <= 0;
        
        // Write Data Phase
        for (beat = 0; beat <= len; beat++) begin
            @(posedge ACLK);
            WDATA <= data[beat];
            WLAST <= (beat == len);
            WVALID <= 1;
            
            // Wait for WREADY
            wait(WREADY);
            $display("[%0t] Write Beat %0d: DATA=0x%08h", $time, beat, data[beat]);
        end
        
        @(posedge ACLK);
        WVALID <= 0;
        WLAST <= 0;
        
        // Write Response Phase
        BREADY <= 1;
        wait(BVALID);
        @(posedge ACLK);
        BREADY <= 0;
        
        if (BRESP == 2'b00 && BID == id) begin
            $display("[%0t] Write Response OK: BID=%0d", $time, BID);
        end else begin
            $display("[%0t] Write Response ERROR: BID=%0d, BRESP=%0b", $time, BID, BRESP);
            error_count++;
        end
        
    endtask
    
    // AXI Read Task
    task automatic axi_read(
        input logic [ID_WIDTH-1:0]     id,
        input logic [ADDR_WIDTH-1:0]   addr,
        input logic [7:0]              len,
        output logic [DATA_WIDTH-1:0]  data[$]
    );
        int beat;
        logic [DATA_WIDTH-1:0] read_data;
        
        $display("[%0t] Starting AXI Read: ID=%0d, ADDR=0x%08h, LEN=%0d", 
                 $time, id, addr, len);
        
        // Clear output queue
        data = {};
        
        // Read Address Phase
        @(posedge ACLK);
        ARID <= id;
        ARADDR <= addr;
        ARLEN <= len;
        ARVALID <= 1;
        
        // Wait for ARREADY
        wait(ARREADY);
        @(posedge ACLK);
        ARVALID <= 0;
        
        // Read Data Phase
        RREADY <= 1;
        for (beat = 0; beat <= len; beat++) begin
            wait(RVALID);
            read_data = RDATA;
            data.push_back(read_data);
            
            $display("[%0t] Read Beat %0d: DATA=0x%08h, LAST=%0b", 
                     $time, beat, read_data, RLAST);
            
            @(posedge ACLK);
            if (RLAST) break;
        end
        RREADY <= 0;
        
        if (RRESP == 2'b00 && RID == id) begin
            $display("[%0t] Read Response OK: RID=%0d", $time, RID);
        end else begin
            $display("[%0t] Read Response ERROR: RID=%0d, RRESP=%0b", $time, RID, RRESP);
            error_count++;
        end
        
    endtask
    
    // Compare Data Task
    task automatic compare_data(
        input logic [DATA_WIDTH-1:0] expected[$],
        input logic [DATA_WIDTH-1:0] actual[$],
        input string test_name
    );
        test_count++;
        
        if (expected.size() != actual.size()) begin
            $display("[%0t] %s FAILED: Size mismatch - Expected=%0d, Actual=%0d", 
                     $time, test_name, expected.size(), actual.size());
            error_count++;
            return;
        end
        
        for (int i = 0; i < expected.size(); i++) begin
            if (expected[i] !== actual[i]) begin
                $display("[%0t] %s FAILED: Data[%0d] - Expected=0x%08h, Actual=0x%08h", 
                         $time, test_name, i, expected[i], actual[i]);
                error_count++;
                return;
            end
        end
        
        $display("[%0t] %s PASSED", $time, test_name);
    endtask

    // ================================================
    // Main Test Sequence
    // ================================================
    initial begin
        logic [DATA_WIDTH-1:0] write_data[$];
        logic [DATA_WIDTH-1:0] read_data[$];
        
        $display("==========================================");
        $display("AXI Slave Testbench Started");
        $display("==========================================");
        
        // Wait for reset
        wait(ARESETn);
        repeat(5) @(posedge ACLK);
        
        // ================================================
        // Test 1: Single Write and Read
        // ================================================
        $display("\n--- Test 1: Single Write and Read ---");
        
        write_data = {32'h12345678};
        axi_write(.id(4'h1), .addr(32'h00000000), .len(8'h00), .data(write_data));
        
        axi_read(.id(4'h2), .addr(32'h00000000), .len(8'h00), .data(read_data));
        compare_data(write_data, read_data, "Test 1");
        
        // ================================================
        // Test 2: Multiple Register Write and Read
        // ================================================
        $display("\n--- Test 2: Multiple Register Access ---");
        
        // Write to register 1
        write_data = {32'hAABBCCDD};
        axi_write(.id(4'h3), .addr(32'h00000004), .len(8'h00), .data(write_data));
        
        // Write to register 2
        write_data = {32'h11223344};
        axi_write(.id(4'h4), .addr(32'h00000008), .len(8'h00), .data(write_data));
        
        // Read register 1
        axi_read(.id(4'h5), .addr(32'h00000004), .len(8'h00), .data(read_data));
        write_data = {32'hAABBCCDD};
        compare_data(write_data, read_data, "Test 2a - Reg1");
        
        // Read register 2
        axi_read(.id(4'h6), .addr(32'h00000008), .len(8'h00), .data(read_data));
        write_data = {32'h11223344};
        compare_data(write_data, read_data, "Test 2b - Reg2");
        
        // ================================================
        // Test 3: Burst Write and Read
        // ================================================
        $display("\n--- Test 3: Burst Write and Read (4 beats) ---");
        
        write_data = {32'hDEADBEEF, 32'hCAFEBABE, 32'h12345678, 32'h87654321};
        axi_write(.id(4'h7), .addr(32'h00000000), .len(8'h03), .data(write_data));
        
        axi_read(.id(4'h8), .addr(32'h00000000), .len(8'h03), .data(read_data));
        compare_data(write_data, read_data, "Test 3");
        
        // ================================================
        // Test 4: Partial Write (WSTRB test)
        // ================================================
        $display("\n--- Test 4: Partial Write Test ---");
        
        // Write full word first
        write_data = {32'hFFFFFFFF};
        axi_write(.id(4'h9), .addr(32'h0000000C), .len(8'h00), .data(write_data));
        
        // Partial write - only lower 2 bytes
        @(posedge ACLK);
        AWID <= 4'hA;
        AWADDR <= 32'h0000000C;
        AWLEN <= 8'h00;
        AWVALID <= 1;
        wait(AWREADY);
        @(posedge ACLK);
        AWVALID <= 0;
        
        @(posedge ACLK);
        WDATA <= 32'h12345678;
        WSTRB <= 4'b0011; // Only lower 2 bytes
        WLAST <= 1;
        WVALID <= 1;
        wait(WREADY);
        @(posedge ACLK);
        WVALID <= 0;
        WLAST <= 0;
        
        BREADY <= 1;
        wait(BVALID);
        @(posedge ACLK);
        BREADY <= 0;
        
        // Read back and check
        axi_read(.id(4'hB), .addr(32'h0000000C), .len(8'h00), .data(read_data));
        write_data = {32'hFFFF5678}; // Upper 2 bytes unchanged, lower 2 bytes updated
        compare_data(write_data, read_data, "Test 4 - Partial Write");
        
        // ================================================
        // Test Results
        // ================================================
        repeat(10) @(posedge ACLK);
        
        $display("\n==========================================");
        $display("Test Summary:");
        $display("Total Tests: %0d", test_count);
        $display("Errors: %0d", error_count);
        
        if (error_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("TESTS FAILED!");
        end
        $display("==========================================");
        
        $finish;
    end
    
    // ================================================
    // Timeout Watchdog
    // ================================================
    initial begin
        #(CLK_PERIOD * 10000);
        $display("TIMEOUT - Testbench ran too long");
        $finish;
    end
    
    // ================================================
    // Waveform Dump
    // ================================================


endmodule