# frozen_string_literal: true
require "fileutils"
require "json"
require_relative "json_value"

module Rubellum
  class RuntimeJournal
    class Full < StandardError; end
    class Owned < StandardError; end
    DEFAULT_LIMIT = 16 * 1024 * 1024
    TERMINAL_RESERVE = 64 * 1024
    attr_reader :state

    def initialize(directory:, limit: DEFAULT_LIMIT, reserve: TERMINAL_RESERVE)
      raise ArgumentError, "invalid journal bounds" unless limit > reserve && reserve.positive?
      FileUtils.mkdir_p(directory, mode: 0o700)
      @directory, @limit, @reserve = directory, limit, reserve
      @path = File.join(directory, "state.json")
      @lock = File.open(File.join(directory, "owner.lock"), File::RDWR | File::CREAT, 0o600)
      unless @lock.flock(File::LOCK_EX | File::LOCK_NB)
        @lock.close
        raise Owned, "A runner already owns this journal"
      end
      @state = File.exist?(@path) ? JsonValue.copy(JSON.parse(File.read(@path))) : JsonValue.copy({})
    rescue StandardError
      @lock&.close unless @lock&.closed?
      raise
    end

    def update(terminal: false)
      copy = JSON.parse(JSON.generate(state))
      yield copy
      encoded = JSON.generate(JsonValue.copy(copy))
      raise Full, "Runner journal is full; stop this session and retain its journal" if encoded.bytesize > @limit - (terminal ? 0 : @reserve)
      temporary = "#{@path}.new"
      begin
        File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
          file.write(encoded)
          file.fsync
        end
        File.rename(temporary, @path)
        File.open(@directory) { |directory| directory.fsync }
        @state = JsonValue.copy(copy)
      ensure
        File.unlink(temporary) if File.exist?(temporary)
      end
    end

    def close
      @lock.close unless @lock.closed?
    end
  end
end
