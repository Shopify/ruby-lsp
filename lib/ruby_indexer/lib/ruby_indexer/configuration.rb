# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Configuration
    extend T::Sig

    sig { returns(T::Array[String]) }
    attr_accessor :files_to_index

    sig { void }
    def initialize
      files_to_index = $LOAD_PATH.flat_map { |p| Dir.glob("#{p}/**/*.rb", base: p) }
      files_to_index.concat(Dir.glob("#{Dir.pwd}/**/*.rb"))
      files_to_index.reject! { |path| path.end_with?("_test.rb") }

      @files_to_index = T.let(files_to_index, T::Array[String])
    end
  end
end
