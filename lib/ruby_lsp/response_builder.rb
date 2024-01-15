# typed: strict
# frozen_string_literal: true

module RubyLsp
  class OperationNotPermitted < StandardError; end

  class ResponseBuilder
    extend T::Sig
    extend T::Generic

    Elem = type_member { { upper: Object } }

    sig { void }
    def initialize
      @response = T.let([], T::Array[Elem])
    end

    sig { params(elem: Elem).void }
    def <<(elem)
      @response << elem
    end

    sig { returns(T.nilable(Elem)) }
    def pop
      @response.pop
    end

    sig { returns(T::Boolean) }
    def empty?
      @response.empty?
    end
  end

  class HoverResponseBuilder < ResponseBuilder
    extend T::Sig
    extend T::Generic

    Elem = type_member { { fixed: String } }

    sig { returns(String) }
    def build_concatenated_response
      @response.join("\n\n")
    end

    sig { override.returns(T.nilable(Elem)) }
    def pop
      raise OperationNotPermitted, "Cannot pop from a HoverResponseBuilder"
    end
  end
end
