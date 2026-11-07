`timescale 1ns/1ps
// tb_board_top.v - smoke test of tang_nano_20k_top (pin polarity, reset button, first SPI byte).
// Shortened timing parameters (hardware defaults are exercised in tb_production_timing).
// Run from sim/work (needs byteforge_rom.hex in the run directory).
module tb_board_top;
    reg clk = 0; always #18.519 clk = ~clk;
    reg rst_btn_n = 1; reg [5:0] b = 6'h3F;
    wire din, sclk, cs, dc, lrst, bl; wire [1:0] led_n;
    tang_nano_20k_top #(.DEBOUNCE_CLKS(50), .CLKS_PER_MS(20), .RST_HIGH1_CLKS(300), .RST_LOW_CLKS(300), .RST_HIGH2_CLKS(300), .POR_CYCLES(16))
      dut(.clk(clk), .rst_btn_n(rst_btn_n), .btn_up_n(b[0]), .btn_down_n(b[1]), .btn_left_n(b[2]), .btn_right_n(b[3]),
          .btn_a_n(b[4]), .btn_b_n(b[5]), .lcd_din(din), .lcd_clk(sclk), .lcd_cs(cs), .lcd_dc(dc), .lcd_rst(lrst), .lcd_bl(bl), .led_n(led_n));
    spi_monitor mon(.sclk(sclk), .mosi(din), .cs_n(cs), .dc(dc));
    integer checks = 0, failures = 0;
    task chk(input [63:0] got, input [63:0] exp, input [8*60-1:0] name);
    begin checks = checks + 1;
        if (got !== exp) begin failures = failures + 1; $display("FAIL: %0s: expected %0h, actual %0h (t=%0t)", name, exp, got, $time); end end
    endtask
    initial begin #30_000_000; $display("FAIL: timeout"); $fatal(1, "tb_board_top timeout"); end
    integer i;
    initial begin
        // registers have no simulation-time initial value in the SPI block; the first clock edges under POR reset define them
        repeat (4) @(posedge clk); #1;
        chk(lrst, 0, "LCD RST low during power-up reset");
        chk(bl, 0, "backlight off at power-up");
        chk(cs, 1, "CS idle high"); chk(sclk, 0, "SCLK idle low");
        repeat (100) @(posedge clk);
        chk(led_n, 2'b11, "LEDs off (not halted, no fault)");
        // wait for the first byte of the panel init
        i = 0; while (mon.n_bytes < 1 && i < 3000000) begin @(posedge clk); i = i + 1; end
        chk(mon.n_bytes >= 1, 1, "first SPI byte arrives");
        chk(mon.byte_val[0], 8'h36, "first byte = 0x36 (MADCTL, command)");
        chk(mon.byte_dc[0], 0, "first byte is a command (DC=0)");
        chk(lrst, 1, "LCD RST released after startup");
        // reset button: pulse low, panel reset line must drop and SPI must restart
        repeat (500) @(posedge clk);
        mon.clear;
        @(negedge clk); rst_btn_n = 0; repeat (6) @(posedge clk); #1;
        chk(lrst, 0, "reset button pulls LCD RST low");
        chk(cs, 1, "CS high during reset"); chk(sclk, 0, "SCLK low during reset");
        @(negedge clk); rst_btn_n = 1;
        i = 0; while (mon.n_bytes < 1 && i < 3000000) begin @(posedge clk); i = i + 1; end
        chk(mon.byte_val[0], 8'h36, "after reset button init restarts with 0x36");
        // buttons idle high do not disturb anything; the demo ignores held-at-start presses
        chk(mon.n_aborted, 0, "no aborted frames");
        $display("tb_board_top: %0d checks, %0d failures", checks, failures);
        if (failures == 0) $display("PASS: tb_board_top"); else $fatal(1, "FAIL: tb_board_top");
        $finish;
    end
endmodule
