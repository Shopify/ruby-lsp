# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module Common
        # WARNING: Methods in this class may be used by Ruby LSP add-ons such as
        # https://github.com/Shopify/ruby-lsp-rails, or add-ons by created by developers outside of Shopify, so be
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

        sig { params(location: T.any(Prism::Location, RubyIndexer::Location)).returns(Interface::Range) }
        def range_from_location(location)
          Interface::Range.new(
            start: Interface::Position.new(
              line: location.start_line - 1,
              character: location.start_column,
            ),
            end: Interface::Position.new(line: location.end_line - 1, character: location.end_column),
          )
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
            max_entries: T.nilable(Integer),
          ).returns(T::Hash[Symbol, String])
        end
        def categorized_markdown_from_index_entries(title, entries, max_entries = nil)
          markdown_title = "```ruby\n#{title}\n```"
          definitions = []
          content = +""
          entries = Array(entries)
          entries_to_format = max_entries ? entries.take(max_entries) : entries
          entries_to_format.each do |entry|
            loc = entry.location

            # We always handle locations as zero based. However, for file links in Markdown we need them to be one
            # based, which is why instead of the usual subtraction of 1 to line numbers, we are actually adding 1 to
            # columns. The format for VS Code file URIs is
            # `file:///path/to/file.rb#Lstart_line,start_column-end_line,end_column`
            uri = "#{entry.uri}#L#{loc.start_line},#{loc.start_column + 1}-#{loc.end_line},#{loc.end_column + 1}"
            definitions << "[#{entry.file_name}](#{uri})"
            content << "\n\n#{entry.comments}" unless entry.comments.empty?
          end

          additional_entries_text = if max_entries && entries.length > max_entries
            additional = entries.length - max_entries
            " | #{additional} other#{additional > 1 ? "s" : ""}"
          else
            ""
          end

          {
            title: markdown_title,
            links: "**Definitions**: #{definitions.join(" | ")}#{additional_entries_text}",
            documentation: content,
          }
        end

        sig do
          params(
            title: String,
            entries: T.any(T::Array[RubyIndexer::Entry], RubyIndexer::Entry),
            max_entries: T.nilable(Integer),
            extra_links: T.nilable(String),
          ).returns(String)
        end
        def markdown_from_index_entries(title, entries, max_entries = nil, extra_links: nil)
          categorized_markdown = categorized_markdown_from_index_entries(title, entries, max_entries)

          markdown = +(categorized_markdown[:title] || "")
          markdown << "\n\n#{extra_links}" if extra_links

          <<~MARKDOWN.chomp
            #{markdown}

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
        rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
               Prism::ConstantPathNode::MissingNodesInConstantPathError
          nil
        end

        sig { params(node: T.any(Prism::ModuleNode, Prism::ClassNode)).returns(T.nilable(String)) }
        def namespace_constant_name(node)
          path = node.constant_path
          case path
          when Prism::ConstantPathNode, Prism::ConstantReadNode
            constant_name(path)
          end
        end

        # Iterates over each part of a constant path, so that we can easily push response items for each section of the
        # name. For example, for `Foo::Bar::Baz`, this method will invoke the block with `Foo`, then `Bar` and finally
        # `Baz`.
        sig do
          params(
            node: Prism::Node,
            block: T.proc.params(part: Prism::Node).void,
          ).void
        end
        def each_constant_path_part(node, &block)
          current = T.let(node, T.nilable(Prism::Node))

          while current.is_a?(Prism::ConstantPathNode)
            block.call(current)
            current = current.parent
          end
        end

        sig { params(entry: RubyIndexer::Entry).returns(T.nilable(Integer)) }
        def kind_for_entry(entry)
          case entry
          when RubyIndexer::Entry::Class
            Constant::SymbolKind::CLASS
          when RubyIndexer::Entry::Module
            Constant::SymbolKind::NAMESPACE
          when RubyIndexer::Entry::Constant
            Constant::SymbolKind::CONSTANT
          when RubyIndexer::Entry::Method
            entry.name == "initialize" ? Constant::SymbolKind::CONSTRUCTOR : Constant::SymbolKind::METHOD
          when RubyIndexer::Entry::Accessor
            Constant::SymbolKind::PROPERTY
          when RubyIndexer::Entry::InstanceVariable
            Constant::SymbolKind::FIELD
          end
        end

        sig { params(sorbet_level: RubyDocument::SorbetLevel).returns(T::Boolean) }
        def sorbet_level_true_or_higher?(sorbet_level)
          sorbet_level == RubyDocument::SorbetLevel::True || sorbet_level == RubyDocument::SorbetLevel::Strict
        end
      end
    end
  end
end
