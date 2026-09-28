require "rbconfig"
require_relative "runtime_journal"
require_relative "dead_runner_recovery"
require_relative "session_agent"

module Rubellum
  class RunnerManager
    MAX_SESSIONS = 8

    def initialize(root:, transport:)
      @root, @transport = root, transport
      @registry = RuntimeJournal.new(directory: File.join(root, "runtime/manager"))
      @registry.update { |state| state["sessions"] = {} } if @registry.state.empty?
      @children, @recovery = {}, {}
      @registry.state.fetch("sessions").each_value { |scope| recover(scope) }
    end

    def step
      @children.keys.each do |key|
        next unless Process.waitpid(@children.fetch(key), Process::WNOHANG)
        @children.delete(key)
        recover(@registry.state.fetch("sessions").fetch(key))
      end
      queue = @transport.ensure_queue(QueueNames::MANAGER)
      @transport.receive(queue, wait_seconds: 0).each do |delivery|
        message = delivery.message
        scope = message.to_h.slice(*SessionAgent::SCOPE_FIELDS)
        key = "#{scope.fetch('session_id')}:#{scope.fetch('generation')}"
        if message["kind"] == "start" && !@registry.state.fetch("sessions").key?(key)
          next if @children.size >= MAX_SESSIONS
          @registry.update { |state| state.fetch("sessions")[key] = scope }
          spawn_agent(key, scope)
        elsif message["kind"] == "restart"
          replacement = scope.merge("generation" => scope.fetch("generation") + 1)
          replacement_key = "#{replacement.fetch('session_id')}:#{replacement.fetch('generation')}"
          if @registry.state.fetch("sessions")[key] == scope && !@registry.state.fetch("sessions").key?(replacement_key)
            terminate_agent(key)
            recover(scope) unless @recovery.key?(key)
            @registry.update { |state| state.fetch("sessions")[replacement_key] = replacement }
            spawn_agent(replacement_key, replacement)
          end
        end
        @transport.delete(queue, delivery)
      end
      @recovery.each_value { |journal| DeadRunnerRecovery.new(journal:, transport: @transport).replay }
    rescue Aws::SQS::Errors::ServiceError, Seahorse::Client::NetworkingError
      nil
    end

    def close
      @children.keys.each { |key| terminate_agent(key) }
      @recovery.each_value(&:close)
      @registry.close
    end

    private

    def terminate_agent(key)
      pid = @children.delete(key)
      return unless pid
      Process.kill("TERM", pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      until Process.waitpid(pid, Process::WNOHANG)
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          Process.kill("KILL", -pid)
          Process.waitpid(pid)
          break
        end
        sleep 0.02
      end
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def spawn_agent(key, scope)
      script = File.expand_path("../../bin/runner-agent", __dir__)
      @children[key] = Process.spawn(RbConfig.ruby, script, JSON.generate(scope), @root, pgroup: true)
    end

    def recover(scope)
      key = "#{scope.fetch('session_id')}:#{scope.fetch('generation')}"
      journal = RuntimeJournal.new(directory: File.join(@root, "runtime/sessions", scope.fetch("session_id"), scope.fetch("generation").to_s))
      ProcessIdentity.terminate_group(journal.state["evaluator"])
      if journal.state.empty?
        journal.update do |state|
          state.merge!("scope" => scope, "commands" => {}, "events" => [], "event_sequence" => 0, "acknowledged" => 0)
        end
      end
      DeadRunnerRecovery.new(journal:, transport: @transport).mark_lost
      @recovery[key] = journal
    end
  end
end
