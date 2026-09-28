# frozen_string_literal: true
require "digest"
require "tempfile"
require_relative "message"

module Rubellum
  # Content addresses, not filenames, identify committed bytes. No overwrite or
  # delete API: retained history and execution references must remain readable.
  class BlobStore
    class Invalid < StandardError; end
    class Full < StandardError; end
    MAX_BYTES = 25 * 1024 * 1024
    APP_LIMIT = 512 * 1024 * 1024
    DIGEST = /\A[0-9a-f]{64}\z/
    CHUNK_BYTES = 64 * 1024

    def self.for_app(root:, app_id:)
      raise Invalid, "invalid app identity" unless Message::UUID.match?(app_id.to_s)
      new(directory: File.join(root, "apps", app_id, "blobs"))
    end

    def initialize(directory:, max_bytes: MAX_BYTES, quota: APP_LIMIT)
      raise ArgumentError, "invalid blob limits" unless max_bytes.positive? && quota >= max_bytes
      @directory, @max_bytes, @quota = File.expand_path(directory), max_bytes, quota
      prepare_directory(@directory)
    end

    def put(io, expected_digest: nil, expected_size: nil)
      validate_reference!("sha256" => expected_digest, "size" => expected_size) if expected_digest || expected_size
      File.open(File.join(@directory, ".lock"), File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        # The exclusive writer lock makes abandoned temporary files recoverable.
        Dir.children(@directory).grep(/\A\.incoming-.*\.blob\z/).each { |name| File.unlink(File.join(@directory, name)) }
        reference = Tempfile.create([".incoming-", ".blob"], @directory, binmode: true) do |temporary|
          digest, size = Digest::SHA256.new, 0
          while (chunk = io.read(CHUNK_BYTES))
            break if chunk.empty?
            size += chunk.bytesize
            raise Full, "Asset exceeds #{@max_bytes} bytes" if size > @max_bytes
            digest.update(chunk)
            temporary.write(chunk)
          end
          reference = { "sha256" => digest.hexdigest, "size" => size }
          if expected_digest && (expected_digest != reference["sha256"] || expected_size != size)
            raise Invalid, "Asset digest or size does not match"
          end
          destination = path(reference)
          if File.exist?(destination) || File.symlink?(destination)
            read(reference)
          else
            used = Dir.children(@directory).grep(DIGEST).sum { |name| File.lstat(File.join(@directory, name)).size }
            raise Full, "App immutable storage exceeds #{@quota} bytes; retained content was not removed" if used + size > @quota
            temporary.flush
            temporary.chmod(0o440)
            temporary.fsync
            File.link(temporary.path, destination)
            sync_directory
          end
          reference.freeze
        end
        sync_directory
        reference
      end
    rescue Errno::ELOOP
      raise Invalid, "Asset storage cannot follow symbolic links"
    end

    def read(reference)
      validate_reference!(reference)
      File.open(path(reference), File::RDONLY | File::NOFOLLOW) do |file|
        raise Invalid, "Asset size does not match" unless file.stat.file? && file.stat.size == reference.fetch("size")
        bytes = file.read(@max_bytes + 1)
        unless bytes.bytesize == reference.fetch("size") && Digest::SHA256.hexdigest(bytes) == reference.fetch("sha256")
          raise Invalid, "Asset digest or size does not match"
        end
        bytes
      end
    rescue Errno::ENOENT
      raise Invalid, "Asset bytes are missing"
    rescue Errno::ELOOP
      raise Invalid, "Asset storage cannot follow symbolic links"
    end

    private

    def validate_reference!(reference)
      unless reference.is_a?(Hash) && DIGEST.match?(reference["sha256"].to_s) &&
          reference["size"].is_a?(Integer) && reference["size"].between?(0, @max_bytes)
        raise Invalid, "Invalid asset reference"
      end
    end

    def path(reference)
      File.join(@directory, reference.fetch("sha256"))
    end

    def prepare_directory(directory)
      raise Invalid, "Asset storage cannot follow symbolic links" if File.symlink?(directory)
      return if File.directory?(directory)
      parent = File.dirname(directory)
      prepare_directory(parent)
      begin
        Dir.mkdir(directory, 0o700)
      rescue Errno::EEXIST
        raise Invalid, "Invalid asset storage directory" unless File.directory?(directory) && !File.symlink?(directory)
      end
      File.open(parent) { |file| file.fsync }
    end

    def sync_directory
      File.open(@directory) { |file| file.fsync }
    end
  end
end
