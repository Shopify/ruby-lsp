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

      TEST_KEYWORDS = ["test", "spec", "integration_test"]

      sig { params(path: String).void }
      def initialize(path)
        super()

        @workspace_path = T.let(Dir.pwd, String)
        @path = T.let(path.delete_prefix(@workspace_path), String)
      end

      sig { override.returns(T::Array[String]) }
      def perform
        find_relevant_paths
      end

      private

      sig { returns(T::Array[String]) }
      def find_relevant_paths
        workspace_path = Dir.pwd
        relative_path = @path.delete_prefix(workspace_path)

        candidate_paths = Dir.glob(File.join("**", relevant_filename_pattern(relative_path)))
        return [] if candidate_paths.empty?

        find_most_similar_with_jacaard(relative_path, candidate_paths).map { File.join(workspace_path, _1) }
      end

      sig { params(path: String).returns(String) }
      def relevant_filename_pattern(path)
        input_basename = File.basename(path, File.extname(path))

        test_prefix_pattern = /^(#{TEST_KEYWORDS.join("_|")}_)/
        test_suffix_pattern = /(_#{TEST_KEYWORDS.join("|_")})$/
        test_pattern = /#{test_prefix_pattern}|#{test_suffix_pattern}/

        relevant_basename_pattern =
          if input_basename.match?(test_pattern)
            input_basename.gsub(test_pattern, "")
          else
            test_prefix_glob = "#{TEST_KEYWORDS.join("_,")}_"
            test_suffix_glob = "_#{TEST_KEYWORDS.join(",_")}"

            "{{#{test_prefix_glob}}#{input_basename},#{input_basename}{#{test_suffix_glob}}}"
          end

        "#{relevant_basename_pattern}#{File.extname(path)}"
      end

      sig { params(path: String, candidates: T::Array[String]).returns(T::Array[String]) }
      def find_most_similar_with_jacaard(path, candidates)
        dirs = get_dir_parts(path)

        _, results = candidates
          .group_by do |other_path|
            other_dirs = get_dir_parts(other_path)
            # Similarity score between the two directories
            (dirs & other_dirs).size.to_f / (dirs | other_dirs).size
          end
          .max_by(&:first)

        results || []
      end

      sig { params(path: String).returns(T::Set[String]) }
      def get_dir_parts(path)
        Set.new(File.dirname(path).split(File::SEPARATOR))
      end
    end
  end
end
