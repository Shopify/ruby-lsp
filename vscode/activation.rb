env = ENV.filter_map { |k, v| "#{k}RUBY_LSP_VS#{v}" if v.dup.force_encoding(Encoding::UTF_8).valid_encoding? }
env.unshift(RUBY_VERSION, Gem.path.join(","), !!defined?(RubyVM::YJIT))
STDERR.print("RUBY_LSP_ACTIVATION_SEPARATOR#{env.join("RUBY_LSP_FS")}RUBY_LSP_ACTIVATION_SEPARATOR")
