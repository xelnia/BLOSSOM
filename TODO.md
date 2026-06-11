# TODO

## In Progress

- Test more MAME versions
- Test simultaneous death/level complete (EXTRA MAN? EXTRA MAN?). DK3 handles this differently. What about board skips in CK?
- Test L22 gameplay/logging in CK

## Considering
- Frame number for every score change
- Scrap this whole thing for an external OCR version Kappa. Test with Tesseract OCR engine obs-ocr plugin
- Dynamically check final stats against DKF+ISLR+Any active scoreboard (snapshot) for record/rank discovery & notification

## DK3 game mode / death status research
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

## v2.1.0: Per-score-change frame tracking
Record the frame number every time the score changes. Enables deep timing
analysis: 5-minute scoring rates, 1-hour scores, scoring velocity curves,
time-between-points distributions. Implementation: single score read at
top of frame loop with change detection, score_changes array in state,
new section in JSON output. Medium refactor - consolidates multiple
read_score_with_rollover_check() calls per frame into one shared local.

## Finished / Deferred
- Add support for DK3
- API research on pre-0.175 to see if we can go further back (we're stuck with 0.175+)
- Change destination for output log file set to new folder (new `blossom_logs` directory in MAME directory)
- Add best/worst stage(s)/L5+ level(s) to final stats
- Differentiate DEATH occurrence with asterisk or indentation
- Convert total playback frames to estimated playing time
- "Pace" for DK3? Projected RBS and Loop scores?
    - Extended stats instead
- Change Final Stage verbiage from pies to conveyor with use of TAB key to justify spacing and vertical visual appeal. Remove redundant : between stage name and the word AVERAGE to improve alignment.
    - More work than it's worth right now
- Separate tied Best/Worst stage(s) by comma within (1) set of parenthesis (14-3, 15-5, 17-1) etc.
- Generate Log YES/NO? confirmation option instead of automatic output? or post-script Keep Log YES/NO? query with automatic discard to Recycle Bin upon NO
    - I don't think we have the option of interactivity within MAME's Lua sandbox. Exports have boolean flags that can be set to `true`/`false` at the top of the script.
- Add support for all games with Donkeykongforum.net leaderboards
    - I think we're there already?
