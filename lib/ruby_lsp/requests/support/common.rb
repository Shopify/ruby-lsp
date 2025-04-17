# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module Common
        # WARNING: Methods in this class may be used by Ruby LSP add-ons such as
        # https://github.com/Shopify/ruby-lsp-rails, or add-ons by created by developers outside of Shopify, so be
        # cautious of changing anything.
        extend T::Helpers

        requires_ancestor { Kernel }

        #: (Prism::Node node) -> Interface::Range
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

        #: ((Prism::Location | RubyIndexer::Location) location) -> Interface::Range
        def range_from_location(location)
          Interface::Range.new(
            start: Interface::Position.new(
              line: location.start_line - 1,
              character: location.start_column,
            ),
            end: Interface::Position.new(line: location.end_line - 1, character: location.end_column),
          )
        end

        #: (Prism::Node node, title: String, command_name: String, arguments: Array[untyped]?, data: Hash[untyped, untyped]?) -> Interface::CodeLens
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

        #: (String file_path) -> bool?
        def not_in_dependencies?(file_path)
          BUNDLE_PATH &&
            !file_path.start_with?(
              BUNDLE_PATH, #: as !nil
            ) &&
            !file_path.start_with?(RbConfig::CONFIG["rubylibdir"])
        end

        #: (Prism::CallNode node) -> bool
        def self_receiver?(node)
          receiver = node.receiver
          receiver.nil? || receiver.is_a?(Prism::SelfNode)
        end

        #: (String title, (Array[RubyIndexer::Entry] | RubyIndexer::Entry) entries, ?Integer? max_entries) -> Hash[Symbol, String]
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

        #: (String title, (Array[RubyIndexer::Entry] | RubyIndexer::Entry) entries, ?Integer? max_entries, ?extra_links: String?) -> String
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

        #: ((Prism::ConstantPathNode | Prism::ConstantReadNode | Prism::ConstantPathTargetNode | Prism::CallNode | Prism::MissingNode) node) -> String?
        def constant_name(node)
          RubyIndexer::Index.constant_name(node)
        end

        #: ((Prism::ModuleNode | Prism::ClassNode) node) -> String?
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
        #: (Prism::Node node) { (Prism::Node part) -> void } -> void
        def each_constant_path_part(node, &block)
          current = node #: Prism::Node?

          while current.is_a?(Prism::ConstantPathNode)
            block.call(current)
            current = current.parent
          end
        end

        #: (RubyIndexer::Entry entry) -> Integer?
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

        #: (RubyDocument::SorbetLevel sorbet_level) -> bool
        def sorbet_level_true_or_higher?(sorbet_level)
          sorbet_level == RubyDocument::SorbetLevel::True || sorbet_level == RubyDocument::SorbetLevel::Strict
        end
      end
    end
  end
end
