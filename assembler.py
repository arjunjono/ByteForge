#!/usr/bin/env python3
"""ByteForge assembler (Section 20 of the ByteForge architecture document).

Usage:
    python assembler.py program.asm
    python assembler.py program.asm --hex out.hex --lst out.lst

By default program.hex and program.lst are written next to the input file.

Outputs
    .hex  one four-digit hexadecimal word per line (for $readmemh), nothing else
    .lst  address, encoded word(s), source line number and source text

Exit status
    0  success
    1  the assembly source contains errors (nothing is written)
    2  usage or file error (unreadable input, unwritable output, ...)

Only the Python 3 standard library is used.
"""

import argparse
import os
import re
import sys

MAX_WORDS = 65536          # program memory size in 16-bit words
MAX_ADDRESS = 65535        # largest 16-bit address / jump target
MAX_IMMEDIATE = 255        # 8-bit immediate

# Instruction forms
F_RR = "two registers"             # MOV ADD SUB AND OR XOR CMP   (1 word)
F_RI = "register, immediate"       # LOADI                        (1 word)
F_RM = "register, [address]"      # LOAD STORE IN OUT            (2 words)
F_R = "one register"               # PUSH POP                     (1 word)
F_J = "jump target"                # JMP JZ JNZ                   (2 words)
F_N = "no operands"                # HALT                         (1 word)

# mnemonic -> (5-bit opcode from Section 8, form)
INSTRUCTIONS = {
    "LOAD":  (0b00000, F_RM),
    "STORE": (0b00001, F_RM),
    "MOV":   (0b00010, F_RR),
    "LOADI": (0b00011, F_RI),
    "ADD":   (0b00100, F_RR),
    "SUB":   (0b00101, F_RR),
    "AND":   (0b00110, F_RR),
    "OR":    (0b00111, F_RR),
    "XOR":   (0b01000, F_RR),
    "CMP":   (0b01001, F_RR),
    "JMP":   (0b01010, F_J),
    "JZ":    (0b01011, F_J),
    "JNZ":   (0b01100, F_J),
    "PUSH":  (0b01101, F_R),
    "POP":   (0b01110, F_R),
    "IN":    (0b01111, F_RM),
    "OUT":   (0b10000, F_RM),
    "HALT":  (0b10001, F_N),
}

OPERAND_COUNT = {F_RR: 2, F_RI: 2, F_RM: 2, F_R: 1, F_J: 1, F_N: 0}
WORD_COUNT = {F_RR: 1, F_RI: 1, F_RM: 2, F_R: 1, F_J: 2, F_N: 1}

_FLAGS = re.ASCII
_LABEL_DEF = re.compile(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*:", _FLAGS)
_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*", _FLAGS)
_MNEMONIC = re.compile(r"[A-Za-z_][A-Za-z0-9_]*", _FLAGS)
_DEC = re.compile(r"[0-9]+", _FLAGS)
_HEX = re.compile(r"0[xX][0-9A-Fa-f]+", _FLAGS)
_BIN = re.compile(r"0[bB][01]+", _FLAGS)
_REG = re.compile(r"[Rr]([0-3])", _FLAGS)
_BRACKET = re.compile(r"\[(.*)\]", _FLAGS | re.DOTALL)
_SPACE = re.compile(r"\s", _FLAGS)

_HUGE = 10 ** 12           # stands in for absurdly long decimal literals


class Diagnostic:
    """One error message tied to a source line (line 0 = whole file)."""

    def __init__(self, line, message):
        self.line = line
        self.message = message


class AssemblyFailed(Exception):
    """Raised by assemble() when the source has errors."""

    def __init__(self, diagnostics):
        Exception.__init__(self, "assembly failed")
        self.diagnostics = diagnostics


class _LineError(Exception):
    pass


class _Statement:
    """A parsed source line: optional label and optional instruction."""

    def __init__(self, line, text):
        self.line = line
        self.text = text               # source text without the comment
        self.label = None
        self.mnemonic = None           # upper-case, or None for label-only lines
        self.form = None
        self.operands = []             # parsed operands, see _parse_operand
        self.address = None            # word address of this line
        self.length = 0                # words emitted
        self.broken = False            # a syntax error was reported for this line


# ----------------------------------------------------------------------------
# Operand parsing
# ----------------------------------------------------------------------------

def parse_number(token):
    """Decimal, 0x hexadecimal or 0b binary literal -> int (no sign, no '_')."""
    if _HEX.fullmatch(token):
        return int(token[2:], 16)
    if _BIN.fullmatch(token):
        return int(token[2:], 2)
    if _DEC.fullmatch(token):
        if len(token.lstrip("0")) > 12:
            return _HUGE
        return int(token, 10)
    raise _LineError("malformed number '%s' (use decimal, 0x hexadecimal or "
                     "0b binary)" % token)


def _parse_register(token):
    m = _REG.fullmatch(token)
    if not m:
        raise _LineError("invalid register '%s' (valid registers are R0, R1, "
                         "R2, R3)" % token)
    return int(m.group(1))


def _parse_immediate(token):
    value = parse_number(token)
    if not 0 <= value <= MAX_IMMEDIATE:
        raise _LineError("immediate value %s is out of range (0-%d)"
                         % (token, MAX_IMMEDIATE))
    return value


def _check_address(token, value, what):
    if not 0 <= value <= MAX_ADDRESS:
        raise _LineError("%s %s is out of range (0-%d)"
                         % (what, token, MAX_ADDRESS))


def _parse_memory_operand(token):
    m = _BRACKET.fullmatch(token)
    if not m:
        raise _LineError("expected a numeric address in square brackets, "
                         "found '%s'" % token)
    inner = m.group(1).strip()
    if inner == "":
        raise _LineError("empty address brackets '[]'")
    if "[" in inner or "]" in inner:
        raise _LineError("malformed address '%s'" % token)
    value = parse_number(inner)
    _check_address(inner, value, "address")
    return value


def _parse_target(token):
    """Jump target: a number (checked now) or a label (resolved in pass 2)."""
    if token[:1] in "[":
        raise _LineError("jump target must be a number or a label, not '%s'"
                         % token)
    if token[:1].isdigit():
        value = parse_number(token)
        _check_address(token, value, "jump target")
        return ("num", value)
    if _IDENT.fullmatch(token):
        return ("label", token)
    raise _LineError("malformed jump target '%s' (expected a number or a "
                     "label name)" % token)


def _split_operands(rest):
    """Split the text after the mnemonic into comma separated operands."""
    rest = rest.strip()
    if rest == "":
        return []
    parts = [p.strip() for p in rest.split(",")]
    for p in parts:
        if p == "":
            raise _LineError("empty operand (missing operand or extra comma)")
    for p in parts:
        if _SPACE.search(p) and not _BRACKET.fullmatch(p):
            raise _LineError("operands must be separated by commas "
                             "(found '%s')" % p)
    return parts


def _parse_statement(line_no, raw):
    """Parse one source line. Raises _LineError on a syntax error."""
    code = raw.split(";", 1)[0].strip()
    st = _Statement(line_no, code)
    if code == "":
        return st

    body = code
    m = _LABEL_DEF.match(body)
    if m:
        st.label = m.group(1)
        body = body[m.end():].strip()
    elif ":" in body:
        raise _LineError("invalid label name before ':' (labels match "
                         "[A-Za-z_][A-Za-z0-9_]*)")
    if ":" in body:
        raise _LineError("unexpected ':' (only one label per line)")
    if body == "":
        return st

    m = _MNEMONIC.match(body)
    if not m:
        raise _LineError("expected an instruction, found '%s'" % body)
    name = m.group(0)
    rest = body[m.end():]
    if rest and not rest[0].isspace():
        raise _LineError("unexpected '%s' after '%s'" % (rest[0], name))
    mnemonic = name.upper()
    if mnemonic not in INSTRUCTIONS:
        hint = " (a label needs a trailing ':')" if rest.strip() == "" else ""
        raise _LineError("unknown instruction '%s'%s" % (name, hint))

    st.mnemonic = mnemonic
    st.form = INSTRUCTIONS[mnemonic][1]
    st.length = WORD_COUNT[st.form]

    tokens = _split_operands(rest)
    want = OPERAND_COUNT[st.form]
    if len(tokens) != want:
        if want == 0:
            raise _LineError("%s takes no operands, found %d"
                             % (mnemonic, len(tokens)))
        raise _LineError("%s expects %d operand%s (%s), found %d"
                         % (mnemonic, want, "" if want == 1 else "s",
                            st.form, len(tokens)))

    form = st.form
    if form == F_RR:
        st.operands = [_parse_register(tokens[0]), _parse_register(tokens[1])]
    elif form == F_RI:
        st.operands = [_parse_register(tokens[0]), _parse_immediate(tokens[1])]
    elif form == F_RM:
        st.operands = [_parse_register(tokens[0]),
                       _parse_memory_operand(tokens[1])]
    elif form == F_R:
        st.operands = [_parse_register(tokens[0])]
    elif form == F_J:
        st.operands = [_parse_target(tokens[0])]
    return st


# ----------------------------------------------------------------------------
# Encoding
# ----------------------------------------------------------------------------

def _encode(st, labels):
    """Return the list of 16-bit words for a parsed statement."""
    opcode = INSTRUCTIONS[st.mnemonic][0]
    first = opcode << 11
    form = st.form
    if form == F_RR:
        a, b = st.operands
        return [first | (a << 9) | (b << 7)]
    if form == F_RI:
        a, imm = st.operands
        return [first | (a << 9) | (imm << 1)]
    if form == F_RM:
        a, addr = st.operands
        return [first | (a << 9), addr]
    if form == F_R:
        return [first | (st.operands[0] << 9)]
    if form == F_J:
        kind, value = st.operands[0]
        target = value if kind == "num" else labels[value]
        return [first, target]
    return [first]                                     # HALT


# ----------------------------------------------------------------------------
# Assembler core
# ----------------------------------------------------------------------------

def assemble(source):
    """Assemble source text.

    Returns (words, rows): words is the list of 16-bit program words and rows
    is a list of (address_or_None, [words], line_number, text) for the listing.
    Raises AssemblyFailed (with .diagnostics) if there are any errors.
    """
    diagnostics = []
    statements = []

    # ---- pass 1: parse, record label addresses, count words -----------------
    labels = {}
    label_lines = {}
    address = 0
    overflow_reported = False
    lines = source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    for line_no, raw in enumerate(lines, 1):
        try:
            st = _parse_statement(line_no, raw)
        except _LineError as exc:
            diagnostics.append(Diagnostic(line_no, str(exc)))
            # keep address counting sensible: use the mnemonic's length if known
            st = _Statement(line_no, raw.split(";", 1)[0].strip())
            st.broken = True
            m = _LABEL_DEF.match(st.text)
            body = st.text[m.end():].strip() if m else st.text
            if m:
                st.label = m.group(1)
            mm = _MNEMONIC.match(body)
            if mm and mm.group(0).upper() in INSTRUCTIONS:
                st.length = WORD_COUNT[INSTRUCTIONS[mm.group(0).upper()][1]]
        if st.label is not None:
            if st.label in labels:
                diagnostics.append(Diagnostic(
                    line_no, "duplicate label '%s' (first defined on line %d)"
                    % (st.label, label_lines[st.label])))
            else:
                labels[st.label] = address
                label_lines[st.label] = line_no
                if address > MAX_ADDRESS:
                    diagnostics.append(Diagnostic(
                        line_no, "label '%s' is at address %d, outside the "
                        "valid range 0-%d" % (st.label, address, MAX_ADDRESS)))
        st.address = address
        if st.length and address + st.length > MAX_WORDS and not overflow_reported:
            diagnostics.append(Diagnostic(
                line_no, "program is longer than %d words" % MAX_WORDS))
            overflow_reported = True
        address += st.length
        statements.append(st)

    if address == 0 and not diagnostics:
        diagnostics.append(Diagnostic(0, "the program contains no instructions"))

    # ---- pass 2: resolve labels and encode ---------------------------------
    for st in statements:
        if st.broken or st.mnemonic is None or st.form != F_J:
            continue
        kind, value = st.operands[0]
        if kind == "label" and value not in labels:
            diagnostics.append(Diagnostic(st.line, "undefined label '%s'" % value))

    if diagnostics:
        diagnostics.sort(key=lambda d: d.line)
        raise AssemblyFailed(diagnostics)

    words = []
    rows = []
    for st in statements:
        if st.mnemonic is None:
            if st.label is not None:
                rows.append((st.address, [], st.line, st.text))
            continue
        encoded = _encode(st, labels)
        words.extend(encoded)
        rows.append((st.address, encoded, st.line, st.text))
    return words, rows


def format_hex(words):
    """One four-digit upper-case hexadecimal word per line."""
    return "".join("%04X\n" % w for w in words)


def format_listing(rows, source_name):
    out = ["; ByteForge listing for %s\n" % source_name,
           "; ADDR  WORD1 WORD2  LINE  SOURCE\n"]
    for address, encoded, line_no, text in rows:
        w1 = "%04X" % encoded[0] if len(encoded) > 0 else "    "
        w2 = "%04X" % encoded[1] if len(encoded) > 1 else "    "
        out.append("%04X   %s  %s  %5d  %s\n" % (address, w1, w2, line_no, text))
    return "".join(out)


# ----------------------------------------------------------------------------
# Command line
# ----------------------------------------------------------------------------

def _write_outputs(outputs):
    """Write [(path, text), ...] through temporary files, then rename them."""
    temps = []
    try:
        for path, text in outputs:
            tmp = "%s.tmp-%d" % (path, os.getpid())
            with open(tmp, "x", encoding="utf-8", newline="\n") as handle:
                temps.append((tmp, path))
                handle.write(text)
        while temps:
            tmp, path = temps[0]
            os.replace(tmp, path)
            temps.pop(0)
    finally:
        for tmp, _ in temps:
            try:
                os.remove(tmp)
            except OSError:
                pass


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="assembler.py",
        description="ByteForge assembler: program.asm -> program.hex + program.lst")
    parser.add_argument("source", help="assembly source file")
    parser.add_argument("--hex", dest="hex_path", metavar="FILE",
                        help="hex output file (default: next to the source)")
    parser.add_argument("--lst", dest="lst_path", metavar="FILE",
                        help="listing output file (default: next to the source)")
    args = parser.parse_args(argv)

    src = args.source
    base = os.path.splitext(src)[0]
    hex_path = args.hex_path or base + ".hex"
    lst_path = args.lst_path or base + ".lst"

    try:
        with open(src, "r", encoding="utf-8-sig") as handle:
            text = handle.read()
    except FileNotFoundError:
        sys.stderr.write("%s: error: file not found\n" % src)
        return 2
    except IsADirectoryError:
        sys.stderr.write("%s: error: is a directory, not a source file\n" % src)
        return 2
    except UnicodeDecodeError:
        sys.stderr.write("%s: error: file is not valid UTF-8 text\n" % src)
        return 2
    except OSError as exc:
        sys.stderr.write("%s: error: cannot read file (%s)\n"
                         % (src, exc.strerror or exc))
        return 2

    same = [p for p in (hex_path, lst_path)
            if os.path.abspath(p) == os.path.abspath(src)]
    if same or os.path.abspath(hex_path) == os.path.abspath(lst_path):
        sys.stderr.write("error: output files must differ from each other "
                         "and from the source file\n")
        return 2

    try:
        words, rows = assemble(text)
    except AssemblyFailed as failure:
        for d in failure.diagnostics:
            if d.line:
                sys.stderr.write("%s:%d: error: %s\n" % (src, d.line, d.message))
            else:
                sys.stderr.write("%s: error: %s\n" % (src, d.message))
        count = len(failure.diagnostics)
        sys.stderr.write("%s: assembly failed with %d error%s; no output "
                         "written\n" % (src, count, "" if count == 1 else "s"))
        return 1

    try:
        _write_outputs([(hex_path, format_hex(words)),
                        (lst_path, format_listing(rows, os.path.basename(src)))])
    except OSError as exc:
        sys.stderr.write("error: cannot write output (%s%s)\n"
                         % (exc.strerror or exc,
                            ": " + exc.filename if exc.filename else ""))
        return 2

    sys.stdout.write("%s: %d words -> %s, %s\n" % (src, len(words),
                                                    hex_path, lst_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
