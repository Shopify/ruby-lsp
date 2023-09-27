# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Reference
    extend T::Sig

    sig { returns(YARP::Location) }
    attr_reader :location

    sig { returns(String) }
    attr_reader :file_path

    sig { params(location: YARP::Location, file_path: String).void }
    def initialize(location, file_path)
      @location = location
      @file_path = file_path
    end
  end
end
