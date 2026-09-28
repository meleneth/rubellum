require_relative "json_value"

module Rubellum
  class Parameters
    TYPES = %w[text number boolean select slider].freeze
    attr_reader :definitions

    def initialize(definitions)
      raise ArgumentError, "parameter definitions must be an array" unless definitions.is_a?(Array)
      @definitions = JsonValue.copy(definitions)
      names = definitions.map do |definition|
        raise ArgumentError, "invalid parameter definition" unless definition.is_a?(Hash) && TYPES.include?(definition["type"]) && definition["name"].is_a?(String) && /\A[a-zA-Z_][a-zA-Z0-9_]*\z/.match?(definition["name"])
        if definition["type"] == "select" && (!definition["options"].is_a?(Array) || definition["options"].empty?)
          raise ArgumentError, "select parameters require options"
        end
        definition.fetch("name")
      end
      raise ArgumentError, "duplicate parameter names" unless names.uniq == names
    end

    def values(supplied = {})
      raise ArgumentError, "parameter values must be an object" unless supplied.is_a?(Hash)
      unknown = supplied.keys - definitions.map { |item| item.fetch("name") }
      raise ArgumentError, "unknown parameters: #{unknown.join(', ')}" unless unknown.empty?
      definitions.to_h do |definition|
        name = definition.fetch("name")
        value = supplied.fetch(name) { definition.fetch("default", default_for(definition.fetch("type"))) }
        [name, validate(definition, value)]
      end
    end

    private

    def default_for(type)
      { "text" => "", "number" => 0, "slider" => 0, "boolean" => false }[type]
    end

    def validate(definition, value)
      case definition.fetch("type")
      when "number", "slider"
        number = Float(value)
        raise ArgumentError, "#{definition['name']} must be finite" unless number.finite?
        raise ArgumentError, "#{definition['name']} is below its minimum" if definition.key?("min") && number < Float(definition["min"])
        raise ArgumentError, "#{definition['name']} exceeds its maximum" if definition.key?("max") && number > Float(definition["max"])
        number
      when "boolean"
        raise ArgumentError, "#{definition['name']} must be boolean" unless [true, false, "true", "false"].include?(value)
        value == true || value == "true"
      when "select"
        choice = definition.fetch("options").find { |option| option.to_s == value.to_s }
        raise ArgumentError, "#{definition['name']} is not an allowed option" if choice.nil?
        choice
      when "text"
        raise ArgumentError, "#{definition['name']} must be text" unless value.is_a?(String) && value.bytesize <= 4096
        value
      end
    rescue TypeError
      raise ArgumentError, "#{definition['name']} has an invalid value"
    end
  end
end
