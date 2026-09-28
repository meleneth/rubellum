require "rails_helper"
require_relative "../support/committed_database"

RSpec.describe "Portable app controls", type: :request do
  include_context "committed database"
  include Rails.application.routes.url_helpers
  let(:notebook) { create(:notebook) }
  let(:project) { notebook.app }

  def uploaded(bytes)
    tempfile = Tempfile.new(["rubellum-package-", ".tar.gz"], binmode: true)
    tempfile.write(bytes)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile, "application/gzip", true)
  end

  it "downloads a validated full or current package from the app library" do
    project
    get root_path
    expect(response.body).to include("Import an app package", "Export full history", "Export current state only", "Duplicate app")
    %w[full current].each do |mode|
      get export_app_path(project, mode:)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/gzip")
      files = Rubellum::PackageArchive.new.read(StringIO.new(response.body))
      expect(Rubellum::PackageManifest.load(files)["mode"]).to eq(mode)
    end
    get export_app_path(project, mode: "merge")
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "offers explicit copy or cancel on collision and installs without executing code" do
    History.new(notebook).add_cell(cell_type: "ruby", source: "raise 'do not run'", expected_notebook_revision: notebook.head_revision_id)
    bytes = AppPackageExport.call(app: project)
    get import_apps_path
    expect(response.body).to include("Cancel — keep the existing app unchanged", "Import as copy")
    post import_apps_path, params: { package: uploaded(bytes) }
    expect(response).to have_http_status(:conflict)
    expect(response.body).to include("already installed", "Select the file again")
    expect(App.count).to eq(1)
    post import_apps_path, params: { package: uploaded(bytes), as_copy: "true" }
    expect(response).to have_http_status(:see_other)
    expect(App.count).to eq(2)
    copy = App.where.not(id: project.id).sole
    expect(response).to redirect_to(app_path(copy))
    expect(copy.notebooks.sole.cells.sole.head_revision.source).to eq("raise 'do not run'")
    expect(Execution.count).to eq(0)
    expect(NotebookSession.count).to eq(0)
  end

  it "duplicates through the same complete serialization path" do
    post duplicate_app_path(project)
    expect(response).to have_http_status(:see_other)
    expect(App.count).to eq(2)
    expect(App.pluck(:portable_id).uniq).to eq([project.portable_id])
    expect(App.pluck(:id).uniq.size).to eq(2)
  end

  it "rejects malformed or non-file uploads without exposing any app" do
    post import_apps_path, params: { package: uploaded("not an archive") }
    expect(response).to have_http_status(:unprocessable_content)
    post import_apps_path, params: { package: "not a file" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(App.count).to eq(0)
  end
end
