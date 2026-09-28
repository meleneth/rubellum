require "capybara/rspec"
require "capybara/cuprite"

Capybara.register_driver(:rubellum_chrome) do |application|
  Capybara::Cuprite::Driver.new(application, window_size: [1400, 1000], timeout: 10,
    browser_path: ENV.fetch("CHROME_BIN", "/usr/bin/google-chrome"),
    url_whitelist: [%r{\Ahttps?://(127\.0\.0\.1|localhost)(:|/)}])
end
