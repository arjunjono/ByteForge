#!/usr/bin/env python3
"""build_rom.py - build every ByteForge machine-code file with the existing assembler.

Standard library only. The assembler (assembler.py, unchanged) does all the
encoding; this script only runs it, pads the demo image and checks results.

Usage (from the project root, or anywhere):
    python sw/build_rom.py                 build demo + ROM image into build/
    python sw/build_rom.py --check         rebuild into a temp dir and compare
                                           with what is in build/ (exit 1 if differ)
    python sw/build_rom.py --all           also rebuild the example programs in programs/

Outputs (default build/):
    demo.hex            assembler output, one 4-digit word per line (455 words)
    demo.lst            assembler listing
    byteforge_rom.hex   demo.hex padded with HALT (8800) to exactly 8192 lines;
                        this is the file program_rom.v reads ($readmemh)
Exit status: 0 ok, 1 assembly/overflow/check failure, 2 usage/file error.

Safety: the script never writes to a .asm path, and refuses an output path
equal to the source. Output is deterministic (no timestamps, absolute paths
or randomness).
"""
import argparse
import filecmp
import hashlib
import os
import subprocess
import sys
import tempfile

ROM_WORDS = 8192
HALT_WORD = "8800"            # opcode 17 << 11, see assembler.py INSTRUCTIONS
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def run_assembler(assembler, asm, hex_out, lst_out):
    """Run the unchanged assembler with relative file names so the listing
    header (which contains only the source base name) cannot vary."""
    cmd = [sys.executable, "-I", assembler, os.path.basename(asm),
           "--hex", hex_out, "--lst", lst_out]
    p = subprocess.run(cmd, cwd=os.path.dirname(os.path.abspath(asm)),
                       capture_output=True, text=True)
    if p.returncode != 0:
        sys.stderr.write(p.stdout + p.stderr)
        return p.returncode
    return 0


def read_words(path):
    words = []
    with open(path, "r", encoding="ascii") as f:
        for n, line in enumerate(f, 1):
            w = line.strip()
            if len(w) != 4 or any(c not in "0123456789ABCDEF" for c in w):
                raise ValueError("%s line %d: bad word %r" % (path, n, w))
            words.append(w)
    return words


def pad_rom(words, out_path):
    if len(words) > ROM_WORDS:
        raise OverflowError("program has %d words, ROM holds %d" % (len(words), ROM_WORDS))
    full = words + [HALT_WORD] * (ROM_WORDS - len(words))
    assert len(full) == ROM_WORDS
    with open(out_path, "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(full) + "\n")


def build_demo(assembler, asm, outdir):
    os.makedirs(outdir, exist_ok=True)
    hex_out = os.path.abspath(os.path.join(outdir, "demo.hex"))
    lst_out = os.path.abspath(os.path.join(outdir, "demo.lst"))
    rom_out = os.path.abspath(os.path.join(outdir, "byteforge_rom.hex"))
    for p in (hex_out, lst_out, rom_out):
        if os.path.abspath(p) == os.path.abspath(asm) or p.lower().endswith(".asm"):
            sys.stderr.write("refusing to write to %s\n" % p)
            return 2
    rc = run_assembler(assembler, asm, hex_out, lst_out)
    if rc:
        return rc
    words = read_words(hex_out)
    try:
        pad_rom(words, rom_out)
    except OverflowError as e:
        sys.stderr.write("ERROR: %s\n" % e)
        return 1
    print("demo: %d words, ROM image padded to %d with HALT" % (len(words), ROM_WORDS))
    return 0


def build_programs(assembler, progdir, outdir_override=None):
    rc_all = 0
    for name in sorted(os.listdir(progdir)):
        if not name.endswith(".asm"):
            continue
        base = name[:-4]
        asm = os.path.join(progdir, name)
        od = outdir_override or progdir
        rc = run_assembler(assembler, asm, os.path.join(od, base + ".hex"),
                           os.path.join(od, base + ".lst"))
        print("program %-14s %s" % (name, "ok" if rc == 0 else "FAILED"))
        rc_all = rc_all or rc
    return rc_all


def same(a, b):
    return os.path.isfile(a) and os.path.isfile(b) and filecmp.cmp(a, b, shallow=False)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--asm", default=os.path.join(HERE, "demo.asm"))
    ap.add_argument("--assembler", default=os.path.join(ROOT, "cpu", "assembler.py"))
    ap.add_argument("--outdir", default=os.path.join(ROOT, "build"))
    ap.add_argument("--programs", default=os.path.join(ROOT, "programs"))
    ap.add_argument("--all", action="store_true", help="also rebuild programs/*.asm")
    ap.add_argument("--check", action="store_true", help="rebuild to a temp dir and compare")
    a = ap.parse_args()

    if not os.path.isfile(a.asm) or not os.path.isfile(a.assembler):
        sys.stderr.write("missing %s or %s\n" % (a.asm, a.assembler))
        return 2

    if a.check:
        with tempfile.TemporaryDirectory() as td:
            rc = build_demo(a.assembler, a.asm, td)
            if rc:
                return rc
            bad = 0
            names = ["demo.hex", "demo.lst", "byteforge_rom.hex"]
            for n in names:
                ok = same(os.path.join(td, n), os.path.join(a.outdir, n))
                print("%-20s %s" % (n, "identical" if ok else "DIFFERS"))
                bad |= (not ok)
            if a.all and os.path.isdir(a.programs):
                for name in sorted(os.listdir(a.programs)):
                    if name.endswith(".asm"):
                        base = name[:-4]
                        tdp = os.path.join(td, "prog")
                        os.makedirs(tdp, exist_ok=True)
                        rc = run_assembler(a.assembler, os.path.join(a.programs, name),
                                           os.path.join(tdp, base + ".hex"), os.path.join(tdp, base + ".lst"))
                        for ext in (".hex", ".lst"):
                            ok = rc == 0 and same(os.path.join(tdp, base + ext), os.path.join(a.programs, base + ext))
                            print("%-20s %s" % (base + ext, "identical" if ok else "DIFFERS"))
                            bad |= (not ok)
            return 1 if bad else 0

    rc = build_demo(a.assembler, a.asm, a.outdir)
    if rc:
        return rc
    if a.all:
        rc = build_programs(a.assembler, a.programs)
        if rc:
            return rc
    for n in ("demo.hex", "demo.lst", "byteforge_rom.hex"):
        with open(os.path.join(a.outdir, n), "rb") as f:
            print("sha256 %s  %s" % (hashlib.sha256(f.read()).hexdigest(), n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
