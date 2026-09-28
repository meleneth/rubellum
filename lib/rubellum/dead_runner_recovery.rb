require_relative "runtime_events"
require_relative "queue_names"

module Rubellum
  class DeadRunnerRecovery
    def initialize(journal:, transport:)
      @journal, @transport = journal, transport
    end

    def mark_lost
      return if @journal.state.empty? || @journal.state["closed"]
      @journal.update(terminal: true) do |state|
        state.fetch("commands").each_value do |command|
          status = command.fetch("state")
          next unless %w[accepted started].include?(status)
          kind = status == "started" ? "execution_unknown" : "execution_cancelled"
          envelope = command.fetch("envelope")
          RuntimeEvents.append(state, kind, { "message" => "Runner was lost; source was not replayed" },
            envelope.fetch("execution_id"), envelope.fetch("message_id"))
          command["state"] = kind
        end
        RuntimeEvents.append(state, "runner_stopped", { "message" => "Ruby context is lost; reset explicitly" })
        state["closed"] = true
      end
    end

    def replay
      return if @journal.state.empty?
      scope = @journal.state.fetch("scope")
      control = @transport.ensure_queue(QueueNames.session(scope["session_id"], scope["generation"], control: true))
      @transport.receive(control, wait_seconds: 0).each do |delivery|
        message = delivery.message
        if message["kind"] == "acknowledge" && scope.all? { |key, value| message[key] == value }
          through = message["payload"]["through_sequence"]
          if through.is_a?(Integer) && through.between?(0, @journal.state.fetch("event_sequence"))
            @journal.update(terminal: true) do |state|
              state["acknowledged"] = [through, state.fetch("acknowledged")].max
              state.fetch("events").reject! { |event| event.fetch("sequence") <= state.fetch("acknowledged") }
            end
          end
        end
        @transport.delete(control, delivery)
      end
      queue = @transport.ensure_queue(QueueNames::EVENTS)
      @journal.state.fetch("events").each { |event| @transport.publish(queue, Message.new(event)) }
    end
  end
end
