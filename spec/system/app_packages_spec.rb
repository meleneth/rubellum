require "rails_helper"
require_relative "../support/chrome"
require_relative "../support/committed_database"

RSpec.describe "Portable app journeys in Chrome", type: :system do
  include_context "committed database"
  before { driven_by :rubellum_chrome }

  it "cancels a collision, explicitly imports a copy and leaves executable cells inert" do
    notebook = create(:notebook, notebook_title: "Portable notebook")
    history = History.new(notebook)
    history.add_cell(cell_type: "markdown", source: "# Portable content", expected_notebook_revision: notebook.head_revision_id)
    history.add_cell(cell_type: "ruby", source: "raise 'must not run during import'", expected_notebook_revision: notebook.reload.head_revision_id)
    history.add_cell(cell_type: "d3", source: "throw new Error('must not render during import')", expected_notebook_revision: notebook.reload.head_revision_id)
    Tempfile.create(["project-", ".rubellum-app.tar.gz"], binmode: true) do |file|
      file.write(AppPackageExport.call(app: notebook.app))
      file.flush
      visit root_path
      click_link "Import an app package"
      attach_file "App package (.rubellum-app.tar.gz)", file.path
      click_button "Import app"
      expect(page).to have_content("This app is already installed")
      expect(App.count).to eq(1)
      attach_file "App package (.rubellum-app.tar.gz)", file.path
      select "Import as copy — create an independent installation", from: "If this app is already installed"
      click_button "Import app"
      expect(page).to have_css(".prose h1", text: "Portable content")
      expect(App.count).to eq(2)
      expect(page).to have_content("Session not started")
      expect(page).to have_button("Render chart")
      expect(page).not_to have_css("iframe[src]")
      expect(Execution.count).to eq(0)
      expect(NotebookSession.count).to eq(0)
      expect(App.pluck(:portable_id).uniq).to eq([notebook.app.portable_id])
    end
  end
end
