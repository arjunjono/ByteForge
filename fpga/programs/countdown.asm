; countdown.asm - ByteForge demonstration program 2
; A backward conditional jump (JNZ) loop that counts R0 down from 5 to 0.
; Each pass adds the counter to a running total (R2) and counts passes (R3).
;
; Registers:  R0 = counter   R1 = constant 1   R2 = running total   R3 = passes
;
; Worked out by hand (hexadecimal):
;
;   pass   R2 += R0   R3 += 1   R0 -= 1   SUB result   JNZ
;   1      0+5 = 05   01        04        non-zero     taken (back to 'loop')
;   2      5+4 = 09   02        03        non-zero     taken
;   3      9+3 = 0C   03        02        non-zero     taken
;   4      C+2 = 0E   04        01        non-zero     taken
;   5      E+1 = 0F   05        00        zero         not taken -> HALT
;
; Word addresses: 0-3 four LOADI, 4 'loop' ADD, 5 ADD, 6 SUB, 7-8 JNZ, 9 HALT.
; Instruction words fetched: 4 + 5 passes x 5 words + 1 = 30.
;
; Expected final state:
;   R0 = 00  R1 = 01  R2 = 0F  R3 = 05
;   Z = 1    C = 0    N = 0     (flags from the last SUB: 1 - 1 = 0)
;   PC = 0x000A (10, one past the HALT word)    SP = 0x0104 (STACK_TOP)
;   No data-memory access at all.

        LOADI R0, 5             ; counter
        LOADI R1, 1             ; step
        LOADI R2, 0             ; running total
        LOADI R3, 0             ; pass counter
loop:   ADD   R2, R0            ; total = total + counter
        ADD   R3, R1            ; passes = passes + 1
        SUB   R0, R1            ; counter = counter - 1; Z = 1 when it reaches 0
        JNZ   loop              ; backward jump while the counter is not zero
        HALT
