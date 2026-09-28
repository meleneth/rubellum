# frozen_string_literal: true
require "rubygems/package"
require "stringio"
require "zlib"

module Rubellum
  # A bounded, inert container. Package semantics are validated separately.
  # Nothing is extracted, and only regular files with canonical paths are accepted.
  class PackageArchive
    class Invalid < ArgumentError; end
    BLOCK = 512
    ZERO = ("\0" * BLOCK).b.freeze

    def initialize(compressed_limit: 64 * 1024 * 1024, expanded_limit: 256 * 1024 * 1024,
      file_limit: 32 * 1024 * 1024, entry_limit: 10_000)
      @compressed_limit, @expanded_limit = compressed_limit, expanded_limit
      @file_limit, @entry_limit = file_limit, entry_limit
    end

    def read(io)
      compressed = io.read(@compressed_limit + 1) || "".b
      raise Invalid, "Compressed archive exceeds limit" if compressed.bytesize > @compressed_limit
      input = StringIO.new(compressed)
      gzip = Zlib::GzipReader.new(input)
      bytes = gzip.read(@expanded_limit + 1) || "".b
      raise Invalid, "Expanded archive exceeds limit" if bytes.bytesize > @expanded_limit
      raise Invalid, "Trailing or concatenated gzip data" if gzip.unused || !input.eof?
      parse(bytes)
    rescue Zlib::Error, EOFError => error
      raise Invalid, "Invalid gzip archive: #{error.message}"
    ensure
      gzip&.close
    end

    def write(files)
      raise Invalid, "Files must be a path-to-bytes map" unless files.is_a?(Hash)
      validate_paths!(files.keys)
      tar = String.new(encoding: Encoding::BINARY)
      files.sort.each do |path, bytes|
        raise Invalid, "File bytes must be strings" unless bytes.is_a?(String)
        raise Invalid, "File exceeds limit" if bytes.bytesize > @file_limit
        padding = (-bytes.bytesize) % BLOCK
        raise Invalid, "Expanded archive exceeds limit" if tar.bytesize + BLOCK + bytes.bytesize + padding + 2 * BLOCK > @expanded_limit
        tar << Gem::Package::TarHeader.new(name: path, prefix: "", size: bytes.bytesize,
          mode: 0o600, mtime: 0, uname: "", gname: "").to_s
        tar << bytes.b << ("\0" * padding)
      end
      tar << ZERO << ZERO
      raise Invalid, "Expanded archive exceeds limit" if tar.bytesize > @expanded_limit
      output = StringIO.new
      gzip = Zlib::GzipWriter.new(output)
      gzip.mtime = 0
      gzip.write(tar)
      gzip.close
      raise Invalid, "Compressed archive exceeds limit" if output.string.bytesize > @compressed_limit
      output.string
    end

    private

    def parse(bytes)
      stream = StringIO.new(bytes)
      files = {}
      loop do
        raw = exact_read(stream, BLOCK)
        if raw == ZERO
          raise Invalid, "Missing archive terminator" unless exact_read(stream, BLOCK) == ZERO
          tail = stream.read
          raise Invalid, "Trailing archive data" unless tail.bytesize % BLOCK == 0 && tail.bytes.all?(&:zero?)
          validate_paths!(files.keys)
          return files.freeze
        end
        checksum = raw.byteslice(148, 8)
        raise Invalid, "Invalid header checksum" unless /\A[0-7]+\x00? *\z/n.match?(checksum)
        actual = raw.bytes.sum - checksum.bytes.sum + 8 * 32
        raise Invalid, "Header checksum mismatch" unless checksum.to_i(8) == actual
        header = Gem::Package::TarHeader.from(StringIO.new(raw))
        unless header.typeflag == "0" && header.linkname.empty? && header.prefix.empty? &&
            header.magic == "ustar" && header.version == 0
          raise Invalid, "Only plain regular USTAR files are supported"
        end
        # Reject hidden suffixes in NUL-terminated names, not merely the parsed name.
        path = header.name
        raise Invalid, "Noncanonical file name" unless raw.byteslice(0, 100) == path.ljust(100, "\0")
        validate_path!(path)
        raise Invalid, "Duplicate archive path" if files.key?(path)
        raise Invalid, "Too many archive entries" if files.size >= @entry_limit
        raise Invalid, "File exceeds limit" if header.size > @file_limit
        files[path.freeze] = exact_read(stream, header.size).freeze
        padding = exact_read(stream, (-header.size) % BLOCK)
        raise Invalid, "Nonzero file padding" unless padding.bytes.all?(&:zero?)
      end
    rescue ArgumentError => error
      raise Invalid, error.message
    end

    def exact_read(stream, size)
      value = stream.read(size)
      raise Invalid, "Truncated archive" unless value && value.bytesize == size
      value
    end

    def validate_paths!(paths)
      raise Invalid, "Too many archive entries" if paths.size > @entry_limit
      paths.each { |path| validate_path!(path) }
      known = paths.to_h { |path| [path, true] }
      paths.each do |path|
        segments = path.split("/")
        (1...segments.size).each do |length|
          raise Invalid, "Conflicting archive paths" if known.key?(segments.first(length).join("/"))
        end
      end
    end

    def validate_path!(path)
      unless path.is_a?(String) && path.ascii_only? && path.bytesize.between?(1, 100) &&
          /\A[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*\z/.match?(path) &&
          (path.split("/") & [".", ".."]).empty?
        raise Invalid, "Unsafe archive path"
      end
    end
  end
end
