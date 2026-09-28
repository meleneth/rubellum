Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.allow_forgery_protection = false
  config.secret_key_base = "test-only-" * 16
  config.hosts << "www.example.com"
  config.log_level = :warn
end
