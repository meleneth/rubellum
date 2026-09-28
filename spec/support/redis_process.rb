require "redis"
require "socket"
require "tmpdir"
require "fileutils"
require "timeout"

class RedisProcess
  attr_reader :url

  def initialize
    @port = TCPServer.open("127.0.0.1", 0) { |socket| socket.addr[1] }
    @directory = Dir.mktmpdir("rubellum-redis-")
    @url = "redis://127.0.0.1:#{@port}/0"
  end

  def start
    local = File.expand_path("../../tmp/tools/redis/usr/bin/redis-server", __dir__)
    binary = ENV.fetch("REDIS_BIN", File.executable?(local) ? local : "/usr/bin/redis-server")
    template = File.read(File.expand_path("../../config/redis.conf", __dir__))
    config = File.join(@directory, "redis.conf")
    File.write(config, template.sub("dir /data/redis", "dir #{@directory}"))
    @pid = Process.spawn(binary, config, "--port", @port.to_s,
      out: File.join(@directory, "redis.log"), err: [:child, :out])
    client = Redis.new(url:, timeout: 0.2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      begin
        return self if client.ping == "PONG"
      rescue Redis::BaseError
        raise "Redis readiness failed: #{File.read(File.join(@directory, 'redis.log'))}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.02
      end
    end
  ensure
    client&.close
  end

  def stop
    return unless @pid
    Process.kill("TERM", @pid)
    begin
      Timeout.timeout(3) { Process.wait(@pid) }
    rescue Timeout::Error
      Process.kill("KILL", @pid)
      Process.wait(@pid)
    end
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  ensure
    @pid = nil
  end

  def close
    stop
    FileUtils.remove_entry(@directory)
  end
end
