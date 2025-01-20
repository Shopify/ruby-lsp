env = { env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION, gemPath: Gem.path }.to_json
STDERR.print("RUBY_LSP_ACTIVATION_SEPARATOR#{env}RUBY_LSP_ACTIVATION_SEPARATOR")
