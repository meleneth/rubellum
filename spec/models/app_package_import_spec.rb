require "rails_helper"
require_relative "../support/committed_database"

RSpec.describe AppPackageImport, type: :model do
  include_context "committed database"
  let(:notebook) { create(:notebook) }
  let(:app) { notebook.app }
  let(:history) { History.new(notebook) }

  def add(type, source, configuration = {})
    history.add_cell(cell_type: type, source:, configuration:, expected_notebook_revision: notebook.reload.head_revision_id)
  end

  def package(mode: "full")
    AppPackageExport.call(app: app.reload, mode:)
  end

  def import(bytes, **options)
    described_class.call(io: StringIO.new(bytes), **options)
  end

  it "installs two independent copies with history, references and immutable asset bytes" do
    asset = create(:asset, app:, bytes: "\x00\xff".b)
    markdown = add("markdown", "# λ\n![file](asset://#{asset.id})", { "asset_ids" => [asset.id] })
    ruby = add("ruby", "raise 'do not execute'")
    chart = add("d3", "throw new Error('do not execute')", { "input" => { "cell_id" => ruby.id, "output" => "rows" } })
    original = markdown.head_revision
    history.save_cell(cell_id: markdown.id, expected_revision: original.id, source: "changed", title: "Changed", cell_type: "markdown")
    history.restore_cell(cell_id: markdown.id, revision_id: original.id, expected_revision: markdown.reload.head_revision_id)
    bytes = package
    copies = 2.times.map { import(bytes, as_copy: true) }
    expect(copies.map(&:id).uniq.size).to eq(2)
    copies.each do |copy|
      expect(copy.portable_id).to eq(app.portable_id)
      page = copy.notebooks.sole
      expect(page.portable_id).to eq(notebook.portable_id)
      expect(page.revisions.count).to eq(notebook.revisions.count)
      cells = page.cells.index_by(&:portable_id)
      cloned = cells.fetch(markdown.portable_id)
      copied_asset = copy.assets.sole
      expect(cloned.head_revision.source).to eq("# λ\n![file](asset://#{copied_asset.id})")
      expect(AssetStorage.for_app(copy).read(copied_asset.reference)).to eq("\x00\xff".b)
      expect(copied_asset.portable_id).to eq(asset.portable_id)
      expect(cloned.revisions.count).to eq(3)
      restored = cloned.head_revision.provenance.fetch("restored_from")
      expect(cloned.revisions.find(restored).source).to eq(cloned.head_revision.source)
      expect(cloned.head_revision.provenance.fetch("imported_from")).to include("revision_id" => markdown.reload.head_revision_id)
      expect(cells.fetch(chart.portable_id).head_revision.configuration.dig("input", "cell_id")).to eq(cells.fetch(ruby.portable_id).id)
      expect(page.head_revision.entries.map { |entry| entry["cell_id"] }).to eq([markdown, ruby, chart].map { |cell| cells.fetch(cell.portable_id).id })
      expect { copied_asset.update!(filename: "overwrite") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      # Re-export validates remapped restore pointers and preserves portable identity.
      round_trip = Rubellum::PackageArchive.new.read(StringIO.new(AppPackageExport.call(app: copy)))
      expect(Rubellum::PackageManifest.load(round_trip)["app"]["id"]).to eq(app.portable_id)
    end
    expect(Execution.count).to eq(0)
    expect(OutboxMessage.count).to eq(0)
    expect(NotebookSession.count).to eq(0)
  end

  it "requires explicit copy on collision and never changes the existing app" do
    add("markdown", "Original")
    bytes = package
    expect { import(bytes) }.to raise_error(described_class::Collision, /Import as copy/)
    expect(App.count).to eq(1)
    expect(notebook.cells.sole.head_revision.source).to eq("Original")
  end

  it "installs new identities and current-only exports without restoring removed content" do
    removed = add("ruby", "removed")
    history.remove_cell(cell_id: removed.id, expected_notebook_revision: notebook.reload.head_revision_id)
    add("markdown", "kept")
    files = Rubellum::PackageArchive.new.read(StringIO.new(package(mode: "current"))).dup
    manifest = JSON.parse(files["manifest.json"])
    manifest["app"]["id"] = SecureRandom.uuid
    files["manifest.json"] = JSON.generate(manifest)
    imported = import(Rubellum::PackageArchive.new.write(files))
    expect(imported.notebooks.sole.cells.sole.head_revision.source).to eq("kept")
    expect(imported.notebooks.sole.revisions.count).to eq(1)
  end

  it "validates complete packages before writing any installation or database record" do
    asset = create(:asset, app:, bytes: "original")
    files = Rubellum::PackageArchive.new.read(StringIO.new(package)).dup
    files["assets/#{asset.sha256}"] = "tampered"
    existing = Dir.glob(File.join(ENV.fetch("RUBELLUM_DATA"), "apps", "*"))
    expect { import(Rubellum::PackageArchive.new.write(files), as_copy: true) }.to raise_error(Rubellum::PackageManifest::Invalid, /asset/)
    expect(App.count).to eq(1)
    expect(Dir.glob(File.join(ENV.fetch("RUBELLUM_DATA"), "apps", "*"))).to eq(existing)
  end

  it "rolls back records and published files when the database transaction fails" do
    create(:asset, app:, bytes: "original")
    bytes = package
    existing = Dir.glob(File.join(ENV.fetch("RUBELLUM_DATA"), "apps", "*"))
    allow(App).to receive(:transaction).and_wrap_original do |transaction, **options, &work|
      transaction.call(**options) do
        work.call
        raise IOError, "commit boundary failure"
      end
    end
    expect { import(bytes, as_copy: true) }.to raise_error(IOError, /commit boundary/)
    expect(App.count).to eq(1)
    expect(Dir.glob(File.join(ENV.fetch("RUBELLUM_DATA"), "apps", "*"))).to eq(existing)
    expect(Dir.children(File.join(ENV.fetch("RUBELLUM_DATA"), "apps/.imports")).grep(Rubellum::Message::UUID)).to be_empty
  end

  it "recovers abandoned staging/publication but preserves a committed installation" do
    alive = create(:app)
    abandoned, published = SecureRandom.uuid, SecureRandom.uuid
    PackageInstallation.synchronize do |installation|
      [abandoned, published, alive.id].each do |id|
        installation.stage(id).put(StringIO.new("kept only after commit"))
        installation.publish(id) unless id == abandoned
      end
    end
    described_class.recover!
    root = File.join(ENV.fetch("RUBELLUM_DATA"), "apps")
    expect(File.exist?(File.join(root, abandoned))).to be(false)
    expect(File.exist?(File.join(root, published))).to be(false)
    expect(Dir.children(File.join(root, ".imports")).grep(Rubellum::Message::UUID)).to be_empty
    expect(Dir.children(File.join(root, alive.id, "blobs")).grep(Rubellum::BlobStore::DIGEST).size).to eq(1)
  end

  it "refuses to expose a package inside a caller-owned uncommitted transaction" do
    bytes = package
    App.transaction do
      expect { import(bytes, as_copy: true) }.to raise_error(ArgumentError, /own.*transaction/)
    end
  end

  it "waits for an in-flight database commit before deciding published files are orphaned" do
    id = SecureRandom.uuid
    ready, finish, observer = Queue.new, Queue.new, Queue.new
    PackageInstallation.synchronize do |installation|
      installation.stage(id).put(StringIO.new("must survive commit"))
      installation.publish(id)
      writer = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          App.transaction do
            installation.lock_identity!(id)
            create(:app, id:)
            ready << true
            finish.pop
          end
        end
      end
      ready.pop
      recovery = Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          observer << connection.select_value("SELECT pg_backend_pid()")
          installation.cleanup(id)
        end
      end
      pid = observer.pop
      Timeout.timeout(5) do
        until ApplicationRecord.connection.select_value("SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = #{Integer(pid)} AND locktype = 'advisory' AND NOT granted)")
          Thread.pass
        end
      end
      finish << true
      writer.value
      recovery.value
      expect(App.exists?(id:)).to be(true)
      expect(File.directory?(File.join(ENV.fetch("RUBELLUM_DATA"), "apps", id, "blobs"))).to be(true)
    ensure
      finish << true
      writer&.join
      recovery&.join
    end
  end
end
