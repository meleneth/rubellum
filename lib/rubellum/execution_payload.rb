# frozen_string_literal: true
require "json"
require "stringio"
require_relative "blob_store"

module Rubellum
  module ExecutionPayload
    class Invalid < ArgumentError; end
    INLINE_BYTES = 32 * 1024
    MAX_BYTES = 8 * 1024 * 1024

    def self.pack(payload, store:)
      encoded = JSON.generate(JsonValue.copy(payload))
      raise Invalid, "Execution payload exceeds #{MAX_BYTES} bytes" if encoded.bytesize > MAX_BYTES
      return payload if encoded.bytesize <= INLINE_BYTES
      { "payload_ref" => store.put(StringIO.new(encoded)), "batch_id" => payload["batch_id"] }
    end

    def self.unpack(payload, store:)
      return payload unless payload.key?("payload_ref")
      reference = payload.fetch("payload_ref")
      unless store && (payload.keys - %w[payload_ref batch_id]).empty? && reference.is_a?(Hash) &&
          reference["size"].is_a?(Integer) && reference["size"].between?(1, MAX_BYTES)
        raise Invalid, "Invalid execution payload reference"
      end
      result = JsonValue.copy(JSON.parse(store.read(reference), max_nesting: 32))
      unless result.is_a?(Hash) && !result.key?("payload_ref") && result["batch_id"] == payload["batch_id"]
        raise Invalid, "Execution payload metadata does not match"
      end
      result
    rescue BlobStore::Invalid, JSON::ParserError => error
      raise Invalid, error.message
    end
  end
end
