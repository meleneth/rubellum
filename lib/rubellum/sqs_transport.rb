# frozen_string_literal: true

require "aws-sdk-sqs"
require_relative "message"

module Rubellum
  class SqsTransport
    Delivery = Data.define(:message, :receipt_handle)

    def self.local(endpoint: "http://127.0.0.1:4100")
      new(client: Aws::SQS::Client.new(
        endpoint:, region: "us-east-1", access_key_id: "rubellum-local",
        secret_access_key: "rubellum-local", retry_limit: 2,
        http_open_timeout: 2, http_read_timeout: 25
      ))
    end

    def initialize(client:)
      @client = client
    end

    def ensure_queue(name)
      unless name.is_a?(String) && /\A[a-zA-Z0-9_-]{1,80}\z/.match?(name)
        raise ArgumentError, "queue name must contain 1–80 letters, digits, underscores or hyphens"
      end
      @client.create_queue(queue_name: name, attributes: { "VisibilityTimeout" => "30" }).queue_url
    end

    def publish(queue_url, message)
      raise ArgumentError, "expected a validated Message" unless message.is_a?(Message)
      @client.send_message(queue_url:, message_body: message.to_json).message_id
    end

    # No implicit deletion: the caller must durably record acceptance first.
    def receive(queue_url, wait_seconds: 20)
      unless wait_seconds.is_a?(Integer) && (0..20).cover?(wait_seconds)
        raise ArgumentError, "wait_seconds must be an integer from 0 to 20"
      end
      @client.receive_message(queue_url:, max_number_of_messages: 1, wait_time_seconds: wait_seconds)
        .messages.map do |item|
          Delivery.new(message: Message.parse(item.body), receipt_handle: item.receipt_handle)
        end
    end

    def delete(queue_url, delivery)
      @client.delete_message(queue_url:, receipt_handle: delivery.receipt_handle)
    end
  end
end
