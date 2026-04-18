# epubrenamer (Python)

`cyrylic_to_romanized.py` **renames `.epub` files** whose **filenames contain Cyrillic characters** to **romanized ASCII**, using ICU’s `uconv` pipeline (`Any-Latin`, then `Latin-ASCII`).

## Purpose

Useful when you want filesystem-friendly, Latin-only names while keeping a predictable transliteration (not manual editing). The script only looks at the **basename** (the filename), not metadata inside the EPUB.

## Requirements

- **Python 3**
- **`uconv`** from [ICU](https://icu.unicode.org/) (package names vary: e.g. `icu` on Arch/Manjaro, `libicu` / `icu-devtools` elsewhere). It must be on your `PATH`.

## Usage

From the `python/` directory (or pass the full path to the script):

```bash
python3 cyrylic_to_romanized.py /path/to/epubs
```

**Dry run** (print planned `mv` lines without renaming):

```bash
python3 cyrylic_to_romanized.py -n /path/to/epubs
# or
python3 cyrylic_to_romanized.py --dry-run /path/to/epubs
```

Only the **single directory** you pass is used; **subdirectories are not** scanned. Only `*.epub` in that directory are considered.

If several files would transliterate to the same name, the script adds numeric suffixes (`_2`, `_3`, … or `__2`, …) so targets stay unique.

## See also

The **`ruby/`** tool checks whether EPUB/MOBI names match author/title from metadata (different job). This Python script only fixes **Cyrillic-in-filename** → **ASCII transliteration**.
