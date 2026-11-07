// assembly_programs_tb.v - end-to-end test: assembler output running on the
// real ByteForge CPU core.
//
// The design under test is the real `cpu` wrapper (control_unit, instruction
// decoder, register_file, flags_register, alu - all unmodified). Only the
// program memory and the data memory are behavioural. The program memory is
// filled from the assembler-generated .hex files with $readmemh; no machine
// code is written in this file.
//
// Each of the three demonstration programs runs three times:
//   mode 0  immediate-ready memories (no wait states)
//   mode 1  fixed wait states (program 3 cycles, data 5 cycles)
//   mode 2  random wait states (program 0-6 cycles, data 0-8 cycles)
//
// The expected results below were worked out by hand (see the comments at the
// top of arithmetic.asm, countdown.asm and memory_stack.asm); they are not
// produced by any model of the CPU in this file.
//
// Files needed in the simulation working directory:
//   arithmetic.hex  countdown.hex  memory_stack.hex
//
// Timing: clk period 10 ns (rising edges at 5, 15, 25 ... ns). Memory ready
// and read data change on falling edges; reset changes 1 ns after a falling
// edge; the scoreboard samples on rising edges (it sees the pre-edge values).
`timescale 1ns/1ps

module assembly_programs_tb;

    localparam [15:0] STACK_BOTTOM = 16'h0100;
    localparam [15:0] STACK_TOP    = 16'h0104;
    localparam        LOGN         = 64;

    // Actual word counts of the assembled programs (bound the $readmemh calls)
    localparam ARITH_WORDS = 13;
    localparam COUNT_WORDS = 10;
    localparam MEM_WORDS   = 16;

    localparam NUM_PROGRAMS   = 3;
    localparam NUM_MODES      = 3;
    localparam MAX_RUN_CYCLES = 20000;

    // ------------------------------------------------------------------
    // CPU core connections
    // ------------------------------------------------------------------
    reg         clk;
    reg         reset;
    reg         prog_ready;
    reg  [15:0] prog_read_data;
    reg         data_ready;
    reg  [7:0]  data_read_data;

    wire        prog_request;
    wire [15:0] prog_address;
    wire        data_request;
    wire        data_write_enable;
    wire [15:0] data_address;
    wire [7:0]  data_write_data;
    wire        halted;
    wire        fault;
    wire [15:0] pc;
    wire [15:0] sp;
    wire        Z, C, N;

    // Read-only taps used by the scoreboard (same hierarchy as cpu_tb.v)
    wire        reg_write_enable   = dut.reg_write_enable;
    wire [1:0]  reg_write_addr     = dut.reg_write_addr;
    wire [7:0]  reg_write_data     = dut.reg_write_data;
    wire        flags_write_enable = dut.flags_write_enable;
    wire        flags_z_in         = dut.flags_z_in;
    wire        flags_c_in         = dut.flags_c_in;
    wire        flags_n_in         = dut.flags_n_in;

    wire [7:0]  rf [0:3];
    assign rf[0] = dut.u_registers.regs[0];
    assign rf[1] = dut.u_registers.regs[1];
    assign rf[2] = dut.u_registers.regs[2];
    assign rf[3] = dut.u_registers.regs[3];

    cpu #(
        .STACK_BOTTOM (STACK_BOTTOM),
        .STACK_TOP    (STACK_TOP)
    ) dut (
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
        .halted            (halted),
        .fault             (fault),
        .pc                (pc),
        .sp                (sp),
        .Z                 (Z),
        .C                 (C),
        .N                 (N)
    );

    // ------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Bookkeeping
    // ------------------------------------------------------------------
    integer checks;
    integer failures;
    integer run_count;
    integer cur_prog;
    integer cur_mode;
    reg [8*16-1:0] cur_name;
    reg [8*24-1:0] cur_mode_name;

    // ------------------------------------------------------------------
    // Memory models: ready/data are driven on falling edges; a pending
    // transaction is cancelled by reset. Writes happen at the rising edge on
    // which request and ready are both high (see the scoreboard below).
    // ------------------------------------------------------------------
    reg [15:0] pmem    [0:65535];
    reg [7:0]  dmem    [0:65535];

    integer prog_delay_max, data_delay_max;
    reg     prog_delay_rand, data_delay_rand;
    integer pseed, dseed;
    integer pw_goal, pw_cnt, dw_goal, dw_cnt;
    reg     pw_active, dw_active;

    always @(negedge clk) begin
        if (reset || !prog_request) begin
            prog_ready     <= 1'b0;
            prog_read_data <= 16'hxxxx;
            pw_active = 1'b0;
            pw_cnt    = 0;
        end else begin
            if (!pw_active) begin
                pw_active = 1'b1;
                pw_cnt    = 0;
                if (prog_delay_rand) pw_goal = {$random(pseed)} % (prog_delay_max + 1);
                else                 pw_goal = prog_delay_max;
            end
            if (pw_cnt >= pw_goal) begin
                prog_ready     <= 1'b1;
                prog_read_data <= pmem[prog_address];
            end else begin
                prog_ready     <= 1'b0;
                prog_read_data <= 16'hxxxx;
                pw_cnt = pw_cnt + 1;
            end
        end
    end

    always @(negedge clk) begin
        if (reset || !data_request) begin
            data_ready     <= 1'b0;
            data_read_data <= 8'hxx;
            dw_active = 1'b0;
            dw_cnt    = 0;
        end else begin
            if (!dw_active) begin
                dw_active = 1'b1;
                dw_cnt    = 0;
                if (data_delay_rand) dw_goal = {$random(dseed)} % (data_delay_max + 1);
                else                 dw_goal = data_delay_max;
            end
            if (dw_cnt >= dw_goal) begin
                data_ready     <= 1'b1;
                data_read_data <= dmem[data_address];
            end else begin
                data_ready     <= 1'b0;
                data_read_data <= 8'hxx;
                dw_cnt = dw_cnt + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Scoreboard: logs every completed transaction and every register, FLAGS
    // and SP update, in order (sampled on rising edges)
    // ------------------------------------------------------------------
    reg     mon_on;
    integer n_prog_txn, n_data_txn, n_data_rd, n_data_wr, n_reg_wr, n_flag_wr, n_sp_chg;

    reg [15:0] plog_addr  [0:LOGN-1];
    reg        dlog_wr    [0:LOGN-1];
    reg [15:0] dlog_addr  [0:LOGN-1];
    reg [7:0]  dlog_data  [0:LOGN-1];
    reg [1:0]  rwlog_addr [0:LOGN-1];
    reg [7:0]  rwlog_data [0:LOGN-1];
    reg [2:0]  fwlog_zcn  [0:LOGN-1];
    reg [15:0] splog_val  [0:LOGN-1];

    reg        p_done, d_done;
    reg [15:0] sp_last;

    always @(posedge clk) begin
        if (mon_on) begin
            checks = checks + 1;
            p_done = (prog_request === 1'b1) && (prog_ready === 1'b1) && !reset;
            d_done = (data_request === 1'b1) && (data_ready === 1'b1) && !reset;

            // Reset must hold off every request and every write
            if (reset) begin
                if (prog_request !== 1'b0 || data_request !== 1'b0 ||
                    reg_write_enable !== 1'b0 || flags_write_enable !== 1'b0) begin
                    failures = failures + 1;
                    $display("FAIL @%0t [%0s | %0s] request or write enable active during reset",
                             $time, cur_name, cur_mode_name);
                end
            end

            if (sp !== sp_last) begin
                if (!reset) begin
                    if (n_sp_chg < LOGN) splog_val[n_sp_chg] = sp;
                    n_sp_chg = n_sp_chg + 1;
                end
                sp_last = sp;
            end

            if (p_done) begin
                if (n_prog_txn < LOGN) plog_addr[n_prog_txn] = prog_address;
                n_prog_txn = n_prog_txn + 1;
            end

            if (d_done) begin
                if (n_data_txn < LOGN) begin
                    dlog_wr[n_data_txn]   = data_write_enable;
                    dlog_addr[n_data_txn] = data_address;
                    dlog_data[n_data_txn] = (data_write_enable === 1'b1) ? data_write_data : data_read_data;
                end
                n_data_txn = n_data_txn + 1;
                if (data_write_enable === 1'b1) begin
                    n_data_wr = n_data_wr + 1;
                    dmem[data_address] <= data_write_data;   // the write happens exactly here, once
                end else begin
                    n_data_rd = n_data_rd + 1;
                end
            end

            if (reg_write_enable === 1'b1 && !reset) begin
                if (n_reg_wr < LOGN) begin
                    rwlog_addr[n_reg_wr] = reg_write_addr;
                    rwlog_data[n_reg_wr] = reg_write_data;
                end
                n_reg_wr = n_reg_wr + 1;
            end

            if (flags_write_enable === 1'b1 && !reset) begin
                if (n_flag_wr < LOGN) fwlog_zcn[n_flag_wr] = {flags_z_in, flags_c_in, flags_n_in};
                n_flag_wr = n_flag_wr + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Check tasks
    // ------------------------------------------------------------------
    task chk;
        input [8*36-1:0] what;
        input integer    idx;
        input [31:0]     exp_v;
        input [31:0]     act_v;
        begin
            checks = checks + 1;
            if (act_v !== exp_v) begin
                failures = failures + 1;
                $display("FAIL @%0t [%0s | %0s] %0s(#%0d): expected 0x%h, actual 0x%h | PC=0x%h SP=0x%h",
                         $time, cur_name, cur_mode_name, what, idx, exp_v, act_v, pc, sp);
            end
        end
    endtask

    integer ri, fi, di, pi_i, si;      // cursors into the logs

    task x_rw;      // expected register write
        input [1:0] a; input [7:0] d;
        begin
            if (ri >= n_reg_wr || ri >= LOGN) begin
                checks = checks + 1; failures = failures + 1;
                $display("FAIL @%0t [%0s | %0s] missing register write #%0d: expected R%0d <= 0x%h",
                         $time, cur_name, cur_mode_name, ri, a, d);
            end else begin
                chk("register write address", ri, a, rwlog_addr[ri]);
                chk("register write data",    ri, d, rwlog_data[ri]);
            end
            ri = ri + 1;
        end
    endtask

    task x_fw;      // expected FLAGS write (Z, C, N)
        input z; input c; input n;
        begin
            if (fi >= n_flag_wr || fi >= LOGN) begin
                checks = checks + 1; failures = failures + 1;
                $display("FAIL @%0t [%0s | %0s] missing FLAGS write #%0d: expected ZCN=%b%b%b",
                         $time, cur_name, cur_mode_name, fi, z, c, n);
            end else begin
                chk("FLAGS write (Z,C,N)", fi, {z, c, n}, fwlog_zcn[fi]);
            end
            fi = fi + 1;
        end
    endtask

    task x_d;       // expected data transaction (1 = write)
        input wr; input [15:0] a; input [7:0] d;
        begin
            if (di >= n_data_txn || di >= LOGN) begin
                checks = checks + 1; failures = failures + 1;
                $display("FAIL @%0t [%0s | %0s] missing data transaction #%0d: expected %0s addr 0x%h data 0x%h",
                         $time, cur_name, cur_mode_name, di, wr ? "write" : "read", a, d);
            end else begin
                chk("data transaction is a write", di, wr, dlog_wr[di]);
                chk("data transaction address",    di, a,  dlog_addr[di]);
                chk("data transaction data",       di, d,  dlog_data[di]);
            end
            di = di + 1;
        end
    endtask

    task x_pf;      // expected program fetch address
        input [15:0] a;
        begin
            if (pi_i >= n_prog_txn || pi_i >= LOGN) begin
                checks = checks + 1; failures = failures + 1;
                $display("FAIL @%0t [%0s | %0s] missing program fetch #%0d: expected address 0x%h",
                         $time, cur_name, cur_mode_name, pi_i, a);
            end else begin
                chk("program fetch address", pi_i, a, plog_addr[pi_i]);
            end
            pi_i = pi_i + 1;
        end
    endtask

    task x_sp;      // expected SP update
        input [15:0] v;
        begin
            if (si >= n_sp_chg || si >= LOGN) begin
                checks = checks + 1; failures = failures + 1;
                $display("FAIL @%0t [%0s | %0s] missing SP update #%0d: expected SP=0x%h",
                         $time, cur_name, cur_mode_name, si, v);
            end else begin
                chk("SP value after update", si, v, splog_val[si]);
            end
            si = si + 1;
        end
    endtask

    // Nothing may have happened beyond what the program was expected to do
    task x_done;
        begin
            chk("extra register writes",    -1, n_reg_wr,   ri);
            chk("extra FLAGS writes",       -1, n_flag_wr,  fi);
            chk("extra data transactions",  -1, n_data_txn, di);
            chk("extra program fetches",    -1, n_prog_txn, pi_i);
            chk("extra SP updates",         -1, n_sp_chg,   si);
        end
    endtask

    task x_final;   // final architectural state
        input [7:0] r0; input [7:0] r1; input [7:0] r2; input [7:0] r3;
        input z; input c; input n;
        input [15:0] epc; input [15:0] esp;
        begin
            chk("halted", -1, 1, halted);
            chk("fault",  -1, 0, fault);
            chk("final R0", -1, r0, rf[0]);
            chk("final R1", -1, r1, rf[1]);
            chk("final R2", -1, r2, rf[2]);
            chk("final R3", -1, r3, rf[3]);
            chk("final Z", -1, z, Z);
            chk("final C", -1, c, C);
            chk("final N", -1, n, N);
            chk("final PC", -1, epc, pc);
            chk("final SP", -1, esp, sp);
        end
    endtask

    // ------------------------------------------------------------------
    // Run infrastructure
    // ------------------------------------------------------------------
    integer k;
    integer counted;
    reg     stopped;

    task clear_memories;
        begin
            for (k = 0; k < 65536; k = k + 1) begin
                pmem[k] = 16'hFFFF;      // run-away execution reaches an invalid opcode and faults
                dmem[k] = 8'h00;
            end
        end
    endtask

    // Load one assembled program. First count the words in the .hex file with
    // $fscanf, so a stale or wrong-length file is caught; then do a $readmemh
    // bounded to the program's actual word count (no short-file warning).
    integer fd, rc;
    reg [15:0] word_tmp;

    task load_program;
        input integer prog;
        integer nwords;
        begin
            case (prog)
                0: begin nwords = ARITH_WORDS; fd = $fopen("arithmetic.hex",   "r"); end
                1: begin nwords = COUNT_WORDS; fd = $fopen("countdown.hex",    "r"); end
                default: begin nwords = MEM_WORDS; fd = $fopen("memory_stack.hex", "r"); end
            endcase
            counted = 0;
            if (fd == 0) begin
                $display("FAIL [%0s | %0s] cannot open the .hex file in the working directory",
                         cur_name, cur_mode_name);
            end else begin
                rc = $fscanf(fd, "%h", word_tmp);
                while (rc == 1) begin
                    counted = counted + 1;
                    rc = $fscanf(fd, "%h", word_tmp);
                end
                $fclose(fd);
            end
            chk("words in .hex file", -1, nwords, counted);
            case (prog)
                0: $readmemh("arithmetic.hex",   pmem, 0, ARITH_WORDS - 1);
                1: $readmemh("countdown.hex",    pmem, 0, COUNT_WORDS - 1);
                default: $readmemh("memory_stack.hex", pmem, 0, MEM_WORDS - 1);
            endcase
        end
    endtask

    task configure_delays;
        input integer mode;
        begin
            case (mode)
                0: begin prog_delay_max = 0; data_delay_max = 0; prog_delay_rand = 1'b0; data_delay_rand = 1'b0; end
                1: begin prog_delay_max = 3; data_delay_max = 5; prog_delay_rand = 1'b0; data_delay_rand = 1'b0; end
                default: begin prog_delay_max = 6; data_delay_max = 8; prog_delay_rand = 1'b1; data_delay_rand = 1'b1; end
            endcase
        end
    endtask

    task clear_scoreboard;
        begin
            n_prog_txn = 0; n_data_txn = 0; n_data_rd = 0; n_data_wr = 0;
            n_reg_wr = 0; n_flag_wr = 0; n_sp_chg = 0;
            ri = 0; fi = 0; di = 0; pi_i = 0; si = 0;
            sp_last = sp;
            mon_on = 1'b1;
        end
    endtask

    task wait_for_stop;
        integer c;
        begin
            stopped = 1'b0;
            c = 0;
            while (!stopped && c < MAX_RUN_CYCLES) begin
                @(negedge clk);
                c = c + 1;
                if (halted === 1'b1 || fault === 1'b1) stopped = 1'b1;
            end
            chk("program stopped before timeout", -1, 1, stopped);
        end
    endtask

    // After HALT the CPU must stay stopped: no requests, no state changes
    task stay_stopped;
        input integer n;
        reg [15:0] s_pc, s_sp;
        reg [7:0]  s_r0, s_r1, s_r2, s_r3;
        reg        s_z, s_c, s_n;
        integer    j;
        begin
            @(negedge clk);
            s_pc = pc; s_sp = sp; s_z = Z; s_c = C; s_n = N;
            s_r0 = rf[0]; s_r1 = rf[1]; s_r2 = rf[2]; s_r3 = rf[3];
            for (j = 0; j < n; j = j + 1) begin
                @(negedge clk);
                chk("stopped: prog_request low", j, 0, prog_request);
                chk("stopped: data_request low", j, 0, data_request);
            end
            chk("stopped: PC stable", -1, s_pc, pc);
            chk("stopped: SP stable", -1, s_sp, sp);
            chk("stopped: R0 stable", -1, s_r0, rf[0]);
            chk("stopped: R1 stable", -1, s_r1, rf[1]);
            chk("stopped: R2 stable", -1, s_r2, rf[2]);
            chk("stopped: R3 stable", -1, s_r3, rf[3]);
            chk("stopped: flags stable", -1, {s_z, s_c, s_n}, {Z, C, N});
        end
    endtask

    // ------------------------------------------------------------------
    // Expected results, worked out by hand (see the .asm file headers)
    // ------------------------------------------------------------------
    task check_arithmetic;
        integer a;
        begin
            x_final(8'h00, 8'h3C, 8'h2C, 8'h9C, 1'b0, 1'b1, 1'b1, 16'h000D, 16'h0104);
            // register writes in program order (CMP and MOV flags/none noted)
            x_rw(0, 8'hC8); x_rw(1, 8'h64); x_rw(2, 8'hC8);
            x_rw(2, 8'h2C); x_fw(0, 1, 0);       // ADD: C8+64 = 12C, carry
            x_rw(3, 8'h64);                      // MOV: no FLAGS write
            x_rw(3, 8'h9C); x_fw(0, 1, 1);       // SUB: 64-C8, borrow, negative
            x_rw(0, 8'hF0); x_rw(1, 8'h3C);
            x_rw(0, 8'h30); x_fw(0, 0, 0);       // AND
            x_rw(0, 8'h3C); x_fw(0, 0, 0);       // OR
            x_rw(0, 8'h00); x_fw(1, 0, 0);       // XOR: zero
            x_fw(0, 1, 1);                       // CMP 2C-3C: FLAGS only, no register write
            for (a = 0; a < 13; a = a + 1) x_pf(a);
            x_done;                              // no memory access, no SP change
            chk("data reads",  -1, 0, n_data_rd);
            chk("data writes", -1, 0, n_data_wr);
        end
    endtask

    task check_countdown;
        integer p;
        begin
            x_final(8'h00, 8'h01, 8'h0F, 8'h05, 1'b1, 1'b0, 1'b0, 16'h000A, 16'h0104);
            x_rw(0, 8'h05); x_rw(1, 8'h01); x_rw(2, 8'h00); x_rw(3, 8'h00);
            // pass 1..5: R2 += R0, R3 += 1, R0 -= 1
            x_rw(2, 8'h05); x_fw(0, 0, 0); x_rw(3, 8'h01); x_fw(0, 0, 0); x_rw(0, 8'h04); x_fw(0, 0, 0);
            x_rw(2, 8'h09); x_fw(0, 0, 0); x_rw(3, 8'h02); x_fw(0, 0, 0); x_rw(0, 8'h03); x_fw(0, 0, 0);
            x_rw(2, 8'h0C); x_fw(0, 0, 0); x_rw(3, 8'h03); x_fw(0, 0, 0); x_rw(0, 8'h02); x_fw(0, 0, 0);
            x_rw(2, 8'h0E); x_fw(0, 0, 0); x_rw(3, 8'h04); x_fw(0, 0, 0); x_rw(0, 8'h01); x_fw(0, 0, 0);
            x_rw(2, 8'h0F); x_fw(0, 0, 0); x_rw(3, 8'h05); x_fw(0, 0, 0); x_rw(0, 8'h00); x_fw(1, 0, 0);
            // fetch order: 0-3, then five passes through 4..8, then HALT at 9
            x_pf(0); x_pf(1); x_pf(2); x_pf(3);
            for (p = 0; p < 5; p = p + 1) begin
                x_pf(4); x_pf(5); x_pf(6); x_pf(7); x_pf(8);
            end
            x_pf(9);
            x_done;
            chk("data reads",  -1, 0, n_data_rd);
            chk("data writes", -1, 0, n_data_wr);
        end
    endtask

    task check_memory_stack;
        integer a;
        begin
            x_final(8'h33, 8'h22, 8'h11, 8'h44, 1'b0, 1'b0, 1'b0, 16'h0010, 16'h0104);
            // register writes (STORE, PUSH write memory only; no FLAGS writes at all)
            x_rw(3, 8'h44); x_rw(3, 8'h00); x_rw(3, 8'h44);           // LOADI, LOADI, LOAD
            x_rw(0, 8'h11); x_rw(1, 8'h22); x_rw(2, 8'h33);
            x_rw(0, 8'h33); x_rw(1, 8'h22); x_rw(2, 8'h11);           // POP R0,R1,R2: reversed
            // data transactions in order
            x_d(1, 16'h0200, 8'h44);                                    // STORE
            x_d(0, 16'h0200, 8'h44);                                    // LOAD
            x_d(1, 16'h0103, 8'h11);                                    // PUSH R0
            x_d(1, 16'h0102, 8'h22);                                    // PUSH R1
            x_d(1, 16'h0101, 8'h33);                                    // PUSH R2
            x_d(0, 16'h0101, 8'h33);                                    // POP R0 (last in, first out)
            x_d(0, 16'h0102, 8'h22);                                    // POP R1
            x_d(0, 16'h0103, 8'h11);                                    // POP R2
            // SP: three pushes down, three pops back up
            x_sp(16'h0103); x_sp(16'h0102); x_sp(16'h0101);
            x_sp(16'h0102); x_sp(16'h0103); x_sp(16'h0104);
            for (a = 0; a < 16; a = a + 1) x_pf(a);
            x_done;
            chk("data reads",  -1, 4, n_data_rd);
            chk("data writes", -1, 4, n_data_wr);
            // memory contents
            chk("mem[0200]", -1, 8'h44, dmem[16'h0200]);
            chk("mem[0103]", -1, 8'h11, dmem[16'h0103]);
            chk("mem[0102]", -1, 8'h22, dmem[16'h0102]);
            chk("mem[0101]", -1, 8'h33, dmem[16'h0101]);
            chk("mem[0100]", -1, 8'h00, dmem[16'h0100]);
        end
    endtask

    // ------------------------------------------------------------------
    // One complete run: reset, clear memories, load the .hex file, execute
    // ------------------------------------------------------------------
    task run_one;
        input integer prog;
        input integer mode;
        integer fails_before;
        begin
            cur_prog = prog;
            cur_mode = mode;
            run_count = run_count + 1;
            fails_before = failures;
            case (prog)
                0: cur_name = "arithmetic";
                1: cur_name = "countdown";
                default: cur_name = "memory_stack";
            endcase
            case (mode)
                0: cur_mode_name = "immediate ready";
                1: cur_mode_name = "fixed waits 3/5";
                default: cur_mode_name = "random waits 0-6/0-8";
            endcase

            // Reset (changes between rising edges), then reload everything
            @(negedge clk); #1;
            reset  = 1'b1;
            mon_on = 1'b0;
            @(posedge clk);
            @(negedge clk); #1;
            clear_memories;
            load_program(prog);
            configure_delays(mode);
            clear_scoreboard;
            @(posedge clk);
            @(negedge clk); #1;
            reset = 1'b0;

            wait_for_stop;
            stay_stopped(6);

            case (prog)
                0: check_arithmetic;
                1: check_countdown;
                default: check_memory_stack;
            endcase

            if (failures == fails_before)
                $display("ok   %0s / %0s: R0-R3=%h %h %h %h  ZCN=%b%b%b  PC=%h  SP=%h  halted=%b fault=%b",
                         cur_name, cur_mode_name, rf[0], rf[1], rf[2], rf[3], Z, C, N, pc, sp, halted, fault);
            else
                $display("FAIL %0s / %0s: see messages above", cur_name, cur_mode_name);
        end
    endtask

    // ------------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------------
    integer ip, im;

    initial begin
        $dumpfile("assembly_programs_waveform.vcd");
        $dumpvars(0, assembly_programs_tb);

        checks = 0; failures = 0; run_count = 0; cur_prog = 0; cur_mode = 0;
        cur_name = "start"; cur_mode_name = "start";
        mon_on = 1'b0;
        n_prog_txn = 0; n_data_txn = 0; n_data_rd = 0; n_data_wr = 0;
        n_reg_wr = 0; n_flag_wr = 0; n_sp_chg = 0;
        ri = 0; fi = 0; di = 0; pi_i = 0; si = 0; sp_last = 16'h0000;
        prog_delay_max = 0; data_delay_max = 0;
        prog_delay_rand = 1'b0; data_delay_rand = 1'b0;
        pseed = 32'h2468_ACE1; dseed = 32'h1357_9BDF;
        pw_active = 1'b0; dw_active = 1'b0; pw_cnt = 0; dw_cnt = 0; pw_goal = 0; dw_goal = 0;
        prog_ready = 1'b0; prog_read_data = 16'h0000;
        data_ready = 1'b0; data_read_data = 8'h00;
        stopped = 1'b0;
        reset = 1'b1;                    // the CPU has no initial block: reset from time 0

        for (ip = 0; ip < NUM_PROGRAMS; ip = ip + 1)
            for (im = 0; im < NUM_MODES; im = im + 1)
                run_one(ip, im);

        $display("----------------------------------------");
        $display("Programs: %0d   Runs: %0d", NUM_PROGRAMS, run_count);
        $display("Checks run: %0d   Failures: %0d", checks, failures);
        if (failures == 0) begin
            $display("PASS: all %0d checks passed", checks);
            $display("----------------------------------------");
            $finish;
        end else begin
            $display("FAIL: %0d of %0d checks failed", failures, checks);
            $display("----------------------------------------");
            $fatal(1, "assembly_programs_tb: %0d check(s) failed", failures);
        end
    end

    // Global watchdog: a stuck handshake can never hang the simulation
    initial begin
        #50000000;
        $display("FAIL: global simulation timeout (program '%0s', mode '%0s')", cur_name, cur_mode_name);
        $fatal(1, "assembly_programs_tb: global timeout");
    end

endmodule
