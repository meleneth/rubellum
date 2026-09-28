require "rubellum/readiness"

RSpec.describe Rubellum::Readiness do
  it "requires real dependencies rather than an empty healthy shell" do
    expect { described_class.new(checks: {}) }.to raise_error(ArgumentError)
  end

  it "is ready only when all checks succeed" do
    result = described_class.new(checks: { postgres: -> { 1 }, sqs: -> { true } }).call
    expect(result).to eq(ready: true, services: { postgres: "ready", sqs: "ready" })
  end

  it "reports failed checks without exposing internal exception details" do
    result = described_class.new(checks: { postgres: -> { raise "secret" }, sqs: -> { true } }).call
    expect(result).to eq(ready: false, services: { postgres: "unavailable", sqs: "ready" })
  end

  it "treats a false result as unavailable" do
    expect(described_class.new(checks: { manager: -> { false } }).call.fetch(:ready)).to be(false)
  end
end
