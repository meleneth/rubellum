require "rails_helper"
require_relative "../support/goaws_process"
require_relative "../support/redis_process"

RSpec.describe "Appliance HTTP", type: :request do
  around do |example|
    broker = GoawsProcess.new
    broker.start
    redis = RedisProcess.new
    redis.start
    previous = ENV["SQS_ENDPOINT"]
    previous_redis = ENV["REDIS_URL"]
    ENV["REDIS_URL"] = redis.url
    ENV["SQS_ENDPOINT"] = broker.endpoint
    @broker = broker
    example.run
  ensure
    ENV["SQS_ENDPOINT"] = previous
    ENV["REDIS_URL"] = previous_redis
    redis&.close
    broker&.close
  end

  it "serves a local Rails page" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rubellum", "Your Ruby notebooks")
  end

  it "checks real PostgreSQL and GoAWS readiness" do
    get "/up"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("ready" => true, "services" => { "postgres" => "ready", "sqs" => "ready", "redis" => "ready" })
  end

  it "fails readiness when the broker is down" do
    @broker.stop
    get "/up"
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch("services").fetch("sqs")).to eq("unavailable")
  end
end
