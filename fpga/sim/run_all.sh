#!/usr/bin/env bash
# run_all.sh - build ROMs and run every ByteForge testbench with Icarus Verilog (iverilog -g2012).
# Usage:  cd fpga/sim && ./run_all.sh [--fast]     (--fast skips the two long runs: tb_demo ~2 min, tb_production_timing ~2-3 min)
# Exit status is nonzero if any test fails. Summary is written to run_all.log.
set -u
cd "$(dirname "$0")"
FAST=0; [ "${1:-}" = "--fast" ] && FAST=1
RTL="../rtl/button_input.v ../rtl/data_bus.v ../rtl/delay_unit.v ../rtl/spi_display_ctrl.v ../rtl/byteforge_io.v"
SYS="$RTL ../rtl/program_rom.v ../rtl/byteforge_system.v ../cpu/alu.v ../cpu/register_file.v ../cpu/flags_register.v ../cpu/instruction_decoder.v ../cpu/control_unit.v ../cpu/cpu.v"
IV="iverilog -g2012 -Wall"
: > run_all.log; FAILS=0
run() { # name, vvp, [dir]
  local name="$1" vvp="$2" dir="${3:-.}"
  local out; out=$(cd "$dir" && vvp "$vvp" 2>&1); local rc=$?
  if [ $rc -eq 0 ] && echo "$out" | grep -q "^PASS"; then echo "PASS  $name  ($(echo "$out" | grep -o '[0-9]* checks' | head -1))" | tee -a run_all.log
  else echo "FAIL  $name (exit $rc)" | tee -a run_all.log; echo "$out" | tail -15 | tee -a run_all.log; FAILS=$((FAILS+1)); fi
}
cc() { $IV "$@" || { echo "FAIL  compile error: $*" | tee -a run_all.log; FAILS=$((FAILS+1)); return 1; }; }
python3 gen_test_files.py >/dev/null && python3 make_test_roms.py >/dev/null || { echo "ROM generation failed"; exit 1; }
python3 ../sw/build_rom.py --all >/dev/null || { echo "build_rom failed"; exit 1; }
mkdir -p work && cp ../build/byteforge_rom.hex ../tb/ref_init.hex work/
cc -o rom.vvp -s tb_program_rom ../rtl/program_rom.v ../tb/tb_program_rom.v && run tb_program_rom rom.vvp
cc -o iobus.vvp -s tb_io_bus $RTL ../tb/spi_monitor.v ../tb/tb_io_bus.v && run tb_io_bus iobus.vvp
cc -o delay.vvp -s tb_delay $RTL ../tb/tb_delay.v && run tb_delay delay.vvp
cc -o btn.vvp -s tb_buttons ../rtl/button_input.v ../tb/tb_buttons.v && run tb_buttons btn.vvp
cc -o rst.vvp -s tb_reset_conditioner ../rtl/reset_conditioner.v ../tb/tb_reset_conditioner.v && run tb_reset_conditioner rst.vvp
for H in 1 2 3; do
  cc -Ptb_spi_display.HALF=$H -o spi$H.vvp -s tb_spi_display ../rtl/spi_display_ctrl.v ../tb/spi_monitor.v ../tb/tb_spi_display.v && run "tb_spi_display HALF=$H" spi$H.vvp
done
for M in "0 stack_basic" "1 stack_limit" "2 stack_underflow"; do set -- $M
  cc -Ptb_stack.MODE=$1 -Ptb_stack.ROM=\"$2.hex\" -o stack$1.vvp -s tb_stack $SYS ../tb/tb_stack.v && run "tb_stack MODE=$1 ($2)" stack$1.vvp
done
cc -o work/board.vvp -s tb_board_top $SYS ../rtl/reset_conditioner.v ../rtl/tang_nano_20k_top.v ../tb/spi_monitor.v ../tb/tb_board_top.v && run tb_board_top board.vvp work
if [ $FAST -eq 0 ]; then
  cc -o work/demo.vvp -s tb_demo $SYS ../tb/spi_monitor.v ../tb/tb_demo.v && run tb_demo demo.vvp work
  cc -o prod.vvp -s tb_production_timing $RTL ../tb/spi_monitor.v ../tb/tb_production_timing.v && run tb_production_timing prod.vvp
fi
# existing regressions (unchanged files)
# assembler_tests.py is run UNMODIFIED, in a scratch directory that has the assembler, the test file and the
# delivered demo programs side by side (the tests look for arithmetic/countdown/memory_stack .asm/.hex next to
# themselves). All 78 tests must run; any skip or failure counts as a failure of this script.
AT=work/asmtests; rm -rf $AT; mkdir -p $AT
cp ../cpu/assembler.py ../cpu/assembler_tests.py ../programs/*.asm ../programs/*.hex $AT/
( cd $AT && python3 assembler_tests.py -v > ../../asm_tests.log 2>&1 ); RC=$?
RAN=$(grep -o "^Ran [0-9]* tests" asm_tests.log | grep -o "[0-9]*"); SK=$(grep -c "skipped" asm_tests.log)
if [ $RC -eq 0 ] && [ "$RAN" = "78" ] && [ "$SK" = "0" ]; then echo "PASS  assembler_tests.py  (78 tests, 0 skipped)" | tee -a run_all.log
else echo "FAIL  assembler_tests.py (rc=$RC ran=$RAN skipped-lines=$SK)" | tee -a run_all.log; FAILS=$((FAILS+1)); fi
CPU="../cpu/alu.v ../cpu/register_file.v ../cpu/flags_register.v ../cpu/instruction_decoder.v ../cpu/control_unit.v ../cpu/cpu.v"
mkdir -p work/reg && cp ../programs/*.hex work/reg/
cc -o work/reg/cpu_tb.vvp -s cpu_tb $CPU ../cpu/cpu_tb.v && run "existing cpu_tb" cpu_tb.vvp work/reg
cc -o work/reg/asmprog.vvp -s assembly_programs_tb $CPU ../cpu/assembly_programs_tb.v && run "existing assembly_programs_tb" asmprog.vvp work/reg
echo "failures: $FAILS" | tee -a run_all.log
exit $FAILS
