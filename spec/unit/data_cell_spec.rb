require "spec_helper"
require "rubellum/data_cell"

RSpec.describe Rubellum::DataCell do
  it "preserves JSON values and freezes the resulting dataset" do
    result = described_class.parse('[{"value":12,"active":false,"missing":null}]')
    expect(result).to eq([{ "value" => 12, "active" => false, "missing" => nil }])
    expect(result.first).to be_frozen
  end

  it "rejects malformed JSON and non-finite numbers" do
    ["{", "[NaN]", "[Infinity]"].each do |source|
      expect { described_class.parse(source) }.to raise_error(JSON::ParserError)
    end
  end

  it "parses quoted CSV without silently converting original strings" do
    expect(described_class.parse("name,value\n\"A,B\",001\n", "format" => "csv"))
      .to eq([{ "name" => "A,B", "value" => "001" }])
  end

  it "honors delimiter and header choices" do
    expect(described_class.parse("a;b\n1;2\n", "format" => "csv", "delimiter" => ";", "headers" => false))
      .to eq([["a", "b"], ["1", "2"]])
  end

  it "rejects duplicate or absent headers and mismatched rows" do
    ["a,a\n1,2", "a,\n1,2", "a,b\n1", "a\n1,2"].each do |source|
      expect { described_class.parse(source, "format" => "csv") }.to raise_error(ArgumentError)
    end
  end

  it "reports malformed CSV and invalid parsing configuration" do
    expect { described_class.parse('"unterminated', "format" => "csv") }.to raise_error(ArgumentError)
    expect { described_class.parse("", "format" => "csv", "delimiter" => "::") }.to raise_error(ArgumentError)
    expect { described_class.parse("", "format" => "yaml") }.to raise_error(ArgumentError)
  end

  it "handles empty CSV without manufacturing data" do
    expect(described_class.parse("", "format" => "csv")).to eq([])
  end
end
