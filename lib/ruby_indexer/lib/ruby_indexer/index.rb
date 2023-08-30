# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Index
    extend T::Sig

    # The minimum Jaro-Winkler similarity score for an entry to be considered a match for a given fuzzy search query
    ENTRY_SIMILARITY_THRESHOLD = 0.7

    sig { void }
    def initialize
      # Holds all entries in the index using the following format:
      # {
      #  "Foo" => [#<Entry::Class>, #<Entry::Class>],
      #  "Foo::Bar" => [#<Entry::Class>],
      # }
      @entries = T.let({}, T::Hash[String, T::Array[Entry]])

      # Holds all entries in the index using a prefix tree for searching based on prefixes to provide autocompletion
      @entries_tree = T.let(PrefixTree[T::Array[Entry]].new, PrefixTree[T::Array[Entry]])

      # Holds references to where entries where discovered so that we can easily delete them
      # {
      #  "/my/project/foo.rb" => [#<Entry::Class>, #<Entry::Class>],
      #  "/my/project/bar.rb" => [#<Entry::Class>],
      # }
      @files_to_entries = T.let({}, T::Hash[String, T::Array[Entry]])

      # Holds all require paths for every indexed item so that we can provide autocomplete for requires
      @require_paths_tree = T.let(PrefixTree[String].new, PrefixTree[String])
    end

    sig { params(indexable: IndexablePath).void }
    def delete(indexable)
      # For each constant discovered in `path`, delete the associated entry from the index. If there are no entries
      # left, delete the constant from the index.
      @files_to_entries[indexable.full_path]&.each do |entry|
        name = entry.name
        entries = @entries[name]
        next unless entries

        # Delete the specific entry from the list for this name
        entries.delete(entry)

        # If all entries were deleted, then remove the name from the hash and from the prefix tree. Otherwise, update
        # the prefix tree with the current entries
        if entries.empty?
          @entries.delete(name)
          @entries_tree.delete(name)
        else
          @entries_tree.insert(name, entries)
        end
      end

      @files_to_entries.delete(indexable.full_path)

      require_path = indexable.require_path
      @require_paths_tree.delete(require_path) if require_path
    end

    sig { params(entry: Entry).void }
    def <<(entry)
      name = entry.name

      (@entries[name] ||= []) << entry
      (@files_to_entries[entry.file_path] ||= []) << entry
      @entries_tree.insert(name, T.must(@entries[name]))
    end

    sig { params(fully_qualified_name: String).returns(T.nilable(T::Array[Entry])) }
    def [](fully_qualified_name)
      @entries[fully_qualified_name.delete_prefix("::")]
    end

    sig { params(query: String).returns(T::Array[String]) }
    def search_require_paths(query)
      @require_paths_tree.search(query)
    end

    # Searches entries in the index based on an exact prefix, intended for providing autocomplete. All possible matches
    # to the prefix are returned. The return is an array of arrays, where each entry is the array of entries for a given
    # name match. For example:
    # ## Example
    # ```ruby
    # # If the index has two entries for `Foo::Bar` and one for `Foo::Baz`, then:
    # index.prefix_search("Foo::B")
    # # Will return:
    # [
    #   [#<Entry::Class name="Foo::Bar">, #<Entry::Class name="Foo::Bar">],
    #   [#<Entry::Class name="Foo::Baz">],
    # ]
    # ```
    sig { params(query: String, nesting: T::Array[String]).returns(T::Array[T::Array[Entry]]) }
    def prefix_search(query, nesting)
      results = (nesting.length + 1).downto(0).flat_map do |i|
        prefix = T.must(nesting[0...i]).join("::")
        namespaced_query = prefix.empty? ? query : "#{prefix}::#{query}"
        @entries_tree.search(namespaced_query)
      end

      results.uniq!
      results
    end

    # Fuzzy searches index entries based on Jaro-Winkler similarity. If no query is provided, all entries are returned
    sig { params(query: T.nilable(String)).returns(T::Array[Entry]) }
    def fuzzy_search(query)
      return @entries.flat_map { |_name, entries| entries } unless query

      normalized_query = query.gsub("::", "").downcase

      results = @entries.filter_map do |name, entries|
        similarity = DidYouMean::JaroWinkler.distance(name.gsub("::", "").downcase, normalized_query)
        [entries, -similarity] if similarity > ENTRY_SIMILARITY_THRESHOLD
      end
      results.sort_by!(&:last)
      results.flat_map(&:first)
    end

    # Try to find the entry based on the nesting from the most specific to the least specific. For example, if we have
    # the nesting as ["Foo", "Bar"] and the name as "Baz", we will try to find it in this order:
    # 1. Foo::Bar::Baz
    # 2. Foo::Baz
    # 3. Baz
    sig { params(name: String, nesting: T::Array[String]).returns(T.nilable(T::Array[Entry])) }
    def resolve(name, nesting)
      (nesting.length + 1).downto(0).each do |i|
        prefix = T.must(nesting[0...i]).join("::")
        full_name = prefix.empty? ? name : "#{prefix}::#{name}"
        entries = @entries[full_name]
        return entries if entries
      end

      nil
    end

    sig { params(indexable_paths: T::Array[IndexablePath]).void }
    def index_all(indexable_paths: RubyIndexer.configuration.indexables)
      indexable_paths.each { |path| index_single(path) }
    end

    sig { params(indexable_path: IndexablePath, source: T.nilable(String)).void }
    def index_single(indexable_path, source = nil)
      content = source || File.read(indexable_path.full_path)
      visitor = IndexVisitor.new(self, YARP.parse(content), indexable_path.full_path)
      visitor.run

      require_path = indexable_path.require_path
      @require_paths_tree.insert(require_path, require_path) if require_path
    rescue Errno::EISDIR
      # If `path` is a directory, just ignore it and continue indexing
    end

    class Entry
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(String) }
      attr_reader :file_path

      sig { returns(YARP::Location) }
      attr_reader :location

      sig { returns(T::Array[String]) }
      attr_reader :comments

      sig { params(name: String, file_path: String, location: YARP::Location, comments: T::Array[String]).void }
      def initialize(name, file_path, location, comments)
        @name = name
        @file_path = file_path
        @location = location
        @comments = comments
      end

      sig { returns(String) }
      def file_name
        File.basename(@file_path)
      end

      class Namespace < Entry
        sig { returns(String) }
        def short_name
          T.must(@name.split("::").last)
        end
      end

      class Module < Namespace
      end

      class Class < Namespace
      end

      class Constant < Entry
      end
    end
  end
end
