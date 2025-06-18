# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "bundler", "~> 2.5"
gem "minitest", "~> 5.25"
gem "test-unit", require: false

group :development do
  gem "debug", "~> 1.9", require: false
  gem "mocha", "~> 2.3"
  gem "psych", "~> 5.1", require: false
  gem "rake", "~> 13.2"
  gem "rubocop-minitest", "~> 0.38", require: false
  gem "rubocop-rake", "~> 0.7", require: false
  gem "rubocop-shopify", "~> 2.16", require: false
  gem "rubocop-sorbet", "~> 0.8", require: false
  gem "rubocop", "~> 1.70"
  gem "syntax_tree", ">= 6.1.1", "< 7"

  platforms :ruby do # C Ruby (MRI), Rubinius or TruffleRuby, but NOT Windows
    # sorbet-static is not available on Windows. We also skip Tapioca since it depends on sorbet-static-and-runtime
    gem "sorbet-static-and-runtime"
    gem "tapioca", "~> 0.16", require: false
  end
end
