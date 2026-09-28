# frozen_string_literal: true

require "rubellum/message"

RSpec.describe Rubellum::Message do
  let(:attributes) { attributes_for(:runner_message).transform_keys(&:to_s) }

  it "round trips the versioned envelope without changing identities or payload" do
    message = described_class.new(attributes)
    expect(described_class.parse(message.to_json).to_h).to eq(attributes)
    expect(message.command?).to be(true)
  end

  it "distinguishes commands from committed event facts" do
    message = build(:runner_message, :started)
    expect(message.command?).to be(false)
  end

  %w[schema_version message_id kind app_installation_id notebook_id session_id generation sequence payload].each do |field|
    it "requires #{field}" do
      expect { described_class.new(attributes.reject { |key, _| key == field }) }
        .to raise_error(described_class::Invalid, /#{field}/)
    end
  end

  {
    "schema_version" => [0, 2, "1", 1.0],
    "kind" => ["unknown", "", nil],
    "generation" => [0, -1, 1.5, "1", nil],
    "sequence" => [0, -1, 1.5, "1", nil],
    "message_id" => ["not-a-uuid", "", nil],
    "app_installation_id" => ["../other-app", nil],
    "notebook_id" => ["", nil],
    "session_id" => ["", nil],
    "execution_id" => ["", nil],
    "payload" => [[], "source", nil, { "invalid" => Float::NAN }]
  }.each do |field, values|
    values.each do |value|
      it "rejects #{field}=#{value.inspect}" do
        expect { described_class.new(attributes.merge(field => value)) }
          .to raise_error(described_class::Invalid)
      end
    end
  end

  it "requires an execution identity for execution-related messages" do
    expect { described_class.new(attributes.reject { |key, _| key == "execution_id" }) }
      .to raise_error(described_class::Invalid, /execution_id/)
  end

  it "allows lifecycle messages without an execution identity" do
    lifecycle = attributes.merge("kind" => "runner_ready").reject { |key, _| key == "execution_id" }
    expect(described_class.new(lifecycle).to_h).to eq(lifecycle)
  end

  it "rejects unknown fields rather than silently dropping them" do
    expect { described_class.new(attributes.merge("generaton" => 9)) }
      .to raise_error(described_class::Invalid, /generaton/)
  end

  it "does not allow callers to mutate a validated message" do
    message = described_class.new(attributes)
    attributes["payload"]["source"].replace("exit!")
    expect(message.to_h["payload"]["source"]).to eq("puts 'hello'")
    expect { message.to_h["payload"]["source"].replace("exit!") }.to raise_error(FrozenError)
  end

  ["{", "null", "[]", "42"].each do |json|
    it "rejects malformed or non-object wire content #{json.inspect}" do
      expect { described_class.parse(json) }.to raise_error(described_class::Invalid)
    end
  end

  it "rejects duplicate keys that would otherwise hide conflicting identities" do
    json = JSON.generate(attributes).sub('"generation":1', '"generation":1,"generation":2')
    expect { described_class.parse(json) }.to raise_error(described_class::Invalid, /duplicate/i)
  end

  it "bounds wire size on both sending and receiving" do
    attributes["payload"] = { "source" => "x" * described_class::MAX_BYTES }
    expect { described_class.new(attributes) }.to raise_error(described_class::Invalid, /size/)
    expect { described_class.parse(" " * (described_class::MAX_BYTES + 1)) }
      .to raise_error(described_class::Invalid, /size/)
  end
end
