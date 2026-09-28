require "rubellum/package_archive"

RSpec.describe Rubellum::PackageArchive do
  subject(:archive) { described_class.new }

  def gzip(bytes)
    output = StringIO.new
    writer = Zlib::GzipWriter.new(output)
    writer.write(bytes)
    writer.close
    output.string
  end

  def entry(path: "manifest.json", bytes: "{}", **header)
    Gem::Package::TarHeader.new(name: path, prefix: "", mode: 0o600,
      size: bytes.bytesize, **header).to_s + bytes + "\0" * ((-bytes.bytesize) % 512)
  end

  def unpack(bytes)
    archive.read(StringIO.new(bytes))
  end

  it "round trips readable sources and exact binary assets without extraction" do
    files = { "manifest.json" => "{}", "sources/cell.md" => "# Hello\n",
      "assets/hash" => "\0\xff".b, "empty" => "" }
    result = unpack(archive.write(files))
    expect(result).to eq(files)
    expect(result).to be_frozen
    expect(result.values).to all(be_frozen)
    expect(archive.write(files)).to eq(archive.write(files.to_a.reverse.to_h))
  end

  it "rejects unsafe or ambiguous paths on both read and write" do
    ["../escape", "/absolute", "./file", "a/../b", "a//b", "a\\b", "a/", "a\0b", "é", "a" * 101].each do |path|
      expect { archive.write(path => "x") }.to raise_error(described_class::Invalid, /path/)
      # USTAR truncates names over 100 bytes on construction; reject them before writing.
      if path.bytesize <= 100
        expect { unpack(gzip(entry(path: path) + "\0" * 1024)) }.to raise_error(described_class::Invalid)
      end
    end
  end

  it "rejects links, directories, devices and extension headers" do
    %w[1 2 3 4 5 6 x g L K].each do |type|
      expect { unpack(gzip(entry(typeflag: type, linkname: "../../outside") + "\0" * 1024)) }
        .to raise_error(described_class::Invalid, /regular/)
    end
    expect { unpack(gzip(entry(prefix: "hidden") + "\0" * 1024)) }.to raise_error(described_class::Invalid)
  end

  it "rejects duplicate entries, including identical bytes" do
    expect { unpack(gzip(entry + entry + "\0" * 1024)) }.to raise_error(described_class::Invalid, /Duplicate/)
    expect { unpack(gzip(entry(path: "a") + entry(path: "a/b") + "\0" * 1024)) }
      .to raise_error(described_class::Invalid, /Conflicting/)
    expect { archive.write("a" => "", "a/b" => "") }.to raise_error(described_class::Invalid, /Conflicting/)
  end

  it "checks header checksums and payload compression integrity" do
    damaged = entry
    damaged.setbyte(0, "X".ord)
    expect { unpack(gzip(damaged + "\0" * 1024)) }.to raise_error(described_class::Invalid, /checksum/)
    compressed = archive.write("manifest.json" => "{}")
    compressed.setbyte(compressed.bytesize - 8, compressed.getbyte(-8) ^ 1)
    expect { unpack(compressed) }.to raise_error(described_class::Invalid, /gzip/)
  end

  it "rejects truncated data, missing terminators and nonzero padding" do
    expect { unpack("") }.to raise_error(described_class::Invalid)
    ["", "bad", entry[0, 513], entry, entry + "\0" * 512,
      entry + "\0" * 1024 + entry, entry + "\0" * 1025].each do |raw|
      expect { unpack(gzip(raw)) }.to raise_error(described_class::Invalid)
    end
    damaged = entry
    damaged.setbyte(514, 1)
    expect { unpack(gzip(damaged + "\0" * 1024)) }.to raise_error(described_class::Invalid, /padding/)
    expect { unpack(archive.write("file" => "hello")[0...-3]) }.to raise_error(described_class::Invalid)
  end

  it "rejects trailing or concatenated gzip streams" do
    good = archive.write("file" => "hello")
    [good + "junk", good + good].each do |bytes|
      expect { unpack(bytes) }.to raise_error(described_class::Invalid, /Trailing/)
    end
  end

  it "bounds compressed input, expansion, files and entry counts" do
    bytes = archive.write("one" => "a" * 2048, "two" => "b")
    [{ compressed_limit: bytes.bytesize - 1 }, { expanded_limit: 2048 },
      { file_limit: 2047 }, { entry_limit: 1 }].each do |limits|
      bounded = described_class.new(**limits)
      expect { bounded.read(StringIO.new(bytes)) }.to raise_error(described_class::Invalid)
      expect { bounded.write("one" => "a" * 2048, "two" => "b") }.to raise_error(described_class::Invalid)
    end
  end

  it "accepts exact configured boundaries and refuses non-string content" do
    files = { "one" => "a" * 512 }
    bytes = archive.write(files)
    bounded = described_class.new(compressed_limit: bytes.bytesize, expanded_limit: 2048, file_limit: 512, entry_limit: 1)
    expect(bounded.read(StringIO.new(bytes))).to eq(files)
    expect(bounded.write(files)).to eq(bytes)
    expect { archive.write("one" => nil) }.to raise_error(described_class::Invalid)
    expect { archive.write([]) }.to raise_error(described_class::Invalid)
  end
end
