// cpu.v - ByteForge CPU core (integration wrapper, simulation stage)
//
// Pure wiring: connects the existing control_unit, register_file,
// flags_register and alu modules. It contains no execution logic and no
// architectural state of its own. The instruction decoder lives inside
// control_unit. Program and data memories stay external.
//
//   program memory <--> u_control <--> data memory
//                        |  ^
//         read addrs/write port    stored Z
//                        v  |
//                    u_registers --A,B--> u_alu --result,Z,C,N--> u_control
//                                                                   |
//                                       u_flags <-- write enable + flag inputs
`timescale 1ns/1ps

module cpu #(
    parameter [15:0] STACK_BOTTOM = 16'h0100,
    parameter [15:0] STACK_TOP    = 16'h0200   // exclusive; empty-stack SP
) (
    input         clk,
    input         reset,              // active-high, synchronous

    // Program memory (word addressed)
    output        prog_request,
    output [15:0] prog_address,
    input         prog_ready,
    input  [15:0] prog_read_data,

    // Data memory (byte addressed)
    output        data_request,
    output        data_write_enable,  // direction of the requested transaction
    output [15:0] data_address,
    output [7:0]  data_write_data,
    input         data_ready,
    input  [7:0]  data_read_data,

    // Status
    output        halted,
    output        fault,
    output [15:0] pc,
    output [15:0] sp,
    output        Z,                  // stored FLAGS
    output        C,
    output        N
);

    // Internal nets between the modules
    wire [1:0] reg_read_addr_a;
    wire [1:0] reg_read_addr_b;
    wire [7:0] reg_read_data_a;
    wire [7:0] reg_read_data_b;
    wire       reg_write_enable;
    wire [1:0] reg_write_addr;
    wire [7:0] reg_write_data;

    wire [4:0] alu_opcode;
    wire [7:0] alu_result;
    wire       alu_z;
    wire       alu_c;
    wire       alu_n;

    wire       flags_write_enable;
    wire       flags_z_in;
    wire       flags_c_in;
    wire       flags_n_in;

    control_unit #(
        .STACK_BOTTOM (STACK_BOTTOM),
        .STACK_TOP    (STACK_TOP)
    ) u_control (
        .clk               (clk),
        .reset             (reset),
        .prog_request      (prog_request),
        .prog_address      (prog_address),
        .prog_ready        (prog_ready),
        .prog_read_data    (prog_read_data),
        .data_request      (data_request),
        .data_write_enable (data_write_enable),
        .data_address      (data_address),
        .data_write_data   (data_write_data),
        .data_ready        (data_ready),
        .data_read_data    (data_read_data),
        .reg_read_addr_a   (reg_read_addr_a),
        .reg_read_addr_b   (reg_read_addr_b),
        .reg_read_data_a   (reg_read_data_a),
        .reg_read_data_b   (reg_read_data_b),
        .reg_write_enable  (reg_write_enable),
        .reg_write_addr    (reg_write_addr),
        .reg_write_data    (reg_write_data),
        .alu_opcode        (alu_opcode),
        .alu_result        (alu_result),
        .alu_z             (alu_z),
        .alu_c             (alu_c),
        .alu_n             (alu_n),
        .flags_write_enable(flags_write_enable),
        .flags_z_in        (flags_z_in),
        .flags_c_in        (flags_c_in),
        .flags_n_in        (flags_n_in),
        .stored_z          (Z),
        .halted            (halted),
        .fault             (fault),
        .pc                (pc),
        .sp                (sp)
    );

    register_file u_registers (
        .clk         (clk),
        .reset       (reset),
        .write_enable(reg_write_enable),
        .write_addr  (reg_write_addr),
        .write_data  (reg_write_data),
        .read_addr_a (reg_read_addr_a),
        .read_addr_b (reg_read_addr_b),
        .read_data_a (reg_read_data_a),
        .read_data_b (reg_read_data_b)
    );

    flags_register u_flags (
        .clk               (clk),
        .reset             (reset),
        .flags_write_enable(flags_write_enable),
        .Z_in              (flags_z_in),
        .C_in              (flags_c_in),
        .N_in              (flags_n_in),
        .Z                 (Z),
        .C                 (C),
        .N                 (N)
    );

    alu u_alu (
        .A     (reg_read_data_a),
        .B     (reg_read_data_b),
        .opcode(alu_opcode),
        .result(alu_result),
        .Z     (alu_z),
        .C     (alu_c),
        .N     (alu_n)
    );

endmodule
