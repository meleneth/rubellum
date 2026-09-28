# frozen_string_literal: true
require "json"
require "rbconfig"
require_relative "message"

module Rubellum
  class EvaluatorProcess
    class Lost < StandardError; end
    OUTPUT_LIMIT = 1024 * 1024
    CHUNK_BYTES = 4096
    attr_reader :pid

    def initialize(workspace:)
      commands_read, @commands = IO.pipe
      @events, events_write = IO.pipe
      @stdout, stdout_write = IO.pipe
      @stderr, stderr_write = IO.pipe
      executable = File.expand_path("../../bin/evaluator", __dir__)
      @pid = Process.spawn({ "PATH" => "/usr/local/bin:/usr/bin:/bin", "LANG" => "C.UTF-8" },
        RbConfig.ruby, executable, 3 => commands_read, 4 => events_write,
        in: File::NULL, out: stdout_write, err: stderr_write,
        unsetenv_others: true, pgroup: true, chdir: workspace)
      @commands.sync = true
      @protocol_buffer = +""
      @streams = { @stdout => "stdout", @stderr => "stderr", @events => "protocol" }
    ensure
      [commands_read, events_write, stdout_write, stderr_write].compact.each(&:close)
    end

    def execute(source:, cell_id:, inputs: {}, datasets: {}, tick: -> {})
      request = JSON.generate({ source:, cell_id:, inputs:, datasets: }) + "\n"
      raise ArgumentError, "evaluator command too large" if request.bytesize > Message::MAX_BYTES
      @commands.write(request)
      recorded = 0
      truncated = false
      decoders = %w[stdout stderr].to_h { |kind| [kind, Encoding::Converter.new("UTF-8", "UTF-16LE", invalid: :replace, undef: :replace)] }
      emit_stream = lambda do |kind, bytes|
        remaining = [OUTPUT_LIMIT - recorded, 0].max
        kept = bytes.byteslice(0, remaining)
        recorded += kept.bytesize
        text = decoders.fetch(kind).convert(kept).encode("UTF-8")
        yield(kind, { "text" => text }) unless text.empty?
        if bytes.bytesize > remaining && !truncated
          yield("output_truncated", { "limit_bytes" => OUTPUT_LIMIT })
          truncated = true
        end
      end
      loop do
        tick.call
        ready = IO.select(@streams.keys, nil, nil, 0.1)&.first || []
        ready.each do |io|
          chunk = io.read_nonblock(CHUNK_BYTES, exception: false)
          next if chunk == :wait_readable
          raise Lost, "Evaluator exited; execution outcome is unknown" if chunk.nil?
          if io != @events
            emit_stream.call(@streams.fetch(io), chunk)
            next
          end
          @protocol_buffer << chunk
          while (newline = @protocol_buffer.index("\n"))
            frame = JSON.parse(@protocol_buffer.slice!(0..newline))
            kind, payload = frame.values_at("kind", "payload")
            if kind.start_with?("execution_")
              # stdout was flushed before the terminal frame was written.
              [@stdout, @stderr].each do |stream|
                while (bytes = stream.read_nonblock(CHUNK_BYTES, exception: false)).is_a?(String)
                  emit_stream.call(@streams.fetch(stream), bytes)
                end
              end
              decoders.each do |stream_kind, decoder|
                tail = decoder.finish.encode("UTF-8")
                yield(stream_kind, { "text" => tail }) unless tail.empty?
              end
              yield(kind, payload)
              return frame
            end
            yield(kind, payload)
          end
          raise Lost, "Oversized evaluator protocol frame" if @protocol_buffer.bytesize > Message::MAX_BYTES
        end
      end
    rescue Errno::EPIPE, IOError => error
      raise Lost, "Evaluator unavailable: #{error.class}"
    end

    def interrupt
      Process.kill("INT", pid)
    end

    def close
      begin
        Process.kill("KILL", -pid) if pid
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(pid) if pid
      rescue Errno::ECHILD
        nil
      end
    ensure
      [@commands, @events, @stdout, @stderr].compact.each { |io| io.close unless io.closed? }
    end
  end
end
