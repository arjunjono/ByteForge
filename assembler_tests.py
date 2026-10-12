#!/usr/bin/env python3
"""Tests for assembler.py (ByteForge Section 20).

Run:  python assembler_tests.py            (or: python -m unittest assembler_tests -v)

Every expected machine-code word below is a constant written out from the
encoding rules of Sections 8 and 15 (opcode in bits 15-11, register A in bits
10-9, register B in bits 8-7, immediate in bits 8-1). The tests never call the
assembler's own encoding code to produce an expected value.
"""

import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ASSEMBLER = os.path.join(HERE, "assembler.py")
sys.path.insert(0, HERE)

import assembler  # noqa: E402  (imported only for assemble() / AssemblyFailed)

# ---------------------------------------------------------------------------
# Independent encoding constants
# ---------------------------------------------------------------------------
# opcode << 11, written out as literals
BASE = {
    "LOAD": 0x0000, "STORE": 0x0800, "MOV": 0x1000, "LOADI": 0x1800,
    "ADD": 0x2000, "SUB": 0x2800, "AND": 0x3000, "OR": 0x3800,
    "XOR": 0x4000, "CMP": 0x4800, "JMP": 0x5000, "JZ": 0x5800,
    "JNZ": 0x6000, "PUSH": 0x6800, "POP": 0x7000, "IN": 0x7800,
    "OUT": 0x8000, "HALT": 0x8800,
}
REG_A = (0x0000, 0x0200, 0x0400, 0x0600)     # R0..R3 in bits 10-9
REG_B = (0x0000, 0x0080, 0x0100, 0x0180)     # R0..R3 in bits 8-7

TWO_REG = ("MOV", "ADD", "SUB", "AND", "OR", "XOR", "CMP")
MEM_OPS = ("LOAD", "STORE", "IN", "OUT")
JUMPS = ("JMP", "JZ", "JNZ")

# One hand-worked example of every one of the 18 instructions
ALL_18 = [
    ("LOAD R1, [0x2000]",   [0x0200, 0x2000]),
    ("STORE R0, [0x0200]",  [0x0800, 0x0200]),
    ("MOV R1, R0",          [0x1200]),
    ("LOADI R0, 25",        [0x1832]),
    ("ADD R0, R1",          [0x2080]),
    ("SUB R2, R1",          [0x2C80]),
    ("AND R1, R1",          [0x3280]),
    ("OR R3, R0",           [0x3E00]),
    ("XOR R2, R3",          [0x4580]),
    ("CMP R3, R2",          [0x4F00]),
    ("JMP 0",               [0x5000, 0x0000]),
    ("JZ 0xFFFF",           [0x5800, 0xFFFF]),
    ("JNZ 0b101",           [0x6000, 0x0005]),
    ("PUSH R3",             [0x6E00]),
    ("POP R3",              [0x7600]),
    ("IN R2, [255]",        [0x7C00, 0x00FF]),
    ("OUT R1, [65535]",     [0x8200, 0xFFFF]),
    ("HALT",                [0x8800]),
]

SECTION20_EXAMPLE = """\
LOADI R0, 3
LOADI R1, 1
loop:
SUB R0, R1
JNZ loop
HALT
"""
SECTION20_WORDS = [0x1806, 0x1A02, 0x2880, 0x6000, 0x0002, 0x8800]

# Hand-worked machine code of the three demonstration programs
ARITHMETIC_WORDS = [0x1990, 0x1AC8, 0x1400, 0x2480, 0x1680, 0x2E00, 0x19E0,
                    0x1A78, 0x3080, 0x3880, 0x4080, 0x4C80, 0x8800]
COUNTDOWN_WORDS = [0x180A, 0x1A02, 0x1C00, 0x1E00, 0x2400, 0x2680, 0x2880,
                   0x6000, 0x0004, 0x8800]
MEMORY_STACK_WORDS = [0x1E88, 0x0E00, 0x0200, 0x1E00, 0x0600, 0x0200, 0x1822,
                      0x1A44, 0x1C66, 0x6800, 0x6A00, 0x6C00, 0x7000, 0x7200,
                      0x7400, 0x8800]


def asm(source):
    """Assemble text with the library entry point; returns the word list."""
    words, _rows = assembler.assemble(source)
    return words


def asm_errors(source):
    """Assemble text that must fail; returns [(line, message), ...]."""
    try:
        assembler.assemble(source)
    except assembler.AssemblyFailed as failure:
        return [(d.line, d.message) for d in failure.diagnostics]
    raise AssertionError("assembly unexpectedly succeeded:\n" + source)


def run_cli(args, cwd=None):
    return subprocess.run([sys.executable, ASSEMBLER] + list(args), cwd=cwd,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True)


# ---------------------------------------------------------------------------
class EncodingTests(unittest.TestCase):

    def test_all_18_instructions_have_a_hand_worked_example(self):
        self.assertEqual(sorted(s.split()[0] for s, _ in ALL_18),
                         sorted(BASE))
        self.assertEqual(len(ALL_18), 18)

    def test_each_of_the_18_instructions(self):
        for source, expected in ALL_18:
            with self.subTest(source):
                self.assertEqual(asm(source), expected)

    def test_section_20_example(self):
        self.assertEqual(asm(SECTION20_EXAMPLE), SECTION20_WORDS)

    def test_two_register_instructions_all_combinations(self):
        for op in TWO_REG:
            for a in range(4):
                for b in range(4):
                    with self.subTest("%s R%d,R%d" % (op, a, b)):
                        words = asm("%s R%d, R%d" % (op, a, b))
                        self.assertEqual(words, [BASE[op] + REG_A[a] + REG_B[b]])
                        self.assertEqual(words[0] & 0x007F, 0)   # reserved bits

    def test_loadi_all_registers_and_boundary_immediates(self):
        for r in range(4):
            for imm in (0, 1, 2, 127, 128, 254, 255):
                with self.subTest("LOADI R%d,%d" % (r, imm)):
                    words = asm("LOADI R%d, %d" % (r, imm))
                    self.assertEqual(words, [BASE["LOADI"] + REG_A[r] + imm * 2])
                    self.assertEqual(words[0] & 0x0001, 0)       # reserved bit

    def test_loadi_literal_extremes(self):
        self.assertEqual(asm("LOADI R0, 0"), [0x1800])
        self.assertEqual(asm("LOADI R0, 255"), [0x19FE])
        self.assertEqual(asm("LOADI R3, 255"), [0x1FFE])
        self.assertEqual(asm("LOADI R3, 0"), [0x1E00])

    def test_memory_instructions_all_registers_and_addresses(self):
        addresses = (0, 1, 0x00FF, 0x0100, 0x1234, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF)
        for op in MEM_OPS:
            for r in range(4):
                for addr in addresses:
                    with self.subTest("%s R%d,[%d]" % (op, r, addr)):
                        words = asm("%s R%d, [%d]" % (op, r, addr))
                        self.assertEqual(words, [BASE[op] + REG_A[r], addr])
                        self.assertEqual(words[0] & 0x01FF, 0)   # reserved bits

    def test_push_pop_all_registers(self):
        for op in ("PUSH", "POP"):
            for r in range(4):
                with self.subTest("%s R%d" % (op, r)):
                    words = asm("%s R%d" % (op, r))
                    self.assertEqual(words, [BASE[op] + REG_A[r]])
                    self.assertEqual(words[0] & 0x01FF, 0)

    def test_jumps_numeric_targets(self):
        for op in JUMPS:
            for target in (0, 1, 0x00FF, 0x0100, 0x8000, 0xFFFF):
                with self.subTest("%s %d" % (op, target)):
                    words = asm("%s %d" % (op, target))
                    self.assertEqual(words, [BASE[op], target])
                    self.assertEqual(words[0] & 0x07FF, 0)

    def test_halt(self):
        self.assertEqual(asm("HALT"), [0x8800])
        self.assertEqual(asm("HALT")[0] & 0x07FF, 0)

    def test_number_formats(self):
        same = ["LOADI R0, 10", "LOADI R0, 0xA", "LOADI R0, 0xa",
                "LOADI R0, 0XA", "LOADI R0, 0b1010", "LOADI R0, 0B1010"]
        for source in same:
            with self.subTest(source):
                self.assertEqual(asm(source), [0x1814])
        self.assertEqual(asm("LOADI R1, 0xFF"), [0x1BFE])
        self.assertEqual(asm("LOADI R1, 0b11111111"), [0x1BFE])
        self.assertEqual(asm("LOAD R0, [0x1F4]"), [0x0000, 0x01F4])
        self.assertEqual(asm("LOAD R0, [500]"), [0x0000, 0x01F4])
        self.assertEqual(asm("LOAD R0, [0b111110100]"), [0x0000, 0x01F4])
        self.assertEqual(asm("JMP 0x10"), [0x5000, 0x0010])
        self.assertEqual(asm("JMP 0b10000"), [0x5000, 0x0010])

    def test_spaces_and_tabs_around_operands(self):
        self.assertEqual(asm("  \tADD\tR0 ,\t R1  "), [0x2080])
        self.assertEqual(asm("LOAD R0 , [ 0x10 ]"), [0x0000, 0x0010])
        self.assertEqual(asm("LOAD R0,[0x10]"), [0x0000, 0x0010])
        self.assertEqual(asm("LOADI R2,7"), [0x1C0E])


class CaseAndLayoutTests(unittest.TestCase):

    def test_instructions_and_registers_are_case_insensitive(self):
        self.assertEqual(asm("add r0, R1"), [0x2080])
        self.assertEqual(asm("Add R0, r1"), [0x2080])
        self.assertEqual(asm("loadi r3, 0xff"), [0x1FFE])
        self.assertEqual(asm("LoAd r1, [0x2000]"), [0x0200, 0x2000])
        self.assertEqual(asm("halt"), [0x8800])
        self.assertEqual(asm("pUsH r2"), [0x6C00])

    def test_labels_are_case_sensitive(self):
        # two labels that differ only in case are two labels
        words = asm("a:\nA: HALT\nJMP a\nJMP A")
        self.assertEqual(words, [0x8800, 0x5000, 0x0000, 0x5000, 0x0000])
        # a reference with the wrong case is undefined
        errors = asm_errors("Loop:\nHALT\nJMP loop")
        self.assertEqual([line for line, _ in errors], [3])
        self.assertIn("undefined label", errors[0][1])

    def test_blank_lines_and_comments(self):
        source = ("; whole line comment\n"
                  "\n"
                  "   \t  \n"
                  "LOADI R0, 1   ; trailing comment\n"
                  ";LOADI R1, 2\n"
                  "HALT ; done ; more ; text\n"
                  "; final comment, no newline")
        self.assertEqual(asm(source), [0x1802, 0x8800])

    def test_semicolon_starts_a_comment_everywhere(self):
        self.assertEqual(asm("HALT;no space"), [0x8800])
        self.assertEqual(asm("lab: ; only a label\nHALT\nJMP lab"),
                         [0x8800, 0x5000, 0x0000])

    def test_crlf_and_lone_cr_line_endings(self):
        self.assertEqual(asm("LOADI R0, 3\r\nHALT\r\n"), [0x1806, 0x8800])
        self.assertEqual(asm("LOADI R0, 3\rHALT\r"), [0x1806, 0x8800])
        errors = asm_errors("HALT\r\nBAD\r\nHALT\r\n")
        self.assertEqual([line for line, _ in errors], [2])


class LabelTests(unittest.TestCase):

    def test_backward_label(self):
        words = asm("start: HALT\nJMP start")
        self.assertEqual(words, [0x8800, 0x5000, 0x0000])

    def test_forward_label(self):
        words = asm("JMP end\nHALT\nend: HALT")
        # JMP occupies addresses 0-1, first HALT is 2, 'end' is 3
        self.assertEqual(words, [0x5000, 0x0003, 0x8800, 0x8800])

    def test_label_after_two_word_instructions(self):
        source = ("LOAD R0, [0x10]\n"       # 0,1
                  "STORE R0, [0x11]\n"      # 2,3
                  "JMP skip\n"              # 4,5
                  "IN R1, [0x12]\n"         # 6,7
                  "skip: OUT R1, [0x13]\n"  # 8,9
                  "after: HALT\n"           # 10
                  "JNZ after\n"             # 11,12
                  "JZ skip")                # 13,14
        words = asm(source)
        self.assertEqual(words, [0x0000, 0x0010, 0x0800 + 0, 0x0011,
                                 0x5000, 0x0008, 0x7A00, 0x0012,
                                 0x8200, 0x0013, 0x8800, 0x6000, 0x000A,
                                 0x5800, 0x0008])

    def test_label_alone_and_label_before_instruction(self):
        a = asm("x:\nHALT\nJMP x")
        b = asm("x: HALT\nJMP x")
        self.assertEqual(a, b)
        self.assertEqual(a, [0x8800, 0x5000, 0x0000])

    def test_several_labels_on_consecutive_lines_share_an_address(self):
        words = asm("a:\nb:\nHALT\nJMP a\nJMP b")
        self.assertEqual(words, [0x8800, 0x5000, 0x0000, 0x5000, 0x0000])

    def test_label_at_address_zero_and_at_end_of_program(self):
        self.assertEqual(asm("top: JMP end\nend:"), [0x5000, 0x0002])
        self.assertEqual(asm("top: HALT\nJMP top")[2], 0x0000)

    def test_label_names(self):
        words = asm("_a1:\nHALT\nAbC_9: HALT\nJMP _a1\nJMP AbC_9")
        self.assertEqual(words, [0x8800, 0x8800, 0x5000, 0x0000,
                                 0x5000, 0x0001])

    def test_label_can_be_defined_after_use_and_used_twice(self):
        words = asm("JMP e\nJZ e\nJNZ e\ne: HALT")
        self.assertEqual(words, [0x5000, 0x0006, 0x5800, 0x0006,
                                 0x6000, 0x0006, 0x8800])

    def test_listing_addresses_count_second_words(self):
        _words, rows = assembler.assemble("LOAD R0, [1]\nHALT\nJMP 0\nHALT")
        self.assertEqual([r[0] for r in rows], [0, 2, 3, 5])
        self.assertEqual([r[2] for r in rows], [1, 2, 3, 4])


class ErrorTests(unittest.TestCase):

    def check(self, source, line, keyword):
        errors = asm_errors(source)
        self.assertIn(line, [e[0] for e in errors], errors)
        message = [m for ln, m in errors if ln == line][0]
        self.assertIn(keyword, message.lower(), message)

    def test_unknown_instructions(self):
        for source in ("NOP", "ADDD R0, R1", "MOVE R0, R1", "LOAD2 R0, [1]",
                       "ret", "CALL 5"):
            with self.subTest(source):
                self.check("HALT\n" + source, 2, "unknown instruction")

    def test_bare_word_hints_at_missing_colon(self):
        self.check("loop\nHALT", 1, "unknown instruction")

    def test_invalid_registers(self):
        for source in ("MOV R4, R0", "MOV R0, R4", "MOV R0, 5", "PUSH R",
                       "PUSH R10", "PUSH RR1", "POP r-1", "LOADI R9, 1",
                       "LOAD R4, [1]", "ADD R0, [R1]", "PUSH 0",
                       "ADD R0, label"):
            with self.subTest(source):
                self.check("HALT\n" + source, 2, "invalid register")

    def test_wrong_operand_counts(self):
        cases = [("ADD R0", "expects 2"), ("ADD R0, R1, R2", "expects 2"),
                 ("MOV R0", "expects 2"), ("LOADI R0", "expects 2"),
                 ("LOADI R0, 1, 2", "expects 2"), ("LOAD R0", "expects 2"),
                 ("STORE R0, [1], R1", "expects 2"),
                 ("PUSH", "expects 1"), ("PUSH R0, R1", "expects 1"),
                 ("POP", "expects 1"), ("JMP", "expects 1"),
                 ("JZ 1, 2", "expects 1"), ("JNZ", "expects 1"),
                 ("HALT R0", "no operands"), ("HALT 1", "no operands")]
        for source, keyword in cases:
            with self.subTest(source):
                self.check("HALT\n" + source, 2, keyword)

    def test_malformed_numbers(self):
        cases = ["LOADI R0, 0x", "LOADI R0, 0b", "LOADI R0, 0b2",
                 "LOADI R0, 12abc", "LOADI R0, -1", "LOADI R0, +5",
                 "LOADI R0, 1_0", "LOADI R0, 0xG1", "LOADI R0, 1.5",
                 "LOADI R0, abc", "LOADI R0, R1", "LOAD R0, [abc]",
                 "LOAD R0, [-1]", "LOAD R0, [0x]", "LOAD R0, [R1]",
                 "JMP 12x", "JMP 0xZZ", "JMP -3", "JZ 1.5", "JNZ 0b12"]
        for source in cases:
            with self.subTest(source):
                self.check("HALT\n" + source, 2, "malformed")

    def test_missing_or_extra_commas(self):
        cases = [("ADD R0 R1", "comma"), ("LOADI R0 5", "comma"),
                 ("LOAD R0 [0x10]", "comma"), ("ADD R0,, R1", "comma"),
                 ("ADD R0, R1,", "comma"), ("ADD ,R0, R1", "comma"),
                 ("PUSH R0,", "comma"), ("ADD,R0,R1", "unexpected ','"),
                 ("LOAD R0,", "comma"), ("JMP 1,", "comma")]
        for source, keyword in cases:
            with self.subTest(source):
                self.check("HALT\n" + source, 2, keyword)

    def test_bracket_errors(self):
        cases = ["LOAD R0, 0x10", "LOAD R0, [0x10", "LOAD R0, 0x10]",
                 "STORE R0, []", "IN R0, [ ]", "OUT R0, [[1]]",
                 "LOAD R0, R1", "LOAD R0, [1][2]", "JMP [5]"]
        for source in cases:
            with self.subTest(source):
                errors = asm_errors("HALT\n" + source)
                self.assertEqual([ln for ln, _ in errors], [2])

    def test_register_operand_where_address_expected_and_vice_versa(self):
        errors = asm_errors("STORE [0x10], R0")
        self.assertEqual([ln for ln, _ in errors], [1])

    def test_duplicate_labels(self):
        errors = asm_errors("a:\nHALT\na:\nHALT")
        self.assertEqual([ln for ln, _ in errors], [3])
        self.assertIn("duplicate label", errors[0][1])
        self.assertIn("line 1", errors[0][1])
        errors = asm_errors("a: HALT\na: HALT")
        self.assertEqual([ln for ln, _ in errors], [2])
        errors = asm_errors("a: a: HALT")
        self.assertEqual([ln for ln, _ in errors], [1])

    def test_undefined_labels(self):
        errors = asm_errors("HALT\nJMP nowhere\nJZ also_missing")
        self.assertEqual([ln for ln, _ in errors], [2, 3])
        self.assertTrue(all("undefined label" in m for _, m in errors))

    def test_invalid_label_names(self):
        for source in ("1abc: HALT", "a-b: HALT", ": HALT", "lab el: HALT",
                       "a.b: HALT", "9:", "%x:"):
            with self.subTest(source):
                errors = asm_errors("HALT\n" + source)
                self.assertEqual([ln for ln, _ in errors], [2])

    def test_stray_colon(self):
        for source in ("a: b: HALT", "HALT HALT:", "ADD R0:, R1", "JMP x:"):
            with self.subTest(source):
                errors = asm_errors("HALT\n" + source)
                self.assertTrue(errors and errors[0][0] == 2, errors)

    def test_out_of_range_immediates(self):
        for source in ("LOADI R0, 256", "LOADI R0, 0x100", "LOADI R0, 1000",
                       "LOADI R0, 0b100000000", "LOADI R0, 65535",
                       "LOADI R0, 99999999999999999999999",
                       "LOADI R0, " + "9" * 5000,
                       "LOADI R0, 0x" + "F" * 40):
            with self.subTest(source[:30]):
                self.check("HALT\n" + source, 2, "out of range")

    def test_out_of_range_addresses_and_targets(self):
        for source in ("LOAD R0, [65536]", "STORE R0, [0x10000]",
                       "IN R0, [100000]", "OUT R0, [0b10000000000000000]",
                       "JMP 65536", "JZ 0x10000", "JNZ 99999999999"):
            with self.subTest(source):
                self.check("HALT\n" + source, 2, "out of range")

    def test_values_are_never_truncated(self):
        # 256 would wrap to 0 and 65536 would wrap to 0 if truncated
        asm_errors("LOADI R0, 256")
        asm_errors("LOAD R0, [65536]")
        asm_errors("JMP 65536")

    def test_all_errors_are_reported_with_correct_line_numbers(self):
        source = ("ADD R0 R1\n"          # 1 comma
                  "LOADI R4, 5\n"        # 2 register
                  "JMP nowhere\n"        # 3 undefined
                  "LOADI R0, 256\n"      # 4 range
                  "foo\n"                # 5 unknown
                  "LOAD R0, [65536]\n"   # 6 range
                  "HALT R1\n"            # 7 operands
                  "x: x: HALT\n"         # 8 stray colon
                  "ADD R0,\n")           # 9 comma
        errors = asm_errors(source)
        self.assertEqual([ln for ln, _ in errors], [1, 2, 3, 4, 5, 6, 7, 8, 9])

    def test_empty_program_is_rejected(self):
        for source in ("", "\n\n", "; just a comment\n", "only_label:\n"):
            with self.subTest(repr(source)):
                errors = asm_errors(source)
                self.assertIn("no instructions", errors[0][1])

    def test_non_ascii_text_is_an_error_not_a_crash(self):
        asm_errors("LOADI R0, \u0663")
        asm_errors("HALT\n\u00e9tiquette: HALT")


class OverflowTests(unittest.TestCase):

    def test_exactly_65536_words_is_accepted(self):
        words = asm("HALT\n" * 65536)
        self.assertEqual(len(words), 65536)

    def test_65537_words_is_rejected(self):
        errors = asm_errors("HALT\n" * 65537)
        self.assertEqual(len(errors), 1)
        self.assertEqual(errors[0][0], 65537)
        self.assertIn("65536", errors[0][1])

    def test_two_word_instruction_straddling_the_limit(self):
        self.assertEqual(len(asm("HALT\n" * 65534 + "JMP 0\n")), 65536)
        errors = asm_errors("HALT\n" * 65535 + "JMP 0\n")
        self.assertEqual(errors[0][0], 65536)

    def test_label_at_last_valid_address(self):
        source = "JMP last\n" + "HALT\n" * 65533 + "last: HALT\n"
        words = asm(source)
        self.assertEqual(len(words), 65536)
        self.assertEqual(words[1], 0xFFFF)

    def test_label_outside_valid_range(self):
        errors = asm_errors("HALT\n" * 65536 + "end:\n")
        self.assertEqual(errors[0][0], 65537)
        self.assertIn("outside", errors[0][1])


class ListingTests(unittest.TestCase):

    def test_hex_text_format(self):
        words = asm(SECTION20_EXAMPLE)
        text = assembler.format_hex(words)
        self.assertEqual(text, "1806\n1A02\n2880\n6000\n0002\n8800\n")

    def test_listing_text(self):
        source = "LOADI R0, 3\nLOADI R1, 1\nloop:\nSUB R0, R1\nJNZ loop\nHALT\n"
        _words, rows = assembler.assemble(source)
        text = assembler.format_listing(rows, "t1.asm")
        expected = (
            "; ByteForge listing for t1.asm\n"
            "; ADDR  WORD1 WORD2  LINE  SOURCE\n"
            "0000   1806            1  LOADI R0, 3\n"
            "0001   1A02            2  LOADI R1, 1\n"
            "0002                   3  loop:\n"
            "0002   2880            4  SUB R0, R1\n"
            "0003   6000  0002      5  JNZ loop\n"
            "0005   8800            6  HALT\n")
        self.assertEqual(text, expected)

    def test_listing_shows_source_without_comment(self):
        _w, rows = assembler.assemble("  ADD   R0 ,R1   ; add them\n")
        self.assertEqual(rows[0][3], "ADD   R0 ,R1")
        self.assertEqual(rows[0][2], 1)

    def test_listing_keeps_original_line_numbers_across_blank_lines(self):
        _w, rows = assembler.assemble("\n\n; c\nHALT\n\nHALT\n")
        self.assertEqual([r[2] for r in rows], [4, 6])


class DemoProgramTests(unittest.TestCase):

    def assemble_demo(self, name):
        path = os.path.join(HERE, name)
        if not os.path.exists(path):
            self.skipTest("%s not found next to the tests" % name)
        with open(path, encoding="utf-8") as handle:
            return asm(handle.read())

    def test_arithmetic(self):
        self.assertEqual(self.assemble_demo("arithmetic.asm"), ARITHMETIC_WORDS)

    def test_countdown(self):
        self.assertEqual(self.assemble_demo("countdown.asm"), COUNTDOWN_WORDS)

    def test_memory_stack(self):
        self.assertEqual(self.assemble_demo("memory_stack.asm"),
                         MEMORY_STACK_WORDS)

    def test_delivered_hex_files_match(self):
        for name, words in (("arithmetic", ARITHMETIC_WORDS),
                            ("countdown", COUNTDOWN_WORDS),
                            ("memory_stack", MEMORY_STACK_WORDS)):
            path = os.path.join(HERE, name + ".hex")
            if not os.path.exists(path):
                continue
            with self.subTest(name):
                with open(path, encoding="ascii") as handle:
                    text = handle.read()
                self.assertEqual(text, "".join("%04X\n" % w for w in words))

    def test_every_demo_program_ends_with_halt(self):
        for words in (ARITHMETIC_WORDS, COUNTDOWN_WORDS, MEMORY_STACK_WORDS):
            self.assertEqual(words[-1], 0x8800)


class CommandLineTests(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = self._tmp.name
        self.other_cwd = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.addCleanup(self.other_cwd.cleanup)

    def write(self, name, text, binary=False):
        path = os.path.join(self.dir, name)
        with open(path, "wb" if binary else "w") as handle:
            handle.write(text)
        return path

    def read(self, name):
        with open(os.path.join(self.dir, name)) as handle:
            return handle.read()

    def files(self):
        return sorted(os.listdir(self.dir))

    def test_success_creates_hex_and_lst_next_to_the_input(self):
        src = self.write("prog.asm", SECTION20_EXAMPLE)
        result = run_cli([src], cwd=self.other_cwd.name)   # cwd is elsewhere
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.files(), ["prog.asm", "prog.hex", "prog.lst"])
        self.assertEqual(self.read("prog.hex"),
                         "1806\n1A02\n2880\n6000\n0002\n8800\n")
        lst = self.read("prog.lst")
        self.assertIn("0003   6000  0002      5  JNZ loop", lst)
        self.assertEqual(result.stderr, "")
        self.assertEqual(os.listdir(self.other_cwd.name), [])

    def test_hex_file_has_only_four_digit_words(self):
        src = self.write("prog.asm", SECTION20_EXAMPLE)
        self.assertEqual(run_cli([src]).returncode, 0)
        for line in self.read("prog.hex").split("\n")[:-1]:
            self.assertRegex(line, r"^[0-9A-F]{4}$")
        self.assertTrue(self.read("prog.hex").endswith("\n"))

    def test_source_without_extension_and_dotted_names(self):
        src = self.write("prog", "HALT\n")
        self.assertEqual(run_cli([src]).returncode, 0)
        self.assertIn("prog.hex", self.files())
        src = self.write("my.prog.asm", "HALT\n")
        self.assertEqual(run_cli([src]).returncode, 0)
        self.assertIn("my.prog.hex", self.files())

    def test_explicit_output_paths(self):
        src = self.write("prog.asm", "HALT\n")
        out_hex = os.path.join(self.dir, "a.hex")
        out_lst = os.path.join(self.dir, "b.txt")
        result = run_cli([src, "--hex", out_hex, "--lst", out_lst])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.files(), ["a.hex", "b.txt", "prog.asm"])
        self.assertEqual(self.read("a.hex"), "8800\n")

    def test_success_overwrites_old_output_and_leaves_no_temp_files(self):
        src = self.write("prog.asm", "HALT\n")
        self.write("prog.hex", "OLD\n")
        self.write("prog.lst", "OLD\n")
        self.assertEqual(run_cli([src]).returncode, 0)
        self.assertEqual(self.read("prog.hex"), "8800\n")
        self.assertEqual(self.files(), ["prog.asm", "prog.hex", "prog.lst"])

    def test_assembly_error_returns_nonzero_and_writes_nothing(self):
        src = self.write("bad.asm", "HALT\nFOO R0\nHALT\n")
        result = run_cli([src])
        self.assertEqual(result.returncode, 1)
        self.assertIn("bad.asm:2: error:", result.stderr)
        self.assertIn("unknown instruction", result.stderr)
        self.assertEqual(self.files(), ["bad.asm"])
        self.assertEqual(result.stdout, "")

    def test_assembly_error_preserves_existing_good_output(self):
        good = self.write("prog.asm", "HALT\n")
        self.assertEqual(run_cli([good]).returncode, 0)
        hex_before, lst_before = self.read("prog.hex"), self.read("prog.lst")
        self.write("prog.asm", "HALT\nBROKEN\n")
        result = run_cli([os.path.join(self.dir, "prog.asm")])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.read("prog.hex"), hex_before)
        self.assertEqual(self.read("prog.lst"), lst_before)
        self.assertEqual(self.files(), ["prog.asm", "prog.hex", "prog.lst"])

    def test_every_error_is_printed_with_its_line_number(self):
        src = self.write("bad.asm", "ADD R0 R1\nLOADI R0, 300\nJMP gone\n")
        result = run_cli([src])
        self.assertEqual(result.returncode, 1)
        for n in (1, 2, 3):
            self.assertIn("bad.asm:%d: error:" % n, result.stderr)

    def test_missing_input_file(self):
        result = run_cli([os.path.join(self.dir, "nope.asm")])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not found", result.stderr)
        self.assertEqual(self.files(), [])

    def test_input_is_a_directory(self):
        os.mkdir(os.path.join(self.dir, "folder.asm"))
        result = run_cli([os.path.join(self.dir, "folder.asm")])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("directory", result.stderr)
        self.assertEqual(self.files(), ["folder.asm"])

    def test_input_is_not_utf8(self):
        src = self.write("bin.asm", b"HALT\n\xff\xfe\x00", binary=True)
        result = run_cli([src])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("UTF-8", result.stderr)
        self.assertEqual(self.files(), ["bin.asm"])

    def test_unwritable_hex_location_leaves_no_partial_files(self):
        src = self.write("prog.asm", "HALT\n")
        bad_hex = os.path.join(self.dir, "no_such_dir", "p.hex")
        good_lst = os.path.join(self.dir, "p.lst")
        result = run_cli([src, "--hex", bad_hex, "--lst", good_lst])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot write", result.stderr)
        self.assertEqual(self.files(), ["prog.asm"])

    def test_unwritable_lst_location_leaves_no_partial_files(self):
        src = self.write("prog.asm", "HALT\n")
        good_hex = os.path.join(self.dir, "p.hex")
        bad_lst = os.path.join(self.dir, "no_such_dir", "p.lst")
        result = run_cli([src, "--hex", good_hex, "--lst", bad_lst])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.files(), ["prog.asm"])     # no p.hex, no temp file

    def test_unwritable_location_keeps_existing_outputs(self):
        src = self.write("prog.asm", "HALT\n")
        self.write("p.hex", "KEEP\n")
        bad_lst = os.path.join(self.dir, "no_such_dir", "p.lst")
        result = run_cli([src, "--hex", os.path.join(self.dir, "p.hex"),
                          "--lst", bad_lst])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read("p.hex"), "KEEP\n")
        self.assertEqual(self.files(), ["p.hex", "prog.asm"])

    def test_output_may_not_overwrite_the_source(self):
        src = self.write("prog.asm", "HALT\n")
        result = run_cli([src, "--hex", src])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read("prog.asm"), "HALT\n")
        result = run_cli([src, "--hex", os.path.join(self.dir, "x"),
                          "--lst", os.path.join(self.dir, "x")])
        self.assertNotEqual(result.returncode, 0)

    def test_no_arguments_is_a_usage_error(self):
        result = run_cli([])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("usage", result.stderr.lower())

    def test_crlf_and_bom_input_files(self):
        src = self.write("win.asm", b"\xef\xbb\xbfLOADI R0, 3\r\nHALT\r\n",
                         binary=True)
        result = run_cli([src])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read("win.hex"), "1806\n8800\n")

    def test_crlf_error_line_numbers(self):
        src = self.write("win.asm", b"HALT\r\nBAD\r\nHALT\r\n", binary=True)
        result = run_cli([src])
        self.assertEqual(result.returncode, 1)
        self.assertIn("win.asm:2: error:", result.stderr)

    def test_empty_file_is_an_error(self):
        src = self.write("empty.asm", "")
        result = run_cli([src])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.files(), ["empty.asm"])

    def test_full_size_program_through_the_cli(self):
        src = self.write("big.asm", "HALT\n" * 65536)
        result = run_cli([src])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read("big.hex").count("\n"), 65536)
        src = self.write("toobig.asm", "HALT\n" * 65537)
        result = run_cli([src])
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("toobig.hex", self.files())


if __name__ == "__main__":
    unittest.main(verbosity=2)
