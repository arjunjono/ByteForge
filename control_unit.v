// control_unit.v - ByteForge clocked control unit (standalone stage)
//
// Owns: FSM state, PC, SP, Instruction Register, Address Register (second
// instruction word), latched data-transaction operands, and the sticky
// halted / fault status. Instantiates the existing combinational
// instruction_decoder on the Instruction Register.
//
// The register file, ALU, stored FLAGS and the program/data memories are
// external. Register and FLAGS write enables are combinational outputs that
// take effect on the rising clock edge at which they are high.
//
// FSM:
//   S_FETCH1   request program word at PC; on completion IR<=word, PC<=PC+1
//   S_DECODE   decode IR: invalid -> S_FAULT, 2-word -> S_FETCH2, else S_EXEC
//   S_FETCH2   request program word at PC; on completion AR<=word, PC<=PC+1
//   S_EXEC     one-cycle execution (register/flag writes, jumps) or dispatch
//   S_MEM_PREP latch the data address / write data (and check the stack)
//   S_MEM_WAIT hold the data request until data_ready; complete exactly once
//   S_HALT     sticky halted state (until reset)
//   S_FAULT    sticky fault state (until reset)
//
// Every transaction is followed by at least one state with that interface's
// request low (S_DECODE after fetch 1, S_EXEC after fetch 2, S_FETCH1 after a
// data transaction).
`timescale 1ns/1ps

module control_unit #(
    parameter [15:0] STACK_BOTTOM = 16'h0100,
    parameter [15:0] STACK_TOP    = 16'h0200   // exclusive; empty-stack SP
) (
    input             clk,
    input             reset,               // active-high, synchronous

    // Program memory (word addressed)
    output            prog_request,
    output [15:0]     prog_address,
    input             prog_ready,
    input  [15:0]     prog_read_data,

    // Data memory (byte addressed)
    output            data_request,
    output            data_write_enable,   // direction of the requested transaction
    output [15:0]     data_address,
    output [7:0]      data_write_data,
    input             data_ready,
    input  [7:0]      data_read_data,

    // External register file (combinational reads, synchronous write)
    output [1:0]      reg_read_addr_a,
    output [1:0]      reg_read_addr_b,
    input  [7:0]      reg_read_data_a,
    input  [7:0]      reg_read_data_b,
    output reg        reg_write_enable,
    output [1:0]      reg_write_addr,
    output reg [7:0]  reg_write_data,

    // External ALU and stored FLAGS
    output [4:0]      alu_opcode,
    input  [7:0]      alu_result,
    input             alu_z,
    input             alu_c,
    input             alu_n,
    output reg        flags_write_enable,
    output            flags_z_in,
    output            flags_c_in,
    output            flags_n_in,
    input             stored_z,

    // Status
    output            halted,
    output            fault,
    output [15:0]     pc,
    output [15:0]     sp
);

    // Elaboration check: STACK_BOTTOM must be less than STACK_TOP.
    // If it is not, the unknown module below makes elaboration fail.
    generate
        if (STACK_BOTTOM >= STACK_TOP) begin : g_bad_stack_parameters
            control_unit_needs_STACK_BOTTOM_less_than_STACK_TOP u_parameter_error ();
        end
    endgenerate

    // ------------------------------------------------------------------
    // Opcodes (same encoding as instruction_decoder)
    // ------------------------------------------------------------------
    localparam [4:0] OP_LOAD  = 5'b00000;
    localparam [4:0] OP_STORE = 5'b00001;
    localparam [4:0] OP_MOV   = 5'b00010;
    localparam [4:0] OP_LOADI = 5'b00011;
    localparam [4:0] OP_ADD   = 5'b00100;
    localparam [4:0] OP_SUB   = 5'b00101;
    localparam [4:0] OP_AND   = 5'b00110;
    localparam [4:0] OP_OR    = 5'b00111;
    localparam [4:0] OP_XOR   = 5'b01000;
    localparam [4:0] OP_CMP   = 5'b01001;
    localparam [4:0] OP_JMP   = 5'b01010;
    localparam [4:0] OP_JZ    = 5'b01011;
    localparam [4:0] OP_JNZ   = 5'b01100;
    localparam [4:0] OP_PUSH  = 5'b01101;
    localparam [4:0] OP_POP   = 5'b01110;
    localparam [4:0] OP_IN    = 5'b01111;
    localparam [4:0] OP_OUT   = 5'b10000;
    localparam [4:0] OP_HALT  = 5'b10001;

    // ------------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------------
    localparam [2:0] S_FETCH1   = 3'd0;
    localparam [2:0] S_DECODE   = 3'd1;
    localparam [2:0] S_FETCH2   = 3'd2;
    localparam [2:0] S_EXEC     = 3'd3;
    localparam [2:0] S_MEM_PREP = 3'd4;
    localparam [2:0] S_MEM_WAIT = 3'd5;
    localparam [2:0] S_HALT     = 3'd6;
    localparam [2:0] S_FAULT    = 3'd7;

    // ------------------------------------------------------------------
    // Storage (owned by this module)
    // ------------------------------------------------------------------
    reg [2:0]  state;
    reg [2:0]  next_state;
    reg [15:0] pc_reg;
    reg [15:0] sp_reg;
    reg [15:0] ir;              // Instruction Register (first word)
    reg [15:0] ar;              // Address Register (second word)
    reg [15:0] mem_addr_reg;    // latched data address
    reg [7:0]  mem_wdata_reg;   // latched data write value
    reg        mem_we_reg;      // latched direction (1 = write)

    // ------------------------------------------------------------------
    // Instruction decoder, connected to the Instruction Register
    // ------------------------------------------------------------------
    wire [4:0] dec_opcode;
    wire       dec_valid;
    wire [1:0] dec_reg_a;
    wire [1:0] dec_reg_b;
    wire [7:0] dec_immediate;
    wire       dec_needs_second_word;
    wire       dec_reg_write_intent;
    wire       dec_flags_write_intent;
    wire       dec_mem_read_intent;
    wire       dec_mem_write_intent;
    wire       dec_jump_intent;
    wire [1:0] dec_jump_condition;
    wire       dec_stack_push_intent;
    wire       dec_stack_pop_intent;
    wire       dec_halt_intent;

    instruction_decoder u_decoder (
        .instruction        (ir),
        .opcode             (dec_opcode),
        .valid              (dec_valid),
        .reg_a              (dec_reg_a),
        .reg_b              (dec_reg_b),
        .immediate          (dec_immediate),
        .needs_second_word  (dec_needs_second_word),
        .reg_write_intent   (dec_reg_write_intent),
        .flags_write_intent (dec_flags_write_intent),
        .mem_read_intent    (dec_mem_read_intent),
        .mem_write_intent   (dec_mem_write_intent),
        .jump_intent        (dec_jump_intent),
        .jump_condition     (dec_jump_condition),
        .stack_push_intent  (dec_stack_push_intent),
        .stack_pop_intent   (dec_stack_pop_intent),
        .halt_intent        (dec_halt_intent)
    );

    // ------------------------------------------------------------------
    // Simple output assignments
    // ------------------------------------------------------------------
    // Requests are gated low while reset is high.
    assign prog_request = ((state == S_FETCH1) || (state == S_FETCH2)) && !reset;
    assign prog_address = pc_reg;

    assign data_request      = (state == S_MEM_WAIT) && !reset;
    assign data_write_enable = data_request && mem_we_reg;   // direction only, not a strobe
    assign data_address      = mem_addr_reg;
    assign data_write_data   = mem_wdata_reg;

    // Transaction completion: request && ready && !reset (request already has !reset)
    wire prog_done = prog_request && prog_ready;
    wire data_done = data_request && data_ready;

    assign reg_read_addr_a = dec_reg_a;
    assign reg_read_addr_b = dec_reg_b;
    assign reg_write_addr  = dec_reg_a;

    // The ALU opcode equals the decoded opcode for ADD..CMP, otherwise 00000.
    wire is_alu_op = dec_valid && ((dec_opcode == OP_ADD) || (dec_opcode == OP_SUB) ||
                                   (dec_opcode == OP_AND) || (dec_opcode == OP_OR)  ||
                                   (dec_opcode == OP_XOR) || (dec_opcode == OP_CMP));
    assign alu_opcode = is_alu_op ? dec_opcode : 5'b00000;

    // Flags come straight from the ALU; flags_write_enable decides if they are stored.
    assign flags_z_in = alu_z;
    assign flags_c_in = alu_c;
    assign flags_n_in = alu_n;

    assign halted = (state == S_HALT);
    assign fault  = (state == S_FAULT);
    assign pc     = pc_reg;
    assign sp     = sp_reg;

    // Stack range checks use comparisons only, so there is no 16-bit wraparound.
    wire push_ok = (sp_reg >  STACK_BOTTOM) && (sp_reg <= STACK_TOP);
    wire pop_ok  = (sp_reg >= STACK_BOTTOM) && (sp_reg <  STACK_TOP);

    // ------------------------------------------------------------------
    // Combinational next-state / write-enable / storage-control logic
    // ------------------------------------------------------------------
    reg        ir_load;      // IR <= prog_read_data
    reg        ar_load;      // AR <= prog_read_data
    reg        pc_inc;       // PC <= PC + 1
    reg        pc_load;      // PC <= AR (taken jump)
    reg        sp_load;      // SP <= sp_next
    reg [15:0] sp_next;
    reg        mem_latch;    // latch address / write data / direction
    reg [15:0] lat_addr;
    reg [7:0]  lat_wdata;
    reg        lat_we;

    always @(*) begin
        // Complete defaults on every path: no latches.
        next_state         = state;
        ir_load            = 1'b0;
        ar_load            = 1'b0;
        pc_inc             = 1'b0;
        pc_load            = 1'b0;
        sp_load            = 1'b0;
        sp_next            = sp_reg;
        mem_latch          = 1'b0;
        lat_addr           = 16'h0000;
        lat_wdata          = 8'h00;
        lat_we             = 1'b0;
        reg_write_enable   = 1'b0;
        reg_write_data     = 8'h00;
        flags_write_enable = 1'b0;

        case (state)

            S_FETCH1: begin
                if (prog_done) begin
                    ir_load    = 1'b1;
                    pc_inc     = 1'b1;
                    next_state = S_DECODE;
                end
            end

            S_DECODE: begin
                if (!dec_valid)
                    next_state = S_FAULT;           // no second-word fetch, no side effects
                else if (dec_needs_second_word)
                    next_state = S_FETCH2;
                else
                    next_state = S_EXEC;
            end

            S_FETCH2: begin
                if (prog_done) begin
                    ar_load    = 1'b1;
                    pc_inc     = 1'b1;
                    next_state = S_EXEC;
                end
            end

            S_EXEC: begin
                next_state = S_FETCH1;
                case (dec_opcode)
                    OP_MOV: begin
                        reg_write_enable = 1'b1;
                        reg_write_data   = reg_read_data_b;
                    end
                    OP_LOADI: begin
                        reg_write_enable = 1'b1;
                        reg_write_data   = dec_immediate;
                    end
                    OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR: begin
                        reg_write_enable   = 1'b1;
                        reg_write_data     = alu_result;
                        flags_write_enable = 1'b1;   // same edge as the register write
                    end
                    OP_CMP: begin
                        flags_write_enable = 1'b1;   // flags only, never a register
                    end
                    OP_JMP: begin
                        pc_load = 1'b1;
                    end
                    OP_JZ: begin
                        if (stored_z == 1'b1)
                            pc_load = 1'b1;
                    end
                    OP_JNZ: begin
                        if (stored_z == 1'b0)
                            pc_load = 1'b1;
                    end
                    OP_LOAD, OP_STORE, OP_IN, OP_OUT, OP_PUSH, OP_POP: begin
                        next_state = S_MEM_PREP;
                    end
                    OP_HALT: begin
                        next_state = S_HALT;
                    end
                    default: begin
                        next_state = S_FAULT;        // unreachable: decoder already validated
                    end
                endcase
            end

            S_MEM_PREP: begin
                case (dec_opcode)
                    OP_LOAD, OP_IN: begin
                        mem_latch  = 1'b1;
                        lat_addr   = ar;
                        lat_we     = 1'b0;
                        next_state = S_MEM_WAIT;
                    end
                    OP_STORE, OP_OUT: begin
                        mem_latch  = 1'b1;
                        lat_addr   = ar;
                        lat_wdata  = reg_read_data_a;
                        lat_we     = 1'b1;
                        next_state = S_MEM_WAIT;
                    end
                    OP_PUSH: begin
                        if (push_ok) begin
                            mem_latch  = 1'b1;
                            lat_addr   = sp_reg - 16'h0001;   // safe: sp_reg > STACK_BOTTOM
                            lat_wdata  = reg_read_data_a;
                            lat_we     = 1'b1;
                            next_state = S_MEM_WAIT;
                        end else begin
                            next_state = S_FAULT;             // before any request or SP update
                        end
                    end
                    OP_POP: begin
                        if (pop_ok) begin
                            mem_latch  = 1'b1;
                            lat_addr   = sp_reg;
                            lat_we     = 1'b0;
                            next_state = S_MEM_WAIT;
                        end else begin
                            next_state = S_FAULT;             // before any request or SP update
                        end
                    end
                    default: begin
                        next_state = S_FAULT;
                    end
                endcase
            end

            S_MEM_WAIT: begin
                // Request, address, direction and write data are held; nothing
                // is updated until the acknowledged completion edge.
                if (data_done) begin
                    next_state = S_FETCH1;
                    case (dec_opcode)
                        OP_LOAD, OP_IN: begin
                            reg_write_enable = 1'b1;
                            reg_write_data   = data_read_data;
                        end
                        OP_POP: begin
                            reg_write_enable = 1'b1;
                            reg_write_data   = data_read_data;
                            sp_load          = 1'b1;
                            sp_next          = mem_addr_reg + 16'h0001;
                        end
                        OP_PUSH: begin
                            sp_load = 1'b1;
                            sp_next = mem_addr_reg;
                        end
                        default: begin
                            // STORE / OUT: the memory write itself is the whole action
                        end
                    endcase
                end
            end

            S_HALT: begin
                next_state = S_HALT;
            end

            S_FAULT: begin
                next_state = S_FAULT;
            end

            default: begin
                next_state = S_FAULT;
            end
        endcase

        // No register or FLAGS write may happen on a reset edge.
        if (reset) begin
            reg_write_enable   = 1'b0;
            flags_write_enable = 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Sequential storage (nonblocking assignments; reset has priority)
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state         <= S_FETCH1;
            pc_reg        <= 16'h0000;
            sp_reg        <= STACK_TOP;
            ir            <= 16'h0000;
            ar            <= 16'h0000;
            mem_addr_reg  <= 16'h0000;
            mem_wdata_reg <= 8'h00;
            mem_we_reg    <= 1'b0;
        end else begin
            state <= next_state;
            if (ir_load)
                ir <= prog_read_data;
            if (ar_load)
                ar <= prog_read_data;
            if (pc_load)
                pc_reg <= ar;
            else if (pc_inc)
                pc_reg <= pc_reg + 16'h0001;
            if (sp_load)
                sp_reg <= sp_next;
            if (mem_latch) begin
                mem_addr_reg  <= lat_addr;
                mem_wdata_reg <= lat_wdata;
                mem_we_reg    <= lat_we;
            end
        end
    end

endmodule
