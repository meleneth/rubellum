require "rubellum/session_agent"
require "tmpdir"

RSpec.describe Rubellum::SessionAgent do
  let(:scope) { attributes_for(:runner_message).transform_keys(&:to_s).slice(*described_class::SCOPE_FIELDS) }
  let(:transport) { instance_double(Rubellum::SqsTransport) }
  let(:evaluator) { instance_double(Rubellum::EvaluatorProcess, pid: nil) }
  let(:payload) { { "source" => "42", "source_digest" => Digest::SHA256.hexdigest("42"), "cell_id" => SecureRandom.uuid, "cell_revision_id" => SecureRandom.uuid } }
  let(:command) { build(:runner_message, **scope.symbolize_keys, payload:) }
  let(:payload_store) { nil }

  around do |example|
    Dir.mktmpdir("rubellum-agent-") do |directory|
      @journal = Rubellum::RuntimeJournal.new(directory:)
      example.run
    ensure
      @journal&.close
    end
  end

  let(:agent) { described_class.new(scope:, transport:, journal: @journal, evaluator:, payload_store:) }

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

  context "with interrupt controls" do
    let(:control_queue) { Rubellum::QueueNames.session(scope["session_id"], scope["generation"], control: true) }

    before do
      allow(transport).to receive(:ensure_queue) { |name| name }
      allow(transport).to receive(:receive).and_return([])
      allow(transport).to receive(:publish)
      allow(transport).to receive(:delete)
    end

    def deliver_interrupt(execution_id: command["execution_id"], sequence: command["sequence"], generation: scope["generation"])
      message = build(:runner_message, **scope.symbolize_keys, kind: "interrupt", execution_id:, sequence:, generation:, payload: {})
      delivery = Rubellum::SqsTransport::Delivery.new(message:, receipt_handle: "control-receipt")
      allow(transport).to receive(:receive).with(control_queue, wait_seconds: 0).and_return([delivery], [])
      delivery
    end

    it "durably records early cancellation before deleting control delivery and never evaluates its source" do
      delivery = deliver_interrupt
      expect(transport).to receive(:delete).with(control_queue, delivery) do
        expect(@journal.state.fetch("interrupts").fetch("1")).to eq(command["execution_id"])
      end
      expect(evaluator).not_to receive(:execute)
      agent.step
      deliver_interrupt
      agent.step
      expect(@journal.state.fetch("interrupts")).to eq("1" => command["execution_id"])
      agent.accept(command)
      agent.step
      expect(@journal.state.fetch("commands").fetch("1")["state"]).to eq("execution_cancelled")
      expect(@journal.state.fetch("next_command")).to eq(2)
      expect(@journal.state.fetch("events").map { |event| event["kind"] }).not_to include("execution_started")
      expect(@journal.state.fetch("interrupts")).to be_empty
    end

    it "rejects an interrupt whose execution identity conflicts with an accepted sequence" do
      agent.accept(command)
      deliver_interrupt(execution_id: SecureRandom.uuid)
      expect { agent.step }.to raise_error(described_class::ProtocolError, /interrupt/)
      expect(@journal.state.fetch("commands").fetch("1")["state"]).to eq("accepted")
    end

    it "does not let an early interrupt cancel a different execution later claiming its sequence" do
      deliver_interrupt
      agent.step
      different = build(:runner_message, **scope.symbolize_keys, payload:)
      expect { agent.accept(different) }.to raise_error(described_class::ProtocolError, /interrupt/)
      expect(@journal.state.fetch("commands")).to be_empty
    end

    it "ignores old-generation and already-terminal interrupts" do
      deliver_interrupt(generation: scope["generation"] + 1)
      expect(evaluator).to receive(:execute).once.and_yield("execution_completed", { "inspection" => "42" })
      agent.accept(command)
      agent.step
      deliver_interrupt
      agent.step
      expect(@journal.state.fetch("commands").fetch("1")["state"]).to eq("execution_completed")
      expect(@journal.state.fetch("interrupts", {})).to be_empty
    end
  end

  context "with referenced command payloads" do
    let(:payload_store) { instance_double(Rubellum::BlobStore) }
    let(:reference) { { "sha256" => "a" * 64, "size" => JSON.generate(payload).bytesize } }
    let(:command) { build(:runner_message, **scope.symbolize_keys, payload: { "payload_ref" => reference }) }

    it "cancels before evaluation if an accepted payload subsequently becomes corrupt" do
      expect(payload_store).to receive(:read).with(reference).ordered.and_return(JSON.generate(payload))
      expect(payload_store).to receive(:read).with(reference).ordered.and_raise(Rubellum::BlobStore::Invalid, "corrupt")
      allow(transport).to receive(:ensure_queue).and_return("queue")
      allow(transport).to receive(:receive).and_return([])
      allow(transport).to receive(:publish)
      expect(evaluator).not_to receive(:execute)
      agent.accept(command)
      agent.accept(command)
      agent.step
      expect(@journal.state.fetch("commands").fetch("1")["state"]).to eq("execution_cancelled")
      expect(@journal.state.fetch("events").map { |event| event["kind"] }).not_to include("execution_started")
    end
  end
end
