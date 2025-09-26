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
        search_roots = determine_search_roots
        candidate_paths = []

        search_roots.each do |root|
          glob_pattern = File.join(root, "**", relevant_filename_pattern)
          candidate_paths.concat(Dir.glob(glob_pattern))
        end

        candidate_paths.map! { |path| path.delete_prefix(@workspace_path).delete_prefix("/") }

        candidate_paths.uniq!
        return [] if candidate_paths.empty?

        find_most_similar_with_jaccard(candidate_paths).map { File.join(@workspace_path, _1) }
      end

      # Determine the search roots based on the closest test directories.
      # This scopes the search to reduce the number of files that need to be checked.
      #: -> Array[String]
      def determine_search_roots
        current_path = File.join(@workspace_path, @path)

        current_dir = File.dirname(current_path)
        while current_dir.start_with?(@workspace_path)
          dir_basename = File.basename(current_dir)

          # If current directory is a test directory, return its parent as search root
          if TEST_KEYWORDS.any? { |keyword| dir_basename.include?(keyword) }
            parent = File.dirname(current_dir)
            return parent.start_with?(@workspace_path) ? [parent] : [@workspace_path]
          end

          # Search the test directories by walking up the directory tree
          begin
            entries = Dir.entries(current_dir).reject { |entry| entry.start_with?(".") }
            test_dir_found = entries.any? do |entry|
              full_path = File.join(current_dir, entry)
              File.directory?(full_path) && TEST_KEYWORDS.any? { |keyword| entry == keyword }
            end

            return [current_dir] if test_dir_found
          rescue Errno::EACCES, Errno::ENOENT
            # Skip directories we can't read
          end

          # Move up one level
          parent_dir = File.dirname(current_dir)
          break if parent_dir == current_dir

          current_dir = parent_dir
        end

        [@workspace_path]
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
