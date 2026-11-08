# ByteForge

A handheld FPGA computer built around a custom 8-bit CPU, an assembler, an SPI display and physical controls. Work in progress.

## Current milestone: routed carrier A1

- Editable carrier CAD, review Gerbers/drills, vendor references and reports: `ByteForge_Entry13_Routed_Carrier_A1.zip`.
- Architecture and milestone history: `ByteForge_Architecture_v13.pdf` (Section 26 is current).
- CPU, system RTL, software and tests: `fpga/`.
- Current pin-72 FPGA results: `fpga/docs/ENTRY13_PIN72_RESULTS.md`.
- Board images: `ByteForge_A1_Routing.png`, `ByteForge_A1_Schematic.png` and `ByteForge_A1_Verification.png`.

KiCad ERC, DRC, connectivity and schematic parity checks pass. All 17 FPGA regression entries pass, and the new pin-72 implementation reaches 93.07 MHz against 27 MHz with zero package-pin mismatches. The CPU/system RTL is unchanged.

The routing image hides ground fills for clarity; the saved PCB includes them. The verification image is a generated report summary. AI assistance was used for design and verification; these are digital results, not evidence of physical hardware operation.

## Hardware status

The Tang Nano 20K, Waveshare display and carrier have not been assembled or tested. Enclosure fit, power measurements, display operation, external I/O timing and the official Gowin flow remain unverified. The supplied manufacturing files are for review; no board has been ordered. The next milestone is enclosure and assembly design, then the final landed budget and pre-order review.

Earlier architecture versions and ZIPs are retained as milestone history. Use A1 and the v13 architecture document for the current carrier design; older A0 images are unrouted.
