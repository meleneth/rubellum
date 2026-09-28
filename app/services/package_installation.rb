require "fileutils"

class PackageInstallation
  # This private namespace contains only generated installation UUIDs. A marker
  # survives publication until Postgres commits; recovery distinguishes both sides
  # of that commit without ever touching existing installations or user paths.
  def self.synchronize
    apps = File.join(ENV.fetch("RUBELLUM_DATA", "/data"), "apps")
    Rubellum::BlobStore.new(directory: File.join(apps, ".imports"))
    imports = File.join(apps, ".imports")
    File.open(File.join(imports, ".install-lock"), File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      yield new(apps, imports)
    end
  end

  def initialize(apps, imports)
    @apps, @imports = apps, imports
  end

  def recover!
    Dir.children(@imports).grep(Rubellum::Message::UUID).each { |id| cleanup(id) }
  end

  def stage(id)
    raise ArgumentError, "Invalid installation identity" unless Rubellum::Message::UUID.match?(id)
    raise ArgumentError, "Installation path already exists" if File.exist?(destination(id)) || File.symlink?(destination(id))
    Dir.mkdir(marker(id), 0o700)
    sync(@imports)
    Rubellum::BlobStore.new(directory: File.join(marker(id), "content", "blobs"))
  end

  def publish(id)
    raise ArgumentError, "Installation path already exists" if File.exist?(destination(id)) || File.symlink?(destination(id))
    File.rename(File.join(marker(id), "content"), destination(id))
    sync(marker(id))
    sync(@apps)
  end

  def cleanup(id)
    raise ArgumentError, "Invalid installation identity" unless Rubellum::Message::UUID.match?(id)
    return unless File.directory?(marker(id)) && !File.symlink?(marker(id))
    ApplicationRecord.transaction(requires_new: true) do
      lock_identity!(id)
      unless App.exists?(id:)
        FileUtils.remove_entry_secure(destination(id)) if File.exist?(destination(id)) || File.symlink?(destination(id))
        sync(@apps)
      end
      FileUtils.remove_entry_secure(marker(id))
      sync(@imports)
    end
  end

  def lock_identity!(id)
    # A dead client can leave COMMIT still finishing in Postgres. Wait for its
    # transaction lock before deciding whether published files are orphaned.
    connection = ApplicationRecord.connection
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote(id)}, 0))")
  end

  private

  def destination(id) = File.join(@apps, id)
  def marker(id) = File.join(@imports, id)
  def sync(path) = File.open(path, File::RDONLY, &:fsync)
end
