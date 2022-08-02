# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class HighlightTarget
        extend T::Sig

        READ = LanguageServer::Protocol::Constant::DocumentHighlightKind::READ
        WRITE = LanguageServer::Protocol::Constant::DocumentHighlightKind::WRITE

        class HighlightMatch < T::Struct
          const :type, Integer
          const :node, SyntaxTree::Node
        end

        sig { params(node: SyntaxTree::Node).void }
        def initialize(node)
          @node = node
          @value = T.let(value(node), T.nilable(String))
        end

        sig { params(other: SyntaxTree::Node).returns(T.nilable(HighlightMatch)) }
        def highlight_type(other)
          matched_highlight(other) if other.is_a?(SyntaxTree::Params) || (@value && @value == value(other))
        end

        private

        # Match the target type (where the cursor is positioned) with the `other` type (the node we're currently
        # visiting)
        sig { params(other: SyntaxTree::Node).returns(T.nilable(HighlightMatch)) }
        def matched_highlight(other)
          case @node
          # Method definitions and invocations
          when SyntaxTree::VCall, SyntaxTree::FCall, SyntaxTree::Call, SyntaxTree::Command,
               SyntaxTree::CommandCall, SyntaxTree::Def, SyntaxTree::Defs, SyntaxTree::DefEndless
            case other
            when SyntaxTree::VCall, SyntaxTree::FCall, SyntaxTree::Call, SyntaxTree::Command, SyntaxTree::CommandCall
              HighlightMatch.new(type: READ, node: other)
            when SyntaxTree::Def, SyntaxTree::Defs, SyntaxTree::Defs
              HighlightMatch.new(type: WRITE, node: other.name)
            end
          # Variables, parameters and constants
          when SyntaxTree::GVar, SyntaxTree::IVar, SyntaxTree::Const, SyntaxTree::CVar, SyntaxTree::VarField,
               SyntaxTree::VarRef, SyntaxTree::Ident
            case other
            when SyntaxTree::VarField
              HighlightMatch.new(type: WRITE, node: other)
            when SyntaxTree::VarRef
              HighlightMatch.new(type: READ, node: other)
            when SyntaxTree::ClassDeclaration, SyntaxTree::ModuleDeclaration
              HighlightMatch.new(type: WRITE, node: other.constant)
            when SyntaxTree::ConstPathRef
              HighlightMatch.new(type: READ, node: other.constant)
            when SyntaxTree::Params
              params = other.child_nodes.compact
              match = params.find { |param| value(param) == @value }
              HighlightMatch.new(type: WRITE, node: match) if match
            end
          end
        end

        sig { params(node: SyntaxTree::Node).returns(T.nilable(String)) }
        def value(node)
          case node
          when SyntaxTree::ConstPathRef, SyntaxTree::ConstPathField, SyntaxTree::TopConstField
            node.constant.value
          when SyntaxTree::GVar, SyntaxTree::IVar, SyntaxTree::Const, SyntaxTree::CVar, SyntaxTree::Ident,
               SyntaxTree::ArgsForward
            node.value
          when SyntaxTree::Field, SyntaxTree::Def, SyntaxTree::Defs, SyntaxTree::DefEndless, SyntaxTree::RestParam,
               SyntaxTree::KwRestParam, SyntaxTree::BlockArg
            node.name&.value
          when SyntaxTree::VarField, SyntaxTree::VarRef, SyntaxTree::VCall, SyntaxTree::FCall
            node.value&.value
          when SyntaxTree::Call, SyntaxTree::Command, SyntaxTree::CommandCall
            message = node.message
            message != :call ? message.value : nil
          when SyntaxTree::ClassDeclaration, SyntaxTree::ModuleDeclaration
            node.constant.constant.value
          end
        end
      end
    end
  end
end
