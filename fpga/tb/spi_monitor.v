`timescale 1ns/1ps
// spi_monitor.v - testbench-only, protocol-level SPI mode-0 decoder.
//
// Written independently of the design: it only watches the pins. It decodes
// bytes (MSB first, sampled at each SCLK rising edge while CS is low) and
// records protocol violations and timing extremes. Nothing here is shared
// with spi_display_ctrl.v.
//
// Counters a testbench can read:
//   n_bytes, byte_val[i], byte_dc[i], byte_t_cs_fall[i], byte_t_cs_rise[i]
//   n_aborted      CS rose with fewer or more than 8 SCLK rising edges
//   last_abort_bits  number of rising edges seen in the last aborted frame
//   err_sclk_cs_high SCLK rose while CS was high
//   err_dc_change    DC changed while CS was low
//   err_cs_sclk_high CS fell or rose while SCLK was high
//   min_setup_ns / min_hold_ns   MOSI stable time before / after SCLK rising
//   min_high_ns, max_high_ns, min_low_ns, max_low_ns   SCLK phase widths
//   min_cs_high_ns   shortest CS-high interval between frames
module spi_monitor #(
    parameter integer MAXB = 300000
) (
    input sclk,
    input mosi,
    input cs_n,
    input dc
);
    reg [7:0] byte_val [0:MAXB-1];
    reg       byte_dc  [0:MAXB-1];
    real      byte_t_cs_fall [0:MAXB-1];
    real      byte_t_cs_rise [0:MAXB-1];
    integer   n_bytes;
    integer   n_aborted, last_abort_bits;
    integer   err_sclk_cs_high, err_dc_change, err_cs_sclk_high, err_overflow;
    real      min_setup_ns, min_hold_ns;
    real      min_high_ns, max_high_ns, min_low_ns, max_low_ns, min_cs_high_ns;

    integer   bits;
    reg [7:0] shift;
    reg       dc_start;
    real      t_mosi_change, t_last_rise, t_last_fall, t_cs_rise_last, t_cs_fall_now;
    reg       in_frame;
    reg       seen_rise;

    task clear;
    begin
        n_bytes = 0; n_aborted = 0; last_abort_bits = 0;
        err_sclk_cs_high = 0; err_dc_change = 0; err_cs_sclk_high = 0; err_overflow = 0;
        min_setup_ns = 1.0e9; min_hold_ns = 1.0e9;
        min_high_ns = 1.0e9; max_high_ns = 0; min_low_ns = 1.0e9; max_low_ns = 0;
        min_cs_high_ns = 1.0e9;
        bits = 0; shift = 0; in_frame = 0; seen_rise = 0;
        t_mosi_change = 0; t_last_rise = 0; t_last_fall = 0; t_cs_rise_last = -1;
    end
    endtask

    initial clear;

    always @(mosi) t_mosi_change = $realtime;

    // frame start
    always @(negedge cs_n) begin
        if (sclk !== 1'b0) err_cs_sclk_high = err_cs_sclk_high + 1;
        if (t_cs_rise_last >= 0 && ($realtime - t_cs_rise_last) < min_cs_high_ns)
            min_cs_high_ns = $realtime - t_cs_rise_last;
        in_frame = 1; bits = 0; shift = 0; seen_rise = 0; dc_start = dc;
        t_cs_fall_now = $realtime;
    end

    // data bits
    always @(posedge sclk) begin
        if (cs_n !== 1'b0) err_sclk_cs_high = err_sclk_cs_high + 1;
        else begin
            shift = {shift[6:0], mosi};
            bits  = bits + 1;
            if (($realtime - t_mosi_change) < min_setup_ns) min_setup_ns = $realtime - t_mosi_change;
            if (seen_rise && ($realtime - t_last_fall) < min_low_ns) min_low_ns = $realtime - t_last_fall;
            if (seen_rise && ($realtime - t_last_fall) > max_low_ns) max_low_ns = $realtime - t_last_fall;
            seen_rise = 1;
        end
        t_last_rise = $realtime;
    end

    always @(negedge sclk) begin
        if (in_frame && seen_rise) begin
            if (($realtime - t_last_rise) < min_high_ns) min_high_ns = $realtime - t_last_rise;
            if (($realtime - t_last_rise) > max_high_ns) max_high_ns = $realtime - t_last_rise;
        end
        t_last_fall = $realtime;
    end

    // MOSI hold: any MOSI change while in a frame, after at least one rising edge
    always @(mosi) if (in_frame && seen_rise) begin
        if (($realtime - t_last_rise) < min_hold_ns && ($realtime - t_last_rise) > 0)
            min_hold_ns = $realtime - t_last_rise;
    end

    always @(dc) if (in_frame && dc !== dc_start) err_dc_change = err_dc_change + 1;

    // frame end
    always @(posedge cs_n) begin
        if (sclk !== 1'b0) err_cs_sclk_high = err_cs_sclk_high + 1;
        if (in_frame) begin
            if (bits == 8) begin
                if (n_bytes < MAXB) begin
                    byte_val[n_bytes] = shift;
                    byte_dc[n_bytes]  = dc_start;
                    byte_t_cs_fall[n_bytes] = t_cs_fall_now;
                    byte_t_cs_rise[n_bytes] = $realtime;
                end else err_overflow = err_overflow + 1;
                n_bytes = n_bytes + 1;
            end else begin
                n_aborted = n_aborted + 1;
                last_abort_bits = bits;
            end
        end
        in_frame = 0;
        t_cs_rise_last = $realtime;
    end
endmodule
