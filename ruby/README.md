# epubrenamer (Ruby)

Small utility that **compares ebook filenames to author and title from the file’s own metadata**, then reports whether each name matches one of two allowed patterns. Optionally it can **rename** files interactively.

## Purpose

- **EPUB**: reads `dc:title` and `dc:creator` from the OPF referenced by `META-INF/container.xml`.
- **MOBI**: reads title and author from the Mobipocket header / EXTH records (standard Kindle/Mobipocket layout).

For each file it expects the basename to be either:

- `Author - Title.ext`, or  
- `Title - Author.ext`

where `ext` is `.epub` or `.mobi`. Author and title are normalized (ASCII folding, unsafe filename characters removed, etc.) before comparison.

Files under a path segment named `calibre` (case-insensitive) are skipped (typical Calibre library layout). EPUBs whose title is mostly outside Latin-1 are reported but not renamed.

## Requirements

- Ruby 3.x (see `Gemfile`)
- [Bundler](https://bundler.io/)

## Setup

```bash
cd ruby
bundle install
```

## Usage

**Check only** (print `OK` or show current vs expected names):

```bash
bundle exec ruby check_epub_names.rb /path/to/ebooks
```

**Interactive rename** (prompts per file; `y` yes, `n` no, `a` yes to all, `q` quit):

```bash
bundle exec ruby check_epub_names.rb --interactive-rename /path/to/ebooks
```

The script walks the given directory **recursively**.

## Files

| File | Role |
|------|------|
| `check_epub_names.rb` | CLI: scan EPUB/MOBI, compare names, optional rename |
| `mobi_metadata.rb` | MOBI/PDB metadata extraction |
| `ascii_tic.rb` | String helpers (e.g. transliteration for safe filenames) |
