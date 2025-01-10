# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Store
    extend T::Sig

    class NonExistingDocumentError < StandardError; end

    sig { returns(T::Hash[Symbol, RequestConfig]) }
    attr_accessor :features_configuration

    sig { returns(String) }
    attr_accessor :client_name

    sig { params(global_state: GlobalState).void }
    def initialize(global_state)
      @global_state = global_state
      @state = T.let({}, T::Hash[String, Document[T.untyped]])
      @features_configuration = T.let(
        {
          inlayHint: RequestConfig.new({
            enableAll: false,
            implicitRescue: false,
            implicitHashValue: false,
          }),
        },
        T::Hash[Symbol, RequestConfig],
      )
      @client_name = T.let("Unknown", String)
    end

    sig { params(uri: URI::Generic).returns(Document[T.untyped]) }
    def get(uri)
      document = @state[uri.to_s]
      return document unless document.nil?

      # For unsaved files (`untitled:Untitled-1` uris), there's no path to read from. If we don't have the untitled file
      # already present in the store, then we have to raise non existing document error
      path = uri.to_standardized_path
      raise NonExistingDocumentError, uri.to_s unless path

      ext = File.extname(path)
      language_id = case ext
      when ".erb", ".rhtml"
        Document::LanguageId::ERB
      when ".rbs"
        Document::LanguageId::RBS
      else
        Document::LanguageId::Ruby
      end

      set(uri: uri, source: File.binread(path), version: 0, language_id: language_id)
      T.must(@state[uri.to_s])
    rescue Errno::ENOENT
      raise NonExistingDocumentError, uri.to_s
    end

    sig do
      params(
        uri: URI::Generic,
        source: String,
        version: Integer,
        language_id: Document::LanguageId,
      ).returns(Document[T.untyped])
    end
    def set(uri:, source:, version:, language_id:)
      @state[uri.to_s] = case language_id
      when Document::LanguageId::ERB
        ERBDocument.new(source: source, version: version, uri: uri, global_state: @global_state)
      when Document::LanguageId::RBS
        RBSDocument.new(source: source, version: version, uri: uri, global_state: @global_state)
      else
        RubyDocument.new(source: source, version: version, uri: uri, global_state: @global_state)
      end
    end

    sig { params(uri: URI::Generic, edits: T::Array[T::Hash[Symbol, T.untyped]], version: Integer).void }
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

    sig { params(uri: URI::Generic).returns(T::Boolean) }
    def key?(uri)
      @state.key?(uri.to_s)
    end

    sig { params(block: T.proc.params(uri: String, document: Document[T.untyped]).void).void }
    def each(&block)
      @state.each do |uri, document|
        block.call(uri, document)
      end
    end

    sig do
      type_parameters(:T)
        .params(
          uri: URI::Generic,
          request_name: String,
          block: T.proc.params(document: Document[T.untyped]).returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
    end
    def cache_fetch(uri, request_name, &block)
      get(uri).cache_fetch(request_name, &block)
    end
  end
end
