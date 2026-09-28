require_relative "../support/redis_process"

RSpec.describe "Bundled Redis persistence" do
  it "retains data across restart and enforces the configured memory policy" do
    server = RedisProcess.new
    server.start
    client = Redis.new(url: server.url)
    expect(client.config(:get, "maxmemory-policy")).to eq("maxmemory-policy" => "noeviction")
    expect(client.config(:get, "bind")).to eq("bind" => "127.0.0.1")
    client.set("rubellum:test", "retained")
    client.close
    server.stop
    server.start
    client = Redis.new(url: server.url)
    expect(client.get("rubellum:test")).to eq("retained")
  ensure
    client&.close
    server&.close
  end
end
