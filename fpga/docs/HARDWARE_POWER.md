# Display power and connections (hardware plan, revision 2)

Status: this is the plan you confirmed. I did **not** check the AP2112K datasheet (current rating, dropout, capacitor requirements) and nothing here is tested on hardware.

## Display supply
- A dedicated **AP2112K-3.3TRG1** 3.3 V regulator on the carrier PCB powers the Waveshare 17344 module (VCC; the module's backlight is supplied from the same VCC).
- Regulator input: the **Tang Nano 5 V header**. Regulator output: display VCC only.
- **1 uF X5R or X7R ceramic capacitor on the input and 1 uF X5R or X7R on the output**, placed close to the regulator pins.
- The regulator's 3.3 V output **must not be connected to the Tang Nano's own 3.3 V rail** (no tie to the 3V3 header pin). Grounds are common.
- Load: Waveshare wiki FAQ quotes 3.3 V / 46 mA maximum for the module.
- Because the FPGA drives the display logic at 3.3 V (LVCMOS33) and the module runs at 3.3 V, supply and logic voltage are consistent, as the wiki requires.

## Unused interfaces
- The Tang Nano's **40-pin RGB LCD connector stays disconnected** and the **HDMI port stays disconnected**. Pins 41 (LCD CS), 42 (BL), 77 (DC), 48 (RST) and the button pins 25-31 are also RGB-connector nets on the Tang Nano, so nothing may be plugged into that connector.

## FPGA package-pin map (not header positions)
| Signal | Pin | Bank (Apycula) |
|---|---|---|
| lcd_din (DIN) | 73 | 1 |
| lcd_clk (CLK) | 74 | 1 |
| lcd_cs (CS) | **41** | 4 |
| lcd_dc (DC) | 77 | 1 |
| lcd_rst (RST) | **48** | 3 |
| lcd_bl (BL) | 42 | 4 |
| Up, Down, Left, Right, A, B, Reset | 27, 28, 25, 26, 29, 30, 31 | 5 |
| clk (27 MHz) | 4 | 7 |
