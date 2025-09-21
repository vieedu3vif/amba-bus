module ahb_slave (
    // Global signals
    input  wire        HCLK,        // Clock signal
    input  wire        HRESETn,     // Active-low reset signal
    
    // AHB Address and control signals
    input  wire [31:0] HADDR,       // Address bus
    input  wire        HWRITE,      // Write/read control: 1 = write, 0 = read
    input  wire [2:0]  HSIZE,       // Transfer size: 000 = byte, 001 = half-word, 010 = word
    input  wire [2:0]  HBURST,      // Burst type: 000 = SINGLE, 001 = INCR, 010 = WRAP4
    input  wire [3:0]  HPROT,       // Protection control
    input  wire [1:0]  HTRANS,      // Transfer type: 00 = IDLE, 01 = BUSY, 10 = NONSEQ, 11 = SEQ
    input  wire        HMASTLOCK,   // Master lock for atomic transactions
    input  wire        HSEL,        // Slave select signal
    
    // AHB Data signals
    input  wire [31:0] HWDATA,      // Write data bus
    output wire [31:0] HRDATA,      // Read data bus
    
    // AHB Transfer response signals
    output wire        HREADY,      // Slave ready signal: 1 = ready, 0 = busy
    output wire        HRESP,       // Slave response: 0 = OKAY, 1 = ERROR
    
    // Custom signal (non-standard for AHB-Lite but useful for byte-level writes)
    input  wire [3:0]  HWSTRB,      // Write strobe: indicates valid byte lanes
    
    // Register outputs (to external UART logic)
    output wire [31:0] tdr_o,       // Transmit Data Register
    output wire [31:0] lcr_o,       // Line Control Register
    output wire [31:0] ocr_o,       // Output Control Register
    output wire [31:0] fcr_o,       // FIFO Control Register
    output wire [31:0] ier_o,       // Interrupt Enable Register
    output wire [31:0] hcr_o,       // Hardware Configuration Register
    
    // Register inputs (from external UART logic)
    input  wire [31:0] rdr_i,       // Receive Data Register
    input  wire [31:0] lsr_i,       // Line Status Register
    input  wire [31:0] iir_i        // Interrupt Identification Register
);

    // Internal signals for connecting controller and register file
    logic        write_read;     // Control signal from controller to reg file
    logic        burst_done;     // Burst completion signal from reg file
    logic        error_flag;     // Error flag from reg file  
    logic        transfer_valid; // Valid transfer signal from controller
    
    logic [31:0] addr;           // Internal address bus
    logic [2:0]  size;           // Internal size signal
    logic [2:0]  burst;          // Internal burst signal
    logic [3:0]  prot;           // Internal protection signal
    logic        mastlock;       // Internal master lock signal
    logic [3:0]  strb;           // Internal write strobe signal
    logic [31:0] write_data;     // Internal write data
    logic [31:0] read_data;      // Internal read data

    // Input validation - ensure no X or Z values in simulation
    logic inputs_valid;
    assign inputs_valid = ~(^{HCLK, HRESETn, HSEL, HTRANS, HWRITE, HSIZE, HBURST} === 1'bx);

    // Instantiate AHB slave controller
    ahb_slave_controller u_controller (
        // Global signals
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        
        // AHB signals from Master
        .HWRITE(HWRITE),
        .HTRANS(HTRANS),
        .HSEL(HSEL),
        .HADDR(HADDR),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HMASTLOCK(HMASTLOCK),
        .HWSTRB(HWSTRB),
        .HWDATA(HWDATA),
        
        // AHB response signals to Master
        .HREADY(HREADY),
        .HRESP(HRESP),
        .HRDATA(HRDATA),
        
        // Interface to Register File
        .addr(addr),
        .size(size),
        .burst(burst),
        .prot(prot),
        .mastlock(mastlock),
        .strb(strb),
        .write_data(write_data),
        .read_data(read_data),
        .write_read(write_read),
        .transfer_valid(transfer_valid),
        .burst_done(burst_done),
        .error_flag(error_flag)
    );

    // Instantiate AHB slave register file
    ahb_slave_reg_file u_reg_file (
        // Global signals
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        
        // Address and control signals from Controller
        .addr(addr),
        .size(size),
        .burst(burst),
        .prot(prot),
        .mastlock(mastlock),
        .strb(strb),
        
        // Data signals
        .write_data(write_data),
        .read_data(read_data),
        
        // Control signals from controller
        .write_read(write_read),
        .transfer_valid(transfer_valid),
        
        // Feedback signals to controller
        .burst_done(burst_done),
        .error_flag(error_flag),
        
        // Register outputs
        .tdr_o(tdr_o),
        .lcr_o(lcr_o),
        .ocr_o(ocr_o),
        .fcr_o(fcr_o),
        .ier_o(ier_o),
        .hcr_o(hcr_o),
        
        // Register inputs
        .rdr_i(rdr_i),
        .lsr_i(lsr_i),
        .iir_i(iir_i)
    );

    // Assertions for design verification (synthesis tools will ignore these)
    `ifdef SIMULATION
        // Check that HREADY is never unknown
        always @(posedge HCLK) begin
            if (HRESETn) begin
                assert (HREADY !== 1'bx) else $error("HREADY is unknown");
                assert (HRESP !== 1'bx) else $error("HRESP is unknown");
            end
        end
        
        // Check valid HTRANS values
        always @(posedge HCLK) begin
            if (HRESETn && HSEL) begin
                assert (HTRANS inside {2'b00, 2'b01, 2'b10, 2'b11}) 
                    else $error("Invalid HTRANS value: %b", HTRANS);
                assert (HSIZE inside {3'b000, 3'b001, 3'b010}) 
                    else $error("Invalid HSIZE value: %b", HSIZE);
            end
        end
        
        // Check burst alignment
        always @(posedge HCLK) begin
            if (HRESETn && HSEL && (HTRANS == 2'b10)) begin // NONSEQ
                case (HSIZE)
                    3'b001: assert (HADDR[0] == 1'b0) else $error("Half-word not aligned");
                    3'b010: assert (HADDR[1:0] == 2'b00) else $error("Word not aligned");
                endcase
            end
        end
    `endif

endmodule