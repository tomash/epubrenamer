# epubrenamer

See `/agent/AGENTS.md` for the multi-repo workspace layout.

## Cursor Cloud specific instructions

### Ruby (this repo pins the workspace Ruby version)

`.tool-versions` specifies **ruby 3.4.9**. From the repo root:

```bash
mise install
cd ruby && bundle install
bundle exec ruby check_epub_names.rb /path/to/ebooks
```

### Python (Cyrillic filenames)

Requires **`uconv`** on `PATH` (ICU). See `python/README.md`. No automated tests in-tree.

### Calibre

Not a running service; the Ruby tool skips paths containing a `calibre` directory segment.
