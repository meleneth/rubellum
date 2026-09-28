class Draft < ApplicationRecord
  belongs_to :cell
  validates :editor_id, :base_revision_id, presence: true
  validates :cell_type, inclusion: { in: CellRevision::TYPES }
end
