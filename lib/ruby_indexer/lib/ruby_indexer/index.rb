# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Index
    extend T::Sig

    class UnresolvableAliasError < StandardError; end
    class NonExistingNamespaceError < StandardError; end

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

      # Holds the linearized ancestors list for every namespace
      @ancestors = T.let({}, T::Hash[String, T::Array[String]])
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

    sig { params(name: String, receiver_name: String).returns(T::Array[Entry]) }
    def method_completion_candidates(name, receiver_name)
      ancestors = linearized_ancestors_of(receiver_name)
      candidates = prefix_search(name).flatten
      candidates.select! do |entry|
        entry.is_a?(RubyIndexer::Entry::Member) && ancestors.any?(entry.owner&.name)
      end
      candidates
    end

    # Resolve a constant to its declaration based on its name and the nesting where the reference was found. Parameter
    # documentation:
    #
    # name: the name of the reference how it was found in the source code (qualified or not)
    # nesting: the nesting structure where the reference was found (e.g.: ["Foo", "Bar"])
    # seen_names: this parameter should not be used by consumers of the api. It is used to avoid infinite recursion when
    # resolving circular references
    sig do
      params(
        name: String,
        nesting: T::Array[String],
        seen_names: T::Array[String],
      ).returns(T.nilable(T::Array[Entry]))
    end
    def resolve(name, nesting, seen_names = [])
      # If we have a top level reference, then we just search for it straight away ignoring the nesting
      if name.start_with?("::")
        entries = direct_or_aliased_constant(name.delete_prefix("::"), seen_names)
        return entries if entries
      end

      # Non qualified reference path
      full_name = nesting.any? ? "#{nesting.join("::")}::#{name}" : name

      # When the name is not qualified with any namespaces, Ruby will take several steps to try to the resolve the
      # constant. First, it will try to find the constant in the exact namespace where the reference was found
      entries = direct_or_aliased_constant(full_name, seen_names)
      return entries if entries

      # If the constant is not found yet, then Ruby will try to find the constant in the enclosing lexical scopes,
      # unwrapping each level one by one. Important note: the top level is not included because that's the fallback of
      # the algorithm after every other possibility has been exhausted
      entries = lookup_enclosing_scopes(name, nesting, seen_names)
      return entries if entries

      # If the constant does not exist in any enclosing scopes, then Ruby will search for it in the ancestors of the
      # specific namespace where the reference was found
      entries = lookup_ancestor_chain(name, nesting, seen_names)
      return entries if entries

      # Finally, as a fallback, Ruby will search for the constant in the top level namespace
      search_top_level(name, seen_names)
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
      dispatcher = Prism::Dispatcher.new

      result = Prism.parse(content)
      DeclarationListener.new(self, dispatcher, result, indexable_path.full_path)
      dispatcher.dispatch(result.value)

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
    sig { params(name: String, seen_names: T::Array[String]).returns(String) }
    def follow_aliased_namespace(name, seen_names = [])
      return name if @entries[name]

      parts = name.split("::")
      real_parts = []

      (parts.length - 1).downto(0).each do |i|
        current_name = T.must(parts[0..i]).join("::")
        entry = @entries[current_name]&.first

        case entry
        when Entry::Alias
          target = entry.target
          return follow_aliased_namespace("#{target}::#{real_parts.join("::")}", seen_names)
        when Entry::UnresolvedAlias
          resolved = resolve_alias(entry, seen_names)

          if resolved.is_a?(Entry::UnresolvedAlias)
            raise UnresolvableAliasError, "The constant #{resolved.name} is an alias to a non existing constant"
          end

          target = resolved.target
          return follow_aliased_namespace("#{target}::#{real_parts.join("::")}", seen_names)
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
      ancestors = linearized_ancestors_of(receiver_name.delete_prefix("::"))
      return unless method_entries

      ancestors.each do |ancestor|
        found = method_entries.select do |entry|
          next unless entry.is_a?(Entry::Member)

          entry.owner&.name == ancestor
        end

        return T.cast(found, T::Array[Entry::Member]) if found.any?
      end

      nil
    rescue NonExistingNamespaceError
      nil
    end

    # Linearizes the ancestors for a given name, returning the order of namespaces in which Ruby will search for method
    # or constant declarations.
    #
    # When we add an ancestor in Ruby, that namespace might have ancestors of its own. Therefore, we need to linearize
    # everything recursively to ensure that we are placing ancestors in the right order. For example, if you include a
    # module that prepends another module, then the prepend module appears before the included module.
    #
    # The order of ancestors is [linearized_prepends, self, linearized_includes, linearized_superclass]
    sig { params(fully_qualified_name: String).returns(T::Array[String]) }
    def linearized_ancestors_of(fully_qualified_name)
      # If we already computed the ancestors for this namespace, return it straight away
      cached_ancestors = @ancestors[fully_qualified_name]
      return cached_ancestors if cached_ancestors

      # If we don't have an entry for `name`, raise
      entries = self[fully_qualified_name]
      raise NonExistingNamespaceError, "No entry found for #{fully_qualified_name}" unless entries

      ancestors = [fully_qualified_name]

      # Cache the linearized ancestors array eagerly. This is important because we might have circular dependencies and
      # this will prevent us from falling into an infinite recursion loop. Because we mutate the ancestors array later,
      # the cache will reflect the final result
      @ancestors[fully_qualified_name] = ancestors

      # If none of the entries for `name` are namespaces, raise
      namespaces = entries.filter_map do |entry|
        case entry
        when Entry::Namespace
          entry
        when Entry::Alias
          self[entry.target]&.grep(Entry::Namespace)
        end
      end.flatten

      raise NonExistingNamespaceError,
        "None of the entries for #{fully_qualified_name} are modules or classes" if namespaces.empty?

      mixin_operations = namespaces.flat_map(&:mixin_operations)
      main_namespace_index = 0

      # The original nesting where we discovered this namespace, so that we resolve the correct names of the
      # included/prepended/extended modules and parent classes
      nesting = T.must(namespaces.first).nesting

      mixin_operations.each do |operation|
        resolved_module = resolve(operation.module_name, nesting)
        next unless resolved_module

        module_fully_qualified_name = T.must(resolved_module.first).name

        case operation
        when Entry::Prepend
          # When a module is prepended, Ruby checks if it hasn't been prepended already to prevent adding it in front of
          # the actual namespace twice. However, it does not check if it has been included because you are allowed to
          # prepend the same module after it has already been included
          linearized_prepends = linearized_ancestors_of(module_fully_qualified_name)

          # When there are duplicate prepended modules, we have to insert the new prepends after the existing ones. For
          # example, if the current ancestors are `["A", "Foo"]` and we try to prepend `["A", "B"]`, then `"B"` has to
          # be inserted after `"A`
          uniq_prepends = linearized_prepends - T.must(ancestors[0...main_namespace_index])
          insert_position = linearized_prepends.length - uniq_prepends.length

          T.unsafe(ancestors).insert(
            insert_position,
            *(linearized_prepends - T.must(ancestors[0...main_namespace_index])),
          )

          main_namespace_index += linearized_prepends.length
        when Entry::Include
          # When including a module, Ruby will always prevent duplicate entries in case the module has already been
          # prepended or included
          linearized_includes = linearized_ancestors_of(module_fully_qualified_name)
          T.unsafe(ancestors).insert(main_namespace_index + 1, *(linearized_includes - ancestors))
        end
      end

      # Find the first class entry that has a parent class. Notice that if the developer makes a mistake and inherits
      # from two diffent classes in different files, we simply ignore it
      superclass = T.cast(namespaces.find { |n| n.is_a?(Entry::Class) && n.parent_class }, T.nilable(Entry::Class))

      if superclass
        # If the user makes a mistake and creates a class that inherits from itself, this method would throw a stack
        # error. We need to ensure that this isn't the case
        parent_class = T.must(superclass.parent_class)

        resolved_parent_class = resolve(parent_class, nesting)
        parent_class_name = resolved_parent_class&.first&.name

        if parent_class_name && fully_qualified_name != parent_class_name
          ancestors.concat(linearized_ancestors_of(parent_class_name))
        end
      end

      ancestors
    end

    # Resolves an instance variable name for a given owner name. This method will linearize the ancestors of the owner
    # and find inherited instance variables as well
    sig { params(variable_name: String, owner_name: String).returns(T.nilable(T::Array[Entry::InstanceVariable])) }
    def resolve_instance_variable(variable_name, owner_name)
      entries = T.cast(self[variable_name], T.nilable(T::Array[Entry::InstanceVariable]))
      return unless entries

      ancestors = linearized_ancestors_of(owner_name)
      return if ancestors.empty?

      entries.select { |e| ancestors.include?(e.owner&.name) }
    end

    # Returns a list of possible candidates for completion of instance variables for a given owner name. The name must
    # include the `@` prefix
    sig { params(name: String, owner_name: String).returns(T::Array[Entry::InstanceVariable]) }
    def instance_variable_completion_candidates(name, owner_name)
      entries = T.cast(prefix_search(name).flatten, T::Array[Entry::InstanceVariable])
      ancestors = linearized_ancestors_of(owner_name)

      variables = entries.select { |e| ancestors.any?(e.owner&.name) }
      variables.uniq!(&:name)
      variables
    end

    # Synchronizes a change made to the given indexable path. This method will ensure that new declarations are indexed,
    # removed declarations removed and that the ancestor linearization cache is cleared if necessary
    sig { params(indexable: IndexablePath).void }
    def handle_change(indexable)
      original_entries = @files_to_entries[indexable.full_path]

      delete(indexable)
      index_single(indexable)

      updated_entries = @files_to_entries[indexable.full_path]

      return unless original_entries && updated_entries

      # A change in one ancestor may impact several different others, which could be including that ancestor through
      # indirect means like including a module that than includes the ancestor. Trying to figure out exactly which
      # ancestors need to be deleted is too expensive. Therefore, if any of the namespace entries has a change to their
      # ancestor hash, we clear all ancestors and start linearizing lazily again from scratch
      original_map = T.cast(
        original_entries.select { |e| e.is_a?(Entry::Namespace) },
        T::Array[Entry::Namespace],
      ).to_h { |e| [e.name, e.ancestor_hash] }

      updated_map = T.cast(
        updated_entries.select { |e| e.is_a?(Entry::Namespace) },
        T::Array[Entry::Namespace],
      ).to_h { |e| [e.name, e.ancestor_hash] }

      @ancestors.clear if original_map.any? { |name, hash| updated_map[name] != hash }
    end

    private

    # Attempts to resolve an UnresolvedAlias into a resolved Alias. If the unresolved alias is pointing to a constant
    # that doesn't exist, then we return the same UnresolvedAlias
    sig do
      params(
        entry: Entry::UnresolvedAlias,
        seen_names: T::Array[String],
      ).returns(T.any(Entry::Alias, Entry::UnresolvedAlias))
    end
    def resolve_alias(entry, seen_names)
      alias_name = entry.name
      return entry if seen_names.include?(alias_name)

      seen_names << alias_name

      target = resolve(entry.target, entry.nesting, seen_names)
      return entry unless target

      target_name = T.must(target.first).name
      resolved_alias = Entry::Alias.new(target_name, entry)

      # Replace the UnresolvedAlias by a resolved one so that we don't have to do this again later
      original_entries = T.must(@entries[alias_name])
      original_entries.delete(entry)
      original_entries << resolved_alias

      @entries_tree.insert(alias_name, original_entries)

      resolved_alias
    end

    sig do
      params(
        name: String,
        nesting: T::Array[String],
        seen_names: T::Array[String],
      ).returns(T.nilable(T::Array[Entry]))
    end
    def lookup_enclosing_scopes(name, nesting, seen_names)
      nesting.length.downto(1).each do |i|
        namespace = T.must(nesting[0...i]).join("::")

        # If we find an entry with `full_name` directly, then we can already return it, even if it contains aliases -
        # because the user might be trying to jump to the alias definition.
        #
        # However, if we don't find it, then we need to search for possible aliases in the namespace. For example, in
        # the LSP itself we alias `RubyLsp::Interface` to `LanguageServer::Protocol::Interface`, which means doing
        # `RubyLsp::Interface::Location` is allowed. For these cases, we need some way to realize that the
        # `RubyLsp::Interface` part is an alias, that has to be resolved
        entries = direct_or_aliased_constant("#{namespace}::#{name}", seen_names)
        return entries if entries
      end

      nil
    end

    sig do
      params(
        name: String,
        nesting: T::Array[String],
        seen_names: T::Array[String],
      ).returns(T.nilable(T::Array[Entry]))
    end
    def lookup_ancestor_chain(name, nesting, seen_names)
      *nesting_parts, constant_name = build_non_redundant_full_name(name, nesting).split("::")
      return if T.must(nesting_parts).empty?

      namespace_entries = resolve(T.must(nesting_parts).join("::"), [], seen_names)
      return unless namespace_entries

      ancestors = T.must(nesting_parts).empty? ? [] : linearized_ancestors_of(T.must(namespace_entries.first).name)

      ancestors.each do |ancestor_name|
        entries = direct_or_aliased_constant("#{ancestor_name}::#{constant_name}", seen_names)
        return entries if entries
      end

      nil
    rescue NonExistingNamespaceError
      nil
    end

    # Removes redudancy from a constant reference's full name. For example, if we find a reference to `A::B::Foo` inside
    # of the ["A", "B"] nesting, then we should not concatenate the nesting with the name or else we'll end up with
    # `A::B::A::B::Foo`. This method will remove any redundant parts from the final name based on the reference and the
    # nesting
    sig { params(name: String, nesting: T::Array[String]).returns(String) }
    def build_non_redundant_full_name(name, nesting)
      return name if nesting.empty?

      namespace = nesting.join("::")

      # If the name is not qualified, we can just concatenate the nesting and the name
      return "#{namespace}::#{name}" unless name.include?("::")

      name_parts = name.split("::")

      # Find the first part of the name that is not in the nesting
      index = name_parts.index { |part| !nesting.include?(part) }

      if index.nil?
        # All parts of the nesting are redundant because they are already present in the name. We can return the name
        # directly
        name
      elsif index == 0
        # No parts of the nesting are in the name, we can concatenate the namespace and the name
        "#{namespace}::#{name}"
      else
        # The name includes some parts of the nesting. We need to remove the redundant parts
        "#{namespace}::#{T.must(name_parts[index..-1]).join("::")}"
      end
    end

    sig { params(full_name: String, seen_names: T::Array[String]).returns(T.nilable(T::Array[Entry])) }
    def direct_or_aliased_constant(full_name, seen_names)
      entries = @entries[full_name] || @entries[follow_aliased_namespace(full_name)]
      entries&.map { |e| e.is_a?(Entry::UnresolvedAlias) ? resolve_alias(e, seen_names) : e }
    end

    sig { params(name: String, seen_names: T::Array[String]).returns(T.nilable(T::Array[Entry])) }
    def search_top_level(name, seen_names)
      @entries[name]&.map { |e| e.is_a?(Entry::UnresolvedAlias) ? resolve_alias(e, seen_names) : e }
    end
  end
end
