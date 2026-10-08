// flags_register.v - ByteForge FLAGS storage (Zero, Carry, Negative)
// Only stores the flags; it does not calculate them.
`timescale 1ns/1ps

module flags_register (
    input      clk,
    input      reset,              // active-high, synchronous
    input      flags_write_enable,
    input      Z_in,
    input      C_in,
    input      N_in,
    output reg Z,
    output reg C,
    output reg N
);

    always @(posedge clk) begin
        if (reset) begin
            // Reset has priority over flags_write_enable
            Z <= 1'b0;
            C <= 1'b0;
            N <= 1'b0;
        end else if (flags_write_enable) begin
            Z <= Z_in;
            C <= C_in;
            N <= N_in;
        end
        // else: flags keep their previous values
    end

endmodule
