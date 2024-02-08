# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class Hover < ResponseBuilder
      ResponseType = type_member { { fixed: String } }

      extend T::Sig
      extend T::Generic

      sig { void }
      def initialize
        super

        @response = T.let(
          {
            title: +"",
            signature: +"",
            links: +"",
            documentation: +"",
          },
          T::Hash[Symbol, String],
        )
      end

      sig { params(content: String, category: Symbol).void }
      def push(content, category)
        hover_content = @response[category]
        if hover_content
          hover_content << content + "\n"
        end
      end

      sig { returns(T::Boolean) }
      def empty?
        @response.all? { |_key, value| value.empty? }
      end

      sig { override.returns(ResponseType) }
      def response
        result = T.must(@response[:title])
        result << @response[:signature] if @response[:signature]
        result << "\n" << @response[:links] if @response[:links]
        result << "\n" << @response[:documentation] if @response[:documentation]

        result.strip
      end
    end
  end
end
