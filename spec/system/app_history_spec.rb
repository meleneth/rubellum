require "rails_helper"
require_relative "../support/chrome"

RSpec.describe "App history in Chrome", type: :system do
  before { driven_by :rubellum_chrome }

  it "renames, compares and restores app metadata without changing archive state" do
    project = create(:app, app_title: "Original research")
    original = project.head_revision_id
    visit root_path
    find("summary", text: "App settings").click
    fill_in "App title", with: "Revised research"
    fill_in "Description", with: "A later description"
    select "Archived", from: "Archive state"
    click_button "Save app revision"
    expect(page).to have_content("Revised research")
    expect(page).to have_css(".eyebrow", text: /archived/i)
    find("summary", text: "App settings").click
    click_link "App history"
    find("a[href='#{history_app_path(project, revision: original)}']").click
    expect(page).to have_css('tr[data-changed="true"]', count: 2)
    click_button "Restore selected metadata as new revision"
    expect(page).to have_content("Restore earlier app metadata")
    expect(project.reload.title).to eq("Original research")
    expect(project.archived_at).not_to be_nil
    expect(project.revisions.count).to eq(3)
    expect(NotebookSession.count).to eq(0)
  end
end
