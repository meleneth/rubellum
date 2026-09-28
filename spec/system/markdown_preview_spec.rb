require "rails_helper"
require_relative "../support/chrome"

RSpec.describe "Markdown authoring modes in Chrome", type: :system do
  before { driven_by :rubellum_chrome }

  it "previews drafts in split/preview modes while retaining the editor, undo and explicit-save semantics" do
    notebook = create(:notebook)
    cell = History.new(notebook).add_cell(cell_type: "markdown", source: "# Saved heading\n\n```ruby\nputs 42\n```", expected_notebook_revision: notebook.head_revision_id)
    visit app_notebook_path(notebook.app, notebook)
    within("#cell-#{cell.id}") do
      find("summary", text: "Edit source").click
      click_button "Split Markdown"
      expect(page).to have_css('.draft-preview h1', text: "Saved heading")
      expect(page).to have_css('.draft-preview .highlight span')
      editor = find(".cm-content")
      editor.click
      editor.send_keys([:control, "a"], "# Draft heading")
      expect(page).to have_css('.draft-preview h1', text: "Draft heading")
      expect(page).to have_css('.cell-content h1', text: "Saved heading")
      expect(cell.revisions.count).to eq(1)
      editor_node = page.evaluate_script("document.querySelector('#cell-#{cell.id} .cm-editor').dataset.testIdentity = 'retained'")
      click_button "Preview Markdown"
      expect(page).not_to have_css(".cm-editor", visible: true)
      expect(page).to have_css('.draft-preview h1', text: "Draft heading")
      click_button "Edit Markdown"
      expect(page).to have_css(".cm-editor[data-test-identity='#{editor_node}']")
      editor = find(".cm-content")
      editor.click
      editor.send_keys([:control, "z"])
      expect(page).to have_css(".cm-content", text: "Saved heading")
      editor.send_keys([:control, "a"], "# Committed heading")
      click_button "Save revision"
      expect(page).to have_css('.cell-content h1', text: "Committed heading")
    end
    expect(cell.reload.revisions.count).to eq(2)
    expect(cell.head_revision.source).to eq("# Committed heading")
    expect(Execution.count).to eq(0)
  end
end
