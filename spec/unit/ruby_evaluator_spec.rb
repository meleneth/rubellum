require "rubellum/ruby_evaluator"
require "securerandom"

RSpec.describe Rubellum::RubyEvaluator do
  let(:evaluator) { described_class.new }
  let(:cell_id) { SecureRandom.uuid }
  def evaluate(source, **args, &events)
    evaluator.call(source:, cell_id:, **args, &events)
  end

  it "retains variables, methods, and required libraries between cells" do
    expect(evaluate("require 'set'; values = Set[1, 2]; def answer; 42; end")["kind"]).to eq("execution_completed")
    expect(evaluate("[values.size, answer]").dig("payload", "inspection")).to eq("[2, 42]")
  end

  it "keeps notebook contexts separate" do
    evaluate("secret = 42")
    other = described_class.new.call(source: "defined?(secret)", cell_id:)
    expect(other.dig("payload", "inspection")).to eq("nil")
  end

  it "supplies immutable inputs and datasets and emits structured values separately" do
    events = []
    result = evaluate('Notebook.emit("sum", data: Notebook.dataset("rows").sum * Notebook.inputs["scale"]); :done',
      inputs: { "scale" => 2 }, datasets: { "rows" => [1, 2] }) { |*event| events << event }
    expect(events).to eq([["structured_output", { "name" => "sum", "data" => 6 }]])
    expect(result.dig("payload", "inspection")).to eq(":done")
  end

  it "rejects non-JSON outputs without stringifying them" do
    result = evaluate('Notebook.emit("bad", data: Float::NAN)') { raise "must not emit" }
    expect(result["kind"]).to eq("execution_failed")
    expect(result.dig("payload", "message")).to include("finite")
  end

  it "reports cell-local error lines" do
    result = evaluate("a = 1\nraise 'broken'")
    expect(result.dig("payload", "backtrace").first).to include("cell:#{cell_id}:2")
    expect(result.dig("payload", "error_class")).to eq("RuntimeError")
  end

  it "survives syntax errors for a subsequent explicit run" do
    expect(evaluate("def broken(")["kind"]).to eq("execution_failed")
    expect(evaluate("21 * 2").dig("payload", "inspection")).to eq("42")
  end

  it "bounds inspected return values and labels truncation" do
    result = evaluate("'x' * 20000")
    expect(result.dig("payload", "inspection").bytesize).to eq(described_class::MAX_INSPECT_BYTES)
    expect(result.dig("payload", "inspection_truncated")).to be(true)
  end

  it "reports interrupt as a distinct outcome with potentially changed state" do
    result = evaluate("raise Interrupt")
    expect(result["kind"]).to eq("execution_interrupted")
  end
end
