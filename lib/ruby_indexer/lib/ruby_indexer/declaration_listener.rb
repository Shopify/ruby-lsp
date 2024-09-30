# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class DeclarationListener
    extend T::Sig

    OBJECT_NESTING = T.let(["Object"].freeze, T::Array[String])
    BASIC_OBJECT_NESTING = T.let(["BasicObject"].freeze, T::Array[String])

    sig { returns(T::Array[String]) }
    attr_reader :indexing_errors

    sig do
      params(
        index: Index,
        dispatcher: Prism::Dispatcher,
        parse_result: Prism::ParseResult,
        file_path: String,
        collect_comments: T::Boolean,
        enhancements: T::Array[Enhancement],
      ).void
    end
    def initialize(index, dispatcher, parse_result, file_path, collect_comments: false, enhancements: [])
      @index = index
      @file_path = file_path
      @enhancements = enhancements
      @visibility_stack = T.let([Entry::Visibility::PUBLIC], T::Array[Entry::Visibility])
      @comments_by_line = T.let(
        parse_result.comments.to_h do |c|
          [c.location.start_line, c]
        end,
        T::Hash[Integer, Prism::Comment],
      )
      @inside_def = T.let(false, T::Boolean)

      # The nesting stack we're currently inside. Used to determine the fully qualified name of constants, but only
      # stored by unresolved aliases which need the original nesting to be lazily resolved
      @stack = T.let([], T::Array[String])

      # A stack of namespace entries that represent where we currently are. Used to properly assign methods to an owner
      @owner_stack = T.let([], T::Array[Entry::Namespace])
      @indexing_errors = T.let([], T::Array[String])
      @collect_comments = collect_comments

      dispatcher.register(
        self,
        :on_class_node_enter,
        :on_class_node_leave,
        :on_module_node_enter,
        :on_module_node_leave,
        :on_singleton_class_node_enter,
        :on_singleton_class_node_leave,
        :on_def_node_enter,
        :on_def_node_leave,
        :on_call_node_enter,
        :on_call_node_leave,
        :on_multi_write_node_enter,
        :on_constant_path_write_node_enter,
        :on_constant_path_or_write_node_enter,
        :on_constant_path_operator_write_node_enter,
        :on_constant_path_and_write_node_enter,
        :on_constant_or_write_node_enter,
        :on_constant_write_node_enter,
        :on_constant_or_write_node_enter,
        :on_constant_and_write_node_enter,
        :on_constant_operator_write_node_enter,
        :on_instance_variable_write_node_enter,
        :on_instance_variable_and_write_node_enter,
        :on_instance_variable_operator_write_node_enter,
        :on_instance_variable_or_write_node_enter,
        :on_instance_variable_target_node_enter,
        :on_alias_method_node_enter,
      )
    end

    sig { params(node: Prism::ClassNode).void }
    def on_class_node_enter(node)
      @visibility_stack.push(Entry::Visibility::PUBLIC)
      constant_path = node.constant_path
      name = constant_path.slice

      comments = collect_comments(node)

      superclass = node.superclass

      nesting = actual_nesting(name)

      parent_class = case superclass
      when Prism::ConstantReadNode, Prism::ConstantPathNode
        superclass.slice
      else
        case nesting
        when OBJECT_NESTING
          # When Object is reopened, its parent class should still be the top-level BasicObject
          "::BasicObject"
        when BASIC_OBJECT_NESTING
          # When BasicObject is reopened, its parent class should still be nil
          nil
        else
          # Otherwise, the parent class should be the top-level Object
          "::Object"
        end
      end

      entry = Entry::Class.new(
        nesting,
        @file_path,
        node.location,
        constant_path.location,
        comments,
        @index.configuration.encoding,
        parent_class,
      )

      @owner_stack << entry
      @index.add(entry)
      @stack << name
    end

    sig { params(node: Prism::ClassNode).void }
    def on_class_node_leave(node)
      @stack.pop
      @owner_stack.pop
      @visibility_stack.pop
    end

    sig { params(node: Prism::ModuleNode).void }
    def on_module_node_enter(node)
      @visibility_stack.push(Entry::Visibility::PUBLIC)
      constant_path = node.constant_path
      name = constant_path.slice

      comments = collect_comments(node)

      entry = Entry::Module.new(
        actual_nesting(name),
        @file_path,
        node.location,
        constant_path.location,
        comments,
        @index.configuration.encoding,
      )

      @owner_stack << entry
      @index.add(entry)
      @stack << name
    end

    sig { params(node: Prism::ModuleNode).void }
    def on_module_node_leave(node)
      @stack.pop
      @owner_stack.pop
      @visibility_stack.pop
    end

    sig { params(node: Prism::SingletonClassNode).void }
    def on_singleton_class_node_enter(node)
      @visibility_stack.push(Entry::Visibility::PUBLIC)

      current_owner = @owner_stack.last

      if current_owner
        expression = node.expression
        name = (expression.is_a?(Prism::SelfNode) ? "<Class:#{@stack.last}>" : "<Class:#{expression.slice}>")
        real_nesting = actual_nesting(name)

        existing_entries = T.cast(@index[real_nesting.join("::")], T.nilable(T::Array[Entry::SingletonClass]))

        if existing_entries
          entry = T.must(existing_entries.first)
          entry.update_singleton_information(
            node.location,
            expression.location,
            collect_comments(node),
            @index.configuration.encoding,
          )
        else
          entry = Entry::SingletonClass.new(
            real_nesting,
            @file_path,
            node.location,
            expression.location,
            collect_comments(node),
            @index.configuration.encoding,
            nil,
          )
          @index.add(entry, skip_prefix_tree: true)
        end

        @owner_stack << entry
        @stack << name
      end
    end

    sig { params(node: Prism::SingletonClassNode).void }
    def on_singleton_class_node_leave(node)
      @stack.pop
      @owner_stack.pop
      @visibility_stack.pop
    end

    sig { params(node: Prism::MultiWriteNode).void }
    def on_multi_write_node_enter(node)
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
    def on_constant_path_write_node_enter(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantPathOrWriteNode).void }
    def on_constant_path_or_write_node_enter(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantPathOperatorWriteNode).void }
    def on_constant_path_operator_write_node_enter(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantPathAndWriteNode).void }
    def on_constant_path_and_write_node_enter(node)
      # ignore variable constants like `var::FOO` or `self.class::FOO`
      target = node.target
      return unless target.parent.nil? || target.parent.is_a?(Prism::ConstantReadNode)

      name = fully_qualify_name(target.location.slice)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantWriteNode).void }
    def on_constant_write_node_enter(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantOrWriteNode).void }
    def on_constant_or_write_node_enter(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantAndWriteNode).void }
    def on_constant_and_write_node_enter(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { params(node: Prism::ConstantOperatorWriteNode).void }
    def on_constant_operator_write_node_enter(node)
      name = fully_qualify_name(node.name.to_s)
      add_constant(node, name)
    end

    sig { params(node: Prism::CallNode).void }
    def on_call_node_enter(node)
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
      when :alias_method
        handle_alias_method(node)
      when :include, :prepend, :extend
        handle_module_operation(node, message)
      when :public
        @visibility_stack.push(Entry::Visibility::PUBLIC)
      when :protected
        @visibility_stack.push(Entry::Visibility::PROTECTED)
      when :private
        @visibility_stack.push(Entry::Visibility::PRIVATE)
      end

      @enhancements.each do |enhancement|
        enhancement.on_call_node(@index, @owner_stack.last, node, @file_path)
      rescue StandardError => e
        @indexing_errors << "Indexing error in #{@file_path} with '#{enhancement.class.name}' enhancement: #{e.message}"
      end
    end

    sig { params(node: Prism::CallNode).void }
    def on_call_node_leave(node)
      message = node.name
      case message
      when :public, :protected, :private
        # We want to restore the visibility stack when we leave a method definition with a visibility modifier
        # e.g. `private def foo; end`
        if node.arguments&.arguments&.first&.is_a?(Prism::DefNode)
          @visibility_stack.pop
        end
      end
    end

    sig { params(node: Prism::DefNode).void }
    def on_def_node_enter(node)
      @inside_def = true
      method_name = node.name.to_s
      comments = collect_comments(node)

      case node.receiver
      when nil
        @index.add(Entry::Method.new(
          method_name,
          @file_path,
          node.location,
          node.name_loc,
          comments,
          @index.configuration.encoding,
          [Entry::Signature.new(list_params(node.parameters))],
          current_visibility,
          @owner_stack.last,
        ))
      when Prism::SelfNode
        owner = @owner_stack.last

        if owner
          singleton = @index.existing_or_new_singleton_class(owner.name)

          @index.add(Entry::Method.new(
            method_name,
            @file_path,
            node.location,
            node.name_loc,
            comments,
            @index.configuration.encoding,
            [Entry::Signature.new(list_params(node.parameters))],
            current_visibility,
            singleton,
          ))

          @owner_stack << singleton
          @stack << "<Class:#{@stack.last}>"
        end
      end
    end

    sig { params(node: Prism::DefNode).void }
    def on_def_node_leave(node)
      @inside_def = false

      if node.receiver.is_a?(Prism::SelfNode)
        @owner_stack.pop
        @stack.pop
      end
    end

    sig { params(node: Prism::InstanceVariableWriteNode).void }
    def on_instance_variable_write_node_enter(node)
      handle_instance_variable(node, node.name_loc)
    end

    sig { params(node: Prism::InstanceVariableAndWriteNode).void }
    def on_instance_variable_and_write_node_enter(node)
      handle_instance_variable(node, node.name_loc)
    end

    sig { params(node: Prism::InstanceVariableOperatorWriteNode).void }
    def on_instance_variable_operator_write_node_enter(node)
      handle_instance_variable(node, node.name_loc)
    end

    sig { params(node: Prism::InstanceVariableOrWriteNode).void }
    def on_instance_variable_or_write_node_enter(node)
      handle_instance_variable(node, node.name_loc)
    end

    sig { params(node: Prism::InstanceVariableTargetNode).void }
    def on_instance_variable_target_node_enter(node)
      handle_instance_variable(node, node.location)
    end

    sig { params(node: Prism::AliasMethodNode).void }
    def on_alias_method_node_enter(node)
      method_name = node.new_name.slice
      comments = collect_comments(node)
      @index.add(
        Entry::UnresolvedMethodAlias.new(
          method_name,
          node.old_name.slice,
          @owner_stack.last,
          @file_path,
          node.new_name.location,
          comments,
          @index.configuration.encoding,
        ),
      )
    end

    private

    sig do
      params(
        node: T.any(
          Prism::InstanceVariableAndWriteNode,
          Prism::InstanceVariableOperatorWriteNode,
          Prism::InstanceVariableOrWriteNode,
          Prism::InstanceVariableTargetNode,
          Prism::InstanceVariableWriteNode,
        ),
        loc: Prism::Location,
      ).void
    end
    def handle_instance_variable(node, loc)
      name = node.name.to_s
      return if name == "@"

      # When instance variables are declared inside the class body, they turn into class instance variables rather than
      # regular instance variables
      owner = @owner_stack.last

      if owner && !@inside_def
        owner = @index.existing_or_new_singleton_class(owner.name)
      end

      @index.add(Entry::InstanceVariable.new(
        name,
        @file_path,
        loc,
        collect_comments(node),
        @index.configuration.encoding,
        owner,
      ))
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
      entries&.each { |entry| entry.visibility = Entry::Visibility::PRIVATE }
    end

    sig { params(node: Prism::CallNode).void }
    def handle_alias_method(node)
      arguments = node.arguments&.arguments
      return unless arguments

      new_name, old_name = arguments
      return unless new_name && old_name

      new_name_value = case new_name
      when Prism::StringNode
        new_name.content
      when Prism::SymbolNode
        new_name.value
      end

      return unless new_name_value

      old_name_value = case old_name
      when Prism::StringNode
        old_name.content
      when Prism::SymbolNode
        old_name.value
      end

      return unless old_name_value

      comments = collect_comments(node)
      @index.add(
        Entry::UnresolvedMethodAlias.new(
          new_name_value,
          old_name_value,
          @owner_stack.last,
          @file_path,
          new_name.location,
          comments,
          @index.configuration.encoding,
        ),
      )
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

      @index.add(
        case value
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          Entry::UnresolvedConstantAlias.new(
            value.slice,
            @stack.dup,
            name,
            @file_path,
            node.location,
            comments,
            @index.configuration.encoding,
          )
        when Prism::ConstantWriteNode, Prism::ConstantAndWriteNode, Prism::ConstantOrWriteNode,
        Prism::ConstantOperatorWriteNode

          # If the right hand side is another constant assignment, we need to visit it because that constant has to be
          # indexed too
          Entry::UnresolvedConstantAlias.new(
            value.name.to_s,
            @stack.dup,
            name,
            @file_path,
            node.location,
            comments,
            @index.configuration.encoding,
          )
        when Prism::ConstantPathWriteNode, Prism::ConstantPathOrWriteNode, Prism::ConstantPathOperatorWriteNode,
        Prism::ConstantPathAndWriteNode

          Entry::UnresolvedConstantAlias.new(
            value.target.slice,
            @stack.dup,
            name,
            @file_path,
            node.location,
            comments,
            @index.configuration.encoding,
          )
        else
          Entry::Constant.new(name, @file_path, node.location, comments, @index.configuration.encoding)
        end,
      )
    end

    sig { params(node: Prism::Node).returns(T.nilable(String)) }
    def collect_comments(node)
      return unless @collect_comments

      comments = +""

      start_line = node.location.start_line - 1
      start_line -= 1 unless @comments_by_line.key?(start_line)

      start_line.downto(1) do |line|
        comment = @comments_by_line[line]
        break unless comment

        comment_content = comment.location.slice

        # invalid encodings would raise an "invalid byte sequence" exception
        if !comment_content.valid_encoding? || comment_content.match?(@index.configuration.magic_comment_regex)
          next
        end

        comment_content.delete_prefix!("#")
        comment_content.delete_prefix!(" ")
        comments.prepend("#{comment_content}\n")
      end

      comments.chomp!
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
          @index.add(Entry::Accessor.new(
            name,
            @file_path,
            loc,
            comments,
            @index.configuration.encoding,
            current_visibility,
            @owner_stack.last,
          ))
        end

        next unless writer

        @index.add(Entry::Accessor.new(
          "#{name}=",
          @file_path,
          loc,
          comments,
          @index.configuration.encoding,
          current_visibility,
          @owner_stack.last,
        ))
      end
    end

    sig { params(node: Prism::CallNode, operation: Symbol).void }
    def handle_module_operation(node, operation)
      return if @inside_def

      owner = @owner_stack.last
      return unless owner

      arguments = node.arguments&.arguments
      return unless arguments

      arguments.each do |node|
        next unless node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)

        case operation
        when :include
          owner.mixin_operations << Entry::Include.new(node.full_name)
        when :prepend
          owner.mixin_operations << Entry::Prepend.new(node.full_name)
        when :extend
          singleton = @index.existing_or_new_singleton_class(owner.name)
          singleton.mixin_operations << Entry::Include.new(node.full_name)
        end
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
             Prism::ConstantPathNode::MissingNodesInConstantPathError
        # Do nothing
      end
    end

    sig { returns(Entry::Visibility) }
    def current_visibility
      T.must(@visibility_stack.last)
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

      rest = parameters_node.rest

      if rest.is_a?(Prism::RestParameterNode)
        rest_name = rest.name || Entry::RestParameter::DEFAULT_NAME
        parameters << Entry::RestParameter.new(name: rest_name)
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

      keyword_rest = parameters_node.keyword_rest

      case keyword_rest
      when Prism::KeywordRestParameterNode
        keyword_rest_name = parameter_name(keyword_rest) || Entry::KeywordRestParameter::DEFAULT_NAME
        parameters << Entry::KeywordRestParameter.new(name: keyword_rest_name)
      when Prism::ForwardingParameterNode
        parameters << Entry::ForwardingParameter.new
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

    sig { params(name: String).returns(T::Array[String]) }
    def actual_nesting(name)
      nesting = @stack + [name]
      corrected_nesting = []

      nesting.reverse_each do |name|
        corrected_nesting.prepend(name.delete_prefix("::"))

        break if name.start_with?("::")
      end

      corrected_nesting
    end
  end
end
