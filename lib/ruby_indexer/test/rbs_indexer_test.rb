# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class RBSIndexerTest < TestCase
    def test_index_core_classes
      entries = @index["Array"] #: as !nil
      refute_nil(entries)
      # Array is a class but also an instance method on Kernel
      assert_equal(2, entries.length)
      entry = entries.find { |entry| entry.is_a?(Entry::Class) } #: as Entry::Class
      assert_match(%r{/gems/rbs-.*/core/array.rbs}, entry.file_path)
      assert_equal("array.rbs", entry.file_name)
      assert_equal("Object", entry.parent_class)
      assert_equal(1, entry.mixin_operations.length)
      enumerable_include = entry.mixin_operations.first #: as !nil
      assert_equal("Enumerable", enumerable_include.module_name)

      # Using fixed positions would be fragile, so let's just check some basics.
      assert_operator(entry.location.start_line, :>, 0)
      assert_operator(entry.location.end_line, :>, entry.location.start_line)
      assert_equal(0, entry.location.start_column)
      assert_operator(entry.location.end_column, :>, 0)
    end

    def test_index_core_modules
      entries = @index["Kernel"] #: as !nil
      refute_nil(entries)
      assert_equal(2, entries.length)
      entry = entries.first #: as Entry::Module
      assert_match(%r{/gems/rbs-.*/core/kernel.rbs}, entry.file_path)
      assert_equal("kernel.rbs", entry.file_name)

      # Using fixed positions would be fragile, so let's just check some basics.
      assert_operator(entry.location.start_line, :>, 0)
      assert_operator(entry.location.end_line, :>, entry.location.start_line)
      assert_equal(0, entry.location.start_column)
      assert_operator(entry.location.end_column, :>, 0)
    end

    def test_index_core_constants
      entries = @index["RUBY_VERSION"] #: as !nil
      refute_nil(entries)
      assert_equal(1, entries.length)

      entries = @index["Complex::I"] #: as !nil
      refute_nil(entries)
      assert_equal(1, entries.length)

      entries = @index["Encoding::US_ASCII"] #: as !nil
      refute_nil(entries)
      assert_equal(1, entries.length)
    end

    def test_index_methods
      entries = @index["initialize"] #: as Array[Entry::Method]
      refute_nil(entries)
      entry = entries.find { |entry| entry.owner&.name == "Array" } #: as Entry::Method
      assert_match(%r{/gems/rbs-.*/core/array.rbs}, entry.file_path)
      assert_equal("array.rbs", entry.file_name)
      assert_equal(:public, entry.visibility)

      # Using fixed positions would be fragile, so let's just check some basics.
      assert_operator(entry.location.start_line, :>, 0)
      assert_operator(entry.location.end_line, :>, entry.location.start_line)
      assert_equal(2, entry.location.start_column)
      assert_operator(entry.location.end_column, :>, 0)
    end

    def test_index_global_declaration
      entries = @index["$DEBUG"] #: as Array[Entry::GlobalVariable]
      refute_nil(entries)
      assert_equal(1, entries.length)

      entry = entries.first #: as Entry::GlobalVariable

      assert_instance_of(Entry::GlobalVariable, entry)
      assert_equal("$DEBUG", entry.name)
      assert_match(%r{/gems/rbs-.*/core/global_variables.rbs}, entry.file_path)
      assert_operator(entry.location.start_column, :<, entry.location.end_column)
      assert_equal(entry.location.start_line, entry.location.end_line)
    end

    def test_attaches_correct_owner_to_singleton_methods
      entries = @index["basename"] #: as Array[Entry::Method]
      refute_nil(entries)

      owner = entries.first&.owner #: as Entry::SingletonClass
      assert_instance_of(Entry::SingletonClass, owner)
      assert_equal("File::<Class:File>", owner.name)
    end

    def test_location_and_name_location_are_the_same
      # NOTE: RBS does not store the name location for classes, modules or methods. This behavior is not exactly what
      # we would like, but for now we assign the same location to both

      entries = @index["Array"] #: as Array[Entry::Class]
      refute_nil(entries)
      entry = entries.find { |entry| entry.is_a?(Entry::Class) } #: as Entry::Class

      assert_same(entry.location, entry.name_location)
    end

    def test_rbs_method_with_required_positionals
      entries = @index["crypt"] #: as Array[Entry::Method]
      assert_equal(1, entries.length)

      entry = entries.first #: as Entry::Method
      signatures = entry.signatures
      assert_equal(1, signatures.length)

      first_signature = signatures.first #: as Entry::Signature

      # (::string salt_str) -> ::String

      assert_equal(1, first_signature.parameters.length)
      assert_kind_of(Entry::RequiredParameter, first_signature.parameters[0])
      assert_equal(:salt_str, first_signature.parameters[0]&.name)
    end

    def test_rbs_method_with_unnamed_required_positionals
      entries = @index["try_convert"] #: as Array[Entry::Method]
      entry = entries.find { |entry| entry.owner&.name == "Array::<Class:Array>" } #: as Entry::Method

      parameters = entry.signatures[0]&.parameters #: as Array[Entry::Parameter]

      assert_equal([:arg0], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
    end

    def test_rbs_method_with_optional_positionals
      entries = @index["polar"] #: as Array[Entry::Method]
      entry = entries.find { |entry| entry.owner&.name == "Complex::<Class:Complex>" } #: as Entry::Method

      # def self.polar: (Numeric, ?Numeric) -> Complex

      parameters = entry.signatures[0]&.parameters #: as Array[Entry::Parameter]

      assert_equal([:arg0, :arg1], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
    end

    def test_rbs_method_with_optional_parameter
      entries = @index["chomp"] #: as Array[Entry::Method]
      assert_equal(1, entries.length)

      entry = entries.first #: as Entry::Method
      signatures = entry.signatures
      assert_equal(1, signatures.length)

      first_signature = signatures.first #: as Entry::Signature

      # (?::string? separator) -> ::String

      assert_equal(1, first_signature.parameters.length)
      assert_kind_of(Entry::OptionalParameter, first_signature.parameters[0])
      assert_equal(:separator, first_signature.parameters[0]&.name)
    end

    def test_rbs_method_with_required_and_optional_parameters
      entries = @index["gsub"] #: as Array[Entry::Method]
      assert_equal(1, entries.length)

      entry = entries.first #: as Entry::Method

      signatures = entry.signatures
      assert_equal(3, signatures.length)

      # (::Regexp | ::string pattern, ::string | ::hash[::String, ::_ToS] replacement) -> ::String
      # | (::Regexp | ::string pattern) -> ::Enumerator[::String, ::String]
      # | (::Regexp | ::string pattern) { (::String match) -> ::_ToS } -> ::String

      parameters = signatures[0]&.parameters #: as !nil
      assert_equal([:pattern, :replacement], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::RequiredParameter, parameters[1])

      parameters = signatures[1]&.parameters #: as !nil
      assert_equal([:pattern], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])

      parameters = signatures[2]&.parameters #: as !nil
      assert_equal([:pattern, :"<anonymous block>"], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::BlockParameter, parameters[1])
    end

    def test_rbs_anonymous_block_parameter
      entries = @index["open"] #: as Array[Entry::Method]
      entry = entries.find { |entry| entry.owner&.name == "File::<Class:File>" } #: as Entry::Method

      assert_equal(2, entry.signatures.length)

      # (::String name, ?::String mode, ?::Integer perm) -> ::IO?
      # | [T] (::String name, ?::String mode, ?::Integer perm) { (::IO) -> T } -> T

      parameters = entry.signatures[0]&.parameters #: as !nil
      assert_equal([:file_name, :mode, :perm], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::OptionalParameter, parameters[2])

      parameters = entry.signatures[1]&.parameters #: as !nil
      assert_equal([:file_name, :mode, :perm, :"<anonymous block>"], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::OptionalParameter, parameters[2])
      assert_kind_of(Entry::BlockParameter, parameters[3])
    end

    def test_rbs_method_with_rest_positionals
      entries = @index["count"] #: as Array[Entry::Method]
      entry = entries.find { |entry| entry.owner&.name == "String" } #: as Entry::Method

      parameters = entry.signatures.first&.parameters #: as !nil
      assert_equal(1, entry.signatures.length)

      # (::String::selector selector_0, *::String::selector more_selectors) -> ::Integer

      assert_equal([:selector_0, :more_selectors], parameters.map(&:name))
      assert_kind_of(RubyIndexer::Entry::RequiredParameter, parameters[0])
      assert_kind_of(RubyIndexer::Entry::RestParameter, parameters[1])
    end

    def test_rbs_method_with_trailing_positionals
      entries = @index["select"] #: as Array[Entry::Method]
      entry = entries.find { |entry| entry.owner&.name == "IO::<Class:IO>" } #: as !nil

      signatures = entry.signatures
      assert_equal(2, signatures.length)

      # def self.select: [X, Y, Z] (::Array[X & io]? read_array, ?::Array[Y & io]? write_array, ?::Array[Z & io]? error_array) -> [ Array[X], Array[Y], Array[Z] ]
      #   | [X, Y, Z] (::Array[X & io]? read_array, ?::Array[Y & io]? write_array, ?::Array[Z & io]? error_array, Time::_Timeout? timeout) -> [ Array[X], Array[Y], Array[Z] ]?

      parameters = signatures[0]&.parameters #: as !nil
      assert_equal([:read_array, :write_array, :error_array], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::OptionalParameter, parameters[2])

      parameters = signatures[1]&.parameters #: as !nil
      assert_equal([:read_array, :write_array, :error_array, :timeout], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::OptionalParameter, parameters[2])
      assert_kind_of(Entry::OptionalParameter, parameters[3])
    end

    def test_rbs_method_with_optional_keywords
      entries = @index["step"] #: as Array[Entry::Method]
      entry = entries.find { |entry| entry.owner&.name == "Numeric" } #: as !nil

      signatures = entry.signatures
      assert_equal(4, signatures.length)

      # (?::Numeric limit, ?::Numeric step) { (::Numeric) -> void } -> self
      # | (?::Numeric limit, ?::Numeric step) -> ::Enumerator[::Numeric, self]
      # | (?by: ::Numeric, ?to: ::Numeric) { (::Numeric) -> void } -> self
      # | (?by: ::Numeric, ?to: ::Numeric) -> ::Enumerator[::Numeric, self]

      parameters = signatures[0]&.parameters #: as !nil
      assert_equal([:limit, :step, :"<anonymous block>"], parameters.map(&:name))
      assert_kind_of(Entry::OptionalParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::BlockParameter, parameters[2])

      parameters = signatures[1]&.parameters #: as !nil
      assert_equal([:limit, :step], parameters.map(&:name))
      assert_kind_of(Entry::OptionalParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])

      parameters = signatures[2]&.parameters #: as !nil
      assert_equal([:by, :to, :"<anonymous block>"], parameters.map(&:name))
      assert_kind_of(Entry::OptionalKeywordParameter, parameters[0])
      assert_kind_of(Entry::OptionalKeywordParameter, parameters[1])
      assert_kind_of(Entry::BlockParameter, parameters[2])

      parameters = signatures[3]&.parameters #: as !nil
      assert_equal([:by, :to], parameters.map(&:name))
      assert_kind_of(Entry::OptionalKeywordParameter, parameters[0])
      assert_kind_of(Entry::OptionalKeywordParameter, parameters[1])
    end

    def test_rbs_method_with_required_keywords
      # There are no methods in Core that have required keyword arguments,
      # so we test against RBS directly

      rbs = <<~RBS
        class File
          def foo: (a: ::Numeric sz, b: ::Numeric) -> void
        end
      RBS
      signatures = parse_rbs_methods(rbs, "foo")
      parameters = signatures[0].parameters
      assert_equal([:a, :b], parameters.map(&:name))
      assert_kind_of(Entry::KeywordParameter, parameters[0])
      assert_kind_of(Entry::KeywordParameter, parameters[1])
    end

    def test_rbs_method_with_rest_keywords
      entries = @index["method_missing"] #: as Array[Entry::Method]
      entry = entries.find { |entry| entry.owner&.name == "BasicObject" } #: as !nil
      signatures = entry.signatures
      assert_equal(1, signatures.length)

      # (Symbol, *untyped, **untyped) ?{ (*untyped, **untyped) -> untyped } -> untyped

      parameters = signatures[0]&.parameters #: as !nil
      assert_equal([:arg0, :"<anonymous splat>", :"<anonymous keyword splat>"], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::RestParameter, parameters[1])
      assert_kind_of(Entry::KeywordRestParameter, parameters[2])
    end

    def test_parse_simple_rbs
      rbs = <<~RBS
        class File
          def self?.open: (String name, ?String mode, ?Integer perm) -> IO?
              | [T] (String name, ?String mode, ?Integer perm) { (IO) -> T } -> T
        end
      RBS
      signatures = parse_rbs_methods(rbs, "open")
      assert_equal(2, signatures.length)
      parameters = signatures[0].parameters
      assert_equal([:name, :mode, :perm], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::OptionalParameter, parameters[2])

      parameters = signatures[1].parameters
      assert_equal([:name, :mode, :perm, :"<anonymous block>"], parameters.map(&:name))
      assert_kind_of(Entry::RequiredParameter, parameters[0])
      assert_kind_of(Entry::OptionalParameter, parameters[1])
      assert_kind_of(Entry::OptionalParameter, parameters[2])
      assert_kind_of(Entry::BlockParameter, parameters[3])
    end

    def test_signature_alias
      # In RBS, an alias means that two methods have the same signature.
      # It does not mean the same thing as a Ruby alias.
      any_entries = @index["any?"] #: as Array[Entry::UnresolvedMethodAlias]

      assert_equal(["Array", "Enumerable", "Hash"], any_entries.map { _1.owner&.name })

      entry = any_entries.find { |entry| entry.owner&.name == "Array" } #: as !nil

      assert_kind_of(RubyIndexer::Entry::UnresolvedMethodAlias, entry)
      assert_equal("any?", entry.name)
      assert_equal("all?", entry.old_name)
      assert_equal("Array", entry.owner&.name)
      assert(entry.file_path&.end_with?("core/array.rbs"))
      refute_empty(entry.comments)
    end

    def test_indexing_untyped_functions
      entries = @index.resolve_method("call", "Method") #: as Array[Entry::Method]

      parameters = entries.first&.signatures&.first&.parameters #: as !nil
      assert_equal(1, parameters.length)
      assert_instance_of(Entry::ForwardingParameter, parameters.first)
    end

    private

    def parse_rbs_methods(rbs, method_name)
      buffer = RBS::Buffer.new(content: rbs, name: "")
      _, _, declarations = RBS::Parser.parse_signature(buffer)
      index = RubyIndexer::Index.new
      indexer = RubyIndexer::RBSIndexer.new(index)
      pathname = Pathname.new("/file.rbs")
      indexer.process_signature(pathname, declarations)
      entry = index[method_name] #: as !nil
        .first #: as Entry::Method

      entry.signatures
    end
  end
end
