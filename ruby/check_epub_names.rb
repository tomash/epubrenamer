#!/usr/bin/env ruby
# frozen_string_literal: true

require "find"
require "optparse"
require "rexml/document"
require "zip"

def usage
  warn "Usage: #{$PROGRAM_NAME} [--interactive-rename] <ebook-directory>"
  exit 1
end

def rename_confirmed?(target_basename)
  STDERR.print "Rename to #{target_basename}? [y/n] "
  line = STDIN.gets
  return false if line.nil?

  line.strip.downcase.start_with?("y")
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
  /[\x00-\x1f\x7f\u0080-\u009F]|[#%&{}\[\]\\<>*?\/$!'":@+`|=]/u.freeze

def safe_title(title)
  s = title.to_s
  s = s.gsub(/\p{Extended_Pictographic}/u, "")
  s = s.gsub(/\uFE0F|\u200D/u, "")
  s = s.gsub(UNSAFE_TITLE_CHARS, "")
  s.gsub(/\s+/, " ").strip
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

def expected_basenames(author, raw_title)
  st = safe_title(raw_title)
  return [nil, "title empty after sanitizing"] if st.empty?

  variants = [
    "#{author} - #{st}.epub",
    "#{st} - #{author}.epub"
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
    opts.on("--interactive-rename", "Prompt y/n before each rename to the primary suggested name") do
      interactive_rename = true
    end
  end.parse!

  usage if ARGV.length != 1

  root = ARGV[0]
  unless File.directory?(root)
    warn "Not a directory: #{root}"
    exit 1
  end

  Find.find(root) do |path|
    next unless File.file?(path)
    next unless File.extname(path).casecmp?(".epub")
    next if under_calibre_directory?(path)

    basename = File.basename(path)
    author, title, err = extract_author_title(path)

    if err
      puts %(is: #{basename}, should be: [error: #{err}])
      next
    end

    expected, tmpl_err = expected_basenames(author, title)
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

      if rename_confirmed?(target)
        File.rename(path, dest)
        warn %(Renamed: #{basename} -> #{target})
      end
    end
  end
end

main if __FILE__ == $PROGRAM_NAME
