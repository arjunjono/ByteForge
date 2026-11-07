`timescale 1ns/1ps
// data_bus.v - ByteForge data-space decoder, 16 KB RAM and transaction FSM
//
// Data map (full 16-bit compare, no aliasing):
//   0x0000-0x3EFF general RAM      0x3F00-0x3FFF stack RAM  (one 16 KB array)
//   0xFF00 buttons (R)   0xFF10 LCD command (W)   0xFF11 LCD data (W)
//   0xFF12 LCD status (R) 0xFF13 backlight (R/W)  0xFF20 delay ms (W)
//   everything else: reads 0, writes complete with no effect.
//   Reads of write-only registers 0xFF10/0xFF11/0xFF20 return 0, no effect.
//   Writes to read-only registers 0xFF00/0xFF12 complete with no effect.
//
// Transaction FSM (identical shape to program_rom):
//   IDLE  request seen at edge E0 (and !reset): address/direction/write data
//         are captured ONCE, RAM read data and peripheral read values are
//         captured at E0, a delay write starts its timer. -> RDY
//   RDY   ready = !reset && peripheral_ok. Completion is the edge where
//         data_request && data_ready. Writes/peripheral actions are pulsed
//         only at that edge. -> DONE
//   DONE  ready = 0 until request has been seen low (exactly-once rule).
// Reset forces IDLE and suppresses ready and every side effect, so a
// transaction pending at reset is simply abandoned. RAM contents survive.
module data_bus (
    input         clk,
    input         reset,

    input         data_request,
    input         data_write_enable,
    input  [15:0] data_address,
    input  [7:0]  data_write_data,
    output        data_ready,
    output [7:0]  data_read_data,

    // peripherals
    input  [7:0]  btn_value,
    input  [7:0]  disp_status,
    input         disp_can_accept,
    output        disp_wr_valid,     // one-cycle pulse at the completion edge
    output        disp_wr_is_data,
    output [7:0]  disp_wr_byte,
    input  [7:0]  bl_value,
    output        bl_wr,             // one-cycle pulse at the completion edge
    output        bl_wr_bit,
    input         delay_active,
    output        delay_start,       // one-cycle pulse at the capture edge
    output [7:0]  delay_value,
    output        delay_cancel
);
    localparam [15:0] A_BTN = 16'hFF00, A_CMD = 16'hFF10, A_DAT = 16'hFF11,
                      A_STAT = 16'hFF12, A_BL = 16'hFF13, A_DLY = 16'hFF20;

    localparam [1:0] S_IDLE = 2'd0, S_RDY = 2'd1, S_DONE = 2'd2;
    reg [1:0] st;

    // ---------------- combinational decode of the live address ----------------
    wire in_ram  = (data_address[15:14] == 2'b00);
    wire is_btn  = (data_address == A_BTN);
    wire is_cmd  = (data_address == A_CMD);
    wire is_dat  = (data_address == A_DAT);
    wire is_stat = (data_address == A_STAT);
    wire is_bl   = (data_address == A_BL);
    wire is_dly  = (data_address == A_DLY);

    // ---------------- values captured once at the IDLE edge -------------------
    reg        cap_we;
    reg [13:0] cap_addr;
    reg [7:0]  cap_wdata;
    reg        r_ram, r_cmd, r_dat, r_bl, r_dly;
    reg [7:0]  rd_q;

    wire capture = (st == S_IDLE) && data_request && !reset;

    always @(posedge clk) begin
        if (capture) begin
            cap_we    <= data_write_enable;
            cap_addr  <= data_address[13:0];
            cap_wdata <= data_write_data;
            r_ram     <= in_ram;
            r_cmd     <= is_cmd;
            r_dat     <= is_dat;
            r_bl      <= is_bl;
            r_dly     <= is_dly;
            rd_q      <= is_btn  ? btn_value   :
                         is_stat ? disp_status :
                         is_bl   ? bl_value    : 8'h00;
        end
    end

    // ---------------- ready / completion ---------------------------------------
    wire per_ok = (r_dly && cap_we)           ? !delay_active   :
                  ((r_cmd || r_dat) && cap_we) ? disp_can_accept : 1'b1;
    assign data_ready = (st == S_RDY) && !reset && per_ok;
    wire complete = data_request && data_ready;

    always @(posedge clk) begin
        if (reset) st <= S_IDLE;
        else case (st)
            S_IDLE: if (data_request) st <= S_RDY;
            S_RDY:  if (!data_request)  st <= S_IDLE;   // withdrawn, nothing done
                    else if (data_ready) st <= S_DONE;
            S_DONE: if (!data_request)  st <= S_IDLE;
            default: st <= S_IDLE;
        endcase
    end

    // ---------------- RAM: single-port, synchronous, never reset ---------------
    // The address is the live bus address in IDLE (the read data is captured at
    // the capture edge) and the captured address afterwards (the write happens
    // at the completion edge). No init loop, no reset: contents are unspecified
    // at power-up and survive reset.
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    reg [7:0] ram [0:16383];
    reg [7:0] ram_q;
    wire [13:0] ram_a  = (st == S_IDLE) ? data_address[13:0] : cap_addr;
    wire        ram_we = complete && cap_we && r_ram;
    always @(posedge clk) begin
        if (ram_we) ram[ram_a] <= cap_wdata;
        ram_q <= ram[ram_a];
    end

    assign data_read_data = r_ram ? ram_q : rd_q;

    // ---------------- peripheral actions (exactly once) -------------------------
    assign disp_wr_valid   = complete && cap_we && (r_cmd || r_dat);
    assign disp_wr_is_data = r_dat;
    assign disp_wr_byte    = cap_wdata;
    assign bl_wr           = complete && cap_we && r_bl;
    assign bl_wr_bit       = cap_wdata[0];
    assign delay_start     = capture && data_write_enable && is_dly && (|data_write_data);
    assign delay_value     = data_write_data;
    assign delay_cancel    = (st == S_RDY) && !data_request;
endmodule
