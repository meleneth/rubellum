# frozen_string_literal: true

require "rubellum/json_value"

RSpec.describe Rubellum::JsonValue do
  it "round trips JSON scalars, arrays, and string-keyed objects without coercion" do
    value = { "rows" => [{ "n" => 1.5, "ok" => true, "missing" => nil }], "n" => 42 }
    expect(described_class.copy(value)).to eq(value)
  end

  [Object.new, :symbol, Float::NAN, Float::INFINITY, -Float::INFINITY,
   { symbol: 1 }, { 1 => "one" }, "\xff".b].each do |value|
    it "rejects unsupported value #{value.inspect}" do
      expect { described_class.copy(value) }.to raise_error(Rubellum::JsonValue::Invalid)
    end
  end

  it "rejects invalid values nested inside otherwise valid objects" do
    expect { described_class.copy({ "rows" => [Object.new] }) }
      .to raise_error(Rubellum::JsonValue::Invalid, /\$\.rows\[0\]/)
  end

  it "copies and deeply freezes data without freezing the caller's values" do
    value = { "rows" => [+"before"] }
    copy = described_class.copy(value)
    value["rows"].first.replace("after")
    expect(copy).to eq({ "rows" => ["before"] })
    expect { copy["rows"] << "other" }.to raise_error(FrozenError)
    expect { copy["rows"].first.replace("other") }.to raise_error(FrozenError)
    expect(copy).to be_frozen
  end

  it "rejects cycles with a bounded error instead of overflowing the Ruby stack" do
    value = []
    value << value
    expect { described_class.copy(value) }.to raise_error(Rubellum::JsonValue::Invalid, /depth/)
  end

  it "enforces a nesting limit" do
    expect(described_class.copy([[1]], max_depth: 2)).to eq([[1]])
    expect { described_class.copy([[[1]]], max_depth: 2) }
      .to raise_error(Rubellum::JsonValue::Invalid, /depth/)
  end
end
