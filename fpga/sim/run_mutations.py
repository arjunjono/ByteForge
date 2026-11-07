#!/usr/bin/env python3
"""run_mutations.py - apply targeted mutations to TEMPORARY COPIES of the RTL and check that the testbenches fail.
The real files in ../rtl are never modified (copies live in sim/mutants/). Usage: python3 run_mutations.py
Exit status 0 only if every mutant is detected AND the unmutated design passes the same testbenches."""
import os, re, shutil, subprocess, sys, hashlib
here = os.path.dirname(os.path.abspath(__file__)); os.chdir(here)
RTLDIR = '../rtl'; MUT = 'mutants'
def sha(p): return hashlib.sha256(open(p, 'rb').read()).hexdigest()
before = {f: sha(f'{RTLDIR}/{f}') for f in os.listdir(RTLDIR)}
MUTATIONS = [
 ('M1 repeated peripheral write (a held request completes again: DONE no longer waits for request low)', 'data_bus.v',
  'S_DONE: if (!data_request)  st <= S_IDLE;', 'S_DONE: st <= S_RDY;'),
 ('M2 wrong RAM address bit (bit 13 dropped)', 'data_bus.v',
  'wire [13:0] ram_a  = (st == S_IDLE) ? data_address[13:0] : cap_addr;',
  "wire [13:0] ram_a  = (st == S_IDLE) ? {1'b0, data_address[12:0]} : {1'b0, cap_addr[12:0]};"),
 ('M3a SPI bit order (first bit sent is bit 0)', 'spi_display_ctrl.v',
  'lcd_mosi  <= wr_byte[7];', 'lcd_mosi  <= wr_byte[0];'),
 ('M3b SPI DC polarity inverted', 'spi_display_ctrl.v',
  'lcd_dc    <= wr_is_data;', 'lcd_dc    <= ~wr_is_data;'),
 ('M4 debounce bypass (stable follows the synchronizer directly)', 'button_input.v',
  'if (sampled_pressed == stable[g])\n                    cnt <= {CW{1\'b0}};',
  'stable[g] <= sampled_pressed;\n                if (sampled_pressed == stable[g])\n                    cnt <= {CW{1\'b0}};'),
]
RTL = ['button_input.v','data_bus.v','delay_unit.v','spi_display_ctrl.v','byteforge_io.v']
def tests(d):
    P = lambda *f: [f'{d}/{x}' for x in f]
    io = P(*RTL) + ['../tb/spi_monitor.v']
    return [
     ('tb_io_bus',   ['-s','tb_io_bus'] + io + ['../tb/tb_io_bus.v']),
     ('tb_delay',    ['-s','tb_delay'] + io + ['../tb/tb_delay.v']),
     ('tb_buttons',  ['-s','tb_buttons', f'{d}/button_input.v', '../tb/tb_buttons.v']),
     ('tb_spi_display', ['-s','tb_spi_display','-Ptb_spi_display.HALF=2', f'{d}/spi_display_ctrl.v','../tb/spi_monitor.v','../tb/tb_spi_display.v']),
    ]
def run_tests(d):
    res = {}
    for name, args in tests(d):
        c = subprocess.run(['iverilog','-g2012','-o','mut.vvp'] + args, capture_output=True, text=True)
        if c.returncode: res[name] = ('COMPILE-ERROR', c.stderr[:200]); continue
        r = subprocess.run(['vvp','mut.vvp'], capture_output=True, text=True)
        out = r.stdout + r.stderr
        fails = [l for l in out.splitlines() if l.startswith('FAIL')]
        ok = r.returncode == 0 and 'PASS' in out
        res[name] = ('PASS' if ok else 'FAIL', fails[0] if fails else '', len(fails))
    return res
log = []; allok = True
shutil.rmtree(MUT, ignore_errors=True); os.makedirs(MUT)
for f in RTL: shutil.copy(f'{RTLDIR}/{f}', f'{MUT}/{f}')
base = run_tests(MUT); log.append('Baseline (unmutated copies): ' + ', '.join(f'{k}={v[0]}' for k, v in base.items()))
if any(v[0] != 'PASS' for v in base.values()): allok = False
for title, fn, old, new in MUTATIONS:
    shutil.copy(f'{RTLDIR}/{fn}', f'{MUT}/{fn}')
    s = open(f'{MUT}/{fn}').read()
    if s.count(old) != 1: print('mutation text not found exactly once:', title); sys.exit(2)
    open(f'{MUT}/{fn}', 'w').write(s.replace(old, new))
    r = run_tests(MUT)
    caught = [k for k, v in r.items() if v[0] != 'PASS']
    log.append(f'{title}\n    detected by: {", ".join(caught) if caught else "NOBODY  <-- GAP"}')
    for k in caught: log.append(f'      {k}: {r[k][0]}  {r[k][1] if len(r[k])>1 else ""} ({r[k][2] if len(r[k])>2 else "-"} failing checks)')
    if not caught: allok = False
    shutil.copy(f'{RTLDIR}/{fn}', f'{MUT}/{fn}')              # restore the mutant copy
after = {f: sha(f'{RTLDIR}/{f}') for f in os.listdir(RTLDIR)}
log.append('Real RTL files unchanged by this script: ' + str(before == after)); allok = allok and before == after
shutil.rmtree(MUT, ignore_errors=True)
open('mutation_results.log', 'w').write('\n'.join(log) + '\n'); print('\n'.join(log))
print('ALL MUTANTS DETECTED' if allok else 'MUTATION CHECK FAILED'); sys.exit(0 if allok else 1)
