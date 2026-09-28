require "marcel"
require "stringio"

class AssetStorage
  def self.for_app(app)
    Rubellum::BlobStore.for_app(root: ENV.fetch("RUBELLUM_DATA", "/data"), app_id: app.id)
  end

  def self.upload(app:, io:, filename:, expected_revision:)
    app.with_lock do
      raise History::Conflict, "App changed; reload before uploading" unless app.head_revision_id == expected_revision
      asset = app.assets.build(filename:, mime_type: "application/octet-stream", sha256: "0" * 64, byte_size: 0)
      asset.validate!
      reference = for_app(app).put(io)
      mime = Marcel::MimeType.for(StringIO.new(for_app(app).read(reference)), name: filename)
      asset.assign_attributes(sha256: reference.fetch("sha256"), byte_size: reference.fetch("size"), mime_type: mime)
      asset.save!
      previous = app.head_revision
      configuration = previous.configuration.merge("asset_ids" => (previous.configuration.fetch("asset_ids", []) + [asset.id]))
      revision = app.revisions.create!(parent_id: previous.id, title: previous.title, description: previous.description,
        landing_notebook_id: previous.landing_notebook_id, configuration:, summary: "Upload #{filename}")
      app.update!(head_revision: revision)
      asset
    end
  end

  def self.register_artifact(execution:, event:)
    app = execution.notebook_session.notebook.app
    payload = event.envelope.fetch("payload")
    reference = payload.fetch("blob")
    bytes = for_app(app).read(reference)
    filename = payload.fetch("filename")
    mime_type = Marcel::MimeType.for(StringIO.new(bytes), name: filename)
    asset = Asset.create_or_find_by!(runner_event: event) do |record|
      record.assign_attributes(app:, execution:, filename:, mime_type:,
        sha256: reference.fetch("sha256"), byte_size: reference.fetch("size"))
    end
    unless asset.app_id == app.id && asset.execution_id == execution.id && asset.reference == reference
      raise Rubellum::BlobStore::Invalid, "Artifact identity was reused"
    end
    asset
  end
end
