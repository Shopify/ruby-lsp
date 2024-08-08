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

      # Discovers and loads all addons. Returns a list of errors when trying to require addons
      sig do
        params(global_state: GlobalState, outgoing_queue: Thread::Queue).returns(T::Array[StandardError])
      end
      def load_addons(global_state, outgoing_queue)
        # Require all addons entry points, which should be placed under
        # `some_gem/lib/ruby_lsp/your_gem_name/addon.rb`
        errors = Gem.find_files("ruby_lsp/**/addon.rb").filter_map do |addon|
          require File.expand_path(addon)
          nil
        rescue => e
          e
        end

        # Instantiate all discovered addon classes
        self.addons = addon_classes.map(&:new)
        self.file_watcher_addons = addons.select { |addon| addon.respond_to?(:workspace_did_change_watched_files) }

        # Activate each one of the discovered addons. If any problems occur in the addons, we don't want to
        # fail to boot the server
        addons.each do |addon|
          addon.activate(global_state, outgoing_queue)
        rescue => e
          addon.add_error(e)
        end

        errors
      end

      # Intended for use by tests for addons
      sig { params(addon_name: String).returns(Addon) }
      def get(addon_name)
        addon = addons.find { |addon| addon.name == addon_name }
        raise "Could not find addon '#{addon_name}'" unless addon

        addon
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
    def errors_details
      @errors.map(&:full_message).join("\n\n")
    end

    # Each addon should implement `MyAddon#activate` and use to perform any sort of initialization, such as
    # reading information into memory or even spawning a separate process
    sig { abstract.params(global_state: GlobalState, outgoing_queue: Thread::Queue).void }
    def activate(global_state, outgoing_queue); end

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
        node_context: NodeContext,
        dispatcher: Prism::Dispatcher,
      ).void
    end
    def create_hover_listener(response_builder, node_context, dispatcher); end

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
        response_builder: ResponseBuilders::CollectionResponseBuilder[T.any(
          Interface::Location,
          Interface::LocationLink,
        )],
        uri: URI::Generic,
        node_context: NodeContext,
        dispatcher: Prism::Dispatcher,
      ).void
    end
    def create_definition_listener(response_builder, uri, node_context, dispatcher); end

    # Creates a new Completion listener. This method is invoked on every Completion request
    sig do
      overridable.params(
        response_builder: ResponseBuilders::CollectionResponseBuilder[Interface::CompletionItem],
        node_context: NodeContext,
        dispatcher: Prism::Dispatcher,
        uri: URI::Generic,
      ).void
    end
    def create_completion_listener(response_builder, node_context, dispatcher, uri); end
  end
end
