# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # GoTo Relevant File is a custom [LSP
    # request](https://microsoft.github.io/language-server-protocol/specification#requestMessage)
    # that navigates to the relevant file for the current document.
    # Currently, it supports source code file <> test file navigation.
    class GoToRelevantFileV2 < Request
      TEST_KEYWORDS = ["test", "spec", "integration_test"]

      TEST_PREFIX_PATTERN = /^(#{TEST_KEYWORDS.join("_|")}_)/
      TEST_SUFFIX_PATTERN = /(_#{TEST_KEYWORDS.join("|_")})$/
      TEST_PATTERN = /#{TEST_PREFIX_PATTERN}|#{TEST_SUFFIX_PATTERN}/

      TEST_PREFIX_GLOB = "#{TEST_KEYWORDS.join("_,")}_" #: String
      TEST_SUFFIX_GLOB = "_#{TEST_KEYWORDS.join(",_")}" #: String

      TEST_REGEX = /^(test_|spec_|integration_test_)|((_test|_spec|_integration_test)$)/

      #: (String path, String workspace_path, RubyIndexer::FileIndex file_index) -> void
      def initialize(path, workspace_path, file_index)
        super()

        @file_index = file_index
        @workspace_path = workspace_path
        @path = path.delete_prefix(workspace_path) #: String
      end

      # @override
      #: -> Array[String]
      def perform
        find_relevant_paths
      end

      private

      #: -> Array[String]
      def find_relevant_paths
        # Extract the base name from the current file (without the extension)
        input_basename = File.basename(@path, File.extname(@path))

        base_name = if input_basename.match?(TEST_PATTERN)
          # If it's a test file, remove the test prefix/suffix
          input_basename.gsub(TEST_PATTERN, "")
        else
          # If it's a source file, use its base name
          input_basename
        end

        # Use the FileIndex to find relevant files via the index
        candidate_paths = if input_basename.match?(TEST_REGEX)
          @file_index.search_subject(base_name)
        else
          @file_index.search_test(base_name)
        end

        return [] if candidate_paths.empty?

        # Filter out the current file from the candidates
        full_path = File.join(@workspace_path, @path)
        candidates = candidate_paths.reject do |path|
          path == full_path
        end

        # Filter to include only files with matching extensions
        extension = File.extname(@path)
        candidates = candidates.select do |path|
          File.extname(path) == extension
        end

        candidates = candidates.map { |path| File.join(@workspace_path, path) }

        return [] if candidates.empty?

        # Find the most similar paths using Jaccard similarity
        find_most_similar_with_jaccard(candidates)
      end

      # Using the Jaccard algorithm to determine the similarity between the
      # input path and the candidate relevant file paths.
      # Ref: https://en.wikipedia.org/wiki/Jaccard_index
      # The main idea of this algorithm is to take the size of interaction and divide
      # it by the size of union between two sets (in our case the elements in each set
      # would be the parts of the path separated by path divider.)
      #: (Array[String] candidates) -> Array[String]
      def find_most_similar_with_jaccard(candidates)
        dirs = get_dir_parts(@path)

        _, results = candidates
          .group_by do |other_path|
            # For consistency with the current path, convert absolute paths to relative if needed
            relative_path = if other_path.start_with?(@workspace_path)
              other_path.delete_prefix(@workspace_path)
            else
              other_path
            end

            other_dirs = get_dir_parts(relative_path)
            # Similarity score between the two directories
            (dirs & other_dirs).size.to_f / (dirs | other_dirs).size
          end
          .max_by(&:first)

        results || []
      end

      #: (String path) -> Set[String]
      def get_dir_parts(path)
        Set.new(File.dirname(path).split(File::SEPARATOR))
      end
    end
  end
end
