class RunAll
  def self.call(notebook)
    notebook.with_lock do
      data = NotebookData.new(notebook)
      inputs, datasets = data.inputs, data.datasets
      batch_id = SecureRandom.uuid
      notebook.head_revision.ordered_revisions.filter_map do |revision|
        next unless revision.cell_type == "ruby"
        ExecutionRequests.submit(notebook:, cell_id: revision.cell_id, expected_revision: revision.id,
          inputs:, datasets:, batch_id:)
      end
    end
  end
end
