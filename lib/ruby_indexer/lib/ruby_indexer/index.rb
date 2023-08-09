# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Index
    extend T::Sig

    sig { returns(T::Hash[String, T::Array[Entry]]) }
    attr_reader :entries

    sig { void }
    def initialize
      # Holds all entries in the index using the following format:
      # {
      #  "Foo" => [#<Entry::Class>, #<Entry::Class>],
      #  "Foo::Bar" => [#<Entry::Class>],
      # }
      @entries = T.let({}, T::Hash[String, T::Array[Entry]])

      # Holds references to where entries where discovered so that we can easily delete them
      # {
      #  "/my/project/foo.rb" => ["Foo"],
      #  "/my/project/bar.rb" => ["Foo::Bar"],
      # }
      @files_to_entries = T.let({}, T::Hash[String, T::Array[String]])
    end

    sig { params(path: String).void }
    def delete(path)
      # For each constant discovered in `path`, delete the associated entry from the index. If there are no entries
      # left, delete the constant from the index.
      @files_to_entries[path]&.each do |fully_qualified_name|
        entries = @entries[fully_qualified_name]
        next unless entries

        entries.reject! { |entry| entry.file_path == path }
        @entries.delete(fully_qualified_name) if entries.empty?
      end

      @files_to_entries.delete(path)
    end

    sig { params(entry: Entry).void }
    def <<(entry)
      (@entries[entry.name] ||= []) << entry
      (@files_to_entries[entry.file_path] ||= []) << entry.name
    end

    sig { params(fully_qualified_name: String).returns(T.nilable(T::Array[Entry])) }
    def [](fully_qualified_name)
      @entries[fully_qualified_name]
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

    sig { void }
    def clear
      @entries.clear
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

      class Module < Entry
        sig { returns(String) }
        def short_name
          T.must(@name.split("::").last)
        end
      end

      class Class < Module
      end
    end
  end
end
