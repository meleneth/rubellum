require "spec_helper"
require "rubellum/parameters"

RSpec.describe Rubellum::Parameters do
  def parameter(type, **options)
    described_class.new([{ "name" => "value", "type" => type }.merge(options.transform_keys(&:to_s))])
  end

  it "provides typed defaults without mutating definitions" do
    definitions = [{ "name" => "count", "type" => "number", "default" => 2 }]
    parameters = described_class.new(definitions)
    definitions.first["default"] = 99
    expect(parameters.values).to eq("count" => 2.0)
    expect(parameters.definitions.first).to be_frozen
  end

  it "accepts text and enforces its byte limit" do
    expect(parameter("text").values("value" => "é")).to eq("value" => "é")
    [1, "x" * 4097].each { |value| expect { parameter("text").values("value" => value) }.to raise_error(ArgumentError) }
  end

  it "validates numeric and slider bounds including their endpoints" do
    %w[number slider].each do |type|
      parameters = parameter(type, min: 1, max: 5)
      expect(parameters.values("value" => "1")).to eq("value" => 1.0)
      expect(parameters.values("value" => 5)).to eq("value" => 5.0)
      [0, 6, "bad", nil, Float::INFINITY].each { |value| expect { parameters.values("value" => value) }.to raise_error(ArgumentError) }
    end
  end

  it "parses booleans explicitly, without Ruby truthiness" do
    parameters = parameter("boolean")
    expect(parameters.values("value" => "false")).to eq("value" => false)
    expect(parameters.values("value" => "true")).to eq("value" => true)
    expect(parameters.values).to eq("value" => false)
    expect { parameters.values("value" => "yes") }.to raise_error(ArgumentError)
  end

  it "accepts only declared select values and preserves their JSON type" do
    parameters = parameter("select", options: [1, 2], default: 1)
    expect(parameters.values("value" => "2")).to eq("value" => 2)
    expect { parameters.values("value" => 3) }.to raise_error(ArgumentError)
    expect { parameter("select", options: []) }.to raise_error(ArgumentError)
  end

  it "rejects invalid definitions, names, types, and duplicate names" do
    [{}, [nil], [{ "name" => "1bad", "type" => "text" }], [{ "name" => "x", "type" => "ruby" }],
     [{ "name" => "x", "type" => "text" }] * 2].each do |definitions|
      expect { described_class.new(definitions) }.to raise_error(ArgumentError)
    end
  end

  it "rejects unknown inputs and non-object input collections" do
    expect { parameter("text").values("typo" => "x") }.to raise_error(ArgumentError, /unknown/)
    expect { parameter("text").values([]) }.to raise_error(ArgumentError, /object/)
  end
end
