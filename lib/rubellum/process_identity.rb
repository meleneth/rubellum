module Rubellum
  module ProcessIdentity
    def self.capture(pid)
      stat = File.read("/proc/#{Integer(pid)}/stat")
      { "pid" => pid, "started" => stat.sub(/\A.*\) /, "").split.fetch(19) }
    rescue Errno::ENOENT, Errno::ESRCH
      nil
    end

    def self.terminate_group(identity)
      return unless identity && capture(identity.fetch("pid")) == identity
      Process.kill("KILL", -identity.fetch("pid"))
    rescue Errno::ESRCH
      nil
    end
  end
end
