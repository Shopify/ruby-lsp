# typed: strict
# frozen_string_literal: true

require "rubocop"
require "sorbet-runtime"
require "strscan"

module RuboCop
  module Cop
    module RubyLsp
      # Detects and flags the use of YARD method annotations.
      # YARD annotations should be converted to RBS comment syntax
      # for better integration with Sorbet and static analysis.
      #
      # @example
      #   # bad
      #   # @param name [String] the name
      #   # @return [String] the greeting
      #   def greet(name)
      #     "Hello #{name}"
      #   end
      #
      #   # good
      #   # name: String -> String
      #   def greet(name)
      #     "Hello #{name}"
      #   end
      class NoYardAnnotations < RuboCop::Cop::Base
        extend T::Sig

        MSG = "Avoid using YARD method annotations. Use RBS comment syntax instead."
        private_constant :MSG

        ANY_WHITESPACE = /\s*/ #: Regexp

        FORBIDDEN_YARD_TAGS = [
          "option",
          "overload",
          "param",
          "return",
          "yield",
          "yieldparam",
          "yieldreturn",
        ].freeze #: Array[String]
        private_constant :FORBIDDEN_YARD_TAGS

        sig { void }
        def on_new_investigation
          return if processed_source.blank?

          yard_tag_blocks.each do |block|
            next unless (tag_block = block.first)
            next unless contains_forbidden_yard_tag?(tag_block.text)

            add_offense(tag_block.source_range, message: MSG)
          end
        end

        private

        sig { returns(T::Enumerator[T::Array[Parser::Source::Comment]]) }
        def yard_tag_blocks
          Enumerator.new do |yielder|
            comments = processed_source.comments
            next if comments.empty?

            current_tag_chunk = []
            previous_line = -1 #: untyped
            tag_indent_level = 0 #: untyped

            comments.each do |comment|
              scanner = StringScanner.new(comment.text)
              next unless scanner.skip("#")

              indent_level = scanner.skip(ANY_WHITESPACE)

              if !current_tag_chunk.empty? &&
                  comment.location.line == previous_line + 1 &&
                  indent_level >= tag_indent_level + 2
                current_tag_chunk << comment
              else
                yielder << current_tag_chunk unless current_tag_chunk.empty?
                current_tag_chunk = []

                if scanner.skip("@")
                  current_tag_chunk << comment
                  tag_indent_level = indent_level
                end
              end

              previous_line = comment.location.line
            end

            yielder << current_tag_chunk unless current_tag_chunk.empty?
          end
        end

        sig { params(comment_text: String).returns(T::Boolean) }
        def contains_forbidden_yard_tag?(comment_text)
          scanner = StringScanner.new(comment_text)
          return false unless scanner.skip("#")

          scanner.skip(ANY_WHITESPACE)

          return false unless scanner.skip("@")

          FORBIDDEN_YARD_TAGS.any? do |tag_name|
            if scanner.skip(tag_name)
              scanner.unscan unless (match = scanner.eos? || scanner.peek(1).lstrip.empty?)
              match
            else
              false
            end
          end
        end
      end
    end
  end
end
