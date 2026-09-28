require "rubellum/artifact_writer"
require "tmpdir"

RSpec.describe Rubellum::ArtifactWriter do
  around do |example|
    Dir.mktmpdir("rubellum-artifacts-") do |directory|
      @directory = directory
      @store = Rubellum::BlobStore.new(directory: File.join(directory, "blobs"))
      @writer = described_class.new(store: @store, workspace: directory)
      example.run
    end
  end

  it "copies a workspace file into immutable storage and records its metadata" do
    File.write(File.join(@directory, "result.txt"), "first")
    artifact = @writer.call("result.txt")
    File.write(File.join(@directory, "result.txt"), "overwritten scratch")
    expect(@store.read(artifact["blob"])).to eq("first")
    expect(artifact).to include("filename" => "result.txt", "mime" => "text/plain")
    expect(artifact).to be_frozen
  end

  it "supports workspace subdirectories but refuses traversal, absolute paths and symlinks" do
    Dir.mkdir(File.join(@directory, "plots"))
    File.write(File.join(@directory, "plots/result.txt"), "plot")
    expect(@writer.call("plots/result.txt")["filename"]).to eq("result.txt")
    File.symlink("/etc/passwd", File.join(@directory, "linked.txt"))
    ["../outside", "/etc/passwd", "plots/../result.txt", "linked.txt", "", "plots//result.txt", "x\x00y"].each do |path|
      expect { @writer.call(path) }.to raise_error(ArgumentError)
    end
  end

  it "rejects directories, missing files and invalid MIME types" do
    expect { @writer.call("blobs") }.to raise_error(ArgumentError, /regular/)
    expect { @writer.call("absent") }.to raise_error(ArgumentError, /missing/)
    File.write(File.join(@directory, "file.txt"), "text")
    expect { @writer.call("file.txt", mime: "text/plain\r\nInjected: true") }.to raise_error(ArgumentError, /MIME/)
  end

  it "bounds artifacts per execution and resets the allowance for an explicit new execution" do
    File.write(File.join(@directory, "file.txt"), "text")
    described_class::MAX_COUNT.times { @writer.call("file.txt") }
    expect { @writer.call("file.txt") }.to raise_error(Rubellum::BlobStore::Full, /limit/)
    @writer.reset
    expect(@writer.call("file.txt")["blob"]["size"]).to eq(4)
  end

  it "refuses an execution byte budget overflow before copying the next file" do
    stub_const("Rubellum::ArtifactWriter::MAX_TOTAL_BYTES", 5)
    File.write(File.join(@directory, "file.txt"), "abc")
    @writer.call("file.txt")
    expect { @writer.call("file.txt") }.to raise_error(Rubellum::BlobStore::Full, /exceed/)
  end
end
