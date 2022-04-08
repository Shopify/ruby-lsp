# frozen_string_literal: true

require "syntax_tree"
require "ruby_lsp/visitor"

module RubyLsp
  class DocumentationVisitor < Visitor
    attr_reader :documentation, :request_name, :content

    def initialize
      @documentation = []
      @above_class = false
      super
    end

    def documentation_skipped?
      @documentation.any? { |doc| doc.strip == ":nodoc:" }
    end

    private

    def visit_module_declaration(node)
      @above_class = true if node.constant.constant.value == "Requests"
      super
    end

    def visit_class_declaration(node)
      return unless @above_class

      @request_name = node.constant.constant.value
      @content = @documentation.join("\n")
    end

    def visit_comment(node)
      return unless @above_class

      @documentation << node.value.gsub(/^# ?/, "")
      super
    end
  end
end
