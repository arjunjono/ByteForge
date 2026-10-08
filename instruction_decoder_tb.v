// instruction_decoder_tb.v - self-checking testbench for instruction_decoder
//
// Expected values are written out explicitly from the ByteForge specification
// (per-opcode constants and loop indices). There is no reference decode
// function that copies the decoder's own logic.
`timescale 1ns/1ps

module instruction_decoder_tb;

    // ---------------- DUT connections ----------------
    reg  [15:0] instruction;
    wire [4:0]  opcode;
    wire        valid;
    wire [1:0]  reg_a;
    wire [1:0]  reg_b;
    wire [7:0]  immediate;
    wire        needs_second_word;
    wire        reg_write_intent;
    wire        flags_write_intent;
    wire        mem_read_intent;
    wire        mem_write_intent;
    wire        jump_intent;
    wire [1:0]  jump_condition;
    wire        stack_push_intent;
    wire        stack_pop_intent;
    wire        halt_intent;

    integer checks;
    integer failures;
    integer i, j, d, n;
    reg [10:0] pats [0:7];
    reg [4:0]  op5;
    reg [1:0]  rd;
    reg [7:0]  imm8;

    // Opcodes from the specification
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

    instruction_decoder dut (
        .instruction        (instruction),
        .opcode             (opcode),
        .valid              (valid),
        .reg_a              (reg_a),
        .reg_b              (reg_b),
        .immediate          (immediate),
        .needs_second_word  (needs_second_word),
        .reg_write_intent   (reg_write_intent),
        .flags_write_intent (flags_write_intent),
        .mem_read_intent    (mem_read_intent),
        .mem_write_intent   (mem_write_intent),
        .jump_intent        (jump_intent),
        .jump_condition     (jump_condition),
        .stack_push_intent  (stack_push_intent),
        .stack_pop_intent   (stack_pop_intent),
        .halt_intent        (halt_intent)
    );

    // ======================================================================
    // Core check: apply one instruction, wait, compare EVERY output with !==.
    // The expected raw opcode is always instr[15:11], even when invalid.
    // ======================================================================
    task apply_and_check;
        input [8*40-1:0] name;
        input [15:0]     instr;
        input            e_valid;
        input [1:0]      e_a;
        input [1:0]      e_b;
        input [7:0]      e_imm;
        input            e_nsw;     // needs_second_word
        input            e_rw;      // reg_write_intent
        input            e_fw;      // flags_write_intent
        input            e_mr;      // mem_read_intent
        input            e_mw;      // mem_write_intent
        input            e_jmp;     // jump_intent
        input [1:0]      e_jc;      // jump_condition
        input            e_push;
        input            e_pop;
        input            e_halt;
        reg [28:0] exp_vec;
        reg [28:0] act_vec;
        begin
            instruction = instr;
            #1;     // let the combinational logic settle
            checks = checks + 1;
            exp_vec = {instr[15:11], e_valid, e_a, e_b, e_imm,
                       e_nsw, e_rw, e_fw, e_mr, e_mw, e_jmp, e_jc,
                       e_push, e_pop, e_halt};
            act_vec = {opcode, valid, reg_a, reg_b, immediate,
                       needs_second_word, reg_write_intent, flags_write_intent,
                       mem_read_intent, mem_write_intent, jump_intent,
                       jump_condition, stack_push_intent, stack_pop_intent,
                       halt_intent};
            if (act_vec !== exp_vec) begin
                failures = failures + 1;
                $display("FAIL @%0d ns: [%0s] instruction=%b (0x%h)",
                         $time, name, instr, instr);
                $display("  expected: opcode=%b valid=%b A=%b B=%b imm=0x%h 2ndword=%b regW=%b flagW=%b memR=%b memW=%b jump=%b cond=%b push=%b pop=%b halt=%b",
                         instr[15:11], e_valid, e_a, e_b, e_imm,
                         e_nsw, e_rw, e_fw, e_mr, e_mw, e_jmp, e_jc,
                         e_push, e_pop, e_halt);
                $display("  actual:   opcode=%b valid=%b A=%b B=%b imm=0x%h 2ndword=%b regW=%b flagW=%b memR=%b memW=%b jump=%b cond=%b push=%b pop=%b halt=%b",
                         opcode, valid, reg_a, reg_b, immediate,
                         needs_second_word, reg_write_intent, flags_write_intent,
                         mem_read_intent, mem_write_intent, jump_intent,
                         jump_condition, stack_push_intent, stack_pop_intent,
                         halt_intent);
            end
        end
    endtask

    // Invalid instruction: valid=0 and every other output 0 (except raw opcode)
    task expect_invalid;
        input [8*40-1:0] name;
        input [15:0]     instr;
        begin
            apply_and_check(name, instr,
                1'b0, 2'b00, 2'b00, 8'h00,
                1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00,
                1'b0, 1'b0, 1'b0);
        end
    endtask

    // ======================================================================
    // Family tests (explicit spec constants per opcode)
    // ======================================================================

    // Two-register opcode: all 16 A/B combinations. Operand bits may be any value.
    task test_two_reg;
        input [8*40-1:0] name;
        input [4:0]      op;
        input            e_rw;
        input            e_fw;
        integer a, b;
        reg [1:0] ra, rb;
        begin
            for (a = 0; a < 4; a = a + 1) begin
                for (b = 0; b < 4; b = b + 1) begin
                    ra = a;
                    rb = b;
                    apply_and_check(name, {op, ra, rb, 7'b0000000},
                        1'b1, ra, rb, 8'h00,
                        1'b0, e_rw, e_fw, 1'b0, 1'b0, 1'b0, 2'b00,
                        1'b0, 1'b0, 1'b0);
                end
            end
        end
    endtask

    // Single-register opcode: all four register selections.
    task test_single;
        input [8*40-1:0] name;
        input [4:0]      op;
        input            e_nsw;
        input            e_rw;
        input            e_mr;
        input            e_mw;
        input            e_push;
        input            e_pop;
        integer r;
        reg [1:0] rr;
        begin
            for (r = 0; r < 4; r = r + 1) begin
                rr = r;
                apply_and_check(name, {op, rr, 9'b000000000},
                    1'b1, rr, 2'b00, 8'h00,
                    e_nsw, e_rw, 1'b0, e_mr, e_mw, 1'b0, 2'b00,
                    e_push, e_pop, 1'b0);
            end
        end
    endtask

    // JMP / JZ / JNZ
    task test_jump;
        input [8*40-1:0] name;
        input [4:0]      op;
        input [1:0]      e_jc;
        begin
            apply_and_check(name, {op, 11'b00000000000},
                1'b1, 2'b00, 2'b00, 8'h00,
                1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, e_jc,
                1'b0, 1'b0, 1'b0);
        end
    endtask

    // ---------- Reserved-bit tests ----------
    // Every single reserved bit set, one at a time. base must be a legal
    // instruction with nonzero operand bits.
    task test_reserved;
        input [8*40-1:0] name;
        input [15:0]     base;
        input [3:0]      nres;      // number of reserved bits (bits [nres-1:0])
        integer b;
        begin
            for (b = 0; b < nres; b = b + 1)
                expect_invalid(name, base | (16'h0001 << b));
        end
    endtask

    // Several reserved bits set together (needs nres >= 3)
    task test_reserved_multi;
        input [8*40-1:0] name;
        input [15:0]     base;
        input [3:0]      nres;
        integer b;
        reg [15:0] mask;
        begin
            mask = (16'h0001 << nres) - 16'h0001;                 // all reserved bits
            expect_invalid(name, base | mask);
            expect_invalid(name, base | (mask & 16'h5555));       // alternating
            expect_invalid(name, base | (mask & 16'hAAAA));       // alternating
            expect_invalid(name, base | 16'h0001 | (16'h0001 << (nres - 1)));  // lowest + highest
            for (b = 0; b < nres - 1; b = b + 1)
                expect_invalid(name, base | (16'h0003 << b));     // adjacent pairs
        end
    endtask

    task reserved_suite;
        input [8*40-1:0] name;
        input [15:0]     base;
        input [3:0]      nres;
        begin
            test_reserved(name, base, nres);
            if (nres >= 3)
                test_reserved_multi(name, base, nres);
        end
    endtask

    // ---------- Canonical instruction table (one entry per opcode) ----------
    // Back-to-back use of different orders changes every field and intent.
    task canon;
        input [4:0] k;
        begin
            case (k)
                //                name              instruction                           v     A      B      imm     nsw   rw    fw    mr    mw    jmp   jc     push  pop   halt
                5'd0:  apply_and_check("canon LOAD R1",     {OP_LOAD,  2'b01, 9'b000000000},   1'b1, 2'b01, 2'b00, 8'h00, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd1:  apply_and_check("canon STORE R2",    {OP_STORE, 2'b10, 9'b000000000},   1'b1, 2'b10, 2'b00, 8'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd2:  apply_and_check("canon MOV R3,R2",   {OP_MOV,   2'b11, 2'b10, 7'b0},    1'b1, 2'b11, 2'b10, 8'h00, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd3:  apply_and_check("canon LOADI R2,A5", {OP_LOADI, 2'b10, 8'hA5, 1'b0},     1'b1, 2'b10, 2'b00, 8'hA5, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd4:  apply_and_check("canon ADD R0,R3",   {OP_ADD,   2'b00, 2'b11, 7'b0},    1'b1, 2'b00, 2'b11, 8'h00, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd5:  apply_and_check("canon SUB R1,R2",   {OP_SUB,   2'b01, 2'b10, 7'b0},    1'b1, 2'b01, 2'b10, 8'h00, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd6:  apply_and_check("canon AND R2,R1",   {OP_AND,   2'b10, 2'b01, 7'b0},    1'b1, 2'b10, 2'b01, 8'h00, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd7:  apply_and_check("canon OR R3,R1",    {OP_OR,    2'b11, 2'b01, 7'b0},    1'b1, 2'b11, 2'b01, 8'h00, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd8:  apply_and_check("canon XOR R0,R2",   {OP_XOR,   2'b00, 2'b10, 7'b0},    1'b1, 2'b00, 2'b10, 8'h00, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd9:  apply_and_check("canon CMP R1,R3",   {OP_CMP,   2'b01, 2'b11, 7'b0},    1'b1, 2'b01, 2'b11, 8'h00, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd10: apply_and_check("canon JMP",         {OP_JMP,   11'b00000000000},       1'b1, 2'b00, 2'b00, 8'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd11: apply_and_check("canon JZ",          {OP_JZ,    11'b00000000000},       1'b1, 2'b00, 2'b00, 8'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0);
                5'd12: apply_and_check("canon JNZ",         {OP_JNZ,   11'b00000000000},       1'b1, 2'b00, 2'b00, 8'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b10, 1'b0, 1'b0, 1'b0);
                5'd13: apply_and_check("canon PUSH R3",     {OP_PUSH,  2'b11, 9'b000000000},   1'b1, 2'b11, 2'b00, 8'h00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 1'b1, 1'b0, 1'b0);
                5'd14: apply_and_check("canon POP R0",      {OP_POP,   2'b00, 9'b000000000},   1'b1, 2'b00, 2'b00, 8'h00, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 2'b00, 1'b0, 1'b1, 1'b0);
                5'd15: apply_and_check("canon IN R2",       {OP_IN,    2'b10, 9'b000000000},   1'b1, 2'b10, 2'b00, 8'h00, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd16: apply_and_check("canon OUT R1",      {OP_OUT,   2'b01, 9'b000000000},   1'b1, 2'b01, 2'b00, 8'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
                5'd17: apply_and_check("canon HALT",        {OP_HALT,  11'b00000000000},       1'b1, 2'b00, 2'b00, 8'h00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b1);
                default: begin
                    failures = failures + 1;
                    $display("FAIL: testbench bug, canon index %0d out of range", k);
                end
            endcase
        end
    endtask

    // ======================================================================
    // Test sequence
    // ======================================================================
    initial begin
        $dumpfile("instruction_decoder_waveform.vcd");
        $dumpvars(0, instruction_decoder_tb);

        checks      = 0;
        failures    = 0;
        instruction = 16'h0000;

        pats[0] = 11'h000;  pats[1] = 11'h7FF;  pats[2] = 11'h555;  pats[3] = 11'h2AA;
        pats[4] = 11'h001;  pats[5] = 11'h400;  pats[6] = 11'h0F0;  pats[7] = 11'h70F;
        #1;

        // ---- Canonical table, forward order (every opcode, every output) ----
        for (i = 0; i < 18; i = i + 1)
            canon(i);

        // ---- Two-register opcodes: all 16 A/B combinations each ----
        //                   name        opcode   regW   flagW
        test_two_reg("MOV",  OP_MOV, 1'b1, 1'b0);   // register write, no flags
        test_two_reg("ADD",  OP_ADD, 1'b1, 1'b1);
        test_two_reg("SUB",  OP_SUB, 1'b1, 1'b1);
        test_two_reg("AND",  OP_AND, 1'b1, 1'b1);
        test_two_reg("OR",   OP_OR,  1'b1, 1'b1);
        test_two_reg("XOR",  OP_XOR, 1'b1, 1'b1);
        test_two_reg("CMP",  OP_CMP, 1'b0, 1'b1);   // flags only, no register write

        // ---- LOADI: every destination register x all 256 immediates ----
        for (d = 0; d < 4; d = d + 1) begin
            for (n = 0; n < 256; n = n + 1) begin
                rd   = d;
                imm8 = n;
                apply_and_check("LOADI", {OP_LOADI, rd, imm8, 1'b0},
                    1'b1, rd, 2'b00, imm8,
                    1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00,
                    1'b0, 1'b0, 1'b0);
            end
        end

        // ---- Single-register opcodes: all four register selections ----
        //                    name     opcode    2nd   regW  memR  memW  push  pop
        test_single("LOAD",  OP_LOAD,  1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        test_single("STORE", OP_STORE, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        test_single("IN",    OP_IN,    1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        test_single("OUT",   OP_OUT,   1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        test_single("PUSH",  OP_PUSH,  1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0);
        test_single("POP",   OP_POP,   1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1);

        // ---- Jumps and HALT ----
        test_jump("JMP", OP_JMP, 2'b00);
        test_jump("JZ",  OP_JZ,  2'b01);
        test_jump("JNZ", OP_JNZ, 2'b10);
        apply_and_check("HALT", {OP_HALT, 11'b00000000000},
            1'b1, 2'b00, 2'b00, 8'h00,
            1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00,
            1'b0, 1'b0, 1'b1);

        // ---- Unsupported opcodes 10010..11111 (14 opcodes), 8 low-bit patterns each ----
        for (i = 18; i < 32; i = i + 1) begin
            op5 = i;
            for (j = 0; j < 8; j = j + 1)
                expect_invalid("unsupported opcode", {op5, pats[j]});
        end

        // ---- Reserved bits: each one individually, then several together ----
        // Bases use nonzero operand bits so legal operand bits are not mistaken for reserved bits.
        reserved_suite("reserved MOV",   {OP_MOV,   2'b11, 2'b10, 7'b0},  4'd7);
        reserved_suite("reserved ADD",   {OP_ADD,   2'b11, 2'b10, 7'b0},  4'd7);
        reserved_suite("reserved SUB",   {OP_SUB,   2'b11, 2'b10, 7'b0},  4'd7);
        reserved_suite("reserved AND",   {OP_AND,   2'b11, 2'b10, 7'b0},  4'd7);
        reserved_suite("reserved OR",    {OP_OR,    2'b11, 2'b10, 7'b0},  4'd7);
        reserved_suite("reserved XOR",   {OP_XOR,   2'b11, 2'b10, 7'b0},  4'd7);
        reserved_suite("reserved CMP",   {OP_CMP,   2'b11, 2'b10, 7'b0},  4'd7);
        reserved_suite("reserved LOADI", {OP_LOADI, 2'b11, 8'hFF, 1'b0},  4'd1);
        reserved_suite("reserved LOAD",  {OP_LOAD,  2'b11, 9'b0},         4'd9);
        reserved_suite("reserved STORE", {OP_STORE, 2'b11, 9'b0},         4'd9);
        reserved_suite("reserved IN",    {OP_IN,    2'b11, 9'b0},         4'd9);
        reserved_suite("reserved OUT",   {OP_OUT,   2'b11, 9'b0},         4'd9);
        reserved_suite("reserved PUSH",  {OP_PUSH,  2'b11, 9'b0},         4'd9);
        reserved_suite("reserved POP",   {OP_POP,   2'b11, 9'b0},         4'd9);
        reserved_suite("reserved JMP",   {OP_JMP,   11'b0},               4'd11);
        reserved_suite("reserved JZ",    {OP_JZ,    11'b0},               4'd11);
        reserved_suite("reserved JNZ",   {OP_JNZ,   11'b0},               4'd11);
        reserved_suite("reserved HALT",  {OP_HALT,  11'b0},               4'd11);

        // ---- Valid <-> invalid transitions (explicit sequences) ----
        // ADD valid -> reserved bit set -> valid again
        apply_and_check("trans ADD valid", {OP_ADD, 2'b10, 2'b01, 7'b0},
            1'b1, 2'b10, 2'b01, 8'h00, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
        expect_invalid("trans ADD reserved bit 3", {OP_ADD, 2'b10, 2'b01, 7'b0001000});
        apply_and_check("trans ADD valid again", {OP_ADD, 2'b10, 2'b01, 7'b0},
            1'b1, 2'b10, 2'b01, 8'h00, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
        // LOADI with immediate FF -> reserved bit -> LOADI valid
        apply_and_check("trans LOADI FF", {OP_LOADI, 2'b11, 8'hFF, 1'b0},
            1'b1, 2'b11, 2'b00, 8'hFF, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
        expect_invalid("trans LOADI reserved bit 0", {OP_LOADI, 2'b11, 8'hFF, 1'b1});
        apply_and_check("trans LOADI 5A", {OP_LOADI, 2'b01, 8'h5A, 1'b0},
            1'b1, 2'b01, 2'b00, 8'h5A, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
        // LOAD R3 -> unsupported opcode -> LOAD R3
        apply_and_check("trans LOAD valid", {OP_LOAD, 2'b11, 9'b0},
            1'b1, 2'b11, 2'b00, 8'h00, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
        expect_invalid("trans unsupported 11111", 16'hF800);
        apply_and_check("trans LOAD valid again", {OP_LOAD, 2'b11, 9'b0},
            1'b1, 2'b11, 2'b00, 8'h00, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0);
        // JZ valid -> reserved bit 10 -> JNZ valid
        apply_and_check("trans JZ valid", {OP_JZ, 11'b0},
            1'b1, 2'b00, 2'b00, 8'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0);
        expect_invalid("trans JZ reserved bit 10", {OP_JZ, 11'b10000000000});
        apply_and_check("trans JNZ valid", {OP_JNZ, 11'b0},
            1'b1, 2'b00, 2'b00, 8'h00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b10, 1'b0, 1'b0, 1'b0);
        // HALT valid -> reserved bit 5 -> HALT valid
        apply_and_check("trans HALT valid", {OP_HALT, 11'b0},
            1'b1, 2'b00, 2'b00, 8'h00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b1);
        expect_invalid("trans HALT reserved bit 5", {OP_HALT, 11'b00000100000});
        apply_and_check("trans HALT valid again", {OP_HALT, 11'b0},
            1'b1, 2'b00, 2'b00, 8'h00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b1);

        // ---- Back-to-back canonical instructions in other orders ----
        for (i = 17; i >= 0; i = i - 1)          // reverse order
            canon(i);
        for (i = 0; i < 18; i = i + 1)           // stride 7 visits all 18 opcodes
            canon((i * 7) % 18);
        for (i = 0; i < 18; i = i + 1)           // stride 5 visits all 18 opcodes
            canon((i * 5) % 18);
        // every valid opcode, then an unsupported opcode, then the same opcode again
        for (i = 0; i < 18; i = i + 1) begin
            canon(i);
            expect_invalid("sweep unsupported 11111", 16'hFFFF);
            canon(i);
            expect_invalid("sweep unsupported 10010", 16'h9000);
        end

        // ---------------- Summary ----------------
        $display("----------------------------------------");
        $display("Checks run: %0d   Failures: %0d", checks, failures);
        if (failures == 0) begin
            $display("PASS: all %0d checks passed", checks);
            $display("----------------------------------------");
            $finish;
        end else begin
            $display("FAIL: %0d of %0d checks failed", failures, checks);
            $display("----------------------------------------");
            $fatal(1, "instruction_decoder_tb: %0d check(s) failed", failures);
        end
    end

endmodule
