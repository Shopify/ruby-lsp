# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "bundler", "~> 2.5"
  gem "debug", "~> 1.9", require: false
  gem "minitest-reporters", "~> 1.6"
  gem "minitest", "~> 5.22"
  gem "mocha", "~> 2.1"
  gem "psych", "~> 5.1", require: false
  gem "rake", "~> 13.1"
  gem "rdoc", require: false, github: "Shopify/rdoc", branch: "create_snapper_generator"
  gem "rubocop-minitest", "~> 0.35.0", require: false
  gem "rubocop-rake", "~> 0.6.0", require: false
  gem "rubocop-shopify", "~> 2.15", require: false
  gem "rubocop-sorbet", "~> 0.8", require: false
  gem "rubocop", "~> 1.62"
  gem "simplecov", require: false
  gem "syntax_tree", ">= 6.1.1", "< 7"

  platforms :ruby do # C Ruby (MRI), Rubinius or TruffleRuby, but NOT Windows
    # sorbet-static is not available on Windows. We also skip Tapioca since it depends on sorbet-static-and-runtime
    gem "sorbet-static-and-runtime"
    gem "tapioca", "~> 0.12", require: false
  end
end
