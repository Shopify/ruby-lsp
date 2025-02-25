env = ENV.filter_map do |k, v|
  utf_8_value = v.dup.force_encoding(Encoding::UTF_8)
  "#{k}RUBY_LSP_VS#{utf_8_value}" if utf_8_value.valid_encoding?
end
env.unshift(RUBY_VERSION, Gem.path.join(","), !!defined?(RubyVM::YJIT))
STDERR.print("RUBY_LSP_ACTIVATION_SEPARATOR#{env.join("RUBY_LSP_FS")}RUBY_LSP_ACTIVATION_SEPARATOR")
