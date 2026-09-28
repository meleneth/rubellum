# frozen_string_literal: true
require_relative "notebook_api"
require_relative "message"

module Rubellum
  class RubyEvaluator
    MAX_INSPECT_BYTES = 16 * 1024

    def initialize
      @api = NotebookApi.new
      context = Class.new
      context.const_set(:Notebook, @api)
      context.class_eval("def context_binding; binding; end", __FILE__, __LINE__)
      @binding = context.new.context_binding
    end

    def call(source:, cell_id:, inputs: {}, datasets: {}, &events)
      raise ArgumentError, "invalid cell identity" unless cell_id.is_a?(String) && Message::UUID.match?(cell_id)
      raise ArgumentError, "source must be a string" unless source.is_a?(String)
      @api.configure(inputs:, datasets:, &events)
      value = @binding.eval(source, "cell:#{cell_id}", 1)
      inspected = value.inspect
      { "kind" => "execution_completed", "payload" => {
        "inspection" => inspected.byteslice(0, MAX_INSPECT_BYTES).force_encoding(Encoding::UTF_8).scrub,
        "inspection_truncated" => inspected.bytesize > MAX_INSPECT_BYTES
      } }
    rescue SyntaxError, StandardError => error
      { "kind" => "execution_failed", "payload" => {
        "error_class" => error.class.name,
        "message" => error.message.to_s.byteslice(0, 4096).force_encoding(Encoding::UTF_8).scrub,
        "backtrace" => Array(error.backtrace).grep(/\Acell:/).first(20)
      } }
    rescue Interrupt
      { "kind" => "execution_interrupted", "payload" => { "message" => "Interrupted; Ruby state may be partially changed" } }
    end
  end
end
