`timescale 1ns/1ps
// tb_buttons.v - button_input: synchronizer latency, debounce, bounce rejection, independence, reset
//
// Run (from sim/): iverilog -g2012 -Wall -o btn.vvp -s tb_buttons ../rtl/button_input.v ../tb/tb_buttons.v && vvp btn.vvp
// Timing model (derived independently of the RTL): a raw change made between edges is first sampled by the
// synchronizer at edge S; the reported (debounced) output changes at edge S + DEB + 1, i.e. DEB + 2 edges
// after the testbench edge counter value at which the pin was changed (change made after edge E, S = E+1).
module tb_buttons;
    localparam integer DEB = 8;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg  [5:0] raw = 6'h3F;
    wire [5:0] pressed;
    button_input #(.N(6), .CLK_HZ(1000000), .DEBOUNCE_CLKS(DEB)) dut (.clk(clk), .reset(reset), .btn_n(raw), .pressed(pressed));

    reg  [1:0] raw1 = 2'b11; wire [1:0] pressed1;
    button_input #(.N(2), .CLK_HZ(1000000), .DEBOUNCE_CLKS(1)) dut1 (.clk(clk), .reset(reset), .btn_n(raw1), .pressed(pressed1));

    integer checks = 0, failures = 0;
    task check_eq(input [31:0] got, input [31:0] exp, input [8*60-1:0] name);
    begin
        checks = checks + 1;
        if (got !== exp) begin
            failures = failures + 1;
            $display("FAIL: %0s: expected %0d (0x%0h), actual %0d (0x%0h)  (t=%0t)", name, exp, exp, got, got, $time);
        end
    end
    endtask

    // edge counter and change recorder (look at outputs at negedge: they changed due to the previous posedge)
    integer ec = 0;
    always @(posedge clk) ec = ec + 1;
    reg [5:0] prev = 6'h00;
    reg [5:0] prev1 = 2'b00;
    integer last_change_ec [0:5];
    integer n_changes [0:5];
    integer last_change1_ec;
    integer q, qa;
    initial begin for (q = 0; q < 6; q = q + 1) begin last_change_ec[q] = -1; n_changes[q] = 0; end end
    always @(negedge clk) begin
        for (qa = 0; qa < 6; qa = qa + 1)
            if (pressed[qa] !== prev[qa]) begin last_change_ec[qa] = ec; n_changes[qa] = n_changes[qa] + 1; end
        prev = pressed;
        if (pressed1 !== prev1) last_change1_ec = ec;
        prev1 = pressed1;
    end

    task tick(input integer n); begin repeat (n) @(negedge clk); end endtask

    integer e_set, base;
    reg [5:0] snapshot;

    initial begin : timeout
        #5_000_000; $display("FAIL: global timeout"); $fatal(1, "tb_buttons timeout");
    end

    initial begin
        // ---- reset: held low pin must not show as pressed during reset ----
        raw = 6'b111110;                              // Up held low during reset
        tick(5);
        check_eq(pressed, 6'b000000, "outputs released while in reset (button held)");
        check_eq(^pressed1 !== 1'bx, 1, "debounced outputs are not X after reset");
        reset = 0; e_set = ec;                        // reset released after edge e_set: first sampling edge e_set+1
        tick(DEB + 6);
        check_eq(pressed[0], 1, "button held through reset appears pressed after the debounce time");
        check_eq(last_change_ec[0], e_set + DEB + 2, "held-at-reset button: pressed edge");
        raw = 6'h3F; tick(DEB + 6);
        check_eq(pressed, 6'b000000, "released");

        // ---- no false press with idle pins ----
        base = n_changes[0] + n_changes[1] + n_changes[2] + n_changes[3] + n_changes[4] + n_changes[5];
        tick(200);
        check_eq(n_changes[0] + n_changes[1] + n_changes[2] + n_changes[3] + n_changes[4] + n_changes[5], base, "no spurious changes when idle");

        // ---- exact synchronizer + debounce latency, press and release, all six inputs ----
        for (q = 0; q < 6; q = q + 1) begin
            tick(3); e_set = ec; raw[q] = 1'b0;
            tick(DEB + 6);
            check_eq(pressed[q], 1, "press reported");
            check_eq(last_change_ec[q], e_set + DEB + 2, "press latency = sync(1)+DEB+1 edges after first sample");
            snapshot = pressed;
            check_eq(snapshot, (6'h01 << q), "only that button reports pressed");
            e_set = ec; raw[q] = 1'b1;
            tick(DEB + 6);
            check_eq(pressed[q], 0, "release reported");
            check_eq(last_change_ec[q], e_set + DEB + 2, "release latency equals press latency");
        end

        // ---- bounce on press: short low/high bursts never report; final stable low does ----
        base = n_changes[2];
        tick(4);
        raw[2] = 0; tick(3); raw[2] = 1; tick(2); raw[2] = 0; tick(DEB - 2); raw[2] = 1; tick(1);
        raw[2] = 0; tick(2); raw[2] = 1; tick(3); raw[2] = 0; tick(1); raw[2] = 1; tick(DEB);
        check_eq(n_changes[2], base, "bounce shorter than the debounce time never reports");
        check_eq(pressed[2], 0, "bounce: still released");
        e_set = ec; raw[2] = 0;                       // settles low
        tick(DEB + 6);
        check_eq(pressed[2], 1, "bounce then stable low reports pressed");
        check_eq(last_change_ec[2], e_set + DEB + 2, "time counted from the last bounce edge");

        // ---- one-clock glitches are ignored (on idle and while pressed) ----
        base = n_changes[4];
        raw[4] = 0; tick(1); raw[4] = 1; tick(DEB + 4);
        check_eq(n_changes[4], base, "single-clock low glitch ignored");
        base = n_changes[2];
        raw[2] = 1; tick(1); raw[2] = 0; tick(DEB + 4);
        check_eq(n_changes[2], base, "single-clock high glitch while pressed ignored");
        check_eq(pressed[2], 1, "still pressed after glitch");

        // ---- release bounce ----
        raw[2] = 1; tick(DEB - 3); raw[2] = 0; tick(2); raw[2] = 1; tick(DEB - 2); raw[2] = 0; tick(DEB - 3);
        check_eq(pressed[2], 1, "release bounce shorter than debounce keeps button pressed");
        e_set = ec; raw[2] = 1; tick(DEB + 6);
        check_eq(pressed[2], 0, "stable release reported");
        check_eq(last_change_ec[2], e_set + DEB + 2, "release time counted from last bounce edge");

        // ---- independence: staggered presses, one bouncing, release of one does not disturb others ----
        base = n_changes[1];
        e_set = ec; raw[0] = 0;
        tick(3);  raw[3] = 0;                         // +3
        tick(2);  raw[4] = 0;                         // +5
        // input 1 bounces for the whole interval
        raw[1] = 0; tick(2); raw[1] = 1; tick(2); raw[1] = 0; tick(2); raw[1] = 1; tick(2);
        tick(DEB + 4);
        check_eq(last_change_ec[0], e_set + DEB + 2, "independent: Up edge");
        check_eq(last_change_ec[3], e_set + 3 + DEB + 2, "independent: Right edge");
        check_eq(last_change_ec[4], e_set + 5 + DEB + 2, "independent: Action A edge");
        check_eq(n_changes[1], base, "independent: bouncing Down never reports");
        check_eq(pressed, 6'b011001, "independent: Up, Right, A pressed");
        e_set = ec; raw[3] = 1; tick(DEB + 4);
        check_eq(pressed, 6'b010001, "independent: releasing Right leaves Up and A");
        raw[0] = 1; raw[4] = 1; tick(DEB + 6);
        check_eq(pressed, 6'b000000, "all released");

        // ---- reset in the middle of a debounce count clears the counter ----
        tick(3); raw[5] = 0; tick(DEB / 2);
        reset = 1; tick(2); reset = 0; e_set = ec;
        tick(DEB + 6);
        check_eq(last_change_ec[5], e_set + DEB + 2, "reset restarts the debounce count");
        check_eq(pressed[5], 1, "button still low after reset is reported pressed after full debounce");
        raw[5] = 1; tick(DEB + 6);

        // ---- smallest debounce setting (1 clock) ----
        tick(2); e_set = ec; raw1[1] = 0; tick(8);
        check_eq(pressed1, 2'b10, "DEB=1: press reported");
        check_eq(last_change1_ec, e_set + 1 + 2, "DEB=1: latency 3 edges");
        raw1[1] = 1; tick(8);
        check_eq(pressed1, 2'b00, "DEB=1: release reported");

        $display("tb_buttons: %0d checks, %0d failures", checks, failures);
        if (failures == 0) $display("PASS: tb_buttons");
        else $fatal(1, "FAIL: tb_buttons (%0d failures)", failures);
        $finish;
    end
endmodule
