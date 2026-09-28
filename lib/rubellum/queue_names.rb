require_relative "message"

module Rubellum
  module QueueNames
    EVENTS = "rubellum-runner-events-v1"
    MANAGER = "rubellum-manager-v1"

    def self.session(session_id, generation, control: false)
      raise ArgumentError, "invalid session identity" unless Message::UUID.match?(session_id.to_s)
      raise ArgumentError, "invalid generation" unless generation.is_a?(Integer) && generation.between?(1, 2**63 - 1)
      "rn-#{session_id}-#{generation}-#{control ? 'ctl' : 'cmd'}"
    end
  end
end
