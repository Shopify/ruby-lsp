# frozen_string_literal: true

module RubyLsp
  class Visitor
    def visit_all(nodes)
      nodes.each do |node|
        visit(node)
      end
    end

    def visit(node)
      return unless node

      send("visit_#{self.class.class_to_visit_method(node.class.name)}", node)
    end

    def self.class_to_visit_method(string)
      word = string.split("::").last
      word.gsub!(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
      word.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
      word.tr!("-", "_")
      word.downcase!
      word
    end

    SyntaxTree.constants.each do |constant|
      class_eval(<<~EOS, __FILE__, __LINE__ + 1)
        def visit_#{class_to_visit_method(constant.to_s)}(node)
          visit_all(node.child_nodes)
        end
      EOS
    end
  end
end
