Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = false
  config.log_level = :info
  config.active_record.dump_schema_after_migration = false
  config.public_file_server.enabled = true
  config.secret_key_base = File.read(ENV.fetch("RUBELLUM_SECRET_FILE", "/data/config/secret_key_base")).strip
  config.hosts << ENV["RUBELLUM_HOST"] if ENV["RUBELLUM_HOST"].present?
end
