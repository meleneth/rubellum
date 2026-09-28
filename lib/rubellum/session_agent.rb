# frozen_string_literal: true
require "securerandom"
require "digest"
require_relative "message"
require_relative "queue_names"
require_relative "runtime_journal"
require_relative "sqs_transport"
require_relative "evaluator_process"
require_relative "runtime_events"
require_relative "process_identity"

module Rubellum
  class SessionAgent
    class ProtocolError < StandardError; end
    SCOPE_FIELDS = %w[app_installation_id notebook_id session_id generation].freeze
    attr_reader :stopped

    def initialize(scope:, transport:, journal:, evaluator:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @scope, @transport, @journal, @evaluator, @clock = JsonValue.copy(scope), transport, journal, evaluator, clock
      @stopped = false
      if journal.state.empty?
        journal.update do |state|
          state.merge!("scope" => scope, "next_command" => 1, "event_sequence" => 0, "acknowledged" => 0, "commands" => {}, "events" => [])
          state["evaluator"] = ProcessIdentity.capture(evaluator.pid) if evaluator.pid
          append_event(state, "runner_ready", {})
        end
      else
        raise ProtocolError, "An existing session journal cannot start a replacement Ruby context"
      end
    end

    def step
      provision
      controls
      @transport.receive(@commands_queue, wait_seconds: 0).each do |delivery|
        accept(delivery.message)
        @transport.delete(@commands_queue, delivery)
      end
      command = @journal.state.fetch("commands")[@journal.state.fetch("next_command").to_s]
      perform(command.fetch("envelope")) if command && !stopped
      replay
    rescue Aws::SQS::Errors::ServiceError, Seahorse::Client::NetworkingError
      # The durable journal remains authoritative; next step recreates topology.
      nil
    end

    def accept(message)
      return unless matches?(message)
      raise ProtocolError, "execution queue only accepts execute" unless message["kind"] == "execute"
      payload = message["payload"]
      unless payload["source"].is_a?(String) && Message::UUID.match?(payload["cell_id"].to_s) &&
          Message::UUID.match?(payload["cell_revision_id"].to_s) &&
          payload["source_digest"] == Digest::SHA256.hexdigest(payload["source"]) &&
          payload.fetch("inputs", {}).is_a?(Hash) && payload.fetch("datasets", {}).is_a?(Hash) &&
          (payload["batch_id"].nil? || Message::UUID.match?(payload["batch_id"].to_s))
        raise ProtocolError, "invalid execution payload or source digest"
      end
      sequence = message["sequence"].to_s
      commands = @journal.state.fetch("commands")
      if (previous = commands[sequence])
        raise ProtocolError, "conflicting command sequence" unless previous.fetch("envelope") == message.to_h
        return
      end
      raise ProtocolError, "duplicate execution with different command identity" if commands.values.any? { |item| item.fetch("envelope")["execution_id"] == message["execution_id"] }
      @journal.update do |state|
        state.fetch("commands")[sequence] = { "envelope" => message.to_h, "state" => "accepted" }
        append_event(state, "execution_accepted", {}, message["execution_id"], message["message_id"])
      end
    end

    def replay
      @journal.state.fetch("events").each { |event| @transport.publish(@events_queue, Message.new(event)) }
    rescue Aws::SQS::Errors::ServiceError, Seahorse::Client::NetworkingError
      nil
    end

    def publish_latest
      event = @journal.state.fetch("events").last
      @transport.publish(@events_queue, Message.new(event)) if event
    rescue Aws::SQS::Errors::ServiceError, Seahorse::Client::NetworkingError
      nil
    end

    def close
      @evaluator.close
      @journal.close
    end

    private

    def provision
      @commands_queue = @transport.ensure_queue(QueueNames.session(@scope.fetch("session_id"), @scope.fetch("generation")))
      @control_queue = @transport.ensure_queue(QueueNames.session(@scope.fetch("session_id"), @scope.fetch("generation"), control: true))
      @events_queue = @transport.ensure_queue(QueueNames::EVENTS)
    end

    def matches?(message)
      SCOPE_FIELDS.all? { |key| message[key] == @scope.fetch(key) }
    end

    def controls
      @transport.receive(@control_queue, wait_seconds: 0).each do |delivery|
        message = delivery.message
        if matches?(message)
          case message["kind"]
          when "acknowledge"
            acknowledged = message["payload"].fetch("through_sequence")
            raise ProtocolError, "invalid event acknowledgment" unless acknowledged.is_a?(Integer) && acknowledged.between?(0, @journal.state.fetch("event_sequence"))
            @journal.update(terminal: true) do |state|
              state["acknowledged"] = [state.fetch("acknowledged"), acknowledged].max
              state["events"].reject! { |event| event.fetch("sequence") <= state.fetch("acknowledged") }
            end
          when "interrupt"
            if @active_execution == message["execution_id"] && !@interrupt_deadline
              @evaluator.interrupt
              @interrupt_deadline = @clock.call + 2
            end
          end
        end
        @transport.delete(@control_queue, delivery)
      end
    end

    def tick
      if @interrupt_deadline && @clock.call >= @interrupt_deadline
        @evaluator.close
        @stopped = true
        raise EvaluatorProcess::Lost, "Interrupt grace exceeded; evaluator process group terminated"
      end
      controls
    rescue Aws::SQS::Errors::ServiceError, Seahorse::Client::NetworkingError
      begin
        provision
      rescue Aws::SQS::Errors::ServiceError, Seahorse::Client::NetworkingError
        nil
      end
    end

    def perform(envelope)
      @active_execution = envelope.fetch("execution_id")
      sequence = envelope.fetch("sequence").to_s
      batch_id = envelope.dig("payload", "batch_id")
      failed = batch_id && @journal.state.fetch("commands").values.find do |command|
        command.dig("envelope", "payload", "batch_id") == batch_id &&
          %w[execution_failed execution_interrupted execution_unknown execution_cancelled].include?(command["state"])
      end
      if failed
        @journal.update(terminal: true) do |state|
          state.fetch("commands").fetch(sequence)["state"] = "execution_cancelled"
          state["next_command"] += 1
          append_event(state, "execution_cancelled", { "message" => "Run all stopped after an earlier cell did not complete successfully", "batch_id" => batch_id }, @active_execution, envelope.fetch("message_id"))
        end
        publish_latest
        return
      end
      @journal.update do |state|
        state.fetch("commands").fetch(sequence)["state"] = "started"
        append_event(state, "execution_started", {}, @active_execution, envelope.fetch("message_id"))
      end
      replay
      payload = envelope.fetch("payload")
      @evaluator.execute(source: payload.fetch("source"), cell_id: payload.fetch("cell_id"),
        inputs: payload.fetch("inputs", {}), datasets: payload.fetch("datasets", {}), tick: method(:tick)) do |kind, data|
        terminal = kind.start_with?("execution_")
        @journal.update(terminal:) do |state|
          append_event(state, kind, data, @active_execution, envelope.fetch("message_id"))
          if terminal
            state.fetch("commands").fetch(sequence)["state"] = kind
            state["next_command"] += 1
          end
        end
        publish_latest
      end
    rescue EvaluatorProcess::Lost, RuntimeJournal::Full => error
      @stopped = true
      @evaluator.close
      @journal.update(terminal: true) do |state|
        append_event(state, "execution_unknown", { "message" => error.message }, @active_execution, envelope.fetch("message_id"))
        state.fetch("commands").fetch(sequence)["state"] = "execution_unknown"
        state["next_command"] += 1
      end
    ensure
      @active_execution = @interrupt_deadline = nil
    end

    def append_event(state, kind, payload, execution_id = nil, command_id = nil)
      RuntimeEvents.append(state, kind, payload, execution_id, command_id)
    end
  end
end
