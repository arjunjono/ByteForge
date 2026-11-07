`timescale 1ns/1ps
// tb_program_rom.v - self-checking test of program_rom (Section 23 Stage 1)
//
// Run (from sim/):  iverilog -g2012 -Wall -o rom.vvp -s tb_program_rom ../rtl/program_rom.v ../tb/tb_program_rom.v
//                   vvp rom.vvp           (needs test_rom.hex from gen_test_files.py in the cwd)
// Expected ROM words are computed by the testbench formula, not by the DUT.
module tb_program_rom;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;

    reg         req = 0;
    reg  [15:0] addr = 0;
    wire        rdy;
    wire [15:0] rdata;

    program_rom #(.ROM_FILE("test_rom.hex")) dut (
        .clk(clk), .reset(reset), .prog_request(req), .prog_address(addr),
        .prog_ready(rdy), .prog_read_data(rdata));

    integer checks = 0, failures = 0;
    task check_eq(input [31:0] got, input [31:0] exp, input [8*56-1:0] name);
    begin
        checks = checks + 1;
        if (got !== exp) begin
            failures = failures + 1;
            $display("FAIL: %0s: expected 0x%0h, actual 0x%0h  (t=%0t)", name, exp, got, $time);
        end
    end
    endtask

    // independent expectation (same formula as sim/gen_test_files.py)
    function [15:0] expw(input integer i);
        reg [31:0] t;
    begin
        t = ((i * 40503 + 32'h1357) ^ (i >> 3)) & 32'hFFFF;
        expw = (t[15:0] == 16'h8800) ? 16'h8801 : t[15:0];
    end
    endfunction

    // every posedge where request && ready && !reset is one completion
    integer completions = 0;
    reg [15:0] comp_data;
    always @(posedge clk) if (req && rdy && !reset) begin
        completions = completions + 1;
        comp_data   = rdata;
    end
    // ready must never be high while reset is high
    integer ready_in_reset = 0;
    always @(posedge clk) if (reset && rdy) ready_in_reset = ready_in_reset + 1;

    // bus master: drive at negedge, DUT samples at posedge
    task fetch(input [15:0] a, output [15:0] d, output integer lat);
        integer n;
        reg done;
    begin
        @(negedge clk); addr = a; req = 1; n = 0; done = 0; d = 16'hxxxx;
        while (!done && n < 50) begin
            @(posedge clk); n = n + 1;
            if (rdy && req && !reset) begin d = rdata; done = 1; end
        end
        lat = n;
        check_eq(done, 1, "fetch completes before timeout");
        @(negedge clk); req = 0;
        @(negedge clk);                       // request low for a full cycle
    end
    endtask

    reg [15:0] d; integer lat, i;

    initial begin : timeout
        #40_000_000;
        $display("FAIL: global timeout");
        $fatal(1, "tb_program_rom timeout");
    end

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        @(negedge clk);

        // --- first and last valid words, latency ---
        fetch(16'h0000, d, lat);  check_eq(d, expw(0),    "ROM first word 0x0000");
        check_eq(lat, 2, "fetch takes 2 edges (capture + completion)");
        fetch(16'h1FFF, d, lat);  check_eq(d, expw(8191), "ROM last word 0x1FFF");
        fetch(16'h0001, d, lat);  check_eq(d, expw(1),    "ROM word 0x0001");

        // --- full sweep of every valid address ---
        for (i = 0; i < 8192; i = i + 1) begin
            fetch(i[15:0], d, lat);
            if (d !== expw(i)) check_eq(d, expw(i), "ROM sweep word");
            else checks = checks + 1;
        end

        // --- out of range: HALT, and not an alias of a valid word ---
        fetch(16'h2000, d, lat);  check_eq(d, 16'h8800, "0x2000 returns HALT (not word 0)");
        fetch(16'h2001, d, lat);  check_eq(d, 16'h8800, "0x2001 returns HALT");
        fetch(16'h3FFF, d, lat);  check_eq(d, 16'h8800, "0x3FFF returns HALT");
        fetch(16'h4000, d, lat);  check_eq(d, 16'h8800, "0x4000 returns HALT (not word 0)");
        fetch(16'h8000, d, lat);  check_eq(d, 16'h8800, "0x8000 returns HALT");
        fetch(16'hA000, d, lat);  check_eq(d, 16'h8800, "0xA000 returns HALT (aliases 0x0000 if 13 bits used)");
        fetch(16'hFFFF, d, lat);  check_eq(d, 16'h8800, "0xFFFF returns HALT (would alias 0x1FFF)");
        fetch(16'hE001, d, lat);  check_eq(d, 16'h8800, "0xE001 returns HALT");

        // --- held request completes once, no repeat ---
        completions = 0;
        @(negedge clk); addr = 16'h0123; req = 1;
        repeat (12) @(posedge clk);
        check_eq(completions, 1, "held request completes exactly once in 12 edges");
        check_eq(comp_data, expw(16'h0123), "held request data");
        @(negedge clk); req = 0;
        repeat (2) @(negedge clk);
        @(negedge clk); addr = 16'h0124; req = 1;      // new transaction after low interval
        repeat (6) @(posedge clk);
        check_eq(completions, 2, "second request after low interval completes once");
        check_eq(comp_data, expw(16'h0124), "second request data");
        @(negedge clk); req = 0; @(negedge clk);

        // --- request that drops before completion: no completion, FSM recovers ---
        completions = 0;
        @(negedge clk); addr = 16'h0200; req = 1;
        @(posedge clk);                                 // capture edge, now RDY
        @(negedge clk); req = 0;                        // withdrawn before completion edge
        repeat (4) @(negedge clk);
        check_eq(completions, 0, "withdrawn request never completes");
        fetch(16'h0201, d, lat);  check_eq(d, expw(16'h0201), "fetch after withdrawn request");

        // --- reset while ready is high: ready suppressed immediately, no completion ---
        completions = 0; ready_in_reset = 0;
        @(negedge clk); addr = 16'h0300; req = 1;
        @(posedge clk);                                 // E0 capture
        @(negedge clk);                                 // mid RDY cycle, ready would be 1
        check_eq(rdy, 1, "ready high in RDY cycle before reset");
        reset = 1;
        #1 check_eq(rdy, 0, "ready drops combinationally when reset asserts");
        req = 0;                                        // CPU withdraws request in reset
        repeat (3) @(posedge clk);
        check_eq(completions, 0, "no completion during/after reset-abandoned fetch");
        @(negedge clk); reset = 0;
        repeat (3) @(negedge clk);
        check_eq(completions, 0, "abandoned fetch does not complete after reset");
        check_eq(ready_in_reset, 0, "ready never high while reset high");
        fetch(16'h0300, d, lat);  check_eq(d, expw(16'h0300), "fetch after reset");

        // --- reset in the same cycle the request is raised ---
        completions = 0;
        @(negedge clk); addr = 16'h0301; req = 1; reset = 1;
        repeat (2) @(posedge clk);
        check_eq(completions, 0, "request raised during reset is not captured");
        @(negedge clk); reset = 0;                      // request still held: new transaction runs once
        repeat (8) @(posedge clk);
        check_eq(completions, 1, "held request after reset release completes once");
        check_eq(comp_data, expw(16'h0301), "data after reset release");
        @(negedge clk); req = 0; @(negedge clk);

        // --- reset in DONE state with request held: abandons, then one new transaction ---
        completions = 0;
        @(negedge clk); addr = 16'h0302; req = 1;
        repeat (3) @(posedge clk);                      // completed at E1, now DONE
        check_eq(completions, 1, "completed before DONE-state reset");
        @(negedge clk); reset = 1; req = 0;
        repeat (2) @(posedge clk);
        @(negedge clk); reset = 0; @(negedge clk);
        fetch(16'h0302, d, lat);  check_eq(d, expw(16'h0302), "fetch after DONE-state reset");

        // --- reset does not erase ROM ---
        @(negedge clk); reset = 1; repeat (4) @(negedge clk); reset = 0; @(negedge clk);
        fetch(16'h0000, d, lat);  check_eq(d, expw(0),    "ROM first word survives reset");
        fetch(16'h1FFF, d, lat);  check_eq(d, expw(8191), "ROM last word survives reset");
        fetch(16'h0FFF, d, lat);  check_eq(d, expw(4095), "ROM middle word survives reset");
        fetch(16'h2000, d, lat);  check_eq(d, 16'h8800, "out-of-range still HALT after reset");

        $display("tb_program_rom: %0d checks, %0d failures", checks, failures);
        if (failures == 0) $display("PASS: tb_program_rom");
        else $fatal(1, "FAIL: tb_program_rom (%0d failures)", failures);
        $finish;
    end
endmodule
