; memory_stack.asm - ByteForge demonstration program 3
; STORE/LOAD through data memory, then PUSH/POP showing last-in-first-out
; order and the stack pointer returning to its starting value.
;
; The simulation uses STACK_BOTTOM = 0x0100 and STACK_TOP = 0x0104, so SP
; starts at 0x0104 and the stack grows downwards (PUSH: SP-1, then write).
;
; Worked out by hand (hexadecimal):
;
;   Part 1  R3 = 44; STORE R3 -> mem[0200] = 44; R3 cleared to 00; LOAD R3 <- mem[0200]
;           so R3 = 44 again, proving the byte went to memory and came back.
;   Part 2  R0 = 11, R1 = 22, R2 = 33
;           PUSH R0 : SP 0104 -> 0103, mem[0103] = 11
;           PUSH R1 : SP 0103 -> 0102, mem[0102] = 22
;           PUSH R2 : SP 0102 -> 0101, mem[0101] = 33
;           POP  R0 : R0 = mem[0101] = 33 (last in, first out), SP 0101 -> 0102
;           POP  R1 : R1 = mem[0102] = 22,                       SP 0102 -> 0103
;           POP  R2 : R2 = mem[0103] = 11 (first in, last out),  SP 0103 -> 0104
;
; Word addresses: 0 LOADI, 1-2 STORE, 3 LOADI, 4-5 LOAD, 6-8 three LOADI,
; 9-11 three PUSH, 12-14 three POP, 15 HALT.
;
; Expected final state:
;   R0 = 33  R1 = 22  R2 = 11  R3 = 44
;   Z = 0    C = 0    N = 0     (no instruction ever writes the flags)
;   PC = 0x0010 (16, one past the HALT word)    SP = 0x0104 (back at STACK_TOP)
;   Data memory: mem[0200] = 44, mem[0103] = 11, mem[0102] = 22,
;                mem[0101] = 33, mem[0100] = 00 (never written)
;   Data transactions in order: W 0200=44, R 0200=44, W 0103=11, W 0102=22,
;                W 0101=33, R 0101=33, R 0102=22, R 0103=11

; ---- Part 1: STORE and LOAD ----
        LOADI R3, 0x44
        STORE R3, [0x0200]      ; mem[0x0200] = 0x44
        LOADI R3, 0             ; wipe the register
        LOAD  R3, [0x0200]      ; R3 = 0x44 again

; ---- Part 2: PUSH three values, POP them back in reverse order ----
        LOADI R0, 0x11
        LOADI R1, 0x22
        LOADI R2, 0x33
        PUSH  R0                ; bottom of the pushed data
        PUSH  R1
        PUSH  R2                ; top of the stack
        POP   R0                ; gets 0x33 - the last value pushed
        POP   R1                ; gets 0x22
        POP   R2                ; gets 0x11 - the first value pushed
        HALT
