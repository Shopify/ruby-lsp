# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Code lens demo](../../misc/code_lens.gif)
    #
    # This feature is currently experimental. Clients will need to pass `experimentalFeaturesEnabled`
    # in the initialization options to enable it.
    #
    # The
    # [code lens](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeLens)
    # request informs the editor of runnable commands such as tests
    #
    # # Example
    #
    # ```ruby
    # # Run
    # class Test < Minitest::Test
    # end
    # ```

    class CodeLens < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::CodeLens] } }

      BASE_COMMAND = T.let((File.exist?("Gemfile.lock") ? "bundle exec ruby" : "ruby") + " -Itest ", String)
      ACCESS_MODIFIERS = T.let(["public", "private", "protected"], T::Array[String])

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { params(uri: String, message_queue: Thread::Queue).void }
      def initialize(uri, message_queue)
        super

        @response = T.let([], ResponseType)
        @path = T.let(uri.delete_prefix("file://"), String)
        @visibility = T.let("public", String)
        @prev_visibility = T.let("public", String)
      end

      listener_events do
        sig { params(node: SyntaxTree::ClassDeclaration).void }
        def on_class(node)
          class_name = node.constant.constant.value
          if class_name.end_with?("Test")
            add_code_lens(node, name: class_name, command: BASE_COMMAND + @path)
          end
        end

        sig { params(node: SyntaxTree::DefNode).void }
        def on_def(node)
          if @visibility == "public"
            method_name = node.name.value
            if method_name.start_with?("test_")
              add_code_lens(
                node,
                name: method_name,
                command: BASE_COMMAND + @path + " --name " + method_name,
              )
            end
          end
        end

        sig { params(node: SyntaxTree::Command).void }
        def on_command(node)
          if ACCESS_MODIFIERS.include?(node.message.value) && node.arguments.parts.any?
            @prev_visibility = @visibility
            @visibility = node.message.value
          end
        end

        sig { params(node: SyntaxTree::Command).void }
        def after_command(node)
          @visibility = @prev_visibility
        end

        sig { params(node: SyntaxTree::CallNode).void }
        def on_call(node)
          ident = node.message if node.message.is_a?(SyntaxTree::Ident)

          if ident
            ident_value = T.cast(ident, SyntaxTree::Ident).value
            if ACCESS_MODIFIERS.include?(ident_value)
              @prev_visibility = @visibility
              @visibility = ident_value
            end
          end
        end

        sig { params(node: SyntaxTree::CallNode).void }
        def after_call(node)
          @visibility = @prev_visibility
        end

        sig { params(node: SyntaxTree::VCall).void }
        def on_vcall(node)
          vcall_value = node.value.value

          if ACCESS_MODIFIERS.include?(vcall_value)
            @prev_visibility = vcall_value
            @visibility = vcall_value
          end
        end
      end

      sig { params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        @response.concat(other.response)
        self
      end

      private

      sig { params(node: SyntaxTree::Node, name: String, command: String).void }
      def add_code_lens(node, name:, command:)
        @response << create_code_lens(
          node,
          path: @path,
          name: name,
          test_command: command,
          type: "test",
        )

        @response << create_code_lens(
          node,
          path: @path,
          name: name,
          test_command: command,
          type: "debug",
        )
      end
    end
  end
end
