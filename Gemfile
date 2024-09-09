# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "bundler", "~> 2.5"
gem "minitest", "~> 5.25"

group :development do
  gem "debug", "~> 1.9", require: false
  gem "minitest-reporters", "~> 1.7"
  gem "mocha", "~> 2.3"
  gem "psych", "~> 5.1", require: false
  gem "rake", "~> 13.2"
  gem "rdoc", require: false, github: "Shopify/rdoc", branch: "create_snapper_generator"
  gem "rubocop-md", "~> 1.2.0", require: false
  gem "rubocop-minitest", "~> 0.35.0", require: false
  gem "rubocop-rake", "~> 0.6.0", require: false
  gem "rubocop-shopify", "~> 2.15", require: false
  gem "rubocop-sorbet", "~> 0.8", require: false
  gem "rubocop", "~> 1.65"
  gem "simplecov", require: false
  gem "syntax_tree", ">= 6.1.1", "< 7"

  platforms :ruby do # C Ruby (MRI), Rubinius or TruffleRuby, but NOT Windows
    # sorbet-static is not available on Windows. We also skip Tapioca since it depends on sorbet-static-and-runtime
    gem "sorbet-static-and-runtime"
    gem "tapioca", "~> 0.16", require: false

    # sass-embedded, a dependency of just-the-docs, doesn't builde with Ruby 3.1 and we only need it for Jekyll
    # so we only install it for Ruby 3.3 and above
    if RUBY_VERSION >= "3.3"
      group :jekyll do
        # We only need to use Jekyll with CRuby
        gem "jekyll", "~> 4.3.3"
        gem "jekyll-feed", "~> 0.12"

        # Theme
        gem "just-the-docs", "~> 0.10.0"
      end
    end
  end
end
