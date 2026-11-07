`timescale 1ns/1ps
// tb_stack.v - real CPU + ROM + RAM: PUSH/POP use the stack region 0x3F00-0x3FFF (STACK_BOTTOM 0x3F00, STACK_TOP 0x4000)
// Run (from sim/), MODE 0 basic, 1 overflow, 2 underflow:
//   iverilog -g2012 -Ptb_stack.MODE=0 -Ptb_stack.ROM="stack_basic.hex" -o stack0.vvp -s tb_stack <rtl> <cpu> ../tb/tb_stack.v
// (the run_all script does all three). RAM contents are inspected through the hierarchy
// (u_io.u_bus.ram) - a white-box peek used only for this check.
module tb_stack;
    parameter integer MODE = 0;
    parameter ROM = "stack_basic.hex";
    reg clk = 0, reset = 1; always #5 clk = ~clk;
    wire halted, fault, ov, sclk, mosi, cs_n, dc, rst_n, bl; wire [15:0] pc, sp;
    byteforge_system #(.CLK_HZ(1000000), .DEBOUNCE_CLKS(4), .CLKS_PER_MS(10), .SPI_HALF_CLKS(2),
                       .RST_HIGH1_CLKS(5), .RST_LOW_CLKS(5), .RST_HIGH2_CLKS(5), .ROM_FILE(ROM)) dut (
        .clk(clk), .reset(reset), .btn_n(6'h3F), .lcd_sclk(sclk), .lcd_mosi(mosi), .lcd_cs_n(cs_n), .lcd_dc(dc),
        .lcd_rst_n(rst_n), .lcd_bl(bl), .halted(halted), .fault(fault), .pc(pc), .sp(sp), .disp_overrun(ov));

    integer checks = 0, failures = 0;
    task check_eq(input [31:0] got, input [31:0] exp, input [8*60-1:0] name);
    begin
        checks = checks + 1;
        if (got !== exp) begin failures = failures + 1;
            $display("FAIL: %0s: expected 0x%0h, actual 0x%0h (t=%0t)", name, exp, got, $time); end
    end
    endtask

    integer k, minsp = 16'hFFFF;
    always @(posedge clk) if (!reset && sp < minsp) minsp = sp;

    initial begin : timeout
        #20_000_000; $display("FAIL: global timeout (program neither halted nor faulted)"); $fatal(1, "tb_stack timeout");
    end
    initial begin
        repeat (4) @(posedge clk); reset <= 0;
        check_eq(sp, 16'h4000, "SP starts at STACK_TOP after reset");
        begin : run
            integer n; n = 0;
            while (!halted && !fault && n < 400000) begin @(posedge clk); n = n + 1; end
        end
        repeat (5) @(posedge clk);
        if (MODE == 0) begin
            check_eq(halted, 1, "basic program halts"); check_eq(fault, 0, "no fault");
            check_eq(sp, 16'h4000, "SP back at STACK_TOP");
            check_eq(dut.u_io.u_bus.ram[16'h3FFF], 8'h11, "first PUSH wrote 0x3FFF");
            check_eq(dut.u_io.u_bus.ram[16'h3FFE], 8'h22, "second PUSH wrote 0x3FFE");
            check_eq(dut.u_io.u_bus.ram[16'h3FFD], 8'h33, "third PUSH wrote 0x3FFD");
            check_eq(dut.u_io.u_bus.ram[16'h0100], 8'h33, "last pushed popped first");
            check_eq(dut.u_io.u_bus.ram[16'h0101], 8'h22, "second pop");
            check_eq(dut.u_io.u_bus.ram[16'h0102], 8'h11, "third pop");
            check_eq(minsp, 16'h3FFD, "lowest SP reached");
        end else if (MODE == 1) begin
            check_eq(fault, 1, "257th PUSH faults (stack overflow)");
            check_eq(sp, 16'h3F00, "SP stops at STACK_BOTTOM");
            check_eq(minsp, 16'h3F00, "SP never goes below STACK_BOTTOM");
            check_eq(dut.u_io.u_bus.ram[16'h3EFF], 8'hAB, "sentinel below the stack region untouched");
            check_eq(dut.u_io.u_bus.ram[16'h0200], 8'h5C, "marker after 256th push executed");
            check_eq((dut.u_io.u_bus.ram[16'h0201] !== 8'h5C), 1, "instruction after faulting PUSH not executed");
            for (k = 0; k < 256; k = k + 1)
                if (dut.u_io.u_bus.ram[16'h3FFF - k] !== ((8'hAB + k) & 8'hFF))
                    check_eq(dut.u_io.u_bus.ram[16'h3FFF - k], (8'hAB + k) & 8'hFF, "stack cell value (distinct per push)");
                else checks = checks + 1;
        end else begin
            check_eq(fault, 1, "POP on empty stack faults (underflow)");
            check_eq(sp, 16'h4000, "SP unchanged");
            check_eq(dut.u_io.u_bus.ram[16'h0300], 8'h77, "store before fault executed");
            check_eq((dut.u_io.u_bus.ram[16'h0301] !== 8'h77), 1, "instruction after faulting POP not executed");
        end
        check_eq(ov, 0, "no display overrun");
        $display("tb_stack (MODE=%0d): %0d checks, %0d failures", MODE, checks, failures);
        if (failures == 0) $display("PASS: tb_stack MODE=%0d", MODE);
        else $fatal(1, "FAIL: tb_stack (%0d failures)", failures);
        $finish;
    end
endmodule
