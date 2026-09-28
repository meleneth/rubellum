require "rails_helper"

RSpec.describe CellFiles, type: :model do
  let(:notebook) { create(:notebook) }

  def import(source, format: "markdown", expected: notebook.reload.head_revision_id)
    described_class.import(notebook:, io: StringIO.new(source), filename: "source.#{format}", format:, expected_revision: expected)
  end

  it "preserves Markdown source and original bytes without executing embedded code" do
    source = "# λ notebook\n\n```ruby\nraise 'must not run'\n```\n"
    cell = import(source)
    expect(cell.head_revision.source).to eq(source)
    asset = Asset.find(cell.head_revision.configuration.fetch("asset_ids").sole)
    expect(AssetStorage.for_app(notebook.app).read(asset.reference)).to eq(source.b)
    expect(Execution.count).to eq(0)
  end

  it "validates JSON/CSV before installation and records CSV parsing choices" do
    expect { import("not JSON", format: "json") }.to raise_error(JSON::ParserError)
    expect { import("a,a\n1,2", format: "csv") }.to raise_error(ArgumentError)
    expect(Asset.count).to eq(0)
    cell = import("name,value\nA,001\n", format: "csv")
    expect(cell.head_revision.cell_type).to eq("data")
    expect(cell.head_revision.configuration.fetch("format")).to eq("csv")
    expect(cell.head_revision.configuration).to include("delimiter" => ",", "headers" => true, "skip_blanks" => true)
    expect(NotebookData.new(notebook).datasets.fetch(cell.id)).to eq([{ "name" => "A", "value" => "001" }])
  end

  it "rejects unsupported formats, oversized files and invalid encoding" do
    expect { import("42", format: "ruby") }.to raise_error(ArgumentError, /format/)
    expect { import("x" * (described_class::MAX_SOURCE_BYTES + 1)) }.to raise_error(ArgumentError, /1 MiB/)
    expect { import("\xff".b) }.to raise_error(ArgumentError, /UTF-8/)
    expect(notebook.cells.count).to eq(0)
  end

  it "rejects a stale document without creating an asset or partial revision" do
    original = notebook.head_revision_id
    import("# first")
    expect { import("# stale", expected: original) }.to raise_error(History::Conflict)
    expect(notebook.cells.count).to eq(1)
    expect(notebook.app.assets.count).to eq(1)
  end
end
