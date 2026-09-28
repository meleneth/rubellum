require "digest"

class ExecutionRequests
  def self.submit(notebook:, cell_id:, expected_revision:, inputs: {}, datasets: {}, batch_id: nil)
    inputs = Rubellum::JsonValue.copy(inputs)
    datasets = Rubellum::JsonValue.copy(datasets)
    raise ArgumentError, "Execution inputs and datasets must be objects" unless inputs.is_a?(Hash) && datasets.is_a?(Hash)
    raise ArgumentError, "Invalid execution batch identity" if batch_id && !Rubellum::Message::UUID.match?(batch_id.to_s)
    notebook.with_lock do
      cell = notebook.cells.find(cell_id)
      raise History::Conflict, "Save this exact revision before running" unless cell.head_revision_id == expected_revision
      unless notebook.head_revision.entries.any? { |entry| entry.fetch("cell_id") == cell.id }
        raise History::Conflict, "Cannot run a removed cell"
      end
      raise ArgumentError, "Only Ruby cells execute" unless cell.head_revision.cell_type == "ruby"
      session = NotebookSession.find_or_create_by!(notebook:)
      raise History::Conflict, "Session is lost; reset it before running" if session.status == "lost"
      execution = session.executions.create!(cell_revision: cell.head_revision,
        notebook_revision: notebook.head_revision, generation: session.generation,
        sequence: session.next_command_sequence, inputs:, datasets:, batch_id:,
        environment_digest: Digest::SHA256.hexdigest("ruby-#{RUBY_VERSION}-builtin-v1"))
      start = Rubellum::Message.new(session.scope_fields.merge("schema_version" => 1,
        "message_id" => SecureRandom.uuid, "kind" => "start", "sequence" => 1, "payload" => {}))
      OutboxMessage.enqueue(queue_name: Rubellum::QueueNames::MANAGER, message: start) if session.status == "requested"
      source = cell.head_revision.source
      payload = { "cell_id" => cell.id, "cell_revision_id" => cell.head_revision_id,
        "source" => source, "source_digest" => Digest::SHA256.hexdigest(source), "inputs" => inputs, "datasets" => datasets,
        "batch_id" => batch_id }
      payload = Rubellum::ExecutionPayload.pack(payload, store: AssetStorage.for_app(notebook.app))
      message = Rubellum::Message.new(session.scope_fields.merge("schema_version" => 1,
        "message_id" => SecureRandom.uuid, "execution_id" => execution.id, "kind" => "execute",
        "sequence" => execution.sequence, "payload" => payload))
      OutboxMessage.enqueue(queue_name: Rubellum::QueueNames.session(session.id, session.generation), message:)
      session.update!(next_command_sequence: session.next_command_sequence + 1)
      execution
    end
  end

  def self.interrupt(execution)
    session = execution.notebook_session
    session.with_lock do
      return if execution.reload.terminal?
      message = Rubellum::Message.new(session.scope_fields.merge("schema_version" => 1,
        "message_id" => SecureRandom.uuid, "execution_id" => execution.id, "generation" => execution.generation,
        "kind" => "interrupt", "sequence" => execution.sequence, "payload" => {}))
      OutboxMessage.enqueue(queue_name: Rubellum::QueueNames.session(session.id, execution.generation, control: true), message:)
    end
  end

  def self.reset(session)
    message = Rubellum::Message.new(session.scope_fields.merge("schema_version" => 1,
      "message_id" => SecureRandom.uuid, "kind" => "restart", "sequence" => 1, "payload" => {}))
    OutboxMessage.enqueue(queue_name: Rubellum::QueueNames::MANAGER, message:)
  end
end
