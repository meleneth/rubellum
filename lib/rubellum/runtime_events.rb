require "securerandom"
require_relative "message"

module Rubellum
  module RuntimeEvents
    def self.append(state, kind, payload, execution_id = nil, command_id = nil)
      state["event_sequence"] += 1
      event = state.fetch("scope").merge("schema_version" => 1, "message_id" => SecureRandom.uuid,
        "kind" => kind, "sequence" => state.fetch("event_sequence"), "payload" => payload)
      event["execution_id"] = execution_id if execution_id
      event["command_id"] = command_id if command_id
      state.fetch("events") << Message.new(event).to_h
    end
  end
end
