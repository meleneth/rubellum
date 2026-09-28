class NotebookRevision < ImmutableRevision
  belongs_to :notebook
  validates :title, presence: true

  def ordered_revisions
    records = CellRevision.where(id: entries.map { |entry| entry.fetch("revision_id") }).index_by(&:id)
    entries.map { |entry| records.fetch(entry.fetch("revision_id")) }
  end
end
