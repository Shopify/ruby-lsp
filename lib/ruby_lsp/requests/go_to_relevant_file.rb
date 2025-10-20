# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # GoTo Relevant File is a custom [LSP
    # request](https://microsoft.github.io/language-server-protocol/specification#requestMessage)
    # that navigates to the relevant file for the current document.
    # Currently, it supports source code file <> test file navigation.
    class GoToRelevantFile < Request
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
        patterns = relevant_filename_patterns

        candidate_paths = patterns.flat_map do |pattern|
          Dir.glob(File.join(search_root, "**", pattern))
        end

        return [] if candidate_paths.empty?

        find_most_similar_with_jaccard(candidate_paths).map { |path| File.expand_path(path, @workspace_path) }
      end

      # Determine the search roots based on the closest test directories.
      # This scopes the search to reduce the number of files that need to be checked.
      #: -> String
      def search_root
        current_path = File.join(".", @path)
        current_dir = File.dirname(current_path)
        while current_dir != "."
          dir_basename = File.basename(current_dir)

          # If current directory is a test directory, return its parent as search root
          if TEST_KEYWORDS.include?(dir_basename)
            return File.dirname(current_dir)
          end

          # Search the test directories by walking up the directory tree
          begin
            contains_test_dir = Dir
              .entries(current_dir)
              .filter { |entry| TEST_KEYWORDS.include?(entry) }
              .any? { |entry| File.directory?(File.join(current_dir, entry)) }

            return current_dir if contains_test_dir
          rescue Errno::EACCES, Errno::ENOENT
            # Skip directories we can't read
          end

          # Move up one level
          parent_dir = File.dirname(current_dir)
          current_dir = parent_dir
        end

        "."
      end

      #: -> Array[String]
      def relevant_filename_patterns
        extension = File.extname(@path)
        input_basename = File.basename(@path, extension)

        if input_basename.match?(TEST_PATTERN)
          # Test file -> find implementation
          base = input_basename.gsub(TEST_PATTERN, "")
          parent_dir = File.basename(File.dirname(@path))

          # If test file is in a directory matching the implementation name
          # (e.g., go_to_relevant_file/test_go_to_relevant_file_a.rb)
          # return patterns for both the base file name and the parent directory name
          if base.include?(parent_dir) && base != parent_dir
            ["#{base}#{extension}", "#{parent_dir}#{extension}"]
          else
            ["#{base}#{extension}"]
          end
        else
          # Implementation file -> find tests (including in matching directory)
          [
            "{#{TEST_PREFIX_GLOB}}#{input_basename}#{extension}",
            "#{input_basename}{#{TEST_SUFFIX_GLOB}}#{extension}",
            "#{input_basename}/{#{TEST_PREFIX_GLOB}}*#{extension}",
            "#{input_basename}/*{#{TEST_SUFFIX_GLOB}}#{extension}",
          ]
        end
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
