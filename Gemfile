# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# sorbet-static is not available on Windows. We also skip Tapioca since it depends on sorbet-static-and-runtime
NON_WINDOWS_PLATFORMS = [:ruby] # C Ruby (MRI), Rubinius or TruffleRuby, but NOT Windows

gem "bundler", "~> 2.4.2"
gem "debug", "~> 1.7", require: false
gem "minitest", "~> 5.18"
gem "minitest-reporters", "~> 1.6"
gem "mocha", "~> 2.0"
gem "rake", "~> 13.0"
gem "rubocop", "~> 1.50"
gem "rubocop-shopify", "~> 2.13", require: false
gem "rubocop-minitest", "~> 0.31.0", require: false
gem "rubocop-rake", "~> 0.6.0", require: false
gem "rubocop-sorbet", "~> 0.7", require: false
gem "sorbet-static-and-runtime", platforms: NON_WINDOWS_PLATFORMS
gem "tapioca", "~> 0.11", require: false, platforms: NON_WINDOWS_PLATFORMS
gem "rdoc", require: false

# The Rails documentation link only activates when railties is detected.
gem "railties", "~> 7.0", require: false
