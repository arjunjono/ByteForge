`timescale 1ns/1ps
// byteforge_io.v - data bus, RAM and every peripheral (everything except the CPU
// and the program ROM). Split out so testbenches can drive the data bus with a
// bus-master model while the wiring under test is exactly the production wiring.
module byteforge_io #(
    parameter integer CLK_HZ         = 27000000,
    parameter integer DEBOUNCE_MS    = 10,
    parameter integer DEBOUNCE_CLKS  = (CLK_HZ / 1000) * DEBOUNCE_MS,
    parameter integer CLKS_PER_MS    = CLK_HZ / 1000,
    parameter integer SPI_HALF_CLKS  = 2,
    parameter integer RST_HIGH1_CLKS = (CLK_HZ / 1000) * 100,
    parameter integer RST_LOW_CLKS   = (CLK_HZ / 1000) * 100,
    parameter integer RST_HIGH2_CLKS = (CLK_HZ / 1000) * 100
) (
    input         clk,
    input         reset,

    input         data_request,
    input         data_write_enable,
    input  [15:0] data_address,
    input  [7:0]  data_write_data,
    output        data_ready,
    output [7:0]  data_read_data,

    input  [5:0]  btn_n,

    output        lcd_sclk,
    output        lcd_mosi,
    output        lcd_cs_n,
    output        lcd_dc,
    output        lcd_rst_n,
    output        lcd_bl,
    output        disp_overrun
);
    wire [5:0] pressed;
    button_input #(.N(6), .CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS),
                   .DEBOUNCE_CLKS(DEBOUNCE_CLKS)) u_buttons (
        .clk(clk), .reset(reset), .btn_n(btn_n), .pressed(pressed)
    );

    wire        disp_wr_valid, disp_wr_is_data, bl_wr, bl_wr_bit;
    wire [7:0]  disp_wr_byte, disp_status, bl_value;
    wire        disp_can_accept;
    wire        delay_active, delay_start, delay_cancel;
    wire [7:0]  delay_value;

    data_bus u_bus (
        .clk(clk), .reset(reset),
        .data_request(data_request), .data_write_enable(data_write_enable),
        .data_address(data_address), .data_write_data(data_write_data),
        .data_ready(data_ready), .data_read_data(data_read_data),
        .btn_value({2'b00, pressed}),
        .disp_status(disp_status), .disp_can_accept(disp_can_accept),
        .disp_wr_valid(disp_wr_valid), .disp_wr_is_data(disp_wr_is_data),
        .disp_wr_byte(disp_wr_byte),
        .bl_value(bl_value), .bl_wr(bl_wr), .bl_wr_bit(bl_wr_bit),
        .delay_active(delay_active), .delay_start(delay_start),
        .delay_value(delay_value), .delay_cancel(delay_cancel)
    );

    delay_unit #(.CLK_HZ(CLK_HZ), .CLKS_PER_MS(CLKS_PER_MS)) u_delay (
        .clk(clk), .reset(reset), .start(delay_start), .value(delay_value),
        .cancel(delay_cancel), .active(delay_active)
    );

    spi_display_ctrl #(.CLK_HZ(CLK_HZ), .SPI_HALF_CLKS(SPI_HALF_CLKS),
                       .RST_HIGH1_CLKS(RST_HIGH1_CLKS), .RST_LOW_CLKS(RST_LOW_CLKS),
                       .RST_HIGH2_CLKS(RST_HIGH2_CLKS)) u_disp (
        .clk(clk), .reset(reset),
        .wr_valid(disp_wr_valid), .wr_is_data(disp_wr_is_data), .wr_byte(disp_wr_byte),
        .bl_wr(bl_wr), .bl_wr_bit(bl_wr_bit),
        .can_accept(disp_can_accept), .status(disp_status), .bl_value(bl_value),
        .overrun(disp_overrun),
        .lcd_sclk(lcd_sclk), .lcd_mosi(lcd_mosi), .lcd_cs_n(lcd_cs_n),
        .lcd_dc(lcd_dc), .lcd_rst_n(lcd_rst_n), .lcd_bl(lcd_bl)
    );
endmodule
