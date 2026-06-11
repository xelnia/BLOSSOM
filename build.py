#!/usr/bin/env python3
"""
build.py - Concatenate BLOSSOM source modules into a single blossom.lua

Usage:
    python build.py           Build blossom.lua from src/*.lua
    python build.py --check   Verify src files are in sync with blossom.lua (no write)
    python build.py --map     Show which source file owns each line range

Output: blossom.lua in the current directory (overwrites existing)
"""

import glob
import os
import sys


def get_source_files():
    """Return sorted list of source files from src/ directory."""
    files = sorted(glob.glob(os.path.join("src", "*.lua")))
    if not files:
        print("ERROR: No .lua files found in src/ directory.")
        print("Make sure you're running this from the BLOSSOM project root.")
        sys.exit(1)
    return files


def build(source_files):
    """Concatenate source files into a single string."""
     # Validate source files are LF-only
    for f in source_files:
        with open(f, "rb") as fh:
            if b"\r\n" in fh.read():
                raise SystemExit(f"CRLF found in {f} - commit with LF line endings")
    parts = []
    for f in source_files:
        with open(f, "r", encoding="utf-8", newline="") as src:
            content = src.read()
            # Ensure each file ends with exactly one newline
            content = content.rstrip("\n") + "\n"
            parts.append(content)

    # Join with a single blank line between files (matching original style)
    return "\n".join(parts)


def build_with_map(source_files):
    """Concatenate and return both the output and a line-number map."""
    output = build(source_files)
    lines = output.split("\n")

    # Build the map by tracking which file each line came from
    line_map = []
    current_line = 1
    for f in source_files:
        with open(f, "r", encoding="utf-8") as src:
            file_lines = src.read().rstrip("\n").split("\n")
            start = current_line
            end = current_line + len(file_lines) - 1
            line_map.append((os.path.basename(f), start, end, len(file_lines)))
            current_line = end + 2  # +2 for the blank line between files

    return output, line_map


def main():
    source_files = get_source_files()

    if "--map" in sys.argv:
        _, line_map = build_with_map(source_files)
        print("Line Range Map:")
        print(f"{'Source File':<25} {'Lines':>12}  {'Count':>5}")
        print("-" * 45)
        for name, start, end, count in line_map:
            print(f"{name:<25} {start:>5}-{end:<5}  {count:>5}")
        total = sum(count for _, _, _, count in line_map)
        print("-" * 45)
        print(f"{'Total':<25} {'':>12}  {total:>5}")
        return

    output = build(source_files)

    # Enforce LF line endings
    output = output.replace("\r\n", "\n")

    if "--check" in sys.argv:
        # Compare against existing blossom.lua
        if not os.path.exists("blossom.lua"):
            print("FAIL: blossom.lua does not exist. Run 'python build.py' first.")
            sys.exit(1)

        with open("blossom.lua", "r", encoding="utf-8") as f:
            existing = f.read()

        if existing == output:
            print("OK: blossom.lua is in sync with src/ files.")
        else:
            print("FAIL: blossom.lua is out of sync with src/ files.")
            print("Run 'python build.py' to rebuild.")
            sys.exit(1)
        return

    # Write output
    with open("blossom.lua", "w", encoding="utf-8", newline="") as f:
        f.write(output)

    total_lines = output.count("\n")
    print(f"Built blossom.lua ({total_lines} lines) from {len(source_files)} source files:")
    for sf in source_files:
        with open(sf, "r", encoding="utf-8") as f:
            count = sum(1 for _ in f)
        print(f"  {os.path.basename(sf):.<30} {count:>5} lines")


if __name__ == "__main__":
    main()
