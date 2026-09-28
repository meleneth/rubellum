require "rails_helper"

RSpec.describe "Durable execution transport", type: :model do
  let(:notebook) { create(:notebook) }
  let(:cell) { History.new(notebook).add_cell(cell_type: "ruby", source: "21 * 2", expected_notebook_revision: notebook.head_revision_id) }
  let(:execution) { ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: cell.head_revision_id, inputs: { "scale" => 2 }) }
  let(:session) { execution.notebook_session }
  let(:ingestor) { EventIngestor.new }

  def event(kind, sequence:, payload: {})
    message = OutboxMessage.where("envelope ->> 'execution_id' = ?", execution.id).first
    build(:runner_message, **session.scope_fields.symbolize_keys, kind:, sequence:, execution_id: execution.id,
      command_id: message.id, payload:)
  end

  it "commits the execution and source-specific outgoing envelope together" do
    expect(execution.status).to eq("queued")
    expect(execution.cell_revision_id).to eq(cell.head_revision_id)
    expect(execution.notebook_revision_id).to eq(notebook.head_revision_id)
    expect(execution.inputs).to eq("scale" => 2)
    message = OutboxMessage.find_by!("envelope ->> 'kind' = 'execute'")
    expect(message.envelope.dig("payload", "source")).to eq("21 * 2")
    expect(message.envelope.dig("payload", "cell_revision_id")).to eq(cell.head_revision_id)
  end

  it "does not enqueue a stale editor's source" do
    cell
    expect { ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: SecureRandom.uuid) }.to raise_error(History::Conflict)
    expect(Execution.count).to eq(0)
    expect(OutboxMessage.count).to eq(0)
  end

  it "stores larger command payloads by immutable digest without expanding the SQS envelope" do
    large = History.new(notebook).add_cell(cell_type: "ruby", source: "x" * 70_000, expected_notebook_revision: notebook.head_revision_id)
    ExecutionRequests.submit(notebook:, cell_id: large.id, expected_revision: large.head_revision_id)
    message = OutboxMessage.find_by!("envelope ->> 'kind' = 'execute'").envelope
    expect(JSON.generate(message).bytesize).to be < 2048
    payload = Rubellum::ExecutionPayload.unpack(message["payload"], store: AssetStorage.for_app(notebook.app))
    expect(payload["source"]).to eq("x" * 70_000)
  end

  it "persists reordered events but advances status and acknowledgments only through contiguous sequences" do
    done = event("execution_completed", sequence: 4, payload: { "inspection" => "42" })
    ingestor.call(done)
    expect(execution.reload.status).to eq("queued")
    expect(EventCursor.first.through_sequence).to eq(0)
    expect(OutboxMessage.where("envelope ->> 'kind' = 'acknowledge'").count).to eq(0)
    ready = event("runner_ready", sequence: 1)
    accepted = event("execution_accepted", sequence: 2)
    started = event("execution_started", sequence: 3)
    [ready, accepted, started, done].each { |message| ingestor.call(message) }
    expect(execution.reload.status).to eq("completed")
    expect(execution.result).to eq("inspection" => "42")
    expect(RunnerEvent.count).to eq(4)
    expect(EventCursor.first.through_sequence).to eq(4)
    expect(OutboxMessage.where("envelope ->> 'kind' = 'execute'").first.confirmed_at).not_to be_nil
  end

  it "keeps late old-generation facts historical without overwriting the replacement session" do
    started = event("execution_started", sequence: 1)
    session.update!(generation: 2, status: "ready")
    ingestor.call(started)
    expect(execution.reload.status).to eq("running")
    expect(session.reload.generation).to eq(2)
    expect(session.status).to eq("ready")
  end

  it "rejects a fact scoped to the wrong app before persisting it" do
    message = event("execution_started", sequence: 1)
    forged = Rubellum::Message.new(message.to_h.merge("app_installation_id" => SecureRandom.uuid))
    expect { ingestor.call(forged) }.to raise_error(EventIngestor::Invalid, /scope/)
    expect(RunnerEvent.count).to eq(0)
  end

  it "keeps the durable outbox outstanding after sending until runner acceptance is committed" do
    execution
    transport = instance_double(Rubellum::SqsTransport)
    expect(transport).to receive(:ensure_queue).twice.and_return("local-queue")
    expect(transport).to receive(:publish).twice
    OutboxDispatcher.new(transport:).call
    expect(OutboxMessage.where(sent_at: nil).count).to eq(0)
    expect(OutboxMessage.where(confirmed_at: nil).count).to eq(2)
  end

  it "prevents relabeling a recorded execution with different input values through SQL" do
    execution
    expect { ApplicationRecord.transaction(requires_new: true) { execution.update_columns(inputs: { "scale" => 99 }) } }
      .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it "requires the actual cell revision to belong to the recorded notebook snapshot" do
    execution
    other = create(:notebook)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        session.executions.create!(cell_revision: cell.head_revision, notebook_revision: other.head_revision,
          generation: 1, sequence: 2, environment_digest: "builtin")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /provenance/)
  end
end
