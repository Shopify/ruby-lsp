# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class IndexVisitor < Prism::Visitor
    extend T::Sig

    sig { params(index: Index, parse_result: Prism::ParseResult, file_path: String).void }
    def initialize(index, parse_result, file_path)
      @index = index
      @file_path = file_path
      @stack = T.let([], T::Array[String])
      @singleton_class_node = T.let(nil, T.nilable(Prism::Node))
      @comments_by_line = T.let(
        parse_result.comments.to_h do |c|
          [c.location.start_line, c]
        end,
        T::Hash[Integer, Prism::Comment],
      )

      super()
    end

    sig { override.params(node: Prism::ClassNode).void }
    def visit_class_node(node)
      add_class_entry(node)
    end

    sig { override.params(node: Prism::SingletonClassNode).void }
    def visit_singleton_class_node(node)
      @singleton_class_node = node.expression
      super
      @singleton_class_node = nil
    end

    sig { override.params(node: Prism::ModuleNode).void }
    def visit_module_node(node)
      add_module_entry(node)
    end

    sig { override.params(node: Prism::MultiWriteNode).void }
    def visit_multi_write_node(node)
      value = node.value
      values = value.is_a?(Prism::ArrayNode) && value.opening_loc ? value.elements : []

      node.targets.each_with_index do |target, i|
        current_value = values[i]
        # The moment we find a splat on the right hand side of the assignment, we can no longer figure out which value
        # gets assigned to what
        values.clear if current_value.is_a?(Prism::SplatNode)

        case target
        when Prism::ConstantTargetNode
          add_constant(target, fully_qualify_name(target.name.to_s), current_value)
        when Prism::ConstantPathTargetNode
          add_constant(target, fully_qualify_name(target.slice), current_value)
        end
      end
    end

    sig { override.params(node: Prism::ConstantPathWriteNode).void }
    def visit_constant_path_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { override.params(node: Prism::ConstantPathOrWriteNode).void }
    def visit_constant_path_or_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { override.params(node: Prism::ConstantPathOperatorWriteNode).void }
    def visit_constant_path_operator_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { override.params(node: Prism::ConstantPathAndWriteNode).void }
    def visit_constant_path_and_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { override.params(node: Prism::ConstantWriteNode).void }
    def visit_constant_write_node(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { override.params(node: Prism::ConstantOrWriteNode).void }
    def visit_constant_or_write_node(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { override.params(node: Prism::ConstantAndWriteNode).void }
    def visit_constant_and_write_node(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { override.params(node: Prism::ConstantOperatorWriteNode).void }
    def visit_constant_operator_write_node(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { override.params(node: Prism::CallNode).void }
    def visit_call_node(node)
      message = node.message
      handle_private_constant(node) if message == "private_constant"
    end

    sig { override.params(node: Prism::DefNode).void }
    def visit_def_node(node)
      method_name = node.name.to_s
      comments = collect_comments(node)
      entry_class = case node.receiver
      when nil
        if @singleton_class_node # i.e. `class << self`
          Entry::SingletonMethod
        else
          Entry::InstanceMethod
        end
      when Prism::SelfNode
        Entry::SingletonMethod
      else
        return
      end
      @index << entry_class.new(method_name, @file_path, node.location, comments, node.parameters)
    end

    private

    sig { params(node: Prism::CallNode).void }
    def handle_private_constant(node)
      arguments = node.arguments&.arguments
      return unless arguments

      first_argument = arguments.first

      name = case first_argument
      when Prism::StringNode
        first_argument.content
      when Prism::SymbolNode
        first_argument.value
      end

      return unless name

      receiver = node.receiver
      name = "#{receiver.slice}::#{name}" if receiver

      # The private_constant method does not resolve the constant name. It always points to a constant that needs to
      # exist in the current namespace
      entries = @index[fully_qualify_name(name)]
      entries&.each { |entry| entry.visibility = :private }
    end

    sig do
      params(
        node: T.any(
          Prism::ConstantWriteNode,
          Prism::ConstantOrWriteNode,
          Prism::ConstantAndWriteNode,
          Prism::ConstantOperatorWriteNode,
          Prism::ConstantPathWriteNode,
          Prism::ConstantPathOrWriteNode,
          Prism::ConstantPathOperatorWriteNode,
          Prism::ConstantPathAndWriteNode,
          Prism::ConstantTargetNode,
          Prism::ConstantPathTargetNode,
        ),
        name: String,
        value: T.nilable(Prism::Node),
      ).void
    end
    def add_constant(node, name, value = nil)
      value = node.value unless node.is_a?(Prism::ConstantTargetNode) || node.is_a?(Prism::ConstantPathTargetNode)
      comments = collect_comments(node)

      @index << case value
      when Prism::ConstantReadNode, Prism::ConstantPathNode
        Entry::UnresolvedAlias.new(value.slice, @stack.dup, name, @file_path, node.location, comments)
      when Prism::ConstantWriteNode, Prism::ConstantAndWriteNode, Prism::ConstantOrWriteNode,
        Prism::ConstantOperatorWriteNode

        # If the right hand side is another constant assignment, we need to visit it because that constant has to be
        # indexed too
        visit(value)
        Entry::UnresolvedAlias.new(value.name.to_s, @stack.dup, name, @file_path, node.location, comments)
      when Prism::ConstantPathWriteNode, Prism::ConstantPathOrWriteNode, Prism::ConstantPathOperatorWriteNode,
        Prism::ConstantPathAndWriteNode

        visit(value)
        Entry::UnresolvedAlias.new(value.target.slice, @stack.dup, name, @file_path, node.location, comments)
      else
        Entry::Constant.new(name, @file_path, node.location, comments)
      end
    end

    sig { params(node: Prism::ModuleNode).void }
    def add_module_entry(node)
      name = node.constant_path.location.slice
      return visit_child_nodes(node) unless /^[A-Z:]/.match?(name)

      comments = collect_comments(node)

      @index << Entry::Module.new(fully_qualify_name(name), @file_path, node.location, comments)
      @stack << name
      visit_child_nodes(node)
      @stack.pop
    end

    sig { params(node: Prism::ClassNode).void }
    def add_class_entry(node)
      name = node.constant_path.location.slice
      return visit_child_nodes(node) unless /^[A-Z:]/.match?(name)

      comments = collect_comments(node)

      superclass = node.superclass
      parent_class = case superclass
      when Prism::ConstantReadNode, Prism::ConstantPathNode
        superclass.slice
      end

      @index << Entry::Class.new(fully_qualify_name(name), @file_path, node.location, comments, parent_class)
      @stack << name
      visit(node.body)
      @stack.pop
    end

    sig { params(node: Prism::Node).returns(T::Array[String]) }
    def collect_comments(node)
      comments = []

      start_line = node.location.start_line - 1
      start_line -= 1 unless @comments_by_line.key?(start_line)

      start_line.downto(1) do |line|
        comment = @comments_by_line[line]
        break unless comment

        comment_content = comment.location.slice.chomp
        next if comment_content.match?(RubyIndexer.configuration.magic_comment_regex)

        comment_content.delete_prefix!("#")
        comment_content.delete_prefix!(" ")
        comments.unshift(comment_content)
      end

      comments
    end

    sig { params(name: String).returns(String) }
    def fully_qualify_name(name)
      if @stack.empty? || name.start_with?("::")
        name
      else
        "#{@stack.join("::")}::#{name}"
      end.delete_prefix("::")
    end
  end
end
