# frozen_string_literal: true

# Reads author and title from Kindle/Mobipocket (.mobi) PDB files using the
# first-record MOBI header and EXTH records (types 100 = author, 503 = title).
# Layout follows the usual Palm PDB + MOBI + EXTH conventions (see Mobileread wiki).

module MobiMetadata
  module_function

  KFX_MAGIC = [0xEA, 0x44, 0x52, 0x4D, 0x49, 0x4F, 0x4E, 0xEE].pack("C*").freeze
  TOPAZ_MAGIC = "TPZ".b.freeze

  def codec_for_codepage(codepage)
    case codepage
    when 65_001 then Encoding::UTF_8
    else Encoding::Windows_1252
    end
  end

  def decode_mobi_bytes(bytes, encoding)
    return +"" if bytes.nil? || bytes.empty?

    bytes.force_encoding(encoding).encode("UTF-8", invalid: :replace, undef: :replace)
  end

  def pdb_first_section(raw)
    return [nil, nil, "file too small"] if raw.bytesize < 86

    ident = raw.byteslice(60, 8).to_s.b.delete("\x00").upcase
    unless %w[BOOKMOBI TEXTREAD].include?(ident)
      return [nil, nil, "not a Mobipocket PDB (type #{ident.inspect})"]
    end

    num_sections = raw.byteslice(76, 2).unpack1("n")
    return [nil, nil, "invalid PDB (no record table)"] if num_sections < 2

    off0 = raw.byteslice(78, 4).unpack1("N")
    off1 = raw.byteslice(86, 4).unpack1("N")
    return [nil, nil, "invalid section offsets"] if off0 >= off1 || off0 >= raw.bytesize

    [raw.byteslice(off0, off1 - off0), nil, nil]
  end

  # Parses EXTH; yields long title from record 503 when present.
  def parse_exth(exth_blob, codec, title_from_header)
    return [nil, title_from_header] if exth_blob.nil? || exth_blob.bytesize < 12
    return [nil, title_from_header] unless exth_blob.byteslice(0, 4) == "EXTH"

    exth_total, num_items = exth_blob.byteslice(4, 8).unpack("NN")
    return [nil, title_from_header] if exth_total < 12 || exth_total > exth_blob.bytesize

    pos = 12
    author = nil
    title = title_from_header

    num_items.times do
      break if pos + 8 > exth_blob.bytesize

      idx, rec_len = exth_blob.byteslice(pos, 8).unpack("NN")
      break if rec_len < 8
      break if pos + rec_len > exth_blob.bytesize

      content = exth_blob.byteslice(pos + 8, rec_len - 8)
      pos += rec_len

      case idx
      when 100
        next if content.nil? || content.empty?

        author = decode_mobi_bytes(content, codec)&.strip
      when 503
        title = decode_mobi_bytes(content, codec)&.strip if content && !content.empty?
      end
    end

    [author, title]
  end

  def extract_author_title(path)
    raw = File.binread(path)
    return [nil, nil, "empty file"] if raw.empty?
    return [nil, nil, "Amazon Topaz (.tpz) — not supported"] if raw.start_with?(TOPAZ_MAGIC)
    return [nil, nil, "KFX — not supported"] if raw.byteslice(0, 8) == KFX_MAGIC

    section0, _err_section, err = pdb_first_section(raw)
    return [nil, nil, err] if section0.nil?

    if section0.bytesize <= 16
      return [nil, nil, "MOBI header too small (non-standard or ancient PRC)"]
    end

    return [nil, nil, 'expected "MOBI" at record 0'] unless section0.byteslice(16, 4) == "MOBI"

    mobi_len, _mobi_type, codepage = section0.byteslice(20, 12).unpack("NNN")
    codec = codec_for_codepage(codepage)

    exth_flag = section0.byteslice(0x80, 4).unpack1("N")

    toff, tlen = section0.byteslice(0x54, 8).unpack("NN")
    title_bytes =
      if toff && tlen && toff + tlen <= section0.bytesize
        section0.byteslice(toff, tlen)
      end

    title_from_header = title_bytes && !title_bytes.empty? ? decode_mobi_bytes(title_bytes, codec).strip : nil

    author = nil
    title = title_from_header

    if (exth_flag & 0x40) != 0 && mobi_len
      exth_off = 16 + mobi_len
      exth_blob = section0.byteslice(exth_off..)
      author, title = parse_exth(exth_blob, codec, title_from_header)
    end

    title = title_from_header if title.nil? || title.empty?

    return [nil, nil, "missing dc:title equivalent (no title in header/EXTH)"] if title.nil? || title.empty?
    return [nil, nil, "missing dc:creator equivalent (no EXTH author 100)"] if author.nil? || author.empty?

    [author, title, nil]
  rescue Errno::ENOENT => e
    [nil, nil, e.message]
  rescue StandardError => e
    [nil, nil, "MOBI parse error: #{e.message}"]
  end
end
