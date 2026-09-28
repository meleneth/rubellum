require "rubellum/runtime_journal"
require "tmpdir"

RSpec.describe Rubellum::RuntimeJournal do
  around do |example|
    Dir.mktmpdir("rubellum-journal-") do |directory|
      @directory = directory
      @journal = described_class.new(directory:)
      example.run
    ensure
      @journal&.close
    end
  end

  it "recovers committed state from disk" do
    @journal.update { |state| state["accepted"] = ["one"] }
    @journal.close
    @journal = described_class.new(directory: @directory)
    expect(@journal.state).to eq("accepted" => ["one"])
  end

  it "protects state against mutation outside a durable update" do
    @journal.update { |state| state["events"] = [] }
    expect { @journal.state["events"] << "lost" }.to raise_error(FrozenError)
  end

  it "permits exactly one process owner" do
    expect { described_class.new(directory: @directory) }.to raise_error(described_class::Owned)
  end

  it "preserves the old committed state if replacement fails" do
    @journal.update { |state| state["n"] = 1 }
    expect(File).to receive(:rename).and_raise(Errno::ENOSPC)
    expect { @journal.update { |state| state["n"] = 2 } }.to raise_error(Errno::ENOSPC)
    expect(@journal.state).to eq("n" => 1)
    expect(JSON.parse(File.read(File.join(@directory, "state.json")))).to eq("n" => 1)
  end

  it "reserves capacity for terminal events under output pressure" do
    @journal.close
    @journal = described_class.new(directory: @directory, limit: 1000, reserve: 200)
    expect { @journal.update { |state| state["output"] = "x" * 850 } }.to raise_error(described_class::Full)
    expect(@journal.state).to eq({})
    @journal.update(terminal: true) { |state| state["output"] = "x" * 850 }
    expect(@journal.state.fetch("output").size).to eq(850)
  end

  it "bounds even terminal writes" do
    @journal.close
    @journal = described_class.new(directory: @directory, limit: 1000, reserve: 200)
    expect { @journal.update(terminal: true) { |state| state["data"] = "x" * 1000 } }.to raise_error(described_class::Full)
  end

  it "refuses corrupt persisted state instead of silently losing deduplication records" do
    @journal.close
    File.write(File.join(@directory, "state.json"), "{")
    expect { described_class.new(directory: @directory) }.to raise_error(JSON::ParserError)
  end
end
