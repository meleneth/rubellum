class CellRevision < ImmutableRevision
  TYPES = %w[markdown ruby d3 data table parameters].freeze
  belongs_to :cell
  validates :cell_type, inclusion: { in: TYPES }
  validates :source, length: { maximum: 1_048_576 }
  before_validation(on: :create) { AssetReferences.validate!(app_id: cell.notebook.app_id, configuration:, source:) }
end
