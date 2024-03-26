# typed: strict
# frozen_string_literal: true

# NOTE: This module is intended to be used by addons for writing their own tests, so keep that in mind if changing.

module RubyLsp
  module TestHelper
    extend T::Sig

    sig do
      type_parameters(:T)
        .params(
          source: T.nilable(String),
          uri: URI::Generic,
          block: T.proc.params(server: RubyLsp::Server, uri: URI::Generic).returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
    end
    def with_server(source = nil, uri = Kernel.URI("file:///fake.rb"), &block)
      server = RubyLsp::Server.new(test_mode: true)
      server.process_message(method: "initialized")

      if source
        server.process_message({
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
            },
          },
        })
      end

      index = server.index
      index.index_single(RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)), source)
      block.call(server, uri)
    ensure
      T.must(server).run_shutdown
    end
  end
end
