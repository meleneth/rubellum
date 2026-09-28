require "rubellum/session_agent"
require_relative "../support/goaws_process"
require "tmpdir"
require "timeout"

RSpec.describe "Real SQS Ruby execution" do
  around do |example|
    Dir.mktmpdir("rubellum-session-") do |directory|
      @broker = GoawsProcess.new.start
      @transport = Rubellum::SqsTransport.local(endpoint: @broker.endpoint)
      @scope = attributes_for(:runner_message).transform_keys(&:to_s).slice(*Rubellum::SessionAgent::SCOPE_FIELDS)
      @journal = Rubellum::RuntimeJournal.new(directory: File.join(directory, "journal"))
      evaluator = Rubellum::EvaluatorProcess.new(workspace: directory)
      @agent = Rubellum::SessionAgent.new(scope: @scope, transport: @transport, journal: @journal, evaluator:)
      @agent.step
      @queue = @transport.ensure_queue(Rubellum::QueueNames.session(@scope["session_id"], 1))
      Timeout.timeout(15) { example.run }
    ensure
      @agent&.close
      @broker&.close
    end
  end

  def command(source, sequence: 1, batch_id: nil)
    build(:runner_message, **@scope.symbolize_keys, sequence:, payload: {
      "cell_id" => SecureRandom.uuid, "cell_revision_id" => SecureRandom.uuid,
      "source" => source, "source_digest" => Digest::SHA256.hexdigest(source), "batch_id" => batch_id
    })
  end

  def events
    queue = @transport.ensure_queue(Rubellum::QueueNames::EVENTS)
    received = []
    loop do
      batch = @transport.receive(queue, wait_seconds: 0)
      break if batch.empty?
      batch.each { |delivery| received << delivery.message; @transport.delete(queue, delivery) }
    end
    received.uniq { |event| event["message_id"] }
  end

  it "transports Ruby commands and real output/results in both directions" do
    request = command('value = 21; puts "hello"; Notebook.emit("rows", data: [value]); value * 2')
    @transport.publish(@queue, request)
    @agent.step
    results = events
    expect(results.map { |event| event["kind"] }).to include("stdout", "structured_output", "execution_completed")
    result = results.find { |event| event["kind"] == "execution_completed" }
    expect(result["payload"]["inspection"]).to eq("42")
    expect(result["execution_id"]).to eq(request["execution_id"])
  end

  it "does not reexecute duplicate commands and preserves state across broker restart" do
    request = command("counter = (counter || 0) + 1")
    @transport.publish(@queue, request)
    @agent.step
    @broker.stop
    @broker.start
    @agent.step
    @queue = @transport.ensure_queue(Rubellum::QueueNames.session(@scope["session_id"], 1))
    @transport.publish(@queue, request)
    @agent.step
    @transport.publish(@queue, command("counter", sequence: 2))
    @agent.step
    expect(@journal.state.fetch("next_command")).to eq(3), @journal.state.inspect
    completions = events.select { |event| event["kind"] == "execution_completed" }
    expect(completions.size).to eq(2)
    expect(completions.map { |event| event["payload"]["inspection"] }).to eq(%w[1 1])
  end

  it "holds sequence gaps and evaluates in command order despite reordered delivery" do
    @transport.publish(@queue, command("value * 2", sequence: 2))
    @agent.step
    expect(events.map { |event| event["kind"] }).not_to include("execution_started")
    @transport.publish(@queue, command("value = 21"))
    @agent.step
    @agent.step
    expect(events.select { |event| event["kind"] == "execution_completed" }.map { |event| event["payload"]["inspection"] }).to eq(%w[21 42])
  end

  it "stops Run all after failure without executing later side effects, including after broker restart" do
    batch_id = SecureRandom.uuid
    @transport.publish(@queue, command('value = 10; raise "stop"', batch_id:))
    @agent.step
    @broker.stop
    @broker.start
    @agent.step
    @queue = @transport.ensure_queue(Rubellum::QueueNames.session(@scope["session_id"], 1))
    @transport.publish(@queue, command("value += 100", sequence: 2, batch_id:))
    @agent.step
    @transport.publish(@queue, command("value", sequence: 3))
    @agent.step
    results = events
    expect(results.map { |event| event["kind"] }).to include("execution_failed", "execution_cancelled")
    expect(results.select { |event| event["kind"] == "execution_completed" }.map { |event| event["payload"]["inspection"] }).to eq(["10"])
  end

  it "compacts only explicitly acknowledged durable event sequences" do
    @transport.publish(@queue, command("42"))
    @agent.step
    count = @journal.state.fetch("event_sequence")
    control = @transport.ensure_queue(Rubellum::QueueNames.session(@scope["session_id"], 1, control: true))
    ack = build(:runner_message, **@scope.symbolize_keys, kind: "acknowledge", payload: { "through_sequence" => count })
    @transport.publish(control, ack)
    @agent.step
    expect(@journal.state.fetch("events")).to be_empty
    expect(@journal.state.fetch("commands").size).to eq(1)
  end

  it "retains an early interrupt across broker restart and cancels before Ruby can have side effects" do
    request = command("cancelled_value = 99")
    control = @transport.ensure_queue(Rubellum::QueueNames.session(@scope["session_id"], 1, control: true))
    interrupt = build(:runner_message, **@scope.symbolize_keys, kind: "interrupt", execution_id: request["execution_id"], payload: {})
    @transport.publish(control, interrupt)
    @agent.step
    expect(@journal.state.fetch("interrupts").fetch("1")).to eq(request["execution_id"])
    @broker.stop
    @broker.start
    @agent.step
    @queue = @transport.ensure_queue(Rubellum::QueueNames.session(@scope["session_id"], 1))
    @transport.publish(@queue, request)
    @agent.step
    @transport.publish(@queue, command("defined?(cancelled_value)", sequence: 2))
    @agent.step
    results = events
    cancelled = results.select { |event| event.to_h["execution_id"] == request["execution_id"] }
    expect(cancelled.sort_by { |event| event["sequence"] }.map { |event| event["kind"] }).to eq(%w[execution_accepted execution_cancelled])
    expect(results.find { |event| event["kind"] == "execution_completed" }["payload"]["inspection"]).to eq("nil")
    expect(@journal.state.fetch("interrupts")).to be_empty
  end

  it "interrupts through the separate SQS control queue while Ruby is running" do
    request = command('puts "ready"; sleep 100')
    @transport.publish(@queue, request)
    worker = Thread.new { @agent.step }
    loop do
      break if events.any? { |event| event["kind"] == "stdout" && event["payload"]["text"].include?("ready") }
      sleep 0.01
    end
    control = @transport.ensure_queue(Rubellum::QueueNames.session(@scope["session_id"], 1, control: true))
    @transport.publish(control, build(:runner_message, **@scope.symbolize_keys,
      kind: "interrupt", execution_id: request["execution_id"], payload: {}))
    worker.value
    expect(events.map { |event| event["kind"] }).to include("execution_interrupted")
  ensure
    worker&.kill if worker&.alive?
    worker&.join
  end

  it "forcibly terminates code that ignores interrupts within the grace period" do
    request = command('trap("INT", "IGNORE"); puts "ready"; loop {}')
    @transport.publish(@queue, request)
    worker = Thread.new { @agent.step }
    loop do
      break if events.any? { |event| event["kind"] == "stdout" && event["payload"]["text"].include?("ready") }
      sleep 0.01
    end
    control = @transport.ensure_queue(Rubellum::QueueNames.session(@scope["session_id"], 1, control: true))
    @transport.publish(control, build(:runner_message, **@scope.symbolize_keys,
      kind: "interrupt", execution_id: request["execution_id"], payload: {}))
    worker.value
    expect(@agent.stopped).to be(true)
    expect(events.map { |event| event["kind"] }).to include("execution_unknown")
  ensure
    worker&.kill if worker&.alive?
    worker&.join
  end
end
