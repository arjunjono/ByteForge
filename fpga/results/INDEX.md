# Provenance of the files in results/

These are logs kept from earlier runs; none is regenerated automatically into this folder. Re-running the scripts writes fresh copies under `sim/` and `build/` (both git-ignored), never over these.

| File | Produced by | Design state |
|---|---|---|
| run_all_full.out, run_all.log, tb_demo.log, tb_demo.time, prod.log, prod.time, assembler_tests_verbose.log | `sim/run_all.sh` (full, no `--fast`), revision 2, 2026-11-07 | before the CS/RST pin remap (RTL identical to now) |
| mutation_results.log | `sim/run_mutations.py`, revision 2 | RTL identical to now |
| syntax_error_demo.log | `sim/run_all.sh --fast` with a temporary syntax error, revision 2 | demonstration only |
| nextpnr.log, yosys.log, pin_verification.txt | `scripts/build_oss.sh` / pin check, revision 3, 2026-11-07 | after the remap (lcd_cs 41, lcd_rst 48) |
| original_hashes_before.txt / original_hashes_after.txt | `sha256sum` of the original CPU, assembler and regression files before / after the work | |

Results of the packaging check (a fresh extraction of this folder) are in `docs/VERIFICATION_RESULTS.md` only if stated there with their date; this index records no new results.
