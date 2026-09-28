require "spec_helper"
require_relative "support/postgres_process"

ENV["RAILS_ENV"] = "test"
# Never connect tests to a user's existing database.
raise "Unset DATABASE_URL for isolated PostgreSQL tests" if ENV["DATABASE_URL"]
postgres = PostgresProcess.new
at_exit { postgres.close }
postgres.start
ENV["PGHOST"] = postgres.directory
ENV["PGUSER"] = "rubellum"
ENV["PGDATABASE"] = "rubellum"
require_relative "../config/environment"
require "rspec/rails"
Dir[File.join(__dir__, "rails_factories", "*.rb")].sort.each { |file| require file }

ActiveRecord::Migration.verbose = false
ActiveRecord::MigrationContext.new(Rails.root.join("db/migrate")).migrate

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
