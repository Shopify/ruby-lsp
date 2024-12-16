# typed: strict
# frozen_string_literal: true

module RubyLsp
  # To register an add-on, inherit from this class and implement both `name` and `activate`
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
  #       "My add-on name"
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
    # Add-on instances that have declared a handler to accept file watcher events
    @file_watcher_addons = T.let([], T::Array[Addon])

    AddonNotFoundError = Class.new(StandardError)

    class IncompatibleApiError < StandardError; end

    class << self
      extend T::Sig

      sig { returns(T::Array[Addon]) }
      attr_accessor :addons

      sig { returns(T::Array[Addon]) }
      attr_accessor :file_watcher_addons

      sig { returns(T::Array[T.class_of(Addon)]) }
      attr_reader :addon_classes

      # Automatically track and instantiate add-on classes
      sig { params(child_class: T.class_of(Addon)).void }
      def inherited(child_class)
        addon_classes << child_class
        super
      end

      # Discovers and loads all add-ons. Returns a list of errors when trying to require add-ons
      sig do
        params(
          global_state: GlobalState,
          outgoing_queue: Thread::Queue,
          include_project_addons: T::Boolean,
        ).returns(T::Array[StandardError])
      end
      def load_addons(global_state, outgoing_queue, include_project_addons: true)
        # Require all add-ons entry points, which should be placed under
        # `some_gem/lib/ruby_lsp/your_gem_name/addon.rb` or in the workspace under
        # `your_project/ruby_lsp/project_name/addon.rb`
        addon_files = Gem.find_files("ruby_lsp/**/addon.rb")

        if include_project_addons
          addon_files.concat(Dir.glob(File.join(global_state.workspace_path, "**", "ruby_lsp/**/addon.rb")))
        end

        errors = addon_files.filter_map do |addon_path|
          # Avoid requiring this file twice. This may happen if you're working on the Ruby LSP itself and at the same
          # time have `ruby-lsp` installed as a vendored gem
          next if File.basename(File.dirname(addon_path)) == "ruby_lsp"

          require File.expand_path(addon_path)
          nil
        rescue => e
          e
        end

        # Instantiate all discovered add-on classes
        self.addons = addon_classes.map(&:new)
        self.file_watcher_addons = addons.select { |addon| addon.respond_to?(:workspace_did_change_watched_files) }

        # Activate each one of the discovered add-ons. If any problems occur in the add-ons, we don't want to
        # fail to boot the server
        addons.each do |addon|
          addon.activate(global_state, outgoing_queue)
        rescue => e
          addon.add_error(e)
        end

        errors
      end

      # Unloads all add-ons. Only intended to be invoked once when shutting down the Ruby LSP server
      sig { void }
      def unload_addons
        @addons.each(&:deactivate)
        @addons.clear
        @addon_classes.clear
        @file_watcher_addons.clear
      end

      # Get a reference to another add-on object by name and version. If an add-on exports an API that can be used by
      # other add-ons, this is the way to get access to that API.
      #
      # Important: if the add-on is not found, AddonNotFoundError will be raised. If the add-on is found, but its
      # current version does not satisfy the given version constraint, then IncompatibleApiError will be raised. It is
      # the responsibility of the add-ons using this API to handle these errors appropriately.
      sig { params(addon_name: String, version_constraints: String).returns(Addon) }
      def get(addon_name, *version_constraints)
        if version_constraints.empty?
          raise IncompatibleApiError, "Must specify version constraints when accessing other add-ons"
        end

        addon = addons.find { |addon| addon.name == addon_name }
        raise AddonNotFoundError, "Could not find add-on '#{addon_name}'" unless addon

        version_object = Gem::Version.new(addon.version)

        unless version_constraints.all? { |constraint| Gem::Requirement.new(constraint).satisfied_by?(version_object) }
          raise IncompatibleApiError,
            "Constraints #{version_constraints.inspect} is incompatible with #{addon_name} version #{addon.version}"
        end

        addon
      end

      # Depend on a specific version of the Ruby LSP. This method should only be used if the add-on is distributed in a
      # gem that does not have a runtime dependency on the ruby-lsp gem. This method should be invoked at the top of the
      # `addon.rb` file before defining any classes or requiring any files. For example:
      #
      # ```ruby
      # RubyLsp::Addon.depend_on_ruby_lsp!(">= 0.18.0")
      #
      # module MyGem
      #   class MyAddon < RubyLsp::Addon
      #     # ...
      #   end
      # end
      # ```
      sig { params(version_constraints: String).void }
      def depend_on_ruby_lsp!(*version_constraints)
        version_object = Gem::Version.new(RubyLsp::VERSION)

        unless version_constraints.all? { |constraint| Gem::Requirement.new(constraint).satisfied_by?(version_object) }
          raise IncompatibleApiError,
            "Add-on is not compatible with this version of the Ruby LSP. Skipping its activation"
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
    def errors_details
      @errors.map(&:full_message).join("\n\n")
    end

    # Each add-on should implement `MyAddon#activate` and use to perform any sort of initialization, such as
    # reading information into memory or even spawning a separate process
    sig { abstract.params(global_state: GlobalState, outgoing_queue: Thread::Queue).void }
    def activate(global_state, outgoing_queue); end

    # Each add-on should implement `MyAddon#deactivate` and use to perform any clean up, like shutting down a
    # child process
    sig { abstract.void }
    def deactivate; end

    # Add-ons should override the `name` method to return the add-on name
    sig { abstract.returns(String) }
    def name; end

    # Add-ons should override the `version` method to return a semantic version string representing the add-on's
    # version. This is used for compatibility checks
    sig { abstract.returns(String) }
    def version; end

    # Handle a response from a window/showMessageRequest request. Add-ons must include the addon_name as part of the
    # original request so that the response is delegated to the correct add-on and must override this method to handle
    # the response
    # https://microsoft.github.io/language-server-protocol/specification#window_showMessageRequest
    sig { overridable.params(title: String).void }
    def handle_window_show_message_response(title); end

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
