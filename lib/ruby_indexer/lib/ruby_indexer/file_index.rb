# typed: false
# frozen_string_literal: true

# Index:
# {
#   "c": ["a/b/c.rb", "a/b/c_test.rb", "a/b/c_integration_test.rb", "a/b/test_c.rb", "a/b/sepc_c.rb", "a/b/integration_test_c.rb"]
# }

# API:
# index.search("c") -> ["a/b/c.rb", "a/b/c_test.rb", "a/b/c_integration_test.rb", "a/b/test_c.rb", "a/b/sepc_c.rb", "a/b/integration_test_c.rb"]
# index.insert("a/b/d.rb")
# index.insert("a/b/d_test.rb")
# index.search("d") -> ["a/b/d.rb", "a/b/d_test.rb"]
# index.delete("a/b/d.rb")
# index.search("d") -> ["a/b/d_test.rb"]
# index.delete("a/b/d_test.rb")
# index.search("d") -> []

module RubyIndexer
  # The FileIndex class maintains an in-memory index of files for fast lookup.
  # It allows searching for files based on their base name, handling various test file patterns.
  class FileIndex # TODO: Provide better naming for just subject/test file index.
    TEST_REGEX = /^(test_|spec_|integration_test_)|((_test|_spec|_integration_test)$)/
    def initialize
      @index = {}
    end

    # Extract the base name from a file path, removing test prefixes and suffixes
    def extract_base_name(path)
      basename = File.basename(path, ".*")

      # Handle patterns like test_hello, spec_hello, integration_test_hello
      basename = basename.sub(/^(test_|spec_|integration_test_)/, "")

      # Handle patterns like hello_test, hello_spec, hello_integration_test
      basename = basename.sub(/((_test|_spec|_integration_test)$)/, "")

      basename
    end

    # Insert a file path into the index
    def insert(path)
      base_name = extract_base_name(path)
      @index[base_name] ||= []
      @index[base_name] << path
    end

    # Delete a file path from the index
    def delete(path)
      base_name = extract_base_name(path)
      if @index.key?(base_name)
        @index[base_name].delete(path)
        @index.delete(base_name) if @index[base_name].empty?
      end
    end

    # Search for files that match the given base name
    def search(base_name)
      @index[base_name] || []
    end

    # Search for files that can be tests of the given base_name
    def search_test(base_name)
      return [] if @index[base_name].nil?

      search(base_name).select do |file|
        File.basename(file, ".*").match?(TEST_REGEX)
      end
    end

    def search_subject(base_name)
      return [] if @index[base_name].nil?

      search(base_name).reject do |file|
        File.basename(file, ".*").match?(TEST_REGEX)
      end
    end

    # Bulk load multiple file paths into the index
    def bulk_load(paths)
      paths.each { |path| insert(path) }
    end

    # Clear the entire index
    def clear
      @index.clear
    end
  end
end
