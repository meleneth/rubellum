require "rubellum/evaluator_process"
require "tmpdir"
require "timeout"

RSpec.describe Rubellum::EvaluatorProcess do
  around do |example|
    Dir.mktmpdir("rubellum-workspace-") do |directory|
      ENV["RUBELLUM_TEST_SECRET"] = "must-not-inherit"
      @process = described_class.new(workspace: directory)
      Timeout.timeout(10) { example.run }
    ensure
      @process&.close
      ENV.delete("RUBELLUM_TEST_SECRET")
    end
  end

  def execute(source)
    events = []
    @process.execute(source:, cell_id: SecureRandom.uuid) { |*event| events << event }
    events
  end

  it "separates user stdout/stderr from protocol and retains Ruby state" do
    events = execute('value = 21; STDOUT.puts %q({"kind":"forged"}); STDERR.puts "warning"; value')
    expect(events.select { |kind, _| kind == "stdout" }.map { |_, data| data["text"] }.join).to eq("{\"kind\":\"forged\"}\n")
    expect(events.map(&:first)).to include("stderr", "execution_completed")
    expect(execute("value * 2").last.last["inspection"]).to eq("42")
  end

  it "does not inherit Rails, Bundler configuration, or unrelated secrets" do
    result = execute('[defined?(Rails), ENV["BUNDLE_GEMFILE"], ENV["DATABASE_URL"], ENV["RUBELLUM_TEST_SECRET"]]')
    expect(result.last.last["inspection"]).to eq("[nil, nil, nil, nil]")
  end

  it "bounds output and visibly reports truncation" do
    events = execute('STDOUT.write("x" * 1_100_000); 42')
    expect(events.select { |kind, _| kind == "stdout" }.sum { |_, data| data["text"].bytesize }).to eq(described_class::OUTPUT_LIMIT)
    expect(events.count { |kind, _| kind == "output_truncated" }).to eq(1)
    expect(events.last.last["inspection"]).to eq("42")
  end

  it "preserves Unicode characters split across stdout pipe chunks" do
    text = "λ🙂" * 9000
    events = execute("STDOUT.write(#{text.inspect}); nil")
    actual = events.select { |kind, _| kind == "stdout" }.map { |_, payload| payload.fetch("text") }.join
    expect(actual).to eq(text)
  end

  it "marks abrupt process loss unknown rather than rerunning source" do
    expect { execute("exit! 9") }.to raise_error(described_class::Lost, /unknown/)
  end
end
