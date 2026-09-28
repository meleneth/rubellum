# frozen_string_literal: true

require_relative "boot"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"

Bundler.require(*Rails.groups)

module Rubellum
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: [])
    config.active_record.schema_format = :sql
    config.generators.test_framework :rspec
    config.generators.fixture_replacement :factory_bot
    config.generators.template_engine :haml
    config.logger = ActiveSupport::Logger.new($stdout)
    config.hosts = ["localhost", "127.0.0.1", /.*\.localhost/]
  end
end
