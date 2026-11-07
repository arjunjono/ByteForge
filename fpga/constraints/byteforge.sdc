# byteforge.sdc - timing constraints (Gowin SDC)
# 27 MHz crystal on pin 4: 37.037 ns period (same constraint as Sipeed's blink_leds.sdc, which also
# lists -waveform {0 18.518}; that is the default 50 % duty cycle and is left out because nextpnr's SDC
# reader rejects -waveform).
create_clock -name clk_27M -period 37.037 [get_ports {clk}]

# Narrow asynchronous-input exceptions: only these seven *ports*. Each of them is read by exactly one
# first-stage synchronizer flop (button_input.sync1[*] / reset_conditioner.chain[*]), so there is no
# internal logic behind the exception. Nothing internal is declared false-path or multicycle.
set_false_path -from [get_ports btn_up_n]
set_false_path -from [get_ports btn_down_n]
set_false_path -from [get_ports btn_left_n]
set_false_path -from [get_ports btn_right_n]
set_false_path -from [get_ports btn_a_n]
set_false_path -from [get_ports btn_b_n]
set_false_path -from [get_ports rst_btn_n]
