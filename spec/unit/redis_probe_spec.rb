require "rubellum/redis_probe"

RSpec.describe Rubellum::RedisProbe do
  let(:client) { instance_double(Redis) }

  it "checks PING and closes the connection" do
    expect(Redis).to receive(:new).with(hash_including(timeout: 1)).and_return(client)
    expect(client).to receive(:ping).and_return("PONG")
    expect(client).to receive(:close)
    expect(described_class.new.call).to be(true)
  end

  it "closes the connection on failure and propagates it to readiness" do
    expect(Redis).to receive(:new).and_return(client)
    expect(client).to receive(:ping).and_raise(Redis::CannotConnectError)
    expect(client).to receive(:close)
    expect { described_class.new.call }.to raise_error(Redis::CannotConnectError)
  end
end
