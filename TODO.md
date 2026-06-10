# TODO

## In Progress

- Test more MAME versions
- Test simultaneous death/level complete (EXTRA MAN? EXTRA MAN?). DK3 handles this differently. What about board skips in CK?
- Test L22 gameplay/logging in CK

## Considering
- Frame number for every score change
- Scrap this whole thing for an external OCR version Kappa. Test with Tesseract OCR engine obs-ocr plugin
- Dynamically check final stats against DKF+ISLR+Any active scoreboard (snapshot) for record/rank discovery & notification

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
