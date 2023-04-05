# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Extension
    class << self
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { params(child_class: T.class_of(Extension)).void }
      def inherited(child_class)
        extensions << child_class
        super
      end

      sig { returns(T::Array[T.class_of(Extension)]) }
      def extensions
        @extensions ||= T.let([], T.nilable(T::Array[T.class_of(Extension)]))
      end

      sig { returns(T::Array[StandardError]) }
      def load_extensions
        # Require all extensions entry points, which should be placed under
        # `some_gem/lib/ruby_lsp/your_gem_name/extension.rb`
        errors = ::Gem.find_files("ruby_lsp/*/extension.rb").filter_map do |extension|
          require File.expand_path(extension)
          nil
        rescue => e
          e
        end

        # Activate each one of the discovered extensions. If any problems occur in the extensions, we don't want to
        # fail to boot the server
        extensions.each do |extension|
          extension.activate
        rescue => e
          errors << e
        end

        errors
      end

      # Each extension should implement `MyExtension.activate` and use to:
      # - Register request hooks
      # - Perform any sort of initialization, such as reading information into memory or even spawning a separate
      # process
      sig { abstract.void }
      def activate; end
    end
  end
end
