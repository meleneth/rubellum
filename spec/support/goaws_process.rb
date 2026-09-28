# frozen_string_literal: true

require "socket"
require "tmpdir"
require "yaml"
require "net/http"
require "timeout"
require "fileutils"

# A real broker per example. This fixture never substitutes an in-memory client.
class GoawsProcess
  attr_reader :endpoint

  def initialize
    @port = TCPServer.open("127.0.0.1", 0) { |socket| socket.addr[1] }
    @directory = Dir.mktmpdir("rubellum-goaws-")
    @endpoint = "http://127.0.0.1:#{@port}"
    @config = File.join(@directory, "goaws.yml")
    config = YAML.safe_load_file(File.expand_path("../../config/goaws.yml", __dir__))
    config.fetch("Local")["Port"] = @port
    File.write(@config, YAML.dump(config))
  end

  def start
    binary = ENV.fetch("GOAWS_BIN", File.expand_path("../../tmp/tools/goaws", __dir__))
    raise "GoAWS missing at #{binary}; run bin/setup-goaws" unless File.executable?(binary)
    @pid = Process.spawn(binary, "-config", @config, out: File.join(@directory, "broker.log"), err: [:child, :out])
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      begin
        response = Net::HTTP.start("127.0.0.1", @port, nil, open_timeout: 0.2, read_timeout: 0.2) do |http|
          http.get("/health")
        end
        return self if response.code == "200"
      rescue SystemCallError, IOError, Timeout::Error
        # Poll a readiness condition, not a fixed startup sleep.
      end
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "GoAWS readiness timed out: #{File.read(File.join(@directory, 'broker.log'))}"
      end
      sleep 0.02
    end
  end

  def stop
    return unless @pid
    Process.kill("TERM", @pid)
    begin
      Timeout.timeout(2) { Process.wait(@pid) }
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
