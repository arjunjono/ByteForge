// registers_tb.v - self-checking testbench for register_file and flags_register
`timescale 1ns/1ps

module registers_tb;

    // ---------------- Signals ----------------
    reg        clk;
    reg        reset;
    reg        write_enable;
    reg  [1:0] write_addr;
    reg  [7:0] write_data;
    reg  [1:0] read_addr_a;
    reg  [1:0] read_addr_b;
    reg        flags_write_enable;
    reg        Z_in, C_in, N_in;

    wire [7:0] read_data_a;
    wire [7:0] read_data_b;
    wire       Z, C, N;

    integer checks;
    integer failures;
    integer i;
    integer edge_count;     // counts rising clock edges
    integer edges_before;
    reg [2:0] combo;

    // ---------------- Devices under test ----------------
    register_file rf (
        .clk         (clk),
        .reset       (reset),
        .write_enable(write_enable),
        .write_addr  (write_addr),
        .write_data  (write_data),
        .read_addr_a (read_addr_a),
        .read_addr_b (read_addr_b),
        .read_data_a (read_data_a),
        .read_data_b (read_data_b)
    );

    flags_register fr (
        .clk               (clk),
        .reset             (reset),
        .flags_write_enable(flags_write_enable),
        .Z_in              (Z_in),
        .C_in              (C_in),
        .N_in              (N_in),
        .Z                 (Z),
        .C                 (C),
        .N                 (N)
    );

    // ---------------- Clock: 10 ns period ----------------
    // Rising edges at 5, 15, 25 ns ...  Falling edges at 10, 20, 30 ns ...
    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) edge_count = edge_count + 1;

    // ---------------- Checking tasks ----------------
    task check_val;
        input [8*40-1:0] name;
        input [8*20-1:0] what;
        input [7:0]      expected;
        input [7:0]      actual;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                failures = failures + 1;
                $display("FAIL @%0d ns: %0s: %0s expected 0x%h, actual 0x%h",
                         $time, name, what, expected, actual);
            end
        end
    endtask

    task check_a;
        input [8*40-1:0] name;
        input [7:0]      expected;
        begin
            check_val(name, "read_data_a", expected, read_data_a);
        end
    endtask

    task check_b;
        input [8*40-1:0] name;
        input [7:0]      expected;
        begin
            check_val(name, "read_data_b", expected, read_data_b);
        end
    endtask

    task check_flags;
        input [8*40-1:0] name;
        input            exp_z;
        input            exp_c;
        input            exp_n;
        begin
            checks = checks + 1;
            if (Z !== exp_z || C !== exp_c || N !== exp_n) begin
                failures = failures + 1;
                $display("FAIL @%0d ns: %0s: flags (Z,C,N) expected %b%b%b, actual %b%b%b",
                         $time, name, exp_z, exp_c, exp_n, Z, C, N);
            end
        end
    endtask

    // Reads R0..R3 using both read ports (two addresses at a time).
    // Read addresses are not sampled by the clock, so they may change
    // between rising edges. Takes 2 ns in total.
    task check_regs;
        input [8*40-1:0] name;
        input [7:0] e0;
        input [7:0] e1;
        input [7:0] e2;
        input [7:0] e3;
        begin
            read_addr_a = 2'b00;
            read_addr_b = 2'b01;
            #1;
            check_val(name, "R0 via port A", e0, read_data_a);
            check_val(name, "R1 via port B", e1, read_data_b);
            read_addr_a = 2'b10;
            read_addr_b = 2'b11;
            #1;
            check_val(name, "R2 via port A", e2, read_data_a);
            check_val(name, "R3 via port B", e3, read_data_b);
        end
    endtask

    // ---------------- Test sequence ----------------
    // Inputs are driven right after @(negedge clk).
    // Stored outputs are checked at @(posedge clk) followed by #1.
    initial begin
        $dumpfile("registers_waveform.vcd");
        $dumpvars(0, registers_tb);

        checks     = 0;
        failures   = 0;
        edge_count = 0;

        // Initial input values, applied before the first rising edge (5 ns)
        reset              = 1'b1;
        write_enable       = 1'b0;
        write_addr         = 2'b00;
        write_data         = 8'h00;
        read_addr_a        = 2'b00;
        read_addr_b        = 2'b01;
        flags_write_enable = 1'b0;
        Z_in = 1'b0; C_in = 1'b0; N_in = 1'b0;

        // ===== T1: initial reset clears all registers and flags =====
        @(posedge clk); #1;
        check_regs("T1 initial reset", 8'h00, 8'h00, 8'h00, 8'h00);
        check_flags("T1 initial reset", 1'b0, 1'b0, 1'b0);

        // ===== T3 + T4: write a distinct value into every register =====
        // After each write, the other registers must be unchanged.
        @(negedge clk);
        reset = 1'b0; write_enable = 1'b1; write_addr = 2'b00; write_data = 8'hA1;
        @(posedge clk); #1;
        check_regs("T3/T4 write R0=A1", 8'hA1, 8'h00, 8'h00, 8'h00);

        @(negedge clk);
        write_addr = 2'b01; write_data = 8'hB2;
        @(posedge clk); #1;
        check_regs("T3/T4 write R1=B2", 8'hA1, 8'hB2, 8'h00, 8'h00);

        @(negedge clk);
        write_addr = 2'b10; write_data = 8'hC3;
        @(posedge clk); #1;
        check_regs("T3/T4 write R2=C3", 8'hA1, 8'hB2, 8'hC3, 8'h00);

        @(negedge clk);
        write_addr = 2'b11; write_data = 8'hD4;
        @(posedge clk); #1;
        check_regs("T3/T4 write R3=D4", 8'hA1, 8'hB2, 8'hC3, 8'hD4);

        // T4: overwrite only R1, others must keep their values
        @(negedge clk);
        write_addr = 2'b01; write_data = 8'h3C;
        @(posedge clk); #1;
        check_regs("T4 overwrite R1=3C", 8'hA1, 8'h3C, 8'hC3, 8'hD4);

        // ===== T5 + T6: two read ports =====
        // State: R0=A1 R1=3C R2=C3 R3=D4
        @(negedge clk);
        write_enable = 1'b0;
        read_addr_a = 2'b00; read_addr_b = 2'b11; #1;          // different registers
        check_a("T5 A=R0", 8'hA1);
        check_b("T5 B=R3", 8'hD4);
        read_addr_a = 2'b01; read_addr_b = 2'b10; #1;
        check_a("T5 A=R1", 8'h3C);
        check_b("T5 B=R2", 8'hC3);
        read_addr_a = 2'b10; read_addr_b = 2'b10; #1;          // same register (T6)
        check_a("T6 A=R2", 8'hC3);
        check_b("T6 B=R2", 8'hC3);

        // ===== T7: reads change with the address, with no clock edge =====
        @(negedge clk);
        edges_before = edge_count;
        read_addr_a = 2'b00; read_addr_b = 2'b00; #1;
        check_a("T6 A=R0", 8'hA1);
        check_b("T6 B=R0", 8'hA1);
        read_addr_a = 2'b11; #1;
        check_a("T7 A changed to R3", 8'hD4);
        check_b("T7 B unchanged R0", 8'hA1);
        read_addr_b = 2'b01; #1;
        check_b("T7 B changed to R1", 8'h3C);
        checks = checks + 1;
        if (edge_count !== edges_before) begin
            failures = failures + 1;
            $display("FAIL @%0d ns: T7 a clock edge occurred during the async read test", $time);
        end

        // ===== T8: write_enable=0 ignores write_addr / write_data =====
        @(negedge clk);
        write_enable = 1'b0; write_addr = 2'b01; write_data = 8'hEE;
        @(posedge clk); #1;
        check_regs("T8 we=0 (R1,EE)", 8'hA1, 8'h3C, 8'hC3, 8'hD4);

        @(negedge clk);
        write_addr = 2'b10; write_data = 8'h77;
        @(posedge clk); #1;
        check_regs("T8 we=0 (R2,77)", 8'hA1, 8'h3C, 8'hC3, 8'hD4);

        // ===== T9 + T10: write takes effect only at the rising edge =====
        // Port A reads R0 while R0 is being written.
        @(negedge clk);
        write_enable = 1'b1; write_addr = 2'b00; write_data = 8'h66;
        read_addr_a = 2'b00; read_addr_b = 2'b01;
        #2;
        check_a("T9/T10 before edge, R0 old", 8'hA1);
        check_b("T9/T10 before edge, R1", 8'h3C);
        #2;
        check_a("T9/T10 just before edge, R0 old", 8'hA1);
        @(posedge clk); #1;
        check_a("T9/T10 after edge, R0 new", 8'h66);
        check_b("T9/T10 after edge, R1", 8'h3C);
        check_regs("T9/T10 after edge", 8'h66, 8'h3C, 8'hC3, 8'hD4);

        // ===== T11: store 0x00 and 0xFF =====
        @(negedge clk);
        write_addr = 2'b01; write_data = 8'h00;
        @(posedge clk); #1;
        check_regs("T11 R1=00", 8'h66, 8'h00, 8'hC3, 8'hD4);

        @(negedge clk);
        write_addr = 2'b10; write_data = 8'hFF;
        @(posedge clk); #1;
        check_regs("T11 R2=FF", 8'h66, 8'h00, 8'hFF, 8'hD4);

        // ===== T12: store all eight Z/C/N combinations =====
        @(negedge clk);
        write_enable = 1'b0; flags_write_enable = 1'b1;
        for (i = 0; i < 8; i = i + 1) begin
            combo = i;
            Z_in = combo[2]; C_in = combo[1]; N_in = combo[0];
            @(posedge clk); #1;
            check_flags("T12 flag combination", combo[2], combo[1], combo[0]);
            @(negedge clk);
        end
        // Registers must not have changed during the flag-only writes (T15)
        check_regs("T12/T15 regs unchanged", 8'h66, 8'h00, 8'hFF, 8'hD4);

        // ===== T13: flags_write_enable=0 preserves flags =====
        // Put a known value (Z=1, C=0, N=1) into the flags first.
        // (Time is now just after a falling edge.)
        @(negedge clk);
        Z_in = 1'b1; C_in = 1'b0; N_in = 1'b1;
        @(posedge clk); #1;
        check_flags("T13 set flags 101", 1'b1, 1'b0, 1'b1);

        @(negedge clk);
        flags_write_enable = 1'b0; Z_in = 1'b0; C_in = 1'b1; N_in = 1'b0;
        @(posedge clk); #1;
        check_flags("T13 fwe=0, inputs 010", 1'b1, 1'b0, 1'b1);

        @(negedge clk);
        Z_in = 1'b1; C_in = 1'b1; N_in = 1'b1;
        @(posedge clk); #1;
        check_flags("T13 fwe=0, inputs 111", 1'b1, 1'b0, 1'b1);

        // ===== T14: register write without changing flags =====
        @(negedge clk);
        write_enable = 1'b1; write_addr = 2'b11; write_data = 8'h12;
        flags_write_enable = 1'b0; Z_in = 1'b0; C_in = 1'b1; N_in = 1'b0;
        @(posedge clk); #1;
        check_regs("T14 reg-only write", 8'h66, 8'h00, 8'hFF, 8'h12);
        check_flags("T14 flags unchanged", 1'b1, 1'b0, 1'b1);

        // ===== T15: flag write without changing registers =====
        @(negedge clk);
        write_enable = 1'b0; write_addr = 2'b00; write_data = 8'h99;
        flags_write_enable = 1'b1; Z_in = 1'b0; C_in = 1'b1; N_in = 1'b0;
        @(posedge clk); #1;
        check_regs("T15 flag-only write", 8'h66, 8'h00, 8'hFF, 8'h12);
        check_flags("T15 flags updated", 1'b0, 1'b1, 1'b0);

        // ===== T16: both update on the same rising edge =====
        @(negedge clk);
        write_enable = 1'b1; write_addr = 2'b01; write_data = 8'h7E;
        flags_write_enable = 1'b1; Z_in = 1'b1; C_in = 1'b1; N_in = 1'b0;
        @(posedge clk); #1;
        check_regs("T16 both update", 8'h66, 8'h7E, 8'hFF, 8'h12);
        check_flags("T16 both update", 1'b1, 1'b1, 1'b0);

        // ===== T2: reset is synchronous =====
        // Registers and flags are populated. Assert reset between edges.
        @(negedge clk);
        reset = 1'b1; write_enable = 1'b0; flags_write_enable = 1'b0;
        #1;
        check_regs("T2 reset asserted, before edge", 8'h66, 8'h7E, 8'hFF, 8'h12);
        check_flags("T2 reset asserted, before edge", 1'b1, 1'b1, 1'b0);
        @(posedge clk); #1;
        check_regs("T2 after edge", 8'h00, 8'h00, 8'h00, 8'h00);
        check_flags("T2 after edge", 1'b0, 1'b0, 1'b0);

        // Release reset; with no writes everything stays at zero
        @(negedge clk);
        reset = 1'b0;
        @(posedge clk); #1;
        check_regs("T2 reset released, idle", 8'h00, 8'h00, 8'h00, 8'h00);
        check_flags("T2 reset released, idle", 1'b0, 1'b0, 1'b0);

        // Re-populate (registers and flags written on the same edge)
        @(negedge clk);
        write_enable = 1'b1; write_addr = 2'b00; write_data = 8'h3A;
        flags_write_enable = 1'b1; Z_in = 1'b1; C_in = 1'b0; N_in = 1'b1;
        @(posedge clk); #1;
        check_regs("Re-populate R0", 8'h3A, 8'h00, 8'h00, 8'h00);
        check_flags("Re-populate flags", 1'b1, 1'b0, 1'b1);

        @(negedge clk);
        write_addr = 2'b11; write_data = 8'hC5;
        @(posedge clk); #1;
        check_regs("Re-populate R3", 8'h3A, 8'h00, 8'h00, 8'hC5);

        // ===== T17: reset wins even with both write enables asserted =====
        @(negedge clk);
        reset = 1'b1; write_enable = 1'b1; write_addr = 2'b01; write_data = 8'hFF;
        flags_write_enable = 1'b1; Z_in = 1'b1; C_in = 1'b1; N_in = 1'b1;
        @(posedge clk); #1;
        check_regs("T17 reset with enables", 8'h00, 8'h00, 8'h00, 8'h00);
        check_flags("T17 reset with enables", 1'b0, 1'b0, 1'b0);

        // ===== T18: writes work again after reset is released =====
        @(negedge clk);
        reset = 1'b0; write_enable = 1'b1; write_addr = 2'b10; write_data = 8'h5C;
        flags_write_enable = 1'b1; Z_in = 1'b0; C_in = 1'b1; N_in = 1'b1;
        @(posedge clk); #1;
        check_regs("T18 write after reset", 8'h00, 8'h00, 8'h5C, 8'h00);
        check_flags("T18 flags after reset", 1'b0, 1'b1, 1'b1);

        @(negedge clk);
        write_addr = 2'b00; write_data = 8'hE1; flags_write_enable = 1'b0;
        @(posedge clk); #1;
        check_regs("T18 second write", 8'hE1, 8'h00, 8'h5C, 8'h00);
        check_flags("T18 flags kept", 1'b0, 1'b1, 1'b1);

        // ---------------- Summary ----------------
        $display("----------------------------------------");
        $display("Checks run: %0d   Failures: %0d", checks, failures);
        if (failures == 0)
            $display("PASS: all %0d checks passed", checks);
        else
            $display("FAIL: %0d of %0d checks failed", failures, checks);
        $display("----------------------------------------");

        $finish;
    end

endmodule
