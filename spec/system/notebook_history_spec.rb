require "rails_helper"
require_relative "../support/chrome"

RSpec.describe "Notebook metadata history in Chrome", type: :system do
  before { driven_by :rubellum_chrome }

  it "edits metadata and restores the original document title and content" do
    notebook = create(:notebook, notebook_title: "Original notebook")
    History.new(notebook).add_cell(cell_type: "markdown", source: "# Retained content", expected_notebook_revision: notebook.head_revision_id)
    original = notebook.reload.head_revision_id
    visit app_notebook_path(notebook.app, notebook)
    find("summary", text: "Notebook settings").click
    within("form[action='#{app_notebook_path(notebook.app, notebook)}']") do
      fill_in "Notebook title", with: "Revised notebook"
      fill_in "Notebook description", with: "A later description"
      fill_in "Notebook edit summary", with: "Clarify metadata"
      click_button "Save notebook revision"
    end
    expect(page).to have_css(".document-heading h1", text: "Revised notebook")
    expect(page).to have_content("A later description")
    expect(page).to have_css(".prose h1", text: "Retained content")
    within(".document-heading") { click_link "History" }
    expect(page).to have_content("Clarify metadata")
    within("#notebook-revision-#{original}") { click_button "Restore as new revision" }
    expect(page).to have_css(".document-heading h1", text: "Original notebook")
    expect(page).not_to have_content("A later description")
    expect(page).to have_css(".prose h1", text: "Retained content")
    expect(notebook.reload.head_revision.provenance).to eq("restored_from" => original)
    expect(Execution.count).to eq(0)
  end
end
