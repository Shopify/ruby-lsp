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
        uri: URI::Generic,
        collect_comments: T::Boolean,
      ).void
    end
    def initialize(index, dispatcher, parse_result, uri, collect_comments: false)
      @index = index
      @uri = uri
      @enhancements = T.let(Enhancement.all(self), T::Array[Enhancement])
      @visibility_stack = T.let([VisibilityScope.public_scope], T::Array[VisibilityScope])
      @comments_by_line = T.let(
        parse_result.comments.to_h do |c|
          [c.location.start_line, c]
        end,
        T::Hash[Integer, Prism::Comment],
      )
      @inside_def = T.let(false, T::Boolean)
      @code_units_cache = T.let(
        parse_result.code_units_cache(@index.configuration.encoding),
        T.any(T.proc.params(arg0: Integer).returns(Integer), Prism::CodeUnitsCache),
      )
      @source_lines = T.let(parse_result.source.lines, T::Array[String])

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
        :on_constant_write_node_enter,
        :on_constant_or_write_node_enter,
        :on_constant_and_write_node_enter,
        :on_constant_operator_write_node_enter,
        :on_global_variable_and_write_node_enter,
        :on_global_variable_operator_write_node_enter,
        :on_global_variable_or_write_node_enter,
        :on_global_variable_target_node_enter,
        :on_global_variable_write_node_enter,
        :on_instance_variable_write_node_enter,
        :on_instance_variable_and_write_node_enter,
        :on_instance_variable_operator_write_node_enter,
        :on_instance_variable_or_write_node_enter,
        :on_instance_variable_target_node_enter,
        :on_alias_method_node_enter,
        :on_class_variable_and_write_node_enter,
        :on_class_variable_operator_write_node_enter,
        :on_class_variable_or_write_node_enter,
        :on_class_variable_target_node_enter,
        :on_class_variable_write_node_enter,
      )
    end

    sig { params(node: Prism::ClassNode).void }
    def on_class_node_enter(node)
      constant_path = node.constant_path
      superclass = node.superclass
      nesting = actual_nesting(constant_path.slice)

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

      add_class(
        nesting,
        node.location,
        constant_path.location,
        parent_class_name: parent_class,
        comments: collect_comments(node),
      )
    end

    sig { params(node: Prism::ClassNode).void }
    def on_class_node_leave(node)
      pop_namespace_stack
    end

    sig { params(node: Prism::ModuleNode).void }
    def on_module_node_enter(node)
      constant_path = node.constant_path
      add_module(constant_path.slice, node.location, constant_path.location, comments: collect_comments(node))
    end

    sig { params(node: Prism::ModuleNode).void }
    def on_module_node_leave(node)
      pop_namespace_stack
    end

    sig { params(node: Prism::SingletonClassNode).void }
    def on_singleton_class_node_enter(node)
      @visibility_stack.push(VisibilityScope.public_scope)

      current_owner = @owner_stack.last

      if current_owner
        expression = node.expression
        name = (expression.is_a?(Prism::SelfNode) ? "<Class:#{last_name_in_stack}>" : "<Class:#{expression.slice}>")
        real_nesting = actual_nesting(name)

        existing_entries = T.cast(@index[real_nesting.join("::")], T.nilable(T::Array[Entry::SingletonClass]))

        if existing_entries
          entry = T.must(existing_entries.first)
          entry.update_singleton_information(
            Location.from_prism_location(node.location, @code_units_cache),
            Location.from_prism_location(expression.location, @code_units_cache),
            collect_comments(node),
          )
        else
          entry = Entry::SingletonClass.new(
            real_nesting,
            @uri,
            Location.from_prism_location(node.location, @code_units_cache),
            Location.from_prism_location(expression.location, @code_units_cache),
            collect_comments(node),
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
      pop_namespace_stack
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
        @visibility_stack.push(VisibilityScope.public_scope)
      when :protected
        @visibility_stack.push(VisibilityScope.new(visibility: Entry::Visibility::PROTECTED))
      when :private
        @visibility_stack.push(VisibilityScope.new(visibility: Entry::Visibility::PRIVATE))
      when :module_function
        handle_module_function(node)
      when :private_class_method
        handle_private_class_method(node)
      end

      @enhancements.each do |enhancement|
        enhancement.on_call_node_enter(node)
      rescue StandardError => e
        @indexing_errors << <<~MSG
          Indexing error in #{@uri} with '#{enhancement.class.name}' on call node enter enhancement: #{e.message}
        MSG
      end
    end

    sig { params(node: Prism::CallNode).void }
    def on_call_node_leave(node)
      message = node.name
      case message
      when :public, :protected, :private, :private_class_method
        # We want to restore the visibility stack when we leave a method definition with a visibility modifier
        # e.g. `private def foo; end`
        if node.arguments&.arguments&.first&.is_a?(Prism::DefNode)
          @visibility_stack.pop
        end
      end

      @enhancements.each do |enhancement|
        enhancement.on_call_node_leave(node)
      rescue StandardError => e
        @indexing_errors << <<~MSG
          Indexing error in #{@uri} with '#{enhancement.class.name}' on call node leave enhancement: #{e.message}
        MSG
      end
    end

    sig { params(node: Prism::DefNode).void }
    def on_def_node_enter(node)
      owner = @owner_stack.last
      return unless owner

      @inside_def = true
      method_name = node.name.to_s
      comments = collect_comments(node)
      scope = current_visibility_scope

      case node.receiver
      when nil
        location = Location.from_prism_location(node.location, @code_units_cache)
        name_location = Location.from_prism_location(node.name_loc, @code_units_cache)
        signatures = [Entry::Signature.new(list_params(node.parameters))]

        @index.add(Entry::Method.new(
          method_name,
          @uri,
          location,
          name_location,
          comments,
          signatures,
          scope.visibility,
          owner,
        ))

        if scope.module_func
          singleton = @index.existing_or_new_singleton_class(owner.name)

          @index.add(Entry::Method.new(
            method_name,
            @uri,
            location,
            name_location,
            comments,
            signatures,
            Entry::Visibility::PUBLIC,
            singleton,
          ))
        end
      when Prism::SelfNode
        singleton = @index.existing_or_new_singleton_class(owner.name)

        @index.add(Entry::Method.new(
          method_name,
          @uri,
          Location.from_prism_location(node.location, @code_units_cache),
          Location.from_prism_location(node.name_loc, @code_units_cache),
          comments,
          [Entry::Signature.new(list_params(node.parameters))],
          scope.visibility,
          singleton,
        ))

        @owner_stack << singleton
      end
    end

    sig { params(node: Prism::DefNode).void }
    def on_def_node_leave(node)
      @inside_def = false

      if node.receiver.is_a?(Prism::SelfNode)
        @owner_stack.pop
      end
    end

    sig { params(node: Prism::GlobalVariableAndWriteNode).void }
    def on_global_variable_and_write_node_enter(node)
      handle_global_variable(node, node.name_loc)
    end

    sig { params(node: Prism::GlobalVariableOperatorWriteNode).void }
    def on_global_variable_operator_write_node_enter(node)
      handle_global_variable(node, node.name_loc)
    end

    sig { params(node: Prism::GlobalVariableOrWriteNode).void }
    def on_global_variable_or_write_node_enter(node)
      handle_global_variable(node, node.name_loc)
    end

    sig { params(node: Prism::GlobalVariableTargetNode).void }
    def on_global_variable_target_node_enter(node)
      handle_global_variable(node, node.location)
    end

    sig { params(node: Prism::GlobalVariableWriteNode).void }
    def on_global_variable_write_node_enter(node)
      handle_global_variable(node, node.name_loc)
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
          @uri,
          Location.from_prism_location(node.new_name.location, @code_units_cache),
          comments,
        ),
      )
    end

    sig { params(node: Prism::ClassVariableAndWriteNode).void }
    def on_class_variable_and_write_node_enter(node)
      handle_class_variable(node, node.name_loc)
    end

    sig { params(node: Prism::ClassVariableOperatorWriteNode).void }
    def on_class_variable_operator_write_node_enter(node)
      handle_class_variable(node, node.name_loc)
    end

    sig { params(node: Prism::ClassVariableOrWriteNode).void }
    def on_class_variable_or_write_node_enter(node)
      handle_class_variable(node, node.name_loc)
    end

    sig { params(node: Prism::ClassVariableTargetNode).void }
    def on_class_variable_target_node_enter(node)
      handle_class_variable(node, node.location)
    end

    sig { params(node: Prism::ClassVariableWriteNode).void }
    def on_class_variable_write_node_enter(node)
      handle_class_variable(node, node.name_loc)
    end

    sig do
      params(
        name: String,
        node_location: Prism::Location,
        signatures: T::Array[Entry::Signature],
        visibility: Entry::Visibility,
        comments: T.nilable(String),
      ).void
    end
    def add_method(name, node_location, signatures, visibility: Entry::Visibility::PUBLIC, comments: nil)
      location = Location.from_prism_location(node_location, @code_units_cache)

      @index.add(Entry::Method.new(
        name,
        @uri,
        location,
        location,
        comments,
        signatures,
        visibility,
        @owner_stack.last,
      ))
    end

    sig do
      params(
        name: String,
        full_location: Prism::Location,
        name_location: Prism::Location,
        comments: T.nilable(String),
      ).void
    end
    def add_module(name, full_location, name_location, comments: nil)
      location = Location.from_prism_location(full_location, @code_units_cache)
      name_loc = Location.from_prism_location(name_location, @code_units_cache)

      entry = Entry::Module.new(
        actual_nesting(name),
        @uri,
        location,
        name_loc,
        comments,
      )

      advance_namespace_stack(name, entry)
    end

    sig do
      params(
        name_or_nesting: T.any(String, T::Array[String]),
        full_location: Prism::Location,
        name_location: Prism::Location,
        parent_class_name: T.nilable(String),
        comments: T.nilable(String),
      ).void
    end
    def add_class(name_or_nesting, full_location, name_location, parent_class_name: nil, comments: nil)
      nesting = name_or_nesting.is_a?(Array) ? name_or_nesting : actual_nesting(name_or_nesting)
      entry = Entry::Class.new(
        nesting,
        @uri,
        Location.from_prism_location(full_location, @code_units_cache),
        Location.from_prism_location(name_location, @code_units_cache),
        comments,
        parent_class_name,
      )

      advance_namespace_stack(T.must(nesting.last), entry)
    end

    sig { params(block: T.proc.params(index: Index, base: Entry::Namespace).void).void }
    def register_included_hook(&block)
      owner = @owner_stack.last
      return unless owner

      @index.register_included_hook(owner.name) do |index, base|
        block.call(index, base)
      end
    end

    sig { void }
    def pop_namespace_stack
      @stack.pop
      @owner_stack.pop
      @visibility_stack.pop
    end

    sig { returns(T.nilable(Entry::Namespace)) }
    def current_owner
      @owner_stack.last
    end

    private

    sig do
      params(
        node: T.any(
          Prism::GlobalVariableAndWriteNode,
          Prism::GlobalVariableOperatorWriteNode,
          Prism::GlobalVariableOrWriteNode,
          Prism::GlobalVariableTargetNode,
          Prism::GlobalVariableWriteNode,
        ),
        loc: Prism::Location,
      ).void
    end
    def handle_global_variable(node, loc)
      name = node.name.to_s
      comments = collect_comments(node)

      @index.add(Entry::GlobalVariable.new(
        name,
        @uri,
        Location.from_prism_location(loc, @code_units_cache),
        comments,
      ))
    end

    sig do
      params(
        node: T.any(
          Prism::ClassVariableAndWriteNode,
          Prism::ClassVariableOperatorWriteNode,
          Prism::ClassVariableOrWriteNode,
          Prism::ClassVariableTargetNode,
          Prism::ClassVariableWriteNode,
        ),
        loc: Prism::Location,
      ).void
    end
    def handle_class_variable(node, loc)
      name = node.name.to_s
      # Ignore incomplete class variable names, which aren't valid Ruby syntax.
      # This could occur if the code is in an incomplete or temporary state.
      return if name == "@@"

      comments = collect_comments(node)

      owner = @owner_stack.last

      # set the class variable's owner to the attached context when defined within a singleton scope.
      if owner.is_a?(Entry::SingletonClass)
        owner = @owner_stack.reverse.find { |entry| !entry.name.include?("<Class:") }
      end

      @index.add(Entry::ClassVariable.new(
        name,
        @uri,
        Location.from_prism_location(loc, @code_units_cache),
        comments,
        owner,
      ))
    end

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
        @uri,
        Location.from_prism_location(loc, @code_units_cache),
        collect_comments(node),
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
          @uri,
          Location.from_prism_location(new_name.location, @code_units_cache),
          comments,
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
            @uri,
            Location.from_prism_location(node.location, @code_units_cache),
            comments,
          )
        when Prism::ConstantWriteNode, Prism::ConstantAndWriteNode, Prism::ConstantOrWriteNode,
        Prism::ConstantOperatorWriteNode

          # If the right hand side is another constant assignment, we need to visit it because that constant has to be
          # indexed too
          Entry::UnresolvedConstantAlias.new(
            value.name.to_s,
            @stack.dup,
            name,
            @uri,
            Location.from_prism_location(node.location, @code_units_cache),
            comments,
          )
        when Prism::ConstantPathWriteNode, Prism::ConstantPathOrWriteNode, Prism::ConstantPathOperatorWriteNode,
        Prism::ConstantPathAndWriteNode

          Entry::UnresolvedConstantAlias.new(
            value.target.slice,
            @stack.dup,
            name,
            @uri,
            Location.from_prism_location(node.location, @code_units_cache),
            comments,
          )
        else
          Entry::Constant.new(
            name,
            @uri,
            Location.from_prism_location(node.location, @code_units_cache),
            comments,
          )
        end,
      )
    end

    sig { params(node: Prism::Node).returns(T.nilable(String)) }
    def collect_comments(node)
      return unless @collect_comments

      comments = +""

      start_line = node.location.start_line - 1
      start_line -= 1 unless comment_exists_at?(start_line)
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

    sig { params(line: Integer).returns(T::Boolean) }
    def comment_exists_at?(line)
      @comments_by_line.key?(line) || !@source_lines[line - 1].to_s.strip.empty?
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
      scope = current_visibility_scope

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
            @uri,
            Location.from_prism_location(loc, @code_units_cache),
            comments,
            scope.visibility,
            @owner_stack.last,
          ))
        end

        next unless writer

        @index.add(Entry::Accessor.new(
          "#{name}=",
          @uri,
          Location.from_prism_location(loc, @code_units_cache),
          comments,
          scope.visibility,
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
        next unless node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode) ||
          (node.is_a?(Prism::SelfNode) && operation == :extend)

        if node.is_a?(Prism::SelfNode)
          singleton = @index.existing_or_new_singleton_class(owner.name)
          singleton.mixin_operations << Entry::Include.new(owner.name)
        else
          case operation
          when :include
            owner.mixin_operations << Entry::Include.new(node.full_name)
          when :prepend
            owner.mixin_operations << Entry::Prepend.new(node.full_name)
          when :extend
            singleton = @index.existing_or_new_singleton_class(owner.name)
            singleton.mixin_operations << Entry::Include.new(node.full_name)
          end
        end
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
             Prism::ConstantPathNode::MissingNodesInConstantPathError
        # Do nothing
      end
    end

    sig { params(node: Prism::CallNode).void }
    def handle_module_function(node)
      # Invoking `module_function` in a class raises
      owner = @owner_stack.last
      return unless owner.is_a?(Entry::Module)

      arguments_node = node.arguments

      # If `module_function` is invoked without arguments, all methods defined after it become singleton methods and the
      # visibility for instance methods changes to private
      unless arguments_node
        @visibility_stack.push(VisibilityScope.module_function_scope)
        return
      end

      owner_name = owner.name

      arguments_node.arguments.each do |argument|
        method_name = case argument
        when Prism::StringNode
          argument.content
        when Prism::SymbolNode
          argument.value
        end
        next unless method_name

        entries = @index.resolve_method(method_name, owner_name)
        next unless entries

        entries.each do |entry|
          entry_owner_name = entry.owner&.name
          next unless entry_owner_name

          entry.visibility = Entry::Visibility::PRIVATE

          singleton = @index.existing_or_new_singleton_class(entry_owner_name)
          location = Location.from_prism_location(argument.location, @code_units_cache)
          @index.add(Entry::Method.new(
            method_name,
            @uri,
            location,
            location,
            collect_comments(node)&.concat(entry.comments),
            entry.signatures,
            Entry::Visibility::PUBLIC,
            singleton,
          ))
        end
      end
    end

    sig { params(node: Prism::CallNode).void }
    def handle_private_class_method(node)
      arguments = node.arguments&.arguments
      return unless arguments

      # If we're passing a method definition directly to `private_class_method`, push a new private scope. That will be
      # applied when the indexer finds the method definition and then popped on `call_node_leave`
      if arguments.first.is_a?(Prism::DefNode)
        @visibility_stack.push(VisibilityScope.new(visibility: Entry::Visibility::PRIVATE))
        return
      end

      owner_name = @owner_stack.last&.name
      return unless owner_name

      # private_class_method accepts strings, symbols or arrays of strings and symbols as arguments. Here we build a
      # single list of all of the method names that have to be made private
      arrays, others = T.cast(
        arguments.partition { |argument| argument.is_a?(Prism::ArrayNode) },
        [T::Array[Prism::ArrayNode], T::Array[Prism::Node]],
      )
      arrays.each { |array| others.concat(array.elements) }

      names = others.filter_map do |argument|
        case argument
        when Prism::StringNode
          argument.unescaped
        when Prism::SymbolNode
          argument.value
        end
      end

      names.each do |name|
        entries = @index.resolve_method(name, @index.existing_or_new_singleton_class(owner_name).name)
        next unless entries

        entries.each do |entry|
          entry.visibility = Entry::Visibility::PRIVATE
        end
      end
    end

    sig { returns(VisibilityScope) }
    def current_visibility_scope
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

    sig { params(short_name: String, entry: Entry::Namespace).void }
    def advance_namespace_stack(short_name, entry)
      @visibility_stack.push(VisibilityScope.public_scope)
      @owner_stack << entry
      @index.add(entry)
      @stack << short_name
    end

    # Returns the last name in the stack not as we found it, but in terms of declared constants. For example, if the
    # last entry in the stack is a compact namespace like `Foo::Bar`, then the last name is `Bar`
    sig { returns(T.nilable(String)) }
    def last_name_in_stack
      name = @stack.last
      return unless name

      name.split("::").last
    end
  end
end
