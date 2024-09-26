# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class EnhancementTest < TestCase
    def test_enhancing_indexing_included_hook
      enhancement_class = Class.new do
        include Enhancement

        def on_call_node(index, owner, node, file_path)
          return unless owner
          return unless node.name == :extend

          arguments = node.arguments&.arguments
          return unless arguments

          location = node.location

          arguments.each do |node|
            next unless node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)

            module_name = node.full_name
            next unless module_name == "ActiveSupport::Concern"

            index.register_included_hook(owner.name) do |index, base|
              class_methods_name = "#{owner.name}::ClassMethods"

              if index.indexed?(class_methods_name)
                singleton = index.existing_or_new_singleton_class(base.name)
                singleton.mixin_operations << Entry::Include.new(class_methods_name)
              end
            end

            index.add(Entry::Method.new(
              "new_method",
              file_path,
              location,
              location,
              nil,
              index.configuration.encoding,
              [Entry::Signature.new([Entry::RequiredParameter.new(name: :a)])],
              Entry::Visibility::PUBLIC,
              owner,
            ))
          rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
                 Prism::ConstantPathNode::MissingNodesInConstantPathError
            # Do nothing
          end
        end
      end

      @index.register_enhancement(enhancement_class.new)
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
      enhancement_class = Class.new do
        include Enhancement

        def on_call_node(index, owner, node, file_path)
          return unless owner

          name = node.name
          return unless name == :has_many

          arguments = node.arguments&.arguments
          return unless arguments

          association_name = arguments.first
          return unless association_name.is_a?(Prism::SymbolNode)

          location = association_name.location

          index.add(Entry::Method.new(
            T.must(association_name.value),
            file_path,
            location,
            location,
            nil,
            index.configuration.encoding,
            [],
            Entry::Visibility::PUBLIC,
            owner,
          ))
        end
      end

      @index.register_enhancement(enhancement_class.new)
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

    def test_error_handling_in_enhancement
      enhancement_class = Class.new do
        include Enhancement

        def on_call_node(index, owner, node, file_path)
          raise "Error"
        end

        class << self
          def name
            "TestEnhancement"
          end
        end
      end

      @index.register_enhancement(enhancement_class.new)

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

      assert_match(%r{Indexing error in /fake/path/foo\.rb with 'TestEnhancement' enhancement}, stderr)
      # The module should still be indexed
      assert_entry("ActiveSupport::Concern", Entry::Module, "/fake/path/foo.rb:1-2:5-5")
    end
  end
end
