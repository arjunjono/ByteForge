#!/usr/bin/env python3
"""make_test_roms.py - assemble the small test programs in this folder into padded 8192-word ROM images
(<name>.hex) using the unchanged assembler. Usage: python make_test_roms.py [assembler.py]"""
import os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
asm = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "cpu", "assembler.py")
for name in sorted(os.listdir(here)):
    if not name.endswith(".asm"):
        continue
    base = name[:-4]
    tmp = os.path.join(here, base + ".raw.hex")
    r = subprocess.run([sys.executable, "-I", asm, name, "--hex", tmp, "--lst", os.path.join(here, base + ".lst")],
                       cwd=here, capture_output=True, text=True)
    if r.returncode:
        sys.stderr.write(r.stdout + r.stderr); sys.exit(1)
    words = [l.strip() for l in open(tmp)]
    os.remove(tmp)
    assert len(words) <= 8192
    words += ["8800"] * (8192 - len(words))
    with open(os.path.join(here, base + ".hex"), "w", newline="\n") as f:
        f.write("\n".join(words) + "\n")
    print("%s: ROM image written" % base)
