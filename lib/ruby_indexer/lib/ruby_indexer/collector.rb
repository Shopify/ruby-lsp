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
      when :include
        handle_include(node)
      when :prepend
        handle_prepend(node)
      end
    end

    sig { params(node: Prism::DefNode).void }
    def handle_def_node(node)
      method_name = node.name.to_s
      comments = collect_comments(node)
      declaration = Entry::MemberDeclaration.new(list_params(node.parameters), @file_path, node.location, comments)
      existing_entry = @current_owner && @index.resolve_method(method_name, @current_owner.name)

      entry = if existing_entry
        existing_entry
      else
        case node.receiver
        when nil
          Entry::InstanceMethod.new(method_name, @current_owner)
        when Prism::SelfNode
          Entry::SingletonMethod.new(method_name, @current_owner)
        end
      end

      if entry
        @index.add_new_entry(entry, @file_path)
        entry.add_declaration(declaration)
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
      entry = @index.get_constant(fully_qualify_name(name))
      entry&.visibility = :private
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
      entry = @index.get_constant(name)

      if entry
        @index.add_file_path(entry, @file_path)
      else
        entry = case value
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          Entry::UnresolvedAlias.new(value.slice, @stack.dup, name)
        when Prism::ConstantWriteNode, Prism::ConstantAndWriteNode, Prism::ConstantOrWriteNode,
        Prism::ConstantOperatorWriteNode

          # If the right hand side is another constant assignment, we need to visit it because that constant has to be
          # indexed too
          @queue.prepend(value)
          Entry::UnresolvedAlias.new(value.name.to_s, @stack.dup, name)
        when Prism::ConstantPathWriteNode, Prism::ConstantPathOrWriteNode, Prism::ConstantPathOperatorWriteNode,
        Prism::ConstantPathAndWriteNode

          @queue.prepend(value)
          Entry::UnresolvedAlias.new(value.target.slice, @stack.dup, name)
        else
          Entry::Constant.new(name)
        end

        @index.add_new_entry(entry, @file_path)
      end

      entry.add_declaration(Entry::Declaration.new(@file_path, node.location, comments))
    end

    sig { params(node: Prism::ModuleNode).void }
    def add_module_entry(node)
      name = node.constant_path.location.slice
      unless /^[A-Z:]/.match?(name)
        @queue << node.body
        return
      end

      comments = collect_comments(node)

      fully_qualified_name = fully_qualify_name(name)
      existing_entry = @index.get_constant(fully_qualified_name)

      # If the user has defined the same constant as a namespace and a constant, then we end up losing the original
      # definition. This is an error in Ruby, but we should still try to handle it gracefully
      @current_owner = existing_entry.is_a?(Entry::Namespace) ? existing_entry : Entry::Module.new(fully_qualified_name)

      if existing_entry
        @index.add_file_path(@current_owner, @file_path)
      else
        @index.add_new_entry(@current_owner, @file_path)
      end

      @current_owner.add_declaration(Entry::Declaration.new(@file_path, node.location, comments))
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

      fully_qualified_name = fully_qualify_name(name)
      existing_entry = @index.get_constant(fully_qualified_name)

      # If the user has defined the same constant as a namespace and a constant, then we end up losing the original
      # definition. This is an error in Ruby, but we should still try to handle it gracefully
      @current_owner = if existing_entry.is_a?(Entry::Namespace)
        existing_entry
      else
        Entry::Class.new(fully_qualified_name, parent_class)
      end

      if existing_entry
        @index.add_file_path(@current_owner, @file_path)
      else
        @index.add_new_entry(@current_owner, @file_path)
      end

      @current_owner.add_declaration(Entry::Declaration.new(@file_path, node.location, comments))
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

        # invalid encodings would raise an "invalid byte sequence" exception
        if !comment_content.valid_encoding? || comment_content.match?(RubyIndexer.configuration.magic_comment_regex)
          next
        end

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

        if reader
          entry = @current_owner && @index.resolve_method(name, @current_owner.name)

          if entry
            @index.add_file_path(entry, @file_path)
          else
            entry = Entry::Accessor.new(name, @current_owner)
            @index.add_new_entry(entry, @file_path)
          end

          entry.add_declaration(Entry::MemberDeclaration.new([], @file_path, loc, comments))
        end

        next unless writer

        writer_name = "#{name}="
        entry = @current_owner && @index.resolve_method(writer_name, @current_owner.name)

        if entry
          @index.add_file_path(entry, @file_path)
        else
          entry = Entry::Accessor.new(writer_name, @current_owner)
          @index.add_new_entry(entry, @file_path)
        end

        entry.add_declaration(Entry::MemberDeclaration.new(
          [Entry::RequiredParameter.new(name: name.to_sym)],
          @file_path,
          loc,
          comments,
        ))
      end
    end

    sig { params(node: Prism::CallNode).void }
    def handle_include(node)
      handle_module_operation(node, :included_modules)
    end

    sig { params(node: Prism::CallNode).void }
    def handle_prepend(node)
      handle_module_operation(node, :prepended_modules)
    end

    sig { params(node: Prism::CallNode, operation: Symbol).void }
    def handle_module_operation(node, operation)
      return unless @current_owner

      arguments = node.arguments&.arguments
      return unless arguments

      names = arguments.filter_map do |node|
        if node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
          node.full_name
        end
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
        # TO DO: add MissingNodesInConstantPathError when released in Prism
        # If a constant path reference is dynamic or missing parts, we can't
        # index it
      end
      collection = operation == :included_modules ? @current_owner.included_modules : @current_owner.prepended_modules
      collection.concat(names)
    end

    sig { params(parameters_node: T.nilable(Prism::ParametersNode)).returns(T::Array[Entry::Parameter]) }
    def list_params(parameters_node)
      return [] unless parameters_node

      parameters = []

      parameters_node.requireds.each do |required|
        name = parameter_name(required)
        next unless name

        parameters << Entry::RequiredParameter.new(name: name)
      end

      parameters_node.optionals.each do |optional|
        name = parameter_name(optional)
        next unless name

        parameters << Entry::OptionalParameter.new(name: name)
      end

      parameters_node.keywords.each do |keyword|
        name = parameter_name(keyword)
        next unless name

        case keyword
        when Prism::RequiredKeywordParameterNode
          parameters << Entry::KeywordParameter.new(name: name)
        when Prism::OptionalKeywordParameterNode
          parameters << Entry::OptionalKeywordParameter.new(name: name)
        end
      end

      rest = parameters_node.rest

      if rest.is_a?(Prism::RestParameterNode)
        rest_name = rest.name || Entry::RestParameter::DEFAULT_NAME
        parameters << Entry::RestParameter.new(name: rest_name)
      end

      keyword_rest = parameters_node.keyword_rest

      if keyword_rest.is_a?(Prism::KeywordRestParameterNode)
        keyword_rest_name = parameter_name(keyword_rest) || Entry::KeywordRestParameter::DEFAULT_NAME
        parameters << Entry::KeywordRestParameter.new(name: keyword_rest_name)
      end

      parameters_node.posts.each do |post|
        name = parameter_name(post)
        next unless name

        parameters << Entry::RequiredParameter.new(name: name)
      end

      block = parameters_node.block
      parameters << Entry::BlockParameter.new(name: block.name || Entry::BlockParameter::DEFAULT_NAME) if block

      parameters
    end

    sig { params(node: T.nilable(Prism::Node)).returns(T.nilable(Symbol)) }
    def parameter_name(node)
      case node
      when Prism::RequiredParameterNode, Prism::OptionalParameterNode,
        Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode,
        Prism::RestParameterNode, Prism::KeywordRestParameterNode
        node.name
      when Prism::MultiTargetNode
        names = node.lefts.map { |parameter_node| parameter_name(parameter_node) }

        rest = node.rest
        if rest.is_a?(Prism::SplatNode)
          name = rest.expression&.slice
          names << (rest.operator == "*" ? "*#{name}".to_sym : name&.to_sym)
        end

        names << nil if rest.is_a?(Prism::ImplicitRestNode)

        names.concat(node.rights.map { |parameter_node| parameter_name(parameter_node) })

        names_with_commas = names.join(", ")
        :"(#{names_with_commas})"
      end
    end
  end
end
