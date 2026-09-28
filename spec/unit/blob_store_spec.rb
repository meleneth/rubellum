require "rubellum/blob_store"
require "stringio"
require "tmpdir"

RSpec.describe Rubellum::BlobStore do
  around do |example|
    Dir.mktmpdir("rubellum-blobs-") do |directory|
      @directory = directory
      example.run
    end
  end
  let(:store) { described_class.new(directory: @directory, max_bytes: 10, quota: 15) }

  def put(bytes, **options)
    store.put(StringIO.new(bytes), **options)
  end

  it "addresses exact binary bytes by digest and returns an immutable reference" do
    bytes = "\x00\xffbinary".b
    reference = put(bytes)
    expect(reference).to eq("sha256" => Digest::SHA256.hexdigest(bytes), "size" => bytes.bytesize)
    expect(reference).to be_frozen
    expect(store.read(reference)).to eq(bytes)
    expect(File.stat(File.join(@directory, reference["sha256"])).mode & 0o222).to eq(0)
  end

  it "deduplicates without changing the existing inode or consuming more quota" do
    reference = put("x" * 10)
    inode = File.stat(File.join(@directory, reference["sha256"])).ino
    expect(put("x" * 10)).to eq(reference)
    expect(File.stat(File.join(@directory, reference["sha256"])).ino).to eq(inode)
  end

  it "retains the original bytes when a filename's replacement has different content" do
    old = put("before")
    replacement = put("after")
    expect(store.read(old)).to eq("before")
    expect(store.read(replacement)).to eq("after")
    expect(old["sha256"]).not_to eq(replacement["sha256"])
  end

  it "bounds individual writes and removes incomplete temporary files" do
    expect { put("x" * 11) }.to raise_error(described_class::Full, /exceeds/)
    expect(Dir.children(@directory)).to eq([".lock"])
  end

  it "refuses quota overflow without deleting retained content" do
    first = put("x" * 10)
    expect { put("y" * 6) }.to raise_error(described_class::Full, /retained/)
    expect(store.read(first)).to eq("x" * 10)
    expect(put("y" * 5)["size"]).to eq(5)
  end

  it "validates supplied digests and sizes before publishing imported content" do
    digest = Digest::SHA256.hexdigest("hello")
    expect(put("hello", expected_digest: digest, expected_size: 5)["sha256"]).to eq(digest)
    expect { put("other", expected_digest: digest, expected_size: 5) }.to raise_error(described_class::Invalid, /does not match/)
    expect { put("hello", expected_digest: digest, expected_size: 4) }.to raise_error(described_class::Invalid)
  end

  it "detects missing or corrupted bytes and never repairs them by overwriting history" do
    reference = put("good")
    filename = File.join(@directory, reference["sha256"])
    File.chmod(0o600, filename)
    File.binwrite(filename, "evil")
    expect { store.read(reference) }.to raise_error(described_class::Invalid, /digest/)
    expect { put("good") }.to raise_error(described_class::Invalid, /digest/)
    expect { store.read("sha256" => "0" * 64, "size" => 4) }.to raise_error(described_class::Invalid, /missing/)
  end

  it "rejects traversal, invalid sizes and symlinks" do
    [{ "sha256" => "../outside", "size" => 1 }, { "sha256" => "0" * 64, "size" => -1 },
     { "sha256" => "0" * 64, "size" => 11 }].each do |reference|
      expect { store.read(reference) }.to raise_error(described_class::Invalid)
    end
    File.symlink("/etc/passwd", File.join(@directory, "0" * 64))
    expect { store.read("sha256" => "0" * 64, "size" => 1) }.to raise_error(described_class::Invalid, /symbolic/)
    expect { described_class.for_app(root: @directory, app_id: "../outside") }.to raise_error(described_class::Invalid)
  end

  it "recovers a crashed writer's temporary file under the exclusive lock" do
    File.binwrite(File.join(@directory, ".incoming-abandoned.blob"), "partial")
    put("ready")
    expect(Dir.children(@directory).grep(/incoming/)).to be_empty
  end

  it "keeps distinct apps in distinct namespaces" do
    first = described_class.for_app(root: @directory, app_id: SecureRandom.uuid)
    second = described_class.for_app(root: @directory, app_id: SecureRandom.uuid)
    reference = first.put(StringIO.new("private"))
    expect { second.read(reference) }.to raise_error(described_class::Invalid, /missing/)
  end
end
