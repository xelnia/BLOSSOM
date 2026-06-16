# Changelog

All notable changes to BLOSSOM are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


## [2.0.1] - 2026-06-15

### Fixed

- Bonus timer value not captured for completed stages (was `null`/empty);
  now reads timer at stage completion detection time (#1)

## [2.0.0] - 2026-06-14

A comprehensive rewrite focused on correctness, richer output, broader MAME
compatibility, and a modular codebase. **This release contains breaking changes
to all three export formats and to output filenames.** Anyone parsing BLOSSOM
output with scripts should review the Changed section before upgrading.

### Added

- **Multi-session INP support** - multiple games inside a single INP file are now
  detected and tracked independently, with a separate set of output files per session
  and a session banner in console output. This was implemented as an edge case: please do not record
  multiple games/attempts in a single INP.
- **Recorded Lives** tracking across all games - starting lives plus any bonus lives
  earned during play.
- **Score milestones** captured at every 100,000-point boundary with the exact frame
  number and time-from-start (start button press).
- **Speedrun timing** (DK / DKJR / CK) - from first player movement to the moment the
  last rivet or key is cleared.
- **Standard start timing** (DK / DKJR / CK) - from start button press to the visual
  level indicator change.
- **Killscreen frame detection** (DK / DKJR / CK) with the documented +3 frame visual
  offset.
- **DK3 milestone timing** - frames for Max Difficulty reached, RBS completion, and
  loop completion.
- **Bonus timer capture** at the moment of death.
- **`[Timing]` one-liner console prints** at each timing detection point during play.
- **End-of-game timing summary** in console output for all games.
- **Build system** (`build.py`) for the new modular source layout, with `--check` and
  `--map` modes for verification and inspection.

### Changed

- **BREAKING - CSV format:** now contains per-stage data rows only (no metadata header
  rows), with snake_case column names. Scripts that parsed the old metadata block at
  the top of the CSV will need to be updated.
- **BREAKING - JSON format:** restructured into six top-level sections - `metadata`,
  `scoring_summary`, `timing_summary`, `score_milestones`, `deaths`, and `stages`.
- **BREAKING - TXT report:** restructured into named sections - SCORING SUMMARY,
  TIMING SUMMARY, SCORE MILESTONES, and STAGE DATA.
- **BREAKING - output filenames:** for multi-session INPs, filenames now include a
  session number to keep each game's output distinct.
- **MAME version range broadened** - tested across 0.175, 0.183, 0.184, 0.221,
  0.223, 0.241, 0.251, 0.254, 0.260, 0.277, 0.286, and 0.288, with
  automatic API adaptation across the 0.254 callback transition
  (`emu.register_frame_done` → `emu.add_machine_frame_notifier`).
- **Gameplay detection** now uses the `$6005` game-state register instead of start
  button edge detection. More reliable across edge cases like pre-banked credits and
  multi-session playback.
- **Frame counter** now reads `screen.frame_number` as a property where available,
  matching MAME's on-screen UI display exactly.
- **Console output labels** clarified to "Recorded Deaths" and
  "Recorded Lives (starting + bonus)".
- **DK3 5 Lives Score** repositioned to appear immediately under Final Score in
  console and TXT output.
- **Source layout** - codebase is now developed as 12 modules under `src/`,
  concatenated into a single `blossom.lua` for distribution. End users still download
  one file.
- **Session ending** consolidated into a single `finalize_session()` path that
  handles GAME OVER, INP end, and manual MAME exit identically.
- **State variables** consolidated into a single `s` table for clarity and reduced
  global namespace pollution.
- **Average life stats** now display with 2-decimal precision in TXT/console and as raw floats in JSON
(previously floored to integers)
- **DKJR labeling** - killscreen now displays as `F-1` (previously `22-1`) and letter-only level labels in summaries
and stage totals render as `L-A` through `L-F` (previously `LA` through `LF`) for readability

### Fixed

- **DK3 death points** miscalculated since March 2026 - death point captured at
  detection time rather than deferred.
- **Platformer zero-score deaths** no longer increment the screen counter incorrectly.
- **Phantom events** firing after INP playback ends (extra deaths, extra stages) are
  fully suppressed.
- **Score milestone frame numbers** were 1 frame behind the visual - corrected with
  a +1 memory-to-video pipeline offset.
- **INP end frame** was 1 frame off on MAME 0.254+ - corrected via `start_frame_offset`.
- **`end_frame` fallback** had an erroneous -1 offset that caused playing time to be
  one frame short when GAME OVER VRAM was unavailable.
- **Speedrun end frame** could fire prematurely if a death occurred on the rivet or
  key screen during the start phase - gate flag now resets correctly on death.
- **DK3 Recorded Lives** reported wrong values in some sessions - fixed.
- **Pre-banked credits** no longer cause later sessions in a multi-session INP to
  lose timing data.
- **Phantom session banners** suppressed when no actual gameplay follows.
- **Killscreen detection** uses `jump ~= 0x01` against the multi-value state register
  at `$6214` (the prior `== 0x00` check missed some bug states).
- **Frame callback timing discrepancy** between MAME 0.175–0.253 and 0.254+ corrected
  via a new `start_frame_offset` value applied to start-button-derived timing.
- **Defensive code hardening from full codebase audit** - added nil guards on
  optional timing fields, suppressed empty timing summary headers when no signals
  were captured, cleaned up state-reset paths for multi-session correctness, and
  tightened cross-references between modules. The build script now enforces LF
  line endings on the distributed `blossom.lua` regardless of source file endings.

### Removed

- **Legacy CSV metadata rows** (score breakdown at top of file). Data is preserved in
  the new TXT and JSON outputs.
- **Old monolithic source layout.** Source is now under `src/`; the shipped
  `blossom.lua` is built from it.

## [1.2.0] - 2026-03-29

### Fixed

- Race condition where a death and a score event landing on the same frame could
  result in the death being recorded with the wrong score. Death recording is now
  deferred by one frame to capture the final settled score.

## [1.1.0] - 2025-10-17

### Added

- Playing time tracking and display, measured from start button press to the
  GAME OVER message.
- Best and worst board reporting for platformer games (DK / DKJR / CK).
- Extended DK3 statistics: best/worst lives, 5 Lives Score for marathon games, and
  first/last life scores.

### Changed

- Various small UX improvements to console output.

## [1.0.0] - 2025-10-15

### Added

- Donkey Kong 3 (`dkong3`) support - stage tracking, scoring, deaths, and
  DK3-specific board naming conventions.

### Changed

- Codebase reformatted with StyLua.
- Minor UX tweaks across console output.

## [0.1.0] - 2025-10-13

### Added

- Initial release.
- Stage-by-stage score tracking for Donkey Kong (`dkong`), Donkey Kong Junior
  (`dkongjr`), and Crazy Kong Part II (`ckongpt2`).
- CSV, JSON, and TXT export formats.
- Death tracking and per-stage statistics.
- Pace calculation with per-stage updates.
- Board and level averages.
- End-of-game console summary.

[Unreleased]: https://github.com/xelnia/BLOSSOM/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/xelnia/BLOSSOM/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/xelnia/BLOSSOM/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/xelnia/BLOSSOM/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/xelnia/BLOSSOM/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/xelnia/BLOSSOM/releases/tag/v0.1.0
