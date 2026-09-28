require "rubellum/dead_runner_recovery"
require "rubellum/session_agent"
require "tmpdir"

RSpec.describe Rubellum::DeadRunnerRecovery do
  it "marks started work unknown, cancels unstarted work, and retains event identities without evaluating" do
    Dir.mktmpdir("rubellum-dead-") do |directory|
      journal = Rubellum::RuntimeJournal.new(directory:)
      transport = instance_double(Rubellum::SqsTransport)
      scope = attributes_for(:runner_message).transform_keys(&:to_s).slice(*Rubellum::SessionAgent::SCOPE_FIELDS)
      first = build(:runner_message, **scope.symbolize_keys)
      second = build(:runner_message, **scope.symbolize_keys, sequence: 2)
      journal.update do |state|
        state.merge!("scope" => scope, "event_sequence" => 0, "acknowledged" => 0, "events" => [],
          "commands" => { "1" => { "state" => "started", "envelope" => first.to_h }, "2" => { "state" => "accepted", "envelope" => second.to_h } })
      end
      recovery = described_class.new(journal:, transport:)
      recovery.mark_lost
      facts = journal.state.fetch("events")
      expect(facts.map { |item| item["kind"] }).to eq(%w[execution_unknown execution_cancelled runner_stopped])
      recovery.mark_lost
      expect(journal.state.fetch("events")).to eq(facts)
    ensure
      journal&.close
    end
  end
end
