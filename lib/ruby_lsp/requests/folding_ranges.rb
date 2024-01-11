# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/folding_ranges"

module RubyLsp
  module Requests
    # ![Folding ranges demo](../../folding_ranges.gif)
    #
    # The [folding ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_foldingRange)
    # request informs the editor of the ranges where and how code can be folded.
    #
    # # Example
    #
    # ```ruby
    # def say_hello # <-- folding range start
    #   puts "Hello"
    # end # <-- folding range end
    # ```
    class FoldingRanges < Request
      extend T::Sig
      extend T::Generic

      class << self
        extend T::Sig

        sig { returns(Interface::FoldingRangeClientCapabilities) }
        def provider
          Interface::FoldingRangeClientCapabilities.new(line_folding_only: true)
        end
      end

      ResponseType = type_member { { fixed: T::Array[Interface::FoldingRange] } }

      sig { params(comments: T::Array[Prism::Comment], dispatcher: Prism::Dispatcher).void }
      def initialize(comments, dispatcher)
        super()
        @listener = T.let(Listeners::FoldingRanges.new(comments, dispatcher), Listener[ResponseType])
      end

      sig { override.returns(ResponseType) }
      def perform
        @listener.response
      end
    end
  end
end
