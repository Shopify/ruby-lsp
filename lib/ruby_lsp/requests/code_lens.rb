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
      SUPPORTED_TEST_LIBRARIES = T.let(["minitest", "test-unit"], T::Array[String])

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { params(uri: String, emitter: EventEmitter, message_queue: Thread::Queue, test_library: String).void }
      def initialize(uri, emitter, message_queue, test_library)
        super(emitter, message_queue)

        @uri = T.let(uri, String)
        @external_listeners = T.let([], T::Array[RubyLsp::Listener[ResponseType]])
        @test_library = T.let(test_library, String)
        @response = T.let([], ResponseType)
        @path = T.let(T.must(URI(URI::Parser.new.escape(uri)).path), String)
        # visibility_stack is a stack of [current_visibility, previous_visibility]
        @visibility_stack = T.let([["public", "public"]], T::Array[T::Array[T.nilable(String)]])
        @class_stack = T.let([], T::Array[String])

        emitter.register(
          self,
          :on_class,
          :after_class,
          :on_def,
          :on_command,
          :after_command,
          :on_call,
          :after_call,
          :on_vcall,
        )

        register_external_listeners!
      end

      sig { void }
      def register_external_listeners!
        self.class.listeners.each do |l|
          @external_listeners << T.unsafe(l).new(@uri, @emitter, @message_queue)
        end
      end

      sig { void }
      def merge_external_listeners_responses!
        @external_listeners.each do |l|
          merge_response!(l)
        end
      end

      sig { params(node: SyntaxTree::ClassDeclaration).void }
      def on_class(node)
        @visibility_stack.push(["public", "public"])
        class_name = node.constant.constant.value
        @class_stack.push(class_name)

        if class_name.end_with?("Test")
          add_test_code_lens(
            node,
            name: class_name,
            command: generate_test_command(class_name: class_name),
            kind: :group,
          )
        end
      end

      sig { params(node: SyntaxTree::ClassDeclaration).void }
      def after_class(node)
        @visibility_stack.pop
        @class_stack.pop
      end

      sig { params(node: SyntaxTree::DefNode).void }
      def on_def(node)
        class_name = @class_stack.last
        return unless class_name&.end_with?("Test")

        visibility, _ = @visibility_stack.last
        if visibility == "public"
          method_name = node.name.value
          if method_name.start_with?("test_")
            add_test_code_lens(
              node,
              name: method_name,
              command: generate_test_command(method_name: method_name, class_name: class_name),
              kind: :example,
            )
          end
        end
      end

      sig { params(node: SyntaxTree::Command).void }
      def on_command(node)
        node_message = node.message.value
        if ACCESS_MODIFIERS.include?(node_message) && node.arguments.parts.any?
          visibility, _ = @visibility_stack.pop
          @visibility_stack.push([node_message, visibility])
        elsif @path.include?("Gemfile") && node_message.include?("gem") && node.arguments.parts.any?
          remote = resolve_gem_remote(node)
          return unless remote

          add_open_gem_remote_code_lens(node, remote)
        end
      end

      sig { params(node: SyntaxTree::Command).void }
      def after_command(node)
        _, prev_visibility = @visibility_stack.pop
        @visibility_stack.push([prev_visibility, prev_visibility])
      end

      sig { params(node: SyntaxTree::CallNode).void }
      def on_call(node)
        ident = node.message if node.message.is_a?(SyntaxTree::Ident)

        if ident
          ident_value = T.cast(ident, SyntaxTree::Ident).value
          if ACCESS_MODIFIERS.include?(ident_value)
            visibility, _ = @visibility_stack.pop
            @visibility_stack.push([ident_value, visibility])
          end
        end
      end

      sig { params(node: SyntaxTree::CallNode).void }
      def after_call(node)
        _, prev_visibility = @visibility_stack.pop
        @visibility_stack.push([prev_visibility, prev_visibility])
      end

      sig { params(node: SyntaxTree::VCall).void }
      def on_vcall(node)
        vcall_value = node.value.value

        if ACCESS_MODIFIERS.include?(vcall_value)
          @visibility_stack.pop
          @visibility_stack.push([vcall_value, vcall_value])
        end
      end

      sig { params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        @response.concat(other.response)
        self
      end

      private

      sig { params(node: SyntaxTree::Node, name: String, command: String, kind: Symbol).void }
      def add_test_code_lens(node, name:, command:, kind:)
        # don't add code lenses if the test library is not supported or unknown
        return unless SUPPORTED_TEST_LIBRARIES.include?(@test_library)

        arguments = [
          @path,
          name,
          command,
          {
            start_line: node.location.start_line - 1,
            start_column: node.location.start_column,
            end_line: node.location.end_line - 1,
            end_column: node.location.end_column,
          },
        ]

        @response << create_code_lens(
          node,
          title: "Run",
          command_name: "rubyLsp.runTest",
          arguments: arguments,
          data: { type: "test", kind: kind },
        )

        @response << create_code_lens(
          node,
          title: "Run In Terminal",
          command_name: "rubyLsp.runTestInTerminal",
          arguments: arguments,
          data: { type: "test_in_terminal", kind: kind },
        )

        @response << create_code_lens(
          node,
          title: "Debug",
          command_name: "rubyLsp.debugTest",
          arguments: arguments,
          data: { type: "debug", kind: kind },
        )
      end

      sig { params(node: SyntaxTree::Command).returns(T.nilable(String)) }
      def resolve_gem_remote(node)
        gem_statement = node.arguments.parts.first
        return unless gem_statement.is_a?(SyntaxTree::StringLiteral)

        gem_name = gem_statement.parts.first
        return unless gem_name.is_a?(SyntaxTree::TStringContent)

        spec = Gem::Specification.stubs.find { |gem| gem.name == gem_name.value }&.to_spec
        return if spec.nil?

        [spec.homepage, spec.metadata["source_code_uri"]].compact.find do |page|
          page.start_with?("https://github.com", "https://gitlab.com")
        end
      end

      sig { params(class_name: String, method_name: T.nilable(String)).returns(String) }
      def generate_test_command(class_name:, method_name: nil)
        command = BASE_COMMAND + @path

        case @test_library
        when "minitest"
          command += if method_name
            " --name " + "/#{Shellwords.escape(class_name + "#" + method_name)}/"
          else
            " --name " + "/#{Shellwords.escape(class_name)}/"
          end
        when "test-unit"
          command += " --testcase " + "/#{Shellwords.escape(class_name)}/"

          if method_name
            command += " --name " + Shellwords.escape(method_name)
          end
        end

        command
      end

      sig { params(node: SyntaxTree::Command, remote: String).void }
      def add_open_gem_remote_code_lens(node, remote)
        @response << create_code_lens(
          node,
          title: "Open remote",
          command_name: "rubyLsp.openLink",
          arguments: [remote],
          data: { type: "link" },
        )
      end
    end
  end
end
