# CLAUDE.md

## What This Is

`ow` is a CLI + MCP stdio server for driving an Owon SDS-series oscilloscope over LAN.
Captures screenshots, single waveforms, and deep-memory waveforms; parses the resulting
`.bin` files; exposes the same operations to LLMs as MCP tools so an agent can inspect
hardware in real time.

Target hardware: SDS7102V (and likely the rest of the SDS series — 6062 / 7072 / 7102
/ 7202 / 8102 / 8202 / 8302 / 9302 — though only the 7102V has been verified).

Default scope on this LAN: `10.0.1.230:3000`. Persisted in `net.bbum.ow` defaults.

## Build / Test / Install

```
swift build              # debug
swift test               # run BinFile parser tests against test-data fixtures
make build               # release
make install             # release → ~/.local/bin/ow
```

Swift 6.2, SPM single executable target, macOS 26+, Apple-frameworks-only
(`Network` for TCP, `AppKit` for BMP→PNG).

## Architecture

```
Sources/ow/
├── ow.swift                    # @main + @OptionGroup ScopeOptions
├── Scope/                      # domain layer
│   ├── ScopeConfig.swift       # host/port/timeouts + net.bbum.ow defaults
│   ├── BinaryReader.swift      # little-endian byte reader
│   ├── WireProtocol.swift      # commands + 12-byte response envelope
│   ├── ScopeClient.swift       # NWConnection async wrapper, idle-timeout
│   ├── BinFile.swift           # parser (handles both live + USB-saved layouts)
│   └── BMP.swift               # BMP→PNG via NSBitmapImageRep
├── Subcommands/                # one struct per CLI subcommand
│   ├── ScreenCommand.swift     #  ow screen <out>
│   ├── DataCommand.swift       #  ow data <out>           (STARTBIN)
│   ├── MemDepthCommand.swift   #  ow memdepth <out>       (STARTMEMDEPTH)
│   ├── BinCommand.swift        #  ow bin [--csv] <files>
│   ├── ConfigCommand.swift     #  ow config get|set host|port
│   ├── StatusCommand.swift     #  ow status [--quick]
│   └── MCPCommand.swift        #  ow mcp [tools…]
└── MCP/                        # JSON-RPC stdio server (modeled on spot)
    ├── JSONRPCTypes.swift
    ├── MCPTool.swift
    ├── MCPServer.swift         # MCPTools enum factory + server loop
    └── Tools/
        ├── ScopeStatusTool.swift          (scope_status)
        ├── CaptureScreenshotTool.swift    (capture_screenshot)
        ├── CaptureWaveformTool.swift      (capture_waveform)
        └── ParseBinFileTool.swift         (parse_bin_file)
```

## Wire Protocol

Reverse-engineered. The vendor manual documents nothing about the protocol —
all knowledge is in `PROTOCOL.md` at repo root and the test-data fixtures.

Three known commands (all ASCII, terminated by `\n`, port 3000):
- `STARTBMP\n` — screenshot, returns 12-byte envelope + BMP file
- `STARTBIN\n` — single waveform capture, envelope + .bin body
- `STARTMEMDEPTH\n` — deep-memory waveform capture, envelope + larger .bin body

The scope does **not** speak SCPI. There is no remote-control surface — only
capture-and-analyze. All probing returned 0 bytes for `*IDN?`, `:TIM:SCAL?`, etc.

Two `.bin` body layouts exist:
- **Live network**: includes a metadata preamble with model+serial.
- **USB-saved**: legacy layout with no preamble. Parser detects via lookahead for `CH<n>` at offset +4.

## MCP Surface

Four tools. Schema is in each tool's source; brief overview:

| Tool                   | What it does                                                    |
|------------------------|-----------------------------------------------------------------|
| `scope_status`         | Probe + identify. Pass `quick=true` for TCP-only.               |
| `capture_screenshot`   | Capture display, return PNG inline. Optional `save_path`.       |
| `capture_waveform`     | Capture + parse. Summary by default; `include_samples` / `decimate` for arrays. `deep_memory=true` for STARTMEMDEPTH. |
| `parse_bin_file`       | Parse a saved `.bin` from disk. Same JSON shape as `capture_waveform`. |

All capture tools accept `host` / `port` overrides per-call. Defaults come from
`net.bbum.ow` (set via `ow config set host …`).

## Conventions

- Each capture tool defaults to **summary statistics**, not raw samples, to keep
  responses LLM-friendly. Opt in to full samples via `include_samples=true` or
  decimate to every Nth via `decimate=N`.
- BMP→PNG conversion happens in the screenshot tool so an LLM can view the
  image inline (~21 KB PNG vs ~1.4 MB BMP).
- Stderr is for human-readable progress; stdout is for parseable output (CLI
  output or JSON-RPC responses in MCP mode).
- Set `OW_DEBUG=1` to see connection-level trace logs.

## Caveats

- Connection throughput is ~100 KB/s (vs nc's ~180 KB/s) due to Network.framework
  per-callback overhead. A 1.4 MB screenshot takes ~14s. Acceptable for now;
  optimize later if needed (raw POSIX socket + select would close the gap).
- The deep-memory `extendedFlags` bits are observed but their full semantics are
  unverified. We trust `collectionPointCount` for sample count, not `blockLength`.
- Sample → voltage formula is best-effort (`voltsMultiplier` treated as mV/count).
  Verified against the live capture's displayed Vpp; may need tuning for other
  scopes / probe configurations.
- ChatGPT-driven research on official/unofficial OWON network API documentation
  was outstanding at last check — `PROTOCOL.md` lists the open questions.

## Test Fixtures

`Tests/owTests/Fixtures/` — copies of:
- `live-startbin-sds7102.raw` — STARTBIN response (envelope + body), 1 kHz square wave, ~5V Vpp
- `live-startbmp-sds7102.raw` — STARTBMP response (envelope + body), 800×600×24 BMP
- `calibration_5v.bin` — USB-saved-format `.bin`, 5V calibration capture (legacy 2013 fixture)

The originals are also in `test-data/` at repo root.
