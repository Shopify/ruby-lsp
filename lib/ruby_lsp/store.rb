# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Store
    extend T::Sig

    sig { returns(String) }
    attr_accessor :encoding

    sig { returns(String) }
    attr_accessor :formatter

    sig { returns(T::Boolean) }
    attr_accessor :supports_progress

    sig { returns(T::Boolean) }
    attr_accessor :experimental_features

    sig { returns(URI::Generic) }
    attr_accessor :workspace_uri

    sig { void }
    def initialize
      @state = T.let({}, T::Hash[String, Document])
      @encoding = T.let(Constant::PositionEncodingKind::UTF8, String)
      @formatter = T.let("auto", String)
      @supports_progress = T.let(true, T::Boolean)
      @experimental_features = T.let(false, T::Boolean)
      @workspace_uri = T.let(URI::Generic.from_path(path: Dir.pwd), URI::Generic)
    end

    sig { params(uri: URI::Generic).returns(Document) }
    def get(uri)
      document = @state[uri.to_s]
      return document unless document.nil?

      path = T.must(uri.to_standardized_path)
      set(uri: uri, source: File.binread(path), version: 0)
      T.must(@state[uri.to_s])
    end

    sig { params(uri: URI::Generic, source: String, version: Integer).void }
    def set(uri:, source:, version:)
      document = RubyDocument.new(source: source, version: version, uri: uri, encoding: @encoding)
      @state[uri.to_s] = document
    end

    sig { params(uri: URI::Generic, edits: T::Array[Document::EditShape], version: Integer).void }
    def push_edits(uri:, edits:, version:)
      T.must(@state[uri.to_s]).push_edits(edits, version: version)
    end

    sig { void }
    def clear
      @state.clear
    end

    sig { returns(T::Boolean) }
    def empty?
      @state.empty?
    end

    sig { params(uri: URI::Generic).void }
    def delete(uri)
      @state.delete(uri.to_s)
    end

    sig do
      type_parameters(:T)
        .params(
          uri: URI::Generic,
          request_name: String,
          block: T.proc.params(document: Document).returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
    end
    def cache_fetch(uri, request_name, &block)
      get(uri).cache_fetch(request_name, &block)
    end
  end
end
