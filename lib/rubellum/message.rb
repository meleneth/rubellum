# frozen_string_literal: true

require "json"
require_relative "json_value"

module Rubellum
  class Message
    class Invalid < ArgumentError; end

    MAX_BYTES = 64 * 1024
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
    COMMANDS = %w[execute interrupt restart stop acknowledge].freeze
    EVENTS = %w[runner_ready execution_accepted execution_started stdout stderr
                structured_output artifact execution_completed execution_failed
                execution_interrupted execution_cancelled execution_unknown heartbeat].freeze
    EXECUTION_KINDS = (EVENTS - %w[runner_ready heartbeat] + %w[execute interrupt]).freeze
    REQUIRED = %w[schema_version message_id kind app_installation_id notebook_id
                  session_id generation sequence payload].freeze
    OPTIONAL = %w[execution_id command_id].freeze

    # JSON normally keeps the last duplicate key. Reject ambiguous envelopes.
    class UniqueObject < Hash
      def []=(key, value)
        raise Invalid, "duplicate JSON key: #{key}" if key?(key)
        super
      end
    end
    private_constant :UniqueObject

    def self.parse(body)
      raise Invalid, "message must be a JSON string" unless body.is_a?(String)
      raise Invalid, "message size exceeds #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES
      new(JSON.parse(body, object_class: UniqueObject, max_nesting: 32))
    rescue JSON::ParserError, JSON::NestingError => error
      raise Invalid, "invalid message JSON: #{error.message}"
    end

    def initialize(attributes)
      raise Invalid, "message must be an object" unless attributes.is_a?(Hash)
      missing = REQUIRED - attributes.keys
      raise Invalid, "missing fields: #{missing.join(', ')}" unless missing.empty?
      extra = attributes.keys - REQUIRED - OPTIONAL
      raise Invalid, "unknown fields: #{extra.join(', ')}" unless extra.empty?
      @attributes = JsonValue.copy(attributes)
      validate!
      @json = JSON.generate(@attributes).freeze
      raise Invalid, "message size exceeds #{MAX_BYTES} bytes" if @json.bytesize > MAX_BYTES
      freeze
    rescue JsonValue::Invalid => error
      raise Invalid, error.message
    end

    def to_h = @attributes
    def to_json(*) = @json
    def [](key) = @attributes.fetch(key)
    def command? = COMMANDS.include?(self["kind"])

    private

    def validate!
      raise Invalid, "unsupported schema_version" unless self["schema_version"].eql?(1)
      raise Invalid, "unknown kind" unless (COMMANDS + EVENTS).include?(self["kind"])
      %w[message_id app_installation_id notebook_id session_id].each { |field| validate_uuid!(field) }
      OPTIONAL.each { |field| validate_uuid!(field) if @attributes.key?(field) }
      validate_uuid!("execution_id") if EXECUTION_KINDS.include?(self["kind"])
      %w[generation sequence].each do |field|
        value = self[field]
        raise Invalid, "#{field} must be a positive integer" unless value.is_a?(Integer) && value.positive?
      end
      raise Invalid, "payload must be an object" unless self["payload"].is_a?(Hash)
    end

    def validate_uuid!(field)
      value = @attributes[field]
      raise Invalid, "#{field} must be a lowercase UUID" unless value.is_a?(String) && UUID.match?(value)
    end
  end
end
