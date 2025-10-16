![Version](https://img.shields.io/github/v/tag/xelnia/BLOSSOM?sort=semver&label=version)
![License](https://img.shields.io/github/license/xelnia/BLOSSOM)
![Lua](https://img.shields.io/badge/Lua-5.3%2F5.4-blue)
![Code style: StyLua](https://img.shields.io/badge/code%20style-StyLua-informational)
![MAME](https://img.shields.io/badge/MAME-0.175–0.281+-purple)

# BLOSSOM - DK-series MAME Score Logger

**B**asic **L**ogging **O**f **S**coring **S**tatistics **O**riginating (in) **M**AME

A Lua script that logs the score after every stage, and calculates board averages and pace. The running totals will be displayed in the command-line console and output in several file formats. This works in PLAYBACK mode only, as Lua scripting is disabled while recording WolfMAME INPs.

## Supported Games
- Donkey Kong (US Set 1) (dkong)
- Donkey Kong Junior (dkongjr)
- Crazy Kong Part II (ckongpt2)
- Donkey Kong 3 (dkong3)

## Supported MAME versions
- 0.175+

## Features
- Stage-by-stage score tracking
- Export to CSV, JSON, and TXT
- Death tracking and statistics
- Pace calculations (DK/DKJR/CK)
- Board and Level averages
- End-of-game summary

## Usage
1) **Local**
    - Put `blossom.lua` in the `scripts` folder in your main MAME directory (create that folder if needed)
    - From the command line, run `mame dkong -playback dkong.inp -autoboot_script scripts/blossom.lua`
    - Profit

2) **Global**
    - Put `blossom.lua` anywhere (e.g. `C:\Games`)
    - From the command line, run `mame dkong -playback dkong.inp -autoboot_script "C:\Games\blossom.lua"`
    - Profit

- Adjust `mame`, `dkong`, and `dkong.inp` to your needs
- The output CSV, JSON, and TXT files will be saved in a new `blossom_logs` directory your main MAME directory.
- The output filenames will be appended with a timestamp to avoid overwriting.

## Acknowledgements
**wflimusic** - for inspiration, project name, and testing
**Flobeamer1922** - for testing
**mahlemiut** - for WolfMAME
**MAMEdev** - for MAME
