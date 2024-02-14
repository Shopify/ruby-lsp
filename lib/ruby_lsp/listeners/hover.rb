# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class Hover
      extend T::Sig
      include Requests::Support::Common

      ALLOWED_TARGETS = T.let(
        [
          Prism::CallNode,
          Prism::ConstantReadNode,
          Prism::ConstantWriteNode,
          Prism::ConstantPathNode,
        ],
        T::Array[T.class_of(Prism::Node)],
      )

      ALLOWED_REMOTE_PROVIDERS = T.let(
        [
          "https://github.com",
          "https://gitlab.com",
        ].freeze,
        T::Array[String],
      )

      sig do
        params(
          response_builder: ResponseBuilders::Hover,
          uri: URI::Generic,
          nesting: T::Array[String],
          index: RubyIndexer::Index,
          dispatcher: Prism::Dispatcher,
          typechecker_enabled: T::Boolean,
        ).void
      end
      def initialize(response_builder, uri, nesting, index, dispatcher, typechecker_enabled) # rubocop:disable Metrics/ParameterLists
        @response_builder = response_builder
        @path = T.let(uri.to_standardized_path, T.nilable(String))
        @nesting = nesting
        @index = index
        @typechecker_enabled = typechecker_enabled

        dispatcher.register(
          self,
          :on_constant_read_node_enter,
          :on_constant_write_node_enter,
          :on_constant_path_node_enter,
          :on_call_node_enter,
        )
      end

      sig { params(node: Prism::ConstantReadNode).void }
      def on_constant_read_node_enter(node)
        return if @typechecker_enabled

        name = constant_name(node)
        return if name.nil?

        generate_hover(name, node.location)
      end

      sig { params(node: Prism::ConstantWriteNode).void }
      def on_constant_write_node_enter(node)
        return if DependencyDetector.instance.typechecker

        generate_hover(node.name.to_s, node.name_loc)
      end

      sig { params(node: Prism::ConstantPathNode).void }
      def on_constant_path_node_enter(node)
        return if DependencyDetector.instance.typechecker

        name = constant_name(node)
        return if name.nil?

        generate_hover(name, node.location)
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        return unless self_receiver?(node)

        if @path && File.basename(@path) == GEMFILE_NAME && node.name == :gem
          generate_gem_hover(node)
          return
        end

        return if @typechecker_enabled

        message = node.message
        return unless message

        methods = @index.resolve_method(message, @nesting.join("::"))
        return unless methods

        categorized_markdown_from_index_entries(message, methods).each do |category, content|
          @response_builder.push(content, category: category)
        end
      end

      private

      sig { params(name: String, location: Prism::Location).void }
      def generate_hover(name, location)
        entries = @index.resolve(name, @nesting)
        return unless entries

        # We should only show hover for private constants if the constant is defined in the same namespace as the
        # reference
        first_entry = T.must(entries.first)
        return if first_entry.visibility == :private && first_entry.name != "#{@nesting.join("::")}::#{name}"

        categorized_markdown_from_index_entries(name, entries).each do |category, content|
          @response_builder.push(content, category: category)
        end
      end

      sig { params(node: Prism::CallNode).void }
      def generate_gem_hover(node)
        first_argument = node.arguments&.arguments&.first
        return unless first_argument.is_a?(Prism::StringNode)

        spec = Gem::Specification.find_by_name(first_argument.content)
        return unless spec

        info = T.let(
          [
            spec.description,
            spec.summary,
            "This rubygem does not have a description or summary.",
          ].find { |text| !text.nil? && !text.empty? },
          String,
        )

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
