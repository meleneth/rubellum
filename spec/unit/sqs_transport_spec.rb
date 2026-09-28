# frozen_string_literal: true

require "rubellum/sqs_transport"

RSpec.describe Rubellum::SqsTransport do
  let(:client) { instance_double(Aws::SQS::Client) }
  let(:transport) { described_class.new(client:) }
  let(:queue_url) { "http://127.0.0.1:4100/100010001000/test" }
  let(:message) { build(:runner_message) }

  it "checks connectivity without creating or consuming messages" do
    expect(client).to receive(:list_queues).and_return(Aws::SQS::Types::ListQueuesResult.new(queue_urls: []))
    expect(transport.available?).to be(true)
  end

  it "creates standard queues with an explicit visibility timeout" do
    expect(client).to receive(:create_queue)
      .with(queue_name: "test", attributes: { "VisibilityTimeout" => "30" })
      .and_return(Aws::SQS::Types::CreateQueueResult.new(queue_url:))
    expect(transport.ensure_queue("test")).to eq(queue_url)
  end

  ["", "with spaces", "../test", "x" * 81, "test.fifo", nil].each do |name|
    it "rejects invalid standard queue name #{name.inspect} before transport" do
      expect(client).not_to receive(:create_queue)
      expect { transport.ensure_queue(name) }.to raise_error(ArgumentError)
    end
  end

  it "publishes the validated envelope without changing its application identity" do
    expect(client).to receive(:send_message).with(queue_url:, message_body: message.to_json)
      .and_return(Aws::SQS::Types::SendMessageResult.new(message_id: "broker-id"))
    expect(transport.publish(queue_url, message)).to eq("broker-id")
  end

  it "rejects an unvalidated hash before transport" do
    expect(client).not_to receive(:send_message)
    expect { transport.publish(queue_url, message.to_h) }.to raise_error(ArgumentError)
  end

  it "returns validated envelopes and receipt handles without acknowledging delivery" do
    expect(client).to receive(:receive_message)
      .with(queue_url:, max_number_of_messages: 1, wait_time_seconds: 20)
      .and_return(Aws::SQS::Types::ReceiveMessageResult.new(messages: [
        Aws::SQS::Types::Message.new(body: message.to_json, receipt_handle: "receipt")
      ]))
    expect(client).not_to receive(:delete_message)
    delivery = transport.receive(queue_url).first
    expect(delivery.message.to_h).to eq(message.to_h)
    expect(delivery.receipt_handle).to eq("receipt")
  end

  it "returns no deliveries for an empty queue" do
    expect(client).to receive(:receive_message)
      .and_return(Aws::SQS::Types::ReceiveMessageResult.new(messages: []))
    expect(transport.receive(queue_url)).to eq([])
  end

  it "rejects malformed envelopes without deleting them" do
    expect(client).to receive(:receive_message)
      .and_return(Aws::SQS::Types::ReceiveMessageResult.new(messages: [
        Aws::SQS::Types::Message.new(body: "{}", receipt_handle: "receipt")
      ]))
    expect(client).not_to receive(:delete_message)
    expect { transport.receive(queue_url) }.to raise_error(Rubellum::Message::Invalid)
  end

  [-1, 21, "20", nil, 0.5].each do |wait_seconds|
    it "rejects invalid receive wait #{wait_seconds.inspect}" do
      expect(client).not_to receive(:receive_message)
      expect { transport.receive(queue_url, wait_seconds:) }.to raise_error(ArgumentError)
    end
  end

  it "deletes only when the durable consumer explicitly acknowledges a receipt" do
    delivery = described_class::Delivery.new(message:, receipt_handle: "receipt")
    expect(client).to receive(:delete_message).with(queue_url:, receipt_handle: "receipt")
    transport.delete(queue_url, delivery)
  end

  it "propagates broker failure for the durable caller to reconcile" do
    expect(client).to receive(:send_message).and_raise(Aws::SQS::Errors::QueueDoesNotExist.new(nil, "gone"))
    expect { transport.publish(queue_url, message) }.to raise_error(Aws::SQS::Errors::QueueDoesNotExist)
  end

  it "constructs a local client without consulting the AWS credential chain" do
    expect(Aws::SQS::Client).to receive(:new).with(hash_including(
      endpoint: "http://127.0.0.1:4100", region: "us-east-1",
      access_key_id: "rubellum-local", secret_access_key: "rubellum-local"
    )).and_return(client)
    expect(described_class.local).to be_a(described_class)
  end
end
