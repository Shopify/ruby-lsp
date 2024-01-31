# typed: strict
# frozen_string_literal: true

require "shellwords"

module RubyLsp
  module Listeners
    class CodeLens
      extend T::Sig
      include Requests::Support::Common

      BASE_COMMAND = T.let(
        begin
          Bundler.with_original_env { Bundler.default_lockfile }
          "bundle exec ruby"
        rescue Bundler::GemfileNotFound
          "ruby"
        end + " -Itest ",
        String,
      )
      ACCESS_MODIFIERS = T.let([:public, :private, :protected], T::Array[Symbol])
      SUPPORTED_TEST_LIBRARIES = T.let(["minitest", "test-unit"], T::Array[String])
      DESCRIBE_KEYWORD = T.let(:describe, Symbol)
      IT_KEYWORD = T.let(:it, Symbol)

      sig do
        params(
          response_builder: ResponseBuilders::CollectionResponseBuilder[Interface::CodeLens],
          uri: URI::Generic,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(response_builder, uri, dispatcher)
        @response_builder = response_builder
        @uri = T.let(uri, URI::Generic)
        @path = T.let(uri.to_standardized_path, T.nilable(String))
        # visibility_stack is a stack of [current_visibility, previous_visibility]
        @visibility_stack = T.let([[:public, :public]], T::Array[T::Array[T.nilable(Symbol)]])
        @group_stack = T.let([], T::Array[String])
        @group_id = T.let(1, Integer)
        @group_id_stack = T.let([], T::Array[Integer])

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_def_node_enter,
          :on_call_node_enter,
          :on_call_node_leave,
        )
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        @visibility_stack.push([:public, :public])
        class_name = node.constant_path.slice
        @group_stack.push(class_name)

        if @path && class_name.end_with?("Test")
          add_test_code_lens(
            node,
            name: class_name,
            command: generate_test_command(group_name: class_name),
            kind: :group,
          )
        end

        @group_id_stack.push(@group_id)
        @group_id += 1
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_leave(node)
        @visibility_stack.pop
        @group_stack.pop
        @group_id_stack.pop
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_enter(node)
        class_name = @group_stack.last
        return unless class_name&.end_with?("Test")

        visibility, _ = @visibility_stack.last
        if visibility == :public
          method_name = node.name.to_s
          if @path && method_name.start_with?("test_")
            add_test_code_lens(
              node,
              name: method_name,
              command: generate_test_command(method_name: method_name, group_name: class_name),
              kind: :example,
            )
          end
        end
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        name = node.name
        arguments = node.arguments

        # If we found `private` by itself or `private def foo`
        if ACCESS_MODIFIERS.include?(name)
          if arguments.nil?
            @visibility_stack.pop
            @visibility_stack.push([name, name])
          elsif arguments.arguments.first.is_a?(Prism::DefNode)
            visibility, _ = @visibility_stack.pop
            @visibility_stack.push([name, visibility])
          end

          return
        end

        if [DESCRIBE_KEYWORD, IT_KEYWORD].include?(name)
          case name
          when DESCRIBE_KEYWORD
            add_spec_code_lens(node, kind: :group)
            @group_id_stack.push(@group_id)
            @group_id += 1
          when IT_KEYWORD
            add_spec_code_lens(node, kind: :example)
          end
        end
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_leave(node)
        _, prev_visibility = @visibility_stack.pop
        @visibility_stack.push([prev_visibility, prev_visibility])
        if node.name == DESCRIBE_KEYWORD
          @group_id_stack.pop
        end
      end

      private

      sig { params(node: Prism::Node, name: String, command: String, kind: Symbol).void }
      def add_test_code_lens(node, name:, command:, kind:)
        # don't add code lenses if the test library is not supported or unknown
        return unless SUPPORTED_TEST_LIBRARIES.include?(DependencyDetector.instance.detected_test_library) && @path

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

        grouping_data = { group_id: @group_id_stack.last, kind: kind }
        grouping_data[:id] = @group_id if kind == :group

        @response_builder << create_code_lens(
          node,
          title: "Run",
          command_name: "rubyLsp.runTest",
          arguments: arguments,
          data: { type: "test", **grouping_data },
        )

        @response_builder << create_code_lens(
          node,
          title: "Run In Terminal",
          command_name: "rubyLsp.runTestInTerminal",
          arguments: arguments,
          data: { type: "test_in_terminal", **grouping_data },
        )

        @response_builder << create_code_lens(
          node,
          title: "Debug",
          command_name: "rubyLsp.debugTest",
          arguments: arguments,
          data: { type: "debug", **grouping_data },
        )
      end

      sig { params(group_name: String, method_name: T.nilable(String)).returns(String) }
      def generate_test_command(group_name:, method_name: nil)
        command = BASE_COMMAND + T.must(@path)

        case DependencyDetector.instance.detected_test_library
        when "minitest"
          command += if method_name
            " --name " + "/#{Shellwords.escape(group_name + "#" + method_name)}/"
          else
            " --name " + "/#{Shellwords.escape(group_name)}/"
          end
        when "test-unit"
          command += " --testcase " + "/#{Shellwords.escape(group_name)}/"

          if method_name
            command += " --name " + Shellwords.escape(method_name)
          end
        end

        command
      end

      sig { params(node: Prism::CallNode, kind: Symbol).void }
      def add_spec_code_lens(node, kind:)
        arguments = node.arguments
        return unless arguments

        first_argument = arguments.arguments.first
        return unless first_argument

        name = case first_argument
        when Prism::StringNode
          first_argument.content
        when Prism::ConstantReadNode
          first_argument.full_name
        end

        return unless name

        add_test_code_lens(
          node,
          name: name,
          command: generate_test_command(group_name: name),
          kind: kind,
        )
      end
    end
  end
end
