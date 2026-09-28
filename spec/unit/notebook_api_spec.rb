require "rubellum/notebook_api"

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
end
