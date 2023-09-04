# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# sorbet-static is not available on Windows. We also skip Tapioca since it depends on sorbet-static-and-runtime
NON_WINDOWS_PLATFORMS = [:ruby] # C Ruby (MRI), Rubinius or TruffleRuby, but NOT Windows

group :development do
  gem "bundler", "~> 2.4.2"
  gem "debug", "~> 1.8", require: false
  gem "minitest", "~> 5.19"
  gem "minitest-reporters", "~> 1.6"
  gem "mocha", "~> 2.1"
  gem "rake", "~> 13.0"
  gem "rubocop", "~> 1.56"
  gem "rubocop-shopify", "~> 2.14", require: false
  gem "rubocop-minitest", "~> 0.31.1", require: false
  gem "rubocop-rake", "~> 0.6.0", require: false
  gem "rubocop-sorbet", "~> 0.7", require: false
  gem "sorbet-static-and-runtime", platforms: NON_WINDOWS_PLATFORMS
  gem "tapioca", "~> 0.11", require: false, platforms: NON_WINDOWS_PLATFORMS
  gem "rdoc", require: false
  gem "psych", "~> 5.1", require: false
end
