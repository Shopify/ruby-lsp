# frozen_string_literal: true

# Typically, GEM_HOME points to $HOME/.gem/ruby/version_without_patch. For example, for Ruby 3.2.2, it would be
# $HOME/.gem/ruby/3.2.0. However, chruby overrides GEM_HOME to use the patch part of the version, resulting in
# $HOME/.gem/ruby/3.2.2. In our activation script, we check if a directory using the patch exists and then prefer
# that over the default one.
user_dir = Gem.user_dir
paths = Gem.path
default_dir = Gem.default_dir

if paths.length > 2
  paths.delete(default_dir)
  paths.delete(user_dir)
  first_path = paths[0]
  user_dir = first_path if first_path && Dir.exist?(first_path)
end

newer_gem_home = File.join(File.dirname(user_dir), ARGV.first)
gems = Dir.exist?(newer_gem_home) ? newer_gem_home : user_dir
STDERR.print(
  [
    default_dir,
    gems,
    !!defined?(RubyVM::YJIT),
    RUBY_VERSION
  ].join("RUBY_LSP_ACTIVATION_SEPARATOR")
)
