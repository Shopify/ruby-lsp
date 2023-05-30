# typed: strict
# frozen_string_literal: true

module RubyLsp
  # EventEmitter is an intermediary between our requests and Syntax Tree visitors. It's used to visit the document's AST
  # and emit events that the requests can listen to for providing functionality. Usages:
  #
  # - For positional requests, locate the target node and use `emit_for_target` to fire events for each listener
  # - For nonpositional requests, use `visit` to go through the AST, which will fire events for each listener as nodes
  # are found
  #
  # # Example
  #
  # ```ruby
  # target_node = document.locate_node(position)
  # emitter = EventEmitter.new
  # listener = Requests::Hover.new(emitter, @message_queue)
  # emitter.emit_for_target(target_node)
  # listener.response
  # ```
  class EventEmitter < SyntaxTree::Visitor
    extend T::Sig

    sig { void }
    def initialize
      @listeners = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[Symbol, T::Array[Listener[T.untyped]]])
      super()
    end

    sig { params(listener: Listener[T.untyped], events: Symbol).void }
    def register(listener, *events)
      events.each { |event| T.must(@listeners[event]) << listener }
    end

    # Emit events for a specific node. This is similar to the regular `visit` method, but avoids going deeper into the
    # tree for performance
    sig { params(node: T.nilable(SyntaxTree::Node)).void }
    def emit_for_target(node)
      case node
      when SyntaxTree::ArrayLiteral
        @listeners[:on_array_literal]&.each { |l| T.unsafe(l).on_array_literal(node) }
      when SyntaxTree::Begin
        @listeners[:on_begin]&.each { |l| T.unsafe(l).on_begin(node) }
      when SyntaxTree::BlockNode
        @listeners[:on_block_node]&.each { |l| T.unsafe(l).on_block_node(node) }
      when SyntaxTree::Case
        @listeners[:on_case]&.each { |l| T.unsafe(l).on_case(node) }
      when SyntaxTree::ClassDeclaration
        @listeners[:on_class]&.each { |l| T.unsafe(l).on_class(node) }
      when SyntaxTree::CallNode
        @listeners[:on_call]&.each { |l| T.unsafe(l).on_call(node) }
      when SyntaxTree::Command
        @listeners[:on_command]&.each { |l| T.unsafe(l).on_command(node) }
      when SyntaxTree::CommandCall
        @listeners[:on_command_call]&.each { |l| T.unsafe(l).on_command_call(node) }
      when SyntaxTree::Const
        @listeners[:on_const]&.each { |l| T.unsafe(l).on_const(node) }
      when SyntaxTree::ConstPathRef
        @listeners[:on_const_path_ref]&.each { |l| T.unsafe(l).on_const_path_ref(node) }
      when SyntaxTree::DefNode
        @listeners[:on_def_node]&.each { |l| T.unsafe(l).on_def_node(node) }
      when SyntaxTree::Else
        @listeners[:on_else]&.each { |l| T.unsafe(l).on_else(node) }
      when SyntaxTree::Ensure
        @listeners[:on_ensure]&.each { |l| T.unsafe(l).on_ensure(node) }
      when SyntaxTree::For
        @listeners[:on_for]&.each { |l| T.unsafe(l).on_for(node) }
      when SyntaxTree::HashLiteral
        @listeners[:on_hash_literal]&.each { |l| T.unsafe(l).on_hash_literal(node) }
      when SyntaxTree::Heredoc
        @listeners[:on_heredoc]&.each { |l| T.unsafe(l).on_heredoc(node) }
      when SyntaxTree::IfNode
        @listeners[:on_if_node]&.each { |l| T.unsafe(l).on_if_node(node) }
      when SyntaxTree::ModuleDeclaration
        @listeners[:on_module]&.each { |l| T.unsafe(l).on_module(node) }
      when SyntaxTree::SClass
        @listeners[:on_sclass]&.each { |l| T.unsafe(l).on_sclass(node) }
      when SyntaxTree::StringConcat
        @listeners[:on_string_concat]&.each { |l| T.unsafe(l).on_string_concat(node) }
      when SyntaxTree::TStringContent
        @listeners[:on_tstring_content]&.each { |l| T.unsafe(l).on_tstring_content(node) }
      when SyntaxTree::UnlessNode
        @listeners[:on_unless_node]&.each { |l| T.unsafe(l).on_unless_node(node) }
      when SyntaxTree::UntilNode
        @listeners[:on_until_node]&.each { |l| T.unsafe(l).on_until_node(node) }
      when SyntaxTree::WhileNode
        @listeners[:on_while_node]&.each { |l| T.unsafe(l).on_while_node(node) }
      when SyntaxTree::Elsif
        @listeners[:on_elsif]&.each { |l| T.unsafe(l).on_elsif(node) }
      when SyntaxTree::In
        @listeners[:on_in]&.each { |l| T.unsafe(l).on_in(node) }
      when SyntaxTree::Rescue
        @listeners[:on_rescue]&.each { |l| T.unsafe(l).on_rescue(node) }
      when SyntaxTree::When
        @listeners[:on_when]&.each { |l| T.unsafe(l).on_when(node) }
      end
    end

    # Visit dispatchers are below. Notice that for nodes that create a new scope (e.g.: classes, modules, method defs)
    # we need both an `on_*` and `after_*` event. This is because some requests must know when we exit the scope
    sig { override.params(node: SyntaxTree::ClassDeclaration).void }
    def visit_class(node)
      @listeners[:on_class]&.each { |l| T.unsafe(l).on_class(node) }
      super
      @listeners[:after_class]&.each { |l| T.unsafe(l).after_class(node) }
    end

    sig { override.params(node: SyntaxTree::ModuleDeclaration).void }
    def visit_module(node)
      @listeners[:on_module]&.each { |l| T.unsafe(l).on_module(node) }
      super
      @listeners[:after_module]&.each { |l| T.unsafe(l).after_module(node) }
    end

    sig { override.params(node: SyntaxTree::Command).void }
    def visit_command(node)
      @listeners[:on_command]&.each { |l| T.unsafe(l).on_command(node) }
      super
      @listeners[:after_command]&.each { |l| T.unsafe(l).after_command(node) }
    end

    sig { override.params(node: SyntaxTree::CommandCall).void }
    def visit_command_call(node)
      @listeners[:on_command_call]&.each { |l| T.unsafe(l).on_command_call(node) }
      super
      # TODO: need 'after'?
      @listeners[:after_command_call]&.each { |l| T.unsafe(l).after_command_call(node) }
    end

    sig { override.params(node: SyntaxTree::CallNode).void }
    def visit_call(node)
      @listeners[:on_call]&.each { |l| T.unsafe(l).on_call(node) }
      super
      @listeners[:after_call]&.each { |l| T.unsafe(l).after_call(node) }
    end

    sig { override.params(node: SyntaxTree::VCall).void }
    def visit_vcall(node)
      @listeners[:on_vcall]&.each { |l| T.unsafe(l).on_vcall(node) }
      super
    end

    sig { override.params(node: SyntaxTree::ConstPathField).void }
    def visit_const_path_field(node)
      @listeners[:on_const_path_field]&.each { |l| T.unsafe(l).on_const_path_field(node) }
      super
    end

    sig { override.params(node: SyntaxTree::TopConstField).void }
    def visit_top_const_field(node)
      @listeners[:on_top_const_field]&.each { |l| T.unsafe(l).on_top_const_field(node) }
      super
    end

    sig { override.params(node: SyntaxTree::DefNode).void }
    def visit_def(node)
      @listeners[:on_def]&.each { |l| T.unsafe(l).on_def(node) }
      super
      @listeners[:after_def]&.each { |l| T.unsafe(l).after_def(node) }
    end

    sig { override.params(node: SyntaxTree::VarField).void }
    def visit_var_field(node)
      @listeners[:on_var_field]&.each { |l| T.unsafe(l).on_var_field(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Comment).void }
    def visit_comment(node)
      @listeners[:on_comment]&.each { |l| T.unsafe(l).on_comment(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Rescue).void }
    def visit_rescue(node)
      @listeners[:on_rescue]&.each { |l| T.unsafe(l).on_rescue(node) }
      super
    end

    # TODO: array_literal?
    sig { override.params(node: SyntaxTree::ArrayLiteral).void }
    def visit_array(node)
      @listeners[:on_array_literal]&.each { |l| T.unsafe(l).on_array_literal(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Begin).void }
    def visit_begin(node)
      @listeners[:on_begin]&.each { |l| T.unsafe(l).on_begin(node) }
      super
    end

    sig { override.params(node: SyntaxTree::BlockNode).void }
    def visit_block(node)
      @listeners[:on_block_node]&.each { |l| T.unsafe(l).on_block_node(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Case).void }
    def visit_case(node)
      @listeners[:on_case]&.each { |l| T.unsafe(l).on_case(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Else).void }
    def visit_else(node)
      @listeners[:on_else]&.each { |l| T.unsafe(l).on_else(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Ensure).void }
    def visit_ensure(node)
      @listeners[:on_ensure]&.each { |l| T.unsafe(l).on_ensure(node) }
      super
    end

    sig { override.params(node: SyntaxTree::For).void }
    def visit_for(node)
      @listeners[:on_for]&.each { |l| T.unsafe(l).on_for(node) }
      super
    end

    sig { override.params(node: SyntaxTree::HashLiteral).void }
    def visit_hash(node)
      @listeners[:on_hash_literal]&.each { |l| T.unsafe(l).on_hash_literal(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Heredoc).void }
    def visit_heredoc(node)
      @listeners[:on_heredoc]&.each { |l| T.unsafe(l).on_heredoc(node) }
      super
    end

    sig { override.params(node: SyntaxTree::IfNode).void }
    def visit_if(node)
      @listeners[:on_if_node]&.each { |l| T.unsafe(l).on_if_node(node) }
      super
    end

    sig { override.params(node: SyntaxTree::SClass).void }
    def visit_sclass(node)
      @listeners[:on_sclass]&.each { |l| T.unsafe(l).on_sclass(node) }
      super
    end

    sig { override.params(node: SyntaxTree::UnlessNode).void }
    def visit_unless(node)
      @listeners[:on_unless_node]&.each { |l| T.unsafe(l).on_unless_node(node) }
      super
    end

    sig { override.params(node: SyntaxTree::UntilNode).void }
    def visit_until(node)
      @listeners[:on_until_node]&.each { |l| T.unsafe(l).on_until_node(node) }
      super
    end

    sig { override.params(node: SyntaxTree::WhileNode).void }
    def visit_while(node)
      @listeners[:on_while_node]&.each { |l| T.unsafe(l).on_while_node(node) }
      super
    end

    sig { override.params(node: SyntaxTree::Elsif).void }
    def visit_elsif(node)
      @listeners[:on_elsif]&.each { |l| T.unsafe(l).on_elsif(node) }
      super
    end

    sig { override.params(node: SyntaxTree::In).void }
    def visit_in(node)
      @listeners[:on_in]&.each { |l| T.unsafe(l).on_in(node) }
      super
    end

    sig { override.params(node: SyntaxTree::When).void }
    def visit_when(node)
      @listeners[:on_when]&.each { |l| T.unsafe(l).on_when(node) }
      super
    end
  end
end
