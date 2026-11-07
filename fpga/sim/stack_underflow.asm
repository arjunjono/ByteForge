; stack_underflow.asm - POP from an empty stack (SP == STACK_TOP) must fault
        LOADI R0, 0x77
        STORE R0, [0x0300]
        POP   R1            ; underflow fault
        STORE R0, [0x0301]  ; must never execute
        HALT
