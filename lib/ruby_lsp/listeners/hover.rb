# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class Hover
      include Requests::Support::Common

      ALLOWED_REMOTE_PROVIDERS = [
        "https://github.com",
        "https://gitlab.com",
      ].freeze #: Array[String]

      #: (ResponseBuilders::Hover response_builder, GlobalState global_state, URI::Generic uri, NodeContext node_context, Prism::Dispatcher dispatcher, SorbetLevel sorbet_level, Hash[Symbol, untyped] position) -> void
      def initialize(response_builder, global_state, uri, node_context, dispatcher, sorbet_level, position) # rubocop:disable Metrics/ParameterLists
        @response_builder = response_builder
        @global_state = global_state
        @index = global_state.index #: RubyIndexer::Index
        @graph = global_state.graph #: Rubydex::Graph
        @type_inferrer = global_state.type_inferrer #: TypeInferrer
        @path = uri.to_standardized_path #: String?
        @node_context = node_context
        @sorbet_level = sorbet_level
        @position = position

        dispatcher.register(
          self,
          :on_alias_global_variable_node_enter,
          :on_alias_method_node_enter,
          :on_and_node_enter,
          :on_begin_node_enter,
          :on_block_node_enter,
          :on_break_node_enter,
          :on_call_node_enter,
          :on_case_match_node_enter,
          :on_case_node_enter,
          :on_class_node_enter,
          :on_singleton_class_node_enter,
          :on_lambda_node_enter,
          :on_class_variable_and_write_node_enter,
          :on_class_variable_operator_write_node_enter,
          :on_class_variable_or_write_node_enter,
          :on_class_variable_read_node_enter,
          :on_class_variable_target_node_enter,
          :on_class_variable_write_node_enter,
          :on_constant_path_node_enter,
          :on_constant_read_node_enter,
          :on_constant_write_node_enter,
          :on_def_node_enter,
          :on_defined_node_enter,
          :on_else_node_enter,
          :on_ensure_node_enter,
          :on_false_node_enter,
          :on_for_node_enter,
          :on_forwarding_super_node_enter,
          :on_global_variable_and_write_node_enter,
          :on_global_variable_operator_write_node_enter,
          :on_global_variable_or_write_node_enter,
          :on_global_variable_read_node_enter,
          :on_global_variable_target_node_enter,
          :on_global_variable_write_node_enter,
          :on_if_node_enter,
          :on_in_node_enter,
          :on_instance_variable_and_write_node_enter,
          :on_instance_variable_operator_write_node_enter,
          :on_instance_variable_or_write_node_enter,
          :on_instance_variable_read_node_enter,
          :on_instance_variable_target_node_enter,
          :on_instance_variable_write_node_enter,
          :on_interpolated_string_node_enter,
          :on_module_node_enter,
          :on_next_node_enter,
          :on_nil_node_enter,
          :on_or_node_enter,
          :on_post_execution_node_enter,
          :on_pre_execution_node_enter,
          :on_redo_node_enter,
          :on_rescue_modifier_node_enter,
          :on_rescue_node_enter,
          :on_retry_node_enter,
          :on_return_node_enter,
          :on_self_node_enter,
          :on_source_encoding_node_enter,
          :on_source_file_node_enter,
          :on_source_line_node_enter,
          :on_string_node_enter,
          :on_super_node_enter,
          :on_true_node_enter,
          :on_undef_node_enter,
          :on_unless_node_enter,
          :on_until_node_enter,
          :on_when_node_enter,
          :on_while_node_enter,
          :on_yield_node_enter,
        )
      end

      #: (Prism::StringNode node) -> void
      def on_string_node_enter(node)
        if @path && File.basename(@path) == GEMFILE_NAME
          call_node = @node_context.call_node
          if call_node && call_node.name == :gem && call_node.arguments&.arguments&.first == node
            generate_gem_hover(call_node)
            return
          end
        end

        generate_heredoc_hover(node)
      end

      #: (Prism::InterpolatedStringNode node) -> void
      def on_interpolated_string_node_enter(node)
        generate_heredoc_hover(node)
      end

      #: (Prism::ConstantReadNode node) -> void
      def on_constant_read_node_enter(node)
        return unless @sorbet_level.ignore?

        name = RubyIndexer::Index.constant_name(node)
        return if name.nil?

        generate_hover(name, node.location)
      end

      #: (Prism::ConstantWriteNode node) -> void
      def on_constant_write_node_enter(node)
        return unless @sorbet_level.ignore?

        generate_hover(node.name.to_s, node.name_loc)
      end

      #: (Prism::ConstantPathNode node) -> void
      def on_constant_path_node_enter(node)
        return unless @sorbet_level.ignore?

        name = RubyIndexer::Index.constant_name(node)
        return if name.nil?

        generate_hover(name, node.location)
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_enter(node)
        return if @sorbet_level.true_or_higher? && self_receiver?(node)

        message = node.message
        return unless message

        # `not x` is parsed as a call to `!` whose message_loc slices to "not"
        if node.name == :! && message == "not"
          handle_keyword_documentation("not")
          return
        end

        handle_method_hover(message)
      end

      #: (Prism::GlobalVariableAndWriteNode node) -> void
      def on_global_variable_and_write_node_enter(node)
        handle_global_variable_hover(node.name.to_s)
      end

      #: (Prism::GlobalVariableOperatorWriteNode node) -> void
      def on_global_variable_operator_write_node_enter(node)
        handle_global_variable_hover(node.name.to_s)
      end

      #: (Prism::GlobalVariableOrWriteNode node) -> void
      def on_global_variable_or_write_node_enter(node)
        handle_global_variable_hover(node.name.to_s)
      end

      #: (Prism::GlobalVariableReadNode node) -> void
      def on_global_variable_read_node_enter(node)
        handle_global_variable_hover(node.name.to_s)
      end

      #: (Prism::GlobalVariableTargetNode node) -> void
      def on_global_variable_target_node_enter(node)
        handle_global_variable_hover(node.name.to_s)
      end

      #: (Prism::GlobalVariableWriteNode node) -> void
      def on_global_variable_write_node_enter(node)
        handle_global_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableReadNode node) -> void
      def on_instance_variable_read_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableWriteNode node) -> void
      def on_instance_variable_write_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableAndWriteNode node) -> void
      def on_instance_variable_and_write_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableOperatorWriteNode node) -> void
      def on_instance_variable_operator_write_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableOrWriteNode node) -> void
      def on_instance_variable_or_write_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableTargetNode node) -> void
      def on_instance_variable_target_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::SuperNode node) -> void
      def on_super_node_enter(node)
        handle_super_node_hover(node.keyword_loc)
      end

      #: (Prism::ForwardingSuperNode node) -> void
      def on_forwarding_super_node_enter(node)
        handle_super_node_hover(node.location)
      end

      #: (Prism::AliasGlobalVariableNode) -> void
      def on_alias_global_variable_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::AliasMethodNode) -> void
      def on_alias_method_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::AndNode) -> void
      def on_and_node_enter(node) = handle_keyword_at_location(node.operator_loc)

      #: (Prism::BeginNode) -> void
      def on_begin_node_enter(node) = handle_keyword_at_location(node.begin_keyword_loc, node.end_keyword_loc)

      #: (Prism::BlockNode) -> void
      def on_block_node_enter(node) = handle_keyword_at_location(node.opening_loc, node.closing_loc)

      #: (Prism::BreakNode) -> void
      def on_break_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::CaseMatchNode) -> void
      def on_case_match_node_enter(node) = handle_keyword_at_location(node.case_keyword_loc, node.end_keyword_loc)

      #: (Prism::CaseNode) -> void
      def on_case_node_enter(node) = handle_keyword_at_location(node.case_keyword_loc, node.end_keyword_loc)

      #: (Prism::ClassNode) -> void
      def on_class_node_enter(node) = handle_keyword_at_location(node.class_keyword_loc, node.end_keyword_loc)

      #: (Prism::SingletonClassNode) -> void
      def on_singleton_class_node_enter(node)
        handle_keyword_at_location(node.class_keyword_loc, node.end_keyword_loc)
      end

      #: (Prism::LambdaNode) -> void
      def on_lambda_node_enter(node) = handle_keyword_at_location(node.opening_loc, node.closing_loc)

      #: (Prism::DefNode) -> void
      def on_def_node_enter(node) = handle_keyword_at_location(node.def_keyword_loc, node.end_keyword_loc)

      #: (Prism::DefinedNode) -> void
      def on_defined_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::ElseNode) -> void
      def on_else_node_enter(node) = handle_keyword_at_location(node.else_keyword_loc, node.end_keyword_loc)

      #: (Prism::EnsureNode) -> void
      def on_ensure_node_enter(node) = handle_keyword_at_location(node.ensure_keyword_loc, node.end_keyword_loc)

      #: (Prism::FalseNode) -> void
      def on_false_node_enter(node) = handle_keyword_at_location(node.location)

      #: (Prism::ForNode) -> void
      def on_for_node_enter(node)
        handle_keyword_at_location(
          node.for_keyword_loc,
          node.in_keyword_loc,
          node.do_keyword_loc,
          node.end_keyword_loc,
        )
      end

      #: (Prism::IfNode) -> void
      def on_if_node_enter(node)
        handle_keyword_at_location(node.if_keyword_loc, node.then_keyword_loc, node.end_keyword_loc)
      end

      #: (Prism::InNode) -> void
      def on_in_node_enter(node) = handle_keyword_at_location(node.in_loc, node.then_loc)

      #: (Prism::ModuleNode) -> void
      def on_module_node_enter(node) = handle_keyword_at_location(node.module_keyword_loc, node.end_keyword_loc)

      #: (Prism::NextNode) -> void
      def on_next_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::NilNode) -> void
      def on_nil_node_enter(node) = handle_keyword_at_location(node.location)

      #: (Prism::OrNode) -> void
      def on_or_node_enter(node) = handle_keyword_at_location(node.operator_loc)

      #: (Prism::PostExecutionNode) -> void
      def on_post_execution_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::PreExecutionNode) -> void
      def on_pre_execution_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::RedoNode) -> void
      def on_redo_node_enter(node) = handle_keyword_at_location(node.location)

      #: (Prism::RescueModifierNode) -> void
      def on_rescue_modifier_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::RescueNode) -> void
      def on_rescue_node_enter(node) = handle_keyword_at_location(node.keyword_loc, node.then_keyword_loc)

      #: (Prism::RetryNode) -> void
      def on_retry_node_enter(node) = handle_keyword_at_location(node.location)

      #: (Prism::ReturnNode) -> void
      def on_return_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::SelfNode) -> void
      def on_self_node_enter(node) = handle_keyword_at_location(node.location)

      #: (Prism::SourceEncodingNode) -> void
      def on_source_encoding_node_enter(node) = handle_keyword_at_location(node.location)

      #: (Prism::SourceFileNode) -> void
      def on_source_file_node_enter(node) = handle_keyword_at_location(node.location)

      #: (Prism::SourceLineNode) -> void
      def on_source_line_node_enter(node) = handle_keyword_at_location(node.location)

      #: (Prism::TrueNode) -> void
      def on_true_node_enter(node) = handle_keyword_at_location(node.location)

      #: (Prism::UndefNode) -> void
      def on_undef_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::UnlessNode) -> void
      def on_unless_node_enter(node)
        handle_keyword_at_location(node.keyword_loc, node.then_keyword_loc, node.end_keyword_loc)
      end

      #: (Prism::UntilNode) -> void
      def on_until_node_enter(node) = handle_keyword_at_location(node.keyword_loc, node.do_keyword_loc, node.closing_loc)

      #: (Prism::WhenNode) -> void
      def on_when_node_enter(node) = handle_keyword_at_location(node.keyword_loc, node.then_keyword_loc)

      #: (Prism::WhileNode) -> void
      def on_while_node_enter(node) = handle_keyword_at_location(node.keyword_loc, node.do_keyword_loc, node.closing_loc)

      #: (Prism::YieldNode) -> void
      def on_yield_node_enter(node) = handle_keyword_at_location(node.keyword_loc)

      #: (Prism::ClassVariableAndWriteNode node) -> void
      def on_class_variable_and_write_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableOperatorWriteNode node) -> void
      def on_class_variable_operator_write_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableOrWriteNode node) -> void
      def on_class_variable_or_write_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableTargetNode node) -> void
      def on_class_variable_target_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableReadNode node) -> void
      def on_class_variable_read_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableWriteNode node) -> void
      def on_class_variable_write_node_enter(node)
        handle_variable_hover(node.name.to_s)
      end

      private

      #: ((Prism::InterpolatedStringNode | Prism::StringNode) node) -> void
      def generate_heredoc_hover(node)
        return unless node.heredoc?

        opening_content = node.opening_loc&.slice
        return unless opening_content

        match = /(<<(?<type>(-|~)?))(?<quote>['"`]?)(?<delimiter>\w+)\k<quote>/.match(opening_content)
        return unless match

        heredoc_delimiter = match.named_captures["delimiter"]

        if heredoc_delimiter
          message = if match["type"] == "~"
            "This is a squiggly heredoc definition using the `#{heredoc_delimiter}` delimiter. " \
              "Indentation will be ignored in the resulting string."
          else
            "This is a heredoc definition using the `#{heredoc_delimiter}` delimiter. " \
              "Indentation will be considered part of the string."
          end

          @response_builder.push(message, category: :documentation)
        end
      end

      #: (String) -> void
      def handle_keyword_documentation(name)
        keyword = @graph.keyword(name)
        return unless keyword

        @response_builder.push("```ruby\n#{keyword.name}\n```", category: :title)
        @response_builder.push(keyword.documentation, category: :documentation)
      end

      # Push keyword documentation when the cursor is on one of the provided locations. The keyword name is taken from
      # the covering location's slice so that operator forms (`&&`, `||`, `{`, `}`, ternary `? :`) yield no hover —
      # their slice is not a keyword in the Rubydex graph.
      #
      #: (*Prism::Location?) -> void
      def handle_keyword_at_location(*locations)
        loc = locations.find { |l| l && covers_position?(l, @position) }
        return unless loc

        handle_keyword_documentation(loc.slice)
      end

      #: (Prism::Location keyword_location) -> void
      def handle_super_node_hover(keyword_location)
        # Sorbet can handle the inherited-method hover on typed true or higher, but it does not surface keyword docs, so
        # we still push those
        unless @sorbet_level.true_or_higher?
          surrounding_method = @node_context.surrounding_method
          handle_method_hover(surrounding_method.name, inherited_only: true) if surrounding_method
        end

        handle_keyword_at_location(keyword_location)
      end

      #: (String message, ?inherited_only: bool) -> void
      def handle_method_hover(message, inherited_only: false)
        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        methods = @index.resolve_method(message, type.name, inherited_only: inherited_only)
        return unless methods

        first_method = methods.first #: as !nil

        title = "#{message}#{first_method.decorated_parameters}"
        title << first_method.formatted_signatures

        if type.is_a?(TypeInferrer::GuessedType)
          title << "\n\nGuessed receiver: #{type.name}"
          @response_builder.push("[Learn more about guessed types](#{GUESSED_TYPES_URL})\n", category: :links)
        end

        categorized_markdown_from_index_entries(title, methods).each do |category, content|
          @response_builder.push(content, category: category)
        end
      end

      #: (String name) -> void
      def handle_global_variable_hover(name)
        declaration = @graph[name]
        return unless declaration

        categorized_markdown_from_definitions(name, declaration.definitions).each do |category, content|
          @response_builder.push(content, category: category)
        end
      end

      # Handle class or instance variables. We collect all definitions across the ancestors of the type
      #
      #: (String name) -> void
      def handle_variable_hover(name)
        # Sorbet enforces that all variables be declared on typed strict or higher, which means it will be able to
        # provide all features for them
        return if @sorbet_level.strict?

        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        owner = @graph[type.name]
        return unless owner.is_a?(Rubydex::Namespace)

        owner.ancestors.each do |ancestor|
          member = ancestor.member(name)
          next unless member

          categorized_markdown_from_definitions(member.name, member.definitions).each do |category, content|
            @response_builder.push(content, category: category)
          end
        end
      end

      #: (String name, Prism::Location location) -> void
      def generate_hover(name, location)
        declaration = @graph.resolve_constant(name, @node_context.nesting)
        return unless declaration

        categorized_markdown_from_definitions(declaration.name, declaration.definitions).each do |category, content|
          @response_builder.push(content, category: category)
        end
      end

      #: (Prism::CallNode node) -> void
      def generate_gem_hover(node)
        first_argument = node.arguments&.arguments&.first
        return unless first_argument.is_a?(Prism::StringNode)

        spec = Gem::Specification.find_by_name(first_argument.content)
        return unless spec

        info = [
          spec.description,
          spec.summary,
          "This rubygem does not have a description or summary.",
        ].find { |text| !text.nil? && !text.empty? } #: String

        # Remove leading whitespace if a heredoc was used for the summary or description
        info = info.gsub(/^ +/, "")

        remote_url = [spec.homepage, spec.metadata["source_code_uri"]].compact.find do |page|
          page.start_with?(*ALLOWED_REMOTE_PROVIDERS)
        end

        @response_builder.push(
          "**#{spec.name}** (#{spec.version}) #{remote_url && " - [open remote](#{remote_url})"}",
          category: :title,
        )
        @response_builder.push(info, category: :documentation)
      rescue Gem::MissingSpecError
        # Do nothing if the spec cannot be found
      end
    end
  end
end
