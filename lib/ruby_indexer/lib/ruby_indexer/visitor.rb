# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class IndexVisitor < YARP::Visitor
    extend T::Sig

    sig { params(index: Index, parse_result: YARP::ParseResult, file_path: String).void }
    def initialize(index, parse_result, file_path)
      @index = index
      @parse_result = parse_result
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

    sig { void }
    def run
      visit(@parse_result.value)
    end

    sig { params(node: T.nilable(YARP::Node)).void }
    def visit(node)
      case node
      when YARP::ProgramNode, YARP::StatementsNode
        visit_child_nodes(node)
      when YARP::ClassNode
        add_index_entry(node, Index::Entry::Class)
      when YARP::ModuleNode
        add_index_entry(node, Index::Entry::Module)
      when YARP::ConstantWriteNode, YARP::ConstantOrWriteNode
        add_constant(node)
      when YARP::ConstantPathWriteNode, YARP::ConstantPathOrWriteNode
        add_constant_with_path(node)
      when YARP::CallNode
        message = node.message
        handle_private_constant(node) if message == "private_constant"
      end
    end

    # Override to avoid using `map` instead of `each`
    sig { params(nodes: T::Array[T.nilable(YARP::Node)]).void }
    def visit_all(nodes)
      nodes.each { |node| visit(node) }
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
        node: T.any(YARP::ConstantWriteNode, YARP::ConstantOrWriteNode),
      ).void
    end
    def add_constant(node)
      comments = collect_comments(node)
      @index << Index::Entry::Constant.new(fully_qualify_name(node.name.to_s), @file_path, node.location, comments)
    end

    sig do
      params(
        node: T.any(YARP::ConstantPathWriteNode, YARP::ConstantPathOrWriteNode),
      ).void
    end
    def add_constant_with_path(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      return unless node.target.parent.nil? || node.target.parent.is_a?(YARP::ConstantReadNode)

      name = node.target.location.slice
      comments = collect_comments(node)
      @index << Index::Entry::Constant.new(fully_qualify_name(name), @file_path, node.location, comments)
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
      visit_child_nodes(node)
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
