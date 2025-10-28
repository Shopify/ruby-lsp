# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class TestStyle < TestDiscovery
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
            item = queue.shift #: as !nil
            tags = Set.new(item[:tags])
            next unless tags.include?("framework:minitest") || tags.include?("framework:test_unit")

            children = item[:children]
            uri = URI(item[:uri])
            path = uri.full_path
            next unless path

            if tags.include?("test_dir")
              if children.empty?
                full_files.concat(
                  Dir.glob(
                    "#{path}/**/{*_test,test_*,*_spec}.rb",
                    File::Constants::FNM_EXTGLOB | File::Constants::FNM_PATHNAME,
                  ).map! { |p| Shellwords.escape(p) },
                )
              end
            elsif tags.include?("test_file")
              full_files << Shellwords.escape(path) if children.empty?
            elsif tags.include?("test_group")
              # If all of the children of the current test group are other groups, then there's no need to add it to the
              # aggregated examples
              unless children.any? && children.all? { |child| child[:tags].include?("test_group") }
                aggregated_tests[path][item[:id]] = { tags: tags, examples: [] }
              end
            else
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
              info[:tags].include?("framework:minitest")
            end

            if minitest_groups.any?
              commands << handle_minitest_groups(file_path, minitest_groups)
            end

            if test_unit_groups.any?
              commands.concat(handle_test_unit_groups(file_path, test_unit_groups))
            end
          end

          unless full_files.empty?
            specs, tests = full_files.partition { |path| spec?(path) }

            commands << "#{COMMAND} -Itest -e \"ARGV.each { |f| require f }\" #{tests.join(" ")}" if tests.any?
            commands << "#{COMMAND} -Ispec -e \"ARGV.each { |f| require f }\" #{specs.join(" ")}" if specs.any?
          end

          commands
        end

        private

        #: (String) -> bool
        def spec?(path)
          File.fnmatch?("**/spec/**/*_spec.rb", path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end

        #: (String, Hash[String, Hash[Symbol, untyped]]) -> String
        def handle_minitest_groups(file_path, groups_and_examples)
          regexes = groups_and_examples.flat_map do |group, info|
            examples = info[:examples].map { |e| Shellwords.escape(e).gsub(/test_\d{4}/, "test_\\d{4}") }
            group_regex = Shellwords.escape(group).gsub(
              Shellwords.escape(TestDiscovery::DYNAMIC_REFERENCE_MARKER),
              ".*",
            )
            if examples.empty?
              "^#{group_regex}(#|::)"
            elsif examples.length == 1
              "^#{group_regex}##{examples[0]}\\$"
            else
              "^#{group_regex}#(#{examples.join("|")})\\$"
            end
          end

          regex = if regexes.length == 1
            regexes[0]
          else
            "(#{regexes.join("|")})"
          end

          load_path = spec?(file_path) ? "-Ispec" : "-Itest"
          "#{COMMAND} #{load_path} #{Shellwords.escape(file_path)} --name \"/#{regex}/\""
        end

        #: (String, Hash[String, Hash[Symbol, untyped]]) -> Array[String]
        def handle_test_unit_groups(file_path, groups_and_examples)
          groups_and_examples.map do |group, info|
            examples = info[:examples]
            group_regex = Shellwords.escape(group).gsub(
              Shellwords.escape(TestDiscovery::DYNAMIC_REFERENCE_MARKER),
              ".*",
            )
            command = +"#{COMMAND} -Itest #{Shellwords.escape(file_path)} --testcase \"/^#{group_regex}\\$/\""

            unless examples.empty?
              command << if examples.length == 1
                " --name \"/#{examples[0]}\\$/\""
              else
                " --name \"/(#{examples.join("|")})\\$/\""
              end
            end

            command
          end
        end
      end

      include Requests::Support::Common

      MINITEST_REPORTER_PATH = File.expand_path("../test_reporters/minitest_reporter.rb", __dir__) #: String
      TEST_UNIT_REPORTER_PATH = File.expand_path("../test_reporters/test_unit_reporter.rb", __dir__) #: String
      BASE_COMMAND = begin
        Bundler.with_unbundled_env { Bundler.default_lockfile }
        "bundle exec ruby"
      rescue Bundler::GemfileNotFound
        "ruby"
      end #: String
      COMMAND = "#{BASE_COMMAND} -r#{MINITEST_REPORTER_PATH} -r#{TEST_UNIT_REPORTER_PATH}" #: String
      ACCESS_MODIFIERS = [:public, :private, :protected].freeze

      #: (ResponseBuilders::TestCollection, GlobalState, Prism::Dispatcher, URI::Generic) -> void
      def initialize(response_builder, global_state, dispatcher, uri)
        super(response_builder, global_state, uri)

        @framework = :minitest #: Symbol
        @parent_stack = [@response_builder] #: Array[(Requests::Support::TestItem | ResponseBuilders::TestCollection)?]

        register_events(
          dispatcher,
          :on_class_node_enter,
          :on_def_node_enter,
          :on_call_node_enter,
          :on_call_node_leave,
        )
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        with_test_ancestor_tracking(node) do |name, ancestors|
          @framework = :test_unit if ancestors.include?("Test::Unit::TestCase")

          if @framework == :test_unit || non_declarative_minitest?(ancestors, name)
            test_item = Requests::Support::TestItem.new(
              name,
              name,
              @uri,
              range_from_node(node),
              framework: @framework,
            )

            last_test_group.add(test_item)
            @response_builder.add_code_lens(test_item)
            @parent_stack << test_item
          else
            @parent_stack << nil
          end
        end
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        @parent_stack.pop
        super
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        @parent_stack << nil
        super
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        @parent_stack.pop
        super
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        return if @visibility_stack.last != :public

        name = node.name.to_s
        return unless name.start_with?("test_")

        current_group_name = RubyIndexer::Index.actual_nesting(@nesting, nil).join("::")
        parent = @parent_stack.last
        return unless parent.is_a?(Requests::Support::TestItem)

        example_item = Requests::Support::TestItem.new(
          "#{current_group_name}##{name}",
          name,
          @uri,
          range_from_node(node),
          framework: @framework,
        )
        parent.add(example_item)
        @response_builder.add_code_lens(example_item)
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        name = node.name
        return unless ACCESS_MODIFIERS.include?(name)

        @visibility_stack << name
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        name = node.name
        return unless ACCESS_MODIFIERS.include?(name)
        return unless node.arguments&.arguments

        @visibility_stack.pop
      end

      private

      #: -> (Requests::Support::TestItem | ResponseBuilders::TestCollection)
      def last_test_group
        index = @parent_stack.rindex { |i| i } #: as !nil
        @parent_stack[index] #: as Requests::Support::TestItem | ResponseBuilders::TestCollection
      end

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
    end
  end
end
