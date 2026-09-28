require "rails_helper"
require "rubellum/runner_manager"
require_relative "../support/goaws_process"
require "tmpdir"
require "timeout"

RSpec.describe "PostgreSQL → SQS → managed Ruby → SQS → PostgreSQL", type: :model do
  it "persists the result of the exact saved revision and acknowledges the runner spool" do
    Dir.mktmpdir("rubellum-full-") do |directory|
      broker = GoawsProcess.new.start
      previous = ENV["SQS_ENDPOINT"]
      previous_data = ENV["RUBELLUM_DATA"]
      ENV["SQS_ENDPOINT"] = broker.endpoint
      ENV["RUBELLUM_DATA"] = directory
      transport = Rubellum::SqsTransport.local(endpoint: broker.endpoint)
      manager = Rubellum::RunnerManager.new(root: directory, transport:)
      notebook = create(:notebook)
      source = 'puts "from Ruby"; File.write("result.txt", "immutable result"); Notebook.asset("result.txt"); File.write("result.txt", "changed scratch"); 6 * 7'
      cell = History.new(notebook).add_cell(cell_type: "ruby", source:, expected_notebook_revision: notebook.head_revision_id)
      execution = ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: cell.head_revision_id)
      dispatcher = OutboxDispatcher.new(transport:)
      ingestor = EventIngestor.new
      Timeout.timeout(15) do
        until execution.reload.terminal?
          dispatcher.call
          manager.step
          queue = transport.ensure_queue(Rubellum::QueueNames::EVENTS)
          transport.receive(queue, wait_seconds: 0).each do |delivery|
            ingestor.call(delivery.message)
            transport.delete(queue, delivery)
          end
          sleep 0.01
        end
      end
      expect(execution.status).to eq("completed")
      expect(execution.result.fetch("inspection")).to eq("42")
      expect(execution.events.map { |event| event.envelope.fetch("kind") }).to include("stdout", "execution_accepted", "execution_started")
      expect(execution.cell_revision_id).to eq(cell.head_revision_id)
      artifact = Asset.find_by!(execution:)
      expect(artifact.filename).to eq("result.txt")
      expect(AssetStorage.for_app(notebook.app).read(artifact.reference)).to eq("immutable result")
      expect { ingestor.call(Rubellum::Message.new(artifact.runner_event.envelope)) }.not_to change(Asset, :count)
      dispatcher.call
      journal_path = File.join(directory, "runtime/sessions", execution.notebook_session_id, "1/state.json")
      Timeout.timeout(5) do
        until JSON.parse(File.read(journal_path)).fetch("events").empty?
          sleep 0.01
        end
      end
    ensure
      manager&.close
      broker&.close
      ENV["SQS_ENDPOINT"] = previous
      ENV["RUBELLUM_DATA"] = previous_data
    end
  end
end
