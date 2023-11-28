# typed: strict
# frozen_string_literal: true

module RubyLsp
  # To register an addon, inherit from this class and implement both `name` and `activate`
  #
  # # Example
  #
  # ```ruby
  # module MyGem
  #   class MyAddon < Addon
  #     def activate
  #       # Perform any relevant initialization
  #     end
  #
  #     def name
  #       "My addon name"
  #     end
  #   end
  # end
  # ```
  class Addon
    extend T::Sig
    extend T::Helpers

    abstract!

    class << self
      extend T::Sig

      # Automatically track and instantiate addon classes
      sig { params(child_class: T.class_of(Addon)).void }
      def inherited(child_class)
        addons << child_class.new
        super
      end

      sig { returns(T::Array[Addon]) }
      def addons
        @addons ||= T.let([], T.nilable(T::Array[Addon]))
      end

      # Discovers and loads all addons. Returns the list of activated addons
      sig { params(message_queue: Thread::Queue).returns(T::Array[Addon]) }
      def load_addons(message_queue)
        # Require all addons entry points, which should be placed under
        # `some_gem/lib/ruby_lsp/your_gem_name/addon.rb`
        Gem.find_files("ruby_lsp/**/addon.rb").each do |addon|
          require File.expand_path(addon)
        rescue => e
          warn(e.message)
          warn(e.backtrace.to_s) # rubocop:disable Lint/RedundantStringCoercion
        end

        # Activate each one of the discovered addons. If any problems occur in the addons, we don't want to
        # fail to boot the server
        addons.each do |addon|
          addon.activate(message_queue)
          nil
        rescue => e
          addon.add_error(e)
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

    # Each addon should implement `MyAddon#activate` and use to perform any sort of initialization, such as
    # reading information into memory or even spawning a separate process
    sig { abstract.params(message_queue: Thread::Queue).void }
    def activate(message_queue); end

    # Each addon should implement `MyAddon#deactivate` and use to perform any clean up, like shutting down a
    # child process
    sig { abstract.void }
    def deactivate; end

    # Addons should override the `name` method to return the addon name
    sig { abstract.returns(String) }
    def name; end

    # Creates a new CodeLens listener. This method is invoked on every CodeLens request
    sig do
      overridable.params(
        uri: URI::Generic,
        dispatcher: Prism::Dispatcher,
      ).returns(T.nilable(Listener[T::Array[Interface::CodeLens]]))
    end
    def create_code_lens_listener(uri, dispatcher); end

    # Creates a new Hover listener. This method is invoked on every Hover request
    sig do
      overridable.params(
        nesting: T::Array[String],
        index: RubyIndexer::Index,
        dispatcher: Prism::Dispatcher,
      ).returns(T.nilable(Listener[T.nilable(Interface::Hover)]))
    end
    def create_hover_listener(nesting, index, dispatcher); end

    # Creates a new DocumentSymbol listener. This method is invoked on every DocumentSymbol request
    sig do
      overridable.params(
        dispatcher: Prism::Dispatcher,
      ).returns(T.nilable(Listener[T::Array[Interface::DocumentSymbol]]))
    end
    def create_document_symbol_listener(dispatcher); end

    # Creates a new Definition listener. This method is invoked on every Definition request
    sig do
      overridable.params(
        uri: URI::Generic,
        nesting: T::Array[String],
        index: RubyIndexer::Index,
        dispatcher: Prism::Dispatcher,
      ).returns(T.nilable(Listener[T.nilable(T.any(T::Array[Interface::Location], Interface::Location))]))
    end
    def create_definition_listener(uri, nesting, index, dispatcher); end
  end
end
