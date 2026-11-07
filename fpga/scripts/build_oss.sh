#!/usr/bin/env bash
# build_oss.sh - open-source flow used for the Stage 7 results (Yosys + nextpnr-himbaechel + Apycula).
# Tested with: Yosys 0.33, nextpnr-himbaechel 9691ce8 (built from source), Apycula 0.35.
# This is NOT the official Gowin flow; the bitstream it writes has not been loaded onto hardware.
set -e
cd "$(dirname "$0")/.."
python3 sw/build_rom.py --all >/dev/null
mkdir -p build/oss && cd build/oss && cp ../byteforge_rom.hex .
yosys -l synth.log -p "read_verilog -sv ../../rtl/tang_nano_20k_top.v ../../rtl/byteforge_system.v ../../rtl/byteforge_io.v ../../rtl/program_rom.v ../../rtl/data_bus.v ../../rtl/delay_unit.v ../../rtl/button_input.v ../../rtl/reset_conditioner.v ../../rtl/spi_display_ctrl.v ../../cpu/alu.v ../../cpu/register_file.v ../../cpu/flags_register.v ../../cpu/instruction_decoder.v ../../cpu/control_unit.v ../../cpu/cpu.v; synth_gowin -top tang_nano_20k_top -json byteforge.json"
nextpnr-himbaechel --json byteforge.json --write byteforge_pnr.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=../../constraints/byteforge.cst --freq 27 --report nextpnr_report.json --seed 1 -l pnr.log
gowin_pack -d GW2A-18C -o byteforge.fs byteforge_pnr.json
grep "Max frequency" pnr.log | tail -1
cd ../..
python3 scripts/verify_pins.py build/oss/byteforge_pnr.json | tail -1
