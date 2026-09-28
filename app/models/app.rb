class App < ApplicationRecord
  belongs_to :head_revision, class_name: "AppRevision", optional: true
  has_many :revisions, class_name: "AppRevision"
  has_many :notebooks
  scope :active, -> { where(archived_at: nil) }
  def title = head_revision&.title || "Untitled app"
end
