class Execution < ApplicationRecord
  belongs_to :notebook_session
  belongs_to :cell_revision
  belongs_to :notebook_revision
  TERMINAL = %w[completed failed interrupted cancelled unknown].freeze
  def terminal? = TERMINAL.include?(status)
  def events
    notebook_session.runner_events.where(generation:).where("envelope ->> 'execution_id' = ?", id).order(:sequence)
  end
end
