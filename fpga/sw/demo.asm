; demo.asm - ByteForge FPGA demonstration (Waveshare 2inch LCD, SKU 17344)
;
; Uses only the existing 18-instruction ISA: no CALL/RET, shifts or immediate
; arithmetic. Four registers only, so loop counters and the colour live in RAM.
;
; WHAT IT DOES
;   1. Polls LCD status (0xFF12) until bit1 (panel startup/reset timing) is 0.
;   2. Sends the Waveshare reference panel initialisation (command bytes to
;      0xFF10, data bytes to 0xFF11) exactly as in LCD_2IN_InitReg() of
;      waveshare/Pico_code (c/lib/LCD/LCD_2in.c, commit c50bc57), with one
;      ADDED 125 ms delay (write 125 to 0xFF20) between SLPOUT (0x11) and
;      DISPON (0x29). The reference has no delay there. Sitronix ST7789V v1.6,
;      section 9.1.12 (SLPOUT): "necessary to wait 5msec before sending any new
;      commands" after SLPOUT, and 120 msec before sending a SLEEP IN command.
;      So the datasheet REQUIRES >= 5 ms here (not 120 ms; the 120 ms rule is for
;      SLPIN). 125 ms is a deliberately conservative choice, far above the 5 ms
;      minimum; it is not a datasheet requirement.
;   3. Window = whole panel in native portrait orientation (MADCTL 0x00,
;      240 columns x 320 rows, no panel offsets): CASET 0..239, RASET 0..319,
;      RAMWR, then streams 76800 pixels of black (0x0000), 2 bytes per pixel,
;      high byte first (RGB565). No framebuffer: every pixel byte is a write.
;   4. Turns the backlight on (0xFF13 = 1), then draws a 40x40 CYAN (0x07FF)
;      patch at columns 100..139, rows 140..179.
;   5. Main loop: reads buttons (0xFF00); a button that has just become
;      pressed (edge) redraws the patch in that button's colour:
;          Up=RED F800  Down=GREEN 07E0  Left=BLUE 001F
;          Right=YELLOW FFE0  A=WHITE FFFF  B=MAGENTA F81F
;      A held button draws once only; release draws nothing.
;      SIMULTANEOUS PRESSES: if several buttons become pressed in the same
;      sample only the first in the order Up, Down, Left, Right, A, B is
;      drawn; the others are recorded as pressed and do not draw while still
;      held (releasing and pressing again draws). Buttons already held when
;      the main loop first starts are ignored until released and pressed again.
;   The program never ends (the hardware demo runs forever); the testbench
;   stops the simulation.
;
; RAM variables (general RAM, initialised below before first use):
;   0x0000 CHI  colour high byte      0x0005 CO  outer loop counter
;   0x0001 CLO  colour low byte       0x0006 CM  middle loop counter
;   0x0002 NOUT outer count           0x0007 PREV previous button sample
;   0x0003 NMID middle count          0x0008 RET  fill return id (0 bg, 1 patch)
;   0x0004 NIN  inner count
; Pixels filled = NOUT * NMID * NIN  (background 240*8*40 = 76800, patch 40*1*40 = 1600)
; Registers in fill: R0=CHI R1=CLO R2=counter R3=1

; ---------------- 1. wait for panel startup/reset timing to finish ----------------
wait_su:
        IN    R0, [0xFF12]
        LOADI R1, 2             ; mask for bit1 (startup)
        AND   R0, R1
        JNZ   wait_su

; ---------------- 2. panel initialisation (Waveshare LCD_2IN_InitReg) ----------------

        LOADI R0, 0x36
        OUT   R0, [0xFF10]       ; MADCTL
        LOADI R0, 0x00
        OUT   R0, [0xFF11]

        LOADI R0, 0x3A
        OUT   R0, [0xFF10]       ; COLMOD: 16-bit RGB565
        LOADI R0, 0x05
        OUT   R0, [0xFF11]

        LOADI R0, 0x21
        OUT   R0, [0xFF10]       ; INVON

        LOADI R0, 0x2A
        OUT   R0, [0xFF10]       ; CASET (as in reference init)
        LOADI R0, 0x00
        OUT   R0, [0xFF11]
        LOADI R0, 0x00
        OUT   R0, [0xFF11]
        LOADI R0, 0x01
        OUT   R0, [0xFF11]
        LOADI R0, 0x3F
        OUT   R0, [0xFF11]

        LOADI R0, 0x2B
        OUT   R0, [0xFF10]       ; RASET (as in reference init)
        LOADI R0, 0x00
        OUT   R0, [0xFF11]
        LOADI R0, 0x00
        OUT   R0, [0xFF11]
        LOADI R0, 0x00
        OUT   R0, [0xFF11]
        LOADI R0, 0xEF
        OUT   R0, [0xFF11]

        LOADI R0, 0xB2
        OUT   R0, [0xFF10]       ; PORCTRL
        LOADI R0, 0x0C
        OUT   R0, [0xFF11]
        LOADI R0, 0x0C
        OUT   R0, [0xFF11]
        LOADI R0, 0x00
        OUT   R0, [0xFF11]
        LOADI R0, 0x33
        OUT   R0, [0xFF11]
        LOADI R0, 0x33
        OUT   R0, [0xFF11]

        LOADI R0, 0xB7
        OUT   R0, [0xFF10]       ; GCTRL
        LOADI R0, 0x35
        OUT   R0, [0xFF11]

        LOADI R0, 0xBB
        OUT   R0, [0xFF10]       ; VCOMS
        LOADI R0, 0x1F
        OUT   R0, [0xFF11]

        LOADI R0, 0xC0
        OUT   R0, [0xFF10]       ; LCMCTRL
        LOADI R0, 0x2C
        OUT   R0, [0xFF11]

        LOADI R0, 0xC2
        OUT   R0, [0xFF10]       ; VDVVRHEN
        LOADI R0, 0x01
        OUT   R0, [0xFF11]

        LOADI R0, 0xC3
        OUT   R0, [0xFF10]       ; VRHS
        LOADI R0, 0x12
        OUT   R0, [0xFF11]

        LOADI R0, 0xC4
        OUT   R0, [0xFF10]       ; VDVS
        LOADI R0, 0x20
        OUT   R0, [0xFF11]

        LOADI R0, 0xC6
        OUT   R0, [0xFF10]       ; FRCTRL2
        LOADI R0, 0x0F
        OUT   R0, [0xFF11]

        LOADI R0, 0xD0
        OUT   R0, [0xFF10]       ; PWCTRL1
        LOADI R0, 0xA4
        OUT   R0, [0xFF11]
        LOADI R0, 0xA1
        OUT   R0, [0xFF11]

        LOADI R0, 0xE0
        OUT   R0, [0xFF10]       ; PVGAMCTRL
        LOADI R0, 0xD0
        OUT   R0, [0xFF11]
        LOADI R0, 0x08
        OUT   R0, [0xFF11]
        LOADI R0, 0x11
        OUT   R0, [0xFF11]
        LOADI R0, 0x08
        OUT   R0, [0xFF11]
        LOADI R0, 0x0C
        OUT   R0, [0xFF11]
        LOADI R0, 0x15
        OUT   R0, [0xFF11]
        LOADI R0, 0x39
        OUT   R0, [0xFF11]
        LOADI R0, 0x33
        OUT   R0, [0xFF11]
        LOADI R0, 0x50
        OUT   R0, [0xFF11]
        LOADI R0, 0x36
        OUT   R0, [0xFF11]
        LOADI R0, 0x13
        OUT   R0, [0xFF11]
        LOADI R0, 0x14
        OUT   R0, [0xFF11]
        LOADI R0, 0x29
        OUT   R0, [0xFF11]
        LOADI R0, 0x2D
        OUT   R0, [0xFF11]

        LOADI R0, 0xE1
        OUT   R0, [0xFF10]       ; NVGAMCTRL
        LOADI R0, 0xD0
        OUT   R0, [0xFF11]
        LOADI R0, 0x08
        OUT   R0, [0xFF11]
        LOADI R0, 0x10
        OUT   R0, [0xFF11]
        LOADI R0, 0x08
        OUT   R0, [0xFF11]
        LOADI R0, 0x06
        OUT   R0, [0xFF11]
        LOADI R0, 0x06
        OUT   R0, [0xFF11]
        LOADI R0, 0x39
        OUT   R0, [0xFF11]
        LOADI R0, 0x44
        OUT   R0, [0xFF11]
        LOADI R0, 0x51
        OUT   R0, [0xFF11]
        LOADI R0, 0x0B
        OUT   R0, [0xFF11]
        LOADI R0, 0x16
        OUT   R0, [0xFF11]
        LOADI R0, 0x14
        OUT   R0, [0xFF11]
        LOADI R0, 0x2F
        OUT   R0, [0xFF11]
        LOADI R0, 0x31
        OUT   R0, [0xFF11]

        LOADI R0, 0x21
        OUT   R0, [0xFF10]       ; INVON (second time, as in reference)

        LOADI R0, 0x11
        OUT   R0, [0xFF10]       ; SLPOUT
        LOADI R0, 125
        OUT   R0, [0xFF20]       ; added: 125 ms after SLPOUT (datasheet minimum 5 ms; see header)

        LOADI R0, 0x29
        OUT   R0, [0xFF10]       ; DISPON

; ---------------- 3. background: window 0..239 x 0..319, RAMWR, black fill ----------------
        LOADI R0, 0x2A          ; CASET
        OUT   R0, [0xFF10]
        LOADI R0, 0x00
        OUT   R0, [0xFF11]      ; XS high
        OUT   R0, [0xFF11]      ; XS low  = 0
        OUT   R0, [0xFF11]      ; XE high = 0
        LOADI R0, 0xEF
        OUT   R0, [0xFF11]      ; XE low  = 239
        LOADI R0, 0x2B          ; RASET
        OUT   R0, [0xFF10]
        LOADI R0, 0x00
        OUT   R0, [0xFF11]      ; YS high
        OUT   R0, [0xFF11]      ; YS low  = 0
        LOADI R0, 0x01
        OUT   R0, [0xFF11]      ; YE high
        LOADI R0, 0x3F
        OUT   R0, [0xFF11]      ; YE low  = 319
        LOADI R0, 0x2C          ; RAMWR
        OUT   R0, [0xFF10]
        LOADI R0, 0
        STORE R0, [0x0000]      ; CHI = 0x00
        STORE R0, [0x0001]      ; CLO = 0x00
        STORE R0, [0x0008]      ; RET = 0 (return to after_bg)
        LOADI R0, 240
        STORE R0, [0x0002]      ; NOUT = 240
        LOADI R0, 8
        STORE R0, [0x0003]      ; NMID = 8
        LOADI R0, 40
        STORE R0, [0x0004]      ; NIN  = 40
        JMP   fill

; ---------------- patch window (CASET 100..139, RASET 140..179, RAMWR) + fill setup ----------------
draw_patch:
        LOADI R0, 0x2A          ; CASET
        OUT   R0, [0xFF10]
        LOADI R0, 0x00
        OUT   R0, [0xFF11]      ; XS high
        LOADI R0, 100
        OUT   R0, [0xFF11]      ; XS low  = 100
        LOADI R0, 0x00
        OUT   R0, [0xFF11]      ; XE high
        LOADI R0, 139
        OUT   R0, [0xFF11]      ; XE low  = 139
        LOADI R0, 0x2B          ; RASET
        OUT   R0, [0xFF10]
        LOADI R0, 0x00
        OUT   R0, [0xFF11]      ; YS high
        LOADI R0, 140
        OUT   R0, [0xFF11]      ; YS low  = 140
        LOADI R0, 0x00
        OUT   R0, [0xFF11]      ; YE high
        LOADI R0, 179
        OUT   R0, [0xFF11]      ; YE low  = 179
        LOADI R0, 0x2C          ; RAMWR
        OUT   R0, [0xFF10]
        LOADI R0, 1
        STORE R0, [0x0008]      ; RET = 1 (return to main)
        LOADI R0, 40
        STORE R0, [0x0002]      ; NOUT = 40
        STORE R0, [0x0004]      ; NIN  = 40
        LOADI R0, 1
        STORE R0, [0x0003]      ; NMID = 1
        ; fall through to fill

; ---------------- fill: stream NOUT*NMID*NIN pixels of colour CHI:CLO ----------------
fill:
        LOAD  R0, [0x0000]      ; CHI
        LOAD  R1, [0x0001]      ; CLO
        LOADI R3, 1             ; constant 1
        LOAD  R2, [0x0002]
        STORE R2, [0x0005]      ; CO = NOUT
f_out:
        LOAD  R2, [0x0003]
        STORE R2, [0x0006]      ; CM = NMID
f_mid:
        LOAD  R2, [0x0004]      ; inner counter = NIN
f_in:
        OUT   R0, [0xFF11]      ; pixel high byte
        OUT   R1, [0xFF11]      ; pixel low byte
        SUB   R2, R3
        JNZ   f_in
        LOAD  R2, [0x0006]
        SUB   R2, R3
        STORE R2, [0x0006]      ; --CM (STORE does not touch flags)
        JNZ   f_mid
        LOAD  R2, [0x0005]
        SUB   R2, R3
        STORE R2, [0x0005]      ; --CO
        JNZ   f_out
        ; fill finished: return by RET id (no CALL/RET in the ISA)
        LOAD  R2, [0x0008]
        LOADI R3, 0
        CMP   R2, R3
        JZ    after_bg
        JMP   main_loop

; ---------------- after the background fill: backlight on, first patch ----------------
after_bg:
        LOADI R0, 1
        OUT   R0, [0xFF13]      ; backlight on
        IN    R0, [0xFF00]
        STORE R0, [0x0007]      ; PREV = buttons held now (ignored until released)
        LOADI R0, 0x07
        STORE R0, [0x0000]      ; CHI = 07
        LOADI R0, 0xFF
        STORE R0, [0x0001]      ; CLO = FF  -> cyan 07FF
        JMP   draw_patch

; ---------------- main loop: edge-detected buttons ----------------
main_loop:
        IN    R0, [0xFF00]      ; current buttons (1 = pressed)
        LOAD  R1, [0x0007]      ; previous
        STORE R0, [0x0007]      ; PREV = current
        MOV   R2, R0
        XOR   R2, R1            ; bits that changed
        AND   R2, R0            ; changed AND now pressed = new presses
        LOADI R3, 0
        CMP   R2, R3
        JZ    main_loop         ; nothing new
        LOADI R3, 1
        AND   R3, R2
        JNZ   do_up
        LOADI R3, 2
        AND   R3, R2
        JNZ   do_down
        LOADI R3, 4
        AND   R3, R2
        JNZ   do_left
        LOADI R3, 8
        AND   R3, R2
        JNZ   do_right
        LOADI R3, 16
        AND   R3, R2
        JNZ   do_a
        JMP   do_b              ; only bit5 can remain (bits 7:6 read 0)

do_up:                          ; RED F800
        LOADI R0, 0xF8
        STORE R0, [0x0000]
        LOADI R0, 0x00
        STORE R0, [0x0001]
        JMP   draw_patch
do_down:                        ; GREEN 07E0
        LOADI R0, 0x07
        STORE R0, [0x0000]
        LOADI R0, 0xE0
        STORE R0, [0x0001]
        JMP   draw_patch
do_left:                        ; BLUE 001F
        LOADI R0, 0x00
        STORE R0, [0x0000]
        LOADI R0, 0x1F
        STORE R0, [0x0001]
        JMP   draw_patch
do_right:                       ; YELLOW FFE0
        LOADI R0, 0xFF
        STORE R0, [0x0000]
        LOADI R0, 0xE0
        STORE R0, [0x0001]
        JMP   draw_patch
do_a:                           ; WHITE FFFF
        LOADI R0, 0xFF
        STORE R0, [0x0000]
        STORE R0, [0x0001]
        JMP   draw_patch
do_b:                           ; MAGENTA F81F
        LOADI R0, 0xF8
        STORE R0, [0x0000]
        LOADI R0, 0x1F
        STORE R0, [0x0001]
        JMP   draw_patch
