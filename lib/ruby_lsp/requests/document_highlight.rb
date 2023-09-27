# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # A module that contains the logic to perform document highlighting.
    module DocumentHighlight
      READ = Constant::DocumentHighlightKind::READ
      WRITE = Constant::DocumentHighlightKind::WRITE

      class Highlight
        extend T::Sig

        sig { returns(Integer) }
        attr_reader :kind

        sig { returns(YARP::Location) }
        attr_reader :location

        sig { params(kind: Integer, location: YARP::Location).void }
        def initialize(kind:, location:)
          @kind = kind
          @location = location
        end
      end

      # ![Document highlight demo](../../document_highlight.gif)
      #
      # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
      # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
      # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
      # and highlight them.
      #
      # For writable elements like constants or variables, their read/write occurrences should be highlighted
      # differently. This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
      #
      # # Example
      #
      # ```ruby
      # FOO = 1 # should be highlighted as "write"
      #
      # def foo
      #   FOO # should be highlighted as "read"
      # end
      # ```
      class HighlightListener < Listener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { override.returns(ResponseType) }
        attr_reader :_response

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
        def initialize(emitter, message_queue)
          super(emitter, message_queue)
          @_response = T.let([], ResponseType)
        end

        private

        sig { params(highlight: Highlight).void }
        def add_highlight(highlight)
          range = range_from_location(highlight.location)
          @_response << Interface::DocumentHighlight.new(range: range, kind: highlight.kind)
        end
      end

      # ![Document highlight demo](../../document_highlight.gif)
      #
      # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
      # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
      # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
      # and highlight them.
      #
      # For writable elements like constants or variables, their read/write occurrences should be highlighted
      # differently. This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
      #
      # # Example
      #
      # ```ruby
      # foo.bar # should be highlighted as "read"
      #
      # def bar # should be highlighted as "write"
      # end
      # ```
      class CallHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(String) }
        attr_reader :message

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue, message: T.nilable(String)).void }
        def initialize(emitter, message_queue, message)
          super(emitter, message_queue)
          return unless message

          @message = T.let(message, String)
          emitter.register(self, :on_call, :on_def)
        end

        sig { params(node: YARP::CallNode).void }
        def on_call(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if node.message == message
        end

        sig { params(node: YARP::DefNode).void }
        def on_def(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name.to_s == message
        end
      end

      # ![Document highlight demo](../../document_highlight.gif)
      #
      # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
      # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
      # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
      # and highlight them.
      #
      # For writable elements like constants or variables, their read/write occurrences should be highlighted
      # differently. This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
      #
      # # Example
      #
      # ```ruby
      # @@foo = 1 # should be highlighted as "write"
      #
      # def foo
      #   @@foo # should be highlighted as "read"
      # end
      # ```
      class ClassVariableHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(Symbol) }
        attr_reader :name

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue, name: Symbol).void }
        def initialize(emitter, message_queue, name)
          super(emitter, message_queue)

          @name = T.let(name, Symbol)
          emitter.register(
            self,
            :on_class_variable_read,
            :on_class_variable_target,
            :on_class_variable_write,
            :on_class_variable_and_write,
            :on_class_variable_or_write,
            :on_class_variable_operator_write,
          )
        end

        sig { params(node: YARP::ClassVariableReadNode).void }
        def on_class_variable_read(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableTargetNode).void }
        def on_class_variable_target(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableWriteNode).void }
        def on_class_variable_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableAndWriteNode).void }
        def on_class_variable_and_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableOrWriteNode).void }
        def on_class_variable_or_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableOperatorWriteNode).void }
        def on_class_variable_operator_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end
      end

      # ![Document highlight demo](../../document_highlight.gif)
      #
      # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
      # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
      # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
      # and highlight them.
      #
      # For writable elements like constants or variables, their read/write occurrences should be highlighted
      # differently. This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
      #
      # # Example
      #
      # ```ruby
      # FOO = 1 # should be highlighted as "write"
      #
      # def foo
      #   FOO # should be highlighted as "read"
      # end
      # ```
      class ConstantHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(Symbol) }
        attr_reader :name

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue, name: Symbol).void }
        def initialize(emitter, message_queue, name)
          super(emitter, message_queue)

          @name = T.let(name, Symbol)
          emitter.register(
            self,
            :on_class,
            :on_constant_read,
            :on_constant_target,
            :on_constant_write,
            :on_constant_and_write,
            :on_constant_or_write,
            :on_constant_operator_write,
            :on_module,
          )
        end

        sig { params(node: YARP::ClassNode).void }
        def on_class(node)
          constant_path = node.constant_path

          if constant_path.is_a?(YARP::ConstantReadNode) && constant_path.name == name
            add_highlight(Highlight.new(kind: WRITE, location: node.constant_path.location))
          end
        end

        sig { params(node: YARP::ConstantReadNode).void }
        def on_constant_read(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::ConstantTargetNode).void }
        def on_constant_target(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::ConstantWriteNode).void }
        def on_constant_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ConstantAndWriteNode).void }
        def on_constant_and_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ConstantOrWriteNode).void }
        def on_constant_or_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ConstantOperatorWriteNode).void }
        def on_constant_operator_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ModuleNode).void }
        def on_module(node)
          constant_path = node.constant_path

          if constant_path.is_a?(YARP::ConstantReadNode) && constant_path.name == name
            add_highlight(Highlight.new(kind: WRITE, location: node.constant_path.location))
          end
        end
      end

      # ![Document highlight demo](../../document_highlight.gif)
      #
      # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
      # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
      # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
      # and highlight them.
      #
      # For writable elements like constants or variables, their read/write occurrences should be highlighted
      # differently. This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
      #
      # # Example
      #
      # ```ruby
      # FOO::BAR = 1 # should be highlighted as "write"
      #
      # def foo
      #   FOO::BAR # should be highlighted as "read"
      # end
      # ```
      class ConstantPathHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(T::Array[T.nilable(Symbol)]) }
        attr_reader :names

        sig do
          params(
            emitter: EventEmitter,
            message_queue: Thread::Queue,
            node: T.any(YARP::ConstantPathNode, YARP::ConstantPathTargetNode),
          ).void
        end
        def initialize(emitter, message_queue, node)
          super(emitter, message_queue)

          @names = T.let(path_names(node), T::Array[T.nilable(Symbol)])
          emitter.register(
            self,
            :on_class,
            :on_constant_path,
            :on_constant_path_target,
            :on_constant_path_write,
            :on_constant_path_and_write,
            :on_constant_path_or_write,
            :on_constant_path_operator_write,
            :on_module,
          )
        end

        sig { params(node: YARP::ClassNode).void }
        def on_class(node)
          constant_path = node.constant_path

          if constant_path.is_a?(YARP::ConstantPathNode) && path_names(constant_path) == names
            add_highlight(Highlight.new(kind: WRITE, location: node.constant_path.location))
          end
        end

        sig { params(node: YARP::ConstantPathNode).void }
        def on_constant_path(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if path_names(node) == names
        end

        sig { params(node: YARP::ConstantPathTargetNode).void }
        def on_constant_path_target(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if path_names(node) == names
        end

        sig { params(node: YARP::ConstantPathWriteNode).void }
        def on_constant_path_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.target.location)) if path_names(node.target) == names
        end

        sig { params(node: YARP::ConstantPathAndWriteNode).void }
        def on_constant_path_and_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.target.location)) if path_names(node.target) == names
        end

        sig { params(node: YARP::ConstantPathOrWriteNode).void }
        def on_constant_path_or_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.target.location)) if path_names(node.target) == names
        end

        sig { params(node: YARP::ConstantPathOperatorWriteNode).void }
        def on_constant_path_operator_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.target.location)) if path_names(node.target) == names
        end

        sig { params(node: YARP::ModuleNode).void }
        def on_module(node)
          constant_path = node.constant_path

          if constant_path.is_a?(YARP::ConstantPathNode) && path_names(constant_path) == names
            add_highlight(Highlight.new(kind: WRITE, location: node.constant_path.location))
          end
        end

        private

        sig do
          params(node: T.any(YARP::ConstantPathNode, YARP::ConstantPathTargetNode)).returns(T::Array[T.nilable(Symbol)])
        end
        def path_names(node)
          queue = [node]
          names = []

          while (current = queue.shift)
            child = current.child
            names << child.name if child.is_a?(YARP::ConstantReadNode)

            parent = current.parent
            if parent.is_a?(YARP::ConstantPathNode)
              queue << parent
            elsif parent.is_a?(YARP::ConstantReadNode)
              names << parent.name
            else
              names << nil
            end
          end

          names.reverse
        end
      end

      # ![Document highlight demo](../../document_highlight.gif)
      #
      # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
      # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
      # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
      # and highlight them.
      #
      # For writable elements like constants or variables, their read/write occurrences should be highlighted
      # differently. This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
      #
      # # Example
      #
      # ```ruby
      # $foo = 1 # should be highlighted as "write"
      #
      # def foo
      #   $foo # should be highlighted as "read"
      # end
      # ```
      class GlobalVariableHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(Symbol) }
        attr_reader :name

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue, name: Symbol).void }
        def initialize(emitter, message_queue, name)
          super(emitter, message_queue)

          @name = T.let(name, Symbol)
          emitter.register(
            self,
            :on_global_variable_read,
            :on_global_variable_target,
            :on_global_variable_write,
            :on_global_variable_and_write,
            :on_global_variable_or_write,
            :on_global_variable_operator_write,
          )
        end

        sig { params(node: YARP::GlobalVariableReadNode).void }
        def on_global_variable_read(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableTargetNode).void }
        def on_global_variable_target(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableWriteNode).void }
        def on_global_variable_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableAndWriteNode).void }
        def on_global_variable_and_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableOrWriteNode).void }
        def on_global_variable_or_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableOperatorWriteNode).void }
        def on_global_variable_operator_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end
      end

      # ![Document highlight demo](../../document_highlight.gif)
      #
      # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
      # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
      # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
      # and highlight them.
      #
      # For writable elements like constants or variables, their read/write occurrences should be highlighted
      # differently. This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
      #
      # # Example
      #
      # ```ruby
      # @foo = 1 # should be highlighted as "write"
      #
      # def foo
      #   @foo # should be highlighted as "read"
      # end
      # ```
      class InstanceVariableHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(Symbol) }
        attr_reader :name

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue, name: Symbol).void }
        def initialize(emitter, message_queue, name)
          super(emitter, message_queue)

          @name = T.let(name, Symbol)
          emitter.register(
            self,
            :on_instance_variable_read,
            :on_instance_variable_target,
            :on_instance_variable_write,
            :on_instance_variable_and_write,
            :on_instance_variable_or_write,
            :on_instance_variable_operator_write,
          )
        end

        sig { params(node: YARP::InstanceVariableReadNode).void }
        def on_instance_variable_read(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableTargetNode).void }
        def on_instance_variable_target(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableWriteNode).void }
        def on_instance_variable_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableAndWriteNode).void }
        def on_instance_variable_and_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableOrWriteNode).void }
        def on_instance_variable_or_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableOperatorWriteNode).void }
        def on_instance_variable_operator_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end
      end

      # ![Document highlight demo](../../document_highlight.gif)
      #
      # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
      # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
      # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
      # and highlight them.
      #
      # For writable elements like constants or variables, their read/write occurrences should be highlighted
      # differently. This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
      #
      # # Example
      #
      # ```ruby
      # bar = 1 # should be highlighted as "write"
      #
      # foo do
      #   bar # should be highlighted as "read"
      # end
      # ```
      class LocalVariableHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(Symbol) }
        attr_reader :name

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue, name: T.nilable(Symbol)).void }
        def initialize(emitter, message_queue, name)
          super(emitter, message_queue)
          return unless name

          @name = T.let(name, Symbol)
          emitter.register(
            self,
            :on_block_parameter,
            :on_def,
            :on_keyword_parameter,
            :on_keyword_rest_parameter,
            :on_local_variable_read,
            :on_local_variable_target,
            :on_local_variable_write,
            :on_local_variable_and_write,
            :on_local_variable_or_write,
            :on_local_variable_operator_write,
            :on_optional_parameter,
            :on_required_parameter,
            :on_rest_parameter,
          )
        end

        sig { params(node: YARP::BlockParameterNode).void }
        def on_block_parameter(node)
          add_highlight(Highlight.new(kind: WRITE, location: T.must(node.name_loc))) if node.name == name
        end

        sig { params(node: YARP::DefNode).void }
        def on_def(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::KeywordParameterNode).void }
        def on_keyword_parameter(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::KeywordRestParameterNode).void }
        def on_keyword_rest_parameter(node)
          add_highlight(Highlight.new(kind: WRITE, location: T.must(node.name_loc))) if node.name == name
        end

        sig { params(node: YARP::LocalVariableReadNode).void }
        def on_local_variable_read(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::LocalVariableTargetNode).void }
        def on_local_variable_target(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::LocalVariableWriteNode).void }
        def on_local_variable_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::LocalVariableAndWriteNode).void }
        def on_local_variable_and_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::LocalVariableOrWriteNode).void }
        def on_local_variable_or_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::LocalVariableOperatorWriteNode).void }
        def on_local_variable_operator_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::OptionalParameterNode).void }
        def on_optional_parameter(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::RequiredParameterNode).void }
        def on_required_parameter(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::RestParameterNode).void }
        def on_rest_parameter(node)
          add_highlight(Highlight.new(kind: WRITE, location: T.must(node.name_loc))) if node.name == name
        end
      end

      # ![Document highlight demo](../../document_highlight.gif)
      #
      # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
      # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
      # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
      # and highlight them.
      #
      # For writable elements like constants or variables, their read/write occurrences should be highlighted
      # differently. This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
      #
      # # Example
      #
      # ```ruby
      # class Foo # when this is highlighted, the null highlight will be used to not match anything
      # end
      # ```
      class NullHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }
      end

      class << self
        extend T::Sig

        sig do
          type_parameters(:ResponseType)
            .params(
              target: T.nilable(YARP::Node),
              parent: T.nilable(YARP::Node),
              emitter: EventEmitter,
              message_queue: Thread::Queue,
            ).returns(Listener[T::Array[Interface::DocumentHighlight]])
        end
        def for(target, parent, emitter, message_queue)
          case target
          when YARP::CallNode
            CallHighlight.new(emitter, message_queue, target.message)
          when YARP::ClassVariableReadNode, YARP::ClassVariableTargetNode, YARP::ClassVariableWriteNode,
               YARP::ClassVariableAndWriteNode, YARP::ClassVariableOrWriteNode, YARP::ClassVariableOperatorWriteNode
            ClassVariableHighlight.new(emitter, message_queue, target.name)
          when YARP::ConstantReadNode, YARP::ConstantTargetNode, YARP::ConstantWriteNode, YARP::ConstantAndWriteNode,
               YARP::ConstantOrWriteNode, YARP::ConstantOperatorWriteNode
            ConstantHighlight.new(emitter, message_queue, target.name)
          when YARP::ConstantPathNode, YARP::ConstantPathTargetNode
            ConstantPathHighlight.new(emitter, message_queue, target)
          when YARP::ConstantPathWriteNode, YARP::ConstantPathAndWriteNode, YARP::ConstantPathOrWriteNode,
               YARP::ConstantPathOperatorWriteNode
            ConstantPathHighlight.new(emitter, message_queue, target.target)
          when YARP::GlobalVariableReadNode, YARP::GlobalVariableTargetNode, YARP::GlobalVariableWriteNode,
               YARP::GlobalVariableAndWriteNode, YARP::GlobalVariableOrWriteNode, YARP::GlobalVariableOperatorWriteNode
            GlobalVariableHighlight.new(emitter, message_queue, target.name)
          when YARP::InstanceVariableReadNode, YARP::InstanceVariableTargetNode, YARP::InstanceVariableWriteNode,
               YARP::InstanceVariableAndWriteNode, YARP::InstanceVariableOrWriteNode,
               YARP::InstanceVariableOperatorWriteNode
            InstanceVariableHighlight.new(emitter, message_queue, target.name)
          when YARP::LocalVariableReadNode, YARP::LocalVariableTargetNode, YARP::LocalVariableWriteNode,
               YARP::LocalVariableAndWriteNode, YARP::LocalVariableOrWriteNode, YARP::LocalVariableOperatorWriteNode,
               YARP::BlockParameterNode, YARP::KeywordParameterNode, YARP::KeywordRestParameterNode,
               YARP::OptionalParameterNode, YARP::RequiredParameterNode, YARP::RestParameterNode
            LocalVariableHighlight.new(emitter, message_queue, target.name)
          else
            NullHighlight.new(emitter, message_queue)
          end
        end
      end
    end
  end
end
