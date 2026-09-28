require "json"
require "csv"
require_relative "json_value"

module Rubellum
  module DataCell
    def self.parse(source, configuration = {})
      case configuration.fetch("format", "json")
      when "json"
        JsonValue.copy(JSON.parse(source, max_nesting: 32))
      when "csv"
        separator = configuration.fetch("delimiter", ",")
        raise ArgumentError, "CSV delimiter must be one character" unless separator.is_a?(String) && separator.length == 1
        rows = CSV.parse(source, col_sep: separator, headers: false, skip_blanks: configuration.fetch("skip_blanks", true))
        if configuration.fetch("headers", true) && !rows.empty?
          headers = rows.shift
          raise ArgumentError, "CSV headers must be present and unique" if headers.any?(&:nil?) || headers.uniq != headers
          rows = rows.map do |row|
            raise ArgumentError, "CSV row does not match header width" unless row.length == headers.length
            headers.zip(row).to_h
          end
        end
        JsonValue.copy(rows)
      else
        raise ArgumentError, "data format must be json or csv"
      end
    rescue CSV::MalformedCSVError => error
      raise ArgumentError, error.message
    end
  end
end
