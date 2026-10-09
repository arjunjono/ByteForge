// cpu_tb.v - self-checking integration testbench for the ByteForge CPU core
//
// The design under test is the real `cpu` wrapper: control_unit (with its
// instruction_decoder), register_file, flags_register and alu, all unmodified.
// ONLY the program memory and the data memory below are behavioural models.
//
// Expected outcomes are written out explicitly from the ByteForge
// specification; they are not derived from the DUT's FSM and there is no
// reference CPU in this file. Intermediate register writes, FLAGS writes,
// memory transactions, SP updates and program fetches are logged on the
// completion edge and compared one by one, so a later instruction cannot hide
// an earlier error.
//
// Program-memory layout used in all scenarios: word address N holds one 16-bit
// word. One-word instructions use one address; two-word instructions (LOAD,
// STORE, IN, OUT, JMP, JZ, JNZ) use the next address for the 16-bit operand.
// Comments next to each program give the word address of every instruction.
//
// Timing: clk period 10 ns (rising edges at 5, 15, 25 ... ns).
//  - Memory ready/data are driven on FALLING edges.
//  - Reset and other stimulus change 1 ns after a falling edge.
//  - Scoreboard/monitors sample on rising edges (they see pre-edge values).
//  - Final-state checks run at least 1 ns after a rising edge, or at falling edges.
`timescale 1ns/1ps

module cpu_tb;

    localparam [15:0] STACK_BOTTOM = 16'h0100;
    localparam [15:0] STACK_TOP    = 16'h0104;   // four stack bytes: 0x100..0x103
    localparam        LOGN         = 512;

    // Opcodes from the ByteForge specification
    localparam [4:0] OP_LOAD  = 5'b00000;
    localparam [4:0] OP_STORE = 5'b00001;
    localparam [4:0] OP_MOV   = 5'b00010;
    localparam [4:0] OP_LOADI = 5'b00011;
    localparam [4:0] OP_ADD   = 5'b00100;
    localparam [4:0] OP_SUB   = 5'b00101;
    localparam [4:0] OP_AND   = 5'b00110;
    localparam [4:0] OP_OR    = 5'b00111;
    localparam [4:0] OP_XOR   = 5'b01000;
    localparam [4:0] OP_CMP   = 5'b01001;
    localparam [4:0] OP_JMP   = 5'b01010;
    localparam [4:0] OP_JZ    = 5'b01011;
    localparam [4:0] OP_JNZ   = 5'b01100;
    localparam [4:0] OP_PUSH  = 5'b01101;
    localparam [4:0] OP_POP   = 5'b01110;
    localparam [4:0] OP_IN    = 5'b01111;
    localparam [4:0] OP_OUT   = 5'b10000;
    localparam [4:0] OP_HALT  = 5'b10001;

    // ------------------------------------------------------------------
    // Wrapper connections (the only things the CPU core sees)
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

    // Monitor taps: the actual write-enable / payload wires inside the wrapper
    wire        reg_write_enable   = dut.reg_write_enable;
    wire [1:0]  reg_write_addr     = dut.reg_write_addr;
    wire [7:0]  reg_write_data     = dut.reg_write_data;
    wire        flags_write_enable = dut.flags_write_enable;
    wire        flags_z_in         = dut.flags_z_in;
    wire        flags_c_in         = dut.flags_c_in;
    wire        flags_n_in         = dut.flags_n_in;

    // Read-only views of the real register storage and stored FLAGS
    wire [7:0]  rf [0:3];
    assign rf[0] = dut.u_registers.regs[0];
    assign rf[1] = dut.u_registers.regs[1];
    assign rf[2] = dut.u_registers.regs[2];
    assign rf[3] = dut.u_registers.regs[3];
    wire        f_z = Z;
    wire        f_c = C;
    wire        f_n = N;

    // Device under test: the real CPU core (small stack so boundaries are short)
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
    integer cyc;
    integer scen_count;
    integer cur_case;
    reg [8*40-1:0] cur_scen;

    // ------------------------------------------------------------------
    // Memory models (ready generated on falling edges)
    // ------------------------------------------------------------------
    reg [15:0] pmem [0:65535];
    reg [7:0]  dmem [0:65535];

    integer prog_delay_max, data_delay_max;     // extra wait cycles
    reg     prog_delay_rand, data_delay_rand;   // 1: random 0..max per transaction
    reg     ready_noise;                        // ready high while no request is active
    integer pseed, dseed;
    integer pw_goal, pw_cnt, dw_goal, dw_cnt;
    reg     pw_active, dw_active;

    always @(negedge clk) begin
        if (reset || !prog_request) begin
            // Idle, or reset: cancel any pending transaction.
            // Noise (ready high with no request) is only generated outside reset.
            prog_ready     <= ready_noise && !reset;
            prog_read_data <= (ready_noise && !reset) ? 16'h5A5A : 16'hxxxx;
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
            data_ready     <= ready_noise && !reset;
            data_read_data <= (ready_noise && !reset) ? 8'hA5 : 8'hxx;
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
    // Scoreboard and protocol monitors (sample on rising edges)
    // ------------------------------------------------------------------
    reg     mon_on;
    integer n_prog_txn, n_data_txn, n_data_rd, n_data_wr;
    integer n_reg_wr, n_flag_wr, n_sp_chg;
    integer last_ddone_cyc;

    reg [15:0] plog_addr  [0:LOGN-1];
    reg        dlog_wr    [0:LOGN-1];
    reg [15:0] dlog_addr  [0:LOGN-1];
    reg [7:0]  dlog_data  [0:LOGN-1];
    reg [1:0]  rwlog_addr [0:LOGN-1];
    reg [7:0]  rwlog_data [0:LOGN-1];
    reg        rwlog_dd   [0:LOGN-1];   // register write on the same edge as a data completion
    reg [2:0]  fwlog_zcn  [0:LOGN-1];
    reg        fwlog_rw   [0:LOGN-1];   // flags write on the same edge as a register write
    reg [15:0] splog_val  [0:LOGN-1];
    integer    splog_dc   [0:LOGN-1];   // data transactions completed when SP changed
    integer    splog_dly  [0:LOGN-1];   // edges between the data completion and the SP change

    reg        p_done, d_done;
    reg        prog_done_prev, data_done_prev;
    reg        prog_pend, data_pend;
    reg [15:0] prog_addr_s, data_addr_s;
    reg        data_we_s;
    reg [7:0]  data_wd_s;
    reg        reset_prev;
    reg [15:0] sp_last;

    task mfail;
        input [8*48-1:0] msg;
        begin
            failures = failures + 1;
            $display("FAIL @%0d ns [%0s #%0d] protocol: %0s | PC=0x%h SP=0x%h state=%0d",
                     $time, cur_scen, cur_case, msg, pc, sp, dut.u_control.state);
        end
    endtask

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (mon_on) begin
            checks = checks + 1;

            // SP change caused by the previous edge (ignore reset-caused changes)
            if (sp !== sp_last) begin
                if (!reset_prev) begin
                    if (n_sp_chg < LOGN) begin
                        splog_val[n_sp_chg] = sp;
                        splog_dc[n_sp_chg]  = n_data_txn;
                        splog_dly[n_sp_chg] = cyc - last_ddone_cyc;
                    end
                    n_sp_chg = n_sp_chg + 1;
                end
                sp_last = sp;
            end

            p_done = (prog_request === 1'b1) && (prog_ready === 1'b1) && !reset;
            d_done = (data_request === 1'b1) && (data_ready === 1'b1) && !reset;

            // Reset gating: nothing may be requested or written on a reset edge
            if (reset) begin
                if (prog_request !== 1'b0) mfail("prog_request not gated low during reset");
                if (data_request !== 1'b0) mfail("data_request not gated low during reset");
                if (reg_write_enable !== 1'b0) mfail("reg_write_enable not gated low during reset");
                if (flags_write_enable !== 1'b0) mfail("flags_write_enable not gated low during reset");
            end

            // data_write_enable only describes a requested transaction
            if (!reset && data_request === 1'b0 && data_write_enable !== 1'b0)
                mfail("data_write_enable high with no data request");

            // At least one low-request cycle after every completed transaction
            if (prog_request === 1'b1 && prog_done_prev)
                mfail("prog_request not low after a completed transaction");
            if (data_request === 1'b1 && data_done_prev)
                mfail("data_request not low after a completed transaction");

            // Program request: hold stable until completion
            if (prog_request === 1'b1) begin
                if (prog_pend) begin
                    if (prog_address !== prog_addr_s) mfail("prog_address changed while waiting");
                end else begin
                    prog_addr_s = prog_address;
                end
                prog_pend = !p_done;
            end else begin
                if (prog_pend && !reset) mfail("prog_request dropped before completion");
                prog_pend = 1'b0;
            end

            // Data request: hold address, direction and write data stable
            if (data_request === 1'b1) begin
                if (data_pend) begin
                    if (data_address !== data_addr_s)           mfail("data_address changed while waiting");
                    if (data_write_enable !== data_we_s)        mfail("data_write_enable changed while waiting");
                    if (data_we_s && (data_write_data !== data_wd_s))
                        mfail("data_write_data changed while waiting");
                end else begin
                    data_addr_s = data_address;
                    data_we_s   = data_write_enable;
                    data_wd_s   = data_write_data;
                end
                data_pend = !d_done;
            end else begin
                if (data_pend && !reset) mfail("data_request dropped before completion");
                data_pend = 1'b0;
            end

            // Completed program transaction
            if (p_done) begin
                if (n_prog_txn < LOGN) plog_addr[n_prog_txn] = prog_address;
                n_prog_txn = n_prog_txn + 1;
            end

            // Completed data transaction
            if (d_done) begin
                if (n_data_txn < LOGN) begin
                    dlog_wr[n_data_txn]   = data_write_enable;
                    dlog_addr[n_data_txn] = data_address;
                    dlog_data[n_data_txn] = (data_write_enable === 1'b1) ? data_write_data : data_read_data;
                end
                n_data_txn = n_data_txn + 1;
                if (data_write_enable === 1'b1) begin
                    n_data_wr = n_data_wr + 1;
                    dmem[data_address] <= data_write_data;     // the write happens exactly here
                end else begin
                    n_data_rd = n_data_rd + 1;
                end
                last_ddone_cyc = cyc;
            end

            // Register write
            if (reg_write_enable === 1'b1 && !reset) begin
                if (n_reg_wr < LOGN) begin
                    rwlog_addr[n_reg_wr] = reg_write_addr;
                    rwlog_data[n_reg_wr] = reg_write_data;
                    rwlog_dd[n_reg_wr]   = d_done;
                end
                n_reg_wr = n_reg_wr + 1;
            end

            // FLAGS write
            if (flags_write_enable === 1'b1 && !reset) begin
                if (n_flag_wr < LOGN) begin
                    fwlog_zcn[n_flag_wr] = {flags_z_in, flags_c_in, flags_n_in};
                    fwlog_rw[n_flag_wr]  = (reg_write_enable === 1'b1);
                end
                n_flag_wr = n_flag_wr + 1;
            end

            prog_done_prev = p_done;
            data_done_prev = d_done;
            reset_prev     = reset;
        end
    end

    // ------------------------------------------------------------------
    // Clocking monitor: all architectural state (R0-R3, Z/C/N, PC, SP, halted,
    // fault, FSM state) must change only right after a rising clock edge.
    // Sampling just before and just after each falling edge catches a module
    // that is clocked by the wrong edge or by an inverted clock.
    // ------------------------------------------------------------------
    reg [71:0] edge_s1, edge_s2;
    always @(posedge clk) begin
        #4;
        edge_s1 = {rf[0], rf[1], rf[2], rf[3], Z, C, N, pc, sp, halted, fault, dut.u_control.state};
        #2;
        edge_s2 = {rf[0], rf[1], rf[2], rf[3], Z, C, N, pc, sp, halted, fault, dut.u_control.state};
        if (mon_on) begin
            checks = checks + 1;
            if (edge_s1 !== edge_s2) mfail("state changed on a falling edge");
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
                $display("FAIL @%0d ns [%0s #%0d] %0s(#%0d): expected 0x%h, actual 0x%h | PC=0x%h SP=0x%h state=%0d",
                         $time, cur_scen, cur_case, what, idx, exp_v, act_v, pc, sp, dut.u_control.state);
            end
        end
    endtask

    // Expectation cursors into the logs
    integer ri, fi, di, pi_i, si;

    task x_rw_gen;
        input [1:0] a;
        input [7:0] d;
        input       dd;
        begin
            if (ri >= n_reg_wr || ri >= LOGN) begin
                checks = checks + 1;
                failures = failures + 1;
                $display("FAIL @%0d ns [%0s #%0d] missing register write #%0d: expected R%0d <= 0x%h",
                         $time, cur_scen, cur_case, ri, a, d);
            end else begin
                chk("register write address", ri, a,  rwlog_addr[ri]);
                chk("register write data",    ri, d,  rwlog_data[ri]);
                chk("write on data-completion edge", ri, dd, rwlog_dd[ri]);
            end
            ri = ri + 1;
        end
    endtask
    task x_rw;  input [1:0] a; input [7:0] d; begin x_rw_gen(a, d, 1'b0); end endtask
    task x_rwm; input [1:0] a; input [7:0] d; begin x_rw_gen(a, d, 1'b1); end endtask

    task x_fw;
        input z; input c; input n; input with_rw;
        begin
            if (fi >= n_flag_wr || fi >= LOGN) begin
                checks = checks + 1;
                failures = failures + 1;
                $display("FAIL @%0d ns [%0s #%0d] missing FLAGS write #%0d: expected ZCN=%b%b%b",
                         $time, cur_scen, cur_case, fi, z, c, n);
            end else begin
                chk("FLAGS written (Z,C,N)", fi, {z, c, n}, fwlog_zcn[fi]);
                chk("FLAGS write same edge as reg write", fi, with_rw, fwlog_rw[fi]);
            end
            fi = fi + 1;
        end
    endtask

    task x_d;
        input wr; input [15:0] a; input [7:0] d;
        begin
            if (di >= n_data_txn || di >= LOGN) begin
                checks = checks + 1;
                failures = failures + 1;
                $display("FAIL @%0d ns [%0s #%0d] missing data transaction #%0d: expected %0s addr 0x%h data 0x%h",
                         $time, cur_scen, cur_case, di, wr ? "write" : "read", a, d);
            end else begin
                chk("data transaction is a write", di, wr, dlog_wr[di]);
                chk("data transaction address",    di, a,  dlog_addr[di]);
                chk("data transaction data",       di, d,  dlog_data[di]);
            end
            di = di + 1;
        end
    endtask

    task x_pf;
        input [15:0] a;
        begin
            if (pi_i >= n_prog_txn || pi_i >= LOGN) begin
                checks = checks + 1;
                failures = failures + 1;
                $display("FAIL @%0d ns [%0s #%0d] missing program fetch #%0d: expected address 0x%h",
                         $time, cur_scen, cur_case, pi_i, a);
            end else begin
                chk("program fetch address", pi_i, a, plog_addr[pi_i]);
            end
            pi_i = pi_i + 1;
        end
    endtask

    // Total number of program words fetched (use when the addresses are not listed)
    task x_pf_count;
        input integer n;
        begin
            chk("program words fetched", -1, n, n_prog_txn);
            pi_i = n_prog_txn;
        end
    endtask

    task x_sp;
        input [15:0] v; input integer dc;
        begin
            if (si >= n_sp_chg || si >= LOGN) begin
                checks = checks + 1;
                failures = failures + 1;
                $display("FAIL @%0d ns [%0s #%0d] missing SP update #%0d: expected SP=0x%h",
                         $time, cur_scen, cur_case, si, v);
            end else begin
                chk("SP value",                      si, v,  splog_val[si]);
                chk("data txns done at SP update",   si, dc, splog_dc[si]);
                chk("SP updated at completion edge", si, 1,  splog_dly[si]);
            end
            si = si + 1;
        end
    endtask

    // Every logged event must have been accounted for (nothing extra happened)
    task x_done;
        begin
            chk("unexpected extra register writes", -1, n_reg_wr,   ri);
            chk("unexpected extra FLAGS writes",    -1, n_flag_wr,  fi);
            chk("unexpected extra data transactions", -1, n_data_txn, di);
            chk("unexpected extra program fetches", -1, n_prog_txn, pi_i);
            chk("unexpected extra SP updates",      -1, n_sp_chg,   si);
        end
    endtask

    task x_regs;
        input [7:0] r0; input [7:0] r1; input [7:0] r2; input [7:0] r3;
        begin
            chk("final R0", -1, r0, rf[0]);
            chk("final R1", -1, r1, rf[1]);
            chk("final R2", -1, r2, rf[2]);
            chk("final R3", -1, r3, rf[3]);
        end
    endtask

    task x_flags;
        input z; input c; input n;
        begin
            chk("final stored Z", -1, z, f_z);
            chk("final stored C", -1, c, f_c);
            chk("final stored N", -1, n, f_n);
        end
    endtask

    task x_pcsp;
        input [15:0] epc; input [15:0] esp;
        begin
            chk("final PC", -1, epc, pc);
            chk("final SP", -1, esp, sp);
        end
    endtask

    task x_status;
        input eh; input ef;
        begin
            chk("halted", -1, eh, halted);
            chk("fault",  -1, ef, fault);
        end
    endtask

    // ------------------------------------------------------------------
    // Scenario infrastructure
    // ------------------------------------------------------------------
    reg [15:0] pp;
    reg        stopped;
    reg        hit;

    task prog_begin;
        integer k;
        begin
            for (k = 0; k < 65536; k = k + 1) pmem[k] = 16'hFFFF;   // run-away code faults
            pp = 16'h0000;
        end
    endtask

    task dmem_clear;
        integer k;
        begin
            for (k = 0; k < 65536; k = k + 1) dmem[k] = 8'h00;
        end
    endtask

    task emit;
        input [15:0] w;
        begin
            pmem[pp] = w;
            pp = pp + 16'h0001;
        end
    endtask

    // Instruction builders (encodings from the ByteForge specification)
    task e_li;   input [1:0] a; input [7:0] imm;
        begin emit({OP_LOADI, a, imm, 1'b0}); end endtask
    task e_rr;   input [4:0] op; input [1:0] a; input [1:0] b;
        begin emit({op, a, b, 7'b0000000}); end endtask
    task e_r;    input [4:0] op; input [1:0] a;
        begin emit({op, a, 9'b000000000}); end endtask
    task e_ra;   input [4:0] op; input [1:0] a; input [15:0] addr;
        begin emit({op, a, 9'b000000000}); emit(addr); end endtask
    task e_j;    input [4:0] op; input [15:0] target;
        begin emit({op, 11'b00000000000}); emit(target); end endtask
    task e_halt;
        begin emit({OP_HALT, 11'b00000000000}); end endtask

    task set_delays;
        input integer pd; input integer dd; input pr; input dr;
        begin
            prog_delay_max  = pd;
            data_delay_max  = dd;
            prog_delay_rand = pr;
            data_delay_rand = dr;
        end
    endtask

    task clear_scoreboard;
        begin
            n_prog_txn = 0; n_data_txn = 0; n_data_rd = 0; n_data_wr = 0;
            n_reg_wr = 0; n_flag_wr = 0; n_sp_chg = 0;
            ri = 0; fi = 0; di = 0; pi_i = 0; si = 0;
            prog_done_prev = 1'b0; data_done_prev = 1'b0;
            prog_pend = 1'b0; data_pend = 1'b0;
            reset_prev = 1'b1;
            sp_last = sp;
            last_ddone_cyc = cyc;
            mon_on = 1'b1;
        end
    endtask

    // Assert reset for one edge (reset changes 1 ns after a falling edge), then
    // clear the scoreboard. Returns 1 ns after the next falling edge with reset still high.
    task do_reset_clear;
        begin
            @(negedge clk); #1;
            reset = 1'b1;
            @(posedge clk);
            @(negedge clk); #1;
            clear_scoreboard;
        end
    endtask

    task release_reset;     // one more reset edge, then release away from a rising edge
        begin
            @(posedge clk);
            @(negedge clk); #1;
            reset = 1'b0;
        end
    endtask

    task begin_scenario;
        input [8*40-1:0] name;
        begin
            cur_scen   = name;
            cur_case   = 0;
            scen_count = scen_count + 1;
            do_reset_clear;
            set_delays(0, 0, 1'b0, 1'b0);
            ready_noise = 1'b0;
        end
    endtask

    task run_until_stop;
        input integer max_cycles;
        integer c;
        begin
            stopped = 1'b0;
            c = 0;
            while (!stopped && c < max_cycles) begin
                @(negedge clk);
                c = c + 1;
                if (halted === 1'b1 || fault === 1'b1) stopped = 1'b1;
            end
            chk("stopped before timeout", -1, 1, stopped);
        end
    endtask

    // HALT / FAULT must stay stopped; ready is raised with no request active
    task hold_check;
        input integer n;
        reg [15:0] s_pc, s_sp;
        reg [7:0]  s_r0, s_r1, s_r2, s_r3;
        reg        s_z, s_c, s_n, s_h, s_f, s_noise;
        integer    s_p, s_d, s_rw, s_fw, s_sc, k;
        begin
            s_noise = ready_noise;
            ready_noise = 1'b1;
            @(negedge clk);
            s_pc = pc; s_sp = sp; s_h = halted; s_f = fault;
            s_r0 = rf[0]; s_r1 = rf[1]; s_r2 = rf[2]; s_r3 = rf[3];
            s_z = f_z; s_c = f_c; s_n = f_n;
            s_p = n_prog_txn; s_d = n_data_txn; s_rw = n_reg_wr; s_fw = n_flag_wr; s_sc = n_sp_chg;
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk);
                chk("stopped: prog_request low", k, 0, prog_request);
                chk("stopped: data_request low", k, 0, data_request);
                chk("stopped: reg_write_enable low", k, 0, reg_write_enable);
                chk("stopped: flags_write_enable low", k, 0, flags_write_enable);
            end
            chk("stopped: PC stable",     -1, s_pc, pc);
            chk("stopped: SP stable",     -1, s_sp, sp);
            chk("stopped: halted stable", -1, s_h, halted);
            chk("stopped: fault stable",  -1, s_f, fault);
            chk("stopped: R0 stable", -1, s_r0, rf[0]);
            chk("stopped: R1 stable", -1, s_r1, rf[1]);
            chk("stopped: R2 stable", -1, s_r2, rf[2]);
            chk("stopped: R3 stable", -1, s_r3, rf[3]);
            chk("stopped: Z stable", -1, s_z, f_z);
            chk("stopped: C stable", -1, s_c, f_c);
            chk("stopped: N stable", -1, s_n, f_n);
            chk("stopped: no program transaction", -1, s_p,  n_prog_txn);
            chk("stopped: no data transaction",    -1, s_d,  n_data_txn);
            chk("stopped: no register write",      -1, s_rw, n_reg_wr);
            chk("stopped: no FLAGS write",         -1, s_fw, n_flag_wr);
            chk("stopped: no SP update",           -1, s_sc, n_sp_chg);
            ready_noise = s_noise;
        end
    endtask

    task finish_run;
        input integer max_cycles;
        begin
            run_until_stop(max_cycles);
            hold_check(6);
        end
    endtask

    // Wait (bounded) for a cycle in which a completion WOULD happen at the next rising edge.
    // Returns 1 ns after a falling edge with request and ready both high.
    task wait_prog_completion;
        input        match_addr;
        input [15:0] want_addr;
        input integer max_cycles;
        integer c;
        begin
            hit = 1'b0;
            c = 0;
            while (!hit && c < max_cycles) begin
                @(negedge clk); #1;
                c = c + 1;
                if (prog_request === 1'b1 && prog_ready === 1'b1 &&
                    (!match_addr || prog_address === want_addr)) hit = 1'b1;
            end
            chk("found program completion edge", -1, 1, hit);
        end
    endtask

    task wait_data_completion;
        input        reads_only;
        input integer max_cycles;
        integer c;
        begin
            hit = 1'b0;
            c = 0;
            while (!hit && c < max_cycles) begin
                @(negedge clk); #1;
                c = c + 1;
                if (data_request === 1'b1 && data_ready === 1'b1 &&
                    (!reads_only || data_write_enable === 1'b0)) hit = 1'b1;
            end
            chk("found data completion edge", -1, 1, hit);
        end
    endtask

    // ==================================================================
    // SCENARIOS
    // ==================================================================

    // S1: synchronous reset, reset values, gating, restart mid-program
    task sc_reset;
        begin
            begin_scenario("S1 reset values, gating, restart");
            prog_begin;
            e_li(0, 8'h05); e_li(1, 8'h06); e_rr(OP_ADD, 0, 1); e_halt;
            // Reset is asserted now, DUT would otherwise be requesting a fetch
            chk("PC reset value",           -1, 16'h0000, pc);
            chk("SP reset value",           -1, STACK_TOP, sp);
            chk("halted cleared",           -1, 0, halted);
            chk("fault cleared",            -1, 0, fault);
            chk("prog_request gated in reset", -1, 0, prog_request);
            chk("data_request gated in reset", -1, 0, data_request);
            chk("reg_write_enable gated in reset", -1, 0, reg_write_enable);
            chk("flags_write_enable gated in reset", -1, 0, flags_write_enable);
            release_reset;
            repeat (8) @(negedge clk);              // partway through the program
            do_reset_clear;                          // synchronous reset in mid-program
            chk("PC after mid-program reset", -1, 16'h0000, pc);
            chk("SP after mid-program reset", -1, STACK_TOP, sp);
            x_status(0, 0);
            x_regs(0, 0, 0, 0);
            x_flags(0, 0, 0);
            release_reset;
            finish_run(200);
            x_status(1, 0);
            x_pcsp(16'h0004, STACK_TOP);
            x_regs(8'h0B, 8'h06, 8'h00, 8'h00);
            x_flags(0, 0, 0);
            x_rw(0, 8'h05); x_rw(1, 8'h06); x_rw(0, 8'h0B);
            x_fw(0, 0, 0, 1);
            x_pf(16'h0000); x_pf(16'h0001); x_pf(16'h0002); x_pf(16'h0003);
            x_done;
        end
    endtask

    // S2: LOADI and MOV, including writable R0; FLAGS untouched
    task sc_loadi_mov;
        begin
            begin_scenario("S2 LOADI/MOV incl. writable R0");
            prog_begin;
            e_li(0, 8'h11); e_li(1, 8'h22); e_li(2, 8'h80); e_li(3, 8'hFF);   // 0-3
            e_rr(OP_MOV, 0, 3);   // 4: R0 <= R3 (FF)
            e_rr(OP_MOV, 3, 1);   // 5: R3 <= R1 (22)
            e_rr(OP_MOV, 2, 0);   // 6: R2 <= R0 (FF)
            e_halt;               // 7
            release_reset;
            finish_run(200);
            x_status(1, 0);
            x_pcsp(16'h0008, STACK_TOP);
            x_regs(8'hFF, 8'h22, 8'hFF, 8'h22);
            x_flags(0, 0, 0);
            x_rw(0, 8'h11); x_rw(1, 8'h22); x_rw(2, 8'h80); x_rw(3, 8'hFF);
            x_rw(0, 8'hFF); x_rw(3, 8'h22); x_rw(2, 8'hFF);
            x_pf_count(8);
            x_done;                 // no FLAGS writes at all
        end
    endtask

    // S3: ADD, SUB, AND, OR, XOR with flag updates on the register-write edge
    task sc_alu;
        begin
            begin_scenario("S3 ALU instructions and flags");
            prog_begin;
            e_li(0, 8'h05); e_li(1, 8'h03); e_rr(OP_ADD, 0, 1);               // 0,1,2
            e_li(2, 8'hFF); e_li(3, 8'h01); e_rr(OP_ADD, 2, 3);               // 3,4,5
            e_li(0, 8'h7F); e_rr(OP_ADD, 0, 3);                               // 6,7
            e_rr(OP_SUB, 1, 3);                                               // 8
            e_li(1, 8'h03); e_li(3, 8'h05); e_rr(OP_SUB, 1, 3);               // 9,10,11
            e_li(0, 8'hAA); e_li(1, 8'h55); e_rr(OP_AND, 0, 1);               // 12,13,14
            e_li(0, 8'hAA); e_rr(OP_OR, 0, 1);                                // 15,16
            e_rr(OP_XOR, 0, 1);                                               // 17
            e_rr(OP_XOR, 1, 1);                                               // 18
            e_li(2, 8'hC8); e_li(3, 8'h64); e_rr(OP_ADD, 2, 3);               // 19,20,21
            e_halt;                                                           // 22
            release_reset;
            finish_run(400);
            x_status(1, 0);
            x_pcsp(16'h0017, STACK_TOP);
            x_regs(8'hAA, 8'h00, 8'h2C, 8'h64);
            x_flags(0, 1, 0);
            x_rw(0, 8'h05); x_rw(1, 8'h03);
            x_rw(0, 8'h08); x_fw(0, 0, 0, 1);      // 5+3
            x_rw(2, 8'hFF); x_rw(3, 8'h01);
            x_rw(2, 8'h00); x_fw(1, 1, 0, 1);      // FF+1: zero with carry
            x_rw(0, 8'h7F);
            x_rw(0, 8'h80); x_fw(0, 0, 1, 1);      // 7F+1: negative
            x_rw(1, 8'h02); x_fw(0, 0, 0, 1);      // 3-1
            x_rw(1, 8'h03); x_rw(3, 8'h05);
            x_rw(1, 8'hFE); x_fw(0, 1, 1, 1);      // 3-5: borrow
            x_rw(0, 8'hAA); x_rw(1, 8'h55);
            x_rw(0, 8'h00); x_fw(1, 0, 0, 1);      // AA & 55
            x_rw(0, 8'hAA);
            x_rw(0, 8'hFF); x_fw(0, 0, 1, 1);      // AA | 55
            x_rw(0, 8'hAA); x_fw(0, 0, 1, 1);      // FF ^ 55
            x_rw(1, 8'h00); x_fw(1, 0, 0, 1);      // 55 ^ 55
            x_rw(2, 8'hC8); x_rw(3, 8'h64);
            x_rw(2, 8'h2C); x_fw(0, 1, 0, 1);      // C8+64: carry, non-zero
            x_pf_count(23);
            x_done;
        end
    endtask

    // S4: CMP updates FLAGS only
    task sc_cmp;
        begin
            begin_scenario("S4 CMP flags only");
            prog_begin;
            e_li(0, 8'h05); e_li(1, 8'h05);          // 0,1
            e_rr(OP_CMP, 0, 1);                      // 2: 5-5
            e_li(2, 8'h03);                          // 3
            e_rr(OP_CMP, 2, 0);                      // 4: 3-5
            e_rr(OP_CMP, 0, 2);                      // 5: 5-3
            e_li(3, 8'h90); e_li(0, 8'h10);          // 6,7
            e_rr(OP_CMP, 3, 0);                      // 8: 90-10
            e_rr(OP_CMP, 0, 3);                      // 9: 10-90
            e_halt;                                  // 10
            release_reset;
            finish_run(200);
            x_status(1, 0);
            x_pcsp(16'h000B, STACK_TOP);
            x_regs(8'h10, 8'h05, 8'h03, 8'h90);
            x_flags(0, 1, 1);
            x_rw(0, 8'h05); x_rw(1, 8'h05);
            x_fw(1, 0, 0, 0);
            x_rw(2, 8'h03);
            x_fw(0, 1, 1, 0);
            x_fw(0, 0, 0, 0);
            x_rw(3, 8'h90); x_rw(0, 8'h10);
            x_fw(0, 0, 1, 0);
            x_fw(0, 1, 1, 0);
            x_pf_count(11);
            x_done;                  // CMP never wrote a register
        end
    endtask

    // S5: FLAGS preserved by MOV/LOADI/memory/stack/jumps; stress with ready noise
    task sc_preserve;
        begin
            begin_scenario("S5 FLAGS preserved, mixed instructions");
            prog_begin; dmem_clear;
            e_li(0, 8'h80); e_li(1, 8'h80); e_rr(OP_ADD, 0, 1);     // 0,1,2: R0=00, flags 1,1,0
            e_rr(OP_MOV, 2, 0);                                     // 3
            e_li(3, 8'h42);                                         // 4
            e_ra(OP_STORE, 3, 16'h0030);                            // 5,6
            e_ra(OP_LOAD,  1, 16'h0030);                            // 7,8
            e_ra(OP_IN,    2, 16'h0050);                            // 9,10
            e_ra(OP_OUT,   2, 16'h0040);                            // 11,12
            e_r(OP_PUSH, 1);                                        // 13
            e_r(OP_POP,  0);                                        // 14
            e_j(OP_JMP, 16'h0013);                                  // 15,16 -> 19
            e_li(0, 8'hEE); e_halt;                                 // 17,18 (skipped)
            e_j(OP_JZ, 16'h0016);                                   // 19,20 taken (Z=1) -> 22
            e_li(0, 8'hDD);                                         // 21 (skipped)
            e_j(OP_JNZ, 16'h0100);                                  // 22,23 not taken
            e_halt;                                                 // 24
            dmem[16'h0050] = 8'h5B;
            ready_noise = 1'b1;
            release_reset;
            finish_run(300);
            x_status(1, 0);
            x_pcsp(16'h0019, STACK_TOP);
            x_regs(8'h42, 8'h42, 8'h5B, 8'h42);
            x_flags(1, 1, 0);
            x_rw(0, 8'h80); x_rw(1, 8'h80);
            x_rw(0, 8'h00); x_fw(1, 1, 0, 1);
            x_rw(2, 8'h00);
            x_rw(3, 8'h42);
            x_d(1, 16'h0030, 8'h42);
            x_d(0, 16'h0030, 8'h42); x_rwm(1, 8'h42);
            x_d(0, 16'h0050, 8'h5B); x_rwm(2, 8'h5B);
            x_d(1, 16'h0040, 8'h5B);
            x_d(1, 16'h0103, 8'h42); x_sp(16'h0103, 5);
            x_d(0, 16'h0103, 8'h42); x_rwm(0, 8'h42); x_sp(16'h0104, 6);
            x_pf(16'h0000); x_pf(16'h0001); x_pf(16'h0002); x_pf(16'h0003);
            x_pf(16'h0004); x_pf(16'h0005); x_pf(16'h0006); x_pf(16'h0007);
            x_pf(16'h0008); x_pf(16'h0009); x_pf(16'h000A); x_pf(16'h000B);
            x_pf(16'h000C); x_pf(16'h000D); x_pf(16'h000E); x_pf(16'h000F);
            x_pf(16'h0010); x_pf(16'h0013); x_pf(16'h0014); x_pf(16'h0016);
            x_pf(16'h0017); x_pf(16'h0018);
            x_done;                  // exactly one FLAGS write in the whole program
            chk("dmem[0030]", -1, 8'h42, dmem[16'h0030]);
            chk("dmem[0040]", -1, 8'h5B, dmem[16'h0040]);
            chk("dmem[0103]", -1, 8'h42, dmem[16'h0103]);
        end
    endtask

    // S6: LOAD/STORE/IN/OUT with 16-bit second-word addresses; sequential PC progression
    task sc_memory;
        integer k;
        begin
            begin_scenario("S6 LOAD/STORE/IN/OUT addresses");
            prog_begin; dmem_clear;
            e_li(0, 8'hA1); e_li(1, 8'hB2); e_li(2, 8'hC3); e_li(3, 8'hD4);   // 0-3
            e_ra(OP_STORE, 0, 16'h1234);                                       // 4,5
            e_ra(OP_STORE, 1, 16'hFFFF);                                       // 6,7
            e_ra(OP_OUT,   2, 16'h8001);                                       // 8,9
            e_ra(OP_OUT,   3, 16'h0000);                                       // 10,11
            e_li(0, 8'h00); e_li(1, 8'h00); e_li(2, 8'h00); e_li(3, 8'h00);   // 12-15
            e_ra(OP_LOAD, 3, 16'h1234);                                        // 16,17
            e_ra(OP_LOAD, 2, 16'hFFFF);                                        // 18,19
            e_ra(OP_IN,   1, 16'h8001);                                        // 20,21
            e_ra(OP_IN,   0, 16'h0000);                                        // 22,23
            e_halt;                                                            // 24
            ready_noise = 1'b1;
            release_reset;
            finish_run(300);
            x_status(1, 0);
            x_pcsp(16'h0019, STACK_TOP);
            x_regs(8'hD4, 8'hC3, 8'hB2, 8'hA1);
            x_flags(0, 0, 0);
            x_rw(0, 8'hA1); x_rw(1, 8'hB2); x_rw(2, 8'hC3); x_rw(3, 8'hD4);
            x_d(1, 16'h1234, 8'hA1);
            x_d(1, 16'hFFFF, 8'hB2);
            x_d(1, 16'h8001, 8'hC3);
            x_d(1, 16'h0000, 8'hD4);
            x_rw(0, 8'h00); x_rw(1, 8'h00); x_rw(2, 8'h00); x_rw(3, 8'h00);
            x_d(0, 16'h1234, 8'hA1); x_rwm(3, 8'hA1);
            x_d(0, 16'hFFFF, 8'hB2); x_rwm(2, 8'hB2);
            x_d(0, 16'h8001, 8'hC3); x_rwm(1, 8'hC3);
            x_d(0, 16'h0000, 8'hD4); x_rwm(0, 8'hD4);
            // Sequential PC: one-word and two-word instructions fetch 0,1,2,...,24
            for (k = 0; k < 25; k = k + 1) x_pf(k);
            x_done;
            chk("dmem[1234]", -1, 8'hA1, dmem[16'h1234]);
            chk("dmem[FFFF]", -1, 8'hB2, dmem[16'hFFFF]);
            chk("dmem[8001]", -1, 8'hC3, dmem[16'h8001]);
            chk("dmem[0000]", -1, 8'hD4, dmem[16'h0000]);
        end
    endtask

    // S8: JMP, JZ taken / not taken, JNZ taken / not taken
    task sc_jumps;
        begin
            begin_scenario("S8 jumps taken and not taken");
            prog_begin;
            e_li(0, 8'h05); e_li(1, 8'h05);          // 0,1
            e_rr(OP_CMP, 0, 1);                      // 2: Z=1
            e_j(OP_JZ, 16'h0008);                    // 3,4 taken
            e_li(3, 8'hE1); e_halt; e_halt;          // 5,6,7 skipped
            e_j(OP_JNZ, 16'h0030);                   // 8,9 not taken (Z=1)
            e_li(2, 8'h11);                          // 10
            e_rr(OP_CMP, 0, 2);                      // 11: 05-11, Z=0
            e_j(OP_JZ, 16'h0030);                    // 12,13 not taken (Z=0)
            e_li(2, 8'h22);                          // 14
            e_j(OP_JNZ, 16'h0013);                   // 15,16 taken
            e_li(3, 8'hE2); e_halt;                  // 17,18 skipped
            e_li(2, 8'h33);                          // 19
            e_j(OP_JMP, 16'h0018);                   // 20,21 unconditional
            e_li(3, 8'hE3); e_halt;                  // 22,23 skipped
            e_halt;                                  // 24
            release_reset;
            finish_run(300);
            x_status(1, 0);
            x_pcsp(16'h0019, STACK_TOP);
            x_regs(8'h05, 8'h05, 8'h33, 8'h00);
            x_flags(0, 1, 1);
            x_rw(0, 8'h05); x_rw(1, 8'h05);
            x_fw(1, 0, 0, 0);
            x_rw(2, 8'h11);
            x_fw(0, 1, 1, 0);
            x_rw(2, 8'h22);
            x_rw(2, 8'h33);
            x_pf(16'h0000); x_pf(16'h0001); x_pf(16'h0002); x_pf(16'h0003);
            x_pf(16'h0004); x_pf(16'h0008); x_pf(16'h0009); x_pf(16'h000A);
            x_pf(16'h000B); x_pf(16'h000C); x_pf(16'h000D); x_pf(16'h000E);
            x_pf(16'h000F); x_pf(16'h0010); x_pf(16'h0013); x_pf(16'h0014);
            x_pf(16'h0015); x_pf(16'h0018);
            x_done;
        end
    endtask

    // Shared stack prefix: LOADI R0..R3 = 71..74, then PUSH R0..R3
    task stack_prefix;
        begin
            e_li(0, 8'h71); e_li(1, 8'h72); e_li(2, 8'h73); e_li(3, 8'h74);   // 0-3
            e_r(OP_PUSH, 0); e_r(OP_PUSH, 1); e_r(OP_PUSH, 2); e_r(OP_PUSH, 3); // 4-7
        end
    endtask

    task x_stack_prefix;
        begin
            x_rw(0, 8'h71); x_rw(1, 8'h72); x_rw(2, 8'h73); x_rw(3, 8'h74);
            x_d(1, 16'h0103, 8'h71); x_sp(16'h0103, 1);
            x_d(1, 16'h0102, 8'h72); x_sp(16'h0102, 2);
            x_d(1, 16'h0101, 8'h73); x_sp(16'h0101, 3);
            x_d(1, 16'h0100, 8'h74); x_sp(16'h0100, 4);
        end
    endtask

    // S9: PUSH/POP LIFO behaviour and SP changes
    task sc_lifo;
        begin
            begin_scenario("S9 PUSH/POP LIFO and SP");
            prog_begin; dmem_clear;
            e_li(0, 8'h11); e_li(1, 8'h22);          // 0,1
            e_r(OP_PUSH, 0); e_r(OP_PUSH, 1);        // 2,3
            e_r(OP_POP, 2);  e_r(OP_POP, 3);         // 4,5
            e_halt;                                  // 6
            release_reset;
            finish_run(200);
            x_status(1, 0);
            x_pcsp(16'h0007, STACK_TOP);
            x_regs(8'h11, 8'h22, 8'h22, 8'h11);
            x_flags(0, 0, 0);
            x_rw(0, 8'h11); x_rw(1, 8'h22);
            x_d(1, 16'h0103, 8'h11); x_sp(16'h0103, 1);
            x_d(1, 16'h0102, 8'h22); x_sp(16'h0102, 2);
            x_d(0, 16'h0102, 8'h22); x_rwm(2, 8'h22); x_sp(16'h0103, 3);
            x_d(0, 16'h0103, 8'h11); x_rwm(3, 8'h11); x_sp(16'h0104, 4);
            x_pf_count(7);
            x_done;
        end
    endtask

    // S10: fill all four stack bytes
    task sc_stack_fill;
        begin
            begin_scenario("S10 fill all four stack bytes");
            prog_begin; dmem_clear;
            stack_prefix;
            e_halt;                                  // 8
            release_reset;
            finish_run(300);
            x_status(1, 0);
            x_pcsp(16'h0009, 16'h0100);
            x_regs(8'h71, 8'h72, 8'h73, 8'h74);
            x_stack_prefix;
            x_pf_count(9);
            x_done;
            chk("dmem[0103]", -1, 8'h71, dmem[16'h0103]);
            chk("dmem[0102]", -1, 8'h72, dmem[16'h0102]);
            chk("dmem[0101]", -1, 8'h73, dmem[16'h0101]);
            chk("dmem[0100]", -1, 8'h74, dmem[16'h0100]);
        end
    endtask

    // S11: a fifth PUSH faults with no extra write and no SP change
    task sc_push_overflow;
        begin
            begin_scenario("S11 fifth PUSH faults");
            prog_begin; dmem_clear;
            stack_prefix;
            e_r(OP_PUSH, 0);                         // 8: stack is full
            e_halt;                                  // 9 (never reached)
            release_reset;
            finish_run(300);
            x_status(0, 1);
            x_pcsp(16'h0009, 16'h0100);
            x_regs(8'h71, 8'h72, 8'h73, 8'h74);
            x_stack_prefix;
            x_pf_count(9);
            x_done;                                  // exactly 4 writes, 4 SP updates
            chk("data writes", -1, 4, n_data_wr);
            chk("data reads",  -1, 0, n_data_rd);
        end
    endtask

    // S12: POP all four bytes; S13: a further POP faults
    task sc_pop_all;
        input fault_after;
        begin
            if (fault_after) begin_scenario("S13 POP on empty stack faults");
            else             begin_scenario("S12 POP all four stack bytes");
            prog_begin; dmem_clear;
            stack_prefix;
            e_r(OP_POP, 0); e_r(OP_POP, 1); e_r(OP_POP, 2); e_r(OP_POP, 3);   // 8-11
            if (fault_after) e_r(OP_POP, 1);                                  // 12: empty
            e_halt;
            release_reset;
            finish_run(400);
            if (fault_after) begin
                x_status(0, 1);
                x_pcsp(16'h000D, STACK_TOP);
                x_pf_count(13);
            end else begin
                x_status(1, 0);
                x_pcsp(16'h000D, STACK_TOP);
                x_pf_count(13);
            end
            x_regs(8'h74, 8'h73, 8'h72, 8'h71);
            x_flags(0, 0, 0);
            x_stack_prefix;
            x_d(0, 16'h0100, 8'h74); x_rwm(0, 8'h74); x_sp(16'h0101, 5);
            x_d(0, 16'h0101, 8'h73); x_rwm(1, 8'h73); x_sp(16'h0102, 6);
            x_d(0, 16'h0102, 8'h72); x_rwm(2, 8'h72); x_sp(16'h0103, 7);
            x_d(0, 16'h0103, 8'h71); x_rwm(3, 8'h71); x_sp(16'h0104, 8);
            x_done;
            chk("data reads",  -1, 4, n_data_rd);
            chk("data writes", -1, 4, n_data_wr);
        end
    endtask

    // S14: unsupported opcodes fault with no side effects and no second-word fetch
    task sc_unsupported;
        integer k;
        reg [4:0]  opx;
        reg [10:0] low;
        begin
            for (k = 18; k < 32; k = k + 1) begin
                opx = k;
                low = ((k % 2) == 0) ? 11'h000 : 11'h5A5;
                begin_scenario("S14 unsupported opcode faults");
                cur_case = k;
                prog_begin;
                e_li(0, 8'h5A);                      // 0
                emit({opx, low});                    // 1: unsupported
                e_halt;                              // 2 (never reached)
                release_reset;
                finish_run(80);
                x_status(0, 1);
                x_pcsp(16'h0002, STACK_TOP);
                x_regs(8'h5A, 8'h00, 8'h00, 8'h00);
                x_rw(0, 8'h5A);
                x_pf_count(2);
                x_done;
                chk("no data transaction", -1, 0, n_data_txn);
                chk("no FLAGS write",      -1, 0, n_flag_wr);
            end
        end
    endtask

    // S15 / S16: nonzero reserved bits fault in every instruction format
    reg [15:0] bad_tab [0:63];
    integer    bad_n;
    task add_bad;
        input [15:0] w;
        begin
            bad_tab[bad_n] = w;
            bad_n = bad_n + 1;
        end
    endtask

    task fill_bad_table;
        begin
            bad_n = 0;
            // Two-register formats (reserved [6:0])
            add_bad({OP_MOV,  2'd0, 2'd1, 7'b0000010});
            add_bad({OP_MOV,  2'd3, 2'd3, 7'b1111111});
            add_bad({OP_ADD,  2'd1, 2'd2, 7'b0000001});
            add_bad({OP_SUB,  2'd2, 2'd0, 7'b1000000});
            add_bad({OP_AND,  2'd3, 2'd1, 7'b0001000});
            add_bad({OP_OR,   2'd0, 2'd2, 7'b1000001});
            add_bad({OP_XOR,  2'd1, 2'd3, 7'b0000100});
            add_bad({OP_CMP,  2'd2, 2'd2, 7'b0100000});
            // LOADI (reserved [0])
            add_bad({OP_LOADI, 2'd2, 8'hFF, 1'b1});
            add_bad({OP_LOADI, 2'd0, 8'h00, 1'b1});
            // Single-register formats (reserved [8:0]); LOAD/STORE/IN/OUT are two-word formats
            add_bad({OP_LOAD,  2'd1, 9'b100000000});
            add_bad({OP_LOAD,  2'd2, 9'b000000001});
            add_bad({OP_STORE, 2'd3, 9'b000010000});
            add_bad({OP_IN,    2'd0, 9'b010000000});
            add_bad({OP_OUT,   2'd1, 9'b000000010});
            add_bad({OP_PUSH,  2'd2, 9'b000000001});
            add_bad({OP_PUSH,  2'd3, 9'b100000000});
            add_bad({OP_POP,   2'd0, 9'b000100000});
            add_bad({OP_POP,   2'd1, 9'b111111111});
            // Address-only formats (reserved [10:0]); two-word formats
            add_bad({OP_JMP,  11'b10000000000});
            add_bad({OP_JMP,  11'b00000000001});
            add_bad({OP_JZ,   11'b00000100000});
            add_bad({OP_JNZ,  11'b01000000000});
            add_bad({OP_JNZ,  11'b11111111111});
            // HALT (reserved [10:0])
            add_bad({OP_HALT, 11'b10000000000});
            add_bad({OP_HALT, 11'b00000000001});
            add_bad({OP_HALT, 11'b00010010000});
        end
    endtask

    task sc_reserved;
        integer k;
        begin
            fill_bad_table;
            for (k = 0; k < bad_n; k = k + 1) begin
                begin_scenario("S15 reserved bits fault");
                cur_case = k;
                prog_begin;
                e_li(0, 8'h5A);                      // 0
                emit(bad_tab[k]);                    // 1: malformed
                emit(16'h0040);                      // 2: would be a second word if (wrongly) fetched
                e_halt;                              // 3 (never reached)
                release_reset;
                finish_run(80);
                x_status(0, 1);
                x_pcsp(16'h0002, STACK_TOP);
                x_regs(8'h5A, 8'h00, 8'h00, 8'h00);
                x_rw(0, 8'h5A);
                x_pf_count(2);                       // S16: no second-word fetch
                x_done;
                chk("no data transaction", -1, 0, n_data_txn);
                chk("no FLAGS write",      -1, 0, n_flag_wr);
            end
        end
    endtask

    // S19: reset exits HALT and fault
    task sc_reset_exit;
        input from_fault;
        begin
            if (from_fault) begin_scenario("S19b reset exits fault");
            else            begin_scenario("S19a reset exits HALT");
            prog_begin;
            e_li(0, 8'h01);
            if (from_fault) emit({5'b10010, 11'h000}); else e_halt;
            release_reset;
            finish_run(60);
            x_status(from_fault ? 1'b0 : 1'b1, from_fault ? 1'b1 : 1'b0);
            x_pcsp(16'h0002, STACK_TOP);
            prog_begin;                               // a different program after reset
            e_li(1, 8'h02); e_halt;
            do_reset_clear;
            x_status(0, 0);
            x_pcsp(16'h0000, STACK_TOP);
            release_reset;
            finish_run(60);
            x_status(1, 0);
            x_pcsp(16'h0002, STACK_TOP);
            x_regs(8'h00, 8'h02, 8'h00, 8'h00);
            x_rw(1, 8'h02);
            x_pf(16'h0000); x_pf(16'h0001);
            x_done;
        end
    endtask

    // S20-S23, S26: complete short program under different wait configurations
    task sc_full;
        input integer pd;
        input integer dd;
        input         pr;
        input         dr;
        input         noise;
        input integer cs;
        begin
            begin_scenario("S26 full program under waits");
            cur_case = cs;
            prog_begin; dmem_clear;
            e_li(0, 8'h00); e_li(1, 8'h04); e_li(2, 8'h01);        // 0,1,2
            e_rr(OP_ADD, 0, 1);                                     // 3: loop
            e_rr(OP_SUB, 1, 2);                                     // 4
            e_j(OP_JNZ, 16'h0003);                                  // 5,6
            e_ra(OP_STORE, 0, 16'h0200);                            // 7,8
            e_r(OP_PUSH, 0);                                        // 9
            e_ra(OP_LOAD, 3, 16'h0200);                             // 10,11
            e_rr(OP_CMP, 3, 0);                                     // 12
            e_j(OP_JZ, 16'h0011);                                   // 13,14 taken
            e_li(3, 8'hEE); e_halt;                                 // 15,16 skipped
            e_r(OP_POP, 1);                                         // 17
            e_ra(OP_OUT, 1, 16'h0210);                              // 18,19
            e_halt;                                                 // 20
            set_delays(pd, dd, pr, dr);
            ready_noise = noise;
            release_reset;
            finish_run(8000);
            x_status(1, 0);
            x_pcsp(16'h0015, STACK_TOP);
            x_regs(8'h0A, 8'h0A, 8'h01, 8'h0A);
            x_flags(1, 0, 0);
            x_rw(0, 8'h00); x_rw(1, 8'h04); x_rw(2, 8'h01);
            x_rw(0, 8'h04); x_fw(0, 0, 0, 1); x_rw(1, 8'h03); x_fw(0, 0, 0, 1);
            x_rw(0, 8'h07); x_fw(0, 0, 0, 1); x_rw(1, 8'h02); x_fw(0, 0, 0, 1);
            x_rw(0, 8'h09); x_fw(0, 0, 0, 1); x_rw(1, 8'h01); x_fw(0, 0, 0, 1);
            x_rw(0, 8'h0A); x_fw(0, 0, 0, 1); x_rw(1, 8'h00); x_fw(1, 0, 0, 1);
            x_d(1, 16'h0200, 8'h0A);
            x_d(1, 16'h0103, 8'h0A); x_sp(16'h0103, 2);
            x_d(0, 16'h0200, 8'h0A); x_rwm(3, 8'h0A);
            x_fw(1, 0, 0, 0);
            x_d(0, 16'h0103, 8'h0A); x_rwm(1, 8'h0A); x_sp(16'h0104, 4);
            x_d(1, 16'h0210, 8'h0A);
            // Fetch order: 0,1,2, four loop passes of 3,4,5,6, then the rest
            x_pf(16'h0000); x_pf(16'h0001); x_pf(16'h0002);
            x_pf(16'h0003); x_pf(16'h0004); x_pf(16'h0005); x_pf(16'h0006);
            x_pf(16'h0003); x_pf(16'h0004); x_pf(16'h0005); x_pf(16'h0006);
            x_pf(16'h0003); x_pf(16'h0004); x_pf(16'h0005); x_pf(16'h0006);
            x_pf(16'h0003); x_pf(16'h0004); x_pf(16'h0005); x_pf(16'h0006);
            x_pf(16'h0007); x_pf(16'h0008); x_pf(16'h0009); x_pf(16'h000A);
            x_pf(16'h000B); x_pf(16'h000C); x_pf(16'h000D); x_pf(16'h000E);
            x_pf(16'h0011); x_pf(16'h0012); x_pf(16'h0013); x_pf(16'h0014);
            x_done;
            chk("dmem[0200]", -1, 8'h0A, dmem[16'h0200]);
            chk("dmem[0210]", -1, 8'h0A, dmem[16'h0210]);
            chk("dmem[0103]", -1, 8'h0A, dmem[16'h0103]);
            chk("data reads",  -1, 2, n_data_rd);
            chk("data writes", -1, 3, n_data_wr);
            if (cs == 1) begin
                $display("---- Mixed program summary (zero-wait run) ----");
                $display("  R0 R1 R2 R3 expected 0a 0a 01 0a | actual %h %h %h %h", rf[0], rf[1], rf[2], rf[3]);
                $display("  Z C N       expected 1 0 0      | actual %b %b %b", Z, C, N);
                $display("  PC          expected 0015       | actual %h", pc);
                $display("  SP          expected 0104       | actual %h", sp);
                $display("  halted/fault expected 1 0       | actual %b %b", halted, fault);
                $display("  mem[0200]   expected 0a         | actual %h", dmem[16'h0200]);
                $display("  mem[0210]   expected 0a         | actual %h", dmem[16'h0210]);
                $display("  mem[0103]   expected 0a         | actual %h", dmem[16'h0103]);
            end
        end
    endtask

    // S24: reset during program-memory waits
    task sc_reset_prog;
        input integer v;
        integer nb;
        begin
            if (v == 0) begin
                begin_scenario("S24a reset during program wait");
                prog_begin; e_li(0, 8'h5C); e_halt;
                set_delays(30, 0, 1'b0, 1'b0);
                release_reset;
                repeat (10) @(negedge clk);
                #1;
                chk("waiting: prog_request high", -1, 1, prog_request);
                chk("waiting: prog_ready low",    -1, 0, prog_ready);
                @(negedge clk); #1;
                reset = 1'b1;                           // reset between rising edges
                #1;
                chk("prog_request cancelled by reset", -1, 0, prog_request);
                @(posedge clk);
                @(negedge clk); #1;
                chk("no fetch completed", -1, 0, n_prog_txn);
                x_pcsp(16'h0000, STACK_TOP);
                x_status(0, 0);
                set_delays(0, 0, 1'b0, 1'b0);
                release_reset;
                finish_run(100);
                x_status(1, 0);
                x_pcsp(16'h0002, STACK_TOP);
                x_regs(8'h5C, 8'h00, 8'h00, 8'h00);
                x_rw(0, 8'h5C);
                x_pf(16'h0000); x_pf(16'h0001);
                x_done;
            end else if (v == 1) begin
                begin_scenario("S24b reset on first-fetch completion");
                prog_begin; e_li(0, 8'h5C); e_halt;
                set_delays(3, 0, 1'b0, 1'b0);
                release_reset;
                wait_prog_completion(1'b0, 16'h0000, 40);
                nb = n_prog_txn;
                reset = 1'b1;                           // reset wins on the completion edge
                @(posedge clk);
                @(negedge clk); #1;
                chk("reset edge completed no fetch", -1, nb, n_prog_txn);
                x_pcsp(16'h0000, STACK_TOP);
                x_status(0, 0);
                set_delays(0, 0, 1'b0, 1'b0);
                release_reset;
                finish_run(100);
                x_status(1, 0);
                x_pcsp(16'h0002, STACK_TOP);
                x_regs(8'h5C, 8'h00, 8'h00, 8'h00);
                x_rw(0, 8'h5C);
                x_pf(16'h0000); x_pf(16'h0001);
                x_done;
            end else begin
                begin_scenario("S24c reset on second-word completion");
                prog_begin; dmem_clear;
                e_ra(OP_LOAD, 0, 16'h0020); e_halt;
                dmem[16'h0020] = 8'h7E;
                set_delays(3, 0, 1'b0, 1'b0);
                release_reset;
                wait_prog_completion(1'b1, 16'h0001, 60);
                nb = n_prog_txn;
                reset = 1'b1;
                @(posedge clk);
                @(negedge clk); #1;
                chk("reset edge completed no fetch", -1, nb, n_prog_txn);
                x_pcsp(16'h0000, STACK_TOP);
                x_status(0, 0);
                set_delays(0, 0, 1'b0, 1'b0);
                release_reset;
                finish_run(100);
                x_status(1, 0);
                x_pcsp(16'h0003, STACK_TOP);
                x_regs(8'h7E, 8'h00, 8'h00, 8'h00);
                x_pf(16'h0000);                          // first run (before reset)
                x_pf(16'h0000); x_pf(16'h0001); x_pf(16'h0002);   // restart from address 0
                x_d(0, 16'h0020, 8'h7E); x_rwm(0, 8'h7E);
                x_done;
            end
        end
    endtask

    // S25: reset during pending data transactions
    task sc_reset_data;
        input integer v;
        integer c;
        begin
            case (v)
                0: begin   // STORE: reset wins on the write-completion edge
                    begin_scenario("S25a reset on STORE completion");
                    prog_begin; dmem_clear;
                    e_li(0, 8'h9C); e_ra(OP_STORE, 0, 16'h0020); e_halt;
                    set_delays(0, 3, 1'b0, 1'b0);
                    release_reset;
                    wait_data_completion(1'b0, 60);
                    reset = 1'b1;
                    @(posedge clk);
                    @(negedge clk); #1;
                    chk("write not committed by reset edge", -1, 8'h00, dmem[16'h0020]);
                    chk("no data transaction counted", -1, 0, n_data_txn);
                    chk("no data write counted",       -1, 0, n_data_wr);
                    x_pcsp(16'h0000, STACK_TOP);
                    set_delays(0, 0, 1'b0, 1'b0);
                    release_reset;
                    finish_run(200);
                    x_status(1, 0);
                    x_pcsp(16'h0004, STACK_TOP);
                    x_regs(8'h9C, 8'h00, 8'h00, 8'h00);
                    x_rw(0, 8'h9C); x_rw(0, 8'h9C);
                    x_d(1, 16'h0020, 8'h9C);
                    x_pf_count(7);
                    x_done;
                    chk("dmem[0020] written once", -1, 8'h9C, dmem[16'h0020]);
                    chk("data writes", -1, 1, n_data_wr);
                end
                1: begin   // LOAD: reset wins, no register write
                    begin_scenario("S25b reset on LOAD completion");
                    prog_begin; dmem_clear;
                    e_li(0, 8'h01); e_ra(OP_LOAD, 1, 16'h0020); e_halt;
                    dmem[16'h0020] = 8'h7E;
                    set_delays(0, 3, 1'b0, 1'b0);
                    release_reset;
                    wait_data_completion(1'b1, 60);
                    reset = 1'b1;
                    @(posedge clk);
                    @(negedge clk); #1;
                    chk("only the LOADI wrote a register", -1, 1, n_reg_wr);
                    chk("no data transaction counted",     -1, 0, n_data_txn);
                    set_delays(0, 0, 1'b0, 1'b0);
                    release_reset;
                    finish_run(200);
                    x_status(1, 0);
                    x_pcsp(16'h0004, STACK_TOP);
                    x_regs(8'h01, 8'h7E, 8'h00, 8'h00);
                    x_rw(0, 8'h01); x_rw(0, 8'h01);
                    x_d(0, 16'h0020, 8'h7E); x_rwm(1, 8'h7E);
                    x_pf_count(7);
                    x_done;
                end
                2: begin   // PUSH: reset wins, no memory write and no SP update
                    begin_scenario("S25c reset on PUSH completion");
                    prog_begin; dmem_clear;
                    e_li(0, 8'hA7); e_r(OP_PUSH, 0); e_halt;
                    set_delays(0, 3, 1'b0, 1'b0);
                    release_reset;
                    wait_data_completion(1'b0, 60);
                    reset = 1'b1;
                    @(posedge clk);
                    @(negedge clk); #1;
                    chk("push write not committed", -1, 8'h00, dmem[16'h0103]);
                    chk("no data transaction counted", -1, 0, n_data_txn);
                    chk("no SP update counted",        -1, 0, n_sp_chg);
                    x_pcsp(16'h0000, STACK_TOP);
                    set_delays(0, 0, 1'b0, 1'b0);
                    release_reset;
                    finish_run(200);
                    x_status(1, 0);
                    x_pcsp(16'h0003, 16'h0103);
                    x_regs(8'hA7, 8'h00, 8'h00, 8'h00);
                    x_rw(0, 8'hA7); x_rw(0, 8'hA7);
                    x_d(1, 16'h0103, 8'hA7); x_sp(16'h0103, 1);
                    x_pf_count(5);
                    x_done;
                    chk("dmem[0103] written once", -1, 8'hA7, dmem[16'h0103]);
                end
                3: begin   // POP: reset wins on the read-completion edge
                    begin_scenario("S25d reset on POP completion");
                    prog_begin; dmem_clear;
                    e_li(0, 8'hB8); e_r(OP_PUSH, 0); e_r(OP_POP, 1); e_halt;
                    set_delays(0, 3, 1'b0, 1'b0);
                    release_reset;
                    wait_data_completion(1'b1, 80);
                    reset = 1'b1;
                    @(posedge clk);
                    @(negedge clk); #1;
                    chk("pop wrote no register", -1, 1, n_reg_wr);
                    chk("only the push completed", -1, 1, n_data_txn);
                    chk("only the push changed SP", -1, 1, n_sp_chg);
                    x_pcsp(16'h0000, STACK_TOP);
                    set_delays(0, 0, 1'b0, 1'b0);
                    release_reset;
                    finish_run(300);
                    x_status(1, 0);
                    x_pcsp(16'h0004, STACK_TOP);
                    x_regs(8'hB8, 8'hB8, 8'h00, 8'h00);
                    x_rw(0, 8'hB8); x_rw(0, 8'hB8);
                    x_d(1, 16'h0103, 8'hB8); x_sp(16'h0103, 1);
                    x_d(1, 16'h0103, 8'hB8); x_sp(16'h0103, 2);
                    x_d(0, 16'h0103, 8'hB8); x_rwm(1, 8'hB8); x_sp(16'h0104, 3);
                    x_pf_count(7);
                    x_done;
                end
                default: begin   // LOAD: reset in the middle of a long data wait
                    begin_scenario("S25e reset during data wait");
                    prog_begin; dmem_clear;
                    e_li(0, 8'h01); e_ra(OP_LOAD, 1, 16'h0020); e_halt;
                    dmem[16'h0020] = 8'h7E;
                    set_delays(0, 30, 1'b0, 1'b0);
                    release_reset;
                    c = 0;
                    while (data_request !== 1'b1 && c < 100) begin
                        @(negedge clk); #1;
                        c = c + 1;
                    end
                    repeat (4) @(negedge clk);
                    #1;
                    chk("waiting: data_request high", -1, 1, data_request);
                    chk("waiting: data_ready low",    -1, 0, data_ready);
                    @(negedge clk); #1;
                    reset = 1'b1;
                    #1;
                    chk("data_request cancelled by reset", -1, 0, data_request);
                    @(posedge clk);
                    @(negedge clk); #1;
                    chk("no data transaction completed", -1, 0, n_data_txn);
                    chk("only the LOADI wrote a register", -1, 1, n_reg_wr);
                    set_delays(0, 0, 1'b0, 1'b0);
                    release_reset;
                    finish_run(200);
                    x_status(1, 0);
                    x_regs(8'h01, 8'h7E, 8'h00, 8'h00);
                    x_rw(0, 8'h01); x_rw(0, 8'h01);
                    x_d(0, 16'h0020, 8'h7E); x_rwm(1, 8'h7E);
                    x_pf_count(7);
                    x_done;
                end
            endcase
        end
    endtask

    // S1b: reset clears populated R0-R3, Z/C/N, PC; SP returns to STACK_TOP
    task sc_reset_state;
        begin
            begin_scenario("S1b reset clears populated state");
            prog_begin;
            e_li(0, 8'hFF);              // 0
            e_li(1, 8'h01);              // 1
            e_rr(OP_ADD, 0, 1);          // 2: R0 = 00, Z=1 C=1 N=0
            e_li(2, 8'h5A);              // 3
            e_li(3, 8'hC3);              // 4
            e_r(OP_PUSH, 3);             // 5: SP 0104 -> 0103
            e_halt;                      // 6
            release_reset;
            finish_run(200);
            x_status(1, 0);
            x_pcsp(16'h0007, 16'h0103);
            x_regs(8'h00, 8'h01, 8'h5A, 8'hC3);
            x_flags(1, 1, 0);
            do_reset_clear;              // reset on the next rising edge
            x_regs(8'h00, 8'h00, 8'h00, 8'h00);
            x_flags(0, 0, 0);
            x_pcsp(16'h0000, STACK_TOP);
            x_status(0, 0);
            release_reset;
            repeat (2) @(negedge clk);
            chk("restart fetches word 0", -1, 16'h0000, plog_addr[0]);
        end
    endtask

    // S27: register A and register B are the same register
    task sc_same_reg;
        begin
            begin_scenario("S27 same register as A and B");
            prog_begin;
            e_li(0, 8'h05);              // 0
            e_li(1, 8'h80);              // 1
            e_li(2, 8'h07);              // 2
            e_li(3, 8'h90);              // 3
            e_rr(OP_ADD, 0, 0);          // 4: 05+05 = 0A, flags 0,0,0
            e_rr(OP_ADD, 1, 1);          // 5: 80+80 = 00 carry, flags 1,1,0
            e_rr(OP_SUB, 2, 2);          // 6: 07-07 = 00, flags 1,0,0
            e_rr(OP_ADD, 3, 3);          // 7: 90+90 = 20 carry, flags 0,1,0
            e_rr(OP_CMP, 0, 0);          // 8: flags 1,0,0; R0 stays 0A
            e_rr(OP_XOR, 3, 3);          // 9: 20^20 = 00, flags 1,0,0
            e_rr(OP_MOV, 0, 0);          // 10: R0 stays 0A, flags preserved
            e_rr(OP_AND, 0, 0);          // 11: 0A, flags 0,0,0
            e_rr(OP_OR,  0, 0);          // 12: 0A, flags 0,0,0
            e_halt;                      // 13
            release_reset;
            finish_run(300);
            x_status(1, 0);
            x_pcsp(16'h000E, STACK_TOP);
            x_regs(8'h0A, 8'h00, 8'h00, 8'h00);
            x_flags(0, 0, 0);
            x_rw(0, 8'h05); x_rw(1, 8'h80); x_rw(2, 8'h07); x_rw(3, 8'h90);
            x_rw(0, 8'h0A); x_fw(0, 0, 0, 1);      // ADD R0,R0
            x_rw(1, 8'h00); x_fw(1, 1, 0, 1);      // ADD R1,R1
            x_rw(2, 8'h00); x_fw(1, 0, 0, 1);      // SUB R2,R2
            x_rw(3, 8'h20); x_fw(0, 1, 0, 1);      // ADD R3,R3
            x_fw(1, 0, 0, 0);                      // CMP R0,R0: flags only
            x_rw(3, 8'h00); x_fw(1, 0, 0, 1);      // XOR R3,R3
            x_rw(0, 8'h0A);                        // MOV R0,R0: no FLAGS write
            x_rw(0, 8'h0A); x_fw(0, 0, 0, 1);      // AND R0,R0
            x_rw(0, 8'h0A); x_fw(0, 0, 0, 1);      // OR R0,R0
            x_pf_count(14);
            x_done;
        end
    endtask

    // ==================================================================
    // Main sequence
    // ==================================================================
    integer ci;

    initial begin
        $dumpfile("cpu_waveform.vcd");
        $dumpvars(0, cpu_tb);

        checks = 0; failures = 0; cyc = 0; scen_count = 0; cur_case = 0;
        cur_scen = "start";
        mon_on = 1'b0;
        n_prog_txn = 0; n_data_txn = 0; n_data_rd = 0; n_data_wr = 0;
        n_reg_wr = 0; n_flag_wr = 0; n_sp_chg = 0; last_ddone_cyc = 0;
        ri = 0; fi = 0; di = 0; pi_i = 0; si = 0;
        prog_done_prev = 1'b0; data_done_prev = 1'b0;
        prog_pend = 1'b0; data_pend = 1'b0; reset_prev = 1'b1; sp_last = 16'h0000;
        prog_delay_max = 0; data_delay_max = 0;
        prog_delay_rand = 1'b0; data_delay_rand = 1'b0;
        ready_noise = 1'b0;
        pseed = 32'h1234_5678; dseed = 32'h0BAD_CAFE;
        pw_active = 1'b0; dw_active = 1'b0; pw_cnt = 0; dw_cnt = 0; pw_goal = 0; dw_goal = 0;
        prog_ready = 1'b0; prog_read_data = 16'h0000;
        data_ready = 1'b0; data_read_data = 8'h00;
        reset = 1'b1;               // reset is high from time 0; the DUT has no initial block
        pp = 16'h0000; stopped = 1'b0; hit = 1'b0; bad_n = 0;

        sc_reset;
        sc_loadi_mov;
        sc_alu;
        sc_cmp;
        sc_preserve;
        sc_memory;
        sc_jumps;
        sc_lifo;
        sc_stack_fill;
        sc_push_overflow;
        sc_pop_all(1'b0);
        sc_pop_all(1'b1);
        sc_unsupported;
        sc_reserved;
        sc_reset_exit(1'b0);
        sc_reset_exit(1'b1);
        sc_reset_state;
        sc_same_reg;

        //          prog_wait data_wait prand drand noise case
        sc_full(0,  0,  1'b0, 1'b0, 1'b0, 1);
        sc_full(0,  0,  1'b0, 1'b0, 1'b1, 2);
        sc_full(1,  1,  1'b0, 1'b0, 1'b0, 3);
        sc_full(3,  0,  1'b0, 1'b0, 1'b0, 4);
        sc_full(0,  3,  1'b0, 1'b0, 1'b1, 5);
        sc_full(7,  12, 1'b0, 1'b0, 1'b1, 6);
        sc_full(25, 25, 1'b0, 1'b0, 1'b0, 7);
        sc_full(4,  4,  1'b1, 1'b1, 1'b0, 8);
        sc_full(9,  9,  1'b1, 1'b1, 1'b1, 9);
        sc_full(2,  15, 1'b1, 1'b1, 1'b0, 10);

        sc_reset_prog(0);
        sc_reset_prog(1);
        sc_reset_prog(2);
        for (ci = 0; ci < 5; ci = ci + 1) sc_reset_data(ci);

        // ---------------- Summary ----------------
        $display("----------------------------------------");
        $display("Scenarios run: %0d", scen_count);
        $display("Checks run: %0d   Failures: %0d", checks, failures);
        if (failures == 0) begin
            $display("PASS: all %0d checks passed", checks);
            $display("----------------------------------------");
            $finish;
        end else begin
            $display("FAIL: %0d of %0d checks failed", failures, checks);
            $display("----------------------------------------");
            $fatal(1, "cpu_tb: %0d check(s) failed", failures);
        end
    end

    // Global watchdog: a broken handshake can never hang the simulation
    initial begin
        #50000000;
        $display("FAIL: global simulation timeout (scenario '%0s')", cur_scen);
        $fatal(1, "cpu_tb: global timeout");
    end

endmodule
