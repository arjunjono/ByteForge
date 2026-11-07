`timescale 1ns/1ps
// tb_demo.v - the assembled demo (build/byteforge_rom.hex) running on the real CPU, ROM, RAM and peripherals.
//
// Run (from sim/work/ after sim/run_all.sh copied the files): see sim/run_all.sh. Needs in the cwd:
//   byteforge_rom.hex (from sw/build_rom.py) and ref_init.hex (from sw/extract_reference_init.py).
//
// Everything checked here comes from outside the design:
//   * SPI bytes are decoded from the pins by spi_monitor.v (written separately from spi_display_ctrl.v);
//   * the expected panel-init stream is read from ref_init.hex, which is extracted from Waveshare's own
//     LCD_2in.c (LCD_2IN_InitReg), not from demo.asm;
//   * window coordinates, colours and pixel counts are written out below from the demo specification.
// Shortened timing: 1 "ms" = 20 clocks, panel reset phases 100 "ms" = 2000 clocks each, debounce 10 "ms" =
// 200 clocks, SPI half period 2 clocks (production value). The demo draws 76800 + 1600 pixels per start-up.
module tb_demo;
    parameter ROM = "byteforge_rom.hex";
    parameter REF = "ref_init.hex";
    localparam integer MS = 20, DEB = 10 * MS, HALF = 2;
    localparam integer T_PH = 100 * MS;            // each panel-reset phase
    localparam integer NREF = 71;                  // bytes in LCD_2IN_InitReg()
    localparam real    TCLK = 40.0;                // ns (25 MHz stand-in; only cycle counts matter)

    reg clk = 0, reset = 1;
    always #20 clk = ~clk;
    reg [5:0] btn_n = 6'h3F;
    wire sclk, mosi, cs_n, dc, rst_n, bl, halted, fault, overrun; wire [15:0] pc, sp;

    byteforge_system #(.CLK_HZ(27000000), .DEBOUNCE_CLKS(DEB), .CLKS_PER_MS(MS), .SPI_HALF_CLKS(HALF),
                       .RST_HIGH1_CLKS(T_PH), .RST_LOW_CLKS(T_PH), .RST_HIGH2_CLKS(T_PH), .ROM_FILE(ROM)) dut (
        .clk(clk), .reset(reset), .btn_n(btn_n),
        .lcd_sclk(sclk), .lcd_mosi(mosi), .lcd_cs_n(cs_n), .lcd_dc(dc), .lcd_rst_n(rst_n), .lcd_bl(bl),
        .halted(halted), .fault(fault), .pc(pc), .sp(sp), .disp_overrun(overrun));

    spi_monitor #(.MAXB(300000)) mon (.sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dc(dc));

    integer checks = 0, failures = 0;
    task check_eq(input [31:0] got, input [31:0] exp, input [8*64-1:0] name);
    begin
        checks = checks + 1;
        if (got !== exp) begin
            failures = failures + 1;
            if (failures < 40) $display("FAIL: %0s: expected 0x%0h, actual 0x%0h  (t=%0t)", name, exp, got, $time);
        end
    end
    endtask
    task check_true(input cond, input [8*64-1:0] name);
    begin
        checks = checks + 1;
        if (!cond) begin failures = failures + 1; if (failures < 40) $display("FAIL: %0s (t=%0t)", name, $time); end
    end
    endtask

    integer ec = 0;
    always @(posedge clk) ec = ec + 1;

    // ---- global watchdogs: the demo must never halt, fault or overrun the display ----
    integer bad_halt = 0, bad_fault = 0, bad_overrun = 0;
    always @(posedge clk) if (!reset) begin
        if (halted) bad_halt = bad_halt + 1;
        if (fault) bad_fault = bad_fault + 1;
        if (overrun) bad_overrun = bad_overrun + 1;
    end

    // ---- reference init stream ----
    reg [8:0] refmem [0:NREF-1];
    initial $readmemh(REF, refmem);

    // ---- bookkeeping for backlight and panel-RST timing ----
    integer bl_rise_bytes = -1;
    integer bl_high_early = 0;
    always @(posedge bl) bl_rise_bytes = mon.n_bytes;
    real t_rst_rise1, t_rst_fall, t_rst_rise2; integer rst_edges;
    always @(negedge rst_n) begin t_rst_fall = $realtime; end
    always @(posedge rst_n) begin
        rst_edges = rst_edges + 1;
        if (rst_edges == 1) t_rst_rise1 = $realtime; else t_rst_rise2 = $realtime;
    end

    // ---- helpers ----
    integer i, j, k, base, n_exp, gap_ok;
    real t_rel, gap;

    task wait_bytes(input integer n);
    begin
        wait (mon.n_bytes >= n);
    end
    endtask

    task check_init_stream(input integer start);   // 71 reference bytes starting at monitor index 'start'
    begin
        for (i = 0; i < NREF; i = i + 1) begin
            if (mon.byte_val[start + i] !== refmem[i][7:0] || mon.byte_dc[start + i] !== refmem[i][8]) begin
                check_eq({mon.byte_dc[start + i], mon.byte_val[start + i]}, refmem[i], "init byte (dc,value) vs Waveshare reference");
            end else checks = checks + 1;
        end
    end
    endtask

    // CASET xs..xe, RASET ys..ye, RAMWR: 11 bytes at monitor index s (commands DC=0, data DC=1)
    task check_window(input integer s, input [15:0] xs, input [15:0] xe, input [15:0] ys, input [15:0] ye);
    begin
        check_eq({mon.byte_dc[s+0],  mon.byte_val[s+0]},  9'h02A,          "CASET command (0x2A, DC=0)");
        check_eq({mon.byte_dc[s+1],  mon.byte_val[s+1]},  {1'b1, xs[15:8]}, "XS high");
        check_eq({mon.byte_dc[s+2],  mon.byte_val[s+2]},  {1'b1, xs[7:0]},  "XS low");
        check_eq({mon.byte_dc[s+3],  mon.byte_val[s+3]},  {1'b1, xe[15:8]}, "XE high");
        check_eq({mon.byte_dc[s+4],  mon.byte_val[s+4]},  {1'b1, xe[7:0]},  "XE low");
        check_eq({mon.byte_dc[s+5],  mon.byte_val[s+5]},  9'h02B,          "RASET command (0x2B, DC=0)");
        check_eq({mon.byte_dc[s+6],  mon.byte_val[s+6]},  {1'b1, ys[15:8]}, "YS high");
        check_eq({mon.byte_dc[s+7],  mon.byte_val[s+7]},  {1'b1, ys[7:0]},  "YS low");
        check_eq({mon.byte_dc[s+8],  mon.byte_val[s+8]},  {1'b1, ye[15:8]}, "YE high");
        check_eq({mon.byte_dc[s+9],  mon.byte_val[s+9]},  {1'b1, ye[7:0]},  "YE low");
        check_eq({mon.byte_dc[s+10], mon.byte_val[s+10]}, 9'h02C,          "RAMWR command (0x2C, DC=0)");
    end
    endtask

    // pixels (count pairs) of colour hi:lo starting at monitor index s: every byte is data (DC=1)
    task check_pixels(input integer s, input integer pairs, input [7:0] hi, input [7:0] lo);
        integer p; integer bad;
    begin
        bad = 0;
        for (p = 0; p < pairs; p = p + 1) begin
            if (mon.byte_val[s + 2*p] !== hi || mon.byte_dc[s + 2*p] !== 1'b1) bad = bad + 1;
            if (mon.byte_val[s + 2*p + 1] !== lo || mon.byte_dc[s + 2*p + 1] !== 1'b1) bad = bad + 1;
        end
        check_eq(bad, 0, "pixel bytes with wrong value/DC");
        checks = checks + 2 * pairs;
    end
    endtask

    // draw of the 40x40 patch (3211 bytes), then confirm nothing more is sent for 'quiet' clocks
    task check_patch_draw(input integer s, input [7:0] hi, input [7:0] lo, input integer quiet, input [8*40-1:0] what);
    begin
        wait_bytes(s + 3211);
        check_window(s, 16'd100, 16'd139, 16'd140, 16'd179);
        check_pixels(s + 11, 1600, hi, lo);
        repeat (quiet) @(posedge clk);
        check_eq(mon.n_bytes, s + 3211, "no further display bytes after the patch redraw");
        $display("  [demo] %0s redraw verified at byte %0d", what, s);
    end
    endtask

    task bounce_press(input integer b);           // contact bounce, then settle low
    begin
        btn_n[b] = 0; repeat (7) @(posedge clk); btn_n[b] = 1; repeat (9) @(posedge clk);
        btn_n[b] = 0; repeat (23) @(posedge clk); btn_n[b] = 1; repeat (5) @(posedge clk);
        btn_n[b] = 0;
    end
    endtask
    task bounce_release(input integer b);
    begin
        btn_n[b] = 1; repeat (11) @(posedge clk); btn_n[b] = 0; repeat (4) @(posedge clk);
        btn_n[b] = 1; repeat (13) @(posedge clk); btn_n[b] = 0; repeat (6) @(posedge clk);
        btn_n[b] = 1;
    end
    endtask

    initial begin : timeout
        #1_200_000_000;                              // 1.2 s of simulated time = 30 M clocks at 25 MHz
        $display("FAIL: global timeout"); $fatal(1, "tb_demo timeout");
    end

    integer bg_end, patch_start, s1, s2, s3, s4, s5, s6, s7;
    initial begin
        rst_edges = 0;
        // ================= run A: power-up, then reset in the middle of the background fill =================
        repeat (5) @(posedge clk);
        check_eq(rst_n, 0, "panel RST low while system reset asserted");
        check_eq(bl, 0, "backlight off in reset");
        reset <= 0;
        wait_bytes(NREF + 11 + 20001);                 // part-way through the 76800-pixel fill
        repeat (9) @(posedge clk);                     // land inside the next byte's frame
        check_eq(bl, 0, "backlight still off during the first fill");
        check_eq(cs_n, 0, "reset lands in the middle of a SPI byte");
        @(negedge clk); reset = 1;
        @(negedge clk);
        check_eq(sclk, 0, "mid-fill reset: SCLK low"); check_eq(cs_n, 1, "mid-fill reset: CS high");
        check_eq(dc, 0, "mid-fill reset: DC low"); check_eq(rst_n, 0, "mid-fill reset: panel RST asserted");
        check_eq(mon.n_aborted, 1, "mid-byte reset aborted exactly one frame");
        check_eq(mon.n_bytes >= NREF + 11 + 20001, 1, "bytes before the reset were all complete");
        repeat (3) @(posedge clk);
        mon.clear;
        // ================= run 1: after that reset, button Right HELD from before reset release =================
        btn_n = 6'b110111;                            // Right (bit 3) held low from before reset release
        rst_edges = 0;
        repeat (2) @(negedge clk);
        reset = 0; t_rel = $realtime;
        bl_rise_bytes = -1;
        // startup / panel reset timing as seen on the pin
        wait_bytes(1);
        check_true(mon.byte_t_cs_fall[0] >= t_rel + 3.0 * T_PH * TCLK, "first SPI byte not before 3 x reset phases elapsed");
        check_eq(rst_edges, 2, "RST rose twice (1: start, 2: after reset pulse)");
        check_real_close(t_rst_fall - t_rst_rise1, T_PH * TCLK, "RST high phase 1 duration");
        check_real_close(t_rst_rise2 - t_rst_fall, T_PH * TCLK, "RST low pulse duration (100 ms-equivalent)");
        wait_bytes(NREF);
        check_init_stream(0);
        // delay between SLPOUT (0x11) and the next command must be >= 120 ms-equivalent: this is the DESIGN's conservative
        // choice (125 ms); the ST7789V datasheet (v1.6, 9.1.12) only requires >= 5 ms before the next command
        k = -1;
        for (i = 0; i < NREF; i = i + 1) if (refmem[i] == 9'h011) k = i;
        check_true(k >= 0, "reference sequence contains SLPOUT");
        gap = mon.byte_t_cs_fall[k + 1] - mon.byte_t_cs_rise[k];
        check_true(gap >= 120.0 * MS * TCLK, "SLPOUT end -> next command start gap >= 120 ms-equivalent");
        check_true(gap <= (125.0 * MS + 400) * TCLK, "SLPOUT -> next command gap not much longer than 125 ms");
        check_true(gap >= (125.0 * MS - 100) * TCLK, "SLPOUT delay is the requested 125 ms (within 100 clocks)");
        gap_ok = 0;
        for (i = 1; i < NREF; i = i + 1)
            if (i != k + 1) begin
                gap = mon.byte_t_cs_fall[i] - mon.byte_t_cs_rise[i - 1];
                if (gap > 400.0 * TCLK) gap_ok = gap_ok + 1;
            end
        check_eq(gap_ok, 0, "no unexpected long pauses inside the init sequence");
        check_eq(bl, 0, "backlight still off during init");

        // ---- background: window, RAMWR, 76800 black pixels ----
        bg_end = NREF + 11 + 153600;
        wait_bytes(bg_end);
        check_window(NREF, 16'd0, 16'd239, 16'd0, 16'd319);   // native portrait 240 x 320, no offsets
        check_pixels(NREF + 11, 76800, 8'h00, 8'h00);
        // backlight on after the fill; patch drawn afterwards
        wait (bl === 1'b1);
        #1;                                            // let the bookkeeping block sample
        check_true(bl_rise_bytes >= bg_end - 1 && bl_rise_bytes <= bg_end, "backlight turns on only after the background fill");
        s1 = bg_end;
        check_patch_draw(s1, 8'h07, 8'hFF, 150000, "initial cyan patch");
        check_eq(mon.n_aborted, 0, "no aborted frames in run 1");
        check_eq(mon.err_sclk_cs_high + mon.err_dc_change + mon.err_cs_sclk_high, 0, "no SPI protocol errors in run 1");
        check_eq(mon.n_bytes, s1 + 3211, "held Right button at start did not draw (ignored until re-pressed)");

        // ================= button tests (edge-based) =================
        // release the held Right: nothing is drawn
        bounce_release(3);
        repeat (6 * DEB) @(posedge clk);
        check_eq(mon.n_bytes, s1 + 3211, "releasing a button draws nothing");

        // Up: red F800, held a long time -> exactly one redraw
        s2 = mon.n_bytes;
        bounce_press(0);
        check_patch_draw(s2, 8'hF8, 8'h00, 300000, "Up (red) held");
        bounce_release(0); repeat (6 * DEB) @(posedge clk);
        check_eq(mon.n_bytes, s2 + 3211, "Up release draws nothing");

        // Down + Left pressed together: only Down (green) is drawn
        s3 = mon.n_bytes;
        btn_n[1] = 0; btn_n[2] = 0;
        check_patch_draw(s3, 8'h07, 8'hE0, 200000, "Down+Left together -> Down (green)");
        // release Down while Left still held: nothing; press Down again with Left still held: green again
        bounce_release(1); repeat (6 * DEB) @(posedge clk);
        check_eq(mon.n_bytes, s3 + 3211, "releasing Down with Left held draws nothing");
        s4 = mon.n_bytes;
        bounce_press(1);
        check_patch_draw(s4, 8'h07, 8'hE0, 100000, "Down again with Left held -> green");
        btn_n[1] = 1; btn_n[2] = 1; repeat (6 * DEB) @(posedge clk);
        check_eq(mon.n_bytes, s4 + 3211, "releasing both draws nothing");

        // Left alone: blue
        s5 = mon.n_bytes;
        btn_n[2] = 0;
        check_patch_draw(s5, 8'h00, 8'h1F, 100000, "Left (blue)");
        btn_n[2] = 1; repeat (6 * DEB) @(posedge clk);

        // Right: yellow FFE0
        s5 = mon.n_bytes; btn_n[3] = 0;
        check_patch_draw(s5, 8'hFF, 8'hE0, 100000, "Right (yellow)");
        btn_n[3] = 1; repeat (6 * DEB) @(posedge clk);

        // A pressed, B pressed while A's redraw is still running: A then B
        s6 = mon.n_bytes; btn_n[4] = 0;
        repeat (2 * DEB + 2000) @(posedge clk);       // A is debounced and its redraw is under way
        check_true(mon.n_bytes > s6 && mon.n_bytes < s6 + 3211, "A redraw in progress when B is pressed");
        btn_n[5] = 0;                                  // B pressed and held during A's redraw
        wait_bytes(s6 + 3211);
        check_window(s6, 16'd100, 16'd139, 16'd140, 16'd179);
        check_pixels(s6 + 11, 1600, 8'hFF, 8'hFF);
        $display("  [demo] A (white) redraw verified at byte %0d", s6);
        s7 = s6 + 3211;
        check_patch_draw(s7, 8'hF8, 8'h1F, 200000, "B (magenta) pressed during A's redraw");
        btn_n[4] = 1; btn_n[5] = 1; repeat (6 * DEB) @(posedge clk);
        check_eq(mon.n_bytes, s7 + 3211, "end of button tests: no extra bytes");

        // ================= reset #2: in the idle main loop, with Up held through it =================
        btn_n[0] = 0;                                  // held across the reset
        repeat (2 * DEB) @(posedge clk);
        check_eq(bl, 1, "backlight on before reset (and Up drew red again first)");
        wait_bytes(s7 + 3211 + 3211);                  // the Up press just now drew red
        repeat (50000) @(posedge clk);
        mon.clear; rst_edges = 0;
        @(negedge clk); reset = 1;
        @(negedge clk); @(negedge clk);
        check_eq(sclk, 0, "reset: SCLK defined low"); check_eq(cs_n, 1, "reset: CS high"); check_eq(dc, 0, "reset: DC low");
        check_eq(bl, 0, "reset: backlight off"); check_eq(rst_n, 0, "reset: panel RST asserted");
        reset = 0; t_rel = $realtime;
        wait_bytes(NREF + 1);
        check_true(mon.byte_t_cs_fall[0] >= t_rel + 3.0 * T_PH * TCLK, "after reset: first byte only after the panel startup timing");
        check_init_stream(0);                          // init restarts from byte 0 and matches the reference again
        check_eq(mon.n_aborted, 0, "restart: clean frames");
        gap = mon.byte_t_cs_fall[k + 1] - mon.byte_t_cs_rise[k];
        check_true(gap >= 120.0 * MS * TCLK, "restart: SLPOUT delay repeated (>= 120 ms)");
        check_eq(bad_halt, 0, "CPU never halted"); check_eq(bad_fault, 0, "CPU never faulted");
        check_eq(bad_overrun, 0, "display never overrun");
        $display("tb_demo: %0d checks, %0d failures, simulated %0d clocks", checks, failures, ec);
        if (failures == 0) $display("PASS: tb_demo");
        else $fatal(1, "FAIL: tb_demo (%0d failures)", failures);
        $finish;                                       // deliberate stop: the real demo runs forever
    end

    task check_real_close(input real got, input real exp, input [8*64-1:0] name);
    begin
        if (exp == 0) checks = checks + 0;
        else begin
            checks = checks + 1;
            if (got < exp - 2*TCLK || got > exp + 2*TCLK) begin
                failures = failures + 1;
                $display("FAIL: %0s: expected %0.1f ns, actual %0.1f ns", name, exp, got);
            end
        end
    end
    endtask
endmodule
