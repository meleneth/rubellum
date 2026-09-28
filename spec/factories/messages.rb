# frozen_string_literal: true

require "rubellum/message"
require "securerandom"

FactoryBot.define do
  factory :runner_message, class: "Rubellum::Message" do
    schema_version { 1 }
    message_id { SecureRandom.uuid }
    kind { "execute" }
    app_installation_id { SecureRandom.uuid }
    notebook_id { SecureRandom.uuid }
    session_id { SecureRandom.uuid }
    generation { 1 }
    execution_id { SecureRandom.uuid }
    add_attribute(:sequence) { 1 }
    payload { { "source" => +"puts 'hello'" } }

    initialize_with { new(attributes.transform_keys(&:to_s)) }

    trait :started do
      kind { "execution_started" }
      payload { {} }
    end
  end
end
