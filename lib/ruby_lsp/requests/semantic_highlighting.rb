# typed: true
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [semantic
    # highlighting](https://microsoft.github.io/language-server-protocol/specification#textDocument_semanticTokens)
    # request informs the editor of the correct token types to provide consistent and accurate highlighting for themes.
    #
    # # Example
    #
    # ```ruby
    # def foo
    #   var = 1 # --> semantic highlighting: local variable
    #   some_invocation # --> semantic highlighting: method invocation
    #   var # --> semantic highlighting: local variable
    # end
    # ```
    class SemanticHighlighting < BaseRequest
      TOKEN_TYPES = [
        :variable,
        :method,
      ].freeze

      TOKEN_MODIFIERS = {
        declaration: 0,
        definition: 1,
        readonly: 2,
        static: 3,
        deprecated: 4,
        abstract: 5,
        async: 6,
        modification: 7,
        documentation: 8,
        default_library: 9,
      }.freeze

      SemanticToken = Struct.new(:location, :length, :type, :modifier)

      def initialize(document, encoder: nil)
        super(document)

        @encoder = encoder
        @tokens = []
        @tree = document.tree
      end

      def run
        visit(@tree)
        return @tokens unless @encoder

        @encoder.encode(@tokens)
      end

      def visit_m_assign(node)
        node.target.parts.each do |var_ref|
          add_token(var_ref.value.location, :variable)
        end
      end

      def visit_var_field(node)
        case node.value
        when SyntaxTree::Ident
          add_token(node.value.location, :variable)
        end
      end

      def visit_var_ref(node)
        case node.value
        when SyntaxTree::Ident
          add_token(node.value.location, :variable)
        end
      end

      def visit_a_ref_field(node)
        add_token(node.collection.value.location, :variable)
      end

      def visit_call(node)
        visit(node.receiver)
        add_token(node.message.location, :method)
        visit(node.arguments)
      end

      def visit_command(node)
        add_token(node.message.location, :method)
        visit(node.arguments)
      end

      def visit_command_call(node)
        visit(node.receiver)
        add_token(node.message.location, :method)
        visit(node.arguments)
      end

      def visit_fcall(node)
        add_token(node.value.location, :method)
        visit(node.arguments)
      end

      def visit_vcall(node)
        add_token(node.value.location, :method)
      end

      def add_token(location, type, modifiers = [])
        length = location.end_char - location.start_char
        modifiers_indices = modifiers.filter_map { |modifier| TOKEN_MODIFIERS[modifier] }
        @tokens.push(SemanticToken.new(location, length, TOKEN_TYPES.index(type), modifiers_indices))
      end
    end
  end
end
