# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Index
    extend T::Sig

    class UnresolvableAliasError < StandardError; end

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
      @require_paths_tree = T.let(PrefixTree[IndexablePath].new, PrefixTree[IndexablePath])
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

    sig { params(query: String).returns(T::Array[IndexablePath]) }
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
    sig { params(query: String, nesting: T.nilable(T::Array[String])).returns(T::Array[T::Array[Entry]]) }
    def prefix_search(query, nesting = nil)
      unless nesting
        results = @entries_tree.search(query)
        results.uniq!
        return results
      end

      results = nesting.length.downto(0).flat_map do |i|
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
      if name.start_with?("::")
        name = name.delete_prefix("::")
        results = @entries[name] || @entries[follow_aliased_namespace(name)]
        return results&.map { |e| e.is_a?(Entry::UnresolvedAlias) ? resolve_alias(e) : e }
      end

      nesting.length.downto(0).each do |i|
        namespace = T.must(nesting[0...i]).join("::")
        full_name = namespace.empty? ? name : "#{namespace}::#{name}"

        # If we find an entry with `full_name` directly, then we can already return it, even if it contains aliases -
        # because the user might be trying to jump to the alias definition.
        #
        # However, if we don't find it, then we need to search for possible aliases in the namespace. For example, in
        # the LSP itself we alias `RubyLsp::Interface` to `LanguageServer::Protocol::Interface`, which means doing
        # `RubyLsp::Interface::Location` is allowed. For these cases, we need some way to realize that the
        # `RubyLsp::Interface` part is an alias, that has to be resolved
        entries = @entries[full_name] || @entries[follow_aliased_namespace(full_name)]
        return entries.map { |e| e.is_a?(Entry::UnresolvedAlias) ? resolve_alias(e) : e } if entries
      end

      nil
    rescue UnresolvableAliasError
      nil
    end

    # Index all files for the given indexable paths, which defaults to what is configured. A block can be used to track
    # and control indexing progress. That block is invoked with the current progress percentage and should return `true`
    # to continue indexing or `false` to stop indexing.
    sig do
      params(
        indexable_paths: T::Array[IndexablePath],
        block: T.nilable(T.proc.params(progress: Integer).returns(T::Boolean)),
      ).void
    end
    def index_all(indexable_paths: RubyIndexer.configuration.indexables, &block)
      # Calculate how many paths are worth 1% of progress
      progress_step = (indexable_paths.length / 100.0).ceil

      indexable_paths.each_with_index do |path, index|
        if block && index % progress_step == 0
          progress = (index / progress_step) + 1
          break unless block.call(progress)
        end

        index_single(path)
      end
    end

    sig { params(indexable_path: IndexablePath, source: T.nilable(String)).void }
    def index_single(indexable_path, source = nil)
      content = source || File.read(indexable_path.full_path)
      result = Prism.parse(content)
      collector = Collector.new(self, result, indexable_path.full_path)
      collector.collect(result.value)

      require_path = indexable_path.require_path
      @require_paths_tree.insert(require_path, indexable_path) if require_path
    rescue Errno::EISDIR, Errno::ENOENT
      # If `path` is a directory, just ignore it and continue indexing. If the file doesn't exist, then we also ignore
      # it
    end

    # Follows aliases in a namespace. The algorithm keeps checking if the name is an alias and then recursively follows
    # it. The idea is that we test the name in parts starting from the complete name to the first namespace. For
    # `Foo::Bar::Baz`, we would test:
    # 1. Is `Foo::Bar::Baz` an alias? Get the target and recursively follow its target
    # 2. Is `Foo::Bar` an alias? Get the target and recursively follow its target
    # 3. Is `Foo` an alias? Get the target and recursively follow its target
    #
    # If we find an alias, then we want to follow its target. In the same example, if `Foo::Bar` is an alias to
    # `Something::Else`, then we first discover `Something::Else::Baz`. But `Something::Else::Baz` might contain other
    # aliases, so we have to invoke `follow_aliased_namespace` again to check until we only return a real name
    sig { params(name: String).returns(String) }
    def follow_aliased_namespace(name)
      return name if @entries[name]

      parts = name.split("::")
      real_parts = []

      (parts.length - 1).downto(0).each do |i|
        current_name = T.must(parts[0..i]).join("::")
        entry = @entries[current_name]&.first

        case entry
        when Entry::Alias
          target = entry.target
          return follow_aliased_namespace("#{target}::#{real_parts.join("::")}")
        when Entry::UnresolvedAlias
          resolved = resolve_alias(entry)

          if resolved.is_a?(Entry::UnresolvedAlias)
            raise UnresolvableAliasError, "The constant #{resolved.name} is an alias to a non existing constant"
          end

          target = resolved.target
          return follow_aliased_namespace("#{target}::#{real_parts.join("::")}")
        else
          real_parts.unshift(T.must(parts[i]))
        end
      end

      real_parts.join("::")
    end

    # Attempts to find methods for a resolved fully qualified receiver name.
    # Returns `nil` if the method does not exist on that receiver
    sig { params(method_name: String, receiver_name: String).returns(T.nilable(T::Array[Entry::Member])) }
    def resolve_method(method_name, receiver_name)
      method_entries = self[method_name]
      owner_entries = self[receiver_name]
      return unless owner_entries && method_entries

      owner_name = T.must(owner_entries.first).name
      T.cast(
        method_entries.grep(Entry::Member).select do |entry|
          T.cast(entry, Entry::Member).owner&.name == owner_name
        end,
        T::Array[Entry::Member],
      )
    end

    private

    # Attempts to resolve an UnresolvedAlias into a resolved Alias. If the unresolved alias is pointing to a constant
    # that doesn't exist, then we return the same UnresolvedAlias
    sig { params(entry: Entry::UnresolvedAlias).returns(T.any(Entry::Alias, Entry::UnresolvedAlias)) }
    def resolve_alias(entry)
      target = resolve(entry.target, entry.nesting)
      return entry unless target

      target_name = T.must(target.first).name
      resolved_alias = Entry::Alias.new(target_name, entry)

      # Replace the UnresolvedAlias by a resolved one so that we don't have to do this again later
      original_entries = T.must(@entries[entry.name])
      original_entries.delete(entry)
      original_entries << resolved_alias

      @entries_tree.insert(entry.name, original_entries)

      resolved_alias
    end
  end
end
