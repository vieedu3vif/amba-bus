module ahb_slave_reg_file (
    // Global signals
    input  logic        HCLK,        // Clock signal
    input  logic        HRESETn,     // Active-low reset signal
    
    // Address and control signals from Controller
    input  logic [31:0] addr,        // Address bus
    input  logic [2:0]  size,        // Transfer size: 000 = byte, 001 = half-word, 010 = word
    input  logic [2:0]  burst,       // Burst type: 000 = SINGLE, 001 = INCR, 010 = WRAP4, etc.
    input  logic [3:0]  prot,        // Protection control
    input  logic        mastlock,    // Master lock for atomic transactions
    input  logic [3:0]  strb,        // Write strobe (custom): indicates valid byte lanes
    
    // Data signals
    input  logic [31:0] write_data,  // Write data from controller     
    output logic [31:0] read_data,   // Read data bus
    
    // Control signals from controller
    input  logic        write_read,     // Control signal from controller: 1 = write, 0 = read
    input  logic        transfer_valid, // Valid transfer signal from controller
    
    // Feedback signals to controller
    output logic        burst_done,  // Signal to controller: 1 = burst complete
    output logic        error_flag,  // Signal to controller: 1 = error (e.g., invalid address or access)
    
    // Register outputs
    output logic [31:0] tdr_o,       // Transmit Data Register
    output logic [31:0] lcr_o,       // Line Control Register
    output logic [31:0] ocr_o,       // Output Control Register
    output logic [31:0] fcr_o,       // FIFO Control Register
    output logic [31:0] ier_o,       // Interrupt Enable Register
    output logic [31:0] hcr_o,       // Hardware Configuration Register
    
    // Register inputs
    input  logic [31:0] rdr_i,       // Receive Data Register
    input  logic [31:0] lsr_i,       // Line Status Register
    input  logic [31:0] iir_i        // Interrupt Identification Register
);

    // Pipeline registers for address and control signals
    logic [31:0] addr_reg;    // Pipeline register for address
    logic [2:0]  size_reg;    // Pipeline register for size
    logic [2:0]  burst_reg;   // Pipeline register for burst
    logic [3:0]  prot_reg;    // Pipeline register for protection
    logic        mastlock_reg;// Pipeline register for master lock
    logic [3:0]  strb_reg;    // Pipeline register for write strobe

    // Burst control
    logic [3:0]  beat_count;  // Counter for burst beats
    logic [31:0] next_addr;   // Next address for burst
    logic        burst_active;// Flag for active burst
    logic        first_beat;  // First beat of transfer

    // Address map enumeration
    typedef enum logic [11:0] {
        ADDR_TDR = 12'h000,
        ADDR_RDR = 12'h004,
        ADDR_LCR = 12'h008,
        ADDR_OCR = 12'h00C,
        ADDR_LSR = 12'h010,
        ADDR_FCR = 12'h014,
        ADDR_IER = 12'h018,
        ADDR_IIR = 12'h01C,
        ADDR_HCR = 12'h020
    } apb_addr_e;

    // Pipeline: Capture address and control signals
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            addr_reg <= 32'b0;
            size_reg <= 3'b0;
            burst_reg <= 3'b0;
            prot_reg <= 4'b0;
            mastlock_reg <= 1'b0;
            strb_reg <= 4'b0;
            beat_count <= 4'b0;
            burst_active <= 1'b0;
            first_beat <= 1'b1;
        end else if (transfer_valid) begin
            if (!burst_active || first_beat) begin
                // Start new transfer or first beat
                addr_reg <= addr;
                size_reg <= size;
                burst_reg <= burst;
                prot_reg <= prot;
                mastlock_reg <= mastlock;
                strb_reg <= strb;
                
                if (burst == 3'b000) begin // SINGLE transfer
                    burst_active <= 1'b0;
                    beat_count <= 4'b0;
                    first_beat <= 1'b1;
                end else begin
                    burst_active <= 1'b1;
                    beat_count <= 4'b1; // Start from 1 (first beat)
                    first_beat <= 1'b0;
                end
            end else begin
                // Continue burst
                addr_reg <= next_addr;
                strb_reg <= strb;
                beat_count <= beat_count + 1;
                
                if (burst_done) begin
                    burst_active <= 1'b0;
                    beat_count <= 4'b0;
                    first_beat <= 1'b1;
                end
            end
        end
    end

    // Address alignment check function
    function automatic logic check_alignment(logic [31:0] address, logic [2:0] transfer_size);
        case (transfer_size)
            3'b000: return 1'b1;                    // Byte - always aligned
            3'b001: return (address[0] == 1'b0);    // Half-word - 2-byte aligned
            3'b010: return (address[1:0] == 2'b00); // Word - 4-byte aligned
            default: return 1'b0;                   // Invalid size
        endcase
    endfunction

    // Burst address calculation
    always_comb begin
        next_addr = addr_reg;
        burst_done = 1'b0;

        // Calculate next address based on size
        case (size_reg)
            3'b000: next_addr = addr_reg + 1; // Byte
            3'b001: next_addr = addr_reg + 2; // Half-word  
            3'b010: next_addr = addr_reg + 4; // Word
            default: next_addr = addr_reg + 4; // Default to word
        endcase

        // Handle wrapping for WRAP bursts
        case (burst_reg)
            3'b010: begin // WRAP4 - 16-byte boundary
                case (size_reg)
                    3'b000: next_addr = (addr_reg & ~32'hF) | ((addr_reg + 1) & 32'hF);
                    3'b001: next_addr = (addr_reg & ~32'hF) | ((addr_reg + 2) & 32'hF);
                    3'b010: next_addr = (addr_reg & ~32'hF) | ((addr_reg + 4) & 32'hF);
                    default: next_addr = addr_reg;
                endcase
            end
            3'b100: begin // WRAP8 - 32-byte boundary
                case (size_reg)
                    3'b000: next_addr = (addr_reg & ~32'h1F) | ((addr_reg + 1) & 32'h1F);
                    3'b001: next_addr = (addr_reg & ~32'h1F) | ((addr_reg + 2) & 32'h1F);
                    3'b010: next_addr = (addr_reg & ~32'h1F) | ((addr_reg + 4) & 32'h1F);
                    default: next_addr = addr_reg;
                endcase
            end
            3'b110: begin // WRAP16 - 64-byte boundary
                case (size_reg)
                    3'b000: next_addr = (addr_reg & ~32'h3F) | ((addr_reg + 1) & 32'h3F);
                    3'b001: next_addr = (addr_reg & ~32'h3F) | ((addr_reg + 2) & 32'h3F);
                    3'b010: next_addr = (addr_reg & ~32'h3F) | ((addr_reg + 4) & 32'h3F);
                    default: next_addr = addr_reg;
                endcase
            end
            default: ; // INCR or SINGLE, no wrapping
        endcase

        // Determine burst completion
        case (burst_reg)
            3'b000: burst_done = 1'b1;                     // SINGLE - always done after 1 beat
            3'b001: burst_done = 1'b0;                     // INCR - determined by master
            3'b011: burst_done = (beat_count >= 4'd4);     // INCR4
            3'b101: burst_done = (beat_count >= 4'd8);     // INCR8  
            3'b111: burst_done = (beat_count >= 4'd16);    // INCR16
            3'b010: burst_done = (beat_count >= 4'd4);     // WRAP4
            3'b100: burst_done = (beat_count >= 4'd8);     // WRAP8
            3'b110: burst_done = (beat_count >= 4'd16);    // WRAP16
            default: burst_done = 1'b1;
        endcase
    end

    // Error detection with comprehensive checks
    always_comb begin
        error_flag = 1'b0;

        if (transfer_valid) begin
            // Address range check - only valid register addresses
            if (addr_reg[31:12] != 20'h0 || 
                (addr_reg[11:0] != ADDR_TDR && 
                 addr_reg[11:0] != ADDR_RDR && 
                 addr_reg[11:0] != ADDR_LCR && 
                 addr_reg[11:0] != ADDR_OCR && 
                 addr_reg[11:0] != ADDR_LSR && 
                 addr_reg[11:0] != ADDR_FCR && 
                 addr_reg[11:0] != ADDR_IER && 
                 addr_reg[11:0] != ADDR_IIR && 
                 addr_reg[11:0] != ADDR_HCR)) begin
                error_flag = 1'b1;
            end
            
            // Address alignment check
            if (!check_alignment(addr_reg, size_reg)) begin
                error_flag = 1'b1;
            end
            
            // Invalid size check
            if (size_reg > 3'b010) begin // Only byte, half-word, word supported
                error_flag = 1'b1;
            end
            
            // Read-only register write protection
            if (write_read && (addr_reg[11:0] == ADDR_RDR || 
                              addr_reg[11:0] == ADDR_LSR || 
                              addr_reg[11:0] == ADDR_IIR)) begin
                error_flag = 1'b1;
            end
        end
    end

    // Register file write access with byte lane support
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            tdr_o <= 32'b0;
            lcr_o <= 32'b0;
            ocr_o <= 32'b0;
            fcr_o <= 32'b0;
            ier_o <= 32'b0;
            hcr_o <= 32'b0;
        end else if (write_read && !error_flag && transfer_valid) begin
            unique case (addr_reg[11:0])
                ADDR_TDR: begin
                    if (strb_reg[0]) tdr_o[7:0]   <= write_data[7:0];
                    if (strb_reg[1]) tdr_o[15:8]  <= write_data[15:8];
                    if (strb_reg[2]) tdr_o[23:16] <= write_data[23:16];
                    if (strb_reg[3]) tdr_o[31:24] <= write_data[31:24];
                end
                ADDR_LCR: begin
                    if (strb_reg[0]) lcr_o[7:0]   <= write_data[7:0];
                    if (strb_reg[1]) lcr_o[15:8]  <= write_data[15:8];
                    if (strb_reg[2]) lcr_o[23:16] <= write_data[23:16];
                    if (strb_reg[3]) lcr_o[31:24] <= write_data[31:24];
                end
                ADDR_OCR: begin
                    if (strb_reg[0]) ocr_o[7:0]   <= write_data[7:0];
                    if (strb_reg[1]) ocr_o[15:8]  <= write_data[15:8];
                    if (strb_reg[2]) ocr_o[23:16] <= write_data[23:16];
                    if (strb_reg[3]) ocr_o[31:24] <= write_data[31:24];
                end
                ADDR_FCR: begin
                    if (strb_reg[0]) fcr_o[7:0]   <= write_data[7:0];
                    if (strb_reg[1]) fcr_o[15:8]  <= write_data[15:8];
                    if (strb_reg[2]) fcr_o[23:16] <= write_data[23:16];
                    if (strb_reg[3]) fcr_o[31:24] <= write_data[31:24];
                end
                ADDR_IER: begin
                    if (strb_reg[0]) ier_o[7:0]   <= write_data[7:0];
                    if (strb_reg[1]) ier_o[15:8]  <= write_data[15:8];
                    if (strb_reg[2]) ier_o[23:16] <= write_data[23:16];
                    if (strb_reg[3]) ier_o[31:24] <= write_data[31:24];
                end
                ADDR_HCR: begin
                    if (strb_reg[0]) hcr_o[7:0]   <= write_data[7:0];
                    if (strb_reg[1]) hcr_o[15:8]  <= write_data[15:8];
                    if (strb_reg[2]) hcr_o[23:16] <= write_data[23:16];
                    if (strb_reg[3]) hcr_o[31:24] <= write_data[31:24];
                end
                default: ; // Do nothing for invalid addresses
            endcase
        end
    end

    // Read data multiplexer
    always_comb begin
        read_data = 32'b0;
        if (!write_read && !error_flag && transfer_valid) begin
            unique case (addr_reg[11:0])
                ADDR_TDR: read_data = tdr_o;
                ADDR_RDR: read_data = rdr_i;
                ADDR_LCR: read_data = lcr_o;
                ADDR_OCR: read_data = ocr_o;
                ADDR_LSR: read_data = lsr_i;
                ADDR_FCR: read_data = fcr_o;
                ADDR_IER: read_data = ier_o;
                ADDR_IIR: read_data = iir_i;
                ADDR_HCR: read_data = hcr_o;
                default: read_data = 32'b0;
            endcase
        end
    end

endmodule