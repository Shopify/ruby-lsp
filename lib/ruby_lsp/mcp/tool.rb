# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/common"

module RubyLsp
  module MCP
    # @abstract
    class Tool
      include RubyLsp::Requests::Support::Common

      MAX_CLASSES_TO_RETURN = 5000

      @tools = {} #: Hash[String, singleton(Tool)]

      #: (RubyIndexer::Index, Hash[Symbol, untyped]) -> void
      def initialize(index, arguments)
        @index = index #: RubyIndexer::Index
        @arguments = arguments #: Hash[Symbol, untyped]
      end

      # @abstract
      #: -> Array[Hash[Symbol, untyped]]
      def perform; end

      class << self
        #: Hash[String, singleton(Tool)]
        attr_reader :tools

        #: (singleton(Tool)) -> void
        def register(tool_class)
          tools[tool_class.name] = tool_class
        end

        #: (String) -> singleton(Tool)?
        def get(name)
          tools[name]
        end

        # @abstract
        #: -> String
        def name; end

        # @abstract
        #: -> String
        def description; end

        # @abstract
        #: -> Hash[Symbol, untyped]
        def input_schema; end
      end
    end

    class GetClassModuleDetails < Tool
      class << self
        # @override
        #: -> String
        def name
          "get_class_module_details"
        end

        # @override
        #: -> String
        def description
          "Show details of classes/modules including comments, definition location, methods, and ancestors." +
            "Use get_methods_details for specific method details."
        end

        # @override
        #: -> Hash[Symbol, untyped]
        def input_schema
          {
            type: "object",
            properties: {
              fully_qualified_names: { type: "array", items: { type: "string" } },
            },
          }
        end
      end

      # @override
      #: -> Array[Hash[Symbol, untyped]]
      def perform
        fully_qualified_names = @arguments[:fully_qualified_names]
        fully_qualified_names.map do |fully_qualified_name|
          *nestings, name = fully_qualified_name.delete_prefix("::").split("::")
          entries = @index.resolve(name, nestings) || []

          begin
            ancestors = @index.linearized_ancestors_of(fully_qualified_name)
            methods = @index.method_completion_candidates(nil, fully_qualified_name)
          rescue RubyIndexer::Index::NonExistingNamespaceError
            # If the namespace doesn't exist, we can't find ancestors or methods
            ancestors = []
            methods = []
          end

          type = case entries.first
          when RubyIndexer::Entry::Class
            "class"
          when RubyIndexer::Entry::Module
            "module"
          else
            "unknown"
          end

          {
            type: "text",
            text: {
              name: fully_qualified_name,
              nestings: nestings,
              type: type,
              ancestors: ancestors,
              methods: methods.map(&:name),
              uris: entries.map { |entry| entry.uri.to_s },
              documentation: markdown_from_index_entries(name, entries),
            }.to_yaml,
          }
        end
      end
    end

    class GetMethodsDetails < Tool
      class << self
        # @override
        #: -> String
        def name
          "get_methods_details"
        end

        # @override
        #: -> String
        def description
          "Show method details including comments, location, visibility, parameters, and owner." +
            "Use Class#method, Module#method, Class.singleton_method, or Module.singleton_method format."
        end

        # @override
        #: -> Hash[Symbol, untyped]
        def input_schema
          {
            type: "object",
            properties: {
              signatures: { type: "array", items: { type: "string" } },
            },
          }
        end
      end

      # @override
      #: -> Array[Hash[Symbol, untyped]]
      def perform
        signatures = @arguments[:signatures]
        signatures.map do |signature|
          entries = nil
          receiver = nil
          method = nil

          if signature.include?("#")
            receiver, method = signature.split("#")
            entries = @index.resolve_method(method, receiver)
          elsif signature.include?(".")
            receiver, method = signature.split(".")
            singleton_class = @index.existing_or_new_singleton_class(receiver)
            entries = @index.resolve_method(method, singleton_class.name)
          end

          next if entries.nil?

          entry_details = entries.map do |entry|
            {
              uri: entry.uri.to_s,
              visibility: entry.visibility,
              comments: entry.comments,
              parameters: entry.decorated_parameters,
              owner: entry.owner&.name,
            }
          end

          {
            type: "text",
            text: {
              receiver: receiver,
              method: method,
              entry_details: entry_details,
            }.to_yaml,
          }
        end.compact
      end
    end

    class GetClassesAndModules < Tool
      class << self
        # @override
        #: -> String
        def name
          "get_classes_and_modules"
        end

        # @override
        #: -> String
        def description
          "Show all indexed classes and modules in the project and dependencies. When query provided, returns filtered matches. Stops after #{Tool::MAX_CLASSES_TO_RETURN} results." +
            "Use get_class_module_details to get the details of a specific class or module."
        end

        # @override
        #: -> Hash[Symbol, untyped]
        def input_schema
          {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "A query to filter the classes and modules",
              },
            },
          }
        end
      end

      # @override
      #: -> Array[Hash[Symbol, untyped]]
      def perform
        query = @arguments[:query]
        class_names = @index.fuzzy_search(query).map do |entry|
          case entry
          when RubyIndexer::Entry::Class
            {
              name: entry.name,
              type: "class",
            }
          when RubyIndexer::Entry::Module
            {
              name: entry.name,
              type: "module",
            }
          end
        end.compact.uniq

        if class_names.size > MAX_CLASSES_TO_RETURN
          [
            {
              type: "text",
              text: "Too many classes and modules to return, please narrow down your request with a query.",
            },
            {
              type: "text",
              text: class_names.first(MAX_CLASSES_TO_RETURN).to_yaml,
            },
          ]
        else
          [
            {
              type: "text",
              text: class_names.to_yaml,
            },
          ]
        end
      end
    end

    Tool.register(GetClassesAndModules)
    Tool.register(GetMethodsDetails)
    Tool.register(GetClassModuleDetails)
  end
end
