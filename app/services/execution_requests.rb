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
      session.with_lock do
        raise History::Conflict, "Session reset is pending; wait for the fresh context" if session.restart_generation
        raise History::Conflict, "Session is lost; reset it before running" if session.status == "lost"
        lifecycle(session, "start") if session.status == "requested"
        execution = enqueue(session:, revision: cell.head_revision, notebook_revision: notebook.head_revision,
          generation: session.generation, sequence: session.next_command_sequence, inputs:, datasets:, batch_id:)
        session.update!(next_command_sequence: session.next_command_sequence + 1)
        execution
      end
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
    session.notebook.with_lock do
      session.with_lock { request_reset(session) }
    end
  end

  def self.restart_all(notebook)
    notebook.with_lock do
      snapshot = notebook.head_revision
      revisions = snapshot.ordered_revisions.select { |revision| revision.cell_type == "ruby" }
      return [] if revisions.empty?
      session = NotebookSession.find_by(notebook:)
      return RunAll.call(notebook) unless session

      session.with_lock do
        request_reset(session)
        data = NotebookData.new(notebook)
        inputs, datasets = data.inputs, data.datasets
        batch_id = SecureRandom.uuid
        revisions.each_with_index.map do |revision, index|
          enqueue(session:, revision:, notebook_revision: snapshot, generation: session.restart_generation,
            sequence: index + 1, inputs:, datasets:, batch_id:)
        end
      end
    end
  end

  def self.request_reset(session)
    raise History::Conflict, "Session reset is already pending" if session.restart_generation
    lifecycle(session, "start") if session.status == "requested"
    session.update!(status: "restarting", restart_generation: session.generation + 1)
    lifecycle(session, "restart")
  end

  def self.lifecycle(session, kind)
    message = Rubellum::Message.new(session.scope_fields.merge("schema_version" => 1,
      "message_id" => SecureRandom.uuid, "kind" => kind, "sequence" => 1, "payload" => {}))
    OutboxMessage.enqueue(queue_name: Rubellum::QueueNames::MANAGER, message:)
  end

  def self.enqueue(session:, revision:, notebook_revision:, generation:, sequence:, inputs:, datasets:, batch_id:)
    execution = session.executions.create!(cell_revision: revision, notebook_revision:, generation:, sequence:,
      inputs:, datasets:, batch_id:, environment_digest: Digest::SHA256.hexdigest("ruby-#{RUBY_VERSION}-builtin-v1"))
    source = revision.source
    payload = { "cell_id" => revision.cell_id, "cell_revision_id" => revision.id,
      "source" => source, "source_digest" => Digest::SHA256.hexdigest(source), "inputs" => inputs, "datasets" => datasets,
      "batch_id" => batch_id }
    payload = Rubellum::ExecutionPayload.pack(payload, store: AssetStorage.for_app(session.notebook.app))
    message = Rubellum::Message.new(session.scope_fields.merge("schema_version" => 1, "generation" => generation,
      "message_id" => SecureRandom.uuid, "execution_id" => execution.id, "kind" => "execute",
      "sequence" => sequence, "payload" => payload))
    OutboxMessage.enqueue(queue_name: Rubellum::QueueNames.session(session.id, generation), message:)
    execution
  end
  private_class_method :request_reset, :lifecycle, :enqueue
end
