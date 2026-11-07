`timescale 1ns/1ps
// tb_spi_display.v - spi_display_ctrl unit test with an independent SPI decoder
//
// Run (from sim/), HALF = SCLK half period in system clocks (production default 2):
//   iverilog -g2012 -Wall -Ptb_spi_display.HALF=3 -o spi3.vvp -s tb_spi_display ../rtl/spi_display_ctrl.v \
//            ../tb/spi_monitor.v ../tb/tb_spi_display.v && vvp spi3.vvp
// Also run with HALF=1 and HALF=2. Expected timings are computed here from HALF/T1/T2/T3.
module tb_spi_display;
    parameter integer HALF = 3;
    localparam integer T1 = 17, T2 = 23, T3 = 19;      // distinct panel-reset phase lengths (clocks)
    localparam real    TCLK = 10.0;                    // ns

    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg wr_valid = 0, wr_is_data = 0; reg [7:0] wr_byte = 0;
    reg bl_wr = 0, bl_wr_bit = 0;
    wire can_accept, overrun, sclk, mosi, cs_n, dc, rst_n, bl; wire [7:0] status, bl_value;

    spi_display_ctrl #(.CLK_HZ(1000000), .SPI_HALF_CLKS(HALF), .RST_HIGH1_CLKS(T1), .RST_LOW_CLKS(T2), .RST_HIGH2_CLKS(T3)) dut (
        .clk(clk), .reset(reset), .wr_valid(wr_valid), .wr_is_data(wr_is_data), .wr_byte(wr_byte),
        .bl_wr(bl_wr), .bl_wr_bit(bl_wr_bit), .can_accept(can_accept), .status(status), .bl_value(bl_value),
        .overrun(overrun), .lcd_sclk(sclk), .lcd_mosi(mosi), .lcd_cs_n(cs_n), .lcd_dc(dc), .lcd_rst_n(rst_n), .lcd_bl(bl));

    spi_monitor mon (.sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dc(dc));

    integer checks = 0, failures = 0;
    task check_eq(input [31:0] got, input [31:0] exp, input [8*60-1:0] name);
    begin
        checks = checks + 1;
        if (got !== exp) begin
            failures = failures + 1;
            $display("FAIL: %0s: expected %0d (0x%0h), actual %0d (0x%0h)  (t=%0t, HALF=%0d)", name, exp, exp, got, got, $time, HALF);
        end
    end
    endtask
    task check_ge_real(input real got, input real minv, input [8*60-1:0] name);
    begin
        checks = checks + 1;
        if (got < minv) begin
            failures = failures + 1;
            $display("FAIL: %0s: expected >= %0.3f, actual %0.3f  (t=%0t, HALF=%0d)", name, minv, got, $time, HALF);
        end
    end
    endtask
    task check_real(input real got, input real exp, input [8*60-1:0] name);
    begin
        checks = checks + 1;
        if (got != exp) begin
            failures = failures + 1;
            $display("FAIL: %0s: expected %0.3f, actual %0.3f  (t=%0t, HALF=%0d)", name, exp, got, $time, HALF);
        end
    end
    endtask

    integer ec = 0;
    always @(posedge clk) ec = ec + 1;

    // edge records (negedge sampling = effect of the previous posedge)
    integer ec_rst_rise1, ec_rst_fall, ec_rst_rise2, ec_su_fall;
    reg rst_prev = 0, su_prev = 1;
    integer rst_rise_count = 0;
    integer busy_cycles = 0;
    integer idle_violations = 0;
    always @(negedge clk) begin
        if (rst_n && !rst_prev) begin rst_rise_count = rst_rise_count + 1; if (rst_rise_count == 1) ec_rst_rise1 = ec; else ec_rst_rise2 = ec; end
        if (!rst_n && rst_prev) ec_rst_fall = ec;
        if (!status[1] && su_prev) ec_su_fall = ec;
        rst_prev = rst_n; su_prev = status[1];
        // while idle (not busy), SCLK low and CS high
        if (!reset && !status[0] && (sclk !== 1'b0 || cs_n !== 1'b1)) idle_violations = idle_violations + 1;
        if (status[0]) busy_cycles = busy_cycles + 1;
    end

    task pulse_write(input isd, input [7:0] b);
    begin
        @(negedge clk); wr_valid = 1; wr_is_data = isd; wr_byte = b;
        @(negedge clk); wr_valid = 0; wr_is_data = 0; wr_byte = 8'h00;
    end
    endtask
    task tick(input integer n); begin repeat (n) @(negedge clk); end endtask
    task wait_idle; integer k; begin k = 0; while (status[0] && k < 2000) begin @(negedge clk); k = k + 1; end end endtask

    integer i, e_rel, phase, base, accept_ec;
    reg [7:0] tv [0:9];
    reg       td [0:9];
    integer offs [0:5];

    initial begin : timeout
        #5_000_000; $display("FAIL: global timeout"); $fatal(1, "tb_spi_display timeout");
    end

    initial begin
        // ===== reset state =====
        tick(3);
        check_eq(rst_n, 0, "panel RST low while system reset asserted");
        check_eq(status, 8'b00000010, "status while in reset: startup=1 busy=0");
        check_eq(can_accept, 0, "cannot accept during reset/startup");
        check_eq(sclk, 0, "SCLK low in reset"); check_eq(cs_n, 1, "CS high in reset"); check_eq(dc, 0, "DC low in reset");
        reset = 0; e_rel = ec;                      // first non-reset edge is e_rel+1
        tick(T1 + T2 + T3 + 10);
        check_eq(ec_rst_rise1, e_rel + 1, "RST rises on the first edge after reset release");
        check_eq(ec_rst_fall - ec_rst_rise1, T1, "RST high phase 1 length (clocks)");
        check_eq(ec_rst_rise2 - ec_rst_fall, T2, "RST low pulse length (clocks)");
        check_eq(ec_su_fall - ec_rst_rise2, T3, "recovery (RST high 2) length until startup clears");
        check_eq(status, 8'h00, "status idle after startup");
        check_eq(can_accept, 1, "can accept after startup");

        // ===== protocol checks for a set of bytes =====
        mon.clear;
        tv[0]=8'h00; td[0]=0; tv[1]=8'hFF; td[1]=1; tv[2]=8'hA5; td[2]=1; tv[3]=8'h5A; td[3]=0; tv[4]=8'h80; td[4]=1;
        tv[5]=8'h01; td[5]=1; tv[6]=8'h7F; td[6]=0; tv[7]=8'hC3; td[7]=1; tv[8]=8'h3C; td[8]=0; tv[9]=8'h36; td[9]=0;
        for (i = 0; i < 10; i = i + 1) begin
            busy_cycles = 0;
            pulse_write(td[i], tv[i]);
            // pulse_write returns one cycle after the accept edge; busy must already be set
            check_eq(status[0], 1, "busy set the cycle after acceptance");
            check_eq(can_accept, 0, "cannot accept while busy");
            wait_idle;
            check_eq(busy_cycles, 18 * HALF, "busy lasts SETUP+16 half-periods+HOLD+GAP = 18*HALF clocks");
            tick(2);
        end
        check_eq(mon.n_bytes, 10, "ten bytes decoded");
        for (i = 0; i < 10; i = i + 1) begin
            check_eq(mon.byte_val[i], tv[i], "decoded byte value (MSB first)");
            check_eq(mon.byte_dc[i], td[i], "decoded DC");
            check_real(mon.byte_t_cs_rise[i] - mon.byte_t_cs_fall[i], 17.0 * HALF * TCLK, "CS low duration = 17*HALF clocks");
        end
        check_eq(mon.n_aborted, 0, "no aborted frames");
        check_eq(mon.err_sclk_cs_high, 0, "SCLK never toggles while CS high");
        check_eq(mon.err_dc_change, 0, "DC stable while CS low");
        check_eq(mon.err_cs_sclk_high, 0, "CS never changes while SCLK high");
        check_real(mon.min_high_ns, HALF * TCLK, "SCLK high width"); check_real(mon.max_high_ns, HALF * TCLK, "SCLK high width (max)");
        check_real(mon.min_low_ns, HALF * TCLK, "SCLK low width");  check_real(mon.max_low_ns, HALF * TCLK, "SCLK low width (max)");
        check_real(mon.min_setup_ns, HALF * TCLK, "MOSI setup before rising edge (>= one half period)");
        check_real(mon.min_hold_ns, HALF * TCLK, "MOSI hold after rising edge (>= one half period)");
        check_ge_real(mon.min_cs_high_ns, HALF * TCLK, "CS high between bytes >= one half period");
        check_eq(idle_violations, 0, "SCLK low / CS high whenever idle");

        // consecutive back-to-back: write the moment can_accept rises
        mon.clear;
        for (i = 0; i < 4; i = i + 1) begin
            while (!can_accept) @(negedge clk);
            @(negedge clk); wr_valid = 1; wr_is_data = 1; wr_byte = 8'h10 + i;
            @(negedge clk); wr_valid = 0;
        end
        wait_idle; tick(2);
        check_eq(mon.n_bytes, 4, "four back-to-back bytes");
        check_ge_real(mon.min_cs_high_ns, HALF * TCLK, "back-to-back: CS high >= one half period");
        check_ge_real((HALF + 3) * TCLK, mon.min_cs_high_ns, "back-to-back: CS high gap is only the GAP phase plus bus hand-off");
        for (i = 0; i < 4; i = i + 1) check_eq(mon.byte_val[i], 8'h10 + i, "back-to-back order");

        // ===== illegal write while busy / during startup is flagged (never silently dropped) =====
        check_eq(overrun, 0, "overrun clear so far");
        @(negedge clk); wr_valid = 1; wr_is_data = 1; wr_byte = 8'h11;     // accepted
        @(negedge clk); wr_byte = 8'h22;                                    // busy now: illegal
        @(negedge clk); wr_valid = 0;
        check_eq(overrun, 1, "write while busy sets the overrun flag");
        wait_idle;
        reset = 1; tick(2); reset = 0; tick(2);
        check_eq(overrun, 0, "reset clears overrun");

        // ===== reset abort at different phases (offset = clocks after the accept edge) =====
        offs[0] = 1; offs[1] = HALF + 2; offs[2] = 2 * HALF + 1; offs[3] = 9 * HALF; offs[4] = 16 * HALF + 2; offs[5] = 17 * HALF + 1;
        for (phase = 0; phase < 6; phase = phase + 1) begin
            // wait for startup end
            while (status[1]) @(negedge clk);
            tick(2);
            mon.clear;
            @(negedge clk); wr_valid = 1; wr_is_data = 1; wr_byte = 8'hA5;
            @(negedge clk); wr_valid = 0; accept_ec = ec - 1;
            tick(offs[phase] - 1);
            reset = 1;
            @(negedge clk);
            check_eq(sclk, 0, "abort: SCLK low"); check_eq(cs_n, 1, "abort: CS high");
            check_eq(dc, 0, "abort: DC defined (low)"); check_eq(mosi, 0, "abort: MOSI defined (low)");
            check_eq(status, 8'b00000010, "abort: busy cleared, startup active");
            check_eq(rst_n, 0, "abort: panel RST low");
            // The panel latches data on SCLK rising edges: the frame is a complete byte as soon as the
            // 8th rising edge (at accept + 15*HALF clocks) has been delivered, otherwise it is aborted.
            if (offs[phase] > 15 * HALF) begin
                check_eq(mon.n_bytes, 1, "reset after the 8th clock edge: byte delivered");
                check_eq(mon.n_aborted, 0, "reset after the 8th clock edge: not an aborted frame");
            end else begin
                check_eq(mon.n_aborted, 1, "abort before the 8th clock edge is an aborted frame");
                check_eq(mon.n_bytes, 0, "aborted frame is not counted as a byte");
            end
            tick(2); reset = 0;
            while (status[1]) @(negedge clk);
            tick(2);
            mon.clear;
            pulse_write(1, 8'h96);
            wait_idle; tick(2);
            check_eq(mon.n_bytes, 1, "clean byte after abort"); check_eq(mon.byte_val[0], 8'h96, "byte after abort correct");
            check_eq(mon.n_aborted, 0, "no residue from aborted frame");
            check_eq(mon.err_sclk_cs_high + mon.err_dc_change + mon.err_cs_sclk_high, 0, "no protocol errors after abort");
        end

        // ===== backlight =====
        check_eq(bl, 0, "BL off by default"); check_eq(bl_value, 8'h00, "BL value reads 0");
        @(negedge clk); bl_wr = 1; bl_wr_bit = 1; @(negedge clk); bl_wr = 0;
        check_eq(bl, 1, "BL on"); check_eq(bl_value, 8'h01, "BL value reads 1");
        @(negedge clk); reset = 1; @(negedge clk); reset = 0;
        check_eq(bl, 0, "BL off after reset");

        $display("tb_spi_display (HALF=%0d): %0d checks, %0d failures", HALF, checks, failures);
        if (failures == 0) $display("PASS: tb_spi_display HALF=%0d", HALF);
        else $fatal(1, "FAIL: tb_spi_display (%0d failures)", failures);
        $finish;
    end
endmodule
