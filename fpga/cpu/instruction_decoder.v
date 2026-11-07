// instruction_decoder.v - ByteForge combinational instruction decoder
//
// Decodes the FIRST 16-bit word of an instruction only.
// The outputs are static "intent" descriptions, not live execution strobes:
// a future clocked control unit will gate real writes, memory accesses and jumps.
//
// Instruction formats (opcode is always instruction[15:11]):
//
//   Two-register : MOV ADD SUB AND OR XOR CMP   (1 word)
//     [15:11] opcode  [10:9] reg A  [8:7] reg B  [6:0] reserved = 0
//
//   Immediate    : LOADI                         (1 word)
//     [15:11] opcode  [10:9] dest   [8:1] imm8   [0]   reserved = 0
//
//   Single-reg   : PUSH POP (1 word), LOAD STORE IN OUT (2 words)
//     [15:11] opcode  [10:9] reg    [8:0] reserved = 0
//
//   Address-only : JMP JZ JNZ                    (2 words)
//     [15:11] opcode  [10:0] reserved = 0
//
//   HALT                                         (1 word)
//     [15:11] opcode  [10:0] reserved = 0
//
// Any unsupported opcode or nonzero reserved bit makes the instruction
// invalid: valid = 0 and every output except the raw opcode is 0.
`timescale 1ns/1ps

module instruction_decoder (
    input      [15:0] instruction,        // first instruction word only

    output reg [4:0]  opcode,             // always raw instruction[15:11]
    output reg        valid,              // 1 = supported opcode, reserved bits zero
    output reg [1:0]  reg_a,
    output reg [1:0]  reg_b,
    output reg [7:0]  immediate,
    output reg        needs_second_word,  // 2-word instruction
    output reg        reg_write_intent,
    output reg        flags_write_intent,
    output reg        mem_read_intent,
    output reg        mem_write_intent,
    output reg        jump_intent,
    output reg [1:0]  jump_condition,     // 00 always, 01 if Z=1, 10 if Z=0, 11 unused
    output reg        stack_push_intent,
    output reg        stack_pop_intent,
    output reg        halt_intent
);

    // Opcodes
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

    always @(*) begin
        // Defaults on every path: no latches, and an invalid instruction
        // leaves everything (except the raw opcode) at zero.
        opcode             = instruction[15:11];
        valid              = 1'b0;
        reg_a              = 2'b00;
        reg_b              = 2'b00;
        immediate          = 8'h00;
        needs_second_word  = 1'b0;
        reg_write_intent   = 1'b0;
        flags_write_intent = 1'b0;
        mem_read_intent    = 1'b0;
        mem_write_intent   = 1'b0;
        jump_intent        = 1'b0;
        jump_condition     = 2'b00;
        stack_push_intent  = 1'b0;
        stack_pop_intent   = 1'b0;
        halt_intent        = 1'b0;

        // Each arm checks its reserved bits first and only then sets outputs.
        case (instruction[15:11])

            // ---- Two-register instructions: reserved bits [6:0] ----
            OP_MOV, OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_CMP: begin
                if (instruction[6:0] == 7'b0000000) begin
                    valid              = 1'b1;
                    reg_a              = instruction[10:9];
                    reg_b              = instruction[8:7];
                    reg_write_intent   = (instruction[15:11] != OP_CMP); // CMP never writes a register
                    flags_write_intent = (instruction[15:11] != OP_MOV); // MOV never writes flags
                end
            end

            // ---- LOADI: reserved bit [0] ----
            OP_LOADI: begin
                if (instruction[0] == 1'b0) begin
                    valid            = 1'b1;
                    reg_a            = instruction[10:9];
                    immediate        = instruction[8:1];
                    reg_write_intent = 1'b1;
                end
            end

            // ---- Single-register instructions: reserved bits [8:0] ----
            OP_LOAD: begin
                if (instruction[8:0] == 9'b000000000) begin
                    valid             = 1'b1;
                    reg_a             = instruction[10:9];
                    needs_second_word = 1'b1;
                    reg_write_intent  = 1'b1;
                    mem_read_intent   = 1'b1;
                end
            end

            OP_STORE: begin
                if (instruction[8:0] == 9'b000000000) begin
                    valid             = 1'b1;
                    reg_a             = instruction[10:9];
                    needs_second_word = 1'b1;
                    mem_write_intent  = 1'b1;
                end
            end

            OP_IN: begin
                if (instruction[8:0] == 9'b000000000) begin
                    valid             = 1'b1;
                    reg_a             = instruction[10:9];
                    needs_second_word = 1'b1;
                    reg_write_intent  = 1'b1;
                    mem_read_intent   = 1'b1;
                end
            end

            OP_OUT: begin
                if (instruction[8:0] == 9'b000000000) begin
                    valid             = 1'b1;
                    reg_a             = instruction[10:9];
                    needs_second_word = 1'b1;
                    mem_write_intent  = 1'b1;
                end
            end

            OP_PUSH: begin
                if (instruction[8:0] == 9'b000000000) begin
                    valid             = 1'b1;
                    reg_a             = instruction[10:9];
                    mem_write_intent  = 1'b1;
                    stack_push_intent = 1'b1;
                end
            end

            OP_POP: begin
                if (instruction[8:0] == 9'b000000000) begin
                    valid             = 1'b1;
                    reg_a             = instruction[10:9];
                    reg_write_intent  = 1'b1;
                    mem_read_intent   = 1'b1;
                    stack_pop_intent  = 1'b1;
                end
            end

            // ---- Address-only instructions: reserved bits [10:0] ----
            OP_JMP: begin
                if (instruction[10:0] == 11'b00000000000) begin
                    valid             = 1'b1;
                    needs_second_word = 1'b1;
                    jump_intent       = 1'b1;
                    jump_condition    = 2'b00;   // unconditional
                end
            end

            OP_JZ: begin
                if (instruction[10:0] == 11'b00000000000) begin
                    valid             = 1'b1;
                    needs_second_word = 1'b1;
                    jump_intent       = 1'b1;
                    jump_condition    = 2'b01;   // jump if Z = 1
                end
            end

            OP_JNZ: begin
                if (instruction[10:0] == 11'b00000000000) begin
                    valid             = 1'b1;
                    needs_second_word = 1'b1;
                    jump_intent       = 1'b1;
                    jump_condition    = 2'b10;   // jump if Z = 0
                end
            end

            // ---- HALT: reserved bits [10:0] ----
            OP_HALT: begin
                if (instruction[10:0] == 11'b00000000000) begin
                    valid       = 1'b1;
                    halt_intent = 1'b1;
                end
            end

            // Unsupported opcodes 10010..11111: defaults stay (invalid)
            default: begin
            end
        endcase
    end

endmodule
