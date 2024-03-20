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
      DYNAMIC_REFERENCE_MARKER = T.let("+dynamic_reference+", String)

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
          :on_module_node_enter,
          :on_module_node_leave,
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
            command: generate_test_command(group_stack: @group_stack),
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
              command: generate_test_command(method_name: method_name, group_stack: @group_stack),
              kind: :example,
            )
          end
        end
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_enter(node)
        if (path = namespace_constant_name(node))
          @group_stack.push(path)
        else
          @group_stack.push(DYNAMIC_REFERENCE_MARKER)
        end
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_leave(node)
        @group_stack.pop
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
            add_spec_group_code_lens(node)
          when IT_KEYWORD
            add_spec_example_code_lens(node)
          end
        end
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_leave(node)
        _, prev_visibility = @visibility_stack.pop
        @visibility_stack.push([prev_visibility, prev_visibility])
        if node.name == DESCRIBE_KEYWORD
          @group_stack.pop
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

      sig do
        params(
          group_stack: T::Array[String],
          spec_name: T.nilable(String),
          method_name: T.nilable(String),
        ).returns(String)
      end
      def generate_test_command(group_stack: [], spec_name: nil, method_name: nil)
        command = BASE_COMMAND + T.must(@path)

        case DependencyDetector.instance.detected_test_library
        when "minitest"
          path = group_stack.join("::")
          path += "#" + method_name if method_name
          is_dynamic = path.include?(DYNAMIC_REFERENCE_MARKER)

          name = if is_dynamic && method_name
            # If we've got the method name, we know the beginning and end of the name.
            # Things in-between might be dynamic (interpolation, variable constant path, etc.),
            # the best we can do then is match these parts by `.*`. When specs are used,
            # the method name itself will be dynamic (`0001`, `0002`, etc.).
            "/^#{Shellwords.escape(path)}$/"
          elsif method_name
            # We know the entire path, everything is static. Do an exact match.
            Shellwords.escape(path)
          else
            # The user wants to execute all tests of a group.  When clicking on a CodeLens
            # for `Test`, `(#|::)` will match all tests that are registered on the class
            # itself (matches after `#`) and all tests that are nested inside of that class
            # in other modules/classes (matches after `::`). The `describe` method for specs
            # creates a class and can make use of the same logic.
            "\"/^#{Shellwords.escape(path)}(#|::)/\""
          end
          # Replace here so that this doesn't get shell escaped.
          name = name.gsub(DYNAMIC_REFERENCE_MARKER, ".*") if is_dynamic
          command += " --name " + name
        when "test-unit"
          group_name = T.must(group_stack.last)
          command += " --testcase " + "/#{Shellwords.escape(group_name)}/"

          if method_name
            command += " --name " + Shellwords.escape(method_name)
          end
        end

        command
      end

      sig { params(node: Prism::CallNode).void }
      def add_spec_group_code_lens(node)
        name = group_or_example_name(node)
        @group_stack.push(name)

        add_test_code_lens(
          node,
          name: name,
          command: generate_test_command(group_stack: @group_stack),
          kind: :group,
        )

        @group_id_stack.push(@group_id)
        @group_id += 1
      end

      sig { params(node: Prism::CallNode).void }
      def add_spec_example_code_lens(node)
        name = group_or_example_name(node)

        # Generated spec test names have the following format:
        # test_0001_example. 0001 is the counter of the current group.
        method_name = "test_#{DYNAMIC_REFERENCE_MARKER}_#{name}"
        add_test_code_lens(
          node,
          name: name,
          command: generate_test_command(group_stack: @group_stack, method_name: method_name),
          kind: :example,
        )
      end

      sig { params(node: Prism::CallNode).returns(String) }
      def group_or_example_name(node)
        arguments = node.arguments
        return DYNAMIC_REFERENCE_MARKER unless arguments

        first_argument = arguments.arguments.first
        return DYNAMIC_REFERENCE_MARKER unless first_argument

        case first_argument
        when Prism::StringNode
          first_argument.content
        when Prism::InterpolatedStringNode
          replace_variables_with_dynamic_references(first_argument)
        when Prism::ConstantPathNode, Prism::ConstantReadNode
          constant_name(first_argument) || DYNAMIC_REFERENCE_MARKER
        else
          DYNAMIC_REFERENCE_MARKER
        end
      end

      sig { params(node: Prism::InterpolatedStringNode).returns(String) }
      def replace_variables_with_dynamic_references(node)
        node.parts.map do |part|
          case part
          when Prism::StringNode
            part.content
          else
            DYNAMIC_REFERENCE_MARKER
          end
        end.join
      end
    end
  end
end
