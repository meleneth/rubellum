# frozen_string_literal: true
require "json"
require_relative "json_value"

module Rubellum
  class NotebookApi
    MAX_OUTPUT_BYTES = 16 * 1024
    attr_reader :inputs

    def initialize(artifact_writer: nil)
      @artifact_writer = artifact_writer
    end

    def configure(inputs:, datasets:, &emit)
      raise ArgumentError, "inputs and datasets must be objects" unless inputs.is_a?(Hash) && datasets.is_a?(Hash)
      @inputs = JsonValue.copy(inputs)
      @datasets = JsonValue.copy(datasets)
      @emit = emit
      @artifact_writer&.reset
    end

    def dataset(name)
      @datasets.fetch(name)
    end

    def emit(name, data:)
      raise ArgumentError, "output name must be 1–100 letters, digits, underscores or hyphens" unless name.is_a?(String) && /\A[a-zA-Z0-9_-]{1,100}\z/.match?(name)
      payload = { "name" => name, "data" => JsonValue.copy(data) }
      raise ArgumentError, "structured output exceeds #{MAX_OUTPUT_BYTES} bytes" if JSON.generate(payload).bytesize > MAX_OUTPUT_BYTES
      @emit.call("structured_output", payload)
      nil
    end

    def display(value, mime: "text/plain")
      raise ArgumentError, "display currently accepts text/plain strings" unless mime == "text/plain" && value.is_a?(String)
      raise ArgumentError, "display exceeds #{MAX_OUTPUT_BYTES} bytes" if value.bytesize > MAX_OUTPUT_BYTES
      @emit.call("display", { "mime" => mime, "value" => JsonValue.copy(value) })
      nil
    end

    def asset(path, mime: nil)
      raise ArgumentError, "Artifact storage is not configured for this evaluator" unless @artifact_writer
      reference = @artifact_writer.call(path, mime:)
      @emit.call("artifact", reference)
      reference
    end
  end
end
