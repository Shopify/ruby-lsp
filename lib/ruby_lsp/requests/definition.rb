# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Definition demo](../../definition.gif)
    #
    # The [definition
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_definition) jumps to the
    # definition of the symbol under the cursor.
    #
    # Currently, only jumping to classes, modules and required files is supported.
    #
    # # Example
    #
    # ```ruby
    # require "some_gem/file" # <- Request go to definition on this string will take you to the file
    # Product.new # <- Request go to definition on this class name will take you to its declaration.
    # ```
    class Definition < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(T.any(T::Array[Interface::Location], Interface::Location)) } }

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig do
        params(
          uri: URI::Generic,
          nesting: T::Array[String],
          index: RubyIndexer::Index,
          emitter: EventEmitter,
          message_queue: Thread::Queue,
        ).void
      end
      def initialize(uri, nesting, index, emitter, message_queue)
        super(emitter, message_queue)

        @uri = uri
        @nesting = nesting
        @index = index
        @response = T.let(nil, ResponseType)
        emitter.register(self, :on_command, :on_const, :on_const_path_ref)
      end

      sig { params(node: SyntaxTree::ConstPathRef).void }
      def on_const_path_ref(node)
        name = full_constant_name(node)
        find_in_index(name)
      end

      sig { params(node: SyntaxTree::Const).void }
      def on_const(node)
        find_in_index(node.value)
      end

      sig { params(node: SyntaxTree::Command).void }
      def on_command(node)
        message = node.message.value
        return unless message == "require" || message == "require_relative"

        argument = node.arguments.parts.first
        return unless argument.is_a?(SyntaxTree::StringLiteral)

        string = argument.parts.first
        return unless string.is_a?(SyntaxTree::TStringContent)

        required_file = "#{string.value}.rb"

        case message
        when "require"
          candidate = find_file_in_load_path(required_file)

          if candidate
            @response = Interface::Location.new(
              uri: URI::Generic.from_path(path: candidate).to_s,
              range: Interface::Range.new(
                start: Interface::Position.new(line: 0, character: 0),
                end: Interface::Position.new(line: 0, character: 0),
              ),
            )
          end
        when "require_relative"
          path = @uri.to_standardized_path
          current_folder = path ? Pathname.new(CGI.unescape(path)).dirname : Dir.pwd
          candidate = File.expand_path(File.join(current_folder, required_file))

          if candidate
            @response = Interface::Location.new(
              uri: URI::Generic.from_path(path: candidate).to_s,
              range: Interface::Range.new(
                start: Interface::Position.new(line: 0, character: 0),
                end: Interface::Position.new(line: 0, character: 0),
              ),
            )
          end
        end
      end

      private

      sig { params(value: String).void }
      def find_in_index(value)
        entries = @index.resolve(value, @nesting)
        return unless entries

        bundle_path = begin
          Bundler.bundle_path.to_s
        rescue Bundler::GemfileNotFound
          nil
        end

        @response = entries.filter_map do |entry|
          location = entry.location
          # If the project has Sorbet, then we only want to handle go to definition for constants defined in gems, as an
          # additional behavior on top of jumping to RBIs. Sorbet can already handle go to definition for all constants
          # in the project, even if the files are typed false
          next if DependencyDetector::HAS_TYPECHECKER && bundle_path && !entry.file_path.start_with?(bundle_path)

          Interface::Location.new(
            uri: URI::Generic.from_path(path: entry.file_path).to_s,
            range: Interface::Range.new(
              start: Interface::Position.new(line: location.start_line - 1, character: location.start_column),
              end: Interface::Position.new(line: location.end_line - 1, character: location.end_column),
            ),
          )
        end
      end

      sig { params(file: String).returns(T.nilable(String)) }
      def find_file_in_load_path(file)
        return unless file.include?("/")

        $LOAD_PATH.each do |p|
          found = Dir.glob("**/#{file}", base: p).first
          return "#{p}/#{found}" if found
        end

        nil
      end
    end
  end
end
