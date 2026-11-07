; arithmetic.asm - ByteForge demonstration program 1
; Register transfers, arithmetic, logic, a carry case, a borrow case, and
; CMP leaving both registers unchanged.
;
; Worked out by hand (all values hexadecimal), flags shown as Z C N:
;
;   addr  instruction        result                              flags after
;   ----  -----------------  ----------------------------------  -----------
;   0     LOADI R0, 200      R0 = C8                             (unchanged)
;   1     LOADI R1, 100      R1 = 64                             (unchanged)
;   2     MOV   R2, R0       R2 = C8                             (unchanged)
;   3     ADD   R2, R1       C8 + 64 = 12C -> R2 = 2C, carry     0 1 0
;   4     MOV   R3, R1       R3 = 64                             0 1 0 (MOV keeps flags)
;   5     SUB   R3, R0       64 - C8 = -9C -> R3 = 9C, borrow    0 1 1
;   6     LOADI R0, 0xF0     R0 = F0                             0 1 1
;   7     LOADI R1, 0b111100 R1 = 3C                             0 1 1
;   8     AND   R0, R1       F0 & 3C = 30 -> R0 = 30             0 0 0
;   9     OR    R0, R1       30 | 3C = 3C -> R0 = 3C             0 0 0
;   10    XOR   R0, R1       3C ^ 3C = 00 -> R0 = 00             1 0 0
;   11    CMP   R2, R1       2C - 3C = F0 (borrow), no register  0 1 1
;                            is written: R2 stays 2C, R1 stays 3C
;   12    HALT
;
; Expected final state:
;   R0 = 00  R1 = 3C  R2 = 2C  R3 = 9C
;   Z = 0    C = 1    N = 1
;   PC = 0x000D (13, one past the HALT word)    SP = 0x0104 (STACK_TOP)
;   No data-memory access at all.

        LOADI R0, 200           ; decimal immediate
        LOADI R1, 100
        MOV   R2, R0            ; register transfer
        ADD   R2, R1            ; 200 + 100 = 300 -> 0x2C with carry
        MOV   R3, R1            ; MOV must not change the flags
        SUB   R3, R0            ; 100 - 200 -> 0x9C with borrow (C = 1, N = 1)

        LOADI R0, 0xF0          ; hexadecimal immediate
        LOADI R1, 0b00111100    ; binary immediate (0x3C)
        AND   R0, R1            ; 0xF0 & 0x3C = 0x30
        OR    R0, R1            ; 0x30 | 0x3C = 0x3C
        XOR   R0, R1            ; 0x3C ^ 0x3C = 0   (Z = 1)

        CMP   R2, R1            ; 0x2C - 0x3C: borrow, negative; registers untouched
        HALT
