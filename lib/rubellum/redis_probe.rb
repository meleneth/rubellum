require "redis"

module Rubellum
  class RedisProbe
    def call
      client = Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"), timeout: 1)
      client.ping == "PONG"
    ensure
      client&.close
    end
  end
end
