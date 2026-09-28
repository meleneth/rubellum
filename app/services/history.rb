class History
  class Conflict < StandardError; end

  def self.create_app(title:, description: "")
    App.transaction do
      app = App.create!
      app.update!(head_revision: app.revisions.create!(title:, description:))
      app
    end
  end

  def self.create_notebook(app:, title:)
    app.with_lock do
      notebook = app.notebooks.create!
      notebook.update!(head_revision: notebook.revisions.create!(title:))
      notebook
    end
  end

  def initialize(notebook)
    @notebook = notebook
  end

  def add_cell(cell_type:, source: "", title: "", configuration: {}, after: nil, expected_notebook_revision:)
    @notebook.with_lock do
      check_document!(expected_notebook_revision)
      entries = @notebook.head_revision.entries.deep_dup
      position = after ? entries.index { |entry| entry.fetch("cell_id") == after } : entries.length - 1
      raise ArgumentError, "insertion cell not in notebook" unless position
      cell = @notebook.cells.create!
      revision = cell.revisions.create!(cell_type:, source:, title:, configuration:)
      cell.update!(head_revision: revision)
      entries.insert(position + 1, { "cell_id" => cell.id, "revision_id" => revision.id })
      append_document(entries:, summary: "Add #{cell_type} cell")
      cell
    end
  end

  def save_cell(cell_id:, expected_revision:, source:, title:, cell_type:, configuration: {}, summary: "", provenance: {})
    @notebook.with_lock do
      cell = @notebook.cells.find(cell_id)
      raise Conflict, "This cell changed in another editor. Your draft is preserved." unless cell.head_revision_id == expected_revision
      entries = @notebook.head_revision.entries.deep_dup
      entry = entries.find { |item| item.fetch("cell_id") == cell.id }
      raise Conflict, "This cell was removed. Your draft is preserved." unless entry
      revision = cell.revisions.create!(parent_id: cell.head_revision_id, source:, title:, cell_type:, configuration:, summary:, provenance:)
      cell.update!(head_revision: revision)
      entry["revision_id"] = revision.id
      append_document(entries:, summary:)
      revision
    end
  end

  def restore_cell(cell_id:, revision_id:, expected_revision:)
    historical = @notebook.cells.find(cell_id).revisions.find(revision_id)
    save_cell(cell_id:, expected_revision:, **historical.attributes.slice("source", "title", "cell_type", "configuration").symbolize_keys,
      summary: "Restore earlier cell revision", provenance: { "restored_from" => historical.id })
  end

  def reorder(cell_ids:, expected_notebook_revision:)
    @notebook.with_lock do
      check_document!(expected_notebook_revision)
      entries = @notebook.head_revision.entries.index_by { |entry| entry.fetch("cell_id") }
      raise ArgumentError, "reorder must contain each current cell exactly once" unless cell_ids.sort == entries.keys.sort
      append_document(entries: cell_ids.map { |id| entries.fetch(id) }, summary: "Reorder cells")
    end
  end

  def remove_cell(cell_id:, expected_notebook_revision:)
    @notebook.with_lock do
      check_document!(expected_notebook_revision)
      entries = @notebook.head_revision.entries
      raise ActiveRecord::RecordNotFound unless entries.any? { |entry| entry.fetch("cell_id") == cell_id }
      append_document(entries: entries.reject { |entry| entry.fetch("cell_id") == cell_id }, summary: "Remove cell")
    end
  end

  def restore_notebook(revision_id:, expected_notebook_revision:)
    @notebook.with_lock do
      check_document!(expected_notebook_revision)
      historical = @notebook.revisions.find(revision_id)
      entries = historical.entries.map do |entry|
        cell = @notebook.cells.find(entry.fetch("cell_id"))
        old = cell.revisions.find(entry.fetch("revision_id"))
        revision = cell.revisions.create!(**old.attributes.slice("source", "title", "cell_type", "configuration"),
          parent_id: cell.head_revision_id, summary: "Restore notebook revision",
          provenance: { "restored_from" => old.id, "notebook_revision" => historical.id })
        cell.update!(head_revision: revision)
        { "cell_id" => cell.id, "revision_id" => revision.id }
      end
      append_document(entries:, summary: "Restore notebook structure",
        provenance: { "restored_from" => historical.id })
    end
  end

  private

  def check_document!(expected)
    raise Conflict, "Notebook structure changed; reload before trying again" unless @notebook.head_revision_id == expected
  end

  def append_document(entries:, summary:, provenance: {})
    previous = @notebook.head_revision
    revision = @notebook.revisions.create!(parent_id: previous.id, title: previous.title,
      description: previous.description, configuration: previous.configuration, entries:, summary:, provenance:)
    @notebook.update!(head_revision: revision)
    revision
  end
end
