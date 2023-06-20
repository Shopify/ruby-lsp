gem "rake", "~> 13.0"
gem "rubocop-minitest", "~> 0.30.0", require: false
gem "foogem"

group :development do
  gem "debug", "~> 1.7", require: false
end

# Make sure we don't break as the user is typing
gem ""

gem something_that_isnt_a_string
