# BLOSSOM - DK-series MAME Score Logger

**B**asic **L**ogging **O**f **S**coring **S**tatistics **O**riginating (in) **M**AME

A Lua script that logs the score after every stage, and calculates board averages and pace. The running totals will be displayed in the command-line console and output in several file formats. This works in PLAYBACK mode only, as Lua scripting is disabled while recording WolfMAME INPs.

## Supported Games
- Donkey Kong (dkong)
- Donkey Kong Junior (dkongjr)
- Crazy Kong Part II (ckongpt2)

## Supported MAME versions
- 0.175+

## Features
- Stage-by-stage score tracking
- Export to CSV, JSON, and TXT
- Death tracking and statistics
- Pace calculations
- Board and Level averages
- End-of-game summary

## Usage
1) Local
- Put `blossom.lua` in the `scripts` folder in your main MAME directory (create that folder if needed)
- From the command line, run `mame dkong -playback dkong.inp -autoboot_script scripts/blossom.lua`
- Profit

2) Global
- Put `blossom.lua` anywhere (e.g. `C:\Games`)
- From the command line, run `mame dkong -playback dkong.inp -autoboot_script "C:\Games\blossom.lua"`
- Profit

The output CSV, JSON, and TXT files will be saved in your main MAME directory.  
Adjust `mame`, `dkong`, and `dkong.inp` to your needs

## Acknowledgements
**wflimusic** - for the inspiration and name