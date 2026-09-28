require "rails_helper"

RSpec.describe "Durable execution artifacts", type: :model do
  let(:notebook) { create(:notebook) }
  let(:cell) { History.new(notebook).add_cell(cell_type: "ruby", source: "42", expected_notebook_revision: notebook.head_revision_id) }
  let(:execution) { ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: cell.head_revision_id) }
  let(:blob) { AssetStorage.for_app(notebook.app).put(StringIO.new("artifact bytes")) }
  let(:message) do
    build(:runner_message, **execution.notebook_session.scope_fields.symbolize_keys, kind: "artifact", sequence: 1,
      execution_id: execution.id, payload: { "filename" => "result.txt", "mime" => "text/plain", "blob" => blob })
  end

  it "commits the artifact, exact execution reference and acknowledgment together, idempotently" do
    ingestor = EventIngestor.new
    2.times { ingestor.call(message) }
    artifact = Asset.find_by!(execution:)
    expect(Asset.count).to eq(1)
    expect(artifact.runner_event_id).to eq(message["message_id"])
    expect(artifact.reference).to eq(blob)
    expect(EventCursor.sole.through_sequence).to eq(1)
    expect(OutboxMessage.where("envelope ->> 'kind' = 'acknowledge'").count).to eq(2)
  end

  it "does not acknowledge missing artifact bytes or retain a partially registered event" do
    bad = Rubellum::Message.new(message.to_h.merge("payload" => message["payload"].merge("blob" => { "sha256" => "0" * 64, "size" => 1 })))
    expect { EventIngestor.new.call(bad) }.to raise_error(Rubellum::BlobStore::Invalid, /missing/)
    expect(Asset.count).to eq(0)
    expect(RunnerEvent.count).to eq(0)
    expect(EventCursor.count).to eq(0)
    expect(OutboxMessage.where("envelope ->> 'kind' = 'acknowledge'").count).to eq(0)
  end

  it "enforces event-to-asset byte identity independently of model callbacks" do
    event = RunnerEvent.create!(id: message["message_id"], notebook_session: execution.notebook_session,
      generation: 1, sequence: 1, envelope: message.to_h)
    attributes = { app_id: notebook.app_id, execution_id: execution.id, runner_event_id: event.id,
      filename: "result.txt", mime_type: "text/plain", sha256: "0" * 64, byte_size: blob["size"], created_at: Time.current }
    expect { ApplicationRecord.transaction(requires_new: true) { Asset.insert_all!([attributes]) } }
      .to raise_error(ActiveRecord::StatementInvalid, /metadata does not match/)
  end

  it "enforces app ownership independently of model callbacks" do
    event = RunnerEvent.create!(id: message["message_id"], notebook_session: execution.notebook_session,
      generation: 1, sequence: 1, envelope: message.to_h)
    attributes = { app_id: create(:app).id, execution_id: execution.id, runner_event_id: event.id,
      filename: "result.txt", mime_type: "text/plain", sha256: blob["sha256"], byte_size: blob["size"], created_at: Time.current }
    expect { ApplicationRecord.transaction(requires_new: true) { Asset.insert_all!([attributes]) } }
      .to raise_error(ActiveRecord::StatementInvalid, /provenance does not match/)
  end
end
