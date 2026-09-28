require "rails_helper"

RSpec.describe History, type: :model do
  let(:notebook) { create(:notebook) }
  let(:history) { described_class.new(notebook) }

  def add(source = "1 + 1")
    history.add_cell(cell_type: "ruby", source:, expected_notebook_revision: notebook.reload.head_revision_id)
  end

  def save(cell, source, expected: cell.reload.head_revision_id)
    history.save_cell(cell_id: cell.id, expected_revision: expected, source:, title: "Example", cell_type: "ruby")
  end

  it "creates app metadata and document histories with stable separate portable identities" do
    app = described_class.create_app(title: "Research")
    page = described_class.create_notebook(app:, title: "Measurements")
    expect(app.title).to eq("Research")
    expect(app.id).not_to eq(app.portable_id)
    expect(page.head_revision.entries).to eq([])
    expect(page.revisions.count).to eq(1)
  end

  it "commits cell content and an ordered document snapshot together" do
    cell = add
    expect(notebook.reload.head_revision.entries).to eq([{ "cell_id" => cell.id, "revision_id" => cell.head_revision_id }])
    expect(cell.head_revision.content_digest).to match(/\A[0-9a-f]{64}\z/)
  end

  it "keeps old content and structure reconstructable after edits" do
    cell = add("old")
    historical = notebook.reload.head_revision
    original = cell.head_revision
    updated = save(cell, "new")
    expect(updated.parent_id).to eq(original.id)
    expect(historical.ordered_revisions.map(&:source)).to eq(["old"])
    expect(notebook.reload.head_revision.ordered_revisions.map(&:source)).to eq(["new"])
  end

  it "rejects a stale editor without losing its recoverable draft" do
    cell = add
    base = cell.head_revision_id
    draft = cell.drafts.create!(editor_id: SecureRandom.uuid, base_revision_id: base, source: "my changes", cell_type: "ruby")
    save(cell, "other tab")
    expect { save(cell, "my changes", expected: base) }.to raise_error(History::Conflict)
    expect(draft.reload.source).to eq("my changes")
    expect(cell.reload.head_revision.source).to eq("other tab")
  end

  it "rolls back both heads on invalid content" do
    cell = add
    cell_head, notebook_head = cell.head_revision_id, notebook.head_revision_id
    expect { history.save_cell(cell_id: cell.id, expected_revision: cell_head, source: "bad", title: "", cell_type: "shell") }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(cell.reload.head_revision_id).to eq(cell_head)
    expect(notebook.reload.head_revision_id).to eq(notebook_head)
  end

  it "restores old cell content by appending, retaining intervening history" do
    cell = add("first")
    original = cell.head_revision
    second = save(cell, "second")
    restored = history.restore_cell(cell_id: cell.id, revision_id: original.id, expected_revision: second.id)
    expect(restored.id).not_to eq(original.id)
    expect(restored.parent_id).to eq(second.id)
    expect(restored.source).to eq("first")
    expect(restored.provenance).to eq("restored_from" => original.id)
    expect(cell.revisions.count).to eq(3)
  end

  it "reorders and removes cells without deleting retained history" do
    a, b = add("a"), add("b")
    original = notebook.reload.head_revision
    history.reorder(cell_ids: [b.id, a.id], expected_notebook_revision: original.id)
    expect(notebook.head_revision.ordered_revisions.map(&:source)).to eq(%w[b a])
    history.remove_cell(cell_id: a.id, expected_notebook_revision: notebook.head_revision_id)
    expect(notebook.head_revision.ordered_revisions.map(&:source)).to eq(["b"])
    expect(original.ordered_revisions.map(&:source)).to eq(%w[a b])
    expect(Cell.exists?(a.id)).to be(true)
  end

  it "restores a removed cell and old content as new revisions" do
    cell = add("first")
    original = notebook.reload.head_revision
    second = save(cell, "second")
    history.remove_cell(cell_id: cell.id, expected_notebook_revision: notebook.head_revision_id)
    history.restore_notebook(revision_id: original.id, expected_notebook_revision: notebook.head_revision_id)
    expect(notebook.head_revision.ordered_revisions.map(&:source)).to eq(["first"])
    expect(cell.reload.head_revision.parent_id).to eq(second.id)
    expect(cell.head_revision.id).not_to eq(original.entries.first.fetch("revision_id"))
  end

  it "refuses stale structural edits" do
    original = notebook.head_revision_id
    cell = add
    expect { history.remove_cell(cell_id: cell.id, expected_notebook_revision: original) }.to raise_error(History::Conflict)
  end

  it "restores notebook metadata as well as cells without rewinding either history" do
    cell = add("first")
    original = notebook.revisions.create!(parent_id: notebook.head_revision_id,
      title: "Original title", description: "Original description", configuration: { "layout" => "wide" },
      entries: notebook.head_revision.entries)
    notebook.update!(head_revision: original)
    later = notebook.revisions.create!(parent_id: original.id, title: "New title", description: "New description",
      configuration: { "layout" => "compact" }, entries: original.entries)
    notebook.update!(head_revision: later)

    restored = history.restore_notebook(revision_id: original.id, expected_notebook_revision: later.id)
    expect(restored.attributes.slice("title", "description", "configuration"))
      .to eq(original.attributes.slice("title", "description", "configuration"))
    expect(restored.parent_id).to eq(later.id)
    expect(restored.id).not_to eq(original.id)
    expect(restored.provenance).to eq("restored_from" => original.id)
    expect(cell.reload.head_revision.provenance).to include("notebook_revision" => original.id)
    expect(later.reload.title).to eq("New title")
  end

  it "rejects missing or duplicated reorder identities" do
    a, b = add, add
    expect { history.reorder(cell_ids: [a.id, a.id], expected_notebook_revision: notebook.head_revision_id) }.to raise_error(ArgumentError)
    expect(notebook.head_revision.entries.map { |entry| entry["cell_id"] }).to eq([a.id, b.id])
  end

  it "does not save a cell through a different notebook" do
    cell = add
    other = described_class.new(create(:notebook))
    expect { other.save_cell(cell_id: cell.id, expected_revision: cell.head_revision_id, source: "bad", title: "", cell_type: "ruby") }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it "records a type change without rewriting the old type" do
    cell = add
    old = cell.head_revision
    history.save_cell(cell_id: cell.id, expected_revision: old.id, source: "# Heading", title: "", cell_type: "markdown")
    expect(cell.reload.head_revision.cell_type).to eq("markdown")
    expect(old.reload.cell_type).to eq("ruby")
  end

  it "enforces revision immutability even through SQL updates and deletes" do
    cell = add
    [cell.head_revision, notebook.head_revision, notebook.app.head_revision].each do |revision|
      ["UPDATE #{revision.class.table_name} SET summary = 'rewritten' WHERE id = '#{revision.id}'",
       "DELETE FROM #{revision.class.table_name} WHERE id = '#{revision.id}'"].each do |sql|
        expect { ApplicationRecord.transaction(requires_new: true) { ApplicationRecord.connection.execute(sql) } }
          .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
      end
    end
  end

  it "enforces cell-head ownership in PostgreSQL" do
    a, b = add, add
    expect { ApplicationRecord.transaction(requires_new: true) { a.update_columns(head_revision_id: b.head_revision_id) } }
      .to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "rejects cross-notebook snapshot references at the storage boundary" do
    cell = add
    other = create(:notebook)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        other.revisions.create!(title: "invalid", entries: [{ "cell_id" => cell.id, "revision_id" => cell.head_revision_id }])
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /invalid or duplicate/)
  end

  it "prevents moving a retained cell to another notebook through SQL" do
    cell = add
    other = create(:notebook)
    expect { ApplicationRecord.transaction(requires_new: true) { cell.update_columns(notebook_id: other.id) } }
      .to raise_error(ActiveRecord::StatementInvalid, /ownership are immutable/)
  end
end
