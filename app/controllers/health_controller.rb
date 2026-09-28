class HealthController < ApplicationController
  def show
    checks = {
      redis: Rubellum::RedisProbe.new,
      postgres: -> { ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") } },
      sqs: -> { Rubellum::SqsTransport.local(endpoint: ENV.fetch("SQS_ENDPOINT", "http://127.0.0.1:4100")).available? }
    }
    result = Rubellum::Readiness.new(checks:).call
    render json: result, status: result.fetch(:ready) ? :ok : :service_unavailable
  end
end
