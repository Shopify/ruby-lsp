# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/document_link"

module RubyLsp
  module Requests
    # ![Document link demo](../../document_link.gif)
    #
    # The [document link](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentLink)
    # makes `# source://PATH_TO_FILE#line` comments in a Ruby/RBI file clickable if the file exists.
    # When the user clicks the link, it'll open that location.
    #
    # # Example
    #
    # ```ruby
    # # source://syntax_tree/3.2.1/lib/syntax_tree.rb#51 <- it will be clickable and will take the user to that location
    # def format(source, maxwidth = T.unsafe(nil))
    # end
    # ```
    class DocumentLink < Request
      extend T::Sig
      extend T::Generic

      class << self
        extend T::Sig

        sig { returns(Interface::DocumentLinkOptions) }
        def provider
          Interface::DocumentLinkOptions.new(resolve_provider: false)
        end
      end

      ResponseType = type_member { { fixed: T::Array[Interface::DocumentLink] } }

      sig do
        params(
          uri: URI::Generic,
          comments: T::Array[Prism::Comment],
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(uri, comments, dispatcher)
        super()
        @listener = T.let(Listeners::DocumentLink.new(uri, comments, dispatcher), Listener[ResponseType])
      end

      sig { override.returns(ResponseType) }
      def response
        @listener.response
      end
    end
  end
end
