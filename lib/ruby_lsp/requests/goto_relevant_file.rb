# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # Goto Relevant File is a custom [LSP
    # request](https://microsoft.github.io/language-server-protocol/specification#requestMessage)
    # that navigates to the relevant file for the current document.
    # Currently, it supports source code file <> test file navigation.
    class GotoRelevantFile < Request
      extend T::Sig

      TYPE_TEST = "test"
      TYPE_SOURCE = "source"

      sig { params(path: String, type: String).void }
      def initialize(path, type)
        super()
        @path = path
        @type = type
      end

      sig { override.returns(T::Array[String]) }
      def perform
        case @type
        when TYPE_TEST
          find_test_locations(@path)
        when TYPE_SOURCE
          find_source_locations(@path)
        else
          []
        end
      end

      private

      sig { params(path: String).returns(T::Array[String]) }
      def find_test_locations(path)
        filename_pattern = test_filename_pattern(path)
        recursively_find_paths(File.join(File.dirname(path), filename_pattern))
      end

      sig { params(path: String).returns(T::Array[String]) }
      def find_source_locations(path)
        filename_pattern = source_filename_pattern(path)
        recursively_find_paths(File.join(File.dirname(path), filename_pattern))
      end

      sig { params(path: String).returns(T::Array[String]) }
      def recursively_find_paths(path)
        matches = Dir.glob(File.join("**", path))

        if matches.any?
          matches.map { File.join(Bundler.root.to_s, _1) }
        elsif File.dirname(path) == "."
          []
        else
          new_path = exclude_leading_directory(path)
          recursively_find_paths(new_path)
        end
      end

      sig { params(path: String).returns(String) }
      def exclude_leading_directory(path)
        parts = path.split(File::SEPARATOR)
        if parts.one?
          T.must(parts.first)
        else
          T.must(parts[1..]).join(File::SEPARATOR)
        end
      end

      sig { params(path: String).returns(String) }
      def test_filename_pattern(path)
        basename = File.basename(path, File.extname(path))
        test_basename =
          "#{basename}{.test,_test,_spec,-spec,_expectations_test,_integration_test}"

        "#{test_basename}#{File.extname(path)}"
      end

      sig { params(path: String).returns(String) }
      def source_filename_pattern(path)
        basename = File.basename(path, File.extname(path))
        source_basename =
          basename.gsub(/(.test|_test|_spec|-spec|expections_test|integration_test)$/, "")

        "#{source_basename}#{File.extname(path)}"
      end
    end
  end
end
