# typed: strict
# frozen_string_literal: true

require "singleton"

module RubyLsp
  module Requests
    module Support
      # :nodoc:
      class SyntaxTreeFormattingRunner
        extend T::Sig
        include Singleton

        sig { params(_uri: String, document: Document).returns(T.nilable(String)) }
        def run(_uri, document)
          SyntaxTree.format(document.source)
        end
      end
    end
  end
end
