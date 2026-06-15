# BLOSSOM Source Modules

The `blossom.lua` file distributed to users is auto-generated. **Edit these source
files, not `blossom.lua` directly.**

## Build

```powershell
python build.py           # Concatenate src/*.lua → blossom.lua
python build.py --check   # Verify blossom.lua matches src/ (no write)
python build.py --map     # Show which source file owns each output line range
```

Run `build.py` before testing in MAME and before committing.

## Module Order

Files are numbered to enforce concatenation order. Each file can reference
anything defined in a lower-numbered file (after concatenation, they're all
in one scope). For current line counts, run `python build.py --map`.

| File | Purpose |
|---|---|
| `00_header.lua` | Version comment block |
| `01_compat.lua` | MAME version detection, API compatibility layer |
| `02_config.lua` | `detect_game()`, `GAME_CONFIGS` table |
| `03_state.lua` | All state tracking variables |
| `04_output_config.lua` | Export flags, filenames, directory creation |
| `05_helpers.lua` | Memory reads, formatting, pace calculation |
| `06_dk3_helpers.lua` | DK3 board naming, variation detection |
| `07_recording.lua` | `record_stage`, `record_board_dk3`, `record_level_total` |
| `08_exports.lua` | `export_csv`, `export_json`, `export_text` |
| `09_summary.lua` | `print_platformer_summary`, `print_dk3_summary`, `finalize_session` (consolidates game-over / INP-end / stop-callback finalization) |
| `10_frame_loops.lua` | `on_frame_platformer`, `on_frame_dkong3` per-frame processing |
| `11_init.lua` | Startup banner, INP playback detection, frame + stop callback registration (stop callback delegates to `finalize_session`) |

## LuaLS Setup

The `.luarc.json` at the repo root tells LuaLS that cross-file variables exist
as globals (since after concatenation, all `local` declarations share one scope).
This suppresses most false "undefined variable" warnings.

**Tradeoff:** `unused-local` diagnostics are disabled because variables defined
in one file but used in another look "unused" to LuaLS. For accurate unused
variable detection, run LuaLS on the built `blossom.lua` instead.

## Adding a New Module

1. Create `src/XX_name.lua` with an appropriate number to place it in order
2. Add any new cross-file variable/function names to `.luarc.json` (at the repo
   root) under `Lua.diagnostics.globals`
3. Run `python build.py` and test in MAME

## Debugging Line Numbers

If MAME reports an error at line N in `blossom.lua`:

```powershell
python build.py --map
```

Find which source file contains line N, then calculate the local line:
`local_line = N - file_start_line + 1`
