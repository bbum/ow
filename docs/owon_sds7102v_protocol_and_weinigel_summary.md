# OWON SDS7102V Protocol Work — Weinigel Hardware/FPGA Series Addendum

Purpose: capture the value of the remaining Christer Weinigel SDS7102 reverse-engineering posts for the SDS7102V Swift MCP server project.

Bottom line: **these posts are amazing, but not useful as direct LAN/TCP protocol documentation.** They are hardware/firmware archaeology. Keep them as references for invasive firmware work, FPGA work, analog-front-end validation, or interpreting what control commands physically change. Do not let the implementation agent burn time mining them for TCP command syntax.

## Current implementation priority

1. Keep protocol work focused on `owoncontrol-qt` / `owoncontrol`.
2. Treat the OWON network protocol as two families:
   - ASCII capture/export commands: `STARTBMP\n`, `STARTBIN\n`, `STARTMEMDEPTH\n`.
   - Proprietary binary control packets from `owoncontrol-qt`.
3. Test binary control packets over TCP/3000, without newline, then verify state changes using `STARTBMP` or `STARTBIN`.
4. Do not chase the Weinigel series unless:
   - TCP control packets fail and we decide to disassemble firmware.
   - We want to replace/patch firmware.
   - We need hardware-level confirmation of what a command changes.

## Classification

| Source family | Protocol value | Usefulness |
|---|---:|---|
| `owoncontrol-qt` | High | Actual discovered command bytes and LAN transport code |
| `owoncontrol` | High | Original Wireshark-derived command work |
| OWON PC Guidance Manual | Medium | Official-ish capture command/envelope confirmation |
| bjonnh `owon-sds7102-protocol` | Medium | `.bin` parsing prior art |
| Weinigel SDS7102 series | Low for protocol / high for hardware | Firmware, FPGA, AFE, buses, Linux port, invasive RE |

## Last four Weinigel links

### 1. The analog frontend of the SDS7102

URL: https://blog.weinigel.se/2016/07/15/sds7102-afe.html

Takeaway: **hardware-level map of attenuation, coupling, gain, trigger-level DACs, trigger muxing, sampling-clock control, ADC configuration, and vertical-position DAC path. Not a LAN protocol source.**

Useful details:

- AC/DC coupling:
  - Channel 1 solid-state relay: `GPA0`.
  - Channel 2 solid-state relay: `GPD8`.

- Attenuation relays:
  - Channel 1 uses `GPA1` and `GPA15` as paired/opposite attenuation controls.
  - Channel 2 uses `GPH12` and `GPE1`.
  - High attenuation is approximately 10x relative to low attenuation.

- Trigger path:
  - Each channel has a four-channel mux feeding trigger circuitry.
  - Channel 2 can switch trigger circuitry to external trigger via relay on `GPE3`.
  - External trigger has its own low/high attenuation relay.
  - Trigger mux outputs feed a dual PECL comparator.
  - Rohm DAC outputs `AO1` and `AO2` are trigger comparator reference voltages.
  - FPGA differential pairs later corrected as:
    - Channel 1 comparator output: `B6/A6`.
    - Channel 2 comparator output: `C9/A9`.

- SPI bus:
  - ADC, ADF sampling-clock synthesizer, Rohm DAC, LMH variable-gain amplifiers, and DAC8532 are behind an FPGA-originated SPI bus.
  - Different devices require different CPOL/CPHA/chip-select behavior.
  - LMH6518 gain, ADF frequency, and ADC config were all controllable once SPI timing was correct.
  - DAC8532 controls vertical position through an op-amp scale/shift path.

- Practical interpretation:
  - If binary control packets work, this post tells us what they are likely driving physically.
  - Useful for naming MCP tools and debug output.
  - Not useful for discovering TCP packet format.

Suggested MCP relevance:

- `setChannelCoupling(channel, ac|dc)` maps conceptually to the GPA0/GPD8 relay path.
- `setChannelScale(channel, voltsPerDiv)` probably changes both attenuation relays and LMH gain.
- `setTriggerLevel(channel, volts)` maps conceptually to Rohm DAC comparator reference.
- `setVerticalOffset(channel, offset)` maps conceptually to DAC8532.

### 2. Source code for my SDS7102 port

URL: https://blog.weinigel.se/2016/07/16/sds7102-source.html  
Repo: https://github.com/wingel/sds7102

Takeaway: **source code exists for a Linux + FPGA port to the SDS7102. It is not an OWON protocol implementation.**

Useful details:

- The post is short; it announces that the cleaned-up Linux port and FPGA image are on GitHub.
- The repo is a Linux/buildroot port to the OWON SDS7102.
- The repo README describes the platform as:
  - Samsung S3C2416 SoC.
  - Xilinx Spartan-6 FPGA doing most signal processing.
  - Ethernet is functional but uses bit-banged `spi-gpio` because hsspi was not working, limiting performance.
  - LCD, USB host/slave, FPGA configuration from SoC are functional.
  - SoC DDR2 bus / FPGA communication work was in progress.

Practical interpretation:

- Useful if we ever want invasive firmware replacement or Linux-side service development.
- Not useful for the stock OWON LAN protocol.
- Do not include this repo as a runtime dependency for the Swift MCP server.

### 3. The fast buses on the SDS7102

URL: https://blog.weinigel.se/2016/07/25/sds7102-fast-buses.html

Takeaway: **deep explanation of SoC↔FPGA DDR-style bus and FPGA↔DDR memory bus. Useful for firmware/FPGA work only.**

Useful details:

- Important bus: SoC to FPGA.
  - FPGA emulates DDR2 memory connected in parallel with real DDR2 memory to the SoC.
  - Runs around 133 MHz with data on both clock edges.
  - The bus has multiple clock domains because DDR uses DQS strobes per byte lane.

- Simplification idea:
  - Since most traffic is sample data FPGA → SoC, Weinigel initially considered read-only DDR emulation.
  - Low-rate SoC → FPGA control could be done over an existing slow SPI path.
  - A read from a specific address could signal “finished reading; perform new capture.”

- DDR protocol notes:
  - Burst length for the SDS7102 DDR memory path is four 16-bit words.
  - DDR transactions include bank activate, reads/writes, precharge, CAS latency, burst behavior.
  - Timing was sensitive; registering external signals delayed data too much until he removed a wasted cycle.
  - Added Xilinx `IODELAY2` to delay DQS slightly and reduce corrupted bits.

- FPGA DDR memory:
  - OWON ignored Xilinx’s RZQ recommendation.
  - By setting `C3_CALIB_SOFT_IP = FALSE`, he could synthesize a memory controller without RZQ.
  - DDR controller appeared to work up to 333 MHz, giving theoretical burst bandwidth around 1333 MB/s.
  - 400 MHz produced errors.

Practical interpretation:

- This explains the physical data path behind deep-memory capture.
- It does **not** document the stock `STARTMEMDEPTH` file format or the LAN command protocol.
- Useful only if implementing custom firmware or trying to reason about capture corruption/noise.

### 4. Capturing ADC data into DDR memory on the SDS7102

URL: https://blog.weinigel.se/2016/08/15/sds7102-ddr-capture.html

Takeaway: **custom FPGA capture path achieved deep high-speed acquisition, but outside stock firmware/protocol.**

Useful details:

- Weinigel made the emulated DDR2 memory on the SoC bus read/write.
- He could use the fast SoC bus for both:
  - controlling the FPGA;
  - reading data out of the FPGA.
- This required hardcoded FPGA IODELAYs.
  - He warned those delays may differ between FPGA production lots.
  - Therefore, the bitstream may not work reliably on other SDS7102 units without calibration.

- ADC-to-DDR capture:
  - Captured samples from ADC into DDR2 memory connected to FPGA.
  - Claimed up to 64 million samples at 1 GS/s in custom firmware.
  - Initial FIFO design dropped samples.
  - Fix involved watching FIFO count (`wr_count`) rather than registered full flag (`wr_full`) so writes stopped before overflow.

- Visualization:
  - Extracted 1 ms = 400,000 samples at 400 MS/s per channel.
  - Rendered analog-ish intensity graphs using Python post-processing.
  - 100 ns view used 400 samples.
  - He preferred 400 MS/s because 500 MS/s showed significantly more noise.

Practical interpretation:

- Not relevant to stock LAN/TCP protocol.
- Interesting evidence that the hardware can support much deeper/faster capture than the stock software exposes.
- Potentially relevant only for future “replace firmware / custom capture engine” ambitions.

## Protocol relevance of the Weinigel series as a whole

### What it gives us

- Hardware identity and topology.
- Bootloader / NAND / filesystem / OS layout context.
- GPIO mapping.
- FPGA pin mapping.
- Front-panel mapping.
- AFE control paths.
- Trigger path understanding.
- Custom Linux + FPGA port source.
- Evidence that the scope can be deeply controlled if firmware is replaced.

### What it does **not** give us

- No published stock TCP command list.
- No stock LAN control-port discovery.
- No SCPI enable path.
- No packet captures of OWON Windows software.
- No direct `.bin` format spec for stock network captures beyond what other projects already expose.
- No semantics for the 12-byte TCP envelope beyond what other sources have guessed.

## How to use this in the MCP implementation

### Do now

- Implement a robust TCP client for port 3000.
- Keep known capture commands:
  - `STARTBMP\n`
  - `STARTBIN\n`
  - `STARTMEMDEPTH\n`
- Parse 12-byte little-endian response envelope:
  - `int32 payloadLength`
  - `int32 unknown`
  - `int32 flag`
- Parse response body based on command:
  - BMP body for image capture.
  - `.bin` body for waveform capture.
- Mine `owoncontrol-qt` for binary control packets.
- Test those binary packets over TCP/3000.
- Verify control effects using screenshot/waveform captures.

### Do later, only if stock protocol stalls

- Search stock firmware image for:
  - `STARTBMP`
  - `STARTBIN`
  - `STARTMEMDEPTH`
  - `START`
  - TCP socket setup
  - command parser tables
  - binary packet dispatch tables
- Use Weinigel repo/notes to orient firmware extraction/disassembly.
- Use AFE/GPIO/FPGA notes to understand physical side effects.

### Do not do initially

- Do not port Weinigel’s Linux/FPGA stack.
- Do not try to make custom FPGA bitstreams.
- Do not rewrite capture hardware.
- Do not spend time mapping AFE relays unless binary control tests produce ambiguous behavior.
- Do not assume Weinigel’s custom capture path corresponds to stock `STARTMEMDEPTH`.

## Recommended source appendix ordering for the agent

### High-priority protocol sources

1. `7oxicshadow/owoncontrol-qt`
   - Actual binary command arrays.
   - LAN transport code.
   - Likely best implementation source.

2. `7oxicshadow/owoncontrol`
   - Original Wireshark-derived SDS7102V control work.

3. OWON PC Guidance Manual
   - Official-ish `STARTBIN`, `STARTBMP`, `STARTMEMDEPTH`, 12-byte response frame evidence.

4. `bjonnh/owon-sds7102-protocol`
   - `.bin` parser prior art.

5. Rei-Labs SDS7102 article
   - Confirms TCP capture commands and points at existing reverse-engineered tools.

### Low-priority but valuable hardware references

1. Weinigel SDS7102 series index / first post:
   - https://blog.weinigel.se/2016/05/01/sds7102-hacking.html

2. AFE:
   - https://blog.weinigel.se/2016/07/15/sds7102-afe.html

3. Source:
   - https://blog.weinigel.se/2016/07/16/sds7102-source.html
   - https://github.com/wingel/sds7102

4. Fast buses:
   - https://blog.weinigel.se/2016/07/25/sds7102-fast-buses.html

5. DDR capture:
   - https://blog.weinigel.se/2016/08/15/sds7102-ddr-capture.html

## One-line conclusion

The Weinigel work proves the SDS7102 is deeply understandable and hackable, but for the Swift MCP server the shortest path remains: **port `owoncontrol-qt` binary commands, send them over TCP/3000, verify with `STARTBMP`/`STARTBIN`, and treat Weinigel as the appendix for when things get weird.**
