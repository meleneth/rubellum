class AppPackageImport
  class Collision < StandardError; end

  def self.call(io:, as_copy: false)
    files = Rubellum::PackageArchive.new.read(io)
    manifest = Rubellum::PackageManifest.load(files)
    new(manifest, files).install(as_copy:)
  end

  def self.recover!
    PackageInstallation.synchronize(&:recover!)
  end

  def initialize(manifest, files)
    @manifest, @files = manifest, files
    @ids, @records = {}, {}
    owners.each do |owner|
      @ids[owner["id"]] = SecureRandom.uuid
      owner["revisions"].each { |revision| @ids[revision["id"]] = SecureRandom.uuid }
    end
    manifest["assets"].each { |asset| @ids[asset["id"]] = SecureRandom.uuid }
  end

  def install(as_copy:)
    if App.connection.transaction_open?
      raise ArgumentError, "App installation must own its database transaction"
    end
    PackageInstallation.synchronize do |installation|
      installation.recover!
      if !as_copy && App.exists?(portable_id: @manifest["app"]["id"])
        raise Collision, "This app is already installed. Choose Import as copy or Cancel."
      end
      id = @ids.fetch(@manifest["app"]["id"])
      store = installation.stage(id)
      begin
        @manifest["assets"].each do |asset|
          store.put(StringIO.new(@files.fetch("assets/#{asset['sha256']}")),
            expected_digest: asset["sha256"], expected_size: asset["byte_size"])
        end
        app = App.transaction(requires_new: true) do
          installation.lock_identity!(id)
          app = create_owners
          @manifest["assets"].each do |asset|
            app.assets.create!(asset.except("id").merge("id" => @ids.fetch(asset["id"]), "portable_id" => asset["id"]))
          end
          # Cell revisions precede notebook entries; app landing references come last.
          (@manifest["cells"] + @manifest["notebooks"] + [@manifest["app"]]).each { |owner| create_revisions(owner) }
          installation.publish(id)
          app.reload
        end
        app
      ensure
        installation.cleanup(id)
      end
    end
  end

  private

  def owners = [@manifest["app"]] + @manifest["notebooks"] + @manifest["cells"]

  def create_owners
    source = @manifest["app"]
    app = App.create!(id: @ids.fetch(source["id"]), portable_id: source["id"])
    @records[source["id"]] = app
    @manifest["notebooks"].each do |notebook|
      @records[notebook["id"]] = app.notebooks.create!(id: @ids.fetch(notebook["id"]), portable_id: notebook["id"])
    end
    @manifest["cells"].each do |cell|
      notebook = @records.fetch(cell["notebook_id"])
      @records[cell["id"]] = notebook.cells.create!(id: @ids.fetch(cell["id"]), portable_id: cell["id"])
    end
    app
  end

  def create_revisions(owner)
    record = @records.fetch(owner["id"])
    children = owner["revisions"].group_by { |revision| revision["parent_id"] }
    pending = children.fetch(nil, []).dup
    index = 0
    while index < pending.size
      source = pending[index]
      revision = source.except("digest").deep_dup
      revision["id"] = @ids.fetch(source["id"])
      revision["parent_id"] = @ids.fetch(source["parent_id"]) if source["parent_id"]
      configuration = revision["configuration"]
      configuration["asset_ids"]&.map! { |id| @ids.fetch(id) }
      input = configuration["input"]
      input["cell_id"] = @ids.fetch(input["cell_id"]) if input
      revision["source"] = revision["source"].gsub(%r{asset://([0-9a-f-]+)}) { "asset://#{@ids.fetch(Regexp.last_match(1))}" } if revision.key?("source")
      revision["entries"]&.each do |entry|
        entry.transform_values! { |id| @ids.fetch(id) }
      end
      revision["landing_notebook_id"] = @ids.fetch(revision["landing_notebook_id"]) if revision["landing_notebook_id"]
      provenance = revision["provenance"]
      %w[restored_from notebook_revision].each { |key| provenance[key] = @ids.fetch(provenance[key]) if provenance[key] }
      # Source identity remains informational and is never used as a local key.
      provenance["imported_from"] = { "app_id" => @manifest["app"]["id"], "revision_id" => source["id"] }
      record.revisions.create!(revision)
      pending.concat(children.fetch(source["id"], []))
      index += 1
    end
    record.update!(head_revision_id: @ids.fetch(owner["head"]))
  end
end
