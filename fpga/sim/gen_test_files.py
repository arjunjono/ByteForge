#!/usr/bin/env python3
"""gen_test_files.py - create the data files the unit testbenches need.

  test_rom.hex   8192 words, word[i] = ((i*40503 + 0x1357) ^ (i >> 3)) & 0xFFFF,
                 nudged so no word equals HALT (0x8800); the testbench computes the
                 same formula itself, so expectations do not come from the design.
Run from anywhere:  python sim/gen_test_files.py [outdir]
"""
import os
import sys

def word(i):
    w = ((i * 40503 + 0x1357) ^ (i >> 3)) & 0xFFFF
    return w if w != 0x8800 else 0x8801

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(out, "test_rom.hex"), "w", newline="\n") as f:
        for i in range(8192):
            f.write("%04X\n" % word(i))

if __name__ == "__main__":
    main()
