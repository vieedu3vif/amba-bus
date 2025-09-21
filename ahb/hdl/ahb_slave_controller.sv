module ahb_slave_controller (
    // Global signals
    input  wire        HCLK,        // Clock signal
    input  wire        HRESETn,     // Active-low reset signal
   
    // AHB signals from Master
    input  wire        HWRITE,      // Write/read control: 1 = write, 0 = read
    input  wire [1:0]  HTRANS,      // Transfer type: 00 = IDLE, 01 = BUSY, 10 = NONSEQ, 11 = SEQ
    input  wire        HSEL,        // Slave select signal
    input  logic [31:0] HADDR,      // Address bus
    input  logic [2:0]  HSIZE,      // Transfer size: 000 = byte, 001 = half-word, 010 = word
    input  logic [2:0]  HBURST,     // Burst type: 000 = SINGLE, 001 = INCR, 010 = WRAP4, etc.
    input  logic [3:0]  HPROT,      // Protection control
    input  logic        HMASTLOCK,  // Master lock for atomic transactions
    input  logic [3:0]  HWSTRB,     // Write strobe (custom): indicates valid byte lanes
    input  logic [31:0] HWDATA,     // Write data
   
    // AHB response signals to Master
    output logic       HREADY,      // Slave ready signal: 1 = ready, 0 = busy
    output logic       HRESP,       // Slave response: 0 = OKAY, 1 = ERROR
    output logic [31:0] HRDATA,     // Read data
    
    // Interface to Register File
    output logic [31:0] addr,       // Address to register file
    output logic [2:0]  size,       // Transfer size to register file
    output logic [2:0]  burst,      // Burst type to register file
    output logic [3:0]  prot,       // Protection control to register file
    output logic        mastlock,   // Master lock to register file
    output logic [3:0]  strb,       // Write strobe to register file
    output logic [31:0] write_data, // Write data to register file
    input  logic [31:0] read_data,  // Read data from register file
    output logic        write_read, // Control signal to register file: 1 = write, 0 = read
    output logic        transfer_valid, // Valid transfer signal to register file
    input  logic        burst_done, // Burst complete signal from register file
    input  logic        error_flag  // Error flag from register file
);

    // Pipeline registers to store control signals for data phase
    logic trans_type_reg;
    logic addr_phase_valid;
    logic data_phase_valid;
    logic [31:0] hwdata_reg;  // Pipeline register for write data
   
    // State machine states
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        DATA_PHASE = 2'b01,
        ERROR = 2'b10
    } state_t;
    state_t state, next_state;

    // Address phase valid detection (NONSEQ or SEQ with HSEL)
    assign addr_phase_valid = HSEL && (HTRANS == 2'b10 || HTRANS == 2'b11);
    
    // Data phase valid - one cycle after address phase
    assign data_phase_valid = (state == DATA_PHASE);

    // Pipeline: Capture control signals in address phase for data phase
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            trans_type_reg <= 1'b0;
            addr <= 32'b0;
            size <= 3'b0;
            burst <= 3'b0;
            prot <= 4'b0;
            mastlock <= 1'b0;
            strb <= 4'b0;
            hwdata_reg <= 32'b0;
        end else begin
            // Capture address phase signals
            if (addr_phase_valid && HREADY) begin
                trans_type_reg <= HWRITE;
                addr <= HADDR;
                size <= HSIZE;
                burst <= HBURST;
                prot <= HPROT;
                mastlock <= HMASTLOCK;
                strb <= HWSTRB;
            end
            // Capture write data in data phase
            if (data_phase_valid) begin
                hwdata_reg <= HWDATA;
            end
        end
    end

    // Pass through pipelined write data
    assign write_data = hwdata_reg;
    
    // Pass through read data from register file
    assign HRDATA = read_data;

    // State machine: Update state
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state <= IDLE;
        end else if (HREADY) begin  // Only transition when ready
            state <= next_state;
        end
    end

    // State machine and control signal generation
    always_comb begin
        // Default values
        write_read = 1'b0;
        transfer_valid = 1'b0;
        HRESP = 1'b0;
        HREADY = 1'b1;
        next_state = state;

        case (state)
            IDLE: begin
                if (addr_phase_valid) begin
                    next_state = DATA_PHASE;
                    HREADY = 1'b1; // Accept address phase
                end
            end
            
            DATA_PHASE: begin
                write_read = trans_type_reg; // Use pipelined HWRITE
                transfer_valid = 1'b1;       // Valid data phase
                
                if (error_flag) begin
                    HRESP = 1'b1;           // Signal error
                    next_state = ERROR;
                    HREADY = 1'b1;          // Complete transfer with error
                end else if (burst_done || burst == 3'b000) begin // Single transfer or burst complete
                    next_state = IDLE;      // Return to idle
                    HREADY = 1'b1;          // Ready for next transfer
                end else begin
                    // Multi-beat burst continues - check for next beat
                    if (addr_phase_valid) begin
                        next_state = DATA_PHASE; // Continue burst
                        HREADY = 1'b1;
                    end else begin
                        next_state = IDLE;   // No more beats
                        HREADY = 1'b1;
                    end
                end
            end
            
            ERROR: begin
                HRESP = 1'b1;       // Continue error response
                HREADY = 1'b1;      // Ready for next transfer
                next_state = IDLE;  // Return to idle
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule