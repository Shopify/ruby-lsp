# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Collector
    extend T::Sig

    LEAVE_EVENT = T.let(Object.new.freeze, Object)

    sig { params(index: Index, parse_result: Prism::ParseResult, file_path: String).void }
    def initialize(index, parse_result, file_path)
      @index = index
      @file_path = file_path
      @stack = T.let([], T::Array[String])
      @comments_by_line = T.let(
        parse_result.comments.to_h do |c|
          [c.location.start_line, c]
        end,
        T::Hash[Integer, Prism::Comment],
      )
      @queue = T.let([], T::Array[Object])
      @current_owner = T.let(nil, T.nilable(Entry::Namespace))

      super()
    end

    sig { params(node: Prism::Node).void }
    def collect(node)
      @queue = [node]

      until @queue.empty?
        node_or_event = @queue.shift

        case node_or_event
        when Prism::ProgramNode
          @queue << node_or_event.statements
        when Prism::StatementsNode
          T.unsafe(@queue).prepend(*node_or_event.body)
        when Prism::ClassNode
          add_class_entry(node_or_event)
        when Prism::ModuleNode
          add_module_entry(node_or_event)
        when Prism::MultiWriteNode
          handle_multi_write_node(node_or_event)
        when Prism::ConstantPathWriteNode
          handle_constant_path_write_node(node_or_event)
        when Prism::ConstantPathOrWriteNode
          handle_constant_path_or_write_node(node_or_event)
        when Prism::ConstantPathOperatorWriteNode
          handle_constant_path_operator_write_node(node_or_event)
        when Prism::ConstantPathAndWriteNode
          handle_constant_path_and_write_node(node_or_event)
        when Prism::ConstantWriteNode
          handle_constant_write_node(node_or_event)
        when Prism::ConstantOrWriteNode
          name = fully_qualify_name(node_or_event.name.to_s)
          add_constant(node_or_event, name)
        when Prism::ConstantAndWriteNode
          name = fully_qualify_name(node_or_event.name.to_s)
          add_constant(node_or_event, name)
        when Prism::ConstantOperatorWriteNode
          name = fully_qualify_name(node_or_event.name.to_s)
          add_constant(node_or_event, name)
        when Prism::CallNode
          handle_call_node(node_or_event)
        when Prism::DefNode
          handle_def_node(node_or_event)
        when LEAVE_EVENT
          @stack.pop
        end
      end
    end

    private

    sig { params(node: Prism::MultiWriteNode).void }
    def handle_multi_write_node(node)
      value = node.value
      values = value.is_a?(Prism::ArrayNode) && value.opening_loc ? value.elements : []

      [*node.lefts, *node.rest, *node.rights].each_with_index do |target, i|
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

    sig { params(node: Prism::ConstantPathWriteNode).void }
    def handle_constant_path_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantPathOrWriteNode).void }
    def handle_constant_path_or_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantPathOperatorWriteNode).void }
    def handle_constant_path_operator_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantPathAndWriteNode).void }
    def handle_constant_path_and_write_node(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantWriteNode).void }
    def handle_constant_write_node(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { params(node: Prism::CallNode).void }
    def handle_call_node(node)
      message = node.name

      case message
      when :private_constant
        handle_private_constant(node)
      when :attr_reader
        handle_attribute(node, reader: true, writer: false)
      when :attr_writer
        handle_attribute(node, reader: false, writer: true)
      when :attr_accessor
        handle_attribute(node, reader: true, writer: true)
      end
    end

    sig { params(node: Prism::DefNode).void }
    def handle_def_node(node)
      method_name = node.name.to_s
      comments = collect_comments(node)
      case node.receiver
      when nil
        @index << Entry::InstanceMethod.new(
          method_name,
          @file_path,
          node.location,
          comments,
          node.parameters,
          @current_owner,
        )
      when Prism::SelfNode
        @index << Entry::SingletonMethod.new(
          method_name,
          @file_path,
          node.location,
          comments,
          node.parameters,
          @current_owner,
        )
      end
    end

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
        @queue.prepend(value)
        Entry::UnresolvedAlias.new(value.name.to_s, @stack.dup, name, @file_path, node.location, comments)
      when Prism::ConstantPathWriteNode, Prism::ConstantPathOrWriteNode, Prism::ConstantPathOperatorWriteNode,
        Prism::ConstantPathAndWriteNode

        @queue.prepend(value)
        Entry::UnresolvedAlias.new(value.target.slice, @stack.dup, name, @file_path, node.location, comments)
      else
        Entry::Constant.new(name, @file_path, node.location, comments)
      end
    end

    sig { params(node: Prism::ModuleNode).void }
    def add_module_entry(node)
      name = node.constant_path.location.slice
      unless /^[A-Z:]/.match?(name)
        @queue << node.body
        return
      end

      comments = collect_comments(node)
      @current_owner = Entry::Module.new(fully_qualify_name(name), @file_path, node.location, comments)
      @index << @current_owner
      @stack << name
      @queue.prepend(node.body, LEAVE_EVENT)
    end

    sig { params(node: Prism::ClassNode).void }
    def add_class_entry(node)
      name = node.constant_path.location.slice

      unless /^[A-Z:]/.match?(name)
        @queue << node.body
        return
      end

      comments = collect_comments(node)

      superclass = node.superclass
      parent_class = case superclass
      when Prism::ConstantReadNode, Prism::ConstantPathNode
        superclass.slice
      end

      @current_owner = Entry::Class.new(
        fully_qualify_name(name),
        @file_path,
        node.location,
        comments,
        parent_class,
      )
      @index << @current_owner
      @stack << name
      @queue.prepend(node.body, LEAVE_EVENT)
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
        comments.prepend(comment_content)
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

    sig { params(node: Prism::CallNode, reader: T::Boolean, writer: T::Boolean).void }
    def handle_attribute(node, reader:, writer:)
      arguments = node.arguments&.arguments
      return unless arguments

      receiver = node.receiver
      return unless receiver.nil? || receiver.is_a?(Prism::SelfNode)

      comments = collect_comments(node)
      arguments.each do |argument|
        name, loc = case argument
        when Prism::SymbolNode
          [argument.value, argument.value_loc]
        when Prism::StringNode
          [argument.content, argument.content_loc]
        end

        next unless name && loc

        @index << Entry::Accessor.new(name, @file_path, loc, comments, @current_owner) if reader
        @index << Entry::Accessor.new("#{name}=", @file_path, loc, comments, @current_owner) if writer
      end
    end
  end
end
