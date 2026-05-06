# ow

CLI and MCP stdio server for Owon SDS-series oscilloscopes. Capture screenshots
and waveforms over LAN; expose the same operations to LLMs so an agent can
debug hardware directly.

Verified against an SDS7102V; should work for the rest of the SDS series.

## Install

```
make install     # → ~/.local/bin/ow
```

Requires Swift 6.2+, macOS 26+.

## Usage

```
ow config set host 10.0.1.230
ow status                     # identify the scope, print current waveform info
ow screen out.png             # capture display (BMP→PNG conversion if .png)
ow data out.bin               # capture waveform via STARTBIN
ow memdepth out.bin           # capture deep-memory waveform via STARTMEMDEPTH
ow bin --csv out.bin          # parse + summarize, write out.csv next to it
ow mcp                        # run as MCP stdio server
```

Run `ow --help` or `ow <subcommand> --help` for details.

## MCP

```
ow mcp
```

Speaks JSON-RPC over stdio. Four tools:

- `scope_status` — probe + identify
- `capture_screenshot` — returns PNG inline (so an LLM can view it)
- `capture_waveform` — capture + parse, with `deep_memory`, `include_samples`, `decimate` options
- `parse_bin_file` — parse a saved `.bin` from disk

Drop the binary in your MCP client config — e.g. for Claude Desktop:

```json
{
  "mcpServers": {
    "ow": { "command": "/Users/you/.local/bin/ow", "args": ["mcp"] }
  }
}
```

## Protocol

The Owon SDS network protocol is reverse-engineered — the vendor manual does
not document it. See [`PROTOCOL.md`](PROTOCOL.md) for the byte-level reference.
The scope does **not** speak SCPI; there is no remote-control surface, only
capture-and-analyze.

## License

MIT (see LICENSE).
