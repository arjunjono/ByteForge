`timescale 1ns/1ps
// program_rom.v - ByteForge synchronous program ROM port (Section 23, Stage 1)
//
// 8192 x 16-bit ROM, program addresses 0x0000-0x1FFF, plus the request/ready
// handshake the CPU's program port expects.
//
//  * Contents come from ROM_FILE ($readmemh, one 4-digit hex word per line,
//    exactly 8192 lines produced by sw/build_rom.py, unused words = HALT 0x8800).
//  * There is no reset path into the array: reset only cancels a transaction.
//  * Fetches at 0x2000-0xFFFF return HALT. The address is decoded with all
//    16 bits, nothing is truncated or aliased onto the 8 K words.
//
// Transaction (2 clock edges, request must fall between transactions):
//   IDLE : request seen at edge E0 -> the synchronous read captures the word
//          at E0, state becomes RDY.
//   RDY  : ready = 1 (never while reset). Completion happens at the next edge
//          E1 where request && ready && !reset. read data is valid at E1.
//   DONE : ready = 0 until request has been seen low, so a held request can
//          not complete (or re-trigger) a second time.
module program_rom #(
    parameter ROM_FILE = "byteforge_rom.hex"
) (
    input         clk,
    input         reset,            // synchronous, active high
    input         prog_request,
    input  [15:0] prog_address,
    output        prog_ready,
    output [15:0] prog_read_data
);
    localparam [15:0] HALT_WORD = 16'h8800;   // opcode 17 << 11

    // Memory-style hints: Yosys (rom_style/ram_style) and Gowin synthesis (syn_ramstyle). Without them
    // Yosys 0.33 maps this ROM to ~20k LUTs (found in the first synthesis run).
    (* rom_style = "block", ram_style = "block", syn_ramstyle = "block_ram" *)
    reg [15:0] rom [0:8191];
    // Initial contents come only from the generated file (exactly 8192 lines; sw/build_rom.py pads
    // the unused words with HALT). No fill loop before $readmemh: Yosys applies the loop after the
    // $readmemh and would overwrite the program with HALT (found by inspecting the synthesised ROM
    // init), so the file must be complete. The check below catches a short file in simulation.
    initial $readmemh(ROM_FILE, rom);
`ifndef SYNTHESIS
    initial begin
        #1;
        if (^rom[0] === 1'bx || ^rom[8191] === 1'bx)
            $display("ERROR: program_rom: ROM_FILE '%0s' does not provide all 8192 words", ROM_FILE);
    end
`endif

    // Synchronous read. The out-of-range flag is registered with the data so
    // both belong to the same fetch; the HALT substitution is after the
    // register, which keeps the array a plain registered-address/output read.
    reg [15:0] rom_q;
    reg        oor_q;
    always @(posedge clk) begin
        rom_q <= rom[prog_address[12:0]];
        oor_q <= |prog_address[15:13];
    end
    assign prog_read_data = oor_q ? HALT_WORD : rom_q;

    localparam [1:0] S_IDLE = 2'd0, S_RDY = 2'd1, S_DONE = 2'd2;
    reg [1:0] st;
    always @(posedge clk) begin
        if (reset) st <= S_IDLE;
        else case (st)
            S_IDLE: if (prog_request) st <= S_RDY;
            S_RDY:  if (!prog_request) st <= S_IDLE;     // withdrawn: no action
                    else               st <= S_DONE;     // completion edge
            S_DONE: if (!prog_request) st <= S_IDLE;
            default: st <= S_IDLE;
        endcase
    end
    assign prog_ready = (st == S_RDY) && !reset;
endmodule
