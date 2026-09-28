require "rubellum/data_directory"
require "tmpdir"

RSpec.describe Rubellum::DataDirectory do
  around { |example| Dir.mktmpdir("rubellum-data-") { |path| @root = path; example.run } }
  let(:directory) { described_class.new(root: @root) }
  let(:secret) { File.join(@root, "config/secret_key_base") }

  it "creates the durable layout and private secret on first boot" do
    directory.prepare
    described_class::DIRECTORIES.each { |name| expect(File.directory?(File.join(@root, name))).to be(true) }
    expect(File.read(secret)).to match(/\A[0-9a-f]{128}\z/)
    expect(File.stat(secret).mode & 0o777).to eq(0o600)
  end

  it "preserves instance identity across repeated boots" do
    directory.prepare
    original = File.read(secret)
    directory.prepare
    expect(File.read(secret)).to eq(original)
  end

  it "refuses a database major mismatch without overwriting user data" do
    directory.prepare
    version = File.join(@root, "postgres/PG_VERSION")
    File.write(version, "16\n")
    expect { directory.prepare }.to raise_error(/major mismatch/)
    expect(File.read(version)).to eq("16\n")
  end

  it "accepts the pinned major on subsequent boots" do
    directory.prepare
    File.write(File.join(@root, "postgres/PG_VERSION"), "17\n")
    expect { directory.prepare }.not_to raise_error
  end

  it "fails visibly on a corrupt secret instead of silently invalidating sessions" do
    directory.prepare
    File.write(secret, "broken")
    expect { directory.prepare }.to raise_error(/Invalid persisted Rails secret/)
    expect(File.read(secret)).to eq("broken")
  end
end
