# frozen_string_literal: true

require "rubellum/sqs_transport"
require_relative "../support/goaws_process"

RSpec.describe "GoAWS 0.5.4 / aws-sdk-sqs 1.119.0 contract" do
  around do |example|
    @broker = GoawsProcess.new
    @broker.start
    example.run
  ensure
    @broker&.close
  end

  let(:transport) { Rubellum::SqsTransport.local(endpoint: @broker.endpoint) }
  let(:client) do
    Aws::SQS::Client.new(endpoint: @broker.endpoint, region: "us-east-1",
      access_key_id: "local", secret_access_key: "local", retry_limit: 0)
  end
  let(:queue) { transport.ensure_queue("rubellum-contract") }
  let(:message) { build(:runner_message) }

  it "creates queues idempotently and sends, receives, and deletes actual JSON envelopes" do
    expect(transport.ensure_queue("rubellum-contract")).to eq(queue)
    expect(URI(queue).host).to eq("127.0.0.1")
    expect(client.config.api.metadata["protocol"]).to eq("json")
    transport.publish(queue, message)
    delivery = transport.receive(queue, wait_seconds: 0).fetch(0)
    expect(delivery.message.to_h).to eq(message.to_h)
    transport.delete(queue, delivery)
    expect(transport.receive(queue, wait_seconds: 0)).to be_empty
  end

  it "carries the full application envelope size budget" do
    base = message.to_json.bytesize
    full = build(:runner_message, payload: { "source" => "x" * (Rubellum::Message::MAX_BYTES - base + "puts 'hello'".bytesize) })
    expect(full.to_json.bytesize).to eq(Rubellum::Message::MAX_BYTES)
    transport.publish(queue, full)
    expect(transport.receive(queue, wait_seconds: 0).fetch(0).message.to_h).to eq(full.to_h)
  end

  it "redelivers unacknowledged messages with their original application identity" do
    transport.publish(queue, message)
    delivery = transport.receive(queue, wait_seconds: 0).fetch(0)
    expect(transport.receive(queue, wait_seconds: 0)).to be_empty
    client.change_message_visibility(queue_url: queue, receipt_handle: delivery.receipt_handle, visibility_timeout: 0)
    redelivery = transport.receive(queue, wait_seconds: 0).fetch(0)
    expect(redelivery.message.to_h).to eq(message.to_h)
    transport.delete(queue, redelivery)
  end

  it "does not deduplicate application message identities in standard queues" do
    2.times { transport.publish(queue, message) }
    messages = 2.times.map do
      delivery = transport.receive(queue, wait_seconds: 0).fetch(0)
      transport.delete(queue, delivery)
      delivery.message.to_h
    end
    expect(messages).to eq([message.to_h, message.to_h])
  end

  it "loses topology on restart and accepts recreated queues and republished envelopes" do
    transport.publish(queue, message)
    original_endpoint = @broker.endpoint
    @broker.stop
    @broker.start
    expect(@broker.endpoint).to eq(original_endpoint)
    expect(client.list_queues.queue_urls).to be_empty
    restored_queue = transport.ensure_queue("rubellum-contract")
    expect(transport.receive(restored_queue, wait_seconds: 0)).to be_empty
    transport.publish(restored_queue, message)
    expect(transport.receive(restored_queue, wait_seconds: 0).fetch(0).message.to_h).to eq(message.to_h)
  end
end

RSpec.describe "GoAWS fixture port ownership" do
  it "recovers a deterministic first-boot port collision without claiming another listener is ready" do
    broker = GoawsProcess.new
    original_endpoint = broker.endpoint
    collision = TCPServer.new("0.0.0.0", URI(original_endpoint).port)
    broker.start
    expect(broker.endpoint).not_to eq(original_endpoint)
    expect(Rubellum::SqsTransport.local(endpoint: broker.endpoint).available?).to be(true)
  ensure
    collision&.close
    broker&.close
  end
end
