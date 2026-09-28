require "rails_helper"

RSpec.describe "Inert Markdown draft preview", type: :request do
  let(:notebook) { create(:notebook) }
  let(:cell) do
    History.new(notebook).add_cell(cell_type: "markdown", source: "# Saved", expected_notebook_revision: notebook.head_revision_id)
  end

  it "renders sanitized draft Markdown and local assets without persisting or executing it" do
    cell
    asset = create(:asset, app: notebook.app, filename: "image.png", mime_type: "image/png")
    counts = [CellRevision.count, NotebookRevision.count, Draft.count, Execution.count]
    post preview_app_notebook_cell_path(notebook.app, notebook, cell), params: {
      source: "# Draft λ\n\n![Image](asset://#{asset.id})\n\n<script>alert('bad')</script>\n\n```ruby\nraise 'do not run'\n```"
    }, as: :json
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML5(response.body)
    expect(document.at_css("h1").text).to eq("Draft λ")
    expect(document.css("script")).to be_empty
    expect(document.at_css("img")["src"]).to eq(app_asset_path(notebook.app, asset))
    expect(document.css(".highlight span")).not_to be_empty
    expect([CellRevision.count, NotebookRevision.count, Draft.count, Execution.count]).to eq(counts)
    expect(cell.reload.head_revision.source).to eq("# Saved")
  end

  it "previews empty Markdown but rejects invalid/oversized source and other cell types" do
    path = preview_app_notebook_cell_path(notebook.app, notebook, cell)
    post path, params: { source: "" }, as: :json
    expect(response).to have_http_status(:ok)
    [[], "\0", "λ" * 524_289].each do |source|
      post path, params: { source: }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
    ruby = History.new(notebook).add_cell(cell_type: "ruby", source: "42", expected_notebook_revision: notebook.reload.head_revision_id)
    post preview_app_notebook_cell_path(notebook.app, notebook, ruby), params: { source: "raise 'never run'" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Execution.count).to eq(0)
  end

  it "rejects cross-app cells and asset references" do
    other = create(:notebook)
    post preview_app_notebook_cell_path(other.app, other, cell), params: { source: "# Cross app" }
    expect(response).to have_http_status(:not_found)
    other_asset = create(:asset, app: other.app)
    post preview_app_notebook_cell_path(notebook.app, notebook, cell), params: { source: "![Bad](asset://#{other_asset.id})" }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
