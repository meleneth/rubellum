# For filesystem/commit-boundary tests, use real commits in the disposable PG
# fixture rather than hiding all operations inside RSpec's outer transaction.
RSpec.shared_context "committed database" do
  self.use_transactional_tests = false

  around do |example|
    connection = ActiveRecord::Base.connection
    tables = connection.tables - %w[schema_migrations ar_internal_metadata]
    reset = -> { connection.execute("TRUNCATE #{tables.map { |name| connection.quote_table_name(name) }.join(', ')} CASCADE") }
    reset.call
    example.run
  ensure
    reset&.call
  end
end
