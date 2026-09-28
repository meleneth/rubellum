require "rails_helper"
require "open3"
require_relative "../support/committed_database"

RSpec.describe "Package CLI", type: :model do
  include_context "committed database"

  it "exports, refuses overwrite/collision and explicitly imports another copy" do
    app = create(:app)
    command = Rails.root.join("bin/app-package").to_s
    Dir.mktmpdir("rubellum-cli-") do |directory|
      path = File.join(directory, "project.rubellum-app.tar.gz")
      output, error, status = Open3.capture3(command, "export", app.id, path)
      expect(status).to be_success, "#{output}\n#{error}"
      original = File.binread(path)
      expect(Rubellum::PackageManifest.load(Rubellum::PackageArchive.new.read(StringIO.new(original)))["app"]["id"]).to eq(app.portable_id)
      _, error, status = Open3.capture3(command, "export", app.id, path)
      expect(status).not_to be_success
      expect(error).to include("File exists")
      expect(File.binread(path)).to eq(original)
      _, error, status = Open3.capture3(command, "import", path)
      expect(status).not_to be_success
      expect(error).to include("Import as copy")
      output, error, status = Open3.capture3(command, "import", path, "--copy")
      expect(status).to be_success, "#{output}\n#{error}"
      expect(App.count).to eq(2)
      expect(output).to include("Installed")
      expect(NotebookSession.count).to eq(0)
    end
  end
end
