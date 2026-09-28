class AppPackageExport
  def self.call(app:, mode: "full")
    new(app, mode).call
  end

  def initialize(app, mode)
    @app, @mode = app, mode
    @files, @ids = {}, {}
  end

  def call
    # Lock the app, then every notebook, matching the app -> notebook import order.
    # Normal edits take the notebook lock; uploads take the app lock.
    @app.with_lock do
      notebooks = @app.notebooks.order(:id).lock.to_a
      cells = notebooks.flat_map { |notebook| notebook.cells.order(:id).to_a }
      assets = @app.assets.order(:id).to_a
      ([@app] + notebooks + cells + assets).each { |record| @ids[record.id] = record.portable_id }
      if @mode == "current"
        selected = notebooks.flat_map { |notebook| notebook.head_revision.entries.map { |entry| entry["cell_id"] } }
        cells.select! { |cell| selected.include?(cell.id) }
      end
      manifest = { "format_version" => 1, "cell_api_version" => 1, "mode" => @mode,
        "app" => owner(@app, :app), "notebooks" => notebooks.map { |record| owner(record, :notebook) },
        "cells" => cells.map { |record| owner(record, :cell) }, "assets" => assets.map { |record| asset(record) } }
      manifest["files"] = @files.transform_values { |bytes| { "sha256" => Digest::SHA256.hexdigest(bytes), "size" => bytes.bytesize } }
      @files["manifest.json"] = JSON.pretty_generate(manifest)
      Rubellum::PackageManifest.load(@files)
      Rubellum::PackageArchive.new.write(@files)
    end
  rescue KeyError => error
    raise Rubellum::PackageManifest::Invalid, "Missing package reference: #{error.key}"
  end

  private

  def owner(record, type)
    revisions = @mode == "current" ? [record.head_revision] : record.revisions.order(:created_at, :id).to_a
    result = { "id" => record.portable_id, "head" => record.head_revision_id,
      "revisions" => revisions.map { |revision| revision_content(revision, type) } }
    if type == :cell
      result["notebook_id"] = @ids.fetch(record.notebook_id)
      head = result["revisions"].find { |revision| revision["id"] == result["head"] }
      extension = { "markdown" => "md", "ruby" => "rb", "d3" => "js", "table" => "json", "parameters" => "json" }.fetch(head["cell_type"], head["configuration"].fetch("format", "json"))
      result["source_path"] = "sources/#{record.portable_id}.#{extension}"
      @files[result["source_path"]] = head["source"]
    end
    result
  end

  def revision_content(revision, type)
    fields = %w[id parent_id title configuration author summary provenance]
    fields += type == :cell ? %w[cell_type source] : %w[description]
    fields += %w[entries] if type == :notebook
    fields += %w[landing_notebook_id] if type == :app
    value = revision.attributes.slice(*fields).deep_dup
    value["created_at"] = revision.created_at.iso8601(6)
    value["configuration"] = map_configuration(value["configuration"])
    value["source"] = value["source"].gsub(%r{asset://([0-9a-f-]+)}) { "asset://#{@ids.fetch(Regexp.last_match(1))}" } if type == :cell
    value["entries"]&.each { |entry| entry["cell_id"] = @ids.fetch(entry["cell_id"]) }
    value["landing_notebook_id"] = @ids.fetch(value["landing_notebook_id"]) if value["landing_notebook_id"]
    if @mode == "current"
      value["parent_id"] = nil
      value["provenance"] = { "source_revision" => revision.id }
    end
    value["digest"] = Rubellum::PackageManifest.digest(value)
    value
  end

  def map_configuration(configuration)
    configuration["asset_ids"]&.map! { |id| @ids.fetch(id) }
    input = configuration["input"]
    input["cell_id"] = @ids.fetch(input["cell_id"]) if input
    configuration
  end

  def asset(record)
    @files["assets/#{record.sha256}"] ||= AssetStorage.for_app(@app).read(record.reference)
    record.attributes.slice("filename", "mime_type", "sha256", "byte_size").merge(
      "id" => record.portable_id, "created_at" => record.created_at.iso8601(6))
  end
end
