require "rubellum/execution_payload"
require "tmpdir"

RSpec.describe Rubellum::ExecutionPayload do
  around do |example|
    Dir.mktmpdir("rubellum-payloads-") do |directory|
      @store = Rubellum::BlobStore.new(directory:)
      example.run
    end
  end

  it "keeps small payloads inline without touching the storage boundary" do
    store = instance_double(Rubellum::BlobStore)
    expect(store).not_to receive(:put)
    payload = { "source" => "42", "batch_id" => nil }
    expect(described_class.pack(payload, store:)).to eq(payload)
    expect(described_class.unpack(payload, store: nil)).to eq(payload)
  end

  it "round trips large source and input snapshots through a bounded digest reference" do
    payload = { "source" => "x" * 70_000, "inputs" => { "label" => "λ" }, "batch_id" => SecureRandom.uuid }
    reference = described_class.pack(payload, store: @store)
    expect(JSON.generate(reference).bytesize).to be < 256
    expect(reference["batch_id"]).to eq(payload["batch_id"])
    expect(described_class.unpack(reference, store: @store)).to eq(payload)
  end

  it "refuses payloads over the limit before writing bytes" do
    stub_const("Rubellum::ExecutionPayload::MAX_BYTES", 64)
    store = instance_double(Rubellum::BlobStore)
    expect(store).not_to receive(:put)
    expect { described_class.pack({ "source" => "x" * 65 }, store:) }.to raise_error(described_class::Invalid, /exceeds/)
  end

  it "rejects invalid, missing, oversized and mismatched references" do
    payload = { "source" => "x" * 70_000, "batch_id" => SecureRandom.uuid }
    reference = described_class.pack(payload, store: @store)
    expect { described_class.unpack(reference, store: nil) }.to raise_error(described_class::Invalid)
    expect { described_class.unpack(reference.merge("batch_id" => SecureRandom.uuid), store: @store) }.to raise_error(described_class::Invalid, /metadata/)
    expect { described_class.unpack(reference.merge("source" => "injected"), store: @store) }.to raise_error(described_class::Invalid)
    expect { described_class.unpack({ "payload_ref" => { "size" => described_class::MAX_BYTES + 1 } }, store: @store) }.to raise_error(described_class::Invalid)
    expect { described_class.unpack({ "payload_ref" => { "sha256" => "0" * 64, "size" => 1 } }, store: @store) }.to raise_error(described_class::Invalid, /missing/)
  end

  it "does not follow nested references or reinterpret non-object JSON as an execution" do
    ["[]", JSON.generate("payload_ref" => {}, "batch_id" => nil)].each do |json|
      reference = @store.put(StringIO.new(json))
      expect { described_class.unpack({ "payload_ref" => reference }, store: @store) }.to raise_error(described_class::Invalid, /metadata/)
    end
  end
end
