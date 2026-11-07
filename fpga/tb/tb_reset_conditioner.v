`timescale 1ns/1ps
// tb_reset_conditioner.v - power-up reset hold, asynchronous assert, synchronous release
// Run (from sim/): iverilog -g2012 -Wall -o rst.vvp -s tb_reset_conditioner ../rtl/reset_conditioner.v ../tb/tb_reset_conditioner.v && vvp rst.vvp
module tb_reset_conditioner;
    localparam integer POR = 16;
    reg clk = 0; always #5 clk = ~clk;
    reg ext_rst_n = 1;
    wire rst_out;
    reset_conditioner #(.POR_CYCLES(POR)) dut (.clk(clk), .ext_rst_n(ext_rst_n), .rst_out(rst_out));

    integer checks = 0, failures = 0;
    task check_eq(input [31:0] got, input [31:0] exp, input [8*60-1:0] name);
    begin
        checks = checks + 1;
        if (got !== exp) begin failures = failures + 1;
            $display("FAIL: %0s: expected %0d, actual %0d (t=%0t)", name, exp, got, $time); end
    end
    endtask

    integer ec = 0; always @(posedge clk) ec = ec + 1;
    integer ec_fall, ec_rise; reg prev = 1;
    always @(negedge clk) begin
        if (!rst_out && prev) ec_fall = ec;
        if (rst_out && !prev) ec_rise = ec;
        prev = rst_out;
    end

    integer e0;
    initial begin : timeout
        #1_000_000; $display("FAIL: global timeout"); $fatal(1, "tb_reset_conditioner timeout");
    end
    initial begin
        // power-up: reset is active from the first clock with no external action
        check_eq(rst_out, 1, "reset active at time 0 (register initial value)");
        repeat (POR + 8) @(negedge clk);
        check_eq(rst_out, 0, "power-up reset released");
        // POR_CYCLES clocks of hold plus the output register: falls after edge POR+1
        check_eq(ec_fall, POR + 1, "power-up reset length");
        // external reset asserts asynchronously (chain) and reaches rst_out at the next clock edge
        @(negedge clk); e0 = ec; ext_rst_n = 0;
        #1 check_eq(dut.chain[1], 1, "chain asserted immediately (asynchronous assert)");
        @(negedge clk);
        check_eq(rst_out, 1, "rst_out high at the next edge after button press");
        repeat (5) @(negedge clk);
        check_eq(rst_out, 1, "reset held while button held");
        // release synchronous: chain needs two clean edges, rst_out falls on the third
        @(negedge clk); ext_rst_n = 1; e0 = ec;
        repeat (6) @(negedge clk);
        check_eq(rst_out, 0, "reset released after the button is released");
        check_eq(ec_fall, e0 + 3, "release is synchronous: three edges after button release");
        // a glitch narrower than a clock period, between edges, still resets
        @(negedge clk); #1 ext_rst_n = 0; #1 ext_rst_n = 1;
        @(negedge clk);
        check_eq(rst_out, 1, "sub-clock low pulse on the reset pin still resets");
        repeat (6) @(negedge clk);
        check_eq(rst_out, 0, "and releases cleanly");
        // button released on a non-clock instant does not violate: no X
        check_eq(^rst_out !== 1'bx, 1, "output never X");

        $display("tb_reset_conditioner: %0d checks, %0d failures", checks, failures);
        if (failures == 0) $display("PASS: tb_reset_conditioner");
        else $fatal(1, "FAIL: tb_reset_conditioner (%0d failures)", failures);
        $finish;
    end
endmodule
