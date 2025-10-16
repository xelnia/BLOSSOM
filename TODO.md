# TODO

## In Progress

- Test more MAME versions
- Test simultaneous death/level complete (EXTRA MAN? EXTRA MAN?). DK3 handles this differently. What about board skips in CK?
- Test L22 gameplay/logging in CK

## Considering

- Add best/worst stage(s)/L5+ level(s) to final stats
- Add support for all games with Donkeykongforum.net leaderboards
- Differentiate DEATH occurrence with asterisk or indentation
- Convert total playback frames to estimated playing time
- "Pace" for DK3? Projected RBS and Loop scores?
- Scrap this whole thing for an external OCR version Kappa. Test with Tesseract OCR engine obs-ocr plugin 
- Dynamically check final stats against DKF+ISLR+Any active scoreboard (snapshot) for record/rank discovery & notification

## Finished
- Add support for DK3
- API research on pre-0.175 to see if we can go further back (we're stuck with 0.175+)
- Change destination for output log file set to new folder (new `blossom_logs` directory in MAME directory)
