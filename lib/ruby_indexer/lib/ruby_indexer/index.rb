# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Index
    class UnresolvableAliasError < StandardError; end
    class NonExistingNamespaceError < StandardError; end
    class IndexNotEmptyError < StandardError; end

    # The minimum Jaro-Winkler similarity score for an entry to be considered a match for a given fuzzy search query
    ENTRY_SIMILARITY_THRESHOLD = 0.7

    #: Configuration
    attr_reader :configuration

    #: bool
    attr_reader :initial_indexing_completed

    class << self
      # Returns the real nesting of a constant name taking into account top level
      # references that may be included anywhere in the name or nesting where that
      # constant was found
      #: (Array[String] stack, String? name) -> Array[String]
      def actual_nesting(stack, name)
        nesting = name ? stack + [name] : stack
        corrected_nesting = []

        nesting.reverse_each do |name|
          corrected_nesting.prepend(name.delete_prefix("::"))

          break if name.start_with?("::")
        end

        corrected_nesting
      end

      # Returns the unresolved name for a constant reference including all parts of a constant path, or `nil` if the
      # constant contains dynamic or incomplete parts
      #: ((Prism::ConstantPathNode | Prism::ConstantReadNode | Prism::ConstantPathTargetNode | Prism::CallNode | Prism::MissingNode) node) -> String?
      def constant_name(node)
        case node
        when Prism::CallNode, Prism::MissingNode
          nil
        else
          node.full_name
        end
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
             Prism::ConstantPathNode::MissingNodesInConstantPathError
        nil
      end
    end

    #: -> void
    def initialize
      # Holds all entries in the index using the following format:
      # {
      #  "Foo" => [#<Entry::Class>, #<Entry::Class>],
      #  "Foo::Bar" => [#<Entry::Class>],
      # }
      @entries = {} #: Hash[String, Array[Entry]]

      # Holds all entries in the index using a prefix tree for searching based on prefixes to provide autocompletion
      @entries_tree = PrefixTree[T::Array[Entry]].new #: PrefixTree[Array[Entry]]

      # Holds references to where entries where discovered so that we can easily delete them
      # {
      #  "file:///my/project/foo.rb" => [#<Entry::Class>, #<Entry::Class>],
      #  "file:///my/project/bar.rb" => [#<Entry::Class>],
      #  "untitled:Untitled-1" => [#<Entry::Class>],
      # }
      @uris_to_entries = {} #: Hash[String, Array[Entry]]

      # Holds all require paths for every indexed item so that we can provide autocomplete for requires
      @require_paths_tree = PrefixTree[URI::Generic].new #: PrefixTree[URI::Generic]

      # Holds the linearized ancestors list for every namespace
      @ancestors = {} #: Hash[String, Array[String]]

      # Map of module name to included hooks that have to be executed when we include the given module
      @included_hooks = {} #: Hash[String, Array[^(Index index, Entry::Namespace base) -> void]]

      @configuration = RubyIndexer::Configuration.new #: Configuration

      @initial_indexing_completed = false #: bool
    end

    # Register an included `hook` that will be executed when `module_name` is included into any namespace
    #: (String module_name) { (Index index, Entry::Namespace base) -> void } -> void
    def register_included_hook(module_name, &hook)
      (@included_hooks[module_name] ||= []) << hook
    end

    #: (URI::Generic uri, ?skip_require_paths_tree: bool) -> void
    def delete(uri, skip_require_paths_tree: false)
      key = uri.to_s
      # For each constant discovered in `path`, delete the associated entry from the index. If there are no entries
      # left, delete the constant from the index.
      @uris_to_entries[key]&.each do |entry|
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

      @uris_to_entries.delete(key)
      return if skip_require_paths_tree

      require_path = uri.require_path
      @require_paths_tree.delete(require_path) if require_path
    end

    #: (Entry entry, ?skip_prefix_tree: bool) -> void
    def add(entry, skip_prefix_tree: false)
      name = entry.name

      (@entries[name] ||= []) << entry
      (@uris_to_entries[entry.uri.to_s] ||= []) << entry

      unless skip_prefix_tree
        @entries_tree.insert(
          name,
          @entries[name], #: as !nil
        )
      end
    end

    #: (String fully_qualified_name) -> Array[Entry]?
    def [](fully_qualified_name)
      @entries[fully_qualified_name.delete_prefix("::")]
    end

    #: (String query) -> Array[URI::Generic]
    def search_require_paths(query)
      @require_paths_tree.search(query)
    end

    # Searches for a constant based on an unqualified name and returns the first possible match regardless of whether
    # there are more possible matching entries
    #: (String name) -> Array[(Entry::Namespace | Entry::ConstantAlias | Entry::UnresolvedConstantAlias | Entry::Constant)]?
    def first_unqualified_const(name)
      # Look for an exact match first
      _name, entries = @entries.find do |const_name, _entries|
        const_name == name || const_name.end_with?("::#{name}")
      end

      # If an exact match is not found, then try to find a constant that ends with the name
      unless entries
        _name, entries = @entries.find do |const_name, _entries|
          const_name.end_with?(name)
        end
      end

      T.cast(
        entries,
        T.nilable(T::Array[T.any(
          Entry::Namespace,
          Entry::ConstantAlias,
          Entry::UnresolvedConstantAlias,
          Entry::Constant,
        )]),
      )
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
    #: (String query, ?Array[String]? nesting) -> Array[Array[Entry]]
    def prefix_search(query, nesting = nil)
      unless nesting
        results = @entries_tree.search(query)
        results.uniq!
        return results
      end

      results = nesting.length.downto(0).flat_map do |i|
        prefix = nesting[0...i] #: as !nil
          .join("::")
        namespaced_query = prefix.empty? ? query : "#{prefix}::#{query}"
        @entries_tree.search(namespaced_query)
      end

      results.uniq!
      results
    end

    # Fuzzy searches index entries based on Jaro-Winkler similarity. If no query is provided, all entries are returned
    #: (String? query) -> Array[Entry]
    def fuzzy_search(query)
      unless query
        entries = @entries.filter_map do |_name, entries|
          next if entries.first.is_a?(Entry::SingletonClass)

          entries
        end

        return entries.flatten
      end

      normalized_query = query.gsub("::", "").downcase

      results = @entries.filter_map do |name, entries|
        next if entries.first.is_a?(Entry::SingletonClass)

        similarity = DidYouMean::JaroWinkler.distance(name.gsub("::", "").downcase, normalized_query)
        [entries, -similarity] if similarity > ENTRY_SIMILARITY_THRESHOLD
      end
      results.sort_by!(&:last)
      results.flat_map(&:first)
    end

    #: (String? name, String receiver_name) -> Array[(Entry::Member | Entry::MethodAlias)]
    def method_completion_candidates(name, receiver_name)
      ancestors = linearized_ancestors_of(receiver_name)

      candidates = name ? prefix_search(name).flatten : @entries.values.flatten
      completion_items = candidates.each_with_object({}) do |entry, hash|
        unless entry.is_a?(Entry::Member) || entry.is_a?(Entry::MethodAlias) ||
            entry.is_a?(Entry::UnresolvedMethodAlias)
          next
        end

        entry_name = entry.name
        ancestor_index = ancestors.index(entry.owner&.name)
        existing_entry, existing_entry_index = hash[entry_name]

        # Conditions for matching a method completion candidate:
        # 1. If an ancestor_index was found, it means that this method is owned by the receiver. The exact index is
        # where in the ancestor chain the method was found. For example, if the ancestors are ["A", "B", "C"] and we
        # found the method declared in `B`, then the ancestors index is 1
        #
        # 2. We already established that this method is owned by the receiver. Now, check if we already added a
        # completion candidate for this method name. If not, then we just go and add it (the left hand side of the or)
        #
        # 3. If we had already found a method entry for the same name, then we need to check if the current entry that
        # we are comparing appears first in the hierarchy or not. For example, imagine we have the method `open` defined
        # in both `File` and its parent `IO`. If we first find the method `open` in `IO`, it will be inserted into the
        # hash. Then, when we find the entry for `open` owned by `File`, we need to replace `IO.open` by `File.open`,
        # since `File.open` appears first in the hierarchy chain and is therefore the correct method being invoked. The
        # last part of the conditional checks if the current entry was found earlier in the hierarchy chain, in which
        # case we must update the existing entry to avoid showing the wrong method declaration for overridden methods
        next unless ancestor_index && (!existing_entry || ancestor_index < existing_entry_index)

        if entry.is_a?(Entry::UnresolvedMethodAlias)
          resolved_alias = resolve_method_alias(entry, receiver_name, [])
          hash[entry_name] = [resolved_alias, ancestor_index] if resolved_alias.is_a?(Entry::MethodAlias)
        else
          hash[entry_name] = [entry, ancestor_index]
        end
      end

      completion_items.values.map!(&:first)
    end

    #: (String name, Array[String] nesting) -> Array[Array[(Entry::Constant | Entry::ConstantAlias | Entry::Namespace | Entry::UnresolvedConstantAlias)]]
    def constant_completion_candidates(name, nesting)
      # If we have a top level reference, then we don't need to include completions inside the current nesting
      if name.start_with?("::")
        return T.cast(
          @entries_tree.search(name.delete_prefix("::")),
          T::Array[T::Array[T.any(
            Entry::Constant,
            Entry::ConstantAlias,
            Entry::Namespace,
            Entry::UnresolvedConstantAlias,
          )]],
        )
      end

      # Otherwise, we have to include every possible constant the user might be referring to. This is essentially the
      # same algorithm as resolve, but instead of returning early we concatenate all unique results

      # Direct constants inside this namespace
      entries = @entries_tree.search(nesting.any? ? "#{nesting.join("::")}::#{name}" : name)

      # Constants defined in enclosing scopes
      nesting.length.downto(1) do |i|
        namespace = nesting[0...i] #: as !nil
          .join("::")
        entries.concat(@entries_tree.search("#{namespace}::#{name}"))
      end

      # Inherited constants
      if name.end_with?("::")
        entries.concat(inherited_constant_completion_candidates(nil, nesting + [name]))
      else
        entries.concat(inherited_constant_completion_candidates(name, nesting))
      end

      # Top level constants
      entries.concat(@entries_tree.search(name))
      entries.uniq!
      T.cast(
        entries,
        T::Array[T::Array[T.any(
          Entry::Constant,
          Entry::ConstantAlias,
          Entry::Namespace,
          Entry::UnresolvedConstantAlias,
        )]],
      )
    end

    # Resolve a constant to its declaration based on its name and the nesting where the reference was found. Parameter
    # documentation:
    #
    # name: the name of the reference how it was found in the source code (qualified or not)
    # nesting: the nesting structure where the reference was found (e.g.: ["Foo", "Bar"])
    # seen_names: this parameter should not be used by consumers of the api. It is used to avoid infinite recursion when
    # resolving circular references
    #: (String name, Array[String] nesting, ?Array[String] seen_names) -> Array[(Entry::Namespace | Entry::ConstantAlias | Entry::UnresolvedConstantAlias)]?
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
      direct_or_aliased_constant(name, seen_names)
    rescue UnresolvableAliasError
      nil
    end

    # Index all files for the given URIs, which defaults to what is configured. A block can be used to track and control
    # indexing progress. That block is invoked with the current progress percentage and should return `true` to continue
    # indexing or `false` to stop indexing.
    #: (?uris: Array[URI::Generic]) ?{ (Integer progress) -> bool } -> void
    def index_all(uris: @configuration.indexable_uris, &block)
      # When troubleshooting an indexing issue, e.g. through irb, it's not obvious that `index_all` will augment the
      # existing index values, meaning it may contain 'stale' entries. This check ensures that the user is aware of this
      # behavior and can take appropriate action.
      if @initial_indexing_completed
        raise IndexNotEmptyError,
          "The index is not empty. To prevent invalid entries, `index_all` can only be called once."
      end

      RBSIndexer.new(self).index_ruby_core
      # Calculate how many paths are worth 1% of progress
      progress_step = (uris.length / 100.0).ceil

      uris.each_with_index do |uri, index|
        if block && index % progress_step == 0
          progress = (index / progress_step) + 1
          break unless block.call(progress)
        end

        index_file(uri, collect_comments: false)
      end

      @initial_indexing_completed = true
    end

    #: (URI::Generic uri, String source, ?collect_comments: bool) -> void
    def index_single(uri, source, collect_comments: true)
      dispatcher = Prism::Dispatcher.new

      result = Prism.parse(source)
      listener = DeclarationListener.new(self, dispatcher, result, uri, collect_comments: collect_comments)
      dispatcher.dispatch(result.value)

      require_path = uri.require_path
      @require_paths_tree.insert(require_path, uri) if require_path

      indexing_errors = listener.indexing_errors.uniq
      indexing_errors.each { |error| $stderr.puts(error) } if indexing_errors.any?
    rescue SystemStackError => e
      if e.backtrace&.first&.include?("prism")
        $stderr.puts "Prism error indexing #{uri}: #{e.message}"
      else
        raise
      end
    end

    # Indexes a File URI by reading the contents from disk
    #: (URI::Generic uri, ?collect_comments: bool) -> void
    def index_file(uri, collect_comments: true)
      path = uri.full_path #: as !nil
      index_single(uri, File.read(path), collect_comments: collect_comments)
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
    #: (String name, ?Array[String] seen_names) -> String
    def follow_aliased_namespace(name, seen_names = [])
      parts = name.split("::")
      real_parts = []

      (parts.length - 1).downto(0) do |i|
        current_name = parts[0..i] #: as !nil
          .join("::")
        entry = @entries[current_name]&.first

        case entry
        when Entry::ConstantAlias
          target = entry.target
          return follow_aliased_namespace("#{target}::#{real_parts.join("::")}", seen_names)
        when Entry::UnresolvedConstantAlias
          resolved = resolve_alias(entry, seen_names)

          if resolved.is_a?(Entry::UnresolvedConstantAlias)
            raise UnresolvableAliasError, "The constant #{resolved.name} is an alias to a non existing constant"
          end

          target = resolved.target
          return follow_aliased_namespace("#{target}::#{real_parts.join("::")}", seen_names)
        else
          real_parts.unshift(
            parts[i], #: as !nil
          )
        end
      end

      real_parts.join("::")
    end

    # Attempts to find methods for a resolved fully qualified receiver name. Do not provide the `seen_names` parameter
    # as it is used only internally to prevent infinite loops when resolving circular aliases
    # Returns `nil` if the method does not exist on that receiver
    #: (String method_name, String receiver_name, ?Array[String] seen_names, ?inherited_only: bool) -> Array[(Entry::Member | Entry::MethodAlias)]?
    def resolve_method(method_name, receiver_name, seen_names = [], inherited_only: false)
      method_entries = self[method_name]
      return unless method_entries

      ancestors = linearized_ancestors_of(receiver_name.delete_prefix("::"))
      ancestors.each do |ancestor|
        next if inherited_only && ancestor == receiver_name

        found = method_entries.filter_map do |entry|
          case entry
          when Entry::Member, Entry::MethodAlias
            entry if entry.owner&.name == ancestor
          when Entry::UnresolvedMethodAlias
            # Resolve aliases lazily as we find them
            if entry.owner&.name == ancestor
              resolved_alias = resolve_method_alias(entry, receiver_name, seen_names)
              resolved_alias if resolved_alias.is_a?(Entry::MethodAlias)
            end
          end
        end

        return found if found.any?
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
    #: (String fully_qualified_name) -> Array[String]
    def linearized_ancestors_of(fully_qualified_name)
      # If we already computed the ancestors for this namespace, return it straight away
      cached_ancestors = @ancestors[fully_qualified_name]
      return cached_ancestors if cached_ancestors

      parts = fully_qualified_name.split("::")
      singleton_levels = 0

      parts.reverse_each do |part|
        break unless part.include?("<Class:")

        singleton_levels += 1
        parts.pop
      end

      attached_class_name = parts.join("::")

      # If we don't have an entry for `name`, raise
      entries = self[fully_qualified_name]

      if singleton_levels > 0 && !entries && indexed?(attached_class_name)
        entries = [existing_or_new_singleton_class(attached_class_name)]
      end

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
        when Entry::ConstantAlias
          self[entry.target]&.grep(Entry::Namespace)
        end
      end.flatten

      raise NonExistingNamespaceError,
        "None of the entries for #{fully_qualified_name} are modules or classes" if namespaces.empty?

      # The original nesting where we discovered this namespace, so that we resolve the correct names of the
      # included/prepended/extended modules and parent classes
      nesting = namespaces.first #: as !nil
        .nesting.flat_map { |n| n.split("::") }

      if nesting.any?
        singleton_levels.times do
          nesting << "<Class:#{nesting.last}>"
        end
      end

      # We only need to run included hooks when linearizing singleton classes. Included hooks are typically used to add
      # new singleton methods or to extend a module through an include. There's no need to support instance methods, the
      # inclusion of another module or the prepending of another module, because those features are already a part of
      # Ruby and can be used directly without any metaprogramming
      run_included_hooks(attached_class_name, nesting) if singleton_levels > 0

      linearize_mixins(ancestors, namespaces, nesting)
      linearize_superclass(
        ancestors,
        attached_class_name,
        fully_qualified_name,
        namespaces,
        nesting,
        singleton_levels,
      )

      ancestors
    end

    # Resolves an instance variable name for a given owner name. This method will linearize the ancestors of the owner
    # and find inherited instance variables as well
    #: (String variable_name, String owner_name) -> Array[Entry::InstanceVariable]?
    def resolve_instance_variable(variable_name, owner_name)
      entries = T.cast(self[variable_name], T.nilable(T::Array[Entry::InstanceVariable]))
      return unless entries

      ancestors = linearized_ancestors_of(owner_name)
      return if ancestors.empty?

      entries.select { |e| ancestors.include?(e.owner&.name) }
    end

    #: (String variable_name, String owner_name) -> Array[Entry::ClassVariable]?
    def resolve_class_variable(variable_name, owner_name)
      entries = self[variable_name]&.grep(Entry::ClassVariable)
      return unless entries&.any?

      ancestors = linearized_attached_ancestors(owner_name)
      return if ancestors.empty?

      entries.select { |e| ancestors.include?(e.owner&.name) }
    end

    # Returns a list of possible candidates for completion of instance variables for a given owner name. The name must
    # include the `@` prefix
    #: (String name, String owner_name) -> Array[(Entry::InstanceVariable | Entry::ClassVariable)]
    def instance_variable_completion_candidates(name, owner_name)
      entries = T.cast(prefix_search(name).flatten, T::Array[T.any(Entry::InstanceVariable, Entry::ClassVariable)])
      # Avoid wasting time linearizing ancestors if we didn't find anything
      return entries if entries.empty?

      ancestors = linearized_ancestors_of(owner_name)

      instance_variables, class_variables = entries.partition { |e| e.is_a?(Entry::InstanceVariable) }
      variables = instance_variables.select { |e| ancestors.any?(e.owner&.name) }

      # Class variables are only owned by the attached class in our representation. If the owner is in a singleton
      # context, we have to search for ancestors of the attached class
      if class_variables.any?
        name_parts = owner_name.split("::")

        if name_parts.last&.start_with?("<Class:")
          attached_name = name_parts[0..-2] #: as !nil
            .join("::")
          attached_ancestors = linearized_ancestors_of(attached_name)
          variables.concat(class_variables.select { |e| attached_ancestors.any?(e.owner&.name) })
        else
          variables.concat(class_variables.select { |e| ancestors.any?(e.owner&.name) })
        end
      end

      variables.uniq!(&:name)
      variables
    end

    #: (String name, String owner_name) -> Array[Entry::ClassVariable]
    def class_variable_completion_candidates(name, owner_name)
      entries = T.cast(prefix_search(name).flatten, T::Array[Entry::ClassVariable])
      # Avoid wasting time linearizing ancestors if we didn't find anything
      return entries if entries.empty?

      ancestors = linearized_attached_ancestors(owner_name)
      variables = entries.select { |e| ancestors.any?(e.owner&.name) }
      variables.uniq!(&:name)
      variables
    end

    # Synchronizes a change made to the given URI. This method will ensure that new declarations are indexed, removed
    # declarations removed and that the ancestor linearization cache is cleared if necessary. If a block is passed, the
    # consumer of this API has to handle deleting and inserting/updating entries in the index instead of passing the
    # document's source (used to handle unsaved changes to files)
    #: (URI::Generic uri, ?String? source) ?{ (Index index) -> void } -> void
    def handle_change(uri, source = nil, &block)
      key = uri.to_s
      original_entries = @uris_to_entries[key]

      if block
        block.call(self)
      else
        delete(uri)
        index_single(
          uri,
          source, #: as !nil
        )
      end

      updated_entries = @uris_to_entries[key]
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

    #: -> bool
    def empty?
      @entries.empty?
    end

    #: -> Array[String]
    def names
      @entries.keys
    end

    #: (String name) -> bool
    def indexed?(name)
      @entries.key?(name)
    end

    #: -> Integer
    def length
      @entries.count
    end

    #: (String name) -> Entry::SingletonClass
    def existing_or_new_singleton_class(name)
      *_namespace, unqualified_name = name.split("::")
      full_singleton_name = "#{name}::<Class:#{unqualified_name}>"
      singleton = T.cast(self[full_singleton_name]&.first, T.nilable(Entry::SingletonClass))

      unless singleton
        attached_ancestor = self[name]&.first #: as !nil

        singleton = Entry::SingletonClass.new(
          [full_singleton_name],
          attached_ancestor.uri,
          attached_ancestor.location,
          attached_ancestor.name_location,
          nil,
          nil,
        )
        add(singleton, skip_prefix_tree: true)
      end

      singleton
    end

    #: [T] (String uri, ?Class[(T & Entry)]? type) -> (Array[Entry] | Array[T])?
    def entries_for(uri, type = nil)
      entries = @uris_to_entries[uri.to_s]
      return entries unless type

      entries&.grep(type)
    end

    private

    # Always returns the linearized ancestors for the attached class, regardless of whether `name` refers to a singleton
    # or attached namespace
    #: (String name) -> Array[String]
    def linearized_attached_ancestors(name)
      name_parts = name.split("::")

      if name_parts.last&.start_with?("<Class:")
        attached_name = name_parts[0..-2] #: as !nil
          .join("::")
        linearized_ancestors_of(attached_name)
      else
        linearized_ancestors_of(name)
      end
    end

    # Runs the registered included hooks
    #: (String fully_qualified_name, Array[String] nesting) -> void
    def run_included_hooks(fully_qualified_name, nesting)
      return if @included_hooks.empty?

      namespaces = self[fully_qualified_name]&.grep(Entry::Namespace)
      return unless namespaces

      namespaces.each do |namespace|
        namespace.mixin_operations.each do |operation|
          next unless operation.is_a?(Entry::Include)

          # First we resolve the include name, so that we know the actual module being referred to in the include
          resolved_modules = resolve(operation.module_name, nesting)
          next unless resolved_modules

          module_name = resolved_modules.first #: as !nil
            .name

          # Then we grab any hooks registered for that module
          hooks = @included_hooks[module_name]
          next unless hooks

          # We invoke the hooks with the index and the namespace that included the module
          hooks.each { |hook| hook.call(self, namespace) }
        end
      end
    end

    # Linearize mixins for an array of namespace entries. This method will mutate the `ancestors` array with the
    # linearized ancestors of the mixins
    #: (Array[String] ancestors, Array[Entry::Namespace] namespace_entries, Array[String] nesting) -> void
    def linearize_mixins(ancestors, namespace_entries, nesting)
      mixin_operations = namespace_entries.flat_map(&:mixin_operations)
      main_namespace_index = 0

      mixin_operations.each do |operation|
        resolved_module = resolve(operation.module_name, nesting)
        next unless resolved_module

        module_fully_qualified_name = resolved_module.first #: as !nil
          .name

        case operation
        when Entry::Prepend
          # When a module is prepended, Ruby checks if it hasn't been prepended already to prevent adding it in front of
          # the actual namespace twice. However, it does not check if it has been included because you are allowed to
          # prepend the same module after it has already been included
          linearized_prepends = linearized_ancestors_of(module_fully_qualified_name)

          # When there are duplicate prepended modules, we have to insert the new prepends after the existing ones. For
          # example, if the current ancestors are `["A", "Foo"]` and we try to prepend `["A", "B"]`, then `"B"` has to
          # be inserted after `"A`
          prepended_ancestors = ancestors[0...main_namespace_index] #: as !nil
          uniq_prepends = linearized_prepends - prepended_ancestors
          insert_position = linearized_prepends.length - uniq_prepends.length

          ancestors #: as untyped
            .insert(insert_position, *uniq_prepends)

          main_namespace_index += linearized_prepends.length
        when Entry::Include
          # When including a module, Ruby will always prevent duplicate entries in case the module has already been
          # prepended or included
          linearized_includes = linearized_ancestors_of(module_fully_qualified_name)
          ancestors #: as untyped
            .insert(main_namespace_index + 1, *(linearized_includes - ancestors))
        end
      end
    end

    # Linearize the superclass of a given namespace (including modules with the implicit `Module` superclass). This
    # method will mutate the `ancestors` array with the linearized ancestors of the superclass
    #: (Array[String] ancestors, String attached_class_name, String fully_qualified_name, Array[Entry::Namespace] namespace_entries, Array[String] nesting, Integer singleton_levels) -> void
    def linearize_superclass( # rubocop:disable Metrics/ParameterLists
      ancestors,
      attached_class_name,
      fully_qualified_name,
      namespace_entries,
      nesting,
      singleton_levels
    )
      # Find the first class entry that has a parent class. Notice that if the developer makes a mistake and inherits
      # from two different classes in different files, we simply ignore it
      superclass = T.cast(
        if singleton_levels > 0
          self[attached_class_name]&.find { |n| n.is_a?(Entry::Class) && n.parent_class }
        else
          namespace_entries.find { |n| n.is_a?(Entry::Class) && n.parent_class }
        end,
        T.nilable(Entry::Class),
      )

      if superclass
        # If the user makes a mistake and creates a class that inherits from itself, this method would throw a stack
        # error. We need to ensure that this isn't the case
        parent_class = superclass.parent_class #: as !nil

        resolved_parent_class = resolve(parent_class, nesting)
        parent_class_name = resolved_parent_class&.first&.name

        if parent_class_name && fully_qualified_name != parent_class_name

          parent_name_parts = parent_class_name.split("::")
          singleton_levels.times do
            parent_name_parts << "<Class:#{parent_name_parts.last}>"
          end

          ancestors.concat(linearized_ancestors_of(parent_name_parts.join("::")))
        end

        # When computing the linearization for a class's singleton class, it inherits from the linearized ancestors of
        # the `Class` class
        if parent_class_name&.start_with?("BasicObject") && singleton_levels > 0
          class_class_name_parts = ["Class"]

          (singleton_levels - 1).times do
            class_class_name_parts << "<Class:#{class_class_name_parts.last}>"
          end

          ancestors.concat(linearized_ancestors_of(class_class_name_parts.join("::")))
        end
      elsif singleton_levels > 0
        # When computing the linearization for a module's singleton class, it inherits from the linearized ancestors of
        # the `Module` class
        mod = T.cast(self[attached_class_name]&.find { |n| n.is_a?(Entry::Module) }, T.nilable(Entry::Module))

        if mod
          module_class_name_parts = ["Module"]

          (singleton_levels - 1).times do
            module_class_name_parts << "<Class:#{module_class_name_parts.last}>"
          end

          ancestors.concat(linearized_ancestors_of(module_class_name_parts.join("::")))
        end
      end
    end

    # Attempts to resolve an UnresolvedAlias into a resolved Alias. If the unresolved alias is pointing to a constant
    # that doesn't exist, then we return the same UnresolvedAlias
    #: (Entry::UnresolvedConstantAlias entry, Array[String] seen_names) -> (Entry::ConstantAlias | Entry::UnresolvedConstantAlias)
    def resolve_alias(entry, seen_names)
      alias_name = entry.name
      return entry if seen_names.include?(alias_name)

      seen_names << alias_name

      target = resolve(entry.target, entry.nesting, seen_names)
      return entry unless target

      target_name = target.first #: as !nil
        .name
      resolved_alias = Entry::ConstantAlias.new(target_name, entry)

      # Replace the UnresolvedAlias by a resolved one so that we don't have to do this again later
      original_entries = @entries[alias_name] #: as !nil
      original_entries.delete(entry)
      original_entries << resolved_alias

      @entries_tree.insert(alias_name, original_entries)

      resolved_alias
    end

    #: (String name, Array[String] nesting, Array[String] seen_names) -> Array[(Entry::Namespace | Entry::ConstantAlias | Entry::UnresolvedConstantAlias)]?
    def lookup_enclosing_scopes(name, nesting, seen_names)
      nesting.length.downto(1) do |i|
        namespace = nesting[0...i] #: as !nil
          .join("::")

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

    #: (String name, Array[String] nesting, Array[String] seen_names) -> Array[(Entry::Namespace | Entry::ConstantAlias | Entry::UnresolvedConstantAlias)]?
    def lookup_ancestor_chain(name, nesting, seen_names)
      *nesting_parts, constant_name = build_non_redundant_full_name(name, nesting).split("::")
      return if nesting_parts.empty?

      namespace_entries = resolve(nesting_parts.join("::"), [], seen_names)
      return unless namespace_entries

      namespace_name = namespace_entries.first #: as !nil
        .name
      ancestors = nesting_parts.empty? ? [] : linearized_ancestors_of(namespace_name)

      ancestors.each do |ancestor_name|
        entries = direct_or_aliased_constant("#{ancestor_name}::#{constant_name}", seen_names)
        return entries if entries
      end

      nil
    rescue NonExistingNamespaceError
      nil
    end

    #: (String? name, Array[String] nesting) -> Array[Array[(Entry::Namespace | Entry::ConstantAlias | Entry::UnresolvedConstantAlias | Entry::Constant)]]
    def inherited_constant_completion_candidates(name, nesting)
      namespace_entries = if name
        *nesting_parts, constant_name = build_non_redundant_full_name(name, nesting).split("::")
        return [] if nesting_parts.empty?

        resolve(nesting_parts.join("::"), [])
      else
        resolve(nesting.join("::"), [])
      end
      return [] unless namespace_entries

      namespace_name = namespace_entries.first #: as !nil
        .name
      ancestors = linearized_ancestors_of(namespace_name)
      candidates = ancestors.flat_map do |ancestor_name|
        @entries_tree.search("#{ancestor_name}::#{constant_name}")
      end

      # For candidates with the same name, we must only show the first entry in the inheritance chain, since that's the
      # one the user will be referring to in completion
      completion_items = candidates.each_with_object({}) do |entries, hash|
        *parts, short_name = entries.first #: as !nil
          .name.split("::")
        namespace_name = parts.join("::")
        ancestor_index = ancestors.index(namespace_name)
        existing_entry, existing_entry_index = hash[short_name]

        next unless ancestor_index && (!existing_entry || ancestor_index < existing_entry_index)

        hash[short_name] = [entries, ancestor_index]
      end

      completion_items.values.map!(&:first)
    rescue NonExistingNamespaceError
      []
    end

    # Removes redundancy from a constant reference's full name. For example, if we find a reference to `A::B::Foo`
    # inside of the ["A", "B"] nesting, then we should not concatenate the nesting with the name or else we'll end up
    # with `A::B::A::B::Foo`. This method will remove any redundant parts from the final name based on the reference and
    # the nesting
    #: (String name, Array[String] nesting) -> String
    def build_non_redundant_full_name(name, nesting)
      # If there's no nesting, then we can just return the name as is
      return name if nesting.empty?

      # If the name is not qualified, we can just concatenate the nesting and the name
      return "#{nesting.join("::")}::#{name}" unless name.include?("::")

      name_parts = name.split("::")
      first_redundant_part = nesting.index(name_parts[0])

      # If there are no redundant parts between the name and the nesting, then the full name is both combined
      return "#{nesting.join("::")}::#{name}" unless first_redundant_part

      # Otherwise, push all of the leading parts of the nesting that aren't redundant into the name. For example, if we
      # have a reference to `Foo::Bar` inside the `[Namespace, Foo]` nesting, then only the `Foo` part is redundant, but
      # we still need to include the `Namespace` part
      T.unsafe(name_parts).unshift(*nesting[0...first_redundant_part])
      name_parts.join("::")
    end

    #: (String full_name, Array[String] seen_names) -> Array[(Entry::Namespace | Entry::ConstantAlias | Entry::UnresolvedConstantAlias)]?
    def direct_or_aliased_constant(full_name, seen_names)
      entries = @entries[full_name] || @entries[follow_aliased_namespace(full_name)]

      T.cast(
        entries&.map { |e| e.is_a?(Entry::UnresolvedConstantAlias) ? resolve_alias(e, seen_names) : e },
        T.nilable(T::Array[T.any(
          Entry::Namespace,
          Entry::ConstantAlias,
          Entry::UnresolvedConstantAlias,
        )]),
      )
    end

    # Attempt to resolve a given unresolved method alias. This method returns the resolved alias if we managed to
    # identify the target or the same unresolved alias entry if we couldn't
    #: (Entry::UnresolvedMethodAlias entry, String receiver_name, Array[String] seen_names) -> (Entry::MethodAlias | Entry::UnresolvedMethodAlias)
    def resolve_method_alias(entry, receiver_name, seen_names)
      new_name = entry.new_name
      return entry if new_name == entry.old_name
      return entry if seen_names.include?(new_name)

      seen_names << new_name

      target_method_entries = resolve_method(entry.old_name, receiver_name, seen_names)
      return entry unless target_method_entries

      resolved_alias = Entry::MethodAlias.new(
        target_method_entries.first, #: as !nil
        entry,
      )
      original_entries = @entries[new_name] #: as !nil
      original_entries.delete(entry)
      original_entries << resolved_alias
      resolved_alias
    end
  end
end
