require 'json'

Dir["test/expectations/**/*.json"].each do |file|
  json = JSON.parse(File.read(file))
  params_index = json.keys.index("params")
  result_index = json.keys.index("result")
  if params_index && params_index > result_index
    exit("Params should be before result in #{file}")
  end
end
