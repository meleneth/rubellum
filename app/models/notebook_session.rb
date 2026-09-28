class NotebookSession < ApplicationRecord
  belongs_to :notebook
  has_many :executions
  has_many :runner_events
  def scope_fields
    { "app_installation_id" => notebook.app_id, "notebook_id" => notebook_id,
      "session_id" => id, "generation" => generation }
  end
end
