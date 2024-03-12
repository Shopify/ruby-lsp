# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module Common
        # WARNING: Methods in this class may be used by Ruby LSP addons such as
        # https://github.com/Shopify/ruby-lsp-rails, or addons by created by developers outside of Shopify, so be
        # cautious of changing anything.
        extend T::Sig
        extend T::Helpers

        requires_ancestor { Kernel }

        sig { params(node: Prism::Node).returns(Interface::Range) }
        def range_from_node(node)
          loc = node.location

          Interface::Range.new(
            start: Interface::Position.new(
              line: loc.start_line - 1,
              character: loc.start_column,
            ),
            end: Interface::Position.new(line: loc.end_line - 1, character: loc.end_column),
          )
        end

        sig { params(location: Prism::Location).returns(Interface::Range) }
        def range_from_location(location)
          Interface::Range.new(
            start: Interface::Position.new(
              line: location.start_line - 1,
              character: location.start_column,
            ),
            end: Interface::Position.new(line: location.end_line - 1, character: location.end_column),
          )
        end

        sig { params(node: T.nilable(Prism::Node), range: T.nilable(T::Range[Integer])).returns(T::Boolean) }
        def visible?(node, range)
          return true if range.nil?
          return false if node.nil?

          loc = node.location
          range.cover?(loc.start_line - 1) && range.cover?(loc.end_line - 1)
        end

        sig do
          params(
            node: Prism::Node,
            title: String,
            command_name: String,
            arguments: T.nilable(T::Array[T.untyped]),
            data: T.nilable(T::Hash[T.untyped, T.untyped]),
          ).returns(Interface::CodeLens)
        end
        def create_code_lens(node, title:, command_name:, arguments:, data:)
          range = range_from_node(node)

          Interface::CodeLens.new(
            range: range,
            command: Interface::Command.new(
              title: title,
              command: command_name,
              arguments: arguments,
            ),
            data: data,
          )
        end

        sig { params(file_path: String).returns(T.nilable(T::Boolean)) }
        def not_in_dependencies?(file_path)
          BUNDLE_PATH &&
            !file_path.start_with?(T.must(BUNDLE_PATH)) &&
            !file_path.start_with?(RbConfig::CONFIG["rubylibdir"])
        end

        sig { params(node: Prism::CallNode).returns(T::Boolean) }
        def self_receiver?(node)
          receiver = node.receiver
          receiver.nil? || receiver.is_a?(Prism::SelfNode)
        end

        sig do
          params(
            title: String,
            entries: T.any(T::Array[RubyIndexer::Entry], RubyIndexer::Entry),
          ).returns(T::Hash[Symbol, String])
        end
        def categorized_markdown_from_index_entries(title, entries)
          markdown_title = "```ruby\n#{title}\n```"
          definitions = []
          content = +""
          Array(entries).each do |entry|
            loc = entry.location

            # We always handle locations as zero based. However, for file links in Markdown we need them to be one
            # based, which is why instead of the usual subtraction of 1 to line numbers, we are actually adding 1 to
            # columns. The format for VS Code file URIs is
            # `file:///path/to/file.rb#Lstart_line,start_column-end_line,end_column`
            uri = URI::Generic.from_path(
              path: entry.file_path,
              fragment: "L#{loc.start_line},#{loc.start_column + 1}-#{loc.end_line},#{loc.end_column + 1}",
            )

            definitions << "[#{entry.file_name}](#{uri})"
            content << "\n\n#{entry.comments.join("\n")}" unless entry.comments.empty?
          end

          {
            title: markdown_title,
            links: "**Definitions**: #{definitions.join(" | ")}",
            documentation: content,
          }
        end

        sig do
          params(
            title: String,
            entries: T.any(T::Array[RubyIndexer::Entry], RubyIndexer::Entry),
          ).returns(String)
        end
        def markdown_from_index_entries(title, entries)
          categorized_markdown = categorized_markdown_from_index_entries(title, entries)

          <<~MARKDOWN.chomp
            #{categorized_markdown[:title]}

            #{categorized_markdown[:links]}

            #{categorized_markdown[:documentation]}
          MARKDOWN
        end

        sig do
          params(
            node: T.any(
              Prism::ConstantPathNode,
              Prism::ConstantReadNode,
              Prism::ConstantPathTargetNode,
            ),
          ).returns(T.nilable(String))
        end
        def constant_name(node)
          node.full_name
        rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
          nil
        end

        sig { params(node: T.any(Prism::ModuleNode, Prism::ClassNode)).returns(T.nilable(String)) }
        def namespace_constant_name(node)
          path = node.constant_path
          case path
          when Prism::ConstantPathNode, Prism::ConstantReadNode, Prism::ConstantPathTargetNode
            constant_name(path)
          end
        end
      end
    end
  end
end
