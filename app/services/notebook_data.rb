class NotebookData
  def initialize(notebook)
    @notebook = notebook
  end

  def inputs
    @notebook.head_revision.ordered_revisions.select { |revision| revision.cell_type == "parameters" }.each_with_object({}) do |revision, result|
      stored = ParameterValue.find_by(cell_id: revision.cell_id)&.values || {}
      definitions = Rubellum::Parameters.new(JSON.parse(revision.source))
      names = definitions.definitions.map { |definition| definition.fetch("name") }
      values = definitions.values(stored.slice(*names))
      raise ArgumentError, "Parameter names must be unique in a notebook" unless (result.keys & values.keys).empty?
      result.merge!(values)
    end
  end

  def datasets
    @notebook.head_revision.ordered_revisions.select { |revision| revision.cell_type == "data" }.each_with_object({}) do |revision, result|
      name = revision.configuration.fetch("name", revision.cell_id)
      raise ArgumentError, "Dataset names must be unique in a notebook" if result.key?(name)
      result[name] = Rubellum::DataCell.parse(revision.source, revision.configuration)
    end
  end

  def resolve(renderer)
    reference = renderer.configuration.fetch("input") { raise ArgumentError, "Choose an input cell in Configuration: {\"input\": {\"cell_id\": \"…\", \"output\": \"rows\"}}" }
    producer = Cell.joins(:notebook).where(notebooks: { app_id: @notebook.app_id }).find(reference.fetch("cell_id"))
    revision = producer.head_revision
    if revision.cell_type == "data"
      { data: Rubellum::DataCell.parse(revision.source, revision.configuration), inputs:,
        provenance: { cell_id: producer.id, revision_id: revision.id }, stale: false }
    elsif revision.cell_type == "ruby"
      scope = Execution.joins(:cell_revision).where(cell_revisions: { cell_id: producer.id }).order(created_at: :desc)
      execution = scope.where(status: "completed").first
      raise ArgumentError, "Run the selected Ruby cell successfully first" unless execution
      output = execution.events.find { |event| event.envelope["kind"] == "structured_output" && event.envelope.dig("payload", "name") == reference.fetch("output", "rows") }
      raise ArgumentError, "Selected output was not emitted by the last successful execution" unless output
      { data: output.envelope.dig("payload", "data"), inputs:,
        provenance: { cell_id: producer.id, revision_id: execution.cell_revision_id, execution_id: execution.id },
        stale: execution.cell_revision_id != revision.id || scope.first.id != execution.id }
    else
      raise ArgumentError, "Renderer inputs must reference a data or Ruby cell"
    end
  end
end
