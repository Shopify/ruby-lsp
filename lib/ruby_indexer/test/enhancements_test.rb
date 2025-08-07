# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class EnhancementTest < TestCase
    def teardown
      super
      Enhancement.clear
    end

    def test_enhancing_indexing_included_hook
      Class.new(Enhancement) do
        def on_call_node_enter(call_node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
          owner = @listener.current_owner
          return unless owner
          return unless call_node.name == :extend

          arguments = call_node.arguments&.arguments
          return unless arguments

          arguments.each do |node|
            next unless node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)

            module_name = node.full_name
            next unless module_name == "ActiveSupport::Concern"

            @listener.register_included_hook do |index, base|
              class_methods_name = "#{owner.name}::ClassMethods"

              if index.indexed?(class_methods_name)
                singleton = index.existing_or_new_singleton_class(base.name)
                singleton.mixin_operations << Entry::Include.new(class_methods_name)
              end
            end

            @listener.add_method(
              "new_method",
              call_node.location,
              [Entry::Signature.new([Entry::RequiredParameter.new(name: :a)])],
            )
          rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
                 Prism::ConstantPathNode::MissingNodesInConstantPathError
            # Do nothing
          end
        end
      end

      index(<<~RUBY)
        module ActiveSupport
          module Concern
            def self.extended(base)
              base.class_eval("def new_method(a); end")
            end
          end
        end

        module ActiveRecord
          module Associations
            extend ActiveSupport::Concern

            module ClassMethods
              def belongs_to(something); end
            end
          end

          class Base
            include Associations
          end
        end

        class User < ActiveRecord::Base
        end
      RUBY

      assert_equal(
        [
          "User::<Class:User>",
          "ActiveRecord::Base::<Class:Base>",
          "ActiveRecord::Associations::ClassMethods",
          "Object::<Class:Object>",
          "BasicObject::<Class:BasicObject>",
          "Class",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("User::<Class:User>"),
      )

      assert_entry("new_method", Entry::Method, "/fake/path/foo.rb:10-4:10-33")
    end

    def test_enhancing_indexing_configuration_dsl
      Class.new(Enhancement) do
        def on_call_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
          return unless @listener.current_owner

          name = node.name
          return unless name == :has_many

          arguments = node.arguments&.arguments
          return unless arguments

          association_name = arguments.first
          return unless association_name.is_a?(Prism::SymbolNode)

          @listener.add_method(
            association_name.value, #: as !nil
            association_name.location,
            [],
          )
        end
      end

      index(<<~RUBY)
        module ActiveSupport
          module Concern
            def self.extended(base)
              base.class_eval("def new_method(a); end")
            end
          end
        end

        module ActiveRecord
          module Associations
            extend ActiveSupport::Concern

            module ClassMethods
              def belongs_to(something); end
            end
          end

          class Base
            include Associations
          end
        end

        class User < ActiveRecord::Base
          has_many :posts
        end
      RUBY

      assert_entry("posts", Entry::Method, "/fake/path/foo.rb:23-11:23-17")
    end

    def test_error_handling_in_on_call_node_enter_enhancement
      Class.new(Enhancement) do
        def on_call_node_enter(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
          raise "Error"
        end

        class << self
          def name
            "TestEnhancement"
          end
        end
      end

      _stdout, stderr = capture_io do
        index(<<~RUBY)
          module ActiveSupport
            module Concern
              def self.extended(base)
                base.class_eval("def new_method(a); end")
              end
            end
          end
        RUBY
      end

      assert_match(
        %r{Indexing error in file:///fake/path/foo\.rb with 'TestEnhancement' on call node enter enhancement},
        stderr,
      )
      # The module should still be indexed
      assert_entry("ActiveSupport::Concern", Entry::Module, "/fake/path/foo.rb:1-2:5-5")
    end

    def test_error_handling_in_on_call_node_leave_enhancement
      Class.new(Enhancement) do
        def on_call_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
          raise "Error"
        end

        class << self
          def name
            "TestEnhancement"
          end
        end
      end

      _stdout, stderr = capture_io do
        index(<<~RUBY)
          module ActiveSupport
            module Concern
              def self.extended(base)
                base.class_eval("def new_method(a); end")
              end
            end
          end
        RUBY
      end

      assert_match(
        %r{Indexing error in file:///fake/path/foo\.rb with 'TestEnhancement' on call node leave enhancement},
        stderr,
      )
      # The module should still be indexed
      assert_entry("ActiveSupport::Concern", Entry::Module, "/fake/path/foo.rb:1-2:5-5")
    end

    def test_advancing_namespace_stack_from_enhancement
      Class.new(Enhancement) do
        def on_call_node_enter(call_node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
          owner = @listener.current_owner
          return unless owner

          case call_node.name
          when :class_methods
            @listener.add_module("ClassMethods", call_node.location, call_node.location)
          when :extend
            arguments = call_node.arguments&.arguments
            return unless arguments

            arguments.each do |node|
              next unless node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)

              module_name = node.full_name
              next unless module_name == "ActiveSupport::Concern"

              @listener.register_included_hook do |index, base|
                class_methods_name = "#{owner.name}::ClassMethods"

                if index.indexed?(class_methods_name)
                  singleton = index.existing_or_new_singleton_class(base.name)
                  singleton.mixin_operations << Entry::Include.new(class_methods_name)
                end
              end
            end
          end
        end

        def on_call_node_leave(call_node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
          return unless call_node.name == :class_methods

          @listener.pop_namespace_stack
        end
      end

      index(<<~RUBY)
        module ActiveSupport
          module Concern
          end
        end

        module MyConcern
          extend ActiveSupport::Concern

          class_methods do
            def foo; end
          end
        end

        class User
          include MyConcern
        end
      RUBY

      assert_equal(
        [
          "User::<Class:User>",
          "MyConcern::ClassMethods",
          "Object::<Class:Object>",
          "BasicObject::<Class:BasicObject>",
          "Class",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("User::<Class:User>"),
      )

      refute_nil(@index.resolve_method("foo", "User::<Class:User>"))
    end

    def test_creating_anonymous_classes_from_enhancement
      Class.new(Enhancement) do
        def on_call_node_enter(call_node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
          case call_node.name
          when :context
            arguments = call_node.arguments&.arguments
            first_argument = arguments&.first
            return unless first_argument.is_a?(Prism::StringNode)

            @listener.add_class(
              "<RSpec:#{first_argument.content}>",
              call_node.location,
              first_argument.location,
            )
          when :subject
            @listener.add_method("subject", call_node.location, [])
          end
        end

        def on_call_node_leave(call_node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
          return unless call_node.name == :context

          @listener.pop_namespace_stack
        end
      end

      index(<<~RUBY)
        context "does something" do
          subject { call_whatever }
        end
      RUBY

      refute_nil(@index.resolve_method("subject", "<RSpec:does something>"))
    end
  end
end
