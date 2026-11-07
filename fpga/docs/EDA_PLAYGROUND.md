# EDA Playground instructions (written, NOT run on EDA Playground)

Settings: Language *SystemVerilog/Verilog*, Simulator *Icarus Verilog 12.0* (the version I used locally; other versions untested), compile option `-g2012`, tick **Use run.do/none**, leave "Open EPWave" off (nothing dumps waves).
EDA Playground has one *design* pane and one *testbench* pane plus extra file tabs (the "+" button). Paste several modules into one pane by concatenating the files; the file names below are the exact names to give the extra tabs.

## Quick checks that fit the browser (small)
| Test | design pane (paste all, in this order) | testbench pane | extra tabs |
|---|---|---|---|
| ROM | `rtl/program_rom.v` | `tb/tb_program_rom.v` | `test_rom.hex` (from `sim/gen_test_files.py`) |
| Buttons | `rtl/button_input.v` | `tb/tb_buttons.v` | - |
| Reset | `rtl/reset_conditioner.v` | `tb/tb_reset_conditioner.v` | - |
| SPI display | `rtl/spi_display_ctrl.v`, `tb/spi_monitor.v` | `tb/tb_spi_display.v` | - (set `-Ptb_spi_display.HALF=2` in compile options) |
| Bus + peripherals | `rtl/button_input.v data_bus.v delay_unit.v spi_display_ctrl.v byteforge_io.v`, `tb/spi_monitor.v` | `tb/tb_io_bus.v` (or `tb_delay.v`) | - |
| Stack | all `rtl/*.v` except `tang_nano_20k_top.v`, all six `cpu/*.v` | `tb/tb_stack.v` | `stack_basic.hex` (+ `-Ptb_stack.MODE=0 -Ptb_stack.ROM=\"stack_basic.hex\"`; `stack_limit.hex` MODE=1; `stack_underflow.hex` MODE=2) |
| Board top | all `rtl/*.v`, six `cpu/*.v`, `tb/spi_monitor.v` | `tb/tb_board_top.v` | `byteforge_rom.hex` (from `build/`) |

The `-P` options go in "Compile Options". Each testbench ends with `PASS: <name>` and exits non-zero via `$fatal` on failure.

## Long runs - run locally instead
- `tb_demo.v` (about 8.8 M clocks, ~2 min on my machine; extra tabs `byteforge_rom.hex`, `ref_init.hex`) and `tb_production_timing.v` (16 M clocks, ~2 min). EDA Playground has a run-time limit I have not measured, so these were only run locally. Shortening the demo timing is a parameter edit in `tb_demo.v` (`MS`, `DEB`, `T_PH`), but the testbench's expected-timing checks were only exercised at the shipped values, so a shortened version would be untested.
- EDA Playground compiles with its own working directory; `$readmemh("byteforge_rom.hex")` finds a file with exactly that tab name. I have not confirmed this on the site.
