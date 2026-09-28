# frozen_string_literal: true
require "json"
require "digest"
require "time"
require_relative "json_value"
require_relative "message"

module Rubellum
  # The executable schema for package format 1. No Rails, evaluation or file writes.
  class PackageManifest
    class Invalid < ArgumentError; end
    MAX_BYTES = 16 * 1024 * 1024
    TYPES = %w[markdown ruby d3 data table parameters].freeze
    COMMON = %w[id parent_id title configuration author summary provenance created_at digest].freeze
    UUID = Message::UUID
    SHA = /\A[0-9a-f]{64}\z/

    class UniqueObject < Hash
      def []=(key, value)
        raise Invalid, "Duplicate JSON key: #{key}" if key?(key)
        super
      end
    end

    def self.digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end

    def self.canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def self.load(files)
      encoded = files.fetch("manifest.json") { raise Invalid, "Missing manifest.json" }
      raise Invalid, "Manifest exceeds limit" if encoded.bytesize > MAX_BYTES
      manifest = JsonValue.copy(JSON.parse(encoded, object_class: UniqueObject, max_nesting: 32))
      new(manifest, files).validate!
      manifest
    rescue JSON::ParserError, JsonValue::Invalid => error
      raise Invalid, error.message
    end

    def initialize(manifest, files)
      @manifest, @files = manifest, files
      @identities, @owners, @revisions, @assets = {}, {}, {}, {}
    end

    def validate!
      object!(@manifest, %w[format_version cell_api_version mode app notebooks cells assets files])
      fail!("Unsupported package or cell API version") unless @manifest["format_version"] == 1 && @manifest["cell_api_version"] == 1
      fail!("Invalid export mode") unless %w[full current].include?(@manifest["mode"])
      array!(@manifest["notebooks"])
      array!(@manifest["cells"])
      array!(@manifest["assets"])
      owner!(@manifest["app"], :app)
      @manifest["notebooks"].each { |owner| owner!(owner, :notebook) }
      @manifest["cells"].each { |owner| owner!(owner, :cell) }
      @manifest["assets"].each { |asset| asset!(asset) }
      @owners.each_value { |owner, type| references!(owner, type) }
      files!
      true
    end

    private

    def owner!(owner, type)
      object!(owner, %w[id head revisions] + (type == :cell ? %w[notebook_id source_path] : []))
      identity!(owner["id"])
      @owners[owner["id"]] = [owner, type]
      array!(owner["revisions"])
      fail!("Missing revision history") if owner["revisions"].empty?
      if @manifest["mode"] == "current" && owner["revisions"].size != 1
        fail!("Current-state packages contain one parentless revision per object")
      end
      own = {}
      owner["revisions"].each do |revision|
        fields = type == :cell ? %w[cell_type source] : %w[description]
        fields += %w[entries] if type == :notebook
        fields += %w[landing_notebook_id] if type == :app
        object!(revision, COMMON + fields)
        fail!("Current-state revisions must be parentless") if @manifest["mode"] == "current" && revision["parent_id"]
        identity!(revision["id"])
        uuid!(revision["parent_id"]) if revision["parent_id"]
        %w[title author summary].each { |field| string!(revision[field]) }
        fail!("Missing author or title") if revision["author"].empty? || (type != :cell && revision["title"].strip.empty?)
        %w[configuration provenance].each { |field| fail!("Expected #{field} object") unless revision[field].is_a?(Hash) }
        string!(revision["created_at"])
        Time.iso8601(revision["created_at"])
        fail!("Revision digest mismatch") unless revision["digest"] == self.class.digest(revision.reject { |key, _| key == "digest" })
        if type == :cell
          fail!("Unknown cell type") unless TYPES.include?(revision["cell_type"])
          string!(revision["source"], limit: 1_048_576)
        else
          string!(revision["description"])
        end
        own[revision["id"]] = revision
        @revisions[revision["id"]] = [revision, owner["id"]]
      end
      fail!("Missing or foreign head revision") unless own.key?(owner["head"])
      own.each_value { |revision| fail!("Missing or foreign revision parent") if revision["parent_id"] && !own.key?(revision["parent_id"]) }
      checked = {}
      own.each_key do |id|
        chain = {}
        while id && !checked[id]
          fail!("Cyclic revision ancestry") if chain[id]
          chain[id] = true
          id = own.fetch(id)["parent_id"]
        end
        checked.merge!(chain)
      end
    rescue ArgumentError => error
      raise Invalid, error.message
    end

    def references!(owner, type)
      if type == :cell
        fail!("Missing owning notebook") unless @owners.dig(owner["notebook_id"], 1) == :notebook
        fail!("Invalid source path") unless /\Asources\/[0-9a-f-]+\.(md|rb|js|json|csv)\z/.match?(owner["source_path"].to_s)
        fail!("Current source file mismatch") unless @files[owner["source_path"]]&.b == @revisions.fetch(owner["head"]).first["source"].b
      end
      owner["revisions"].each do |revision|
        configuration = revision["configuration"]
        asset_ids = configuration.fetch("asset_ids", [])
        array!(asset_ids)
        source_ids = type == :cell ? revision["source"].scan(%r{asset://([^\s)\]"<>]+)}).flatten : []
        (asset_ids + source_ids).each { |id| fail!("Missing asset reference") unless @assets.key?(id) }
        if configuration.key?("input")
          input = configuration["input"]
          fail!("Invalid renderer input") unless input.is_a?(Hash) && @owners.dig(input["cell_id"], 1) == :cell
          string!(input["output"]) if input.key?("output")
        end
        provenance = revision["provenance"]
        if provenance["restored_from"]
          fail!("Missing restore provenance") unless @revisions.dig(provenance["restored_from"], 1) == owner["id"]
        end
        if provenance["notebook_revision"]
          fail!("Missing notebook provenance") unless type == :cell && @revisions.dig(provenance["notebook_revision"], 1) == owner["notebook_id"]
        end
        if type == :app && revision["landing_notebook_id"]
          fail!("Missing landing notebook") unless @owners.dig(revision["landing_notebook_id"], 1) == :notebook
        elsif type == :notebook
          array!(revision["entries"])
          seen = {}
          revision["entries"].each do |entry|
            object!(entry, %w[cell_id revision_id])
            cell = @owners.dig(entry["cell_id"], 0)
            unless cell && cell["notebook_id"] == owner["id"] && @revisions.dig(entry["revision_id"], 1) == cell["id"] && !seen[cell["id"]]
              fail!("Missing, duplicate or foreign notebook entry")
            end
            seen[cell["id"]] = true
          end
        end
      end
    end

    def asset!(asset)
      @assets ||= {}
      object!(asset, %w[id filename mime_type sha256 byte_size created_at])
      identity!(asset["id"])
      string!(asset["filename"], limit: 255)
      fail!("Invalid asset filename") if asset["filename"].empty? || asset["filename"].match?(%r{[/\\\x00-\x1f\x7f]})
      fail!("Invalid MIME type") unless asset["mime_type"].is_a?(String) && %r{\A[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+\z}.match?(asset["mime_type"])
      fail!("Invalid asset digest") unless asset["sha256"].is_a?(String) && SHA.match?(asset["sha256"])
      fail!("Invalid asset size") unless asset["byte_size"].is_a?(Integer) && asset["byte_size"].between?(0, 25 * 1024 * 1024)
      string!(asset["created_at"])
      Time.iso8601(asset["created_at"])
      bytes = @files["assets/#{asset['sha256']}"]
      fail!("Missing or corrupt asset") unless bytes && bytes.bytesize == asset["byte_size"] && Digest::SHA256.hexdigest(bytes) == asset["sha256"]
      @assets[asset["id"]] = asset
    rescue ArgumentError => error
      raise Invalid, error.message
    end

    def files!
      inventory = @manifest["files"]
      fail!("Invalid file inventory") unless inventory.is_a?(Hash)
      required = @manifest["cells"].map { |cell| cell["source_path"] } + @manifest["assets"].map { |asset| "assets/#{asset['sha256']}" }
      fail!("Unexpected or missing package files") unless inventory.keys.sort == required.uniq.sort && @files.keys.sort == (inventory.keys + ["manifest.json"]).sort
      inventory.each do |path, reference|
        object!(reference, %w[sha256 size])
        bytes = @files.fetch(path)
        fail!("File checksum mismatch") unless reference["size"] == bytes.bytesize && reference["sha256"] == Digest::SHA256.hexdigest(bytes)
      end
    end

    def identity!(id)
      uuid!(id)
      fail!("Duplicate package identity") if @identities[id]
      @identities[id] = true
    end

    def uuid!(id)
      fail!("Invalid UUID") unless id.is_a?(String) && UUID.match?(id)
    end

    def object!(value, fields)
      fail!("Unexpected or missing object fields") unless value.is_a?(Hash) && value.keys.sort == fields.sort
    end

    def array!(value)
      fail!("Expected array") unless value.is_a?(Array)
    end

    def string!(value, limit: MAX_BYTES)
      fail!("Invalid or oversized UTF-8 string") unless value.is_a?(String) && value.valid_encoding? && value.bytesize <= limit && !value.include?("\0")
    end

    def fail!(message)
      raise Invalid, message
    end
  end
end
