`timescale 1ns/1ps
// tang_nano_20k_top.v - ByteForge board top for Sipeed Tang Nano 20K (GW2AR-LV18QN88C8/I7)
//
// One clock domain: the 27 MHz crystal (FPGA pin 4) is used directly, no PLL.
// Asynchronous inputs (six buttons, reset button) go through synchronizers
// inside byteforge_system / reset_conditioner. The SPI clock is an ordinary
// registered output, never used as an internal clock.
//
// Pin names here are the names used in constraints/byteforge.cst.
module tang_nano_20k_top #(
    parameter         ROM_FILE      = "byteforge_rom.hex",
    parameter integer CLK_HZ        = 27000000,
    parameter integer SPI_HALF_CLKS = 2,                 // SCLK = 27 MHz / 4 = 6.75 MHz
    parameter integer DEBOUNCE_MS   = 10,
    // overridable only for board-level simulation; leave at the defaults for hardware
    parameter integer DEBOUNCE_CLKS  = (CLK_HZ / 1000) * DEBOUNCE_MS,
    parameter integer CLKS_PER_MS    = CLK_HZ / 1000,
    parameter integer RST_HIGH1_CLKS = (CLK_HZ / 1000) * 100,
    parameter integer RST_LOW_CLKS   = (CLK_HZ / 1000) * 100,
    parameter integer RST_HIGH2_CLKS = (CLK_HZ / 1000) * 100,
    parameter integer POR_CYCLES     = 256
) (
    input        clk,            // 27 MHz crystal, pin 4
    input        rst_btn_n,      // external reset button, active low
    input        btn_up_n,
    input        btn_down_n,
    input        btn_left_n,
    input        btn_right_n,
    input        btn_a_n,
    input        btn_b_n,

    output       lcd_din,        // module DIN  (MOSI)
    output       lcd_clk,        // module CLK  (SCLK)
    output       lcd_cs,         // module CS   (active low)
    output       lcd_dc,         // module DC
    output       lcd_rst,        // module RST  (active low)
    output       lcd_bl,         // module BL   (1 = backlight on)

    output [1:0] led_n           // on-board LEDs, active low: [0] = fault, [1] = halted
);
    wire rst;
    reset_conditioner #(.POR_CYCLES(POR_CYCLES)) u_reset (
        .clk(clk), .ext_rst_n(rst_btn_n), .rst_out(rst)
    );

    wire halted, fault, overrun;
    wire [15:0] pc_unused, sp_unused;

    byteforge_system #(
        .CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS), .DEBOUNCE_CLKS(DEBOUNCE_CLKS),
        .CLKS_PER_MS(CLKS_PER_MS), .SPI_HALF_CLKS(SPI_HALF_CLKS),
        .RST_HIGH1_CLKS(RST_HIGH1_CLKS), .RST_LOW_CLKS(RST_LOW_CLKS), .RST_HIGH2_CLKS(RST_HIGH2_CLKS),
        .ROM_FILE(ROM_FILE)
    ) u_system (
        .clk(clk), .reset(rst),
        .btn_n({btn_b_n, btn_a_n, btn_right_n, btn_left_n, btn_down_n, btn_up_n}),
        .lcd_sclk(lcd_clk), .lcd_mosi(lcd_din), .lcd_cs_n(lcd_cs), .lcd_dc(lcd_dc),
        .lcd_rst_n(lcd_rst), .lcd_bl(lcd_bl),
        .halted(halted), .fault(fault), .pc(pc_unused), .sp(sp_unused), .disp_overrun(overrun)
    );

    assign led_n = ~{halted, fault | overrun};
endmodule
