class OutboxMessage < ApplicationRecord
  def self.enqueue(queue_name:, message:)
    create!(id: message["message_id"], queue_name:, envelope: message.to_h)
  end
end
