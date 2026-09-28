class AppHistory
  FIELDS = %w[title description landing_notebook_id configuration].freeze

  def initialize(app)
    @app = app
  end

  def update(expected_revision:, attributes:, archived: nil, summary: "Update app metadata", provenance: {})
    attributes = attributes.to_h.stringify_keys
    raise ArgumentError, "Unknown app metadata field" unless (attributes.keys - FIELDS).empty?
    raise ArgumentError, "Archive state must be true or false" unless [true, false, nil].include?(archived)
    @app.with_lock do
      raise History::Conflict, "App metadata changed; reload before trying again" unless @app.head_revision_id == expected_revision
      previous = @app.head_revision
      content = previous.attributes.slice(*FIELDS).merge(attributes)
      landing = content["landing_notebook_id"].presence
      @app.notebooks.find(landing) if landing
      content["landing_notebook_id"] = landing
      revision = @app.revisions.create!(**content, parent_id: previous.id, summary:, provenance:)
      archive_time = archived.nil? ? @app.archived_at : (archived ? @app.archived_at || Time.current : nil)
      @app.update!(head_revision: revision, archived_at: archive_time)
      revision
    end
  end

  def restore(revision_id:, expected_revision:)
    historical = @app.revisions.find(revision_id)
    update(expected_revision:, attributes: historical.attributes.slice(*FIELDS),
      summary: "Restore earlier app metadata", provenance: { "restored_from" => historical.id })
  end
end
