# byteforge_oss.sdc - clock constraint for the open-source (nextpnr-himbaechel) flow.
# nextpnr's SDC reader has no get_clocks and needs -to with set_false_path, and it does not time paths that
# start at ports without an input delay, so the Gowin-IDE false-path lines are not needed or accepted here.
create_clock -name clk_27M -period 37.037 [get_ports {clk}]
