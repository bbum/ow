# Owon Oscilloscope Wire Protocol & .bin File Format

Reverse-engineered notes for an Owon **SDS7102** (100 MHz, 1 GS/s, deep-memory-capable).
Sources: the 2013 ObjC `ow` codebase (now deleted) and live captures from a real
device at 10.0.1.230:3000 saved under `test-data/`. Captured here so the rewrite
can stand on its own.

> **Important:** The live network protocol and the USB-saved `.bin` file format
> are **NOT the same layout**. The 2013 code parsed the USB-saved format and
> accidentally never saw the live network format (it dumped the bytes to disk
> and never decoded them). The new parser must handle both.

## Wire Protocol (TCP)

- Default port: **3000**
- Default host on this LAN: `10.0.1.230`
- ASCII commands terminated with `\n`
- Connection is opened, command is sent, scope streams the response, then drops
  the connection (verified: 8s netcat with `-w 8` returns clean EOF after the
  expected byte count).

### Known commands

| Command | Wire bytes | Response |
|---------|------------|----------|
| Screenshot | `STARTBMP\n` | 12-byte envelope + raw BMP file |
| Binary capture | `STARTBIN\n` | 12-byte envelope + live `.bin` body |

### 12-byte response envelope (both commands)

All multi-byte fields little-endian.

| Offset | Type   | Field          | Notes |
|--------|--------|----------------|-------|
| 0      | int32  | `payloadLength`| Bytes that follow the envelope. Verified: matches actual BMP body size to the byte; matches `len(stripped_bin)` for STARTBIN. |
| 4      | int32  | unknown        | Old code skipped. Live STARTBMP showed a non-zero value (`0x9b1c389c`), STARTBIN showed `0`. Possibly checksum, timestamp, or capture-id. **TODO: identify.** |
| 8      | int32  | `flag`         | STARTBMP: `1`. STARTBIN (this scope, normal capture): `128`. Old code rejected `flag > 128` as "deep-memory dump". The live boundary value of `128` means the old `>` comparison should be `>=` — or, more likely, the flag's real meaning is something else (capture mode bits?). **TODO: identify.** |

The 12-byte envelope is *not* part of the BMP/`.bin` file body.

## Live STARTBIN Body Layout (SDS7102)

Bytes are *after* the 12-byte envelope is stripped. Sample fixture:
`test-data/live-startbin-sds7102.raw` (envelope-included; strip first 12 bytes
to get the body shown here). Total body = 6193 bytes for this 3040-sample
capture.

| Offset | Size | Type    | Field                | Live value | Notes |
|--------|------|---------|----------------------|-----------|-------|
| 0      | 6    | ASCII   | `deviceIdentifier`   | `SPBS02`  | `SPBS` prefix marks SDS-family devices. |
| 6      | 4    | bytes   | unknown              | `65 00 11 80` | Possibly version/format word. **TODO: identify.** |
| 10     | 9    | ASCII   | padding (spaces)     | `' ' × 9` | |
| 19     | 13   | ASCII   | `model + serial`     | `SDS7102125102` | "SDS7102" model + "125102" serial. |
| 32     | 1    | ASCII   | unknown              | `1`       | Possibly channel count or firmware variant. |
| 33     | 9    | bytes   | reserved/zero        | `00 × 9`  | |
| 42     | 4    | bytes   | unknown              | `02 01 00 50` | |
| 46     | 4    | ASCII   | `tag`                | `PCGs` (or similar — 4-char magic) | Possibly format magic. **TODO: identify.** |
| 50     | 4    | bytes   | unknown              | `00 65 2B 00` | |
| 54     | 3    | ASCII   | `channelIdentifier`  | `CH1`     | Match `^CH[0-9]$`. **Use this as anchor when parsing — preamble shape may vary.** |
| 57     | 4    | int32   | `blockLength`        | `-6136`   | Negative → "extended" capture, read flag word next. **NOT a reliable sample-byte count** — use `collectionPointCount` instead. |
| 61     | 4    | int32   | `extendedFlags`      | `2`       | Bit 0 = `deepMemoryCapture`, Bit 1 = `deepMemoryCapable`. Live = capable but not in deep mode. |
| 65     | 4    | int32   | `blockOffset`        | `0`       | SDS-only field (was conditional on `SPBS` prefix in old code). |
| 69     | 4    | int32   | `collectionPoint`    | `3040`    | |
| 73     | 4    | int32   | `collectionPointCount` | `3040`  | **Authoritative sample count** — matches body size: 3040 × 2 = 6080 sample bytes. |
| 77     | 4    | int32   | `slowScanningRange`  | `0`       | |
| 81     | 4    | int32   | `timeDivisor`        | `16`      | |
| 85     | 4    | int32   | `zeroPoint`          | `0`       | Sample value at 0V (subtract before scaling). |
| 89     | 4    | int32   | `voltsDivisor`       | `9`       | |
| 93     | 4    | int32   | `attenuation`        | `0`       | |
| 97     | 4    | float32 | `timeMultiplier`     | `2.5`     | |
| 101    | 4    | float32 | `frequency`          | `1000.0`  | **Hz — matches displayed F:1.000kHz exactly.** |
| 105    | 4    | float32 | `period`             | `1000.0`  | Units unclear (µs? matches T:1.000ms display if µs). **TODO: confirm units.** |
| 109    | 4    | float32 | `voltsMultiplier`    | `80.0`    | Looks like **mV per ADC count**: peak sample 61 × 80 mV ≈ 4.88V matches displayed Vp:5.04V. **TODO: confirm.** |
| 113    | rest | int16[] LE | `samples`         | 3040 × int16 | Range -1..62 in this fixture. Sample count = `collectionPointCount`, body bytes = count × 2. |

### Sample → real value (best current guess)

```
voltage_at_i = (sample[i] - zeroPoint) * voltsMultiplier / 1000.0   # if voltsMultiplier is mV/count
time_at_i    = i * timeMultiplier * 1e-6                            # if timeMultiplier is µs/sample
```

Sanity check from the live capture (1 kHz square wave, ~5V peak):
- Peak sample 62, zeroPoint 0, voltsMult 80 mV → 62 × 80 mV = 4.96V ≈ Vp 5.04V ✓
- 3040 samples × 2.5 µs = 7.6 ms total window. Display showed 500 µs/div × 12 div ≈ 6 ms. Close enough that 2.5 µs/sample is plausible. ✓

These formulas are **conjecture pending the manual** and may be wrong on the
voltsDivisor / attenuation interaction.

## USB-Saved .bin File Format (legacy, simpler)

`test-data/5v Calibration.bin` is a **different layout** — it's what the scope
writes when you save to a USB stick (or what the 2013 codebase fed back through
its decoder). It lacks the model/serial preamble seen in the network format.

| Offset | Size | Type        | Field                  | Notes |
|--------|------|-------------|------------------------|-------|
| 0      | 6    | ASCII       | `deviceIdentifier`     | `SPBS02` |
| 6      | 4    | int32       | `fileLength`           | Often a sentinel `0x00FFFFFF` — don't trust. |
| 10     | 3    | ASCII       | `channelIdentifier`    | `CH1` immediately after `fileLength`. |
| 13     | 4    | int32       | `blockLength`          | If negative, extended capture (read flags next). |
| +4     | 4    | int32       | `extendedFlags`        | Only if `blockLength < 0`. |
| +4     | 4    | int32       | `blockOffset`          | Only if device starts with `SPBS`. |
| ...    | ...  | ...         | (same int32/float fields as live format from `collectionPoint` onward) | |

### Reference values from `5v Calibration.bin`

```
deviceIdentifier   = "SPBS02"
fileLength         = 0x00FFFFFF (sentinel)
channelIdentifier  = "CH1"
blockLength        = -10056
extendedFlags      = 3 (deepMemoryCapture=YES, deepMemoryCapable=YES)
blockOffset        = 1200
collectionPoint    = 7600
collectionPointCount = 2,560,000   (suspect — file body is only 10000 bytes)
slowScanningRange  = 0
timeDivisor        = 4096
zeroPoint          = 0
voltsDivisor       = 1280
attenuation        = 256
timeMultiplier     = 2.5
frequency          = 1000.0
period             = 1000.0
voltsMultiplier    = 4.0
```

The fixture's `collectionPointCount = 2,560,000` doesn't match the body size
(10000 bytes). Either it's a deep-memory file with a separate body convention,
or some fields shift around for deep-memory captures (extendedFlags = 3 here vs.
2 live). **TODO: re-record this fixture from a known-good capture once we trust
the live format.**

## Parser Strategy for the Rewrite

1. **Distinguish formats** by checking the byte at offset 10:
   - If it's an ASCII letter starting "CH" → it's the **USB-saved** format.
   - Otherwise → it's the **live network** format with a metadata preamble.
   - Or: scan forward from offset 6 for the first `^CH[0-9]$` ASCII marker.
2. Read deviceIdentifier (6 bytes).
3. Read or skip preamble per format detection.
4. Anchor on `CH<n>` for channel identifier (3 bytes).
5. Read `blockLength` (signed int32 LE). If negative, read `extendedFlags` next.
6. If `deviceIdentifier.hasPrefix("SPBS")`, read `blockOffset` (int32 LE).
7. Read remaining int32 fields (`collectionPoint` through `attenuation`).
8. Read four float32 fields (`timeMultiplier`, `frequency`, `period`, `voltsMultiplier`).
9. Remaining body is `collectionPointCount` × int16 LE samples.

## Open Questions for the Manual

- Authoritative sample → voltage / time formula (units of every field).
- Meaning of `voltsDivisor` and `attenuation` when `voltsMultiplier` already
  appears to be in real units (mV/count).
- The unknown 4-byte "channel count?" / "firmware variant?" field at body
  offset 32, the `02 01 00 50` block at offset 42, the `PCGs`-like tag at 46.
- Multi-channel `.bin` layout (separate request per channel? interleaved? new command?).
- Deep-memory capture envelope (does the `flag` field in the 12-byte envelope
  encode this, or is it the `extendedFlags` bit?).
- Whether the scope speaks **SCPI** in addition to `STARTBMP` / `STARTBIN`. If so:
  - List of supported commands (`*IDN?`, `:CHAN1:SCAL?`, `:TIM:SCAL?`, etc.)
  - Whether settings can be changed remotely (timebase, voltage scale, trigger).
  - This determines how rich the MCP tool surface can be — capture-only vs.
    full remote-control.
- The `STARTBMP` envelope's second int32 (`0x9b1c389c` in our capture) — is that
  a checksum, capture timestamp, or something else?

## Defaults / Configuration

The rewrite uses the defaults suite **`net.bbum.ow`** (replacing the legacy
`com.friday.ow`) with keys `host` (string) and `port` (integer).

## Code-Shape Lessons (not protocol)

- The 2013 code used run-loop + stream callbacks and `exit()` from inside the
  callback. New code should use `Network.framework` (`NWConnection`) bridged to
  `async/await` via continuations.
- No timeouts in the old code — add configurable connect/read timeouts.
- Old code never gracefully closed the connection (just exited the process).
- Old code never decoded sample data into voltages or time. CSV export was
  stubbed. Both of those are first-class deliverables for the rewrite.

## Live Test Fixtures

- `test-data/live-startbmp-sds7102.raw` — 12-byte envelope + 1,440,054-byte BMP (800×600×24).
- `test-data/live-startbin-sds7102.raw` — 12-byte envelope + 6,193-byte body containing 3040 int16 samples of a 1 kHz square wave at ~5V.
- `test-data/SampleImage.bmp` — pre-stripped BMP (no envelope; from 2013 capture).
- `test-data/5v Calibration.bin` — pre-stripped USB-saved-format .bin (no envelope; 2013 capture).
