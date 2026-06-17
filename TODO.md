# TODO

## In Progress

- Test more MAME versions (always ongoing)
- Test simultaneous death/level complete behavior across all four games.
  In DK/CK, this adds a life then removes it when next stage loads
  (EXTRA MAN? EXTRA MAN?). Unsure how DKJR works. In DK3, the bonuses
  are calculated and the next board loads with the life truly lost
  (no add/subtract).

## v2.1.0 Candidates

### Custom DIP tracking for platformers
Custom DIPs that don't match existing competitive categories are already parsed for DK3, but not
for the platformers (DK/DKJR/CK).

### Per-score-change frame tracking
Record the frame number and bonus timer value every time the score changes. Enables deep timing
analysis: 5-minute scoring rates, 1-hour scores, scoring velocity curves,
time-between-points distributions. Implementation: single score read at
top of frame loop with change detection, score_changes array in state,
new section in JSON output. Medium refactor - consolidates multiple
`read_score_with_rollover_check()` calls per frame into one shared local. We should indicate if the
score changed because of end-of-stage bonus calculation.



### Board-level timing
Record frame-accurate timings of each board/level. There are no existing
community conventions on when a board starts (when character appears? when
character is controllable? when board fully loads? etc.) or when a board
ends (when control is lost? when bonus is finished calculating? when next
stage loads? etc.) so we might just create some arbitrary start/end points.

### DK3 game mode / death status research
Deeper investigation into whether DK3's death detection can use a pattern
closer to the platformer games. All four games have game modes and a "dead"
flag - the current split (platformer uses game_mode dead value, DK3 uses
separate dead_status address) may be a consequence of initial implementation
rather than a hard requirement. Research tasks:
- Compare death handling routines across all four games
- Determine if DK3 has a game_mode dead value that was overlooked
- Determine if platformers have a separate dead flag that could unify detection
- Goal: evaluate whether the two frame loops could share a common death
  detection and settlement pattern, reducing duplication

### ROM revisions - immediate implementations
1) Donkey Kong (US Set 2) - `dkongo`
    - Mapping: identical to `dkong`. One-line config alias.

### ROM revisions - possible quick implementations
1) Donkey Kong (Japan Set 1) - `dkongj`
    - Older versions of MAME had different romset name, but our script
      doesn't go back that far.
    - Mapping: Stage order is identical to ckongpt2. All other aspects
      are identical to dkong.
2) Donkey Kong (Japan Set 2) - `dkongjo`
    - Mapping: Stage order is identical to ckongpt2. All other aspects
      are identical to dkong.
3) Donkey Kong (Japan Set 3) - `dkongjo1`
    - Older versions of MAME had different romset name, but our script
      doesn't go back that far.
    - Mapping: Stage order is identical to ckongpt2. Level 22 play and
      pace formula is identical to ckongpt2, but the
      specific variables would be different. All other aspects
      identical to dkong.
    - Let's implement a 22-4 pace calculation the same way we do for
      ckongpt2, and I'll update the specific variables later. This game
      is rarely played.

### ROM revisions - needs research
1) Donkey Kong Junior (Japan set F-1) - `dkongjnrj`
2) Donkey Kong Junior (E kit) - `dkongjre`
3) Donkey Kong Jr. (Japan) - `dkongjrj`
4) Donkey Kong Junior (P kit, bootleg) - `dkongjrpb`
5) Donkey Kong (hard kit) - `dkonghrd`
    - Essentially a speed-up hack where the game starts at max difficulty
6) Donkey Kong: Pauline Edition Rev 5 (2013-04-22) - `dkongpe`
    - Essentially just a re-skin of dkong. Mapping should be identical.
      Unsure about memory locations though.
7) Donkey Kong II: Jumpman Returns (hack, V1.2) - `dkongx-dk2`
    - Modern hack of dkong. Vastly different levels and progression.
      Would need a completely separate game config and memory value
      verification.
8) Donkey Kong II: Jumpman Returns (hack, V1.1) - `dkongx11-dk2`
    - Early release of Donkey Kong II v1.2
9) Donkey Kong 3 (Japan) - `dkong3j`
    - Possibly exact same mappings. More research needed.
10) Crazy Kong Part II (set 2) - `ckongpt2a`
    - Possibly exact same mappings. More research needed.
11) Crazy Kong Part II (Japan) - `ckongpt2j`
    - Possibly exact same mappings. More research needed.
12) Crazy Kong Part II (alternative levels) - `ckongpt2b`
    - Possibly exact same mappings. More research needed.
    - Stages are different within game, but ordering and types are
      the same I think.
13) The vast array of Crazy Kong bootlegs
    - Generally follow the same stage order
    - Memory values are likely different
    - Pace calculations are likely different
    - This specific item is VERY LOW PRIORITY

## Player Suggestions (Deferred)

- Interactive export confirmation - not feasible inside MAME's Lua sandbox.
  Exports have boolean flags that can be set to `true`/`false` at the top
  of the script as a static equivalent.

## Considering

- Dynamically check final stats against DKF + IBR + any active scoreboard
  (snapshot) for record/rank discovery and notification
- Scrap this whole thing for an external OCR version Kappa. Test with
  Tesseract OCR engine obs-ocr plugin

## Finished

- [x] Add support for DK3
- [x] API research on pre-0.175 to see if we can go further back
  (we're stuck with 0.175+)
- [x] Change destination for output log file set to new folder
  (new `blossom_logs` directory in MAME directory)
- [x] Add best/worst stage(s)/L5+ level(s) to final stats
- [x] Differentiate DEATH occurrence with asterisk or indentation
- [x] Convert total playback frames to estimated playing time
- [x] DK3 extended stats (in lieu of pace calculation)
- [x] Separate tied Best/Worst stage(s) by comma within (1) set of
  parenthesis (14-3, 15-5, 17-1) etc.
- [x] Test L22 gameplay/logging in CK
- [x] Add support for all games with Donkeykongforum.net leaderboards
    - DK/DKJR/CK/DK3 are implemented. D2K is scoped under
      "ROM revisions" above.
- [x] Multi-session INP support (v2.0.0)
- [x] Recorded Lives tracking (v2.0.0)
- [x] Score milestone tracking (v2.0.0)
- [x] Frame timing offset audit (v2.0.0)
- [x] Output refactor - CSV/JSON/TXT restructured for v2.0.0
- [x] State table refactor - 85 per-session variables wrapped in `s` table
- [x] `finalize_session()` consolidation of session-ending paths
- [x] Modular source layout under `src/` with `build.py`
- [x] Compact/simple mode to toggle off or omit milesstone/timing/frames data reporting. Milestone,
      in particular, muddles neat level statistics. Why 2 instances (in-game and summary)?
    - Toggles implemented
- [x] Restore support for Blossom.lua to run in the scripts folder. 2.0 gives a path error.
    - Never technically broken, but README documentation wasn't correct.
- [x] Move Scoring Summary below -Exported + Timing Summary + Score Milestone. Crucial compact
      data in cmd's resting viewpoint.
    - Toggles implemented. Order not changed.

## Rejected / Won't Do

- Change Final Stage verbiage from pies to conveyor with use of TAB key
  to justify spacing and vertical visual appeal. Remove redundant `:`
  between stage name and the word AVERAGE to improve alignment.
    - More work than it's worth right now.
- Column-aligned console output (from 2026-06-09 session).
    - Console formatting is intentionally width-tolerant; full column alignment
      would require fixed-width assumptions that conflict with that.
- Generate Log YES/NO confirmation option instead of automatic output,
  or post-script Keep Log YES/NO query with automatic discard to Recycle
  Bin upon NO.
    - We don't have the option of interactivity within MAME's Lua sandbox.
      Exports have boolean flags that can be set to `true`/`false` at the
      top of the script.
- "Pace" for DK3 / projected RBS and Loop scores.
    - Implemented extended stats (best/worst lives, 5 Lives Score,
      first/last life scores) instead.
- Start End Timing reports and populates before 4-5 stage score outputs. -Should be reversed-
    - Running log is chronological. Start end timing happens before 4-5 stage score is finalized.
      Current behavior is correct.






