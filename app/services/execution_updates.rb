class ExecutionUpdates
  def self.broadcast(session)
    notebook = session.notebook
    Turbo::StreamsChannel.broadcast_replace_to(notebook, target: "notebook-status-#{notebook.id}",
      partial: "notebooks/status", locals: { notebook: })
    session.executions.joins(:cell_revision).distinct.pluck("cell_revisions.cell_id").each do |cell_id|
      cell = notebook.cells.find(cell_id)
      Turbo::StreamsChannel.broadcast_replace_to(notebook, target: "cell-output-#{cell.id}",
        partial: "cells/output", locals: { cell: })
    end
  end
end
