# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class Hover < ResponseBuilder
      extend T::Generic

      ResponseType = type_member { { fixed: String } }

      #: -> void
      def initialize
        super

        @response = {
          title: +"",
          links: +"",
          documentation: +"",
        } #: Hash[Symbol, String]
      end

      #: (String content, category: Symbol) -> void
      def push(content, category:)
        hover_content = @response[category]
        if hover_content
          hover_content << content + "\n"
        end
      end

      #: -> bool
      def empty?
        @response.values.all?(&:empty?)
      end

      # @override
      #: -> ResponseType
      def response
        result = @response[:title] #: as !nil
        result << "\n" << @response[:links] if @response[:links]
        result << "\n" << @response[:documentation] if @response[:documentation]

        result.strip
      end
    end
  end
end
