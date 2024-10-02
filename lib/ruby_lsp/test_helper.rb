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
          stub_no_typechecker: T::Boolean,
          load_addons: T::Boolean,
          block: T.proc.params(server: RubyLsp::Server, uri: URI::Generic).returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
    end
    def with_server(source = nil, uri = Kernel.URI("file:///fake.rb"), stub_no_typechecker: false, load_addons: true,
      &block)
      server = RubyLsp::Server.new(test_mode: true)
      server.global_state.apply_options({ initializationOptions: { experimentalFeaturesEnabled: true } })
      server.global_state.instance_variable_set(:@has_type_checker, false) if stub_no_typechecker
      language_id = uri.to_s.end_with?(".erb") ? "erb" : "ruby"

      if source
        server.process_message({
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1,
              languageId: language_id,
            },
          },
        })
      end

      server.global_state.index.index_single(
        RubyIndexer::IndexablePath.new(nil, T.must(uri.to_standardized_path)),
        source,
      )
      server.load_addons(include_project_addons: false) if load_addons
      block.call(server, uri)
    ensure
      if load_addons
        RubyLsp::Addon.addons.each(&:deactivate)
        RubyLsp::Addon.addons.clear
      end
      T.must(server).run_shutdown
    end
  end
end
