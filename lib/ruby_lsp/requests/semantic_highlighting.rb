# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/semantic_highlighting"

module RubyLsp
  module Requests
    # ![Semantic highlighting demo](../../semantic_highlighting.gif)
    #
    # The [semantic
    # highlighting](https://microsoft.github.io/language-server-protocol/specification#textDocument_semanticTokens)
    # request informs the editor of the correct token types to provide consistent and accurate highlighting for themes.
    #
    # # Example
    #
    # ```ruby
    # def foo
    #   var = 1 # --> semantic highlighting: local variable
    #   some_invocation # --> semantic highlighting: method invocation
    #   var # --> semantic highlighting: local variable
    # end
    #
    # # Strategy
    #
    # To maximize editor performance, the Ruby LSP will return the minimum number of semantic tokens, since applying
    # them is an expensive operation for the client. This means that the server only returns tokens for ambiguous pieces
    # of syntax, such as method invocations with no receivers or parenthesis (which can be confused with local
    # variables).
    #
    # Offloading as much handling as possible to Text Mate grammars or equivalent will guarantee responsiveness in the
    # editor and allow for a much smoother experience.
    # ```
    class SemanticHighlighting < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(Interface::SemanticTokensRegistrationOptions) }
        def provider
          Interface::SemanticTokensRegistrationOptions.new(
            document_selector: [{ language: "ruby" }],
            legend: Interface::SemanticTokensLegend.new(
              token_types: ResponseBuilders::SemanticHighlighting::TOKEN_TYPES.keys,
              token_modifiers: ResponseBuilders::SemanticHighlighting::TOKEN_MODIFIERS.keys,
            ),
            range: true,
            full: { delta: true },
          )
        end

        # The compute_delta method receives the current semantic tokens and the previous semantic tokens and then tries
        # to compute the smallest possible semantic token edit that will turn previous into current
        sig do
          params(
            current_tokens: T::Array[Integer],
            previous_tokens: T::Array[Integer],
            result_id: String,
          ).returns(Interface::SemanticTokensDelta)
        end
        def compute_delta(current_tokens, previous_tokens, result_id)
          # Find the index of the first token that is different between the two sets of tokens
          first_different_position = current_tokens.zip(previous_tokens).find_index { |new, old| new != old }

          # When deleting a token from the end, the first_different_position will be nil, but since we're removing at
          # the end, then we have to initialize it to the length of the current tokens after the deletion
          if !first_different_position && current_tokens.length < previous_tokens.length
            first_different_position = current_tokens.length
          end

          unless first_different_position
            return Interface::SemanticTokensDelta.new(result_id: result_id, edits: [])
          end

          # Filter the tokens based on the first different position. This must happen at this stage, before we try to
          # find the next position from the end or else we risk confusing sets of token that may have different lengths,
          # but end with the exact same token
          old_tokens = T.must(previous_tokens[first_different_position...])
          new_tokens = T.must(current_tokens[first_different_position...])

          # Then search from the end to find the first token that doesn't match. Since the user is normally editing the
          # middle of the file, this will minimize the number of edits since the end of the token array has not changed
          first_different_token_from_end = new_tokens.reverse.zip(old_tokens.reverse).find_index do |new, old|
            new != old
          end || 0

          # Filter the old and new tokens to only the section that will be replaced/inserted/deleted
          old_tokens = T.must(old_tokens[...old_tokens.length - first_different_token_from_end])
          new_tokens = T.must(new_tokens[...new_tokens.length - first_different_token_from_end])

          # And we send back a single edit, replacing an entire section for the new tokens
          Interface::SemanticTokensDelta.new(
            result_id: result_id,
            edits: [{ start: first_different_position, deleteCount: old_tokens.length, data: new_tokens }],
          )
        end

        sig { returns(Integer) }
        def next_result_id
          @mutex.synchronize do
            @result_id += 1
          end
        end
      end

      @result_id = T.let(0, Integer)
      @mutex = T.let(Mutex.new, Mutex)

      sig do
        params(
          global_state: GlobalState,
          dispatcher: Prism::Dispatcher,
          document: T.any(RubyDocument, ERBDocument),
          previous_result_id: T.nilable(String),
          range: T.nilable(T::Range[Integer]),
        ).void
      end
      def initialize(global_state, dispatcher, document, previous_result_id, range: nil)
        super()

        @document = document
        @previous_result_id = previous_result_id
        @range = range
        @result_id = T.let(SemanticHighlighting.next_result_id.to_s, String)
        @response_builder = T.let(
          ResponseBuilders::SemanticHighlighting.new(global_state.encoding),
          ResponseBuilders::SemanticHighlighting,
        )
        Listeners::SemanticHighlighting.new(dispatcher, @response_builder)

        Addon.addons.each do |addon|
          addon.create_semantic_highlighting_listener(@response_builder, dispatcher)
        end
      end

      sig { override.returns(T.any(Interface::SemanticTokens, Interface::SemanticTokensDelta)) }
      def perform
        previous_tokens = @document.semantic_tokens
        tokens = @response_builder.response
        encoded_tokens = ResponseBuilders::SemanticHighlighting::SemanticTokenEncoder.new.encode(tokens)
        full_response = Interface::SemanticTokens.new(result_id: @result_id, data: encoded_tokens)
        @document.semantic_tokens = full_response

        if @range
          tokens_within_range = tokens.select { |token| @range.cover?(token.start_line - 1) }

          return Interface::SemanticTokens.new(
            result_id: @result_id,
            data: ResponseBuilders::SemanticHighlighting::SemanticTokenEncoder.new.encode(tokens_within_range),
          )
        end

        # Semantic tokens full delta
        if @previous_result_id
          response = if previous_tokens.is_a?(Interface::SemanticTokens) &&
              previous_tokens.result_id == @previous_result_id
            Requests::SemanticHighlighting.compute_delta(encoded_tokens, previous_tokens.data, @result_id)
          else
            full_response
          end

          return response
        end

        # Semantic tokens full
        full_response
      end
    end
  end
end
