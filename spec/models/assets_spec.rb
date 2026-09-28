require "rails_helper"

RSpec.describe "Immutable app assets", type: :model do
  let(:project) { create(:app) }

  def upload(bytes, filename: "notes.txt")
    AssetStorage.upload(app: project, io: StringIO.new(bytes), filename:,
      expected_revision: project.reload.head_revision_id)
  end

  it "retains both versions when a filename is uploaded twice and versions the app asset list" do
    first = upload("original")
    previous = project.reload.head_revision
    second = upload("replacement")
    expect(first.id).not_to eq(second.id)
    expect(AssetStorage.for_app(project).read(first.reference)).to eq("original")
    expect(AssetStorage.for_app(project).read(second.reference)).to eq("replacement")
    expect(previous.configuration.fetch("asset_ids")).to eq([first.id])
    expect(project.head_revision.configuration.fetch("asset_ids")).to eq([first.id, second.id])
    expect(first.mime_type).to eq("text/plain")
  end

  it "refuses stale uploads and unsafe filenames before storing bytes" do
    original = project.head_revision_id
    upload("first")
    expect { AssetStorage.upload(app: project, io: StringIO.new("second"), filename: "x", expected_revision: original) }.to raise_error(History::Conflict)
    expect { upload("bad", filename: "../secret") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(project.assets.count).to eq(1)
  end

  it "enforces asset immutability through raw SQL updates and deletes" do
    asset = create(:asset, app: project)
    ["UPDATE assets SET filename = 'changed' WHERE id = '#{asset.id}'", "DELETE FROM assets WHERE id = '#{asset.id}'"].each do |sql|
      expect { ApplicationRecord.transaction(requires_new: true) { ApplicationRecord.connection.execute(sql) } }
        .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end
  end

  it "validates cross-app references in Ruby and in direct SQL revision inserts" do
    asset = create(:asset)
    notebook = create(:notebook, app: project)
    cell = History.new(notebook).add_cell(cell_type: "markdown", expected_notebook_revision: notebook.head_revision_id)
    expect { History.new(notebook).save_cell(cell_id: cell.id, expected_revision: cell.head_revision_id,
      cell_type: "markdown", title: "", source: "[secret](asset://#{asset.id})") }.to raise_error(ArgumentError, /cross-app/)
    attributes = cell.head_revision.attributes.except("id").merge("source" => "[secret](asset://#{asset.id})")
    expect { ApplicationRecord.transaction(requires_new: true) { CellRevision.insert_all!([attributes]) } }
      .to raise_error(ActiveRecord::StatementInvalid, /cross-app/)
  end

  it "keeps historical Markdown references tied to the original asset after replacement and restore" do
    first = upload("original")
    notebook = create(:notebook, app: project)
    history = History.new(notebook)
    cell = history.add_cell(cell_type: "markdown", source: "[notes](asset://#{first.id})", expected_notebook_revision: notebook.head_revision_id)
    old = cell.head_revision
    replacement = upload("replacement")
    newer = history.save_cell(cell_id: cell.id, expected_revision: old.id, cell_type: "markdown", title: "", source: "[notes](asset://#{replacement.id})")
    restored = history.restore_cell(cell_id: cell.id, revision_id: old.id, expected_revision: newer.id)
    expect(restored.source).to eq(old.source)
    expect(AssetStorage.for_app(project).read(first.reference)).to eq("original")
  end
end
