# frozen_string_literal: true

require "bundler/setup"
require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  track_files "lib/**/*.rb"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "factory_bot"
FactoryBot.find_definitions

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) do |mocks|
    mocks.verify_partial_doubles = true
    mocks.verify_doubled_constant_names = true
  end
  config.example_status_persistence_file_path = "tmp/rspec-status.txt"
  config.order = :random
  Kernel.srand config.seed
end
