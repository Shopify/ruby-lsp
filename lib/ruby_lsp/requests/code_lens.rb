# typed: strict
# frozen_string_literal: true

require "shellwords"

require "ruby_lsp/listeners/code_lens"

module RubyLsp
  module Requests
    # ![Code lens demo](../../code_lens.gif)
    #
    # The
    # [code lens](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeLens)
    # request informs the editor of runnable commands such as tests
    #
    # # Configuration
    #
    # To disable gem code lenses, set `rubyLsp.featuresConfiguration.codeLens.gemfileLinks` to `false`.
    #
    # # Example
    #
    # ```ruby
    # # Run
    # class Test < Minitest::Test
    # end
    # ```
    class CodeLens < Request
      extend T::Sig
      extend T::Generic

      class << self
        extend T::Sig

        sig { returns(Interface::CodeLensOptions) }
        def provider
          Interface::CodeLensOptions.new(resolve_provider: false)
        end
      end

      ResponseType = type_member { { fixed: T::Array[Interface::CodeLens] } }

      sig do
        params(
          uri: URI::Generic,
          lenses_configuration: RequestConfig,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(uri, lenses_configuration, dispatcher)
        super()
        @listeners = T.let(
          [Listeners::CodeLens.new(uri, lenses_configuration, dispatcher)],
          T::Array[Listener[ResponseType]],
        )

        Addon.addons.each do |addon|
          addon_listener = addon.create_code_lens_listener(uri, dispatcher)
          @listeners << addon_listener if addon_listener
        end
      end

      sig { override.returns(ResponseType) }
      def response
        @listeners.flat_map(&:response)
      end
    end
  end
end
