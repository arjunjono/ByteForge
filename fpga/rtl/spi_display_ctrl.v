`timescale 1ns/1ps
// spi_display_ctrl.v - ST7789 (Waveshare 2inch LCD, SKU 17344) SPI byte sender,
// panel reset sequencer and backlight register.
//
// SPI: mode 0 (CPOL=0, CPHA=0), MSB first, single-byte transmitter, no FIFO.
//   SCLK is a registered output, low when idle. One half period = SPI_HALF_CLKS
//   system clocks (SCLK = CLK_HZ / (2*SPI_HALF_CLKS)). Per byte:
//     SETUP  CS=0, DC and MOSI(bit7) stable, SCLK low, 1 half period
//     8 x    SCLK high 1 half period (slave samples at the rising edge; MOSI
//            was stable for a full half period before it and stays for a
//            full half period after it), then SCLK low 1 half period; MOSI is
//            moved to the next bit at the falling edge
//     HOLD   (the 8th low phase) CS stays low, SCLK low
//     GAP    CS=1 for 1 half period before another byte can be accepted
//   DC is changed only while idle (it is set at the accept edge, before CS
//   falls in the same edge), so it is stable from before CS falls until after
//   CS rises.
//
// Accept rule: the bus pulses wr_valid only at its completion edge, and only
// when can_accept = !busy && !startup was true (it stalls ready otherwise).
// The byte and DC are registered at that one edge; busy is 1 from the next
// cycle (status bit0 therefore includes an accepted byte that has not yet
// toggled SCLK). If wr_valid ever arrived while !can_accept the byte would be
// lost, so 'overrun' latches it (simulation / debug visibility).
//
// Panel reset (separate from the CPU reset *button*; it is driven only by this
// sequencer, but is restarted by system reset because a reset can abort a
// byte mid-transfer and leave the panel in an unknown state):
//   While 'reset' is asserted: RST=0, startup=1.
//   After release: RST=1 for RST_HIGH1, RST=0 for RST_LOW, RST=1 for RST_HIGH2.
//   Defaults 100 ms / 100 ms / 100 ms: source - Waveshare reference code
//   LCD_2IN_Reset() in waveshare/Pico_code c/lib/LCD/LCD_2in.c:
//   RST=1; delay 100; RST=0; delay 100; RST=1; delay 100.
//   status bit1 (startup) is 1 for the whole time and until the last 100 ms
//   has elapsed; no byte is accepted meanwhile.
module spi_display_ctrl #(
    parameter integer CLK_HZ          = 27000000,
    parameter integer SPI_HALF_CLKS   = 2,
    parameter integer RST_HIGH1_CLKS  = (CLK_HZ / 1000) * 100,
    parameter integer RST_LOW_CLKS    = (CLK_HZ / 1000) * 100,
    parameter integer RST_HIGH2_CLKS  = (CLK_HZ / 1000) * 100
) (
    input            clk,
    input            reset,

    // from the data bus
    input            wr_valid,
    input            wr_is_data,
    input      [7:0] wr_byte,
    input            bl_wr,
    input            bl_wr_bit,

    // to the data bus
    output           can_accept,
    output     [7:0] status,
    output     [7:0] bl_value,
    output reg       overrun,

    // pins
    output reg       lcd_sclk,
    output reg       lcd_mosi,
    output reg       lcd_cs_n,
    output reg       lcd_dc,
    output reg       lcd_rst_n,
    output           lcd_bl
);
    // ---------------- panel reset / startup timing ----------------
    localparam [2:0] SU_START = 3'd0, SU_HIGH1 = 3'd1, SU_LOW = 3'd2,
                     SU_HIGH2 = 3'd3, SU_DONE = 3'd4;
    reg [2:0]  su_state;
    reg [31:0] su_cnt;
    reg        startup;

    always @(posedge clk) begin
        if (reset) begin
            lcd_rst_n <= 1'b0;
            startup   <= 1'b1;
            su_state  <= SU_START;
            su_cnt    <= 32'd0;
        end else case (su_state)
            SU_START: begin
                lcd_rst_n <= 1'b1;
                su_cnt    <= RST_HIGH1_CLKS - 1;
                su_state  <= SU_HIGH1;
            end
            SU_HIGH1: if (su_cnt == 0) begin
                lcd_rst_n <= 1'b0;
                su_cnt    <= RST_LOW_CLKS - 1;
                su_state  <= SU_LOW;
            end else su_cnt <= su_cnt - 1'b1;
            SU_LOW: if (su_cnt == 0) begin
                lcd_rst_n <= 1'b1;
                su_cnt    <= RST_HIGH2_CLKS - 1;
                su_state  <= SU_HIGH2;
            end else su_cnt <= su_cnt - 1'b1;
            SU_HIGH2: if (su_cnt == 0) begin
                startup  <= 1'b0;
                su_state <= SU_DONE;
            end else su_cnt <= su_cnt - 1'b1;
            default: ;                       // SU_DONE: hold
        endcase
    end

    // ---------------- SPI byte engine ----------------
    localparam [2:0] SP_IDLE = 3'd0, SP_SETUP = 3'd1, SP_HI = 3'd2,
                     SP_LO = 3'd3, SP_HOLD = 3'd4, SP_GAP = 3'd5;
    localparam integer HW = (SPI_HALF_CLKS > 1) ? $clog2(SPI_HALF_CLKS) : 1;
    reg [2:0]    sp;
    reg [HW-1:0] hc;
    reg [7:0]    shreg;
    reg [2:0]    bits_left;

    wire busy = (sp != SP_IDLE);
    assign can_accept = !busy && !startup;
    assign status     = {6'b000000, startup, busy};

    wire last_half = (hc == 0);

    always @(posedge clk) begin
        if (reset) begin
            sp        <= SP_IDLE;
            hc        <= {HW{1'b0}};
            shreg     <= 8'h00;
            bits_left <= 3'd0;
            lcd_sclk  <= 1'b0;
            lcd_mosi  <= 1'b0;
            lcd_cs_n  <= 1'b1;
            lcd_dc    <= 1'b0;
            overrun   <= 1'b0;
        end else begin
            if (wr_valid && !can_accept) overrun <= 1'b1;
            case (sp)
                SP_IDLE: if (wr_valid && can_accept) begin
                    shreg     <= wr_byte;
                    lcd_dc    <= wr_is_data;
                    lcd_mosi  <= wr_byte[7];
                    lcd_cs_n  <= 1'b0;
                    bits_left <= 3'd7;
                    hc        <= SPI_HALF_CLKS - 1;
                    sp        <= SP_SETUP;
                end
                SP_SETUP: if (last_half) begin
                    lcd_sclk <= 1'b1;
                    hc       <= SPI_HALF_CLKS - 1;
                    sp       <= SP_HI;
                end else hc <= hc - 1'b1;
                SP_HI: if (last_half) begin
                    lcd_sclk <= 1'b0;                    // falling edge
                    hc       <= SPI_HALF_CLKS - 1;
                    if (bits_left == 3'd0) sp <= SP_HOLD;
                    else begin
                        shreg     <= {shreg[6:0], 1'b0};
                        lcd_mosi  <= shreg[6];           // next bit, changes with the fall
                        bits_left <= bits_left - 1'b1;
                        sp        <= SP_LO;
                    end
                end else hc <= hc - 1'b1;
                SP_LO: if (last_half) begin
                    lcd_sclk <= 1'b1;                    // rising edge
                    hc       <= SPI_HALF_CLKS - 1;
                    sp       <= SP_HI;
                end else hc <= hc - 1'b1;
                SP_HOLD: if (last_half) begin
                    lcd_cs_n <= 1'b1;
                    hc       <= SPI_HALF_CLKS - 1;
                    sp       <= SP_GAP;
                end else hc <= hc - 1'b1;
                SP_GAP: if (last_half) sp <= SP_IDLE;
                        else hc <= hc - 1'b1;
                default: sp <= SP_IDLE;
            endcase
        end
    end

    // ---------------- backlight register ----------------
    // BL drives the module's BL pin (a 1 k resistor into an NPN base per the
    // Waveshare schematic netlist, so a 3.3 V GPIO is adequate); 0 = off.
    reg bl_q;
    always @(posedge clk) begin
        if (reset)      bl_q <= 1'b0;
        else if (bl_wr) bl_q <= bl_wr_bit;
    end
    assign bl_value = {7'b0000000, bl_q};
    assign lcd_bl   = bl_q;
endmodule
