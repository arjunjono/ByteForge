# ByteForge FPGA system (Tang Nano 20K + Waveshare 17344)

Status: simulated extensively and run through an open-source synthesis/place-and-route flow. **Not built with the Gowin IDE, not tested on hardware.** See `docs/VERIFICATION_RESULTS.md` before trusting anything here.

## Layout
- `cpu/` - your six CPU files, `assembler.py`, `assembler_tests.py`, `cpu_tb.v`, `assembly_programs_tb.v` (byte-identical to the originals, hashes checked).
- `rtl/` - new design: `program_rom.v`, `data_bus.v`, `delay_unit.v`, `button_input.v`, `reset_conditioner.v`, `spi_display_ctrl.v`, `byteforge_io.v` (peripherals + bus), `byteforge_system.v` (real CPU + ROM + io), `tang_nano_20k_top.v`.
- `sw/` - `demo.asm`, `build_rom.py` (uses the unchanged assembler; pads to 8192 words with HALT; rejects overflow; `--check` verifies determinism), `extract_reference_init.py`.
- `build/` - `demo.hex`, `demo.lst`, `byteforge_rom.hex` (8192 words), OSS-flow outputs in `build/oss/`.
- `tb/`, `sim/` - testbenches, `run_all.sh`, `run_mutations.py`, ROM generators.
- `constraints/` - `byteforge.cst`, `byteforge.sdc` (Gowin), `byteforge_oss.sdc`. `gowin/` - `byteforge_tang20k.gprj` + ROM copy. `scripts/build_oss.sh`.
- `docs/` - corrections, results, Windows build, EDA Playground.

## How it works (short)
- **Bus**: ROM and data bus use the same three-state handshake IDLE -> RDY -> DONE. The address/data are captured once in IDLE; `ready` is only true in RDY (and not in reset, and only when the peripheral can accept); the effect happens at the single edge where `request && ready`; DONE waits for `request` to fall, so a held request cannot repeat an action.
- **Memories**: ROM 8192x16 in block RAM, loaded with `$readmemh`; out-of-range fetch returns HALT. RAM 16384x8 single-port block RAM, never reset or initialised.
- **Peripherals**: 2-FF synchronizer + independent 10 ms debounce per button; blocking millisecond delay; SPI-mode-0 byte transmitter (no FIFO) with startup sequencer for the panel reset; backlight register.
- **Reset**: external active-low button and a power-on counter go through a 2-FF async-assert/sync-release chain with initial values; the CPU keeps its synchronous reset. One clock domain (27 MHz crystal, no PLL); SPI clock is a registered output only.
- **Demo**: waits for startup, replays Waveshare's init, fills the screen black, draws a cyan square, recolours it on button edges.

## Commands
```
cd sim && ./run_all.sh --fast        # all unit/integration tests + existing regressions (about 1 min)
cd sim && ./run_all.sh               # also tb_demo and tb_production_timing (about 4 more min)
cd sim && python3 run_mutations.py   # mutation checks on temporary copies
python3 sw/build_rom.py              # regenerate demo.hex/.lst and the padded ROM;  --check, --all
./scripts/build_oss.sh               # yosys + nextpnr + apycula (needs those tools)
```
(Each testbench's header comment has its exact `iverilog` line; `run_all.sh` uses the same ones.)

## Unresolved issues
1. Gowin IDE flow, timing and resources: NOT VERIFIED; `$readmemh` path handling and initial-value/attribute support in Gowin synthesis unconfirmed.
2. Display supply: 3.3 V from a dedicated AP2112K-3.3TRG1 on the carrier PCB (5 V header in, 1 uF in/out), separate from the Tang Nano 3V3 rail - see docs/HARDWARE_POWER.md. The regulator and its datasheet were not checked by me.
3. **Pins 73 and 74 (LCD DIN/CLK) carry BL616 HSPI net names in Sipeed's schematic** (possible contention); CS and RST were moved to pins 41 and 48 in revision 2. Not resolved - check continuity (docs section B).
4. Bank 4 voltage (pins 41 = LCD CS and 42 = BL) not confirmed (assumed 3.3 V). Pin 41 carries CS, so a non-3.3 V bank would matter there.
5. Orientation: reference code is internally inconsistent (A2); check on the real panel.
6. Post-SLPOUT delay: datasheet needs only >= 5 ms (v1.6 9.1.12); the demo's 125 ms is a conservative choice. Panel hardware-reset timing (100/100/100 ms) is the Waveshare reference's, ST7789V section 7.4.5 not read. 6.75 MHz SPI is not datasheet-verified.
7. Gowin SDC input false paths and all external I/O timing untested; hardware operation untested; Windows/EDA Playground steps not executed.
