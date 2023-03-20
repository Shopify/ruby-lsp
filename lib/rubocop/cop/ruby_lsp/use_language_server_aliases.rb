# typed: strict
# frozen_string_literal: true

require "rubocop"
require "sorbet-runtime"

module RuboCop
  module Cop
    module RubyLsp
      # Prefer using `Interface`, `Transport` and `Constant` aliases
      # within the `RubyLsp` module, without having to prefix with
      # `LanguageServer::Protocol`
      #
      # @example
      #   # bad
      #   module RubyLsp
      #     class FoldingRanges
      #       sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::FoldingRange], Object)) }
      #       def run; end
      #     end
      #
      #   # good
      #   module RubyLsp
      #     class FoldingRanges
      #       sig { override.returns(T.all(T::Array[Interface::FoldingRange], Object)) }
      #       def run; end
      #     end
      #   end
      class UseLanguageServerAliases < RuboCop::Cop::Base
        extend RuboCop::Cop::AutoCorrector

        ALIASED_CONSTANTS = T.let([:Interface, :Transport, :Constant].freeze, T::Array[Symbol])

        MSG = "Use constant alias `%{constant}`."

        def_node_search :ruby_lsp_modules, <<~PATTERN
          (module (const nil? :RubyLsp) ...)
        PATTERN

        def_node_search :lsp_constant_usages, <<~PATTERN
          (const (const (const nil? :LanguageServer) :Protocol) {:Interface | :Transport | :Constant})
        PATTERN

        def on_new_investigation
          return if processed_source.blank?

          ruby_lsp_modules(processed_source.ast).each do |ruby_lsp_mod|
            lsp_constant_usages(ruby_lsp_mod).each do |node|
              lsp_const = node.children.last

              next unless ALIASED_CONSTANTS.include?(lsp_const)

              add_offense(node, message: format(MSG, constant: lsp_const)) do |corrector|
                corrector.replace(node, lsp_const)
              end
            end
          end
        end
      end
    end
  end
end
