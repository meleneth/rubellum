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
    @directory = Dir.mktmpdir("rubellum-goaws-")
    @config = File.join(@directory, "goaws.yml")
    select_port
  end

  def start
    binary = ENV.fetch("GOAWS_BIN", File.expand_path("../../tmp/tools/goaws", __dir__))
    raise "GoAWS missing at #{binary}; run bin/setup-goaws" unless File.executable?(binary)
    @pid = Process.spawn(binary, "-config", @config, out: File.join(@directory, "broker.log"), err: [:child, :out])
    retries = 0
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      if Process.waitpid(@pid, Process::WNOHANG)
        @pid = nil
        log = File.read(File.join(@directory, "broker.log"))
        unless !@started_once && retries < 3 && log.include?("address already in use")
          raise "GoAWS exited before readiness: #{log}"
        end
        # There is an unavoidable close/bind window without socket activation.
        # Retry only a first-boot collision; restarts must retain their endpoint.
        retries += 1
        select_port
        @pid = Process.spawn(binary, "-config", @config, out: File.join(@directory, "broker.log"), err: [:child, :out])
        next
      end
      begin
        response = Net::HTTP.start("127.0.0.1", @port, nil, open_timeout: 0.2, read_timeout: 0.2) do |http|
          http.get("/health")
        end
        if response.code == "200"
          @started_once = true
          return self
        end
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

  private

  def select_port
    @port = TCPServer.open("0.0.0.0", 0) { |socket| socket.addr[1] }
    @endpoint = "http://127.0.0.1:#{@port}"
    config = YAML.safe_load_file(File.expand_path("../../config/goaws.yml", __dir__))
    config.fetch("Local")["Port"] = @port
    File.write(@config, YAML.dump(config))
  end
end
