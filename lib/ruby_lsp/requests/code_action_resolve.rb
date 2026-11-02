# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [code action resolve](https://microsoft.github.io/language-server-protocol/specification#codeAction_resolve)
    # request is used to to resolve the edit field for a given code action, if it is not already provided in the
    # textDocument/codeAction response. We can use it for scenarios that require more computation such as refactoring.
    class CodeActionResolve < Request
      include Support::Common

      NEW_VARIABLE_NAME = "new_variable"
      NEW_METHOD_NAME = "new_method"

      # The nodes that start a new local variable scope
      SCOPE_NODES = [
        Prism::ProgramNode,
        Prism::DefNode,
        Prism::ClassNode,
        Prism::ModuleNode,
        Prism::SingletonClassNode,
        Prism::BlockNode,
        Prism::LambdaNode,
      ] #: Array[singleton(Prism::Node)]

      # Binding strength of the operators an inlined value can contain, from loosest to tightest. Operators that are
      # methods are keyed by name
      OPERATOR_PRECEDENCE = {
        ternary: 0,
        range: 1,
        "||": 2,
        "&&": 3,
        "<=>": 4,
        "==": 4,
        "===": 4,
        "!=": 4,
        "=~": 4,
        "!~": 4,
        ">": 5,
        ">=": 5,
        "<": 5,
        "<=": 5,
        "|": 6,
        "^": 6,
        "&": 7,
        "<<": 8,
        ">>": 8,
        "+": 9,
        "-": 9,
        "*": 10,
        "/": 10,
        "%": 10,
        "-@": 11,
        "**": 12,
        "!": 13,
        "~": 13,
        "+@": 13,
      } #: Hash[Symbol, Integer]

      # Operators an inlined value may repeat without changing what the code does. `<<` is left out because it appends
      # to its receiver
      PURE_OPERATORS = (OPERATOR_PRECEDENCE.keys - [:ternary, :range, :"||", :"&&", :<<]).freeze #: Array[Symbol]

      class CodeActionError < StandardError; end
      class EmptySelectionError < CodeActionError; end
      class InvalidTargetRangeError < CodeActionError; end
      class UnknownCodeActionError < CodeActionError; end

      #: (RubyDocument document, GlobalState global_state, Hash[Symbol, untyped] code_action) -> void
      def initialize(document, global_state, code_action)
        super()
        @document = document
        @global_state = global_state
        @code_action = code_action
      end

      # @override
      #: -> (Interface::CodeAction)
      def perform
        raise EmptySelectionError, "Invalid selection for refactor" if @document.source.empty?

        case @code_action[:title]
        when CodeActions::EXTRACT_TO_VARIABLE_TITLE
          refactor_variable
        when CodeActions::EXTRACT_TO_METHOD_TITLE
          refactor_method
        when CodeActions::TOGGLE_BLOCK_STYLE_TITLE
          switch_block_style
        when CodeActions::INLINE_VARIABLE_TITLE
          inline_variable
        when CodeActions::CREATE_ATTRIBUTE_READER,
             CodeActions::CREATE_ATTRIBUTE_WRITER,
             CodeActions::CREATE_ATTRIBUTE_ACCESSOR
          create_attribute_accessor
        else
          raise UnknownCodeActionError, "Unknown code action: #{@code_action[:title]}"
        end
      end

      private

      #: -> (Interface::CodeAction)
      def switch_block_style
        source_range = @code_action.dig(:data, :range)
        if source_range[:start] == source_range[:end]
          block_context = @document.locate_node(
            source_range[:start],
            node_types: [Prism::BlockNode],
          )
          node = block_context.node
          unless node.is_a?(Prism::BlockNode)
            raise InvalidTargetRangeError, "Cursor is not inside a block"
          end

          # Find the call node at the block node's start position.
          # This should be the call node whose block the cursor is inside of.
          call_context = RubyDocument.locate(
            @document.ast,
            node.location.cached_start_code_units_offset(@document.code_units_cache),
            node_types: [Prism::CallNode],
            code_units_cache: @document.code_units_cache,
          )
          target = call_context.node
          unless target.is_a?(Prism::CallNode) && target.block == node
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end
        else
          target = @document.locate_first_within_range(
            @code_action.dig(:data, :range),
            node_types: [Prism::CallNode],
          )

          unless target.is_a?(Prism::CallNode)
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end

          node = target.block
          unless node.is_a?(Prism::BlockNode)
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end
        end

        indentation = " " * target.location.start_column unless node.opening_loc.slice == "do"

        Interface::CodeAction.new(
          title: CodeActions::TOGGLE_BLOCK_STYLE_TITLE,
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: [
                  Interface::TextEdit.new(
                    range: range_from_location(node.location),
                    new_text: recursively_switch_nested_block_styles(node, indentation),
                  ),
                ],
              ),
            ],
          ),
        )
      end

      #: -> (Interface::CodeAction)
      def refactor_variable
        source_range = @code_action.dig(:data, :range)
        raise EmptySelectionError, "Invalid selection for refactor" if source_range[:start] == source_range[:end]

        start_index, end_index = @document.find_index_by_position(source_range[:start], source_range[:end])
        extracted_source = @document.source[start_index...end_index] #: as !nil

        # Find the closest statements node, so that we place the refactor in a valid position
        node_context = RubyDocument
          .locate(@document.ast,
            start_index,
            node_types: [
              Prism::StatementsNode,
              Prism::BlockNode,
            ],
            code_units_cache: @document.code_units_cache)

        closest_statements = node_context.node
        parent_statements = node_context.parent
        if closest_statements.nil? || closest_statements.child_nodes.compact.empty?
          raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
        end

        # Find the node with the end line closest to the requested position, so that we can place the refactor
        # immediately after that closest node
        closest_node = closest_statements.child_nodes.compact.min_by do |node|
          distance = source_range.dig(:start, :line) - (node.location.end_line - 1)
          distance <= 0 ? Float::INFINITY : distance
        end #: as !nil

        if closest_node.is_a?(Prism::MissingNode)
          raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
        end

        closest_node_loc = closest_node.location
        # If the parent expression is a single line block, then we have to extract it inside of the one-line block
        if parent_statements.is_a?(Prism::BlockNode) &&
            parent_statements.location.start_line == parent_statements.location.end_line

          variable_source = " #{NEW_VARIABLE_NAME} = #{extracted_source};"
          character = source_range.dig(:start, :character) - 1
          target_range = {
            start: { line: closest_node_loc.end_line - 1, character: character },
            end: { line: closest_node_loc.end_line - 1, character: character },
          }
        else
          # If the closest node covers the requested location, then we're extracting a statement nested inside of it. In
          # that case, we want to place the extraction at the start of the closest node (one line above). Otherwise, we
          # want to place the extract right below the closest node
          if closest_node_loc.start_line - 1 <= source_range.dig(
            :start,
            :line,
          ) && closest_node_loc.end_line - 1 >= source_range.dig(:end, :line)
            indentation_line_number = closest_node_loc.start_line - 1
            target_line = indentation_line_number
          else
            target_line = closest_node_loc.end_line
            indentation_line_number = closest_node_loc.end_line - 1
          end

          lines = @document.source.lines

          indentation_line = lines[indentation_line_number]
          unless indentation_line
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end

          indentation = indentation_line[/\A */] #: as !nil
            .size

          target_range = {
            start: { line: target_line, character: indentation },
            end: { line: target_line, character: indentation },
          }

          line = lines[target_line]
          unless line
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end

          variable_source = if line.strip.empty?
            "\n#{" " * indentation}#{NEW_VARIABLE_NAME} = #{extracted_source}"
          else
            "#{NEW_VARIABLE_NAME} = #{extracted_source}\n#{" " * indentation}"
          end
        end

        Interface::CodeAction.new(
          title: CodeActions::EXTRACT_TO_VARIABLE_TITLE,
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: [
                  create_text_edit(source_range, NEW_VARIABLE_NAME),
                  create_text_edit(target_range, variable_source),
                ],
              ),
            ],
          ),
        )
      end

      #: -> (Interface::CodeAction)
      def refactor_method
        source_range = @code_action.dig(:data, :range)
        raise EmptySelectionError, "Invalid selection for refactor" if source_range[:start] == source_range[:end]

        start_index, end_index = @document.find_index_by_position(source_range[:start], source_range[:end])
        extracted_source = @document.source[start_index...end_index] #: as !nil

        # Find the closest method declaration node, so that we place the refactor in a valid position
        node_context = RubyDocument.locate(
          @document.ast,
          start_index,
          node_types: [Prism::DefNode],
          code_units_cache: @document.code_units_cache,
        )
        closest_node = node_context.node
        unless closest_node
          raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
        end

        target_range = if closest_node.is_a?(Prism::DefNode)
          end_keyword_loc = closest_node.end_keyword_loc
          unless end_keyword_loc
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end

          end_line = end_keyword_loc.end_line - 1
          character = end_keyword_loc.end_column
          indentation = " " * end_keyword_loc.start_column

          new_method_source = <<~RUBY.chomp


            #{indentation}def #{NEW_METHOD_NAME}
            #{indentation}  #{extracted_source}
            #{indentation}end
          RUBY

          {
            start: { line: end_line, character: character },
            end: { line: end_line, character: character },
          }
        else
          new_method_source = <<~RUBY
            #{indentation}def #{NEW_METHOD_NAME}
            #{indentation}  #{extracted_source.gsub("\n", "\n  ")}
            #{indentation}end

          RUBY

          line = [0, source_range.dig(:start, :line) - 1].max
          {
            start: { line: line, character: source_range.dig(:start, :character) },
            end: { line: line, character: source_range.dig(:start, :character) },
          }
        end

        Interface::CodeAction.new(
          title: CodeActions::EXTRACT_TO_METHOD_TITLE,
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: [
                  create_text_edit(target_range, new_method_source),
                  create_text_edit(source_range, NEW_METHOD_NAME),
                ],
              ),
            ],
          ),
        )
      end

      #: -> (Interface::CodeAction)
      def inline_variable
        source_range = @code_action.dig(:data, :range)
        target = CodeActions.local_variable_at(@document, source_range)
        raise InvalidTargetRangeError, "Inline variable needs the cursor on a local variable" unless target

        scope = declaring_scope(target)
        raise InvalidTargetRangeError, "Couldn't find where the variable is defined" unless scope

        references = LocalVariableReferences.new(target.name)
        references.collect(scope)

        writes = references.writes
        if writes.size != 1 || references.other_writes > 0
          raise InvalidTargetRangeError, "Only a variable assigned once can be inlined"
        end

        write, write_ancestors = writes.first #: as !nil

        statements = write_ancestors.last
        unless statements.is_a?(Prism::StatementsNode)
          raise InvalidTargetRangeError, "Only a variable assigned in a statement of its own can be inlined"
        end

        reads = references.reads
        raise InvalidTargetRangeError, "The variable is never read" if reads.empty?

        value = write.value
        raise InvalidTargetRangeError, "Values with heredocs can't be inlined" if contains_heredoc?(value)

        write_end = write.location.end_offset
        statements_end = statements.location.end_offset
        unless reads.all? { |read, _| read.location.start_offset >= write_end && read.location.end_offset <= statements_end }
          raise InvalidTargetRangeError, "The variable is read where its assignment may not have run"
        end

        if pure_value?(value)
          # A read inside a block can run any time later, so the value has to hold until the end of the scope
          deferred = reads.any? { |_, ancestors| deferred_read?(ancestors, statements) }
          last_use = deferred ? scope.location.end_offset : reads.map { |read, _| read.location.start_offset }.max #: as !nil
          if reassigned_between?(scope, variable_names(value), write_end, last_use)
            raise InvalidTargetRangeError, "A variable the value uses is reassigned before the value is read"
          end
        else
          read, ancestors = reads.first #: as !nil
          unless reads.size == 1 && evaluated_once_after?(read, ancestors, statements, write)
            raise InvalidTargetRangeError,
              "A value that calls methods or builds objects can only be inlined once, into the next statement"
          end
        end

        edits = reads.map do |read, ancestors|
          source = value.slice
          source = "(#{source})" if needs_parentheses?(value, read, ancestors)
          Interface::TextEdit.new(range: range_from_location(read.location), new_text: source)
        end
        edits.unshift(Interface::TextEdit.new(range: assignment_removal_range(write), new_text: ""))

        Interface::CodeAction.new(
          title: CodeActions::INLINE_VARIABLE_TITLE,
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: edits,
              ),
            ],
          ),
        )
      end

      # The scope a local variable belongs to: the enclosing scope node as many block levels up as the variable's depth
      #: ((Prism::LocalVariableWriteNode | Prism::LocalVariableReadNode) target) -> Prism::Node?
      def declaring_scope(target)
        scopes = enclosing_scopes(@document.ast, target, [])
        return unless scopes

        index = scopes.size - 1 - target.depth
        scopes[index] if index >= 0
      end

      #: (Prism::Node node, Prism::Node target, Array[Prism::Node] scopes) -> Array[Prism::Node]?
      def enclosing_scopes(node, target, scopes)
        return scopes if node.equal?(target)

        scopes = [*scopes, node] if SCOPE_NODES.any? { |type| node.is_a?(type) }
        target_location = target.location

        node.compact_child_nodes.each do |child|
          location = child.location
          next if location.start_offset > target_location.start_offset
          next if location.end_offset < target_location.end_offset

          found = enclosing_scopes(child, target, scopes)
          return found if found
        end

        nil
      end

      # Whether a read inside a block or lambda may run after the statements the assignment is part of
      #: (Array[Prism::Node] ancestors, Prism::StatementsNode statements) -> bool
      def deferred_read?(ancestors, statements)
        index = ancestors.index { |node| node.equal?(statements) } || 0
        ancestors.drop(index).any? { |node| node.is_a?(Prism::BlockNode) || node.is_a?(Prism::LambdaNode) }
      end

      # Whether the read is in the statement right after the assignment, where it is evaluated exactly once whenever
      # that statement runs
      #: (Prism::LocalVariableReadNode read, Array[Prism::Node] ancestors, Prism::StatementsNode statements, Prism::LocalVariableWriteNode write) -> bool
      def evaluated_once_after?(read, ancestors, statements, write)
        body = statements.body
        index = body.index { |node| node.equal?(write) } #: as !nil
        next_statement = body[index + 1]
        return false unless next_statement

        path = [*ancestors, read]
        start = path.index { |node| node.equal?(next_statement) }
        return false unless start

        path.drop(start).each_cons(2).all? { |node, child| node && child && evaluated_once_with?(node, child) }
      end

      # Whether `child` is evaluated exactly once each time `node` is
      #: (Prism::Node node, Prism::Node child) -> bool
      def evaluated_once_with?(node, child)
        case node
        when Prism::IfNode, Prism::UnlessNode, Prism::CaseNode, Prism::CaseMatchNode
          node.predicate.equal?(child)
        when Prism::AndNode, Prism::OrNode
          node.left.equal?(child)
        when Prism::ForNode
          node.collection.equal?(child)
        when Prism::RescueModifierNode
          node.expression.equal?(child)
        when Prism::CallNode
          !node.safe_navigation? || node.receiver.equal?(child)
        when Prism::BlockNode, Prism::LambdaNode, Prism::WhileNode, Prism::UntilNode, Prism::BeginNode,
          Prism::DefinedNode
          false
        else
          true
        end
      end

      # Whether evaluating the value again, or later, gives the same result as long as the variables it reads keep
      # their values: literals that don't create objects, variables, constants and operators over them
      #: (Prism::Node node) -> bool
      def pure_value?(node)
        pure = case node
        when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode, Prism::SymbolNode,
          Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::SelfNode, Prism::LocalVariableReadNode,
          Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode, Prism::GlobalVariableReadNode,
          Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ParenthesesNode, Prism::StatementsNode,
          Prism::ArgumentsNode
          true
        when Prism::CallNode
          operator_call?(node) && PURE_OPERATORS.include?(node.name)
        else
          false
        end

        pure && node.compact_child_nodes.all? { |child| pure_value?(child) }
      end

      #: (Prism::Node node) -> Array[Symbol]
      def variable_names(node)
        names = case node
        when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode,
          Prism::GlobalVariableReadNode
          [node.name]
        else
          []
        end

        node.compact_child_nodes.each { |child| names.concat(variable_names(child)) }
        names
      end

      # Whether any of the variables is assigned between the two offsets
      #: (Prism::Node node, Array[Symbol] names, Integer from, Integer to) -> bool
      def reassigned_between?(node, names, from, to)
        return false if names.empty?

        case node
        when Prism::LocalVariableWriteNode, Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableAndWriteNode,
          Prism::LocalVariableOrWriteNode, Prism::LocalVariableTargetNode, Prism::InstanceVariableWriteNode,
          Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableAndWriteNode,
          Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableTargetNode, Prism::ClassVariableWriteNode,
          Prism::ClassVariableOperatorWriteNode, Prism::ClassVariableAndWriteNode, Prism::ClassVariableOrWriteNode,
          Prism::ClassVariableTargetNode, Prism::GlobalVariableWriteNode, Prism::GlobalVariableOperatorWriteNode,
          Prism::GlobalVariableAndWriteNode, Prism::GlobalVariableOrWriteNode, Prism::GlobalVariableTargetNode
          offset = node.location.start_offset
          return true if offset > from && offset < to && names.include?(node.name)
        end

        node.compact_child_nodes.any? { |child| reassigned_between?(child, names, from, to) }
      end

      #: (Prism::Node node) -> bool
      def contains_heredoc?(node)
        heredoc = case node
        when Prism::StringNode, Prism::InterpolatedStringNode, Prism::XStringNode, Prism::InterpolatedXStringNode
          node.heredoc?
        else
          false
        end

        heredoc || node.compact_child_nodes.any? { |child| contains_heredoc?(child) }
      end

      # Whether the value needs parentheses to keep its meaning where the read was
      #: (Prism::Node value, Prism::LocalVariableReadNode read, Array[Prism::Node] ancestors) -> bool
      def needs_parentheses?(value, read, ancestors)
        parent = ancestors.last
        owner = ancestors[-2]

        # `puts { a: 1 }` would pass a block
        if value.is_a?(Prism::HashNode) && parent.is_a?(Prism::ArgumentsNode) &&
            !(owner.is_a?(Prism::CallNode) && owner.opening_loc)
          return true
        end

        return false if atomic?(value)

        case parent
        when Prism::StatementsNode
          loose?(value)
        when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode, Prism::ClassVariableWriteNode,
          Prism::GlobalVariableWriteNode, Prism::ConstantWriteNode
          loose?(value)
        when Prism::AssocNode
          loose?(value) || command_call?(value)
        when Prism::ArrayNode
          parent.opening_loc.nil? || loose?(value) || command_call?(value)
        when Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode
          return true unless parent.predicate.equal?(read)

          if parent.is_a?(Prism::IfNode) && parent.if_keyword_loc.nil?
            # A ternary's condition
            value_precedence = precedence(value)
            value_precedence.nil? || value_precedence <= OPERATOR_PRECEDENCE.fetch(:ternary)
          else
            value.is_a?(Prism::RescueModifierNode)
          end
        when Prism::ArgumentsNode
          if owner.is_a?(Prism::CallNode) && operator_call?(owner)
            operator_needs_parentheses?(value, owner, receiver: false)
          elsif owner.is_a?(Prism::CallNode) && owner.opening_loc
            loose?(value) || command_call?(value)
          else
            # Arguments without parentheses: `puts a`
            loose?(value) || command_call?(value) || do_block_call?(value)
          end
        when Prism::CallNode
          # The read is the receiver
          operator_call?(parent) ? operator_needs_parentheses?(value, parent, receiver: true) : true
        else
          true
        end
      end

      # Whether the value, placed as an operand of the operator call, would bind to its neighbours differently
      #: (Prism::Node value, Prism::CallNode call, receiver: bool) -> bool
      def operator_needs_parentheses?(value, call, receiver:)
        value_precedence = precedence(value)
        return true unless value_precedence

        call_precedence = OPERATOR_PRECEDENCE.fetch(call.name)
        return value_precedence < call_precedence if value_precedence != call_precedence

        # At the same precedence, `**` groups to the right, `==` and its peers don't group at all, and the others
        # group to the left
        return receiver if call.name == :**
        return true if call_precedence == OPERATOR_PRECEDENCE.fetch(:==)

        !receiver
      end

      #: (Prism::Node node) -> Integer?
      def precedence(node)
        case node
        when Prism::CallNode
          OPERATOR_PRECEDENCE[node.name] if operator_call?(node) && !loose?(node)
        when Prism::AndNode, Prism::OrNode
          OPERATOR_PRECEDENCE[node.operator_loc.slice.to_sym] unless loose?(node)
        when Prism::RangeNode
          OPERATOR_PRECEDENCE[:range]
        when Prism::IfNode
          OPERATOR_PRECEDENCE[:ternary] if node.if_keyword_loc.nil?
        when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode
          OPERATOR_PRECEDENCE[:-@]
        end
      end

      # Values that read the same wherever they are placed
      #: (Prism::Node node) -> bool
      def atomic?(node)
        case node
        when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode
          !node.slice.start_with?("-")
        when Prism::StringNode, Prism::InterpolatedStringNode, Prism::SymbolNode, Prism::InterpolatedSymbolNode,
          Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode, Prism::XStringNode,
          Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::SelfNode, Prism::LocalVariableReadNode,
          Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode, Prism::GlobalVariableReadNode,
          Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ParenthesesNode, Prism::ArrayNode,
          Prism::HashNode
          true
        when Prism::CallNode
          !operator_call?(node) && !command_call?(node) && !do_block_call?(node)
        else
          false
        end
      end

      # Method calls with a `do...end` block, which binds to an enclosing call without parentheses
      #: (Prism::Node node) -> bool
      def do_block_call?(node)
        return false unless node.is_a?(Prism::CallNode)

        block = node.block
        block.is_a?(Prism::BlockNode) && block.opening_loc.slice == "do"
      end

      # Operator calls written as operators: `a + b`, `-a`, `!a`, but not `a.+(b)`
      #: (Prism::CallNode node) -> bool
      def operator_call?(node)
        OPERATOR_PRECEDENCE.key?(node.name) && node.call_operator_loc.nil? && node.message != "not"
      end

      # Method calls with arguments but no parentheses, like `foo bar`
      #: (Prism::Node node) -> bool
      def command_call?(node)
        node.is_a?(Prism::CallNode) && !operator_call?(node) && !node.arguments.nil? && node.opening_loc.nil?
      end

      # Expressions that bind looser than assignment and argument lists
      #: (Prism::Node node) -> bool
      def loose?(node)
        case node
        when Prism::AndNode, Prism::OrNode
          ["and", "or"].include?(node.operator_loc.slice)
        when Prism::CallNode
          node.message == "not"
        when Prism::RescueModifierNode
          true
        when Prism::DefinedNode
          node.lparen_loc.nil?
        else
          false
        end
      end

      #: (Prism::IfNode | Prism::UnlessNode | Prism::WhileNode | Prism::UntilNode node) -> bool
      def keyword_predicate?(node)
        case node
        when Prism::IfNode
          !node.if_keyword_loc.nil? && !node.end_keyword_loc.nil?
        when Prism::UnlessNode
          !node.end_keyword_loc.nil?
        else
          !node.closing_loc.nil?
        end
      end

      # The range that removes the assignment: its whole lines when nothing else is on them, or the assignment and
      # the semicolon that follows it
      #: (Prism::LocalVariableWriteNode write) -> Interface::Range
      def assignment_removal_range(write)
        location = write.location
        lines = @document.source.lines
        first_line = lines[location.start_line - 1] || ""
        last_line = lines[location.end_line - 1] || ""
        before = first_line.byteslice(0, location.start_column) || ""
        after = last_line.byteslice(location.end_column..) || ""

        if before.strip.empty? && after.strip.empty?
          return Interface::Range.new(
            start: Interface::Position.new(line: location.start_line - 1, character: 0),
            end: Interface::Position.new(line: location.end_line, character: 0),
          )
        end

        separator = after[/\A\s*;[ \t]*/]
        return range_from_location(location) unless separator

        Interface::Range.new(
          start: Interface::Position.new(line: location.start_line - 1, character: location.start_column),
          end: Interface::Position.new(line: location.end_line - 1, character: location.end_column + separator.bytesize),
        )
      end

      #: (Hash[Symbol, untyped] range, String new_text) -> Interface::TextEdit
      def create_text_edit(range, new_text)
        Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: range.dig(:start, :line), character: range.dig(:start, :character)),
            end: Interface::Position.new(line: range.dig(:end, :line), character: range.dig(:end, :character)),
          ),
          new_text: new_text,
        )
      end

      #: (Prism::BlockNode node, String? indentation) -> String
      def recursively_switch_nested_block_styles(node, indentation)
        parameters = node.parameters
        body = node.body

        # We use the indentation to differentiate between do...end and brace style blocks because only the do...end
        # style requires the indentation to build the edit.
        #
        # If the block is using `do...end` style, we change it to a single line brace block. Newlines are turned into
        # semi colons, so that the result is valid Ruby code and still a one liner. If the block is using brace style,
        # we do the opposite and turn it into a `do...end` block, making all semi colons into newlines.
        source = +""

        if indentation
          source << "do"
          source << " #{parameters.slice}" if parameters
          source << "\n#{indentation}  "
          source << switch_block_body(body, indentation) if body
          source << "\n#{indentation}end"
        else
          source << "{ "
          source << "#{parameters.slice} " if parameters
          source << switch_block_body(body, nil) if body
          source << "}"
        end

        source
      end

      #: (Prism::Node body, String? indentation) -> String
      def switch_block_body(body, indentation)
        # Check if there are any nested blocks inside of the current block
        body_loc = body.location
        nested_block = @document.locate_first_within_range(
          {
            start: { line: body_loc.start_line - 1, character: body_loc.start_column },
            end: { line: body_loc.end_line - 1, character: body_loc.end_column },
          },
          node_types: [Prism::BlockNode],
        )

        body_content = body.slice.dup

        # If there are nested blocks, then we change their style too and we have to mutate the string using the
        # relative position in respect to the beginning of the body
        if nested_block.is_a?(Prism::BlockNode)
          location = nested_block.location
          correction_start = location.start_offset - body_loc.start_offset
          correction_end = location.end_offset - body_loc.start_offset
          next_indentation = indentation ? "#{indentation}  " : nil

          body_content[correction_start...correction_end] =
            recursively_switch_nested_block_styles(nested_block, next_indentation)
        end

        indentation ? body_content.gsub(";", "\n") : "#{body_content.gsub("\n", ";")} "
      end

      #: -> (Interface::CodeAction)
      def create_attribute_accessor
        source_range = @code_action.dig(:data, :range)

        node = if source_range[:start] != source_range[:end]
          @document.locate_first_within_range(
            @code_action.dig(:data, :range),
            node_types: CodeActions::INSTANCE_VARIABLE_NODES,
          )
        end

        if node.nil?
          node_context = @document.locate_node(
            source_range[:start],
            node_types: CodeActions::INSTANCE_VARIABLE_NODES,
          )
          node = node_context.node

          unless CodeActions::INSTANCE_VARIABLE_NODES.include?(node.class)
            raise EmptySelectionError, "Invalid selection for refactor"
          end
        end

        node = node #: as Prism::InstanceVariableAndWriteNode | Prism::InstanceVariableOperatorWriteNode | Prism::InstanceVariableOrWriteNode | Prism::InstanceVariableReadNode | Prism::InstanceVariableTargetNode | Prism::InstanceVariableWriteNode

        node_context = @document.locate_node(
          {
            line: node.location.start_line,
            character: node.location.start_character_column,
          },
          node_types: [
            Prism::ClassNode,
            Prism::ModuleNode,
            Prism::SingletonClassNode,
          ],
        )
        closest_node = node_context.node
        if closest_node.nil?
          raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
        end

        attribute_name = node.name[1..]
        indentation = " " * (closest_node.location.start_column + 2)
        attribute_accessor_source = case @code_action[:title]
        when CodeActions::CREATE_ATTRIBUTE_READER
          "#{indentation}attr_reader :#{attribute_name}\n\n"
        when CodeActions::CREATE_ATTRIBUTE_WRITER
          "#{indentation}attr_writer :#{attribute_name}\n\n"
        when CodeActions::CREATE_ATTRIBUTE_ACCESSOR
          "#{indentation}attr_accessor :#{attribute_name}\n\n"
        end #: as !nil

        target_start_line = closest_node.location.start_line
        target_range = {
          start: { line: target_start_line, character: 0 },
          end: { line: target_start_line, character: 0 },
        }

        Interface::CodeAction.new(
          title: @code_action[:title],
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: [
                  create_text_edit(target_range, attribute_accessor_source),
                ],
              ),
            ],
          ),
        )
      end

      # Collects the assignments and reads of a local variable in the scope that declares it, with the nodes that
      # enclose each one
      class LocalVariableReferences
        #: Array[[Prism::LocalVariableWriteNode, Array[Prism::Node]]]
        attr_reader :writes

        #: Array[[Prism::LocalVariableReadNode, Array[Prism::Node]]]
        attr_reader :reads

        # Other ways the variable gets a value: parameters, operator assignments and multiple assignment targets
        #: Integer
        attr_reader :other_writes

        #: (Symbol name) -> void
        def initialize(name)
          @name = name
          @writes = [] #: Array[[Prism::LocalVariableWriteNode, Array[Prism::Node]]]
          @reads = [] #: Array[[Prism::LocalVariableReadNode, Array[Prism::Node]]]
          @other_writes = 0 #: Integer
        end

        #: (Prism::Node scope) -> void
        def collect(scope)
          scope.compact_child_nodes.each { |child| visit(child, [scope], 0) }
        end

        private

        # `depth` counts the blocks between the node and the scope, matching the depth Prism gives references to the
        # variable from inside them
        #: (Prism::Node node, Array[Prism::Node] ancestors, Integer depth) -> void
        def visit(node, ancestors, depth)
          record(node, ancestors, depth)
          ancestors = [*ancestors, node]

          case node
          when Prism::DefNode
            # A method body has its own variables, but its receiver is evaluated in the enclosing scope
            receiver = node.receiver
            visit(receiver, ancestors, depth) if receiver
          when Prism::ClassNode
            superclass = node.superclass
            visit(superclass, ancestors, depth) if superclass
          when Prism::SingletonClassNode
            visit(node.expression, ancestors, depth)
          when Prism::ModuleNode
            nil
          else
            depth += 1 if node.is_a?(Prism::BlockNode) || node.is_a?(Prism::LambdaNode)
            node.compact_child_nodes.each { |child| visit(child, ancestors, depth) }
          end
        end

        #: (Prism::Node node, Array[Prism::Node] ancestors, Integer depth) -> void
        def record(node, ancestors, depth)
          case node
          when Prism::LocalVariableReadNode
            @reads << [node, ancestors] if node.name == @name && node.depth == depth
          when Prism::LocalVariableWriteNode
            @writes << [node, ancestors] if node.name == @name && node.depth == depth
          when Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableAndWriteNode, Prism::LocalVariableOrWriteNode,
            Prism::LocalVariableTargetNode
            @other_writes += 1 if node.name == @name && node.depth == depth
          when Prism::RequiredParameterNode, Prism::OptionalParameterNode, Prism::RestParameterNode,
            Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode, Prism::KeywordRestParameterNode,
            Prism::BlockParameterNode, Prism::BlockLocalVariableNode
            # Parameters of the scope itself; those of nested blocks declare variables of their own
            @other_writes += 1 if node.name == @name && depth.zero?
          end
        end
      end
    end
  end
end
