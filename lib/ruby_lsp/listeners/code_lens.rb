# typed: strict
# frozen_string_literal: true

require "shellwords"

module RubyLsp
  module Listeners
    class CodeLens
      include Requests::Support::Common

      BASE_COMMAND = begin
        Bundler.with_original_env { Bundler.default_lockfile }
        "bundle exec ruby"
      rescue Bundler::GemfileNotFound
        "ruby"
      end #: String
      ACCESS_MODIFIERS = [:public, :private, :protected] #: Array[Symbol]
      SUPPORTED_TEST_LIBRARIES = ["minitest", "test-unit"] #: Array[String]
      DYNAMIC_REFERENCE_MARKER = "<dynamic_reference>" #: String

      #: (ResponseBuilders::CollectionResponseBuilder[Interface::CodeLens] response_builder, GlobalState global_state, URI::Generic uri, Prism::Dispatcher dispatcher) -> void
      def initialize(response_builder, global_state, uri, dispatcher)
        @response_builder = response_builder
        @global_state = global_state
        @uri = uri #: URI::Generic
        @path = uri.to_standardized_path #: String?
        # visibility_stack is a stack of [current_visibility, previous_visibility]
        @visibility_stack = [[:public, :public]] #: Array[Array[Symbol?]]
        @group_stack = [] #: Array[String]
        @group_id = 1 #: Integer
        @group_id_stack = [] #: Array[Integer]
        # We want to avoid adding code lenses for nested definitions
        @def_depth = 0 #: Integer
        @spec_id = 0 #: Integer

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_module_node_enter,
          :on_module_node_leave,
          :on_def_node_enter,
          :on_def_node_leave,
          :on_call_node_enter,
          :on_call_node_leave,
        )
      end

      #: (Prism::ClassNode node) -> void
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
            id: generate_fully_qualified_id(group_stack: @group_stack),
          )

          @group_id_stack.push(@group_id)
          @group_id += 1
        end
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_leave(node)
        @visibility_stack.pop
        @group_stack.pop

        class_name = node.constant_path.slice

        if @path && class_name.end_with?("Test")
          @group_id_stack.pop
        end
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_enter(node)
        @def_depth += 1
        return if @def_depth > 1

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
              id: generate_fully_qualified_id(group_stack: @group_stack, method_name: method_name),
            )
          end
        end
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_leave(node)
        @def_depth -= 1
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node)
        if (path = namespace_constant_name(node))
          @group_stack.push(path)
        else
          @group_stack.push(DYNAMIC_REFERENCE_MARKER)
        end
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_leave(node)
        @group_stack.pop
      end

      #: (Prism::CallNode node) -> void
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

        case name
        when :describe
          add_spec_code_lens(node, kind: :group)
          @group_id_stack.push(@group_id)
          @group_id += 1
        when :it, :specify # `specify` is an alias for `it`
          add_spec_code_lens(node, kind: :example)
        end
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_leave(node)
        _, prev_visibility = @visibility_stack.pop
        @visibility_stack.push([prev_visibility, prev_visibility])
        if node.name == :describe
          @group_id_stack.pop
          @group_stack.pop
        end
      end

      private

      #: (Prism::Node node, name: String, command: String, kind: Symbol, ?id: String) -> void
      def add_test_code_lens(node, name:, command:, kind:, id: name)
        # don't add code lenses if the test library is not supported or unknown
        return unless SUPPORTED_TEST_LIBRARIES.include?(@global_state.test_library) && @path

        arguments = [
          @path,
          id,
          command,
          {
            start_line: node.location.start_line - 1,
            start_column: node.location.start_column,
            end_line: node.location.end_line - 1,
            end_column: node.location.end_column,
          },
          name,
        ]

        grouping_data = { group_id: @group_id_stack.last, kind: kind }
        grouping_data[:id] = @group_id if kind == :group

        @response_builder << create_code_lens(
          node,
          title: "▶ Run",
          command_name: "rubyLsp.runTest",
          arguments: arguments,
          data: { type: "test", **grouping_data },
        )

        @response_builder << create_code_lens(
          node,
          title: "▶ Run In Terminal",
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

      #: (?group_stack: Array[String], ?spec_name: String?, ?method_name: String?) -> String
      def generate_test_command(group_stack: [], spec_name: nil, method_name: nil)
        path = @path #: as !nil
        command = BASE_COMMAND
        command += " -Itest" if File.fnmatch?("**/test/**/*", path, File::FNM_PATHNAME)
        command += " -Ispec" if File.fnmatch?("**/spec/**/*", path, File::FNM_PATHNAME)
        command += " #{path}"

        case @global_state.test_library
        when "minitest"
          command += generate_minitest_command(group_stack, method_name, spec_name)
        when "test-unit"
          command += generate_test_unit_command(group_stack, method_name)
        end

        command
      end

      #: (Array[String] group_stack, String? method_name, String? spec_name) -> String
      def generate_minitest_command(group_stack, method_name, spec_name)
        last_dynamic_reference_index = group_stack.rindex(DYNAMIC_REFERENCE_MARKER)

        if last_dynamic_reference_index
          # In cases where the test path looks like `foo::Bar`
          # the best we can do is match everything to the right of it.
          # Tests are classes, dynamic references are only a thing for modules,
          # so there must be something to the left of the available path.
          dynamic_stack = group_stack[last_dynamic_reference_index + 1..] #: as !nil

          if method_name
            " --name " + "/::#{Shellwords.escape(dynamic_stack.join("::")) + "#" + Shellwords.escape(method_name)}$/"
          else
            # When clicking on a CodeLens for `Test`, `(#|::)` will match all tests
            # that are registered on the class itself (matches after `#`) and all tests
            # that are nested inside of that class in other modules/classes (matches after `::`)
            " --name " + "\"/::#{Shellwords.escape(dynamic_stack.join("::"))}(#|::)/\""
          end
        elsif method_name
          # We know the entire path, do an exact match
          " --name " + Shellwords.escape(group_stack.join("::")) + "#" + Shellwords.escape(method_name)
        elsif spec_name
          " --name " + "\"/^#{Shellwords.escape(group_stack.join("::"))}##{Shellwords.escape(spec_name)}$/\""
        else
          # Execute all tests of the selected class and tests in
          # modules/classes nested inside of that class
          " --name " + "\"/^#{Shellwords.escape(group_stack.join("::"))}(#|::)/\""
        end
      end

      #: (Array[String] group_stack, String? method_name) -> String
      def generate_test_unit_command(group_stack, method_name)
        group_name = group_stack.last #: as !nil
        command = " --testcase " + "/#{Shellwords.escape(group_name)}/"

        if method_name
          command += " --name " + Shellwords.escape(method_name)
        end

        command
      end

      #: (Prism::CallNode node, kind: Symbol) -> void
      def add_spec_code_lens(node, kind:)
        arguments = node.arguments
        return unless arguments

        first_argument = arguments.arguments.first
        return unless first_argument

        name = case first_argument
        when Prism::StringNode
          first_argument.content
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          RubyIndexer::Index.constant_name(first_argument)
        end

        return unless name

        if kind == :example
          # Increment spec_id for each example
          @spec_id += 1
        else
          # Reset spec_id when entering a new group
          @spec_id = 0
          @group_stack.push(name)
        end

        if @path
          method_name = format("test_%04d_%s", @spec_id, name) if kind == :example
          add_test_code_lens(
            node,
            name: name,
            command: generate_test_command(group_stack: @group_stack, spec_name: method_name),
            kind: kind,
            id: generate_fully_qualified_id(group_stack: @group_stack, method_name: method_name),
          )
        end
      end

      #: (group_stack: Array[String], ?method_name: String?) -> String
      def generate_fully_qualified_id(group_stack:, method_name: nil)
        if method_name
          # For tests, this will be the test class and method name: `Foo::BarTest#test_baz`.
          # For specs, this will be the nested descriptions and formatted test name: `a::b::c#test_001_foo`.
          group_stack.join("::") + "#" + method_name
        else
          # For tests, this will be the test class: `Foo::BarTest`.
          # For specs, this will be the nested descriptions: `a::b::c`.
          group_stack.join("::")
        end
      end
    end
  end
end
