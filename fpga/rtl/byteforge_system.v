`timescale 1ns/1ps
// byteforge_system.v - the real ByteForge CPU plus ROM, RAM and peripherals.
//
// Everything runs on the single clock 'clk'. 'reset' is the already
// conditioned synchronous active-high system reset (see reset_conditioner).
// Parameters with *_CLKS names exist so simulations can shorten timing; the
// defaults are the production values derived from CLK_HZ.
module byteforge_system #(
    parameter integer CLK_HZ         = 27000000,
    parameter integer DEBOUNCE_MS    = 10,
    parameter integer DEBOUNCE_CLKS  = (CLK_HZ / 1000) * DEBOUNCE_MS,
    parameter integer CLKS_PER_MS    = CLK_HZ / 1000,
    parameter integer SPI_HALF_CLKS  = 2,
    parameter integer RST_HIGH1_CLKS = (CLK_HZ / 1000) * 100,
    parameter integer RST_LOW_CLKS   = (CLK_HZ / 1000) * 100,
    parameter integer RST_HIGH2_CLKS = (CLK_HZ / 1000) * 100,
    parameter         ROM_FILE       = "byteforge_rom.hex"
) (
    input         clk,
    input         reset,

    // buttons, raw, active low: [0]Up [1]Down [2]Left [3]Right [4]A [5]B
    input  [5:0]  btn_n,

    // display module pins
    output        lcd_sclk,
    output        lcd_mosi,
    output        lcd_cs_n,
    output        lcd_dc,
    output        lcd_rst_n,
    output        lcd_bl,

    // observation
    output        halted,
    output        fault,
    output [15:0] pc,
    output [15:0] sp,
    output        disp_overrun
);
    wire        prog_request, prog_ready;
    wire [15:0] prog_address, prog_read_data;
    wire        data_request, data_write_enable, data_ready;
    wire [15:0] data_address;
    wire [7:0]  data_write_data, data_read_data;
    wire        zf, cf, nf;

    cpu #(.STACK_BOTTOM(16'h3F00), .STACK_TOP(16'h4000)) u_cpu (
        .clk(clk), .reset(reset),
        .prog_request(prog_request), .prog_address(prog_address),
        .prog_ready(prog_ready),     .prog_read_data(prog_read_data),
        .data_request(data_request), .data_write_enable(data_write_enable),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_ready(data_ready),     .data_read_data(data_read_data),
        .halted(halted), .fault(fault), .pc(pc), .sp(sp),
        .Z(zf), .C(cf), .N(nf)
    );

    program_rom #(.ROM_FILE(ROM_FILE)) u_rom (
        .clk(clk), .reset(reset),
        .prog_request(prog_request), .prog_address(prog_address),
        .prog_ready(prog_ready), .prog_read_data(prog_read_data)
    );

    byteforge_io #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS), .DEBOUNCE_CLKS(DEBOUNCE_CLKS),
                   .CLKS_PER_MS(CLKS_PER_MS), .SPI_HALF_CLKS(SPI_HALF_CLKS),
                   .RST_HIGH1_CLKS(RST_HIGH1_CLKS), .RST_LOW_CLKS(RST_LOW_CLKS),
                   .RST_HIGH2_CLKS(RST_HIGH2_CLKS)) u_io (
        .clk(clk), .reset(reset),
        .data_request(data_request), .data_write_enable(data_write_enable),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_ready(data_ready), .data_read_data(data_read_data),
        .btn_n(btn_n),
        .lcd_sclk(lcd_sclk), .lcd_mosi(lcd_mosi), .lcd_cs_n(lcd_cs_n),
        .lcd_dc(lcd_dc), .lcd_rst_n(lcd_rst_n), .lcd_bl(lcd_bl),
        .disp_overrun(disp_overrun)
    );
endmodule
