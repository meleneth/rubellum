require "rails_helper"

RSpec.describe "Restart and run all", type: :model do
  let(:notebook) { create(:notebook) }

  def add(type, source = CellTemplates.source(type))
    History.new(notebook).add_cell(cell_type: type, source:, expected_notebook_revision: notebook.reload.head_revision_id)
  end

  it "reserves one immutable ordered batch in the next generation and continues after its reserved sequences" do
    first = add("ruby", "value = 21")
    add("markdown")
    second = add("ruby", "value * 2")
    add("parameters")
    old = RunAll.call(notebook)
    session = old.first.notebook_session
    executions = ExecutionRequests.restart_all(notebook)
    snapshot = notebook.head_revision_id
    expect(executions.map(&:cell_revision_id)).to eq([first.head_revision_id, second.head_revision_id])
    expect(executions.map(&:generation)).to eq([2, 2])
    expect(executions.map(&:sequence)).to eq([1, 2])
    expect(executions.map(&:batch_id).uniq.size).to eq(1)
    expect(executions.first.batch_id).not_to eq(old.first.batch_id)
    expect(executions.map(&:inputs)).to eq([{ "scale" => 1.0 }] * 2)
    expect(executions.map(&:notebook_revision_id).uniq).to eq([snapshot])
    expect(session.reload.generation).to eq(1)
    expect(session.restart_generation).to eq(2)
    commands = OutboxMessage.where("envelope ->> 'kind' = 'execute' AND envelope ->> 'generation' = '2'")
    expect(commands.map(&:queue_name).uniq).to eq([Rubellum::QueueNames.session(session.id, 2)])
    expect(commands.map { |command| command.envelope.dig("payload", "batch_id") }.uniq).to eq([executions.first.batch_id])
    expect(OutboxMessage.where("envelope ->> 'kind' = 'start' AND envelope ->> 'generation' = '2'")).to be_empty

    History.new(notebook).save_cell(cell_id: first.id, expected_revision: first.head_revision_id,
      source: "value = 999", title: "Newer edit", cell_type: "ruby")
    expect(executions.first.reload.cell_revision.source).to eq("value = 21")
    ingestor = EventIngestor.new
    ready = build(:runner_message, **session.scope_fields.symbolize_keys, kind: "runner_ready", generation: 2, sequence: 1)
    2.times { ingestor.call(ready) }
    expect(session.reload.next_command_sequence).to eq(3)
    next_execution = ExecutionRequests.submit(notebook:, cell_id: second.id, expected_revision: second.head_revision_id)
    expect(next_execution).to have_attributes(generation: 2, sequence: 3)
    ingestor.call(build(:runner_message, **session.scope_fields.symbolize_keys, kind: "runner_stopped", generation: 1, sequence: 1))
    expect(old.map { |execution| execution.reload.status }).to eq(["cancelled", "cancelled"])
    expect(executions.map { |execution| execution.reload.status }).to eq(["queued", "queued"])
    expect(session.reload.status).to eq("ready")
  end

  it "uses the first clean generation when no context has ever existed" do
    add("ruby", "42")
    execution = ExecutionRequests.restart_all(notebook).first
    expect(execution).to have_attributes(generation: 1, sequence: 1)
    expect(OutboxMessage.pluck(:envelope).map { |message| message.fetch("kind") }).to contain_exactly("start", "execute")
  end

  it "does not allocate or reset a context without Ruby cells" do
    add("markdown")
    expect(ExecutionRequests.restart_all(notebook)).to eq([])
    expect(NotebookSession.count).to eq(0)
    expect(OutboxMessage.count).to eq(0)
  end

  it "rejects a second batch while reset is pending" do
    add("ruby", "42")
    RunAll.call(notebook)
    ExecutionRequests.restart_all(notebook)
    count = Execution.count
    expect { ExecutionRequests.restart_all(notebook) }.to raise_error(History::Conflict, /reset/)
    expect(Execution.count).to eq(count)
  end

  it "rolls back the reset and whole new batch if any payload is invalid" do
    add("ruby", "42")
    session = RunAll.call(notebook).first.notebook_session
    add("ruby", "x" * 70_000)
    stub_const("Rubellum::ExecutionPayload::MAX_BYTES", 1024)
    before = [Execution.count, OutboxMessage.count]
    expect { ExecutionRequests.restart_all(notebook) }.to raise_error(Rubellum::ExecutionPayload::Invalid)
    expect([Execution.count, OutboxMessage.count]).to eq(before)
    expect(session.reload).to have_attributes(generation: 1, restart_generation: nil, status: "requested")
  end
end
