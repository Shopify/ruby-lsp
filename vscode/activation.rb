env = ENV.filter_map do |k, v|
  "#{k}RUBY_LSP_VS#{v.encode(Encoding::UTF_8)}"
rescue Encoding::UndefinedConversionError
  nil
end
env.unshift(RUBY_VERSION, Gem.path.join(","), !!defined?(RubyVM::YJIT))
STDERR.print("RUBY_LSP_ACTIVATION_SEPARATOR#{env.join("RUBY_LSP_FS")}RUBY_LSP_ACTIVATION_SEPARATOR")
