# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class HighlightTarget
        extend T::Sig

        READ = LanguageServer::Protocol::Constant::DocumentHighlightKind::READ
        WRITE = LanguageServer::Protocol::Constant::DocumentHighlightKind::WRITE

        sig { params(node: SyntaxTree::Node).void }
        def initialize(node)
          @node = node
          @value = T.let(value(node), T.nilable(String))
        end

        sig { params(other: SyntaxTree::Node).returns(T.nilable(Integer)) }
        def highlight_type(other)
          matched_highlight(other) if @value == value(other)
        end

        private

        sig { params(other: SyntaxTree::Node).returns(T.nilable(Integer)) }
        def matched_highlight(other)
          case @node
          when SyntaxTree::VCall
            if other.is_a?(SyntaxTree::VCall)
              READ
            elsif other.is_a?(SyntaxTree::Def)
              WRITE
            end
          when SyntaxTree::GVar,
               SyntaxTree::IVar,
               SyntaxTree::Const,
               SyntaxTree::CVar,
               SyntaxTree::VarField,
               SyntaxTree::VarRef
            if other.is_a?(SyntaxTree::VarField)
              WRITE
            elsif other.is_a?(SyntaxTree::VarRef)
              READ
            end
          end
        end

        sig { params(node: SyntaxTree::Node).returns(T.nilable(String)) }
        def value(node)
          case node
          when SyntaxTree::GVar, SyntaxTree::IVar, SyntaxTree::Const, SyntaxTree::CVar
            node.value
          when SyntaxTree::Assign
            value(node.target)
          when SyntaxTree::ConstPathField, SyntaxTree::TopConstField
            node.constant.value
          when SyntaxTree::Field
            node.name.value
          when SyntaxTree::VarField, SyntaxTree::VarRef
            node.value&.value
          when SyntaxTree::Ident
            node.value
          end
        end
      end
    end
  end
end
