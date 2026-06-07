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
in one scope).

| File | Lines | Purpose |
|---|---|---|
| `00_header.lua` | ~7 | Version comment block |
| `01_compat.lua` | ~100 | MAME version detection, API compatibility layer |
| `02_config.lua` | ~267 | `detect_game()`, `GAME_CONFIGS` table |
| `03_state.lua` | ~94 | All state tracking variables |
| `04_output_config.lua` | ~57 | Export flags, filenames, directory creation |
| `05_helpers.lua` | ~219 | Memory reads, formatting, pace calculation |
| `06_dk3_helpers.lua` | ~58 | DK3 board naming, variation detection |
| `07_recording.lua` | ~493 | `record_stage`, `record_board_dk3`, `record_level_total` |
| `08_exports.lua` | ~632 | `export_csv`, `export_json`, `export_text` |
| `09_summary.lua` | ~252 | Console Game Over / Session Ended summaries |
| `10_frame_loops.lua` | ~433 | Per-frame processing (platformer + DK3) |
| `11_init.lua` | ~154 | Startup print, callback registration, stop handler |

## LuaLS Setup

The `.luarc.json` in this directory tells LuaLS that cross-file variables exist
as globals (since after concatenation, all `local` declarations share one scope).
This suppresses most false "undefined variable" warnings.

**Tradeoff:** `unused-local` diagnostics are disabled because variables defined
in one file but used in another look "unused" to LuaLS. For accurate unused
variable detection, run LuaLS on the built `blossom.lua` instead.

## Adding a New Module

1. Create `src/XX_name.lua` with an appropriate number to place it in order
2. Add any new cross-file variable/function names to `src/.luarc.json`
   under `Lua.diagnostics.globals`
3. Run `python build.py` and test in MAME

## Debugging Line Numbers

If MAME reports an error at line N in `blossom.lua`:

```powershell
python build.py --map
```

Find which source file contains line N, then calculate the local line:
`local_line = N - file_start_line + 1`
