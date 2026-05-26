---
name: ogg2mp3
description: Convert QQ Music .ogg/.oggh audio files on macOS to .mp3 with embedded cover art (extracted from ICNS in the macOS Resource Fork) and metadata. Provides `convert` (single file), `batch` (directory, optional recursion + skip/overwrite/dry-run), `inspect` (read-only metadata + cover probe, no conversion), and `doctor` (environment self-check). Output is plain MP3 with id3v2.3 tags. Use when the user has QQ Music downloads and wants standard MP3 with covers intact. Not for general audio transcoding — the cover extraction path is QQ Music–specific (reads macOS Resource Fork).
min_binary_version: 2026.5.0
---

# ogg2mp3

QQ Music's macOS app stores audio as Vorbis-in-Ogg (`.ogg` or `.oggh`) with the cover image hidden in the **macOS Resource Fork** as an ICNS resource — *not* in the Vorbis stream. `ogg2mp3` reassembles audio + cover + metadata into a standard MP3 with id3v2.3 tags using `ffmpeg`, `derez`, and `icnsutil`.

## When to use

- User has `.ogg` or `.oggh` files from QQ Music's Mac app and wants `.mp3`.
- User wants to inspect what's in a file before converting.
- User wants to verify the environment is ready for conversion.

## When NOT to use

- `.ogg` files from other sources (web downloads, Bandcamp, etc.) — conversion will still produce a valid MP3 but `cover_embedded` will be `false` because the file has no ICNS in its Resource Fork.
- Non-OGG audio (MP3 / FLAC / WAV / M4A in / out): use `ffmpeg` directly.
- Audio editing (trim, mix, normalize, format other than MP3): use `ffmpeg` directly.

## Prerequisites

1. The binary must be on PATH at `~/.local/bin/ogg2mp3`. If `command -v ogg2mp3` fails, the user has not installed it — instruct them to `git clone https://github.com/HerbertGao/ogg2mp3 && bash ogg2mp3/scripts/install.sh`.
2. Run `ogg2mp3 doctor --json` once per session before any `convert` / `batch` call. Parse `.ok`; if `false`, stop and surface each failing check's `install_hint` to the user.
3. Verify `.binary_version` from `doctor` is `2026.5.0` or higher. If the binary is newer and emits a different JSON shape, trust the binary over this document.

## Tools

### `convert <input>` — convert one file

```
ogg2mp3 convert <input> [-o <output>] [--no-cover] [--no-metadata] [--overwrite] [--yes] [--json]
```

| Flag | Meaning |
|---|---|
| `-o <path>` | Output path. Default: `<input>` with extension swapped to `.mp3`, same directory. |
| `--no-cover` | Skip cover art extraction and embedding. |
| `--no-metadata` | Skip metadata copying. |
| `--overwrite` | Replace existing output without prompting. |
| `--yes` | Required for non-interactive callers. Skips all confirmation prompts. |
| `--json` | Emit a single JSON object to stdout. |

**JSON result** (with `--json`):

```json
{
  "ok": true,
  "input": "/path/to/song.ogg",
  "output": "/path/to/song.mp3",
  "cover_embedded": true,
  "metadata_fields": 3
}
```

Without `--json`, stdout is one line: the output path. Logs go to stderr.

**Exit codes**: `0` success · `1` conversion failed or output exists without `--overwrite` · `2` bad args · `3` missing dependency or running as root.

**Agent rules**:
- Always pass `--yes`. You are non-interactive; without it, an existing output blocks the run waiting for stdin.
- Always pass `--json` so you can parse the result.
- Do not pass `--no-cover` unless the user explicitly says they don't want cover art — cover embedding is the whole point of this tool over plain `ffmpeg`.
- A successful result with `cover_embedded: false` is not an error; it usually means the source had no ICNS in its Resource Fork (i.e. not actually from QQ Music). Surface this to the user as a note, don't retry.

### `batch <dir>` — convert a directory

```
ogg2mp3 batch <dir> [-r|--recursive] [--skip-existing | --overwrite] [--no-cover] [--no-metadata] [--dry-run] [--yes] [--json]
```

| Flag | Meaning |
|---|---|
| `-r`, `--recursive` | Recurse into subdirectories. Default: top level only. |
| `--skip-existing` | Skip files whose `.mp3` already exists. **Mutually exclusive with `--overwrite`.** |
| `--overwrite` | Replace existing `.mp3` files. |
| `--dry-run` | List planned conversions; do not execute. |
| `--yes`, `--json`, `--no-cover`, `--no-metadata` | Same semantics as `convert`. |

**Output format** (`--json` mode → NDJSON, one object per line):

| Outcome | Schema |
|---|---|
| Converted | `{"ok": true, "input": "...", "output": "...", "cover_embedded": bool, "metadata_fields": int}` |
| Skipped | `{"ok": true, "skipped": true, "input": "...", "output": "..."}` |
| Failed | `{"ok": false, "input": "...", "output": "...", "error": "..."}` |
| Dry-run preview | `{"input": "...", "output": "...", "planned_action": "convert"\|"skip"\|"fail", "reason": null \| "..."}` |

Plain mode emits `OK\t<path>` / `SKIP\t<path>` / `FAIL\t<path>\t<reason>` per line.

**Exit codes**: `0` all succeeded (or dry-run) · `1` at least one file failed · `2` bad args (including using `--skip-existing` and `--overwrite` together) · `3` missing dep or root.

**Default flag combinations Agents should use**:

| User intent | Recommended flags |
|---|---|
| "Convert all songs in this folder" | `-r --skip-existing --yes --json` |
| "Reconvert everything" | `-r --overwrite --yes --json` |
| "Show me what this will do" | `-r --dry-run --json` |

If `.mp3` already exists and the user did not specify policy, default to `--skip-existing` and tell the user how many were skipped — do not silently overwrite.

### `inspect <input>` — read-only probe

```
ogg2mp3 inspect <input> [--json]
```

Does not convert. Reports codec, duration, bitrate, all vorbis tags, and whether an ICNS cover is present in the Resource Fork.

**JSON schema**:

```json
{
  "file": "/path/to/song.ogg",
  "codec": "vorbis",
  "duration_sec": 181.25,
  "bitrate": 314482,
  "metadata": { "TITLE": "...", "ARTIST": "...", "ALBUM": "..." },
  "cover": { "present": true, "size_bytes": 356845 }
}
```

**Exit codes**: `0` readable · `1` ffprobe could not parse the file.

**Agent rules**:
- Use this when the user asks "what's in this file?" without wanting conversion.
- Do **not** use `inspect` as a precondition for `convert` — `convert` already handles missing covers gracefully and is the canonical write path.

### `doctor` — environment self-check

```
ogg2mp3 doctor [--json]
```

**JSON schema**:

```json
{
  "ok": true,
  "binary_version": "2026.5.0",
  "checks": [
    {
      "name": "ffmpeg",
      "found": true,
      "path": "/opt/homebrew/bin/ffmpeg",
      "version": "8.1.1",
      "install_hint": "brew install ffmpeg"
    }
  ]
}
```

Checks all of: `ffmpeg`, `ffprobe`, `derez`, `icnsutil`, `jq`, `xxd`, `grep`, `sed`.

**Exit codes**: `0` all green · `3` any missing.

**Agent rules**:
- Call this once at the start of any session that will run `convert` or `batch`.
- If `.ok` is `false`, **do not** call `convert` or `batch`. Surface each failing check's `install_hint` to the user verbatim.
- Verify `.binary_version` is `2026.5.0` or higher (CalVer; major = year, minor = month). If the binary is newer and emits a JSON shape that disagrees with this document, trust the binary.

## Capabilities NOT exposed to Agents

These exist for human terminal users and **will hang or misbehave** if an Agent invokes them:

| Don't | Why |
|---|---|
| `ogg2mp3` with no subcommand | Drops into an interactive menu prompt. Blocks on stdin in a TTY; in non-interactive agent contexts exits 0 or 1 without performing any action. Always pass an explicit subcommand. |
| `convert` or `batch` without `--yes` when output exists | Prompts `y/N` only in a TTY; in non-interactive agent contexts the binary exits 1 immediately rather than blocking. Always pass `--yes`. |
| `--skip-existing` together with `--overwrite` | Exit 2 (mutually exclusive). |
| Running under `sudo` / as root | Exit 3 (`require_unprivileged` guard). The binary refuses on purpose to avoid leaving root-owned files in the user's library. |

## Output contract recap

- **stdout** = data only: paths (plain mode) or JSON / NDJSON (`--json`).
- **stderr** = all human-readable logs (`→`, `✓`, `warning:`, `error:`).
- Agents should redirect or ignore stderr when parsing; **never** parse stderr for data.

## Failure modes Agents should handle

| Symptom | Meaning | What to do |
|---|---|---|
| `exit 3` from anything | Missing dependency or running as root | Run `doctor --json`; surface `install_hint`s. Never retry the same call. |
| `exit 1` from `convert` | Conversion failed | Read stderr (`ffmpeg:` lines) for the real cause. Don't silently retry. |
| `cover_embedded: false` on success | No ICNS in Resource Fork | Note it to the user (likely not a QQ Music file). MP3 is still valid. |
| `metadata_fields: 0` on success | OGG had no Vorbis tags | Note it. MP3 is still valid, just untagged. |
| Batch exits `1` but most files are `ok: true` | Some files failed | Filter NDJSON for `ok: false` lines and report those to the user. |
