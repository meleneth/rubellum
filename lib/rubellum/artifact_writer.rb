# frozen_string_literal: true
require_relative "blob_store"

module Rubellum
  class ArtifactWriter
    MAX_COUNT = 32
    MAX_TOTAL_BYTES = 100 * 1024 * 1024
    MIME_TYPES = { ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
      ".gif" => "image/gif", ".webp" => "image/webp", ".avif" => "image/avif", ".svg" => "image/svg+xml",
      ".txt" => "text/plain", ".csv" => "text/csv", ".json" => "application/json", ".pdf" => "application/pdf" }.freeze

    def initialize(store:, workspace:)
      @store, @workspace = store, File.realpath(workspace)
      reset
    end

    def reset
      @count = @bytes = 0
    end

    def call(relative_path, mime: nil)
      unless relative_path.is_a?(String) && !relative_path.empty? && relative_path.valid_encoding? &&
          !relative_path.match?(%r{[\\\x00-\x1f\x7f]}) && !relative_path.start_with?("/") &&
          relative_path.split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
        raise ArgumentError, "Artifact path must be a relative workspace file without traversal"
      end
      path = @workspace
      relative_path.split("/").each do |part|
        path = File.join(path, part)
        raise ArgumentError, "Artifact path cannot follow symbolic links" if File.symlink?(path)
      end
      filename = File.basename(path)
      raise ArgumentError, "Artifact filename exceeds 255 characters" if filename.length > 255
      mime ||= MIME_TYPES.fetch(File.extname(filename).downcase, "application/octet-stream")
      raise ArgumentError, "Invalid artifact MIME type" unless mime.is_a?(String) && %r{\A[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+\z}.match?(mime)
      raise BlobStore::Full, "Execution artifact limit is #{MAX_COUNT} files" if @count >= MAX_COUNT
      File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
        raise ArgumentError, "Artifacts must be regular files" unless file.stat.file?
        raise BlobStore::Full, "Execution artifacts exceed #{MAX_TOTAL_BYTES} bytes" if @bytes + file.stat.size > MAX_TOTAL_BYTES
        reference = @store.put(file)
        @count += 1
        @bytes += reference.fetch("size")
        raise BlobStore::Full, "Execution artifacts exceed #{MAX_TOTAL_BYTES} bytes" if @bytes > MAX_TOTAL_BYTES
        JsonValue.copy({ "filename" => filename, "mime" => mime, "blob" => reference })
      end
    rescue Errno::ENOENT, Errno::ELOOP => error
      raise ArgumentError, "Artifact file is missing or unsafe: #{error.class}"
    end
  end
end
