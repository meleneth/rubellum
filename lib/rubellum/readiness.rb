# frozen_string_literal: true

module Rubellum
  class Readiness
    def initialize(checks:)
      raise ArgumentError, "readiness needs at least one dependency" if checks.empty?
      @checks = checks
    end

    def call
      services = @checks.transform_values do |check|
        check.call ? "ready" : "unavailable"
      rescue StandardError
        "unavailable"
      end
      { ready: services.values.all?("ready"), services: }
    end
  end
end
