# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # GoTo Relevant File is a custom [LSP
    # request](https://microsoft.github.io/language-server-protocol/specification#requestMessage)
    # that navigates to the relevant file for the current document.
    # Currently, it supports source code file <> test file navigation.
    class GoToRelevantFile < Request
      extend T::Sig

      TEST_KEYWORDS = ["test", "spec", "integration_test"]

      TEST_PREFIX_PATTERN = /^(#{TEST_KEYWORDS.join("_|")}_)/
      TEST_SUFFIX_PATTERN = /(_#{TEST_KEYWORDS.join("|_")})$/
      TEST_PATTERN = /#{TEST_PREFIX_PATTERN}|#{TEST_SUFFIX_PATTERN}/

      TEST_PREFIX_GLOB = "#{TEST_KEYWORDS.join("_,")}_" #: String
      TEST_SUFFIX_GLOB = "_#{TEST_KEYWORDS.join(",_")}" #: String

      #: (String path, String workspace_path) -> void
      def initialize(path, workspace_path)
        super()

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
        candidate_paths = Dir.glob(File.join("**", relevant_filename_pattern))
        return [] if candidate_paths.empty?

        find_most_similar_with_jaccard(candidate_paths).map { File.join(@workspace_path, _1) }
      end

      #: -> String
      def relevant_filename_pattern
        input_basename = File.basename(@path, File.extname(@path))

        relevant_basename_pattern =
          if input_basename.match?(TEST_PATTERN)
            input_basename.gsub(TEST_PATTERN, "")
          else
            "{{#{TEST_PREFIX_GLOB}}#{input_basename},#{input_basename}{#{TEST_SUFFIX_GLOB}}}"
          end

        "#{relevant_basename_pattern}#{File.extname(@path)}"
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
            other_dirs = get_dir_parts(other_path)
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
