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

    @addons = T.let([], T::Array[Addon])
    @addon_classes = T.let([], T::Array[T.class_of(Addon)])
    # Addon instances that have declared a handler to accept file watcher events
    @file_watcher_addons = T.let([], T::Array[Addon])

    class << self
      extend T::Sig

      sig { returns(T::Array[Addon]) }
      attr_accessor :addons

      sig { returns(T::Array[Addon]) }
      attr_accessor :file_watcher_addons

      sig { returns(T::Array[T.class_of(Addon)]) }
      attr_reader :addon_classes

      # Automatically track and instantiate addon classes
      sig { params(child_class: T.class_of(Addon)).void }
      def inherited(child_class)
        addon_classes << child_class
        super
      end

      # Discovers and loads all addons. Returns the list of activated addons
      sig { params(message_queue: Thread::Queue).returns(T::Array[Addon]) }
      def load_addons(message_queue)
        # Require all addons entry points, which should be placed under
        # `some_gem/lib/ruby_lsp/your_gem_name/addon.rb`
        Gem.find_files("ruby_lsp/**/addon.rb").each do |addon|
          require File.expand_path(addon)
        rescue => e
          $stderr.puts(e.full_message)
        end

        # Instantiate all discovered addon classes
        self.addons = addon_classes.map(&:new)
        self.file_watcher_addons = addons.select { |addon| addon.respond_to?(:workspace_did_change_watched_files) }

        # Activate each one of the discovered addons. If any problems occur in the addons, we don't want to
        # fail to boot the server
        addons.each do |addon|
          addon.activate(message_queue)
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
        response_builder: ResponseBuilders::CollectionResponseBuilder[Interface::CodeLens],
        uri: URI::Generic,
        dispatcher: Prism::Dispatcher,
      ).void
    end
    def create_code_lens_listener(response_builder, uri, dispatcher); end

    # Creates a new Hover listener. This method is invoked on every Hover request
    sig do
      overridable.params(
        response_builder: ResponseBuilders::Hover,
        nesting: T::Array[String],
        index: RubyIndexer::Index,
        dispatcher: Prism::Dispatcher,
      ).void
    end
    def create_hover_listener(response_builder, nesting, index, dispatcher); end

    # Creates a new DocumentSymbol listener. This method is invoked on every DocumentSymbol request
    sig do
      overridable.params(
        response_builder: ResponseBuilders::DocumentSymbol,
        dispatcher: Prism::Dispatcher,
      ).void
    end
    def create_document_symbol_listener(response_builder, dispatcher); end

    sig do
      overridable.params(
        response_builder: ResponseBuilders::SemanticHighlighting,
        dispatcher: Prism::Dispatcher,
      ).void
    end
    def create_semantic_highlighting_listener(response_builder, dispatcher); end

    # Creates a new Definition listener. This method is invoked on every Definition request
    sig do
      overridable.params(
        response_builder: ResponseBuilders::CollectionResponseBuilder[Interface::Location],
        uri: URI::Generic,
        nesting: T::Array[String],
        index: RubyIndexer::Index,
        dispatcher: Prism::Dispatcher,
      ).void
    end
    def create_definition_listener(response_builder, uri, nesting, index, dispatcher); end
  end
end
