#!/usr/bin/env ruby
# frozen_string_literal: true

require "find"
require "optparse"
require "rexml/document"
require "zip"

require_relative "ascii_tic"
require_relative "mobi_metadata"
String.include AsciiTic

def usage
  warn "Usage: #{$PROGRAM_NAME} [--interactive-rename] <ebook-directory>"
  warn "Checks .epub and .mobi files (same naming rules)."
  exit 1
end

# Returns :yes, :no, :all (yes + rename all subsequent without asking), or :quit
def read_rename_decision(target_basename)
  STDERR.print "Rename to #{target_basename}? [y/n/a/q] "
  line = STDIN.gets
  return :no if line.nil?

  case line.strip.downcase
  when "y", "yes" then :yes
  when "a", "all" then :all
  when "q", "quit" then :quit
  else :no
  end
end

def epub_rootfile_path(zip)
  entry = zip.find_entry("META-INF/container.xml")
  return nil unless entry

  xml = zip.read(entry)
  doc = REXML::Document.new(xml)
  rootfile = REXML::XPath.first(doc, "//*[local-name()='rootfile']")
  return nil unless rootfile

  rootfile.attribute("full-path")&.to_s
end

def read_zip_entry(zip, path)
  entry = zip.find_entry(path)
  return nil unless entry

  zip.read(entry)
end

# Reference: common illegal filename characters (# % & {} \ <> * ? / $ ! ' " : @ + ` | =),
# plus [] for glob/shell safety; controls/C1; emojis (Extended_Pictographic) and stray VS/ZWJ.
# Spaces (U+0020) are kept; other whitespace is removed via the control-char rule where applicable.
UNSAFE_TITLE_CHARS =
  /[\x00-\x1f\x7f\u0080-\u009F]|[#%&{}\[\]\\<>*?\/$!'":@+`|=\u2019\u201C\u201D\u201E]/u.freeze

def safe_title(title)
  s = title.to_s.to_ascii_brutal
  s = s.gsub(/\p{Extended_Pictographic}/u, "")
  s = s.gsub(/\uFE0F|\u200D/u, "")
  s = s.gsub(UNSAFE_TITLE_CHARS, "")
  s.gsub(/\s+/, " ").strip
end

# ISO-8859-1 spans U+0000–U+00FF. True when over half of codepoints are above that range (e.g. Cyrillic).
def title_mostly_outside_latin1?(title)
  s = title.to_s
  return false if s.empty?

  outside = s.each_char.count { |c| c.ord > 0xFF }
  (outside.to_f / s.length) > 0.5
end

def texts_for_local_name(doc, local)
  REXML::XPath.match(doc, "//*[local-name()='#{local}']").filter_map do |el|
    t = el.text&.strip
    t unless t.nil? || t.empty?
  end
end

def metadata_from_opf(xml)
  doc = REXML::Document.new(xml)
  titles = texts_for_local_name(doc, "title")
  creators = texts_for_local_name(doc, "creator")
  [titles.first, creators.join(", ")]
end

def extract_author_title(epub_path)
  Zip::File.open(epub_path) do |zip|
    rootfile_rel = epub_rootfile_path(zip)
    return [nil, nil, "no META-INF/container.xml or rootfile"] unless rootfile_rel

    opf_xml = read_zip_entry(zip, rootfile_rel)
    return [nil, nil, "cannot read OPF: #{rootfile_rel}"] unless opf_xml

    title, author = metadata_from_opf(opf_xml)
    return [nil, nil, "missing dc:title"] if title.nil? || title.empty?
    return [nil, nil, "missing dc:creator"] if author.nil? || author.empty?

    [author, title, nil]
  end
rescue Zip::Error => e
  [nil, nil, "not a valid zip/epub: #{e.message}"]
rescue StandardError => e
  [nil, nil, e.message]
end

def expected_basenames(author, raw_title, ext)
  sa = safe_title(author)
  return [nil, "author empty after sanitizing"] if sa.empty?

  st = safe_title(raw_title)
  return [nil, "title empty after sanitizing"] if st.empty?

  suffix = ext.downcase
  variants = [
    "#{sa} - #{st}#{suffix}",
    "#{st} - #{sa}#{suffix}"
  ]
  [variants, nil]
end

CALIBRE_DIR = /calibre/i.freeze

def under_calibre_directory?(path)
  File.dirname(path).split(File::SEPARATOR).any? { |segment| segment.match?(CALIBRE_DIR) }
end

def main
  interactive_rename = false
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] <ebook-directory>"
    opts.on("--interactive-rename", "Prompt before each rename: y=yes, n=no, a=yes to all, q=quit") do
      interactive_rename = true
    end
  end.parse!

  usage if ARGV.length != 1

  root = ARGV[0]
  unless File.directory?(root)
    warn "Not a directory: #{root}"
    exit 1
  end

  rename_all = false
  Find.find(root) do |path|
    next unless File.file?(path)
    ext = File.extname(path)
    next unless [".epub", ".mobi"].any? { |e| ext.casecmp?(e) }
    next if under_calibre_directory?(path)

    basename = File.basename(path)
    author, title, err =
      if ext.casecmp?(".epub")
        extract_author_title(path)
      else
        MobiMetadata.extract_author_title(path)
      end

    if err
      puts %(is: #{basename}, should be: [error: #{err}])
      next
    end

    if title_mostly_outside_latin1?(title)
      puts %(#{basename} OK (rename skipped: title mostly outside Latin-1))
      next
    end

    expected, tmpl_err = expected_basenames(author, title, ext)
    if tmpl_err
      puts %(is: #{basename}, should be: [error: #{tmpl_err}])
      next
    end

    if expected.include?(basename)
      puts %(#{basename} OK)
    else
      puts %(is: #{basename}, should be: #{expected.join(" or ")})

      next unless interactive_rename

      target = expected.first
      dir = File.dirname(path)
      dest = File.join(dir, target)
      if File.exist?(dest)
        warn %(target already exists, skipping rename: #{target})
        next
      end

      unless rename_all
        case read_rename_decision(target)
        when :quit
          exit 0
        when :all
          rename_all = true
        when :no
          next
        end
      end

      File.rename(path, dest)
      warn %(Renamed: #{basename} -> #{target})
    end
  end
end

main if __FILE__ == $PROGRAM_NAME
