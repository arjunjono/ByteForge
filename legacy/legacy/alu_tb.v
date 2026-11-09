// alu_tb.v - self-checking testbench for alu
`timescale 1ns/1ps

module alu_tb;

    reg  [7:0] A;
    reg  [7:0] B;
    reg  [4:0] opcode;
    wire [7:0] result;
    wire       Z, C, N;

    integer tests;
    integer failures;

    // Opcodes (same values as the ALU)
    localparam [4:0] OP_ADD = 5'b00100;
    localparam [4:0] OP_SUB = 5'b00101;
    localparam [4:0] OP_AND = 5'b00110;
    localparam [4:0] OP_OR  = 5'b00111;
    localparam [4:0] OP_XOR = 5'b01000;
    localparam [4:0] OP_CMP = 5'b01001;

    alu dut (
        .A      (A),
        .B      (B),
        .opcode (opcode),
        .result (result),
        .Z      (Z),
        .C      (C),
        .N      (N)
    );

    // Apply inputs, wait, compare outputs with expected values
    task check;
        input [8*8-1:0] name;
        input [4:0] op;
        input [7:0] a_in;
        input [7:0] b_in;
        input [7:0] exp_result;
        input       exp_z;
        input       exp_c;
        input       exp_n;
        begin
            A      = a_in;
            B      = b_in;
            opcode = op;
            #5;   // allow combinational logic to settle
            tests = tests + 1;
            if (result !== exp_result || Z !== exp_z ||
                C !== exp_c || N !== exp_n) begin
                failures = failures + 1;
                $display("FAIL: %0s opcode=%b A=%0d (0x%h) B=%0d (0x%h)",
                         name, op, a_in, a_in, b_in, b_in);
                $display("      expected: result=%0d (0x%h) Z=%b C=%b N=%b",
                         exp_result, exp_result, exp_z, exp_c, exp_n);
                $display("      actual:   result=%0d (0x%h) Z=%b C=%b N=%b",
                         result, result, Z, C, N);
            end
        end
    endtask

    initial begin
        $dumpfile("alu_waveform.vcd");
        $dumpvars(0, alu_tb);

        tests    = 0;
        failures = 0;
        A = 8'h00; B = 8'h00; opcode = 5'b00000;
        #5;

        // ---------------- ADD ----------------
        //     name   op      A     B     result Z  C  N
        check("ADD",  OP_ADD, 8'd5,   8'd3,   8'd8,   0, 0, 0);
        check("ADD",  OP_ADD, 8'd255, 8'd1,   8'd0,   1, 1, 0);
        check("ADD",  OP_ADD, 8'd127, 8'd1,   8'd128, 0, 0, 1);
        check("ADD",  OP_ADD, 8'd0,   8'd0,   8'd0,   1, 0, 0);
        check("ADD",  OP_ADD, 8'd200, 8'd100, 8'd44,  0, 1, 0);
        check("ADD",  OP_ADD, 8'd128, 8'd128, 8'd0,   1, 1, 0);
        check("ADD",  OP_ADD, 8'd255, 8'd255, 8'd254, 0, 1, 1);
        check("ADD",  OP_ADD, 8'd100, 8'd28,  8'd128, 0, 0, 1);

        // ---------------- SUB ----------------
        check("SUB",  OP_SUB, 8'd8,   8'd3,   8'd5,   0, 0, 0);
        check("SUB",  OP_SUB, 8'd3,   8'd5,   8'd254, 0, 1, 1);
        check("SUB",  OP_SUB, 8'd0,   8'd0,   8'd0,   1, 0, 0);
        check("SUB",  OP_SUB, 8'd0,   8'd1,   8'd255, 0, 1, 1);
        check("SUB",  OP_SUB, 8'd255, 8'd255, 8'd0,   1, 0, 0);
        check("SUB",  OP_SUB, 8'd128, 8'd1,   8'd127, 0, 0, 0);
        check("SUB",  OP_SUB, 8'd200, 8'd100, 8'd100, 0, 0, 0);
        check("SUB",  OP_SUB, 8'd100, 8'd200, 8'd156, 0, 1, 1);

        // ---------------- CMP (same as SUB) ----------------
        check("CMP",  OP_CMP, 8'd7,   8'd7,   8'd0,   1, 0, 0);
        check("CMP",  OP_CMP, 8'd8,   8'd3,   8'd5,   0, 0, 0);
        check("CMP",  OP_CMP, 8'd3,   8'd5,   8'd254, 0, 1, 1);
        check("CMP",  OP_CMP, 8'd0,   8'd0,   8'd0,   1, 0, 0);

        // ---------------- AND ----------------
        check("AND",  OP_AND, 8'hAA,  8'h55,  8'h00,  1, 0, 0);
        check("AND",  OP_AND, 8'hFF,  8'h0F,  8'h0F,  0, 0, 0);
        check("AND",  OP_AND, 8'hFF,  8'hFF,  8'hFF,  0, 0, 1);
        check("AND",  OP_AND, 8'h00,  8'hFF,  8'h00,  1, 0, 0);

        // ---------------- OR ----------------
        check("OR",   OP_OR,  8'hAA,  8'h55,  8'hFF,  0, 0, 1);
        check("OR",   OP_OR,  8'h00,  8'h00,  8'h00,  1, 0, 0);
        check("OR",   OP_OR,  8'h0F,  8'hF0,  8'hFF,  0, 0, 1);
        check("OR",   OP_OR,  8'h01,  8'h02,  8'h03,  0, 0, 0);

        // ---------------- XOR ----------------
        check("XOR",  OP_XOR, 8'hAA,  8'hAA,  8'h00,  1, 0, 0);
        check("XOR",  OP_XOR, 8'hFF,  8'h0F,  8'hF0,  0, 0, 1);
        check("XOR",  OP_XOR, 8'h55,  8'hAA,  8'hFF,  0, 0, 1);
        check("XOR",  OP_XOR, 8'h00,  8'h00,  8'h00,  1, 0, 0);

        // ---------------- Unsupported opcodes ----------------
        // Inputs chosen so a wrongly-decoded op would give non-zero outputs
        check("BAD",  5'b00000, 8'hFF, 8'h01, 8'h00, 0, 0, 0);
        check("BAD",  5'b00001, 8'hFF, 8'h01, 8'h00, 0, 0, 0);
        check("BAD",  5'b00011, 8'hFF, 8'h01, 8'h00, 0, 0, 0);
        check("BAD",  5'b01010, 8'hFF, 8'h01, 8'h00, 0, 0, 0);
        check("BAD",  5'b10100, 8'hFF, 8'h01, 8'h00, 0, 0, 0);
        check("BAD",  5'b11111, 8'hFF, 8'h01, 8'h00, 0, 0, 0);

        // ---------------- Summary ----------------
        $display("----------------------------------------");
        $display("Tests run: %0d   Failures: %0d", tests, failures);
        if (failures == 0)
            $display("PASS: all %0d tests passed", tests);
        else
            $display("FAIL: %0d of %0d tests failed", failures, tests);
        $display("----------------------------------------");

        $finish;
    end

endmodule
