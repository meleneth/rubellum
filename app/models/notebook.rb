class Notebook < ApplicationRecord
  belongs_to :app
  belongs_to :head_revision, class_name: "NotebookRevision", optional: true
  has_many :revisions, class_name: "NotebookRevision"
  has_many :cells
  def title = head_revision&.title || "Untitled notebook"
end
