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
      BASE_COMMAND = T.let(File.exist?("Gemfile.lock") ? "bundle exec ruby" : "ruby", String)

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
          add_code_lens(node, path: @path, name: class_name, command: BASE_COMMAND + " -Itest " + @path)
        end
        visit(node.bodystmt)
      end

      sig { override.params(node: SyntaxTree::DefNode).void }
      def visit_def(node)
        if @modifier == "public"
          method_name = node.name.value
          if method_name.start_with?("test")
            add_code_lens(
              node,
              path: @path + ":" + node.location.start_line.to_s,
              name: method_name,
              command: BASE_COMMAND + " -Itest " + @path + " --name " + method_name,
            )
          end
        end
      end

      sig { override.params(node: SyntaxTree::Command).void }
      def visit_command(node)
        if node.message.value == "public"
          modifier = @modifier
          @modifier = "public"
          visit(node.arguments)
          @modifier = modifier
        end
      end

      sig { override.params(node: SyntaxTree::VCall).void }
      def visit_vcall(node)
        vcall_value = node.value.value

        if ["private", "protected", "public"].include?(vcall_value)
          @modifier = vcall_value
        end
      end

      private

      sig { params(node: SyntaxTree::Node, path: String, name: String, command: String).void }
      def add_code_lens(node, path:, name:, command:)
        @results << Interface::CodeLens.new(
          range: range_from_syntax_tree_node(node),
          command: Interface::Command.new(title: "Run", command: "rubyLsp.runTest", arguments: [path, name, command]),
          data: { type: "test" },
        )
      end

      sig { returns(String) }
      def test_command
        if ENV["BUNDLE_GEMFILE"]
          "bundle exec ruby -Itest "
        else
          "ruby -Itest "
        end
      end
    end
  end
end
