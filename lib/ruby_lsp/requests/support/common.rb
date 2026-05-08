# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      # @requires_ancestor: Kernel
      module Common
        # WARNING: Methods in this class may be used by Ruby LSP add-ons such as
        # https://github.com/Shopify/ruby-lsp-rails, or add-ons by created by developers outside of Shopify, so be
        # cautious of changing anything.

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

        #: (Prism::Location? location, Hash[Symbol, untyped] position) -> bool
        def covers_position?(location, position)
          return false unless location

          start_line = location.start_line - 1
          end_line = location.end_line - 1
          line = position[:line]
          character = position[:character]

          (start_line < line || (start_line == line && location.start_column <= character)) &&
            (end_line > line || (end_line == line && location.end_column >= character))
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

        # Returns true when a constant declaration is reachable from the call site. Private constants are only
        # reachable from within the namespace where they are defined.
        #
        #: (Rubydex::Declaration declaration, String value, NodeContext node_context) -> bool
        def constant_reachable_from_call_site?(declaration, value, node_context)
          return true unless declaration.is_a?(Rubydex::Visibility) && declaration.private?

          declaration.name == "#{node_context.fully_qualified_name}::#{value}"
        end

        # Returns true when a method is reachable from the call site, considering visibility and receiver type.
        # A method is reachable when:
        # - there's no concrete receiver type to compare against
        # - the call site is inside the receiver's own namespace (implicit/self call)
        # - it is public
        # - it is protected and the call site's class is in the same hierarchy as the method's defining class
        #
        # The `method_decl` is duck-typed to support `Rubydex::Method`, `RubyIndexer::Entry::Member` and
        # `RubyIndexer::Entry::MethodAlias`. All respond to `public?`, `private?` and `owner` (an object with a
        # `name` attribute).
        #
        #: ((Rubydex::Method | RubyIndexer::Entry::Member | RubyIndexer::Entry::MethodAlias) method_decl, TypeInferrer::Type? receiver_type, Rubydex::Graph graph, NodeContext node_context) -> bool
        def method_reachable_from_call_site?(method_decl, receiver_type, graph, node_context)
          return true unless receiver_type

          caller_namespace = node_context.fully_qualified_name
          return true if caller_namespace == receiver_type.name

          return true if method_decl.public?
          return false if method_decl.private?

          owner_name = method_decl.owner&.name
          return false unless owner_name

          caller_declaration = graph[caller_namespace]
          return false unless caller_declaration.is_a?(Rubydex::Namespace)

          caller_declaration.ancestors.any? { |ancestor| ancestor.name == owner_name }
        end

        #: (String, Enumerable[Rubydex::Definition], ?Integer?) -> Hash[Symbol, String]
        def categorized_markdown_from_definitions(title, definitions, max_entries = nil)
          markdown_title = "```ruby\n#{title}\n```"
          file_links = []
          content = +""
          defs = max_entries ? definitions.take(max_entries) : definitions
          defs.each do |definition|
            # For Markdown links, we need 1 based display locations
            loc = definition.location.to_display
            uri = URI(loc.uri)

            file_name = case uri.scheme
            when "file"
              full_path = uri.full_path #: as !nil
              File.basename(full_path)
            when "untitled"
              uri.opaque #: as !nil
            end

            # Omit the link for magic schemes like rubydex:built-in
            if file_name
              # The format for VS Code file URIs is `file:///path/to/file.rb#Lstart_line,start_column-end_line,end_column`
              string_uri = "#{loc.uri}#L#{loc.start_line},#{loc.start_column}-#{loc.end_line},#{loc.end_column}"
              file_links << "[#{file_name}](#{string_uri})"
            end

            content << "\n\n#{definition.comments.map { |comment| comment.string.delete_prefix("# ") }.join("\n")}" unless definition.comments.empty?
          end

          total_definitions = definitions.count

          additional_entries_text = if max_entries && total_definitions > max_entries
            additional = total_definitions - max_entries
            " | #{additional} other#{additional > 1 ? "s" : ""}"
          else
            ""
          end

          {
            title: markdown_title,
            links: "**Definitions**: #{file_links.join(" | ")}#{additional_entries_text}",
            documentation: content,
          }
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

        #: (String title, Enumerable[Rubydex::Definition] definitions, ?Integer? max_entries, ?extra_links: String?) -> String
        def markdown_from_definitions(title, definitions, max_entries = nil, extra_links: nil)
          categorized_markdown = categorized_markdown_from_definitions(title, definitions, max_entries)

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

        #: (RubyIndexer::Entry entry) -> Integer
        def kind_for_entry(entry)
          case entry
          when RubyIndexer::Entry::Class
            Constant::SymbolKind::CLASS
          when RubyIndexer::Entry::Module
            Constant::SymbolKind::NAMESPACE
          when RubyIndexer::Entry::Constant, RubyIndexer::Entry::UnresolvedConstantAlias, RubyIndexer::Entry::ConstantAlias
            Constant::SymbolKind::CONSTANT
          when RubyIndexer::Entry::Method, RubyIndexer::Entry::UnresolvedMethodAlias, RubyIndexer::Entry::MethodAlias
            entry.name == "initialize" ? Constant::SymbolKind::CONSTRUCTOR : Constant::SymbolKind::METHOD
          when RubyIndexer::Entry::Accessor
            Constant::SymbolKind::PROPERTY
          when RubyIndexer::Entry::InstanceVariable, RubyIndexer::Entry::ClassVariable
            Constant::SymbolKind::FIELD
          when RubyIndexer::Entry::GlobalVariable
            Constant::SymbolKind::VARIABLE
          else
            Constant::SymbolKind::NULL
          end
        end
      end
    end
  end
end
