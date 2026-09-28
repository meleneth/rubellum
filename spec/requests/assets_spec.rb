require "rails_helper"
require "base64"

RSpec.describe "App asset HTTP", type: :request do
  let(:project) { create(:app) }
  let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII=") }

  it "uploads a file through the public route and shows its immutable Markdown reference" do
    Tempfile.create(["upload", ".txt"]) do |file|
      file.write("uploaded notes"); file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "text/plain", original_filename: "notes.txt")
      post app_assets_path(project), params: { file: upload, expected_revision: project.head_revision_id }
      expect(response).to have_http_status(:see_other)
    end
    asset = project.assets.sole
    follow_redirect!
    expect(response.body).to include("asset://#{asset.id}", "notes.txt")
    get app_asset_path(project, asset)
    expect(response.body).to eq("uploaded notes")
    expect(response.headers["Content-Disposition"]).to start_with("attachment")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  it "renders app-local Markdown images from immutable asset identities" do
    asset = AssetStorage.upload(app: project, io: StringIO.new(png), filename: "plot.png", expected_revision: project.head_revision_id)
    notebook = create(:notebook, app: project)
    History.new(notebook).add_cell(cell_type: "markdown", source: "![Plot](asset://#{asset.id})", expected_notebook_revision: notebook.head_revision_id)
    get app_notebook_path(project, notebook)
    expect(Nokogiri::HTML5(response.body).at_css(".prose img")["src"]).to eq(app_asset_path(project, asset))
    get app_asset_path(project, asset)
    expect(response.body.b).to eq(png)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Content-Disposition"]).to start_with("inline")
  end

  it "serves active content as a sandboxed download, never a same-origin document" do
    asset = AssetStorage.upload(app: project, io: StringIO.new('<html><script>alert(1)</script></html>'), filename: "pretend.png", expected_revision: project.head_revision_id)
    get app_asset_path(project, asset)
    expect(response.headers["Content-Disposition"]).to start_with("attachment")
    expect(response.headers["Content-Security-Policy"]).to include("sandbox", "default-src 'none'")
  end

  it "does not expose asset content through another app" do
    asset = create(:asset)
    get app_asset_path(project, asset)
    expect(response).to have_http_status(:not_found)
  end

  it "reports corruption rather than serving bytes that no longer match the recorded identity" do
    asset = create(:asset, app: project)
    path = File.join(ENV.fetch("RUBELLUM_DATA"), "apps", project.id, "blobs", asset.sha256)
    File.chmod(0o600, path)
    File.binwrite(path, "corrupted")
    get app_asset_path(project, asset)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("does not match")
  end
end
