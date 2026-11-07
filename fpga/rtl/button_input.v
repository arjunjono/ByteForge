`timescale 1ns/1ps
// button_input.v - synchronizers + independent debouncers for N active-low buttons
//
// Per input: raw pin -> 2-flop synchronizer -> debounce counter -> stable bit.
// pressed = 1 in 'pressed' output (the pins are active low).
//   * The first synchronizer flop samples the asynchronous pin; it is the only
//     metastability-exposed flop and is marked (keep / syn_preserve) so the
//     tools do not merge, retime or duplicate the chain. Gowin has no
//     ASYNC_REG attribute; whether syn_preserve is honoured by the Gowin
//     synthesizer must be checked in its log (NOT VERIFIED here).
//   * A change must persist for DEBOUNCE_CLKS consecutive clocks before the
//     reported state follows it; a glitch shorter than that restarts the
//     count. Press and release use the same time. Every input has its own
//     counter, so buttons never affect each other.
//   * Reset: synchronizer = released, reported state = released, counters 0.
//     A button still held when reset ends is reported as pressed after one
//     debounce time (it is a real press); nothing is reported before that.
// Latency from a clean raw edge sampled at edge Ek to the pressed output
// changing after edge E(k+DEBOUNCE_CLKS+1).
module button_input #(
    parameter integer N             = 6,
    parameter integer CLK_HZ        = 27000000,
    parameter integer DEBOUNCE_MS   = 10,
    parameter integer DEBOUNCE_CLKS = (CLK_HZ / 1000) * DEBOUNCE_MS
) (
    input          clk,
    input          reset,
    input  [N-1:0] btn_n,        // raw, asynchronous, active low
    output [N-1:0] pressed       // debounced, 1 = pressed
);
    localparam integer CW = (DEBOUNCE_CLKS > 1) ? $clog2(DEBOUNCE_CLKS) : 1;

    (* keep = 1, syn_preserve = 1 *) reg [N-1:0] sync1;
    (* keep = 1, syn_preserve = 1 *) reg [N-1:0] sync2;
    reg [N-1:0] stable;
    assign pressed = stable;

    genvar g;
    generate for (g = 0; g < N; g = g + 1) begin : ch
        reg [CW-1:0] cnt;
        wire sampled_pressed = ~sync2[g];
        always @(posedge clk) begin
            if (reset) begin
                sync1[g] <= 1'b1;
                sync2[g] <= 1'b1;
                stable[g] <= 1'b0;
                cnt <= {CW{1'b0}};
            end else begin
                sync1[g] <= btn_n[g];
                sync2[g] <= sync1[g];
                if (sampled_pressed == stable[g])
                    cnt <= {CW{1'b0}};
                else if (cnt == DEBOUNCE_CLKS - 1) begin
                    stable[g] <= sampled_pressed;
                    cnt <= {CW{1'b0}};
                end else
                    cnt <= cnt + 1'b1;
            end
        end
    end endgenerate
endmodule
