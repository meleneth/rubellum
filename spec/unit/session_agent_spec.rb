require "rubellum/session_agent"
require "tmpdir"

RSpec.describe Rubellum::SessionAgent do
  let(:scope) { attributes_for(:runner_message).transform_keys(&:to_s).slice(*described_class::SCOPE_FIELDS) }
  let(:transport) { instance_double(Rubellum::SqsTransport) }
  let(:evaluator) { instance_double(Rubellum::EvaluatorProcess, pid: nil) }
  let(:payload) { { "source" => "42", "source_digest" => Digest::SHA256.hexdigest("42"), "cell_id" => SecureRandom.uuid, "cell_revision_id" => SecureRandom.uuid } }
  let(:command) { build(:runner_message, **scope.symbolize_keys, payload:) }

  around do |example|
    Dir.mktmpdir("rubellum-agent-") do |directory|
      @journal = Rubellum::RuntimeJournal.new(directory:)
      example.run
    ensure
      @journal&.close
    end
  end

  let(:agent) { described_class.new(scope:, transport:, journal: @journal, evaluator:) }

  it "durably accepts and deduplicates without evaluating at acceptance" do
    expect(evaluator).not_to receive(:execute)
    agent.accept(command)
    agent.accept(command)
    expect(@journal.state.fetch("commands").size).to eq(1)
    expect(@journal.state.fetch("events").map { |event| event["kind"] }).to eq(%w[runner_ready execution_accepted])
  end

  it "fences delayed messages from another generation" do
    agent.accept(build(:runner_message, **scope.symbolize_keys, generation: scope.fetch("generation") + 1, payload:))
    expect(@journal.state.fetch("commands")).to be_empty
  end

  it "rejects altered source before acceptance" do
    bad = build(:runner_message, **scope.symbolize_keys, payload: payload.merge("source" => "exit!"))
    expect { agent.accept(bad) }.to raise_error(described_class::ProtocolError, /digest/)
    expect(@journal.state.fetch("commands")).to be_empty
  end

  it "refuses two different commands using the same sequence" do
    agent.accept(command)
    expect { agent.accept(build(:runner_message, **scope.symbolize_keys, payload:)) }.to raise_error(described_class::ProtocolError, /sequence/)
  end

  it "does not reuse a journal to reconstruct a lost Ruby context" do
    agent
    expect { described_class.new(scope:, transport:, journal: @journal, evaluator:) }.to raise_error(described_class::ProtocolError, /replacement/)
  end

  it "cancels the rest of a failed batch without evaluating it, but permits an explicit new run" do
    batch_id = SecureRandom.uuid
    first = build(:runner_message, **scope.symbolize_keys, payload: payload.merge("batch_id" => batch_id))
    second = build(:runner_message, **scope.symbolize_keys, sequence: 2, payload: payload.merge("batch_id" => batch_id))
    third = build(:runner_message, **scope.symbolize_keys, sequence: 3, payload:)
    allow(transport).to receive(:ensure_queue).and_return("queue")
    allow(transport).to receive(:receive).and_return([])
    allow(transport).to receive(:publish)
    expect(evaluator).to receive(:execute).ordered.and_yield("execution_failed", { "message" => "failed" })
    expect(evaluator).to receive(:execute).ordered.and_yield("execution_completed", { "inspection" => "42" })
    [second, first, third].each { |message| agent.accept(message) }
    3.times { agent.step }
    expect(@journal.state.fetch("commands").values_at("1", "2", "3").map { |item| item["state"] })
      .to eq(%w[execution_failed execution_cancelled execution_completed])
    expect(@journal.state.fetch("events").count { |event| event["kind"] == "execution_started" }).to eq(2)
  end

  it "rejects a malformed batch identifier before acceptance" do
    message = build(:runner_message, **scope.symbolize_keys, payload: payload.merge("batch_id" => "not-a-uuid"))
    expect { agent.accept(message) }.to raise_error(described_class::ProtocolError)
  end
end
