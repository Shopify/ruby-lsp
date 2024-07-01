# typed: true

class RuboCop::Runner
  def initialize(options, config_store)
    @config_store = T.let(T.unsafe(nil), RuboCop::ConfigStore)
  end
end
