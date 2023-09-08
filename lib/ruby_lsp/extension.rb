# typed: strict
# frozen_string_literal: true

module RubyLsp
  # To register an extension, inherit from this class and implement both `name` and `activate`
  #
  # # Example
  #
  # ```ruby
  # module MyGem
  #   class MyExtension < Extension
  #     def activate
  #       # Perform any relevant initialization
  #     end
  #
  #     def name
  #       "My extension name"
  #     end
  #   end
  # end
  # ```
  class Extension
    extend T::Sig
    extend T::Helpers

    abstract!

    class << self
      extend T::Sig

      # Automatically track and instantiate extension classes
      sig { params(child_class: T.class_of(Extension)).void }
      def inherited(child_class)
        extensions << child_class.new
        super
      end

      sig { returns(T::Array[Extension]) }
      def extensions
        @extensions ||= T.let([], T.nilable(T::Array[Extension]))
      end

      # Discovers and loads all extensions. Returns the list of activated extensions
      sig { returns(T::Array[Extension]) }
      def load_extensions
        # Require all extensions entry points, which should be placed under
        # `some_gem/lib/ruby_lsp/your_gem_name/extension.rb`
        Gem.find_files("ruby_lsp/**/extension.rb").each do |extension|
          require File.expand_path(extension)
        rescue => e
          warn(e.message)
          warn(e.backtrace.to_s) # rubocop:disable Lint/RedundantStringCoercion
        end

        # Activate each one of the discovered extensions. If any problems occur in the extensions, we don't want to
        # fail to boot the server
        extensions.each do |extension|
          extension.activate
          nil
        rescue => e
          extension.add_error(e)
        end
      end
    end

    sig { void }
    def initialize
      @errors = T.let([], T::Array[StandardError])
    end

    sig { params(error: StandardError).returns(T.self_type) }
    def add_error(error)
      @errors << error
      self
    end

    sig { returns(T::Boolean) }
    def error?
      @errors.any?
    end

    sig { returns(String) }
    def formatted_errors
      <<~ERRORS
        #{name}:
          #{@errors.map(&:message).join("\n")}
      ERRORS
    end

    sig { returns(String) }
    def backtraces
      @errors.filter_map(&:backtrace).join("\n\n")
    end

    # Each extension should implement `MyExtension#activate` and use to perform any sort of initialization, such as
    # reading information into memory or even spawning a separate process
    sig { abstract.void }
    def activate; end

    # Each extension should implement `MyExtension#deactivate` and use to perform any clean up, like shutting down a
    # child process
    sig { abstract.void }
    def deactivate; end

    # Extensions should override the `name` method to return the extension name
    sig { abstract.returns(String) }
    def name; end

    # Creates a new CodeLens listener. This method is invoked on every CodeLens request
    sig do
      overridable.params(
        uri: URI::Generic,
        emitter: EventEmitter,
        message_queue: Thread::Queue,
      ).returns(T.nilable(Listener[T::Array[Interface::CodeLens]]))
    end
    def create_code_lens_listener(uri, emitter, message_queue); end

    # Creates a new Hover listener. This method is invoked on every Hover request
    sig do
      overridable.params(
        emitter: EventEmitter,
        message_queue: Thread::Queue,
      ).returns(T.nilable(Listener[T.nilable(Interface::Hover)]))
    end
    def create_hover_listener(emitter, message_queue); end

    # Creates a new DocumentSymbol listener. This method is invoked on every DocumentSymbol request
    sig do
      overridable.params(
        emitter: EventEmitter,
        message_queue: Thread::Queue,
      ).returns(T.nilable(Listener[T::Array[Interface::DocumentSymbol]]))
    end
    def create_document_symbol_listener(emitter, message_queue); end

    # Creates a new Definition listener. This method is invoked on every Definition request
    sig do
      overridable.params(
        uri: URI::Generic,
        nesting: T::Array[String],
        index: RubyIndexer::Index,
        emitter: EventEmitter,
        message_queue: Thread::Queue,
      ).returns(T.nilable(Listener[T.nilable(T.any(T::Array[Interface::Location], Interface::Location))]))
    end
    def create_definition_listener(uri, nesting, index, emitter, message_queue); end
  end
end
