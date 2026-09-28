require "rails_helper"

RSpec.describe AppPackageExport, type: :model do
  let(:notebook) { create(:notebook) }
  let(:app) { notebook.app }
  let(:history) { History.new(notebook) }

  def add(type, source, configuration = {})
    history.add_cell(cell_type: type, source:, configuration:, expected_notebook_revision: notebook.reload.head_revision_id)
  end

  def export(mode: "full")
    bytes = described_class.call(app: app.reload, mode:)
    files = Rubellum::PackageArchive.new.read(StringIO.new(bytes))
    [Rubellum::PackageManifest.load(files), files]
  end

  it "exports full immutable history, removed cells, readable sources and verified assets" do
    asset = create(:asset, app:, bytes: "original")
    cell = add("markdown", "![file](asset://#{asset.id})")
    original = cell.head_revision
    history.save_cell(cell_id: cell.id, expected_revision: original.id, source: "new", title: "Changed", cell_type: "markdown")
    history.restore_cell(cell_id: cell.id, revision_id: original.id, expected_revision: cell.reload.head_revision_id)
    history.remove_cell(cell_id: cell.id, expected_notebook_revision: notebook.reload.head_revision_id)
    manifest, files = export
    exported = manifest["cells"].sole
    expect(exported["id"]).to eq(cell.portable_id)
    expect(exported["revisions"].size).to eq(3)
    expect(exported["revisions"].last["provenance"]).to eq("restored_from" => original.id)
    expect(files.fetch(exported["source_path"])).to eq("![file](asset://#{asset.portable_id})")
    expect(files.fetch("assets/#{asset.sha256}")).to eq("original")
    expect(manifest["notebooks"].sole["revisions"].last["entries"]).to be_empty
    expect(manifest["assets"].sole.keys).not_to include("execution_id", "runner_event_id")
    expect(manifest["app"]["id"]).to eq(app.portable_id)
  end

  it "maps renderer and notebook references to portable identities without running code" do
    producer = add("ruby", "raise 'import must not run code'")
    renderer = add("d3", "throw new Error('must not render')", { "input" => { "cell_id" => producer.id, "output" => "rows" } })
    manifest, = export
    chart = manifest["cells"].find { |cell| cell["id"] == renderer.portable_id }
    expect(chart["revisions"].sole.dig("configuration", "input", "cell_id")).to eq(producer.portable_id)
    entries = manifest["notebooks"].sole["revisions"].last["entries"]
    expect(entries.map { |entry| entry["cell_id"] }).to eq([producer.portable_id, renderer.portable_id])
    expect(Execution.count).to eq(0)
    expect(NotebookSession.count).to eq(0)
  end

  it "exports current state without removed cell sources or revision ancestry" do
    removed = add("ruby", "private previous content")
    history.remove_cell(cell_id: removed.id, expected_notebook_revision: notebook.reload.head_revision_id)
    add("markdown", "Visible λ")
    manifest, files = export(mode: "current")
    expect(manifest["cells"].size).to eq(1)
    expect(files.values.join).not_to include("private previous content")
    ([manifest["app"]] + manifest["notebooks"] + manifest["cells"]).each do |owner|
      expect(owner["revisions"].size).to eq(1)
      expect(owner["revisions"].sole["parent_id"]).to be_nil
    end
  end

  it "refuses invalid renderer references" do
    add("d3", "", { "input" => { "cell_id" => SecureRandom.uuid } })
    expect { export }.to raise_error(Rubellum::PackageManifest::Invalid, /reference/)
  end
end
