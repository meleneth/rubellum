require "rails_helper"

RSpec.describe "Notebook authoring", type: :request do
  let(:notebook) { create(:notebook) }
  let(:project) { notebook.app }

  def add_cell(type = "ruby", source: CellTemplates.source(type))
    History.new(notebook).add_cell(cell_type: type, source:, expected_notebook_revision: notebook.reload.head_revision_id)
  end

  it "creates an independent app with a welcome notebook" do
    post apps_path, params: { title: "Experiments" }
    expect(response).to have_http_status(:see_other)
    created = App.order(created_at: :desc).first
    expect(created.title).to eq("Experiments")
    expect(created.notebooks.first.title).to eq("Welcome")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Experiments", "Session not started")
  end

  it "renders each of the six cell types through Haml with inert JavaScript" do
    CellRevision::TYPES.each { |type| add_cell(type) }
    get app_notebook_path(project, notebook)
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML5(response.body)
    expect(document.css("article.cell").size).to eq(6)
    expect(document.css("iframe").first["sandbox"]).to eq("allow-scripts")
    expect(document.css("iframe").first["src"]).to be_nil
    expect(document.css("textarea[data-editor-target=source]").size).to eq(6)
    expect(document.css("[data-controller=parameters] input[type=range]").size).to eq(1)
    expect(document.css("[data-controller=table]").size).to eq(1)
  end

  it "escapes source and metadata instead of treating notebook content as template HTML" do
    cell = add_cell(source: '</textarea><script>alert("source")</script>')
    History.new(notebook).save_cell(cell_id: cell.id, expected_revision: cell.head_revision_id,
      source: cell.head_revision.source, title: '<img src=x onerror="alert(1)">', cell_type: "ruby")
    get app_notebook_path(project, notebook)
    document = Nokogiri::HTML5(response.body)
    expect(document.css("textarea[data-editor-target=source]").first.text).to eq(cell.head_revision.source)
    expect(document.css("article.cell script, article.cell img")).to be_empty
    expect(document.css("article.cell strong").first.text).to include("<img")
  end

  it "keeps drafts separate, rejects stale saves, and leaves the losing draft recoverable" do
    cell = add_cell
    editor_id = SecureRandom.uuid
    old = cell.head_revision_id
    draft = { editor_id:, expected_revision: old, source: "my draft", title: "", cell_type: "ruby", configuration: "{}" }
    put draft_app_notebook_cell_path(project, notebook, cell), params: draft
    expect(response).to have_http_status(:ok)
    expect(cell.revisions.count).to eq(1)
    History.new(notebook).save_cell(cell_id: cell.id, expected_revision: old, source: "other tab", title: "", cell_type: "ruby")
    patch app_notebook_cell_path(project, notebook, cell), params: draft
    expect(response).to have_http_status(:conflict)
    get draft_app_notebook_cell_path(project, notebook, cell), params: { editor_id: }
    expect(response.parsed_body.fetch("source")).to eq("my draft")
    expect(cell.reload.head_revision.source).to eq("other tab")
    get draft_app_notebook_cell_path(project, notebook, cell), params: { editor_id: SecureRandom.uuid }
    expect(response.parsed_body).to eq({})
  end

  it "commits Save and run atomically against the exact new revision" do
    cell = add_cell
    post_params = { expected_revision: cell.head_revision_id, source: "42", title: "Answer", cell_type: "ruby", intent: "run", configuration: "{}" }
    patch app_notebook_cell_path(project, notebook, cell), params: post_params
    expect(response).to have_http_status(:see_other)
    execution = Execution.last
    expect(execution.cell_revision_id).to eq(cell.reload.head_revision_id)
    expect(execution.cell_revision.source).to eq("42")
    expect(OutboxMessage.where("envelope ->> 'kind' = 'execute'").last.envelope.dig("payload", "source")).to eq("42")
  end

  it "does not let app switching expose another app's cells or drafts" do
    cell = add_cell
    other = create(:notebook)
    get draft_app_notebook_cell_path(other.app, other, cell), params: { editor_id: SecureRandom.uuid }
    expect(response).to have_http_status(:not_found)
    get app_notebook_path(other.app, notebook)
    expect(response).to have_http_status(:not_found)
  end

  it "shows both histories and keeps historical renderer previews inert" do
    cell = add_cell("d3")
    old = notebook.reload.head_revision_id
    add_cell("markdown")
    get history_app_notebook_path(project, notebook)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Historical preview", "Restore as new revision")
    get history_app_notebook_cell_path(project, notebook, cell)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Selected revision", "Current revision")
    get app_notebook_path(project, notebook, revision: old)
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("iframe, [data-controller=editor]")).to be_empty
  end

  it "updates typed parameter values without enqueuing Ruby" do
    cell = add_cell("parameters")
    expect { patch parameters_app_notebook_cell_path(project, notebook, cell), params: { values: { scale: "2.5" } } }
      .not_to change(OutboxMessage, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("inputs" => { "scale" => 2.5 })
    patch parameters_app_notebook_cell_path(project, notebook, cell), params: { values: { scale: "99" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(ParameterValue.find_by!(cell:).values).to eq("scale" => 2.5)
  end

  it "renders the local iframe bootstrap without the application shell" do
    get "/renderer"
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css("#chart").size).to eq(1)
    expect(document.css("script[src]").first["src"]).to match(%r{\A/assets/renderer})
    expect(document.css(".topbar")).to be_empty
  end
end
