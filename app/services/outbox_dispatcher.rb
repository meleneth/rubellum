class OutboxDispatcher
  def initialize(transport: Rubellum::SqsTransport.local(endpoint: ENV.fetch("SQS_ENDPOINT", "http://127.0.0.1:4100")), clock: -> { Time.current })
    @transport, @clock = transport, clock
  end

  def call
    OutboxMessage.where(confirmed_at: nil).where("sent_at IS NULL OR sent_at < ?", @clock.call - 5).limit(100).each do |record|
      queue = @transport.ensure_queue(record.queue_name)
      @transport.publish(queue, Rubellum::Message.new(record.envelope))
      # ACKs are recreated on duplicate event delivery; commands stay outstanding
      # until a committed acceptance fact arrives.
      attributes = { sent_at: @clock.call }
      attributes[:confirmed_at] = @clock.call if %w[acknowledge interrupt].include?(record.envelope.fetch("kind"))
      record.update!(attributes)
    end
  end
end
