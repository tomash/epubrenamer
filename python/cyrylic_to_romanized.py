#!/usr/bin/env python3
"""Rename .epub files whose basenames contain Cyrillic to ICU transliteration (ASCII)."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections import defaultdict

CYR = re.compile(r"[\u0400-\u04FF]")


def translit_filename(name: str) -> str:
    p1 = subprocess.run(
        ["uconv", "-x", "Any-Latin"],
        input=name.encode("utf-8"),
        stdout=subprocess.PIPE,
        check=True,
    )
    p2 = subprocess.run(
        ["uconv", "-x", "Latin-ASCII"],
        input=p1.stdout,
        stdout=subprocess.PIPE,
        check=True,
    )
    return p2.stdout.decode("utf-8").rstrip("\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Rename .epub files with Cyrillic in the filename to romanized ASCII "
            "(ICU uconv: Any-Latin, then Latin-ASCII). Only the directory given is scanned "
            "(not subdirectories)."
        )
    )
    parser.add_argument(
        "directory",
        help="Directory containing .epub files",
    )
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="Print planned renames without renaming",
    )
    args = parser.parse_args()

    directory = os.path.abspath(args.directory)
    if not os.path.isdir(directory):
        print(f"Not a directory: {directory}", file=sys.stderr)
        return 1

    os.chdir(directory)
    epubs = [f for f in os.listdir(".") if f.endswith(".epub")]
    to_rename = [f for f in epubs if CYR.search(f)]
    if not to_rename:
        print("No .epub files with Cyrillic in the name.")
        return 0

    pairs: list[tuple[str, str]] = []
    for old in sorted(to_rename):
        new = translit_filename(old)
        if new == old:
            print(f"SKIP (unchanged): {old!r}")
            continue
        if "\n" in new or "/" in new or new.startswith("."):
            print(f"SKIP (unsafe): {old!r} -> {new!r}")
            continue
        pairs.append((old, new))

    by_new: dict[str, list[str]] = defaultdict(list)
    for old, new in pairs:
        by_new[new].append(old)

    resolved: list[tuple[str, str]] = []
    for new, olds in sorted(by_new.items()):
        olds_sorted = sorted(olds)
        if len(olds_sorted) == 1:
            resolved.append((olds_sorted[0], new))
            continue
        stem, ext = os.path.splitext(new)
        for idx, old in enumerate(olds_sorted):
            dest = new if idx == 0 else f"{stem}_{idx + 1}{ext}"
            resolved.append((old, dest))

    used_dest: set[str] = set(epubs)
    final: list[tuple[str, str]] = []
    planned_dests: set[str] = set()
    for old, dest in resolved:
        candidate = dest
        stem, ext = os.path.splitext(dest)
        n = 2
        while candidate in planned_dests or (
            candidate in used_dest and candidate != old
        ):
            candidate = f"{stem}__{n}{ext}"
            n += 1
        planned_dests.add(candidate)
        final.append((old, candidate))

    for old, dest in final:
        print(f"mv {old!r} -> {dest!r}")
        if not args.dry_run:
            os.rename(os.path.join(directory, old), os.path.join(directory, dest))

    action = "Would rename" if args.dry_run else "Renamed"
    print(f"{action} {len(final)} file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
