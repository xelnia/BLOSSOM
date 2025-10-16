# TODO

## In Progress
- Test more MAME versions
- Test simultaneous death/level complete (EXTRA MAN? EXTRA MAN?). DK3 handles this differently. What about board skips in CK?
- Test L22 gameplay/logging in CK

## Considering

- Add best/worst stage(s) to final stats
- Differentiate DEATH occurence with asterisk or indentation
- Convert total playback frames to estimated playing time
- Add support for dkonghrd set
    - We should be able to easily add support for a lot of the "original" rom revisions
    - Need to double-check how dkonghrd works internally see if Start/Pace/Average calculations need changing
- "Pace" for DK3? Projected RBS and Loop scores?
- Scrap this whole thing for an external OCR version Kappa


## Finished
- Add support for DK3
- API research on pre-0.175 to see if we can go further back (we're stuck with 0.175+)
- Change destination for output log file set to new folder (new `blossom_logs` directory in MAME directory)
