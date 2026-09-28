require "rails_helper"

RSpec.describe "Durable session reset", type: :model do
  let(:notebook) { create(:notebook) }
  let(:cell) { History.new(notebook).add_cell(cell_type: "ruby", source: "42", expected_notebook_revision: notebook.head_revision_id) }
  let(:execution) { ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: cell.head_revision_id) }
  let(:session) { execution.notebook_session }

  def fact(kind, generation:, sequence:)
    build(:runner_message, **session.scope_fields.symbolize_keys, kind:, generation:, sequence:)
  end

  it "records a pending reset without claiming that the manager has changed generation" do
    request = ExecutionRequests.reset(session)
    expect(session.reload.status).to eq("restarting")
    expect(session.generation).to eq(1)
    expect(session.restart_generation).to eq(2)
    expect(request.envelope).to include("kind" => "restart", "generation" => 1)
    expect { ExecutionRequests.reset(session) }.to raise_error(History::Conflict, /reset/)
    expect { ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: cell.head_revision_id) }
      .to raise_error(History::Conflict, /reset/)
    expect(Execution.count).to eq(1)
  end

  it "keeps the pending reset visible through old ready and stopped facts until replacement readiness" do
    request = ExecutionRequests.reset(session)
    ingestor = EventIngestor.new
    ingestor.call(fact("runner_ready", generation: 1, sequence: 1))
    expect(session.reload.status).to eq("restarting")
    ingestor.call(fact("runner_stopped", generation: 1, sequence: 2))
    expect(session.reload.status).to eq("restarting")
    expect(execution.reload.status).to eq("cancelled")
    expect(request.reload.confirmed_at).to be_nil
    ingestor.call(fact("runner_ready", generation: 2, sequence: 1))
    expect(session.reload).to have_attributes(status: "ready", generation: 2, restart_generation: nil, next_command_sequence: 1)
    expect(request.reload.confirmed_at).not_to be_nil
    next_execution = ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: cell.head_revision_id)
    expect(next_execution).to have_attributes(generation: 2, sequence: 1)
  end

  it "can request a reset from a lost context" do
    session.update!(status: "lost")
    expect { ExecutionRequests.reset(session) }.to change(OutboxMessage, :count).by(1)
    expect(session.reload.restart_generation).to eq(2)
  end
end
