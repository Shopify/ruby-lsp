# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class TestStyle
      class << self
        # Resolves the minimal set of commands required to execute the requested tests
        #: (Array[Hash[Symbol, untyped]]) -> Array[String]
        def resolve_test_commands(items)
          # A nested hash of file_path => test_group => { tags: [], examples: [test_example] } to ensure we build the
          # minimum amount of commands needed to execute the requested tests. This is only used for specific examples
          # where we will need more complex regexes to execute it all at the same time
          aggregated_tests = Hash.new do |hash, key|
            hash[key] = Hash.new do |inner_h, inner_k|
              inner_h[inner_k] = { tags: Set.new, examples: [] }
            end
          end

          # Full files are paths that should be executed as a whole e.g.: an entire test file or directory
          full_files = []
          queue = items.dup

          until queue.empty?
            item = T.must(queue.shift)
            tags = Set.new(item[:tags])

            children = item[:children]
            uri = URI(item[:uri])
            path = uri.full_path
            next unless path

            if tags.include?("test_dir")
              full_files << "#{path}/**/*" if children.empty?
            elsif tags.include?("test_file")
              full_files << path if children.empty?
            elsif tags.include?("test_group")
              # If all of the children of the current test group are other groups, then there's no need to add it to the
              # aggregated examples
              unless children.any? && children.all? { |child| child[:tags].include?("test_group") }
                aggregated_tests[path][item[:label]] = { tags: tags, examples: [] }
              end
            elsif tags.include?("minitest") || tags.include?("test_unit")
              class_name, method_name = item[:id].split("#")
              aggregated_tests[path][class_name][:examples] << method_name
              aggregated_tests[path][class_name][:tags].merge(tags)
            end

            queue.concat(children) unless children.empty?
          end

          commands = []

          aggregated_tests.each do |file_path, groups_and_examples|
            # Separate groups into Minitest and Test Unit. You can have both frameworks in the same file, but you cannot
            # have a group belongs to both at the same time
            minitest_groups, test_unit_groups = groups_and_examples.partition do |_, info|
              info[:tags].include?("minitest")
            end

            if minitest_groups.any?
              commands << handle_minitest_groups(file_path, minitest_groups)
            end

            if test_unit_groups.any?
              commands.concat(handle_test_unit_groups(file_path, test_unit_groups))
            end
          end

          commands << "#{BASE_COMMAND} -Itest #{full_files.join(" ")}" unless full_files.empty?
          commands
        end

        private

        #: (String, Hash[String, Hash[Symbol, untyped]]) -> String
        def handle_minitest_groups(file_path, groups_and_examples)
          regexes = groups_and_examples.flat_map do |group, info|
            examples = info[:examples]
            group_regex = Shellwords.escape(group).gsub(Shellwords.escape(DYNAMIC_REFERENCE_MARKER), ".*")
            if examples.empty?
              "^#{group_regex}(#|::)"
            elsif examples.length == 1
              "^#{group_regex}##{examples[0]}$"
            else
              "^#{group_regex}#(#{examples.join("|")})$"
            end
          end

          regex = if regexes.length == 1
            regexes[0]
          else
            "(#{regexes.join("|")})"
          end

          "#{BASE_COMMAND} -Itest #{file_path} --name \"/#{regex}/\""
        end

        #: (String, Hash[String, Hash[Symbol, untyped]]) -> Array[String]
        def handle_test_unit_groups(file_path, groups_and_examples)
          groups_and_examples.map do |group, info|
            examples = info[:examples]
            group_regex = Shellwords.escape(group).gsub(Shellwords.escape(DYNAMIC_REFERENCE_MARKER), ".*")
            command = +"#{BASE_COMMAND} -Itest #{file_path} --testcase \"/^#{group_regex}$/\""

            unless examples.empty?
              command << if examples.length == 1
                " --name \"/#{examples[0]}$/\""
              else
                " --name \"/(#{examples.join("|")})$/\""
              end
            end

            command
          end
        end
      end

      include Requests::Support::Common

      ACCESS_MODIFIERS = [:public, :private, :protected].freeze
      DYNAMIC_REFERENCE_MARKER = "<dynamic_reference>"
      BASE_COMMAND = T.let(
        begin
          Bundler.with_original_env { Bundler.default_lockfile }
          "bundle exec ruby"
        rescue Bundler::GemfileNotFound
          "ruby"
        end,
        String,
      )

      #: (ResponseBuilders::TestCollection response_builder, GlobalState global_state, Prism::Dispatcher dispatcher, URI::Generic uri) -> void
      def initialize(response_builder, global_state, dispatcher, uri)
        @response_builder = response_builder
        @uri = uri
        @index = T.let(global_state.index, RubyIndexer::Index)
        @visibility_stack = T.let([:public], T::Array[Symbol])
        @nesting = T.let([], T::Array[String])
        @framework_tag = T.let(:minitest, Symbol)

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

      #: (Prism::ClassNode node) -> void
      def on_class_node_enter(node)
        @visibility_stack << :public
        name = constant_name(node.constant_path)
        name ||= name_with_dynamic_reference(node.constant_path)

        fully_qualified_name = RubyIndexer::Index.actual_nesting(@nesting, name).join("::")

        attached_ancestors = begin
          @index.linearized_ancestors_of(fully_qualified_name)
        rescue RubyIndexer::Index::NonExistingNamespaceError
          # When there are dynamic parts in the constant path, we will not have indexed the namespace. We can still
          # provide test functionality if the class inherits directly from Test::Unit::TestCase or Minitest::Test
          [node.superclass&.slice].compact
        end

        @framework_tag = :test_unit if attached_ancestors.include?("Test::Unit::TestCase")

        if @framework_tag == :test_unit || non_declarative_minitest?(attached_ancestors, fully_qualified_name)
          @response_builder.add(Requests::Support::TestItem.new(
            fully_qualified_name,
            fully_qualified_name,
            @uri,
            range_from_node(node),
            tags: [@framework_tag],
          ))
        end

        @nesting << name
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node)
        @visibility_stack << :public

        name = constant_name(node.constant_path)
        name ||= name_with_dynamic_reference(node.constant_path)

        @nesting << name
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_leave(node)
        @visibility_stack.pop
        @nesting.pop
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_leave(node)
        @visibility_stack.pop
        @nesting.pop
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_enter(node)
        return if @visibility_stack.last != :public

        name = node.name.to_s
        return unless name.start_with?("test_")

        current_group_name = RubyIndexer::Index.actual_nesting(@nesting, nil).join("::")

        # If we're finding a test method, but for the wrong framework, then the group test item will not have been
        # previously pushed and thus we return early and avoid adding items for a framework this listener is not
        # interested in
        test_item = @response_builder[current_group_name]
        return unless test_item

        test_item.add(Requests::Support::TestItem.new(
          "#{current_group_name}##{name}",
          name,
          @uri,
          range_from_node(node),
          tags: [@framework_tag],
        ))
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_enter(node)
        name = node.name
        return unless ACCESS_MODIFIERS.include?(name)

        @visibility_stack << name
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_leave(node)
        name = node.name
        return unless ACCESS_MODIFIERS.include?(name)
        return unless node.arguments&.arguments

        @visibility_stack.pop
      end

      private

      #: (Array[String] attached_ancestors, String fully_qualified_name) -> bool
      def non_declarative_minitest?(attached_ancestors, fully_qualified_name)
        return false unless attached_ancestors.include?("Minitest::Test")

        # We only support regular Minitest tests. The declarative syntax provided by ActiveSupport is handled by the
        # Rails add-on
        name_parts = fully_qualified_name.split("::")
        singleton_name = "#{name_parts.join("::")}::<Class:#{name_parts.last}>"
        !@index.linearized_ancestors_of(singleton_name).include?("ActiveSupport::Testing::Declarative")
      rescue RubyIndexer::Index::NonExistingNamespaceError
        true
      end

      #: ((Prism::ConstantPathNode | Prism::ConstantReadNode | Prism::ConstantPathTargetNode | Prism::CallNode | Prism::MissingNode) node) -> String
      def name_with_dynamic_reference(node)
        slice = node.slice
        slice.gsub(/((?<=::)|^)[a-z]\w*/, DYNAMIC_REFERENCE_MARKER)
      end
    end
  end
end
