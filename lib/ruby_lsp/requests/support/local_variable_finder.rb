# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      # Resolves local variables in a single document. Every read, write, target and parameter is grouped by the scope
      # that declares it, using the `depth` Prism assigns to each local variable node. This means that two locals with the
      # same name in different methods or blocks are kept apart, while a block that reads a local from its enclosing
      # method is correctly linked to it.
      #
      # Local variables can't be referenced from other files, so this never needs the index or a workspace scan.
      class LocalVariableFinder < Prism::Visitor
        # A single place where a local variable appears in the source
        class Occurrence
          # One of `:read`, `:write`, `:parameter`, `:keyword_parameter`, `:shorthand` or `:regexp_capture`.
          # `:shorthand` is a value omitted from a hash or keyword argument (`{ name: }`) or from a hash pattern
          # (`in { name: }`), where the name also acts as the key
          #: Symbol
          attr_reader :kind

          # The location of the variable's name only
          #: Prism::Location
          attr_reader :location

          #: (Prism::Location location, Symbol kind, write: bool) -> void
          def initialize(location, kind, write:)
            @location = location
            @kind = kind
            @write = write
          end

          # Whether this occurrence assigns the variable, which includes parameters
          #: -> bool
          def write?
            @write
          end
        end

        # A local variable and all of the places where it appears, in source order
        class Variable
          #: Symbol
          attr_reader :name

          #: Prism::Node
          attr_reader :scope

          #: Array[Occurrence]
          attr_reader :occurrences

          #: (Symbol name, Prism::Node scope) -> void
          def initialize(name, scope)
            @name = name
            @scope = scope
            @occurrences = [] #: Array[Occurrence]
          end

          # The parameter or first assignment that introduced the variable
          #: -> Occurrence?
          def declaration
            @occurrences.find(&:write?)
          end
        end

        class << self
          # Builds an LSP range for a location, accounting for the encoding negotiated with the client so that names after
          # multibyte characters are still placed correctly
          #: (Prism::Location location, (^(Integer arg0) -> Integer | Prism::CodeUnitsCache) code_units_cache) -> Interface::Range
          def range_for(location, code_units_cache)
            Interface::Range.new(
              start: Interface::Position.new(
                line: location.start_line - 1,
                character: location.cached_start_code_units_column(code_units_cache),
              ),
              end: Interface::Position.new(
                line: location.end_line - 1,
                character: location.cached_end_code_units_column(code_units_cache),
              ),
            )
          end
        end

        HARD_SCOPES = [
          Prism::ProgramNode,
          Prism::ClassNode,
          Prism::ModuleNode,
          Prism::SingletonClassNode,
          Prism::DefNode,
        ].freeze #: Array[singleton(Prism::Node)]

        #: (Prism::Node ast) -> void
        def initialize(ast)
          super()
          @scopes = [] #: Array[Prism::Node]
          @variables = {}.compare_by_identity #: Hash[Prism::Node, Hash[Symbol, Variable]]
          # The enclosing scope of every block and lambda, so we can walk up to the scopes they can see
          @parent_scopes = {}.compare_by_identity #: Hash[Prism::Node, Prism::Node]
          # Blocks and lambdas nested directly in each scope, without crossing a method or class boundary
          @child_scopes = {}.compare_by_identity #: Hash[Prism::Node, Array[Prism::Node]]
          # Names of method calls without receiver or arguments (e.g.: `foo`), per scope. A local with the same name would
          # shadow them
          @variable_calls = {}.compare_by_identity #: Hash[Prism::Node, Array[Symbol]]
          ast.accept(self)

          @variables.each_value do |variables|
            variables.each_value { |variable| variable.occurrences.sort_by! { |o| o.location.start_offset } }
          end
        end

        # Finds the local variable whose name covers the given position. A position right after the end of the name also
        # counts, so that requests work when the cursor is placed at the end of the identifier
        #: (Integer char_position, (^(Integer arg0) -> Integer | Prism::CodeUnitsCache) code_units_cache) -> [Variable, Occurrence]?
        def variable_at(char_position, code_units_cache)
          adjacent = nil #: [Variable, Occurrence]?

          @variables.each_value do |variables|
            variables.each_value do |variable|
              variable.occurrences.each do |occurrence|
                location = occurrence.location
                start_offset = location.cached_start_code_units_offset(code_units_cache)
                end_offset = location.cached_end_code_units_offset(code_units_cache)

                return [variable, occurrence] if start_offset <= char_position && char_position < end_offset

                adjacent ||= [variable, occurrence] if char_position == end_offset
              end
            end
          end

          adjacent
        end

        # Returns true if renaming `variable` to `new_name` would make it collide with another local or with a method
        # call that would then be shadowed
        #: (Variable variable, Symbol new_name) -> bool
        def name_in_use?(variable, new_name)
          visible = scopes_visible_from(variable.scope)

          visible.any? do |scope|
            locals_of(scope).include?(new_name) || @variable_calls[scope]&.include?(new_name)
          end
        end

        # @override
        #: (Prism::ProgramNode node) -> void
        def visit_program_node(node)
          with_scope(node) { super }
        end

        # @override
        #: (Prism::ClassNode node) -> void
        def visit_class_node(node)
          # The constant path and the superclass are evaluated in the enclosing scope
          visit(node.constant_path)
          visit(node.superclass)
          with_scope(node) { visit(node.body) }
        end

        # @override
        #: (Prism::ModuleNode node) -> void
        def visit_module_node(node)
          visit(node.constant_path)
          with_scope(node) { visit(node.body) }
        end

        # @override
        #: (Prism::SingletonClassNode node) -> void
        def visit_singleton_class_node(node)
          visit(node.expression)
          with_scope(node) { visit(node.body) }
        end

        # @override
        #: (Prism::DefNode node) -> void
        def visit_def_node(node)
          # The receiver in `def foo.bar` is evaluated in the enclosing scope
          visit(node.receiver)
          with_scope(node) do
            visit(node.parameters)
            visit(node.body)
          end
        end

        # @override
        #: (Prism::BlockNode node) -> void
        def visit_block_node(node)
          with_scope(node) { super }
        end

        # @override
        #: (Prism::LambdaNode node) -> void
        def visit_lambda_node(node)
          with_scope(node) { super }
        end

        # @override
        #: (Prism::LocalVariableReadNode node) -> void
        def visit_local_variable_read_node(node)
          add(node.name, node.depth, node.location, :read)
        end

        # @override
        #: (Prism::LocalVariableTargetNode node) -> void
        def visit_local_variable_target_node(node)
          add(node.name, node.depth, node.location, :write)
        end

        # @override
        #: (Prism::LocalVariableWriteNode node) -> void
        def visit_local_variable_write_node(node)
          add(node.name, node.depth, node.name_loc, :write)
          super
        end

        # @override
        #: (Prism::LocalVariableAndWriteNode node) -> void
        def visit_local_variable_and_write_node(node)
          add(node.name, node.depth, node.name_loc, :write)
          super
        end

        # @override
        #: (Prism::LocalVariableOrWriteNode node) -> void
        def visit_local_variable_or_write_node(node)
          add(node.name, node.depth, node.name_loc, :write)
          super
        end

        # @override
        #: (Prism::LocalVariableOperatorWriteNode node) -> void
        def visit_local_variable_operator_write_node(node)
          add(node.name, node.depth, node.name_loc, :write)
          super
        end

        # @override
        #: (Prism::RequiredParameterNode node) -> void
        def visit_required_parameter_node(node)
          add(node.name, 0, node.location, :parameter)
        end

        # @override
        #: (Prism::OptionalParameterNode node) -> void
        def visit_optional_parameter_node(node)
          add(node.name, 0, node.name_loc, :parameter)
          super
        end

        # @override
        #: (Prism::RestParameterNode node) -> void
        def visit_rest_parameter_node(node)
          add_named_parameter(node.name, node.name_loc, :parameter)
        end

        # @override
        #: (Prism::KeywordRestParameterNode node) -> void
        def visit_keyword_rest_parameter_node(node)
          add_named_parameter(node.name, node.name_loc, :parameter)
        end

        # @override
        #: (Prism::BlockParameterNode node) -> void
        def visit_block_parameter_node(node)
          add_named_parameter(node.name, node.name_loc, :parameter)
        end

        # @override
        #: (Prism::RequiredKeywordParameterNode node) -> void
        def visit_required_keyword_parameter_node(node)
          # The name location includes the trailing colon
          add(node.name, 0, name_only(node.name_loc, node.name), :keyword_parameter)
        end

        # @override
        #: (Prism::OptionalKeywordParameterNode node) -> void
        def visit_optional_keyword_parameter_node(node)
          add(node.name, 0, name_only(node.name_loc, node.name), :keyword_parameter)
          super
        end

        # @override
        #: (Prism::BlockLocalVariableNode node) -> void
        def visit_block_local_variable_node(node)
          add(node.name, 0, node.location, :write)
        end

        # @override
        #: (Prism::ImplicitNode node) -> void
        def visit_implicit_node(node)
          value = node.value

          case value
          when Prism::LocalVariableReadNode
            # In `{ name: }` the location of the value includes the colon
            add(value.name, value.depth, name_only(value.location, value.name), :shorthand, write: false)
          when Prism::LocalVariableTargetNode
            # `in { name: }` assigns the matched value to `name`
            add(value.name, value.depth, name_only(value.location, value.name), :shorthand, write: true)
          else
            super
          end
        end

        # @override
        #: (Prism::MatchWriteNode node) -> void
        def visit_match_write_node(node)
          # Named captures in `/(?<year>\d+)/ =~ string` define locals. The target nodes span the whole regexp, so we
          # find the location of the name inside of the capture group instead
          regexp = node.call.receiver

          node.targets.each do |target|
            next unless target.is_a?(Prism::LocalVariableTargetNode)

            locations = regexp.is_a?(Prism::RegularExpressionNode) ? capture_name_locations(regexp, target.name) : []
            # Even if we can't point at the name, we still need to register the local in its scope
            register_name(target.name, target.depth)
            locations.each { |location| add(target.name, target.depth, location, :regexp_capture) }
          end

          visit(node.call)
        end

        # @override
        #: (Prism::CallNode node) -> void
        def visit_call_node(node)
          scope = @scopes.last
          (@variable_calls[scope] ||= []) << node.name if scope && node.variable_call?
          super
        end

        private

        #: (Prism::Node scope) { -> void } -> void
        def with_scope(scope, &block)
          parent = @scopes.last

          if parent && !HARD_SCOPES.include?(scope.class)
            @parent_scopes[scope] = parent
            (@child_scopes[parent] ||= []) << scope
          end

          @scopes << scope
          block.call
        ensure
          @scopes.pop
        end

        #: (Symbol name, Integer depth, Prism::Location location, Symbol kind, ?write: bool) -> void
        def add(name, depth, location, kind, write: kind != :read)
          variable = register_name(name, depth)
          variable&.occurrences&.<<(Occurrence.new(location, kind, write: write))
        end

        #: (Symbol? name, Prism::Location? location, Symbol kind) -> void
        def add_named_parameter(name, location, kind)
          # Anonymous parameters such as `*`, `**` and `&` don't define a local we can reference
          return unless name && location

          add(name, 0, location, kind)
        end

        #: (Symbol name, Integer depth) -> Variable?
        def register_name(name, depth)
          # Numbered parameters (`_1`) can't be renamed or declared
          return if name.match?(/\A_[1-9]\z/)

          scope = @scopes[-1 - depth]
          return unless scope

          variables = (@variables[scope] ||= {})
          variables[name] ||= Variable.new(name, scope)
        end

        #: (Prism::Location location, Symbol name) -> Prism::Location
        def name_only(location, name)
          location.copy(length: name.to_s.bytesize)
        end

        # A regexp may repeat the same group name (e.g.: `/(?<n>a)|(?<n>b)/`), so we return all of them
        #: (Prism::RegularExpressionNode regexp, Symbol name) -> Array[Prism::Location]
        def capture_name_locations(regexp, name)
          content_location = regexp.content_loc
          content = content_location.slice
          name_length = name.to_s.bytesize
          locations = [] #: Array[Prism::Location]

          ["(?<#{name}>", "(?'#{name}'"].each do |group|
            search_from = 0

            loop do
              index = content.index(group, search_from)
              break unless index

              start_offset = content_location.start_offset + content[0, index + 3].to_s.bytesize
              locations << content_location.copy(start_offset: start_offset, length: name_length)
              search_from = index + group.length
            end
          end

          locations
        end

        # The declaring scope, the blocks it encloses and the blocks enclosing it all share the same locals
        #: (Prism::Node scope) -> Array[Prism::Node]
        def scopes_visible_from(scope)
          visible = [] #: Array[Prism::Node]
          pending = [scope]

          until pending.empty?
            current = pending.pop #: as !nil
            visible << current
            pending.concat(@child_scopes[current] || [])
          end

          parent = @parent_scopes[scope] #: Prism::Node?
          while parent
            visible << parent
            parent = @parent_scopes[parent]
          end

          visible
        end

        #: (Prism::Node scope) -> Array[Symbol]
        def locals_of(scope)
          case scope
          when Prism::ProgramNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode, Prism::DefNode,
            Prism::BlockNode, Prism::LambdaNode
            scope.locals
          else
            []
          end
        end
      end
    end
  end
end
