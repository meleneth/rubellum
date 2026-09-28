# frozen_string_literal: true

module Rubellum
  module JsonValue
    class Invalid < ArgumentError; end

    def self.copy(value, max_depth: 32, path: "$", depth: 0)
      raise Invalid, "#{path}: maximum JSON depth exceeded" if depth > max_depth

      child = ->(item, location) { copy(item, max_depth:, path: location, depth: depth + 1) }
      case value
      when Hash
        value.to_h do |key, item|
          raise Invalid, "#{path}: JSON object keys must be strings" unless key.is_a?(String)
          [copy(key), child.call(item, "#{path}.#{key}")]
        end.freeze
      when Array
        value.each_with_index.map { |item, index| child.call(item, "#{path}[#{index}]") }.freeze
      when String
        utf8 = value.encode(Encoding::UTF_8)
        raise Invalid, "#{path}: invalid UTF-8 string" unless utf8.valid_encoding?
        utf8.freeze
      when Integer, true, false, nil
        value
      when Float
        raise Invalid, "#{path}: JSON numbers must be finite" unless value.finite?
        value
      else
        raise Invalid, "#{path}: unsupported JSON type #{value.class}"
      end
    rescue EncodingError
      raise Invalid, "#{path}: invalid UTF-8 string"
    end
  end
end
