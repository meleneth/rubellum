require "rails_helper"

RSpec.describe ExecutionUpdates, type: :model do
  it "broadcasts only output and status replacements to the owning notebook" do
    notebook = create(:notebook)
    cell = History.new(notebook).add_cell(cell_type: "ruby", source: "42", expected_notebook_revision: notebook.head_revision_id)
    execution = ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: cell.head_revision_id)
    other = create(:notebook)
    broadcaster = class_double(Turbo::StreamsChannel).as_stubbed_const
    expect(broadcaster).to receive(:broadcast_replace_to).with(notebook, target: "notebook-status-#{notebook.id}", partial: "notebooks/status", locals: { notebook: })
    expect(broadcaster).to receive(:broadcast_replace_to).with(notebook, target: "cell-output-#{cell.id}", partial: "cells/output", locals: { cell: })
    expect(broadcaster).not_to receive(:broadcast_replace_to).with(other, any_args)
    described_class.broadcast(execution.notebook_session)
  end
end
