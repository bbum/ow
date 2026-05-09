# OWON SDS7102V LAN/TCP Protocol Research Handoff

## Goal

Build a Swift MCP server that gives an LLM as much practical remote capability as possible over an OWON SDS7102V oscilloscope.

This document assumes the existing local findings are correct and does **not** re-prove them. The highest-value next step is to test whether the proprietary binary control packets from `owoncontrol-qt` work over the SDS7102V LAN socket.

---

## Known local ground truth

Hardware:

- OWON SDS7102V
- 100 MHz, 1 GS/s, 10M deep memory, dual channel
- Binary captures identify it as device `SPBS02`
- Model/serial observed as `SDS7102125102`
- Manual: **SDS Series User Manual, Nov 2017 edition V1.7.4**
- Manual has no programming reference; only describes OWON Windows GUI software

Confirmed data socket:

- TCP port: `3000`
- ASCII commands terminated with `\n`

Confirmed commands:

| Command | Status | Response |
|---|---:|---|
| `STARTBMP\n` | verified | 12-byte envelope + raw 800x600x24 BMP |
| `STARTBIN\n` | verified | 12-byte envelope + `.bin` body, single capture |
| `STARTMEMDEPTH\n` | verified | 12-byte envelope + `.bin` body, deep-memory capture |

12-byte envelope, little-endian:

| Offset | Type | Meaning |
|---:|---|---|
| 0 | `int32` | payload length |
| 4 | `int32` | unknown; zero on `STARTBIN`, nonzero on `STARTBMP` |
| 8 | `int32` | flag; observed `128` for BIN/MEMDEPTH, `1` for BMP |

Already probed and confirmed unsupported / zero-byte response:

- SCPI: `*IDN?`, `*RST`, `*OPC?`, `:SYST:VERS?`, `:MEAS:FREQ?`, `:TIM:SCAL?`, `:CHAN1:SCAL?`
- Owon-ish queries: `STARTSET`, `STARTINFO`, `STARTID`, `STARTSTAT`, `IDN`, `GETID`, `QUERY`
- Other deep-memory guesses: `STARTMEM`, `STARTDEPTH`, `STARTHIMEM`, `STARTBIG`, `STARTLONG`, `STARTHMD`, `STARTDM`

OWON Windows GUI behavior:

- Exposes only three transfer modes:
  - WaveForm = `STARTBIN`
  - Image = `STARTBMP`
  - High Memory Depth = `STARTMEMDEPTH`
- “Keep Getting Delay (ms)” is client-side timer polling.
- GUI does **not** expose remote setting control.

Local parser reference:

- Authoritative project notes are in:
  - `/Users/bbum/Developer/ow/PROTOCOL.md`

---

## Core conclusion from external research

The most promising control path is **not SCPI** and probably not ASCII `STARTxxx`.

The strongest public evidence points to this architecture:

- Capture/data commands are ASCII on TCP port 3000.
- Scope-control commands are proprietary binary packets.
- `owoncontrol` / `owoncontrol-qt` contain packet-captured command arrays originally discovered from OWON’s official Windows software.
- `owoncontrol-qt` includes a LAN transport path and targets the SDS7102V.

Therefore the implementing agent should test whether the same binary command packets work over the existing TCP/3000 LAN connection.

---

# Tier 1 — highest-value sources for real remote control

## 1. `7oxicshadow/owoncontrol`

Link:

- <https://github.com/7oxicshadow/owoncontrol>

Takeaway:

- This is the strongest lead for actual remote-control support.
- README says commands were discovered by using Wireshark to monitor traffic from the official Windows app.
- Project is explicitly associated with the OWON SDS7102V.
- Supports changing scope settings, not just data capture.

Likely useful capabilities:

- channel coupling
- probe scale
- volts/div
- trace position
- memory depth
- timebase
- trigger controls
- autoset
- self-calibration
- factory reset

Implementation note:

- Mine this repo for command structure, but prefer the later `owoncontrol-qt` code first.

---

## 2. `7oxicshadow/owoncontrol-qt`

Link:

- <https://github.com/7oxicshadow/owoncontrol-qt>

Takeaway:

- Successor / Qt version of `owoncontrol`.
- Claims functional UI control of SDS7102V.
- Adds screenshot capture.
- Includes a LAN interface.
- Author notes LAN support is poor / packet-loss prone and recommends fixed IP or direct crossover-style setup.

Implementation note:

- Treat this as the primary source for the Swift MCP control API.
- Extract command byte arrays and enum mappings.
- Try the binary packets over TCP/3000 exactly as-is, without newline termination.

---

## 3. `owoncontrol-qt/usb_interface.cpp`

Link:

- <https://raw.githubusercontent.com/7oxicshadow/owoncontrol-qt/master/usb_interface.cpp>

Takeaway:

- Contains the actual binary command arrays.
- This is probably the single most important implementation source.

Command groups to port/test:

- `autoset`
- `self_cal`
- `factory_reset`
- `force_trigger`
- trigger level helpers: 50%, zero
- channel coupling
- probe scale
- volts/div
- memory depth
- timebase
- trace vertical position
- horizontal trigger position
- acquisition mode
- averaging count
- edge trigger
- alternate trigger
- video trigger

Implementation note:

- Start with low-risk commands only.
- Avoid `factory_reset` and `self_cal` until command transport is proven.
- Build a packet abstraction only after raw command replay is confirmed.

---

## 4. `owoncontrol-qt/owon_commands.h`

Link:

- <https://raw.githubusercontent.com/7oxicshadow/owoncontrol-qt/master/owon_commands.h>

Takeaway:

- Defines enum mappings needed to expose a sane Swift API.

Useful enum families:

- timebase values
- voltage ranges
- memory depth
- trigger mode
- trigger source
- trigger slope
- trigger coupling
- acquisition mode
- channel IDs

Implementation note:

- Use this header to validate public MCP tool schemas.
- Do not expose raw enum integers directly to the LLM unless also exposing symbolic names.

---

## 5. `owoncontrol-qt/lan_interface.cpp`

Link:

- <https://raw.githubusercontent.com/7oxicshadow/owoncontrol-qt/master/lan_interface.cpp>

Takeaway:

- Opens TCP socket to configurable IP and port.
- Uses `STARTBMP` for screenshot capture.
- Default/example port is `3000`.
- No strong evidence here for a separate control port.

Implementation note:

- This supports the hypothesis that binary control and ASCII capture may share TCP/3000.
- Verify by sending binary control packets over the same socket.

---

## 6. Rei-Labs SDS7102V article

Link:

- <https://www.rei-labs.net/fetching-data-from-owon-sds7102v-to-pc/>

Takeaway:

- Confirms SDS7102V does not respond to SCPI in the author’s tests.
- Documents TCP dump commands:
  - `STARTBMP`
  - `STARTBIN`
  - `STARTMEMDEPTH`
- Points to `owoncontrol` for parameter-changing support.

Implementation note:

- Useful independent confirmation matching the local observations.

---

## 7. pyvisa-py issue #145

Link:

- <https://github.com/pyvisa/pyvisa-py/issues/145>

Takeaway:

- SDS7102E user tried SCPI over `TCPIP0::<ip>::3000::SOCKET`.
- `*IDN?` was transmitted but not recognized by the scope.

Implementation note:

- Further evidence that SDS7102-class LAN does not expose normal SCPI on port 3000.

---

## 8. sigrok OWON SDS series wiki

Link:

- <https://sigrok.org/wiki/Owon_SDS_series>

Takeaway:

- Notes that SDS-series protocol includes simple text commands over USB/Ethernet for data.
- Some models support SCPI, but SDS7102 reportedly does not.
- Mentions special commands can trigger menu items.

Implementation note:

- Treat as background confirmation, not a complete driver source.

---

# Tier 2 — capture API, `.bin` format, envelope semantics

## 9. OWON Oscilloscope PC Guidance Manual v1.3

Link:

- <https://bikealive.nl/tl_files/EmbeddedSystems/Test_Measurement/owon/OWON%20Oscilloscope%20PC%20Guidance%20Manual.pdf>

Takeaway:

- Search result text indicates this manual documents SDS `START_COMMAND` values:
  - `STARTBIN`
  - `STARTBMP`
  - `STARTMEMDEPTH`
- Also identifies `RESPONSE_START_LENGTH = 12`.

Implementation note:

- Use this as the closest official-ish source for the three ASCII capture commands and 12-byte response prefix.
- If the PDF is hard to fetch, use sigrok’s linked copy/index.

---

## 10. sigrok SDS resources index

Link:

- <https://sigrok.org/wiki/Owon_SDS_series>

Takeaway:

- Links several canonical artifacts:
  - PC Guidance Manual
  - SDS SCPI protocol PDF
  - SDS service manual

Implementation note:

- Use this page as a jumping-off point for official and semi-official documents.

---

## 11. `bjonnh/owon-sds7102-protocol`

Link:

- <https://github.com/bjonnh/owon-sds7102-protocol>

Takeaway:

- C tools for dumping/parsing OWON SDS capture data.
- Tested with SDS7103 and SDS5032.
- Common base for later parsers.

Implementation note:

- Compare its struct definitions against local `/Users/bbum/Developer/ow/PROTOCOL.md`.
- Do not assume it is authoritative where it conflicts with local captures.

---

## 12. `bjonnh/parse.h`

Link:

- <https://raw.githubusercontent.com/bjonnh/owon-sds7102-protocol/master/parse.h>

Takeaway:

- Contains useful field names for `.bin` parsing:
  - `length`
  - `unknown1`
  - `type`
  - `model[7]`
  - `serial[30]`
  - `triggerstatus`
  - per-channel `samples_count`
  - `timediv`
  - `offsety`
  - `voltsdiv`
  - `attenuation`
  - `time_mul`
  - `frequency`
  - `period`
  - `volts_mul`

Implementation note:

- Useful naming reference, but semantics need validation against local captures.

---

## 13. `owoncontrol-qt/usb_interface.h`

Link:

- <https://raw.githubusercontent.com/7oxicshadow/owoncontrol-qt/master/usb_interface.h>

Takeaway:

- Defines response header struct:
  - `length`
  - `unknown`
  - `flag`
- Comments say `flag` is:
  - `0` for waveform
  - `1` for bitmap
  - `128` if multipart

Implementation note:

- Treat the comment as suspect.
- Local captures show `STARTBIN` already returns flag `128`, so the old interpretation is probably wrong or incomplete.

---

# Tier 3 — ecosystem / prior art

## 14. Official OWON SDS Series downloads

Link:

- <https://www.owon.com.hk/download.asp?SortTag=&category=Digital+Oscilloscope&model=&series=SDS+Series>

Takeaway:

- Official SDS Series download page lists:
  - PC software
  - user manual
  - LabVIEW development case
  - SCPI protocol for SDS Series DSO

Implementation note:

- Useful for collecting current official artifacts.
- Do not assume the SCPI PDF applies to the 2017 SDS7102V firmware.

---

## 15. Official OWON SDS1000 Series downloads

Link:

- <https://www.owon.com.hk/download.asp?SortTag=&category=Digital+Oscilloscope&model=&series=SDS1000+Series>

Takeaway:

- Lists SCPI commands for SDS1000 Series DSO.

Implementation note:

- Useful cross-reference for newer OWON command vocabulary.
- Probably not directly implemented on SDS7102V.

---

## 16. SDS1000 SCPI PDF mirror

Link:

- <https://technica-m.ru/upload/support_ext/owon_sds1000_oscilloscopes_scpi_protocol.pdf>

Takeaway:

- Documents standard-ish SCPI subsystems:
  - acquire
  - horizontal
  - channel
  - measurement
  - trigger
  - file
  - waveform

Implementation note:

- Only useful if a firmware/port path enabling SCPI is found.
- Current local evidence says SDS7102V does not accept these over TCP/3000.

---

## 17. OWON support application page

Link:

- <https://owonna.com/support_Application_list12>

Takeaway:

- Shows OWON publishes separate protocol/programming materials per model family.

Implementation note:

- Search this site for SDS-specific or older archived protocol PDFs.

---

## 18. sigrok supported hardware / OWON SDS

Link:

- <https://sigrok.org/wiki/Supported_hardware>

Takeaway:

- SDS7102 appears in sigrok ecosystem references, but not as evidence of a complete LAN control driver.

Implementation note:

- Useful lead, not a drop-in solution.

---

## 19. Christer Weinigel SDS7102 hacking article

Link:

- <https://blog.weinigel.se/2016/05/01/sds7102-hacking.html>

Takeaway:

- Deep hardware/firmware reverse-engineering context.
- Identifies SoC, FPGA, Ethernet MAC/PHY, NAND, and serial console details.
- Mentions Ethernet instability/crashes on his unit.

Implementation note:

- Useful if firmware spelunking becomes necessary.
- Not a published LAN command set.

---

## 20. Christer / wingel `sds7102` repo

Link:

- <https://github.com/wingel/sds7102>

Takeaway:

- Linux/buildroot-related work for SDS7102.

Implementation note:

- Useful for firmware-level archaeology, not first-pass MCP implementation.

---

## 21. EEVblog SDS7102 reverse-engineering thread

Link:

- <https://www.eevblog.com/forum/testgear/review-of-owon-sds7102/1680/?wap2=>

Takeaway:

- Search result text mentions “control interface to enable SCPI protocol and communicate through SCPI protocol.”
- Page may be captcha-blocked from automated fetches.

Implementation note:

- Manually search EEVblog for:
  - `SDS7102 SCPI enable`
  - `SDS7102 control interface`
  - `SDS7102 STARTBIN`
  - `Owon SDS7102 Wireshark`
  - `SPBS02`

---

# Recommended implementation path

## Phase 1 — prove binary control over LAN

Use the existing TCP/3000 connection.

Test sequence:

1. Connect TCP to scope on port `3000`.
2. Verify capture path with `STARTBMP\n`.
3. Send one low-risk binary command from `owoncontrol-qt/usb_interface.cpp`, with no newline.
4. Immediately issue `STARTBMP\n` or `STARTBIN\n` to verify whether scope state changed.
5. Repeat with a small set of safe commands.

Suggested first commands:

- `force_trigger`
- set trigger level to 50%
- horizontal timebase change
- volts/div change on currently visible channel
- channel coupling change only if a harmless test signal is connected

Avoid initially:

- `factory_reset`
- `self_cal`
- anything that changes calibration or persistent settings

Important detail:

- ASCII capture commands are newline-terminated.
- Binary control packets should be sent exactly as raw bytes from the repo, with no trailing newline, unless the source code clearly does otherwise.

---

## Phase 2 — build Swift protocol layer

Proposed Swift layers:

1. `OwonTransport`
   - TCP connect/read/write
   - timeout handling
   - reconnect
   - optional socket drain

2. `OwonCaptureClient`
   - `captureBitmap()`
   - `captureWaveform()`
   - `captureDeepMemory()`
   - parses 12-byte envelope
   - validates payload length

3. `OwonBinaryControlClient`
   - raw packet sender
   - symbolic wrappers around command arrays
   - optional read-after-write behavior if commands produce responses

4. `OwonBinParser`
   - local `.bin` parser from `/Users/bbum/Developer/ow/PROTOCOL.md`
   - field validation
   - channel extraction
   - sample scaling

5. `OwonMCPServer`
   - exposes LLM-safe tools
   - limits destructive operations
   - snapshots before/after setting changes

---

## Phase 3 — MCP tool design

Suggested MCP tools:

### Safe capture tools

- `owon.capture_screen()`
- `owon.capture_waveform()`
- `owon.capture_deep_memory()`
- `owon.get_waveform_summary()`
- `owon.get_channel_samples(channel)`
- `owon.export_capture(format)`

### Conditionally safe control tools

- `owon.autoset()`
- `owon.force_trigger()`
- `owon.set_timebase(value)`
- `owon.set_channel_scale(channel, volts_per_div)`
- `owon.set_channel_coupling(channel, coupling)`
- `owon.set_trigger_source(channel)`
- `owon.set_trigger_slope(slope)`
- `owon.set_trigger_level(level)`
- `owon.set_memory_depth(depth)`

### Dangerous / gated tools

Require explicit user confirmation or disable by default:

- `owon.self_calibrate()`
- `owon.factory_reset()`
- any persistent setup write if discovered

---

## Open questions for the implementing agent

1. Do `owoncontrol-qt` binary command packets work over TCP/3000 on this exact SDS7102V?
2. Do binary control packets return responses, or are they fire-and-forget?
3. Is there a required initialization packet before control commands?
4. Does the scope tolerate mixing binary control packets and ASCII `STARTxxx` captures on one socket?
5. Is one command per TCP connection safer than a persistent socket?
6. Is the 12-byte envelope used only for capture responses, or also for binary command responses?
7. Does the unknown envelope int32 correlate with bitmap metadata, capture sequence, checksum, timestamp, or payload type?
8. Can the Windows app be packet-captured during setting changes if connected over LAN, or does it only use USB for control?
9. Does any firmware image expose SCPI, or is SCPI only for newer SDS/SDS1000 families?
10. Is there a hidden service/control port? If binary packets fail on 3000, scan only the scope host carefully on the local LAN.

---

## Concrete next probe script behavior

The first probe tool should support:

- connect to `host:3000`
- send `STARTBMP\n`
- parse envelope
- save screenshot
- send one named raw binary command from `owoncontrol-qt`
- wait briefly
- send `STARTBMP\n` again
- save second screenshot
- compare or present before/after images

Suggested first test:

1. Display a stable test waveform.
2. Capture screenshot A.
3. Send a safe timebase or volts/div binary command.
4. Capture screenshot B.
5. Confirm visible grid/waveform changed.

If that works, the MCP server becomes a real remote-control server rather than capture-only.

---

## Key implementation warning

Do not overfit to SCPI.

For this SDS7102V generation, evidence strongly points to:

```text
ASCII STARTxxx commands -> capture/export only
binary proprietary packets -> scope control
same TCP/3000 socket likely, but must be verified
```

The fastest path to value is replaying `owoncontrol-qt` command packets over LAN and validating with screenshots/waveform captures.
