`timescale 1ns/1ps
// tb_delay.v - blocking millisecond delay at 0xFF20 (short timing: 1 ms = 10 clocks)
//
// Run (from sim/): iverilog -g2012 -Wall -o delay.vvp -s tb_delay ../rtl/button_input.v ../rtl/data_bus.v \
//     ../rtl/delay_unit.v ../rtl/spi_display_ctrl.v ../rtl/byteforge_io.v ../tb/tb_delay.v && vvp delay.vvp
// Expected duration is computed here: the capture edge E0 is the first edge with request high;
// ready may first be high after edge E0 + value*CLKS_PER_MS and the completion edge is the one after.
module tb_delay;
    localparam integer MS = 10;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg req = 0, we = 0; reg [15:0] addr = 0; reg [7:0] wdata = 0;
    wire rdy; wire [7:0] rdata;
    wire sclk, mosi, cs_n, dc, rst_n, bl, overrun;

    byteforge_io #(.CLK_HZ(1000000), .DEBOUNCE_CLKS(4), .CLKS_PER_MS(MS), .SPI_HALF_CLKS(2),
                   .RST_HIGH1_CLKS(5), .RST_LOW_CLKS(5), .RST_HIGH2_CLKS(5)) dut (
        .clk(clk), .reset(reset), .data_request(req), .data_write_enable(we), .data_address(addr),
        .data_write_data(wdata), .data_ready(rdy), .data_read_data(rdata), .btn_n(6'h3F),
        .lcd_sclk(sclk), .lcd_mosi(mosi), .lcd_cs_n(cs_n), .lcd_dc(dc), .lcd_rst_n(rst_n),
        .lcd_bl(bl), .disp_overrun(overrun));

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

    integer completions = 0, early_ready = 0, rdy_in_reset = 0;
    always @(posedge clk) begin
        if (req && rdy && !reset) completions = completions + 1;
        if (reset && rdy) rdy_in_reset = rdy_in_reset + 1;
    end

    // measures edges from the capture edge (E0 = 1) to the completion edge; ready low before it
    integer lat; reg [7:0] rd_val;
    task xfer(input we_i, input [15:0] a, input [7:0] wd);
        integer n; reg done;
    begin
        @(negedge clk); we = we_i; addr = a; wdata = wd; req = 1; n = 0; done = 0; rd_val = 8'hxx; early_ready = 0;
        while (!done && n < 5000) begin
            @(posedge clk); n = n + 1;
            if (rdy && req && !reset) begin rd_val = rdata; done = 1; end
        end
        lat = n;
        check_eq(done, 1, "completes");
        @(negedge clk); req = 0; we = 0; @(negedge clk);
    end
    endtask

    // ready must be low on every posedge before the expected completion edge
    task delay_expect(input [7:0] v);
        integer n, expect_edge; reg done;
    begin
        expect_edge = v * MS + 1; if (v == 0) expect_edge = 1;
        @(negedge clk); we = 1; addr = 16'hFF20; wdata = v; req = 1; n = 0; done = 0; early_ready = 0;
        while (!done && n < 5000) begin
            @(posedge clk); n = n + 1;
            if (rdy && req && !reset) done = 1;
            else if (rdy) early_ready = early_ready + 1;
        end
        // v==0 and v>0 both: completion edge index n must equal expect_edge + 1 (E0 is edge 1)
        check_eq(n, expect_edge + 1, "completion edge count (value*clks_per_ms + capture + completion)");
        @(negedge clk); req = 0; we = 0; @(negedge clk);
        @(negedge clk);
    end
    endtask

    initial begin : timeout
        #50_000_000; $display("FAIL: global timeout"); $fatal(1, "tb_delay timeout");
    end

    integer t;
    initial begin
        repeat (3) @(negedge clk); reset = 0; @(negedge clk);

        // zero: no intentional delay (same latency as any 2-edge transaction)
        xfer(1, 16'hFF20, 8'h00); check_eq(lat, 2, "write 0 completes without delay");
        // reads return 0 and do not delay
        xfer(0, 16'hFF20, 8'h00); check_eq(lat, 2, "read FF20 no delay"); check_eq(rd_val, 8'h00, "read FF20 = 0");

        // durations
        delay_expect(8'd1);
        delay_expect(8'd2);
        delay_expect(8'd3);
        delay_expect(8'd7);
        delay_expect(8'd100);
        delay_expect(8'd255);
        delay_expect(8'd0);

        // value captured once: changing wdata while stalled has no effect
        completions = 0;
        @(negedge clk); we = 1; addr = 16'hFF20; wdata = 8'd4; req = 1;
        @(posedge clk);                         // E0 capture
        @(negedge clk); wdata = 8'd200;         // protocol violation, must be ignored
        t = 1;
        while (completions == 0 && t < 3000) begin @(posedge clk); #1; t = t + 1; end
        check_eq(t, 4 * MS + 1 + 1 - 0, "captured value used (4 ms), not the changed 200 ms");
        check_eq(completions, 1, "single completion");
        // held request does not repeat the delay
        repeat (3 * MS * 4) @(posedge clk);
        check_eq(completions, 1, "held request after delay does not complete or delay again");
        @(negedge clk); req = 0; we = 0; @(negedge clk);

        // a following normal transaction is not delayed
        xfer(1, 16'h0010, 8'h12); check_eq(lat, 2, "transaction after delay is not delayed");
        xfer(0, 16'h0010, 8'h00); check_eq(rd_val, 8'h12, "RAM works after delay");

        // reset cancels a delay in progress
        rdy_in_reset = 0; completions = 0;
        @(negedge clk); we = 1; addr = 16'hFF20; wdata = 8'd10; req = 1;
        repeat (3 * MS) @(posedge clk);         // ~3 of 10 ms elapsed
        @(negedge clk); reset = 1; req = 0; we = 0;
        repeat (2) @(negedge clk); reset = 0; @(negedge clk);
        check_eq(completions, 0, "cancelled delay never completes");
        check_eq(rdy_in_reset, 0, "ready not asserted during reset");
        xfer(1, 16'h0011, 8'h34); check_eq(lat, 2, "transaction right after reset is not delayed (timer cancelled)");
        repeat (12 * MS) @(posedge clk);
        check_eq(completions, 1, "no late completion of cancelled delay (only the new write)");

        // reset on the capture edge: delay never starts
        completions = 0;
        @(negedge clk); reset = 1; we = 1; addr = 16'hFF20; wdata = 8'd5; req = 1;
        repeat (2) @(negedge clk); req = 0; we = 0; reset = 0; @(negedge clk);
        xfer(0, 16'h0011, 8'h00); check_eq(lat, 2, "no delay left over after reset on capture edge");
        check_eq(rd_val, 8'h34, "RAM survived");

        // request withdrawn without reset cancels the delay
        @(negedge clk); we = 1; addr = 16'hFF20; wdata = 8'd9; req = 1;
        repeat (2 * MS) @(posedge clk);
        @(negedge clk); req = 0; we = 0;
        repeat (2) @(negedge clk);
        xfer(0, 16'h0011, 8'h00); check_eq(lat, 2, "delay cancelled when request withdrawn");

        $display("tb_delay: %0d checks, %0d failures", checks, failures);
        if (failures == 0) $display("PASS: tb_delay");
        else $fatal(1, "FAIL: tb_delay (%0d failures)", failures);
        $finish;
    end
endmodule
