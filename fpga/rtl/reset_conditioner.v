`timescale 1ns/1ps
// reset_conditioner.v - board reset for the single 27 MHz clock domain
//
// Sources of reset (rst_out is synchronous, active high, glitch-free flop):
//  1. Power-up: the FPGA loads every register's INIT value from the bitstream
//     at configuration. chain resets to 2'b11 and por_active to 1, so rst_out
//     is 1 from the first clock; por_active then holds it for POR_CYCLES
//     clocks (256 clocks = ~9.5 us at 27 MHz) so the PLL-free design starts
//     from a clean state. This relies on register initial values, which the
//     Gowin flow supports (INIT attribute); it does not use a GSR pin.
//  2. External reset button (ext_rst_n, active low, async): asserts the chain
//     asynchronously (reset recognised at once), releases synchronously through
//     a 2-flop chain, so rst_out falls only on a clock edge with no recovery
//     violations. The button is NOT debounced: bounce just produces a few
//     extra resets, which are harmless because reset is idempotent.
// The CPU, memories and peripherals all use this one synchronous reset.
module reset_conditioner #(
    parameter integer POR_CYCLES = 256
) (
    input      clk,
    input      ext_rst_n,
    output reg rst_out
);
    (* keep = 1, syn_preserve = 1 *) reg [1:0] chain = 2'b11;
    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) chain <= 2'b11;
        else            chain <= {chain[0], 1'b0};
    end

    localparam integer PW = $clog2(POR_CYCLES + 1);
    reg [PW-1:0] por_cnt    = {PW{1'b0}};
    reg          por_active = 1'b1;
    always @(posedge clk) begin
        if (por_active) begin
            if (por_cnt == POR_CYCLES - 1) por_active <= 1'b0;
            por_cnt <= por_cnt + 1'b1;
        end
    end

    initial rst_out = 1'b1;
    always @(posedge clk) rst_out <= chain[1] | por_active;
endmodule
