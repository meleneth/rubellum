require "tmpdir"
require "fileutils"

class PostgresProcess
  attr_reader :directory

  def start
    @directory = Dir.mktmpdir("rubellum-postgres-")
    local = File.expand_path("../../tmp/tools/postgresql/usr/lib/postgresql/17/bin", __dir__)
    @bin = ENV.fetch("POSTGRES_BIN", File.executable?("#{local}/initdb") ? local : "/usr/lib/postgresql/17/bin")
    run("initdb", "-D", "#{directory}/cluster", "-U", "rubellum", "--auth-local=trust", "--no-locale")
    run("pg_ctl", "-D", "#{directory}/cluster", "-l", "#{directory}/postgres.log", "-w", "start",
      "-o", "-k #{directory} -c listen_addresses='' -c fsync=on")
    @running = true
    run("createdb", "-h", directory, "-U", "rubellum", "rubellum")
    self
  end

  def close
    run("pg_ctl", "-D", "#{directory}/cluster", "-w", "stop", "-m", "fast") if @running
    FileUtils.remove_entry(directory) if directory
  end

  private

  def run(command, *args)
    binary = File.join(@bin, command)
    binary = File.join("/usr/lib/postgresql/17/bin", command) unless File.executable?(binary)
    raise "Missing PostgreSQL server binary #{binary}; install PostgreSQL 17 or set POSTGRES_BIN" unless File.executable?(binary)
    return if system(binary, *args, out: File.join(directory, "commands.log"), err: [:child, :out])
    raise "PostgreSQL #{command} failed: #{File.read(File.join(directory, 'commands.log'))}"
  end
end
