`timescale 1ns/1ps
// delay_unit.v - blocking millisecond delay (address 0xFF20)
//
// start (one clock pulse, taken at the bus capture edge E0) loads 'value'
// (1..255). active is 1 from just after E0 until exactly value*CLKS_PER_MS
// clock edges later; the bus asserts ready only while active is 0.
// value 0 is never started (bus does not pulse start), so there is no delay.
// cancel / reset clear the delay at once.
module delay_unit #(
    parameter integer CLK_HZ      = 27000000,
    parameter integer CLKS_PER_MS = CLK_HZ / 1000      // may be overridden in simulation
) (
    input        clk,
    input        reset,
    input        start,
    input  [7:0] value,
    input        cancel,
    output reg   active
);
    // 255 ms is the longest request; the per-ms counter only needs to hold
    // CLKS_PER_MS-1 (15 bits at 27 MHz), the ms counter 8 bits.
    localparam integer SW = (CLKS_PER_MS > 1) ? $clog2(CLKS_PER_MS) : 1;
    reg [SW-1:0] sub;
    reg [7:0]    ms_left;

    always @(posedge clk) begin
        if (reset || cancel) begin
            active  <= 1'b0;
            sub     <= {SW{1'b0}};
            ms_left <= 8'd0;
        end else if (start && !active) begin
            active  <= 1'b1;
            sub     <= CLKS_PER_MS - 1;
            ms_left <= value;
        end else if (active) begin
            if (sub == 0) begin
                sub <= CLKS_PER_MS - 1;
                if (ms_left == 8'd1) begin
                    active  <= 1'b0;
                    ms_left <= 8'd0;
                end else
                    ms_left <= ms_left - 8'd1;
            end else
                sub <= sub - 1'b1;
        end
    end
endmodule
