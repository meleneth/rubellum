class AssetReferences
  def self.validate!(app_id:, configuration:, source: "")
    raise ArgumentError, "Configuration must be an object" unless configuration.is_a?(Hash)
    ids = configuration.fetch("asset_ids", [])
    raise ArgumentError, "asset_ids must be an array" unless ids.is_a?(Array)
    ids = (ids + source.scan(%r{asset://([^\s)\]"<>]+)}).flatten).uniq
    unless ids.all? { |id| id.is_a?(String) && Rubellum::Message::UUID.match?(id) }
      raise ArgumentError, "Invalid asset identity"
    end
    existing = Asset.where(app_id:, id: ids).pluck(:id)
    raise ArgumentError, "Missing or cross-app asset reference" unless (ids - existing).empty?
  end
end
