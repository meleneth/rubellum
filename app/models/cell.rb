class Cell < ApplicationRecord
  belongs_to :notebook
  belongs_to :head_revision, class_name: "CellRevision", optional: true
  has_many :revisions, class_name: "CellRevision"
  has_many :drafts
end
