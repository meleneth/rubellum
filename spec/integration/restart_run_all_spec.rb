require "rails_helper"
require "rubellum/runner_manager"
require_relative "../support/goaws_process"
require "tmpdir"
require "timeout"

RSpec.describe "Restart batch through the real broker and manager", type: :model do
  it "survives lost notifications and runs the captured batch once in a fresh Ruby context" do
    Dir.mktmpdir("rubellum-restart-batch-") do |directory|
      previous_endpoint, previous_data = ENV.values_at("SQS_ENDPOINT", "RUBELLUM_DATA")
      broker = GoawsProcess.new.start
      ENV["SQS_ENDPOINT"], ENV["RUBELLUM_DATA"] = broker.endpoint, directory
      transport = Rubellum::SqsTransport.local(endpoint: broker.endpoint)
      manager = Rubellum::RunnerManager.new(root: directory, transport:)
      now = Time.current
      dispatcher = OutboxDispatcher.new(transport:, clock: -> { now })
      ingestor = EventIngestor.new
      held = []
      hold_stopped = false
      pump = lambda do |executions|
        Timeout.timeout(15) do
          until executions.all? { |execution| execution.reload.terminal? }
            dispatcher.call
            manager.step
            queue = transport.ensure_queue(Rubellum::QueueNames::EVENTS)
            transport.receive(queue, wait_seconds: 0).each do |delivery|
              message = delivery.message
              if hold_stopped && message["kind"] == "runner_stopped" && message["generation"] == 1
                held << message
              else
                ingestor.call(message)
              end
              transport.delete(queue, delivery)
            end
            sleep 0.01
          end
        end
      end
      notebook = create(:notebook)
      marker = File.join(directory, "side-effects")
      source = "counter = (defined?(counter) && counter || 0) + 1; File.open(#{marker.inspect}, 'a') { |file| file.puts(counter) }; counter"
      first = History.new(notebook).add_cell(cell_type: "ruby", source:, expected_notebook_revision: notebook.head_revision_id)
      second = History.new(notebook).add_cell(cell_type: "ruby", source: "counter * 10", expected_notebook_revision: notebook.head_revision_id)
      2.times do |index|
        execution = ExecutionRequests.submit(notebook:, cell_id: first.id, expected_revision: first.head_revision_id)
        pump.call([execution])
        expect(execution.result.fetch("inspection")).to eq((index + 1).to_s)
      end

      batch = ExecutionRequests.restart_all(notebook)
      History.new(notebook).save_cell(cell_id: first.id, expected_revision: first.head_revision_id,
        source: "raise 'new draft must not run'", title: "Edited after request", cell_type: "ruby")
      dispatcher.call
      # Lose already-sent restart and next-generation execution notifications.
      broker.stop
      broker.start
      now += 6
      hold_stopped = true
      pump.call(batch)
      expect(batch.map(&:status)).to eq(["completed", "completed"])
      expect(batch.map { |execution| execution.result.fetch("inspection") }).to eq(["1", "10"])
      expect(File.readlines(marker, chomp: true)).to eq(["1", "2", "1"])
      session = batch.first.notebook_session.reload
      expect(session).to have_attributes(generation: 2, status: "ready", restart_generation: nil)
      expect(held).not_to be_empty
      held.each { |message| ingestor.call(message) }
      expect(session.reload.status).to eq("ready")
      expect(OutboxMessage.where(confirmed_at: nil).where("envelope ->> 'kind' = 'restart'")).to be_empty
      following = ExecutionRequests.submit(notebook:, cell_id: second.id, expected_revision: second.head_revision_id)
      expect(following).to have_attributes(generation: 2, sequence: 3)
      pump.call([following])
      expect(following.result.fetch("inspection")).to eq("10")
    ensure
      manager&.close
      broker&.close
      ENV["SQS_ENDPOINT"], ENV["RUBELLUM_DATA"] = previous_endpoint, previous_data
    end
  end
end
