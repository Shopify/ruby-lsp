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
      end
    end

    # Override to avoid using `map` instead of `each`
    sig { params(nodes: T::Array[T.nilable(YARP::Node)]).void }
    def visit_all(nodes)
      nodes.each { |node| visit(node) }
    end

    private

    sig { params(node: T.any(YARP::ClassNode, YARP::ModuleNode), klass: T.class_of(Index::Entry)).void }
    def add_index_entry(node, klass)
      name = node.constant_path.location.slice

      unless /^[A-Z:]/.match?(name)
        return visit_child_nodes(node)
      end

      fully_qualified_name = name.start_with?("::") ? name : fully_qualify_name(name)
      name.delete_prefix!("::")

      comments = collect_comments(node)
      @index << klass.new(fully_qualified_name, @file_path, node.location, comments)
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

        comments.unshift(comment.location.slice)
      end

      comments
    end

    sig { params(name: String).returns(String) }
    def fully_qualify_name(name)
      return name if @stack.empty?

      "#{@stack.join("::")}::#{name}"
    end
  end
end
