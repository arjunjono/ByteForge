; stack_basic.asm - PUSH/POP through the configured stack region 0x3F00-0x3FFF (STACK_TOP 0x4000)
        LOADI R0, 0x11
        LOADI R1, 0x22
        LOADI R2, 0x33
        PUSH  R0            ; mem[0x3FFF] = 11, SP = 0x3FFF
        PUSH  R1            ; mem[0x3FFE] = 22
        PUSH  R2            ; mem[0x3FFD] = 33, SP = 0x3FFD
        POP   R3            ; R3 = 33
        STORE R3, [0x0100]
        POP   R3            ; R3 = 22
        STORE R3, [0x0101]
        POP   R3            ; R3 = 11
        STORE R3, [0x0102]
        HALT
