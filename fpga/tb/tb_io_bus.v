`timescale 1ns/1ps
// tb_io_bus.v - data bus, RAM, buttons register, display write path, backlight and
// unmapped/read-only behaviour, driven by a bus-master model (no CPU).
//
// Run (from sim/):
//   iverilog -g2012 -Wall -o iobus.vvp -s tb_io_bus ../rtl/button_input.v ../rtl/data_bus.v ../rtl/delay_unit.v \
//            ../rtl/spi_display_ctrl.v ../rtl/byteforge_io.v ../tb/spi_monitor.v ../tb/tb_io_bus.v
//   vvp iobus.vvp
// Expected RAM contents come from a testbench-side model array; expected SPI bytes come
// from the independent decoder in spi_monitor.v.
module tb_io_bus;
    localparam integer DEB = 20, MS = 10, HALF = 2, T1 = 15, T2 = 20, T3 = 25;

    reg clk = 0, reset = 1;
    always #5 clk = ~clk;

    reg         req = 0, we = 0;
    reg  [15:0] addr = 0;
    reg  [7:0]  wdata = 0;
    wire        rdy;
    wire [7:0]  rdata;
    reg  [5:0]  btn_n = 6'h3F;
    wire sclk, mosi, cs_n, dc, rst_n, bl, overrun;

    byteforge_io #(.CLK_HZ(1000000), .DEBOUNCE_CLKS(DEB), .CLKS_PER_MS(MS), .SPI_HALF_CLKS(HALF),
                   .RST_HIGH1_CLKS(T1), .RST_LOW_CLKS(T2), .RST_HIGH2_CLKS(T3)) dut (
        .clk(clk), .reset(reset),
        .data_request(req), .data_write_enable(we), .data_address(addr), .data_write_data(wdata),
        .data_ready(rdy), .data_read_data(rdata), .btn_n(btn_n),
        .lcd_sclk(sclk), .lcd_mosi(mosi), .lcd_cs_n(cs_n), .lcd_dc(dc), .lcd_rst_n(rst_n),
        .lcd_bl(bl), .disp_overrun(overrun));

    spi_monitor mon (.sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dc(dc));

    integer checks = 0, failures = 0;
    task check_eq(input [31:0] got, input [31:0] exp, input [8*60-1:0] name);
    begin
        checks = checks + 1;
        if (got !== exp) begin
            failures = failures + 1;
            $display("FAIL: %0s: expected 0x%0h, actual 0x%0h  (t=%0t)", name, exp, got, $time);
        end
    end
    endtask

    // completion definition from the spec
    integer completions = 0, rdy_in_reset = 0;
    always @(posedge clk) begin
        if (req && rdy && !reset) completions = completions + 1;
        if (reset && rdy) rdy_in_reset = rdy_in_reset + 1;
    end

    // ---------------- bus master ----------------
    integer lat;
    reg [7:0] rd_val;
    task xfer(input we_i, input [15:0] a, input [7:0] wd);
        integer n; reg done;
    begin
        @(negedge clk); we = we_i; addr = a; wdata = wd; req = 1; n = 0; done = 0; rd_val = 8'hxx;
        while (!done && n < 3000) begin
            @(posedge clk); n = n + 1;
            if (rdy && req && !reset) begin rd_val = rdata; done = 1; end
        end
        lat = n;
        check_eq(done, 1, "transaction completes before timeout");
        @(negedge clk); req = 0; we = 0;
        @(negedge clk);
    end
    endtask
    task wr(input [15:0] a, input [7:0] v); begin xfer(1, a, v); end endtask
    task rd(input [15:0] a);               begin xfer(0, a, 8'h00); end endtask
    task idle(input integer n); begin repeat (n) @(negedge clk); end endtask

    task do_reset(input integer n);
    begin
        @(negedge clk); reset = 1; req = 0; we = 0;
        repeat (n) @(negedge clk);
        reset = 0;
        @(negedge clk);
    end
    endtask

    task wait_startup;
        integer k;
    begin
        k = 0; rd(16'hFF12);
        while (rd_val[1] && k < 500) begin rd(16'hFF12); k = k + 1; end
        check_eq(rd_val[1], 0, "startup bit clears");
    end
    endtask

    task wait_idle;                       // transmitter idle
        integer k;
    begin
        k = 0; rd(16'hFF12);
        while (rd_val[0] && k < 500) begin rd(16'hFF12); k = k + 1; end
        check_eq(rd_val[0], 0, "busy bit clears");
    end
    endtask

    // ---------------- RAM model ----------------
    reg [7:0] model [0:16383];
    reg       known [0:16383];
    integer i, j, k0, base_bytes;
    reg [31:0] lfsr;
    function [31:0] nxt(input [31:0] s);
        reg [31:0] x;
    begin x = s; x = x ^ (x << 13); x = x ^ (x >> 17); x = x ^ (x << 5); nxt = x; end
    endfunction

    reg [15:0] alist [0:11];
    reg [15:0] ua [0:15];
    reg [15:0] a16;

    initial begin : timeout
        #100_000_000;
        $display("FAIL: global timeout");
        $fatal(1, "tb_io_bus timeout");
    end

    initial begin
        for (i = 0; i < 16384; i = i + 1) known[i] = 0;
        repeat (3) @(negedge clk);
        reset = 0;
        @(negedge clk);

        // ===== A. startup state after reset =====
        rd(16'hFF12);
        check_eq(rd_val[1], 1, "status bit1 (startup) set right after reset release");
        check_eq(rd_val[7:2], 0, "status bits 7:2 are zero");
        wait_startup;
        rd(16'hFF12);
        check_eq(rd_val, 8'h00, "status idle = 0x00 after startup");

        // ===== B. RAM boundaries =====
        alist[0] = 16'h0000; alist[1] = 16'h0001; alist[2] = 16'h00FF; alist[3] = 16'h0100;
        alist[4] = 16'h1FFF; alist[5] = 16'h2000; alist[6] = 16'h3EFE; alist[7] = 16'h3EFF;
        alist[8] = 16'h3F00; alist[9] = 16'h3F01; alist[10] = 16'h3FFE; alist[11] = 16'h3FFF;
        for (i = 0; i < 12; i = i + 1) begin
            wr(alist[i], i * 17 + 5);
            check_eq(lat, 2, "RAM write takes 2 edges");
            model[alist[i][13:0]] = i * 17 + 5; known[alist[i][13:0]] = 1;
        end
        for (i = 0; i < 12; i = i + 1) begin
            rd(alist[i]);
            check_eq(lat, 2, "RAM read takes 2 edges");
            check_eq(rd_val, model[alist[i][13:0]], "RAM boundary read-back");
        end

        // single-bit addresses: a missing/wrong address bit makes two cells collide
        for (i = 0; i < 14; i = i + 1) ua[i] = 16'h0001 << i;
        ua[14] = 16'h0000; ua[15] = 16'h3FFF;
        for (i = 0; i < 16; i = i + 1) begin
            wr(ua[i], 8'h40 + i);
            model[ua[i][13:0]] = 8'h40 + i; known[ua[i][13:0]] = 1;
        end
        for (i = 0; i < 16; i = i + 1) begin
            rd(ua[i]);
            check_eq(rd_val, 8'h40 + i, "address-bit independence read-back");
        end

        // pseudo-random writes verified against the model
        lfsr = 32'hC0FFEE01;
        for (i = 0; i < 300; i = i + 1) begin
            lfsr = nxt(lfsr); a16 = {2'b00, lfsr[13:0]};
            wr(a16, lfsr[23:16]);
            model[a16[13:0]] = lfsr[23:16]; known[a16[13:0]] = 1;
        end
        k0 = 0;
        for (i = 0; i < 16384; i = i + 1)
            if (known[i] && k0 < 700) begin
                rd(i[15:0]);
                if (rd_val !== model[i]) check_eq(rd_val, model[i], "random RAM model read-back");
                else checks = checks + 1;
                k0 = k0 + 1;
            end

        // ===== C. no aliasing onto RAM or registers from unmapped addresses =====
        wr(16'h0000, 8'h11); model[0] = 8'h11;
        base_bytes = mon.n_bytes;
        uamap;
        check_eq(mon.n_bytes, base_bytes, "unmapped writes send no display byte");
        rd(16'h0000); check_eq(rd_val, 8'h11, "RAM[0] unchanged by unmapped writes");
        rd(16'h3FFF); check_eq(rd_val, 8'h40 + 15, "RAM[0x3FFF] unchanged by unmapped writes");
        rd(16'h0001); check_eq(rd_val, 8'h40 + 0, "RAM[0x0001] unchanged by unmapped writes");

        // ===== D. read-only registers ignore writes; write-only registers read 0 =====
        base_bytes = mon.n_bytes;
        wr(16'hFF00, 8'hFF); check_eq(lat, 2, "write to read-only FF00 completes");
        wr(16'hFF12, 8'hFF); check_eq(lat, 2, "write to read-only FF12 completes");
        rd(16'hFF00); check_eq(rd_val, 8'h00, "buttons unaffected by write to FF00");
        rd(16'hFF12); check_eq(rd_val, 8'h00, "status unaffected by write to FF12");
        rd(16'hFF10); check_eq(rd_val, 8'h00, "read of write-only FF10 returns 0");
        rd(16'hFF11); check_eq(rd_val, 8'h00, "read of write-only FF11 returns 0");
        rd(16'hFF20); check_eq(rd_val, 8'h00, "read of FF20 returns 0");
        check_eq(lat, 2, "read of FF20 does not delay");
        idle(100);
        check_eq(mon.n_bytes, base_bytes, "reads/ro-writes send no display byte");

        // ===== E. buttons register =====
        rd(16'hFF00); check_eq(rd_val, 8'h00, "no buttons pressed reads 0");
        for (i = 0; i < 6; i = i + 1) begin
            btn_n = ~(6'h01 << i);
            idle(DEB + 10);
            rd(16'hFF00); check_eq(rd_val, 8'h01 << i, "single button bit position");
            btn_n = 6'h3F; idle(DEB + 10);
        end
        btn_n = 6'b101010;                    // bits 0,2,4 pressed
        idle(DEB + 10);
        rd(16'hFF00); check_eq(rd_val, 8'b00010101, "multiple buttons, bits 7:6 zero");
        btn_n = 6'h3F; idle(DEB + 10);
        rd(16'hFF00); check_eq(rd_val, 8'h00, "all released reads 0");

        // ===== F. backlight =====
        rd(16'hFF13); check_eq(rd_val, 8'h00, "backlight reads 0 by default");
        check_eq(bl, 0, "BL pin low by default");
        wr(16'hFF13, 8'h01); rd(16'hFF13); check_eq(rd_val, 8'h01, "BL write 1 reads 1"); check_eq(bl, 1, "BL pin high");
        wr(16'hFF13, 8'hFE); rd(16'hFF13); check_eq(rd_val, 8'h00, "BL write FE (bit0=0) reads 0, other bits ignored"); check_eq(bl, 0, "BL pin low");
        wr(16'hFF13, 8'hFF); rd(16'hFF13); check_eq(rd_val, 8'h01, "BL write FF reads 01"); check_eq(bl, 1, "BL pin high after FF");
        wr(16'hFF13, 8'h02); rd(16'hFF13); check_eq(rd_val, 8'h00, "BL write 02 reads 0"); check_eq(bl, 0, "BL pin low after 02");
        wr(16'hFF13, 8'h03); rd(16'hFF13); check_eq(rd_val, 8'h01, "BL write 03 reads 1");
        do_reset(3);
        rd(16'hFF13); check_eq(rd_val, 8'h00, "backlight off after reset");
        check_eq(bl, 0, "BL pin low after reset");
        wait_startup;

        // ===== G. display writes: order, DC, consecutive, held request, backpressure =====
        mon.clear;
        completions = 0;
        wr(16'hFF10, 8'h2A);
        wr(16'hFF11, 8'h00); wr(16'hFF11, 8'h64); wr(16'hFF11, 8'h00); wr(16'hFF11, 8'h8B);
        wr(16'hFF10, 8'h2C);
        wait_idle;
        check_eq(mon.n_bytes, 6, "six display bytes sent");
        check_eq(mon.byte_val[0], 8'h2A, "byte0 value"); check_eq(mon.byte_dc[0], 0, "byte0 is a command (DC=0)");
        check_eq(mon.byte_val[1], 8'h00, "byte1 value"); check_eq(mon.byte_dc[1], 1, "byte1 is data (DC=1)");
        check_eq(mon.byte_val[2], 8'h64, "byte2 value"); check_eq(mon.byte_dc[2], 1, "byte2 DC");
        check_eq(mon.byte_val[3], 8'h00, "byte3 value");
        check_eq(mon.byte_val[4], 8'h8B, "byte4 value"); check_eq(mon.byte_dc[4], 1, "byte4 DC");
        check_eq(mon.byte_val[5], 8'h2C, "byte5 value"); check_eq(mon.byte_dc[5], 0, "byte5 command DC=0");
        check_eq(mon.n_aborted, 0, "no aborted frames");

        // back-to-back writes with no polling: stalled until the transmitter is free
        mon.clear;
        wr(16'hFF11, 8'hA5);
        check_eq(lat, 2, "write to idle transmitter completes in 2 edges");
        rd(16'hFF12);
        check_eq(rd_val[0], 1, "busy set after accepted byte");
        wr(16'hFF11, 8'h5A);
        check_eq((lat > 4), 1, "second write is stalled while the first is sent");
        wr(16'hFF11, 8'h01);
        wr(16'hFF11, 8'h80);
        wr(16'hFF10, 8'hFF);
        wait_idle;
        check_eq(mon.n_bytes, 5, "no byte dropped under backpressure");
        check_eq(mon.byte_val[0], 8'hA5, "bp byte0"); check_eq(mon.byte_val[1], 8'h5A, "bp byte1");
        check_eq(mon.byte_val[2], 8'h01, "bp byte2"); check_eq(mon.byte_val[3], 8'h80, "bp byte3");
        check_eq(mon.byte_val[4], 8'hFF, "bp byte4"); check_eq(mon.byte_dc[4], 0, "bp byte4 is a command");
        check_eq(mon.err_sclk_cs_high + mon.err_dc_change + mon.err_cs_sclk_high, 0, "no protocol errors");

        // held request: exactly one byte even though request stays high 40 cycles
        mon.clear; completions = 0;
        @(negedge clk); we = 1; addr = 16'hFF11; wdata = 8'hC3; req = 1;
        repeat (40) @(posedge clk);
        check_eq(completions, 1, "held display write completes once");
        @(negedge clk); addr = 16'hFF10; wdata = 8'h99;         // protocol violation: change address while held
        repeat (60) @(posedge clk);
        check_eq(completions, 1, "changing address while held does not start another transaction");
        @(negedge clk); req = 0; we = 0;
        idle(80);
        check_eq(mon.n_bytes, 1, "held request sent exactly one byte");
        check_eq(mon.byte_val[0], 8'hC3, "held request byte value");
        check_eq(mon.byte_dc[0], 1, "held request DC");

        // held backlight write completes once
        completions = 0;
        @(negedge clk); we = 1; addr = 16'hFF13; wdata = 8'h01; req = 1;
        repeat (20) @(posedge clk);
        check_eq(completions, 1, "held backlight write completes once");
        @(negedge clk); req = 0; we = 0; idle(2);
        rd(16'hFF13); check_eq(rd_val, 8'h01, "backlight set by held write");
        wr(16'hFF13, 8'h00);

        // ===== H. reset in different transaction phases =====
        // H1: RAM write abandoned by reset in the RDY cycle (before completion) -> no write
        wr(16'h1234, 8'h11);
        @(negedge clk); we = 1; addr = 16'h1234; wdata = 8'h5A; req = 1;
        @(posedge clk);                       // capture edge
        @(negedge clk); reset = 1; req = 0; we = 0;      // reset where ready would be 1
        #1 check_eq(rdy, 0, "ready suppressed in reset (data bus)");
        repeat (3) @(negedge clk); reset = 0; @(negedge clk);
        rd(16'h1234); check_eq(rd_val, 8'h11, "write cancelled by reset leaves old value");
        // H2: reset the cycle after completion (DONE): the write already happened exactly once
        @(negedge clk); we = 1; addr = 16'h1234; wdata = 8'h5A; req = 1;
        @(posedge clk); @(posedge clk);       // completion edge passed
        @(negedge clk); reset = 1; req = 0; we = 0;
        repeat (3) @(negedge clk); reset = 0; @(negedge clk);
        rd(16'h1234); check_eq(rd_val, 8'h5A, "completed write retained across reset");
        // H3: reset in the IDLE capture cycle: nothing captured
        @(negedge clk); reset = 1; we = 1; addr = 16'h1235; wdata = 8'h77; req = 1;
        repeat (2) @(negedge clk); req = 0; we = 0; reset = 0; @(negedge clk);
        rd(16'h1235); check_eq((rd_val !== 8'h77), 1, "request raised during reset is not captured");
        // H4: RAM retention across reset
        wr(16'h2345, 8'hA5);
        do_reset(4);
        rd(16'h2345); check_eq(rd_val, 8'hA5, "RAM contents survive reset");
        rd(16'h1234); check_eq(rd_val, 8'h5A, "RAM contents survive reset (second cell)");
        wait_startup;
        check_eq(rdy_in_reset, 0, "ready never high while reset high");

        // ===== I. display: reset while a write is stalled / byte in flight =====
        mon.clear;
        wr(16'hFF11, 8'hAA);                  // starts sending
        @(negedge clk); we = 1; addr = 16'hFF11; wdata = 8'hBB; req = 1;   // stalled behind AA
        repeat (6) @(posedge clk);
        @(negedge clk); reset = 1; req = 0; we = 0;
        @(negedge clk);
        check_eq(sclk, 0, "SCLK low after reset abort"); check_eq(cs_n, 1, "CS high after reset abort");
        check_eq(dc, 0, "DC low after reset abort");
        check_eq(rst_n, 0, "panel RST held low while system reset is asserted");
        repeat (2) @(negedge clk); reset = 0; @(negedge clk);
        check_eq(mon.n_bytes, 0, "aborted byte not counted and stalled byte never sent");
        check_eq(mon.n_aborted, 1, "one aborted frame seen by the monitor");
        rd(16'hFF12); check_eq(rd_val[1], 1, "startup active again after reset");
        check_eq(rd_val[0], 0, "transmitter idle after reset abort");
        // write issued during startup is stalled until startup ends, then sent whole
        mon.clear;
        wr(16'hFF11, 8'h3C);
        check_eq((lat > T1 + T2), 1, "write during startup stalls through the reset timing");
        wait_idle;
        check_eq(mon.n_bytes, 1, "byte sent after startup");
        check_eq(mon.byte_val[0], 8'h3C, "byte value after startup");
        check_eq(mon.n_aborted, 0, "clean frame after startup");

        // reset exactly when a display write would complete: nothing accepted
        wait_startup;
        mon.clear; base_bytes = 0;
        @(negedge clk); we = 1; addr = 16'hFF11; wdata = 8'h66; req = 1;
        @(posedge clk);                        // capture edge
        @(negedge clk); reset = 1; req = 0; we = 0;   // completion edge would be next
        repeat (2) @(negedge clk); reset = 0; @(negedge clk);
        idle(100);
        check_eq(mon.n_bytes, 0, "no byte accepted when reset coincides with completion edge");
        check_eq(mon.n_aborted, 0, "nothing started");
        check_eq(overrun, 0, "display overrun flag never set");

        $display("tb_io_bus: %0d checks, %0d failures", checks, failures);
        if (failures == 0) $display("PASS: tb_io_bus");
        else $fatal(1, "FAIL: tb_io_bus (%0d failures)", failures);
        $finish;
    end

    // unmapped address probe list (reads return 0, writes have no effect)
    reg [15:0] um [0:25];
    task uamap;
        integer q;
    begin
        um[0]=16'h4000; um[1]=16'h4001; um[2]=16'h7FFF; um[3]=16'h8000; um[4]=16'hC000; um[5]=16'hFEFF;
        um[6]=16'hFF01; um[7]=16'hFF0F; um[8]=16'hFF14; um[9]=16'hFF1F; um[10]=16'hFF21; um[11]=16'hFFFF;
        um[12]=16'hFF40; um[13]=16'h8001; um[14]=16'hBFFF; um[15]=16'hFF02; um[16]=16'h4100;
        um[17]=16'hFF30; um[18]=16'hFE00; um[19]=16'hFF80; um[20]=16'hFF22; um[21]=16'hFF13 ^ 16'h0100;
        um[22]=16'h0000 | 16'h4000; um[23]=16'h8000 | 16'h0001; um[24]=16'hC001; um[25]=16'hFF10 ^ 16'h8000;
        for (q = 0; q < 26; q = q + 1) begin
            rd(um[q]);
            check_eq(rd_val, 8'h00, "unmapped read returns 0");
            check_eq(lat, 2, "unmapped read completes in 2 edges");
            wr(um[q], 8'hFF);
            check_eq(lat, 2, "unmapped write completes in 2 edges, no delay");
        end
        rd(16'hFF13); check_eq(rd_val, 8'h00, "backlight unchanged by unmapped writes");
        rd(16'hFF00); check_eq(rd_val, 8'h00, "buttons unchanged by unmapped writes");
    end
    endtask
endmodule
