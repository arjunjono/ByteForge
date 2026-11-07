`timescale 1ns/1ps
// tb_production_timing.v - production parameters at the real 27 MHz (no shortened timings anywhere)
//
// Run (from sim/): iverilog -g2012 -Wall -o prod.vvp -s tb_production_timing <rtl files> ../tb/spi_monitor.v ../tb/tb_production_timing.v
// About 15 M clock cycles (a minute or two of simulation). Covers: derived parameter values, 10 ms debounce,
// 1 ms and 255 ms delays (full counter widths), the 100/100/100 ms panel reset sequence and the real SCLK rate.
// Expected values are written out here from CLK_HZ = 27 000 000 with plain arithmetic.
module tb_production_timing;
    localparam integer CLK_HZ = 27000000;
    // The simulator rounds delays to 1 ps: half period 18.5185 ns -> 18.519 ns, so the simulated clock period is 37.038 ns
    // (27 MHz is 37.037037 ns; +0.027 ppm... i.e. +0.0026 %). Time-based checks use the simulated period; clock-count checks are exact.
    localparam real    TCLK_NS = 37.038;
    reg clk = 0, reset = 1;
    always #18.519 clk = ~clk;

    reg req = 0, we = 0; reg [15:0] addr = 0; reg [7:0] wdata = 0;
    wire rdy; wire [7:0] rdata;
    reg [5:0] btn_n = 6'h3F;
    wire sclk, mosi, cs_n, dc, rst_n, bl, overrun;

    // all timing parameters left at their production defaults
    byteforge_io #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .reset(reset), .data_request(req), .data_write_enable(we), .data_address(addr),
        .data_write_data(wdata), .data_ready(rdy), .data_read_data(rdata), .btn_n(btn_n),
        .lcd_sclk(sclk), .lcd_mosi(mosi), .lcd_cs_n(cs_n), .lcd_dc(dc), .lcd_rst_n(rst_n), .lcd_bl(bl), .disp_overrun(overrun));
    spi_monitor mon (.sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dc(dc));

    integer checks = 0, failures = 0;
    task check_eq(input [63:0] got, input [63:0] exp, input [8*64-1:0] name);
    begin
        checks = checks + 1;
        if (got !== exp) begin failures = failures + 1;
            $display("FAIL: %0s: expected %0d, actual %0d (t=%0t)", name, exp, got, $time); end
    end
    endtask
    task check_near(input real got, input real exp, input real tol, input [8*64-1:0] name);
    begin
        checks = checks + 1;
        if (got < exp - tol || got > exp + tol) begin failures = failures + 1;
            $display("FAIL: %0s: expected %0.6f +/- %0.6f, actual %0.6f (t=%0t)", name, exp, tol, got, $time); end
    end
    endtask

    integer ec = 0; always @(posedge clk) ec = ec + 1;

    // pin/edge records
    integer ec_rst_rise1 = -1, ec_rst_fall = -1, ec_rst_rise2 = -1;
    real    t_rst_rise1, t_rst_fall, t_rst_rise2;
    reg rst_prev = 0; integer n_rise = 0;
    always @(negedge clk) begin
        if (rst_n && !rst_prev) begin n_rise = n_rise + 1;
            if (n_rise == 1) begin ec_rst_rise1 = ec; t_rst_rise1 = $realtime; end else begin ec_rst_rise2 = ec; t_rst_rise2 = $realtime; end end
        if (!rst_n && rst_prev) begin ec_rst_fall = ec; t_rst_fall = $realtime; end
        rst_prev = rst_n;
    end
    integer ec_pressed = -1; reg pr_prev = 0;
    always @(negedge clk) begin
        if (dut.u_buttons.pressed[2] !== pr_prev) ec_pressed = ec;
        pr_prev = dut.u_buttons.pressed[2];
    end

    integer lat; reg [7:0] rd_val;
    task xfer(input we_i, input [15:0] a, input [7:0] wd);
        integer n; reg done;
    begin
        @(negedge clk); we = we_i; addr = a; wdata = wd; req = 1; n = 0; done = 0; rd_val = 8'hxx;
        while (!done && n < 20000000) begin
            @(posedge clk); n = n + 1;
            if (rdy && req && !reset) begin rd_val = rdata; done = 1; end
        end
        lat = n;
        check_eq(done, 1, "transaction completes");
        @(negedge clk); req = 0; we = 0; @(negedge clk);
    end
    endtask

    initial begin : timeout
        #1_000_000_000;                                 // 1.0 s of simulated time (the test needs about 0.65 s)
        $display("FAIL: global timeout"); $fatal(1, "tb_production_timing timeout");
    end

    integer e_set; real t0, t1;
    initial begin
        // ---- derived parameter values, from plain arithmetic ----
        check_eq(dut.DEBOUNCE_CLKS, 270000, "DEBOUNCE_CLKS = 27e6 * 10 ms");
        check_eq(dut.CLKS_PER_MS, 27000, "CLKS_PER_MS = 27e6 / 1000");
        check_eq(dut.RST_HIGH1_CLKS, 2700000, "RST_HIGH1_CLKS = 100 ms");
        check_eq(dut.RST_LOW_CLKS, 2700000, "RST_LOW_CLKS = 100 ms");
        check_eq(dut.RST_HIGH2_CLKS, 2700000, "RST_HIGH2_CLKS = 100 ms");
        check_eq(dut.SPI_HALF_CLKS, 2, "SPI half period = 2 clocks (SCLK 6.75 MHz)");
        check_eq(dut.u_delay.SW, 15, "delay sub-ms counter is 15 bits wide (needs 26999 < 32768)");
        check_eq(dut.u_buttons.CW, 19, "debounce counter is 19 bits wide (needs 269999 < 524288)");

        // ---- panel reset sequence and startup (8.1 M clocks) ----
        repeat (4) @(negedge clk); t0 = $realtime;
        reset = 0;
        // read status immediately: startup active
        xfer(0, 16'hFF12, 8'h00); check_eq(rd_val[1], 1, "startup bit set after reset release");
        // poll until startup clears (each poll is cheap), note the time
        begin : poll integer k; k = 0; while (rd_val[1] && k < 400000) begin
            repeat (20000) @(negedge clk);                      // coarse poll step ~0.74 ms
            xfer(0, 16'hFF12, 8'h00); k = k + 1; end end
        t1 = $realtime;
        check_eq(rd_val[1], 0, "startup bit clears");
        check_near((t1 - t0) / 1.0e6, 300.0, 0.8, "startup ends about 300 ms after reset release (ms)");
        check_eq(n_rise, 2, "RST rises twice");
        check_near((t_rst_fall - t_rst_rise1) / 1.0e6, 100.0, 0.005, "RST high phase 1 = 100 ms");
        check_near((t_rst_rise2 - t_rst_fall) / 1.0e6, 100.0, 0.005, "RST low pulse = 100 ms");
        check_eq(ec_rst_fall - ec_rst_rise1, 2700000, "RST high phase 1 = 2 700 000 clocks");
        check_eq(ec_rst_rise2 - ec_rst_fall, 2700000, "RST low pulse = 2 700 000 clocks");

        // ---- 10 ms debounce at 27 MHz ----
        e_set = ec; btn_n[2] = 0;
        repeat (270000 + 20) @(negedge clk);
        check_eq(dut.u_buttons.pressed[2], 1, "button reported pressed after 10 ms");
        check_eq(ec_pressed, e_set + 270000 + 2, "press latency = 270 000 + 2 clocks");
        check_near((ec_pressed - e_set) * TCLK_NS / 1.0e6, 10.0, 0.002, "press latency about 10.000 ms");
        // a 9.9 ms bounce is rejected
        btn_n[2] = 1; repeat (270000 + 20) @(negedge clk);
        check_eq(dut.u_buttons.pressed[2], 0, "release reported");
        btn_n[2] = 0; repeat (267000) @(negedge clk); btn_n[2] = 1; repeat (300000) @(negedge clk);
        check_eq(dut.u_buttons.pressed[2], 0, "9.9 ms low pulse rejected at production debounce");

        // ---- delays at 27 MHz ----
        t0 = $realtime;
        xfer(1, 16'hFF20, 8'd1);
        t1 = $realtime;
        check_eq(lat, 27000 + 2, "1 ms delay = 27 000 clocks + capture/completion");
        check_near((t1 - t0) / 1.0e6, 1.0, 0.002, "1 ms delay in ms");
        t0 = $realtime;
        xfer(1, 16'hFF20, 8'd255);
        t1 = $realtime;
        check_eq(lat, 255 * 27000 + 2, "255 ms delay = 6 885 000 clocks + capture/completion");
        check_near((t1 - t0) / 1.0e6, 255.0, 0.02, "255 ms delay in ms");

        // ---- real SCLK rate and framing ----
        mon.clear;
        xfer(1, 16'hFF11, 8'hA7);
        xfer(0, 16'hFF12, 8'h00);
        begin : w integer k; k = 0; while (rd_val[0] && k < 1000) begin xfer(0, 16'hFF12, 8'h00); k = k + 1; end end
        check_eq(mon.n_bytes, 1, "one byte sent");
        check_eq(mon.byte_val[0], 8'hA7, "byte value"); check_eq(mon.byte_dc[0], 1, "DC=1");
        check_near(mon.min_high_ns, 2 * TCLK_NS, 0.01, "SCLK high = 2 clocks (74.07 ns)");
        check_near(mon.min_low_ns, 2 * TCLK_NS, 0.01, "SCLK low = 2 clocks (74.07 ns)");
        check_near(1000.0 / (mon.min_high_ns + mon.min_low_ns), 6.75, 0.001, "SCLK frequency 6.75 MHz");
        check_eq(overrun, 0, "no overrun");

        $display("tb_production_timing: %0d checks, %0d failures, %0d clocks simulated", checks, failures, ec);
        if (failures == 0) $display("PASS: tb_production_timing");
        else $fatal(1, "FAIL: tb_production_timing (%0d failures)", failures);
        $finish;
    end
endmodule
