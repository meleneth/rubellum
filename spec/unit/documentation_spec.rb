require "rubellum/ruby_evaluator"
require "rubellum/parameters"
require "pathname"

RSpec.describe "Documented examples" do
  let(:root) { Pathname.new(File.expand_path("../..", __dir__)) }
  let(:readme) { root.join("README.md").read }

  it "runs the README's first-notebook example and produces its documented result" do
    source = readme.match(/^   ```ruby\n(.*?)^   ```/m).captures.first.lines.map { |line| line.delete_prefix("   ") }.join
    events = []
    result = Rubellum::RubyEvaluator.new.call(source:, cell_id: SecureRandom.uuid) { |*event| events << event }
    expect(result.fetch("kind")).to eq("execution_completed")
    expect(result.dig("payload", "inspection")).to eq("36")
    expect(events).to eq([["structured_output", { "name" => "rows", "data" => [
      { "label" => "One", "value" => 12 }, { "label" => "Two", "value" => 24 }
    ] }]])
  end

  it "keeps README links pointed at real repository documents" do
    paths = readme.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.reject { |path| path.start_with?("http", "#", "asset://") }
    expect(paths).not_to be_empty
    paths.each { |path| expect(root.join(path)).to exist, "Missing README link target: #{path}" }
  end

  it "maps every quick-start container to explicit persistent /data storage" do
    commands = readme.scan(/docker run .*?(?=\n```)/m)
    expect(commands.size).to eq(2)
    expect(commands.first).to include("-v rubellum-data:/data")
    expect(commands.last).to include('--mount type=bind,source="$(pwd)/rubellum-data",target=/data')
    expect(readme).to include("Always mount persistent storage at `/data`", "A persistent mount is not a backup.")
  end

  it "accepts the documented parameter definitions and typed defaults" do
    examples = root.join("docs/cells.md").read.scan(/```json\n(.*?)```/m).flatten.map { |source| JSON.parse(source) }
    definitions = examples.find { |example| example.is_a?(Array) }
    expect(Rubellum::Parameters.new(definitions).values).to eq(
      "scale" => 1.0, "caption" => "Measurements", "visible" => true, "color" => "orange")
  end
end
