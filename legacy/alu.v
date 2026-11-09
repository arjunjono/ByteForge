// alu.v - ByteForge 8-bit combinational ALU
`timescale 1ns/1ps

module alu (
    input  [7:0] A,
    input  [7:0] B,
    input  [4:0] opcode,
    output reg [7:0] result,
    output reg       Z,
    output reg       C,
    output reg       N
);

    // Opcodes
    localparam [4:0] OP_ADD = 5'b00100;
    localparam [4:0] OP_SUB = 5'b00101;
    localparam [4:0] OP_AND = 5'b00110;
    localparam [4:0] OP_OR  = 5'b00111;
    localparam [4:0] OP_XOR = 5'b01000;
    localparam [4:0] OP_CMP = 5'b01001;

    reg [8:0] a_wide;   // A widened to 9 bits
    reg [8:0] b_wide;   // B widened to 9 bits
    reg [8:0] sum;      // 9-bit sum, bit 8 = carry out
    reg       valid;    // 1 when opcode is supported

    always @(*) begin
        // Default values on every path: no latches inferred
        a_wide = {1'b0, A};
        b_wide = {1'b0, B};
        sum    = a_wide + b_wide;
        result = 8'h00;
        C      = 1'b0;
        valid  = 1'b1;

        case (opcode)
            OP_ADD: begin
                result = sum[7:0];
                C      = sum[8];          // unsigned sum exceeded 255
            end
            OP_SUB, OP_CMP: begin
                result = A - B;           // lowest 8 bits
                C      = (A < B);         // unsigned borrow
            end
            OP_AND: result = A & B;
            OP_OR:  result = A | B;
            OP_XOR: result = A ^ B;
            default: begin
                result = 8'h00;
                C      = 1'b0;
                valid  = 1'b0;
            end
        endcase

        // Flags: forced to 0 for unsupported opcodes
        Z = valid & (result == 8'h00);
        N = valid & result[7];
    end

endmodule
