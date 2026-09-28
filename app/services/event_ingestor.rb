class EventIngestor
  class Invalid < StandardError; end

  def call(message)
    raise Invalid, "expected a fact" if message.command?
    session = NotebookSession.find(message["session_id"])
    unless session.notebook_id == message["notebook_id"] && session.notebook.app_id == message["app_installation_id"]
      raise Invalid, "event scope does not match session"
    end
    session.with_lock do
      event = RunnerEvent.create_or_find_by!(id: message["message_id"]) do |record|
        record.assign_attributes(notebook_session: session, generation: message["generation"], sequence: message["sequence"], envelope: message.to_h)
      end
      raise Invalid, "event identity reused for different content" unless event.envelope == message.to_h
      cursor = EventCursor.find_or_create_by!(notebook_session: session, generation: message["generation"])
      loop do
        next_event = session.runner_events.find_by(generation: cursor.generation, sequence: cursor.through_sequence + 1)
        break unless next_event
        apply(session, next_event.envelope)
        cursor.update!(through_sequence: next_event.sequence)
      end
      acknowledge(session, cursor) if cursor.through_sequence.positive?
    end
  end

  private

  def apply(session, envelope)
    kind = envelope.fetch("kind")
    current = session.generation == envelope.fetch("generation")
    if kind == "runner_ready"
      if envelope.fetch("generation") >= session.generation
        attributes = { status: "ready", generation: envelope.fetch("generation") }
        attributes[:next_command_sequence] = 1 unless current
        session.update!(attributes)
        OutboxMessage.where(confirmed_at: nil).where("envelope ->> 'session_id' = ? AND envelope ->> 'kind' = 'restart' AND (envelope ->> 'generation')::integer < ?", session.id, session.generation).update_all(confirmed_at: Time.current)
      end
      OutboxMessage.where(confirmed_at: nil).where("envelope ->> 'session_id' = ? AND envelope ->> 'kind' = 'start' AND (envelope ->> 'generation')::integer = ?", session.id, envelope.fetch("generation")).update_all(confirmed_at: Time.current)
    elsif kind == "runner_stopped"
      session.update!(status: "lost") if current
      session.executions.where(generation: envelope.fetch("generation"), status: "running").update_all(status: "unknown")
      session.executions.where(generation: envelope.fetch("generation"), status: %w[queued accepted]).update_all(status: "cancelled")
      OutboxMessage.where(confirmed_at: nil).where("envelope ->> 'session_id' = ? AND (envelope ->> 'generation')::integer = ? AND envelope ->> 'kind' IN ('start', 'execute')", session.id, envelope.fetch("generation")).update_all(confirmed_at: Time.current)
    elsif (execution_id = envelope["execution_id"])
      execution = session.executions.find_by!(id: execution_id, generation: envelope.fetch("generation"))
      status = { "execution_accepted" => "accepted", "execution_started" => "running", "execution_completed" => "completed",
        "execution_failed" => "failed", "execution_interrupted" => "interrupted", "execution_cancelled" => "cancelled", "execution_unknown" => "unknown" }[kind]
      if status && !execution.terminal?
        execution.update!(status:, result: envelope.fetch("payload"))
      end
      if kind == "execution_accepted"
        OutboxMessage.where(id: envelope["command_id"]).update_all(confirmed_at: Time.current)
      end
    end
  end

  def acknowledge(session, cursor)
    message = Rubellum::Message.new(session.scope_fields.merge("schema_version" => 1, "message_id" => SecureRandom.uuid,
      "generation" => cursor.generation, "kind" => "acknowledge", "sequence" => cursor.through_sequence,
      "payload" => { "through_sequence" => cursor.through_sequence }))
    OutboxMessage.enqueue(queue_name: Rubellum::QueueNames.session(session.id, cursor.generation, control: true), message:)
  end
end
