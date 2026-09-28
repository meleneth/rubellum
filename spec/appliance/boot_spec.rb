require "open3"
require "securerandom"
require "timeout"

RSpec.describe "Single-container appliance" do
  def docker(*arguments)
    output, error, status = Open3.capture3("docker", *arguments)
    raise "docker #{arguments.first} failed: #{error}\n#{output}" unless status.success?
    (arguments.first == "logs" ? output + error : output).strip
  end

  def await_ready
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
    loop do
      state = JSON.parse(docker("inspect", @name)).first.fetch("State")
      return if state.dig("Health", "Status") == "healthy"
      if !state.fetch("Running") || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "Appliance failed readiness:\n#{docker('logs', @name)}"
      end
      sleep 0.1
    end
  end

  def boot
    docker("run", "-d", "--name", @name, "-p", "127.0.0.1::3000", "-v", "#{@volume}:/data", ENV.fetch("RUBELLUM_IMAGE", "rubellum:dev"))
    await_ready
  end

  def inside(*command)
    docker("exec", @name, *command)
  end

  around do |example|
    identity = SecureRandom.hex(6)
    @name = "rubellum-spec-#{identity}"
    @volume = "rubellum-spec-data-#{identity}"
    boot
    example.run
  ensure
    # Only resources created by this example; never user's application volumes.
    system("docker", "rm", "-f", @name, out: File::NULL, err: File::NULL) if @name
    system("docker", "volume", "rm", @volume, out: File::NULL, err: File::NULL) if @volume
  end

  it "boots all dependencies with one HTTP port and retains data across restart and replacement" do
    info = JSON.parse(docker("inspect", @name)).first
    expect(info.fetch("HostConfig").fetch("PortBindings").keys).to eq(["3000/tcp"])
    expect(JSON.parse(inside("curl", "-fsS", "http://127.0.0.1:3000/up")).fetch("ready")).to be(true)
    expect(inside("curl", "-fsS", "http://127.0.0.1:3000/")).to include("Rubellum")
    inside("s6-setuidgid", "rubellum", "psql", "-h", "/run/postgresql", "-d", "rubellum", "-c", "CREATE TABLE boot_probe (value text); INSERT INTO boot_probe VALUES ('retained')")
    inside("redis-cli", "SET", "boot-probe", "retained")
    secret_digest = inside("sha256sum", "/data/config/secret_key_base")
    docker("restart", "--time", "20", @name)
    await_ready
    expect(inside("redis-cli", "GET", "boot-probe")).to eq("retained")
    docker("stop", "--time", "20", @name)
    expect(docker("logs", @name)).to include("database system is shut down")
    docker("rm", @name)
    boot
    expect(inside("s6-setuidgid", "rubellum", "psql", "-h", "/run/postgresql", "-d", "rubellum", "-tAc", "SELECT value FROM boot_probe")).to eq("retained")
    expect(inside("redis-cli", "GET", "boot-probe")).to eq("retained")
    expect(inside("sha256sum", "/data/config/secret_key_base")).to eq(secret_digest)
  end

  it "stops the container when a critical service dies" do
    inside("s6-svc", "-k", "/run/service/redis")
    exit_code = Timeout.timeout(30) { docker("wait", @name) }
    expect(exit_code).not_to eq("0")
    expect(docker("logs", @name)).to include("Critical service exited unexpectedly")
  end
end
