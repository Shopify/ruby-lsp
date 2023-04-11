# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Code lens demo](../../misc/code_lens.gif)
    #
    # This feature is currently experimental. Clients will need to pass `experimentalFeaturesEnabled`
    # in the initialization options to enable it.
    #
    # The
    # [code lens](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeLens)
    # request informs the editor of runnable commands such as tests
    #
    # # Example
    #
    # ```ruby
    # # Run
    # class Test < Minitest::Test
    # end
    # ```

    class CodeLens < BaseRequest
      BASE_COMMAND = T.let((File.exist?("Gemfile.lock") ? "bundle exec ruby" : "ruby") + " -Itest ", String)
      ACCESS_MODIFIERS = T.let(["public", "private", "protected"], T::Array[String])

      sig do
        params(
          document: Document,
        ).void
      end
      def initialize(document)
        super(document)
        @results = T.let([], T::Array[Interface::CodeLens])
        @path = T.let(document.uri.delete_prefix("file://"), String)
        @modifier = T.let("public", String)
      end

      sig { override.returns(T.all(T::Array[Interface::CodeLens], Object)) }
      def run
        visit(@document.tree) if @document.parsed?
        @results
      end

      sig { override.params(node: SyntaxTree::ClassDeclaration).void }
      def visit_class(node)
        class_name = node.constant.constant.value
        if class_name.end_with?("Test")
          add_code_lens(node, name: class_name, command: BASE_COMMAND + @path)
        end
        visit(node.bodystmt)
      end

      sig { override.params(node: SyntaxTree::DefNode).void }
      def visit_def(node)
        if @modifier == "public"
          method_name = node.name.value
          if method_name.start_with?("test_")
            add_code_lens(
              node,
              name: method_name,
              command: BASE_COMMAND + @path + " --name " + method_name,
            )
          end
        end
      end

      sig { override.params(node: SyntaxTree::Command).void }
      def visit_command(node)
        if node.message.value == "public"
          with_visiblity("public", node)
        end
      end

      sig { override.params(node: SyntaxTree::CallNode).void }
      def visit_call(node)
        ident = node.message if node.message.is_a?(SyntaxTree::Ident)

        if ident
          if T.cast(ident, SyntaxTree::Ident).value == "public"
            with_visiblity("public", node)
          end
        end
      end

      sig { override.params(node: SyntaxTree::VCall).void }
      def visit_vcall(node)
        vcall_value = node.value.value

        if ACCESS_MODIFIERS.include?(vcall_value)
          @modifier = vcall_value
        end
      end

      private

      sig do
        params(
          visibility: String,
          node: T.any(SyntaxTree::CallNode, SyntaxTree::Command),
        ).void
      end
      def with_visiblity(visibility, node)
        current_visibility = @modifier
        @modifier = visibility
        visit(node.arguments)
      ensure
        @modifier = T.must(current_visibility)
      end

      sig { params(node: SyntaxTree::Node, name: String, command: String).void }
      def add_code_lens(node, name:, command:)
        @results << Interface::CodeLens.new(
          range: range_from_syntax_tree_node(node),
          command: Interface::Command.new(
            title: "Run",
            command: "rubyLsp.runTest",
            arguments: [
              @path,
              name,
              command,
              {
                start_line: node.location.start_line - 1,
                start_column: node.location.start_column,
                end_line: node.location.end_line - 1,
                end_column: node.location.end_column,
              },
            ],
          ),
          data: { type: "test" },
        )
      end
    end
  end
end
