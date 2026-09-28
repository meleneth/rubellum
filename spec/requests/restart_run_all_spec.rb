require "rails_helper"

RSpec.describe "Restart and run all controls", type: :request do
  let(:notebook) { create(:notebook) }
  let!(:cell) { History.new(notebook).add_cell(cell_type: "ruby", source: "42", expected_notebook_revision: notebook.head_revision_id) }

  it "queues a fresh batch and shows the pending state without changing committed content" do
    old = RunAll.call(notebook).first
    snapshot = notebook.head_revision_id
    post restart_all_app_notebook_path(notebook.app, notebook)
    expect(response).to have_http_status(:see_other)
    expect(Execution.order(:created_at).last).to have_attributes(generation: 2, notebook_revision_id: snapshot, cell_revision_id: cell.head_revision_id)
    follow_redirect!
    expect(response.body).to include("restarting · generation 1", "Restart and run all")
    post run_all_app_notebook_path(notebook.app, notebook)
    expect(response).to have_http_status(:conflict)
    post restart_all_app_notebook_path(notebook.app, notebook)
    expect(response).to have_http_status(:conflict)
    expect(old.reload.status).to eq("queued")
    expect(Execution.count).to eq(2)
    expect(notebook.reload.head_revision_id).to eq(snapshot)
  end

  it "rejects cross-app requests without creating sessions or messages" do
    other = create(:notebook)
    post restart_all_app_notebook_path(other.app, notebook)
    expect(response).to have_http_status(:not_found)
    expect(NotebookSession.count).to eq(0)
    expect(OutboxMessage.count).to eq(0)
  end

  it "offers execution controls only on the current document, not a historical preview" do
    snapshot = notebook.head_revision_id
    History.new(notebook).add_cell(cell_type: "markdown", source: "Later", expected_notebook_revision: snapshot)
    get app_notebook_path(notebook.app, notebook, revision: snapshot)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Restart and run all", "Run all saved Ruby")
  end
end
