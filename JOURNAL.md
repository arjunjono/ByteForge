---
title: "ByteForge"
github: "https://github.com/arjunjono/ByteForge"
description: "I want to build a small handheld computer around an FPGA, with a custom 8-bit CPU that I design and implement myself. The computer will have its own instruction set, memory, display and physical controls, all integrated onto a custom PCB and housed in a 3D-printed enclosure. I also plan to write a simple assembler so I can create and run programs on the CPU. I'm building this because I want to learn how computers work at the hardware level, from digital logic and processor architecture to PCB design and the final physical device."
created_at: "2026-10-03"
total_time: "37h"
---

# October 3, 2026: Initial ByteForge architecture
<!-- fabricate:entry 89 -->

What I worked on:
Today I planned the first version of ByteForge, a handheld FPGA computer with a custom 8-bit CPU. I defined the main goals of the project and decided on the basic CPU architecture. I chose an 8-bit data width, a 16-bit address space and four general-purpose registers called R0 to R3. I also included a program counter, stack pointer and a FLAGS register containing Zero, Carry and Negative flags. I created an initial instruction set containing load/store operations, arithmetic and logic operations, jumps, stack operations and input/output instructions. I also decided that the computer will use memory-mapped I/O so the CPU can communicate with the buttons and display through specific memory addresses. The final goal is for ByteForge to run on an FPGA, read physical buttons, output to a colour display and run simple programs written for my custom instruction set. I also plan to design a PCB, enclosure and assembler later in the project.

![](https://fabricate.hackclub-assets.com/b1dd638d034d281e2c136fee67e6b8f711f5ecf217ea1e74e56c4776b07feb43/ByteForge_initialarch_diagram.png)

- [ByteForge_InitialArchitecture.pdf](https://fabricate.hackclub-assets.com/2a2cc92b9cfb13bc032d44aed12ff012b427213515669094604e2eb3f6aa66bd/ByteForge_InitialArchitecture.pdf)

**Total time spent: 2h**

# October 4, 2026: Designed instruction encoding and CPU datapath
<!-- fabricate:entry 118 -->

Today I designed how ByteForge’s instructions will be represented and how data will move through the CPU. I decided to use 16-bit instruction words with a 5-bit opcode, which gives enough space for the current instruction set and future expansion. Since ByteForge has four general-purpose registers, each register can be selected using 2 bits. I also defined how different instruction types will work. Register instructions such as ADD and SUB store the opcode and register selections in one 16-bit word, while instructions that need a full 16-bit memory address can use a second word. I also added a LOADI instruction so programs can load constant values directly into registers. I then designed the first CPU datapath, showing how the program counter, program memory, instruction register, instruction decoder, control unit, registers, ALU, flags, RAM and memory-mapped I/O will connect. Finally, I outlined the fetch-decode-execute cycle that the processor will use to run instructions.

![](https://fabricate.hackclub-assets.com/d9d628f1cb77162ec08e12243fbd6c0fc9b7df68b364819fb0433d79775a793a/CPU%20datapath%20diagram.png)

- [Updated full ByteForge architecture PDF.pdf](https://fabricate.hackclub-assets.com/2038323b544ed3179d1b60be54c3c40340ed26d193a1cb27423b23f248d4640d/Updated%20full%20ByteForge%20architecture%20PDF.pdf)

**Total time spent: 3h**

# October 4, 2026 (entry 2): Refined memory architecture and stack design
<!-- fabricate:entry 119 -->

Today I refined ByteForge’s memory architecture and stack design. I decided to keep program memory separate from the main data-memory space so that instruction fetching can be handled independently from RAM and input/output access. RAM and memory-mapped I/O will share the data-memory space. I also defined how the Stack Pointer will work. The stack will be stored in RAM, with PUSH decrementing the Stack Pointer before writing a register value to memory, and POP reading the value from memory before incrementing the Stack Pointer. I then updated the CPU datapath to include the Stack Pointer and make the memory design consistent with the rest of the architecture.

![](https://fabricate.hackclub-assets.com/d504c3a896610df60ea690bcb5f62ac92a395b3f171f91af2a1795053584cd60/ByteForge_Memory_Stack_Datapath.png.png)

- [ByteForge_Architecture_v3.pdf.pdf](https://fabricate.hackclub-assets.com/36ddeb2c3a85b3dce5010d0188e40813158e3b5facb30e5a3b693432aebc834f/ByteForge_Architecture_v3.pdf.pdf)

**Total time spent: 2h 30m**

# October 5, 2026: Implemented and tested the 8-bit ALU
<!-- fabricate:entry 132 -->

Today I implemented ByteForge’s 8-bit ALU in Verilog with AI assistance. It supports ADD, SUB, AND, OR, XOR and the subtraction used by CMP. I defined the Zero, Carry and Negative flag rules, including carry for addition and borrow for subtraction. I ran a self-checking testbench using Icarus Verilog on EDA Playground. All 38 tests passed with zero failures, covering arithmetic, bitwise operations, flag behaviour and unsupported opcodes. I also updated the architecture document with the implementation details and results.

Code and simulation: https://www.edaplayground.com/x/R8vK

![](https://fabricate.hackclub-assets.com/b753251a7fce98a4433aa3916846d1e6035b733b6cc1754c3326084f43e00443/ByteForge_ALU_Test_Results.png)

- [ByteForge_Architecture_v4.pdf.pdf](https://fabricate.hackclub-assets.com/834bdc20d73f727453bacfb9583cc9ca9f82e6865f41418f1199be5bd8221f09/ByteForge_Architecture_v4.pdf.pdf)

**Total time spent: 2h**

# October 6, 2026: Implemented and tested registers and flags
<!-- fabricate:entry 156 -->

Today I implemented ByteForge’s four 8-bit registers and FLAGS storage in Verilog with Claude’s assistance. The register file supports two simultaneous reads and one write on the rising clock edge. The flags have a separate write enable, and both modules use synchronous reset to clear their stored values.
I ran the self-checking testbench on EDA Playground, where all 131 checks passed with zero failures. These covered reads, writes, value retention, flag updates and reset behaviour. I then updated the architecture document with these details and saved the simulation results.
Code and simulation: https://www.edaplayground.com/x/ADVd

![](https://fabricate.hackclub-assets.com/f049fe31ae3ad2e95244443eaef5a616bb06a7cc127711647df28c913bcea01a/ByteForge_Registers_Test_Results.png)

- [ByteForge_Architecture_v5.pdf.pdf](https://fabricate.hackclub-assets.com/81367f541e27b0a1543548a404b0c47bfc572bcd00c042946b1dd927cf454904/ByteForge_Architecture_v5.pdf.pdf)

**Total time spent: 1h 30m**

# October 7, 2026: Finalised instruction encoding and tested the decoder
<!-- fabricate:entry 175 -->

I finalised ByteForge’s instruction formats, operand fields and reserved-bit rules, then used Claude to help generate the Verilog instruction decoder and self-checking testbench. The decoder identifies instructions, extracts register selections and immediate values, and indicates which operations each instruction requires. I ran the simulation in EDA Playground, where all 1,781 checks passed with zero failures. The tests covered supported and unsupported opcodes, register combinations, immediate values, reserved bits and instruction transitions. I documented the encoding rules and testing results in Sections 15 and 16 of the architecture document and saved the simulation link and results screenshot.

![](https://fabricate.hackclub-assets.com/073943ee80b5e4fbe271177c70505aa25117f4a3c17de86a042c6be960867f31/ByteForge_Decoder_Test_Results.png)

- [ByteForge_Architecture_v6.pdf](https://fabricate.hackclub-assets.com/6138a9ec3e295dbc50572f497b155b9704b342c78977b657fdee45146e7e1a94/ByteForge_Architecture_v6.pdf)

**Total time spent: 2h**

# October 8, 2026: Implemented and tested the CPU control unit
<!-- fabricate:entry 198 -->

I defined ByteForge’s instruction execution rules, including memory timing, jumps, stack boundaries, reset and fault handling. Using Claude to help generate the Verilog code, I implemented a clocked control unit that uses the existing instruction decoder to coordinate CPU operations. I ran its self-checking testbench in EDA Playground, where 73 scenarios and 10,577 checks passed with zero failures. The tests covered instruction execution, memory delays, stack operations, HALT, invalid instructions and reset during pending transactions. I documented the rules and results in Sections 17 and 18 of the architecture document. The next step is connecting the control unit to the actual ALU, register file and FLAGS modules.

![](https://fabricate.hackclub-assets.com/6546df1a6c66dbf38238f3a2a9a55b8c3af868bebd5bb6b0e0771502b239d25c/image-png/ByteForge_Control_Unit_Test_Results.png)

- [ByteForge_Architecture_v7.pdf](https://fabricate.hackclub-assets.com/e34c0de75230f95bbe23b9a767d9e90284ae394567ed4486a012bffd5f5c10c8/application-octet-stream/ByteForge_Architecture_v7.pdf)

**Total time spent: 2h 30m**

# October 9, 2026: Integrated and tested the ByteForge CPU core
<!-- fabricate:entry 216 -->

Today I connected the ALU, register file, FLAGS register and control unit into the ByteForge CPU core, with the instruction decoder inside the control unit. I ran the integration testbench in EDA Playground using Icarus Verilog. All 75 scenarios and 15,234 checks passed with zero failures, covering instruction execution, jumps, memory accesses, stack operations, reset and fault handling. A mixed program also produced the expected final register, flag and memory values. I added Section 19 to the architecture document and saved the simulation results. The CPU now works as an integrated core in simulation; FPGA memory, peripherals and physical hardware testing are still to come.

![](https://fabricate.hackclub-assets.com/f8d57234eff9077217be422cbe29c8d43295fd5c3fc68b3661eb7675c9635898/image-png/ByteForge_CPU_Test_Results.png)

- [ByteForge_Architecture_v8.pdf](https://fabricate.hackclub-assets.com/d51b86bfc04a6933cc82e464cd4c98c113188b44dd96dcafcd9497ad782ada5e/application-octet-stream/ByteForge_Architecture_v8.pdf)

**Total time spent: 2h 30m**

# October 12, 2026: Built the ByteForge assembler and tested assembly programs
<!-- fabricate:entry 353 -->

Today I added a Python assembler that converts readable ByteForge instructions into machine code, with support for labels, comments and input validation. All 78 assembler tests passed. I also tested three assembly programs covering arithmetic and logic, a countdown loop, and memory and stack operations. Each program ran on the integrated CPU simulation with immediate, fixed-delay and random-delay memory responses. All nine runs and 1,986 checks passed with zero failures. I saved the simulation results and added Sections 20–21 to the architecture document. This completes the path from readable assembly to CPU execution in simulation.

![](https://fabricate.hackclub-assets.com/b0df4979ac459a9db16488935254796aac85d6170e4abfd6dd0323beec56406d/image-png/ByteForge_Assembly_Program_Test_Results.png)

- [ByteForge_Architecture_v9.pdf](https://fabricate.hackclub-assets.com/6c9b49a42aa38a1956e409ee5fb6aced9eaa54bd10417be7cb750b214e5356e9/application-octet-stream/ByteForge_Architecture_v9.pdf)

**Total time spent: 3h**

# October 25, 2026: Planned ByteForge hardware, connections and budget
<!-- fabricate:entry 1239 -->

Today I planned ByteForge’s hardware around the Tang Nano 20K FPGA module, a Waveshare 2-inch colour display, six control buttons and a reset button. I documented proposed FPGA pin assignments, power connections and the custom carrier PCB approach. I also prepared a preliminary US$207.10 budget and created a hardware connection diagram. Section 22 records these choices, with final pricing, FPGA synthesis and physical testing still outstanding.

Project repository: https://github.com/arjunjono/ByteForge

![](https://fabricate.hackclub-assets.com/25a3e6703861c0d0656f0fbd8f81adae15b78cb91e9ff1d54dd99e79f511aa00/image-png/ByteForge_Hardware_Connection_Plan.png)

**Total time spent: 2h**

# November 7, 2026: Integrated FPGA memories, controls and SPI display interface
<!-- fabricate:entry 2321 -->

For this update, I integrated the CPU with program ROM, data RAM, debounced button inputs, reset handling, a delay peripheral and an SPI display controller. An assembly demo was tested using simulated button presses and an independent SPI monitor. The full regression reported zero failures, including 179,499 demo checks and the existing CPU and assembler tests. I also reviewed the hardware connections, corrected two display-pin assignments and updated the display power plan. The revised open-source FPGA build used 16 of 46 block RAMs and reported a maximum internal clock frequency of 85.90 MHz against the 27 MHz target. Sections 23–24 document the implementation and results. Physical hardware and external display timing remain untested.

![](https://fabricate.hackclub-assets.com/0a08380dfa4476cfe6155581695e39ae87029110f8284a802760ad5b4f79f3dd/image-png/ByteForge_FPGA_Test_Results.png)
![](https://fabricate.hackclub-assets.com/51abafb0a0820670a76e123d6db5ba6bc1f0d8e4d2cd31a4c967a072fabf098a/image-png/ByteForge_FPGA_Timing_Results.png)

**Total time spent: 4h**

# November 8, 2026: Carrier-Board Schematic and Initial PCB Placement
<!-- fabricate:entry 2376 -->

Created the first carrier-board schematic and PCB placement for ByteForge, including the FPGA module sockets, display connector, seven buttons, pull-up resistors, a dedicated 3.3 V display regulator, decoupling capacitors and mounting holes. Reviewing the Tang Nano schematic revealed a pull-down resistor on the original Right-button pin, so its assignment was changed from FPGA pin 26 to pin 72. Imported the design into EasyEDA Pro, corrected component-property differences and checked the schematic-to-PCB change reports while preserving the four mounting holes. Exported images of the schematic and initial PCB layout and updated the architecture document. The board remains unrouted; mechanical confirmation, copper routing and final verification are the next steps.

![](https://fabricate.hackclub-assets.com/ab72a4be396b5ea59338c801ebbb397687c24cba33959ad380f451734f7f8207/image-png/PCB_ByteForge_Carrier_2026-11-07.png)
![](https://fabricate.hackclub-assets.com/4a3c265eac8405340c8a228f2cfb80cd11ffbb73722773c5e47bc27a3bb08732/image-png/SCH_ByteForge_Carrier_1-ByteForge_Carrier_2026-11-07.png)

**Total time spent: 4h 30m**

# November 8, 2026 (entry 2): Carrier A1 Routing and Design Verification
<!-- fabricate:entry 2380 -->

This entry moved ByteForge from the preliminary unrouted carrier to the routed A1 revision. The two-layer PCB connects the Tang Nano sockets, LCD connector, seven buttons, and dedicated LCD power circuit, with ground fills on both layers. The Right button uses the corrected FPGA pin 72 assignment. After importing A1 into EasyEDA, I encountered a schematic–PCB mismatch, missing-footprint errors for the supply markers, and copper-clearance errors. I excluded the supply markers from PCB conversion and the BOM, synchronised the schematic and PCB, and aligned the copper-fill clearance settings. The final EasyEDA DRC reported no issues. The saved verification reports also record passing schematic and PCB checks, all 17 FPGA regression entries passing, and an internal timing result of 93.07 MHz against the 27 MHz target. I saved the corrected EasyEDA project, created a backup, and collected the schematic, routing image, and DRC screenshot. Physical operation and enclosure fit still need testing.

![](https://fabricate.hackclub-assets.com/02232a0ff47d47035bbeb2dd8b96951f4b33c10722418a13ff8c1c25cb53176b/image-png/ByteForge_A1_EasyEDA_DRC_Pass.png)
![](https://fabricate.hackclub-assets.com/dbc0a5294f855b8a8280fbf5c6cdb85500bde7b655708637dc1fa7aee6033499/image-png/ByteForge_A1_Routing.png)
![](https://fabricate.hackclub-assets.com/94f2ee5a1b32ca58c7dc85623a17449310e3f71b3c2eede3364e531ed65d59b3/image-png/ByteForge_A1_Schematic.png)

**Total time spent: 3h**

# November 9, 2026: Designing the ByteForge Enclosure
<!-- fabricate:entry 2474 -->

This entry focused on how the routed A1 board would fit into a handheld case. I used the 90 × 110 mm PCB as the starting point so the four standoffs and seven button guides line up with the board. The E0 design puts the display above the controls, leaves an opening for USB access, and uses separate screws for the lid so it can come off without removing the PCB. The base, lid, plungers and caps were exported as separate STL files and checked for closed meshes. The PCB itself stayed the same. Before printing the full case, I still need to check the display’s mounting points and retention, make sure the actual USB plug can reach the recessed port, and test the button travel on a small fit print.

![](https://fabricate.hackclub-assets.com/9601cb305b5b44b621d454e218bb7d7997fcdf3b1c6278e3eef0a8c95f53b88f/image-png/ByteForge_E0_Preview.png)

**Total time spent: 1h 30m**

# November 9, 2026 (entry 2): Pre-Order Review and Grant Prep
<!-- fabricate:entry 2478 -->

This entry focused on getting ByteForge ready for design review before ordering parts. The fabrication audit confirmed that the A1 board outline is 90 × 110 mm and that all 94 drill locations match the PCB design. I also put together a provisional budget of S$223 for one handheld, including five bare PCBs, spare components, printing, and delivery. Since Entry 14, the enclosure has moved from the E0 prototype to E1, which brings the carrier, Tang Nano, display, and controls together in one STEP assembly. Nothing has been ordered yet. Once funding is approved, the next step is to get a final quote, then check the enclosure fit with the actual parts before printing the full case.

![](https://fabricate.hackclub-assets.com/c4f49e969a239b53db28aa44994569c6e6710e31a2da190577a041f9f57d838e/image-png/ByteForge_Entry15_Journal.png)
![](https://fabricate.hackclub-assets.com/9aeb65ad1631d451f58ab999d91f8e622f96ac73514159b136d5f3eb88d04897/image-png/ByteForge_A1_E1_Assembly.png)

**Total time spent: 1h**
