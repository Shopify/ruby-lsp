# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Index
    extend T::Sig

    class UnresolvableAliasError < StandardError; end

    ConstantType = T.type_alias do
      T.any(Entry::Class, Entry::Module, Entry::Constant, Entry::Alias, Entry::UnresolvedAlias)
    end

    # The minimum Jaro-Winkler similarity score for an entry to be considered a match for a given fuzzy search query
    ENTRY_SIMILARITY_THRESHOLD = 0.7

    sig { void }
    def initialize
      # Holds all constant entries in the index using the following format:
      # {
      #  "Foo" => #<Entry::Class @declarations=[#<Declaration>, #<Declaration>]>,
      #  "Foo::Bar" => #<Entry::Class @declarations=[#<Declaration>]>,
      # }
      @constant_entries = T.let({}, T::Hash[String, ConstantType])

      # Holds all entries in the index using a prefix tree for searching based on prefixes to provide autocompletion
      @constant_entries_tree = T.let(PrefixTree[ConstantType].new, PrefixTree[ConstantType])

      # Holds all method entries in the index using the following format. We keep the owner names so that we can check
      # if a method entry already exists for that owner in a performant way without slowing down indexing
      # {
      #  "method_name" => { "OwnerModuleName" => #<Entry::Method>, "OwnerClassName" => #<Entry::Method> },
      #  "foo" => { "OwnerClassName" => #<Entry::Accessor> },
      # }
      @method_entries = T.let({}, T::Hash[String, T::Hash[String, Entry::Member]])

      # Holds all entries in the index using a prefix tree for searching based on prefixes to provide autocompletion
      @method_entries_tree = T.let(PrefixTree[T::Array[Entry::Member]].new, PrefixTree[T::Array[Entry::Member]])

      # Holds references to where entries where discovered so that we can easily delete them
      # {
      #  "/my/project/foo.rb" => [#<Entry::Class @declarations=[#<Declaration>, #<Declaration>]>, #<Entry::Accessor>],
      #  "/my/project/bar.rb" => #<Entry::Class @declarations=[#<Declaration>]>,
      # }
      @files_to_entries = T.let({}, T::Hash[String, T::Array[Entry]])

      # Holds all require paths for every indexed item so that we can provide autocomplete for requires
      @require_paths_tree = T.let(PrefixTree[IndexablePath].new, PrefixTree[IndexablePath])
    end

    sig { params(indexable: IndexablePath).void }
    def delete(indexable)
      # For each constant discovered in `path`, delete the associated entry from the index. If there are no entries
      # left, delete the constant from the index.
      full_path = indexable.full_path

      @files_to_entries[full_path]&.each do |file_entry|
        name = file_entry.name
        declarations = file_entry.declarations
        deleted_declaration = T.must(declarations.find { |declaration| declaration.file_path == full_path })
        declarations.delete(deleted_declaration)

        if declarations.empty?
          if file_entry.is_a?(Entry::Member)
            @method_entries.delete(name)
            @method_entries_tree.delete(name)
          else
            @constant_entries.delete(name)
            @constant_entries_tree.delete(name)
          end
        end
      end

      @files_to_entries.delete(full_path)
      require_path = indexable.require_path
      @require_paths_tree.delete(require_path) if require_path
    end

    # Add a new entry to the index. This method is only intended to be invoked for new entries that are discovered. For
    # new occurrences of an existing entry, invoke `add_declaration` on the entry and add the file_path using
    # `add_file_path`.
    sig { params(entry: Entry, file_path: String).void }
    def add_new_entry(entry, file_path)
      name = entry.name
      (@files_to_entries[file_path] ||= []) << entry

      case entry
      when Entry::Member
        owner_name = entry.owner&.name

        if owner_name
          (@method_entries[name] ||= {})[owner_name] = entry
          @method_entries_tree.insert(name, T.must(@method_entries[name]).values)
        end
      when Entry::Class, Entry::Module, Entry::Constant, Entry::Alias, Entry::UnresolvedAlias
        @constant_entries[name] = entry
        @constant_entries_tree.insert(name, entry)
      end
    end

    # Adds a file path for an existing entry in the index
    sig { params(entry: Entry, file_path: String).void }
    def add_file_path(entry, file_path)
      (@files_to_entries[file_path] ||= []) << entry
    end

    sig { params(fully_qualified_name: String).returns(T.nilable(ConstantType)) }
    def get_constant(fully_qualified_name)
      @constant_entries[fully_qualified_name.delete_prefix("::")]
    end

    sig { params(name: String).returns(T.nilable(T::Array[Entry::Member])) }
    def get_methods(name)
      @method_entries[name]&.values
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
    sig { params(query: String, nesting: T.nilable(T::Array[String])).returns(T::Array[ConstantType]) }
    def prefix_search_constants(query, nesting = nil)
      unless nesting
        results = @constant_entries_tree.search(query)
        results.uniq!
        return results
      end

      results = nesting.length.downto(0).flat_map do |i|
        prefix = T.must(nesting[0...i]).join("::")
        namespaced_query = prefix.empty? ? query : "#{prefix}::#{query}"
        @constant_entries_tree.search(namespaced_query)
      end

      results.uniq!
      results
    end

    sig { params(query: String, nesting: T.nilable(T::Array[String])).returns(T::Array[T::Array[Entry::Member]]) }
    def prefix_search_methods(query, nesting = nil)
      unless nesting
        results = @method_entries_tree.search(query)
        results.uniq!
        return results
      end

      results = nesting.length.downto(0).flat_map do |i|
        prefix = T.must(nesting[0...i]).join("::")
        namespaced_query = prefix.empty? ? query : "#{prefix}::#{query}"
        @method_entries_tree.search(namespaced_query)
      end

      results.uniq!
      results
    end

    # Fuzzy searches index entries based on Jaro-Winkler similarity. If no query is provided, all entries are returned
    sig { params(query: T.nilable(String)).returns(T::Array[Entry]) }
    def fuzzy_search(query)
      return @constant_entries.values + @method_entries.values.flat_map(&:values) unless query

      normalized_query = query.gsub("::", "").downcase

      results = @constant_entries.filter_map do |name, entries|
        similarity = DidYouMean::JaroWinkler.distance(name.gsub("::", "").downcase, normalized_query)
        [entries, -similarity] if similarity > ENTRY_SIMILARITY_THRESHOLD
      end

      results.concat(@method_entries.filter_map do |name, hash|
        similarity = DidYouMean::JaroWinkler.distance(name.gsub("::", "").downcase, normalized_query)
        [hash.values, -similarity] if similarity > ENTRY_SIMILARITY_THRESHOLD
      end)

      results.sort_by!(&:last)
      results.flat_map(&:first)
    end

    # Try to find the entry based on the nesting from the most specific to the least specific. For example, if we have
    # the nesting as ["Foo", "Bar"] and the name as "Baz", we will try to find it in this order:
    # 1. Foo::Bar::Baz
    # 2. Foo::Baz
    # 3. Baz
    sig { params(name: String, nesting: T::Array[String]).returns(T.nilable(ConstantType)) }
    def resolve_constant(name, nesting)
      if name.start_with?("::")
        name = name.delete_prefix("::")
        target_entry = @constant_entries[name] || @constant_entries[follow_aliased_namespace(name)]
        return target_entry.is_a?(Entry::UnresolvedAlias) ? resolve_alias(target_entry) : target_entry
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
        entry = @constant_entries[full_name] || @constant_entries[follow_aliased_namespace(full_name)]
        return entry.is_a?(Entry::UnresolvedAlias) ? resolve_alias(entry) : entry if entry
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
      return name if @constant_entries[name]

      parts = name.split("::")
      real_parts = []

      (parts.length - 1).downto(0).each do |i|
        current_name = T.must(parts[0..i]).join("::")
        entry = @constant_entries[current_name]

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
    sig { params(method_name: String, receiver_name: String).returns(T.nilable(Entry::Member)) }
    def resolve_method(method_name, receiver_name)
      @method_entries.dig(method_name, receiver_name)
    end

    private

    # Attempts to resolve an UnresolvedAlias into a resolved Alias. If the unresolved alias is pointing to a constant
    # that doesn't exist, then we return the same UnresolvedAlias
    sig { params(entry: Entry::UnresolvedAlias).returns(T.any(Entry::Alias, Entry::UnresolvedAlias)) }
    def resolve_alias(entry)
      target = resolve_constant(entry.target, entry.nesting)
      return entry unless target

      target_name = target.name
      resolved_alias = Entry::Alias.new(target_name, entry)

      # Replace the UnresolvedAlias by a resolved one so that we don't have to do this again later
      @constant_entries[entry.name] = resolved_alias
      @constant_entries_tree.insert(entry.name, resolved_alias)

      resolved_alias
    end
  end
end
