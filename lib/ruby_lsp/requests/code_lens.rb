# typed: strict
# frozen_string_literal: true

require "shellwords"

module RubyLsp
  module Requests
    # ![Code lens demo](../../code_lens.gif)
    #
    # This feature is currently experimental. Clients will need to pass `experimentalFeaturesEnabled`
    # in the initialization options to enable it.
    #
    # The
    # [code lens](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeLens)
    # request informs the editor of runnable commands such as tests
    #
    # # Example
    #
    # ```ruby
    # # Run
    # class Test < Minitest::Test
    # end
    # ```
    class CodeLens < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::CodeLens] } }

      BASE_COMMAND = T.let((File.exist?("Gemfile.lock") ? "bundle exec ruby" : "ruby") + " -Itest ", String)
      ACCESS_MODIFIERS = T.let(["public", "private", "protected"], T::Array[String])

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { params(uri: String, emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(uri, emitter, message_queue)
        super(emitter, message_queue)

        @response = T.let([], ResponseType)
        @path = T.let(T.must(URI(uri).path), String)
        @visibility = T.let("public", String)
        @prev_visibility = T.let("public", String)

        emitter.register(self, :on_class, :on_def, :on_command, :after_command, :on_call, :after_call, :on_vcall)
      end

      sig { params(node: SyntaxTree::ClassDeclaration).void }
      def on_class(node)
        class_name = node.constant.constant.value
        if class_name.end_with?("Test")
          add_code_lens(node, name: class_name, command: BASE_COMMAND + @path)
        end
      end

      sig { params(node: SyntaxTree::DefNode).void }
      def on_def(node)
        if @visibility == "public"
          method_name = node.name.value
          if method_name.start_with?("test_")
            add_code_lens(
              node,
              name: method_name,
              command: BASE_COMMAND + @path + " --name " + Shellwords.escape(method_name),
            )
          end
        end
      end

      sig { params(node: SyntaxTree::Command).void }
      def on_command(node)
        if ACCESS_MODIFIERS.include?(node.message.value) && node.arguments.parts.any?
          @prev_visibility = @visibility
          @visibility = node.message.value
        elsif @path.include?("Gemfile") && node.message.value.include?("gem") && node.arguments.parts.any?
          homepage = resolve_gem_homepage(node)
          return unless homepage

          add_open_gem_homepage_code_lens(node, homepage: homepage)
        end
      end

      sig { params(node: SyntaxTree::Command).void }
      def after_command(node)
        @visibility = @prev_visibility
      end

      sig { params(node: SyntaxTree::CallNode).void }
      def on_call(node)
        ident = node.message if node.message.is_a?(SyntaxTree::Ident)

        if ident
          ident_value = T.cast(ident, SyntaxTree::Ident).value
          if ACCESS_MODIFIERS.include?(ident_value)
            @prev_visibility = @visibility
            @visibility = ident_value
          end
        end
      end

      sig { params(node: SyntaxTree::CallNode).void }
      def after_call(node)
        @visibility = @prev_visibility
      end

      sig { params(node: SyntaxTree::VCall).void }
      def on_vcall(node)
        vcall_value = node.value.value

        if ACCESS_MODIFIERS.include?(vcall_value)
          @prev_visibility = vcall_value
          @visibility = vcall_value
        end
      end

      sig { params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        @response.concat(other.response)
        self
      end

      private

      sig { params(node: SyntaxTree::Node, name: String, command: String).void }
      def add_code_lens(node, name:, command:)
        @response << create_code_lens(
          node,
          title: "Run",
          command_name: "rubyLsp.runTest",
          path: @path,
          name: name,
          test_command: command,
          type: "test",
        )

        @response << create_code_lens(
          node,
          title: "Run In Terminal",
          command_name: "rubyLsp.runTestInTerminal",
          path: @path,
          name: name,
          test_command: command,
          type: "test_in_terminal",
        )

        @response << create_code_lens(
          node,
          title: "Debug",
          command_name: "rubyLsp.debugTest",
          path: @path,
          name: name,
          test_command: command,
          type: "debug",
        )
      end

      sig { params(node: SyntaxTree::Command).returns(T.nilable(String)) }
      def resolve_gem_homepage(node)
        gem_name = node.arguments.parts.flat_map(&:child_nodes).first.value
        spec = Gem::Specification.stubs.find { |gem| gem.name == gem_name }&.to_spec
        return if spec.nil?

        spec.homepage || spec.metadata.fetch("homepage_uri", nil)
      end

      sig { params(node: SyntaxTree::Command, homepage: String).void }
      def add_open_gem_homepage_code_lens(node, homepage:)
        range = range_from_syntax_tree_node(node)

        @response << Interface::CodeLens.new(
          range: range,
          command: Interface::Command.new(
            title: "Open Homepage",
            command: "rubyLsp.openGemHomepage",
            arguments: [homepage],
          ),
          data: { type: "browser" },
        )
      end
    end
  end
end
