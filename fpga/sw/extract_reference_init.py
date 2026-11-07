#!/usr/bin/env python3
"""extract_reference_init.py - pull the panel init sequence out of Waveshare's own source.

Source (primary): GitHub waveshare/Pico_code, file c/lib/LCD/LCD_2in.c, function LCD_2IN_InitReg(),
commit c50bc57040a33ee9540e993a2bbe99bf6e621fbd (2021-05-22).
The file is not redistributed here; download it yourself and run:

    python sw/extract_reference_init.py path/to/LCD_2in.c  [tb/ref_init.hex]

It prints every command/data byte of LCD_2IN_InitReg() and writes tb/ref_init.hex, one 3-digit hex
entry per line: first digit 0 = command (DC=0), 1 = data (DC=1), then the byte. The demo testbench
loads that file as its expected SPI byte stream, so its expectation comes from Waveshare's source,
not from demo.asm. SHA-256 of the file used for the committed ref_init.hex is printed with --sha.
"""
import hashlib, re, sys

def extract(path):
    text = open(path, "r", encoding="latin-1").read()
    m = re.search(r"static void LCD_2IN_InitReg\(void\)\s*\{(.*?)^\}", text, re.S | re.M)
    if not m:
        raise SystemExit("LCD_2IN_InitReg not found")
    out = []
    for kind, val in re.findall(r"LCD_2IN_Send(Command|Data_8Bit)\(\s*(0[xX][0-9A-Fa-f]+)\s*\)", m.group(1)):
        out.append((0 if kind == "Command" else 1, int(val, 16)))
    return out, hashlib.sha256(open(path, "rb").read()).hexdigest()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    seq, sha = extract(sys.argv[1])
    dst = sys.argv[2] if len(sys.argv) > 2 else "tb/ref_init.hex"
    with open(dst, "w", newline="\n") as f:
        for d, v in seq:
            f.write("%d%02X\n" % (d, v))
    print("%d bytes (%d commands) -> %s" % (len(seq), sum(1 for d, _ in seq if d == 0), dst))
    print("source sha256", sha)
