`timescale 1ns/1ps

module tb_ahb_slave;

    // Clock and Reset
    logic        HCLK;
    logic        HRESETn;
    
    // AHB Master Interface
    logic [31:0] HADDR;
    logic        HWRITE;
    logic [2:0]  HSIZE;
    logic [2:0]  HBURST;
    logic [3:0]  HPROT;
    logic [1:0]  HTRANS;
    logic        HMASTLOCK;
    logic        HSEL;
    logic [31:0] HWDATA;
    wire [31:0]  HRDATA;
    wire         HREADY;
    wire         HRESP;
    logic [3:0]  HWSTRB;
    
    // Register Interface
    wire [31:0]  tdr_o, lcr_o, ocr_o, fcr_o, ier_o, hcr_o;
    logic [31:0] rdr_i, lsr_i, iir_i;
    
    // Test control
    integer test_count = 0;
    integer error_count = 0;
    logic [31:0] expected_data;
    
    // AHB Transfer Types
    localparam [1:0] IDLE    = 2'b00;
    localparam [1:0] BUSY    = 2'b01;
    localparam [1:0] NONSEQ  = 2'b10;
    localparam [1:0] SEQ     = 2'b11;
    
    // AHB Burst Types
    localparam [2:0] SINGLE  = 3'b000;
    localparam [2:0] INCR    = 3'b001;
    localparam [2:0] WRAP4   = 3'b010;
    localparam [2:0] INCR4   = 3'b011;
    localparam [2:0] WRAP8   = 3'b100;
    localparam [2:0] INCR8   = 3'b101;
    localparam [2:0] WRAP16  = 3'b110;
    localparam [2:0] INCR16  = 3'b111;
    
    // AHB Transfer Sizes
    localparam [2:0] SIZE_BYTE = 3'b000;
    localparam [2:0] SIZE_HWORD = 3'b001;
    localparam [2:0] SIZE_WORD = 3'b010;
    
    // Register Addresses
    localparam [31:0] ADDR_TDR = 32'h00000000;
    localparam [31:0] ADDR_RDR = 32'h00000004;
    localparam [31:0] ADDR_LCR = 32'h00000008;
    localparam [31:0] ADDR_OCR = 32'h0000000C;
    localparam [31:0] ADDR_LSR = 32'h00000010;
    localparam [31:0] ADDR_FCR = 32'h00000014;
    localparam [31:0] ADDR_IER = 32'h00000018;
    localparam [31:0] ADDR_IIR = 32'h0000001C;
    localparam [31:0] ADDR_HCR = 32'h00000020;
    
    // DUT Instantiation
    ahb_slave dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HADDR(HADDR),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HTRANS(HTRANS),
        .HMASTLOCK(HMASTLOCK),
        .HSEL(HSEL),
        .HWDATA(HWDATA),
        .HRDATA(HRDATA),
        .HREADY(HREADY),
        .HRESP(HRESP),
        .HWSTRB(HWSTRB),
        .tdr_o(tdr_o),
        .lcr_o(lcr_o),
        .ocr_o(ocr_o),
        .fcr_o(fcr_o),
        .ier_o(ier_o),
        .hcr_o(hcr_o),
        .rdr_i(rdr_i),
        .lsr_i(lsr_i),
        .iir_i(iir_i)
    );
    
    // Clock generation
    initial begin
        HCLK = 0;
        forever #5 HCLK = ~HCLK; // 100MHz clock
    end
    
    // Initialize input registers
    initial begin
        rdr_i = 32'hA5A5A5A5;
        lsr_i = 32'h12345678;
        iir_i = 32'h87654321;
    end
    
    // Test stimulus
    initial begin
        $display("========================================");
        $display("Starting AHB Slave Testbench");
        $display("========================================");
        
        // Initialize signals
        reset_bus();
        
        // Wait for reset deassertion
        repeat(5) @(posedge HCLK);
        
        // Test 1: Basic Single Transfers
        $display("\n--- Test 1: Basic Single Transfers ---");
        test_single_write(ADDR_TDR, 32'hDEADBEEF, SIZE_WORD, 4'hF);
        test_single_read(ADDR_TDR, 32'hDEADBEEF, SIZE_WORD);
        
        test_single_write(ADDR_LCR, 32'h12345678, SIZE_WORD, 4'hF);
        test_single_read(ADDR_LCR, 32'h12345678, SIZE_WORD);
        
        // Test 2: Byte-level transfers
        $display("\n--- Test 2: Byte-level Transfers ---");
        test_single_write(ADDR_OCR, 32'h000000AA, SIZE_BYTE, 4'h1);
        test_single_write(ADDR_OCR + 1, 32'h0000BB00, SIZE_BYTE, 4'h2);
        test_single_write(ADDR_OCR + 2, 32'h00CC0000, SIZE_BYTE, 4'h4);
        test_single_write(ADDR_OCR + 3, 32'hDD000000, SIZE_BYTE, 4'h8);
        test_single_read(ADDR_OCR, 32'hDDCCBBAA, SIZE_WORD);
        
        // Test 3: Half-word transfers
        $display("\n--- Test 3: Half-word Transfers ---");
        test_single_write(ADDR_FCR, 32'h00001234, SIZE_HWORD, 4'h3);
        test_single_write(ADDR_FCR + 2, 32'h56780000, SIZE_HWORD, 4'hC);
        test_single_read(ADDR_FCR, 32'h56781234, SIZE_WORD);
        
        // Test 4: Read-only registers
        $display("\n--- Test 4: Read-only Register Tests ---");
        test_single_read(ADDR_RDR, 32'hA5A5A5A5, SIZE_WORD); // Should return rdr_i
        test_single_read(ADDR_LSR, 32'h12345678, SIZE_WORD); // Should return lsr_i
        test_single_read(ADDR_IIR, 32'h87654321, SIZE_WORD); // Should return iir_i
        
        // Test 5: Error conditions
        $display("\n--- Test 5: Error Condition Tests ---");
        test_error_transfer(32'h00000100, 32'h12345678, SIZE_WORD, 4'hF); // Invalid address
        test_error_transfer(ADDR_TDR + 1, 32'h12345678, SIZE_WORD, 4'hF); // Misaligned word
        test_error_transfer(ADDR_TDR + 1, 32'h12345678, SIZE_HWORD, 4'h3); // Misaligned half-word
        test_error_transfer(ADDR_RDR, 32'h12345678, SIZE_WORD, 4'hF); // Write to read-only
        
        // Test 6: INCR4 Burst
        $display("\n--- Test 6: INCR4 Burst Transfer ---");
        test_incr4_burst();
        
        // Test 7: WRAP4 Burst
        $display("\n--- Test 7: WRAP4 Burst Transfer ---");
        test_wrap4_burst();
        
        // Test 8: Master Lock
        $display("\n--- Test 8: Master Lock Transfer ---");
        test_master_lock();
        
        // Test Summary
        $display("\n========================================");
        $display("Test Summary:");
        $display("Total Tests: %0d", test_count);
        $display("Errors: %0d", error_count);
        if (error_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");
        $display("========================================");
        
        $finish;
    end
    
    // Task: Reset bus to idle state
    task reset_bus();
        HRESETn = 0;
        HADDR = 32'h0;
        HWRITE = 1'b0;
        HSIZE = SIZE_WORD;
        HBURST = SINGLE;
        HPROT = 4'h0;
        HTRANS = IDLE;
        HMASTLOCK = 1'b0;
        HSEL = 1'b0;
        HWDATA = 32'h0;
        HWSTRB = 4'h0;
        
        repeat(3) @(posedge HCLK);
        HRESETn = 1;
        repeat(2) @(posedge HCLK);
    endtask
    
    // Task: Single Write Transfer
    task test_single_write(
        input [31:0] addr,
        input [31:0] data,
        input [2:0] size,
        input [3:0] strb
    );
        test_count++;
        $display("Test %0d: Write 0x%08h to address 0x%08h (size=%0d)", test_count, data, addr, size);
        
        // Address Phase
        @(posedge HCLK);
        HADDR = addr;
        HWRITE = 1'b1;
        HSIZE = size;
        HBURST = INCR;
        HTRANS = NONSEQ;
        HSEL = 1'b1;
        HWSTRB = strb;
        
        // Data Phase
        @(posedge HCLK);
        HTRANS = IDLE;
        HSEL = 1'b0;
        HWDATA = data;
        
        // Wait for completion
        wait(HREADY);
        @(posedge HCLK);
        
        if (HRESP) begin
            $display("ERROR: Unexpected error response for write");
            error_count++;
        end else begin
            $display("PASS: Write completed successfully");
        end
    endtask
    
    // Task: Single Read Transfer
    task test_single_read(
        input [31:0] addr,
        input [31:0] expected,
        input [2:0] size
    );
        test_count++;
        $display("Test %0d: Read from address 0x%08h, expect 0x%08h", test_count, addr, expected);
        
        // Address Phase
        @(posedge HCLK);
        HADDR = addr;
        HWRITE = 1'b0;
        HSIZE = size;
        HBURST = SINGLE;
        HTRANS = NONSEQ;
        HSEL = 1'b1;
        
        // Data Phase
        @(posedge HCLK);
        HTRANS = IDLE;
        HSEL = 1'b0;
        
        // Wait for completion
        wait(HREADY);
        
        if (HRESP) begin
            $display("ERROR: Unexpected error response for read");
            error_count++;
        end else if (HRDATA !== expected) begin
            $display("ERROR: Read data mismatch. Got 0x%08h, expected 0x%08h", HRDATA, expected);
            error_count++;
        end else begin
            $display("PASS: Read data correct");
        end
        
        @(posedge HCLK);
    endtask
    
    // Task: Test error transfer
    task test_error_transfer(
        input [31:0] addr,
        input [31:0] data,
        input [2:0] size,
        input [3:0] strb
    );
        test_count++;
        $display("Test %0d: Error test - Write 0x%08h to address 0x%08h", test_count, data, addr);
        
        // Address Phase
        @(posedge HCLK);
        HADDR = addr;
        HWRITE = 1'b1;
        HSIZE = size;
        HBURST = SINGLE;
        HTRANS = NONSEQ;
        HSEL = 1'b1;
        HWSTRB = strb;
        
        // Data Phase
        @(posedge HCLK);
        HTRANS = IDLE;
        HSEL = 1'b0;
        HWDATA = data;
        
        // Wait for completion
        wait(HREADY);
        @(posedge HCLK);
        
        if (!HRESP) begin
            $display("ERROR: Expected error response but got OKAY");
            error_count++;
        end else begin
            $display("PASS: Error correctly detected");
        end
    endtask
    
    // Task: INCR4 Burst Test
    task test_incr4_burst();
        logic [31:0] burst_data [4] = '{32'h11111111, 32'h22222222, 32'h33333333, 32'h44444444};
        int i;
        
        test_count++;
        $display("Test %0d: INCR4 Burst Write starting at 0x%08h", test_count, ADDR_TDR);
        
        // First beat (NONSEQ)
        @(posedge HCLK);
        HADDR = ADDR_TDR;
        HWRITE = 1'b1;
        HSIZE = SIZE_WORD;
        HBURST = INCR4;
        HTRANS = NONSEQ;
        HSEL = 1'b1;
        HWSTRB = 4'hF;
        
        for (i = 0; i < 4; i++) begin
            // Data phase for current beat
            @(posedge HCLK);
            if (i < 3) begin
                // Setup next address phase
                HADDR = ADDR_TDR + ((i+1) * 4);
                HTRANS = SEQ;
            end else begin
                HTRANS = IDLE;
                HSEL = 1'b0;
            end
            HWDATA = burst_data[i];
            
            wait(HREADY);
            if (HRESP) begin
                $display("ERROR: Unexpected error in burst beat %0d", i);
                error_count++;
                break;
            end
        end
        
        @(posedge HCLK);
        $display("PASS: INCR4 burst completed");
        
        // Verify burst data
        for (i = 0; i < 4; i++) begin
            test_single_read(ADDR_TDR + (i*4), burst_data[i], SIZE_WORD);
        end
    endtask
    
    // Task: WRAP4 Burst Test  
    task test_wrap4_burst();
        logic [31:0] wrap_data [4] = '{32'hAAAAAAAA, 32'hBBBBBBBB, 32'hCCCCCCCC, 32'hDDDDDDDD};
        logic [31:0] base_addr = ADDR_LCR; // Start at 0x08
        int i;
        
        test_count++;
        $display("Test %0d: WRAP4 Burst Write starting at 0x%08h", test_count, base_addr);
        
        // First beat (NONSEQ)
        @(posedge HCLK);
        HADDR = base_addr;
        HWRITE = 1'b1;
        HSIZE = SIZE_WORD;
        HBURST = WRAP4;
        HTRANS = NONSEQ;
        HSEL = 1'b1;
        HWSTRB = 4'hF;
        
        for (i = 0; i < 4; i++) begin
            // Data phase for current beat
            @(posedge HCLK);
            if (i < 3) begin
                // Calculate wrapped address
                HADDR = (base_addr & ~32'hF) | ((base_addr + ((i+1) * 4)) & 32'hF);
                HTRANS = SEQ;
            end else begin
                HTRANS = IDLE;
                HSEL = 1'b0;
            end
            HWDATA = wrap_data[i];
            
            wait(HREADY);
            if (HRESP) begin
                $display("ERROR: Unexpected error in wrap burst beat %0d", i);
                error_count++;
                break;
            end
        end
        
        @(posedge HCLK);
        $display("PASS: WRAP4 burst completed");
    endtask
    
    // Task: Master Lock Test
    task test_master_lock();
        test_count++;
        $display("Test %0d: Master Lock Transfer to HCR", test_count);
        
        // Locked transfer
        @(posedge HCLK);
        HADDR = ADDR_HCR;
        HWRITE = 1'b1;
        HSIZE = SIZE_WORD;
        HBURST = SINGLE;
        HTRANS = NONSEQ;
        HSEL = 1'b1;
        HMASTLOCK = 1'b1; // Assert master lock
        HWSTRB = 4'hF;
        
        // Data Phase
        @(posedge HCLK);
        HTRANS = IDLE;
        HSEL = 1'b0;
        HMASTLOCK = 1'b0; // Deassert lock
        HWDATA = 32'hDEADC0DE;
        
        // Wait for completion
        wait(HREADY);
        @(posedge HCLK);
        
        if (HRESP) begin
            $display("ERROR: Unexpected error response for locked transfer");
            error_count++;
        end else begin
            $display("PASS: Master lock transfer completed");
        end
        
        // Verify the data
        test_single_read(ADDR_HCR, 32'hDEADC0DE, SIZE_WORD);
    endtask
    
    // Monitor for debugging
    initial begin
        $dumpfile("ahb_slave_tb.vcd");
        $dumpvars(0, tb_ahb_slave);
        
        // Timeout
        #100000 begin
            $display("ERROR: Simulation timeout!");
            $finish;
        end
    end

endmodule