; stack_limit.asm - fill the whole stack region with distinct bytes, then overflow it
        LOADI R0, 0xAB
        STORE R0, [0x3EFF]  ; sentinel just below the stack region (general RAM)
        LOADI R2, 255
        LOADI R3, 1
loop:   PUSH  R0            ; 255 pushes, value increments each time
        ADD   R0, R3
        SUB   R2, R3
        JNZ   loop
        PUSH  R0            ; 256th push: SP 0x3F01 -> 0x3F00 (still legal)
        LOADI R1, 0x5C
        STORE R1, [0x0200]  ; marker: executed
        PUSH  R0            ; 257th push: SP == STACK_BOTTOM -> stack overflow fault
        STORE R1, [0x0201]  ; must never execute
        HALT
