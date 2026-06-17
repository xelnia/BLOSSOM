![Version](https://img.shields.io/github/v/tag/xelnia/BLOSSOM?sort=semver&label=version)
![License](https://img.shields.io/github/license/xelnia/BLOSSOM)
![Lua](https://img.shields.io/badge/Lua-5.3%2F5.4-blue)
![Code style: StyLua](https://img.shields.io/badge/code%20style-StyLua-informational)
![MAME](https://img.shields.io/badge/MAME-0.175–0.288+-purple)

# BLOSSOM

**B**asic **L**ogging **O**f **S**coring **S**tatistics **O**riginating (in) **M**AME

A Lua script for [MAME](https://www.mamedev.org/) that tracks stage-by-stage scoring statistics during INP playback for classic Donkey Kong arcade games: Donkey Kong, Donkey Kong Junior, Crazy Kong Part II, and Donkey Kong 3.

BLOSSOM works in **playback mode only** (`-playback`/`-pb`), as WolfMAME disables Lua scripting during INP recording.

## Supported Games

| Game | Romset |
|------|--------|
| Donkey Kong (US Set 1) | `dkong` |
| Donkey Kong Junior | `dkongjr` |
| Crazy Kong Part II (Set 1) | `ckongpt2` |
| Donkey Kong 3 | `dkong3` |

## Quick Start

Place `blossom.lua` in your MAME `scripts` directory and run:

```
mame dkong -pb your_game.inp -autoboot_script scripts/blossom.lua
```

Or specify a full path:

```
mame dkong -pb your_game.inp -autoboot_script "C:\Games\blossom.lua"
```

Adjust `mame`, `dkong`, and `your_game.inp` to your needs.

Output files (CSV, JSON, TXT) are saved to a `blossom_logs/` directory inside the MAME directory, with timestamps to avoid overwriting.

## What's New in v2.0.0

v2.0.0 is a comprehensive rewrite focused on correctness, richer output, and broader compatibility. Highlights:

- **Frame-accurate timing** - speedrun start/end, killscreen detection, score milestones, all anchored to MAME's deterministic frame counter
- **Restructured exports** - new CSV schema (per-stage rows only), JSON with `metadata`/`scoring_summary`/`timing_summary`/`score_milestones`/`deaths`/`stages` sections, redesigned TXT report
- **Multi-session INP support** - multiple games inside a single INP file are tracked independently. But please don't record multiple games in a single INP.
- **Modular source layout** - codebase split into 12 modules under `src/`, concatenated into a single `blossom.lua` for distribution

See `CHANGELOG.md` for the full list of changes. Note: v2.0.0 includes breaking changes to all three export formats.

## Features

### Scoring
- Stage-by-stage score tracking with running totals
- Screen type averages and level averages with best/worst analysis (L4+ for DKJR, L5+ for DK/CK)
- Million-point rollover detection
- Pace calculation with per-stage updates (DK/DKJR/CK)
- Start score breakdown with death point separation
- Score milestones at every 100K with frame and time references and remaining lives
- 5 Lives Score for marathon DK3 games
- Max difficulty (Board 27+) screen averages (DK3)
- RBS and Loop score tracking (DK3)
- Per-life statistics: longest, shortest, average life by points and boards (DK3)

### Deaths
- Deferred death recording for accurate score settlement (catches simultaneous score and death events)
- Death point tracking with bonus timer capture

### Timing
- Full Game timing: start button press to "GAME OVER" message
- Speedrun Killscreen timing: first movement to first killscreen bug activation (DK/DKJR/CK)
- Speedrun Start timing: first movement to last rivet/key clear (DK/DKJR/CK)
- Standard Start timing: start button press to level indicator change (DK/DKJR/CK)
- RBS, loop, and max difficulty milestone timing (DK3)
- DK3 speedrun timing is not yet defined (no community convention for start/end events)
- All timing uses MAME's deterministic frame counter for reproducibility

### Output
- **CSV** - Pure per-stage data, no metadata rows. One row per stage or death.
- **JSON** - Hierarchical structure with six sections: `metadata`, `scoring_summary`, `timing_summary`, `score_milestones`, `deaths`, `stages`.
- **TXT** - Human-readable report with scoring summary, timing summary, milestones, and per-stage data.
- **Console** - Real-time stage-by-stage output with end-of-game summary.

### Partial Analysis
- Exiting MAME mid-analysis will still generate summaries and outputs of the accumulated data up to
that point

### Compatibility
- MAME versions 0.175 through 0.288+ (and counting)
- Automatic API detection handles differences across MAME versions
- Single-file distribution - just `blossom.lua`, no dependencies

## Configuration

At the top of `blossom.lua`, toggles control output behavior. All default to `true`.

### Export Toggles

```lua
local EXPORT_CSV = true
local EXPORT_JSON = true
local EXPORT_TEXT = true
```

Set any to `false` to suppress that output file.

### Console Display Toggles

```lua
local SHOW_RUNNING_LOG = true
local SHOW_SCORING_SUMMARY = true
local SHOW_LIVES_SUMMARY = true
local SHOW_TIMING_SUMMARY = true
local SHOW_SCORE_MILESTONES = true
```

These control which sections appear in the MAME console during and after playback. Export files always contain complete session data regardless of these settings.

| Toggle | Controls |
|--------|----------|
| `SHOW_RUNNING_LOG` | Real-time per-board prints, milestone alerts, and `[Timing]` events during playback |
| `SHOW_SCORING_SUMMARY` | Final score, board progress, pace, screen/level averages, death points |
| `SHOW_LIVES_SUMMARY` | Recorded lives/deaths, per-life statistics (first, last, longest, shortest, average) |
| `SHOW_TIMING_SUMMARY` | Elapsed times and frame ranges for speedrun, standard start, killscreen, and full game |
| `SHOW_SCORE_MILESTONES` | 100,000-point milestone log with board, timer, lives, and elapsed time |

For a compact scorer view, set everything to `false` except `SHOW_SCORING_SUMMARY`.

> **Note:** When the bonus timer value is appended to a killscreen death or completion in any output, the value reflects the internal bug state, not the corrupted display value.

## How It Works

BLOSSOM registers a per-frame callback through MAME's Lua scripting API. Each frame, it reads game state from memory (game mode, score, level, screen type, lives) and detects transitions: stage completions, deaths, level changes, and game over. Score is read from BCD-encoded memory with rollover detection for million-point games.

Timing signals use a combination of memory reads and VRAM tile checks. VRAM-based signals (standard start, game over) match what you'd see on a video recording of the arcade screen. Memory-based signals (speedrun start, killscreen bug) apply documented offsets where memory state leads the visual by one or more frames.

A compatibility layer in the script detects the MAME version at startup and adapts API calls accordingly. This handles differences like `manager.machine` being a property vs. a method, different frame callback registration APIs, and `table` vs. `userdata` types for device collections.

## Recording Best Practices

Please record a single game per INP file. While BLOSSOM will correctly handle multi-session INPs (multiple GAME OVER cycles in one file), this is treated as an edge case - competitive scoring conventions expect one game per INP, and single-game INPs produce cleaner output.

## MAME Compatibility

BLOSSOM requires **MAME 0.175 or newer**. It has been tested on 0.175, 0.183, 0.184, 0.221, 0.223, 0.241, 0.251, 0.254, 0.260, 0.277, 0.286, and 0.288, and should work on any version in that range and beyond (until MAME's Lua implementation changes).

Key API transitions the compatibility layer handles:

| Change | Older MAME | Newer MAME |
|--------|-----------|------------|
| Machine access | `manager:machine()` (method) | `manager.machine` (property) |
| Frame callback | `emu.register_frame_done` | `emu.add_machine_frame_notifier` (0.254+) |
| Frame number | `screen:frame_number()` (method) | `screen.frame_number` (property) |
| Device collections | `table` type (some ~0.220 builds) | `userdata` type |

MAME 0.254+ requires frame/stop callback subscriptions to be stored in global scope (`_G`) to prevent Lua garbage collection after approximately 300 frames.

## Project Structure

BLOSSOM is developed as 12 source modules that are concatenated into a single `blossom.lua` for distribution:

```
src/
  00_header.lua        Version, export flags
  01_compat.lua        MAME API compatibility layer
  02_config.lua        Game detection and configuration
  03_state.lua         State tracking variables
  04_output_config.lua File paths and directory creation
  05_helpers.lua       Memory reads, formatting, pace math
  06_dk3_helpers.lua   DK3 board naming, variation detection
  07_recording.lua     Stage/board recording with console output
  08_exports.lua       CSV, JSON, TXT export functions
  09_summary.lua       End-of-game console summaries
  10_frame_loops.lua   Per-frame state machine (platformer + DK3)
  11_init.lua          Startup, callback registration, stop handler
build.py               Concatenation build script
```

To build after editing source modules:

```
python build.py           # Build blossom.lua from src/*.lua
python build.py --check   # Verify blossom.lua matches src/ (no write)
python build.py --map     # Show which source file owns each line range
```

The build script enforces LF line endings on the distributed `blossom.lua` regardless of source file endings.

Example module map after build (these values might not be current):
```text
Line Range Map:
Source File                      Lines  Count
---------------------------------------------
00_header.lua                     1-21     21
01_compat.lua                   23-156    134
02_config.lua                  158-488    331
03_state.lua                   490-661    172
04_output_config.lua           663-717     55
05_helpers.lua                 719-967    249
06_dk3_helpers.lua            969-1026     58
07_recording.lua             1028-1642    615
08_exports.lua               1644-3071   1428
09_summary.lua               3073-3944    872
10_frame_loops.lua           3946-4687    742
11_init.lua                  4689-4729     41
---------------------------------------------
Separators (1 between files)               11
Total source lines                       4718
Final blossom.lua length                 4729
```

## Timing Definitions

All timing values are based on MAME's deterministic frame counter (`screen.frame_number`) and are reproducible across identical INP playbacks.

- **Full Game** - Start button press to game over VRAM appearance (or last gameplay frame if session ended early). Converted at the game's native frame rate (2000/33 Hz ≈ 60.606061 for DK/DKJR/DK3, 60.0 Hz for CK).
- **Speedrun Start** - Frame of first player position change (memory leads visual by 1 frame, offset applied).
- **Standard Start** - Start button press to VRAM level digit change (start phase completion).
- **Speedrun Killscreen** - Speedrun start to killscreen trigger (+ 3 frame pipeline delay for visual death).
- **DK3 Milestones** - Frame when max difficulty, RBS completion, or loop completion is detected.

All timing values in output are labeled "Unofficial" until confirmed via further analysis.

## Acknowledgements

- **[wflimusic](https://github.com/wflimusic)** - inspiration, project name, and testing
- **[Flobeamer1922](https://www.twitch.tv/flobeamer1922)** - testing
- **[mahlemiut](https://github.com/mahlemiut)** - WolfMAME
- **[MAMEdev](https://github.com/mamedev)** - MAME
