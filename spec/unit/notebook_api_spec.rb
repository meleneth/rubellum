require "rubellum/notebook_api"
require "rubellum/artifact_writer"

RSpec.describe Rubellum::NotebookApi do
  let(:api) { described_class.new }
  let(:events) { [] }
  before { api.configure(inputs: { "scale" => 2 }, datasets: { "rows" => [1, 2] }) { |*event| events << event } }

  it "makes input snapshots immutable" do
    expect { api.inputs["scale"] = 3 }.to raise_error(FrozenError)
    expect { api.dataset("rows") << 3 }.to raise_error(FrozenError)
  end

  it "reports missing datasets rather than silently supplying nil" do
    expect { api.dataset("missing") }.to raise_error(KeyError)
  end

  it "validates object-shaped inputs and datasets" do
    expect { api.configure(inputs: [], datasets: {}) }.to raise_error(ArgumentError, /objects/)
    expect { api.configure(inputs: {}, datasets: []) }.to raise_error(ArgumentError, /objects/)
  end

  ["", "has spaces", "x" * 101, nil].each do |name|
    it "rejects invalid output name #{name.inspect}" do
      expect { api.emit(name, data: {}) }.to raise_error(ArgumentError)
      expect(events).to eq([])
    end
  end

  it "rejects excessive structured outputs before emitting" do
    expect { api.emit("large", data: "x" * described_class::MAX_OUTPUT_BYTES) }.to raise_error(ArgumentError, /exceeds/)
    expect(events).to be_empty
  end

  it "displays bounded plain text without interpreting it as machine-readable data" do
    api.display("<script>not HTML</script>")
    expect(events).to eq([["display", { "mime" => "text/plain", "value" => "<script>not HTML</script>" }]])
  end

  it "rejects unsupported MIME, coercion, and excessive display content" do
    expect { api.display("<b>HTML</b>", mime: "text/html") }.to raise_error(ArgumentError)
    expect { api.display(Object.new) }.to raise_error(ArgumentError)
    expect { api.display("x" * (described_class::MAX_OUTPUT_BYTES + 1)) }.to raise_error(ArgumentError)
  end

  it "emits an artifact only after the writer returns its durable reference" do
    writer = instance_double(Rubellum::ArtifactWriter)
    reference = { "filename" => "plot.png", "mime" => "image/png", "blob" => { "sha256" => "a" * 64, "size" => 42 } }
    expect(writer).to receive(:reset)
    expect(writer).to receive(:call).with("plot.png", mime: nil).and_return(reference)
    configured = described_class.new(artifact_writer: writer)
    configured.configure(inputs: {}, datasets: {}) { |*event| events << event }
    expect(configured.asset("plot.png")).to eq(reference)
    expect(events).to eq([["artifact", reference]])
  end

  it "does not emit an artifact if storage fails" do
    writer = instance_double(Rubellum::ArtifactWriter, reset: nil)
    allow(writer).to receive(:call).and_raise(Rubellum::BlobStore::Full, "quota")
    configured = described_class.new(artifact_writer: writer)
    configured.configure(inputs: {}, datasets: {}) { |*event| events << event }
    expect { configured.asset("plot.png") }.to raise_error(Rubellum::BlobStore::Full)
    expect(events).to be_empty
  end
end
