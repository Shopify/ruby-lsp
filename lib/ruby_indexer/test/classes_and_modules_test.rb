# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class ClassesAndModulesTest < TestCase
    def test_empty_statements_class
      index(<<~RUBY)
        class Foo
        end
      RUBY

      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_conditional_class
      index(<<~RUBY)
        class Foo
        end if condition
      RUBY

      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_class_with_statements
      index(<<~RUBY)
        class Foo
          def something; end
        end
      RUBY

      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:2-3")
    end

    def test_colon_colon_class
      index(<<~RUBY)
        class ::Foo
        end
      RUBY

      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_colon_colon_class_inside_class
      index(<<~RUBY)
        class Bar
          class ::Foo
          end
        end
      RUBY

      assert_entry("Bar", Entry::Class, "/fake/path/foo.rb:0-0:3-3")
      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:1-2:2-5")
    end

    def test_namespaced_class
      index(<<~RUBY)
        class Foo::Bar
        end
      RUBY

      assert_entry("Foo::Bar", Entry::Class, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_dynamically_namespaced_class
      index(<<~RUBY)
        class self::Bar
        end
      RUBY

      assert_entry("self::Bar", Entry::Class, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_dynamically_namespaced_class_does_not_affect_other_classes
      index(<<~RUBY)
        class Foo
          class self::Bar
          end

          class Bar
          end
        end
      RUBY

      refute_entry("self::Bar")
      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:6-3")
      assert_entry("Foo::Bar", Entry::Class, "/fake/path/foo.rb:4-2:5-5")
    end

    def test_empty_statements_module
      index(<<~RUBY)
        module Foo
        end
      RUBY

      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_conditional_module
      index(<<~RUBY)
        module Foo
        end if condition
      RUBY

      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_module_with_statements
      index(<<~RUBY)
        module Foo
          def something; end
        end
      RUBY

      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:2-3")
    end

    def test_colon_colon_module
      index(<<~RUBY)
        module ::Foo
        end
      RUBY

      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_namespaced_module
      index(<<~RUBY)
        module Foo::Bar
        end
      RUBY

      assert_entry("Foo::Bar", Entry::Module, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_dynamically_namespaced_module
      index(<<~RUBY)
        module self::Bar
        end
      RUBY

      assert_entry("self::Bar", Entry::Module, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_dynamically_namespaced_module_does_not_affect_other_modules
      index(<<~RUBY)
        module Foo
          class self::Bar
          end

          module Bar
          end
        end
      RUBY

      assert_entry("Foo::self::Bar", Entry::Class, "/fake/path/foo.rb:1-2:2-5")
      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:6-3")
      assert_entry("Foo::Bar", Entry::Module, "/fake/path/foo.rb:4-2:5-5")
    end

    def test_nested_modules_and_classes_with_multibyte_characters
      index(<<~RUBY)
        module A動物
          class Bねこ; end
        end
      RUBY

      assert_entry("A動物", Entry::Module, "/fake/path/foo.rb:0-0:2-3")
      assert_entry("A動物::Bねこ", Entry::Class, "/fake/path/foo.rb:1-2:1-16")
    end

    def test_nested_modules_and_classes
      index(<<~RUBY)
        module Foo
          class Bar
          end

          module Baz
            class Qux
              class Something
              end
            end
          end
        end
      RUBY

      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:10-3")
      assert_entry("Foo::Bar", Entry::Class, "/fake/path/foo.rb:1-2:2-5")
      assert_entry("Foo::Baz", Entry::Module, "/fake/path/foo.rb:4-2:9-5")
      assert_entry("Foo::Baz::Qux", Entry::Class, "/fake/path/foo.rb:5-4:8-7")
      assert_entry("Foo::Baz::Qux::Something", Entry::Class, "/fake/path/foo.rb:6-6:7-9")
    end

    def test_deleting_from_index_based_on_file_path
      index(<<~RUBY)
        class Foo
        end
      RUBY

      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:1-3")

      @index.delete(URI::Generic.from_path(path: "/fake/path/foo.rb"))
      refute_entry("Foo")

      assert_no_indexed_entries
    end

    def test_comments_can_be_attached_to_a_class
      index(<<~RUBY)
        # This is method comment
        def foo; end
        # This is a Foo comment
        # This is another Foo comment
        class Foo
          # This should not be attached
        end

        # Ignore me

        # This Bar comment has 1 line padding

        class Bar; end
      RUBY

      foo_entry = @index["Foo"] #: as !nil
        .first #: as !nil
      assert_equal("This is a Foo comment\nThis is another Foo comment", foo_entry.comments)

      bar_entry = @index["Bar"] #: as !nil
        .first #: as !nil
      assert_equal("This Bar comment has 1 line padding", bar_entry.comments)
    end

    def test_skips_comments_containing_invalid_encodings
      index(<<~RUBY)
        # comment \xBA
        class Foo
        end
      RUBY
      assert(@index["Foo"]&.first)
    end

    def test_comments_can_be_attached_to_a_namespaced_class
      index(<<~RUBY)
        # This is a Foo comment
        # This is another Foo comment
        class Foo
          # This is a Bar comment
          class Bar; end
        end
      RUBY

      foo_entry = @index["Foo"] #: as !nil
        .first #: as !nil
      assert_equal("This is a Foo comment\nThis is another Foo comment", foo_entry.comments)

      bar_entry = @index["Foo::Bar"] #: as !nil
        .first #: as !nil
      assert_equal("This is a Bar comment", bar_entry.comments)
    end

    def test_comments_can_be_attached_to_a_reopened_class
      index(<<~RUBY)
        # This is a Foo comment
        class Foo; end

        # This is another Foo comment
        class Foo; end
      RUBY

      first_foo_entry, second_foo_entry = @index["Foo"] #: as !nil
      assert_equal("This is a Foo comment", first_foo_entry&.comments)
      assert_equal("This is another Foo comment", second_foo_entry&.comments)
    end

    def test_comments_removes_the_leading_pound_and_space
      index(<<~RUBY)
        # This is a Foo comment
        class Foo; end

        #This is a Bar comment
        class Bar; end
      RUBY

      first_foo_entry = @index["Foo"] #: as !nil
        .first #: as !nil
      assert_equal("This is a Foo comment", first_foo_entry.comments)

      second_foo_entry = @index["Bar"] #: as !nil
        .first #: as !nil
      assert_equal("This is a Bar comment", second_foo_entry.comments)
    end

    def test_private_class_and_module_indexing
      index(<<~RUBY)
        class A
          class B; end
          private_constant(:B)

          module C; end
          private_constant("C")

          class D; end
        end
      RUBY

      b_const = @index["A::B"] #: as !nil
        .first
      assert_predicate(b_const, :private?)

      c_const = @index["A::C"] #: as !nil
        .first
      assert_predicate(c_const, :private?)

      d_const = @index["A::D"] #: as !nil
        .first
      assert_predicate(d_const, :public?)
    end

    def test_keeping_track_of_super_classes
      index(<<~RUBY)
        class Foo < Bar
        end

        class Baz
        end

        module Something
          class Baz
          end

          class Qux < ::Baz
          end
        end

        class FinalThing < Something::Baz
        end
      RUBY

      foo = @index["Foo"] #: as !nil
        .first #: as Entry::Class
      assert_equal("Bar", foo.parent_class)

      baz = @index["Baz"] #: as !nil
        .first #: as Entry::Class
      assert_equal("::Object", baz.parent_class)

      qux = @index["Something::Qux"] #: as !nil
        .first #: as Entry::Class
      assert_equal("::Baz", qux.parent_class)

      final_thing = @index["FinalThing"] #: as !nil
        .first #: as Entry::Class
      assert_equal("Something::Baz", final_thing.parent_class)
    end

    def test_keeping_track_of_included_modules
      index(<<~RUBY)
        class Foo
          # valid syntaxes that we can index
          include A1
          self.include A2
          include A3, A4
          self.include A5, A6

          # valid syntaxes that we cannot index because of their dynamic nature
          include some_variable_or_method_call
          self.include some_variable_or_method_call

          def something
            include A7 # We should not index this because of this dynamic nature
          end

          # Valid inner class syntax definition with its own modules included
          class Qux
            include Corge
            self.include Corge
            include Baz

            include some_variable_or_method_call
          end
        end

        class ConstantPathReferences
          include Foo::Bar
          self.include Foo::Bar2

          include dynamic::Bar
          include Foo::
        end
      RUBY

      foo = @index["Foo"] #: as !nil
        .first #: as Entry::Class
      assert_equal(["A1", "A2", "A3", "A4", "A5", "A6"], foo.mixin_operation_module_names)

      qux = @index["Foo::Qux"] #: as !nil
        .first #: as Entry::Class
      assert_equal(["Corge", "Corge", "Baz"], qux.mixin_operation_module_names)

      constant_path_references = @index["ConstantPathReferences"] #: as !nil
        .first #: as Entry::Class
      assert_equal(["Foo::Bar", "Foo::Bar2"], constant_path_references.mixin_operation_module_names)
    end

    def test_keeping_track_of_prepended_modules
      index(<<~RUBY)
        class Foo
          # valid syntaxes that we can index
          prepend A1
          self.prepend A2
          prepend A3, A4
          self.prepend A5, A6

          # valid syntaxes that we cannot index because of their dynamic nature
          prepend some_variable_or_method_call
          self.prepend some_variable_or_method_call

          def something
            prepend A7 # We should not index this because of this dynamic nature
          end

          # Valid inner class syntax definition with its own modules prepended
          class Qux
            prepend Corge
            self.prepend Corge
            prepend Baz

            prepend some_variable_or_method_call
          end
        end

        class ConstantPathReferences
          prepend Foo::Bar
          self.prepend Foo::Bar2

          prepend dynamic::Bar
          prepend Foo::
        end
      RUBY

      foo = @index["Foo"] #: as !nil
        .first #: as Entry::Class
      assert_equal(["A1", "A2", "A3", "A4", "A5", "A6"], foo.mixin_operation_module_names)

      qux = @index["Foo::Qux"] #: as !nil
        .first #: as Entry::Class
      assert_equal(["Corge", "Corge", "Baz"], qux.mixin_operation_module_names)

      constant_path_references = @index["ConstantPathReferences"] #: as !nil
        .first #: as Entry::Class
      assert_equal(["Foo::Bar", "Foo::Bar2"], constant_path_references.mixin_operation_module_names)
    end

    def test_keeping_track_of_extended_modules
      index(<<~RUBY)
        class Foo
          # valid syntaxes that we can index
          extend A1
          self.extend A2
          extend A3, A4
          self.extend A5, A6

          # valid syntaxes that we cannot index because of their dynamic nature
          extend some_variable_or_method_call
          self.extend some_variable_or_method_call

          def something
            extend A7 # We should not index this because of this dynamic nature
          end

          # Valid inner class syntax definition with its own modules prepended
          class Qux
            extend Corge
            self.extend Corge
            extend Baz

            extend some_variable_or_method_call
          end
        end

        class ConstantPathReferences
          extend Foo::Bar
          self.extend Foo::Bar2

          extend dynamic::Bar
          extend Foo::
        end
      RUBY

      foo = @index["Foo::<Class:Foo>"] #: as !nil
        .first #: as Entry::Class
      assert_equal(["A1", "A2", "A3", "A4", "A5", "A6"], foo.mixin_operation_module_names)

      qux = @index["Foo::Qux::<Class:Qux>"] #: as !nil
        .first #: as Entry::Class
      assert_equal(["Corge", "Corge", "Baz"], qux.mixin_operation_module_names)

      constant_path_references = @index["ConstantPathReferences::<Class:ConstantPathReferences>"] #: as !nil
        .first #: as Entry::Class
      assert_equal(["Foo::Bar", "Foo::Bar2"], constant_path_references.mixin_operation_module_names)
    end

    def test_tracking_singleton_classes
      index(<<~RUBY)
        class Foo; end
        class Foo
          # Some extra comments
          class << self
          end
        end
      RUBY

      foo = @index["Foo::<Class:Foo>"] #: as !nil
        .first #: as Entry::SingletonClass
      assert_equal(4, foo.location.start_line)
      assert_equal("Some extra comments", foo.comments)
    end

    def test_dynamic_singleton_class_blocks
      index(<<~RUBY)
        class Foo
          # Some extra comments
          class << bar
          end
        end
      RUBY

      singleton = @index["Foo::<Class:bar>"] #: as !nil
        .first #: as Entry::SingletonClass

      # Even though this is not correct, we consider any dynamic singleton class block as a regular singleton class.
      # That pattern cannot be properly analyzed statically and assuming that it's always a regular singleton simplifies
      # the implementation considerably.
      assert_equal(3, singleton.location.start_line)
      assert_equal("Some extra comments", singleton.comments)
    end

    def test_namespaces_inside_singleton_blocks
      index(<<~RUBY)
        class Foo
          class << self
            class Bar
            end
          end
        end
      RUBY

      assert_entry("Foo::<Class:Foo>::Bar", Entry::Class, "/fake/path/foo.rb:2-4:3-7")
    end

    def test_name_location_points_to_constant_path_location
      index(<<~RUBY)
        class Foo
          def foo; end
        end

        module Bar
          def bar; end
        end
      RUBY

      foo = @index["Foo"] #: as !nil
        .first #: as Entry::Class
      refute_equal(foo.location, foo.name_location)

      name_location = foo.name_location
      assert_equal(1, name_location.start_line)
      assert_equal(1, name_location.end_line)
      assert_equal(6, name_location.start_column)
      assert_equal(9, name_location.end_column)

      bar = @index["Bar"] #: as !nil
        .first #: as Entry::Module
      refute_equal(bar.location, bar.name_location)

      name_location = bar.name_location
      assert_equal(5, name_location.start_line)
      assert_equal(5, name_location.end_line)
      assert_equal(7, name_location.start_column)
      assert_equal(10, name_location.end_column)
    end

    def test_indexing_namespaces_inside_top_level_references
      index(<<~RUBY)
        module ::Foo
          class Bar
          end
        end
      RUBY

      # We want to explicitly verify that we didn't introduce the leading `::` by accident, but `Index#[]` deletes the
      # prefix when we use `refute_entry`
      entries = @index.instance_variable_get(:@entries)
      refute(entries.key?("::Foo"))
      refute(entries.key?("::Foo::Bar"))
      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:3-3")
      assert_entry("Foo::Bar", Entry::Class, "/fake/path/foo.rb:1-2:2-5")
    end

    def test_indexing_singletons_inside_top_level_references
      index(<<~RUBY)
        module ::Foo
          class Bar
            class << self
            end
          end
        end
      RUBY

      # We want to explicitly verify that we didn't introduce the leading `::` by accident, but `Index#[]` deletes the
      # prefix when we use `refute_entry`
      entries = @index.instance_variable_get(:@entries)
      refute(entries.key?("::Foo"))
      refute(entries.key?("::Foo::Bar"))
      refute(entries.key?("::Foo::Bar::<Class:Bar>"))
      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:5-3")
      assert_entry("Foo::Bar", Entry::Class, "/fake/path/foo.rb:1-2:4-5")
      assert_entry("Foo::Bar::<Class:Bar>", Entry::SingletonClass, "/fake/path/foo.rb:2-4:3-7")
    end

    def test_indexing_namespaces_inside_nested_top_level_references
      index(<<~RUBY)
        class Baz
          module ::Foo
            class Bar
            end

            class ::Qux
            end
          end
        end
      RUBY

      refute_entry("Baz::Foo")
      refute_entry("Baz::Foo::Bar")
      assert_entry("Baz", Entry::Class, "/fake/path/foo.rb:0-0:8-3")
      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:1-2:7-5")
      assert_entry("Foo::Bar", Entry::Class, "/fake/path/foo.rb:2-4:3-7")
      assert_entry("Qux", Entry::Class, "/fake/path/foo.rb:5-4:6-7")
    end

    def test_lazy_comment_fetching_uses_correct_line_breaks_for_rendering
      uri = URI::Generic.from_path(
        load_path_entry: "#{Dir.pwd}/lib",
        path: "#{Dir.pwd}/lib/ruby_lsp/node_context.rb",
      )

      @index.index_file(uri, collect_comments: false)

      entry = @index["RubyLsp::NodeContext"] #: as !nil
        .first #: as !nil

      assert_equal(<<~COMMENTS.chomp, entry.comments)
        This class allows listeners to access contextual information about a node in the AST, such as its parent,
        its namespace nesting, and the surrounding CallNode (e.g. a method call).
      COMMENTS
    end

    def test_lazy_comment_fetching_does_not_fail_if_file_gets_deleted
      uri = URI::Generic.from_path(
        load_path_entry: "#{Dir.pwd}/lib",
        path: "#{Dir.pwd}/lib/ruby_lsp/does_not_exist.rb",
      )

      @index.index_single(uri, <<~RUBY, collect_comments: false)
        class Foo
        end
      RUBY

      entry = @index["Foo"]&.first #: as !nil
      assert_empty(entry.comments)
    end

    def test_singleton_inside_compact_namespace
      index(<<~RUBY)
        module Foo::Bar
          class << self
            def baz; end
          end
        end
      RUBY

      # Verify we didn't index the incorrect name
      assert_nil(@index["Foo::Bar::<Class:Foo::Bar>"])

      # Verify we indexed the correct name
      assert_entry("Foo::Bar::<Class:Bar>", Entry::SingletonClass, "/fake/path/foo.rb:1-2:3-5")

      method = @index["baz"]&.first #: as Entry::Method
      assert_equal("Foo::Bar::<Class:Bar>", method.owner&.name)
    end

    def test_lazy_comments_with_spaces_are_properly_attributed
      path = File.join(Dir.pwd, "lib", "foo.rb")
      source =  <<~RUBY
        require "whatever"

        # These comments belong to the declaration below
        # They have to be associated with it

        class Foo
        end
      RUBY
      File.write(path, source)
      @index.index_single(URI::Generic.from_path(path: path), source, collect_comments: false)

      entry = @index["Foo"]&.first #: as !nil

      begin
        assert_equal(<<~COMMENTS.chomp, entry.comments)
          These comments belong to the declaration below
          They have to be associated with it
        COMMENTS
      ensure
        FileUtils.rm(path)
      end
    end

    def test_lazy_comments_with_no_spaces_are_properly_attributed
      path = File.join(Dir.pwd, "lib", "foo.rb")
      source = <<~RUBY
        require "whatever"

        # These comments belong to the declaration below
        # They have to be associated with it
        class Foo
        end
      RUBY
      File.write(path, source)
      @index.index_single(URI::Generic.from_path(path: path), source, collect_comments: false)

      entry = @index["Foo"]&.first #: as !nil

      begin
        assert_equal(<<~COMMENTS.chomp, entry.comments)
          These comments belong to the declaration below
          They have to be associated with it
        COMMENTS
      ensure
        FileUtils.rm(path)
      end
    end

    def test_lazy_comments_with_two_extra_spaces_are_properly_ignored
      path = File.join(Dir.pwd, "lib", "foo.rb")
      source = <<~RUBY
        require "whatever"

        # These comments don't belong to the declaration below
        # They will not be associated with it


        class Foo
        end
      RUBY
      File.write(path, source)
      @index.index_single(URI::Generic.from_path(path: path), source, collect_comments: false)

      entry = @index["Foo"]&.first #: as !nil

      begin
        assert_empty(entry.comments)
      ensure
        FileUtils.rm(path)
      end
    end
  end
end
