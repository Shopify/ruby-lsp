# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # @abstract
    class Request
      class InvalidFormatter < StandardError; end

      # @abstract
      #: -> untyped
      def perform
        raise AbstractMethodInvokedError
      end

      private

      # Signals to the client that the request should be delegated to the language server server for the host language
      # in ERB files
      #: (GlobalState global_state, Document[untyped] document, Integer char_position) -> void
      def delegate_request_if_needed!(global_state, document, char_position)
        if global_state.client_capabilities.supports_request_delegation &&
            document.is_a?(ERBDocument) &&
            document.inside_host_language?(char_position)
          raise DelegateRequestError
        end
      end

      # Checks if a location covers a position
      #: (Prism::Location location, untyped position, (RubyDocument | ERBDocument) document) -> bool
      def cover?(location, position, document)
        start_column, end_column = location_columns(location, document.encoding, document.code_units_cache)

        start_covered =
          location.start_line - 1 < position[:line] ||
          (
            location.start_line - 1 == position[:line] &&
              start_column <= position[:character]
          )
        end_covered =
          location.end_line - 1 > position[:line] ||
          (
            location.end_line - 1 == position[:line] &&
              end_column >= position[:character]
          )
        start_covered && end_covered
      end

      # Based on a constant node target, a constant path node parent and a position, this method will find the exact
      # portion of the constant path that matches the requested position, for higher precision in hover and
      # definition. For example:
      #
      # ```ruby
      # Foo::Bar::Baz
      #  #        ^ Going to definition here should go to Foo::Bar::Baz
      #  #   ^ Going to definition here should go to Foo::Bar
      # #^ Going to definition here should go to Foo
      # ```
      #: (Prism::Node target, Prism::Node parent, Hash[Symbol, Integer] position, (RubyDocument | ERBDocument) document) -> Prism::Node
      def determine_target(target, parent, position, document)
        return target unless parent.is_a?(Prism::ConstantPathNode)

        target = parent #: Prism::Node
        parent = target #: as Prism::ConstantPathNode
          .parent #: Prism::Node?

        while parent && cover?(parent.location, position, document)
          target = parent
          parent = target.is_a?(Prism::ConstantPathNode) ? target.parent : nil
        end

        target
      end

      # Checks if a given location covers the position requested
      #: (Prism::Location? location, Hash[Symbol, untyped] position, (RubyDocument | ERBDocument) document) -> bool
      def covers_position?(location, position, document)
        return false unless location

        start_line = location.start_line - 1
        end_line = location.end_line - 1
        line = position[:line]
        character = position[:character]
        start_column, end_column = location_columns(location, document.encoding, document.code_units_cache)

        (start_line < line || (start_line == line && start_column <= character)) &&
          (end_line > line || (end_line == line && end_column >= character))
      end

      # Returns the start and end columns of a Prism location in the code units of the position encoding negotiated
      # with the client. Prism's `start_column` and `end_column` count bytes, which match the code units only in UTF-8
      #: (Prism::Location location, Encoding encoding, (^(Integer arg0) -> Integer | Prism::CodeUnitsCache) code_units_cache) -> [Integer, Integer]
      def location_columns(location, encoding, code_units_cache)
        # For UTF-8, the byte columns are already correct. The code units cache can't be used for UTF-8, because Prism
        # versions before 2.0 count characters instead of bytes for it (ruby/prism#4098)
        return [location.start_column, location.end_column] if encoding == Encoding::UTF_8

        [
          location.cached_start_code_units_column(code_units_cache),
          location.cached_end_code_units_column(code_units_cache),
        ]
      end

      # Builds an LSP range for a Prism location in the position encoding negotiated with the client
      #: (Prism::Location location, Encoding encoding, (^(Integer arg0) -> Integer | Prism::CodeUnitsCache) code_units_cache) -> Interface::Range
      def range_in_encoding(location, encoding, code_units_cache)
        start_column, end_column = location_columns(location, encoding, code_units_cache)

        Interface::Range.new(
          start: Interface::Position.new(line: location.start_line - 1, character: start_column),
          end: Interface::Position.new(line: location.end_line - 1, character: end_column),
        )
      end
    end
  end
end
