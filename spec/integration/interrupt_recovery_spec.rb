require "rails_helper"
require "rubellum/runner_manager"
require_relative "../support/goaws_process"

RSpec.describe "Durable interrupt recovery", type: :model do
  it "republishes an interrupt lost by a real broker restart and stops the existing evaluator" do
    Dir.mktmpdir("rubellum-interrupt-") do |directory|
      previous_endpoint, previous_data = ENV["SQS_ENDPOINT"], ENV["RUBELLUM_DATA"]
      broker = GoawsProcess.new.start
      ENV["SQS_ENDPOINT"], ENV["RUBELLUM_DATA"] = broker.endpoint, directory
      transport = Rubellum::SqsTransport.local(endpoint: broker.endpoint)
      manager = Rubellum::RunnerManager.new(root: directory, transport:)
      now = Time.current
      dispatcher = OutboxDispatcher.new(transport:, clock: -> { now })
      ingestor = EventIngestor.new
      notebook = create(:notebook)
      source = 'File.write("agent.pid", Process.ppid.to_s); File.open("starts", "a") { |f| f.puts("once") }; loop { sleep 0.02 }'
      cell = History.new(notebook).add_cell(cell_type: "ruby", source:, expected_notebook_revision: notebook.head_revision_id)
      execution = ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: cell.head_revision_id)
      workspace = File.join(directory, "apps", notebook.app_id, "workspaces", notebook.id)
      pump = lambda do
        dispatcher.call
        manager.step
        queue = transport.ensure_queue(Rubellum::QueueNames::EVENTS)
        transport.receive(queue, wait_seconds: 0).each do |delivery|
          ingestor.call(delivery.message)
          transport.delete(queue, delivery)
        end
      end
      Timeout.timeout(15) do
        until execution.reload.status == "running" && File.exist?(File.join(workspace, "starts"))
          pump.call
          sleep 0.01
        end
      end

      # Freeze only this generated agent at a deterministic delivery boundary.
      # Its evaluator remains alive. The broker can acknowledge SendMessage,
      # then lose the notification before any consumer can receive it.
      agent_pid = Integer(File.read(File.join(workspace, "agent.pid")))
      Process.kill("STOP", agent_pid)
      Timeout.timeout(5) do
        sleep 0.005 until File.read("/proc/#{agent_pid}/status").match?(/^State:\s+T/)
      end
      request = ExecutionRequests.interrupt(execution)
      dispatcher.call
      expect(request.reload.sent_at).not_to be_nil
      expect(request.confirmed_at).to be_nil
      broker.stop
      broker.start
      control = transport.ensure_queue(Rubellum::QueueNames.session(execution.notebook_session_id, execution.generation, control: true))
      expect(transport.receive(control, wait_seconds: 0)).to be_empty
      now += 6
      dispatcher.call
      Process.kill("CONT", agent_pid)
      agent_pid = nil
      Timeout.timeout(15) do
        until execution.reload.terminal?
          pump.call
          sleep 0.01
        end
      end
      expect(execution.status).to eq("interrupted")
      expect(request.reload.confirmed_at).not_to be_nil
      expect(File.readlines(File.join(workspace, "starts"))).to eq(["once\n"])
      expect(execution.notebook_session.reload.generation).to eq(1)
    ensure
      begin
        Process.kill("CONT", agent_pid) if agent_pid
      rescue Errno::ESRCH
        nil
      end
      manager&.close
      broker&.close
      ENV["SQS_ENDPOINT"], ENV["RUBELLUM_DATA"] = previous_endpoint, previous_data
    end
  end
end
