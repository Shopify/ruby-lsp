# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class Hover
      include Requests::Support::Common

      ALLOWED_TARGETS = [
        Prism::BreakNode,
        Prism::CallNode,
        Prism::ConstantReadNode,
        Prism::ConstantWriteNode,
        Prism::ConstantPathNode,
        Prism::GlobalVariableAndWriteNode,
        Prism::GlobalVariableOperatorWriteNode,
        Prism::GlobalVariableOrWriteNode,
        Prism::GlobalVariableReadNode,
        Prism::GlobalVariableTargetNode,
        Prism::GlobalVariableWriteNode,
        Prism::InstanceVariableReadNode,
        Prism::InstanceVariableAndWriteNode,
        Prism::InstanceVariableOperatorWriteNode,
        Prism::InstanceVariableOrWriteNode,
        Prism::InstanceVariableTargetNode,
        Prism::InstanceVariableWriteNode,
        Prism::SymbolNode,
        Prism::StringNode,
        Prism::InterpolatedStringNode,
        Prism::SuperNode,
        Prism::ForwardingSuperNode,
        Prism::YieldNode,
        Prism::ClassVariableAndWriteNode,
        Prism::ClassVariableOperatorWriteNode,
        Prism::ClassVariableOrWriteNode,
        Prism::ClassVariableReadNode,
        Prism::ClassVariableTargetNode,
        Prism::ClassVariableWriteNode,
      ] #: Array[singleton(Prism::Node)]

      ALLOWED_REMOTE_PROVIDERS = [
        "https://github.com",
        "https://gitlab.com",
      ].freeze #: Array[String]

      #: (ResponseBuilders::Hover response_builder, GlobalState global_state, URI::Generic uri, NodeContext node_context, Prism::Dispatcher dispatcher, SorbetLevel sorbet_level) -> void
      def initialize(response_builder, global_state, uri, node_context, dispatcher, sorbet_level) # rubocop:disable Metrics/ParameterLists
        @response_builder = response_builder
        @global_state = global_state
        @index = global_state.index #: RubyIndexer::Index
        @type_inferrer = global_state.type_inferrer #: TypeInferrer
        @path = uri.to_standardized_path #: String?
        @node_context = node_context
        @sorbet_level = sorbet_level

        dispatcher.register(
          self,
          :on_break_node_enter,
          :on_constant_read_node_enter,
          :on_constant_write_node_enter,
          :on_constant_path_node_enter,
          :on_call_node_enter,
          :on_global_variable_and_write_node_enter,
          :on_global_variable_operator_write_node_enter,
          :on_global_variable_or_write_node_enter,
          :on_global_variable_read_node_enter,
          :on_global_variable_target_node_enter,
          :on_global_variable_write_node_enter,
          :on_instance_variable_read_node_enter,
          :on_instance_variable_write_node_enter,
          :on_instance_variable_and_write_node_enter,
          :on_instance_variable_operator_write_node_enter,
          :on_instance_variable_or_write_node_enter,
          :on_instance_variable_target_node_enter,
          :on_super_node_enter,
          :on_forwarding_super_node_enter,
          :on_string_node_enter,
          :on_interpolated_string_node_enter,
          :on_yield_node_enter,
          :on_class_variable_and_write_node_enter,
          :on_class_variable_operator_write_node_enter,
          :on_class_variable_or_write_node_enter,
          :on_class_variable_read_node_enter,
          :on_class_variable_target_node_enter,
          :on_class_variable_write_node_enter,
        )
      end

      #: (Prism::BreakNode node) -> void
      def on_break_node_enter(node)
        handle_keyword_documentation(node.keyword)
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
        handle_instance_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableWriteNode node) -> void
      def on_instance_variable_write_node_enter(node)
        handle_instance_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableAndWriteNode node) -> void
      def on_instance_variable_and_write_node_enter(node)
        handle_instance_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableOperatorWriteNode node) -> void
      def on_instance_variable_operator_write_node_enter(node)
        handle_instance_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableOrWriteNode node) -> void
      def on_instance_variable_or_write_node_enter(node)
        handle_instance_variable_hover(node.name.to_s)
      end

      #: (Prism::InstanceVariableTargetNode node) -> void
      def on_instance_variable_target_node_enter(node)
        handle_instance_variable_hover(node.name.to_s)
      end

      #: (Prism::SuperNode node) -> void
      def on_super_node_enter(node)
        handle_super_node_hover
      end

      #: (Prism::ForwardingSuperNode node) -> void
      def on_forwarding_super_node_enter(node)
        handle_super_node_hover
      end

      #: (Prism::YieldNode node) -> void
      def on_yield_node_enter(node)
        handle_keyword_documentation(node.keyword)
      end

      #: (Prism::ClassVariableAndWriteNode node) -> void
      def on_class_variable_and_write_node_enter(node)
        handle_class_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableOperatorWriteNode node) -> void
      def on_class_variable_operator_write_node_enter(node)
        handle_class_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableOrWriteNode node) -> void
      def on_class_variable_or_write_node_enter(node)
        handle_class_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableTargetNode node) -> void
      def on_class_variable_target_node_enter(node)
        handle_class_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableReadNode node) -> void
      def on_class_variable_read_node_enter(node)
        handle_class_variable_hover(node.name.to_s)
      end

      #: (Prism::ClassVariableWriteNode node) -> void
      def on_class_variable_write_node_enter(node)
        handle_class_variable_hover(node.name.to_s)
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

      #: (String keyword) -> void
      def handle_keyword_documentation(keyword)
        content = KEYWORD_DOCS[keyword]
        return unless content

        doc_uri = URI::Generic.from_path(path: File.join(STATIC_DOCS_PATH, "#{keyword}.md"))

        @response_builder.push("```ruby\n#{keyword}\n```", category: :title)
        @response_builder.push("[Read more](#{doc_uri})", category: :links)
        @response_builder.push(content, category: :documentation)
      end

      #: -> void
      def handle_super_node_hover
        # Sorbet can handle super hover on typed true or higher
        return if @sorbet_level.true_or_higher?

        surrounding_method = @node_context.surrounding_method
        return unless surrounding_method

        handle_method_hover(surrounding_method, inherited_only: true)
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
      def handle_instance_variable_hover(name)
        # Sorbet enforces that all instance variables be declared on typed strict or higher, which means it will be able
        # to provide all features for them
        return if @sorbet_level.strict?

        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        entries = @index.resolve_instance_variable(name, type.name)
        return unless entries

        categorized_markdown_from_index_entries(name, entries).each do |category, content|
          @response_builder.push(content, category: category)
        end
      rescue RubyIndexer::Index::NonExistingNamespaceError
        # If by any chance we haven't indexed the owner, then there's no way to find the right declaration
      end

      #: (String name) -> void
      def handle_global_variable_hover(name)
        entries = @index[name]
        return unless entries

        categorized_markdown_from_index_entries(name, entries).each do |category, content|
          @response_builder.push(content, category: category)
        end
      end

      #: (String name) -> void
      def handle_class_variable_hover(name)
        type = @type_inferrer.infer_receiver_type(@node_context)
        return unless type

        entries = @index.resolve_class_variable(name, type.name)
        return unless entries

        categorized_markdown_from_index_entries(name, entries).each do |category, content|
          @response_builder.push(content, category: category)
        end
      rescue RubyIndexer::Index::NonExistingNamespaceError
        # If by any chance we haven't indexed the owner, then there's no way to find the right declaration
      end

      #: (String name, Prism::Location location) -> void
      def generate_hover(name, location)
        entries = @index.resolve(name, @node_context.nesting)
        return unless entries

        # We should only show hover for private constants if the constant is defined in the same namespace as the
        # reference
        first_entry = entries.first #: as !nil
        full_name = first_entry.name
        return if first_entry.private? && full_name != "#{@node_context.fully_qualified_name}::#{name}"

        categorized_markdown_from_index_entries(full_name, entries).each do |category, content|
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
