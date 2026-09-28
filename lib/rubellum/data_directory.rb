# frozen_string_literal: true
require "fileutils"
require "securerandom"

module Rubellum
  class DataDirectory
    POSTGRES_MAJOR = "17"
    DIRECTORIES = %w[postgres redis apps bundles runtime config backups].freeze

    def initialize(root:)
      @root = File.expand_path(root)
    end

    def prepare
      DIRECTORIES.each { |name| FileUtils.mkdir_p(File.join(@root, name), mode: 0o700) }
      version = File.join(@root, "postgres/PG_VERSION")
      if File.exist?(version) && File.read(version).strip != POSTGRES_MAJOR
        raise "PostgreSQL major mismatch: expected #{POSTGRES_MAJOR}; back up and follow the upgrade procedure"
      end
      secret = File.join(@root, "config/secret_key_base")
      unless File.exist?(secret)
        temporary = "#{secret}.#{SecureRandom.hex(8)}"
        begin
          File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            file.write(SecureRandom.hex(64))
            file.fsync
          end
          File.link(temporary, secret)
          File.open(File.dirname(secret)) { |directory| directory.fsync }
        rescue Errno::EEXIST
          # A concurrent prepare already installed the secret.
        ensure
          File.unlink(temporary) if File.exist?(temporary)
        end
      end
      raise "Invalid persisted Rails secret" unless File.read(secret).match?(/\A[0-9a-f]{128}\z/)
      File.chmod(0o600, secret)
    end
  end
end
