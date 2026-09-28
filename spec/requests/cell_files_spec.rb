require "rails_helper"

RSpec.describe "Cell source import/export", type: :request do
  it "imports Markdown through the public route and exports the exact selected historical source" do
    notebook = create(:notebook)
    source = "# Original λ\n\n```ruby\nputs 42\n```\n"
    Tempfile.create(["source", ".md"]) do |file|
      file.write(source); file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "text/markdown", original_filename: "Notes.md")
      post import_file_app_notebook_cells_path(notebook.app, notebook), params: {
        file: upload, format: "markdown", expected_revision: notebook.head_revision_id
      }
      expect(response).to have_http_status(:see_other)
    end
    cell = notebook.cells.sole
    old = cell.head_revision
    History.new(notebook).save_cell(cell_id: cell.id, expected_revision: old.id, source: "# Changed", title: "Changed", cell_type: "markdown")
    get export_app_notebook_cell_path(notebook.app, notebook, cell, revision: old.id)
    expect(response.body).to eq(source)
    expect(response.headers["Content-Disposition"]).to include("attachment", ".md")
    get export_app_notebook_cell_path(notebook.app, notebook, cell)
    expect(response.body).to eq("# Changed")
  end
end
