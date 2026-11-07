// register_file.v - ByteForge general-purpose register file
// Four 8-bit registers (R0-R3), two combinational read ports,
// one synchronous write port, active-high synchronous reset.
`timescale 1ns/1ps

module register_file (
    input        clk,
    input        reset,          // active-high, synchronous
    input        write_enable,
    input  [1:0] write_addr,
    input  [7:0] write_data,
    input  [1:0] read_addr_a,
    input  [1:0] read_addr_b,
    output [7:0] read_data_a,
    output [7:0] read_data_b
);

    // Storage: regs[0]=R0, regs[1]=R1, regs[2]=R2, regs[3]=R3
    // No initial block: the testbench (or CPU) must apply reset.
    reg [7:0] regs [0:3];

    // Clocked write / reset (nonblocking assignments)
    always @(posedge clk) begin
        if (reset) begin
            // Reset has priority over write_enable
            regs[0] <= 8'h00;
            regs[1] <= 8'h00;
            regs[2] <= 8'h00;
            regs[3] <= 8'h00;
        end else if (write_enable) begin
            regs[write_addr] <= write_data;
        end
        // else: no assignment, so the registers keep their values
    end

    // Combinational (asynchronous) read ports
    assign read_data_a = regs[read_addr_a];
    assign read_data_b = regs[read_addr_b];

endmodule
