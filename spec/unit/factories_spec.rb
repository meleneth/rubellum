# frozen_string_literal: true

RSpec.describe "Test factories" do
  it "builds valid objects for every factory and trait without persistence" do
    FactoryBot.lint(strategy: :build, traits: true)
  end
end
