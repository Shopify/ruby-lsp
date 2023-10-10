# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class IndexVisitor < YARP::Visitor
    extend T::Sig

    sig { params(index: Index, parse_result: YARP::ParseResult, file_path: String).void }
    def initialize(index, parse_result, file_path)
      @index = index
      @file_path = file_path
      @stack = T.let([], T::Array[String])
      @comments_by_line = T.let(
        parse_result.comments.to_h do |c|
          [c.location.start_line, c]
        end,
        T::Hash[Integer, YARP::Comment],
      )

      super()
    end

    sig { override.params(node: YARP::ClassNode).void }
    def visit_class_node(node)
      add_index_entry(node, Index::Entry::Class)
    end

    sig { override.params(node: YARP::ModuleNode).void }
    def visit_module_node(node)
      add_index_entry(node, Index::Entry::Module)
    end

    sig { override.params(node: YARP::ConstantPathWriteNode).void }
    def visit_constant_path_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(YARP::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { override.params(node: YARP::ConstantPathOrWriteNode).void }
    def visit_constant_path_or_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(YARP::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { override.params(node: YARP::ConstantPathOperatorWriteNode).void }
    def visit_constant_path_operator_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(YARP::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { override.params(node: YARP::ConstantPathAndWriteNode).void }
    def visit_constant_path_and_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(YARP::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { override.params(node: YARP::ConstantWriteNode).void }
    def visit_constant_write_node(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { override.params(node: YARP::ConstantOrWriteNode).void }
    def visit_constant_or_write_node(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { override.params(node: YARP::ConstantAndWriteNode).void }
    def visit_constant_and_write_node(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { override.params(node: YARP::ConstantOperatorWriteNode).void }
    def visit_constant_operator_write_node(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { override.params(node: YARP::CallNode).void }
    def visit_call_node(node)
      message = node.message
      handle_private_constant(node) if message == "private_constant"
    end

    private

    sig { params(node: YARP::CallNode).void }
    def handle_private_constant(node)
      arguments = node.arguments&.arguments
      return unless arguments

      first_argument = arguments.first

      name = case first_argument
      when YARP::StringNode
        first_argument.content
      when YARP::SymbolNode
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
          YARP::ConstantWriteNode,
          YARP::ConstantOrWriteNode,
          YARP::ConstantAndWriteNode,
          YARP::ConstantOperatorWriteNode,
          YARP::ConstantPathWriteNode,
          YARP::ConstantPathOrWriteNode,
          YARP::ConstantPathOperatorWriteNode,
          YARP::ConstantPathAndWriteNode,
        ),
        name: String,
      ).void
    end
    def add_constant(node, name)
      value = node.value
      comments = collect_comments(node)

      @index << case value
      when YARP::ConstantReadNode, YARP::ConstantPathNode
        Index::Entry::UnresolvedAlias.new(value.slice, @stack.dup, name, @file_path, node.location, comments)
      when YARP::ConstantWriteNode, YARP::ConstantAndWriteNode, YARP::ConstantOrWriteNode,
        YARP::ConstantOperatorWriteNode

        # If the right hand side is another constant assignment, we need to visit it because that constant has to be
        # indexed too
        visit(value)
        Index::Entry::UnresolvedAlias.new(value.name.to_s, @stack.dup, name, @file_path, node.location, comments)
      when YARP::ConstantPathWriteNode, YARP::ConstantPathOrWriteNode, YARP::ConstantPathOperatorWriteNode,
        YARP::ConstantPathAndWriteNode

        visit(value)
        Index::Entry::UnresolvedAlias.new(value.target.slice, @stack.dup, name, @file_path, node.location, comments)
      else
        Index::Entry::Constant.new(name, @file_path, node.location, comments)
      end
    end

    sig { params(node: T.any(YARP::ClassNode, YARP::ModuleNode), klass: T.class_of(Index::Entry)).void }
    def add_index_entry(node, klass)
      name = node.constant_path.location.slice

      unless /^[A-Z:]/.match?(name)
        return visit_child_nodes(node)
      end

      comments = collect_comments(node)
      @index << klass.new(fully_qualify_name(name), @file_path, node.location, comments)
      @stack << name
      visit(node.body)
      @stack.pop
    end

    sig { params(node: YARP::Node).returns(T::Array[String]) }
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
