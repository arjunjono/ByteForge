#!/usr/bin/env python3
"""verify_pins.py - check where nextpnr actually placed each top-level port against the requested package pins.
Usage: python3 scripts/verify_pins.py [build/oss/byteforge_pnr.json]   (writes build/oss/pin_verification.txt)
Maps each placed IO site to a package pin with Apycula's GW2AR-18C QFN88 table and compares it with the pins in
constraints/byteforge.cst (parsed from the file, not hard-coded). Exit status 1 on any mismatch."""
import json, os, re, sys, glob
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.dirname(here)
pnr = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'build', 'oss', 'byteforge_pnr.json')
cst = open(os.path.join(root, 'constraints', 'byteforge.cst')).read()
req = {}
for m in re.finditer(r'^\s*IO_LOC\s+"([^"]+)"\s+(\d+)\s*;', cst, re.M):
    req[m.group(1)] = int(m.group(2))
import apycula
from apycula import chipdb
dbf = glob.glob(os.path.join(os.path.dirname(apycula.__file__), 'GW2A-18C.msgpack*'))[0]
db = chipdb.load_chipdb(dbf)
inv = {(v if isinstance(v, str) else v[0]): k for k, v in db.pinout['GW2AR-18C']['QFN88'].items()}
rows = db.rows - 1
top = list(json.load(open(pnr))['modules'].values())[0]
out = ["port | BEL | IO name | package pin | requested | match"]; bad = 0; seen = set()
for n, c in top['cells'].items():
    a = c.get('attributes', {})
    m = re.match(r'X(\d+)Y(\d+)/IOB([AB])$', a.get('NEXTPNR_BEL', ''))
    if not m or not c['type'].endswith('BUF'): continue
    x, y, ab = int(m[1]), int(m[2]), m[3]
    io = f'IOT{x+1}{ab}' if y == 0 else f'IOB{x+1}{ab}' if y == rows else f'IOL{y+1}{ab}' if x == 0 else f'IOR{y+1}{ab}'
    pin = int(inv[io])
    bits = set(sum([v for k, v in c['connections'].items() if k in ('I', 'O')], []))
    for p, pd in top['ports'].items():
        for i, b in enumerate(pd['bits']):
            if b in bits:
                name = p if len(pd['bits']) == 1 else f'{p}[{i}]'
                r = req.get(name); ok = (r == pin); bad += (not ok); seen.add(name)
                out.append(f'{name} | {a["NEXTPNR_BEL"]} | {io} | {pin} | {r} | {"OK" if ok else "MISMATCH"}')
missing = set(req) - seen
for n in sorted(missing): out.append(f'{n} | NOT PLACED | | | {req[n]} | MISMATCH'); bad += 1
out.append(f'mismatches: {bad}')
txt = '\n'.join(out) + '\n'
open(os.path.join(os.path.dirname(pnr), 'pin_verification.txt'), 'w').write(txt); print(txt, end='')
sys.exit(1 if bad else 0)
