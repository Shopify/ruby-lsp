# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Store
    class NonExistingDocumentError < StandardError; end

    #: Hash[Symbol, RequestConfig]
    attr_accessor :features_configuration

    #: String
    attr_accessor :client_name

    #: (GlobalState global_state) -> void
    def initialize(global_state)
      @global_state = global_state
      @state = {} #: Hash[String, Document[untyped]]
      @features_configuration = {
        inlayHint: RequestConfig.new({
          enableAll: false,
          implicitRescue: false,
          implicitHashValue: false,
        }),
      } #: Hash[Symbol, RequestConfig]
      @client_name = "Unknown" #: String
    end

    #: (URI::Generic uri) -> Document[untyped]
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
      @state[uri.to_s] #: as !nil
    rescue Errno::ENOENT
      raise NonExistingDocumentError, uri.to_s
    end

    #: (uri: URI::Generic, source: String, version: Integer, language_id: Document::LanguageId) -> Document[untyped]
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

    #: (uri: URI::Generic, edits: Array[Hash[Symbol, untyped]], version: Integer) -> void
    def push_edits(uri:, edits:, version:)
      @state[uri.to_s] #: as !nil
        .push_edits(edits, version: version)
    end

    #: -> void
    def clear
      @state.clear
    end

    #: -> bool
    def empty?
      @state.empty?
    end

    #: (URI::Generic uri) -> void
    def delete(uri)
      @state.delete(uri.to_s)
    end

    #: (URI::Generic uri) -> bool
    def key?(uri)
      @state.key?(uri.to_s)
    end

    #: { (String uri, Document[untyped] document) -> void } -> void
    def each(&block)
      @state.each do |uri, document|
        block.call(uri, document)
      end
    end

    #: [T] (URI::Generic uri, String request_name) { (Document[untyped] document) -> T } -> T
    def cache_fetch(uri, request_name, &block)
      get(uri).cache_fetch(request_name, &block)
    end
  end
end
