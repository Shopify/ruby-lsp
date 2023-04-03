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
          add_code_lens(node, [@path, class_name, BASE_COMMAND + " -Itest " + @path])
        end
      end

      private

      sig { params(node: SyntaxTree::Node, args: T::Array[String]).void }
      def add_code_lens(node, args)
        @results << Interface::CodeLens.new(
          range: range_from_syntax_tree_node(node),
          command: Interface::Command.new(title: "Run", command: "rubyLsp.runTest", arguments: args),
          data: { type: "test" },
        )
      end
    end
  end
end
