require "rails_helper"

RSpec.describe RunAll, type: :model do
  let(:notebook) { create(:notebook) }

  def add(type, source = CellTemplates.source(type))
    History.new(notebook).add_cell(cell_type: type, source:, expected_notebook_revision: notebook.reload.head_revision_id)
  end

  it "commits one ordered batch with an identical notebook and input snapshot" do
    first = add("ruby", "value = 21")
    add("markdown")
    second = add("ruby", "value * 2")
    add("parameters")
    executions = described_class.call(notebook)
    expect(executions.map(&:cell_revision_id)).to eq([first.head_revision_id, second.head_revision_id])
    expect(executions.map(&:sequence)).to eq([1, 2])
    expect(executions.map(&:batch_id).uniq.size).to eq(1)
    expect(executions.first.batch_id).not_to be_nil
    expect(executions.map(&:notebook_revision_id).uniq).to eq([notebook.head_revision_id])
    expect(executions.map(&:inputs)).to eq([{ "scale" => 1.0 }] * 2)
    messages = OutboxMessage.where("envelope ->> 'kind' = 'execute'")
    expect(messages.map { |message| message.envelope.dig("payload", "batch_id") }.uniq).to eq([executions.first.batch_id])
  end

  it "rolls back the whole batch if any cell cannot be queued" do
    stub_const("Rubellum::ExecutionPayload::MAX_BYTES", 1024)
    add("ruby", "42")
    add("ruby", "x" * 70_000)
    expect { described_class.call(notebook) }.to raise_error(Rubellum::ExecutionPayload::Invalid)
    expect(Execution.count).to eq(0)
    expect(OutboxMessage.count).to eq(0)
  end

  it "does not start a session for a notebook with no Ruby" do
    add("markdown")
    expect(described_class.call(notebook)).to eq([])
    expect(NotebookSession.count).to eq(0)
  end
end
