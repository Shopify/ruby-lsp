# typed: strict
# frozen_string_literal: true

require "json"

Dir["test/expectations/**/*.json"].each do |file|
  json = JSON.parse(File.read(file))
  params_index = json.keys.index("params")
  result_index = json.keys.index("result")
  if params_index && params_index > result_index
    puts "params should be before result in #{file}"
    exit(1)
  end
end
