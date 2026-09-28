require "rails_helper"

RSpec.describe "Notebook metadata", type: :request do
  let(:notebook) { create(:notebook) }

  it "saves a metadata revision and restores its historical title and description" do
    original = notebook.head_revision
    patch app_notebook_path(notebook.app, notebook), params: { expected_revision: original.id, title: "New title", description: "New notes", summary: "Rename" }
    expect(response).to have_http_status(:see_other)
    expect(notebook.reload.title).to eq("New title")
    get history_app_notebook_path(notebook.app, notebook)
    expect(response.body).to include("New title", "New notes", "Rename", original.title)
    get app_notebook_path(notebook.app, notebook, revision: original.id)
    expect(response.body).to include("Historical preview")
    expect(response.body).not_to include("Save notebook revision")
    post restore_app_notebook_path(notebook.app, notebook), params: { expected_revision: notebook.head_revision_id, revision_id: original.id }
    expect(response).to have_http_status(:see_other)
    expect(notebook.reload.title).to eq(original.title)
    expect(notebook.head_revision.description).to eq(original.description)
  end

  it "rejects stale and cross-app notebook metadata writes" do
    original = notebook.head_revision_id
    path = app_notebook_path(notebook.app, notebook)
    patch path, params: { expected_revision: original, title: "Saved", description: "Notes" }
    patch path, params: { expected_revision: original, title: "Stale" }
    expect(response).to have_http_status(:conflict)
    expect(notebook.reload.title).to eq("Saved")
    patch app_notebook_path(create(:app), notebook), params: { expected_revision: notebook.head_revision_id, title: "Wrong app" }
    expect(response).to have_http_status(:not_found)
    expect(notebook.reload.title).to eq("Saved")
  end
end
